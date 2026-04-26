package service

import (
	"context"
	"fmt"
	"log/slog"
	"regexp"
	"slices"
	"sort"
	"strings"
	"unicode/utf8"

	"folio-server/internal/domain"
)

type KnowledgeMode = domain.KnowledgeMode

const (
	KnowledgeModeAsk   = domain.KnowledgeModeAsk
	KnowledgeModeSpark = domain.KnowledgeModeSpark
	KnowledgeModeLearn = domain.KnowledgeModeLearn
)

type KnowledgeStatus = domain.KnowledgeStatus

const (
	KnowledgeStatusAnswered             = domain.KnowledgeStatusAnswered
	KnowledgeStatusInsufficientEvidence = domain.KnowledgeStatusInsufficientEvidence
)

type KnowledgeDocument = domain.KnowledgeDocument
type KnowledgeSource = domain.KnowledgeSource

type KnowledgeRetrieveOptions struct {
	Mode       KnowledgeMode
	MaxSources int
}

type KnowledgeContext struct {
	Query        string
	Sources      []KnowledgeSource
	Insufficient bool
}

type EvidenceRetrieveOptions struct {
	MaxSources int
}

type EvidenceContext struct {
	Query        string
	Sources      []KnowledgeSource
	Insufficient bool
}

type KnowledgeAnswer = domain.KnowledgeAnswer
type KnowledgeSparkInsight = domain.KnowledgeSparkInsight
type KnowledgeSparkResult = domain.KnowledgeSparkResult
type KnowledgeLearnItem = domain.KnowledgeLearnItem
type KnowledgeLearnResult = domain.KnowledgeLearnResult

type knowledgeQueryPlan struct {
	Terms   []string
	Phrases []string
}

type knowledgeRecallPath struct {
	Name     string
	Terms    []string
	Priority float64
}

type knowledgeDocumentLister interface {
	ListKnowledgeDocuments(ctx context.Context, userID string) ([]KnowledgeDocument, error)
}

type knowledgeQueryExpander interface {
	ExpandQuery(ctx context.Context, question string) ([]string, error)
}

type knowledgeBroadRecaller interface {
	BroadRecallKnowledgeDocuments(ctx context.Context, userID string, keywords []string, limit int) ([]KnowledgeDocument, error)
}

type KnowledgeService struct {
	repo     knowledgeDocumentLister
	evidence *EvidenceService
}

type EvidenceService struct {
	repo      knowledgeDocumentLister
	expander  knowledgeQueryExpander
	retriever knowledgeBroadRecaller
}

func NewKnowledgeService(repo knowledgeDocumentLister) *KnowledgeService {
	return &KnowledgeService{
		repo:     repo,
		evidence: NewEvidenceService(repo, nil, nil),
	}
}

func NewKnowledgeServiceWithRetrieval(repo knowledgeDocumentLister, expander knowledgeQueryExpander, retriever knowledgeBroadRecaller) *KnowledgeService {
	return &KnowledgeService{
		repo:     repo,
		evidence: NewEvidenceService(repo, expander, retriever),
	}
}

func NewEvidenceService(repo knowledgeDocumentLister, expander knowledgeQueryExpander, retriever knowledgeBroadRecaller) *EvidenceService {
	return &EvidenceService{
		repo:      repo,
		expander:  expander,
		retriever: retriever,
	}
}

func (s *KnowledgeService) Retrieve(ctx context.Context, userID, query string, opts KnowledgeRetrieveOptions) (*KnowledgeContext, error) {
	query = strings.TrimSpace(query)

	maxSources := opts.MaxSources
	if maxSources <= 0 {
		switch opts.Mode {
		case KnowledgeModeSpark:
			maxSources = 8
		case KnowledgeModeLearn:
			maxSources = 6
		default:
			maxSources = 5
		}
	}

	evidence := s.evidence
	if evidence == nil {
		evidence = NewEvidenceService(s.repo, nil, nil)
	}

	result, err := evidence.Retrieve(ctx, userID, query, EvidenceRetrieveOptions{MaxSources: maxSources})
	if err != nil {
		return nil, err
	}

	return &KnowledgeContext{
		Query:        result.Query,
		Sources:      result.Sources,
		Insufficient: result.Insufficient,
	}, nil
}

