package worker

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/hibiken/asynq"

	"folio-server/internal/client"
	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

func strPtr(s string) *string { return &s }

// TestCrawlFallbackDecision verifies the decision logic used in the crawl handler
// when the scrape fails: if the article has client-provided markdown content,
// the handler should fall back to using it for AI processing instead of failing.
func TestCrawlFallbackDecision_HasClientContent(t *testing.T) {
	article := &domain.Article{
		ID:              "article-1",
		Title:           strPtr("Client Title"),
		Author:          strPtr("Client Author"),
		SiteName:        strPtr("Client Site"),
		MarkdownContent: strPtr("# Client Content\n\nSome text here."),
	}

	// Simulate the fallback check from ProcessTask
	hasClientContent := article != nil &&
		article.MarkdownContent != nil &&
		*article.MarkdownContent != ""

	if !hasClientContent {
		t.Fatal("expected article with MarkdownContent to trigger fallback")
	}

	// Verify the AI task payload would be built correctly
	title := ""
	if article.Title != nil {
		title = *article.Title
	}
	source := ""
	if article.SiteName != nil {
		source = *article.SiteName
	}
	if source == "" {
		source = "web"
	}
	author := ""
	if article.Author != nil {
		author = *article.Author
	}

	if title != "Client Title" {
		t.Errorf("title = %q, want %q", title, "Client Title")
	}
	if source != "Client Site" {
		t.Errorf("source = %q, want %q", source, "Client Site")
	}
	if author != "Client Author" {
		t.Errorf("author = %q, want %q", author, "Client Author")
	}
}

func TestCrawlFallbackDecision_NoClientContent(t *testing.T) {
	article := &domain.Article{
		ID: "article-1",
		// No MarkdownContent, Title, Author, SiteName
	}

	hasClientContent := article != nil &&
		article.MarkdownContent != nil &&
		*article.MarkdownContent != ""

	if hasClientContent {
		t.Fatal("expected article without MarkdownContent to NOT trigger fallback")
	}
}

func TestCrawlFallbackDecision_EmptyMarkdownContent(t *testing.T) {
	article := &domain.Article{
		ID:              "article-1",
		MarkdownContent: strPtr(""),
	}

	hasClientContent := article != nil &&
		article.MarkdownContent != nil &&
		*article.MarkdownContent != ""

	if hasClientContent {
		t.Fatal("expected article with empty MarkdownContent to NOT trigger fallback")
	}
}

func TestCrawlFallbackDecision_NilArticle(t *testing.T) {
	var article *domain.Article

	hasClientContent := article != nil &&
		article.MarkdownContent != nil &&
		*article.MarkdownContent != ""

	if hasClientContent {
		t.Fatal("expected nil article to NOT trigger fallback")
	}
}

func TestCrawlFallbackDecision_DefaultSourceWeb(t *testing.T) {
	// When SiteName is nil, source should default to "web"
	article := &domain.Article{
		ID:              "article-1",
		MarkdownContent: strPtr("# Content"),
		// SiteName is nil
	}

	source := ""
	if article.SiteName != nil {
		source = *article.SiteName
	}
	if source == "" {
		source = "web"
	}

	if source != "web" {
		t.Errorf("source = %q, want %q", source, "web")
	}
}

func TestCrawlFallbackDecision_NilOptionalFields(t *testing.T) {
	// Article with only MarkdownContent, all other optional fields nil
	article := &domain.Article{
		ID:              "article-1",
		MarkdownContent: strPtr("# Markdown only"),
	}

	hasClientContent := article != nil &&
		article.MarkdownContent != nil &&
		*article.MarkdownContent != ""

	if !hasClientContent {
		t.Fatal("expected fallback to trigger with MarkdownContent present")
	}

	title := ""
	if article.Title != nil {
		title = *article.Title
	}
	source := ""
	if article.SiteName != nil {
		source = *article.SiteName
	}
	if source == "" {
		source = "web"
	}
	author := ""
	if article.Author != nil {
		author = *article.Author
	}

	if title != "" {
		t.Errorf("title = %q, want empty", title)
	}
	if source != "web" {
		t.Errorf("source = %q, want %q", source, "web")
	}
	if author != "" {
		t.Errorf("author = %q, want empty", author)
	}
}

func TestNewAIProcessTask_PayloadContainsCorrectFields(t *testing.T) {
	task := NewAIProcessTask("art-1", "task-1", "user-1", "Title", "# Markdown", "blog", "Author")

	if task.Type() != TypeAIProcess {
		t.Errorf("task type = %q, want %q", task.Type(), TypeAIProcess)
	}

	var payload AIProcessPayload
	if err := json.Unmarshal(task.Payload(), &payload); err != nil {
		t.Fatalf("failed to unmarshal payload: %v", err)
	}

	if payload.ArticleID != "art-1" {
		t.Errorf("ArticleID = %q, want %q", payload.ArticleID, "art-1")
	}
	if payload.TaskID != "task-1" {
		t.Errorf("TaskID = %q, want %q", payload.TaskID, "task-1")
	}
	if payload.UserID != "user-1" {
		t.Errorf("UserID = %q, want %q", payload.UserID, "user-1")
	}
	if payload.Title != "Title" {
		t.Errorf("Title = %q, want %q", payload.Title, "Title")
	}
	if payload.Markdown != "# Markdown" {
		t.Errorf("Markdown = %q, want %q", payload.Markdown, "# Markdown")
	}
	if payload.Source != "blog" {
		t.Errorf("Source = %q, want %q", payload.Source, "blog")
	}
	if payload.Author != "Author" {
		t.Errorf("Author = %q, want %q", payload.Author, "Author")
	}
}

func TestNewCrawlTask_PayloadRoundTrip(t *testing.T) {
	task := NewCrawlTask("art-1", "task-1", "https://example.com", "user-1")

	if task.Type() != TypeCrawlArticle {
		t.Errorf("task type = %q, want %q", task.Type(), TypeCrawlArticle)
	}

	var payload CrawlPayload
	if err := json.Unmarshal(task.Payload(), &payload); err != nil {
		t.Fatalf("failed to unmarshal payload: %v", err)
	}

	if payload.ArticleID != "art-1" {
		t.Errorf("ArticleID = %q, want %q", payload.ArticleID, "art-1")
	}
	if payload.URL != "https://example.com" {
		t.Errorf("URL = %q, want %q", payload.URL, "https://example.com")
	}
}

