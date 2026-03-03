package worker

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"regexp"
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

// crawlCategoryRepo abstracts category lookup for resolving cached category_slug.
type crawlCategoryRepo interface {
	GetIDBySlug(ctx context.Context, slug string) (string, error)
}

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
