package service

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"folio-server/internal/client"
	"folio-server/internal/repository"

	"github.com/jackc/pgx/v5/pgxpool"
)

// StatsService provides monthly and echo statistics for users.
type StatsService struct {
	db       *pgxpool.Pool
	aiClient client.Analyzer
	userRepo *repository.UserRepo
}

// NewStatsService creates a new StatsService.
func NewStatsService(db *pgxpool.Pool, aiClient client.Analyzer, userRepo *repository.UserRepo) *StatsService {
	return &StatsService{
		db:       db,
		aiClient: aiClient,
		userRepo: userRepo,
	}
}

// TopicStat holds per-category article counts.
type TopicStat struct {
	CategorySlug string `json:"category_slug"`
	CategoryName string `json:"category_name"`
	Count        int    `json:"count"`
}

// MonthlyStats is the response for the monthly stats endpoint.
type MonthlyStats struct {
	ArticlesCount     int         `json:"articles_count"`
	InsightsCount     int         `json:"insights_count"`
	StreakDays        int         `json:"streak_days"`
	TopicDistribution []TopicStat `json:"topic_distribution"`
	TrendInsight      *string     `json:"trend_insight"`
}

// EchoStats is the response for the echo stats endpoint.
type EchoStats struct {
	CompletionRate  int `json:"completion_rate"`
	TotalReviews    int `json:"total_reviews"`
	RememberedCount int `json:"remembered_count"`
	ForgottenCount  int `json:"forgotten_count"`
}

// monthRange returns the [start, end) time range for the given year/month in UTC.
func monthRange(year, month int) (start, end time.Time) {
	start = time.Date(year, time.Month(month), 1, 0, 0, 0, 0, time.UTC)
	end = start.AddDate(0, 1, 0)
	return
}

// GetMonthlyStats returns aggregated reading stats for the given month.
func (s *StatsService) GetMonthlyStats(ctx context.Context, userID string, year, month int) (*MonthlyStats, error) {
	start, end := monthRange(year, month)

	// 1. articles_count: ready articles created in the month
	var articlesCount int
	err := s.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM articles
		WHERE user_id = $1 AND status = 'ready'
		  AND created_at >= $2 AND created_at < $3`,
		userID, start, end,
	).Scan(&articlesCount)
	if err != nil {
		return nil, fmt.Errorf("count articles: %w", err)
	}

	// 2. insights_count: articles with non-empty summary in the month
	var insightsCount int
	err = s.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM articles
		WHERE user_id = $1
		  AND summary IS NOT NULL AND summary != ''
		  AND created_at >= $2 AND created_at < $3`,
		userID, start, end,
	).Scan(&insightsCount)
	if err != nil {
		return nil, fmt.Errorf("count insights: %w", err)
	}

	// 3. streak_days: consecutive days up to today with at least one article saved
	streakDays, err := s.calcStreakDays(ctx, userID)
	if err != nil {
		slog.Warn("failed to compute streak days", "user_id", userID, "error", err)
		streakDays = 0
	}

	// 4. topic_distribution: category breakdown for the month
	topicDist, err := s.getTopicDistribution(ctx, userID, start, end)
	if err != nil {
		slog.Warn("failed to get topic distribution", "user_id", userID, "error", err)
		topicDist = []TopicStat{}
	}

	// 5. trend_insight: compare this month vs last month (AI only)
	var trendInsight *string
	if s.aiClient.IsRealAI() {
		// Only call AI when a real analyzer is wired (i.e. DeepSeek key is present).
		prevYear, prevMonth := year, month-1
		if prevMonth == 0 {
			prevMonth = 12
			prevYear--
		}
		prevStart, prevEnd := monthRange(prevYear, prevMonth)
		prevDist, err := s.getTopicDistribution(ctx, userID, prevStart, prevEnd)
		if err != nil {
			slog.Warn("failed to get prev topic distribution for trend", "error", err)
		} else {
			insight := s.generateTrendInsight(ctx, topicDist, prevDist)
			trendInsight = insight
		}
	}

	return &MonthlyStats{
		ArticlesCount:     articlesCount,
		InsightsCount:     insightsCount,
		StreakDays:        streakDays,
		TopicDistribution: topicDist,
		TrendInsight:      trendInsight,
	}, nil
}

