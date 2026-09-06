package worker

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"folio-server/internal/client"
	"folio-server/internal/pipeline"
	"folio-server/internal/repository"
)

func TestCrawlFetchedContentHandler_CompletePersistsAndEnqueuesFollowups(t *testing.T) {
	articleRepo := &mockCrawlArticleRepo{}
	taskRepo := &mockCrawlTaskRepo{}
	enqueuer := &mockCrawlEnqueuer{}
	handler := crawlFetchedContentHandler{
		articleRepo: articleRepo,
		taskRepo:    taskRepo,
		aiHandoff:   crawlAIHandoff{taskRepo: taskRepo, asynqClient: enqueuer},
		asynqClient: enqueuer,
		enableImage: true,
	}

	err := handler.complete(context.Background(), fetchedContentTestPayload(), crawlFetchResult{
		response: &client.ScrapeResponse{
			Markdown: "# Article\n\n![photo](https://img.example.com/photo.jpg)\n\nBody",
			Metadata: client.ReaderMetadata{
				Title:    "Fetched Title",
				Author:   "Author",
				SiteName: "Example",
				OGImage:  "https://example.com/cover.jpg",
				Language: "en",
				Favicon:  "https://example.com/favicon.ico",
			},
		},
		stage:    pipeline.StageCrawlReader,
		provider: pipeline.ProviderReader,
	}, time.Now())
	if err != nil {
		t.Fatalf("complete() error = %v", err)
	}

	if len(articleRepo.updateCrawlCalls) != 1 {
		t.Fatalf("UpdateCrawlResult calls = %d, want 1", len(articleRepo.updateCrawlCalls))
	}
	crawl := articleRepo.updateCrawlCalls[0]
	if crawl.Title != "Fetched Title" || crawl.Author != "Author" || crawl.SiteName != "Example" || crawl.Markdown == "" {
		t.Fatalf("crawl result = %+v, want fetched metadata and markdown", crawl)
	}
	if len(enqueuer.enqueuedTasks) != 2 {
		t.Fatalf("enqueued tasks = %d, want AI + image upload", len(enqueuer.enqueuedTasks))
	}
	if enqueuer.enqueuedTasks[0].Type() != TypeAIProcess || enqueuer.enqueuedTasks[1].Type() != TypeImageUpload {
		t.Fatalf("enqueued task types = %s, %s; want AI then image", enqueuer.enqueuedTasks[0].Type(), enqueuer.enqueuedTasks[1].Type())
	}
	if len(taskRepo.setCrawlFinishedCalls) != 1 || taskRepo.setCrawlFinishedCalls[0] != "task-1" {
		t.Fatalf("SetCrawlFinished calls = %v, want [task-1]", taskRepo.setCrawlFinishedCalls)
	}

	var aiPayload AIProcessPayload
	if err := json.Unmarshal(enqueuer.enqueuedTasks[0].Payload(), &aiPayload); err != nil {
		t.Fatalf("unmarshal AI payload: %v", err)
	}
	if aiPayload.Title != "Fetched Title" || aiPayload.Source != "Example" || aiPayload.Author != "Author" {
		t.Fatalf("AI payload = %+v, want fetched fields", aiPayload)
	}

	var imagePayload ImageUploadPayload
	if err := json.Unmarshal(enqueuer.enqueuedTasks[1].Payload(), &imagePayload); err != nil {
		t.Fatalf("unmarshal image payload: %v", err)
	}
	if len(imagePayload.ImageURLs) != 1 || imagePayload.ImageURLs[0] != "https://img.example.com/photo.jpg" {
		t.Fatalf("image payload = %+v, want extracted image URL", imagePayload)
	}
}

func TestCrawlFetchedContentHandler_CompleteMarksTaskFailedWhenPersistFails(t *testing.T) {
	articleRepo := &mockCrawlArticleRepo{
		updateCrawlFn: func(ctx context.Context, id string, cr repository.CrawlResult) error {
			return errors.New("database unavailable")
		},
	}
	taskRepo := &mockCrawlTaskRepo{}
	enqueuer := &mockCrawlEnqueuer{}
	handler := crawlFetchedContentHandler{
		articleRepo: articleRepo,
		taskRepo:    taskRepo,
		aiHandoff:   crawlAIHandoff{taskRepo: taskRepo, asynqClient: enqueuer},
		asynqClient: enqueuer,
	}

	err := handler.complete(context.Background(), fetchedContentTestPayload(), crawlFetchResult{
		response: &client.ScrapeResponse{
			Markdown: "# Article",
			Metadata: client.ReaderMetadata{Title: "Fetched Title"},
		},
		stage:    pipeline.StageCrawlJina,
		provider: pipeline.ProviderJina,
	}, time.Now())
	if err == nil || !strings.Contains(err.Error(), "update crawl result") {
		t.Fatalf("complete() error = %v, want update crawl result error", err)
	}
	if len(taskRepo.setFailedCalls) != 1 {
		t.Fatalf("SetFailed calls = %d, want 1", len(taskRepo.setFailedCalls))
	}
	failure := taskRepo.setFailedCalls[0].Failure
	if failure.Provider == nil || *failure.Provider != "jina" {
		t.Fatalf("failure provider = %v, want jina", failure.Provider)
	}
	if failure.Code == nil || *failure.Code != "internal" {
		t.Fatalf("failure code = %v, want internal", failure.Code)
	}
	if len(enqueuer.enqueuedTasks) != 0 {
		t.Fatalf("enqueued tasks = %d, want 0", len(enqueuer.enqueuedTasks))
	}
}

func TestExtractImageURLs(t *testing.T) {
	got := extractImageURLs("![a](https://img.example.com/a.jpg) text ![b](https://img.example.com/b.png)")

	if len(got) != 2 || got[0] != "https://img.example.com/a.jpg" || got[1] != "https://img.example.com/b.png" {
		t.Fatalf("extractImageURLs() = %v, want two image URLs", got)
	}
}

func fetchedContentTestPayload() CrawlPayload {
	return CrawlPayload{
		ArticleID: "art-1",
		TaskID:    "task-1",
		URL:       "https://example.com/article",
		UserID:    "user-1",
	}
}
