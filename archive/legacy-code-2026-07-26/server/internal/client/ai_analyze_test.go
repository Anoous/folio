package client

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"folio-server/internal/pipeline"
)

func TestDeepSeekAnalyze_ClassifiesRateLimited(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
		_, _ = io.WriteString(w, `{"error":{"message":"rate limited"}}`)
	}))
	defer srv.Close()

	analyzer := NewDeepSeekAnalyzer("test-key", srv.URL)
	analyzer.httpClient = srv.Client()

	_, err := analyzer.Analyze(context.Background(), AnalyzeRequest{Title: "Example", Content: "Body"})
	if err == nil {
		t.Fatal("Analyze() error = nil, want classified pipeline error")
	}

	var pErr *pipeline.Error
	if !errors.As(err, &pErr) {
		t.Fatalf("error = %T, want *pipeline.Error", err)
	}
	if pErr.Stage != pipeline.StageAIAnalyze {
		t.Fatalf("Stage = %q, want %q", pErr.Stage, pipeline.StageAIAnalyze)
	}
	if pErr.Provider != pipeline.ProviderDeepSeek {
		t.Fatalf("Provider = %q, want %q", pErr.Provider, pipeline.ProviderDeepSeek)
	}
	if pErr.Code != pipeline.CodeRateLimited {
		t.Fatalf("Code = %q, want %q", pErr.Code, pipeline.CodeRateLimited)
	}
	if !pErr.Retryable {
		t.Fatal("Retryable = false, want true")
	}
}

func TestDeepSeekAnalyze_ClassifiesTransportTimeout(t *testing.T) {
	analyzer := NewDeepSeekAnalyzer("test-key", "https://deepseek.test")
	analyzer.httpClient = &http.Client{
		Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
			return nil, context.DeadlineExceeded
		}),
	}

	_, err := analyzer.Analyze(context.Background(), AnalyzeRequest{Title: "Example", Content: "Body"})
	if err == nil {
		t.Fatal("Analyze() error = nil, want timeout classification")
	}

	var pErr *pipeline.Error
	if !errors.As(err, &pErr) {
		t.Fatalf("error = %T, want *pipeline.Error", err)
	}
	if pErr.Code != pipeline.CodeTimeout {
		t.Fatalf("Code = %q, want %q", pErr.Code, pipeline.CodeTimeout)
	}
	if !pErr.Retryable {
		t.Fatal("Retryable = false, want true")
	}
}

func TestDeepSeekAnalyze_ClassifiesInvalidResponse(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"choices":[{"message":{"content":"not-json"}}]}`)
	}))
	defer srv.Close()

	analyzer := NewDeepSeekAnalyzer("test-key", srv.URL)
	analyzer.httpClient = srv.Client()

	_, err := analyzer.Analyze(context.Background(), AnalyzeRequest{Title: "Example", Content: "Body"})
	if err == nil {
		t.Fatal("Analyze() error = nil, want invalid response classification")
	}

	var pErr *pipeline.Error
	if !errors.As(err, &pErr) {
		t.Fatalf("error = %T, want *pipeline.Error", err)
	}
	if pErr.Code != pipeline.CodeInvalidResponse {
		t.Fatalf("Code = %q, want %q", pErr.Code, pipeline.CodeInvalidResponse)
	}
	if pErr.Retryable {
		t.Fatal("Retryable = true, want false")
	}
}
