package service

import (
	"context"
	"fmt"
	"log/slog"
	"strings"

	"folio-server/internal/client"
	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

type articleSearchWorkflow struct {
	articleRepo       articleCreator
	aiClient          queryExpander
	evidenceRepo      knowledgeDocumentLister
	evidenceRetriever knowledgeBroadRecaller
}

func (s *ArticleService) searchWorkflow() articleSearchWorkflow {
	return articleSearchWorkflow{
		articleRepo:       s.articleRepo,
		aiClient:          s.aiClient,
		evidenceRepo:      s.evidenceRepo,
		evidenceRetriever: s.evidenceRetriever,
	}
}

func (w articleSearchWorkflow) Search(ctx context.Context, userID, query string, page, perPage int) (*repository.ListArticlesResult, error) {
	result, err := w.articleRepo.Search(ctx, userID, query, page, perPage)
	if err != nil {
		return nil, err
	}
	trimmedQuery := strings.TrimSpace(query)
	if result.Total > 0 {
		w.attachEvidenceSnippets(ctx, userID, trimmedQuery, result.Articles)
		return result, nil
	}
	if trimmedQuery == "" {
		return result, nil
	}
	return w.searchWithEvidence(ctx, userID, trimmedQuery, page, perPage)
}

func (w articleSearchWorkflow) SemanticSearch(ctx context.Context, userID, question string, page, perPage int) (*repository.ListArticlesResult, error) {
	candidates, err := w.searchEvidenceCandidates(ctx, userID, question, 50)
	if err != nil || len(candidates) == 0 {
		slog.Warn("semantic search: evidence retrieval failed, falling back to keyword", "error", err)
		return w.Search(ctx, userID, question, page, perPage)
	}

	rerankCandidates := make([]client.RerankCandidate, len(candidates))
	for i, article := range candidates {
		summary := ""
		if article.Summary != nil {
			summary = *article.Summary
		}
		title := ""
		if article.Title != nil {
			title = *article.Title
		}
		rerankCandidates[i] = client.RerankCandidate{
			Index:     i + 1,
			Title:     title,
			Summary:   summary,
			KeyPoints: article.KeyPoints,
		}
	}

	ranked, err := w.aiClient.RerankArticles(ctx, question, rerankCandidates)
	if err != nil {
		slog.Warn("semantic search: rerank failed, returning recall order", "error", err)
		return paginateArticleResults(candidates, page, perPage), nil
	}

	reranked := make([]domain.Article, 0, len(ranked))
	for _, result := range ranked {
		idx := result.Index - 1
		if idx >= 0 && idx < len(candidates) {
			reranked = append(reranked, candidates[idx])
		}
	}

	return paginateArticleResults(reranked, page, perPage), nil
}

func (w articleSearchWorkflow) searchWithEvidence(ctx context.Context, userID, query string, page, perPage int) (*repository.ListArticlesResult, error) {
	candidates, err := w.searchEvidenceCandidates(ctx, userID, query, max(page*perPage, 20))
	if err != nil {
		return nil, err
	}
	if len(candidates) == 0 {
		return &repository.ListArticlesResult{Articles: []domain.Article{}, Total: 0}, nil
	}
	return paginateArticleResults(candidates, page, perPage), nil
}

func (w articleSearchWorkflow) searchEvidenceCandidates(ctx context.Context, userID, query string, limit int) ([]domain.Article, error) {
	contextResult, err := w.retrieveEvidenceContext(ctx, userID, query, limit)
	if err != nil {
		return nil, err
	}
	if contextResult == nil || contextResult.Insufficient || len(contextResult.Sources) == 0 {
		return nil, nil
	}

	articles := make([]domain.Article, 0, len(contextResult.Sources))
	for _, source := range contextResult.Sources {
		article, err := w.articleRepo.GetByID(ctx, source.ArticleID)
		if err != nil {
			return nil, fmt.Errorf("get evidence article %s: %w", source.ArticleID, err)
		}
		if article == nil || article.DeletedAt != nil || article.UserID != userID {
			continue
		}
		article.SearchSnippet = source.EvidenceSnippet
		articles = append(articles, *article)
	}

	return articles, nil
}

func (w articleSearchWorkflow) attachEvidenceSnippets(ctx context.Context, userID, query string, articles []domain.Article) {
	if len(articles) == 0 || strings.TrimSpace(query) == "" {
		return
	}

	articleIndex := make(map[string]int, len(articles))
	for idx, article := range articles {
		articleIndex[article.ID] = idx
	}

	contextResult, err := w.retrieveEvidenceContext(ctx, userID, query, max(len(articles)*2, 20))
	if err != nil {
		slog.Warn("search: evidence snippet retrieval failed", "error", err)
		return
	}
	if contextResult == nil || contextResult.Insufficient {
		return
	}

	for _, source := range contextResult.Sources {
		idx, ok := articleIndex[source.ArticleID]
		if !ok {
			continue
		}
		articles[idx].SearchSnippet = source.EvidenceSnippet
	}
}

func (w articleSearchWorkflow) retrieveEvidenceContext(ctx context.Context, userID, query string, limit int) (*EvidenceContext, error) {
	if w.evidenceRepo == nil {
		return nil, nil
	}

	evidenceService := NewEvidenceService(w.evidenceRepo, w.aiClient, w.evidenceRetriever)
	return evidenceService.Retrieve(ctx, userID, query, EvidenceRetrieveOptions{
		MaxSources: max(limit, 20),
	})
}

func paginateArticleResults(articles []domain.Article, page, perPage int) *repository.ListArticlesResult {
	total := len(articles)
	start := (page - 1) * perPage
	end := start + perPage
	if start > total {
		start = total
	}
	if end > total {
		end = total
	}
	return &repository.ListArticlesResult{
		Articles: articles[start:end],
		Total:    total,
	}
}