func (s *EvidenceService) Retrieve(ctx context.Context, userID, query string, opts EvidenceRetrieveOptions) (*EvidenceContext, error) {
	query = strings.TrimSpace(query)
	if s == nil || s.repo == nil {
		return &EvidenceContext{Query: query, Insufficient: true}, nil
	}

	plan := s.buildKnowledgeQueryPlan(ctx, query)
	if len(plan.Terms) == 0 && len(plan.Phrases) == 0 {
		return &EvidenceContext{Query: query, Insufficient: true}, nil
	}

	maxSources := opts.MaxSources
	if maxSources <= 0 {
		maxSources = 5
	}

	docs, err := s.loadCandidateDocuments(ctx, userID, query, plan, maxSources)
	if err != nil {
		return nil, err
	}
	if len(docs) == 0 {
		return &EvidenceContext{Query: query, Insufficient: true}, nil
	}

	scored := make([]scoredKnowledgeDocument, 0, len(docs))
	for _, doc := range docs {
		score, matches, evidenceSnippet, phraseMatches := scoreKnowledgeDocument(doc, plan)
		if score <= 0 {
			continue
		}
		score += doc.RecallScore * 10
		scored = append(scored, scoredKnowledgeDocument{
			doc:             doc,
			score:           score,
			matches:         matches,
			evidenceSnippet: evidenceSnippet,
			phraseMatches:   phraseMatches,
		})
	}

	sort.SliceStable(scored, func(i, j int) bool {
		if scored[i].score == scored[j].score {
			return scored[i].doc.CreatedAt.After(scored[j].doc.CreatedAt)
		}
		return scored[i].score > scored[j].score
	})

	insufficient := isKnowledgeInsufficient(query, plan, scored)
	if insufficient {
		return &EvidenceContext{Query: query, Insufficient: true}, nil
	}

	if len(scored) > maxSources {
		scored = scored[:maxSources]
	}

	sources := make([]KnowledgeSource, 0, len(scored))
	for _, item := range scored {
		summary := item.doc.Summary
		sources = append(sources, KnowledgeSource{
			ArticleID:       item.doc.ArticleID,
			Title:           item.doc.Title,
			SiteName:        item.doc.SiteName,
			Summary:         &summary,
			EvidenceSnippet: item.evidenceSnippet,
			CreatedAt:       item.doc.CreatedAt,
			Relevance:       item.score,
		})
	}

	return &EvidenceContext{
		Query:        query,
		Sources:      sources,
		Insufficient: false,
	}, nil
}

func (s *EvidenceService) buildKnowledgeQueryPlan(ctx context.Context, query string) knowledgeQueryPlan {
	terms := mergeKnowledgeTerms(nil, expandKnowledgeTerms(query)...)
	if s.expander != nil && strings.TrimSpace(query) != "" {
		expanded, err := s.expander.ExpandQuery(ctx, query)
		if err != nil {
			slog.Warn("knowledge retrieval: query expansion failed", "error", err)
		} else {
			terms = mergeKnowledgeTerms(terms, expanded...)
		}
	}

	return knowledgeQueryPlan{
		Terms:   terms,
		Phrases: buildKnowledgePhrases(query, terms),
	}
}

func (s *EvidenceService) loadCandidateDocuments(ctx context.Context, userID, query string, plan knowledgeQueryPlan, maxSources int) ([]KnowledgeDocument, error) {
	paths := buildKnowledgeRecallPaths(plan)
	if s.retriever != nil && len(paths) > 0 {
		limit := max(maxSources*4, 12)
		docs, err := s.fusedBroadRecall(ctx, userID, query, paths, limit)
		if err == nil && len(docs) > 0 {
			return docs, nil
		}
		if err != nil {
			slog.Warn("knowledge retrieval: fused broad recall failed, falling back to full scan", "error", err, "query", query)
		} else {
			slog.Debug("knowledge retrieval: fused broad recall empty, falling back to full scan", "query", query)
		}
	}

	docs, err := s.repo.ListKnowledgeDocuments(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("list knowledge documents: %w", err)
	}
	return docs, nil
}

func (s *EvidenceService) fusedBroadRecall(ctx context.Context, userID, query string, paths []knowledgeRecallPath, limit int) ([]KnowledgeDocument, error) {
	type fusedDocument struct {
		doc        KnowledgeDocument
		score      float64
		bestRank   int
		latestDate int64
	}

	const rrfK = 60.0
	fused := map[string]*fusedDocument{}
	var lastErr error

	for _, path := range paths {
		if len(path.Terms) == 0 {
			continue
		}
		docs, err := s.retriever.BroadRecallKnowledgeDocuments(ctx, userID, path.Terms, limit)
		if err != nil {
			lastErr = err
			slog.Warn("knowledge retrieval: recall path failed", "path", path.Name, "error", err, "query", query)
			continue
		}
		for rank, doc := range docs {
			if doc.ArticleID == "" {
				continue
			}
			score := path.Priority / (rrfK + float64(rank+1))
			current, ok := fused[doc.ArticleID]
			if !ok {
				fused[doc.ArticleID] = &fusedDocument{
					doc:        doc,
					score:      score,
					bestRank:   rank + 1,
					latestDate: doc.CreatedAt.UnixNano(),
				}
				continue
			}
			current.score += score
			if rank+1 < current.bestRank {
				current.bestRank = rank + 1
				current.doc = doc
			}
			if doc.CreatedAt.UnixNano() > current.latestDate {
				current.latestDate = doc.CreatedAt.UnixNano()
			}
		}
	}

	if len(fused) == 0 {
		return nil, lastErr
	}

	results := make([]fusedDocument, 0, len(fused))
	for _, item := range fused {
		item.doc.RecallScore = item.score
		results = append(results, *item)
	}
	sort.SliceStable(results, func(i, j int) bool {
		if results[i].score == results[j].score {
			if results[i].bestRank == results[j].bestRank {
				return results[i].latestDate > results[j].latestDate
			}
			return results[i].bestRank < results[j].bestRank
		}
		return results[i].score > results[j].score
	})

	if len(results) > limit {
		results = results[:limit]
	}

	docs := make([]KnowledgeDocument, 0, len(results))
	for _, item := range results {
		docs = append(docs, item.doc)
	}
	return docs, nil
}