// --- Weibo content cleaning tests ---

func TestIsWeiboURL(t *testing.T) {
	tests := []struct {
		url  string
		want bool
	}{
		{"https://weibo.com/1234567890/post123", true},
		{"https://m.weibo.cn/detail/123456", true},
		{"https://s.weibo.com/weibo?q=test", true},
		{"https://example.com/article", false},
		{"https://go.dev/blog/post", false},
	}
	for _, tt := range tests {
		if got := isWeiboURL(tt.url); got != tt.want {
			t.Errorf("isWeiboURL(%q) = %v, want %v", tt.url, got, tt.want)
		}
	}
}

func TestIsGenericWeiboTitle(t *testing.T) {
	tests := []struct {
		title string
		want  bool
	}{
		{"微博正文 - 微博", true},
		{"微博正文", true},
		{"Sina Visitor System", true},
		{"微博", true},
		{"", true},
		{"   ", true},
		{"张三的技术分享", false},
		{"Go语言最佳实践", false},
	}
	for _, tt := range tests {
		if got := isGenericWeiboTitle(tt.title); got != tt.want {
			t.Errorf("isGenericWeiboTitle(%q) = %v, want %v", tt.title, got, tt.want)
		}
	}
}

func TestExtractTitleFromMarkdown(t *testing.T) {
	tests := []struct {
		name string
		md   string
		want string
	}{
		{
			name: "first text line",
			md:   "这是一条微博内容，分享技术心得\n\n更多详情请看下文",
			want: "这是一条微博内容，分享技术心得",
		},
		{
			name: "skip image lines",
			md:   "![photo](https://img.weibo.com/pic.jpg)\n这是正文内容",
			want: "这是正文内容",
		},
		{
			name: "strip heading markers",
			md:   "# 标题文本\n\n内容",
			want: "标题文本",
		},
		{
			name: "skip bare URLs",
			md:   "https://example.com\n实际内容在这里",
			want: "实际内容在这里",
		},
		{
			name: "extract text from markdown links",
			md:   "[#Go语言#](//s.weibo.com/weibo?q=Go) 今天分享一个技巧",
			want: "#Go语言# 今天分享一个技巧",
		},
		{
			name: "empty markdown",
			md:   "",
			want: "",
		},
		{
			name: "only images",
			md:   "![a](https://img.com/a.jpg)\n![b](https://img.com/b.jpg)",
			want: "",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := extractTitleFromMarkdown(tt.md)
			if got != tt.want {
				t.Errorf("extractTitleFromMarkdown() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestCleanWeiboMarkdown(t *testing.T) {
	tests := []struct {
		name string
		md   string
		want string
	}{
		{
			name: "hashtag links to plain text",
			md:   `[#Go语言#](//s.weibo.com/weibo?q=%23Go%E8%AF%AD%E8%A8%80%23) 今天学了新知识`,
			want: `#Go语言# 今天学了新知识`,
		},
		{
			name: "mention links to plain text",
			md:   `[@张三](//weibo.com/u/1234567) 你怎么看？`,
			want: `@张三 你怎么看？`,
		},
		{
			name: "bare weibo search URLs removed",
			md:   `查看更多 //s.weibo.com/weibo?q=test 相关内容`,
			want: `查看更多 相关内容`,
		},
		{
			name: "combined noise",
			md:   "[#技术#](//s.weibo.com/weibo?q=%23%E6%8A%80%E6%9C%AF%23) [@李四](//weibo.com/u/999) 分享内容 //s.weibo.com/weibo?q=other",
			want: "#技术# @李四 分享内容",
		},
		{
			name: "no weibo noise passes through",
			md:   "# Normal Article\n\nSome content [link](https://example.com).",
			want: "# Normal Article\n\nSome content [link](https://example.com).",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := cleanWeiboMarkdown(tt.md)
			if got != tt.want {
				t.Errorf("cleanWeiboMarkdown() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestProcessTask_WeiboURL_CleansContentAndTitle(t *testing.T) {
	weiboMarkdown := "[#Go语言#](//s.weibo.com/weibo?q=%23Go%23) 今天分享一个Go的最佳实践 [@技术博主](//weibo.com/u/123)"
	scrapeResp := &client.ScrapeResponse{
		Markdown: weiboMarkdown,
		Metadata: client.ReaderMetadata{
			Title:    "微博正文 - 微博",
			SiteName: "微博",
		},
	}

	mockReader := &mockScraper{
		scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
			return scrapeResp, nil
		},
	}
	mockArtRepo := &mockCrawlArticleRepo{}
	mockTaskRepo := &mockCrawlTaskRepo{}
	mockEnq := &mockCrawlEnqueuer{}

	h := newTestCrawlHandler(mockReader, mockArtRepo, mockTaskRepo, mockEnq, false)

	task := newCrawlAsynqTask("art-1", "task-1", "https://weibo.com/1234567890/post123", "user-1")
	err := h.ProcessTask(context.Background(), task)
	if err != nil {
		t.Fatalf("ProcessTask returned error: %v", err)
	}

	// Verify title was extracted from content (not the generic "微博正文 - 微博")
	if len(mockArtRepo.updateCrawlCalls) != 1 {
		t.Fatalf("UpdateCrawlResult calls = %d, want 1", len(mockArtRepo.updateCrawlCalls))
	}
	cr := mockArtRepo.updateCrawlCalls[0]
	if cr.Title == "微博正文 - 微博" {
		t.Errorf("Title should not be the generic Weibo title, got %q", cr.Title)
	}
	if cr.Title == "" {
		t.Error("Title should not be empty after extraction")
	}

	// Verify markdown was cleaned (no weibo search links)
	if strings.Contains(cr.Markdown, "s.weibo.com") {
		t.Errorf("Markdown should not contain weibo search URLs, got %q", cr.Markdown)
	}
	if strings.Contains(cr.Markdown, "weibo.com/u/") {
		t.Errorf("Markdown should not contain weibo user profile URLs, got %q", cr.Markdown)
	}

	// Verify AI task uses cleaned content
	if len(mockEnq.enqueuedTasks) < 1 {
		t.Fatal("AI task should be enqueued")
	}
	var aiPayload AIProcessPayload
	json.Unmarshal(mockEnq.enqueuedTasks[0].Payload(), &aiPayload)
	if strings.Contains(aiPayload.Markdown, "s.weibo.com") {
		t.Errorf("AI payload markdown should not contain weibo URLs")
	}
	if aiPayload.Title == "微博正文 - 微博" {
		t.Errorf("AI payload title should not be generic Weibo title")
	}
}

// --- Mock implementations for CrawlHandler integration tests ---

type mockScraper struct {
	scrapeFn func(ctx context.Context, url string) (*client.ScrapeResponse, error)
}

func (m *mockScraper) Scrape(ctx context.Context, url string) (*client.ScrapeResponse, error) {
	if m.scrapeFn != nil {
		return m.scrapeFn(ctx, url)
	}
	return nil, errors.New("not implemented")
}

type mockCrawlArticleRepo struct {
	getByIDFn           func(ctx context.Context, id string) (*domain.Article, error)
	updateCrawlFn       func(ctx context.Context, id string, cr repository.CrawlResult) error
	setErrorFn          func(ctx context.Context, id string, errMsg string) error
	updateCrawlCalls    []repository.CrawlResult
	updateAIResultCalls []repository.AIResult
	setErrorCalls       []struct{ ID, ErrMsg string }
	updateStatusCalls   []struct{ ID string; Status domain.ArticleStatus }
}

func (m *mockCrawlArticleRepo) GetByID(ctx context.Context, id string) (*domain.Article, error) {
	if m.getByIDFn != nil {
		return m.getByIDFn(ctx, id)
	}
	return nil, nil
}

func (m *mockCrawlArticleRepo) UpdateCrawlResult(ctx context.Context, id string, cr repository.CrawlResult) error {
	m.updateCrawlCalls = append(m.updateCrawlCalls, cr)
	if m.updateCrawlFn != nil {
		return m.updateCrawlFn(ctx, id, cr)
	}
	return nil
}

func (m *mockCrawlArticleRepo) UpdateAIResult(ctx context.Context, id string, ai repository.AIResult) error {
	m.updateAIResultCalls = append(m.updateAIResultCalls, ai)
	return nil
}

func (m *mockCrawlArticleRepo) UpdateStatus(ctx context.Context, id string, status domain.ArticleStatus) error {
	m.updateStatusCalls = append(m.updateStatusCalls, struct{ ID string; Status domain.ArticleStatus }{id, status})
	return nil
}

func (m *mockCrawlArticleRepo) SetError(ctx context.Context, id string, errMsg string) error {
	m.setErrorCalls = append(m.setErrorCalls, struct{ ID, ErrMsg string }{id, errMsg})
	if m.setErrorFn != nil {
		return m.setErrorFn(ctx, id, errMsg)
	}
	return nil
}

type mockCrawlTaskRepo struct {
	setCrawlStartedCalls  []string
	setCrawlFinishedCalls []string
	setFailedCalls        []struct{ ID, ErrMsg string }
	setCrawlStartedFn     func(ctx context.Context, id string) error
}

func (m *mockCrawlTaskRepo) SetCrawlStarted(ctx context.Context, id string) error {
	m.setCrawlStartedCalls = append(m.setCrawlStartedCalls, id)
	if m.setCrawlStartedFn != nil {
		return m.setCrawlStartedFn(ctx, id)
	}
	return nil
}

func (m *mockCrawlTaskRepo) SetCrawlFinished(ctx context.Context, id string) error {
	m.setCrawlFinishedCalls = append(m.setCrawlFinishedCalls, id)
	return nil
}

func (m *mockCrawlTaskRepo) SetFailed(ctx context.Context, id string, errMsg string) error {
	m.setFailedCalls = append(m.setFailedCalls, struct{ ID, ErrMsg string }{id, errMsg})
	return nil
}

type mockCrawlEnqueuer struct {
	enqueuedTasks []*asynq.Task
}

func (m *mockCrawlEnqueuer) EnqueueContext(ctx context.Context, task *asynq.Task, opts ...asynq.Option) (*asynq.TaskInfo, error) {
	m.enqueuedTasks = append(m.enqueuedTasks, task)
	return &asynq.TaskInfo{}, nil
}

type mockContentCacheRepo struct {
	getByURLFn func(ctx context.Context, url string) (*domain.ContentCache, error)
	upsertFn   func(ctx context.Context, c *domain.ContentCache) error
}

func (m *mockContentCacheRepo) GetByURL(ctx context.Context, url string) (*domain.ContentCache, error) {
	if m.getByURLFn != nil {
		return m.getByURLFn(ctx, url)
	}
	return nil, nil
}

func (m *mockContentCacheRepo) Upsert(ctx context.Context, c *domain.ContentCache) error {
	if m.upsertFn != nil {
		return m.upsertFn(ctx, c)
	}
	return nil
}

type mockCrawlTagRepo struct {
	createFn func(ctx context.Context, userID, name string, isAI bool) (*domain.Tag, error)
	attachFn func(ctx context.Context, articleID, tagID string) error
}

func (m *mockCrawlTagRepo) Create(ctx context.Context, userID, name string, isAI bool) (*domain.Tag, error) {
	if m.createFn != nil {
		return m.createFn(ctx, userID, name, isAI)
	}
	return &domain.Tag{ID: "tag-" + name, Name: name}, nil
}

func (m *mockCrawlTagRepo) AttachToArticle(ctx context.Context, articleID, tagID string) error {
	if m.attachFn != nil {
		return m.attachFn(ctx, articleID, tagID)
	}
	return nil
}

// newTestCrawlHandler creates a CrawlHandler with mock dependencies for testing.
func newTestCrawlHandler(
	scraper *mockScraper,
	articleRepo *mockCrawlArticleRepo,
	taskRepo *mockCrawlTaskRepo,
	enqueuer *mockCrawlEnqueuer,
	enableImage bool,
) *CrawlHandler {
	return &CrawlHandler{
		readerClient: scraper,
		articleRepo:  articleRepo,
		taskRepo:     taskRepo,
		asynqClient:  enqueuer,
		enableImage:  enableImage,
		cacheRepo:    &mockContentCacheRepo{},
		tagRepo:      &mockCrawlTagRepo{},
	}
}

// newCrawlAsynqTask creates an asynq.Task with a CrawlPayload for testing.
func newCrawlAsynqTask(articleID, taskID, url, userID string) *asynq.Task {
	payload, _ := json.Marshal(CrawlPayload{
		ArticleID: articleID,
		TaskID:    taskID,
		URL:       url,
		UserID:    userID,
	})
	return asynq.NewTask(TypeCrawlArticle, payload)
}

// --- ProcessTask integration tests ---

func TestProcessTask_ScrapeSuccess_NormalFlow(t *testing.T) {
	scrapeResp := &client.ScrapeResponse{
		Markdown: "# Scraped Content\n\nBody text here.",
		Metadata: client.ReaderMetadata{
			Title:    "Scraped Title",
			Author:   "Scraped Author",
			SiteName: "Scraped Site",
			OGImage:  "https://example.com/image.jpg",
			Language: "en",
			Favicon:  "https://example.com/favicon.ico",
		},
	}

	mockReader := &mockScraper{
		scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
			return scrapeResp, nil
		},
	}
	mockArtRepo := &mockCrawlArticleRepo{}
	mockTaskRepo := &mockCrawlTaskRepo{}
	mockEnq := &mockCrawlEnqueuer{}

	h := newTestCrawlHandler(mockReader, mockArtRepo, mockTaskRepo, mockEnq, false)

	task := newCrawlAsynqTask("art-1", "task-1", "https://example.com/article", "user-1")
	err := h.ProcessTask(context.Background(), task)
	if err != nil {
		t.Fatalf("ProcessTask returned error: %v", err)
	}

	// Verify crawl started was called
	if len(mockTaskRepo.setCrawlStartedCalls) != 1 || mockTaskRepo.setCrawlStartedCalls[0] != "task-1" {
		t.Errorf("SetCrawlStarted calls = %v, want [task-1]", mockTaskRepo.setCrawlStartedCalls)
	}

	// Verify article was updated with crawl results
	if len(mockArtRepo.updateCrawlCalls) != 1 {
		t.Fatalf("UpdateCrawlResult calls = %d, want 1", len(mockArtRepo.updateCrawlCalls))
	}
	cr := mockArtRepo.updateCrawlCalls[0]
	if cr.Title != "Scraped Title" {
		t.Errorf("CrawlResult.Title = %q, want %q", cr.Title, "Scraped Title")
	}
	if cr.Author != "Scraped Author" {
		t.Errorf("CrawlResult.Author = %q, want %q", cr.Author, "Scraped Author")
	}
	if cr.Markdown != "# Scraped Content\n\nBody text here." {
		t.Errorf("CrawlResult.Markdown = %q, want scraped content", cr.Markdown)
	}

	// Verify crawl finished was called
	if len(mockTaskRepo.setCrawlFinishedCalls) != 1 || mockTaskRepo.setCrawlFinishedCalls[0] != "task-1" {
		t.Errorf("SetCrawlFinished calls = %v, want [task-1]", mockTaskRepo.setCrawlFinishedCalls)
	}

	// Verify AI task was enqueued
	if len(mockEnq.enqueuedTasks) != 1 {
		t.Fatalf("enqueued tasks = %d, want 1", len(mockEnq.enqueuedTasks))
	}
	aiTask := mockEnq.enqueuedTasks[0]
	if aiTask.Type() != TypeAIProcess {
		t.Errorf("enqueued task type = %q, want %q", aiTask.Type(), TypeAIProcess)
	}
	var aiPayload AIProcessPayload
	if err := json.Unmarshal(aiTask.Payload(), &aiPayload); err != nil {
		t.Fatalf("failed to unmarshal AI payload: %v", err)
	}
	if aiPayload.ArticleID != "art-1" {
		t.Errorf("AI payload ArticleID = %q, want %q", aiPayload.ArticleID, "art-1")
	}
	if aiPayload.Title != "Scraped Title" {
		t.Errorf("AI payload Title = %q, want %q", aiPayload.Title, "Scraped Title")
	}
	if aiPayload.Source != "Scraped Site" {
		t.Errorf("AI payload Source = %q, want %q", aiPayload.Source, "Scraped Site")
	}

	// Verify no failures
	if len(mockTaskRepo.setFailedCalls) != 0 {
		t.Errorf("SetFailed should not have been called, got %d calls", len(mockTaskRepo.setFailedCalls))
	}
	if len(mockArtRepo.setErrorCalls) != 0 {
		t.Errorf("SetError should not have been called, got %d calls", len(mockArtRepo.setErrorCalls))
	}
}

func TestProcessTask_ScrapeFail_ClientContentFallback(t *testing.T) {
	// Scrape fails, but article has client-provided content
	mockReader := &mockScraper{
		scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
			return nil, errors.New("scrape timeout")
		},
	}
	mockArtRepo := &mockCrawlArticleRepo{
		getByIDFn: func(ctx context.Context, id string) (*domain.Article, error) {
			return &domain.Article{
				ID:              "art-1",
				Title:           strPtr("Client Title"),
				Author:          strPtr("Client Author"),
				SiteName:        strPtr("Client Site"),
				MarkdownContent: strPtr("# Client Content\n\nFallback body."),
			}, nil
		},
	}
	mockTaskRepo := &mockCrawlTaskRepo{}
	mockEnq := &mockCrawlEnqueuer{}

	h := newTestCrawlHandler(mockReader, mockArtRepo, mockTaskRepo, mockEnq, false)

	task := newCrawlAsynqTask("art-1", "task-1", "https://example.com/article", "user-1")
	err := h.ProcessTask(context.Background(), task)
	if err != nil {
		t.Fatalf("ProcessTask should succeed with client fallback, got: %v", err)
	}

	// Verify crawl was marked finished (not failed)
	if len(mockTaskRepo.setCrawlFinishedCalls) != 1 {
		t.Errorf("SetCrawlFinished calls = %d, want 1", len(mockTaskRepo.setCrawlFinishedCalls))
	}
	if len(mockTaskRepo.setFailedCalls) != 0 {
		t.Errorf("SetFailed should not have been called in fallback path, got %d calls", len(mockTaskRepo.setFailedCalls))
	}

	// Verify AI task was enqueued with client content
	if len(mockEnq.enqueuedTasks) != 1 {
		t.Fatalf("enqueued tasks = %d, want 1", len(mockEnq.enqueuedTasks))
	}
	var aiPayload AIProcessPayload
	if err := json.Unmarshal(mockEnq.enqueuedTasks[0].Payload(), &aiPayload); err != nil {
		t.Fatalf("failed to unmarshal AI payload: %v", err)
	}
	if aiPayload.Title != "Client Title" {
		t.Errorf("AI payload Title = %q, want %q", aiPayload.Title, "Client Title")
	}
	if aiPayload.Markdown != "# Client Content\n\nFallback body." {
		t.Errorf("AI payload Markdown = %q, want client content", aiPayload.Markdown)
	}
	if aiPayload.Source != "Client Site" {
		t.Errorf("AI payload Source = %q, want %q", aiPayload.Source, "Client Site")
	}
	if aiPayload.Author != "Client Author" {
		t.Errorf("AI payload Author = %q, want %q", aiPayload.Author, "Client Author")
	}

	// Article should NOT have been marked as failed
	if len(mockArtRepo.setErrorCalls) != 0 {
		t.Errorf("SetError should not have been called in fallback path, got %d calls", len(mockArtRepo.setErrorCalls))
	}
}

func TestProcessTask_ScrapeFail_NoClientContent_Fails(t *testing.T) {
	// Scrape fails and article has no client-provided content
	mockReader := &mockScraper{
		scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
			return nil, errors.New("scrape failed: 404")
		},
	}
	mockArtRepo := &mockCrawlArticleRepo{
		getByIDFn: func(ctx context.Context, id string) (*domain.Article, error) {
			// Article exists but has no markdown content
			return &domain.Article{
				ID:     "art-1",
				UserID: "user-1",
			}, nil
		},
	}
	mockTaskRepo := &mockCrawlTaskRepo{}
	mockEnq := &mockCrawlEnqueuer{}

	h := newTestCrawlHandler(mockReader, mockArtRepo, mockTaskRepo, mockEnq, false)

	task := newCrawlAsynqTask("art-1", "task-1", "https://example.com/article", "user-1")
	err := h.ProcessTask(context.Background(), task)
	if err == nil {
		t.Fatal("ProcessTask should return error when scrape fails and no client content")
	}

	// Verify task was marked failed
	if len(mockTaskRepo.setFailedCalls) != 1 {
		t.Fatalf("SetFailed calls = %d, want 1", len(mockTaskRepo.setFailedCalls))
	}
	if mockTaskRepo.setFailedCalls[0].ID != "task-1" {
		t.Errorf("SetFailed task ID = %q, want %q", mockTaskRepo.setFailedCalls[0].ID, "task-1")
	}

	// Verify article was marked with error
	if len(mockArtRepo.setErrorCalls) != 1 {
		t.Fatalf("SetError calls = %d, want 1", len(mockArtRepo.setErrorCalls))
	}
	if mockArtRepo.setErrorCalls[0].ID != "art-1" {
		t.Errorf("SetError article ID = %q, want %q", mockArtRepo.setErrorCalls[0].ID, "art-1")
	}

	// Verify no AI task was enqueued
	if len(mockEnq.enqueuedTasks) != 0 {
		t.Errorf("no tasks should have been enqueued, got %d", len(mockEnq.enqueuedTasks))
	}

	// Verify crawl was NOT marked finished
	if len(mockTaskRepo.setCrawlFinishedCalls) != 0 {
		t.Errorf("SetCrawlFinished should not have been called, got %d calls", len(mockTaskRepo.setCrawlFinishedCalls))
	}
}

func TestProcessTask_ScrapeFail_GetByIDError_Fails(t *testing.T) {
	// Scrape fails and GetByID also returns an error
	mockReader := &mockScraper{
		scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
			return nil, errors.New("connection refused")
		},
	}
	mockArtRepo := &mockCrawlArticleRepo{
		getByIDFn: func(ctx context.Context, id string) (*domain.Article, error) {
			return nil, errors.New("database connection lost")
		},
	}
	mockTaskRepo := &mockCrawlTaskRepo{}
	mockEnq := &mockCrawlEnqueuer{}

	h := newTestCrawlHandler(mockReader, mockArtRepo, mockTaskRepo, mockEnq, false)

	task := newCrawlAsynqTask("art-1", "task-1", "https://example.com/article", "user-1")
	err := h.ProcessTask(context.Background(), task)
	if err == nil {
		t.Fatal("ProcessTask should return error when both scrape and GetByID fail")
	}

	// Verify task was marked failed (the original scrape error path)
	if len(mockTaskRepo.setFailedCalls) != 1 {
		t.Fatalf("SetFailed calls = %d, want 1", len(mockTaskRepo.setFailedCalls))
	}

	// Verify article was marked with error
	if len(mockArtRepo.setErrorCalls) != 1 {
		t.Fatalf("SetError calls = %d, want 1", len(mockArtRepo.setErrorCalls))
	}

	// No AI task should have been enqueued
	if len(mockEnq.enqueuedTasks) != 0 {
		t.Errorf("no tasks should have been enqueued, got %d", len(mockEnq.enqueuedTasks))
	}
}

func TestProcessTask_ScrapeFail_ArticleNotFound_Fails(t *testing.T) {
	// When scrape fails and GetByID returns (nil, nil) — article not found —
	// the code should fall through to the failure path since the fallback
	// condition (article != nil && article.MarkdownContent != nil && ...) is false.
	mockReader := &mockScraper{
		scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
			return nil, errors.New("scrape connection refused")
		},
	}
	mockArtRepo := &mockCrawlArticleRepo{
		getByIDFn: func(ctx context.Context, id string) (*domain.Article, error) {
			// Article not found: returns (nil, nil)
			return nil, nil
		},
	}
	mockTaskRepo := &mockCrawlTaskRepo{}
	mockEnq := &mockCrawlEnqueuer{}

	h := newTestCrawlHandler(mockReader, mockArtRepo, mockTaskRepo, mockEnq, false)

	task := newCrawlAsynqTask("art-gone", "task-1", "https://example.com/deleted", "user-1")
	err := h.ProcessTask(context.Background(), task)
	if err == nil {
		t.Fatal("ProcessTask should return error when scrape fails and article not found (nil, nil)")
	}

	// Verify task was marked failed
	if len(mockTaskRepo.setFailedCalls) != 1 {
		t.Fatalf("SetFailed calls = %d, want 1", len(mockTaskRepo.setFailedCalls))
	}
	if mockTaskRepo.setFailedCalls[0].ID != "task-1" {
		t.Errorf("SetFailed task ID = %q, want %q", mockTaskRepo.setFailedCalls[0].ID, "task-1")
	}

	// Verify article error was set
	if len(mockArtRepo.setErrorCalls) != 1 {
		t.Fatalf("SetError calls = %d, want 1", len(mockArtRepo.setErrorCalls))
	}
	if mockArtRepo.setErrorCalls[0].ID != "art-gone" {
		t.Errorf("SetError article ID = %q, want %q", mockArtRepo.setErrorCalls[0].ID, "art-gone")
	}

	// No AI task should have been enqueued
	if len(mockEnq.enqueuedTasks) != 0 {
		t.Errorf("no tasks should have been enqueued, got %d", len(mockEnq.enqueuedTasks))
	}

	// Crawl should NOT be marked finished
	if len(mockTaskRepo.setCrawlFinishedCalls) != 0 {
		t.Errorf("SetCrawlFinished should not have been called, got %d calls", len(mockTaskRepo.setCrawlFinishedCalls))
	}
}

func TestProcessTask_ClientFallback_NoImageTask(t *testing.T) {
	// When using client content fallback (scrape fails, article has client content),
	// images are NOT extracted/rehosted. Even with enableImage=true, only the AI task
	// should be enqueued — no image upload task.
	// This documents intentional behavior: the client fallback path skips image processing.
	mockReader := &mockScraper{
		scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
			return nil, errors.New("scrape timeout")
		},
	}
	// Client content includes markdown with image references
	markdownWithImages := "# Article\n\n![photo](https://img.example.com/photo.jpg)\n\nText here.\n\n![diagram](https://img.example.com/diagram.png)"
	mockArtRepo := &mockCrawlArticleRepo{
		getByIDFn: func(ctx context.Context, id string) (*domain.Article, error) {
			return &domain.Article{
				ID:              "art-1",
				Title:           strPtr("Client Title"),
				Author:          strPtr("Client Author"),
				SiteName:        strPtr("Client Site"),
				MarkdownContent: strPtr(markdownWithImages),
			}, nil
		},
	}
	mockTaskRepo := &mockCrawlTaskRepo{}
	mockEnq := &mockCrawlEnqueuer{}

	// enableImage = true — normally would trigger image task on the scrape-success path
	h := newTestCrawlHandler(mockReader, mockArtRepo, mockTaskRepo, mockEnq, true)

	task := newCrawlAsynqTask("art-1", "task-1", "https://example.com/article", "user-1")
	err := h.ProcessTask(context.Background(), task)
	if err != nil {
		t.Fatalf("ProcessTask should succeed with client fallback, got: %v", err)
	}

	// Verify exactly 1 task was enqueued (AI only, no image task)
	if len(mockEnq.enqueuedTasks) != 1 {
		t.Fatalf("enqueued tasks = %d, want 1 (AI only, no image task)", len(mockEnq.enqueuedTasks))
	}

	// The single enqueued task must be the AI task
	aiTask := mockEnq.enqueuedTasks[0]
	if aiTask.Type() != TypeAIProcess {
		t.Errorf("enqueued task type = %q, want %q (should be AI, not image)", aiTask.Type(), TypeAIProcess)
	}

	// Verify AI payload contains client content
	var aiPayload AIProcessPayload
	if err := json.Unmarshal(aiTask.Payload(), &aiPayload); err != nil {
		t.Fatalf("failed to unmarshal AI payload: %v", err)
	}
	if aiPayload.Title != "Client Title" {
		t.Errorf("AI payload Title = %q, want %q", aiPayload.Title, "Client Title")
	}
	if aiPayload.Markdown != markdownWithImages {
		t.Errorf("AI payload Markdown does not match client content")
	}

	// Verify crawl was marked finished (not failed)
	if len(mockTaskRepo.setCrawlFinishedCalls) != 1 {
		t.Errorf("SetCrawlFinished calls = %d, want 1", len(mockTaskRepo.setCrawlFinishedCalls))
	}

	// Verify no failure markers
	if len(mockTaskRepo.setFailedCalls) != 0 {
		t.Errorf("SetFailed should not have been called, got %d calls", len(mockTaskRepo.setFailedCalls))
	}
	if len(mockArtRepo.setErrorCalls) != 0 {
		t.Errorf("SetError should not have been called, got %d calls", len(mockArtRepo.setErrorCalls))
	}
}

func TestProcessTask_ScrapeSuccess_EmptyMarkdown_PreservesClientContent(t *testing.T) {
	// Scrape returns empty markdown but valid metadata —
	// client-extracted markdown_content should be preserved.
	scrapeResp := &client.ScrapeResponse{
		Markdown: "", // empty
		Metadata: client.ReaderMetadata{
			Title:    "Scraped Title",
			Author:   "Scraped Author",
			SiteName: "Scraped Site",
			OGImage:  "https://example.com/image.jpg",
			Language: "en",
			Favicon:  "https://example.com/favicon.ico",
		},
	}

	mockReader := &mockScraper{
		scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
			return scrapeResp, nil
		},
	}
	mockArtRepo := &mockCrawlArticleRepo{}
	mockTaskRepo := &mockCrawlTaskRepo{}
	mockEnq := &mockCrawlEnqueuer{}

	h := newTestCrawlHandler(mockReader, mockArtRepo, mockTaskRepo, mockEnq, false)

	task := newCrawlAsynqTask("art-1", "task-1", "https://example.com/article", "user-1")
	err := h.ProcessTask(context.Background(), task)
	if err != nil {
		t.Fatalf("ProcessTask returned error: %v", err)
	}

	// Verify UpdateCrawlResult was called with empty markdown.
	// The SQL COALESCE(NULLIF($4, ''), markdown_content) guard preserves
	// any existing client-extracted content when Reader returns empty markdown.
	if len(mockArtRepo.updateCrawlCalls) != 1 {
		t.Fatalf("UpdateCrawlResult calls = %d, want 1", len(mockArtRepo.updateCrawlCalls))
	}
	cr := mockArtRepo.updateCrawlCalls[0]
	if cr.Markdown != "" {
		t.Errorf("CrawlResult.Markdown = %q, want empty (DB guard preserves existing)", cr.Markdown)
	}
	// Metadata should still be passed through
	if cr.Title != "Scraped Title" {
		t.Errorf("CrawlResult.Title = %q, want %q", cr.Title, "Scraped Title")
	}
	if cr.Author != "Scraped Author" {
		t.Errorf("CrawlResult.Author = %q, want %q", cr.Author, "Scraped Author")
	}
	if cr.Language != "en" {
		t.Errorf("CrawlResult.Language = %q, want %q", cr.Language, "en")
	}
}

