package worker

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"regexp"
	"strings"
	"time"

	"github.com/hibiken/asynq"

	"folio-server/internal/client"
	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

// scraper abstracts the reader client for testing.
type scraper interface {
	Scrape(ctx context.Context, url string) (*client.ScrapeResponse, error)
}

// crawlArticleRepo abstracts the article repository methods used by CrawlHandler.
type crawlArticleRepo interface {
	GetByID(ctx context.Context, id string) (*domain.Article, error)
	UpdateCrawlResult(ctx context.Context, id string, cr repository.CrawlResult) error
	UpdateAIResult(ctx context.Context, id string, ai repository.AIResult) error
	UpdateStatus(ctx context.Context, id string, status domain.ArticleStatus) error
	SetError(ctx context.Context, id string, errMsg string) error
}

// crawlTaskRepo abstracts the task repository methods used by CrawlHandler.
type crawlTaskRepo interface {
	SetCrawlStarted(ctx context.Context, id string) error
	SetCrawlFinished(ctx context.Context, id string) error
	SetAIFinished(ctx context.Context, id string) error
	SetFailed(ctx context.Context, id string, errMsg string) error
}

// crawlEnqueuer abstracts the asynq client for enqueueing tasks.
type crawlEnqueuer interface {
	EnqueueContext(ctx context.Context, task *asynq.Task, opts ...asynq.Option) (*asynq.TaskInfo, error)
}

// crawlContentCacheRepo abstracts the content cache repository for CrawlHandler.
type crawlContentCacheRepo interface {
	GetByURL(ctx context.Context, url string) (*domain.ContentCache, error)
}

// crawlTagRepo abstracts the tag repository methods used by CrawlHandler for cache-hit tag creation.
type crawlTagRepo interface {
	Create(ctx context.Context, userID, name string, isAIGenerated bool) (*domain.Tag, error)
	AttachToArticle(ctx context.Context, articleID, tagID string) error
}

// crawlCategoryRepo abstracts the category repository methods used by CrawlHandler.
type crawlCategoryRepo interface {
	FindOrCreate(ctx context.Context, slug, nameZH, nameEN string) (*domain.Category, error)
}

type CrawlHandler struct {
	readerClient scraper
	jinaClient   scraper
	articleRepo  crawlArticleRepo
	taskRepo     crawlTaskRepo
	asynqClient  crawlEnqueuer
	enableImage  bool
	cacheRepo    crawlContentCacheRepo
	tagRepo      crawlTagRepo
	categoryRepo crawlCategoryRepo
}

func NewCrawlHandler(
	readerClient *client.ReaderClient,
	jinaClient *client.JinaClient,
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
		jinaClient:   jinaClient,
		articleRepo:  articleRepo,
		taskRepo:     taskRepo,
		asynqClient:  asynqClient,
		enableImage:  enableImage,
		cacheRepo:    cacheRepo,
		tagRepo:      tagRepo,
		categoryRepo: categoryRepo,
	}
}

