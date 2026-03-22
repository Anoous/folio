package client

import (
	"context"
	"fmt"
	"regexp"
	"strings"
	"unicode/utf8"
)

// MockAnalyzer implements Analyzer with deterministic results (no API calls).
// Port of the Python mock at scripts/mock_ai_service.py.
type MockAnalyzer struct{}

// compile regex patterns once at package level
var (
	reEnglishWord  = regexp.MustCompile(`[A-Za-z][A-Za-z0-9+#.]{1,}`)
	reChineseChunk = regexp.MustCompile(`[\x{4e00}-\x{9fff}]{2,4}`)
	reMDLink       = regexp.MustCompile(`\[([^\]]*)\]\([^)]+\)`)
	reBareURL      = regexp.MustCompile(`(?:https?:)?//[^\s)]+`)
	reMDImage      = regexp.MustCompile(`!\[[^\]]*\]\([^)]+\)`)
	reMDSyntax     = regexp.MustCompile(`[#*` + "`" + `~>\[\](){}|]`)
	reWhitespace   = regexp.MustCompile(`\s+`)
)

// categoryRule maps a URL substring to a category slug and display name.
type categoryRule struct {
	pattern string
	slug    string
	name    string
}

var urlCategoryRules = []categoryRule{
	{"github.com", "tech", "Technology"},
	{"go.dev", "tech", "Technology"},
	{"dev.to", "tech", "Technology"},
	{"stackoverflow", "tech", "Technology"},
	{"arxiv.org", "science", "Science"},
	{"nature.com", "science", "Science"},
	{"bbc.com", "news", "News"},
	{"cnn.com", "news", "News"},
	{"reuters.com", "news", "News"},
	{"medium.com", "culture", "Culture"},
	{"dribbble.com", "design", "Design"},
	{"figma.com", "design", "Design"},
	{"zhihu.com", "education", "Education"},
	{"bloomberg.com", "business", "Business"},
	{"techcrunch.com", "business", "Business"},
	{"youtube.com", "lifestyle", "Lifestyle"},
}

// keywordRule maps a set of content keywords to a category.
type keywordRule struct {
	keywords []string
	slug     string
	name     string
}

var contentKeywordRules = []keywordRule{
	{[]string{"code", "programming", "api", "software", "tech"}, "tech", "Technology"},
	{[]string{"science", "research", "study"}, "science", "Science"},
	{[]string{"design", "ui", "ux"}, "design", "Design"},
	{[]string{"business", "startup", "market"}, "business", "Business"},
}

var stopWords = map[string]bool{
	"the": true, "a": true, "an": true, "is": true, "are": true,
	"was": true, "were": true, "be": true, "been": true, "being": true,
	"have": true, "has": true, "had": true, "do": true, "does": true,
	"did": true, "will": true, "would": true, "could": true,
	"should": true, "may": true, "might": true, "shall": true, "can": true,
	"to": true, "of": true, "in": true, "for": true,
	"on": true, "with": true, "at": true, "by": true, "from": true,
	"as": true, "into": true, "about": true, "between": true,
	"through": true, "after": true, "before": true, "and": true,
	"but": true, "or": true, "not": true, "no": true, "so": true,
	"if": true, "than": true, "too": true, "very": true, "just": true,
	"how": true, "what": true, "why": true, "when": true,
	"where": true, "who": true, "which": true, "that": true,
	"this": true, "these": true, "those": true, "it": true, "its": true,
	"my": true, "your": true, "his": true, "her": true, "our": true,
	"their": true, "all": true, "each": true, "every": true,
	"up": true, "out": true, "new": true, "old": true, "use": true,
	"using": true, "used": true,
	// Common Chinese particles
	"的": true, "了": true, "在": true, "是": true, "我": true,
	"有": true, "和": true, "就": true, "不": true, "人": true,
	"都": true, "一": true, "一个": true, "上": true, "也": true,
	"而": true, "到": true, "说": true, "要": true, "会": true,
	"对": true, "与": true,
}

// Analyze returns a deterministic analysis without calling any external API.
func (m *MockAnalyzer) Analyze(_ context.Context, req AnalyzeRequest) (*AnalyzeResponse, error) {
	title := orDefault(strings.TrimSpace(req.Title), "Untitled")
	content := strings.TrimSpace(req.Content)

	slug, name := pickCategory(req.Source, req.Title, req.Content)
	tags := extractMockTags(title, content)
	summary := cleanForSummary(content)

	return &AnalyzeResponse{
		Category:     slug,
		CategoryName: name,
		Confidence:   0.88,
		Tags:         tags,
		Summary:      summary,
		KeyPoints: []string{
			fmt.Sprintf("来源：%s", orDefault(req.Source, "web")),
			fmt.Sprintf("作者：%s", orDefault(req.Author, "unknown")),
			"Mock 模式，未调用 AI",
		},
		Language: detectLanguage(title),
	}, nil
}

