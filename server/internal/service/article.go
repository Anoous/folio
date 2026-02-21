package service

import (
	"context"
	"fmt"

	"github.com/hibiken/asynq"

	"folio-server/internal/domain"
	"folio-server/internal/repository"
	"folio-server/internal/worker"
)

type ArticleService struct {
	articleRepo  *repository.ArticleRepo
	taskRepo     *repository.TaskRepo
	tagRepo      *repository.TagRepo
	categoryRepo *repository.CategoryRepo
	quotaService *QuotaService
	asynqClient  *asynq.Client
}

func NewArticleService(
	articleRepo *repository.ArticleRepo,
	taskRepo *repository.TaskRepo,
	tagRepo *repository.TagRepo,
	categoryRepo *repository.CategoryRepo,
	quotaService *QuotaService,
	asynqClient *asynq.Client,
) *ArticleService {
	return &ArticleService{
		articleRepo:  articleRepo,
		taskRepo:     taskRepo,
		tagRepo:      tagRepo,
		categoryRepo: categoryRepo,
		quotaService: quotaService,
		asynqClient:  asynqClient,
	}
}

type SubmitURLRequest struct {
	URL    string   `json:"url"`
	TagIDs []string `json:"tag_ids,omitempty"`
}

type SubmitURLResponse struct {
	ArticleID string `json:"article_id"`
	TaskID    string `json:"task_id"`
}

func (s *ArticleService) SubmitURL(ctx context.Context, userID string, req SubmitURLRequest) (*SubmitURLResponse, error) {
	// Check quota
	if err := s.quotaService.CheckAndIncrement(ctx, userID); err != nil {
		return nil, err
	}

	// Detect source
	sourceType := DetectSource(req.URL)

	// Create article
	article, err := s.articleRepo.Create(ctx, repository.CreateArticleParams{
		UserID:     userID,
		URL:        req.URL,
		SourceType: sourceType,
	})
	if err != nil {
		return nil, fmt.Errorf("create article: %w", err)
	}

	// Attach user-provided tags
	for _, tagID := range req.TagIDs {
		if err := s.tagRepo.AttachToArticle(ctx, article.ID, tagID); err != nil {
			// Non-fatal: log and continue
			continue
		}
	}

	// Create crawl task
	task, err := s.taskRepo.Create(ctx, repository.CreateTaskParams{
		ArticleID:  article.ID,
		UserID:     userID,
		URL:        req.URL,
		SourceType: string(sourceType),
	})
	if err != nil {
		return nil, fmt.Errorf("create task: %w", err)
	}

	// Enqueue async crawl
	crawlTask := worker.NewCrawlTask(article.ID, task.ID, req.URL, userID)
	if _, err := s.asynqClient.EnqueueContext(ctx, crawlTask); err != nil {
		return nil, fmt.Errorf("enqueue crawl: %w", err)
	}

	return &SubmitURLResponse{
		ArticleID: article.ID,
		TaskID:    task.ID,
	}, nil
}

func (s *ArticleService) GetByID(ctx context.Context, userID, articleID string) (*domain.Article, error) {
	article, err := s.articleRepo.GetByID(ctx, articleID)
	if err != nil {
		return nil, err
	}
	if article == nil {
		return nil, ErrNotFound
	}
	if article.UserID != userID {
		return nil, ErrForbidden
	}

	// Load category
	if article.CategoryID != nil {
		cat, err := s.categoryRepo.GetByID(ctx, *article.CategoryID)
		if err == nil && cat != nil {
			article.Category = cat
		}
	}

	// Load tags
	tags, err := s.tagRepo.GetByArticle(ctx, articleID)
	if err == nil {
		article.Tags = tags
	}

	return article, nil
}

func (s *ArticleService) ListByUser(ctx context.Context, params repository.ListArticlesParams) (*repository.ListArticlesResult, error) {
	return s.articleRepo.ListByUser(ctx, params)
}

func (s *ArticleService) Update(ctx context.Context, userID, articleID string, params repository.UpdateArticleParams) error {
	article, err := s.articleRepo.GetByID(ctx, articleID)
	if err != nil {
		return err
	}
	if article == nil {
		return ErrNotFound
	}
	if article.UserID != userID {
		return ErrForbidden
	}
	return s.articleRepo.Update(ctx, articleID, params)
}

func (s *ArticleService) Delete(ctx context.Context, userID, articleID string) error {
	article, err := s.articleRepo.GetByID(ctx, articleID)
	if err != nil {
		return err
	}
	if article == nil {
		return ErrNotFound
	}
	if article.UserID != userID {
		return ErrForbidden
	}
	return s.articleRepo.Delete(ctx, articleID)
}

func (s *ArticleService) Search(ctx context.Context, userID, query string, page, perPage int) (*repository.ListArticlesResult, error) {
	return s.articleRepo.SearchByTitle(ctx, userID, query, page, perPage)
}
