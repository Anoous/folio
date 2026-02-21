package worker

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/hibiken/asynq"

	"folio-server/internal/client"
	"folio-server/internal/repository"
)

type AIHandler struct {
	aiClient     *client.AIClient
	articleRepo  *repository.ArticleRepo
	taskRepo     *repository.TaskRepo
	categoryRepo *repository.CategoryRepo
	tagRepo      *repository.TagRepo
}

func NewAIHandler(
	aiClient *client.AIClient,
	articleRepo *repository.ArticleRepo,
	taskRepo *repository.TaskRepo,
	categoryRepo *repository.CategoryRepo,
	tagRepo *repository.TagRepo,
) *AIHandler {
	return &AIHandler{
		aiClient:     aiClient,
		articleRepo:  articleRepo,
		taskRepo:     taskRepo,
		categoryRepo: categoryRepo,
		tagRepo:      tagRepo,
	}
}

func (h *AIHandler) ProcessTask(ctx context.Context, t *asynq.Task) error {
	var p AIProcessPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("unmarshal ai payload: %w", err)
	}

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
		h.taskRepo.SetFailed(ctx, p.TaskID, err.Error())
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

	return nil
}
