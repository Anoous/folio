package service

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/hibiken/asynq"

	"folio-server/internal/domain"
	"folio-server/internal/repository"
	"folio-server/internal/worker"
)

type ArticleService struct {
	articleRepo  articleCreator
	taskRepo     taskCreator
	tagRepo      tagAttacher
	categoryRepo categoryGetter
	quotaService quotaChecker
	asynqClient  taskEnqueuer
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
	URL             string   `json:"url"`
	TagIDs          []string `json:"tag_ids,omitempty"`
	Title           *string  `json:"title,omitempty"`
	Author          *string  `json:"author,omitempty"`
	SiteName        *string  `json:"site_name,omitempty"`
	MarkdownContent *string  `json:"markdown_content,omitempty"`
	WordCount       *int     `json:"word_count,omitempty"`
}

type SubmitURLResponse struct {
	ArticleID string `json:"article_id"`
	TaskID    string `json:"task_id"`
}

type SubmitManualContentRequest struct {
	Content  string   `json:"content"`
	Title    *string  `json:"title,omitempty"`
	TagIDs   []string `json:"tag_ids,omitempty"`
	ClientID *string  `json:"client_id,omitempty"`
}

func (s *ArticleService) SubmitURL(ctx context.Context, userID string, req SubmitURLRequest) (*SubmitURLResponse, error) {
	// Check for duplicate URL before consuming quota
	if exists, err := s.articleRepo.ExistsByUserAndURL(ctx, userID, req.URL); err != nil {
		return nil, fmt.Errorf("check duplicate: %w", err)
	} else if exists {
		slog.Debug("duplicate URL rejected", "user_id", userID, "url", req.URL)
		return nil, ErrDuplicateURL
	}

	// Check quota
	if err := s.quotaService.CheckAndIncrement(ctx, userID); err != nil {
		return nil, err
	}

	// Detect source
	sourceType := DetectSource(req.URL)

	// Create article
	article, err := s.articleRepo.Create(ctx, repository.CreateArticleParams{
		UserID:          userID,
		URL:             &req.URL,
		SourceType:      sourceType,
		Title:           req.Title,
		Author:          req.Author,
		SiteName:        req.SiteName,
		MarkdownContent: req.MarkdownContent,
		WordCount:       req.WordCount,
	})
	if err != nil {
		// Rollback quota on creation failure
		_ = s.quotaService.DecrementQuota(ctx, userID)
		return nil, fmt.Errorf("create article: %w", err)
	}

	// Attach user-provided tags
	for _, tagID := range req.TagIDs {
		if err := s.tagRepo.AttachToArticle(ctx, article.ID, tagID); err != nil {
			slog.Error("failed to attach tag", "article_id", article.ID, "tag_id", tagID, "error", err)
			continue
		}
	}

	// Create crawl task
	task, err := s.taskRepo.Create(ctx, repository.CreateTaskParams{
		ArticleID:  article.ID,
		UserID:     userID,
		URL:        &req.URL,
		SourceType: string(sourceType),
	})
	if err != nil {
		_ = s.quotaService.DecrementQuota(ctx, userID)
		return nil, fmt.Errorf("create task: %w", err)
	}

	// Enqueue async crawl
	crawlTask := worker.NewCrawlTask(article.ID, task.ID, req.URL, userID)
	if _, err := s.asynqClient.EnqueueContext(ctx, crawlTask); err != nil {
		_ = s.quotaService.DecrementQuota(ctx, userID)
		return nil, fmt.Errorf("enqueue crawl: %w", err)
	}

	slog.Info("article submitted", "article_id", article.ID, "task_id", task.ID, "url", req.URL)

	return &SubmitURLResponse{
		ArticleID: article.ID,
		TaskID:    task.ID,
	}, nil
}

func (s *ArticleService) SubmitManualContent(ctx context.Context, userID string, req SubmitManualContentRequest) (*SubmitURLResponse, error) {
	// Check for duplicate by client_id
	if req.ClientID != nil && *req.ClientID != "" {
		if exists, err := s.articleRepo.ExistsByUserAndClientID(ctx, userID, *req.ClientID); err != nil {
			return nil, fmt.Errorf("check duplicate: %w", err)
		} else if exists {
			slog.Debug("duplicate manual content rejected", "user_id", userID, "client_id", *req.ClientID)
			return nil, ErrDuplicateURL
		}
	}

	// Check quota
	if err := s.quotaService.CheckAndIncrement(ctx, userID); err != nil {
		return nil, err
	}

	// Compute word count
	wordCount := repository.CountWords(req.Content)

	// Create article
	article, err := s.articleRepo.Create(ctx, repository.CreateArticleParams{
		UserID:          userID,
		URL:             nil,
		SourceType:      domain.SourceManual,
		Title:           req.Title,
		MarkdownContent: &req.Content,
		WordCount:       &wordCount,
		ClientID:        req.ClientID,
	})
	if err != nil {
		_ = s.quotaService.DecrementQuota(ctx, userID)
		return nil, fmt.Errorf("create article: %w", err)
	}

	// Attach user-provided tags
	for _, tagID := range req.TagIDs {
		if err := s.tagRepo.AttachToArticle(ctx, article.ID, tagID); err != nil {
			slog.Error("failed to attach tag", "article_id", article.ID, "tag_id", tagID, "error", err)
			continue
		}
	}

	// Create task for AI processing
	task, err := s.taskRepo.Create(ctx, repository.CreateTaskParams{
		ArticleID:  article.ID,
		UserID:     userID,
		URL:        nil,
		SourceType: string(domain.SourceManual),
	})
	if err != nil {
		_ = s.quotaService.DecrementQuota(ctx, userID)
		return nil, fmt.Errorf("create task: %w", err)
	}

	// Enqueue AI processing directly (no crawl needed for manual content)
	title := ""
	if req.Title != nil {
		title = *req.Title
	}
	aiTask := worker.NewAIProcessTask(article.ID, task.ID, userID, title, req.Content, string(domain.SourceManual), "")
	if _, err := s.asynqClient.EnqueueContext(ctx, aiTask); err != nil {
		_ = s.quotaService.DecrementQuota(ctx, userID)
		return nil, fmt.Errorf("enqueue ai process: %w", err)
	}

	slog.Info("manual content submitted", "article_id", article.ID, "task_id", task.ID, "word_count", wordCount)

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
	return s.articleRepo.Update(ctx, articleID, userID, params)
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
	return s.articleRepo.Delete(ctx, articleID, userID)
}

func (s *ArticleService) Search(ctx context.Context, userID, query string, page, perPage int) (*repository.ListArticlesResult, error) {
	return s.articleRepo.Search(ctx, userID, query, page, perPage)
}
