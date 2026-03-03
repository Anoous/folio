# Crawl Optimization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Skip redundant Reader crawls when content is already available (client-extracted or cached from another user), and cache crawl+AI results for cross-user reuse.

**Architecture:** New `content_cache` table stores processed URL content. CrawlHandler checks cache before calling Reader. AIHandler writes to cache after success. The `articles` table and all API responses remain unchanged.

**Tech Stack:** Go / pgx v5 / asynq / PostgreSQL

**Design doc:** `docs/plans/2026-03-04-crawl-optimization-design.md`

---

### Task 1: Database Migration

**Files:**
- Create: `server/migrations/002_content_cache.up.sql`
- Create: `server/migrations/002_content_cache.down.sql`

**Step 1: Write the up migration**

```sql
-- server/migrations/002_content_cache.up.sql
CREATE TABLE content_cache (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    url              TEXT NOT NULL UNIQUE,
    title            VARCHAR(500),
    author           VARCHAR(200),
    site_name        VARCHAR(200),
    favicon_url      VARCHAR(500),
    cover_image_url  VARCHAR(500),
    markdown_content TEXT,
    word_count       INTEGER DEFAULT 0,
    language         VARCHAR(10),
    published_at     TIMESTAMPTZ,
    category_slug    VARCHAR(50),
    summary          TEXT,
    key_points       JSONB DEFAULT '[]',
    ai_confidence    DECIMAL(3,2),
    ai_tag_names     TEXT[] DEFAULT '{}',
    crawled_at       TIMESTAMPTZ,
    ai_analyzed_at   TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER update_content_cache_updated_at
    BEFORE UPDATE ON content_cache
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

**Step 2: Write the down migration**

```sql
-- server/migrations/002_content_cache.down.sql
DROP TRIGGER IF EXISTS update_content_cache_updated_at ON content_cache;
DROP TABLE IF EXISTS content_cache;
```

**Step 3: Apply migration to dev database**

Run: `docker exec $(docker ps --filter "publish=5432" -q) psql -U folio -d folio -f - < server/migrations/002_content_cache.up.sql`

Verify: `docker exec $(docker ps --filter "publish=5432" -q) psql -U folio -d folio -c "\d content_cache"`

Expected: table with all columns listed.

**Step 4: Commit**

```bash
git add server/migrations/002_content_cache.up.sql server/migrations/002_content_cache.down.sql
git commit -m "feat: add content_cache table migration for cross-user crawl reuse"
```

---

### Task 2: Domain Model

**Files:**
- Create: `server/internal/domain/content_cache.go`

**Step 1: Write the domain struct and quality gate function**

```go
// server/internal/domain/content_cache.go
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
```

**Step 2: Run compile check**

Run: `cd server && go build ./internal/domain/...`
Expected: success, no errors.

**Step 3: Commit**

```bash
git add server/internal/domain/content_cache.go
git commit -m "feat: add ContentCache domain model and IsCacheWorthy quality gate"
```

---

### Task 3: Content Cache Repository

**Files:**
- Create: `server/internal/repository/content_cache.go`
- Create: `server/internal/repository/content_cache_test.go`

**Step 1: Write the failing test for GetByURL**

```go
// server/internal/repository/content_cache_test.go
package repository

import (
	"testing"

	"folio-server/internal/domain"
)

func TestIsCacheWorthy_ShortContent(t *testing.T) {
	if domain.IsCacheWorthy("short", 0.9) {
		t.Error("content under 200 bytes should not be cache-worthy")
	}
}

func TestIsCacheWorthy_LongContent(t *testing.T) {
	content := make([]byte, 200)
	for i := range content {
		content[i] = 'a'
	}
	if !domain.IsCacheWorthy(string(content), 0.9) {
		t.Error("content at 200 bytes should be cache-worthy")
	}
}
```

**Step 2: Run test to verify it passes** (tests domain logic, no DB needed)

Run: `cd server && go test ./internal/repository/ -run TestIsCacheWorthy -v`
Expected: PASS

**Step 3: Write the repository**

Reference `server/internal/repository/article.go` for patterns (uses `pgxpool.Pool`, same `NewPool` connection).

```go
// server/internal/repository/content_cache.go
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
		nilOrTime(c.CrawledAt, now), c.AIAnalyzedAt,
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

