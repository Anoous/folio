package worker

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"regexp"
	"strings"
	"time"

	"github.com/hibiken/asynq"

	"folio-server/internal/client"
	"folio-server/internal/domain"
	"folio-server/internal/pipeline"
	"folio-server/internal/repository"
)

// scraper abstracts the reader client for testing.
type scraper interface {
	Scrape(ctx context.Context, url string) (*client.ScrapeResponse, error)
}

type CrawlHandler struct {
	readerClient scraper
	jinaClient   scraper
	articleRepo  interface {
		ArticleGetter
		ArticleCrawlUpdater
		ArticleAIUpdater
		ArticleStatusUpdater
	}
	taskRepo interface {
		TaskCrawlTracker
		TaskAIFinisher
		TaskFailer
	}
	asynqClient  Enqueuer
	enableImage  bool
	cacheRepo    ContentCacheReader
	tagRepo      TagCreator
	categoryRepo CategoryFinder
}

func NewCrawlHandler(
	readerClient *client.ReaderClient,
	jinaClient *client.JinaClient,
	articleRepo *repository.ArticleRepo,
	taskRepo *repository.TaskRepo,
	asynqClient *asynq.Client,
	enableImage bool,
	cacheRepo *repository.ContentCacheRepo,
	tagRepo *repository.TagRepo,
	categoryRepo *repository.CategoryRepo,
) *CrawlHandler {
	return &CrawlHandler{
		readerClient: readerClient,
		jinaClient:   jinaClient,
		articleRepo:  articleRepo,
		taskRepo:     taskRepo,
		asynqClient:  asynqClient,
		enableImage:  enableImage,
		cacheRepo:    cacheRepo,
		tagRepo:      tagRepo,
		categoryRepo: categoryRepo,
	}
}

