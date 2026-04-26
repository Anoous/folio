package service

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/hibiken/asynq"

	"folio-server/internal/client"
	"folio-server/internal/domain"
	"folio-server/internal/repository"
	"folio-server/internal/worker"
)

type queryExpander interface {
	ExpandQuery(ctx context.Context, question string) ([]string, error)
	RerankArticles(ctx context.Context, question string, candidates []client.RerankCandidate) ([]client.RerankResult, error)
}

type ArticleService struct {
	articleRepo       articleCreator
	taskRepo          taskCreator
	tagRepo           tagAttacher
	categoryRepo      categoryGetter
	quotaService      quotaChecker
	asynqClient       taskEnqueuer
	aiClient          queryExpander
	evidenceRepo      knowledgeDocumentLister
	evidenceRetriever knowledgeBroadRecaller
}

func NewArticleService(
	articleRepo *repository.ArticleRepo,
	taskRepo *repository.TaskRepo,
	tagRepo *repository.TagRepo,
	categoryRepo *repository.CategoryRepo,
	quotaService *QuotaService,
	asynqClient *asynq.Client,
	aiClient client.Analyzer,
) *ArticleService {
	return &ArticleService{
		articleRepo:       articleRepo,
		taskRepo:          taskRepo,
		tagRepo:           tagRepo,
		categoryRepo:      categoryRepo,
		quotaService:      quotaService,
		asynqClient:       asynqClient,
		aiClient:          aiClient,
		evidenceRepo:      articleRepo,
		evidenceRetriever: articleRepo,
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
	Content    string   `json:"content"`
	Title      *string  `json:"title,omitempty"`
	TagIDs     []string `json:"tag_ids,omitempty"`
	ClientID   *string  `json:"client_id,omitempty"`
	SourceType string   `json:"source_type,omitempty"`
}

func (s *ArticleService) SubmitURL(ctx context.Context, userID string, req SubmitURLRequest) (*SubmitURLResponse, error) {
	// Check for duplicate URL before consuming quota
	if exists, err := s.articleRepo.ExistsByUserAndURL(ctx, userID, req.URL); err != nil {
		return nil, fmt.Errorf("check duplicate: %w", err)
	} else if exists {
		slog.Debug("duplicate URL rejected", "user_id", userID, "url", req.URL)
		return nil, ErrDuplicateURL
	}

	// Detect source
	sourceType := DetectSource(req.URL)

	return s.submitIngestion(ctx, articleIngestion{
		userID: userID,
		createArticle: repository.CreateArticleParams{
			UserID:          userID,
			URL:             &req.URL,
			SourceType:      sourceType,
			Title:           req.Title,
			Author:          req.Author,
			SiteName:        req.SiteName,
			MarkdownContent: req.MarkdownContent,
			WordCount:       req.WordCount,
		},
		tagIDs:          req.TagIDs,
		taskURL:         &req.URL,
		sourceType:      sourceType,
		taskCreateLabel: "create task",
		enqueueLabel:    "enqueue crawl",
		buildTask: func(article *domain.Article, task *domain.CrawlTask) *asynq.Task {
			return worker.NewCrawlTask(article.ID, task.ID, req.URL, userID)
		},
		logSubmitted: func(article *domain.Article, task *domain.CrawlTask) {
			slog.Info("article submitted", "article_id", article.ID, "task_id", task.ID, "url", req.URL)
		},
	})
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

	// Compute word count
	wordCount := repository.CountWords(req.Content)

	// Resolve source type (default to manual if not provided)
	sourceType := domain.SourceType(req.SourceType)
	if sourceType == "" {
		sourceType = domain.SourceManual
	}

	title := ""
	if req.Title != nil {
		title = *req.Title
	}

	return s.submitIngestion(ctx, articleIngestion{
		userID: userID,
		createArticle: repository.CreateArticleParams{
			UserID:          userID,
			URL:             nil,
			SourceType:      sourceType,
			Title:           req.Title,
			MarkdownContent: &req.Content,
			WordCount:       &wordCount,
			ClientID:        req.ClientID,
		},
		tagIDs:          req.TagIDs,
		taskURL:         nil,
		sourceType:      sourceType,
		taskCreateLabel: "create task",
		enqueueLabel:    "enqueue ai process",
		buildTask: func(article *domain.Article, task *domain.CrawlTask) *asynq.Task {
			return worker.NewAIProcessTask(article.ID, task.ID, userID, title, req.Content, string(sourceType), "")
		},
		logSubmitted: func(article *domain.Article, task *domain.CrawlTask) {
			slog.Info("manual content submitted", "article_id", article.ID, "task_id", task.ID, "word_count", wordCount)
		},
	})
}

func (s *ArticleService) GetByID(ctx context.Context, userID, articleID string) (*domain.Article, error) {
	article, err := s.articleRepo.GetByID(ctx, articleID)
	if err != nil {
		return nil, err
	}
	if article == nil || article.DeletedAt != nil {
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
	if article == nil || article.DeletedAt != nil {
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
	if article == nil || article.DeletedAt != nil {
		return ErrNotFound
	}
	if article.UserID != userID {
		return ErrForbidden
	}
	return s.articleRepo.Delete(ctx, articleID, userID)
}

func (s *ArticleService) Search(ctx context.Context, userID, query string, page, perPage int) (*repository.ListArticlesResult, error) {
	return s.searchWorkflow().Search(ctx, userID, query, page, perPage)
}

// RetryArticle re-enqueues a failed article for processing.
func (s *ArticleService) RetryArticle(ctx context.Context, userID, articleID string) (*SubmitURLResponse, error) {
	article, err := s.articleRepo.GetByID(ctx, articleID)
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

	// Reset status
	if err := s.articleRepo.UpdateStatus(ctx, articleID, domain.ArticleStatusPending); err != nil {
		return nil, fmt.Errorf("reset status: %w", err)
	}

	// Create new task
	task, err := s.taskRepo.Create(ctx, repository.CreateTaskParams{
		ArticleID:  articleID,
		UserID:     userID,
		URL:        article.URL,
		SourceType: string(article.SourceType),
	})
	if err != nil {
		return nil, fmt.Errorf("create retry task: %w", err)
	}

	// Enqueue based on type
	if article.URL != nil && *article.URL != "" {
		crawlTask := worker.NewCrawlTask(articleID, task.ID, *article.URL, userID)
		if _, err := s.asynqClient.EnqueueContext(ctx, crawlTask); err != nil {
			return nil, fmt.Errorf("enqueue retry crawl: %w", err)
		}
	} else {
		content := ""
		if article.MarkdownContent != nil {
			content = *article.MarkdownContent
		}
		title := ""
		if article.Title != nil {
			title = *article.Title
		}
		aiTask := worker.NewAIProcessTask(articleID, task.ID, userID, title, content, string(article.SourceType), "")
		if _, err := s.asynqClient.EnqueueContext(ctx, aiTask); err != nil {
			return nil, fmt.Errorf("enqueue retry ai: %w", err)
		}
	}

	slog.Info("article retry enqueued", "article_id", articleID, "task_id", task.ID)

	return &SubmitURLResponse{ArticleID: articleID, TaskID: task.ID}, nil
}

// SemanticSearch does LLM-powered search: expand query → broad recall → LLM rerank.
func (s *ArticleService) SemanticSearch(ctx context.Context, userID, question string, page, perPage int) (*repository.ListArticlesResult, error) {
	return s.searchWorkflow().SemanticSearch(ctx, userID, question, page, perPage)
}