func nilOrTime(t *time.Time, fallback time.Time) time.Time {
	if t != nil {
		return *t
	}
	return fallback
}
```

**Step 4: Run compile check**

Run: `cd server && go build ./internal/repository/...`
Expected: success.

**Step 5: Commit**

```bash
git add server/internal/repository/content_cache.go server/internal/repository/content_cache_test.go
git commit -m "feat: add ContentCacheRepo with GetByURL and Upsert"
```

---

### Task 4: CrawlHandler — Add Cache Lookup + Client Content Shortcut

This is the core logic change. The CrawlHandler needs two new dependencies and two new code paths inserted before the Reader call.

**Files:**
- Modify: `server/internal/worker/crawl_handler.go`
- Modify: `server/internal/worker/crawl_handler_test.go`

**Step 1: Write failing tests for the three new paths**

Add to `crawl_handler_test.go`. We need new mock interfaces for the cache and tag repos:

```go
// --- Add these mocks after the existing mocks ---

type mockContentCacheRepo struct {
	getByURLFn func(ctx context.Context, url string) (*domain.ContentCache, error)
	upsertFn   func(ctx context.Context, c *domain.ContentCache) error
}

func (m *mockContentCacheRepo) GetByURL(ctx context.Context, url string) (*domain.ContentCache, error) {
	if m.getByURLFn != nil {
		return m.getByURLFn(ctx, url)
	}
	return nil, nil
}

func (m *mockContentCacheRepo) Upsert(ctx context.Context, c *domain.ContentCache) error {
	if m.upsertFn != nil {
		return m.upsertFn(ctx, c)
	}
	return nil
}

type mockCrawlTagRepo struct {
	createFn          func(ctx context.Context, userID, name string, isAI bool) (*domain.Tag, error)
	attachFn          func(ctx context.Context, articleID, tagID string) error
}

func (m *mockCrawlTagRepo) Create(ctx context.Context, userID, name string, isAI bool) (*domain.Tag, error) {
	if m.createFn != nil {
		return m.createFn(ctx, userID, name, isAI)
	}
	return &domain.Tag{ID: "tag-" + name, Name: name}, nil
}

func (m *mockCrawlTagRepo) AttachToArticle(ctx context.Context, articleID, tagID string) error {
	if m.attachFn != nil {
		return m.attachFn(ctx, articleID, tagID)
	}
	return nil
}

type mockCrawlCategoryRepo struct{}

