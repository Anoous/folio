package main

import (
	"context"
	"log/slog"
	"net"
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
	"folio-server/internal/logger"
	"folio-server/internal/repository"
	"folio-server/internal/service"
	"folio-server/internal/worker"
)

func main() {
	logger.Init()

	cfg, err := config.Load()
	if err != nil {
		slog.Error("failed to load config", "error", err)
		os.Exit(1)
	}

	// Database
	ctx := context.Background()
	pool, err := repository.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		slog.Error("failed to connect to database", "error", err)
		os.Exit(1)
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
	// AI analyzer — real DeepSeek API if key is set, mock for development
	var aiAnalyzer client.Analyzer
	if cfg.DeepSeekAPIKey != "" {
		aiAnalyzer = client.NewDeepSeekAnalyzer(cfg.DeepSeekAPIKey, cfg.DeepSeekBaseURL)
		slog.Info("using DeepSeek AI analyzer")
	} else {
		aiAnalyzer = &client.MockAnalyzer{}
		slog.Warn("DEEPSEEK_API_KEY not set, using mock AI analyzer")
	}

	// Apple Store client — real if key path is set, mock for development
	appleClient, err := client.NewAppleClient(
		cfg.AppleAPIKeyID, cfg.AppleAPIIssuerID, cfg.AppleAPIKeyPath,
		cfg.AppleBundleID, cfg.APNSSandbox,
	)
	if err != nil {
		slog.Error("failed to create Apple client", "error", err)
		os.Exit(1)
	}

	// R2 client (optional — nil if not configured)
	var r2Client *client.R2Client
	if cfg.R2Endpoint != "" && cfg.R2AccessKey != "" && cfg.R2SecretKey != "" {
		r2Client, err = client.NewR2Client(
			cfg.R2Endpoint, cfg.R2AccessKey, cfg.R2SecretKey,
			cfg.R2BucketName, cfg.R2PublicURL,
		)
		if err != nil {
			slog.Error("failed to create R2 client", "error", err)
			os.Exit(1)
		}
	}

	// Asynq client
	asynqClient := asynq.NewClient(asynq.RedisClientOpt{Addr: cfg.RedisAddr})
	defer asynqClient.Close()

	// Services
	quotaService := service.NewQuotaService(userRepo)
	resendClient := client.NewResendClient(cfg.ResendAPIKey, "EchoLore <noreply@echolore.ai>")
	authService := service.NewAuthService(userRepo, cfg.JWTSecret, cfg.AppleBundleID, resendClient)
	tagService := service.NewTagService(tagRepo)
	articleService := service.NewArticleService(
		articleRepo, taskRepo, tagRepo, categoryRepo,
		quotaService, asynqClient, aiAnalyzer,
	)
	subscriptionService := service.NewSubscriptionService(appleClient, userRepo, cfg.AppleBundleID)

	// Handlers
	authHandler := handler.NewAuthHandler(authService)
	articleHandler := handler.NewArticleHandler(articleService, userRepo)
	searchHandler := handler.NewSearchHandler(articleService)
	tagHandler := handler.NewTagHandler(tagService)
	categoryHandler := handler.NewCategoryHandler(categoryRepo)
	taskHandler := handler.NewTaskHandler(taskRepo)
	subscriptionHandler := handler.NewSubscriptionHandler(subscriptionService)

	// Device repository
	deviceRepo := repository.NewDeviceRepo(pool)

	// APNs client
	apnsClient, err := client.NewAPNSClient(cfg.APNSKeyID, cfg.APNSTeamID, cfg.APNSKeyPath, cfg.APNSSandbox)
	if err != nil {
		slog.Error("failed to create APNs client", "error", err)
		os.Exit(1)
	}

	// Device handler (API)
	deviceHandler := handler.NewDeviceHandler(deviceRepo)

	// Content cache repository
	contentCacheRepo := repository.NewContentCacheRepo(pool)

	// Highlight
	highlightRepo := repository.NewHighlightRepo(pool)
	highlightService := service.NewHighlightService(highlightRepo, articleRepo, asynqClient)
	highlightHandler := handler.NewHighlightHandler(highlightService)

	// Echo repository
	echoRepo := repository.NewEchoRepo(pool)

	echoService := service.NewEchoService(echoRepo, userRepo)
	echoAPIHandler := handler.NewEchoHandler(echoService)

	// RAG
	ragRepo := repository.NewRAGRepo(pool)
	ragService := service.NewRAGService(ragRepo, userRepo, aiAnalyzer)
	ragAPIHandler := handler.NewRAGHandler(ragService)

	// Relations
	relationRepo := repository.NewRelationRepo(pool)
	relationHandler := handler.NewRelationHandler(relationRepo)

	// Stats
	statsService := service.NewStatsService(pool, aiAnalyzer, userRepo)
	statsHandler := handler.NewStatsHandler(statsService, userRepo)

	// Router
	router := api.NewRouter(api.RouterDeps{
		AuthService:         authService,
		AuthHandler:         authHandler,
		ArticleHandler:      articleHandler,
		SearchHandler:       searchHandler,
		TagHandler:          tagHandler,
		CategoryHandler:     categoryHandler,
		TaskHandler:         taskHandler,
		SubscriptionHandler: subscriptionHandler,
		EchoHandler:         echoAPIHandler,
		HighlightHandler:    highlightHandler,
		RAGHandler:          ragAPIHandler,
		StatsHandler:        statsHandler,
		DeviceHandler:       deviceHandler,
		RelationHandler:     relationHandler,
	})

	// Worker server
	jinaClient := client.NewJinaClient(cfg.JinaAPIKey)
	crawlHandler := worker.NewCrawlHandler(readerClient, jinaClient, articleRepo, taskRepo, asynqClient, r2Client != nil, contentCacheRepo, tagRepo, categoryRepo)
	aiHandler := worker.NewAIHandler(aiAnalyzer, articleRepo, taskRepo, categoryRepo, tagRepo, contentCacheRepo, asynqClient)
	echoHandler := worker.NewEchoHandler(aiAnalyzer, articleRepo, echoRepo, highlightRepo)
	pushHandler := worker.NewPushHandler(deviceRepo, apnsClient, cfg.AppleBundleID)
	relateHandler := worker.NewRelateHandler(articleRepo, ragRepo, aiAnalyzer, relationRepo)

	var workerServer *worker.WorkerServer
	if r2Client != nil {
		imageHandler := worker.NewImageHandler(r2Client, articleRepo)
		workerServer = worker.NewWorkerServer(cfg.RedisAddr, crawlHandler, aiHandler, imageHandler, echoHandler, pushHandler, relateHandler)
	} else {
		workerServer = worker.NewWorkerServer(cfg.RedisAddr, crawlHandler, aiHandler, nil, echoHandler, pushHandler, relateHandler)
	}

	// HTTP server
	httpServer := &http.Server{
		Addr:         "0.0.0.0:" + cfg.Port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// startPushScheduler enqueues push:echo tasks hourly via a ticker goroutine.
	startPushScheduler := func() {
		go func() {
			// Enqueue immediately on startup, then hourly.
			if _, err := asynqClient.Enqueue(
				asynq.NewTask(worker.TypePushEcho, nil),
				asynq.Queue(worker.QueueLow),
				asynq.MaxRetry(1),
				asynq.Timeout(2*time.Minute),
			); err != nil {
				slog.Error("push scheduler: initial enqueue failed", "error", err)
			}

			ticker := time.NewTicker(1 * time.Hour)
			defer ticker.Stop()
			for range ticker.C {
				if _, err := asynqClient.Enqueue(
					asynq.NewTask(worker.TypePushEcho, nil),
					asynq.Queue(worker.QueueLow),
					asynq.MaxRetry(1),
					asynq.Timeout(2*time.Minute),
				); err != nil {
					slog.Error("push scheduler: enqueue failed", "error", err)
				}
			}
		}()
	}

	switch cfg.AppMode {
	case "worker":
		slog.Info("starting in worker mode")
		startPushScheduler()
		if err := workerServer.Run(); err != nil {
			slog.Error("worker server error", "error", err)
			return
		}
	case "api":
		slog.Info("starting in api mode")
		runHTTPServer(httpServer, cfg.Port, nil)
	default: // "all"
		slog.Info("starting in all mode")
		startPushScheduler()
		go func() {
			if err := workerServer.Run(); err != nil {
				slog.Error("worker server error", "error", err)
				os.Exit(1)
			}
		}()
		runHTTPServer(httpServer, cfg.Port, workerServer)
	}

	slog.Info("server stopped")
}

func runHTTPServer(server *http.Server, port string, workerServer *worker.WorkerServer) {
	done := make(chan os.Signal, 1)
	signal.Notify(done, os.Interrupt, syscall.SIGTERM)

	go func() {
		ln, err := net.Listen("tcp4", server.Addr)
		if err != nil {
			slog.Error("listen failed", "error", err)
			os.Exit(1)
		}
		slog.Info("folio api server listening", "addr", server.Addr)
		if err := server.Serve(ln); err != nil && err != http.ErrServerClosed {
			slog.Error("server failed", "error", err)
			os.Exit(1)
		}
	}()

	<-done
	slog.Info("shutting down")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := server.Shutdown(shutdownCtx); err != nil {
		slog.Error("http server shutdown error", "error", err)
	}
	if workerServer != nil {
		workerServer.Shutdown()
	}
}