func buildKnowledgeRecallPaths(plan knowledgeQueryPlan) []knowledgeRecallPath {
	paths := make([]knowledgeRecallPath, 0, 3)
	if len(plan.Phrases) > 0 {
		paths = append(paths, knowledgeRecallPath{Name: "phrases", Terms: plan.Phrases, Priority: 1.35})
	}
	if len(plan.Terms) > 0 {
		paths = append(paths, knowledgeRecallPath{Name: "terms", Terms: plan.Terms, Priority: 1.0})
	}
	allTerms := mergeKnowledgeTerms(plan.Terms, plan.Phrases...)
	if len(plan.Terms) > 0 && len(plan.Phrases) > 0 && len(allTerms) > max(len(plan.Phrases), len(plan.Terms)) {
		paths = append(paths, knowledgeRecallPath{Name: "combined", Terms: allTerms, Priority: 0.85})
	}
	return paths
}

func (s *KnowledgeService) Ask(ctx context.Context, userID, question string) (*KnowledgeAnswer, error) {
	contextResult, err := s.Retrieve(ctx, userID, question, KnowledgeRetrieveOptions{
		Mode:       KnowledgeModeAsk,
		MaxSources: 5,
	})
	if err != nil {
		return nil, err
	}
	if contextResult.Insufficient || len(contextResult.Sources) == 0 {
		return &KnowledgeAnswer{
			Status:              KnowledgeStatusInsufficientEvidence,
			Answer:              "证据不足，暂时无法根据你的收藏确认这个问题。",
			FollowupSuggestions: []string{"换个角度再问一次", "先继续收藏相关内容"},
		}, nil
	}

	multiSource := isCrossSourceQuestion(question)
	cited := 1
	if multiSource {
		cited = min(2, len(contextResult.Sources))
		if cited < 2 {
			return &KnowledgeAnswer{
				Status:              KnowledgeStatusInsufficientEvidence,
				Answer:              "证据不足，暂时无法根据你的收藏确认这个跨来源问题。",
				FollowupSuggestions: []string{"把问题收窄到一个主题", "先继续收藏相关内容"},
			}, nil
		}
	}

	sources := slices.Clone(contextResult.Sources[:cited])
	citedIndices := make([]int, 0, cited)
	for i := range sources {
		citedIndices = append(citedIndices, i+1)
	}

	answer := buildKnowledgeAnswer(question, sources, citedIndices, multiSource)
	result := &KnowledgeAnswer{
		Status:              KnowledgeStatusAnswered,
		Answer:              answer,
		Sources:             sources,
		CitedIndices:        citedIndices,
		FollowupSuggestions: buildKnowledgeFollowups(question, sources),
	}
	if !isKnowledgeAnswerGrounded(result) {
		return &KnowledgeAnswer{
			Status:              KnowledgeStatusInsufficientEvidence,
			Answer:              "证据不足，暂时无法根据你的收藏确认这个问题。",
			FollowupSuggestions: []string{"换个角度再问一次", "先继续收藏相关内容"},
		}, nil
	}
	return result, nil
}

func (s *KnowledgeService) Spark(ctx context.Context, userID, prompt string) (*KnowledgeSparkResult, error) {
	var docs []KnowledgeSource
	if strings.TrimSpace(prompt) == "" {
		allDocs, err := s.repo.ListKnowledgeDocuments(ctx, userID)
		if err != nil {
			return nil, fmt.Errorf("list knowledge documents: %w", err)
		}
		for _, doc := range allDocs {
			summary := doc.Summary
			docs = append(docs, KnowledgeSource{
				ArticleID: doc.ArticleID,
				Title:     doc.Title,
				SiteName:  doc.SiteName,
				Summary:   &summary,
				CreatedAt: doc.CreatedAt,
				Relevance: 1,
			})
		}
	} else {
		contextResult, err := s.Retrieve(ctx, userID, prompt, KnowledgeRetrieveOptions{
			Mode:       KnowledgeModeSpark,
			MaxSources: 8,
		})
		if err != nil {
			return nil, err
		}
		docs = contextResult.Sources
	}
	if len(docs) < 6 {
		allDocs, err := s.repo.ListKnowledgeDocuments(ctx, userID)
		if err != nil {
			return nil, fmt.Errorf("list knowledge documents: %w", err)
		}
		existing := map[string]bool{}
		for _, doc := range docs {
			existing[doc.ArticleID] = true
		}
		for _, doc := range allDocs {
			if len(docs) >= 6 {
				break
			}
			if existing[doc.ArticleID] {
				continue
			}
			summary := doc.Summary
			docs = append(docs, KnowledgeSource{
				ArticleID: doc.ArticleID,
				Title:     doc.Title,
				SiteName:  doc.SiteName,
				Summary:   &summary,
				CreatedAt: doc.CreatedAt,
				Relevance: 0.5,
			})
		}
	}

	insights := composeSparkInsights(prompt, docs)
	result := groundSparkResult(insights, docs)
	return result, nil
}

func (s *KnowledgeService) Learn(ctx context.Context, userID, prompt string) (*KnowledgeLearnResult, error) {
	contextResult, err := s.Retrieve(ctx, userID, prompt, KnowledgeRetrieveOptions{
		Mode:       KnowledgeModeLearn,
		MaxSources: 6,
	})
	if err != nil {
		return nil, err
	}
	if contextResult.Insufficient || len(contextResult.Sources) == 0 {
		contextResult, err = s.Retrieve(ctx, userID, "knowledge learning review", KnowledgeRetrieveOptions{
			Mode:       KnowledgeModeLearn,
			MaxSources: 6,
		})
		if err != nil {
			return nil, err
		}
	}

	summary := composeLearnSummary(prompt, contextResult.Sources)
	items := composeLearnItems(prompt, contextResult.Sources)
	result := &KnowledgeLearnResult{
		Summary: summary,
		Items:   items,
	}
	return groundLearnResult(result, contextResult.Sources), nil
}

