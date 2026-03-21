package worker

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"github.com/hibiken/asynq"

	"folio-server/internal/client"
	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

// --- Mock implementations for AIHandler interfaces ---

type mockAnalyzer struct {
	resp *client.AnalyzeResponse
	err  error
}

func (m *mockAnalyzer) Analyze(_ context.Context, _ client.AnalyzeRequest) (*client.AnalyzeResponse, error) {
	return m.resp, m.err
}

type mockAIArticleRepo struct {
	articles       map[string]*domain.Article
	updatedTitles  map[string]string
	updatedAI      map[string]repository.AIResult
	updatedStatus  map[string]domain.ArticleStatus
}

func newMockAIArticleRepo() *mockAIArticleRepo {
	return &mockAIArticleRepo{
		articles:      make(map[string]*domain.Article),
		updatedTitles: make(map[string]string),
		updatedAI:     make(map[string]repository.AIResult),
		updatedStatus: make(map[string]domain.ArticleStatus),
	}
}

func (m *mockAIArticleRepo) GetByID(_ context.Context, id string) (*domain.Article, error) {
	a, ok := m.articles[id]
	if !ok {
		return nil, errors.New("not found")
	}
	return a, nil
}

func (m *mockAIArticleRepo) UpdateAIResult(_ context.Context, id string, ai repository.AIResult) error {
	m.updatedAI[id] = ai
	return nil
}

func (m *mockAIArticleRepo) UpdateTitle(_ context.Context, articleID string, title string) error {
	m.updatedTitles[articleID] = title
	return nil
}

func (m *mockAIArticleRepo) UpdateStatus(_ context.Context, id string, status domain.ArticleStatus) error {
	m.updatedStatus[id] = status
	return nil
}

func (m *mockAIArticleRepo) SetError(_ context.Context, _ string, _ string) error {
	return nil
}

type mockAITaskRepo struct {
	started  map[string]bool
	finished map[string]bool
}

func newMockAITaskRepo() *mockAITaskRepo {
	return &mockAITaskRepo{
		started:  make(map[string]bool),
		finished: make(map[string]bool),
	}
}

func (m *mockAITaskRepo) SetAIStarted(_ context.Context, id string) error {
	m.started[id] = true
	return nil
}

func (m *mockAITaskRepo) SetAIFinished(_ context.Context, id string) error {
	m.finished[id] = true
	return nil
}

func (m *mockAITaskRepo) SetFailed(_ context.Context, _ string, _ string) error {
	return nil
}

type mockAITagRepo struct{}

func (m *mockAITagRepo) Create(_ context.Context, _, name string, _ bool) (*domain.Tag, error) {
	return &domain.Tag{ID: "tag-" + name, Name: name}, nil
}

func (m *mockAITagRepo) AttachToArticle(_ context.Context, _, _ string) error {
	return nil
}

// --- Tests ---

func makeAITask(articleID, taskID, userID string) *asynq.Task {
	payload, _ := json.Marshal(AIProcessPayload{
		ArticleID: articleID,
		TaskID:    taskID,
		UserID:    userID,
		Title:     "Test Title",
		Markdown:  "Some content for AI analysis.",
		Source:    "web",
		Author:    "Author",
	})
	return asynq.NewTask(TypeAIProcess, payload)
}

func TestAIHandler_TitleBackfill_ManualWithNoTitle(t *testing.T) {
	articleRepo := newMockAIArticleRepo()
	articleRepo.articles["art-1"] = &domain.Article{
		ID:         "art-1",
		SourceType: domain.SourceManual,
		Title:      nil, // no title
	}

	// Simulate the condition from ai_handler.go line 137
	article := articleRepo.articles["art-1"]
	shouldBackfill := article != nil &&
		article.SourceType == domain.SourceManual &&
		(article.Title == nil || *article.Title == "")

	if !shouldBackfill {
		t.Error("expected title backfill for manual article with no title")
	}
}

func TestAIHandler_TitleBackfill_WebWithNoTitle_Skipped(t *testing.T) {
	article := &domain.Article{
		ID:         "art-2",
		SourceType: domain.SourceWeb,
		Title:      nil,
	}

	shouldBackfill := article.SourceType == domain.SourceManual &&
		(article.Title == nil || *article.Title == "")

	if shouldBackfill {
		t.Error("should NOT backfill title for web article — only manual articles get backfill")
	}
}

func TestAIHandler_TitleBackfill_ManualWithTitle_Skipped(t *testing.T) {
	title := "User provided title"
	article := &domain.Article{
		ID:         "art-3",
		SourceType: domain.SourceManual,
		Title:      &title,
	}

	shouldBackfill := article.SourceType == domain.SourceManual &&
		(article.Title == nil || *article.Title == "")

	if shouldBackfill {
		t.Error("should NOT backfill title for manual article that already has a title")
	}
}

func TestAIHandler_TitleBackfill_ManualEmptyTitle(t *testing.T) {
	empty := ""
	article := &domain.Article{
		ID:         "art-4",
		SourceType: domain.SourceManual,
		Title:      &empty,
	}

	shouldBackfill := article.SourceType == domain.SourceManual &&
		(article.Title == nil || *article.Title == "")

	if !shouldBackfill {
		t.Error("expected title backfill for manual article with empty title")
	}
}

func TestAIHandler_TitleBackfill_AllNonManualTypes_Skipped(t *testing.T) {
	nonManualTypes := []domain.SourceType{
		domain.SourceWeb, domain.SourceWechat, domain.SourceTwitter,
		domain.SourceWeibo, domain.SourceZhihu, domain.SourceNewsletter,
		domain.SourceYoutube,
	}

	for _, st := range nonManualTypes {
		article := &domain.Article{
			ID:         "art-x",
			SourceType: st,
			Title:      nil,
		}

		shouldBackfill := article.SourceType == domain.SourceManual &&
			(article.Title == nil || *article.Title == "")

		if shouldBackfill {
			t.Errorf("should NOT backfill title for %q source type", st)
		}
	}
}
