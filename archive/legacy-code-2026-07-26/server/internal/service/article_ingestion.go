package service

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/hibiken/asynq"

	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

type articleIngestion struct {
	userID          string
	createArticle   repository.CreateArticleParams
	tagIDs          []string
	taskURL         *string
	sourceType      domain.SourceType
	buildTask       func(article *domain.Article, task *domain.CrawlTask) *asynq.Task
	taskCreateLabel string
	enqueueLabel    string
	logSubmitted    func(article *domain.Article, task *domain.CrawlTask)
}

func (s *ArticleService) submitIngestion(ctx context.Context, in articleIngestion) (*SubmitURLResponse, error) {
	if err := s.quotaService.CheckAndIncrement(ctx, in.userID); err != nil {
		return nil, err
	}
	rollbackQuota := func() {
		_ = s.quotaService.DecrementQuota(ctx, in.userID)
	}

	article, err := s.articleRepo.Create(ctx, in.createArticle)
	if err != nil {
		rollbackQuota()
		return nil, fmt.Errorf("create article: %w", err)
	}

	for _, tagID := range in.tagIDs {
		if err := s.tagRepo.AttachToArticle(ctx, article.ID, tagID); err != nil {
			slog.Error("failed to attach tag", "article_id", article.ID, "tag_id", tagID, "error", err)
			continue
		}
	}

	task, err := s.taskRepo.Create(ctx, repository.CreateTaskParams{
		ArticleID:  article.ID,
		UserID:     in.userID,
		URL:        in.taskURL,
		SourceType: string(in.sourceType),
	})
	if err != nil {
		rollbackQuota()
		return nil, fmt.Errorf("%s: %w", in.taskCreateLabel, err)
	}

	if _, err := s.asynqClient.EnqueueContext(ctx, in.buildTask(article, task)); err != nil {
		rollbackQuota()
		return nil, fmt.Errorf("%s: %w", in.enqueueLabel, err)
	}

	if in.logSubmitted != nil {
		in.logSubmitted(article, task)
	}

	return &SubmitURLResponse{
		ArticleID: article.ID,
		TaskID:    task.ID,
	}, nil
}
