package service

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/hibiken/asynq"

	"folio-server/internal/domain"
	"folio-server/internal/repository"
	"folio-server/internal/worker"
)

type HighlightService struct {
	highlightRepo *repository.HighlightRepo
	articleRepo   *repository.ArticleRepo
	asynqClient   *asynq.Client
}

func NewHighlightService(
	highlightRepo *repository.HighlightRepo,
	articleRepo *repository.ArticleRepo,
	asynqClient *asynq.Client,
) *HighlightService {
	return &HighlightService{
		highlightRepo: highlightRepo,
		articleRepo:   articleRepo,
		asynqClient:   asynqClient,
	}
}

// CreateHighlight creates a highlight, increments the article's highlight count,
// and enqueues an echo:generate task for the highlight.
func (s *HighlightService) CreateHighlight(
	ctx context.Context,
	userID, articleID, text string,
	startOffset, endOffset int,
) (*domain.Highlight, error) {
	// Verify article belongs to user
	article, err := s.articleRepo.GetByID(ctx, articleID)
	if err != nil {
		return nil, fmt.Errorf("get article: %w", err)
	}
	if article == nil {
		return nil, ErrNotFound
	}
	if article.UserID != userID {
		return nil, ErrForbidden
	}

	// Create highlight
	h := &domain.Highlight{
		ArticleID:   articleID,
		UserID:      userID,
		Text:        text,
		StartOffset: startOffset,
		EndOffset:   endOffset,
		Color:       "yellow",
	}
	if err := s.highlightRepo.CreateHighlight(ctx, h); err != nil {
		return nil, fmt.Errorf("create highlight: %w", err)
	}

	// Increment article highlight count
	if err := s.highlightRepo.IncrementArticleHighlightCount(ctx, articleID); err != nil {
		slog.Error("failed to increment highlight count",
			"article_id", articleID,
			"error", err,
		)
		// Non-fatal: highlight was created successfully
	}

	// Enqueue echo:generate with highlight_id
	echoTask, err := worker.NewEchoTask(articleID, userID, h.ID)
	if err == nil {
		if _, enqErr := s.asynqClient.EnqueueContext(ctx, echoTask); enqErr != nil {
			slog.Error("failed to enqueue echo task for highlight",
				"highlight_id", h.ID,
				"article_id", articleID,
				"error", enqErr,
			)
			// Non-fatal: highlight was created successfully
		}
	}

	return h, nil
}

// GetArticleHighlights returns all highlights for a given article owned by the user.
func (s *HighlightService) GetArticleHighlights(
	ctx context.Context,
	userID, articleID string,
) ([]domain.Highlight, error) {
	// Verify article belongs to user
	article, err := s.articleRepo.GetByID(ctx, articleID)
	if err != nil {
		return nil, fmt.Errorf("get article: %w", err)
	}
	if article == nil {
		return nil, ErrNotFound
	}
	if article.UserID != userID {
		return nil, ErrForbidden
	}

	return s.highlightRepo.GetByArticle(ctx, articleID, userID)
}

// DeleteHighlight deletes a highlight and decrements the article's highlight count.
func (s *HighlightService) DeleteHighlight(
	ctx context.Context,
	userID, highlightID string,
) error {
	articleID, err := s.highlightRepo.DeleteHighlight(ctx, highlightID, userID)
	if err != nil {
		return fmt.Errorf("delete highlight: %w", err)
	}
	if articleID == "" {
		return ErrNotFound
	}

	// Decrement article highlight count
	if err := s.highlightRepo.DecrementArticleHighlightCount(ctx, articleID); err != nil {
		slog.Error("failed to decrement highlight count",
			"article_id", articleID,
			"error", err,
		)
		// Non-fatal: highlight was already deleted
	}

	return nil
}
