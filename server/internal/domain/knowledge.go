package domain

import "time"

type KnowledgeMode string

const (
	KnowledgeModeAsk   KnowledgeMode = "ask"
	KnowledgeModeSpark KnowledgeMode = "spark"
	KnowledgeModeLearn KnowledgeMode = "learn"
)

type KnowledgeStatus string

const (
	KnowledgeStatusAnswered             KnowledgeStatus = "answered"
	KnowledgeStatusInsufficientEvidence KnowledgeStatus = "insufficient_evidence"
)

type KnowledgeDocument struct {
	ArticleID        string
	Title            string
	Summary          string
	KeyPoints        []string
	SemanticKeywords []string
	MarkdownContent  string
	SiteName         *string
	CreatedAt        time.Time
	RecallScore      float64
}

type KnowledgeSource struct {
	ArticleID       string    `json:"article_id"`
	Title           string    `json:"title"`
	SiteName        *string   `json:"site_name,omitempty"`
	Summary         *string   `json:"summary,omitempty"`
	EvidenceSnippet *string   `json:"evidence_snippet,omitempty"`
	CreatedAt       time.Time `json:"created_at"`
	Relevance       float64   `json:"relevance"`
}

type KnowledgeAnswer struct {
	Status              KnowledgeStatus   `json:"status"`
	Answer              string            `json:"answer"`
	Sources             []KnowledgeSource `json:"sources"`
	CitedIndices        []int             `json:"cited_indices"`
	FollowupSuggestions []string          `json:"followup_suggestions"`
}

type KnowledgeSparkInsight struct {
	Insight          string   `json:"insight"`
	WhyItMatters     string   `json:"why_it_matters"`
	SourceIDs        []string `json:"source_ids"`
	FollowupQuestion string   `json:"followup_question"`
}

type KnowledgeSparkResult struct {
	Insights []KnowledgeSparkInsight `json:"insights"`
	Sources  []KnowledgeSource       `json:"sources,omitempty"`
}

type KnowledgeLearnItem struct {
	Type      string   `json:"type"`
	Title     string   `json:"title"`
	Content   string   `json:"content"`
	SourceIDs []string `json:"source_ids"`
}

type KnowledgeLearnResult struct {
	Summary string               `json:"summary"`
	Items   []KnowledgeLearnItem `json:"items"`
	Sources []KnowledgeSource    `json:"sources,omitempty"`
}
