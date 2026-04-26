package worker

import (
	"context"
	"log/slog"

	"folio-server/internal/client"
	"folio-server/internal/domain"
)

type aiTitleArticleRepo interface {
	ArticleGetter
	ArticleTitleUpdater
}

type aiTitleBackfiller struct {
	articleRepo aiTitleArticleRepo
}

func (h *AIHandler) titleBackfiller() aiTitleBackfiller {
	return aiTitleBackfiller{articleRepo: h.articleRepo}
}

func (b aiTitleBackfiller) backfill(ctx context.Context, p AIProcessPayload, result *client.AnalyzeResponse) {
	article, err := b.articleRepo.GetByID(ctx, p.ArticleID)
	if err != nil || !shouldBackfillManualTitle(article) {
		return
	}

	generatedTitle := generatedManualTitle(result)
	if generatedTitle == "" {
		return
	}
	if err := b.articleRepo.UpdateTitle(ctx, p.ArticleID, generatedTitle); err != nil {
		slog.Error("failed to backfill title", "article_id", p.ArticleID, "error", err)
	}
}

func shouldBackfillManualTitle(article *domain.Article) bool {
	return article != nil &&
		article.SourceType == domain.SourceManual &&
		(article.Title == nil || *article.Title == "")
}

func generatedManualTitle(result *client.AnalyzeResponse) string {
	if len(result.KeyPoints) > 0 {
		return result.KeyPoints[0]
	}
	if result.Summary == "" {
		return ""
	}
	runes := []rune(result.Summary)
	if len(runes) > 50 {
		return string(runes[:50])
	}
	return result.Summary
}
