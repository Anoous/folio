package worker

import (
	"context"
	"log/slog"
	"time"

	"folio-server/internal/domain"
)

type crawlExistingContentRoute struct {
	articleRepo ArticleStatusUpdater
	aiHandoff   crawlAIHandoff
}

func (h *CrawlHandler) existingContentRoute() crawlExistingContentRoute {
	return crawlExistingContentRoute{
		articleRepo: h.articleRepo,
		aiHandoff:   h.aiHandoff(),
	}
}

func (r crawlExistingContentRoute) beforeCrawl(ctx context.Context, p CrawlPayload, article *domain.Article) (bool, error) {
	if article == nil {
		return false, nil
	}

	if article.HighlightCount > 0 {
		if markdown, ok := articleMarkdown(article); ok {
			slog.Info("crawl skipped: article has highlights and content, routing to AI",
				"article_id", p.ArticleID,
				"highlight_count", article.HighlightCount,
			)
			return true, r.aiHandoff.enqueue(ctx, crawlAIHandoffRequest{
				payload:             p,
				title:               derefOrEmpty(article.Title),
				markdown:            markdown,
				source:              derefOrDefault(article.SiteName, "web"),
				author:              derefOrEmpty(article.Author),
				finishBeforeEnqueue: true,
				setFinishedLabel:    "highlights: set crawl finished",
				enqueueLabel:        "enqueue ai task (highlights)",
			})
		}
		slog.Info("crawl proceeding: article has highlights but no content",
			"article_id", p.ArticleID,
			"highlight_count", article.HighlightCount,
		)
	}

	if isScreenshotOrVoice(article.SourceType) {
		if markdown, ok := articleMarkdown(article); ok {
			slog.Info("crawl skipped: screenshot/voice article has content, routing to AI",
				"article_id", p.ArticleID,
				"source_type", article.SourceType,
			)
			return true, r.aiHandoff.enqueue(ctx, crawlAIHandoffRequest{
				payload:             p,
				title:               derefOrEmpty(article.Title),
				markdown:            markdown,
				source:              string(article.SourceType),
				author:              derefOrEmpty(article.Author),
				finishBeforeEnqueue: true,
				setFinishedLabel:    "screenshot/voice: set crawl finished",
				enqueueLabel:        "enqueue ai task (screenshot/voice)",
			})
		}
		slog.Info("crawl skipped: screenshot/voice article has no content, marking ready",
			"article_id", p.ArticleID,
			"source_type", article.SourceType,
		)
		return true, r.articleRepo.UpdateStatus(ctx, p.ArticleID, domain.ArticleStatusReady)
	}

	return false, nil
}

func (r crawlExistingContentRoute) afterCacheMiss(ctx context.Context, p CrawlPayload, article *domain.Article, start time.Time) (bool, error) {
	markdown, ok := articleMarkdown(article)
	if !ok {
		return false, nil
	}

	slog.Info("crawl task using client-provided content, skipping Reader",
		"article_id", p.ArticleID,
		"duration_ms", time.Since(start).Milliseconds(),
	)
	return true, r.aiHandoff.enqueue(ctx, crawlAIHandoffRequest{
		payload:             p,
		title:               derefOrEmpty(article.Title),
		markdown:            markdown,
		source:              derefOrDefault(article.SiteName, "web"),
		author:              derefOrEmpty(article.Author),
		finishBeforeEnqueue: false,
		setFinishedLabel:    "client content: set crawl finished",
		enqueueLabel:        "enqueue ai task (client content)",
	})
}

func articleMarkdown(article *domain.Article) (string, bool) {
	if article == nil || article.MarkdownContent == nil || *article.MarkdownContent == "" {
		return "", false
	}
	return *article.MarkdownContent, true
}

func isScreenshotOrVoice(sourceType domain.SourceType) bool {
	return sourceType == domain.SourceScreenshot || sourceType == domain.SourceVoice
}
