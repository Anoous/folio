package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type ArticleRelation struct {
	SourceArticleID  string
	RelatedArticleID string
	RelevanceReason  string
	Score            int
	CreatedAt        time.Time
}

type RelatedArticleRow struct {
	ID              string  `json:"id"`
	Title           string  `json:"title"`
	Summary         *string `json:"summary,omitempty"`
	SiteName        *string `json:"site_name,omitempty"`
	CoverImageURL   *string `json:"cover_image_url,omitempty"`
	RelevanceReason string  `json:"relevance_reason"`
}

type RelationRepo struct {
	pool *pgxpool.Pool
}

func NewRelationRepo(pool *pgxpool.Pool) *RelationRepo {
	return &RelationRepo{pool: pool}
}

// SaveBatch replaces all relations for a source article (idempotent).
func (r *RelationRepo) SaveBatch(ctx context.Context, sourceID string, relations []ArticleRelation) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `DELETE FROM article_relations WHERE source_article_id = $1`, sourceID)
	if err != nil {
		return fmt.Errorf("delete old relations: %w", err)
	}

	for _, rel := range relations {
		_, err = tx.Exec(ctx, `
			INSERT INTO article_relations (source_article_id, related_article_id, relevance_reason, score)
			VALUES ($1, $2, $3, $4)`,
			rel.SourceArticleID, rel.RelatedArticleID, rel.RelevanceReason, rel.Score)
		if err != nil {
			return fmt.Errorf("insert relation: %w", err)
		}
	}

	return tx.Commit(ctx)
}

// ListBySource returns related articles for a source article, ordered by score DESC.
func (r *RelationRepo) ListBySource(ctx context.Context, sourceID string) ([]RelatedArticleRow, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT a.id, a.title, a.summary, a.site_name, a.cover_image_url, ar.relevance_reason
		FROM article_relations ar
		JOIN articles a ON a.id = ar.related_article_id
		WHERE ar.source_article_id = $1
			AND a.deleted_at IS NULL
		ORDER BY ar.score DESC`,
		sourceID)
	if err != nil {
		return nil, fmt.Errorf("list relations: %w", err)
	}
	defer rows.Close()

	result := make([]RelatedArticleRow, 0)
	for rows.Next() {
		var r RelatedArticleRow
		if err := rows.Scan(&r.ID, &r.Title, &r.Summary, &r.SiteName, &r.CoverImageURL, &r.RelevanceReason); err != nil {
			return nil, fmt.Errorf("scan relation: %w", err)
		}
		result = append(result, r)
	}
	return result, rows.Err()
}
