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

type relateRAGRepo interface {
	BroadRecallSummaries(ctx context.Context, userID string, keywords []string, limit int, excludeID string) ([]domain.RAGSource, error)
}

type relateSelector interface {
	SelectRelatedArticles(ctx context.Context, sourceTitle, sourceSummary string, candidates []client.RerankCandidate) ([]client.RelatedResult, error)
}

type relateRelationRepo interface {
	SaveBatch(ctx context.Context, sourceID string, relations []repository.ArticleRelation) error
}

type RelateHandler struct {
	articleRepo  ArticleGetter
	ragRepo      relateRAGRepo
	aiClient     relateSelector
	relationRepo relateRelationRepo
}

func NewRelateHandler(
	articleRepo ArticleGetter,
	ragRepo relateRAGRepo,
	aiClient relateSelector,
	relationRepo relateRelationRepo,
) *RelateHandler {
	return &RelateHandler{
		articleRepo:  articleRepo,
		ragRepo:      ragRepo,
		aiClient:     aiClient,
		relationRepo: relationRepo,
	}
}

func (h *RelateHandler) ProcessTask(ctx context.Context, t *asynq.Task) error {
	var p RelatePayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("unmarshal relate payload: %w", err)
	}

	start := time.Now()

	article, err := h.articleRepo.GetByID(ctx, p.ArticleID)
	if err != nil || article == nil {
		return fmt.Errorf("get article %s: %w", p.ArticleID, err)
	}

	// Need semantic_keywords to do recall
	if len(article.SemanticKeywords) == 0 {
		slog.Info("[RELATE] skipping — no semantic_keywords", "article_id", p.ArticleID)
		return nil
	}

	// Broad recall using article's semantic_keywords, excluding self
	candidates, err := h.ragRepo.BroadRecallSummaries(ctx, p.UserID, article.SemanticKeywords, 30, p.ArticleID)
	if err != nil || len(candidates) == 0 {
		slog.Info("[RELATE] no candidates found", "article_id", p.ArticleID, "error", err)
		return nil // Not an error — just no related articles
	}

	// Build RerankCandidate list
	rerankCandidates := make([]client.RerankCandidate, len(candidates))
	for i, c := range candidates {
		summary := ""
		if c.Summary != nil {
			summary = *c.Summary
		}
		rerankCandidates[i] = client.RerankCandidate{
			Index:     i + 1,
			Title:     c.Title,
			Summary:   summary,
			KeyPoints: c.KeyPoints,
		}
	}

	title := ""
	if article.Title != nil {
		title = *article.Title
	}
	summary := ""
	if article.Summary != nil {
		summary = *article.Summary
	}

	results, err := h.aiClient.SelectRelatedArticles(ctx, title, summary, rerankCandidates)
	if err != nil {
		slog.Error("[RELATE] LLM selection failed", "article_id", p.ArticleID, "error", err)
		return fmt.Errorf("select related articles: %w", err)
	}

	// Map results back to article IDs and save
	relations := make([]repository.ArticleRelation, 0, len(results))
	for rank, r := range results {
		idx := r.Index - 1
		if idx < 0 || idx >= len(candidates) {
			continue
		}
		relations = append(relations, repository.ArticleRelation{
			SourceArticleID:  p.ArticleID,
			RelatedArticleID: candidates[idx].ArticleID,
			RelevanceReason:  r.Reason,
			Score:            5 - rank, // 5, 4, 3, 2, 1
		})
	}

	if len(relations) > 0 {
		if err := h.relationRepo.SaveBatch(ctx, p.ArticleID, relations); err != nil {
			return fmt.Errorf("save relations: %w", err)
		}
	}

	slog.Info("[RELATE] completed",
		"article_id", p.ArticleID,
		"candidates", len(candidates),
		"related", len(relations),
		"duration_ms", time.Since(start).Milliseconds(),
	)
	return nil
}
