package handler

import (
	"encoding/json"
	"errors"
	"net/http"

	"folio-server/internal/api/middleware"
	"folio-server/internal/service"
)

// RAGHandler handles RAG (Retrieval-Augmented Generation) endpoints.
type RAGHandler struct {
	ragService *service.RAGService
}

// NewRAGHandler creates a new RAGHandler.
func NewRAGHandler(ragService *service.RAGService) *RAGHandler {
	return &RAGHandler{ragService: ragService}
}

type ragQueryRequest struct {
	Question       string  `json:"question"`
	ConversationID *string `json:"conversation_id"`
}

type ragSourceResponse struct {
	ArticleID string  `json:"article_id"`
	Title     string  `json:"title"`
	SiteName  *string `json:"site_name"`
	Summary   *string `json:"summary"`
	CreatedAt string  `json:"created_at"`
	Relevance float64 `json:"relevance"`
}

type ragQueryResponse struct {
	Answer              string              `json:"answer"`
	Sources             []ragSourceResponse `json:"sources"`
	SourceCount         int                 `json:"source_count"`
	FollowupSuggestions []string            `json:"followup_suggestions"`
	ConversationID      string              `json:"conversation_id"`
}

// HandleQuery handles POST /api/v1/rag/query
func (h *RAGHandler) HandleQuery(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	var req ragQueryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.Question == "" {
		writeError(w, http.StatusBadRequest, "question is required")
		return
	}
	if len([]rune(req.Question)) > 500 {
		writeError(w, http.StatusBadRequest, "question must be 500 characters or fewer")
		return
	}

	conversationID := ""
	if req.ConversationID != nil {
		conversationID = *req.ConversationID
	}

	result, err := h.ragService.Query(r.Context(), userID, req.Question, conversationID)
	if err != nil {
		if errors.Is(err, service.ErrRAGQuotaExceeded) {
			writeError(w, http.StatusTooManyRequests, "monthly RAG quota exceeded")
			return
		}
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	sources := make([]ragSourceResponse, 0, len(result.Sources))
	for _, s := range result.Sources {
		sources = append(sources, ragSourceResponse{
			ArticleID: s.ArticleID,
			Title:     s.Title,
			SiteName:  s.SiteName,
			Summary:   s.Summary,
			CreatedAt: s.CreatedAt.UTC().Format("2006-01-02T15:04:05Z07:00"),
			Relevance: s.Relevance,
		})
	}

	writeJSON(w, http.StatusOK, ragQueryResponse{
		Answer:              result.Answer,
		Sources:             sources,
		SourceCount:         result.SourceCount,
		FollowupSuggestions: result.FollowupSuggestions,
		ConversationID:      result.ConversationID,
	})
}
