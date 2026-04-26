package service

import (
	"context"
	"testing"
)

func TestKnowledgeLearnContextCollector_UsesPromptResultWhenSufficient(t *testing.T) {
	calls := []string{}
	stringPtr := func(s string) *string { return &s }
	collector := knowledgeLearnContextCollector{
		retrieve: func(ctx context.Context, userID, query string, opts KnowledgeRetrieveOptions) (*KnowledgeContext, error) {
			calls = append(calls, query)
			if userID != "user-1" || opts.Mode != KnowledgeModeLearn || opts.MaxSources != 6 {
				t.Fatalf("retrieve args = user:%s opts:%+v", userID, opts)
			}
			return &KnowledgeContext{
				Query: query,
				Sources: []KnowledgeSource{
					{ArticleID: "a1", Title: "One", Summary: stringPtr("One summary")},
				},
			}, nil
		},
	}

	result, err := collector.collect(context.Background(), "user-1", "active recall")
	if err != nil {
		t.Fatalf("collect() error = %v", err)
	}
	if result.Query != "active recall" {
		t.Fatalf("query = %q, want original prompt", result.Query)
	}
	if len(calls) != 1 || calls[0] != "active recall" {
		t.Fatalf("calls = %v, want prompt only", calls)
	}
}

func TestKnowledgeLearnContextCollector_FallsBackWhenPromptInsufficient(t *testing.T) {
	calls := []string{}
	stringPtr := func(s string) *string { return &s }
	collector := knowledgeLearnContextCollector{
		retrieve: func(ctx context.Context, userID, query string, opts KnowledgeRetrieveOptions) (*KnowledgeContext, error) {
			calls = append(calls, query)
			if query == "active recall" {
				return &KnowledgeContext{Query: query, Insufficient: true}, nil
			}
			return &KnowledgeContext{
				Query: query,
				Sources: []KnowledgeSource{
					{ArticleID: "review", Title: "Review", Summary: stringPtr("Review summary")},
				},
			}, nil
		},
	}

	result, err := collector.collect(context.Background(), "user-1", "active recall")
	if err != nil {
		t.Fatalf("collect() error = %v", err)
	}
	if result.Query != "knowledge learning review" {
		t.Fatalf("query = %q, want fallback query", result.Query)
	}
	if len(calls) != 2 || calls[0] != "active recall" || calls[1] != "knowledge learning review" {
		t.Fatalf("calls = %v, want prompt then fallback", calls)
	}
}
