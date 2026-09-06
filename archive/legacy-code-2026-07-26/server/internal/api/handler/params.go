package handler

import (
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

func requireUUIDParam(w http.ResponseWriter, r *http.Request, name, label string) (string, bool) {
	value := chi.URLParam(r, name)
	if value == "" {
		writeError(w, http.StatusBadRequest, label+" is required")
		return "", false
	}

	if _, err := uuid.Parse(value); err != nil {
		writeError(w, http.StatusBadRequest, "invalid "+label)
		return "", false
	}

	return value, true
}
