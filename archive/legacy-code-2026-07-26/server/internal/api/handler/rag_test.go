package handler

import (
	"encoding/json"
	"testing"
	"time"

	"folio-server/internal/domain"
)

func TestDomainSourcesToResponseMapsEvidenceSnippet(t *testing.T) {
	siteName := "Example"
	summary := "Article summary"
	evidenceSnippet := "Matched evidence from retrieval"

	sources := domainSourcesToResponse([]domain.RAGSource{{
		ArticleID:       "article-1",
		Title:           "A grounded answer",
		SiteName:        &siteName,
		Summary:         &summary,
		EvidenceSnippet: &evidenceSnippet,
		CreatedAt:       time.Date(2026, 4, 26, 12, 30, 0, 0, time.FixedZone("UTC+8", 8*60*60)),
		Relevance:       0.92,
	}})

	if len(sources) != 1 {
		t.Fatalf("source count = %d, want 1", len(sources))
	}
	if sources[0].EvidenceSnippet == nil || *sources[0].EvidenceSnippet != evidenceSnippet {
		t.Fatalf("evidence snippet = %v, want %q", sources[0].EvidenceSnippet, evidenceSnippet)
	}
	if sources[0].CreatedAt != "2026-04-26T04:30:00Z" {
		t.Fatalf("created_at = %q, want UTC timestamp", sources[0].CreatedAt)
	}

	payload, err := json.Marshal(sources[0])
	if err != nil {
		t.Fatalf("marshal source response: %v", err)
	}
	var body map[string]any
	if err := json.Unmarshal(payload, &body); err != nil {
		t.Fatalf("unmarshal source response: %v", err)
	}
	if body["evidence_snippet"] != evidenceSnippet {
		t.Fatalf("evidence_snippet JSON = %v, want %q", body["evidence_snippet"], evidenceSnippet)
	}
}