func (h *CrawlHandler) ProcessTask(ctx context.Context, t *asynq.Task) error {
	var p CrawlPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("unmarshal crawl payload: %w", err)
	}

	start := time.Now()
	slog.Info("crawl task started", "article_id", p.ArticleID, "task_id", p.TaskID, "url", p.URL)

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
			if err := h.articleRepo.UpdateCrawlResult(ctx, p.ArticleID, repository.CrawlResult{
				Title:      derefOrEmpty(cached.Title),
				Author:     derefOrEmpty(cached.Author),
				SiteName:   derefOrEmpty(cached.SiteName),
				Markdown:   derefOrEmpty(cached.MarkdownContent),
				CoverImage: derefOrEmpty(cached.CoverImageURL),
				Language:   derefOrEmpty(cached.Language),
				FaviconURL: derefOrEmpty(cached.FaviconURL),
			}); err != nil {
				return fmt.Errorf("cache partial: update crawl result: %w", err)
			}
			if err := h.taskRepo.SetCrawlFinished(ctx, p.TaskID); err != nil {
				return fmt.Errorf("cache partial: set crawl finished: %w", err)
			}
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

	slog.Debug("cache miss, checking client content", "article_id", p.ArticleID)

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

	// --- Normal path: call Reader, fallback to Jina ---
	slog.Debug("no client content, calling reader", "article_id", p.ArticleID)
	result, err := h.readerClient.Scrape(ctx, p.URL)
	if err != nil {
		slog.Warn("reader failed, trying jina fallback",
			"article_id", p.ArticleID,
			"url", p.URL,
			"error", err,
		)
		result, err = h.jinaClient.Scrape(ctx, p.URL)
		if err != nil {
			slog.Error("crawl task failed (reader + jina both failed)",
				"article_id", p.ArticleID,
				"error", err,
			)
			h.taskRepo.SetFailed(ctx, p.TaskID, err.Error())
			h.articleRepo.SetError(ctx, p.ArticleID, err.Error())
			return fmt.Errorf("scrape failed: %w", err)
		}
		slog.Info("jina fallback succeeded", "article_id", p.ArticleID, "url", p.URL, "duration_ms", time.Since(start).Milliseconds())
	}

	// Post-process Weibo content
	title := result.Metadata.Title
	markdown := result.Markdown
	if isWeiboURL(p.URL) {
		markdown = cleanWeiboMarkdown(markdown)
		if isGenericWeiboTitle(title) {
			if extracted := extractTitleFromMarkdown(markdown); extracted != "" {
				title = extracted
			}
		}
	}

	if err := h.articleRepo.UpdateCrawlResult(ctx, p.ArticleID, repository.CrawlResult{
		Title:      title,
		Author:     result.Metadata.Author,
		SiteName:   result.Metadata.SiteName,
		Markdown:   markdown,
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
		title, markdown,
		source, result.Metadata.Author,
	)
	if _, err := h.asynqClient.EnqueueContext(ctx, aiTask); err != nil {
		return fmt.Errorf("enqueue ai task: %w", err)
	}

	slog.Info("crawl task completed",
		"article_id", p.ArticleID,
		"source", source,
		"title", title,
		"content_len", len(markdown),
		"duration_ms", time.Since(start).Milliseconds(),
	)

	// Enqueue image upload task (extract image URLs from markdown)
	imageURLs := extractImageURLs(result.Markdown)
	if h.enableImage && len(imageURLs) > 0 {
		imgTask := NewImageUploadTask(p.ArticleID, imageURLs)
		h.asynqClient.EnqueueContext(ctx, imgTask) // Non-blocking, errors OK
	}

	return nil
}

