package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/hibiken/asynq"

	"folio-server/internal/api"
	"folio-server/internal/api/handler"
	"folio-server/internal/client"
	"folio-server/internal/config"
	"folio-server/internal/repository"
	"folio-server/internal/service"
	"folio-server/internal/worker"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("failed to load config: %v", err)
	}

	// Database
	ctx := context.Background()
	pool, err := repository.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}
	defer pool.Close()

	// Repositories
	userRepo := repository.NewUserRepo(pool)
	articleRepo := repository.NewArticleRepo(pool)
	tagRepo := repository.NewTagRepo(pool)
	categoryRepo := repository.NewCategoryRepo(pool)
	taskRepo := repository.NewTaskRepo(pool)

	// External clients
	readerClient := client.NewReaderClient(cfg.ReaderURL)
	aiClient := client.NewAIClient(cfg.AIServiceURL)

	// R2 client (optional — nil if not configured)
	var r2Client *client.R2Client
	if cfg.R2Endpoint != "" && cfg.R2AccessKey != "" && cfg.R2SecretKey != "" {
		r2Client, err = client.NewR2Client(
			cfg.R2Endpoint, cfg.R2AccessKey, cfg.R2SecretKey,
			cfg.R2BucketName, cfg.R2PublicURL,
		)
		if err != nil {
			log.Fatalf("failed to create R2 client: %v", err)
		}
	}

	// Asynq client
	asynqClient := asynq.NewClient(asynq.RedisClientOpt{Addr: cfg.RedisAddr})
	defer asynqClient.Close()

	// Services
	quotaService := service.NewQuotaService(userRepo)
	authService := service.NewAuthService(userRepo, cfg.JWTSecret)
	tagService := service.NewTagService(tagRepo)
	articleService := service.NewArticleService(
		articleRepo, taskRepo, tagRepo, categoryRepo,
		quotaService, asynqClient,
	)

	// Handlers
	authHandler := handler.NewAuthHandler(authService)
	articleHandler := handler.NewArticleHandler(articleService)
	searchHandler := handler.NewSearchHandler(articleService)
	tagHandler := handler.NewTagHandler(tagService)
	categoryHandler := handler.NewCategoryHandler(categoryRepo)
	taskHandler := handler.NewTaskHandler(taskRepo)
	subscriptionHandler := handler.NewSubscriptionHandler()

	// Router
	router := api.NewRouter(api.RouterDeps{
		AuthService:         authService,
		DevMode:             cfg.DevMode,
		AuthHandler:         authHandler,
		ArticleHandler:      articleHandler,
		SearchHandler:       searchHandler,
		TagHandler:          tagHandler,
		CategoryHandler:     categoryHandler,
		TaskHandler:         taskHandler,
		SubscriptionHandler: subscriptionHandler,
	})

	// Worker server
	crawlHandler := worker.NewCrawlHandler(readerClient, articleRepo, taskRepo, asynqClient, r2Client != nil)
	aiHandler := worker.NewAIHandler(aiClient, articleRepo, taskRepo, categoryRepo, tagRepo)

	var workerServer *worker.WorkerServer
	if r2Client != nil {
		imageHandler := worker.NewImageHandler(r2Client, articleRepo)
		workerServer = worker.NewWorkerServer(cfg.RedisAddr, crawlHandler, aiHandler, imageHandler)
	} else {
		workerServer = worker.NewWorkerServer(cfg.RedisAddr, crawlHandler, aiHandler, nil)
	}

	// HTTP server
	httpServer := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	switch cfg.AppMode {
	case "worker":
		log.Println("Starting in WORKER mode...")
		if err := workerServer.Run(); err != nil {
			log.Printf("worker server error: %v", err)
			return
		}
	case "api":
		log.Println("Starting in API mode (no worker)...")
		runHTTPServer(httpServer, cfg.Port, nil)
	default: // "all"
		log.Println("Starting in ALL mode (API + Worker)...")
		go func() {
			if err := workerServer.Run(); err != nil {
				log.Fatalf("worker server error: %v", err)
			}
		}()
		runHTTPServer(httpServer, cfg.Port, workerServer)
	}

	log.Println("Server stopped")
}

func runHTTPServer(server *http.Server, port string, workerServer *worker.WorkerServer) {
	done := make(chan os.Signal, 1)
	signal.Notify(done, os.Interrupt, syscall.SIGTERM)

	go func() {
		fmt.Printf("Folio API server listening on :%s\n", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server failed: %v", err)
		}
	}()

	<-done
	log.Println("Shutting down...")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Printf("HTTP server shutdown error: %v", err)
	}
	if workerServer != nil {
		workerServer.Shutdown()
	}
}
