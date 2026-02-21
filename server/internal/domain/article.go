package domain

import "time"

type ArticleStatus string

const (
	ArticleStatusPending    ArticleStatus = "pending"
	ArticleStatusProcessing ArticleStatus = "processing"
	ArticleStatusReady      ArticleStatus = "ready"
	ArticleStatusFailed     ArticleStatus = "failed"
)

type SourceType string

const (
	SourceWeb        SourceType = "web"
	SourceWechat     SourceType = "wechat"
	SourceTwitter    SourceType = "twitter"
	SourceWeibo      SourceType = "weibo"
	SourceZhihu      SourceType = "zhihu"
	SourceNewsletter SourceType = "newsletter"
	SourceYoutube    SourceType = "youtube"
)

type Article struct {
	ID              string        `json:"id"`
	UserID          string        `json:"user_id"`
	URL             string        `json:"url"`
	Title           *string       `json:"title,omitempty"`
	Author          *string       `json:"author,omitempty"`
	SiteName        *string       `json:"site_name,omitempty"`
	FaviconURL      *string       `json:"favicon_url,omitempty"`
	CoverImageURL   *string       `json:"cover_image_url,omitempty"`
	MarkdownContent *string       `json:"markdown_content,omitempty"`
	RawHTML         *string       `json:"raw_html,omitempty"`
	WordCount       int           `json:"word_count"`
	Language        *string       `json:"language,omitempty"`
	CategoryID      *string       `json:"category_id,omitempty"`
	Summary         *string       `json:"summary,omitempty"`
	KeyPoints       []string      `json:"key_points"`
	AIConfidence    *float64      `json:"ai_confidence,omitempty"`
	Status          ArticleStatus `json:"status"`
	SourceType      SourceType    `json:"source_type"`
	FetchError      *string       `json:"fetch_error,omitempty"`
	RetryCount      int           `json:"retry_count"`
	IsFavorite      bool          `json:"is_favorite"`
	IsArchived      bool          `json:"is_archived"`
	ReadProgress    float64       `json:"read_progress"`
	LastReadAt      *time.Time    `json:"last_read_at,omitempty"`
	PublishedAt     *time.Time    `json:"published_at,omitempty"`
	CreatedAt       time.Time     `json:"created_at"`
	UpdatedAt       time.Time     `json:"updated_at"`

	// Joined fields (not stored directly)
	Category *Category `json:"category,omitempty"`
	Tags     []Tag     `json:"tags,omitempty"`
}