func TestProcessTask_ScrapeSuccess_EmptySiteName_DefaultsToWeb(t *testing.T) {
	// Scrape succeeds but SiteName is empty — source should default to "web"
	scrapeResp := &client.ScrapeResponse{
		Markdown: "# Content",
		Metadata: client.ReaderMetadata{
			Title:    "Title",
			SiteName: "", // empty
		},
	}

	mockReader := &mockScraper{
		scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
			return scrapeResp, nil
		},
	}
	mockArtRepo := &mockCrawlArticleRepo{}
	mockTaskRepo := &mockCrawlTaskRepo{}
	mockEnq := &mockCrawlEnqueuer{}

	h := newTestCrawlHandler(mockReader, mockArtRepo, mockTaskRepo, mockEnq, false)

	task := newCrawlAsynqTask("art-1", "task-1", "https://example.com", "user-1")
	err := h.ProcessTask(context.Background(), task)
	if err != nil {
		t.Fatalf("ProcessTask returned error: %v", err)
	}

	// Verify AI task was enqueued with source = "web"
	if len(mockEnq.enqueuedTasks) < 1 {
		t.Fatal("expected at least 1 enqueued task")
	}
	var aiPayload AIProcessPayload
	if err := json.Unmarshal(mockEnq.enqueuedTasks[0].Payload(), &aiPayload); err != nil {
		t.Fatalf("failed to unmarshal AI payload: %v", err)
	}
	if aiPayload.Source != "web" {
		t.Errorf("AI payload Source = %q, want %q", aiPayload.Source, "web")
	}
}

