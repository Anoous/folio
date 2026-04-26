package service

import (
	"context"
	"testing"
)

func TestKnowledgeSparkSourceCollector_EmptyPromptUsesAllDocuments(t *testing.T) {
	repo := &mockKnowledgeRepo{
		docs: []KnowledgeDocument{
			benchmarkDoc("a1", "One", "One summary"),
			benchmarkDoc("a2", "Two", "Two summary"),
			benchmarkDoc("a3", "Three", "Three summary"),
			benchmarkDoc("a4", "Four", "Four summary"),
			benchmarkDoc("a5", "Five", "Five summary"),
			benchmarkDoc("a6", "Six", "Six summary"),
		},
	}
	collector := knowledgeSparkSourceCollector{
		repo: repo,
		retrieve: func(ctx context.Context, userID, query string, opts KnowledgeRetrieveOptions) (*KnowledgeContext, error) {
			t.Fatal("retrieve should not be called for empty prompt")
			return nil, nil
		},
	}

	sources, err := collector.collect(context.Background(), "user-1", "   ")
	if err != nil {
		t.Fatalf("collect() error = %v", err)
	}
	if repo.listCalls != 1 {
		t.Fatalf("list calls = %d, want 1", repo.listCalls)
	}
	if len(sources) != 6 {
		t.Fatalf("sources = %d, want 6", len(sources))
	}
	if sources[0].ArticleID != "a1" || sources[0].Summary == nil || *sources[0].Summary != "One summary" {
		t.Fatalf("first source = %+v, want mapped document", sources[0])
	}
	for _, source := range sources {
		if source.Relevance != 1 {
			t.Fatalf("source relevance = %v, want 1 for empty-prompt sources", source.Relevance)
		}
	}
}

func TestKnowledgeSparkSourceCollector_FillsPromptedSourcesWithoutDuplicates(t *testing.T) {
	repo := &mockKnowledgeRepo{
		docs: []KnowledgeDocument{
			benchmarkDoc("a1", "One", "One summary"),
			benchmarkDoc("a2", "Two", "Two summary"),
			benchmarkDoc("a3", "Three", "Three summary"),
			benchmarkDoc("a4", "Four", "Four summary"),
			benchmarkDoc("a5", "Five", "Five summary"),
			benchmarkDoc("a6", "Six", "Six summary"),
		},
	}
	retrieveCalls := 0
	collector := knowledgeSparkSourceCollector{
		repo: repo,
		retrieve: func(ctx context.Context, userID, query string, opts KnowledgeRetrieveOptions) (*KnowledgeContext, error) {
			retrieveCalls++
			if userID != "user-1" || query != "systems" || opts.Mode != KnowledgeModeSpark || opts.MaxSources != 8 {
				t.Fatalf("retrieve args = user:%s query:%s opts:%+v", userID, query, opts)
			}
			return &KnowledgeContext{
				Sources: []KnowledgeSource{
					{ArticleID: "a1", Title: "One", Summary: strPtr("Retrieved summary"), Relevance: 0.9},
				},
			}, nil
		},
	}

	sources, err := collector.collect(context.Background(), "user-1", "systems")
	if err != nil {
		t.Fatalf("collect() error = %v", err)
	}
	if retrieveCalls != 1 {
		t.Fatalf("retrieve calls = %d, want 1", retrieveCalls)
	}
	if repo.listCalls != 1 {
		t.Fatalf("list calls = %d, want 1 fill pass", repo.listCalls)
	}
	if got := sourceIDs(sources); len(got) != 6 || countString(got, "a1") != 1 || got[0] != "a1" || got[1] != "a2" {
		t.Fatalf("source IDs = %v, want retrieved source plus unique fill", got)
	}
	if sources[0].Relevance != 0.9 {
		t.Fatalf("retrieved relevance = %v, want unchanged", sources[0].Relevance)
	}
	if sources[1].Relevance != 0.5 {
		t.Fatalf("filled relevance = %v, want 0.5", sources[1].Relevance)
	}
}
