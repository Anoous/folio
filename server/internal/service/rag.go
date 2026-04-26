package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"slices"
	"strings"
	"time"

	"folio-server/internal/client"
	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

const (
	ragFreeMonthlyLimit   = 5
	ragMaxSummaryRunes    = 200
	ragTokenBudget        = 50000
	ragArticleFallbackCap = 500
	ragSearchFallbackSize = 50
	ragHistoryLimit       = 10
)

// RAGService orchestrates question-answering over a user's saved articles.
type RAGService struct {
	ragRepo          *repository.RAGRepo
	userRepo         *repository.UserRepo
	aiClient         client.Analyzer
	knowledgeService *KnowledgeService
}

// NewRAGService creates a new RAGService.
func NewRAGService(ragRepo *repository.RAGRepo, userRepo *repository.UserRepo, aiClient client.Analyzer, knowledgeService *KnowledgeService) *RAGService {
	return &RAGService{
		ragRepo:          ragRepo,
		userRepo:         userRepo,
		aiClient:         aiClient,
		knowledgeService: knowledgeService,
	}
}

// Query answers a user question using their saved article summaries as context.
func (s *RAGService) Query(ctx context.Context, userID, question, conversationID string) (*domain.RAGResponse, error) {
	// 1. Quota check
	if err := s.checkQuota(ctx, userID); err != nil {
		return nil, err
	}

	// 2. Load articles
	articles, err := s.ragRepo.LoadArticleSummaries(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("load articles: %w", err)
	}
	if len(articles) == 0 {
		return &domain.RAGResponse{
			Answer:      "先收藏一些文章再来提问吧。",
			Sources:     nil,
			SourceCount: 0,
		}, nil
	}

	question = strings.TrimSpace(client.SanitizeField(question))
	knowledgeAnswer, err := s.knowledgeService.Ask(ctx, userID, question)
	if err != nil {
		slog.Error("knowledge ask failed", "user_id", userID, "error", err)
		return &domain.RAGResponse{
			Answer:      "抱歉，回答生成失败，请重试。",
			Sources:     nil,
			SourceCount: 0,
		}, nil
	}

	ragResult := &client.RAGResult{
		Answer:              knowledgeAnswer.Answer,
		CitedIndices:        knowledgeAnswer.CitedIndices,
		FollowupSuggestions: knowledgeAnswer.FollowupSuggestions,
	}
	sources := knowledgeSourcesToRAGSources(knowledgeAnswer.Sources)

	// 9. Save conversation.
	conversationID, err = s.saveConversation(ctx, userID, conversationID, question, ragResult, sources)
	if err != nil {
		slog.Error("failed to save rag conversation", "user_id", userID, "error", err)
		// Non-fatal: still return the answer.
	}

	// 10. Increment quota for Free users (best-effort).
	if incrErr := s.incrementQuotaIfFree(ctx, userID); incrErr != nil {
		slog.Error("failed to increment rag quota", "user_id", userID, "error", incrErr)
	}

	return &domain.RAGResponse{
		Answer:              knowledgeAnswer.Answer,
		Sources:             sources,
		SourceCount:         len(sources),
		FollowupSuggestions: knowledgeAnswer.FollowupSuggestions,
		ConversationID:      conversationID,
	}, nil
}

