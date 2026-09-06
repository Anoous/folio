package worker

import (
	"context"
	"encoding/json"
	"reflect"
	"testing"
	"time"

	"github.com/hibiken/asynq"

	"folio-server/internal/domain"
)

func TestCrawlExistingContentRoute_BeforeCrawlRoutesHighlightedContentToAI(t *testing.T) {
	events := []string{}
	articleRepo := &mockCrawlArticleRepo{}
	taskRepo := &mockCrawlTaskRepo{
		setCrawlFinishedFn: func(ctx context.Context, id string) error {
			events = append(events, "finish:"+id)
			return nil
		},
	}
	enqueuer := &mockCrawlEnqueuer{
		enqueueFn: func(ctx context.Context, task *asynq.Task, opts ...asynq.Option) (*asynq.TaskInfo, error) {
			events = append(events, "enqueue:"+task.Type())
			return &asynq.TaskInfo{}, nil
		},
	}
	route := crawlExistingContentRoute{
		articleRepo: articleRepo,
		aiHandoff:   crawlAIHandoff{taskRepo: taskRepo, asynqClient: enqueuer},
	}

	handled, err := route.beforeCrawl(context.Background(), existingContentTestPayload(), &domain.Article{
		ID:              "art-1",
		Title:           strPtr("Highlighted Title"),
		SiteName:        strPtr("Reader Site"),
		Author:          strPtr("Author"),
		MarkdownContent: strPtr("# Existing Content"),
		HighlightCount:  2,
	})
	if err != nil {
		t.Fatalf("beforeCrawl() error = %v", err)
	}
	if !handled {
		t.Fatal("beforeCrawl() handled = false, want true")
	}
	if !reflect.DeepEqual(events, []string{"finish:task-1", "enqueue:" + TypeAIProcess}) {
		t.Fatalf("events = %v, want finish before enqueue", events)
	}
	if len(articleRepo.updateStatusCalls) != 0 {
		t.Fatalf("UpdateStatus calls = %+v, want none", articleRepo.updateStatusCalls)
	}

	var payload AIProcessPayload
	if err := json.Unmarshal(enqueuer.enqueuedTasks[0].Payload(), &payload); err != nil {
		t.Fatalf("unmarshal AI payload: %v", err)
	}
	if payload.Title != "Highlighted Title" || payload.Markdown != "# Existing Content" || payload.Source != "Reader Site" || payload.Author != "Author" {
		t.Fatalf("AI payload = %+v, want highlighted article content", payload)
	}
}

func TestCrawlExistingContentRoute_BeforeCrawlMarksEmptyScreenshotReady(t *testing.T) {
	articleRepo := &mockCrawlArticleRepo{}
	taskRepo := &mockCrawlTaskRepo{}
	enqueuer := &mockCrawlEnqueuer{}
	route := crawlExistingContentRoute{
		articleRepo: articleRepo,
		aiHandoff:   crawlAIHandoff{taskRepo: taskRepo, asynqClient: enqueuer},
	}

	handled, err := route.beforeCrawl(context.Background(), existingContentTestPayload(), &domain.Article{
		ID:         "art-1",
		SourceType: domain.SourceScreenshot,
	})
	if err != nil {
		t.Fatalf("beforeCrawl() error = %v", err)
	}
	if !handled {
		t.Fatal("beforeCrawl() handled = false, want true")
	}
	if len(articleRepo.updateStatusCalls) != 1 || articleRepo.updateStatusCalls[0].Status != domain.ArticleStatusReady {
		t.Fatalf("UpdateStatus calls = %+v, want ready", articleRepo.updateStatusCalls)
	}
	if len(enqueuer.enqueuedTasks) != 0 {
		t.Fatalf("enqueued tasks = %d, want 0", len(enqueuer.enqueuedTasks))
	}
	if len(taskRepo.setCrawlFinishedCalls) != 0 {
		t.Fatalf("SetCrawlFinished calls = %v, want none", taskRepo.setCrawlFinishedCalls)
	}
}

func TestCrawlExistingContentRoute_AfterCacheMissRoutesClientContentToAI(t *testing.T) {
	events := []string{}
	articleRepo := &mockCrawlArticleRepo{}
	taskRepo := &mockCrawlTaskRepo{
		setCrawlFinishedFn: func(ctx context.Context, id string) error {
			events = append(events, "finish:"+id)
			return nil
		},
	}
	enqueuer := &mockCrawlEnqueuer{
		enqueueFn: func(ctx context.Context, task *asynq.Task, opts ...asynq.Option) (*asynq.TaskInfo, error) {
			events = append(events, "enqueue:"+task.Type())
			return &asynq.TaskInfo{}, nil
		},
	}
	route := crawlExistingContentRoute{
		articleRepo: articleRepo,
		aiHandoff:   crawlAIHandoff{taskRepo: taskRepo, asynqClient: enqueuer},
	}

	handled, err := route.afterCacheMiss(context.Background(), existingContentTestPayload(), &domain.Article{
		ID:              "art-1",
		Title:           strPtr("Client Title"),
		SiteName:        strPtr("Client Site"),
		Author:          strPtr("Client Author"),
		MarkdownContent: strPtr("# Client Content"),
	}, time.Now())
	if err != nil {
		t.Fatalf("afterCacheMiss() error = %v", err)
	}
	if !handled {
		t.Fatal("afterCacheMiss() handled = false, want true")
	}
	if !reflect.DeepEqual(events, []string{"enqueue:" + TypeAIProcess, "finish:task-1"}) {
		t.Fatalf("events = %v, want enqueue before finish", events)
	}

	var payload AIProcessPayload
	if err := json.Unmarshal(enqueuer.enqueuedTasks[0].Payload(), &payload); err != nil {
		t.Fatalf("unmarshal AI payload: %v", err)
	}
	if payload.Title != "Client Title" || payload.Markdown != "# Client Content" || payload.Source != "Client Site" || payload.Author != "Client Author" {
		t.Fatalf("AI payload = %+v, want client article content", payload)
	}
}

func TestCrawlExistingContentRoute_HighlightsWithoutContentAreNotHandled(t *testing.T) {
	articleRepo := &mockCrawlArticleRepo{}
	taskRepo := &mockCrawlTaskRepo{}
	enqueuer := &mockCrawlEnqueuer{}
	route := crawlExistingContentRoute{
		articleRepo: articleRepo,
		aiHandoff:   crawlAIHandoff{taskRepo: taskRepo, asynqClient: enqueuer},
	}

	handled, err := route.beforeCrawl(context.Background(), existingContentTestPayload(), &domain.Article{
		ID:             "art-1",
		HighlightCount: 1,
	})
	if err != nil {
		t.Fatalf("beforeCrawl() error = %v", err)
	}
	if handled {
		t.Fatal("beforeCrawl() handled = true, want false")
	}
	if len(articleRepo.updateStatusCalls) != 0 || len(enqueuer.enqueuedTasks) != 0 || len(taskRepo.setCrawlFinishedCalls) != 0 {
		t.Fatalf("unexpected side effects: statuses=%d enqueued=%d finished=%d",
			len(articleRepo.updateStatusCalls), len(enqueuer.enqueuedTasks), len(taskRepo.setCrawlFinishedCalls))
	}
}

func existingContentTestPayload() CrawlPayload {
	return CrawlPayload{
		ArticleID: "art-1",
		TaskID:    "task-1",
		URL:       "https://example.com/article",
		UserID:    "user-1",
	}
}
