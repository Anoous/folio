package client

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

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

	userPrompt := fmt.Sprintf("文章标题：%s\n来源：%s\n要点：\n%s", SanitizeField(title), SanitizeField(source), pointsBuilder.String())

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

	respBody, err := d.doRequest(ctx, chatReq)
	if err != nil {
		return nil, fmt.Errorf("generate echo cards: %w", err)
	}

	content := string(respBody)

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
