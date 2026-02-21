package handler

import (
	"net/http"

	"folio-server/internal/repository"
)

type CategoryHandler struct {
	categoryRepo *repository.CategoryRepo
}

func NewCategoryHandler(categoryRepo *repository.CategoryRepo) *CategoryHandler {
	return &CategoryHandler{categoryRepo: categoryRepo}
}

func (h *CategoryHandler) HandleListCategories(w http.ResponseWriter, r *http.Request) {
	categories, err := h.categoryRepo.ListAll(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	writeJSON(w, http.StatusOK, ListResponse{
		Data: categories,
		Pagination: PaginationResponse{
			Page:    1,
			PerPage: len(categories),
			Total:   len(categories),
		},
	})
}
