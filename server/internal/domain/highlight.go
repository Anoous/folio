package domain

import "time"

type Highlight struct {
	ID          string
	ArticleID   string
	UserID      string
	Text        string
	StartOffset int
	EndOffset   int
	Color       string
	Note        *string
	CreatedAt   time.Time
}
