package handler

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"folio-server/internal/api/middleware"
	"folio-server/internal/service"
)

type SubscriptionHandler struct {
	subscriptionService *service.SubscriptionService
}

func NewSubscriptionHandler(subscriptionService *service.SubscriptionService) *SubscriptionHandler {
	return &SubscriptionHandler{subscriptionService: subscriptionService}
}

// HandleVerify handles POST /api/v1/subscription/verify.
// Requires JWT auth — extracts userID from context.
func (h *SubscriptionHandler) HandleVerify(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	if userID == "" {
		writeError(w, http.StatusUnauthorized, "missing user ID")
		return
	}

	var body struct {
		TransactionID string `json:"transaction_id"`
		ProductID     string `json:"product_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if body.TransactionID == "" {
		writeError(w, http.StatusBadRequest, "transaction_id is required")
		return
	}
	if body.ProductID == "" {
		writeError(w, http.StatusBadRequest, "product_id is required")
		return
	}

	result, err := h.subscriptionService.VerifyAndActivate(r.Context(), userID, body.TransactionID, body.ProductID)
	if err != nil {
		handleServiceError(w, r, err)
		return
	}

	writeJSON(w, http.StatusOK, result)
}

// HandleWebhook handles POST /api/v1/webhook/apple.
// This is a PUBLIC endpoint — Apple calls it without JWT auth.
// Always returns 200 OK to prevent Apple from retrying.
func (h *SubscriptionHandler) HandleWebhook(w http.ResponseWriter, r *http.Request) {
	var body struct {
		SignedPayload string `json:"signedPayload"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		slog.Warn("webhook: invalid request body", "error", err)
		// Still return 200 to Apple.
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
		return
	}
	if body.SignedPayload == "" {
		slog.Warn("webhook: empty signedPayload")
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
		return
	}

	if err := h.subscriptionService.HandleWebhookEvent(r.Context(), body.SignedPayload); err != nil {
		slog.Error("webhook: processing failed", "error", err)
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
