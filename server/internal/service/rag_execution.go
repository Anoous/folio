package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"folio-server/internal/client"
	"folio-server/internal/domain"
)

var (
	errRAGNoArticles   = errors.New("rag has no articles")
	errRAGAnswerFailed = errors.New("rag answer failed")
)

type ragRepository interface {
	LoadArticleSummaries(ctx context.Context, userID string) ([]domain.RAGSource, error)
	SearchArticleSummaries(ctx context.Context, userID, query string, limit int) ([]domain.RAGSource, error)
	BroadRecallSummaries(ctx context.Context, userID string, keywords []string, limit int, excludeID string) ([]domain.RAGSource, error)
	CreateConversation(ctx context.Context, conv *domain.RAGConversation) error
	AddMessage(ctx context.Context, msg *domain.RAGMessage) error
	GetUserRAGQuota(ctx context.Context, userID string) (count int, resetAt *time.Time, err error)
	ResetRAGMonthCount(ctx context.Context, userID string, resetAt time.Time) error
	IncrementRAGMonthCount(ctx context.Context, userID string) error
}

type ragUserRepository interface {
	GetByID(ctx context.Context, id string) (*domain.User, error)
}

type ragKnowledgeAnswerer interface {
	Ask(ctx context.Context, userID, question string) (*KnowledgeAnswer, error)
}

type ragAnswerRun struct {
	question            string
	answer              string
	sources             []domain.RAGSource
	citedIndices        []int
	followupSuggestions []string
}

func (r *ragAnswerRun) result() *client.RAGResult {
	return &client.RAGResult{
		Answer:              r.answer,
		CitedIndices:        r.citedIndices,
		FollowupSuggestions: r.followupSuggestions,
	}
}

func (s *RAGService) prepareKnowledgeRAG(ctx context.Context, userID, question string) (*ragAnswerRun, error) {
	if err := s.checkQuota(ctx, userID); err != nil {
		return nil, err
	}

	articles, err := s.ragRepo.LoadArticleSummaries(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("load articles: %w", err)
	}
	if len(articles) == 0 {
		return nil, errRAGNoArticles
	}

	question = strings.TrimSpace(client.SanitizeField(question))
	knowledgeAnswer, err := s.knowledgeService.Ask(ctx, userID, question)
	if err != nil {
		slog.Error("knowledge ask failed", "user_id", userID, "error", err)
		return nil, fmt.Errorf("%w: %v", errRAGAnswerFailed, err)
	}

	return &ragAnswerRun{
		question:            question,
		answer:              knowledgeAnswer.Answer,
		sources:             knowledgeSourcesToRAGSources(knowledgeAnswer.Sources),
		citedIndices:        knowledgeAnswer.CitedIndices,
		followupSuggestions: knowledgeAnswer.FollowupSuggestions,
	}, nil
}

func (s *RAGService) createRAGConversation(ctx context.Context, userID, question string) (string, error) {
	conv := &domain.RAGConversation{
		UserID: userID,
		Title:  truncateStringPtr(question, 50),
	}
	if err := s.ragRepo.CreateConversation(ctx, conv); err != nil {
		return "", fmt.Errorf("create conversation: %w", err)
	}
	return conv.ID, nil
}

func (s *RAGService) completeRAGAnswer(ctx context.Context, userID, conversationID string, run *ragAnswerRun) string {
	savedConversationID, err := s.saveConversation(ctx, userID, conversationID, run.question, run.result(), run.sources)
	if err != nil {
		slog.Error("failed to save rag conversation", "user_id", userID, "error", err)
	} else {
		conversationID = savedConversationID
	}

	if incrErr := s.incrementQuotaIfFree(ctx, userID); incrErr != nil {
		slog.Error("failed to increment rag quota", "user_id", userID, "error", incrErr)
	}

	return conversationID
}
