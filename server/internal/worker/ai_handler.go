package worker

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"github.com/hibiken/asynq"

	"folio-server/internal/client"
	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

// analyzer abstracts the AI client for testing.
type analyzer interface {
	Analyze(ctx context.Context, req client.AnalyzeRequest) (*client.AnalyzeResponse, error)
}

// aiArticleRepo abstracts the article repository methods used by AIHandler.
type aiArticleRepo interface {
	GetByID(ctx context.Context, id string) (*domain.Article, error)
	UpdateAIResult(ctx context.Context, id string, ai repository.AIResult) error
	UpdateTitle(ctx context.Context, articleID string, title string) error
	UpdateStatus(ctx context.Context, id string, status domain.ArticleStatus) error
	SetError(ctx context.Context, id string, errMsg string) error
}

// aiTaskRepo abstracts the task repository methods used by AIHandler.
type aiTaskRepo interface {
	SetAIStarted(ctx context.Context, id string) error
	SetAIFinished(ctx context.Context, id string) error
	SetFailed(ctx context.Context, id string, errMsg string) error
}

// aiTagRepo abstracts the tag repository methods used by AIHandler.
type aiTagRepo interface {
	Create(ctx context.Context, userID, name string, isAIGenerated bool) (*domain.Tag, error)
	AttachToArticle(ctx context.Context, articleID, tagID string) error
}

// aiContentCacheRepo abstracts the content cache repository for AIHandler.
type aiContentCacheRepo interface {
	Upsert(ctx context.Context, cache *domain.ContentCache) error
}

type AIHandler struct {
	aiClient     analyzer
	articleRepo  aiArticleRepo
	taskRepo     aiTaskRepo
	categoryRepo *repository.CategoryRepo
	tagRepo      aiTagRepo
	cacheRepo    aiContentCacheRepo
}

func NewAIHandler(
	aiClient *client.AIClient,
	articleRepo *repository.ArticleRepo,
	taskRepo *repository.TaskRepo,
	categoryRepo *repository.CategoryRepo,
	tagRepo *repository.TagRepo,
	cacheRepo *repository.ContentCacheRepo,
) *AIHandler {
	return &AIHandler{
		aiClient:     aiClient,
		articleRepo:  articleRepo,
		taskRepo:     taskRepo,
		categoryRepo: categoryRepo,
		tagRepo:      tagRepo,
		cacheRepo:    cacheRepo,
	}
}

func (h *AIHandler) ProcessTask(ctx context.Context, t *asynq.Task) error {
	var p AIProcessPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("unmarshal ai payload: %w", err)
	}

	start := time.Now()

	// Mark AI started
	if err := h.taskRepo.SetAIStarted(ctx, p.TaskID); err != nil {
		return fmt.Errorf("set ai started: %w", err)
	}

	// Analyze
	result, err := h.aiClient.Analyze(ctx, client.AnalyzeRequest{
		Title:   p.Title,
		Content: p.Markdown,
		Source:  p.Source,
		Author:  p.Author,
	})
	if err != nil {
		slog.Error("ai task failed",
			"article_id", p.ArticleID,
			"error", err,
		)
		h.taskRepo.SetFailed(ctx, p.TaskID, err.Error())
		h.articleRepo.SetError(ctx, p.ArticleID, err.Error())
		h.articleRepo.UpdateStatus(ctx, p.ArticleID, domain.ArticleStatusFailed)
		return fmt.Errorf("ai analyze failed: %w", err)
	}

	// Ensure category exists (create if needed)
	cat, err := h.categoryRepo.FindOrCreate(ctx, result.Category, result.CategoryName, result.CategoryName)
	if err != nil {
		slog.Error("ai task failed to find/create category",
			"article_id", p.ArticleID,
			"slug", result.Category,
			"error", err,
		)
		h.taskRepo.SetFailed(ctx, p.TaskID, err.Error())
		return fmt.Errorf("find or create category: %w", err)
	}

	// Update article with AI results
	if err := h.articleRepo.UpdateAIResult(ctx, p.ArticleID, repository.AIResult{
		CategoryID: cat.ID,
		Summary:    result.Summary,
		KeyPoints:  result.KeyPoints,
		Confidence: result.Confidence,
		Language:   result.Language,
	}); err != nil {
		slog.Error("ai task failed to persist result",
			"article_id", p.ArticleID,
			"error", err,
		)
		h.taskRepo.SetFailed(ctx, p.TaskID, err.Error())
		return fmt.Errorf("update ai result: %w", err)
	}

	// Backfill title for manual entries that have no user-provided title
	article, err := h.articleRepo.GetByID(ctx, p.ArticleID)
	if err == nil && article != nil && (article.Title == nil || *article.Title == "") {
		var generatedTitle string
		if len(result.KeyPoints) > 0 {
			generatedTitle = result.KeyPoints[0]
		} else if result.Summary != "" {
			runes := []rune(result.Summary)
			if len(runes) > 50 {
				generatedTitle = string(runes[:50])
			} else {
				generatedTitle = result.Summary
			}
		}
		if generatedTitle != "" {
			if err := h.articleRepo.UpdateTitle(ctx, p.ArticleID, generatedTitle); err != nil {
				slog.Error("failed to backfill title", "article_id", p.ArticleID, "error", err)
			}
		}
	}

	// Create AI-generated tags and attach to article
	for _, tagName := range result.Tags {
		tag, err := h.tagRepo.Create(ctx, p.UserID, tagName, true)
		if err != nil {
			continue // Non-fatal
		}
		h.tagRepo.AttachToArticle(ctx, p.ArticleID, tag.ID) // Non-fatal
	}

	// Mark AI finished
	if err := h.taskRepo.SetAIFinished(ctx, p.TaskID); err != nil {
		return fmt.Errorf("set ai finished: %w", err)
	}

	slog.Info("ai task completed",
		"article_id", p.ArticleID,
		"duration_ms", time.Since(start).Milliseconds(),
	)

	// Write to content cache for cross-user reuse
	if h.cacheRepo != nil {
		article, err := h.articleRepo.GetByID(ctx, p.ArticleID)
		if err == nil && article != nil && article.URL != nil {
			markdown := derefOrEmpty(article.MarkdownContent)
			if domain.IsCacheWorthy(markdown, result.Confidence) {
				now := time.Now()
				h.cacheRepo.Upsert(ctx, &domain.ContentCache{
					URL:             *article.URL,
					Title:           article.Title,
					Author:          article.Author,
					SiteName:        article.SiteName,
					FaviconURL:      article.FaviconURL,
					CoverImageURL:   article.CoverImageURL,
					MarkdownContent: article.MarkdownContent,
					WordCount:       article.WordCount,
					Language:        article.Language,
					CategorySlug:    &result.Category,
					Summary:         &result.Summary,
					KeyPoints:       result.KeyPoints,
					AIConfidence:    &result.Confidence,
					AITagNames:      result.Tags,
					AIAnalyzedAt:    &now,
				}) // Non-fatal: cache write failure doesn't affect the article
			}
		}
	}

	return nil
}
