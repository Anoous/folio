package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"folio-server/internal/domain"
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
	URL        string
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
		       error_message, retry_count, created_at, updated_at
		FROM crawl_tasks WHERE id = $1`, id,
	).Scan(
		&t.ID, &t.ArticleID, &t.UserID, &t.URL, &t.SourceType, &t.Status,
		&t.CrawlStartedAt, &t.CrawlFinishedAt, &t.AIStartedAt, &t.AIFinishedAt,
		&t.ErrorMessage, &t.RetryCount, &t.CreatedAt, &t.UpdatedAt,
	)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get task: %w", err)
	}
	return &t, nil
}

func (r *TaskRepo) UpdateStatus(ctx context.Context, id string, status domain.TaskStatus) error {
	_, err := r.pool.Exec(ctx, `UPDATE crawl_tasks SET status = $1 WHERE id = $2`, status, id)
	if err != nil {
		return fmt.Errorf("update task status: %w", err)
	}
	return nil
}

func (r *TaskRepo) SetCrawlStarted(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE crawl_tasks SET status = 'crawling', crawl_started_at = NOW() WHERE id = $1`, id)
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
		`UPDATE crawl_tasks SET status = 'ai_processing', ai_started_at = NOW() WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("set ai started: %w", err)
	}
	return nil
}

func (r *TaskRepo) SetAIFinished(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE crawl_tasks SET status = 'done', ai_finished_at = NOW() WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("set ai finished: %w", err)
	}
	return nil
}

func (r *TaskRepo) SetFailed(ctx context.Context, id string, errMsg string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE crawl_tasks SET status = 'failed', error_message = $1, retry_count = retry_count + 1 WHERE id = $2`,
		errMsg, id)
	if err != nil {
		return fmt.Errorf("set task failed: %w", err)
	}
	return nil
}
