package handler

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"folio-server/internal/service"
)

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func handleServiceError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, service.ErrNotFound):
		slog.Debug("not found", "path", r.URL.Path)
		writeError(w, http.StatusNotFound, "not found")
	case errors.Is(err, service.ErrForbidden):
		slog.Debug("forbidden", "path", r.URL.Path)
		writeError(w, http.StatusForbidden, "forbidden")
	case errors.Is(err, service.ErrQuotaExceeded):
		slog.Info("quota exceeded", "path", r.URL.Path)
		writeError(w, http.StatusTooManyRequests, "monthly quota exceeded")
	case errors.Is(err, service.ErrDuplicateURL):
		slog.Debug("duplicate URL", "path", r.URL.Path)
		writeError(w, http.StatusConflict, "url already saved")
	default:
		slog.Error("internal error", "path", r.URL.Path, "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
	}
}

type PaginationResponse struct {
	Page    int `json:"page"`
	PerPage int `json:"per_page"`
	Total   int `json:"total"`
}

type ListResponse struct {
	Data       any                `json:"data"`
	Pagination PaginationResponse `json:"pagination"`
	ServerTime string             `json:"server_time,omitempty"`
}
