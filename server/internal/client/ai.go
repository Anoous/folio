package client

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// RAGResult is the parsed output from the RAG LLM call.
type RAGResult struct {
	Answer              string   `json:"answer"`
	CitedIndices        []int    `json:"cited_indices"`
	FollowupSuggestions []string `json:"followup_suggestions"`
}

// Analyzer abstracts AI analysis so callers can swap implementations (real vs mock).
type Analyzer interface {
	Analyze(ctx context.Context, req AnalyzeRequest) (*AnalyzeResponse, error)
	GenerateEchoCards(ctx context.Context, title string, source string, keyPoints []string) ([]EchoQAPair, error)
	GenerateRAGAnswer(ctx context.Context, systemPrompt, userPrompt string) (*RAGResult, error)
}

// AnalyzeRequest is the input for AI article analysis.
type AnalyzeRequest struct {
	Title   string `json:"title"`
	Content string `json:"content"`
	Source  string `json:"source"`
	Author  string `json:"author"`
}

// AnalyzeResponse is the output from AI article analysis.
type AnalyzeResponse struct {
	Category     string   `json:"category"`
	CategoryName string   `json:"category_name"`
	Confidence   float64  `json:"confidence"`
	Tags         []string `json:"tags"`
	Summary      string   `json:"summary"`
	KeyPoints    []string `json:"key_points"`
	Language     string   `json:"language"`
}

// categoryEntry holds a slug→name pair for the 9 predefined categories.
type categoryEntry struct {
	Slug string
	Name string
}

var categoryList = []categoryEntry{
	{"tech", "Technology"}, {"business", "Business"}, {"science", "Science"},
	{"culture", "Culture"}, {"lifestyle", "Lifestyle"}, {"news", "News"},
	{"education", "Education"}, {"design", "Design"}, {"other", "Other"},
}

var validCategories = func() map[string]string {
	m := make(map[string]string, len(categoryList))
	for _, c := range categoryList {
		m[c.Slug] = c.Name
	}
	return m
}()

// DeepSeekAnalyzer calls the DeepSeek (OpenAI-compatible) API directly.
type DeepSeekAnalyzer struct {
	apiKey     string
	baseURL    string
	httpClient *http.Client
}

// NewDeepSeekAnalyzer creates a DeepSeekAnalyzer.
// baseURL should be e.g. "https://api.deepseek.com" (no trailing slash).
func NewDeepSeekAnalyzer(apiKey, baseURL string) *DeepSeekAnalyzer {
	return &DeepSeekAnalyzer{
		apiKey:     apiKey,
		baseURL:    strings.TrimRight(baseURL, "/"),
		httpClient: &http.Client{Timeout: 60 * time.Second},
	}
}

// --- OpenAI-compatible request/response types ---

type chatRequest struct {
	Model          string        `json:"model"`
	Messages       []chatMessage `json:"messages"`
	Temperature    float64       `json:"temperature"`
	MaxTokens      int           `json:"max_tokens"`
	ResponseFormat *respFormat   `json:"response_format,omitempty"`
}

type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type respFormat struct {
	Type string `json:"type"`
}

type chatResponse struct {
	Choices []chatChoice `json:"choices"`
	Error   *chatError   `json:"error,omitempty"`
}

type chatChoice struct {
	Message chatMessage `json:"message"`
}

type chatError struct {
	Message string `json:"message"`
	Type    string `json:"type"`
}

