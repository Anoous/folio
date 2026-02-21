package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"folio-server/internal/domain"
)

type TagRepo struct {
	pool *pgxpool.Pool
}

func NewTagRepo(pool *pgxpool.Pool) *TagRepo {
	return &TagRepo{pool: pool}
}

func (r *TagRepo) ListByUser(ctx context.Context, userID string) ([]domain.Tag, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, name, user_id, is_ai_generated, article_count, created_at
		 FROM tags WHERE user_id = $1 ORDER BY article_count DESC`, userID)
	if err != nil {
		return nil, fmt.Errorf("list tags: %w", err)
	}
	defer rows.Close()

	tags := make([]domain.Tag, 0)
	for rows.Next() {
		var t domain.Tag
		if err := rows.Scan(&t.ID, &t.Name, &t.UserID, &t.IsAIGenerated, &t.ArticleCount, &t.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan tag: %w", err)
		}
		tags = append(tags, t)
	}
	return tags, nil
}

func (r *TagRepo) Create(ctx context.Context, userID, name string, isAIGenerated bool) (*domain.Tag, error) {
	var t domain.Tag
	err := r.pool.QueryRow(ctx, `
		INSERT INTO tags (user_id, name, is_ai_generated)
		VALUES ($1, $2, $3)
		ON CONFLICT (user_id, name) DO UPDATE SET name = EXCLUDED.name
		RETURNING id, name, user_id, is_ai_generated, article_count, created_at`,
		userID, name, isAIGenerated,
	).Scan(&t.ID, &t.Name, &t.UserID, &t.IsAIGenerated, &t.ArticleCount, &t.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("create tag: %w", err)
	}
	return &t, nil
}

func (r *TagRepo) Delete(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM tags WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("delete tag: %w", err)
	}
	return nil
}

func (r *TagRepo) AttachToArticle(ctx context.Context, articleID, tagID string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO article_tags (article_id, tag_id) VALUES ($1, $2)
		ON CONFLICT DO NOTHING`, articleID, tagID)
	if err != nil {
		return fmt.Errorf("attach tag: %w", err)
	}
	// Increment counter
	r.pool.Exec(ctx, `UPDATE tags SET article_count = article_count + 1 WHERE id = $1`, tagID)
	return nil
}

func (r *TagRepo) DetachFromArticle(ctx context.Context, articleID, tagID string) error {
	ct, err := r.pool.Exec(ctx,
		`DELETE FROM article_tags WHERE article_id = $1 AND tag_id = $2`, articleID, tagID)
	if err != nil {
		return fmt.Errorf("detach tag: %w", err)
	}
	if ct.RowsAffected() > 0 {
		r.pool.Exec(ctx, `UPDATE tags SET article_count = GREATEST(article_count - 1, 0) WHERE id = $1`, tagID)
	}
	return nil
}

func (r *TagRepo) GetByArticle(ctx context.Context, articleID string) ([]domain.Tag, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT t.id, t.name, t.user_id, t.is_ai_generated, t.article_count, t.created_at
		FROM tags t
		JOIN article_tags at ON t.id = at.tag_id
		WHERE at.article_id = $1
		ORDER BY t.name`, articleID)
	if err != nil {
		return nil, fmt.Errorf("get tags by article: %w", err)
	}
	defer rows.Close()

	tags := make([]domain.Tag, 0)
	for rows.Next() {
		var t domain.Tag
		if err := rows.Scan(&t.ID, &t.Name, &t.UserID, &t.IsAIGenerated, &t.ArticleCount, &t.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan tag: %w", err)
		}
		tags = append(tags, t)
	}
	return tags, nil
}

func (r *TagRepo) GetByID(ctx context.Context, id string) (*domain.Tag, error) {
	var t domain.Tag
	err := r.pool.QueryRow(ctx,
		`SELECT id, name, user_id, is_ai_generated, article_count, created_at
		 FROM tags WHERE id = $1`, id,
	).Scan(&t.ID, &t.Name, &t.UserID, &t.IsAIGenerated, &t.ArticleCount, &t.CreatedAt)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get tag: %w", err)
	}
	return &t, nil
}
