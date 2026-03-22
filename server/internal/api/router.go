package api

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"

	"folio-server/internal/api/handler"
	"folio-server/internal/api/middleware"
	"folio-server/internal/service"
)

type RouterDeps struct {
	AuthService *service.AuthService

	AuthHandler         *handler.AuthHandler
	ArticleHandler      *handler.ArticleHandler
	SearchHandler       *handler.SearchHandler
	TagHandler          *handler.TagHandler
	CategoryHandler     *handler.CategoryHandler
	TaskHandler         *handler.TaskHandler
	SubscriptionHandler *handler.SubscriptionHandler
	EchoHandler         *handler.EchoHandler
	HighlightHandler    *handler.HighlightHandler
	RAGHandler          *handler.RAGHandler
	StatsHandler        *handler.StatsHandler
	DeviceHandler       *handler.DeviceHandler
}

func NewRouter(deps RouterDeps) http.Handler {
	r := chi.NewRouter()

	r.Use(chimw.Logger)
	r.Use(chimw.Recoverer)
	r.Use(chimw.RequestID)

	// Limit request body to 1 MB to prevent memory exhaustion (DoS)
	const maxBodyBytes int64 = 1 << 20 // 1 MB
	r.Use(func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
			next.ServeHTTP(w, r)
		})
	})

	// Health check
	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
	})

	r.Route("/api/v1", func(r chi.Router) {
		// Public routes
		r.Post("/auth/apple", deps.AuthHandler.HandleAppleLogin)
		r.Post("/auth/refresh", deps.AuthHandler.HandleRefreshToken)
		r.Post("/auth/email/code", deps.AuthHandler.HandleSendCode)
		r.Post("/auth/email/verify", deps.AuthHandler.HandleVerifyCode)

		// Apple webhook — public endpoint (Apple calls without JWT)
		r.Post("/webhook/apple", deps.SubscriptionHandler.HandleWebhook)

		// Protected routes
		r.Group(func(r chi.Router) {
			r.Use(middleware.JWTAuth(deps.AuthService))

			// Articles — search BEFORE {id} for chi route priority
			r.Get("/articles/search", deps.SearchHandler.HandleSearch)
			r.Post("/articles", deps.ArticleHandler.HandleSubmitURL)
			r.Post("/articles/manual", deps.ArticleHandler.HandleSubmitManual)
			r.Get("/articles", deps.ArticleHandler.HandleListArticles)
			r.Get("/articles/{id}", deps.ArticleHandler.HandleGetArticle)
			r.Put("/articles/{id}", deps.ArticleHandler.HandleUpdateArticle)
			r.Delete("/articles/{id}", deps.ArticleHandler.HandleDeleteArticle)

			// Tags
			r.Get("/tags", deps.TagHandler.HandleListTags)
			r.Post("/tags", deps.TagHandler.HandleCreateTag)
			r.Delete("/tags/{id}", deps.TagHandler.HandleDeleteTag)

			// Categories
			r.Get("/categories", deps.CategoryHandler.HandleListCategories)

			// Tasks
			r.Get("/tasks/{id}", deps.TaskHandler.HandleGetTask)

			// Subscription
			r.Post("/subscription/verify", deps.SubscriptionHandler.HandleVerify)

			// Highlights
			r.Post("/articles/{id}/highlights", deps.HighlightHandler.HandleCreateHighlight)
			r.Get("/articles/{id}/highlights", deps.HighlightHandler.HandleGetHighlights)
			r.Delete("/highlights/{id}", deps.HighlightHandler.HandleDeleteHighlight)

			// Echo (spaced repetition)
			r.Get("/echo/today", deps.EchoHandler.HandleGetToday)
			r.Post("/echo/{id}/review", deps.EchoHandler.HandleSubmitReview)

			// RAG (question answering over saved articles)
			r.Post("/rag/query", deps.RAGHandler.HandleQuery)

			// Devices (push notification registration)
			r.Post("/devices", deps.DeviceHandler.HandleRegister)

			// Stats (knowledge map)
			r.Get("/stats/monthly", deps.StatsHandler.HandleMonthlyStats)
			r.Get("/stats/echo", deps.StatsHandler.HandleEchoStats)
		})
	})

	return r
}
