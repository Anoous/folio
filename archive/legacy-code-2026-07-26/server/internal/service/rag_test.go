package service

import (
	"context"
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

	"folio-server/internal/domain"
)

type mockRAGRepository struct {
	articles           []domain.RAGSource
	quotaReserveDenied bool
	loadCalls          int
	createCalls        int
	messages           []domain.RAGMessage
	reserveCalls       int
	releaseCalls       int
}

func (m *mockRAGRepository) LoadArticleSummaries(_ context.Context, _ string) ([]domain.RAGSource, error) {
	m.loadCalls++
	return append([]domain.RAGSource(nil), m.articles...), nil
}

func (m *mockRAGRepository) SearchArticleSummaries(_ context.Context, _, _ string, _ int) ([]domain.RAGSource, error) {
	return nil, nil
}

func (m *mockRAGRepository) BroadRecallSummaries(_ context.Context, _ string, _ []string, _ int, _ string) ([]domain.RAGSource, error) {
	return nil, nil
}

func (m *mockRAGRepository) CreateConversation(_ context.Context, conv *domain.RAGConversation) error {
	m.createCalls++
	if conv.ID == "" {
		conv.ID = "conv-1"
	}
	conv.CreatedAt = time.Date(2026, 4, 26, 0, 0, 0, 0, time.UTC)
	conv.UpdatedAt = conv.CreatedAt
	return nil
}

func (m *mockRAGRepository) AddMessage(_ context.Context, msg *domain.RAGMessage) error {
	copied := *msg
	copied.SourceArticleIDs = append([]string(nil), msg.SourceArticleIDs...)
	m.messages = append(m.messages, copied)
	return nil
}

func (m *mockRAGRepository) ReserveRAGQuota(_ context.Context, _ string, _ int) (bool, error) {
	m.reserveCalls++
	return !m.quotaReserveDenied, nil
}

func (m *mockRAGRepository) ReleaseReservedRAGQuota(_ context.Context, _ string) error {
	m.releaseCalls++
	return nil
}

type mockRAGUserRepository struct {
	user     *domain.User
	getCalls int
}

func (m *mockRAGUserRepository) GetByID(_ context.Context, _ string) (*domain.User, error) {
	m.getCalls++
	return m.user, nil
}

type mockRAGKnowledgeAnswerer struct {
	answer       *KnowledgeAnswer
	err          error
	askCalls     int
	lastQuestion string
}

func (m *mockRAGKnowledgeAnswerer) Ask(_ context.Context, _ string, question string) (*KnowledgeAnswer, error) {
	m.askCalls++
	m.lastQuestion = question
	if m.err != nil {
		return nil, m.err
	}
	return m.answer, nil
}

func TestKnowledgeSourcesToRAGSourcesPreservesEvidenceSnippet(t *testing.T) {
	summary := "Summary"
	evidenceSnippet := "Matched retrieval evidence"

	sources := knowledgeSourcesToRAGSources([]KnowledgeSource{{
		ArticleID:       "article-1",
		Title:           "Grounded source",
		Summary:         &summary,
		EvidenceSnippet: &evidenceSnippet,
		Relevance:       0.88,
	}})

	if len(sources) != 1 {
		t.Fatalf("source count = %d, want 1", len(sources))
	}
	if sources[0].EvidenceSnippet == nil || *sources[0].EvidenceSnippet != evidenceSnippet {
		t.Fatalf("evidence snippet = %v, want %q", sources[0].EvidenceSnippet, evidenceSnippet)
	}
	if sources[0].Summary == nil || *sources[0].Summary != summary {
		t.Fatalf("summary = %v, want %q", sources[0].Summary, summary)
	}
}

