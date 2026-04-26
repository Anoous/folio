package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"

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
	ReserveRAGQuota(ctx context.Context, userID string, limit int) (bool, error)
	ReleaseReservedRAGQuota(ctx context.Context, userID string) error
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
	quotaReserved       bool
}

func (r *ragAnswerRun) result() *client.RAGResult {
	return &client.RAGResult{
		Answer:              r.answer,
		CitedIndices:        r.citedIndices,
		FollowupSuggestions: r.followupSuggestions,
	}
}

func (s *RAGService) prepareKnowledgeRAG(ctx context.Context, userID, question string) (*ragAnswerRun, error) {
	quotaReserved, err := s.reserveRAGQuota(ctx, userID)
	if err != nil {
		return nil, err
	}
	committed := false
	defer func() {
		if !committed {
			s.releaseReservedRAGQuota(userID, quotaReserved)
		}
	}()

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

	committed = true
	return &ragAnswerRun{
		question:            question,
		answer:              knowledgeAnswer.Answer,
		sources:             knowledgeSourcesToRAGSources(knowledgeAnswer.Sources),
		citedIndices:        knowledgeAnswer.CitedIndices,
		followupSuggestions: knowledgeAnswer.FollowupSuggestions,
		quotaReserved:       quotaReserved,
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

	return conversationID
}