// calcStreakDays counts consecutive days with at least one saved article,
// walking backwards from today.
func (s *StatsService) calcStreakDays(ctx context.Context, userID string) (int, error) {
	rows, err := s.db.Query(ctx, `
		SELECT DISTINCT DATE(created_at AT TIME ZONE 'UTC') AS day
		FROM articles
		WHERE user_id = $1
		ORDER BY day DESC
		LIMIT 366`, userID)
	if err != nil {
		return 0, fmt.Errorf("query streak dates: %w", err)
	}
	defer rows.Close()

	var dates []time.Time
	for rows.Next() {
		var d time.Time
		if err := rows.Scan(&d); err != nil {
			return 0, fmt.Errorf("scan streak date: %w", err)
		}
		dates = append(dates, d.UTC())
	}
	if err := rows.Err(); err != nil {
		return 0, fmt.Errorf("iterate streak dates: %w", err)
	}

	if len(dates) == 0 {
		return 0, nil
	}

	today := time.Now().UTC()
	todayDate := time.Date(today.Year(), today.Month(), today.Day(), 0, 0, 0, 0, time.UTC)

	streak := 0
	expected := todayDate
	for _, d := range dates {
		day := time.Date(d.Year(), d.Month(), d.Day(), 0, 0, 0, 0, time.UTC)
		if !day.Equal(expected) {
			break
		}
		streak++
		expected = expected.AddDate(0, 0, -1)
	}
	return streak, nil
}

// getTopicDistribution returns per-category article counts for the given period.
func (s *StatsService) getTopicDistribution(ctx context.Context, userID string, start, end time.Time) ([]TopicStat, error) {
	rows, err := s.db.Query(ctx, `
		SELECT c.slug, c.name_zh, COUNT(a.id) AS cnt
		FROM articles a
		JOIN categories c ON a.category_id = c.id
		WHERE a.user_id = $1
		  AND a.created_at >= $2 AND a.created_at < $3
		GROUP BY c.slug, c.name_zh
		ORDER BY cnt DESC
		LIMIT 10`,
		userID, start, end,
	)
	if err != nil {
		return nil, fmt.Errorf("query topic distribution: %w", err)
	}
	defer rows.Close()

	var stats []TopicStat
	for rows.Next() {
		var ts TopicStat
		if err := rows.Scan(&ts.CategorySlug, &ts.CategoryName, &ts.Count); err != nil {
			return nil, fmt.Errorf("scan topic stat: %w", err)
		}
		stats = append(stats, ts)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate topic stats: %w", err)
	}
	if stats == nil {
		stats = []TopicStat{}
	}
	return stats, nil
}

// generateTrendInsight calls DeepSeek to produce a one-sentence trend summary.
// Returns nil on any error so callers can treat it as optional.
func (s *StatsService) generateTrendInsight(ctx context.Context, current, prev []TopicStat) *string {
	currentMap := topicStatMap(current)
	prevMap := topicStatMap(prev)

	if len(currentMap) == 0 && len(prevMap) == 0 {
		return nil
	}

	currentJSON, _ := json.Marshal(currentMap)
	prevJSON, _ := json.Marshal(prevMap)

	prompt := fmt.Sprintf(
		"用一句话总结用户的阅读趋势变化（不超过 50 字）。\n本月收藏分布：%s\n上月收藏分布：%s",
		string(currentJSON), string(prevJSON),
	)

	systemPrompt := "你是用户的个人知识助手，帮助分析阅读趋势。直接输出一句话，不要 JSON，不要解释。"

	result, err := s.aiClient.GenerateRAGAnswer(ctx, systemPrompt, prompt)
	if err != nil {
		slog.Warn("trend insight ai call failed", "error", err)
		return nil
	}

	// GenerateRAGAnswer returns a RAGResult struct; we want just the Answer field.
	// Strip trailing whitespace/newlines.
	insight := strings.TrimSpace(result.Answer)
	if insight == "" {
		return nil
	}
	return &insight
}

// topicStatMap converts a slice of TopicStat to a map[slug]count for JSON serialisation.
func topicStatMap(stats []TopicStat) map[string]int {
	m := make(map[string]int, len(stats))
	for _, ts := range stats {
		m[ts.CategorySlug] = ts.Count
	}
	return m
}

// GetEchoStats returns echo review statistics for the given month.
func (s *StatsService) GetEchoStats(ctx context.Context, userID string, year, month int) (*EchoStats, error) {
	start, end := monthRange(year, month)

	var remembered, total int
	err := s.db.QueryRow(ctx, `
		SELECT
			COUNT(*) FILTER (WHERE result = 'remembered') AS remembered,
			COUNT(*) AS total
		FROM echo_reviews
		WHERE user_id = $1
		  AND reviewed_at >= $2 AND reviewed_at < $3`,
		userID, start, end,
	).Scan(&remembered, &total)
	if err != nil {
		return nil, fmt.Errorf("query echo stats: %w", err)
	}

	completionRate := 0
	if total > 0 {
		completionRate = remembered * 100 / total
	}

	forgotten := total - remembered

	return &EchoStats{
		CompletionRate:  completionRate,
		TotalReviews:    total,
		RememberedCount: remembered,
		ForgottenCount:  forgotten,
	}, nil
}
