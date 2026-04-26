package worker

import (
	"context"
	"errors"
	"testing"
	"time"

	"folio-server/internal/client"
	"folio-server/internal/domain"
)

type recordingAnalyzer struct {
	requests []client.AnalyzeRequest
	response *client.AnalyzeResponse
	err      error
}

func (r *recordingAnalyzer) Analyze(ctx context.Context, req client.AnalyzeRequest) (*client.AnalyzeResponse, error) {
	r.requests = append(r.requests, req)
	return r.response, r.err
}

type recordingAIAnalysisArticleRepo struct {
	statuses map[string]domain.ArticleStatus
	errors   map[string]string
}

func (r *recordingAIAnalysisArticleRepo) UpdateStatus(ctx context.Context, id string, status domain.ArticleStatus) error {
	r.statuses[id] = status
	return nil
}

func (r *recordingAIAnalysisArticleRepo) SetError(ctx context.Context, id string, errMsg string) error {
	r.errors[id] = errMsg
	return nil
}

type recordingAIAnalysisTaskRepo struct {
	startErr error
	started  []string
	failed   map[string]domain.TaskFailure
}

func (r *recordingAIAnalysisTaskRepo) SetAIStarted(ctx context.Context, id string) error {
	r.started = append(r.started, id)
	return r.startErr
}

func (r *recordingAIAnalysisTaskRepo) SetFailed(ctx context.Context, id string, failure domain.TaskFailure) error {
	r.failed[id] = failure
	return nil
}

func TestAIAnalysisRunner_SuccessStartsAndCallsAnalyzer(t *testing.T) {
	analyzer := &recordingAnalyzer{
		response: &client.AnalyzeResponse{Summary: "Summary"},
	}
	taskRepo := &recordingAIAnalysisTaskRepo{failed: map[string]domain.TaskFailure{}}
	articleRepo := &recordingAIAnalysisArticleRepo{
		statuses: map[string]domain.ArticleStatus{},
		errors:   map[string]string{},
	}
	runner := aiAnalysisRunner{
		aiClient:    analyzer,
		articleRepo: articleRepo,
		taskRepo:    taskRepo,
	}

	result, err := runner.run(context.Background(), analysisRunnerTestPayload(), time.Now())
	if err != nil {
		t.Fatalf("run() error = %v", err)
	}
	if result.done {
		t.Fatal("result.done = true, want false on success")
	}
	if result.response == nil || result.response.Summary != "Summary" {
		t.Fatalf("response = %+v, want analyzer response", result.response)
	}
	if len(taskRepo.started) != 1 || taskRepo.started[0] != "task-1" {
		t.Fatalf("started = %v, want [task-1]", taskRepo.started)
	}
	if len(analyzer.requests) != 1 {
		t.Fatalf("analyzer requests = %d, want 1", len(analyzer.requests))
	}
	req := analyzer.requests[0]
	if req.Title != "Title" || req.Content != "# Markdown" || req.Source != "web" || req.Author != "Author" {
		t.Fatalf("analyze request = %+v, want payload fields", req)
	}
	if len(taskRepo.failed) != 0 || len(articleRepo.errors) != 0 || len(articleRepo.statuses) != 0 {
		t.Fatalf("unexpected failure side effects: failed=%v errors=%v statuses=%v", taskRepo.failed, articleRepo.errors, articleRepo.statuses)
	}
}

func TestAIAnalysisRunner_AnalyzeFailureMarksTaskFailedAndArticleReady(t *testing.T) {
	analyzer := &recordingAnalyzer{err: errors.New("model unavailable")}
	taskRepo := &recordingAIAnalysisTaskRepo{failed: map[string]domain.TaskFailure{}}
	articleRepo := &recordingAIAnalysisArticleRepo{
		statuses: map[string]domain.ArticleStatus{},
		errors:   map[string]string{},
	}
	runner := aiAnalysisRunner{
		aiClient:    analyzer,
		articleRepo: articleRepo,
		taskRepo:    taskRepo,
	}

	result, err := runner.run(context.Background(), analysisRunnerTestPayload(), time.Now())
	if err != nil {
		t.Fatalf("run() error = %v", err)
	}
	if !result.done {
		t.Fatal("result.done = false, want true after handled analyze failure")
	}
	if _, ok := taskRepo.failed["task-1"]; !ok {
		t.Fatal("task should be marked failed")
	}
	if articleRepo.errors["art-1"] == "" {
		t.Fatal("article error should be set")
	}
	if articleRepo.statuses["art-1"] != domain.ArticleStatusReady {
		t.Fatalf("article status = %q, want ready", articleRepo.statuses["art-1"])
	}
}

func TestAIAnalysisRunner_StartFailureReturnsErrorWithoutAnalyze(t *testing.T) {
	analyzer := &recordingAnalyzer{response: &client.AnalyzeResponse{Summary: "Summary"}}
	taskRepo := &recordingAIAnalysisTaskRepo{
		startErr: errors.New("task store unavailable"),
		failed:   map[string]domain.TaskFailure{},
	}
	articleRepo := &recordingAIAnalysisArticleRepo{
		statuses: map[string]domain.ArticleStatus{},
		errors:   map[string]string{},
	}
	runner := aiAnalysisRunner{
		aiClient:    analyzer,
		articleRepo: articleRepo,
		taskRepo:    taskRepo,
	}

	_, err := runner.run(context.Background(), analysisRunnerTestPayload(), time.Now())
	if err == nil {
		t.Fatal("run() error = nil, want start error")
	}
	if len(analyzer.requests) != 0 {
		t.Fatalf("analyzer requests = %d, want 0", len(analyzer.requests))
	}
	if len(taskRepo.failed) != 0 || len(articleRepo.errors) != 0 {
		t.Fatalf("unexpected failure side effects: failed=%v errors=%v", taskRepo.failed, articleRepo.errors)
	}
}

func analysisRunnerTestPayload() AIProcessPayload {
	return AIProcessPayload{
		ArticleID: "art-1",
		TaskID:    "task-1",
		UserID:    "user-1",
		Title:     "Title",
		Markdown:  "# Markdown",
		Source:    "web",
		Author:    "Author",
	}
}