func (h *CrawlHandler) ProcessTask(ctx context.Context, t *asynq.Task) error {
	var p CrawlPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("unmarshal crawl payload: %w", err)
	}

	start := time.Now()

	// Load article once for pre-crawl checks
	preCheckArticle, preCheckErr := h.articleRepo.GetByID(ctx, p.ArticleID)

	// If article has highlights AND already has server-extracted content, skip Reader and go to AI.
	// If article has highlights but NO content, proceed with Reader crawl normally.
	if preCheckErr == nil && preCheckArticle != nil && preCheckArticle.HighlightCount > 0 {
		if preCheckArticle.MarkdownContent != nil && *preCheckArticle.MarkdownContent != "" {
			slog.Info("crawl skipped: article has highlights and content, routing to AI",
				"article_id", p.ArticleID,
				"highlight_count", preCheckArticle.HighlightCount,
			)
			return h.aiHandoff().enqueue(ctx, crawlAIHandoffRequest{
				payload:             p,
				title:               derefOrEmpty(preCheckArticle.Title),
				markdown:            *preCheckArticle.MarkdownContent,
				source:              derefOrDefault(preCheckArticle.SiteName, "web"),
				author:              derefOrEmpty(preCheckArticle.Author),
				finishBeforeEnqueue: true,
				setFinishedLabel:    "highlights: set crawl finished",
				enqueueLabel:        "enqueue ai task (highlights)",
			})
		}
		slog.Info("crawl proceeding: article has highlights but no content",
			"article_id", p.ArticleID,
			"highlight_count", preCheckArticle.HighlightCount,
		)
	}

	// Skip crawl for screenshot/voice — they have content, just need AI
	if preCheckErr == nil && preCheckArticle != nil &&
		(preCheckArticle.SourceType == domain.SourceScreenshot || preCheckArticle.SourceType == domain.SourceVoice) {
		if preCheckArticle.MarkdownContent != nil && *preCheckArticle.MarkdownContent != "" {
			slog.Info("crawl skipped: screenshot/voice article has content, routing to AI",
				"article_id", p.ArticleID,
				"source_type", preCheckArticle.SourceType,
			)
			return h.aiHandoff().enqueue(ctx, crawlAIHandoffRequest{
				payload:             p,
				title:               derefOrEmpty(preCheckArticle.Title),
				markdown:            *preCheckArticle.MarkdownContent,
				source:              string(preCheckArticle.SourceType),
				author:              derefOrEmpty(preCheckArticle.Author),
				finishBeforeEnqueue: true,
				setFinishedLabel:    "screenshot/voice: set crawl finished",
				enqueueLabel:        "enqueue ai task (screenshot/voice)",
			})
		}
		// No content — mark as ready (e.g. image-only screenshot with no extracted text)
		slog.Info("crawl skipped: screenshot/voice article has no content, marking ready",
			"article_id", p.ArticleID,
			"source_type", preCheckArticle.SourceType,
		)
		return h.articleRepo.UpdateStatus(ctx, p.ArticleID, domain.ArticleStatusReady)
	}

	// Mark crawl started
	if err := h.taskRepo.SetCrawlStarted(ctx, p.TaskID); err != nil {
		return fmt.Errorf("set crawl started: %w", err)
	}

	// Set article status to processing
	if err := h.articleRepo.UpdateStatus(ctx, p.ArticleID, domain.ArticleStatusProcessing); err != nil {
		return fmt.Errorf("update article status to processing: %w", err)
	}

	// --- Optimization 1: Check content cache ---
	if cached, err := h.cacheRepo.GetByURL(ctx, p.URL); err == nil && cached != nil {
		handled, err := h.cacheHandler().handle(ctx, p, cached, start)
		if handled || err != nil {
			return err
		}
	}

	slog.Debug("cache miss, checking client content", "article_id", p.ArticleID)

	// --- Optimization 2: Check client-extracted content ---
	article, getErr := h.articleRepo.GetByID(ctx, p.ArticleID)
	if getErr == nil && article != nil && article.MarkdownContent != nil && *article.MarkdownContent != "" {
		slog.Info("crawl task using client-provided content, skipping Reader",
			"article_id", p.ArticleID,
			"duration_ms", time.Since(start).Milliseconds(),
		)
		return h.aiHandoff().enqueue(ctx, crawlAIHandoffRequest{
			payload:             p,
			title:               derefOrEmpty(article.Title),
			markdown:            *article.MarkdownContent,
			source:              derefOrDefault(article.SiteName, "web"),
			author:              derefOrEmpty(article.Author),
			finishBeforeEnqueue: false,
			setFinishedLabel:    "client content: set crawl finished",
			enqueueLabel:        "enqueue ai task (client content)",
		})
	}

	// --- Normal path: call Reader, fallback to Jina ---
	slog.Debug("no client content, calling reader", "article_id", p.ArticleID)
	currentStage := pipeline.StageCrawlReader
	currentProvider := pipeline.ProviderReader
	logPipelineStarted(currentStage, currentProvider, p.TaskID, p.ArticleID, p.UserID, p.URL)
	result, err := h.readerClient.Scrape(ctx, p.URL)
	if err != nil {
		readerErr := ensurePipelineErr(currentStage, currentProvider, true, "reader scrape failed", err)
		logPipelineFallbackStarted(currentStage, currentProvider, p.TaskID, p.ArticleID, p.UserID, p.URL, pipeline.ProviderJina, readerErr)

		currentStage = pipeline.StageCrawlJina
		currentProvider = pipeline.ProviderJina
		result, err = h.jinaClient.Scrape(ctx, p.URL)
		if err != nil {
			rawFallbackErr := err
			failureErr := ensurePipelineErr(currentStage, currentProvider, true, "jina scrape failed", err)
			if _, ok := clientErr(readerErr); ok {
				if _, fallbackOK := clientErr(rawFallbackErr); !fallbackOK {
					failureErr = readerErr
					currentStage = pipeline.StageCrawlReader
					currentProvider = pipeline.ProviderReader
				}
			}
			logPipelineFailed(currentStage, currentProvider, p.TaskID, p.ArticleID, p.UserID, p.URL, time.Since(start), failureErr)
			h.taskRepo.SetFailed(ctx, p.TaskID, buildTaskFailure(failureErr, time.Since(start)))
			h.articleRepo.SetError(ctx, p.ArticleID, failureErr.Error())
			return nil
		}
		logPipelineFallbackSucceeded(currentStage, currentProvider, p.TaskID, p.ArticleID, p.UserID, p.URL, pipeline.ProviderReader, time.Since(start))
	}

	// Post-process Weibo content
	title := result.Metadata.Title
	markdown := result.Markdown
	if isWeiboURL(p.URL) {
		markdown = cleanWeiboMarkdown(markdown)
		if isGenericWeiboTitle(title) {
			if extracted := extractTitleFromMarkdown(markdown); extracted != "" {
				title = extracted
			}
		}
	}

	if err := h.articleRepo.UpdateCrawlResult(ctx, p.ArticleID, repository.CrawlResult{
		Title:      title,
		Author:     result.Metadata.Author,
		SiteName:   result.Metadata.SiteName,
		Markdown:   markdown,
		CoverImage: result.Metadata.OGImage,
		Language:   result.Metadata.Language,
		FaviconURL: result.Metadata.Favicon,
	}); err != nil {
		failureErr := ensurePipelineErr(currentStage, currentProvider, true, "persist crawl result", err)
		logPipelineFailed(currentStage, currentProvider, p.TaskID, p.ArticleID, p.UserID, p.URL, time.Since(start), failureErr)
		h.taskRepo.SetFailed(ctx, p.TaskID, buildTaskFailure(failureErr, time.Since(start)))
		return fmt.Errorf("update crawl result: %w", err)
	}

	source := result.Metadata.SiteName
	if source == "" {
		source = "web"
	}
	if err := h.aiHandoff().enqueue(ctx, crawlAIHandoffRequest{
		payload:             p,
		title:               title,
		markdown:            markdown,
		source:              source,
		author:              result.Metadata.Author,
		finishBeforeEnqueue: false,
		setFinishedLabel:    "set crawl finished",
		enqueueLabel:        "enqueue ai task",
	}); err != nil {
		return err
	}

	logPipelineSucceeded(currentStage, currentProvider, p.TaskID, p.ArticleID, p.UserID, p.URL, time.Since(start))

	// Enqueue image upload task (extract image URLs from markdown)
	imageURLs := extractImageURLs(result.Markdown)
	if h.enableImage && len(imageURLs) > 0 {
		imgTask := NewImageUploadTask(p.ArticleID, imageURLs)
		h.asynqClient.EnqueueContext(ctx, imgTask) // Non-blocking, errors OK
	}

	return nil
}

