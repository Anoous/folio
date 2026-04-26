package repository

import (
	"slices"
	"testing"
)

func TestPrepareKnowledgeRecallTerms_BuildsFullTextQuery(t *testing.T) {
	cleaned, escaped, queryText := prepareKnowledgeRecallTerms([]string{
		" Lunar ",
		"spool",
		"lunar",
		"latency pattern",
		"",
	})

	wantCleaned := []string{"lunar", "spool", "latency pattern"}
	if !slices.Equal(cleaned, wantCleaned) {
		t.Fatalf("cleaned = %v, want %v", cleaned, wantCleaned)
	}
	if !slices.Equal(escaped, wantCleaned) {
		t.Fatalf("escaped = %v, want %v", escaped, wantCleaned)
	}
	if queryText != `lunar spool "latency pattern"` {
		t.Fatalf("queryText = %q, want quoted phrase query", queryText)
	}
}
