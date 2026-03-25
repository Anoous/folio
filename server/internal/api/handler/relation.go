package handler

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"folio-server/internal/api/middleware"
	"folio-server/internal/repository"
)

type RelationHandler struct {
	relationRepo *repository.RelationRepo
}

func NewRelationHandler(relationRepo *repository.RelationRepo) *RelationHandler {
	return &RelationHandler{relationRepo: relationRepo}
}

func (h *RelationHandler) HandleGetRelated(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	articleID := chi.URLParam(r, "id")
	if articleID == "" {
		writeError(w, http.StatusBadRequest, "article id required")
		return
	}

	related, err := h.relationRepo.ListBySource(r.Context(), userID, articleID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get related articles")
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"articles": related,
	})
}
