package worker

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"

	"github.com/hibiken/asynq"

	"folio-server/internal/client"
	"folio-server/internal/repository"
)

type CrawlHandler struct {
	readerClient *client.ReaderClient
	articleRepo  *repository.ArticleRepo
	taskRepo     *repository.TaskRepo
	asynqClient  *asynq.Client
	enableImage  bool
}

func NewCrawlHandler(
	readerClient *client.ReaderClient,
	articleRepo *repository.ArticleRepo,
	taskRepo *repository.TaskRepo,
	asynqClient *asynq.Client,
	enableImage bool,
) *CrawlHandler {
	return &CrawlHandler{
		readerClient: readerClient,
		articleRepo:  articleRepo,
		taskRepo:     taskRepo,
		asynqClient:  asynqClient,
		enableImage:  enableImage,
	}
}

func (h *CrawlHandler) ProcessTask(ctx context.Context, t *asynq.Task) error {
	var p CrawlPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("unmarshal crawl payload: %w", err)
	}

	// Mark crawl started
	if err := h.taskRepo.SetCrawlStarted(ctx, p.TaskID); err != nil {
		return fmt.Errorf("set crawl started: %w", err)
	}

	// Scrape
	result, err := h.readerClient.Scrape(ctx, p.URL)
	if err != nil {
		h.taskRepo.SetFailed(ctx, p.TaskID, err.Error())
		h.articleRepo.SetError(ctx, p.ArticleID, err.Error())
		return fmt.Errorf("scrape failed: %w", err)
	}

	// Update article with crawl results
	if err := h.articleRepo.UpdateCrawlResult(ctx, p.ArticleID, repository.CrawlResult{
		Title:      result.Metadata.Title,
		Author:     result.Metadata.Author,
		SiteName:   result.Metadata.SiteName,
		Markdown:   result.Markdown,
		CoverImage: result.Metadata.OGImage,
		Language:   result.Metadata.Language,
		FaviconURL: result.Metadata.Favicon,
	}); err != nil {
		h.taskRepo.SetFailed(ctx, p.TaskID, err.Error())
		return fmt.Errorf("update crawl result: %w", err)
	}

	// Mark crawl finished
	h.taskRepo.SetCrawlFinished(ctx, p.TaskID)

	// Enqueue AI processing task
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

	// Enqueue image upload task (extract image URLs from markdown)
	imageURLs := extractImageURLs(result.Markdown)
	if h.enableImage && len(imageURLs) > 0 {
		imgTask := NewImageUploadTask(p.ArticleID, imageURLs)
		h.asynqClient.EnqueueContext(ctx, imgTask) // Non-blocking, errors OK
	}

	return nil
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
