package handler

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"

	"folio-server/internal/api/middleware"
	"folio-server/internal/service"
)

type HighlightHandler struct {
	highlightService *service.HighlightService
}

func NewHighlightHandler(highlightService *service.HighlightService) *HighlightHandler {
	return &HighlightHandler{highlightService: highlightService}
}

type createHighlightRequest struct {
	Text        string `json:"text"`
	StartOffset int    `json:"start_offset"`
	EndOffset   int    `json:"end_offset"`
}

type highlightResponse struct {
	ID          string  `json:"id"`
	ArticleID   string  `json:"article_id"`
	Text        string  `json:"text"`
	StartOffset int     `json:"start_offset"`
	EndOffset   int     `json:"end_offset"`
	Color       string  `json:"color"`
	Note        *string `json:"note,omitempty"`
	CreatedAt   string  `json:"created_at"`
}

// HandleCreateHighlight handles POST /api/v1/articles/{id}/highlights
func (h *HighlightHandler) HandleCreateHighlight(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	articleID := chi.URLParam(r, "id")

	var req createHighlightRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.Text == "" {
		writeError(w, http.StatusBadRequest, "text is required")
		return
	}

	highlight, err := h.highlightService.CreateHighlight(
		r.Context(), userID, articleID,
		req.Text, req.StartOffset, req.EndOffset,
	)
	if err != nil {
		handleServiceError(w, r, err)
		return
	}

	writeJSON(w, http.StatusCreated, highlightResponse{
		ID:          highlight.ID,
		ArticleID:   highlight.ArticleID,
		Text:        highlight.Text,
		StartOffset: highlight.StartOffset,
		EndOffset:   highlight.EndOffset,
		Color:       highlight.Color,
		Note:        highlight.Note,
		CreatedAt:   highlight.CreatedAt.UTC().Format("2006-01-02T15:04:05Z07:00"),
	})
}

// HandleGetHighlights handles GET /api/v1/articles/{id}/highlights
func (h *HighlightHandler) HandleGetHighlights(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	articleID := chi.URLParam(r, "id")

	highlights, err := h.highlightService.GetArticleHighlights(r.Context(), userID, articleID)
	if err != nil {
		handleServiceError(w, r, err)
		return
	}

	data := make([]highlightResponse, 0, len(highlights))
	for _, hl := range highlights {
		data = append(data, highlightResponse{
			ID:          hl.ID,
			ArticleID:   hl.ArticleID,
			Text:        hl.Text,
			StartOffset: hl.StartOffset,
			EndOffset:   hl.EndOffset,
			Color:       hl.Color,
			Note:        hl.Note,
			CreatedAt:   hl.CreatedAt.UTC().Format("2006-01-02T15:04:05Z07:00"),
		})
	}

	writeJSON(w, http.StatusOK, map[string]any{"data": data})
}

// HandleDeleteHighlight handles DELETE /api/v1/highlights/{id}
func (h *HighlightHandler) HandleDeleteHighlight(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	highlightID := chi.URLParam(r, "id")

	if err := h.highlightService.DeleteHighlight(r.Context(), userID, highlightID); err != nil {
		handleServiceError(w, r, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