// --- Weibo content cleaning ---

// isWeiboURL checks if the URL belongs to Weibo.
func isWeiboURL(url string) bool {
	return strings.Contains(url, "weibo.com") || strings.Contains(url, "weibo.cn")
}

// Generic useless titles from Weibo HTML <title>.
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
// Falls back to the first 80 characters of content if nothing suitable found.
func extractTitleFromMarkdown(md string) string {
	lines := strings.Split(md, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		// Skip lines that are only links or images
		if strings.HasPrefix(line, "![") || strings.HasPrefix(line, "[![") {
			continue
		}
		// Strip markdown heading markers
		cleaned := strings.TrimLeft(line, "# ")
		// Skip lines that are only URLs
		if strings.HasPrefix(cleaned, "http://") || strings.HasPrefix(cleaned, "https://") || strings.HasPrefix(cleaned, "//") {
			continue
		}
		// Remove inline markdown links but keep text: [text](url) → text
		cleaned = mdLinkTextRegex.ReplaceAllString(cleaned, "$1")
		cleaned = strings.TrimSpace(cleaned)
		if cleaned == "" {
			continue
		}
		// Truncate to reasonable title length
		if len([]rune(cleaned)) > 80 {
			runes := []rune(cleaned)
			cleaned = string(runes[:80]) + "…"
		}
		return cleaned
	}
	return ""
}

// Regex patterns for Weibo markdown cleaning.
var (
	// Matches markdown links to weibo search/hashtag pages: [#topic#](//s.weibo.com/...)
	weiboHashtagLinkRegex = regexp.MustCompile(`\[#([^#\]]+)#\]\([^)]*(?:s\.weibo\.com|weibo\.com/p/)[^)]*\)`)
	// Matches markdown links to weibo user profiles: [@user](//weibo.com/u/...)
	weiboMentionLinkRegex = regexp.MustCompile(`\[@([^\]]+)\]\([^)]*weibo\.com[^)]*\)`)
	// Matches bare weibo URLs (protocol-relative or absolute)
	weiboBareLinkRegex = regexp.MustCompile(`(?:https?:)?//[^\s)]*(?:s\.weibo\.com|weibo\.com/p/)[^\s)]*`)
	// Extract link text from markdown links: [text](url)
	mdLinkTextRegex = regexp.MustCompile(`\[([^\]]*)\]\([^)]+\)`)
)

// cleanWeiboMarkdown removes Weibo-specific noise from markdown content.
func cleanWeiboMarkdown(md string) string {
	// Replace hashtag links with plain hashtag text: [#topic#](url) → #topic#
	result := weiboHashtagLinkRegex.ReplaceAllString(md, "#$1#")
	// Replace @mention links with plain @mention: [@user](url) → @user
	result = weiboMentionLinkRegex.ReplaceAllString(result, "@$1")
	// Remove remaining bare weibo search/hashtag URLs
	result = weiboBareLinkRegex.ReplaceAllString(result, "")
	// Clean up extra whitespace from removals
	result = strings.ReplaceAll(result, "  ", " ")
	return strings.TrimSpace(result)
}

var imageURLRegex = regexp.MustCompile(`!\[.*?\]\((https?://[^\s)]+)\)`)

func extractImageURLs(markdown string) []string {
	matches := imageURLRegex.FindAllStringSubmatch(markdown, -1)
	urls := make([]string, 0, len(matches))
	for _, m := range matches {
		if len(m) > 1 {
			urls = append(urls, m[1])
		}
	}
	return urls
}
