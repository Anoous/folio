package handler

import (
	"encoding/json"
	"errors"
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

func handleServiceError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, service.ErrNotFound):
		writeError(w, http.StatusNotFound, "not found")
	case errors.Is(err, service.ErrForbidden):
		writeError(w, http.StatusForbidden, "forbidden")
	case errors.Is(err, service.ErrQuotaExceeded):
		writeError(w, http.StatusTooManyRequests, "monthly quota exceeded")
	default:
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
}
