package domain

import "time"

type Subscription string

const (
	SubscriptionFree Subscription = "free"
	SubscriptionPro  Subscription = "pro"
)

type User struct {
	ID                   string       `json:"id"`
	AppleID              *string      `json:"apple_id,omitempty"`
	Email                *string      `json:"email,omitempty"`
	Nickname             *string      `json:"nickname,omitempty"`
	AvatarURL            *string      `json:"avatar_url,omitempty"`
	Subscription         Subscription `json:"subscription"`
	SubscriptionExpiresAt *time.Time  `json:"subscription_expires_at,omitempty"`
	OriginalTransactionID *string     `json:"original_transaction_id,omitempty"`
	MonthlyQuota         int          `json:"monthly_quota"`
	CurrentMonthCount    int          `json:"current_month_count"`
	QuotaResetAt         *time.Time   `json:"quota_reset_at,omitempty"`
	PreferredLanguage    string       `json:"preferred_language"`
	CreatedAt            time.Time    `json:"created_at"`
	UpdatedAt            time.Time    `json:"updated_at"`
	SyncEpoch            int          `json:"sync_epoch"`
	// Echo quota fields (migration 008)
	EchoCountThisWeek int        `json:"echo_count_this_week"`
	EchoWeekResetAt   *time.Time `json:"echo_week_reset_at,omitempty"`
}
