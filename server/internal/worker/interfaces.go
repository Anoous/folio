package worker

import (
	"context"

	"github.com/hibiken/asynq"

	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

// --- Article repository building blocks ---

// ArticleGetter reads articles by ID.
type ArticleGetter interface {
	GetByID(ctx context.Context, id string) (*domain.Article, error)
}

// ArticleStatusUpdater updates article status and errors.
type ArticleStatusUpdater interface {
	UpdateStatus(ctx context.Context, id string, status domain.ArticleStatus) error
	SetError(ctx context.Context, id string, errMsg string) error
}

// ArticleCrawlUpdater updates crawl results.
type ArticleCrawlUpdater interface {
	UpdateCrawlResult(ctx context.Context, id string, cr repository.CrawlResult) error
}

// ArticleAIUpdater updates AI results.
type ArticleAIUpdater interface {
	UpdateAIResult(ctx context.Context, id string, ai repository.AIResult) error
}

// ArticleTitleUpdater updates article title.
type ArticleTitleUpdater interface {
	UpdateTitle(ctx context.Context, articleID string, title string) error
}

// --- Task repository building blocks ---

// TaskCrawlTracker tracks crawl task lifecycle.
type TaskCrawlTracker interface {
	SetCrawlStarted(ctx context.Context, id string) error
	SetCrawlFinished(ctx context.Context, id string) error
}

// TaskAIStarter marks AI processing as started.
type TaskAIStarter interface {
	SetAIStarted(ctx context.Context, id string) error
}

// TaskAIFinisher marks AI processing as finished.
type TaskAIFinisher interface {
	SetAIFinished(ctx context.Context, id string) error
}

// TaskFailer marks a task as failed.
type TaskFailer interface {
	SetFailed(ctx context.Context, id string, errMsg string) error
}

// --- Other shared interfaces ---

// TagCreator creates tags and attaches them to articles.
type TagCreator interface {
	Create(ctx context.Context, userID, name string, isAIGenerated bool) (*domain.Tag, error)
	AttachToArticle(ctx context.Context, articleID, tagID string) error
}

// CategoryFinder finds or creates categories.
type CategoryFinder interface {
	FindOrCreate(ctx context.Context, slug, nameZH, nameEN string) (*domain.Category, error)
}

// ContentCacheReader reads content cache by URL.
type ContentCacheReader interface {
	GetByURL(ctx context.Context, url string) (*domain.ContentCache, error)
}

// ContentCacheWriter writes to content cache.
type ContentCacheWriter interface {
	Upsert(ctx context.Context, cache *domain.ContentCache) error
}

// Enqueuer abstracts the asynq client for enqueueing tasks.
type Enqueuer interface {
	EnqueueContext(ctx context.Context, task *asynq.Task, opts ...asynq.Option) (*asynq.TaskInfo, error)
}
