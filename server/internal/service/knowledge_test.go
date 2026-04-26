package service

import (
	"context"
	"errors"
	"slices"
	"strings"
	"testing"
	"time"
)

type mockKnowledgeRepo struct {
	docs       []KnowledgeDocument
	err        error
	listCalls  int
	lastUserID string
}

func (m *mockKnowledgeRepo) ListKnowledgeDocuments(_ context.Context, userID string) ([]KnowledgeDocument, error) {
	m.listCalls++
	m.lastUserID = userID
	if m.err != nil {
		return nil, m.err
	}
	return slices.Clone(m.docs), nil
}

type mockKnowledgeExpander struct {
	keywords  []string
	err       error
	callCount int
	lastQuery string
}

func (m *mockKnowledgeExpander) ExpandQuery(_ context.Context, query string) ([]string, error) {
	m.callCount++
	m.lastQuery = query
	if m.err != nil {
		return nil, m.err
	}
	return slices.Clone(m.keywords), nil
}

type mockKnowledgeRetriever struct {
	docs         []KnowledgeDocument
	responses    [][]KnowledgeDocument
	err          error
	callCount    int
	lastUserID   string
	lastKeywords []string
	callKeywords [][]string
	lastLimit    int
}

func (m *mockKnowledgeRetriever) BroadRecallKnowledgeDocuments(_ context.Context, userID string, keywords []string, limit int) ([]KnowledgeDocument, error) {
	callIndex := m.callCount
	m.callCount++
	m.lastUserID = userID
	m.lastKeywords = slices.Clone(keywords)
	m.callKeywords = append(m.callKeywords, slices.Clone(keywords))
	m.lastLimit = limit
	if m.err != nil {
		return nil, m.err
	}
	if len(m.responses) > 0 {
		if callIndex >= len(m.responses) {
			return []KnowledgeDocument{}, nil
		}
		return slices.Clone(m.responses[callIndex]), nil
	}
	return slices.Clone(m.docs), nil
}

func TestKnowledgeRetrieve_UsesHybridRecallWithoutFullScan(t *testing.T) {
	repo := &mockKnowledgeRepo{
		err: errors.New("full scan should not run on recall hit"),
	}
	expander := &mockKnowledgeExpander{
		keywords: []string{"service-level-objectives"},
	}
	retriever := &mockKnowledgeRetriever{
		docs: []KnowledgeDocument{
			benchmarkDoc("ds5", "SLOs and Structured Logs", "结构化日志和 SLO 让系统可观测、可追责、可恢复。"),
		},
	}

	svc := NewKnowledgeServiceWithRetrieval(repo, expander, retriever)

	ctx, err := svc.Retrieve(context.Background(), "user-1", "为什么结构化日志、SLO 对可靠服务重要？", KnowledgeRetrieveOptions{
		Mode:       KnowledgeModeAsk,
		MaxSources: 3,
	})
	if err != nil {
		t.Fatalf("Retrieve() error = %v", err)
	}
	if retriever.callCount == 0 {
		t.Fatalf("retriever call count = %d, want at least 1", retriever.callCount)
	}
	if repo.listCalls != 0 {
		t.Fatalf("full scan should not run when broad recall hits, got %d calls", repo.listCalls)
	}
	if expander.callCount != 1 {
		t.Fatalf("expander call count = %d, want 1", expander.callCount)
	}
	if len(ctx.Sources) != 1 || ctx.Sources[0].ArticleID != "ds5" {
		t.Fatalf("Retrieve() sources = %v, want ds5", sourceIDs(ctx.Sources))
	}
	if !retrieverCallsContainKeyword(retriever.callKeywords, "service level objectives") {
		t.Fatalf("expanded keyword missing from retriever input: %v", retriever.callKeywords)
	}
}

