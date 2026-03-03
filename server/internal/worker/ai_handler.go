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

type AIHandler struct {
	aiClient     *client.AIClient
	articleRepo  *repository.ArticleRepo
	taskRepo     *repository.TaskRepo
	categoryRepo *repository.CategoryRepo
	tagRepo      *repository.TagRepo
	cacheRepo    *repository.ContentCacheRepo
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

	// Update article with AI results
	if err := h.articleRepo.UpdateAIResult(ctx, p.ArticleID, repository.AIResult{
		CategorySlug: result.Category,
		Summary:      result.Summary,
		KeyPoints:    result.KeyPoints,
		Confidence:   result.Confidence,
		Language:     result.Language,
	}); err != nil {
		slog.Error("ai task failed to persist result",
			"article_id", p.ArticleID,
			"error", err,
		)
		h.taskRepo.SetFailed(ctx, p.TaskID, err.Error())
		return fmt.Errorf("update ai result: %w", err)
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
		if err == nil && article != nil {
			markdown := derefOrEmpty(article.MarkdownContent)
			if domain.IsCacheWorthy(markdown, result.Confidence) {
				now := time.Now()
				h.cacheRepo.Upsert(ctx, &domain.ContentCache{
					URL:             article.URL,
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
