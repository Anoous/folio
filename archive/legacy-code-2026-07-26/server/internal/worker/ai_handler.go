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

	analysis, err := h.analysisRunner().run(ctx, p, start)
	if err != nil {
		return err
	}
	if analysis.done {
		return nil
	}
	result := analysis.response

	cat, err := h.categoryResolver().resolve(ctx, p, result)
	if err != nil {
		// Both primary and fallback category creation failed.
		// Mark task failed AND article as ready (content is still readable).
		failureErr := ensurePipelineErr(pipeline.StageAIAnalyze, pipeline.ProviderDeepSeek, true, "persist ai category", err)
		logPipelineFailed(pipeline.StageAIAnalyze, pipeline.ProviderDeepSeek, p.TaskID, p.ArticleID, p.UserID, "", time.Since(start), failureErr)
		h.taskRepo.SetFailed(ctx, p.TaskID, buildTaskFailure(failureErr, time.Since(start)))
		h.articleRepo.UpdateStatus(ctx, p.ArticleID, domain.ArticleStatusReady)
		return fmt.Errorf("create fallback category: %w", err)
	}

	if err := h.resultPersister().persist(ctx, p, result, cat.ID, start); err != nil {
		return err
	}

	h.titleBackfiller().backfill(ctx, p, result)

	h.tagApplier().apply(ctx, p, result.Tags)

	// Mark AI finished
	if err := h.taskRepo.SetAIFinished(ctx, p.TaskID); err != nil {
		return fmt.Errorf("set ai finished: %w", err)
	}

	logPipelineSucceeded(pipeline.StageAIAnalyze, pipeline.ProviderDeepSeek, p.TaskID, p.ArticleID, p.UserID, "", time.Since(start))

	// Write to content cache for cross-user reuse
	h.cacheWriter().write(ctx, p, result)

	h.followupEnqueuer().enqueue(ctx, p)

	return nil
}