func TestKnowledgeRetrieve_BroadRecallReceivesExactPhrases(t *testing.T) {
	repo := &mockKnowledgeRepo{
		err: errors.New("full scan should not run on recall hit"),
	}
	retriever := &mockKnowledgeRetriever{
		docs: []KnowledgeDocument{
			{
				ArticleID:        "phrase",
				Title:            "Operations note",
				Summary:          "A body-only exact phrase should still drive recall.",
				KeyPoints:        []string{},
				SemanticKeywords: []string{"operations"},
				MarkdownContent:  "The hidden anchor phrase is lunar spool latency pattern.",
				CreatedAt:        time.Date(2026, 4, 17, 12, 0, 0, 0, time.UTC),
			},
		},
	}

	svc := NewKnowledgeServiceWithRetrieval(repo, nil, retriever)

	ctx, err := svc.Retrieve(context.Background(), "user-1", "lunar spool latency pattern", KnowledgeRetrieveOptions{
		Mode:       KnowledgeModeAsk,
		MaxSources: 3,
	})
	if err != nil {
		t.Fatalf("Retrieve() error = %v", err)
	}
	if ctx.Insufficient {
		t.Fatalf("Retrieve() should use exact-phrase fan-out before falling back")
	}
	if !retrieverCallsContainKeyword(retriever.callKeywords, "lunar spool latency pattern") {
		t.Fatalf("retriever keywords = %v, want exact phrase fan-out", retriever.callKeywords)
	}
}

func TestKnowledgeRetrieve_FusesRecallPathsAndDeduplicates(t *testing.T) {
	phraseDoc := KnowledgeDocument{
		ArticleID:        "phrase",
		Title:            "Operations anomaly note",
		Summary:          "The incident note preserves the exact lunar spool latency pattern.",
		KeyPoints:        []string{"exact phrase evidence"},
		SemanticKeywords: []string{"operations", "latency"},
		MarkdownContent:  "The hidden anchor phrase is lunar spool latency pattern.",
		CreatedAt:        time.Date(2026, 4, 17, 12, 0, 0, 0, time.UTC),
	}
	keywordDoc := KnowledgeDocument{
		ArticleID:        "keyword",
		Title:            "Operations latency runbook",
		Summary:          "Operations teams track latency patterns and escalation paths.",
		KeyPoints:        []string{"operations latency pattern"},
		SemanticKeywords: []string{"operations", "latency", "runbook"},
		MarkdownContent:  "Runbooks explain how operations teams respond when latency patterns appear.",
		CreatedAt:        time.Date(2026, 4, 16, 12, 0, 0, 0, time.UTC),
	}
	repo := &mockKnowledgeRepo{
		err: errors.New("full scan should not run when fused recall hits"),
	}
	retriever := &mockKnowledgeRetriever{
		responses: [][]KnowledgeDocument{
			{phraseDoc},
			{keywordDoc, phraseDoc},
		},
	}

	svc := NewKnowledgeServiceWithRetrieval(repo, nil, retriever)

	ctx, err := svc.Retrieve(context.Background(), "user-1", "lunar spool latency pattern operations", KnowledgeRetrieveOptions{
		Mode:       KnowledgeModeAsk,
		MaxSources: 5,
	})
	if err != nil {
		t.Fatalf("Retrieve() error = %v", err)
	}
	if retriever.callCount < 2 {
		t.Fatalf("retriever call count = %d, want multiple fan-out paths", retriever.callCount)
	}
	ids := sourceIDs(ctx.Sources)
	if !slices.Contains(ids, "phrase") || !slices.Contains(ids, "keyword") {
		t.Fatalf("Retrieve() sources = %v, want fused phrase and keyword candidates", ids)
	}
	if countString(ids, "phrase") != 1 {
		t.Fatalf("Retrieve() sources = %v, want deduplicated phrase candidate", ids)
	}
}

