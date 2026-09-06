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
	highlightRepo highlightStore
	articleRepo   highlightArticleStore
	asynqClient   taskEnqueuer
}

type highlightStore interface {
	CreateHighlight(ctx context.Context, h *domain.Highlight) error
	GetByArticle(ctx context.Context, articleID, userID string) ([]domain.Highlight, error)
	DeleteHighlight(ctx context.Context, id, userID string) (articleID string, err error)
}

type highlightArticleStore interface {
	GetByID(ctx context.Context, id string) (*domain.Article, error)
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

// CreateHighlight creates a highlight and enqueues an echo:generate task for it.
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

// DeleteHighlight deletes a highlight owned by the user.
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

	return nil
}
