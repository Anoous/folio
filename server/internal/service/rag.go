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
	completed := false
	defer func() {
		if !completed {
			s.releaseReservedRAGQuota(userID, run.quotaReserved)
		}
	}()

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
	completed = true

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

// reserveRAGQuota atomically reserves one completed-answer slot for free users.
// Pro users are unlimited and do not need a reservation.
func (s *RAGService) reserveRAGQuota(ctx context.Context, userID string) (bool, error) {
	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return false, fmt.Errorf("get user for quota: %w", err)
	}
	if user == nil {
		return false, ErrNotFound
	}

	if user.Subscription != domain.SubscriptionFree {
		return false, nil
	}

	reserved, err := s.ragRepo.ReserveRAGQuota(ctx, userID, ragFreeMonthlyLimit)
	if err != nil {
		return false, fmt.Errorf("reserve rag quota: %w", err)
	}
	if !reserved {
		return false, ErrRAGQuotaExceeded
	}
	return true, nil
}

func (s *RAGService) releaseReservedRAGQuota(userID string, reserved bool) {
	if !reserved {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := s.ragRepo.ReleaseReservedRAGQuota(ctx, userID); err != nil {
		slog.Error("failed to release rag quota reservation", "user_id", userID, "error", err)
	}
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
