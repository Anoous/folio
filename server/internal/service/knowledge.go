package service

import (
	"context"
	"fmt"
	"strings"

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

type KnowledgeService struct {
	repo     knowledgeDocumentLister
	evidence *EvidenceService
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

func (s *KnowledgeService) Ask(ctx context.Context, userID, question string) (*KnowledgeAnswer, error) {
	contextResult, err := s.Retrieve(ctx, userID, question, KnowledgeRetrieveOptions{
		Mode:       KnowledgeModeAsk,
		MaxSources: 5,
	})
	if err != nil {
		return nil, err
	}
	return knowledgeAnswerComposer{}.compose(question, contextResult), nil
}

func (s *KnowledgeService) Spark(ctx context.Context, userID, prompt string) (*KnowledgeSparkResult, error) {
	docs, err := s.sparkSourceCollector().collect(ctx, userID, prompt)
	if err != nil {
		return nil, err
	}

	insights := composeSparkInsights(prompt, docs)
	result := groundSparkResult(insights, docs)
	return result, nil
}

func (s *KnowledgeService) Learn(ctx context.Context, userID, prompt string) (*KnowledgeLearnResult, error) {
	contextResult, err := s.learnContextCollector().collect(ctx, userID, prompt)
	if err != nil {
		return nil, err
	}

	summary := composeLearnSummary(prompt, contextResult.Sources)
	items := composeLearnItems(prompt, contextResult.Sources)
	result := &KnowledgeLearnResult{
		Summary: summary,
		Items:   items,
	}
	return groundLearnResult(result, contextResult.Sources), nil
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
	grounding := newKnowledgeGrounding(sources)
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
		sourceIDs := grounding.groundedSourceIDs(insight.SourceIDs)
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
		Sources:  grounding.sourcesByUsedIDs(usedSources),
	}
}

func groundLearnResult(result *KnowledgeLearnResult, sources []KnowledgeSource) *KnowledgeLearnResult {
	if result == nil {
		return &KnowledgeLearnResult{Summary: "目前还没有足够来源生成学习包。"}
	}

	grounding := newKnowledgeGrounding(sources)
	grounded := make([]KnowledgeLearnItem, 0, len(result.Items))
	usedSources := map[string]bool{}
	for _, item := range result.Items {
		if strings.TrimSpace(item.Type) == "" ||
			strings.TrimSpace(item.Title) == "" ||
			strings.TrimSpace(item.Content) == "" {
			continue
		}
		sourceIDs := grounding.groundedSourceIDs(item.SourceIDs)
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
		Sources: grounding.sourcesByUsedIDs(usedSources),
	}
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