func (m *mockCrawlCategoryRepo) GetIDBySlug(ctx context.Context, slug string) (string, error) {
	return "cat-" + slug, nil
}
```

Update `newTestCrawlHandler` to include new dependencies:

```go
func newTestCrawlHandler(
	scraper *mockScraper,
	articleRepo *mockCrawlArticleRepo,
	taskRepo *mockCrawlTaskRepo,
	enqueuer *mockCrawlEnqueuer,
	enableImage bool,
) *CrawlHandler {
	return &CrawlHandler{
		readerClient: scraper,
		articleRepo:  articleRepo,
		taskRepo:     taskRepo,
		asynqClient:  enqueuer,
		enableImage:  enableImage,
		cacheRepo:    &mockContentCacheRepo{},  // default: cache miss
		tagRepo:      &mockCrawlTagRepo{},
		categoryRepo: &mockCrawlCategoryRepo{},
	}
}
```

Then add the three new test functions:

```go
func TestProcessTask_CacheHitFull_SkipsCrawlAndAI(t *testing.T) {
	// Cache has full results (content + AI) → skip Reader + AI entirely
	summary := "A cached summary"
	markdown := "# Cached Article\n\nLong enough content for the cache hit to work properly in our test scenario here."
	confidence := 0.85
	catSlug := "tech"

	mockReader := &mockScraper{
		scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
			t.Fatal("Reader should NOT be called on cache hit")
			return nil, nil
		},
	}
	mockArtRepo := &mockCrawlArticleRepo{}
	mockTaskRepo := &mockCrawlTaskRepo{}
	mockEnq := &mockCrawlEnqueuer{}
	mockCache := &mockContentCacheRepo{
		getByURLFn: func(ctx context.Context, url string) (*domain.ContentCache, error) {
			return &domain.ContentCache{
				URL:             url,
				Title:           strPtr("Cached Title"),
				Author:          strPtr("Cached Author"),
				SiteName:        strPtr("Cached Site"),
				MarkdownContent: &markdown,
				WordCount:       42,
				Language:        strPtr("en"),
				CategorySlug:    &catSlug,
				Summary:         &summary,
				KeyPoints:       []string{"point1", "point2"},
				AIConfidence:    &confidence,
				AITagNames:      []string{"go", "backend"},
			}, nil
		},
	}

	h := &CrawlHandler{
		readerClient: mockReader,
		articleRepo:  mockArtRepo,
		taskRepo:     mockTaskRepo,
		asynqClient:  mockEnq,
		cacheRepo:    mockCache,
		tagRepo:      &mockCrawlTagRepo{},
		categoryRepo: &mockCrawlCategoryRepo{},
	}

	task := newCrawlAsynqTask("art-1", "task-1", "https://example.com/cached", "user-1")
	err := h.ProcessTask(context.Background(), task)
	if err != nil {
		t.Fatalf("ProcessTask returned error: %v", err)
	}

	// Verify no AI task was enqueued (skipped)
	if len(mockEnq.enqueuedTasks) != 0 {
		t.Errorf("no tasks should be enqueued on full cache hit, got %d", len(mockEnq.enqueuedTasks))
	}

	// Verify article status was set to processing then crawl finished
	if len(mockArtRepo.updateStatusCalls) < 1 {
		t.Fatal("UpdateStatus should have been called")
	}

	// Verify task was marked finished (not failed)
	if len(mockTaskRepo.setCrawlFinishedCalls) != 1 {
		t.Errorf("SetCrawlFinished calls = %d, want 1", len(mockTaskRepo.setCrawlFinishedCalls))
	}
	if len(mockTaskRepo.setFailedCalls) != 0 {
		t.Errorf("SetFailed should not be called on cache hit, got %d", len(mockTaskRepo.setFailedCalls))
	}
}

func TestProcessTask_CacheMiss_ClientContent_SkipsReader(t *testing.T) {
	// Cache misses, but article has client-extracted content → skip Reader, enqueue AI
	mockReader := &mockScraper{
		scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
			t.Fatal("Reader should NOT be called when client content exists")
			return nil, nil
		},
	}
	clientMarkdown := "# Client Extracted\n\nSome content from the client extraction pipeline."
	mockArtRepo := &mockCrawlArticleRepo{
		getByIDFn: func(ctx context.Context, id string) (*domain.Article, error) {
			return &domain.Article{
				ID:              "art-1",
				Title:           strPtr("Client Title"),
				Author:          strPtr("Client Author"),
				SiteName:        strPtr("Client Site"),
				MarkdownContent: &clientMarkdown,
			}, nil
		},
	}
	mockTaskRepo := &mockCrawlTaskRepo{}
	mockEnq := &mockCrawlEnqueuer{}

	h := &CrawlHandler{
		readerClient: mockReader,
		articleRepo:  mockArtRepo,
		taskRepo:     mockTaskRepo,
		asynqClient:  mockEnq,
		cacheRepo:    &mockContentCacheRepo{}, // cache miss (default nil)
		tagRepo:      &mockCrawlTagRepo{},
		categoryRepo: &mockCrawlCategoryRepo{},
	}

	task := newCrawlAsynqTask("art-1", "task-1", "https://example.com/client", "user-1")
	err := h.ProcessTask(context.Background(), task)
	if err != nil {
		t.Fatalf("ProcessTask returned error: %v", err)
	}

	// Verify AI task was enqueued
	if len(mockEnq.enqueuedTasks) != 1 {
		t.Fatalf("enqueued tasks = %d, want 1 (AI)", len(mockEnq.enqueuedTasks))
	}
	if mockEnq.enqueuedTasks[0].Type() != TypeAIProcess {
		t.Errorf("enqueued task type = %q, want %q", mockEnq.enqueuedTasks[0].Type(), TypeAIProcess)
	}

	// Verify crawl was marked finished
	if len(mockTaskRepo.setCrawlFinishedCalls) != 1 {
		t.Errorf("SetCrawlFinished calls = %d, want 1", len(mockTaskRepo.setCrawlFinishedCalls))
	}
}

