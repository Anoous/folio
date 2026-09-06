package worker

import (
	"regexp"
	"strings"

	"folio-server/internal/client"
)

type crawlContentPostprocessor struct{}

type processedCrawlContent struct {
	title    string
	markdown string
}

func (p crawlContentPostprocessor) apply(url string, result *client.ScrapeResponse) processedCrawlContent {
	title := result.Metadata.Title
	markdown := result.Markdown
	if isWeiboURL(url) {
		markdown = cleanWeiboMarkdown(markdown)
		if isGenericWeiboTitle(title) {
			if extracted := extractTitleFromMarkdown(markdown); extracted != "" {
				title = extracted
			}
		}
	}
	return processedCrawlContent{
		title:    title,
		markdown: markdown,
	}
}

// isWeiboURL checks if the URL belongs to Weibo.
func isWeiboURL(url string) bool {
	return strings.Contains(url, "weibo.com") || strings.Contains(url, "weibo.cn")
}

var weiboGenericTitles = []string{
	"微博正文",
	"Sina Visitor System",
	"微博",
}

// isGenericWeiboTitle returns true if the title is a known useless Weibo default.
func isGenericWeiboTitle(title string) bool {
	t := strings.TrimSpace(title)
	for _, g := range weiboGenericTitles {
		if strings.Contains(t, g) {
			return true
		}
	}
	return t == ""
}

// extractTitleFromMarkdown extracts the first non-empty, non-link line from markdown as a title.
func extractTitleFromMarkdown(md string) string {
	lines := strings.Split(md, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, "![") || strings.HasPrefix(line, "[![") {
			continue
		}
		cleaned := strings.TrimLeft(line, "# ")
		if strings.HasPrefix(cleaned, "http://") || strings.HasPrefix(cleaned, "https://") || strings.HasPrefix(cleaned, "//") {
			continue
		}
		cleaned = mdLinkTextRegex.ReplaceAllString(cleaned, "$1")
		cleaned = strings.TrimSpace(cleaned)
		if cleaned == "" {
			continue
		}
		if len([]rune(cleaned)) > 80 {
			runes := []rune(cleaned)
			cleaned = string(runes[:80]) + "…"
		}
		return cleaned
	}
	return ""
}

var (
	weiboHashtagLinkRegex = regexp.MustCompile(`\[#([^#\]]+)#\]\([^)]*(?:s\.weibo\.com|weibo\.com/p/)[^)]*\)`)
	weiboMentionLinkRegex = regexp.MustCompile(`\[@([^\]]+)\]\([^)]*weibo\.com[^)]*\)`)
	weiboBareLinkRegex    = regexp.MustCompile(`(?:https?:)?//[^\s)]*(?:s\.weibo\.com|weibo\.com/p/)[^\s)]*`)
	mdLinkTextRegex       = regexp.MustCompile(`\[([^\]]*)\]\([^)]+\)`)
)

// cleanWeiboMarkdown removes Weibo-specific noise from markdown content.
func cleanWeiboMarkdown(md string) string {
	result := weiboHashtagLinkRegex.ReplaceAllString(md, "#$1#")
	result = weiboMentionLinkRegex.ReplaceAllString(result, "@$1")
	result = weiboBareLinkRegex.ReplaceAllString(result, "")
	result = strings.ReplaceAll(result, "  ", " ")
	return strings.TrimSpace(result)
}