func TestProcessTask_ScrapeSuccess_WithImages_EnqueuesImageTask(t *testing.T) {
	// Scrape succeeds with markdown containing images — should enqueue image task when enabled
	scrapeResp := &client.ScrapeResponse{
		Markdown: "# Article\n\n![photo](https://img.example.com/photo.jpg)\n\nSome text.\n\n![diagram](https://img.example.com/diagram.png)",
		Metadata: client.ReaderMetadata{
			Title:    "Image Article",
			SiteName: "Example",
		},
	}

	mockReader := &mockScraper{
		scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
			return scrapeResp, nil
		},
	}
	mockArtRepo := &mockCrawlArticleRepo{}
	mockTaskRepo := &mockCrawlTaskRepo{}
	mockEnq := &mockCrawlEnqueuer{}

	h := newTestCrawlHandler(mockReader, mockArtRepo, mockTaskRepo, mockEnq, true) // enableImage = true

	task := newCrawlAsynqTask("art-1", "task-1", "https://example.com", "user-1")
	err := h.ProcessTask(context.Background(), task)
	if err != nil {
		t.Fatalf("ProcessTask returned error: %v", err)
	}

	// Should have enqueued AI task + image upload task
	if len(mockEnq.enqueuedTasks) != 2 {
		t.Fatalf("enqueued tasks = %d, want 2 (AI + image)", len(mockEnq.enqueuedTasks))
	}

	// First task should be AI
	if mockEnq.enqueuedTasks[0].Type() != TypeAIProcess {
		t.Errorf("first enqueued task type = %q, want %q", mockEnq.enqueuedTasks[0].Type(), TypeAIProcess)
	}

	// Second task should be image upload
	if mockEnq.enqueuedTasks[1].Type() != TypeImageUpload {
		t.Errorf("second enqueued task type = %q, want %q", mockEnq.enqueuedTasks[1].Type(), TypeImageUpload)
	}

	var imgPayload ImageUploadPayload
	if err := json.Unmarshal(mockEnq.enqueuedTasks[1].Payload(), &imgPayload); err != nil {
		t.Fatalf("failed to unmarshal image payload: %v", err)
	}
	if len(imgPayload.ImageURLs) != 2 {
		t.Errorf("image URLs count = %d, want 2", len(imgPayload.ImageURLs))
	}
}