// QueryStream runs the three-phase RAG pipeline, emitting events to the channel.
func (s *RAGService) QueryStream(ctx context.Context, userID, question, conversationID string, events chan<- domain.RAGStreamEvent) {
	defer close(events)

	// Phase 1: Retrieval

	if err := s.checkQuota(ctx, userID); err != nil {
		if errors.Is(err, ErrRAGQuotaExceeded) {
			events <- domain.RAGStreamEvent{Type: "error", ErrorCode: "quota_exceeded", ErrorMessage: "monthly RAG quota exceeded"}
		} else {
			events <- domain.RAGStreamEvent{Type: "error", ErrorCode: "internal_error", ErrorMessage: "internal error"}
		}
		return
	}

	articles, err := s.ragRepo.LoadArticleSummaries(ctx, userID)
	if err != nil {
		events <- domain.RAGStreamEvent{Type: "error", ErrorCode: "internal_error", ErrorMessage: "internal error"}
		return
	}
	if len(articles) == 0 {
		events <- domain.RAGStreamEvent{Type: "error", ErrorCode: "no_articles", ErrorMessage: "no articles saved yet"}
		return
	}

	question = strings.TrimSpace(client.SanitizeField(question))
	knowledgeAnswer, err := s.knowledgeService.Ask(ctx, userID, question)
	if err != nil {
		events <- domain.RAGStreamEvent{Type: "error", ErrorCode: "internal_error", ErrorMessage: "answer generation failed"}
		return
	}
	sources := knowledgeSourcesToRAGSources(knowledgeAnswer.Sources)

	// Create conversation early so we can send conversation_id in sources event
	if conversationID == "" {
		conv := &domain.RAGConversation{
			UserID: userID,
			Title:  truncateStringPtr(question, 50),
		}
		if err := s.ragRepo.CreateConversation(ctx, conv); err != nil {
			slog.Error("failed to create conversation", "error", err)
		} else {
			conversationID = conv.ID
		}
	}

	select {
	case events <- domain.RAGStreamEvent{
		Type:           "sources",
		Sources:        sources,
		SourceCount:    len(sources),
		ConversationID: conversationID,
	}:
	case <-ctx.Done():
		return
	}

	// Phase 2: Streaming answer generation
	fullAnswer := knowledgeAnswer.Answer
	for _, r := range fullAnswer {
		select {
		case events <- domain.RAGStreamEvent{Type: "delta", Text: string(r)}:
		case <-ctx.Done():
			return
		}
	}

	// Phase 3: Post-processing
	citedIndices := knowledgeAnswer.CitedIndices
	followups := knowledgeAnswer.FollowupSuggestions

	if _, saveErr := s.saveConversation(ctx, userID, conversationID, question, &client.RAGResult{
		Answer:              fullAnswer,
		CitedIndices:        citedIndices,
		FollowupSuggestions: followups,
	}, sources); saveErr != nil {
		slog.Error("failed to save rag conversation", "user_id", userID, "error", saveErr)
	}

	if incrErr := s.incrementQuotaIfFree(ctx, userID); incrErr != nil {
		slog.Error("failed to increment rag quota", "user_id", userID, "error", incrErr)
	}

	select {
	case events <- domain.RAGStreamEvent{
		Type:                "done",
		CitedIndices:        citedIndices,
		FollowupSuggestions: followups,
	}:
	case <-ctx.Done():
	}
}

func knowledgeSourcesToRAGSources(sources []KnowledgeSource) []domain.RAGSource {
	result := make([]domain.RAGSource, 0, len(sources))
	for _, source := range sources {
		result = append(result, domain.RAGSource{
			ArticleID:       source.ArticleID,
			Title:           source.Title,
			SiteName:        source.SiteName,
			Summary:         source.Summary,
			EvidenceSnippet: source.EvidenceSnippet,
			CreatedAt:       source.CreatedAt,
			Relevance:       source.Relevance,
		})
	}
	return result
}

// checkQuota verifies the user hasn't exceeded their monthly RAG quota.
// Pro users are unlimited; Free users get ragFreeMonthlyLimit per month.
func (s *RAGService) checkQuota(ctx context.Context, userID string) error {
	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return fmt.Errorf("get user for quota: %w", err)
	}
	if user == nil {
		return ErrNotFound
	}

	// Pro users have unlimited RAG queries.
	if user.Subscription != domain.SubscriptionFree {
		return nil
	}

	count, resetAt, err := s.ragRepo.GetUserRAGQuota(ctx, userID)
	if err != nil {
		return fmt.Errorf("get rag quota: %w", err)
	}

	// Reset if needed: resetAt is nil or before the 1st of this month.
	now := time.Now().UTC()
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	if resetAt == nil || resetAt.Before(monthStart) {
		if resetErr := s.ragRepo.ResetRAGMonthCount(ctx, userID, now); resetErr != nil {
			return fmt.Errorf("reset rag month count: %w", resetErr)
		}
		count = 0
	}

	if count >= ragFreeMonthlyLimit {
		return ErrRAGQuotaExceeded
	}
	return nil
}

// applyTokenBudget selects articles that fit within the token budget.
// If the user has >500 articles, use smart retrieval (LLM query expansion → broad recall).
// Otherwise, use the original token budget logic.
func (s *RAGService) applyTokenBudget(ctx context.Context, userID, question string, articles []domain.RAGSource) []domain.RAGSource {
	if len(articles) > ragArticleFallbackCap {
		// Smart retrieval: LLM query expansion → multi-keyword broad recall
		keywords, err := s.aiClient.ExpandQuery(ctx, question)
		if err != nil {
			slog.Warn("query expansion failed, falling back to pg_trgm", "error", err)
			return s.fallbackSearch(ctx, userID, question, articles)
		}
		recalled, err := s.ragRepo.BroadRecallSummaries(ctx, userID, keywords, ragSearchFallbackSize, "")
		if err != nil || len(recalled) == 0 {
			slog.Warn("broad recall failed or empty, falling back to pg_trgm",
				"error", err, "recalled", len(recalled))
			return s.fallbackSearch(ctx, userID, question, articles)
		}
		return recalled
	}

	// < 500 articles: original token budget logic unchanged
	var selected []domain.RAGSource
	var estimatedTokens int

	for _, a := range articles {
		summary := derefString(a.Summary)
		summary = truncateRunes(summary, ragMaxSummaryRunes)

		title := a.Title
		tokens := estimateTokens(title) + estimateTokens(summary)

		if estimatedTokens+tokens > ragTokenBudget {
			searched, err := s.ragRepo.SearchArticleSummaries(ctx, userID, question, ragSearchFallbackSize)
			if err != nil {
				slog.Warn("search fallback failed after budget exceeded", "error", err)
				break
			}
			return searched
		}

		estimatedTokens += tokens
		selected = append(selected, a)
	}

	if len(selected) == 0 {
		return articles
	}
	return selected
}

