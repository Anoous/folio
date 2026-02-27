package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"

	"folio-server/internal/api/middleware"
	"folio-server/internal/domain"
	"folio-server/internal/repository"
	"folio-server/internal/service"
)

// articleServicer defines the methods that ArticleHandler needs from the article service.
type articleServicer interface {
	SubmitURL(ctx context.Context, userID string, req service.SubmitURLRequest) (*service.SubmitURLResponse, error)
	ListByUser(ctx context.Context, params repository.ListArticlesParams) (*repository.ListArticlesResult, error)
	GetByID(ctx context.Context, userID, articleID string) (*domain.Article, error)
	Update(ctx context.Context, userID, articleID string, params repository.UpdateArticleParams) error
	Delete(ctx context.Context, userID, articleID string) error
	Search(ctx context.Context, userID, query string, page, perPage int) (*repository.ListArticlesResult, error)
}

type ArticleHandler struct {
	articleService articleServicer
}

func NewArticleHandler(articleService *service.ArticleService) *ArticleHandler {
	return &ArticleHandler{articleService: articleService}
}

// maxMarkdownContentBytes is the maximum allowed size for client-provided markdown content (500 KB).
const maxMarkdownContentBytes = 500 * 1024

func (h *ArticleHandler) HandleSubmitURL(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	var req service.SubmitURLRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.URL == "" {
		writeError(w, http.StatusBadRequest, "url is required")
		return
	}

	// Truncate markdown_content if it exceeds 500 KB, ensuring valid UTF-8 boundary
	if req.MarkdownContent != nil && len(*req.MarkdownContent) > maxMarkdownContentBytes {
		truncated := (*req.MarkdownContent)[:maxMarkdownContentBytes]
		// Walk back from the cut point to find a valid UTF-8 boundary.
		// If the last byte(s) form an incomplete multi-byte sequence, remove them.
		for len(truncated) > 0 && !utf8.ValidString(truncated) {
			truncated = truncated[:len(truncated)-1]
		}
		req.MarkdownContent = &truncated
	}

	resp, err := h.articleService.SubmitURL(r.Context(), userID, req)
	if err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusAccepted, resp)
}

func (h *ArticleHandler) HandleListArticles(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	perPage, _ := strconv.Atoi(r.URL.Query().Get("per_page"))
	if page < 1 {
		page = 1
	}
	if perPage < 1 {
		perPage = 20
	}
	if perPage > 100 {
		perPage = 100
	}

	params := repository.ListArticlesParams{
		UserID:  userID,
		Page:    page,
		PerPage: perPage,
	}

	if cat := r.URL.Query().Get("category"); cat != "" {
		params.Category = &cat
	}
	if status := r.URL.Query().Get("status"); status != "" {
		s := domain.ArticleStatus(status)
		params.Status = &s
	}
	if fav := r.URL.Query().Get("favorite"); fav != "" {
		b := fav == "true"
		params.Favorite = &b
	}

	result, err := h.articleService.ListByUser(r.Context(), params)
	if err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, ListResponse{
		Data: result.Articles,
		Pagination: PaginationResponse{
			Page:    page,
			PerPage: perPage,
			Total:   result.Total,
		},
	})
}

func (h *ArticleHandler) HandleGetArticle(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	articleID := chi.URLParam(r, "id")

	article, err := h.articleService.GetByID(r.Context(), userID, articleID)
	if err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, article)
}

func (h *ArticleHandler) HandleUpdateArticle(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	articleID := chi.URLParam(r, "id")

	var params repository.UpdateArticleParams
	if err := json.NewDecoder(r.Body).Decode(&params); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := h.articleService.Update(r.Context(), userID, articleID, params); err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

func (h *ArticleHandler) HandleDeleteArticle(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	articleID := chi.URLParam(r, "id")

	if err := h.articleService.Delete(r.Context(), userID, articleID); err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