// pickCategory selects a category based on URL patterns, then content keywords.
func pickCategory(source, title, content string) (slug, name string) {
	if s := strings.TrimSpace(source); s != "" {
		lower := strings.ToLower(s)
		for _, r := range urlCategoryRules {
			if strings.Contains(lower, r.pattern) {
				return r.slug, r.name
			}
		}
	}

	// Fallback: keyword matching on title + content[:200]
	contentSnippet := content
	if runes := []rune(content); len(runes) > 200 {
		contentSnippet = string(runes[:200])
	}
	textLower := strings.ToLower(title + " " + contentSnippet)
	for _, r := range contentKeywordRules {
		for _, kw := range r.keywords {
			if strings.Contains(textLower, kw) {
				return r.slug, r.name
			}
		}
	}

	// Default when source is present but unmatched
	if strings.TrimSpace(source) != "" {
		return "tech", "Technology"
	}
	return "other", "Other"
}

// extractMockTags extracts meaningful keywords from title (and optionally
// first line of content) as tags.
func extractMockTags(title, content string) []string {
	text := title
	// Also take first line of content if title is short
	if utf8.RuneCountInString(title) < 20 && content != "" {
		firstLine := strings.SplitN(content, "\n", 2)[0]
		firstLine = strings.TrimLeft(firstLine, "# ")
		firstLine = strings.TrimSpace(firstLine)
		text = title + " " + firstLine
	}

	// Remove markdown syntax
	text = reMDLink.ReplaceAllString(text, "$1")
	text = reMDSyntax.ReplaceAllString(text, " ")

	// Extract English words (2+ chars) and Chinese segments (2-4 chars)
	enWords := reEnglishWord.FindAllString(text, -1)
	zhSegments := reChineseChunk.FindAllString(text, -1)

	var tags []string
	seen := make(map[string]bool)
	for _, w := range append(enWords, zhSegments...) {
		lower := strings.ToLower(w)
		if stopWords[lower] || seen[lower] || len(lower) < 2 {
			continue
		}
		seen[lower] = true
		// Preserve capitalization for proper nouns; lowercase otherwise
		if w[0] >= 'A' && w[0] <= 'Z' {
			tags = append(tags, w)
		} else if !isASCII(w) {
			tags = append(tags, w)
		} else {
			tags = append(tags, lower)
		}
		if len(tags) >= 5 {
			break
		}
	}

	// Ensure at least 2 tags
	if len(tags) < 2 {
		tags = append(tags, "article")
	}
	if len(tags) > 5 {
		tags = tags[:5]
	}
	return tags
}

// cleanForSummary removes markdown artifacts, URLs, and noise from content,
// then returns a punchy single-sentence insight (truncated to 40 runes).
func cleanForSummary(text string) string {
	// Remove markdown links but keep text: [text](url) -> text
	text = reMDLink.ReplaceAllString(text, "$1")
	// Remove bare URLs
	text = reBareURL.ReplaceAllString(text, "")
	// Remove markdown image syntax
	text = reMDImage.ReplaceAllString(text, "")
	// Collapse whitespace
	text = reWhitespace.ReplaceAllString(text, " ")
	text = strings.TrimSpace(text)

	if text == "" {
		return "Mock 模式：此文章尚未经过真实 AI 分析。"
	}
	// Take only the first sentence to form a punchy insight
	for _, sep := range []string{"。", "！", "？", ". ", "! ", "? "} {
		if idx := strings.Index(text, sep); idx != -1 {
			sentence := strings.TrimSpace(text[:idx+len(sep)])
			if utf8.RuneCountInString(sentence) >= 8 {
				return truncate(sentence, 40)
			}
		}
	}
	return truncate(text, 40)
}

// detectLanguage returns "zh" if the text contains Chinese characters, else "en".
func detectLanguage(text string) string {
	if reChineseChunk.MatchString(text) {
		return "zh"
	}
	return "en"
}

// orDefault returns s if non-empty, otherwise fallback.
func orDefault(s, fallback string) string {
	if s == "" {
		return fallback
	}
	return s
}

// truncate returns s truncated to maxRunes runes, appending "..." if truncated.
func truncate(s string, maxRunes int) string {
	runes := []rune(s)
	if len(runes) <= maxRunes {
		return s
	}
	return string(runes[:maxRunes]) + "..."
}

// GenerateEchoCards returns deterministic mock echo Q&A pairs without calling any API.
func (m *MockAnalyzer) GenerateEchoCards(_ context.Context, title string, source string, keyPoints []string) ([]EchoQAPair, error) {
	if len(keyPoints) == 0 {
		return nil, nil
	}

	pairs := make([]EchoQAPair, 0, len(keyPoints))
	for i, kp := range keyPoints {
		if i >= 2 {
			break // Max 2 mock cards
		}
		pairs = append(pairs, EchoQAPair{
			Question:      fmt.Sprintf("关于「%s」，%s 的要点是什么？", orDefault(title, "本文"), kp),
			Answer:        kp,
			SourceContext: kp,
		})
	}
	return pairs, nil
}

// isASCII reports whether s contains only ASCII characters.
func isASCII(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] > 127 {
			return false
		}
	}
	return true
}
