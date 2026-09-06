package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"folio-server/internal/domain"
)

type RefreshSessionRepo struct {
	pool *pgxpool.Pool
}

func NewRefreshSessionRepo(pool *pgxpool.Pool) *RefreshSessionRepo {
	return &RefreshSessionRepo{pool: pool}
}

const refreshSessionColumns = `id, user_id, token_hash, expires_at, last_used_at,
	rotated_at, revoked_at, replaced_by_token_hash, created_at, updated_at`

func scanRefreshSession(row pgx.Row) (*domain.RefreshSession, error) {
	var session domain.RefreshSession
	err := row.Scan(
		&session.ID,
		&session.UserID,
		&session.TokenHash,
		&session.ExpiresAt,
		&session.LastUsedAt,
		&session.RotatedAt,
		&session.RevokedAt,
		&session.ReplacedByTokenHash,
		&session.CreatedAt,
		&session.UpdatedAt,
	)
	return &session, err
}

func (r *RefreshSessionRepo) Create(ctx context.Context, session *domain.RefreshSession) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO refresh_sessions (
			id, user_id, token_hash, expires_at, last_used_at,
			rotated_at, revoked_at, replaced_by_token_hash, created_at, updated_at
		) VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6, $7, $8, $9, $10)
	`,
		session.ID,
		session.UserID,
		session.TokenHash,
		session.ExpiresAt,
		session.LastUsedAt,
		session.RotatedAt,
		session.RevokedAt,
		session.ReplacedByTokenHash,
		session.CreatedAt,
		session.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("create refresh session: %w", err)
	}
	return nil
}

func (r *RefreshSessionRepo) GetByID(ctx context.Context, sessionID string) (*domain.RefreshSession, error) {
	session, err := scanRefreshSession(r.pool.QueryRow(ctx,
		`SELECT `+refreshSessionColumns+` FROM refresh_sessions WHERE id = $1::uuid`,
		sessionID,
	))
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get refresh session: %w", err)
	}
	return session, nil
}

func (r *RefreshSessionRepo) Rotate(ctx context.Context, sessionID, currentTokenHash, newTokenHash string, expiresAt, now time.Time) (*domain.RefreshSession, error) {
	session, err := scanRefreshSession(r.pool.QueryRow(ctx, `
		UPDATE refresh_sessions
		SET token_hash = $3,
		    expires_at = $4,
		    last_used_at = $5,
		    rotated_at = $5,
		    replaced_by_token_hash = $2
		WHERE id = $1::uuid
		  AND token_hash = $2
		  AND revoked_at IS NULL
		  AND expires_at > $5
		RETURNING `+refreshSessionColumns,
		sessionID,
		currentTokenHash,
		newTokenHash,
		expiresAt,
		now,
	))
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("rotate refresh session: %w", err)
	}
	return session, nil
}

func (r *RefreshSessionRepo) Revoke(ctx context.Context, sessionID, tokenHash string, now time.Time) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE refresh_sessions
		SET revoked_at = COALESCE(revoked_at, $3)
		WHERE id = $1::uuid
		  AND revoked_at IS NULL
		  AND (NULLIF($2, '') IS NULL OR token_hash = $2)
	`,
		sessionID,
		tokenHash,
		now,
	)
	if err != nil {
		return fmt.Errorf("revoke refresh session: %w", err)
	}
	return nil
}
