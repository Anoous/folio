package worker

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

type crawlCacheArticleRepo interface {
	ArticleCrawlUpdater
	ArticleAIUpdater
	ArticleStatusUpdater
}

type crawlCacheTaskRepo interface {
	TaskCrawlTracker
	TaskAIFinisher
}

type crawlCacheHandler struct {
	articleRepo  crawlCacheArticleRepo
	taskRepo     crawlCacheTaskRepo
	aiHandoff    crawlAIHandoff
	tagRepo      TagCreator
	categoryRepo CategoryFinder
}

func (h *CrawlHandler) cacheHandler() crawlCacheHandler {
	return crawlCacheHandler{
		articleRepo:  h.articleRepo,
		taskRepo:     h.taskRepo,
		aiHandoff:    h.aiHandoff(),
		tagRepo:      h.tagRepo,
		categoryRepo: h.categoryRepo,
	}
}

func (h crawlCacheHandler) handle(ctx context.Context, p CrawlPayload, cached *domain.ContentCache, start time.Time) (bool, error) {
	if cached == nil {
		return false, nil
	}
	if cached.HasFullResult() {
		return true, h.applyFullHit(ctx, p, cached, start)
	}
	if cached.HasContent() {
		return true, h.applyPartialHit(ctx, p, cached, start)
	}
	return false, nil
}

func (h crawlCacheHandler) applyFullHit(ctx context.Context, p CrawlPayload, cached *domain.ContentCache, start time.Time) error {
	if err := h.articleRepo.UpdateCrawlResult(ctx, p.ArticleID, cachedCrawlResult(cached)); err != nil {
		return fmt.Errorf("cache hit: update crawl result: %w", err)
	}

	categoryID, err := h.findCachedCategory(ctx, cached)
	if err != nil {
		return err
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

	if err := h.articleRepo.UpdateStatus(ctx, p.ArticleID, domain.ArticleStatusReady); err != nil {
		return fmt.Errorf("cache hit: update article status: %w", err)
	}

	h.attachCachedTags(ctx, p, cached.AITagNames)

	if err := h.taskRepo.SetAIFinished(ctx, p.TaskID); err != nil {
		return fmt.Errorf("cache hit: set task done: %w", err)
	}

	slog.Info("crawl task completed via cache hit",
		"article_id", p.ArticleID,
		"duration_ms", time.Since(start).Milliseconds(),
	)
	return nil
}

func (h crawlCacheHandler) applyPartialHit(ctx context.Context, p CrawlPayload, cached *domain.ContentCache, start time.Time) error {
	if err := h.articleRepo.UpdateCrawlResult(ctx, p.ArticleID, cachedCrawlResult(cached)); err != nil {
		return fmt.Errorf("cache partial: update crawl result: %w", err)
	}
	if err := h.aiHandoff.enqueue(ctx, crawlAIHandoffRequest{
		payload:             p,
		title:               derefOrEmpty(cached.Title),
		markdown:            derefOrEmpty(cached.MarkdownContent),
		source:              derefOrDefault(cached.SiteName, "web"),
		author:              derefOrEmpty(cached.Author),
		finishBeforeEnqueue: true,
		setFinishedLabel:    "cache partial: set crawl finished",
		enqueueLabel:        "enqueue ai task (cache partial)",
	}); err != nil {
		return err
	}
	slog.Info("crawl task using cached content (partial, needs AI)",
		"article_id", p.ArticleID,
		"duration_ms", time.Since(start).Milliseconds(),
	)
	return nil
}

func (h crawlCacheHandler) findCachedCategory(ctx context.Context, cached *domain.ContentCache) (string, error) {
	categorySlug := derefOrEmpty(cached.CategorySlug)
	if categorySlug == "" {
		return "", nil
	}
	cat, err := h.categoryRepo.FindOrCreate(ctx, categorySlug, categorySlug, categorySlug)
	if err != nil {
		return "", fmt.Errorf("cache hit: find or create category: %w", err)
	}
	return cat.ID, nil
}

func (h crawlCacheHandler) attachCachedTags(ctx context.Context, p CrawlPayload, tagNames []string) {
	for _, tagName := range tagNames {
		tag, err := h.tagRepo.Create(ctx, p.UserID, tagName, true)
		if err != nil {
			continue
		}
		h.tagRepo.AttachToArticle(ctx, p.ArticleID, tag.ID)
	}
}

func cachedCrawlResult(cached *domain.ContentCache) repository.CrawlResult {
	return repository.CrawlResult{
		Title:      derefOrEmpty(cached.Title),
		Author:     derefOrEmpty(cached.Author),
		SiteName:   derefOrEmpty(cached.SiteName),
		Markdown:   derefOrEmpty(cached.MarkdownContent),
		CoverImage: derefOrEmpty(cached.CoverImageURL),
		Language:   derefOrEmpty(cached.Language),
		FaviconURL: derefOrEmpty(cached.FaviconURL),
	}
}
