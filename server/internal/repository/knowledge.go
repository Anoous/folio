package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"folio-server/internal/domain"
)

type KnowledgeRepo struct {
	pool *pgxpool.Pool
}

func NewKnowledgeRepo(pool *pgxpool.Pool) *KnowledgeRepo {
	return &KnowledgeRepo{pool: pool}
}

func (r *KnowledgeRepo) ListKnowledgeDocuments(ctx context.Context, userID string) ([]domain.KnowledgeDocument, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, title, summary, key_points, semantic_keywords, markdown_content, site_name, created_at
		FROM articles
		WHERE user_id = $1
		  AND status = 'ready'
		  AND deleted_at IS NULL
		ORDER BY created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, fmt.Errorf("list knowledge documents: %w", err)
	}
	defer rows.Close()

	docs := make([]domain.KnowledgeDocument, 0)
	for rows.Next() {
		var doc domain.KnowledgeDocument
		var keyPointsJSON []byte
		if err := rows.Scan(
			&doc.ArticleID,
			&doc.Title,
			&doc.Summary,
			&keyPointsJSON,
			&doc.SemanticKeywords,
			&doc.MarkdownContent,
			&doc.SiteName,
			&doc.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan knowledge document: %w", err)
		}
		if len(keyPointsJSON) > 0 {
			if err := json.Unmarshal(keyPointsJSON, &doc.KeyPoints); err != nil {
				return nil, fmt.Errorf("unmarshal key points: %w", err)
			}
		}
		if doc.KeyPoints == nil {
			doc.KeyPoints = []string{}
		}
		if doc.SemanticKeywords == nil {
			doc.SemanticKeywords = []string{}
		}
		docs = append(docs, doc)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate knowledge documents: %w", err)
	}
	return docs, nil
}

func (r *KnowledgeRepo) BroadRecallKnowledgeDocuments(ctx context.Context, userID string, keywords []string, limit int) ([]domain.KnowledgeDocument, error) {
	if len(keywords) == 0 {
		return []domain.KnowledgeDocument{}, nil
	}

	cleaned, escaped, fullTextQuery := prepareKnowledgeRecallTerms(keywords)
	if len(cleaned) == 0 {
		return []domain.KnowledgeDocument{}, nil
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin knowledge broad recall tx: %w", err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `SELECT set_config('pg_trgm.similarity_threshold', '0.1', true)`); err != nil {
		return nil, fmt.Errorf("set trigram threshold: %w", err)
	}

	rows, err := tx.Query(ctx, `
		WITH search_query AS (
			SELECT websearch_to_tsquery('simple', $4) AS q
		),
		keyword_matches AS (
			SELECT DISTINCT ON (a.id)
				a.id, a.title, a.summary, a.key_points, a.semantic_keywords, a.markdown_content, a.site_name, a.created_at,
				(
					CASE WHEN a.knowledge_search_vector @@ sq.q THEN ts_rank_cd(a.knowledge_search_vector, sq.q) * 10 ELSE 0 END
					+ CASE WHEN a.semantic_keywords && $2::text[] THEN 4 ELSE 0 END
					+ CASE WHEN EXISTS (SELECT 1 FROM unnest($2::text[]) kw WHERE a.title % kw) THEN 2 ELSE 0 END
					+ CASE WHEN EXISTS (SELECT 1 FROM unnest($3::text[]) esc WHERE a.summary ILIKE '%' || esc || '%') THEN 1 ELSE 0 END
					+ CASE WHEN EXISTS (SELECT 1 FROM unnest($3::text[]) esc WHERE a.key_points::text ILIKE '%' || esc || '%') THEN 0.8 ELSE 0 END
					+ CASE WHEN EXISTS (SELECT 1 FROM unnest($3::text[]) esc WHERE a.markdown_content ILIKE '%' || esc || '%') THEN 0.5 ELSE 0 END
				) AS score
			FROM articles a
			CROSS JOIN search_query sq
			WHERE a.user_id = $1
				AND a.status = 'ready'
				AND a.deleted_at IS NULL
				AND (
					a.knowledge_search_vector @@ sq.q
					OR a.semantic_keywords && $2::text[]
					OR EXISTS (SELECT 1 FROM unnest($2::text[]) kw WHERE a.title % kw)
					OR EXISTS (SELECT 1 FROM unnest($3::text[]) esc WHERE a.summary ILIKE '%' || esc || '%')
					OR EXISTS (SELECT 1 FROM unnest($3::text[]) esc WHERE a.key_points::text ILIKE '%' || esc || '%')
					OR EXISTS (SELECT 1 FROM unnest($3::text[]) esc WHERE a.markdown_content ILIKE '%' || esc || '%')
				)
			ORDER BY a.id, score DESC
		)
		SELECT id, title, summary, key_points, semantic_keywords, markdown_content, site_name, created_at
		FROM keyword_matches
		ORDER BY score DESC, created_at DESC
		LIMIT $5`,
		userID, cleaned, escaped, fullTextQuery, limit,
	)
	if err != nil {
		return nil, fmt.Errorf("broad recall knowledge documents: %w", err)
	}
	defer rows.Close()

	docs := make([]domain.KnowledgeDocument, 0)
	for rows.Next() {
		var doc domain.KnowledgeDocument
		var keyPointsJSON []byte
		if err := rows.Scan(
			&doc.ArticleID,
			&doc.Title,
			&doc.Summary,
			&keyPointsJSON,
			&doc.SemanticKeywords,
			&doc.MarkdownContent,
			&doc.SiteName,
			&doc.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan knowledge broad recall: %w", err)
		}
		if len(keyPointsJSON) > 0 {
			if err := json.Unmarshal(keyPointsJSON, &doc.KeyPoints); err != nil {
				return nil, fmt.Errorf("unmarshal knowledge key points: %w", err)
			}
		}
		if doc.KeyPoints == nil {
			doc.KeyPoints = []string{}
		}
		if doc.SemanticKeywords == nil {
			doc.SemanticKeywords = []string{}
		}
		docs = append(docs, doc)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate knowledge broad recall: %w", err)
	}
	return docs, nil
}