func TestProcessTask_CacheMiss_NoClientContent_CallsReader(t *testing.T) {
	// Cache misses, no client content → normal Reader flow (existing behavior)
	readerCalled := false
	mockReader := &mockScraper{
		scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
			readerCalled = true
			return &client.ScrapeResponse{
				Markdown: "# Reader Content\n\nExtracted by reader.",
				Metadata: client.ReaderMetadata{
					Title:    "Reader Title",
					SiteName: "Reader Site",
				},
			}, nil
		},
	}
	mockArtRepo := &mockCrawlArticleRepo{
		getByIDFn: func(ctx context.Context, id string) (*domain.Article, error) {
			return &domain.Article{ID: "art-1"}, nil // no markdown
		},
	}
	mockTaskRepo := &mockCrawlTaskRepo{}
	mockEnq := &mockCrawlEnqueuer{}

	h := &CrawlHandler{
		readerClient: mockReader,
		articleRepo:  mockArtRepo,
		taskRepo:     mockTaskRepo,
		asynqClient:  mockEnq,
		cacheRepo:    &mockContentCacheRepo{}, // cache miss
		tagRepo:      &mockCrawlTagRepo{},
		categoryRepo: &mockCrawlCategoryRepo{},
	}

	task := newCrawlAsynqTask("art-1", "task-1", "https://example.com/fresh", "user-1")
	err := h.ProcessTask(context.Background(), task)
	if err != nil {
		t.Fatalf("ProcessTask returned error: %v", err)
	}

	if !readerCalled {
		t.Error("Reader should be called when cache misses and no client content")
	}

	// Verify AI task was enqueued
	if len(mockEnq.enqueuedTasks) < 1 {
		t.Fatal("AI task should be enqueued after Reader success")
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd server && go test ./internal/worker/ -run "TestProcessTask_Cache" -v`
Expected: FAIL — `CrawlHandler` doesn't have `cacheRepo`, `tagRepo`, `categoryRepo` fields yet.

**Step 3: Add new interfaces and fields to CrawlHandler**

Modify `server/internal/worker/crawl_handler.go`:

Add interfaces after the existing ones (after line 41):

```go
// crawlContentCacheRepo abstracts the content cache repository for CrawlHandler.
type crawlContentCacheRepo interface {
	GetByURL(ctx context.Context, url string) (*domain.ContentCache, error)
}

// crawlTagRepo abstracts the tag repository methods used by CrawlHandler for cache-hit tag creation.
type crawlTagRepo interface {
	Create(ctx context.Context, userID, name string, isAIGenerated bool) (*domain.Tag, error)
	AttachToArticle(ctx context.Context, articleID, tagID string) error
}

// crawlCategoryRepo abstracts category lookup for resolving cached category_slug.
type crawlCategoryRepo interface {
	GetIDBySlug(ctx context.Context, slug string) (string, error)
}
```

Add fields to `CrawlHandler` struct:

```go
type CrawlHandler struct {
	readerClient scraper
	articleRepo  crawlArticleRepo
	taskRepo     crawlTaskRepo
	asynqClient  crawlEnqueuer
	enableImage  bool
	cacheRepo    crawlContentCacheRepo
	tagRepo      crawlTagRepo
	categoryRepo crawlCategoryRepo
}
```

Update `NewCrawlHandler` to accept the new dependencies:

```go
func NewCrawlHandler(
	readerClient *client.ReaderClient,
	articleRepo *repository.ArticleRepo,
	taskRepo *repository.TaskRepo,
	asynqClient *asynq.Client,
	enableImage bool,
	cacheRepo *repository.ContentCacheRepo,
	tagRepo *repository.TagRepo,
	categoryRepo *repository.CategoryRepo,
) *CrawlHandler {
	return &CrawlHandler{
		readerClient: readerClient,
		articleRepo:  articleRepo,
		taskRepo:     taskRepo,
		asynqClient:  asynqClient,
		enableImage:  enableImage,
		cacheRepo:    cacheRepo,
		tagRepo:      tagRepo,
		categoryRepo: categoryRepo,
	}
}
```

Add `UpdateAIResult` to the `crawlArticleRepo` interface (needed for cache-hit path):

```go
type crawlArticleRepo interface {
	GetByID(ctx context.Context, id string) (*domain.Article, error)
	UpdateCrawlResult(ctx context.Context, id string, cr repository.CrawlResult) error
	UpdateAIResult(ctx context.Context, id string, ai repository.AIResult) error
	UpdateStatus(ctx context.Context, id string, status domain.ArticleStatus) error
	SetError(ctx context.Context, id string, errMsg string) error
}
```

Add `UpdateAIResult` to `mockCrawlArticleRepo`:

```go
// Add field:
updateAIResultCalls []repository.AIResult

// Add method:
func (m *mockCrawlArticleRepo) UpdateAIResult(ctx context.Context, id string, ai repository.AIResult) error {
	m.updateAIResultCalls = append(m.updateAIResultCalls, ai)
	return nil
}
```

Add `GetIDBySlug` to `CategoryRepo`. Check if it exists — if not, add it to `server/internal/repository/category.go`:

```go
func (r *CategoryRepo) GetIDBySlug(ctx context.Context, slug string) (string, error) {
	var id string
	err := r.pool.QueryRow(ctx, `SELECT id FROM categories WHERE slug = $1`, slug).Scan(&id)
	if err != nil {
		return "", fmt.Errorf("get category id by slug: %w", err)
	}
	return id, nil
}
```

**Step 4: Implement the new ProcessTask logic**

Replace the `ProcessTask` method in `crawl_handler.go`. Insert the cache check + client content check **before** the Reader call (between the current lines 83 and 85):

```go
func (h *CrawlHandler) ProcessTask(ctx context.Context, t *asynq.Task) error {
	var p CrawlPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("unmarshal crawl payload: %w", err)
	}

	start := time.Now()

	// Mark crawl started
	if err := h.taskRepo.SetCrawlStarted(ctx, p.TaskID); err != nil {
		return fmt.Errorf("set crawl started: %w", err)
	}

	// Set article status to processing
	if err := h.articleRepo.UpdateStatus(ctx, p.ArticleID, domain.ArticleStatusProcessing); err != nil {
		return fmt.Errorf("update article status to processing: %w", err)
	}

	// --- Optimization 1: Check content cache ---
	if cached, err := h.cacheRepo.GetByURL(ctx, p.URL); err == nil && cached != nil {
		if cached.HasFullResult() {
			return h.applyCacheHit(ctx, p, cached, start)
		}
		if cached.HasContent() {
			// Partial hit: have content but no AI. Use cached content, run AI.
			h.articleRepo.UpdateCrawlResult(ctx, p.ArticleID, repository.CrawlResult{
				Title:      derefOrEmpty(cached.Title),
				Author:     derefOrEmpty(cached.Author),
				SiteName:   derefOrEmpty(cached.SiteName),
				Markdown:   derefOrEmpty(cached.MarkdownContent),
				CoverImage: derefOrEmpty(cached.CoverImageURL),
				Language:   derefOrEmpty(cached.Language),
				FaviconURL: derefOrEmpty(cached.FaviconURL),
			})
			h.taskRepo.SetCrawlFinished(ctx, p.TaskID)
			source := derefOrDefault(cached.SiteName, "web")
			aiTask := NewAIProcessTask(
				p.ArticleID, p.TaskID, p.UserID,
				derefOrEmpty(cached.Title), derefOrEmpty(cached.MarkdownContent),
				source, derefOrEmpty(cached.Author),
			)
			if _, enqErr := h.asynqClient.EnqueueContext(ctx, aiTask); enqErr != nil {
				return fmt.Errorf("enqueue ai task (cache partial): %w", enqErr)
			}
			slog.Info("crawl task using cached content (partial, needs AI)",
				"article_id", p.ArticleID,
				"duration_ms", time.Since(start).Milliseconds(),
			)
			return nil
		}
	}

	// --- Optimization 2: Check client-extracted content ---
	article, getErr := h.articleRepo.GetByID(ctx, p.ArticleID)
	if getErr == nil && article != nil && article.MarkdownContent != nil && *article.MarkdownContent != "" {
		slog.Info("crawl task using client-provided content, skipping Reader",
			"article_id", p.ArticleID,
			"duration_ms", time.Since(start).Milliseconds(),
		)
		h.taskRepo.SetCrawlFinished(ctx, p.TaskID)
		source := derefOrDefault(article.SiteName, "web")
		aiTask := NewAIProcessTask(
			p.ArticleID, p.TaskID, p.UserID,
			derefOrEmpty(article.Title), *article.MarkdownContent,
			source, derefOrEmpty(article.Author),
		)
		if _, enqErr := h.asynqClient.EnqueueContext(ctx, aiTask); enqErr != nil {
			return fmt.Errorf("enqueue ai task (client content): %w", enqErr)
		}
		return nil
	}

	// --- Normal path: call Reader ---
	result, err := h.readerClient.Scrape(ctx, p.URL)
	if err != nil {
		// Existing fallback: check client content (for the case where GetByID above
		// failed but article still has content — shouldn't happen, but defensive)
		slog.Error("crawl task failed",
			"article_id", p.ArticleID,
			"error", err,
		)
		h.taskRepo.SetFailed(ctx, p.TaskID, err.Error())
		h.articleRepo.SetError(ctx, p.ArticleID, err.Error())
		return fmt.Errorf("scrape failed: %w", err)
	}

	if err := h.articleRepo.UpdateCrawlResult(ctx, p.ArticleID, repository.CrawlResult{
		Title:      result.Metadata.Title,
		Author:     result.Metadata.Author,
		SiteName:   result.Metadata.SiteName,
		Markdown:   result.Markdown,
		CoverImage: result.Metadata.OGImage,
		Language:   result.Metadata.Language,
		FaviconURL: result.Metadata.Favicon,
	}); err != nil {
		slog.Error("crawl task failed to persist result",
			"article_id", p.ArticleID,
			"error", err,
		)
		h.taskRepo.SetFailed(ctx, p.TaskID, err.Error())
		return fmt.Errorf("update crawl result: %w", err)
	}

	h.taskRepo.SetCrawlFinished(ctx, p.TaskID)

	source := result.Metadata.SiteName
	if source == "" {
		source = "web"
	}
	aiTask := NewAIProcessTask(
		p.ArticleID, p.TaskID, p.UserID,
		result.Metadata.Title, result.Markdown,
		source, result.Metadata.Author,
	)
	if _, err := h.asynqClient.EnqueueContext(ctx, aiTask); err != nil {
		return fmt.Errorf("enqueue ai task: %w", err)
	}

	slog.Info("crawl task completed",
		"article_id", p.ArticleID,
		"duration_ms", time.Since(start).Milliseconds(),
	)

	// Enqueue image upload task
	imageURLs := extractImageURLs(result.Markdown)
	if h.enableImage && len(imageURLs) > 0 {
		imgTask := NewImageUploadTask(p.ArticleID, imageURLs)
		h.asynqClient.EnqueueContext(ctx, imgTask)
	}

	return nil
}

