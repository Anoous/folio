package pipeline

import (
	"errors"
	"strings"
	"testing"
)

func TestWrap_PreservesMetadataAndCause(t *testing.T) {
	cause := errors.New("upstream timed out")

	err := Wrap(
		StageCrawlReader,
		ProviderReader,
		CodeTimeout,
		true,
		504,
		"reader request timed out",
		cause,
	)

	if err.Stage != StageCrawlReader {
		t.Fatalf("Stage = %q, want %q", err.Stage, StageCrawlReader)
	}
	if err.Provider != ProviderReader {
		t.Fatalf("Provider = %q, want %q", err.Provider, ProviderReader)
	}
	if err.Code != CodeTimeout {
		t.Fatalf("Code = %q, want %q", err.Code, CodeTimeout)
	}
	if !err.Retryable {
		t.Fatal("Retryable = false, want true")
	}
	if err.StatusCode != 504 {
		t.Fatalf("StatusCode = %d, want 504", err.StatusCode)
	}
	if !errors.Is(err, cause) {
		t.Fatal("wrapped error should expose original cause")
	}
}

func TestErrorString_IncludesClassificationContext(t *testing.T) {
	err := Wrap(
		StageAIAnalyze,
		ProviderDeepSeek,
		CodeInvalidResponse,
		false,
		200,
		"decode response failed",
		errors.New("unexpected EOF"),
	)

	got := err.Error()
	for _, part := range []string{"ai_analyze", "deepseek", "invalid_response", "decode response failed", "unexpected EOF"} {
		if !strings.Contains(got, part) {
			t.Fatalf("Error() = %q, missing %q", got, part)
		}
	}
}

func TestAs_ReturnsTypedPipelineError(t *testing.T) {
	err := Wrap(StageCrawlJina, ProviderJina, CodeNetwork, true, 0, "request failed", errors.New("dial tcp"))

	got, ok := As(err)
	if !ok {
		t.Fatal("As() = false, want true")
	}
	if got != err {
		t.Fatal("As() should return the original typed error")
	}
}
