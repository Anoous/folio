package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"folio-server/internal/domain"
)

// Task status values used in SQL queries (from domain.TaskStatus constants).
var (
	taskStatusCrawling     = string(domain.TaskStatusCrawling)
	taskStatusAIProcessing = string(domain.TaskStatusAIProcessing)
	taskStatusDone         = string(domain.TaskStatusDone)
	taskStatusFailed       = string(domain.TaskStatusFailed)
)

type TaskRepo struct {
	pool *pgxpool.Pool
}

func NewTaskRepo(pool *pgxpool.Pool) *TaskRepo {
	return &TaskRepo{pool: pool}
}

type CreateTaskParams struct {
	ArticleID  string
	UserID     string
	URL        *string
	SourceType string
}

func (r *TaskRepo) Create(ctx context.Context, p CreateTaskParams) (*domain.CrawlTask, error) {
	var t domain.CrawlTask
	err := r.pool.QueryRow(ctx, `
		INSERT INTO crawl_tasks (article_id, user_id, url, source_type)
		VALUES ($1, $2, $3, $4)
		RETURNING id, article_id, user_id, url, source_type, status, created_at, updated_at`,
		p.ArticleID, p.UserID, p.URL, p.SourceType,
	).Scan(&t.ID, &t.ArticleID, &t.UserID, &t.URL, &t.SourceType, &t.Status, &t.CreatedAt, &t.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("create task: %w", err)
	}
	return &t, nil
}

func (r *TaskRepo) GetByID(ctx context.Context, id string) (*domain.CrawlTask, error) {
	var t domain.CrawlTask
	err := r.pool.QueryRow(ctx, `
		SELECT id, article_id, user_id, url, source_type, status,
		       crawl_started_at, crawl_finished_at, ai_started_at, ai_finished_at,
		       error_message, error_stage, error_code, error_provider,
		       error_retryable, last_duration_ms, last_attempt_at,
		       retry_count, created_at, updated_at
		FROM crawl_tasks WHERE id = $1`, id,
	).Scan(
		&t.ID, &t.ArticleID, &t.UserID, &t.URL, &t.SourceType, &t.Status,
		&t.CrawlStartedAt, &t.CrawlFinishedAt, &t.AIStartedAt, &t.AIFinishedAt,
		&t.ErrorMessage, &t.ErrorStage, &t.ErrorCode, &t.ErrorProvider,
		&t.ErrorRetryable, &t.LastDurationMs, &t.LastAttemptAt,
		&t.RetryCount, &t.CreatedAt, &t.UpdatedAt,
	)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get task: %w", err)
	}
	return &t, nil
}

func (r *TaskRepo) SetCrawlStarted(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE crawl_tasks SET status = $2, crawl_started_at = NOW() WHERE id = $1`, id, taskStatusCrawling)
	if err != nil {
		return fmt.Errorf("set crawl started: %w", err)
	}
	return nil
}

func (r *TaskRepo) SetCrawlFinished(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE crawl_tasks SET crawl_finished_at = NOW() WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("set crawl finished: %w", err)
	}
	return nil
}

func (r *TaskRepo) SetAIStarted(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE crawl_tasks SET status = $2, ai_started_at = NOW() WHERE id = $1`, id, taskStatusAIProcessing)
	if err != nil {
		return fmt.Errorf("set ai started: %w", err)
	}
	return nil
}

func (r *TaskRepo) SetAIFinished(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE crawl_tasks SET status = $2, ai_finished_at = NOW() WHERE id = $1`, id, taskStatusDone)
	if err != nil {
		return fmt.Errorf("set ai finished: %w", err)
	}
	return nil
}

func (r *TaskRepo) SetFailed(ctx context.Context, id string, failure domain.TaskFailure) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE crawl_tasks
		 SET status = $8,
		     error_message = $1,
		     error_stage = $2,
		     error_code = $3,
		     error_provider = $4,
		     error_retryable = $5,
		     last_duration_ms = $6,
		     last_attempt_at = NOW(),
		     retry_count = retry_count + 1
		 WHERE id = $7`,
		failure.Message,
		nullableString(failure.Stage),
		nullableString(failure.Code),
		nullableString(failure.Provider),
		nullableBool(failure.Retryable),
		nullableInt64(failure.DurationMs),
		id,
		taskStatusFailed,
	)
	if err != nil {
		return fmt.Errorf("set task failed: %w", err)
	}
	return nil
}

func nullableString(value *string) any {
	if value == nil || *value == "" {
		return nil
	}
	return *value
}

func nullableBool(value *bool) any {
	if value == nil {
		return nil
	}
	return *value
}

func nullableInt64(value *int64) any {
	if value == nil {
		return nil
	}
	return *value
}
