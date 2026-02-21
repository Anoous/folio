package handler

import "net/http"

type SubscriptionHandler struct{}

func NewSubscriptionHandler() *SubscriptionHandler {
	return &SubscriptionHandler{}
}

func (h *SubscriptionHandler) HandleVerify(w http.ResponseWriter, r *http.Request) {
	writeError(w, http.StatusNotImplemented, "subscription verification not yet implemented")
}
