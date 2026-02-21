package handler

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"

	"folio-server/internal/api/middleware"
	"folio-server/internal/service"
)

type TagHandler struct {
	tagService *service.TagService
}

func NewTagHandler(tagService *service.TagService) *TagHandler {
	return &TagHandler{tagService: tagService}
}

func (h *TagHandler) HandleListTags(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	tags, err := h.tagService.ListByUser(r.Context(), userID)
	if err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, ListResponse{
		Data: tags,
		Pagination: PaginationResponse{
			Page:    1,
			PerPage: len(tags),
			Total:   len(tags),
		},
	})
}

func (h *TagHandler) HandleCreateTag(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.Name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}

	tag, err := h.tagService.Create(r.Context(), userID, req.Name)
	if err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusCreated, tag)
}

func (h *TagHandler) HandleDeleteTag(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	tagID := chi.URLParam(r, "id")

	if err := h.tagService.Delete(r.Context(), userID, tagID); err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
