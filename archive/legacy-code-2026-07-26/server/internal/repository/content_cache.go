package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"folio-server/internal/domain"
)

type ContentCacheRepo struct {
	pool *pgxpool.Pool
}

func NewContentCacheRepo(pool *pgxpool.Pool) *ContentCacheRepo {
	return &ContentCacheRepo{pool: pool}
}

// GetByURL looks up cached content for a URL. Returns (nil, nil) if not found.
func (r *ContentCacheRepo) GetByURL(ctx context.Context, url string) (*domain.ContentCache, error) {
	row := r.pool.QueryRow(ctx, `
		SELECT id, url, title, author, site_name, favicon_url, cover_image_url,
		       markdown_content, word_count, language,
		       category_slug, summary, key_points, ai_confidence, ai_tag_names,
		       crawled_at, ai_analyzed_at, created_at, updated_at
		FROM content_cache WHERE url = $1`, url)

	var c domain.ContentCache
	var keyPointsJSON []byte
	err := row.Scan(
		&c.ID, &c.URL, &c.Title, &c.Author, &c.SiteName, &c.FaviconURL, &c.CoverImageURL,
		&c.MarkdownContent, &c.WordCount, &c.Language,
		&c.CategorySlug, &c.Summary, &keyPointsJSON, &c.AIConfidence, &c.AITagNames,
		&c.CrawledAt, &c.AIAnalyzedAt, &c.CreatedAt, &c.UpdatedAt,
	)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get content cache by url: %w", err)
	}
	if keyPointsJSON != nil {
		json.Unmarshal(keyPointsJSON, &c.KeyPoints)
	}
	return &c, nil
}

// Upsert inserts or updates a content cache entry for a URL.
func (r *ContentCacheRepo) Upsert(ctx context.Context, c *domain.ContentCache) error {
	keyPointsJSON, _ := json.Marshal(c.KeyPoints)
	now := time.Now()

	crawledAt := now
	if c.CrawledAt != nil {
		crawledAt = *c.CrawledAt
	}

	_, err := r.pool.Exec(ctx, `
		INSERT INTO content_cache (
			url, title, author, site_name, favicon_url, cover_image_url,
			markdown_content, word_count, language,
			category_slug, summary, key_points, ai_confidence, ai_tag_names,
			crawled_at, ai_analyzed_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)
		ON CONFLICT (url) DO UPDATE SET
			title            = COALESCE(NULLIF(EXCLUDED.title, ''), content_cache.title),
			author           = COALESCE(NULLIF(EXCLUDED.author, ''), content_cache.author),
			site_name        = COALESCE(NULLIF(EXCLUDED.site_name, ''), content_cache.site_name),
			favicon_url      = COALESCE(NULLIF(EXCLUDED.favicon_url, ''), content_cache.favicon_url),
			cover_image_url  = COALESCE(NULLIF(EXCLUDED.cover_image_url, ''), content_cache.cover_image_url),
			markdown_content = COALESCE(NULLIF(EXCLUDED.markdown_content, ''), content_cache.markdown_content),
			word_count       = CASE WHEN NULLIF(EXCLUDED.markdown_content, '') IS NOT NULL
			                   THEN EXCLUDED.word_count ELSE content_cache.word_count END,
			language         = COALESCE(NULLIF(EXCLUDED.language, ''), content_cache.language),
			category_slug    = COALESCE(NULLIF(EXCLUDED.category_slug, ''), content_cache.category_slug),
			summary          = COALESCE(NULLIF(EXCLUDED.summary, ''), content_cache.summary),
			key_points       = CASE WHEN EXCLUDED.summary IS NOT NULL AND EXCLUDED.summary != ''
			                   THEN EXCLUDED.key_points ELSE content_cache.key_points END,
			ai_confidence    = COALESCE(EXCLUDED.ai_confidence, content_cache.ai_confidence),
			ai_tag_names     = CASE WHEN EXCLUDED.ai_tag_names != '{}' AND EXCLUDED.ai_tag_names IS NOT NULL
			                   THEN EXCLUDED.ai_tag_names ELSE content_cache.ai_tag_names END,
			crawled_at       = COALESCE(EXCLUDED.crawled_at, content_cache.crawled_at),
			ai_analyzed_at   = COALESCE(EXCLUDED.ai_analyzed_at, content_cache.ai_analyzed_at)`,
		c.URL,
		derefStr(c.Title), derefStr(c.Author), derefStr(c.SiteName),
		derefStr(c.FaviconURL), derefStr(c.CoverImageURL),
		derefStr(c.MarkdownContent), c.WordCount, derefStr(c.Language),
		derefStr(c.CategorySlug), derefStr(c.Summary), keyPointsJSON,
		c.AIConfidence, c.AITagNames,
		crawledAt, c.AIAnalyzedAt,
	)
	if err != nil {
		return fmt.Errorf("upsert content cache: %w", err)
	}
	return nil
}

func derefStr(s *string) string {
	if s != nil {
		return *s
	}
	return ""
}

