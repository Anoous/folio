package domain

import "time"

type Device struct {
	ID         string
	UserID     string
	Token      string
	Platform   string
	LastPushAt *time.Time
	CreatedAt  time.Time
	UpdatedAt  time.Time
}

// PushTarget represents a device eligible for a push notification,
// joined with the earliest due echo card question.
type PushTarget struct {
	UserID   string
	Token    string
	Question string
}
