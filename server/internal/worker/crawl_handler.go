package worker

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"

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

type CrawlHandler struct {
	readerClient scraper
	articleRepo  crawlArticleRepo
	taskRepo     crawlTaskRepo
	asynqClient  crawlEnqueuer
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
		// Fallback: check if article already has client-provided content
		article, getErr := h.articleRepo.GetByID(ctx, p.ArticleID)
		if getErr == nil && article != nil && article.MarkdownContent != nil && *article.MarkdownContent != "" {
			h.taskRepo.SetCrawlFinished(ctx, p.TaskID)

			source := derefOrDefault(article.SiteName, "web")
			aiTask := NewAIProcessTask(
				p.ArticleID, p.TaskID, p.UserID,
				derefOrEmpty(article.Title), *article.MarkdownContent,
				source, derefOrEmpty(article.Author),
			)
			if _, enqErr := h.asynqClient.EnqueueContext(ctx, aiTask); enqErr != nil {
				return fmt.Errorf("enqueue ai task (client fallback): %w", enqErr)
			}
			return nil
		}

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

	// Enqueue image upload task (extract image URLs from markdown)
	imageURLs := extractImageURLs(result.Markdown)
	if h.enableImage && len(imageURLs) > 0 {
		imgTask := NewImageUploadTask(p.ArticleID, imageURLs)
		h.asynqClient.EnqueueContext(ctx, imgTask) // Non-blocking, errors OK
	}

	return nil
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
