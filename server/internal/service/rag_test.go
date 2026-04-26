package service

import (
	"slices"
	"testing"
)

func TestExtractCitedIndices(t *testing.T) {
	tests := []struct {
		name     string
		answer   string
		expected []int
	}{
		{
			name:     "unicode superscripts",
			answer:   "根据收藏¹，技术趋势²已经改变³",
			expected: []int{1, 2, 3},
		},
		{
			name:     "bracket citations",
			answer:   "如文章所述[1]，另外[3]也提到",
			expected: []int{1, 3},
		},
		{
			name:     "mixed formats",
			answer:   "观点¹与[2]互补，另见³",
			expected: []int{1, 2, 3},
		},
		{
			name:     "duplicates removed",
			answer:   "引用¹和¹重复了",
			expected: []int{1},
		},
		{
			name:     "no citations",
			answer:   "没有引用任何文章",
			expected: []int{},
		},
		{
			name:     "high index superscripts 4-9",
			answer:   "⁴⁵⁶⁷⁸⁹",
			expected: []int{4, 5, 6, 7, 8, 9},
		},
		{
			name:     "multi-digit bracket",
			answer:   "参见[12]",
			expected: []int{12},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := extractCitedIndices(tt.answer)
			if len(tt.expected) == 0 && len(got) == 0 {
				return
			}
			slices.Sort(got)
			slices.Sort(tt.expected)
			if !slices.Equal(got, tt.expected) {
				t.Errorf("extractCitedIndices(%q) = %v, want %v", tt.answer, got, tt.expected)
			}
		})
	}
}

func TestKnowledgeSourcesToRAGSourcesPreservesEvidenceSnippet(t *testing.T) {
	summary := "Summary"
	evidenceSnippet := "Matched retrieval evidence"

	sources := knowledgeSourcesToRAGSources([]KnowledgeSource{{
		ArticleID:       "article-1",
		Title:           "Grounded source",
		Summary:         &summary,
		EvidenceSnippet: &evidenceSnippet,
		Relevance:       0.88,
	}})

	if len(sources) != 1 {
		t.Fatalf("source count = %d, want 1", len(sources))
	}
	if sources[0].EvidenceSnippet == nil || *sources[0].EvidenceSnippet != evidenceSnippet {
		t.Fatalf("evidence snippet = %v, want %q", sources[0].EvidenceSnippet, evidenceSnippet)
	}
	if sources[0].Summary == nil || *sources[0].Summary != summary {
		t.Fatalf("summary = %v, want %q", sources[0].Summary, summary)
	}
}