func TestRAGServiceQueryRunsSharedKnowledgePipeline(t *testing.T) {
	now := time.Date(2026, 4, 26, 0, 0, 0, 0, time.UTC)
	summary := "Retrieval summary"
	evidence := "Matched retrieval evidence"
	repo := &mockRAGRepository{
		articles: []domain.RAGSource{{
			ArticleID: "ready-article",
			Title:     "Ready Article",
			Summary:   &summary,
			CreatedAt: now,
		}},
	}
	userRepo := &mockRAGUserRepository{user: &domain.User{ID: "user-1", Subscription: domain.SubscriptionFree}}
	knowledge := &mockRAGKnowledgeAnswerer{answer: &KnowledgeAnswer{
		Answer:              "Use retrieved evidence¹",
		CitedIndices:        []int{1},
		FollowupSuggestions: []string{"How should I apply this?"},
		Sources: []KnowledgeSource{{
			ArticleID:       "ready-article",
			Title:           "Ready Article",
			Summary:         &summary,
			EvidenceSnippet: &evidence,
			CreatedAt:       now,
			Relevance:       0.91,
		}},
	}}
	svc := &RAGService{ragRepo: repo, userRepo: userRepo, knowledgeService: knowledge}

	response, err := svc.Query(context.Background(), "user-1", "  How does retrieval work?  ", "")
	if err != nil {
		t.Fatalf("Query() error = %v", err)
	}

	if knowledge.askCalls != 1 {
		t.Fatalf("knowledge ask calls = %d, want 1", knowledge.askCalls)
	}
	if knowledge.lastQuestion != "How does retrieval work?" {
		t.Fatalf("question = %q, want trimmed question", knowledge.lastQuestion)
	}
	if response.ConversationID != "conv-1" {
		t.Fatalf("conversation id = %q, want conv-1", response.ConversationID)
	}
	if len(response.Sources) != 1 || response.Sources[0].EvidenceSnippet == nil || *response.Sources[0].EvidenceSnippet != evidence {
		t.Fatalf("response sources = %+v, want evidence snippet", response.Sources)
	}
	if repo.createCalls != 1 {
		t.Fatalf("created conversations = %d, want 1", repo.createCalls)
	}
	if len(repo.messages) != 2 {
		t.Fatalf("messages saved = %d, want 2", len(repo.messages))
	}
	if repo.messages[0].Role != "user" || repo.messages[0].Content != "How does retrieval work?" {
		t.Fatalf("user message = %+v", repo.messages[0])
	}
	if repo.messages[1].Role != "assistant" || !slices.Equal(repo.messages[1].SourceArticleIDs, []string{"ready-article"}) {
		t.Fatalf("assistant message = %+v", repo.messages[1])
	}
	if repo.reserveCalls != 1 {
		t.Fatalf("quota reservations = %d, want 1", repo.reserveCalls)
	}
	if repo.releaseCalls != 0 {
		t.Fatalf("quota releases = %d, want 0", repo.releaseCalls)
	}
}

func TestRAGServiceQueryStreamUsesSamePreparedAnswer(t *testing.T) {
	now := time.Date(2026, 4, 26, 0, 0, 0, 0, time.UTC)
	summary := "Streaming summary"
	evidence := "Streaming evidence"
	repo := &mockRAGRepository{
		articles: []domain.RAGSource{{ArticleID: "stream-article", Title: "Stream Article", CreatedAt: now}},
	}
	userRepo := &mockRAGUserRepository{user: &domain.User{ID: "user-1", Subscription: domain.SubscriptionFree}}
	knowledge := &mockRAGKnowledgeAnswerer{answer: &KnowledgeAnswer{
		Answer:              "Streamed answer¹",
		CitedIndices:        []int{1},
		FollowupSuggestions: []string{"What next?"},
		Sources: []KnowledgeSource{{
			ArticleID:       "stream-article",
			Title:           "Stream Article",
			Summary:         &summary,
			EvidenceSnippet: &evidence,
			CreatedAt:       now,
			Relevance:       0.87,
		}},
	}}
	svc := &RAGService{ragRepo: repo, userRepo: userRepo, knowledgeService: knowledge}
	events := make(chan domain.RAGStreamEvent, 64)

	svc.QueryStream(context.Background(), "user-1", "stream question", "", events)

	var collected []domain.RAGStreamEvent
	var delta strings.Builder
	for event := range events {
		collected = append(collected, event)
		if event.Type == "delta" {
			delta.WriteString(event.Text)
		}
	}

	if len(collected) < 3 {
		t.Fatalf("event count = %d, want sources, deltas, done", len(collected))
	}
	if collected[0].Type != "sources" || collected[0].ConversationID != "conv-1" {
		t.Fatalf("first event = %+v, want sources with conversation", collected[0])
	}
	if len(collected[0].Sources) != 1 || collected[0].Sources[0].EvidenceSnippet == nil || *collected[0].Sources[0].EvidenceSnippet != evidence {
		t.Fatalf("sources event = %+v, want evidence snippet", collected[0])
	}
	if delta.String() != "Streamed answer¹" {
		t.Fatalf("streamed answer = %q", delta.String())
	}
	last := collected[len(collected)-1]
	if last.Type != "done" || !slices.Equal(last.CitedIndices, []int{1}) {
		t.Fatalf("last event = %+v, want done with cited indices", last)
	}
	if repo.createCalls != 1 {
		t.Fatalf("created conversations = %d, want 1", repo.createCalls)
	}
	if len(repo.messages) != 2 {
		t.Fatalf("messages saved = %d, want 2", len(repo.messages))
	}
	if repo.reserveCalls != 1 {
		t.Fatalf("quota reservations = %d, want 1", repo.reserveCalls)
	}
	if repo.releaseCalls != 0 {
		t.Fatalf("quota releases = %d, want 0", repo.releaseCalls)
	}
}

