package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"folio-server/internal/domain"
)

type UserRepo struct {
	pool *pgxpool.Pool
}

func NewUserRepo(pool *pgxpool.Pool) *UserRepo {
	return &UserRepo{pool: pool}
}

func (r *UserRepo) GetByID(ctx context.Context, id string) (*domain.User, error) {
	var u domain.User
	err := r.pool.QueryRow(ctx, `
		SELECT id, apple_id, email, nickname, avatar_url,
		       subscription, subscription_expires_at, monthly_quota,
		       current_month_count, quota_reset_at, preferred_language,
		       created_at, updated_at
		FROM users WHERE id = $1`, id,
	).Scan(
		&u.ID, &u.AppleID, &u.Email, &u.Nickname, &u.AvatarURL,
		&u.Subscription, &u.SubscriptionExpiresAt, &u.MonthlyQuota,
		&u.CurrentMonthCount, &u.QuotaResetAt, &u.PreferredLanguage,
		&u.CreatedAt, &u.UpdatedAt,
	)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get user: %w", err)
	}
	return &u, nil
}

func (r *UserRepo) GetByAppleID(ctx context.Context, appleID string) (*domain.User, error) {
	var u domain.User
	err := r.pool.QueryRow(ctx, `
		SELECT id, apple_id, email, nickname, avatar_url,
		       subscription, subscription_expires_at, monthly_quota,
		       current_month_count, quota_reset_at, preferred_language,
		       created_at, updated_at
		FROM users WHERE apple_id = $1`, appleID,
	).Scan(
		&u.ID, &u.AppleID, &u.Email, &u.Nickname, &u.AvatarURL,
		&u.Subscription, &u.SubscriptionExpiresAt, &u.MonthlyQuota,
		&u.CurrentMonthCount, &u.QuotaResetAt, &u.PreferredLanguage,
		&u.CreatedAt, &u.UpdatedAt,
	)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get user by apple_id: %w", err)
	}
	return &u, nil
}

type CreateUserParams struct {
	AppleID  string
	Email    *string
	Nickname *string
}

func (r *UserRepo) Create(ctx context.Context, p CreateUserParams) (*domain.User, error) {
	var u domain.User
	err := r.pool.QueryRow(ctx, `
		INSERT INTO users (apple_id, email, nickname)
		VALUES ($1, $2, $3)
		RETURNING id, apple_id, email, nickname, avatar_url,
		          subscription, subscription_expires_at, monthly_quota,
		          current_month_count, quota_reset_at, preferred_language,
		          created_at, updated_at`,
		p.AppleID, p.Email, p.Nickname,
	).Scan(
		&u.ID, &u.AppleID, &u.Email, &u.Nickname, &u.AvatarURL,
		&u.Subscription, &u.SubscriptionExpiresAt, &u.MonthlyQuota,
		&u.CurrentMonthCount, &u.QuotaResetAt, &u.PreferredLanguage,
		&u.CreatedAt, &u.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("create user: %w", err)
	}
	return &u, nil
}

func (r *UserRepo) IncrementMonthCount(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE users SET current_month_count = current_month_count + 1 WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("increment month count: %w", err)
	}
	return nil
}

func (r *UserRepo) ResetMonthCount(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE users SET current_month_count = 0, quota_reset_at = NOW() WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("reset month count: %w", err)
	}
	return nil
}
