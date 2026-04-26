package worker

import (
	"context"
	"time"

	"folio-server/internal/client"
	"folio-server/internal/domain"
)

type aiCacheWriter struct {
	articleRepo ArticleGetter
	cacheRepo   ContentCacheWriter
}

func (h *AIHandler) cacheWriter() aiCacheWriter {
	return aiCacheWriter{
		articleRepo: h.articleRepo,
		cacheRepo:   h.cacheRepo,
	}
}

func (w aiCacheWriter) write(ctx context.Context, p AIProcessPayload, result *client.AnalyzeResponse) {
	if w.cacheRepo == nil {
		return
	}
	article, err := w.articleRepo.GetByID(ctx, p.ArticleID)
	if err != nil || article == nil || article.URL == nil {
		return
	}

	markdown := derefOrEmpty(article.MarkdownContent)
	if !domain.IsCacheWorthy(markdown, result.Confidence) {
		return
	}

	now := time.Now()
	w.cacheRepo.Upsert(ctx, &domain.ContentCache{
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
	})
}
