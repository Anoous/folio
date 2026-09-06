package worker

import (
	"context"
	"fmt"
	"time"

	"folio-server/internal/client"
	"folio-server/internal/domain"
	"folio-server/internal/pipeline"
)

type aiAnalysisTaskRepo interface {
	TaskAIStarter
	TaskFailer
}

type aiAnalysisRunner struct {
	aiClient    analyzer
	articleRepo ArticleStatusUpdater
	taskRepo    aiAnalysisTaskRepo
}

type aiAnalysisRunResult struct {
	response *client.AnalyzeResponse
	done     bool
}

func (h *AIHandler) analysisRunner() aiAnalysisRunner {
	return aiAnalysisRunner{
		aiClient:    h.aiClient,
		articleRepo: h.articleRepo,
		taskRepo:    h.taskRepo,
	}
}

func (r aiAnalysisRunner) run(ctx context.Context, p AIProcessPayload, start time.Time) (aiAnalysisRunResult, error) {
	if err := r.taskRepo.SetAIStarted(ctx, p.TaskID); err != nil {
		return aiAnalysisRunResult{}, fmt.Errorf("set ai started: %w", err)
	}

	logPipelineStarted(pipeline.StageAIAnalyze, pipeline.ProviderDeepSeek, p.TaskID, p.ArticleID, p.UserID, "")

	response, err := r.aiClient.Analyze(ctx, client.AnalyzeRequest{
		Title:   p.Title,
		Content: p.Markdown,
		Source:  p.Source,
		Author:  p.Author,
	})
	if err == nil {
		return aiAnalysisRunResult{response: response}, nil
	}

	failureErr := ensurePipelineErr(pipeline.StageAIAnalyze, pipeline.ProviderDeepSeek, false, "analyze article", err)
	logPipelineFailed(pipeline.StageAIAnalyze, pipeline.ProviderDeepSeek, p.TaskID, p.ArticleID, p.UserID, "", time.Since(start), failureErr)
	r.taskRepo.SetFailed(ctx, p.TaskID, buildTaskFailure(failureErr, time.Since(start)))
	r.articleRepo.SetError(ctx, p.ArticleID, failureErr.Error())
	// Content was already crawled successfully, so keep the article readable even when AI enrichment fails.
	r.articleRepo.UpdateStatus(ctx, p.ArticleID, domain.ArticleStatusReady)
	return aiAnalysisRunResult{done: true}, nil
}