// applyCacheHit handles the full cache hit: copies content + AI results to the article,
// creates user-specific tags, and marks the task as done.
func (h *CrawlHandler) applyCacheHit(ctx context.Context, p CrawlPayload, cached *domain.ContentCache, start time.Time) error {
	// Update article with cached crawl results
	h.articleRepo.UpdateCrawlResult(ctx, p.ArticleID, repository.CrawlResult{
		Title:      derefOrEmpty(cached.Title),
		Author:     derefOrEmpty(cached.Author),
		SiteName:   derefOrEmpty(cached.SiteName),
		Markdown:   derefOrEmpty(cached.MarkdownContent),
		CoverImage: derefOrEmpty(cached.CoverImageURL),
		Language:   derefOrEmpty(cached.Language),
		FaviconURL: derefOrEmpty(cached.FaviconURL),
	})

	// Update article with cached AI results
	h.articleRepo.UpdateAIResult(ctx, p.ArticleID, repository.AIResult{
		CategorySlug: derefOrEmpty(cached.CategorySlug),
		Summary:      derefOrEmpty(cached.Summary),
		KeyPoints:    cached.KeyPoints,
		Confidence:   derefFloat(cached.AIConfidence),
		Language:     derefOrEmpty(cached.Language),
	})

	// Create per-user tags from cached AI tag names
	for _, tagName := range cached.AITagNames {
		tag, err := h.tagRepo.Create(ctx, p.UserID, tagName, true)
		if err != nil {
			continue
		}
		h.tagRepo.AttachToArticle(ctx, p.ArticleID, tag.ID)
	}

	// Mark task as done
	h.taskRepo.SetCrawlFinished(ctx, p.TaskID)

	slog.Info("crawl task completed via cache hit",
		"article_id", p.ArticleID,
		"duration_ms", time.Since(start).Milliseconds(),
	)
	return nil
}