type scoredKnowledgeDocument struct {
	doc             KnowledgeDocument
	score           float64
	matches         []string
	evidenceSnippet *string
	phraseMatches   int
}

var (
	knowledgeEnglishWord = regexp.MustCompile(`[a-z0-9][a-z0-9+\-]{1,}`)
	knowledgeChineseTerm = regexp.MustCompile(`[\p{Han}]{2,}`)
	knowledgeStopWords   = map[string]bool{
		"为什么": true, "怎么": true, "怎样": true, "如何": true, "以及": true, "还有": true,
		"这些": true, "文章": true, "资料": true, "用户": true, "系统": true, "需要": true,
		"what": true, "why": true, "how": true, "with": true, "from": true, "into": true,
		"that": true, "this": true, "have": true, "does": true, "need": true, "your": true,
		"folio": true,
	}
	knowledgeAliases = map[string][]string{
		"结构化日志":      {"structured logs", "observability"},
		"slo":        {"slos", "service level objectives"},
		"可靠服务":       {"reliability", "incident response"},
		"可靠性":        {"reliability", "trust"},
		"保存和同步":      {"capture", "sync", "idempotency", "compensation", "retries"},
		"保存":         {"capture", "save", "collection"},
		"同步":         {"sync", "retries", "distributed systems"},
		"手动选文章":      {"user choice", "configuration", "defaults"},
		"手动选择":       {"user choice", "configuration"},
		"上下文":        {"context", "retrieval"},
		"grounded":   {"grounded", "evidence", "citation"},
		"可补偿":        {"compensation", "compensating workflows"},
		"幂等":         {"idempotency", "retries"},
		"主动回忆":       {"active recall", "questions", "retrieval practice"},
		"真正理解":       {"understanding", "learning", "active recall", "synthesis"},
		"理解":         {"understanding", "learning", "synthesis"},
		"从收藏走向真正理解":  {"active recall", "synthesis", "highlights", "understanding"},
		"来源追溯":       {"provenance", "traceability", "source linked"},
		"追溯":         {"provenance", "traceability"},
		"默认简单":       {"defaults", "quiet defaults", "two tap flow"},
		"两步交互":       {"two tap flow", "capture", "recall"},
		"零配置":        {"defaults", "quiet defaults", "configuration"},
		"calm":       {"calm software", "quiet defaults"},
		"说不知道":       {"i don't know", "insufficient evidence", "refusal"},
		"证据不足":       {"insufficient evidence", "i don't know", "refusal"},
		"相关文章":       {"connections", "related articles"},
		"学习科学":       {"learning science", "spaced repetition", "active recall", "interleaving"},
		"学习功能":       {"spaced repetition", "active recall", "study cards"},
		"知识闭环":       {"connections", "related articles", "study cards", "insight"},
		"产品灵感":       {"connections", "insight", "tension"},
		"用户信任":       {"trust", "traceability", "automation"},
		"可靠性工程":      {"reliability", "idempotency", "backpressure", "observability"},
		"知识收藏产品":     {"knowledge base", "capture", "recall", "defaults"},
		"可追溯证据":      {"citation", "provenance", "traceability"},
		"学习科学生成学习卡片": {"learning science", "study cards", "active recall"},
		"provenance": {"provenance", "traceability", "source linked"},
		"synthesis":  {"synthesis", "comparison", "tension"},
	}
)

func expandKnowledgeTerms(query string) []string {
	normalized := normalizeKnowledgeText(query)
	terms := make([]string, 0, 16)
	addTerm := newKnowledgeTermAdder(&terms)

	for alias, expansions := range knowledgeAliases {
		if strings.Contains(normalized, normalizeKnowledgeText(alias)) {
			addTerm(alias)
			for _, expansion := range expansions {
				addTerm(expansion)
			}
		}
	}

	for _, match := range knowledgeEnglishWord.FindAllString(normalized, -1) {
		addTerm(match)
	}
	for _, match := range knowledgeChineseTerm.FindAllString(query, -1) {
		addTerm(match)
	}

	return terms
}

func buildKnowledgePhrases(query string, terms []string) []string {
	phrases := make([]string, 0, 16)
	addPhrase := newKnowledgeTermAdder(&phrases)
	normalized := normalizeKnowledgeText(query)

	if len(strings.Fields(normalized)) >= 3 || utf8.RuneCountInString(normalized) >= 12 {
		addPhrase(normalized)
	}

	for alias, expansions := range knowledgeAliases {
		if strings.Contains(normalized, normalizeKnowledgeText(alias)) {
			addPhrase(alias)
			for _, expansion := range expansions {
				if strings.Contains(expansion, " ") || utf8.RuneCountInString(expansion) >= 4 {
					addPhrase(expansion)
				}
			}
		}
	}

	for _, term := range terms {
		if strings.Contains(term, " ") || utf8.RuneCountInString(term) >= 4 {
			addPhrase(term)
		}
	}

	englishTokens := significantKnowledgeEnglishTokens(normalized)
	for size := 2; size <= 4; size++ {
		if len(englishTokens) < size {
			break
		}
		for start := 0; start+size <= len(englishTokens); start++ {
			addPhrase(strings.Join(englishTokens[start:start+size], " "))
		}
	}

	return phrases
}

