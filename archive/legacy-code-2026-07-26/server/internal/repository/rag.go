package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"folio-server/internal/domain"
)

type RAGRepo struct {
	db *pgxpool.Pool
}

func NewRAGRepo(db *pgxpool.Pool) *RAGRepo {
	return &RAGRepo{db: db}
}

// LoadArticleSummaries returns all ready articles for a user with their summaries.
func (r *RAGRepo) LoadArticleSummaries(ctx context.Context, userID string) ([]domain.RAGSource, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, title, summary, site_name, created_at
		FROM articles
		WHERE user_id = $1 AND status = 'ready'
		ORDER BY created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, fmt.Errorf("load article summaries: %w", err)
	}
	defer rows.Close()

	sources := make([]domain.RAGSource, 0)
	for rows.Next() {
		var s domain.RAGSource
		if err := rows.Scan(&s.ArticleID, &s.Title, &s.Summary, &s.SiteName, &s.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan article summary: %w", err)
		}
		sources = append(sources, s)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate article summaries: %w", err)
	}
	return sources, nil
}

// SearchArticleSummaries uses pg_trgm similarity search on title + summary.
func (r *RAGRepo) SearchArticleSummaries(ctx context.Context, userID, query string, limit int) ([]domain.RAGSource, error) {
	rows, err := r.db.Query(ctx, `
		SELECT
			id, title, summary, site_name, created_at,
			GREATEST(
				similarity(title, $2),
				COALESCE(similarity(summary, $2), 0)
			) AS relevance
		FROM articles
		WHERE user_id = $1
		  AND status = 'ready'
		  AND (
			similarity(title, $2) > 0.1
			OR similarity(summary, $2) > 0.1
		  )
		ORDER BY relevance DESC
		LIMIT $3`,
		userID, query, limit,
	)
	if err != nil {
		return nil, fmt.Errorf("search article summaries: %w", err)
	}
	defer rows.Close()

	sources := make([]domain.RAGSource, 0)
	for rows.Next() {
		var s domain.RAGSource
		if err := rows.Scan(&s.ArticleID, &s.Title, &s.Summary, &s.SiteName, &s.CreatedAt, &s.Relevance); err != nil {
			return nil, fmt.Errorf("scan search result: %w", err)
		}
		sources = append(sources, s)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate search results: %w", err)
	}
	return sources, nil
}

// BroadRecallSummaries does multi-path keyword recall for RAG and related articles.
func (r *RAGRepo) BroadRecallSummaries(ctx context.Context, userID string, keywords []string, limit int, excludeID string) ([]domain.RAGSource, error) {
	cleaned := make([]string, len(keywords))
	escaped := make([]string, len(keywords))
	for i, kw := range keywords {
		lc := strings.ToLower(strings.TrimSpace(kw))
		cleaned[i] = lc
		escaped[i] = escapeILIKE(lc)
	}

	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin broad recall tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Set low trigram threshold for broad recall (transaction-scoped)
	if _, err := tx.Exec(ctx, `SELECT set_config('pg_trgm.similarity_threshold', '0.1', true)`); err != nil {
		return nil, fmt.Errorf("set trigram threshold: %w", err)
	}

	var excludeUUID interface{}
	if excludeID != "" {
		excludeUUID = excludeID
	}

	rows, err := tx.Query(ctx, `
		WITH keyword_matches AS (
			SELECT DISTINCT ON (a.id)
				a.id, a.title, a.summary, a.key_points, a.site_name, a.created_at,
				CASE
					WHEN a.semantic_keywords && $2::text[] THEN 1.0
					WHEN EXISTS (SELECT 1 FROM unnest($2::text[]) kw WHERE a.title % kw) THEN 0.6
					ELSE 0.1
				END AS score
			FROM articles a
			WHERE a.user_id = $1
				AND a.status = 'ready'
				AND a.deleted_at IS NULL
				AND ($5::uuid IS NULL OR a.id != $5)
				AND (
					a.semantic_keywords && $2::text[]
					OR EXISTS (SELECT 1 FROM unnest($2::text[]) kw WHERE a.title % kw)
					OR EXISTS (SELECT 1 FROM unnest($3::text[]) esc WHERE a.summary ILIKE '%' || esc || '%')
					OR EXISTS (SELECT 1 FROM unnest($3::text[]) esc WHERE a.key_points::text ILIKE '%' || esc || '%')
				)
			ORDER BY a.id, score DESC
		)
		SELECT id, title, summary, key_points, site_name, created_at
		FROM keyword_matches
		ORDER BY score DESC
		LIMIT $4`,
		userID, cleaned, escaped, limit, excludeUUID,
	)
	if err != nil {
		return nil, fmt.Errorf("broad recall summaries: %w", err)
	}
	defer rows.Close()

	sources := make([]domain.RAGSource, 0)
	for rows.Next() {
		var s domain.RAGSource
		var kpJSON []byte
		if err := rows.Scan(&s.ArticleID, &s.Title, &s.Summary, &kpJSON, &s.SiteName, &s.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan broad recall: %w", err)
		}
		if len(kpJSON) > 0 {
			json.Unmarshal(kpJSON, &s.KeyPoints)
		}
		sources = append(sources, s)
	}
	return sources, rows.Err()
}