func derefFloat(f *float64) float64 {
	if f != nil {
		return *f
	}
	return 0
}
```

**Step 5: Run tests**

Run: `cd server && go test ./internal/worker/ -v`
Expected: ALL tests pass (both new and existing).

**Step 6: Commit**

```bash
git add server/internal/worker/crawl_handler.go server/internal/worker/crawl_handler_test.go server/internal/repository/category.go
git commit -m "feat: add cache lookup and client content shortcut to CrawlHandler"
```

---

### Task 5: AIHandler — Write to Cache After Success

**Files:**
- Modify: `server/internal/worker/ai_handler.go`

**Step 1: Add ContentCacheRepo dependency to AIHandler**

Add field and update constructor:

```go
type AIHandler struct {
	aiClient     *client.AIClient
	articleRepo  *repository.ArticleRepo
	taskRepo     *repository.TaskRepo
	categoryRepo *repository.CategoryRepo
	tagRepo      *repository.TagRepo
	cacheRepo    *repository.ContentCacheRepo
}

func NewAIHandler(
	aiClient *client.AIClient,
	articleRepo *repository.ArticleRepo,
	taskRepo *repository.TaskRepo,
	categoryRepo *repository.CategoryRepo,
	tagRepo *repository.TagRepo,
	cacheRepo *repository.ContentCacheRepo,
) *AIHandler {
	return &AIHandler{
		aiClient:     aiClient,
		articleRepo:  articleRepo,
		taskRepo:     taskRepo,
		categoryRepo: categoryRepo,
		tagRepo:      tagRepo,
		cacheRepo:    cacheRepo,
	}
}
```

**Step 2: Add cache write after AI success**

At the end of `ProcessTask`, after `SetAIFinished` and the success log (after current line 105), add:

```go
	// Write to content cache for cross-user reuse
	if h.cacheRepo != nil {
		article, err := h.articleRepo.GetByID(ctx, p.ArticleID)
		if err == nil && article != nil {
			markdown := derefOrEmpty(article.MarkdownContent)
			if domain.IsCacheWorthy(markdown, result.Confidence) {
				now := time.Now()
				h.cacheRepo.Upsert(ctx, &domain.ContentCache{
					URL:             article.URL,
					Title:           article.Title,
					Author:          article.Author,
					SiteName:        article.SiteName,
					FaviconURL:      article.FaviconURL,
					CoverImageURL:   article.CoverImageURL,
					MarkdownContent: article.MarkdownContent,
					WordCount:       article.WordCount,
					Language:        article.Language,
					CategorySlug:    &result.Category,
					Summary:         &result.Summary,
					KeyPoints:       result.KeyPoints,
					AIConfidence:    &result.Confidence,
					AITagNames:      result.Tags,
					AIAnalyzedAt:    &now,
				}) // Non-fatal: cache write failure doesn't affect the article
			}
		}
	}
