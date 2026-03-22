package handler

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"folio-server/internal/api/middleware"
	"folio-server/internal/domain"
	"folio-server/internal/service"
)

type EchoHandler struct {
	echoService *service.EchoService
}

func NewEchoHandler(echoService *service.EchoService) *EchoHandler {
	return &EchoHandler{echoService: echoService}
}

type echoCardResponse struct {
	ID            string  `json:"id"`
	ArticleID     string  `json:"article_id"`
	ArticleTitle  string  `json:"article_title"`
	CardType      string  `json:"card_type"`
	Question      string  `json:"question"`
	Answer        string  `json:"answer"`
	SourceContext *string `json:"source_context,omitempty"`
	NextReviewAt  string  `json:"next_review_at"`
	IntervalDays  int     `json:"interval_days"`
	ReviewCount   int     `json:"review_count"`
}

type getTodayResponse struct {
	Data           []echoCardResponse `json:"data"`
	RemainingToday int                `json:"remaining_today"`
	WeeklyCount    int                `json:"weekly_count"`
	WeeklyLimit    *int               `json:"weekly_limit"`
}

func (h *EchoHandler) HandleGetToday(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	limit := 5
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			limit = n
		}
	}

	cards, remaining, weeklyCount, weeklyLimit, err := h.echoService.GetTodayCards(r.Context(), userID, limit)
	if err != nil {
		handleServiceError(w, r, err)
		return
	}

	data := make([]echoCardResponse, 0, len(cards))
	for _, c := range cards {
		data = append(data, echoCardResponse{
			ID:            c.ID,
			ArticleID:     c.ArticleID,
			ArticleTitle:  c.ArticleTitle,
			CardType:      string(c.CardType),
			Question:      c.Question,
			Answer:        c.Answer,
			SourceContext: c.SourceContext,
			NextReviewAt:  c.NextReviewAt.UTC().Format("2006-01-02T15:04:05Z07:00"),
			IntervalDays:  c.IntervalDays,
			ReviewCount:   c.ReviewCount,
		})
	}

	writeJSON(w, http.StatusOK, getTodayResponse{
		Data:           data,
		RemainingToday: remaining,
		WeeklyCount:    weeklyCount,
		WeeklyLimit:    weeklyLimit,
	})
}

type submitReviewRequest struct {
	Result         string `json:"result"`
	ResponseTimeMs *int   `json:"response_time_ms,omitempty"`
}

type streakResponse struct {
	WeeklyRate      int    `json:"weekly_rate"`
	ConsecutiveDays int    `json:"consecutive_days"`
	Display         string `json:"display"`
}

type submitReviewResponse struct {
	NextReviewAt string         `json:"next_review_at"`
	IntervalDays int            `json:"interval_days"`
	ReviewCount  int            `json:"review_count"`
	CorrectCount int            `json:"correct_count"`
	Streak       streakResponse `json:"streak"`
}

func (h *EchoHandler) HandleSubmitReview(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	cardID := chi.URLParam(r, "id")

	var req submitReviewRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	result := domain.EchoReviewResult(req.Result)
	if result != domain.EchoRemembered && result != domain.EchoForgot {
		writeError(w, http.StatusBadRequest, "result must be \"remembered\" or \"forgot\"")
		return
	}

	rv, err := h.echoService.SubmitReview(r.Context(), userID, cardID, result, req.ResponseTimeMs)
	if err != nil {
		handleServiceError(w, r, err)
		return
	}

	writeJSON(w, http.StatusOK, submitReviewResponse{
		NextReviewAt: rv.NextReviewAt.UTC().Format("2006-01-02T15:04:05Z07:00"),
		IntervalDays: rv.IntervalDays,
		ReviewCount:  rv.ReviewCount,
		CorrectCount: rv.CorrectCount,
		Streak: streakResponse{
			WeeklyRate:      rv.Streak.WeeklyRate,
			ConsecutiveDays: rv.Streak.ConsecutiveDays,
			Display:         rv.Streak.Display,
		},
	})
}