// --- Cache optimization tests ---

func TestProcessTask_CacheHitFull_SkipsCrawlAndAI(t *testing.T) {
	// Cache has full results (content + AI) → skip Reader + AI entirely
	summary := "A cached summary"
	markdown := "# Cached Article\n\nLong enough content for the cache hit to work properly in our test scenario here."
	confidence := 0.85
	catSlug := "tech"

	mockReader := &mockScraper{
		scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
			t.Fatal("Reader should NOT be called on cache hit")
			return nil, nil
		},
	}
	mockArtRepo := &mockCrawlArticleRepo{}
	mockTaskRepo := &mockCrawlTaskRepo{}
	mockEnq := &mockCrawlEnqueuer{}
	mockCache := &mockContentCacheRepo{
		getByURLFn: func(ctx context.Context, url string) (*domain.ContentCache, error) {
			return &domain.ContentCache{
				URL:             url,
				Title:           strPtr("Cached Title"),
				Author:          strPtr("Cached Author"),
				SiteName:        strPtr("Cached Site"),
				MarkdownContent: &markdown,
				WordCount:       42,
				Language:        strPtr("en"),
				CategorySlug:    &catSlug,
				Summary:         &summary,
				KeyPoints:       []string{"point1", "point2"},
				AIConfidence:    &confidence,
				AITagNames:      []string{"go", "backend"},
			}, nil
		},
	}

	h := &CrawlHandler{
		readerClient: mockReader,
		articleRepo:  mockArtRepo,
		taskRepo:     mockTaskRepo,
		asynqClient:  mockEnq,
		cacheRepo:    mockCache,
		tagRepo:      &mockCrawlTagRepo{},
	}

	task := newCrawlAsynqTask("art-1", "task-1", "https://example.com/cached", "user-1")
	err := h.ProcessTask(context.Background(), task)
	if err != nil {
		t.Fatalf("ProcessTask returned error: %v", err)
	}

	// Verify no AI task was enqueued (skipped)
	if len(mockEnq.enqueuedTasks) != 0 {
		t.Errorf("no tasks should be enqueued on full cache hit, got %d", len(mockEnq.enqueuedTasks))
	}

	// Verify article status was set to processing then crawl finished
	if len(mockArtRepo.updateStatusCalls) < 1 {
		t.Fatal("UpdateStatus should have been called")
	}

	// Verify task was marked finished (not failed)
	if len(mockTaskRepo.setCrawlFinishedCalls) != 1 {
		t.Errorf("SetCrawlFinished calls = %d, want 1", len(mockTaskRepo.setCrawlFinishedCalls))
	}
	if len(mockTaskRepo.setFailedCalls) != 0 {
		t.Errorf("SetFailed should not be called on cache hit, got %d", len(mockTaskRepo.setFailedCalls))
	}
}

