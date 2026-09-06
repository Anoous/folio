package domain

import "time"

type EchoCardType string

const (
	EchoCardInsight   EchoCardType = "insight"
	EchoCardHighlight EchoCardType = "highlight"
	EchoCardRelated   EchoCardType = "related"
)

type EchoReviewResult string

const (
	EchoRemembered EchoReviewResult = "remembered"
	EchoForgot     EchoReviewResult = "forgot"
)

type EchoCard struct {
	ID               string
	UserID           string
	ArticleID        string
	CardType         EchoCardType
	Question         string
	Answer           string
	SourceContext    *string
	NextReviewAt     time.Time
	IntervalDays     int
	EaseFactor       float64
	ReviewCount      int
	CorrectCount     int
	RelatedArticleID *string
	HighlightID      *string
	CreatedAt        time.Time
	UpdatedAt        time.Time
	// Joined fields (not stored directly)
	ArticleTitle string
}

type EchoReview struct {
	ID             string
	CardID         string
	UserID         string
	Result         EchoReviewResult
	ResponseTimeMs *int
	ReviewedAt     time.Time
}

type EchoStreak struct {
	WeeklyRate      int    // 0-100
	ConsecutiveDays int
	Display         string // "本周回忆率 85% · 已连续 7 天"
}
