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
	"folio-server/internal/pipeline"
	"folio-server/internal/repository"
)

// analyzer abstracts the AI client for testing.
type analyzer interface {
	Analyze(ctx context.Context, req client.AnalyzeRequest) (*client.AnalyzeResponse, error)
}

type AIHandler struct {
	aiClient    analyzer
	articleRepo interface {
		ArticleGetter
		ArticleAIUpdater
		ArticleTitleUpdater
		ArticleStatusUpdater
	}
	taskRepo interface {
		TaskAIStarter
		TaskAIFinisher
		TaskFailer
	}
	categoryRepo CategoryFinder
	tagRepo      TagCreator
	cacheRepo    ContentCacheWriter
	asynqClient  Enqueuer
}

func NewAIHandler(
	aiClient client.Analyzer,
	articleRepo *repository.ArticleRepo,
	taskRepo *repository.TaskRepo,
	categoryRepo *repository.CategoryRepo,
	tagRepo *repository.TagRepo,
	cacheRepo *repository.ContentCacheRepo,
	asynqClient *asynq.Client,
) *AIHandler {
	return &AIHandler{
		aiClient:     aiClient,
		articleRepo:  articleRepo,
		taskRepo:     taskRepo,
		categoryRepo: categoryRepo,
		tagRepo:      tagRepo,
		cacheRepo:    cacheRepo,
		asynqClient:  asynqClient,
	}
}

func (h *AIHandler) ProcessTask(ctx context.Context, t *asynq.Task) error {
	var p AIProcessPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("unmarshal ai payload: %w", err)
	}

	// Check if AI already processed (dedup for crash-retry scenarios).
	// Return nil without calling SetAIFinished — SetAIStarted was never
	// called, so skipping both keeps the state machine consistent.  The task
	// was already marked done by the original successful run.
	article, err := h.articleRepo.GetByID(ctx, p.ArticleID)
	if err == nil && article != nil && article.Summary != nil && *article.Summary != "" {
		slog.Info("ai: article already analyzed, skipping", "article_id", p.ArticleID)
		return nil
	}

	start := time.Now()

	// Mark AI started
	if err := h.taskRepo.SetAIStarted(ctx, p.TaskID); err != nil {
		return fmt.Errorf("set ai started: %w", err)
	}

	logPipelineStarted(pipeline.StageAIAnalyze, pipeline.ProviderDeepSeek, p.TaskID, p.ArticleID, p.UserID, "")

	// Analyze
	result, err := h.aiClient.Analyze(ctx, client.AnalyzeRequest{
		Title:   p.Title,
		Content: p.Markdown,
		Source:  p.Source,
		Author:  p.Author,
	})
	if err != nil {
		failureErr := ensurePipelineErr(pipeline.StageAIAnalyze, pipeline.ProviderDeepSeek, false, "analyze article", err)
		logPipelineFailed(pipeline.StageAIAnalyze, pipeline.ProviderDeepSeek, p.TaskID, p.ArticleID, p.UserID, "", time.Since(start), failureErr)
		h.taskRepo.SetFailed(ctx, p.TaskID, buildTaskFailure(failureErr, time.Since(start)))
		h.articleRepo.SetError(ctx, p.ArticleID, failureErr.Error())
		// Content was already crawled successfully — mark as ready so the
		// article remains readable.  Only the AI enrichment (summary, tags,
		// category) is missing.
		h.articleRepo.UpdateStatus(ctx, p.ArticleID, domain.ArticleStatusReady)
		return nil
	}

	// Ensure category exists (create if needed)
	cat, err := h.categoryRepo.FindOrCreate(ctx, result.Category, result.CategoryName, result.CategoryName)
	if err != nil {
		slog.Warn("ai: category creation failed, falling back to 'other'",
			"article_id", p.ArticleID,
			"slug", result.Category,
			"error", err,
		)
		cat, err = h.categoryRepo.FindOrCreate(ctx, "other", "其他", "Other")
		if err != nil {
			// Both primary and fallback category creation failed.
			// Mark task failed AND article as ready (content is still readable).
			failureErr := ensurePipelineErr(pipeline.StageAIAnalyze, pipeline.ProviderDeepSeek, true, "persist ai category", err)
			logPipelineFailed(pipeline.StageAIAnalyze, pipeline.ProviderDeepSeek, p.TaskID, p.ArticleID, p.UserID, "", time.Since(start), failureErr)
			h.taskRepo.SetFailed(ctx, p.TaskID, buildTaskFailure(failureErr, time.Since(start)))
			h.articleRepo.UpdateStatus(ctx, p.ArticleID, domain.ArticleStatusReady)
			return fmt.Errorf("create fallback category: %w", err)
		}
	}

	// Update article with AI results
	if err := h.articleRepo.UpdateAIResult(ctx, p.ArticleID, repository.AIResult{
		CategoryID:       cat.ID,
		Summary:          result.Summary,
		KeyPoints:        result.KeyPoints,
		Confidence:       result.Confidence,
		Language:         result.Language,
		SemanticKeywords: result.SemanticKeywords,
	}); err != nil {
		failureErr := ensurePipelineErr(pipeline.StageAIAnalyze, pipeline.ProviderDeepSeek, true, "persist ai result", err)
		logPipelineFailed(pipeline.StageAIAnalyze, pipeline.ProviderDeepSeek, p.TaskID, p.ArticleID, p.UserID, "", time.Since(start), failureErr)
		h.taskRepo.SetFailed(ctx, p.TaskID, buildTaskFailure(failureErr, time.Since(start)))
		return fmt.Errorf("update ai result: %w", err)
	}

	// Backfill title for manual entries that have no user-provided title
	article, err = h.articleRepo.GetByID(ctx, p.ArticleID)
	if err == nil && article != nil && article.SourceType == domain.SourceManual && (article.Title == nil || *article.Title == "") {
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

	logPipelineSucceeded(pipeline.StageAIAnalyze, pipeline.ProviderDeepSeek, p.TaskID, p.ArticleID, p.UserID, "", time.Since(start))

	// Write to content cache for cross-user reuse
	h.cacheWriter().write(ctx, p, result)

	// Enqueue echo card generation (non-blocking)
	echoTask, err := NewEchoTask(p.ArticleID, p.UserID, "")
	if err == nil {
		if _, err := h.asynqClient.EnqueueContext(ctx, echoTask); err != nil {
			slog.Error("[ECHO] failed to enqueue for article",
				"article_id", p.ArticleID,
				"error", err,
			)
		}
	}

	// Enqueue related article computation (non-blocking)
	relateTask := NewRelateTask(p.ArticleID, p.UserID)
	if _, err := h.asynqClient.EnqueueContext(ctx, relateTask); err != nil {
		slog.Error("[RELATE] failed to enqueue for article",
			"article_id", p.ArticleID,
			"error", err,
		)
	}

	return nil
}