func TestKnowledgeRetrieve_FallsBackToFullScanWhenRecallMisses(t *testing.T) {
	repo := &mockKnowledgeRepo{
		docs: []KnowledgeDocument{
			benchmarkDoc("prod2", "Default Context Wins", "系统应默认选择上下文，而不是把选择权转移给用户。"),
		},
	}
	retriever := &mockKnowledgeRetriever{}
	expander := &mockKnowledgeExpander{}

	svc := NewKnowledgeServiceWithRetrieval(repo, expander, retriever)

	ctx, err := svc.Retrieve(context.Background(), "user-1", "为什么不能让用户手动选文章做上下文？", KnowledgeRetrieveOptions{
		Mode:       KnowledgeModeAsk,
		MaxSources: 3,
	})
	if err != nil {
		t.Fatalf("Retrieve() error = %v", err)
	}
	if retriever.callCount == 0 {
		t.Fatalf("retriever call count = %d, want at least 1", retriever.callCount)
	}
	if repo.listCalls != 1 {
		t.Fatalf("full scan should run once on recall miss, got %d calls", repo.listCalls)
	}
	if ctx.Insufficient {
		t.Fatalf("Retrieve() should recover via full scan")
	}
	if len(ctx.Sources) != 1 || ctx.Sources[0].ArticleID != "prod2" {
		t.Fatalf("Retrieve() sources = %v, want prod2", sourceIDs(ctx.Sources))
	}
}

func TestKnowledgeRetrieve_ContinuesWhenExpansionFails(t *testing.T) {
	repo := &mockKnowledgeRepo{
		docs: []KnowledgeDocument{
			benchmarkDoc("learn16", "Active Recall Beats Passive Review", "主动回忆比被动重读更能形成长期记忆。"),
		},
	}
	expander := &mockKnowledgeExpander{
		err: errors.New("expand failed"),
	}
	retriever := &mockKnowledgeRetriever{
		err: errors.New("retriever unavailable"),
	}

	svc := NewKnowledgeServiceWithRetrieval(repo, expander, retriever)

	ctx, err := svc.Retrieve(context.Background(), "user-1", "为什么学习功能需要主动回忆题？", KnowledgeRetrieveOptions{
		Mode:       KnowledgeModeLearn,
		MaxSources: 3,
	})
	if err != nil {
		t.Fatalf("Retrieve() error = %v", err)
	}
	if ctx.Insufficient {
		t.Fatalf("Retrieve() should fall back to repository scan when expansion/recall fail")
	}
	if len(ctx.Sources) != 1 || ctx.Sources[0].ArticleID != "learn16" {
		t.Fatalf("Retrieve() sources = %v, want learn16", sourceIDs(ctx.Sources))
	}
	if repo.listCalls != 1 {
		t.Fatalf("full scan call count = %d, want 1", repo.listCalls)
	}
}

func TestKnowledgeRetrieve_PrefersExactPhraseOverKeywordScatter(t *testing.T) {
	repo := &mockKnowledgeRepo{
		docs: []KnowledgeDocument{
			{
				ArticleID:        "exact",
				Title:            "Observability First",
				Summary:          "Structured logs and SLOs reveal where user pain starts and which failure modes deserve engineering time.",
				KeyPoints:        []string{"structured logs and slos reveal where user pain starts"},
				SemanticKeywords: []string{"structured logs", "slos", "observability"},
				MarkdownContent:  "Reliable systems need observability before they need dashboards. Structured logs and SLOs reveal where user pain starts and which failure modes deserve engineering time.",
				CreatedAt:        time.Date(2026, 4, 16, 12, 0, 0, 0, time.UTC),
			},
			{
				ArticleID:        "scatter",
				Title:            "Logs, Users, Pain, Failures, Time",
				Summary:          "This note mentions structured systems, logs, SLOs, user pain, failure modes, and engineering time, but never as one coherent claim.",
				KeyPoints:        []string{"structured", "logs", "slos", "user pain", "failure modes", "engineering time"},
				SemanticKeywords: []string{"structured", "logs", "slos", "user", "pain", "failure"},
				MarkdownContent:  "The words appear here separately: structured. logs. SLOs. user pain. failure modes. engineering time.",
				CreatedAt:        time.Date(2026, 4, 16, 11, 0, 0, 0, time.UTC),
			},
		},
	}

	svc := NewKnowledgeService(repo)

	ctx, err := svc.Retrieve(context.Background(), "user-1", "structured logs and slos reveal where user pain starts", KnowledgeRetrieveOptions{
		Mode:       KnowledgeModeAsk,
		MaxSources: 2,
	})
	if err != nil {
		t.Fatalf("Retrieve() error = %v", err)
	}
	if len(ctx.Sources) != 2 {
		t.Fatalf("Retrieve() source count = %d, want 2", len(ctx.Sources))
	}
	if ctx.Sources[0].ArticleID != "exact" {
		t.Fatalf("top source = %q, want exact", ctx.Sources[0].ArticleID)
	}
	if ctx.Sources[0].Relevance <= ctx.Sources[1].Relevance {
		t.Fatalf("exact phrase source should outrank scatter source: %+v", ctx.Sources)
	}
}