// CreateConversation inserts a new RAG conversation, returning id, created_at, updated_at.
func (r *RAGRepo) CreateConversation(ctx context.Context, conv *domain.RAGConversation) error {
	err := r.db.QueryRow(ctx, `
		INSERT INTO rag_conversations (id, user_id, title)
		VALUES (
			COALESCE(NULLIF($1, '')::uuid, uuid_generate_v4()),
			$2::uuid, $3
		)
		RETURNING id, created_at, updated_at`,
		conv.ID, conv.UserID, conv.Title,
	).Scan(&conv.ID, &conv.CreatedAt, &conv.UpdatedAt)
	if err != nil {
		return fmt.Errorf("create rag conversation: %w", err)
	}
	return nil
}

// AddMessage inserts a RAG message into rag_messages.
// source_article_ids is stored as JSONB.
func (r *RAGRepo) AddMessage(ctx context.Context, msg *domain.RAGMessage) error {
	idsJSON, err := json.Marshal(msg.SourceArticleIDs)
	if err != nil {
		return fmt.Errorf("marshal source_article_ids: %w", err)
	}

	err = r.db.QueryRow(ctx, `
		INSERT INTO rag_messages (id, conversation_id, role, content, source_article_ids, source_count)
		VALUES (
			COALESCE(NULLIF($1, '')::uuid, uuid_generate_v4()),
			$2::uuid, $3, $4, $5::jsonb, $6
		)
		RETURNING id, created_at`,
		msg.ID, msg.ConversationID, msg.Role, msg.Content, string(idsJSON), msg.SourceCount,
	).Scan(&msg.ID, &msg.CreatedAt)
	if err != nil {
		return fmt.Errorf("add rag message: %w", err)
	}
	return nil
}

// GetConversationMessages returns messages for a conversation ordered by created_at ASC.
func (r *RAGRepo) GetConversationMessages(ctx context.Context, conversationID string, limit int) ([]domain.RAGMessage, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, conversation_id, role, content, source_article_ids, source_count, created_at
		FROM rag_messages
		WHERE conversation_id = $1
		ORDER BY created_at ASC
		LIMIT $2`,
		conversationID, limit,
	)
	if err != nil {
		return nil, fmt.Errorf("query conversation messages: %w", err)
	}
	defer rows.Close()

	msgs := make([]domain.RAGMessage, 0)
	for rows.Next() {
		var m domain.RAGMessage
		var idsJSON []byte
		if err := rows.Scan(
			&m.ID, &m.ConversationID, &m.Role, &m.Content,
			&idsJSON, &m.SourceCount, &m.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan rag message: %w", err)
		}
		if len(idsJSON) > 0 {
			if err := json.Unmarshal(idsJSON, &m.SourceArticleIDs); err != nil {
				return nil, fmt.Errorf("unmarshal source_article_ids: %w", err)
			}
		}
		if m.SourceArticleIDs == nil {
			m.SourceArticleIDs = []string{}
		}
		msgs = append(msgs, m)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate conversation messages: %w", err)
	}
	return msgs, nil
}

// ReserveRAGQuota atomically reserves one free-tier RAG answer for the current
// month. It returns false when the monthly limit has already been reached.
func (r *RAGRepo) ReserveRAGQuota(ctx context.Context, userID string, limit int) (bool, error) {
	var newCount int
	err := r.db.QueryRow(ctx, `
		UPDATE users SET
			rag_count_this_month = CASE
				WHEN rag_month_reset_at IS NULL
				     OR date_trunc('month', rag_month_reset_at) < date_trunc('month', NOW())
				THEN 1
				ELSE rag_count_this_month + 1
			END,
			rag_month_reset_at = CASE
				WHEN rag_month_reset_at IS NULL
				     OR date_trunc('month', rag_month_reset_at) < date_trunc('month', NOW())
				THEN NOW()
				ELSE rag_month_reset_at
			END
		WHERE id = $1
		  AND (
			rag_month_reset_at IS NULL
			OR date_trunc('month', rag_month_reset_at) < date_trunc('month', NOW())
			OR rag_count_this_month < $2
		  )
		RETURNING rag_count_this_month`,
		userID, limit,
	).Scan(&newCount)
	if err == pgx.ErrNoRows {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("reserve rag quota: %w", err)
	}
	return true, nil
}

// ReleaseReservedRAGQuota rolls back a quota reservation when answer generation
// does not complete.
func (r *RAGRepo) ReleaseReservedRAGQuota(ctx context.Context, userID string) error {
	_, err := r.db.Exec(ctx,
		`UPDATE users SET rag_count_this_month = GREATEST(rag_count_this_month - 1, 0) WHERE id = $1`,
		userID,
	)
	if err != nil {
		return fmt.Errorf("release rag quota reservation: %w", err)
	}
	return nil
}