// fallbackSearch is the degradation path when smart retrieval fails.
func (s *RAGService) fallbackSearch(ctx context.Context, userID, question string, articles []domain.RAGSource) []domain.RAGSource {
	searched, err := s.ragRepo.SearchArticleSummaries(ctx, userID, question, ragSearchFallbackSize)
	if err != nil || len(searched) == 0 {
		if len(articles) > ragSearchFallbackSize {
			return articles[:ragSearchFallbackSize]
		}
		return articles
	}
	return searched
}

// estimateTokens gives a rough token count for a string.
// CJK characters are counted as ~1.5 tokens each; ASCII chars as ~0.25 tokens (4 chars/token).
func estimateTokens(s string) int {
	var tokens float64
	for _, r := range s {
		if r >= 0x4e00 && r <= 0x9fff {
			tokens += 1.5
		} else {
			tokens += 0.25
		}
	}
	if tokens < 1 {
		return 1
	}
	return int(tokens)
}

// buildRAGSystemPrompt returns the system prompt for RAG queries.
func buildRAGSystemPrompt() string {
	return `你是用户的个人知识助手。以下是用户收藏的文章摘要列表。
基于且仅基于这些文章回答用户的问题。

输出 JSON 格式（不要 markdown 代码块）：
{
  "answer": "回答正文，在引用处用上标数字标注对应文章编号，如 ¹ ² ³",
  "cited_indices": [1, 3, 5],
  "followup_suggestions": ["建议追问1", "建议追问2"]
}

规则：
1. 只基于用户的收藏回答，不编造内容
2. 引用标注必须对应下方文章列表的编号
3. 回答风格：简洁、有洞察力、直击核心。对核心观点用加粗强调
4. 给出 2 个建议的跟进问题
5. 如果收藏中没有相关内容，answer 写 "你的收藏中没有找到与此相关的内容。"，cited_indices 为空`
}

// buildRAGUserPrompt constructs the user prompt with articles, history, and question.
func buildRAGUserPrompt(articles []domain.RAGSource, history []domain.RAGMessage, question string) string {
	var b strings.Builder

	fmt.Fprintf(&b, "用户收藏（共 %d 篇）：\n\n", len(articles))

	for i, a := range articles {
		title := a.Title
		siteName := derefString(a.SiteName)
		if siteName == "" {
			siteName = "未知来源"
		}
		date := a.CreatedAt.Format("2006-01-02")
		summary := derefString(a.Summary)
		summary = truncateRunes(summary, ragMaxSummaryRunes)

		fmt.Fprintf(&b, "[%d] 《%s》(%s, %s): %s\n", i+1, title, siteName, date, summary)
	}

	// Append conversation history if present.
	if len(history) > 0 {
		b.WriteString("\n")
		for _, msg := range history {
			switch msg.Role {
			case "user":
				fmt.Fprintf(&b, "用户：%s\n", msg.Content)
			case "assistant":
				// Extract just the answer text from the stored JSON if possible.
				answer := extractAnswerFromContent(msg.Content)
				fmt.Fprintf(&b, "助手：%s\n", answer)
			}
		}
	}

	fmt.Fprintf(&b, "\n用户问题：%s", question)

	return b.String()
}

// extractCitedIndices extracts 1-based citation indices from answer text.
// Matches Unicode superscript digits (¹²³⁴⁵⁶⁷⁸⁹) and bracket citations ([1], [12]).
// Returns deduplicated, sorted indices.
func extractCitedIndices(answer string) []int {
	seen := make(map[int]bool)
	var indices []int

	superscripts := map[rune]int{
		'\u00B9': 1, '\u00B2': 2, '\u00B3': 3,
		'\u2074': 4, '\u2075': 5, '\u2076': 6,
		'\u2077': 7, '\u2078': 8, '\u2079': 9,
	}

	runes := []rune(answer)
	for i := 0; i < len(runes); i++ {
		if idx, ok := superscripts[runes[i]]; ok {
			if !seen[idx] {
				seen[idx] = true
				indices = append(indices, idx)
			}
			continue
		}

		if runes[i] == '[' && i+2 < len(runes) {
			j := i + 1
			num := 0
			for j < len(runes) && runes[j] >= '0' && runes[j] <= '9' {
				num = num*10 + int(runes[j]-'0')
				j++
			}
			if j > i+1 && j < len(runes) && runes[j] == ']' && num > 0 {
				if !seen[num] {
					seen[num] = true
					indices = append(indices, num)
				}
				i = j
			}
		}
	}

	slices.Sort(indices)
	return indices
}

