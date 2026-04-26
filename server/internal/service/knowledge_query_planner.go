package service

import (
	"context"
	"log/slog"
	"regexp"
	"slices"
	"strings"
	"unicode/utf8"
)

type knowledgeQueryPlanner struct {
	expander knowledgeQueryExpander
}

func (p knowledgeQueryPlanner) Plan(ctx context.Context, query string) knowledgeQueryPlan {
	terms := mergeKnowledgeTerms(nil, expandKnowledgeTerms(query)...)
	if p.expander != nil && strings.TrimSpace(query) != "" {
		expanded, err := p.expander.ExpandQuery(ctx, query)
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

func (s *EvidenceService) buildKnowledgeQueryPlan(ctx context.Context, query string) knowledgeQueryPlan {
	return knowledgeQueryPlanner{expander: s.expander}.Plan(ctx, query)
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
