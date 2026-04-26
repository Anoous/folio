package service

import (
	"context"
	"fmt"
	"log/slog"
	"sort"
	"strings"
	"unicode/utf8"
)

type EvidenceRetrieveOptions struct {
	MaxSources int
}

type EvidenceContext struct {
	Query        string
	Sources      []KnowledgeSource
	Insufficient bool
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

type EvidenceService struct {
	repo      knowledgeDocumentLister
	expander  knowledgeQueryExpander
	retriever knowledgeBroadRecaller
}

func NewEvidenceService(repo knowledgeDocumentLister, expander knowledgeQueryExpander, retriever knowledgeBroadRecaller) *EvidenceService {
	return &EvidenceService{
		repo:      repo,
		expander:  expander,
		retriever: retriever,
	}
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

type scoredKnowledgeDocument struct {
	doc             KnowledgeDocument
	score           float64
	matches         []string
	evidenceSnippet *string
	phraseMatches   int
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
