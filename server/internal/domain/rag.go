package domain

import "time"

type RAGSource struct {
	ArticleID       string
	Title           string
	SiteName        *string
	Summary         *string
	EvidenceSnippet *string
	KeyPoints       []string
	CreatedAt       time.Time
	Relevance       float64
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

// RAGStreamEvent is an event emitted by the streaming RAG pipeline.
type RAGStreamEvent struct {
	Type string // "sources" | "delta" | "done" | "error"

	// sources event fields
	Sources        []RAGSource
	SourceCount    int
	ConversationID string

	// delta event field
	Text string

	// done event fields
	CitedIndices        []int
	FollowupSuggestions []string

	// error event fields
	ErrorCode    string
	ErrorMessage string
}