func mergeKnowledgeTerms(base []string, additions ...string) []string {
	terms := slices.Clone(base)
	addTerm := newKnowledgeTermAdder(&terms)
	for _, addition := range additions {
		addTerm(addition)
	}
	return terms
}

func newKnowledgeTermAdder(target *[]string) func(string) {
	seen := map[string]bool{}
	for _, term := range *target {
		normalized := strings.TrimSpace(normalizeKnowledgeText(term))
		if normalized != "" {
			seen[normalized] = true
		}
	}

	return func(term string) {
		term = strings.TrimSpace(normalizeKnowledgeText(term))
		if term == "" || knowledgeStopWords[term] || seen[term] {
			return
		}
		seen[term] = true
		*target = append(*target, term)
	}
}

type knowledgeField struct {
	raw            string
	normalized     string
	phraseWeight   float64
	termWeight     float64
	coverageWeight float64
}

func scoreKnowledgeDocument(doc KnowledgeDocument, plan knowledgeQueryPlan) (float64, []string, *string, int) {
	fields := []knowledgeField{
		{raw: doc.Title, normalized: normalizeKnowledgeText(doc.Title), phraseWeight: 30, termWeight: 8, coverageWeight: 1.8},
		{raw: strings.Join(doc.SemanticKeywords, " "), normalized: normalizeKnowledgeText(strings.Join(doc.SemanticKeywords, " ")), phraseWeight: 24, termWeight: 7, coverageWeight: 1.4},
		{raw: strings.Join(doc.KeyPoints, " "), normalized: normalizeKnowledgeText(strings.Join(doc.KeyPoints, " ")), phraseWeight: 20, termWeight: 6, coverageWeight: 1.2},
		{raw: doc.Summary, normalized: normalizeKnowledgeText(doc.Summary), phraseWeight: 16, termWeight: 5, coverageWeight: 1.0},
		{raw: doc.MarkdownContent, normalized: normalizeKnowledgeText(doc.MarkdownContent), phraseWeight: 13, termWeight: 3, coverageWeight: 0.6},
	}

	score := 0.0
	matches := make([]string, 0, len(plan.Terms)+len(plan.Phrases))
	phraseMatchCount := 0
	bestSnippetWeight := -1.0
	var bestSnippet *string

	for _, phrase := range plan.Phrases {
		phrase = normalizeKnowledgeText(phrase)
		if phrase == "" {
			continue
		}
		for _, field := range fields {
			if !strings.Contains(field.normalized, phrase) {
				continue
			}
			score += field.phraseWeight
			matches = append(matches, phrase)
			phraseMatchCount++
			bestSnippet, bestSnippetWeight = chooseKnowledgeSnippet(bestSnippet, bestSnippetWeight, field.raw, phrase, field.phraseWeight)
			break
		}
	}

	for _, term := range plan.Terms {
		term = normalizeKnowledgeText(term)
		if term == "" {
			continue
		}
		bestTermWeight := 0.0
		bestTermField := ""
		for _, field := range fields {
			if strings.Contains(field.normalized, term) && field.termWeight > bestTermWeight {
				bestTermWeight = field.termWeight
				bestTermField = field.raw
			}
		}
		if bestTermWeight == 0 {
			continue
		}
		score += bestTermWeight
		matches = append(matches, term)
		bestSnippet, bestSnippetWeight = chooseKnowledgeSnippet(bestSnippet, bestSnippetWeight, bestTermField, term, bestTermWeight)
	}

	uniqueMatches := uniqueStrings(matches)
	if len(uniqueMatches) > 1 {
		score += float64(len(uniqueMatches) - 1)
	}
	if phraseMatchCount > 0 {
		score += float64(phraseMatchCount * 2)
	}

	for _, field := range fields {
		coverage := fieldKnowledgeCoverage(field.normalized, plan.Terms)
		if coverage > 1 {
			score += float64(coverage-1) * field.coverageWeight
		}
	}

	return score, uniqueMatches, bestSnippet, phraseMatchCount
}

func isKnowledgeInsufficient(query string, plan knowledgeQueryPlan, scored []scoredKnowledgeDocument) bool {
	if len(scored) == 0 {
		return true
	}
	top := scored[0]
	if top.score < 8 || top.evidenceSnippet == nil || strings.TrimSpace(*top.evidenceSnippet) == "" {
		return true
	}
	if len(top.matches) == 0 {
		return true
	}
	if isCrossSourceQuestion(query) {
		if len(scored) < 2 {
			return true
		}
		if scored[1].score < 6 || scored[1].evidenceSnippet == nil || strings.TrimSpace(*scored[1].evidenceSnippet) == "" {
			return true
		}
	}
	minMatchCount := 1
	if len(plan.Terms) >= 3 {
		minMatchCount = 2
	}
	return len(uniqueStrings(top.matches)) < minMatchCount
}

func buildKnowledgeAnswer(question string, sources []KnowledgeSource, citedIndices []int, multiSource bool) string {
	if len(sources) == 0 {
		return "证据不足，暂时无法根据你的收藏确认这个问题。"
	}
	if multiSource && len(sources) >= 2 {
		first := derefKnowledgeEvidence(sources[0])
		second := derefKnowledgeEvidence(sources[1])
		return fmt.Sprintf("从你的收藏看，这个问题更像是多个原则的组合：%s¹；同时，%s²。把两者放在一起，核心不是多做一步，而是让系统默认完成选择并保留可追溯证据。", first, second)
	}
	first := derefKnowledgeEvidence(sources[0])
	return fmt.Sprintf("%s¹ 这也是为什么这个能力应该作为默认路径存在，而不是要求用户先手动配置上下文。", first)
}

