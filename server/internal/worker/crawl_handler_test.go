package worker

import (
	"context"
	"encoding/json"
	"errors"
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
	getByIDFn          func(ctx context.Context, id string) (*domain.Article, error)
	updateCrawlFn      func(ctx context.Context, id string, cr repository.CrawlResult) error
	setErrorFn         func(ctx context.Context, id string, errMsg string) error
	updateCrawlCalls   []repository.CrawlResult
	setErrorCalls      []struct{ ID, ErrMsg string }
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
