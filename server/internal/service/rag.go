package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"folio-server/internal/client"
	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

const (
	ragFreeMonthlyLimit = 5
)

// RAGService orchestrates question-answering over a user's saved articles.
type RAGService struct {
	ragRepo          ragRepository
	userRepo         ragUserRepository
	aiClient         client.Analyzer
	knowledgeService ragKnowledgeAnswerer
}

// NewRAGService creates a new RAGService.
func NewRAGService(ragRepo *repository.RAGRepo, userRepo *repository.UserRepo, aiClient client.Analyzer, knowledgeService *KnowledgeService) *RAGService {
	return &RAGService{
		ragRepo:          ragRepo,
		userRepo:         userRepo,
		aiClient:         aiClient,
		knowledgeService: knowledgeService,
	}
}

// Query answers a user question using their saved article summaries as context.
func (s *RAGService) Query(ctx context.Context, userID, question, conversationID string) (*domain.RAGResponse, error) {
	run, err := s.prepareKnowledgeRAG(ctx, userID, question)
	if err != nil {
		switch {
		case errors.Is(err, errRAGNoArticles):
			return &domain.RAGResponse{
				Answer:      "先收藏一些文章再来提问吧。",
				Sources:     nil,
				SourceCount: 0,
			}, nil
		case errors.Is(err, errRAGAnswerFailed):
			return &domain.RAGResponse{
				Answer:      "抱歉，回答生成失败，请重试。",
				Sources:     nil,
				SourceCount: 0,
			}, nil
		default:
			return nil, err
		}
	}

	conversationID = s.completeRAGAnswer(ctx, userID, conversationID, run)

	return &domain.RAGResponse{
		Answer:              run.answer,
		Sources:             run.sources,
		SourceCount:         len(run.sources),
		FollowupSuggestions: run.followupSuggestions,
		ConversationID:      conversationID,
	}, nil
}

// QueryStream runs the three-phase RAG pipeline, emitting events to the channel.
func (s *RAGService) QueryStream(ctx context.Context, userID, question, conversationID string, events chan<- domain.RAGStreamEvent) {
	defer close(events)

	run, err := s.prepareKnowledgeRAG(ctx, userID, question)
	if err != nil {
		switch {
		case errors.Is(err, ErrRAGQuotaExceeded):
			events <- domain.RAGStreamEvent{Type: "error", ErrorCode: "quota_exceeded", ErrorMessage: "monthly RAG quota exceeded"}
		case errors.Is(err, errRAGNoArticles):
			events <- domain.RAGStreamEvent{Type: "error", ErrorCode: "no_articles", ErrorMessage: "no articles saved yet"}
		case errors.Is(err, errRAGAnswerFailed):
			events <- domain.RAGStreamEvent{Type: "error", ErrorCode: "internal_error", ErrorMessage: "answer generation failed"}
		default:
			events <- domain.RAGStreamEvent{Type: "error", ErrorCode: "internal_error", ErrorMessage: "internal error"}
		}
		return
	}

	// Create conversation early so we can send conversation_id in sources event.
	if conversationID == "" {
		createdID, err := s.createRAGConversation(ctx, userID, run.question)
		if err != nil {
			slog.Error("failed to create rag conversation", "user_id", userID, "error", err)
		} else {
			conversationID = createdID
		}
	}

	select {
	case events <- domain.RAGStreamEvent{
		Type:           "sources",
		Sources:        run.sources,
		SourceCount:    len(run.sources),
		ConversationID: conversationID,
	}:
	case <-ctx.Done():
		return
	}

	for _, r := range run.answer {
		select {
		case events <- domain.RAGStreamEvent{Type: "delta", Text: string(r)}:
		case <-ctx.Done():
			return
		}
	}

	s.completeRAGAnswer(ctx, userID, conversationID, run)

	select {
	case events <- domain.RAGStreamEvent{
		Type:                "done",
		CitedIndices:        run.citedIndices,
		FollowupSuggestions: run.followupSuggestions,
	}:
	case <-ctx.Done():
	}
}

