package worker

import (
	"errors"
	"testing"
	"time"

	"folio-server/internal/pipeline"
)

func TestBuildTaskFailure_FromPipelineError(t *testing.T) {
	err := pipeline.Wrap(
		pipeline.StageCrawlReader,
		pipeline.ProviderReader,
		pipeline.CodeTimeout,
		true,
		504,
		"reader request timed out",
		errors.New("context deadline exceeded"),
	)

	failure := buildTaskFailure(err, 1500*time.Millisecond)

	if failure.Message == "" {
		t.Fatal("Message should not be empty")
	}
	if failure.Stage == nil || *failure.Stage != "crawl_reader" {
		t.Fatalf("Stage = %v, want crawl_reader", failure.Stage)
	}
	if failure.Code == nil || *failure.Code != "timeout" {
		t.Fatalf("Code = %v, want timeout", failure.Code)
	}
	if failure.Provider == nil || *failure.Provider != "reader" {
		t.Fatalf("Provider = %v, want reader", failure.Provider)
	}
	if failure.Retryable == nil || !*failure.Retryable {
		t.Fatalf("Retryable = %v, want true", failure.Retryable)
	}
	if failure.DurationMs == nil || *failure.DurationMs != 1500 {
		t.Fatalf("DurationMs = %v, want 1500", failure.DurationMs)
	}
}

func TestBuildTaskFailure_FromPlainError(t *testing.T) {
	failure := buildTaskFailure(errors.New("database write failed"), 42*time.Millisecond)

	if failure.Message != "database write failed" {
		t.Fatalf("Message = %q, want %q", failure.Message, "database write failed")
	}
	if failure.Stage != nil || failure.Code != nil || failure.Provider != nil || failure.Retryable != nil {
		t.Fatal("plain errors should not set structured pipeline metadata")
	}
	if failure.DurationMs == nil || *failure.DurationMs != 42 {
		t.Fatalf("DurationMs = %v, want 42", failure.DurationMs)
	}
}
