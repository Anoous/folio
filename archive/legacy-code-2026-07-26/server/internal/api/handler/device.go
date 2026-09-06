package handler

import (
	"encoding/json"
	"net/http"

	"folio-server/internal/api/middleware"
	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

type DeviceHandler struct {
	deviceRepo *repository.DeviceRepo
}

func NewDeviceHandler(deviceRepo *repository.DeviceRepo) *DeviceHandler {
	return &DeviceHandler{deviceRepo: deviceRepo}
}

type registerDeviceRequest struct {
	Token    string `json:"token"`
	Platform string `json:"platform"`
}

func (h *DeviceHandler) HandleRegister(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	var req registerDeviceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.Token == "" {
		writeError(w, http.StatusBadRequest, "token is required")
		return
	}

	platform := req.Platform
	if platform == "" {
		platform = "ios"
	}

	device := &domain.Device{
		UserID:   userID,
		Token:    req.Token,
		Platform: platform,
	}

	if err := h.deviceRepo.Upsert(r.Context(), device); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to register device")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