// buildRAGStreamSystemPrompt returns the system prompt for streaming RAG queries.
// Unlike buildRAGSystemPrompt, this produces plain text (not JSON) for streaming.
func buildRAGStreamSystemPrompt() string {
	return `你是用户的个人知识助手。以下是用户收藏的文章摘要列表。
基于且仅基于这些文章回答用户的问题。

规则：
1. 只基于用户的收藏回答，不编造内容
2. 在引用处用上标数字标注对应文章编号，如 ¹ ² ³
3. 回答风格：简洁、有洞察力、直击核心。对核心观点用 **加粗** 强调
4. 如果收藏中没有相关内容，回答"你的收藏中没有找到与此相关的内容。"`
}

// extractAnswerFromContent tries to parse stored assistant content as JSON and extract
// just the answer field. Falls back to the raw content if parsing fails.
func extractAnswerFromContent(content string) string {
	var parsed struct {
		Answer string `json:"answer"`
	}
	if err := json.Unmarshal([]byte(content), &parsed); err == nil && parsed.Answer != "" {
		return parsed.Answer
	}
	return content
}

// mapCitedSources converts 1-based cited indices to actual RAGSource entries.
// Invalid indices (out of range) are logged and filtered.
func mapCitedSources(citedIndices []int, articles []domain.RAGSource) []domain.RAGSource {
	if len(citedIndices) == 0 {
		return nil
	}

	seen := make(map[int]bool)
	var sources []domain.RAGSource
	for _, idx := range citedIndices {
		// cited_indices are 1-based.
		arrayIdx := idx - 1
		if arrayIdx < 0 || arrayIdx >= len(articles) {
			slog.Warn("rag: citation index out of bounds", "index", idx, "total", len(articles))
			continue
		}
		if seen[idx] {
			continue
		}
		seen[idx] = true
		sources = append(sources, articles[arrayIdx])
	}
	return sources
}

// saveConversation persists the user question and assistant answer.
// Returns the conversation ID (possibly newly created).
func (s *RAGService) saveConversation(
	ctx context.Context,
	userID, conversationID, question string,
	ragResult *client.RAGResult,
	sources []domain.RAGSource,
) (string, error) {
	// Create new conversation if none provided.
	if conversationID == "" {
		conv := &domain.RAGConversation{
			UserID: userID,
			Title:  truncateStringPtr(question, 50),
		}
		if err := s.ragRepo.CreateConversation(ctx, conv); err != nil {
			return "", fmt.Errorf("create conversation: %w", err)
		}
		conversationID = conv.ID
	}

	// Save user message.
	userMsg := &domain.RAGMessage{
		ConversationID:   conversationID,
		Role:             "user",
		Content:          question,
		SourceArticleIDs: []string{},
		SourceCount:      0,
	}
	if err := s.ragRepo.AddMessage(ctx, userMsg); err != nil {
		return conversationID, fmt.Errorf("save user message: %w", err)
	}

	// Save assistant message with cited sources.
	sourceIDs := make([]string, 0, len(sources))
	for _, src := range sources {
		sourceIDs = append(sourceIDs, src.ArticleID)
	}

	// Store the full RAG result JSON as the assistant content.
	assistantContent, _ := json.Marshal(ragResult)

	assistantMsg := &domain.RAGMessage{
		ConversationID:   conversationID,
		Role:             "assistant",
		Content:          string(assistantContent),
		SourceArticleIDs: sourceIDs,
		SourceCount:      len(sourceIDs),
	}
	if err := s.ragRepo.AddMessage(ctx, assistantMsg); err != nil {
		return conversationID, fmt.Errorf("save assistant message: %w", err)
	}

	return conversationID, nil
}

// incrementQuotaIfFree increments RAG usage count for Free-tier users.
func (s *RAGService) incrementQuotaIfFree(ctx context.Context, userID string) error {
	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return err
	}
	if user == nil || user.Subscription != domain.SubscriptionFree {
		return nil
	}
	return s.ragRepo.IncrementRAGMonthCount(ctx, userID)
}

// truncateRunes truncates s to maxRunes runes, appending "..." if truncated.
func truncateRunes(s string, maxRunes int) string {
	runes := []rune(s)
	if len(runes) <= maxRunes {
		return s
	}
	return string(runes[:maxRunes]) + "…"
}

// truncateStringPtr returns a *string truncated to maxRunes runes.
func truncateStringPtr(s string, maxRunes int) *string {
	t := truncateRunes(s, maxRunes)
	return &t
}

// derefString safely dereferences a *string, returning "" if nil.
func derefString(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
