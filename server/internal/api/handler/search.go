package handler

import (
	"net/http"
	"strconv"

	"folio-server/internal/api/middleware"
	"folio-server/internal/service"
)

type SearchHandler struct {
	articleService *service.ArticleService
}

func NewSearchHandler(articleService *service.ArticleService) *SearchHandler {
	return &SearchHandler{articleService: articleService}
}

func (h *SearchHandler) HandleSearch(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	query := r.URL.Query().Get("q")
	if query == "" {
		writeError(w, http.StatusBadRequest, "q parameter is required")
		return
	}

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

	result, err := h.articleService.Search(r.Context(), userID, query, page, perPage)
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
