package domain

import "time"

type Subscription string

const (
	SubscriptionFree    Subscription = "free"
	SubscriptionPro     Subscription = "pro"
	SubscriptionProPlus Subscription = "pro_plus"
)

type User struct {
	ID                   string       `json:"id"`
	AppleID              *string      `json:"apple_id,omitempty"`
	Email                *string      `json:"email,omitempty"`
	Nickname             *string      `json:"nickname,omitempty"`
	AvatarURL            *string      `json:"avatar_url,omitempty"`
	Subscription         Subscription `json:"subscription"`
	SubscriptionExpiresAt *time.Time  `json:"subscription_expires_at,omitempty"`
	MonthlyQuota         int          `json:"monthly_quota"`
	CurrentMonthCount    int          `json:"current_month_count"`
	QuotaResetAt         *time.Time   `json:"quota_reset_at,omitempty"`
	PreferredLanguage    string       `json:"preferred_language"`
	CreatedAt            time.Time    `json:"created_at"`
	UpdatedAt            time.Time    `json:"updated_at"`
}
