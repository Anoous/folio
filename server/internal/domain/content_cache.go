package domain

import "time"

// ContentCache holds crawl + AI results for a URL, shared across users.
type ContentCache struct {
	ID              string
	URL             string
	Title           *string
	Author          *string
	SiteName        *string
	FaviconURL      *string
	CoverImageURL   *string
	MarkdownContent *string
	WordCount       int
	Language        *string
	CategorySlug    *string
	Summary         *string
	KeyPoints       []string
	AIConfidence    *float64
	AITagNames      []string
	CrawledAt       *time.Time
	AIAnalyzedAt    *time.Time
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

// HasFullResult returns true if this cache entry has both content and AI results.
func (c *ContentCache) HasFullResult() bool {
	return c.MarkdownContent != nil && *c.MarkdownContent != "" &&
		c.Summary != nil && *c.Summary != ""
}

// HasContent returns true if this cache entry has crawled content (but maybe no AI yet).
func (c *ContentCache) HasContent() bool {
	return c.MarkdownContent != nil && *c.MarkdownContent != ""
}

// IsCacheWorthy checks if content meets quality threshold for caching.
// MVP: only checks content length. Signature reserves aiConfidence for future use.
func IsCacheWorthy(content string, aiConfidence float64) bool {
	return len(content) >= 200
}
