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
	DevMode     bool

	AuthHandler         *handler.AuthHandler
	ArticleHandler      *handler.ArticleHandler
	SearchHandler       *handler.SearchHandler
	TagHandler          *handler.TagHandler
	CategoryHandler     *handler.CategoryHandler
	TaskHandler         *handler.TaskHandler
	SubscriptionHandler *handler.SubscriptionHandler
}

func NewRouter(deps RouterDeps) http.Handler {
	r := chi.NewRouter()

	r.Use(chimw.Logger)
	r.Use(chimw.Recoverer)
	r.Use(chimw.RequestID)

	// Health check
	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
	})

	r.Route("/api/v1", func(r chi.Router) {
		// Public routes
		r.Post("/auth/apple", deps.AuthHandler.HandleAppleLogin)
		r.Post("/auth/refresh", deps.AuthHandler.HandleRefreshToken)
		if deps.DevMode {
			r.Post("/auth/dev", deps.AuthHandler.HandleDevLogin)
		}

		// Protected routes
		r.Group(func(r chi.Router) {
			r.Use(middleware.JWTAuth(deps.AuthService))

			// Articles — search BEFORE {id} for chi route priority
			r.Get("/articles/search", deps.SearchHandler.HandleSearch)
			r.Post("/articles", deps.ArticleHandler.HandleSubmitURL)
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
		})
	})

	return r
}