func TestKnowledgeRetrieve_ReturnsEvidenceSnippetFromMatchingField(t *testing.T) {
	repo := &mockKnowledgeRepo{
		docs: []KnowledgeDocument{
			{
				ArticleID:        "ds5",
				Title:            "Observability First: Structured Logs and SLOs",
				Summary:          "Structured logs, traces, and service level objectives turn incidents from guesswork into measurable feedback loops.",
				KeyPoints:        []string{"structured logs speed up debugging"},
				SemanticKeywords: []string{"structured logs", "slos", "observability"},
				MarkdownContent:  "Reliable systems need observability before they need dashboards. Structured logs, traces, and service level objectives turn incidents from guesswork into measurable feedback loops.",
				CreatedAt:        time.Date(2026, 4, 16, 12, 0, 0, 0, time.UTC),
			},
		},
	}

	svc := NewKnowledgeService(repo)

	ctx, err := svc.Retrieve(context.Background(), "user-1", "guesswork into measurable feedback loops", KnowledgeRetrieveOptions{
		Mode:       KnowledgeModeAsk,
		MaxSources: 1,
	})
	if err != nil {
		t.Fatalf("Retrieve() error = %v", err)
	}
	if len(ctx.Sources) != 1 {
		t.Fatalf("Retrieve() source count = %d, want 1", len(ctx.Sources))
	}
	if ctx.Sources[0].EvidenceSnippet == nil || strings.TrimSpace(*ctx.Sources[0].EvidenceSnippet) == "" {
		t.Fatalf("Retrieve() must return a non-empty evidence snippet: %+v", ctx.Sources[0])
	}
	if !strings.Contains(strings.ToLower(*ctx.Sources[0].EvidenceSnippet), "guesswork into measurable feedback loops") {
		t.Fatalf("evidence snippet %q must contain the matching phrase", *ctx.Sources[0].EvidenceSnippet)
	}
}

func TestKnowledgeRetrieve_SnippetPrefersExactPhraseOverTitleKeyword(t *testing.T) {
	repo := &mockKnowledgeRepo{
		docs: []KnowledgeDocument{
			{
				ArticleID:        "direct-hit",
				Title:            "Direct hit",
				Summary:          "Direct search summary mentions direct evidence.",
				KeyPoints:        []string{},
				SemanticKeywords: []string{"direct"},
				MarkdownContent:  "Direct evidence stays attached without changing result ordering.",
				CreatedAt:        time.Date(2026, 4, 17, 12, 0, 0, 0, time.UTC),
			},
		},
	}

	svc := NewKnowledgeService(repo)

	ctx, err := svc.Retrieve(context.Background(), "user-1", "direct evidence", KnowledgeRetrieveOptions{
		Mode:       KnowledgeModeAsk,
		MaxSources: 1,
	})
	if err != nil {
		t.Fatalf("Retrieve() error = %v", err)
	}
	if len(ctx.Sources) != 1 {
		t.Fatalf("Retrieve() source count = %d, want 1", len(ctx.Sources))
	}
	if ctx.Sources[0].EvidenceSnippet == nil || !strings.Contains(strings.ToLower(*ctx.Sources[0].EvidenceSnippet), "direct evidence") {
		t.Fatalf("evidence snippet %v must prefer the exact phrase over title keyword", ctx.Sources[0].EvidenceSnippet)
	}
}