// Analyze sends the article to DeepSeek and returns the structured analysis.
func (d *DeepSeekAnalyzer) Analyze(ctx context.Context, req AnalyzeRequest) (*AnalyzeResponse, error) {
	systemPrompt := buildSystemPrompt()
	userPrompt := buildUserPrompt(req.Title, req.Content, req.Source, req.Author)

	chatReq := chatRequest{
		Model: "deepseek-chat",
		Messages: []chatMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
		Temperature:    0.3,
		MaxTokens:      1024,
		ResponseFormat: &respFormat{Type: "json_object"},
	}

	body, err := json.Marshal(chatReq)
	if err != nil {
		return nil, fmt.Errorf("marshal chat request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", d.baseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+d.apiKey)

	resp, err := d.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("deepseek request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("deepseek api error: status %d, body: %s", resp.StatusCode, string(respBody))
	}

	var chatResp chatResponse
	if err := json.Unmarshal(respBody, &chatResp); err != nil {
		return nil, fmt.Errorf("decode chat response: %w", err)
	}

	if chatResp.Error != nil {
		return nil, fmt.Errorf("deepseek api error: %s", chatResp.Error.Message)
	}

	if len(chatResp.Choices) == 0 {
		return nil, fmt.Errorf("deepseek returned no choices")
	}

	var result AnalyzeResponse
	if err := json.Unmarshal([]byte(chatResp.Choices[0].Message.Content), &result); err != nil {
		return nil, fmt.Errorf("decode analysis json: %w (raw: %s)", err, chatResp.Choices[0].Message.Content)
	}

	validateResponse(&result)
	return &result, nil
}

// buildSystemPrompt constructs the system prompt with the category list.
func buildSystemPrompt() string {
	var catLines strings.Builder
	for _, c := range categoryList {
		fmt.Fprintf(&catLines, "   - %s (%s)\n", c.Slug, c.Name)
	}

	return fmt.Sprintf(`你是一个文章分析助手。给定一篇文章的标题、正文、来源和作者，你需要完成以下任务：

1. **分类**：从以下 9 个类别中选择最合适的一个：
%s
2. **标签**：提取 3-5 个关键标签（关键词），用于描述文章主题。

3. **语言检测**：判断文章主要语言，输出 "zh"（中文）或 "en"（英文）。

4. **置信度**：给出你对分类结果的置信度（0.0-1.0）。

5. **summary**：一句核心洞察（不是概括全文，而是文章中最令人惊讶、最反直觉、或最有价值的单一发现），用陈述句，像 pull quote 一样有冲击力。不超过 40 字。

6. **key_points**：3-5 个支撑核心洞察的要点，每条不超过 15 字，是具体论据而非泛泛概括。

**重要规则**：
- 摘要和标签的语言应跟随文章本身的语言（中文文章用中文，英文文章用英文）。
- category 必须是上述 9 个 slug 之一，不得自创。
- 直接输出 JSON，不要用 markdown code fence 包裹。

输出格式（严格 JSON）：
{
  "category": "<slug>",
  "category_name": "<人类可读分类名>",
  "confidence": <0.0-1.0>,
  "tags": ["tag1", "tag2", "tag3"],
  "summary": "<摘要>",
  "key_points": ["要点1", "要点2", "要点3"],
  "language": "zh 或 en"
}`, catLines.String())
}

// sanitizeField removes injection markers from a single field.
func sanitizeField(s string) string {
	s = strings.ReplaceAll(s, "```", "")
	s = strings.ReplaceAll(s, "system:", "")
	s = strings.ReplaceAll(s, "assistant:", "")
	s = strings.ReplaceAll(s, "user:", "")
	return s
}

// buildUserPrompt constructs the user prompt, sanitizing inputs and truncating
// content to 12000 runes.
func buildUserPrompt(title, content, source, author string) string {
	title = sanitizeField(title)
	content = sanitizeField(content)
	source = sanitizeField(source)
	author = sanitizeField(author)

	const maxContentRunes = 12000
	runes := []rune(content)
	if len(runes) > maxContentRunes {
		content = string(runes[:maxContentRunes]) + "\n...(内容已截断)"
	}

	return fmt.Sprintf("标题：%s\n来源：%s\n作者：%s\n\n正文：\n%s", title, source, author, content)
}

// validateResponse fixes invalid LLM outputs in place.
func validateResponse(resp *AnalyzeResponse) {
	// Validate category
	if name, ok := validCategories[resp.Category]; ok {
		resp.CategoryName = name
	} else {
		resp.Category = "other"
		resp.CategoryName = "Other"
		if resp.Confidence > 0.5 {
			resp.Confidence = 0.5
		}
	}

	// Clamp confidence to [0, 1]
	if resp.Confidence < 0 {
		resp.Confidence = 0
	}
	if resp.Confidence > 1.0 {
		resp.Confidence = 1.0
	}

	// Validate tags
	if len(resp.Tags) == 0 {
		resp.Tags = []string{"untagged"}
	}
	if len(resp.Tags) > 5 {
		resp.Tags = resp.Tags[:5]
	}

	// Validate key_points
	if len(resp.KeyPoints) == 0 {
		resp.KeyPoints = []string{"N/A"}
	}
	if len(resp.KeyPoints) > 5 {
		resp.KeyPoints = resp.KeyPoints[:5]
	}

	// Validate language
	if resp.Language != "zh" && resp.Language != "en" {
		resp.Language = "en"
	}
}

// EchoQAPair represents a question/answer pair for echo card generation.
type EchoQAPair struct {
	Question      string `json:"question"`
	Answer        string `json:"answer"`
	SourceContext string `json:"source_context"`
}

// GenerateEchoCards calls DeepSeek to generate 1-2 echo Q&A pairs from article key points.
// If the analyzer has no API key, it returns a deterministic fallback using key_points directly.
func (d *DeepSeekAnalyzer) GenerateEchoCards(ctx context.Context, title string, source string, keyPoints []string) ([]EchoQAPair, error) {
	if d.apiKey == "" {
		return generateMockEchoCards(title, source, keyPoints), nil
	}

	systemPrompt := `你是一个回忆测试生成器。基于文章要点，生成 1-2 个回忆测试问答对。

要求：
1. question：用"还记得……吗？"的口吻，引导用户主动回忆，不超过 30 字
2. answer：简洁的答案，可以是原文引用或精炼表述，不超过 50 字
3. source_context：格式为 "来自《文章标题》· 来源名"

输出 JSON 数组，不要 markdown 代码块：[{"question":"...", "answer":"...", "source_context":"..."}]`

	var pointsBuilder strings.Builder
	for _, kp := range keyPoints {
		fmt.Fprintf(&pointsBuilder, "- %s\n", kp)
	}

	userPrompt := fmt.Sprintf("文章标题：%s\n来源：%s\n要点：\n%s", sanitizeField(title), sanitizeField(source), pointsBuilder.String())

	chatReq := chatRequest{
		Model: "deepseek-chat",
		Messages: []chatMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
		Temperature:    0.3,
		MaxTokens:      512,
		ResponseFormat: &respFormat{Type: "json_object"},
	}

	body, err := json.Marshal(chatReq)
	if err != nil {
		return nil, fmt.Errorf("marshal echo chat request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", d.baseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create echo request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+d.apiKey)

	resp, err := d.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("echo deepseek request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read echo response body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("echo deepseek api error: status %d, body: %s", resp.StatusCode, string(respBody))
	}

	var chatResp chatResponse
	if err := json.Unmarshal(respBody, &chatResp); err != nil {
		return nil, fmt.Errorf("decode echo chat response: %w", err)
	}

	if chatResp.Error != nil {
		return nil, fmt.Errorf("echo deepseek api error: %s", chatResp.Error.Message)
	}

	if len(chatResp.Choices) == 0 {
		return nil, fmt.Errorf("echo deepseek returned no choices")
	}

	content := chatResp.Choices[0].Message.Content

	// Try parsing as array directly
	var pairs []EchoQAPair
	if err := json.Unmarshal([]byte(content), &pairs); err == nil && len(pairs) > 0 {
		return pairs, nil
	}

	// Try parsing as object with array field (json_object mode may wrap)
	var wrapper map[string]json.RawMessage
	if err := json.Unmarshal([]byte(content), &wrapper); err == nil {
		for _, v := range wrapper {
			if err := json.Unmarshal(v, &pairs); err == nil && len(pairs) > 0 {
				return pairs, nil
			}
		}
	}

	// Fallback: return a template card using the first key point
	return echoFallbackCards(title, source, keyPoints), nil
}

// generateMockEchoCards returns deterministic echo cards without calling any API.
func generateMockEchoCards(title, source string, keyPoints []string) []EchoQAPair {
	return echoFallbackCards(title, source, keyPoints)
}

// GenerateRAGAnswer calls DeepSeek to produce a RAG answer from a system + user prompt.
// Uses a 30-second timeout. If no API key is configured, returns a mock fallback.
func (d *DeepSeekAnalyzer) GenerateRAGAnswer(ctx context.Context, systemPrompt, userPrompt string) (*RAGResult, error) {
	if d.apiKey == "" {
		return &RAGResult{
			Answer:              "这是一个模拟回答。基于你的收藏¹，...",
			CitedIndices:        []int{1},
			FollowupSuggestions: []string{"还有什么相关的？"},
		}, nil
	}

	chatReq := chatRequest{
		Model: "deepseek-chat",
		Messages: []chatMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
		Temperature:    0.3,
		MaxTokens:      2048,
		ResponseFormat: &respFormat{Type: "json_object"},
	}

	body, err := json.Marshal(chatReq)
	if err != nil {
		return nil, fmt.Errorf("marshal rag chat request: %w", err)
	}

	// Use a 30-second timeout for RAG calls.
	ragCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	httpReq, err := http.NewRequestWithContext(ragCtx, "POST", d.baseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create rag request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+d.apiKey)

	resp, err := d.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("rag deepseek request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read rag response body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("rag deepseek api error: status %d, body: %s", resp.StatusCode, string(respBody))
	}

	var chatResp chatResponse
	if err := json.Unmarshal(respBody, &chatResp); err != nil {
		return nil, fmt.Errorf("decode rag chat response: %w", err)
	}

	if chatResp.Error != nil {
		return nil, fmt.Errorf("rag deepseek api error: %s", chatResp.Error.Message)
	}

	if len(chatResp.Choices) == 0 {
		return nil, fmt.Errorf("rag deepseek returned no choices")
	}

	content := chatResp.Choices[0].Message.Content

	var result RAGResult
	if err := json.Unmarshal([]byte(content), &result); err != nil {
		return nil, fmt.Errorf("decode rag json: %w (raw: %s)", err, content)
	}

	// Ensure slices are non-nil.
	if result.CitedIndices == nil {
		result.CitedIndices = []int{}
	}
	if result.FollowupSuggestions == nil {
		result.FollowupSuggestions = []string{}
	}

	return &result, nil
}

// echoFallbackCards builds 1-2 template-based echo cards from key points.
func echoFallbackCards(title, source string, keyPoints []string) []EchoQAPair {
	if len(keyPoints) == 0 {
		return nil
	}
	sourceCtx := fmt.Sprintf("来自《%s》· %s", title, source)

	pairs := []EchoQAPair{
		{
			Question:      "还记得这篇文章的核心观点吗？",
			Answer:        keyPoints[0],
			SourceContext: sourceCtx,
		},
	}
	if len(keyPoints) >= 2 {
		pairs = append(pairs, EchoQAPair{
			Question:      "还记得这篇文章的关键论据吗？",
			Answer:        keyPoints[1],
			SourceContext: sourceCtx,
		})
	}
	return pairs
}
