package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/hibiken/asynq"

	"folio-server/internal/domain"
	"folio-server/internal/worker"
)

type fakeHighlightStore struct {
	createCalls     int
	created         *domain.Highlight
	createErr       error
	highlights      []domain.Highlight
	deleteCalls     int
	deleteArticleID string
	deleteErr       error
}

func (s *fakeHighlightStore) CreateHighlight(_ context.Context, h *domain.Highlight) error {
	s.createCalls++
	if s.createErr != nil {
		return s.createErr
	}
	if h.ID == "" {
		h.ID = "highlight-1"
	}
	h.CreatedAt = time.Date(2026, 4, 26, 0, 0, 0, 0, time.UTC)
	copied := *h
	s.created = &copied
	return nil
}

func (s *fakeHighlightStore) GetByArticle(_ context.Context, _, _ string) ([]domain.Highlight, error) {
	return append([]domain.Highlight(nil), s.highlights...), nil
}

func (s *fakeHighlightStore) DeleteHighlight(_ context.Context, _, _ string) (string, error) {
	s.deleteCalls++
	if s.deleteErr != nil {
		return "", s.deleteErr
	}
	return s.deleteArticleID, nil
}

type fakeHighlightArticleStore struct {
	article *domain.Article
	err     error
	calls   int
}

func (s *fakeHighlightArticleStore) GetByID(_ context.Context, _ string) (*domain.Article, error) {
	s.calls++
	if s.err != nil {
		return nil, s.err
	}
	return s.article, nil
}

type fakeHighlightEnqueuer struct {
	calls    int
	taskType string
	err      error
}

func (e *fakeHighlightEnqueuer) EnqueueContext(_ context.Context, task *asynq.Task, _ ...asynq.Option) (*asynq.TaskInfo, error) {
	e.calls++
	e.taskType = task.Type()
	if e.err != nil {
		return nil, e.err
	}
	return &asynq.TaskInfo{}, nil
}

func TestHighlightServiceCreateHighlightPersistsAndEnqueuesEcho(t *testing.T) {
	highlights := &fakeHighlightStore{}
	articles := &fakeHighlightArticleStore{article: &domain.Article{ID: "article-1", UserID: "user-1"}}
	enqueuer := &fakeHighlightEnqueuer{}
	svc := &HighlightService{highlightRepo: highlights, articleRepo: articles, asynqClient: enqueuer}

	highlight, err := svc.CreateHighlight(context.Background(), "user-1", "article-1", "important text", 2, 16)
	if err != nil {
		t.Fatalf("CreateHighlight() error = %v", err)
	}

	if highlight.ID != "highlight-1" {
		t.Fatalf("highlight ID = %q, want highlight-1", highlight.ID)
	}
	if highlights.createCalls != 1 {
		t.Fatalf("create calls = %d, want 1", highlights.createCalls)
	}
	if highlights.created == nil || highlights.created.ArticleID != "article-1" || highlights.created.Color != "yellow" {
		t.Fatalf("created highlight = %+v", highlights.created)
	}
	if enqueuer.calls != 1 || enqueuer.taskType != worker.TypeEchoGenerate {
		t.Fatalf("enqueued = %d %q, want one echo task", enqueuer.calls, enqueuer.taskType)
	}
}

func TestHighlightServiceCreateHighlightRejectsForeignArticle(t *testing.T) {
	highlights := &fakeHighlightStore{}
	articles := &fakeHighlightArticleStore{article: &domain.Article{ID: "article-1", UserID: "other-user"}}
	enqueuer := &fakeHighlightEnqueuer{}
	svc := &HighlightService{highlightRepo: highlights, articleRepo: articles, asynqClient: enqueuer}

	highlight, err := svc.CreateHighlight(context.Background(), "user-1", "article-1", "text", 0, 4)
	if !errors.Is(err, ErrForbidden) {
		t.Fatalf("CreateHighlight() error = %v, want ErrForbidden", err)
	}
	if highlight != nil {
		t.Fatalf("highlight = %+v, want nil", highlight)
	}
	if highlights.createCalls != 0 {
		t.Fatalf("create calls = %d, want 0", highlights.createCalls)
	}
	if enqueuer.calls != 0 {
		t.Fatalf("enqueue calls = %d, want 0", enqueuer.calls)
	}
}

func TestHighlightServiceDeleteHighlightDelegatesToStore(t *testing.T) {
	highlights := &fakeHighlightStore{deleteArticleID: "article-1"}
	svc := &HighlightService{highlightRepo: highlights}

	if err := svc.DeleteHighlight(context.Background(), "user-1", "highlight-1"); err != nil {
		t.Fatalf("DeleteHighlight() error = %v", err)
	}
	if highlights.deleteCalls != 1 {
		t.Fatalf("delete calls = %d, want 1", highlights.deleteCalls)
	}
}

func TestHighlightServiceDeleteHighlightReturnsNotFoundWhenStoreMisses(t *testing.T) {
	highlights := &fakeHighlightStore{}
	svc := &HighlightService{highlightRepo: highlights}

	err := svc.DeleteHighlight(context.Background(), "user-1", "missing-highlight")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("DeleteHighlight() error = %v, want ErrNotFound", err)
	}
}
