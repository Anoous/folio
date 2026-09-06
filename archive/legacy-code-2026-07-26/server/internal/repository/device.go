package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"folio-server/internal/domain"
)

type DeviceRepo struct {
	db *pgxpool.Pool
}

func NewDeviceRepo(db *pgxpool.Pool) *DeviceRepo {
	return &DeviceRepo{db: db}
}

// Upsert inserts a new device or updates updated_at if (user_id, token)
// already exists.
func (r *DeviceRepo) Upsert(ctx context.Context, device *domain.Device) error {
	err := r.db.QueryRow(ctx, `
		INSERT INTO devices (user_id, token, platform)
		VALUES ($1::uuid, $2, $3)
		ON CONFLICT (user_id, token) DO UPDATE SET updated_at = NOW()
		RETURNING id, created_at, updated_at`,
		device.UserID, device.Token, device.Platform,
	).Scan(&device.ID, &device.CreatedAt, &device.UpdatedAt)
	if err != nil {
		return fmt.Errorf("upsert device: %w", err)
	}
	return nil
}

// GetByUserID returns all devices for a user.
func (r *DeviceRepo) GetByUserID(ctx context.Context, userID string) ([]domain.Device, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, user_id, token, platform, last_push_at, created_at, updated_at
		FROM devices
		WHERE user_id = $1::uuid
		ORDER BY updated_at DESC`,
		userID,
	)
	if err != nil {
		return nil, fmt.Errorf("query devices by user: %w", err)
	}
	defer rows.Close()

	devices := make([]domain.Device, 0)
	for rows.Next() {
		var d domain.Device
		if err := rows.Scan(
			&d.ID, &d.UserID, &d.Token, &d.Platform,
			&d.LastPushAt, &d.CreatedAt, &d.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan device: %w", err)
		}
		devices = append(devices, d)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate devices: %w", err)
	}
	return devices, nil
}

// GetPushableDevices returns one device per user that has due echo cards,
// has not been pushed today, and has not reviewed today. The returned
// question is the earliest due card's question for that user.
// Date comparisons use the user's timezone (defaults to Asia/Shanghai).
func (r *DeviceRepo) GetPushableDevices(ctx context.Context) ([]domain.PushTarget, error) {
	rows, err := r.db.Query(ctx, `
		SELECT DISTINCT ON (d.user_id) d.user_id, d.token, ec.question
		FROM devices d
		JOIN users u ON u.id = d.user_id
		JOIN echo_cards ec ON ec.user_id = d.user_id
		WHERE ec.next_review_at <= NOW()
		AND (d.last_push_at IS NULL
		     OR d.last_push_at < (NOW() AT TIME ZONE COALESCE(u.timezone, 'Asia/Shanghai'))::date)
		AND NOT EXISTS (
			SELECT 1 FROM echo_reviews er
			WHERE er.user_id = d.user_id
			AND DATE(er.reviewed_at AT TIME ZONE COALESCE(u.timezone, 'Asia/Shanghai'))
			    = (NOW() AT TIME ZONE COALESCE(u.timezone, 'Asia/Shanghai'))::date
		)
		ORDER BY d.user_id, ec.next_review_at ASC`)
	if err != nil {
		return nil, fmt.Errorf("query pushable devices: %w", err)
	}
	defer rows.Close()

	targets := make([]domain.PushTarget, 0)
	for rows.Next() {
		var t domain.PushTarget
		if err := rows.Scan(&t.UserID, &t.Token, &t.Question); err != nil {
			return nil, fmt.Errorf("scan push target: %w", err)
		}
		targets = append(targets, t)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate push targets: %w", err)
	}
	return targets, nil
}

// DeleteByToken removes a device registration by its APNs token. Used to
// clean up tokens that APNs has reported as invalid (HTTP 410 / bad token).
func (r *DeviceRepo) DeleteByToken(ctx context.Context, token string) error {
	_, err := r.db.Exec(ctx,
		`DELETE FROM devices WHERE token = $1`,
		token,
	)
	if err != nil {
		return fmt.Errorf("delete device by token: %w", err)
	}
	return nil
}

// UpdateLastPushAt sets last_push_at = NOW() for all devices of a user.
func (r *DeviceRepo) UpdateLastPushAt(ctx context.Context, userID string) error {
	_, err := r.db.Exec(ctx,
		`UPDATE devices SET last_push_at = NOW() WHERE user_id = $1::uuid`,
		userID,
	)
	if err != nil {
		return fmt.Errorf("update last push at: %w", err)
	}
	return nil
}