func knowledgeSourcesToRAGSources(sources []KnowledgeSource) []domain.RAGSource {
	result := make([]domain.RAGSource, 0, len(sources))
	for _, source := range sources {
		result = append(result, domain.RAGSource{
			ArticleID:       source.ArticleID,
			Title:           source.Title,
			SiteName:        source.SiteName,
			Summary:         source.Summary,
			EvidenceSnippet: source.EvidenceSnippet,
			CreatedAt:       source.CreatedAt,
			Relevance:       source.Relevance,
		})
	}
	return result
}

// checkQuota verifies the user hasn't exceeded their monthly RAG quota.
// Pro users are unlimited; Free users get ragFreeMonthlyLimit per month.
func (s *RAGService) checkQuota(ctx context.Context, userID string) error {
	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return fmt.Errorf("get user for quota: %w", err)
	}
	if user == nil {
		return ErrNotFound
	}

	// Pro users have unlimited RAG queries.
	if user.Subscription != domain.SubscriptionFree {
		return nil
	}

	count, resetAt, err := s.ragRepo.GetUserRAGQuota(ctx, userID)
	if err != nil {
		return fmt.Errorf("get rag quota: %w", err)
	}

	// Reset if needed: resetAt is nil or before the 1st of this month.
	now := time.Now().UTC()
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	if resetAt == nil || resetAt.Before(monthStart) {
		if resetErr := s.ragRepo.ResetRAGMonthCount(ctx, userID, now); resetErr != nil {
			return fmt.Errorf("reset rag month count: %w", resetErr)
		}
		count = 0
	}

	if count >= ragFreeMonthlyLimit {
		return ErrRAGQuotaExceeded
	}
	return nil
}

// saveConversation persists the user question and assistant answer.
// Returns the conversation ID (possibly newly created).
func (s *RAGService) saveConversation(
	ctx context.Context,
	userID, conversationID, question string,
	ragResult *client.RAGResult,
	sources []domain.RAGSource,
) (string, error) {
	// Create new conversation if none provided.
	if conversationID == "" {
		createdID, err := s.createRAGConversation(ctx, userID, question)
		if err != nil {
			return "", err
		}
		conversationID = createdID
	}

	// Save user message.
	userMsg := &domain.RAGMessage{
		ConversationID:   conversationID,
		Role:             "user",
		Content:          question,
		SourceArticleIDs: []string{},
		SourceCount:      0,
	}
	if err := s.ragRepo.AddMessage(ctx, userMsg); err != nil {
		return conversationID, fmt.Errorf("save user message: %w", err)
	}

	// Save assistant message with cited sources.
	sourceIDs := make([]string, 0, len(sources))
	for _, src := range sources {
		sourceIDs = append(sourceIDs, src.ArticleID)
	}

	// Store the full RAG result JSON as the assistant content.
	assistantContent, _ := json.Marshal(ragResult)

	assistantMsg := &domain.RAGMessage{
		ConversationID:   conversationID,
		Role:             "assistant",
		Content:          string(assistantContent),
		SourceArticleIDs: sourceIDs,
		SourceCount:      len(sourceIDs),
	}
	if err := s.ragRepo.AddMessage(ctx, assistantMsg); err != nil {
		return conversationID, fmt.Errorf("save assistant message: %w", err)
	}

	return conversationID, nil
}

// incrementQuotaIfFree increments RAG usage count for Free-tier users.
func (s *RAGService) incrementQuotaIfFree(ctx context.Context, userID string) error {
	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return err
	}
	if user == nil || user.Subscription != domain.SubscriptionFree {
		return nil
	}
	return s.ragRepo.IncrementRAGMonthCount(ctx, userID)
}

// truncateRunes truncates s to maxRunes runes, appending "..." if truncated.
func truncateRunes(s string, maxRunes int) string {
	runes := []rune(s)
	if len(runes) <= maxRunes {
		return s
	}
	return string(runes[:maxRunes]) + "…"
}

// truncateStringPtr returns a *string truncated to maxRunes runes.
func truncateStringPtr(s string, maxRunes int) *string {
	t := truncateRunes(s, maxRunes)
	return &t
}
