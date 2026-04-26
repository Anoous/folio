package service

import (
	"context"
	"fmt"
	"testing"
	"time"
)

func TestEvidenceServiceNilRepositoryReturnsInsufficientContext(t *testing.T) {
	svc := NewEvidenceService(nil, nil, nil)

	ctx, err := svc.Retrieve(context.Background(), "user-1", "  structured logs  ", EvidenceRetrieveOptions{})
	if err != nil {
		t.Fatalf("Retrieve() error = %v", err)
	}
	if ctx.Query != "structured logs" {
		t.Fatalf("query = %q, want trimmed query", ctx.Query)
	}
	if !ctx.Insufficient {
		t.Fatalf("Retrieve() should return insufficient context without a repository")
	}
	if len(ctx.Sources) != 0 {
		t.Fatalf("sources = %v, want empty", ctx.Sources)
	}
}

func TestEvidenceServiceDefaultMaxSourcesCapsReturnedSources(t *testing.T) {
	docs := make([]KnowledgeDocument, 0, 6)
	for i := 0; i < 6; i++ {
		docs = append(docs, KnowledgeDocument{
			ArticleID:        fmt.Sprintf("doc-%d", i),
			Title:            fmt.Sprintf("Lunar spool latency pattern %d", i),
			Summary:          "The lunar spool latency pattern is the exact evidence for this retrieval test.",
			KeyPoints:        []string{"lunar spool latency pattern"},
			SemanticKeywords: []string{"lunar spool latency pattern", "operations"},
			MarkdownContent:  "The lunar spool latency pattern appears in the body as grounded evidence.",
			CreatedAt:        time.Date(2026, 4, 17, 12-i, 0, 0, 0, time.UTC),
		})
	}
	repo := &mockKnowledgeRepo{docs: docs}
	svc := NewEvidenceService(repo, nil, nil)

	ctx, err := svc.Retrieve(context.Background(), "user-1", "lunar spool latency pattern", EvidenceRetrieveOptions{})
	if err != nil {
		t.Fatalf("Retrieve() error = %v", err)
	}
	if ctx.Insufficient {
		t.Fatalf("Retrieve() should find evidence")
	}
	if len(ctx.Sources) != 5 {
		t.Fatalf("source count = %d, want default cap 5", len(ctx.Sources))
	}
	for _, source := range ctx.Sources {
		if source.EvidenceSnippet == nil || *source.EvidenceSnippet == "" {
			t.Fatalf("source %s missing evidence snippet", source.ArticleID)
		}
	}
}
