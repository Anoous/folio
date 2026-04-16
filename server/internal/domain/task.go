package domain

import "time"

type TaskStatus string

const (
	TaskStatusQueued       TaskStatus = "queued"
	TaskStatusCrawling     TaskStatus = "crawling"
	TaskStatusAIProcessing TaskStatus = "ai_processing"
	TaskStatusDone         TaskStatus = "done"
	TaskStatusFailed       TaskStatus = "failed"
)

type CrawlTask struct {
	ID              string     `json:"id"`
	ArticleID       *string    `json:"article_id,omitempty"`
	UserID          string     `json:"user_id"`
	URL             *string    `json:"url,omitempty"`
	SourceType      *string    `json:"source_type,omitempty"`
	Status          TaskStatus `json:"status"`
	CrawlStartedAt  *time.Time `json:"crawl_started_at,omitempty"`
	CrawlFinishedAt *time.Time `json:"crawl_finished_at,omitempty"`
	AIStartedAt     *time.Time `json:"ai_started_at,omitempty"`
	AIFinishedAt    *time.Time `json:"ai_finished_at,omitempty"`
	ErrorMessage    *string    `json:"error_message,omitempty"`
	ErrorStage      *string    `json:"error_stage,omitempty"`
	ErrorCode       *string    `json:"error_code,omitempty"`
	ErrorProvider   *string    `json:"error_provider,omitempty"`
	ErrorRetryable  *bool      `json:"error_retryable,omitempty"`
	LastDurationMs  *int64     `json:"last_duration_ms,omitempty"`
	LastAttemptAt   *time.Time `json:"last_attempt_at,omitempty"`
	RetryCount      int        `json:"retry_count"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
}

type TaskFailure struct {
	Message    string
	Stage      *string
	Code       *string
	Provider   *string
	Retryable  *bool
	DurationMs *int64
}
