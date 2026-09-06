package domain

import "time"

type RefreshSession struct {
	ID                  string     `json:"id"`
	UserID              string     `json:"user_id"`
	TokenHash           string     `json:"-"`
	ExpiresAt           time.Time  `json:"expires_at"`
	LastUsedAt          *time.Time `json:"last_used_at,omitempty"`
	RotatedAt           *time.Time `json:"rotated_at,omitempty"`
	RevokedAt           *time.Time `json:"revoked_at,omitempty"`
	ReplacedByTokenHash *string    `json:"-"`
	CreatedAt           time.Time  `json:"created_at"`
	UpdatedAt           time.Time  `json:"updated_at"`
}
