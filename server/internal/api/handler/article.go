package handler

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"folio-server/internal/api/middleware"
	"folio-server/internal/domain"
	"folio-server/internal/repository"
	"folio-server/internal/service"
)

type ArticleHandler struct {
	articleService *service.ArticleService
}

func NewArticleHandler(articleService *service.ArticleService) *ArticleHandler {
	return &ArticleHandler{articleService: articleService}
}

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
