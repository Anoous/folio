package client

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"folio-server/internal/pipeline"
)

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

	respBody, statusCode, err := d.doChatRequest(ctx, chatReq)
	if err != nil {
		if isTimeoutError(err) {
			return nil, pipeline.Wrap(
				pipeline.StageAIAnalyze,
				pipeline.ProviderDeepSeek,
				pipeline.CodeTimeout,
				true,
				http.StatusGatewayTimeout,
				"deepseek analyze request timed out",
				err,
			)
		}
		return nil, pipeline.Wrap(
			pipeline.StageAIAnalyze,
			pipeline.ProviderDeepSeek,
			pipeline.CodeNetwork,
			true,
			http.StatusBadGateway,
			"deepseek analyze request failed",
			err,
		)
	}
	if statusCode != http.StatusOK {
		return nil, pipeline.Wrap(
			pipeline.StageAIAnalyze,
			pipeline.ProviderDeepSeek,
			classifyDeepSeekStatus(statusCode),
			deepSeekRetryable(statusCode),
			statusCode,
			fmt.Sprintf("deepseek returned status %d", statusCode),
			nil,
		)
	}

	var chatResp chatResponse
	if err := json.Unmarshal(respBody, &chatResp); err != nil {
		return nil, pipeline.Wrap(
			pipeline.StageAIAnalyze,
			pipeline.ProviderDeepSeek,
			pipeline.CodeInvalidResponse,
			false,
			http.StatusOK,
			"decode analyze response",
			err,
		)
	}
	if chatResp.Error != nil {
		return nil, pipeline.Wrap(
			pipeline.StageAIAnalyze,
			pipeline.ProviderDeepSeek,
			pipeline.CodeInvalidResponse,
			false,
			http.StatusOK,
			chatResp.Error.Message,
			nil,
		)
	}
	if len(chatResp.Choices) == 0 {
		return nil, pipeline.Wrap(
			pipeline.StageAIAnalyze,
			pipeline.ProviderDeepSeek,
			pipeline.CodeInvalidResponse,
			false,
			http.StatusOK,
			"deepseek returned no choices",
			nil,
		)
	}

	var result AnalyzeResponse
	if err := json.Unmarshal([]byte(chatResp.Choices[0].Message.Content), &result); err != nil {
		return nil, pipeline.Wrap(
			pipeline.StageAIAnalyze,
			pipeline.ProviderDeepSeek,
			pipeline.CodeInvalidResponse,
			false,
			http.StatusOK,
			"decode analysis json",
			err,
		)
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

7. **semantic_keywords**：生成 10-15 个语义关键词（全部小写），用于后续检索匹配。包含核心概念的中英文双语表达、同义词、上下位概念。

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
  "language": "zh 或 en",
  "semantic_keywords": ["keyword1", "关键词2", ...]
}`, catLines.String())
}

// buildUserPrompt constructs the user prompt, sanitizing inputs and truncating
// content to 12000 runes.
func buildUserPrompt(title, content, source, author string) string {
	title = SanitizeField(title)
	content = SanitizeField(content)
	source = SanitizeField(source)
	author = SanitizeField(author)

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

	// Lowercase all semantic keywords
	for i, kw := range resp.SemanticKeywords {
		resp.SemanticKeywords[i] = strings.ToLower(kw)
	}
	if resp.SemanticKeywords == nil {
		resp.SemanticKeywords = []string{}
	}
}
