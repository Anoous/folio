package handler

import (
	"context"
	"encoding/json"
	"net/http"

	"folio-server/internal/api/middleware"
	"folio-server/internal/service"
)

type knowledgeServicer interface {
	Spark(ctx context.Context, userID, prompt string) (*service.KnowledgeSparkResult, error)
	Learn(ctx context.Context, userID, prompt string) (*service.KnowledgeLearnResult, error)
}

type KnowledgeHandler struct {
	knowledgeService knowledgeServicer
}

func NewKnowledgeHandler(knowledgeService knowledgeServicer) *KnowledgeHandler {
	return &KnowledgeHandler{knowledgeService: knowledgeService}
}

type knowledgePromptRequest struct {
	Prompt string `json:"prompt"`
}

func (h *KnowledgeHandler) HandleSpark(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	var req knowledgePromptRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	result, err := h.knowledgeService.Spark(r.Context(), userID, req.Prompt)
	if err != nil {
		handleServiceError(w, r, err)
		return
	}

	writeJSON(w, http.StatusOK, result)
}

func (h *KnowledgeHandler) HandleLearn(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	var req knowledgePromptRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	result, err := h.knowledgeService.Learn(r.Context(), userID, req.Prompt)
	if err != nil {
		handleServiceError(w, r, err)
		return
	}

	writeJSON(w, http.StatusOK, result)
}
