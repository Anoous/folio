package worker

import (
	"context"
	"fmt"
	"time"

	"folio-server/internal/client"
	"folio-server/internal/pipeline"
	"folio-server/internal/repository"
)

type aiResultPersister struct {
	articleRepo ArticleAIUpdater
	taskRepo    TaskFailer
}

func (h *AIHandler) resultPersister() aiResultPersister {
	return aiResultPersister{
		articleRepo: h.articleRepo,
		taskRepo:    h.taskRepo,
	}
}

func (p aiResultPersister) persist(ctx context.Context, payload AIProcessPayload, result *client.AnalyzeResponse, categoryID string, start time.Time) error {
	if err := p.articleRepo.UpdateAIResult(ctx, payload.ArticleID, repository.AIResult{
		CategoryID:       categoryID,
		Summary:          result.Summary,
		KeyPoints:        result.KeyPoints,
		Confidence:       result.Confidence,
		Language:         result.Language,
		SemanticKeywords: result.SemanticKeywords,
	}); err != nil {
		failureErr := ensurePipelineErr(pipeline.StageAIAnalyze, pipeline.ProviderDeepSeek, true, "persist ai result", err)
		logPipelineFailed(pipeline.StageAIAnalyze, pipeline.ProviderDeepSeek, payload.TaskID, payload.ArticleID, payload.UserID, "", time.Since(start), failureErr)
		p.taskRepo.SetFailed(ctx, payload.TaskID, buildTaskFailure(failureErr, time.Since(start)))
		return fmt.Errorf("update ai result: %w", err)
	}
	return nil
}