// applyCacheHit handles the full cache hit: copies content + AI results to the article,
// creates user-specific tags, and marks the task as done.
func (h *CrawlHandler) applyCacheHit(ctx context.Context, p CrawlPayload, cached *domain.ContentCache, start time.Time) error {
	// Update article with cached crawl results
	if err := h.articleRepo.UpdateCrawlResult(ctx, p.ArticleID, repository.CrawlResult{
		Title:      derefOrEmpty(cached.Title),
		Author:     derefOrEmpty(cached.Author),
		SiteName:   derefOrEmpty(cached.SiteName),
		Markdown:   derefOrEmpty(cached.MarkdownContent),
		CoverImage: derefOrEmpty(cached.CoverImageURL),
		Language:   derefOrEmpty(cached.Language),
		FaviconURL: derefOrEmpty(cached.FaviconURL),
	}); err != nil {
		return fmt.Errorf("cache hit: update crawl result: %w", err)
	}

	// Ensure category exists and update article with cached AI results
	categorySlug := derefOrEmpty(cached.CategorySlug)
	var categoryID string
	if categorySlug != "" {
		cat, err := h.categoryRepo.FindOrCreate(ctx, categorySlug, categorySlug, categorySlug)
		if err != nil {
			return fmt.Errorf("cache hit: find or create category: %w", err)
		}
		categoryID = cat.ID
	}
	if err := h.articleRepo.UpdateAIResult(ctx, p.ArticleID, repository.AIResult{
		CategoryID: categoryID,
		Summary:    derefOrEmpty(cached.Summary),
		KeyPoints:  cached.KeyPoints,
		Confidence: derefFloat(cached.AIConfidence),
		Language:   derefOrEmpty(cached.Language),
	}); err != nil {
		return fmt.Errorf("cache hit: update ai result: %w", err)
	}

	// Set article status to ready (cache hit has full content + AI)
	if err := h.articleRepo.UpdateStatus(ctx, p.ArticleID, domain.ArticleStatusReady); err != nil {
		return fmt.Errorf("cache hit: update article status: %w", err)
	}

	// Create per-user tags from cached AI tag names
	for _, tagName := range cached.AITagNames {
		tag, err := h.tagRepo.Create(ctx, p.UserID, tagName, true)
		if err != nil {
			continue
		}
		h.tagRepo.AttachToArticle(ctx, p.ArticleID, tag.ID)
	}

	// Mark task as done (SetAIFinished sets status='done')
	if err := h.taskRepo.SetAIFinished(ctx, p.TaskID); err != nil {
		return fmt.Errorf("cache hit: set task done: %w", err)
	}

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

// derefOrEmpty returns the dereferenced string or "" if the pointer is nil.
func derefOrEmpty(s *string) string {
	if s != nil {
		return *s
	}
	return ""
}

// derefOrDefault returns the dereferenced string, or fallback if nil or empty.
func derefOrDefault(s *string, fallback string) string {
	if s != nil && *s != "" {
		return *s
	}
	return fallback
}

// --- Weibo content cleaning ---

// isWeiboURL checks if the URL belongs to Weibo.
func isWeiboURL(url string) bool {
	return strings.Contains(url, "weibo.com") || strings.Contains(url, "weibo.cn")
}

// Generic useless titles from Weibo HTML <title>.
var weiboGenericTitles = []string{
	"微博正文",
	"Sina Visitor System",
	"微博",
}

// isGenericWeiboTitle returns true if the title is a known useless Weibo default.
func isGenericWeiboTitle(title string) bool {
	t := strings.TrimSpace(title)
	for _, g := range weiboGenericTitles {
		if strings.Contains(t, g) {
			return true
		}
	}
	return t == ""
}

// extractTitleFromMarkdown extracts the first non-empty, non-link line from markdown as a title.
// Falls back to the first 80 characters of content if nothing suitable found.
func extractTitleFromMarkdown(md string) string {
	lines := strings.Split(md, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		// Skip lines that are only links or images
		if strings.HasPrefix(line, "![") || strings.HasPrefix(line, "[![") {
			continue
		}
		// Strip markdown heading markers
		cleaned := strings.TrimLeft(line, "# ")
		// Skip lines that are only URLs
		if strings.HasPrefix(cleaned, "http://") || strings.HasPrefix(cleaned, "https://") || strings.HasPrefix(cleaned, "//") {
			continue
		}
		// Remove inline markdown links but keep text: [text](url) → text
		cleaned = mdLinkTextRegex.ReplaceAllString(cleaned, "$1")
		cleaned = strings.TrimSpace(cleaned)
		if cleaned == "" {
			continue
		}
		// Truncate to reasonable title length
		if len([]rune(cleaned)) > 80 {
			runes := []rune(cleaned)
			cleaned = string(runes[:80]) + "…"
		}
		return cleaned
	}
	return ""
}

// Regex patterns for Weibo markdown cleaning.
var (
	// Matches markdown links to weibo search/hashtag pages: [#topic#](//s.weibo.com/...)
	weiboHashtagLinkRegex = regexp.MustCompile(`\[#([^#\]]+)#\]\([^)]*(?:s\.weibo\.com|weibo\.com/p/)[^)]*\)`)
	// Matches markdown links to weibo user profiles: [@user](//weibo.com/u/...)
	weiboMentionLinkRegex = regexp.MustCompile(`\[@([^\]]+)\]\([^)]*weibo\.com[^)]*\)`)
	// Matches bare weibo URLs (protocol-relative or absolute)
	weiboBareLinkRegex = regexp.MustCompile(`(?:https?:)?//[^\s)]*(?:s\.weibo\.com|weibo\.com/p/)[^\s)]*`)
	// Extract link text from markdown links: [text](url)
	mdLinkTextRegex = regexp.MustCompile(`\[([^\]]*)\]\([^)]+\)`)
)

// cleanWeiboMarkdown removes Weibo-specific noise from markdown content.
func cleanWeiboMarkdown(md string) string {
	// Replace hashtag links with plain hashtag text: [#topic#](url) → #topic#
	result := weiboHashtagLinkRegex.ReplaceAllString(md, "#$1#")
	// Replace @mention links with plain @mention: [@user](url) → @user
	result = weiboMentionLinkRegex.ReplaceAllString(result, "@$1")
	// Remove remaining bare weibo search/hashtag URLs
	result = weiboBareLinkRegex.ReplaceAllString(result, "")
	// Clean up extra whitespace from removals
	result = strings.ReplaceAll(result, "  ", " ")
	return strings.TrimSpace(result)
}

var imageURLRegex = regexp.MustCompile(`!\[.*?\]\((https?://[^\s)]+)\)`)

func extractImageURLs(markdown string) []string {
	matches := imageURLRegex.FindAllStringSubmatch(markdown, -1)
	urls := make([]string, 0, len(matches))
	for _, m := range matches {
		if len(m) > 1 {
			urls = append(urls, m[1])
		}
	}
	return urls
}
