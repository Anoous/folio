package worker

import (
	"context"
	"errors"
	"testing"
	"time"

	"folio-server/internal/client"
	"folio-server/internal/repository"
)

type failingAIResultArticleRepo struct{}

func (f failingAIResultArticleRepo) UpdateAIResult(ctx context.Context, id string, ai repository.AIResult) error {
	return errors.New("database unavailable")
}

func TestAIResultPersister_MapsAnalyzeResponse(t *testing.T) {
	articleRepo := newMockAIArticleRepo()
	taskRepo := newMockAITaskRepo()
	persister := aiResultPersister{
		articleRepo: articleRepo,
		taskRepo:    taskRepo,
	}

	err := persister.persist(context.Background(), resultPersisterTestPayload(), &client.AnalyzeResponse{
		Summary:          "Summary",
		KeyPoints:        []string{"point 1"},
		Confidence:       0.88,
		Language:         "en",
		SemanticKeywords: []string{"go", "architecture"},
	}, "cat-tech", time.Now())
	if err != nil {
		t.Fatalf("persist() error = %v", err)
	}

	stored := articleRepo.updatedAI["art-1"]
	if stored.CategoryID != "cat-tech" || stored.Summary != "Summary" || stored.Confidence != 0.88 || stored.Language != "en" {
		t.Fatalf("stored AI result = %+v, want mapped fields", stored)
	}
	if len(stored.SemanticKeywords) != 2 || stored.SemanticKeywords[1] != "architecture" {
		t.Fatalf("SemanticKeywords = %v, want mapped keywords", stored.SemanticKeywords)
	}
	if len(taskRepo.failed) != 0 {
		t.Fatalf("failed tasks = %v, want none", taskRepo.failed)
	}
}

func TestAIResultPersister_MarksTaskFailedOnPersistError(t *testing.T) {
	taskRepo := newMockAITaskRepo()
	persister := aiResultPersister{
		articleRepo: failingAIResultArticleRepo{},
		taskRepo:    taskRepo,
	}

	err := persister.persist(context.Background(), resultPersisterTestPayload(), &client.AnalyzeResponse{
		Summary: "Summary",
	}, "cat-tech", time.Now())
	if err == nil {
		t.Fatal("persist() error = nil, want error")
	}

	failure, ok := taskRepo.failed["task-1"]
	if !ok {
		t.Fatal("task should be marked failed")
	}
	if failure.Provider == nil || *failure.Provider != "deepseek" {
		t.Fatalf("failure provider = %v, want deepseek", failure.Provider)
	}
	if failure.Code == nil || *failure.Code != "internal" {
		t.Fatalf("failure code = %v, want internal", failure.Code)
	}
}

func resultPersisterTestPayload() AIProcessPayload {
	return AIProcessPayload{
		ArticleID: "art-1",
		TaskID:    "task-1",
		UserID:    "user-1",
	}
}
