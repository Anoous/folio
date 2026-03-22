package repository

import (
	"context"
	"fmt"
	"time"

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

// userColumns is the canonical SELECT column list for users.
const userColumns = `id, apple_id, email, nickname, avatar_url,
	subscription, subscription_expires_at, original_transaction_id,
	monthly_quota, current_month_count, quota_reset_at, preferred_language,
	created_at, updated_at, sync_epoch`

// scanUser scans a row into a domain.User using the canonical column order.
func scanUser(row pgx.Row) (*domain.User, error) {
	var u domain.User
	err := row.Scan(
		&u.ID, &u.AppleID, &u.Email, &u.Nickname, &u.AvatarURL,
		&u.Subscription, &u.SubscriptionExpiresAt, &u.OriginalTransactionID,
		&u.MonthlyQuota, &u.CurrentMonthCount, &u.QuotaResetAt, &u.PreferredLanguage,
		&u.CreatedAt, &u.UpdatedAt, &u.SyncEpoch,
	)
	return &u, err
}

func (r *UserRepo) GetByID(ctx context.Context, id string) (*domain.User, error) {
	u, err := scanUser(r.pool.QueryRow(ctx,
		`SELECT `+userColumns+` FROM users WHERE id = $1`, id))
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get user: %w", err)
	}
	return u, nil
}

func (r *UserRepo) GetByAppleID(ctx context.Context, appleID string) (*domain.User, error) {
	u, err := scanUser(r.pool.QueryRow(ctx,
		`SELECT `+userColumns+` FROM users WHERE apple_id = $1`, appleID))
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get user by apple_id: %w", err)
	}
	return u, nil
}

func (r *UserRepo) GetByEmail(ctx context.Context, email string) (*domain.User, error) {
	u, err := scanUser(r.pool.QueryRow(ctx,
		`SELECT `+userColumns+` FROM users WHERE email = $1`, email))
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get user by email: %w", err)
	}
	return u, nil
}

type CreateUserParams struct {
	AppleID  *string
	Email    *string
	Nickname *string
}

func (r *UserRepo) Create(ctx context.Context, p CreateUserParams) (*domain.User, error) {
	u, err := scanUser(r.pool.QueryRow(ctx, `
		INSERT INTO users (apple_id, email, nickname)
		VALUES ($1, $2, $3)
		RETURNING `+userColumns,
		p.AppleID, p.Email, p.Nickname,
	))
	if err != nil {
		return nil, fmt.Errorf("create user: %w", err)
	}
	return u, nil
}

func (r *UserRepo) DecrementMonthCount(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE users SET current_month_count = GREATEST(current_month_count - 1, 0) WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("decrement month count: %w", err)
	}
	return nil
}

// AtomicResetAndIncrement resets the month count if needed and increments it
// atomically. Returns the new count, or -1 if quota exceeded.
func (r *UserRepo) AtomicResetAndIncrement(ctx context.Context, id string) (int, error) {
	var newCount int
	err := r.pool.QueryRow(ctx, `
		UPDATE users SET
			current_month_count = CASE
				WHEN quota_reset_at IS NULL
				     OR date_trunc('month', quota_reset_at) < date_trunc('month', NOW())
				THEN 1
				ELSE current_month_count + 1
			END,
			quota_reset_at = CASE
				WHEN quota_reset_at IS NULL
				     OR date_trunc('month', quota_reset_at) < date_trunc('month', NOW())
				THEN NOW()
				ELSE quota_reset_at
			END
		WHERE id = $1
		  AND (
			-- New month: always allow (reset to 1)
			quota_reset_at IS NULL
			OR date_trunc('month', quota_reset_at) < date_trunc('month', NOW())
			-- Same month: check quota
			OR current_month_count < monthly_quota
		  )
		RETURNING current_month_count`, id).Scan(&newCount)
	if err == pgx.ErrNoRows {
		return -1, nil // quota exceeded (WHERE clause didn't match)
	}
	if err != nil {
		return 0, fmt.Errorf("atomic reset and increment: %w", err)
	}
	return newCount, nil
}

// UpdateSubscription sets the user's subscription tier, expiry, and stores the
// Apple original_transaction_id for webhook lookup. Pro users get 9999 quota.
func (r *UserRepo) UpdateSubscription(ctx context.Context, userID string, subscription domain.Subscription, expiresAt *time.Time, originalTxnID *string) error {
	quota := 30 // free tier default
	if subscription == domain.SubscriptionPro {
		quota = 9999
	}
	_, err := r.pool.Exec(ctx, `
		UPDATE users
		SET subscription = $2,
		    subscription_expires_at = $3,
		    original_transaction_id = COALESCE($4, original_transaction_id),
		    monthly_quota = $5
		WHERE id = $1`,
		userID, string(subscription), expiresAt, originalTxnID, quota,
	)
	if err != nil {
		return fmt.Errorf("update subscription: %w", err)
	}
	return nil
}

// GetByOriginalTransactionID finds a user by their Apple original transaction ID.
func (r *UserRepo) GetByOriginalTransactionID(ctx context.Context, txnID string) (*domain.User, error) {
	u, err := scanUser(r.pool.QueryRow(ctx,
		`SELECT `+userColumns+` FROM users WHERE original_transaction_id = $1`, txnID))
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get user by original_transaction_id: %w", err)
	}
	return u, nil
}
