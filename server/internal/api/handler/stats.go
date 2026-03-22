package handler

import (
	"net/http"
	"time"

	"folio-server/internal/api/middleware"
	"folio-server/internal/domain"
	"folio-server/internal/repository"
	"folio-server/internal/service"
)

// StatsHandler handles statistics endpoints.
type StatsHandler struct {
	statsService *service.StatsService
	userRepo     *repository.UserRepo
}

// NewStatsHandler creates a new StatsHandler.
func NewStatsHandler(statsService *service.StatsService, userRepo *repository.UserRepo) *StatsHandler {
	return &StatsHandler{
		statsService: statsService,
		userRepo:     userRepo,
	}
}

// parseMonthParam parses a "YYYY-MM" query param. Defaults to the current month.
// Returns year and month.
func parseMonthParam(r *http.Request) (int, int) {
	raw := r.URL.Query().Get("month")
	if raw != "" {
		t, err := time.Parse("2006-01", raw)
		if err == nil {
			return t.Year(), int(t.Month())
		}
	}
	now := time.Now().UTC()
	return now.Year(), int(now.Month())
}

// checkProSubscription loads the user and returns false (writing 403) if not Pro.
func (h *StatsHandler) checkProSubscription(w http.ResponseWriter, r *http.Request, userID string) bool {
	user, err := h.userRepo.GetByID(r.Context(), userID)
	if err != nil || user == nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return false
	}
	if user.Subscription == domain.SubscriptionFree {
		writeError(w, http.StatusForbidden, "pro subscription required")
		return false
	}
	return true
}

// HandleMonthlyStats handles GET /api/v1/stats/monthly
func (h *StatsHandler) HandleMonthlyStats(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	if !h.checkProSubscription(w, r, userID) {
		return
	}

	year, month := parseMonthParam(r)

	stats, err := h.statsService.GetMonthlyStats(r.Context(), userID, year, month)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	type topicStatResponse struct {
		CategorySlug string `json:"category_slug"`
		CategoryName string `json:"category_name"`
		Count        int    `json:"count"`
	}

	type monthlyStatsResponse struct {
		ArticlesCount     int                 `json:"articles_count"`
		InsightsCount     int                 `json:"insights_count"`
		StreakDays        int                 `json:"streak_days"`
		TopicDistribution []topicStatResponse `json:"topic_distribution"`
		TrendInsight      *string             `json:"trend_insight"`
	}

	topics := make([]topicStatResponse, 0, len(stats.TopicDistribution))
	for _, ts := range stats.TopicDistribution {
		topics = append(topics, topicStatResponse{
			CategorySlug: ts.CategorySlug,
			CategoryName: ts.CategoryName,
			Count:        ts.Count,
		})
	}

	writeJSON(w, http.StatusOK, monthlyStatsResponse{
		ArticlesCount:     stats.ArticlesCount,
		InsightsCount:     stats.InsightsCount,
		StreakDays:        stats.StreakDays,
		TopicDistribution: topics,
		TrendInsight:      stats.TrendInsight,
	})
}

// HandleEchoStats handles GET /api/v1/stats/echo
func (h *StatsHandler) HandleEchoStats(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	if !h.checkProSubscription(w, r, userID) {
		return
	}

	year, month := parseMonthParam(r)

	stats, err := h.statsService.GetEchoStats(r.Context(), userID, year, month)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	type echoStatsResponse struct {
		CompletionRate  int `json:"completion_rate"`
		TotalReviews    int `json:"total_reviews"`
		RememberedCount int `json:"remembered_count"`
		ForgottenCount  int `json:"forgotten_count"`
	}

	writeJSON(w, http.StatusOK, echoStatsResponse{
		CompletionRate:  stats.CompletionRate,
		TotalReviews:    stats.TotalReviews,
		RememberedCount: stats.RememberedCount,
		ForgottenCount:  stats.ForgottenCount,
	})
}