func TestProcessTask_CacheMiss_ClientContent_SkipsReader(t *testing.T) {
	// Cache misses, but article has client-extracted content → skip Reader, enqueue AI
	mockReader := &mockScraper{
		scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
			t.Fatal("Reader should NOT be called when client content exists")
			return nil, nil
		},
	}
	clientMarkdown := "# Client Extracted\n\nSome content from the client extraction pipeline."
	mockArtRepo := &mockCrawlArticleRepo{
		getByIDFn: func(ctx context.Context, id string) (*domain.Article, error) {
			return &domain.Article{
				ID:              "art-1",
				Title:           strPtr("Client Title"),
				Author:          strPtr("Client Author"),
				SiteName:        strPtr("Client Site"),
				MarkdownContent: &clientMarkdown,
			}, nil
		},
	}
	mockTaskRepo := &mockCrawlTaskRepo{}
	mockEnq := &mockCrawlEnqueuer{}

	h := &CrawlHandler{
		readerClient: mockReader,
		articleRepo:  mockArtRepo,
		taskRepo:     mockTaskRepo,
		asynqClient:  mockEnq,
		cacheRepo:    &mockContentCacheRepo{}, // cache miss (default nil)
		tagRepo:      &mockCrawlTagRepo{},
	}

	task := newCrawlAsynqTask("art-1", "task-1", "https://example.com/client", "user-1")
	err := h.ProcessTask(context.Background(), task)
	if err != nil {
		t.Fatalf("ProcessTask returned error: %v", err)
	}

	// Verify AI task was enqueued
	if len(mockEnq.enqueuedTasks) != 1 {
		t.Fatalf("enqueued tasks = %d, want 1 (AI)", len(mockEnq.enqueuedTasks))
	}
	if mockEnq.enqueuedTasks[0].Type() != TypeAIProcess {
		t.Errorf("enqueued task type = %q, want %q", mockEnq.enqueuedTasks[0].Type(), TypeAIProcess)
	}

	// Verify crawl was marked finished
	if len(mockTaskRepo.setCrawlFinishedCalls) != 1 {
		t.Errorf("SetCrawlFinished calls = %d, want 1", len(mockTaskRepo.setCrawlFinishedCalls))
	}
}