func isKnowledgeAnswerGrounded(answer *KnowledgeAnswer) bool {
	if answer == nil || answer.Status != KnowledgeStatusAnswered {
		return false
	}
	if strings.TrimSpace(answer.Answer) == "" || len(answer.Sources) == 0 || len(answer.CitedIndices) == 0 {
		return false
	}
	for _, idx := range answer.CitedIndices {
		if idx < 1 || idx > len(answer.Sources) {
			return false
		}
		if !knowledgeSourceHasEvidence(answer.Sources[idx-1]) {
			return false
		}
		if !strings.Contains(answer.Answer, citationMarker(idx)) {
			return false
		}
	}
	return true
}

func groundSparkResult(insights []KnowledgeSparkInsight, sources []KnowledgeSource) *KnowledgeSparkResult {
	sourceByID := knowledgeSourceMap(sources)
	grounded := make([]KnowledgeSparkInsight, 0, len(insights))
	usedInsights := map[string]bool{}
	usedSources := map[string]bool{}

	for _, insight := range insights {
		if strings.TrimSpace(insight.Insight) == "" ||
			strings.TrimSpace(insight.WhyItMatters) == "" ||
			strings.TrimSpace(insight.FollowupQuestion) == "" {
			continue
		}
		key := normalizeKnowledgeText(insight.Insight)
		if key == "" || usedInsights[key] {
			continue
		}
		sourceIDs := groundedSourceIDs(insight.SourceIDs, sourceByID)
		if len(sourceIDs) < 2 {
			continue
		}
		usedInsights[key] = true
		insight.SourceIDs = sourceIDs
		grounded = append(grounded, insight)
		for _, id := range sourceIDs {
			usedSources[id] = true
		}
	}
	return &KnowledgeSparkResult{
		Insights: grounded,
		Sources:  sourcesByUsedIDs(sources, usedSources),
	}
}

func groundLearnResult(result *KnowledgeLearnResult, sources []KnowledgeSource) *KnowledgeLearnResult {
	if result == nil {
		return &KnowledgeLearnResult{Summary: "目前还没有足够来源生成学习包。"}
	}

	sourceByID := knowledgeSourceMap(sources)
	grounded := make([]KnowledgeLearnItem, 0, len(result.Items))
	usedSources := map[string]bool{}
	for _, item := range result.Items {
		if strings.TrimSpace(item.Type) == "" ||
			strings.TrimSpace(item.Title) == "" ||
			strings.TrimSpace(item.Content) == "" {
			continue
		}
		sourceIDs := groundedSourceIDs(item.SourceIDs, sourceByID)
		if len(sourceIDs) == 0 {
			continue
		}
		item.SourceIDs = sourceIDs
		grounded = append(grounded, item)
		for _, id := range sourceIDs {
			usedSources[id] = true
		}
	}

	summary := strings.TrimSpace(result.Summary)
	if summary == "" {
		summary = composeLearnSummary("", sources)
	}
	return &KnowledgeLearnResult{
		Summary: summary,
		Items:   grounded,
		Sources: sourcesByUsedIDs(sources, usedSources),
	}
}

func knowledgeSourceMap(sources []KnowledgeSource) map[string]KnowledgeSource {
	sourceByID := make(map[string]KnowledgeSource, len(sources))
	for _, source := range sources {
		if source.ArticleID == "" || !knowledgeSourceHasEvidence(source) {
			continue
		}
		sourceByID[source.ArticleID] = source
	}
	return sourceByID
}

func groundedSourceIDs(ids []string, sourceByID map[string]KnowledgeSource) []string {
	seen := map[string]bool{}
	result := make([]string, 0, len(ids))
	for _, id := range ids {
		if id == "" || seen[id] {
			continue
		}
		if _, ok := sourceByID[id]; !ok {
			continue
		}
		seen[id] = true
		result = append(result, id)
	}
	return result
}

func sourcesByUsedIDs(sources []KnowledgeSource, used map[string]bool) []KnowledgeSource {
	result := make([]KnowledgeSource, 0, len(used))
	for _, source := range sources {
		if used[source.ArticleID] {
			result = append(result, source)
		}
	}
	return result
}

func knowledgeSourceHasEvidence(source KnowledgeSource) bool {
	if source.ArticleID == "" {
		return false
	}
	if source.EvidenceSnippet != nil && strings.TrimSpace(*source.EvidenceSnippet) != "" {
		return true
	}
	return source.Summary != nil && strings.TrimSpace(*source.Summary) != ""
}

