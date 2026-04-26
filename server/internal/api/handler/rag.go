package handler

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"

	"folio-server/internal/api/middleware"
	"folio-server/internal/domain"
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
	ArticleID       string  `json:"article_id"`
	Title           string  `json:"title"`
	SiteName        *string `json:"site_name"`
	Summary         *string `json:"summary"`
	EvidenceSnippet *string `json:"evidence_snippet,omitempty"`
	CreatedAt       string  `json:"created_at"`
	Relevance       float64 `json:"relevance"`
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

	writeJSON(w, http.StatusOK, ragQueryResponse{
		Answer:              result.Answer,
		Sources:             domainSourcesToResponse(result.Sources),
		SourceCount:         result.SourceCount,
		FollowupSuggestions: result.FollowupSuggestions,
		ConversationID:      result.ConversationID,
	})
}

// HandleQueryStream handles POST /api/v1/rag/query/stream via Server-Sent Events.
func (h *RAGHandler) HandleQueryStream(w http.ResponseWriter, r *http.Request) {
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

	flusher, ok := w.(http.Flusher)
	if !ok {
		writeError(w, http.StatusInternalServerError, "streaming not supported")
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")

	conversationID := ""
	if req.ConversationID != nil {
		conversationID = *req.ConversationID
	}

	eventCh := make(chan domain.RAGStreamEvent, 8)
	go h.ragService.QueryStream(r.Context(), userID, req.Question, conversationID, eventCh)

	for {
		select {
		case event, ok := <-eventCh:
			if !ok {
				return
			}
			writeSSEEvent(w, flusher, event)
		case <-r.Context().Done():
			return
		}
	}
}

func writeSSEEvent(w http.ResponseWriter, flusher http.Flusher, event domain.RAGStreamEvent) {
	var data []byte

	switch event.Type {
	case "sources":
		data, _ = json.Marshal(struct {
			Sources        []ragSourceResponse `json:"sources"`
			SourceCount    int                 `json:"source_count"`
			ConversationID string              `json:"conversation_id"`
		}{
			Sources:        domainSourcesToResponse(event.Sources),
			SourceCount:    event.SourceCount,
			ConversationID: event.ConversationID,
		})
	case "delta":
		data, _ = json.Marshal(struct {
			Text string `json:"text"`
		}{Text: event.Text})
	case "done":
		citedIndices := event.CitedIndices
		if citedIndices == nil {
			citedIndices = []int{}
		}
		followups := event.FollowupSuggestions
		if followups == nil {
			followups = []string{}
		}
		data, _ = json.Marshal(struct {
			CitedIndices        []int    `json:"cited_indices"`
			FollowupSuggestions []string `json:"followup_suggestions"`
		}{
			CitedIndices:        citedIndices,
			FollowupSuggestions: followups,
		})
	case "error":
		data, _ = json.Marshal(struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		}{Code: event.ErrorCode, Message: event.ErrorMessage})
	}

	fmt.Fprintf(w, "event: %s\ndata: %s\n\n", event.Type, string(data))
	flusher.Flush()
}

func domainSourcesToResponse(sources []domain.RAGSource) []ragSourceResponse {
	result := make([]ragSourceResponse, 0, len(sources))
	for _, s := range sources {
		result = append(result, ragSourceResponse{
			ArticleID:       s.ArticleID,
			Title:           s.Title,
			SiteName:        s.SiteName,
			Summary:         s.Summary,
			EvidenceSnippet: s.EvidenceSnippet,
			CreatedAt:       s.CreatedAt.UTC().Format("2006-01-02T15:04:05Z07:00"),
			Relevance:       s.Relevance,
		})
	}
	return result
}