func TestProcessTask_CacheMiss_NoClientContent_CallsReader(t *testing.T) {
	// Cache misses, no client content → normal Reader flow (existing behavior)
	readerCalled := false
	mockReader := &mockScraper{
		scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
			readerCalled = true
			return &client.ScrapeResponse{
				Markdown: "# Reader Content\n\nExtracted by reader.",
				Metadata: client.ReaderMetadata{
					Title:    "Reader Title",
					SiteName: "Reader Site",
				},
			}, nil
		},
	}
	mockArtRepo := &mockCrawlArticleRepo{
		getByIDFn: func(ctx context.Context, id string) (*domain.Article, error) {
			return &domain.Article{ID: "art-1"}, nil // no markdown
		},
	}
	mockTaskRepo := &mockCrawlTaskRepo{}
	mockEnq := &mockCrawlEnqueuer{}

	h := &CrawlHandler{
		readerClient: mockReader,
		articleRepo:  mockArtRepo,
		taskRepo:     mockTaskRepo,
		asynqClient:  mockEnq,
		cacheRepo:    &mockContentCacheRepo{}, // cache miss
		tagRepo:      &mockCrawlTagRepo{},
	}

	task := newCrawlAsynqTask("art-1", "task-1", "https://example.com/fresh", "user-1")
	err := h.ProcessTask(context.Background(), task)
	if err != nil {
		t.Fatalf("ProcessTask returned error: %v", err)
	}

	if !readerCalled {
		t.Error("Reader should be called when cache misses and no client content")
	}

	// Verify AI task was enqueued
	if len(mockEnq.enqueuedTasks) < 1 {
		t.Fatal("AI task should be enqueued after Reader success")
	}
}
