package worker

import (
	"context"
	"fmt"
	"regexp"
	"time"

	"folio-server/internal/repository"
)

type crawlFetchedContentHandler struct {
	articleRepo ArticleCrawlUpdater
	taskRepo    TaskFailer
	aiHandoff   crawlAIHandoff
	asynqClient Enqueuer
	enableImage bool
}

func (h *CrawlHandler) fetchedContentHandler() crawlFetchedContentHandler {
	return crawlFetchedContentHandler{
		articleRepo: h.articleRepo,
		taskRepo:    h.taskRepo,
		aiHandoff:   h.aiHandoff(),
		asynqClient: h.asynqClient,
		enableImage: h.enableImage,
	}
}

func (h crawlFetchedContentHandler) complete(ctx context.Context, p CrawlPayload, fetch crawlFetchResult, start time.Time) error {
	result := fetch.response
	processed := crawlContentPostprocessor{}.apply(p.URL, result)

	if err := h.articleRepo.UpdateCrawlResult(ctx, p.ArticleID, repository.CrawlResult{
		Title:      processed.title,
		Author:     result.Metadata.Author,
		SiteName:   result.Metadata.SiteName,
		Markdown:   processed.markdown,
		CoverImage: result.Metadata.OGImage,
		Language:   result.Metadata.Language,
		FaviconURL: result.Metadata.Favicon,
	}); err != nil {
		failureErr := ensurePipelineErr(fetch.stage, fetch.provider, true, "persist crawl result", err)
		logPipelineFailed(fetch.stage, fetch.provider, p.TaskID, p.ArticleID, p.UserID, p.URL, time.Since(start), failureErr)
		h.taskRepo.SetFailed(ctx, p.TaskID, buildTaskFailure(failureErr, time.Since(start)))
		return fmt.Errorf("update crawl result: %w", err)
	}

	source := result.Metadata.SiteName
	if source == "" {
		source = "web"
	}
	if err := h.aiHandoff.enqueue(ctx, crawlAIHandoffRequest{
		payload:             p,
		title:               processed.title,
		markdown:            processed.markdown,
		source:              source,
		author:              result.Metadata.Author,
		finishBeforeEnqueue: false,
		setFinishedLabel:    "set crawl finished",
		enqueueLabel:        "enqueue ai task",
	}); err != nil {
		return err
	}

	logPipelineSucceeded(fetch.stage, fetch.provider, p.TaskID, p.ArticleID, p.UserID, p.URL, time.Since(start))
	h.enqueueImageUpload(ctx, p.ArticleID, result.Markdown)
	return nil
}

func (h crawlFetchedContentHandler) enqueueImageUpload(ctx context.Context, articleID string, markdown string) {
	imageURLs := extractImageURLs(markdown)
	if h.enableImage && len(imageURLs) > 0 {
		imgTask := NewImageUploadTask(articleID, imageURLs)
		h.asynqClient.EnqueueContext(ctx, imgTask)
	}
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
