package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

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

// GetUserRAGQuota returns rag_count_this_month and rag_month_reset_at for a user.
func (r *RAGRepo) GetUserRAGQuota(ctx context.Context, userID string) (count int, resetAt *time.Time, err error) {
	err = r.db.QueryRow(ctx,
		`SELECT rag_count_this_month, rag_month_reset_at FROM users WHERE id = $1`,
		userID,
	).Scan(&count, &resetAt)
	if err == pgx.ErrNoRows {
		return 0, nil, nil
	}
	if err != nil {
		return 0, nil, fmt.Errorf("get user rag quota: %w", err)
	}
	return count, resetAt, nil
}

// ResetRAGMonthCount resets rag_count_this_month to 0 and sets rag_month_reset_at.
func (r *RAGRepo) ResetRAGMonthCount(ctx context.Context, userID string, resetAt time.Time) error {
	_, err := r.db.Exec(ctx,
		`UPDATE users SET rag_count_this_month = 0, rag_month_reset_at = $1 WHERE id = $2`,
		resetAt, userID,
	)
	if err != nil {
		return fmt.Errorf("reset rag month count: %w", err)
	}
	return nil
}

// IncrementRAGMonthCount increments rag_count_this_month by 1.
func (r *RAGRepo) IncrementRAGMonthCount(ctx context.Context, userID string) error {
	_, err := r.db.Exec(ctx,
		`UPDATE users SET rag_count_this_month = rag_count_this_month + 1 WHERE id = $1`,
		userID,
	)
	if err != nil {
		return fmt.Errorf("increment rag month count: %w", err)
	}
	return nil
}