```

Note: `derefOrEmpty` is defined in `crawl_handler.go` in the same package, so it's accessible.

**Step 3: Run compile check**

Run: `cd server && go build ./internal/worker/...`
Expected: success.

**Step 4: Commit**

```bash
git add server/internal/worker/ai_handler.go
git commit -m "feat: AIHandler writes to content_cache after successful analysis"
```

---

### Task 6: Wire Everything Up in main.go and WorkerServer

**Files:**
- Modify: `server/cmd/server/main.go`
- Modify: `server/internal/worker/server.go` (no change needed — WorkerServer doesn't need cache repo)

**Step 1: Add ContentCacheRepo instantiation and pass to handlers**

In `main.go`, after the existing repository instantiations (after line 47), add:

```go
	contentCacheRepo := repository.NewContentCacheRepo(pool)
```

Update the CrawlHandler construction (current line 102):

```go
	crawlHandler := worker.NewCrawlHandler(readerClient, articleRepo, taskRepo, asynqClient, r2Client != nil, contentCacheRepo, tagRepo, categoryRepo)
```

Update the AIHandler construction (current line 103):

```go
	aiHandler := worker.NewAIHandler(aiClient, articleRepo, taskRepo, categoryRepo, tagRepo, contentCacheRepo)
```

**Step 2: Run compile check**

Run: `cd server && go build ./cmd/server/...`
Expected: success.

**Step 3: Commit**

```bash
git add server/cmd/server/main.go
git commit -m "feat: wire ContentCacheRepo into CrawlHandler and AIHandler"
```

---

### Task 7: Run Full Test Suite and Verify

**Step 1: Run unit tests**

Run: `cd server && go test ./... -v`
Expected: ALL tests pass.

**Step 2: Apply migration to test database and run E2E tests**

Run:
```bash
# Apply migration to test DB
docker exec $(docker ps --filter "publish=15432" -q) psql -U folio -d folio -f - < server/migrations/002_content_cache.up.sql

# Run E2E tests
cd server && ./scripts/run_e2e.sh
```

Expected: E2E tests pass (the new code paths are additive; existing flows should work identically).

**Step 3: Manual smoke test**

1. Start dev environment: `cd server && ./scripts/dev-start.sh`
2. Submit the same URL twice with the same dev user → second should process normally (first populates cache)
3. Create a second dev user (`POST /api/v1/auth/dev` with `{"alias": "user2"}`), submit the same URL → should complete nearly instantly via cache hit
4. Check cache: `docker exec $(docker ps --filter "publish=5432" -q) psql -U folio -d folio -c "SELECT url, title, category_slug, array_length(ai_tag_names, 1) as tag_count FROM content_cache"`

**Step 4: Final commit**

```bash
git add -A
git commit -m "test: verify crawl optimization with cache hit and client content shortcut"
```
