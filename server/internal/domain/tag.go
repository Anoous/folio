package domain

import "time"

type Tag struct {
	ID            string    `json:"id"`
	Name          string    `json:"name"`
	UserID        *string   `json:"user_id,omitempty"`
	IsAIGenerated bool      `json:"is_ai_generated"`
	ArticleCount  int       `json:"article_count"`
	CreatedAt     time.Time `json:"created_at"`
}
