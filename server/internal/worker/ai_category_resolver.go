package worker

import (
	"context"
	"log/slog"

	"folio-server/internal/client"
	"folio-server/internal/domain"
)

type aiCategoryResolver struct {
	categoryRepo CategoryFinder
}

func (h *AIHandler) categoryResolver() aiCategoryResolver {
	return aiCategoryResolver{categoryRepo: h.categoryRepo}
}

func (r aiCategoryResolver) resolve(ctx context.Context, p AIProcessPayload, result *client.AnalyzeResponse) (*domain.Category, error) {
	cat, err := r.categoryRepo.FindOrCreate(ctx, result.Category, result.CategoryName, result.CategoryName)
	if err == nil {
		return cat, nil
	}

	slog.Warn("ai: category creation failed, falling back to 'other'",
		"article_id", p.ArticleID,
		"slug", result.Category,
		"error", err,
	)
	return r.categoryRepo.FindOrCreate(ctx, "other", "其他", "Other")
}
