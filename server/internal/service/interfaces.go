package service

import (
	"context"

	"github.com/hibiken/asynq"

	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

// articleCreator is the subset of ArticleRepo used by ArticleService for creating articles.
type articleCreator interface {
	Create(ctx context.Context, p repository.CreateArticleParams) (*domain.Article, error)
	GetByID(ctx context.Context, id string) (*domain.Article, error)
	ListByUser(ctx context.Context, p repository.ListArticlesParams) (*repository.ListArticlesResult, error)
	Update(ctx context.Context, id string, p repository.UpdateArticleParams) error
	Delete(ctx context.Context, id string) error
	SearchByTitle(ctx context.Context, userID, query string, page, perPage int) (*repository.ListArticlesResult, error)
}

// taskCreator is the subset of TaskRepo used by ArticleService.
type taskCreator interface {
	Create(ctx context.Context, p repository.CreateTaskParams) (*domain.CrawlTask, error)
}

// tagAttacher is the subset of TagRepo used by ArticleService.
type tagAttacher interface {
	AttachToArticle(ctx context.Context, articleID, tagID string) error
	GetByArticle(ctx context.Context, articleID string) ([]domain.Tag, error)
}

// categoryGetter is the subset of CategoryRepo used by ArticleService.
type categoryGetter interface {
	GetByID(ctx context.Context, id string) (*domain.Category, error)
}

// quotaChecker is the subset of QuotaService used by ArticleService.
type quotaChecker interface {
	CheckAndIncrement(ctx context.Context, userID string) error
}

// taskEnqueuer abstracts the asynq.Client for enqueueing tasks.
type taskEnqueuer interface {
	EnqueueContext(ctx context.Context, task *asynq.Task, opts ...asynq.Option) (*asynq.TaskInfo, error)
}
