package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"folio-server/internal/domain"
)

type HighlightRepo struct {
	db *pgxpool.Pool
}

func NewHighlightRepo(db *pgxpool.Pool) *HighlightRepo {
	return &HighlightRepo{db: db}
}

// CreateHighlight inserts a new highlight, returning id and created_at.
func (r *HighlightRepo) CreateHighlight(ctx context.Context, h *domain.Highlight) error {
	err := r.db.QueryRow(ctx, `
		INSERT INTO highlights (
			id, article_id, user_id, text, start_offset, end_offset, color, note
		) VALUES (
			COALESCE(NULLIF($1, '')::uuid, uuid_generate_v4()),
			$2::uuid, $3::uuid, $4, $5, $6, $7, $8
		)
		RETURNING id, created_at`,
		h.ID, h.ArticleID, h.UserID, h.Text, h.StartOffset, h.EndOffset, h.Color, h.Note,
	).Scan(&h.ID, &h.CreatedAt)
	if err != nil {
		return fmt.Errorf("create highlight: %w", err)
	}
	return nil
}

// GetByArticle returns all highlights for a given article owned by userID,
// ordered by start_offset ascending.
func (r *HighlightRepo) GetByArticle(ctx context.Context, articleID, userID string) ([]domain.Highlight, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, article_id, user_id, text, start_offset, end_offset, color, note, created_at
		FROM highlights
		WHERE article_id = $1::uuid AND user_id = $2::uuid
		ORDER BY start_offset ASC`,
		articleID, userID,
	)
	if err != nil {
		return nil, fmt.Errorf("query highlights by article: %w", err)
	}
	defer rows.Close()

	highlights := make([]domain.Highlight, 0)
	for rows.Next() {
		var h domain.Highlight
		if err := rows.Scan(
			&h.ID, &h.ArticleID, &h.UserID, &h.Text,
			&h.StartOffset, &h.EndOffset, &h.Color, &h.Note, &h.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan highlight: %w", err)
		}
		highlights = append(highlights, h)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate highlights: %w", err)
	}
	return highlights, nil
}

// GetByID returns a single highlight, verifying user ownership.
// Returns nil, nil if not found.
func (r *HighlightRepo) GetByID(ctx context.Context, id, userID string) (*domain.Highlight, error) {
	var h domain.Highlight
	err := r.db.QueryRow(ctx, `
		SELECT id, article_id, user_id, text, start_offset, end_offset, color, note, created_at
		FROM highlights
		WHERE id = $1::uuid AND user_id = $2::uuid`,
		id, userID,
	).Scan(
		&h.ID, &h.ArticleID, &h.UserID, &h.Text,
		&h.StartOffset, &h.EndOffset, &h.Color, &h.Note, &h.CreatedAt,
	)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get highlight by id: %w", err)
	}
	return &h, nil
}

// DeleteHighlight deletes a highlight by id with ownership check.
// Returns the article_id for use in count updates.
func (r *HighlightRepo) DeleteHighlight(ctx context.Context, id, userID string) (articleID string, err error) {
	err = r.db.QueryRow(ctx, `
		DELETE FROM highlights
		WHERE id = $1::uuid AND user_id = $2::uuid
		RETURNING article_id`,
		id, userID,
	).Scan(&articleID)
	if err == pgx.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("delete highlight: %w", err)
	}
	return articleID, nil
}

// IncrementArticleHighlightCount increments highlight_count by 1.
func (r *HighlightRepo) IncrementArticleHighlightCount(ctx context.Context, articleID string) error {
	_, err := r.db.Exec(ctx,
		`UPDATE articles SET highlight_count = highlight_count + 1 WHERE id = $1::uuid`,
		articleID,
	)
	if err != nil {
		return fmt.Errorf("increment article highlight count: %w", err)
	}
	return nil
}

// DecrementArticleHighlightCount decrements highlight_count by 1, floored at 0.
func (r *HighlightRepo) DecrementArticleHighlightCount(ctx context.Context, articleID string) error {
	_, err := r.db.Exec(ctx,
		`UPDATE articles SET highlight_count = GREATEST(0, highlight_count - 1) WHERE id = $1::uuid`,
		articleID,
	)
	if err != nil {
		return fmt.Errorf("decrement article highlight count: %w", err)
	}
	return nil
}
