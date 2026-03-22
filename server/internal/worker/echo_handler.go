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
)

// echoArticleRepo abstracts the article repository methods used by EchoHandler.
type echoArticleRepo interface {
	GetByID(ctx context.Context, id string) (*domain.Article, error)
}

// echoCardRepo abstracts the echo repository methods used by EchoHandler.
type echoCardRepo interface {
	CountCardsByArticle(ctx context.Context, articleID string) (int, error)
	CreateCard(ctx context.Context, card *domain.EchoCard) error
}

// echoCardGenerator abstracts the AI method for generating echo cards.
type echoCardGenerator interface {
	GenerateEchoCards(ctx context.Context, title string, source string, keyPoints []string) ([]client.EchoQAPair, error)
}

// EchoHandler processes echo:generate tasks.
type EchoHandler struct {
	aiClient    echoCardGenerator
	articleRepo echoArticleRepo
	echoRepo    echoCardRepo
}

// NewEchoHandler creates an EchoHandler.
func NewEchoHandler(
	aiClient echoCardGenerator,
	articleRepo echoArticleRepo,
	echoRepo echoCardRepo,
) *EchoHandler {
	return &EchoHandler{
		aiClient:    aiClient,
		articleRepo: articleRepo,
		echoRepo:    echoRepo,
	}
}

// ProcessTask handles the echo:generate task.
func (h *EchoHandler) ProcessTask(ctx context.Context, t *asynq.Task) error {
	var p EchoPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("unmarshal echo payload: %w", err)
	}

	start := time.Now()

	// Fetch article
	article, err := h.articleRepo.GetByID(ctx, p.ArticleID)
	if err != nil {
		return fmt.Errorf("get article for echo: %w", err)
	}
	if article == nil {
		slog.Warn("echo task: article not found, skipping", "article_id", p.ArticleID)
		return nil
	}

	// Skip if no key points
	if len(article.KeyPoints) == 0 {
		slog.Debug("echo task: no key points, skipping", "article_id", p.ArticleID)
		return nil
	}

	// Skip if echo cards already exist for this article
	count, err := h.echoRepo.CountCardsByArticle(ctx, p.ArticleID)
	if err != nil {
		return fmt.Errorf("count echo cards: %w", err)
	}
	if count > 0 {
		slog.Debug("echo task: cards already exist, skipping",
			"article_id", p.ArticleID,
			"existing_cards", count,
		)
		return nil
	}

	// Build inputs for AI call
	title := derefOrEmpty(article.Title)
	source := derefOrDefault(article.SiteName, "web")

	// Generate Q&A pairs via DeepSeek (or mock)
	pairs, err := h.aiClient.GenerateEchoCards(ctx, title, source, article.KeyPoints)
	if err != nil {
		slog.Error("echo task: generate cards failed",
			"article_id", p.ArticleID,
			"error", err,
		)
		return fmt.Errorf("generate echo cards: %w", err)
	}

	if len(pairs) == 0 {
		slog.Warn("echo task: no pairs generated", "article_id", p.ArticleID)
		return nil
	}

	// Insert echo cards
	for _, qa := range pairs {
		card := &domain.EchoCard{
			UserID:        p.UserID,
			ArticleID:     p.ArticleID,
			CardType:      domain.EchoCardInsight,
			Question:      qa.Question,
			Answer:        qa.Answer,
			SourceContext: &qa.SourceContext,
			NextReviewAt:  time.Now().Add(24 * time.Hour),
			IntervalDays:  1,
			EaseFactor:    2.50,
		}
		if err := h.echoRepo.CreateCard(ctx, card); err != nil {
			slog.Error("echo task: create card failed",
				"article_id", p.ArticleID,
				"error", err,
			)
			// Non-fatal: continue with remaining cards
			continue
		}
	}

	slog.Info("echo task completed",
		"article_id", p.ArticleID,
		"cards_generated", len(pairs),
		"duration_ms", time.Since(start).Milliseconds(),
	)

	return nil
}