func TestKnowledgeAnswerGroundingRejectsInvalidCitation(t *testing.T) {
	answer := &KnowledgeAnswer{
		Status:       KnowledgeStatusAnswered,
		Answer:       "Supported claim¹ and hallucinated claim².",
		Sources:      []KnowledgeSource{{ArticleID: "a1", Title: "One", EvidenceSnippet: strPtr("Supported claim")}},
		CitedIndices: []int{1, 2},
	}

	if isKnowledgeAnswerGrounded(answer) {
		t.Fatalf("answer with out-of-range citation should not be grounded")
	}
}

func TestSparkGroundingFiltersInvalidAndDuplicateInsights(t *testing.T) {
	sources := []KnowledgeSource{
		{ArticleID: "a1", Title: "One", Summary: strPtr("One summary")},
		{ArticleID: "a2", Title: "Two", Summary: strPtr("Two summary")},
	}
	insights := []KnowledgeSparkInsight{
		{Insight: "连接可靠性和信任", WhyItMatters: "有来源支撑", SourceIDs: []string{"a1", "a2"}, FollowupQuestion: "继续问？"},
		{Insight: "连接可靠性和信任", WhyItMatters: "重复", SourceIDs: []string{"a1", "a2"}, FollowupQuestion: "重复？"},
		{Insight: "无效来源", WhyItMatters: "缺来源", SourceIDs: []string{"a1", "missing"}, FollowupQuestion: "无效？"},
	}

	result := groundSparkResult(insights, sources)
	if len(result.Insights) != 1 {
		t.Fatalf("grounded insight count = %d, want 1", len(result.Insights))
	}
	if len(result.Sources) != 2 {
		t.Fatalf("grounded sources count = %d, want 2", len(result.Sources))
	}
}

func TestLearnGroundingFiltersUnsupportedItems(t *testing.T) {
	sources := []KnowledgeSource{
		{ArticleID: "a1", Title: "One", Summary: strPtr("One summary")},
	}
	result := &KnowledgeLearnResult{
		Summary: "Summary",
		Items: []KnowledgeLearnItem{
			{Type: "concept", Title: "Grounded", Content: "One summary", SourceIDs: []string{"a1"}},
			{Type: "concept", Title: "Unsupported", Content: "No source", SourceIDs: []string{"missing"}},
		},
	}

	grounded := groundLearnResult(result, sources)
	if len(grounded.Items) != 1 {
		t.Fatalf("grounded item count = %d, want 1", len(grounded.Items))
	}
	if len(grounded.Sources) != 1 || grounded.Sources[0].ArticleID != "a1" {
		t.Fatalf("grounded sources = %+v, want only a1", grounded.Sources)
	}
}

func benchmarkDoc(id, title, summary string) KnowledgeDocument {
	now := time.Date(2026, 4, 16, 12, 0, 0, 0, time.UTC)
	return KnowledgeDocument{
		ArticleID:        id,
		Title:            title,
		Summary:          summary,
		KeyPoints:        []string{summary},
		SemanticKeywords: expandKnowledgeTerms(title + " " + summary),
		MarkdownContent:  summary,
		CreatedAt:        now,
	}
}

func countString(values []string, target string) int {
	count := 0
	for _, value := range values {
		if value == target {
			count++
		}
	}
	return count
}

func retrieverCallsContainKeyword(calls [][]string, target string) bool {
	for _, keywords := range calls {
		if slices.Contains(keywords, target) {
			return true
		}
	}
	return false
}
