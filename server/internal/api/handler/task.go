package handler

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"folio-server/internal/api/middleware"
	"folio-server/internal/repository"
)

type TaskHandler struct {
	taskRepo *repository.TaskRepo
}

func NewTaskHandler(taskRepo *repository.TaskRepo) *TaskHandler {
	return &TaskHandler{taskRepo: taskRepo}
}

func (h *TaskHandler) HandleGetTask(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	taskID := chi.URLParam(r, "id")

	task, err := h.taskRepo.GetByID(r.Context(), taskID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	if task == nil {
		writeError(w, http.StatusNotFound, "task not found")
		return
	}
	if task.UserID != userID {
		writeError(w, http.StatusForbidden, "forbidden")
		return
	}

	writeJSON(w, http.StatusOK, task)
}
