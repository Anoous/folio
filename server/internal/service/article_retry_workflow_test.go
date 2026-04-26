package service

import (
	"context"
	"encoding/json"
	"testing"

	"folio-server/internal/domain"
	"folio-server/internal/worker"
)

func TestArticleRetryWorkflow_WebArticleEnqueuesCrawl(t *testing.T) {
	url := "https://example.com/article"
	articleRepo := &mockArticleRepo{
		getByIDFn: func(ctx context.Context, id string) (*domain.Article, error) {
			return &domain.Article{
				ID:         "article-1",
				UserID:     "user-1",
				URL:        &url,
				SourceType: domain.SourceWeb,
				Status:     domain.ArticleStatusFailed,
			}, nil
		},
	}
	taskRepo := &mockTaskRepo{}
	enqueuer := &mockEnqueuer{}
	workflow := articleRetryWorkflow{
		articleRepo: articleRepo,
		taskRepo:    taskRepo,
		asynqClient: enqueuer,
	}

	resp, err := workflow.Retry(context.Background(), "user-1", "article-1")
	if err != nil {
		t.Fatalf("Retry() error = %v", err)
	}
	if resp.ArticleID != "article-1" || resp.TaskID != "task-123" {
		t.Fatalf("response = %+v, want article/task IDs", resp)
	}
	if len(articleRepo.updateStatusCalls) != 1 || articleRepo.updateStatusCalls[0].Status != domain.ArticleStatusPending {
		t.Fatalf("UpdateStatus calls = %+v, want pending", articleRepo.updateStatusCalls)
	}
	if taskRepo.lastCreateP == nil || taskRepo.lastCreateP.URL == nil || *taskRepo.lastCreateP.URL != url {
		t.Fatalf("task create params = %+v, want retry URL", taskRepo.lastCreateP)
	}
	if len(enqueuer.enqueuedTasks) != 1 || enqueuer.enqueuedTasks[0].Type() != worker.TypeCrawlArticle {
		t.Fatalf("enqueued tasks = %+v, want crawl task", enqueuer.enqueuedTasks)
	}

	var payload worker.CrawlPayload
	if err := json.Unmarshal(enqueuer.enqueuedTasks[0].Payload(), &payload); err != nil {
		t.Fatalf("unmarshal crawl payload: %v", err)
	}
	if payload.URL != url || payload.ArticleID != "article-1" || payload.UserID != "user-1" {
		t.Fatalf("crawl payload = %+v, want retry article URL", payload)
	}
}

func TestArticleRetryWorkflow_ContentArticleEnqueuesAI(t *testing.T) {
	title := "Manual title"
	content := "# Manual content"
	articleRepo := &mockArticleRepo{
		getByIDFn: func(ctx context.Context, id string) (*domain.Article, error) {
			return &domain.Article{
				ID:              "article-1",
				UserID:          "user-1",
				SourceType:      domain.SourceManual,
				Status:          domain.ArticleStatusFailed,
				Title:           &title,
				MarkdownContent: &content,
			}, nil
		},
	}
	taskRepo := &mockTaskRepo{}
	enqueuer := &mockEnqueuer{}
	workflow := articleRetryWorkflow{
		articleRepo: articleRepo,
		taskRepo:    taskRepo,
		asynqClient: enqueuer,
	}

	_, err := workflow.Retry(context.Background(), "user-1", "article-1")
	if err != nil {
		t.Fatalf("Retry() error = %v", err)
	}
	if len(enqueuer.enqueuedTasks) != 1 || enqueuer.enqueuedTasks[0].Type() != worker.TypeAIProcess {
		t.Fatalf("enqueued tasks = %+v, want AI task", enqueuer.enqueuedTasks)
	}

	var payload worker.AIProcessPayload
	if err := json.Unmarshal(enqueuer.enqueuedTasks[0].Payload(), &payload); err != nil {
		t.Fatalf("unmarshal AI payload: %v", err)
	}
	if payload.Title != title || payload.Markdown != content || payload.Source != string(domain.SourceManual) {
		t.Fatalf("AI payload = %+v, want manual content", payload)
	}
}
