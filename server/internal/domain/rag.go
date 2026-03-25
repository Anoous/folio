package domain

import "time"

type RAGSource struct {
	ArticleID string
	Title     string
	SiteName  *string
	Summary   *string
	KeyPoints []string
	CreatedAt time.Time
	Relevance float64
}

type RAGResponse struct {
	Answer              string
	Sources             []RAGSource
	SourceCount         int
	FollowupSuggestions []string
	ConversationID      string
}

type RAGMessage struct {
	ID               string
	ConversationID   string
	Role             string // "user" | "assistant"
	Content          string
	SourceArticleIDs []string
	SourceCount      int
	CreatedAt        time.Time
}

type RAGConversation struct {
	ID        string
	UserID    string
	Title     *string
	CreatedAt time.Time
	UpdatedAt time.Time
}
