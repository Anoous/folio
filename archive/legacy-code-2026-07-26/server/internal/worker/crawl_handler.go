package worker

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
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

type CrawlHandler struct {
	readerClient scraper
	jinaClient   scraper
	articleRepo  interface {
		ArticleGetter
		ArticleCrawlUpdater
		ArticleAIUpdater
		ArticleStatusUpdater
	}
	taskRepo interface {
		TaskCrawlTracker
		TaskAIFinisher
		TaskFailer
	}
	asynqClient  Enqueuer
	enableImage  bool
	cacheRepo    ContentCacheReader
	tagRepo      TagCreator
	categoryRepo CategoryFinder
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

	// Load article once for pre-crawl checks
	preCheckArticle, preCheckErr := h.articleRepo.GetByID(ctx, p.ArticleID)
	if preCheckErr == nil {
		handled, err := h.existingContentRoute().beforeCrawl(ctx, p, preCheckArticle)
		if handled || err != nil {
			return err
		}
	}

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
		handled, err := h.cacheHandler().handle(ctx, p, cached, start)
		if handled || err != nil {
			return err
		}
	}

	slog.Debug("cache miss, checking client content", "article_id", p.ArticleID)

	// --- Optimization 2: Check client-extracted content ---
	article, getErr := h.articleRepo.GetByID(ctx, p.ArticleID)
	if getErr == nil {
		handled, err := h.existingContentRoute().afterCacheMiss(ctx, p, article, start)
		if handled || err != nil {
			return err
		}
	}

	// --- Normal path: call Reader, fallback to Jina ---
	slog.Debug("no client content, calling reader", "article_id", p.ArticleID)
	fetch, err := h.contentFetcher().fetch(ctx, p, start)
	if err != nil {
		logPipelineFailed(fetch.stage, fetch.provider, p.TaskID, p.ArticleID, p.UserID, p.URL, time.Since(start), err)
		h.taskRepo.SetFailed(ctx, p.TaskID, buildTaskFailure(err, time.Since(start)))
		h.articleRepo.SetError(ctx, p.ArticleID, err.Error())
		return nil
	}
	return h.fetchedContentHandler().complete(ctx, p, fetch, start)
}
