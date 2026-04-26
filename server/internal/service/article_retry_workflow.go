package service

import (
	"context"
	"fmt"
	"log/slog"

	"folio-server/internal/domain"
	"folio-server/internal/repository"
	"folio-server/internal/worker"
)

type articleRetryWorkflow struct {
	articleRepo articleCreator
	taskRepo    taskCreator
	asynqClient taskEnqueuer
}

func (s *ArticleService) retryWorkflow() articleRetryWorkflow {
	return articleRetryWorkflow{
		articleRepo: s.articleRepo,
		taskRepo:    s.taskRepo,
		asynqClient: s.asynqClient,
	}
}

func (w articleRetryWorkflow) Retry(ctx context.Context, userID, articleID string) (*SubmitURLResponse, error) {
	article, err := w.articleRepo.GetByID(ctx, articleID)
	if err != nil {
		return nil, fmt.Errorf("get article: %w", err)
	}
	if article == nil || article.DeletedAt != nil {
		return nil, ErrNotFound
	}
	if article.UserID != userID {
		return nil, ErrForbidden
	}
	if article.Status != domain.ArticleStatusFailed {
		return nil, fmt.Errorf("article not in failed state")
	}

	if err := w.articleRepo.UpdateStatus(ctx, articleID, domain.ArticleStatusPending); err != nil {
		return nil, fmt.Errorf("reset status: %w", err)
	}

	task, err := w.taskRepo.Create(ctx, repository.CreateTaskParams{
		ArticleID:  articleID,
		UserID:     userID,
		URL:        article.URL,
		SourceType: string(article.SourceType),
	})
	if err != nil {
		return nil, fmt.Errorf("create retry task: %w", err)
	}

	if err := w.enqueueRetryTask(ctx, userID, article, task); err != nil {
		return nil, err
	}

	slog.Info("article retry enqueued", "article_id", articleID, "task_id", task.ID)
	return &SubmitURLResponse{ArticleID: articleID, TaskID: task.ID}, nil
}

func (w articleRetryWorkflow) enqueueRetryTask(ctx context.Context, userID string, article *domain.Article, task *domain.CrawlTask) error {
	if article.URL != nil && *article.URL != "" {
		crawlTask := worker.NewCrawlTask(article.ID, task.ID, *article.URL, userID)
		if _, err := w.asynqClient.EnqueueContext(ctx, crawlTask); err != nil {
			return fmt.Errorf("enqueue retry crawl: %w", err)
		}
		return nil
	}

	content := derefArticleString(article.MarkdownContent)
	title := derefArticleString(article.Title)
	aiTask := worker.NewAIProcessTask(article.ID, task.ID, userID, title, content, string(article.SourceType), "")
	if _, err := w.asynqClient.EnqueueContext(ctx, aiTask); err != nil {
		return fmt.Errorf("enqueue retry ai: %w", err)
	}
	return nil
}

func derefArticleString(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}
