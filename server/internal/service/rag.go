package service

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
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
	ragRepo  *repository.RAGRepo
	userRepo *repository.UserRepo
	aiClient client.Analyzer
}

// NewRAGService creates a new RAGService.
func NewRAGService(ragRepo *repository.RAGRepo, userRepo *repository.UserRepo, aiClient client.Analyzer) *RAGService {
	return &RAGService{
		ragRepo:  ragRepo,
		userRepo: userRepo,
		aiClient: aiClient,
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

	// 3. Token budget — decide which articles to include in the prompt.
	articles = s.applyTokenBudget(ctx, userID, question, articles)

	// 4. Load conversation history (if continuing a conversation).
	var history []domain.RAGMessage
	if conversationID != "" {
		history, err = s.ragRepo.GetConversationMessages(ctx, conversationID, ragHistoryLimit)
		if err != nil {
			slog.Warn("failed to load conversation history", "conversation_id", conversationID, "error", err)
			history = nil
		}
	}

	// 5. Sanitize question.
	question = strings.TrimSpace(client.SanitizeField(question))

	// 6. Build prompts.
	systemPrompt := buildRAGSystemPrompt()
	userPrompt := buildRAGUserPrompt(articles, history, question)

	// 7. Call AI.
	ragResult, err := s.aiClient.GenerateRAGAnswer(ctx, systemPrompt, userPrompt)
	if err != nil {
		slog.Error("rag ai call failed", "user_id", userID, "error", err)
		return &domain.RAGResponse{
			Answer:      "抱歉，回答生成失败，请重试。",
			Sources:     nil,
			SourceCount: 0,
		}, nil
	}

	// 8. Map cited_indices to actual article sources.
	sources := mapCitedSources(ragResult.CitedIndices, articles)

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
		Answer:              ragResult.Answer,
		Sources:             sources,
		SourceCount:         len(articles),
		FollowupSuggestions: ragResult.FollowupSuggestions,
		ConversationID:      conversationID,
	}, nil
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
// Invalid indices (out of range) are silently filtered.
func mapCitedSources(citedIndices []int, articles []domain.RAGSource) []domain.RAGSource {
	if len(citedIndices) == 0 {
		return nil
	}

	seen := make(map[int]bool)
	var sources []domain.RAGSource
	for _, idx := range citedIndices {
		// cited_indices are 1-based.
		arrayIdx := idx - 1
		if arrayIdx < 0 || arrayIdx >= len(articles) || seen[idx] {
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