func citationMarker(idx int) string {
	markers := []string{"", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"}
	if idx >= 1 && idx < len(markers) {
		return markers[idx]
	}
	return fmt.Sprintf("[%d]", idx)
}

func buildKnowledgeFollowups(question string, sources []KnowledgeSource) []string {
	if len(sources) == 0 {
		return []string{"换个问题再试一次", "继续收藏相关主题"}
	}
	return []string{
		fmt.Sprintf("如果继续展开“%s”，下一步最值得验证什么？", sources[0].Title),
		fmt.Sprintf("这个结论在 %q 里的另一个约束是什么？", question),
	}
}

func composeSparkInsights(prompt string, sources []KnowledgeSource) []KnowledgeSparkInsight {
	if len(sources) < 2 {
		return nil
	}

	pairs := buildSparkPairs(sources)
	insights := make([]KnowledgeSparkInsight, 0, len(pairs))
	usedLabels := map[string]int{}
	for _, pair := range pairs {
		if len(pair) < 2 {
			continue
		}
		label := sharedThemeLabel(pair)
		if usedLabels[label] > 0 {
			label = compactPairLabel(pair)
		}
		usedLabels[label]++
		sourceIDs := []string{pair[0].ArticleID, pair[1].ArticleID}
		insights = append(insights, KnowledgeSparkInsight{
			Insight:          fmt.Sprintf("你的收藏把“%s”反复当成系统级杠杆，而不是单点技巧。", label),
			WhyItMatters:     fmt.Sprintf("《%s》与《%s》都把它和长期信任、可持续复用或更高质量决策联系在一起。", pair[0].Title, pair[1].Title),
			SourceIDs:        sourceIDs,
			FollowupQuestion: fmt.Sprintf("如果把“%s”变成 Folio 的默认约束，还有哪些步骤可以被系统吞掉？", label),
		})
	}
	if len(insights) > 5 {
		insights = insights[:5]
	}
	return insights
}

func composeLearnSummary(prompt string, sources []KnowledgeSource) string {
	if len(sources) == 0 {
		return "目前还没有足够来源生成学习包。"
	}
	if len(sources) == 1 {
		return fmt.Sprintf("这一组内容的核心在于：%s。", derefKnowledgeSummary(sources[0].Summary))
	}
	return fmt.Sprintf("这一组收藏反复强调两件事：%s¹；以及 %s²。把它们放在一起，形成了一个可复习、可迁移的知识框架。", derefKnowledgeSummary(sources[0].Summary), derefKnowledgeSummary(sources[1].Summary))
}

func composeLearnItems(prompt string, sources []KnowledgeSource) []KnowledgeLearnItem {
	if len(sources) == 0 {
		return nil
	}

	types := []string{"concept", "question", "card"}
	items := make([]KnowledgeLearnItem, 0, min(10, len(sources)*2))
	for idx, source := range sources {
		if len(items) >= 10 {
			break
		}
		items = append(items, KnowledgeLearnItem{
			Type:      types[idx%len(types)],
			Title:     fmt.Sprintf("记住《%s》的核心观点", source.Title),
			Content:   derefKnowledgeSummary(source.Summary),
			SourceIDs: []string{source.ArticleID},
		})
		if len(items) >= 10 {
			break
		}
		items = append(items, KnowledgeLearnItem{
			Type:      types[(idx+1)%len(types)],
			Title:     fmt.Sprintf("复习问题：%s", source.Title),
			Content:   fmt.Sprintf("为什么《%s》强调这件事？试着用自己的话回答，再回看来源。", source.Title),
			SourceIDs: []string{source.ArticleID},
		})
	}
	if len(items) > 10 {
		items = items[:10]
	}
	return items
}

func sourcesForInsight(sources []KnowledgeSource, indices ...int) []KnowledgeSource {
	result := make([]KnowledgeSource, 0, len(indices))
	for _, idx := range indices {
		if idx >= 0 && idx < len(sources) {
			result = append(result, sources[idx])
		}
	}
	return result
}

func sharedThemeLabel(sources []KnowledgeSource) string {
	candidates := []string{
		"默认简单",
		"可追溯性",
		"可靠性",
		"学习闭环",
		"跨源综合",
	}
	text := normalizeKnowledgeText(strings.Join(func() []string {
		acc := make([]string, 0, len(sources)*2)
		for _, source := range sources {
			acc = append(acc, source.Title)
			acc = append(acc, derefKnowledgeSummary(source.Summary))
		}
		return acc
	}(), " "))

	switch {
	case strings.Contains(text, "trust") || strings.Contains(text, "traceability") || strings.Contains(text, "provenance"):
		return candidates[1]
	case strings.Contains(text, "reliability") || strings.Contains(text, "idempotency") || strings.Contains(text, "backpressure"):
		return candidates[2]
	case strings.Contains(text, "learning") || strings.Contains(text, "recall") || strings.Contains(text, "study"):
		return candidates[3]
	case strings.Contains(text, "defaults") || strings.Contains(text, "quiet") || strings.Contains(text, "configuration"):
		return candidates[0]
	default:
		return candidates[4]
	}
}

func isCrossSourceQuestion(question string) bool {
	normalized := normalizeKnowledgeText(question)
	markers := []string{"结合", "共同", "同时", "串成", "之间", "跨", "和", "与", "既有", "both", "combine", "together"}
	for _, marker := range markers {
		if strings.Contains(normalized, normalizeKnowledgeText(marker)) {
			return true
		}
	}
	return false
}

func normalizeKnowledgeText(text string) string {
	text = strings.ToLower(text)
	replacer := strings.NewReplacer(
		"“", " ", "”", " ", "‘", " ", "’", " ", "’", " ",
		"，", " ", "。", " ", "：", " ", "；", " ", "！", " ", "？", " ",
		"(", " ", ")", " ", "（", " ", "）", " ", ",", " ", ".", " ",
		":", " ", ";", " ", "!", " ", "?", " ", "-", " ", "_", " ",
	)
	return strings.Join(strings.Fields(replacer.Replace(text)), " ")
}

func uniqueStrings(values []string) []string {
	seen := map[string]bool{}
	result := make([]string, 0, len(values))
	for _, value := range values {
		if seen[value] {
			continue
		}
		seen[value] = true
		result = append(result, value)
	}
	return result
}

func derefKnowledgeSummary(summary *string) string {
	if summary == nil || strings.TrimSpace(*summary) == "" {
		return "这篇来源强调了一个值得保留的原则"
	}
	return strings.TrimSpace(*summary)
}

func derefKnowledgeEvidence(source KnowledgeSource) string {
	if source.EvidenceSnippet != nil && strings.TrimSpace(*source.EvidenceSnippet) != "" {
		return strings.TrimSpace(*source.EvidenceSnippet)
	}
	return derefKnowledgeSummary(source.Summary)
}

func significantKnowledgeEnglishTokens(text string) []string {
	tokens := knowledgeEnglishWord.FindAllString(text, -1)
	result := make([]string, 0, len(tokens))
	for _, token := range tokens {
		if !knowledgeStopWords[token] {
			result = append(result, token)
		}
	}
	return result
}

func fieldKnowledgeCoverage(field string, terms []string) int {
	count := 0
	for _, term := range uniqueStrings(terms) {
		term = normalizeKnowledgeText(term)
		if term == "" {
			continue
		}
		if strings.Contains(field, term) {
			count++
		}
	}
	return count
}

func chooseKnowledgeSnippet(current *string, currentWeight float64, raw, needle string, weight float64) (*string, float64) {
	weightedSnippet := knowledgeSnippetWeight(needle, weight)
	if weightedSnippet < currentWeight {
		return current, currentWeight
	}
	snippet := extractKnowledgeSnippet(raw, needle)
	if snippet == nil {
		return current, currentWeight
	}
	return snippet, weightedSnippet
}

func knowledgeSnippetWeight(needle string, base float64) float64 {
	normalized := normalizeKnowledgeText(needle)
	if strings.Contains(normalized, " ") {
		return base + min(float64(utf8.RuneCountInString(normalized))*2, 64)
	}
	if utf8.RuneCountInString(normalized) >= 8 {
		return base + 4
	}
	return base
}

func extractKnowledgeSnippet(raw, needle string) *string {
	raw = strings.Join(strings.Fields(strings.TrimSpace(raw)), " ")
	if raw == "" {
		return nil
	}

	lowerRaw := strings.ToLower(raw)
	searchTerms := []string{strings.ToLower(strings.TrimSpace(needle))}
	if strings.Contains(searchTerms[0], " ") {
		searchTerms = append(searchTerms,
			strings.ReplaceAll(searchTerms[0], " ", "-"),
			strings.ReplaceAll(searchTerms[0], " ", ""),
		)
	}

	matchIdx := -1
	matchLen := 0
	for _, term := range uniqueStrings(searchTerms) {
		if term == "" {
			continue
		}
		if idx := strings.Index(lowerRaw, term); idx >= 0 {
			matchIdx = idx
			matchLen = len(term)
			break
		}
	}

	if matchIdx < 0 {
		for _, token := range strings.Fields(strings.ToLower(needle)) {
			if len(token) < 3 {
				continue
			}
			if idx := strings.Index(lowerRaw, token); idx >= 0 {
				matchIdx = idx
				matchLen = len(token)
				break
			}
		}
	}

	if matchIdx < 0 {
		for _, token := range knowledgeChineseTerm.FindAllString(needle, -1) {
			if idx := strings.Index(lowerRaw, strings.ToLower(token)); idx >= 0 {
				matchIdx = idx
				matchLen = len(token)
				break
			}
		}
	}

	if matchIdx < 0 {
		snippet := truncateKnowledgeText(raw, 160)
		return &snippet
	}

	startRune := max(0, utf8.RuneCountInString(raw[:matchIdx])-40)
	endRune := min(len([]rune(raw)), utf8.RuneCountInString(raw[:matchIdx+matchLen])+60)
	runes := []rune(raw)
	snippet := string(runes[startRune:endRune])
	if startRune > 0 {
		snippet = "..." + snippet
	}
	if endRune < len(runes) {
		snippet += "..."
	}
	snippet = strings.TrimSpace(snippet)
	return &snippet
}

func truncateKnowledgeText(text string, limit int) string {
	runes := []rune(text)
	if len(runes) <= limit {
		return text
	}
	return strings.TrimSpace(string(runes[:limit])) + "..."
}

func buildSparkPairs(sources []KnowledgeSource) [][]KnowledgeSource {
	pairs := make([][]KnowledgeSource, 0, 3)
	for start := 0; start+1 < len(sources) && len(pairs) < 3; start += 2 {
		pairs = append(pairs, sourcesForInsight(sources, start, start+1))
	}
	for start := 0; start+2 < len(sources) && len(pairs) < 3; start++ {
		pairs = append(pairs, sourcesForInsight(sources, start, start+2))
	}
	for len(pairs) < 3 && len(sources) >= 2 {
		pairs = append(pairs, sourcesForInsight(sources, 0, len(sources)-1))
	}
	return pairs
}

func compactPairLabel(pair []KnowledgeSource) string {
	if len(pair) < 2 {
		return "跨源连接"
	}
	first := firstMeaningfulWord(pair[0].Title)
	second := firstMeaningfulWord(pair[1].Title)
	if first == second {
		return first
	}
	return fmt.Sprintf("%s x %s", first, second)
}

func firstMeaningfulWord(title string) string {
	normalized := normalizeKnowledgeText(title)
	for _, match := range knowledgeEnglishWord.FindAllString(normalized, -1) {
		if !knowledgeStopWords[match] {
			return match
		}
	}
	return "跨源连接"
}