func TestRAGServiceQueryRejectsWhenFreeQuotaReservationDenied(t *testing.T) {
	repo := &mockRAGRepository{quotaReserveDenied: true}
	userRepo := &mockRAGUserRepository{user: &domain.User{ID: "user-1", Subscription: domain.SubscriptionFree}}
	knowledge := &mockRAGKnowledgeAnswerer{}
	svc := &RAGService{ragRepo: repo, userRepo: userRepo, knowledgeService: knowledge}

	response, err := svc.Query(context.Background(), "user-1", "quota question", "")
	if !errors.Is(err, ErrRAGQuotaExceeded) {
		t.Fatalf("Query() error = %v, want ErrRAGQuotaExceeded", err)
	}
	if response != nil {
		t.Fatalf("response = %+v, want nil", response)
	}
	if repo.reserveCalls != 1 {
		t.Fatalf("quota reservations = %d, want 1", repo.reserveCalls)
	}
	if repo.loadCalls != 0 {
		t.Fatalf("loaded articles = %d, want 0", repo.loadCalls)
	}
	if knowledge.askCalls != 0 {
		t.Fatalf("knowledge asks = %d, want 0", knowledge.askCalls)
	}
	if repo.releaseCalls != 0 {
		t.Fatalf("quota releases = %d, want 0", repo.releaseCalls)
	}
}

func TestRAGServiceQueryReleasesReservedQuotaWhenNoArticles(t *testing.T) {
	repo := &mockRAGRepository{}
	userRepo := &mockRAGUserRepository{user: &domain.User{ID: "user-1", Subscription: domain.SubscriptionFree}}
	knowledge := &mockRAGKnowledgeAnswerer{}
	svc := &RAGService{ragRepo: repo, userRepo: userRepo, knowledgeService: knowledge}

	response, err := svc.Query(context.Background(), "user-1", "empty library", "")
	if err != nil {
		t.Fatalf("Query() error = %v", err)
	}
	if response == nil || response.Answer != "先收藏一些文章再来提问吧。" {
		t.Fatalf("response = %+v, want no-articles answer", response)
	}
	if repo.reserveCalls != 1 {
		t.Fatalf("quota reservations = %d, want 1", repo.reserveCalls)
	}
	if repo.releaseCalls != 1 {
		t.Fatalf("quota releases = %d, want 1", repo.releaseCalls)
	}
	if knowledge.askCalls != 0 {
		t.Fatalf("knowledge asks = %d, want 0", knowledge.askCalls)
	}
}

func TestRAGServicePrepareReleasesReservedQuotaWhenAnswerFails(t *testing.T) {
	now := time.Date(2026, 4, 26, 0, 0, 0, 0, time.UTC)
	repo := &mockRAGRepository{
		articles: []domain.RAGSource{{ArticleID: "article-1", Title: "Article", CreatedAt: now}},
	}
	userRepo := &mockRAGUserRepository{user: &domain.User{ID: "user-1", Subscription: domain.SubscriptionFree}}
	knowledge := &mockRAGKnowledgeAnswerer{err: errors.New("model unavailable")}
	svc := &RAGService{ragRepo: repo, userRepo: userRepo, knowledgeService: knowledge}

	run, err := svc.prepareKnowledgeRAG(context.Background(), "user-1", "question")
	if !errors.Is(err, errRAGAnswerFailed) {
		t.Fatalf("prepareKnowledgeRAG() error = %v, want errRAGAnswerFailed", err)
	}
	if run != nil {
		t.Fatalf("run = %+v, want nil", run)
	}
	if repo.reserveCalls != 1 {
		t.Fatalf("quota reservations = %d, want 1", repo.reserveCalls)
	}
	if repo.releaseCalls != 1 {
		t.Fatalf("quota releases = %d, want 1", repo.releaseCalls)
	}
}

func TestRAGServiceQueryDoesNotReserveQuotaForProUser(t *testing.T) {
	now := time.Date(2026, 4, 26, 0, 0, 0, 0, time.UTC)
	repo := &mockRAGRepository{
		articles: []domain.RAGSource{{ArticleID: "article-1", Title: "Article", CreatedAt: now}},
	}
	userRepo := &mockRAGUserRepository{user: &domain.User{ID: "user-1", Subscription: domain.SubscriptionPro}}
	knowledge := &mockRAGKnowledgeAnswerer{answer: &KnowledgeAnswer{
		Answer: "Pro answer",
		Sources: []KnowledgeSource{{
			ArticleID: "article-1",
			Title:     "Article",
			CreatedAt: now,
		}},
	}}
	svc := &RAGService{ragRepo: repo, userRepo: userRepo, knowledgeService: knowledge}

	response, err := svc.Query(context.Background(), "user-1", "question", "")
	if err != nil {
		t.Fatalf("Query() error = %v", err)
	}
	if response == nil || response.Answer != "Pro answer" {
		t.Fatalf("response = %+v, want pro answer", response)
	}
	if repo.reserveCalls != 0 {
		t.Fatalf("quota reservations = %d, want 0", repo.reserveCalls)
	}
	if repo.releaseCalls != 0 {
		t.Fatalf("quota releases = %d, want 0", repo.releaseCalls)
	}
}
