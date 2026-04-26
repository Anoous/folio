package service

import (
	"context"
	"fmt"
	"log/slog"
	"strings"

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

	// Resolve source type (default to manual if not provided)
	sourceType := domain.SourceType(req.SourceType)
	if sourceType == "" {
		sourceType = domain.SourceManual
	}

	// Create article
	article, err := s.articleRepo.Create(ctx, repository.CreateArticleParams{
		UserID:          userID,
		URL:             nil,
		SourceType:      sourceType,
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
		SourceType: string(sourceType),
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
	aiTask := worker.NewAIProcessTask(article.ID, task.ID, userID, title, req.Content, string(sourceType), "")
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
	result, err := s.articleRepo.Search(ctx, userID, query, page, perPage)
	if err != nil {
		return nil, err
	}
	trimmedQuery := strings.TrimSpace(query)
	if result.Total > 0 {
		s.attachEvidenceSnippets(ctx, userID, trimmedQuery, result.Articles)
		return result, nil
	}
	if trimmedQuery == "" {
		return result, nil
	}
	return s.searchWithEvidence(ctx, userID, trimmedQuery, page, perPage)
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
	candidates, err := s.searchEvidenceCandidates(ctx, userID, question, 50)
	if err != nil || len(candidates) == 0 {
		slog.Warn("semantic search: evidence retrieval failed, falling back to keyword", "error", err)
		return s.Search(ctx, userID, question, page, perPage)
	}

	// 2. LLM rerank
	rerankCandidates := make([]client.RerankCandidate, len(candidates))
	for i, a := range candidates {
		summary := ""
		if a.Summary != nil {
			summary = *a.Summary
		}
		title := ""
		if a.Title != nil {
			title = *a.Title
		}
		rerankCandidates[i] = client.RerankCandidate{
			Index:     i + 1,
			Title:     title,
			Summary:   summary,
			KeyPoints: a.KeyPoints,
		}
	}

	ranked, err := s.aiClient.RerankArticles(ctx, question, rerankCandidates)
	if err != nil {
		slog.Warn("semantic search: rerank failed, returning recall order", "error", err)
		return paginateArticleResults(candidates, page, perPage), nil
	}

	// 3. Map ranked indices back
	reranked := make([]domain.Article, 0, len(ranked))
	for _, r := range ranked {
		idx := r.Index - 1
		if idx >= 0 && idx < len(candidates) {
			reranked = append(reranked, candidates[idx])
		}
	}

	return paginateArticleResults(reranked, page, perPage), nil
}

func (s *ArticleService) searchWithEvidence(ctx context.Context, userID, query string, page, perPage int) (*repository.ListArticlesResult, error) {
	candidates, err := s.searchEvidenceCandidates(ctx, userID, query, max(page*perPage, 20))
	if err != nil {
		return nil, err
	}
	if len(candidates) == 0 {
		return &repository.ListArticlesResult{Articles: []domain.Article{}, Total: 0}, nil
	}
	return paginateArticleResults(candidates, page, perPage), nil
}

func (s *ArticleService) searchEvidenceCandidates(ctx context.Context, userID, query string, limit int) ([]domain.Article, error) {
	contextResult, err := s.retrieveEvidenceContext(ctx, userID, query, limit)
	if err != nil {
		return nil, err
	}
	if contextResult == nil || contextResult.Insufficient || len(contextResult.Sources) == 0 {
		return nil, nil
	}

	articles := make([]domain.Article, 0, len(contextResult.Sources))
	for _, source := range contextResult.Sources {
		article, err := s.articleRepo.GetByID(ctx, source.ArticleID)
		if err != nil {
			return nil, fmt.Errorf("get evidence article %s: %w", source.ArticleID, err)
		}
		if article == nil || article.DeletedAt != nil || article.UserID != userID {
			continue
		}
		article.SearchSnippet = source.EvidenceSnippet
		articles = append(articles, *article)
	}

	return articles, nil
}

func (s *ArticleService) attachEvidenceSnippets(ctx context.Context, userID, query string, articles []domain.Article) {
	if len(articles) == 0 || strings.TrimSpace(query) == "" {
		return
	}

	articleIndex := make(map[string]int, len(articles))
	for idx, article := range articles {
		articleIndex[article.ID] = idx
	}

	contextResult, err := s.retrieveEvidenceContext(ctx, userID, query, max(len(articles)*2, 20))
	if err != nil {
		slog.Warn("search: evidence snippet retrieval failed", "error", err)
		return
	}
	if contextResult == nil || contextResult.Insufficient {
		return
	}

	for _, source := range contextResult.Sources {
		idx, ok := articleIndex[source.ArticleID]
		if !ok {
			continue
		}
		articles[idx].SearchSnippet = source.EvidenceSnippet
	}
}

func (s *ArticleService) retrieveEvidenceContext(ctx context.Context, userID, query string, limit int) (*EvidenceContext, error) {
	if s.evidenceRepo == nil {
		return nil, nil
	}

	evidenceService := NewEvidenceService(s.evidenceRepo, s.aiClient, s.evidenceRetriever)
	return evidenceService.Retrieve(ctx, userID, query, EvidenceRetrieveOptions{
		MaxSources: max(limit, 20),
	})
}

func paginateArticleResults(articles []domain.Article, page, perPage int) *repository.ListArticlesResult {
	total := len(articles)
	start := (page - 1) * perPage
	end := start + perPage
	if start > total {
		start = total
	}
	if end > total {
		end = total
	}
	return &repository.ListArticlesResult{
		Articles: articles[start:end],
		Total:    total,
	}
}
