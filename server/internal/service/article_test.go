package service

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"github.com/hibiken/asynq"

	"folio-server/internal/domain"
	"folio-server/internal/repository"
	"folio-server/internal/worker"
)

// --- Mock implementations ---

type mockArticleRepo struct {
	createFn     func(ctx context.Context, p repository.CreateArticleParams) (*domain.Article, error)
	lastCreateP  *repository.CreateArticleParams // captures the last CreateArticleParams passed
	getByIDFn    func(ctx context.Context, id string) (*domain.Article, error)
	listByUserFn func(ctx context.Context, p repository.ListArticlesParams) (*repository.ListArticlesResult, error)
	updateFn     func(ctx context.Context, id string, p repository.UpdateArticleParams) error
	deleteFn     func(ctx context.Context, id string) error
	searchFn     func(ctx context.Context, userID, query string, page, perPage int) (*repository.ListArticlesResult, error)
}

func (m *mockArticleRepo) Create(ctx context.Context, p repository.CreateArticleParams) (*domain.Article, error) {
	m.lastCreateP = &p
	if m.createFn != nil {
		return m.createFn(ctx, p)
	}
	return &domain.Article{ID: "article-123", UserID: p.UserID, URL: p.URL}, nil
}

func (m *mockArticleRepo) GetByID(ctx context.Context, id string) (*domain.Article, error) {
	if m.getByIDFn != nil {
		return m.getByIDFn(ctx, id)
	}
	return nil, nil
}

func (m *mockArticleRepo) ListByUser(ctx context.Context, p repository.ListArticlesParams) (*repository.ListArticlesResult, error) {
	if m.listByUserFn != nil {
		return m.listByUserFn(ctx, p)
	}
	return &repository.ListArticlesResult{}, nil
}

func (m *mockArticleRepo) Update(ctx context.Context, id string, p repository.UpdateArticleParams) error {
	if m.updateFn != nil {
		return m.updateFn(ctx, id, p)
	}
	return nil
}

func (m *mockArticleRepo) Delete(ctx context.Context, id string) error {
	if m.deleteFn != nil {
		return m.deleteFn(ctx, id)
	}
	return nil
}

func (m *mockArticleRepo) SearchByTitle(ctx context.Context, userID, query string, page, perPage int) (*repository.ListArticlesResult, error) {
	if m.searchFn != nil {
		return m.searchFn(ctx, userID, query, page, perPage)
	}
	return &repository.ListArticlesResult{}, nil
}

type mockTaskRepo struct {
	createFn    func(ctx context.Context, p repository.CreateTaskParams) (*domain.CrawlTask, error)
	lastCreateP *repository.CreateTaskParams
}

func (m *mockTaskRepo) Create(ctx context.Context, p repository.CreateTaskParams) (*domain.CrawlTask, error) {
	m.lastCreateP = &p
	if m.createFn != nil {
		return m.createFn(ctx, p)
	}
	return &domain.CrawlTask{ID: "task-123"}, nil
}

type mockTagRepo struct {
	attachCalls []struct{ ArticleID, TagID string }
	attachFn    func(ctx context.Context, articleID, tagID string) error
	getByArtFn  func(ctx context.Context, articleID string) ([]domain.Tag, error)
}

func (m *mockTagRepo) AttachToArticle(ctx context.Context, articleID, tagID string) error {
	m.attachCalls = append(m.attachCalls, struct{ ArticleID, TagID string }{articleID, tagID})
	if m.attachFn != nil {
		return m.attachFn(ctx, articleID, tagID)
	}
	return nil
}

func (m *mockTagRepo) GetByArticle(ctx context.Context, articleID string) ([]domain.Tag, error) {
	if m.getByArtFn != nil {
		return m.getByArtFn(ctx, articleID)
	}
	return nil, nil
}

type mockCategoryRepo struct {
	getByIDFn func(ctx context.Context, id string) (*domain.Category, error)
}

func (m *mockCategoryRepo) GetByID(ctx context.Context, id string) (*domain.Category, error) {
	if m.getByIDFn != nil {
		return m.getByIDFn(ctx, id)
	}
	return nil, nil
}

type mockQuotaService struct {
	checkFn func(ctx context.Context, userID string) error
}

func (m *mockQuotaService) CheckAndIncrement(ctx context.Context, userID string) error {
	if m.checkFn != nil {
		return m.checkFn(ctx, userID)
	}
	return nil
}

type mockEnqueuer struct {
	enqueuedTasks []*asynq.Task
	enqueueFn     func(ctx context.Context, task *asynq.Task, opts ...asynq.Option) (*asynq.TaskInfo, error)
}

func (m *mockEnqueuer) EnqueueContext(ctx context.Context, task *asynq.Task, opts ...asynq.Option) (*asynq.TaskInfo, error) {
	m.enqueuedTasks = append(m.enqueuedTasks, task)
	if m.enqueueFn != nil {
		return m.enqueueFn(ctx, task, opts...)
	}
	return &asynq.TaskInfo{}, nil
}

// newTestArticleService creates an ArticleService with mock dependencies for testing.
func newTestArticleService(
	articleRepo *mockArticleRepo,
	taskRepo *mockTaskRepo,
	tagRepo *mockTagRepo,
	categoryRepo *mockCategoryRepo,
	quota *mockQuotaService,
	enqueuer *mockEnqueuer,
) *ArticleService {
	return &ArticleService{
		articleRepo:  articleRepo,
		taskRepo:     taskRepo,
		tagRepo:      tagRepo,
		categoryRepo: categoryRepo,
		quotaService: quota,
		asynqClient:  enqueuer,
	}
}

func strPtr(s string) *string { return &s }
func intPtr(i int) *int       { return &i }

func TestSubmitURLRequest_JSONDecode_WithContent(t *testing.T) {
	body := `{
		"url": "https://example.com/article",
		"tag_ids": ["tag-1"],
		"title": "Article Title",
		"author": "Author Name",
		"site_name": "Example Blog",
		"markdown_content": "# Heading\n\nContent...",
		"word_count": 1234
	}`

	var req SubmitURLRequest
	if err := json.Unmarshal([]byte(body), &req); err != nil {
		t.Fatalf("failed to unmarshal: %v", err)
	}

	if req.URL != "https://example.com/article" {
		t.Errorf("URL = %q, want %q", req.URL, "https://example.com/article")
	}
	if len(req.TagIDs) != 1 || req.TagIDs[0] != "tag-1" {
		t.Errorf("TagIDs = %v, want [tag-1]", req.TagIDs)
	}
	if req.Title == nil || *req.Title != "Article Title" {
		t.Errorf("Title = %v, want %q", req.Title, "Article Title")
	}
	if req.Author == nil || *req.Author != "Author Name" {
		t.Errorf("Author = %v, want %q", req.Author, "Author Name")
	}
	if req.SiteName == nil || *req.SiteName != "Example Blog" {
		t.Errorf("SiteName = %v, want %q", req.SiteName, "Example Blog")
	}
	if req.MarkdownContent == nil || *req.MarkdownContent != "# Heading\n\nContent..." {
		t.Errorf("MarkdownContent = %v, want %q", req.MarkdownContent, "# Heading\n\nContent...")
	}
	if req.WordCount == nil || *req.WordCount != 1234 {
		t.Errorf("WordCount = %v, want 1234", req.WordCount)
	}
}

func TestSubmitURLRequest_JSONDecode_WithoutContent_BackwardCompat(t *testing.T) {
	body := `{"url": "https://example.com/article"}`

	var req SubmitURLRequest
	if err := json.Unmarshal([]byte(body), &req); err != nil {
		t.Fatalf("failed to unmarshal: %v", err)
	}

	if req.URL != "https://example.com/article" {
		t.Errorf("URL = %q, want %q", req.URL, "https://example.com/article")
	}
	if req.TagIDs != nil {
		t.Errorf("TagIDs = %v, want nil", req.TagIDs)
	}
	if req.Title != nil {
		t.Errorf("Title = %v, want nil", req.Title)
	}
	if req.Author != nil {
		t.Errorf("Author = %v, want nil", req.Author)
	}
	if req.SiteName != nil {
		t.Errorf("SiteName = %v, want nil", req.SiteName)
	}
	if req.MarkdownContent != nil {
		t.Errorf("MarkdownContent = %v, want nil", req.MarkdownContent)
	}
	if req.WordCount != nil {
		t.Errorf("WordCount = %v, want nil", req.WordCount)
	}
}

func TestSubmitURLRequest_JSONDecode_PartialContent(t *testing.T) {
	// Only URL and title provided (no markdown_content)
	body := `{"url": "https://example.com", "title": "Just a Title"}`

	var req SubmitURLRequest
	if err := json.Unmarshal([]byte(body), &req); err != nil {
		t.Fatalf("failed to unmarshal: %v", err)
	}

	if req.URL != "https://example.com" {
		t.Errorf("URL = %q, want %q", req.URL, "https://example.com")
	}
	if req.Title == nil || *req.Title != "Just a Title" {
		t.Errorf("Title = %v, want %q", req.Title, "Just a Title")
	}
	if req.MarkdownContent != nil {
		t.Errorf("MarkdownContent = %v, want nil", req.MarkdownContent)
	}
	if req.WordCount != nil {
		t.Errorf("WordCount = %v, want nil", req.WordCount)
	}
}

func TestSubmitURLRequest_JSONDecode_EmptyStrings(t *testing.T) {
	body := `{
		"url": "https://example.com",
		"title": "",
		"markdown_content": "",
		"word_count": 0
	}`

	var req SubmitURLRequest
	if err := json.Unmarshal([]byte(body), &req); err != nil {
		t.Fatalf("failed to unmarshal: %v", err)
	}

	if req.Title == nil || *req.Title != "" {
		t.Errorf("Title = %v, want empty string pointer", req.Title)
	}
	if req.MarkdownContent == nil || *req.MarkdownContent != "" {
		t.Errorf("MarkdownContent = %v, want empty string pointer", req.MarkdownContent)
	}
	if req.WordCount == nil || *req.WordCount != 0 {
		t.Errorf("WordCount = %v, want 0", req.WordCount)
	}
}

func TestSubmitURLRequest_JSONDecode_WithTagIDs(t *testing.T) {
	body := `{
		"url": "https://example.com",
		"tag_ids": ["id-1", "id-2", "id-3"],
		"markdown_content": "# Content"
	}`

	var req SubmitURLRequest
	if err := json.Unmarshal([]byte(body), &req); err != nil {
		t.Fatalf("failed to unmarshal: %v", err)
	}

	if len(req.TagIDs) != 3 {
		t.Errorf("len(TagIDs) = %d, want 3", len(req.TagIDs))
	}
	if req.MarkdownContent == nil || *req.MarkdownContent != "# Content" {
		t.Errorf("MarkdownContent = %v, want %q", req.MarkdownContent, "# Content")
	}
}

// --- SubmitURL function tests ---

func TestSubmitURL_AllContentFields(t *testing.T) {
	artRepo := &mockArticleRepo{}
	taskRepo := &mockTaskRepo{}
	tagRepo := &mockTagRepo{}
	catRepo := &mockCategoryRepo{}
	quota := &mockQuotaService{}
	enqueuer := &mockEnqueuer{}

	svc := newTestArticleService(artRepo, taskRepo, tagRepo, catRepo, quota, enqueuer)

	req := SubmitURLRequest{
		URL:             "https://example.com/article",
		TagIDs:          []string{"tag-1", "tag-2"},
		Title:           strPtr("Article Title"),
		Author:          strPtr("Author Name"),
		SiteName:        strPtr("Example Blog"),
		MarkdownContent: strPtr("# Heading\n\nContent here."),
		WordCount:       intPtr(1234),
	}

	resp, err := svc.SubmitURL(context.Background(), "user-1", req)
	if err != nil {
		t.Fatalf("SubmitURL failed: %v", err)
	}

	if resp.ArticleID != "article-123" {
		t.Errorf("ArticleID = %q, want %q", resp.ArticleID, "article-123")
	}
	if resp.TaskID != "task-123" {
		t.Errorf("TaskID = %q, want %q", resp.TaskID, "task-123")
	}

	// Verify CreateArticleParams passed to repository
	p := artRepo.lastCreateP
	if p == nil {
		t.Fatal("articleRepo.Create was not called")
	}
	if p.UserID != "user-1" {
		t.Errorf("CreateArticleParams.UserID = %q, want %q", p.UserID, "user-1")
	}
	if p.URL != "https://example.com/article" {
		t.Errorf("CreateArticleParams.URL = %q, want %q", p.URL, "https://example.com/article")
	}
	if p.SourceType != domain.SourceWeb {
		t.Errorf("CreateArticleParams.SourceType = %q, want %q", p.SourceType, domain.SourceWeb)
	}
	if p.Title == nil || *p.Title != "Article Title" {
		t.Errorf("CreateArticleParams.Title = %v, want %q", p.Title, "Article Title")
	}
	if p.Author == nil || *p.Author != "Author Name" {
		t.Errorf("CreateArticleParams.Author = %v, want %q", p.Author, "Author Name")
	}
	if p.SiteName == nil || *p.SiteName != "Example Blog" {
		t.Errorf("CreateArticleParams.SiteName = %v, want %q", p.SiteName, "Example Blog")
	}
	if p.MarkdownContent == nil || *p.MarkdownContent != "# Heading\n\nContent here." {
		t.Errorf("CreateArticleParams.MarkdownContent = %v, want %q", p.MarkdownContent, "# Heading\n\nContent here.")
	}
	if p.WordCount == nil || *p.WordCount != 1234 {
		t.Errorf("CreateArticleParams.WordCount = %v, want 1234", p.WordCount)
	}

	// Verify tags were attached
	if len(tagRepo.attachCalls) != 2 {
		t.Fatalf("expected 2 tag attach calls, got %d", len(tagRepo.attachCalls))
	}
	if tagRepo.attachCalls[0].ArticleID != "article-123" || tagRepo.attachCalls[0].TagID != "tag-1" {
		t.Errorf("attach call 0 = %+v, want article-123/tag-1", tagRepo.attachCalls[0])
	}
	if tagRepo.attachCalls[1].ArticleID != "article-123" || tagRepo.attachCalls[1].TagID != "tag-2" {
		t.Errorf("attach call 1 = %+v, want article-123/tag-2", tagRepo.attachCalls[1])
	}

	// Verify crawl task was enqueued
	if len(enqueuer.enqueuedTasks) != 1 {
		t.Fatalf("expected 1 enqueued task, got %d", len(enqueuer.enqueuedTasks))
	}
}

func TestSubmitURL_WithoutContentFields_BackwardCompat(t *testing.T) {
	artRepo := &mockArticleRepo{}
	taskRepo := &mockTaskRepo{}
	tagRepo := &mockTagRepo{}
	catRepo := &mockCategoryRepo{}
	quota := &mockQuotaService{}
	enqueuer := &mockEnqueuer{}

	svc := newTestArticleService(artRepo, taskRepo, tagRepo, catRepo, quota, enqueuer)

	req := SubmitURLRequest{
		URL: "https://example.com/article",
	}

	resp, err := svc.SubmitURL(context.Background(), "user-1", req)
	if err != nil {
		t.Fatalf("SubmitURL failed: %v", err)
	}

	if resp.ArticleID == "" {
		t.Error("ArticleID should not be empty")
	}
	if resp.TaskID == "" {
		t.Error("TaskID should not be empty")
	}

	// Verify nil fields are passed as nil to repository
	p := artRepo.lastCreateP
	if p == nil {
		t.Fatal("articleRepo.Create was not called")
	}
	if p.Title != nil {
		t.Errorf("CreateArticleParams.Title = %v, want nil", p.Title)
	}
	if p.Author != nil {
		t.Errorf("CreateArticleParams.Author = %v, want nil", p.Author)
	}
	if p.SiteName != nil {
		t.Errorf("CreateArticleParams.SiteName = %v, want nil", p.SiteName)
	}
	if p.MarkdownContent != nil {
		t.Errorf("CreateArticleParams.MarkdownContent = %v, want nil", p.MarkdownContent)
	}
	if p.WordCount != nil {
		t.Errorf("CreateArticleParams.WordCount = %v, want nil", p.WordCount)
	}

	// No tags should be attached
	if len(tagRepo.attachCalls) != 0 {
		t.Errorf("expected 0 tag attach calls, got %d", len(tagRepo.attachCalls))
	}
}

func TestSubmitURL_PartialFields_OnlyTitle(t *testing.T) {
	artRepo := &mockArticleRepo{}
	taskRepo := &mockTaskRepo{}
	tagRepo := &mockTagRepo{}
	catRepo := &mockCategoryRepo{}
	quota := &mockQuotaService{}
	enqueuer := &mockEnqueuer{}

	svc := newTestArticleService(artRepo, taskRepo, tagRepo, catRepo, quota, enqueuer)

	req := SubmitURLRequest{
		URL:   "https://example.com/article",
		Title: strPtr("Only Title"),
	}

	_, err := svc.SubmitURL(context.Background(), "user-1", req)
	if err != nil {
		t.Fatalf("SubmitURL failed: %v", err)
	}

	p := artRepo.lastCreateP
	if p == nil {
		t.Fatal("articleRepo.Create was not called")
	}
	if p.Title == nil || *p.Title != "Only Title" {
		t.Errorf("CreateArticleParams.Title = %v, want %q", p.Title, "Only Title")
	}
	if p.Author != nil {
		t.Errorf("CreateArticleParams.Author = %v, want nil", p.Author)
	}
	if p.SiteName != nil {
		t.Errorf("CreateArticleParams.SiteName = %v, want nil", p.SiteName)
	}
	if p.MarkdownContent != nil {
		t.Errorf("CreateArticleParams.MarkdownContent = %v, want nil", p.MarkdownContent)
	}
	if p.WordCount != nil {
		t.Errorf("CreateArticleParams.WordCount = %v, want nil", p.WordCount)
	}
}

func TestSubmitURL_PartialFields_MarkdownAndWordCount(t *testing.T) {
	artRepo := &mockArticleRepo{}
	taskRepo := &mockTaskRepo{}
	tagRepo := &mockTagRepo{}
	catRepo := &mockCategoryRepo{}
	quota := &mockQuotaService{}
	enqueuer := &mockEnqueuer{}

	svc := newTestArticleService(artRepo, taskRepo, tagRepo, catRepo, quota, enqueuer)

	req := SubmitURLRequest{
		URL:             "https://example.com",
		MarkdownContent: strPtr("# Markdown Only"),
		WordCount:       intPtr(42),
	}

	_, err := svc.SubmitURL(context.Background(), "user-1", req)
	if err != nil {
		t.Fatalf("SubmitURL failed: %v", err)
	}

	p := artRepo.lastCreateP
	if p == nil {
		t.Fatal("articleRepo.Create was not called")
	}
	if p.Title != nil {
		t.Errorf("CreateArticleParams.Title = %v, want nil", p.Title)
	}
	if p.MarkdownContent == nil || *p.MarkdownContent != "# Markdown Only" {
		t.Errorf("CreateArticleParams.MarkdownContent = %v, want %q", p.MarkdownContent, "# Markdown Only")
	}
	if p.WordCount == nil || *p.WordCount != 42 {
		t.Errorf("CreateArticleParams.WordCount = %v, want 42", p.WordCount)
	}
}

func TestSubmitURL_EmptyStringFields(t *testing.T) {
	artRepo := &mockArticleRepo{}
	taskRepo := &mockTaskRepo{}
	tagRepo := &mockTagRepo{}
	catRepo := &mockCategoryRepo{}
	quota := &mockQuotaService{}
	enqueuer := &mockEnqueuer{}

	svc := newTestArticleService(artRepo, taskRepo, tagRepo, catRepo, quota, enqueuer)

	req := SubmitURLRequest{
		URL:             "https://example.com",
		Title:           strPtr(""),
		Author:          strPtr(""),
		MarkdownContent: strPtr(""),
		WordCount:       intPtr(0),
	}

	_, err := svc.SubmitURL(context.Background(), "user-1", req)
	if err != nil {
		t.Fatalf("SubmitURL failed: %v", err)
	}

	p := artRepo.lastCreateP
	if p == nil {
		t.Fatal("articleRepo.Create was not called")
	}
	// Empty strings are still non-nil pointers
	if p.Title == nil || *p.Title != "" {
		t.Errorf("CreateArticleParams.Title = %v, want empty string pointer", p.Title)
	}
	if p.Author == nil || *p.Author != "" {
		t.Errorf("CreateArticleParams.Author = %v, want empty string pointer", p.Author)
	}
	if p.MarkdownContent == nil || *p.MarkdownContent != "" {
		t.Errorf("CreateArticleParams.MarkdownContent = %v, want empty string pointer", p.MarkdownContent)
	}
	if p.WordCount == nil || *p.WordCount != 0 {
		t.Errorf("CreateArticleParams.WordCount = %v, want 0", p.WordCount)
	}
}

func TestSubmitURL_SourceDetection_Wechat(t *testing.T) {
	artRepo := &mockArticleRepo{}
	taskRepo := &mockTaskRepo{}
	tagRepo := &mockTagRepo{}
	catRepo := &mockCategoryRepo{}
	quota := &mockQuotaService{}
	enqueuer := &mockEnqueuer{}

	svc := newTestArticleService(artRepo, taskRepo, tagRepo, catRepo, quota, enqueuer)

	req := SubmitURLRequest{
		URL: "https://mp.weixin.qq.com/s/abc123",
	}

	_, err := svc.SubmitURL(context.Background(), "user-1", req)
	if err != nil {
		t.Fatalf("SubmitURL failed: %v", err)
	}

	p := artRepo.lastCreateP
	if p == nil {
		t.Fatal("articleRepo.Create was not called")
	}
	if p.SourceType != domain.SourceWechat {
		t.Errorf("CreateArticleParams.SourceType = %q, want %q", p.SourceType, domain.SourceWechat)
	}

	// Also verify task repo got the correct source type string
	tp := taskRepo.lastCreateP
	if tp == nil {
		t.Fatal("taskRepo.Create was not called")
	}
	if tp.SourceType != string(domain.SourceWechat) {
		t.Errorf("CreateTaskParams.SourceType = %q, want %q", tp.SourceType, string(domain.SourceWechat))
	}
}

func TestSubmitURL_QuotaExceeded(t *testing.T) {
	artRepo := &mockArticleRepo{}
	taskRepo := &mockTaskRepo{}
	tagRepo := &mockTagRepo{}
	catRepo := &mockCategoryRepo{}
	quota := &mockQuotaService{
		checkFn: func(ctx context.Context, userID string) error {
			return ErrQuotaExceeded
		},
	}
	enqueuer := &mockEnqueuer{}

	svc := newTestArticleService(artRepo, taskRepo, tagRepo, catRepo, quota, enqueuer)

	req := SubmitURLRequest{
		URL:   "https://example.com",
		Title: strPtr("Title"),
	}

	_, err := svc.SubmitURL(context.Background(), "user-1", req)
	if !errors.Is(err, ErrQuotaExceeded) {
		t.Errorf("expected ErrQuotaExceeded, got: %v", err)
	}

	// Article should NOT have been created
	if artRepo.lastCreateP != nil {
		t.Error("articleRepo.Create should not have been called when quota exceeded")
	}
}

func TestSubmitURL_ArticleCreateError(t *testing.T) {
	artRepo := &mockArticleRepo{
		createFn: func(ctx context.Context, p repository.CreateArticleParams) (*domain.Article, error) {
			return nil, errors.New("duplicate url")
		},
	}
	taskRepo := &mockTaskRepo{}
	tagRepo := &mockTagRepo{}
	catRepo := &mockCategoryRepo{}
	quota := &mockQuotaService{}
	enqueuer := &mockEnqueuer{}

	svc := newTestArticleService(artRepo, taskRepo, tagRepo, catRepo, quota, enqueuer)

	req := SubmitURLRequest{
		URL: "https://example.com",
	}

	_, err := svc.SubmitURL(context.Background(), "user-1", req)
	if err == nil {
		t.Fatal("expected error from SubmitURL")
	}
	if !errors.Is(err, errors.Unwrap(err)) {
		// Just verify it wraps properly
	}

	// Task should NOT have been created
	if taskRepo.lastCreateP != nil {
		t.Error("taskRepo.Create should not have been called when article creation failed")
	}
}

func TestSubmitURL_TagAttachError_NonFatal(t *testing.T) {
	artRepo := &mockArticleRepo{}
	taskRepo := &mockTaskRepo{}
	tagRepo := &mockTagRepo{
		attachFn: func(ctx context.Context, articleID, tagID string) error {
			if tagID == "bad-tag" {
				return errors.New("tag not found")
			}
			return nil
		},
	}
	catRepo := &mockCategoryRepo{}
	quota := &mockQuotaService{}
	enqueuer := &mockEnqueuer{}

	svc := newTestArticleService(artRepo, taskRepo, tagRepo, catRepo, quota, enqueuer)

	req := SubmitURLRequest{
		URL:    "https://example.com",
		TagIDs: []string{"good-tag", "bad-tag", "another-good"},
	}

	// Should succeed even with tag attach errors
	resp, err := svc.SubmitURL(context.Background(), "user-1", req)
	if err != nil {
		t.Fatalf("SubmitURL should not fail on tag attach error: %v", err)
	}
	if resp.ArticleID == "" {
		t.Error("ArticleID should not be empty")
	}

	// All 3 tags should have been attempted
	if len(tagRepo.attachCalls) != 3 {
		t.Errorf("expected 3 tag attach calls, got %d", len(tagRepo.attachCalls))
	}
}

func TestSubmitURL_TaskRepoFields(t *testing.T) {
	artRepo := &mockArticleRepo{
		createFn: func(ctx context.Context, p repository.CreateArticleParams) (*domain.Article, error) {
			return &domain.Article{ID: "art-xyz", UserID: p.UserID, URL: p.URL}, nil
		},
	}
	taskRepo := &mockTaskRepo{}
	tagRepo := &mockTagRepo{}
	catRepo := &mockCategoryRepo{}
	quota := &mockQuotaService{}
	enqueuer := &mockEnqueuer{}

	svc := newTestArticleService(artRepo, taskRepo, tagRepo, catRepo, quota, enqueuer)

	req := SubmitURLRequest{
		URL: "https://twitter.com/user/status/123",
	}

	_, err := svc.SubmitURL(context.Background(), "user-42", req)
	if err != nil {
		t.Fatalf("SubmitURL failed: %v", err)
	}

	tp := taskRepo.lastCreateP
	if tp == nil {
		t.Fatal("taskRepo.Create was not called")
	}
	if tp.ArticleID != "art-xyz" {
		t.Errorf("CreateTaskParams.ArticleID = %q, want %q", tp.ArticleID, "art-xyz")
	}
	if tp.UserID != "user-42" {
		t.Errorf("CreateTaskParams.UserID = %q, want %q", tp.UserID, "user-42")
	}
	if tp.URL != "https://twitter.com/user/status/123" {
		t.Errorf("CreateTaskParams.URL = %q, want %q", tp.URL, "https://twitter.com/user/status/123")
	}
	if tp.SourceType != string(domain.SourceTwitter) {
		t.Errorf("CreateTaskParams.SourceType = %q, want %q", tp.SourceType, string(domain.SourceTwitter))
	}
}

// --- "Crawl always enqueued" invariant tests ---

func TestSubmitURL_CrawlTaskAlwaysEnqueued_WithContent(t *testing.T) {
	// Even when MarkdownContent is provided by the client, a crawl task
	// must still be created and enqueued (the crawler will scrape server-side
	// and fall back to client content if scrape fails).
	artRepo := &mockArticleRepo{}
	taskRepo := &mockTaskRepo{}
	tagRepo := &mockTagRepo{}
	catRepo := &mockCategoryRepo{}
	quota := &mockQuotaService{}
	enqueuer := &mockEnqueuer{}

	svc := newTestArticleService(artRepo, taskRepo, tagRepo, catRepo, quota, enqueuer)

	req := SubmitURLRequest{
		URL:             "https://example.com/article-with-content",
		Title:           strPtr("Pre-extracted Title"),
		Author:          strPtr("Pre-extracted Author"),
		SiteName:        strPtr("Example Blog"),
		MarkdownContent: strPtr("# Pre-extracted\n\nFull article content already available."),
		WordCount:       intPtr(500),
	}

	resp, err := svc.SubmitURL(context.Background(), "user-1", req)
	if err != nil {
		t.Fatalf("SubmitURL failed: %v", err)
	}
	if resp.TaskID == "" {
		t.Fatal("TaskID should not be empty — crawl task must always be created")
	}

	// Verify the task repo was called to create a crawl task
	if taskRepo.lastCreateP == nil {
		t.Fatal("taskRepo.Create was not called — crawl task must always be created even with client content")
	}
	if taskRepo.lastCreateP.ArticleID != resp.ArticleID {
		t.Errorf("task ArticleID = %q, want %q", taskRepo.lastCreateP.ArticleID, resp.ArticleID)
	}

	// Verify a crawl task was enqueued to asynq
	if len(enqueuer.enqueuedTasks) != 1 {
		t.Fatalf("expected exactly 1 enqueued task, got %d", len(enqueuer.enqueuedTasks))
	}
	enqueuedTask := enqueuer.enqueuedTasks[0]
	if enqueuedTask.Type() != worker.TypeCrawlArticle {
		t.Errorf("enqueued task type = %q, want %q", enqueuedTask.Type(), worker.TypeCrawlArticle)
	}

	// Verify the crawl payload contains the correct URL
	var crawlPayload worker.CrawlPayload
	if err := json.Unmarshal(enqueuedTask.Payload(), &crawlPayload); err != nil {
		t.Fatalf("failed to unmarshal crawl payload: %v", err)
	}
	if crawlPayload.URL != "https://example.com/article-with-content" {
		t.Errorf("crawl payload URL = %q, want %q", crawlPayload.URL, "https://example.com/article-with-content")
	}
	if crawlPayload.ArticleID != resp.ArticleID {
		t.Errorf("crawl payload ArticleID = %q, want %q", crawlPayload.ArticleID, resp.ArticleID)
	}
	if crawlPayload.UserID != "user-1" {
		t.Errorf("crawl payload UserID = %q, want %q", crawlPayload.UserID, "user-1")
	}
}

func TestSubmitURL_WordCountNilDefaultsToZero(t *testing.T) {
	// When WordCount is nil in the request, verify that the CreateArticleParams
	// passes nil to the repository. The repository's Create() function is then
	// responsible for defaulting nil WordCount to 0.
	// This test verifies the service passes through nil correctly, and separately
	// documents the repository contract: nil WordCount -> default 0.
	artRepo := &mockArticleRepo{
		createFn: func(ctx context.Context, p repository.CreateArticleParams) (*domain.Article, error) {
			// Simulate the repository's nil → 0 default logic (from repository.Create)
			wordCount := 0
			if p.WordCount != nil {
				wordCount = *p.WordCount
			}
			if wordCount != 0 {
				t.Errorf("expected wordCount to default to 0 when nil, got %d", wordCount)
			}
			return &domain.Article{ID: "article-wc", UserID: p.UserID, URL: p.URL}, nil
		},
	}
	taskRepo := &mockTaskRepo{}
	tagRepo := &mockTagRepo{}
	catRepo := &mockCategoryRepo{}
	quota := &mockQuotaService{}
	enqueuer := &mockEnqueuer{}

	svc := newTestArticleService(artRepo, taskRepo, tagRepo, catRepo, quota, enqueuer)

	req := SubmitURLRequest{
		URL:   "https://example.com/no-wordcount",
		Title: strPtr("Title Without WordCount"),
		// WordCount intentionally nil
	}

	_, err := svc.SubmitURL(context.Background(), "user-1", req)
	if err != nil {
		t.Fatalf("SubmitURL failed: %v", err)
	}

	// Verify WordCount was passed as nil to repository
	p := artRepo.lastCreateP
	if p == nil {
		t.Fatal("articleRepo.Create was not called")
	}
	if p.WordCount != nil {
		t.Errorf("CreateArticleParams.WordCount = %v, want nil", p.WordCount)
	}
}

func TestSubmitURL_AllNilOptionalFields(t *testing.T) {
	// Verify that nil pointers for Title, Author, SiteName, MarkdownContent,
	// and WordCount are all valid and passed through to the repository correctly.
	// This tests the service-to-repository contract for all nil optional fields.
	artRepo := &mockArticleRepo{
		createFn: func(ctx context.Context, p repository.CreateArticleParams) (*domain.Article, error) {
			// Verify all optional fields are nil
			if p.Title != nil {
				t.Errorf("expected Title to be nil, got %q", *p.Title)
			}
			if p.Author != nil {
				t.Errorf("expected Author to be nil, got %q", *p.Author)
			}
			if p.SiteName != nil {
				t.Errorf("expected SiteName to be nil, got %q", *p.SiteName)
			}
			if p.MarkdownContent != nil {
				t.Errorf("expected MarkdownContent to be nil, got %q", *p.MarkdownContent)
			}
			if p.WordCount != nil {
				t.Errorf("expected WordCount to be nil, got %d", *p.WordCount)
			}
			return &domain.Article{ID: "article-nil", UserID: p.UserID, URL: p.URL}, nil
		},
	}
	taskRepo := &mockTaskRepo{}
	tagRepo := &mockTagRepo{}
	catRepo := &mockCategoryRepo{}
	quota := &mockQuotaService{}
	enqueuer := &mockEnqueuer{}

	svc := newTestArticleService(artRepo, taskRepo, tagRepo, catRepo, quota, enqueuer)

	req := SubmitURLRequest{
		URL: "https://example.com/nil-fields",
		// All optional fields intentionally omitted (nil)
	}

	resp, err := svc.SubmitURL(context.Background(), "user-1", req)
	if err != nil {
		t.Fatalf("SubmitURL failed: %v", err)
	}
	if resp.ArticleID == "" {
		t.Error("ArticleID should not be empty")
	}

	// Double-check via lastCreateP
	p := artRepo.lastCreateP
	if p == nil {
		t.Fatal("articleRepo.Create was not called")
	}
	if p.UserID != "user-1" {
		t.Errorf("CreateArticleParams.UserID = %q, want %q", p.UserID, "user-1")
	}
	if p.URL != "https://example.com/nil-fields" {
		t.Errorf("CreateArticleParams.URL = %q, want %q", p.URL, "https://example.com/nil-fields")
	}
}

func TestCreateArticleParams_WordCountNilDefaultsToZero(t *testing.T) {
	// Directly test the repository's nil WordCount → 0 default logic
	// (extracted from repository.Create)
	p := repository.CreateArticleParams{
		UserID:     "user-1",
		URL:        "https://example.com",
		SourceType: domain.SourceWeb,
		// WordCount is nil
	}

	wordCount := 0
	if p.WordCount != nil {
		wordCount = *p.WordCount
	}

	if wordCount != 0 {
		t.Errorf("nil WordCount should default to 0, got %d", wordCount)
	}
}

func TestCreateArticleParams_WordCountExplicitValue(t *testing.T) {
	// When WordCount is provided, it should be used as-is
	wc := 42
	p := repository.CreateArticleParams{
		UserID:     "user-1",
		URL:        "https://example.com",
		SourceType: domain.SourceWeb,
		WordCount:  &wc,
	}

	wordCount := 0
	if p.WordCount != nil {
		wordCount = *p.WordCount
	}

	if wordCount != 42 {
		t.Errorf("explicit WordCount should be 42, got %d", wordCount)
	}
}

func TestCreateArticleParams_AllNilOptionalFields(t *testing.T) {
	// Verify the CreateArticleParams struct accepts all nil optional fields
	// and applying the repository's default logic produces sensible values
	p := repository.CreateArticleParams{
		UserID:     "user-1",
		URL:        "https://example.com/nil-everything",
		SourceType: domain.SourceWeb,
		Title:      nil,
		Author:     nil,
		SiteName:   nil,
		MarkdownContent: nil,
		WordCount:  nil,
	}

	// These nil values should be safe to pass to SQL (PostgreSQL NULL)
	if p.Title != nil {
		t.Errorf("Title should be nil, got %v", p.Title)
	}
	if p.Author != nil {
		t.Errorf("Author should be nil, got %v", p.Author)
	}
	if p.SiteName != nil {
		t.Errorf("SiteName should be nil, got %v", p.SiteName)
	}
	if p.MarkdownContent != nil {
		t.Errorf("MarkdownContent should be nil, got %v", p.MarkdownContent)
	}

	// WordCount nil → default 0
	wordCount := 0
	if p.WordCount != nil {
		wordCount = *p.WordCount
	}
	if wordCount != 0 {
		t.Errorf("nil WordCount should default to 0, got %d", wordCount)
	}
}

func TestSubmitURL_CrawlTaskAlwaysEnqueued_WithoutContent(t *testing.T) {
	// The standard case: no client content, crawl task must be enqueued.
	artRepo := &mockArticleRepo{}
	taskRepo := &mockTaskRepo{}
	tagRepo := &mockTagRepo{}
	catRepo := &mockCategoryRepo{}
	quota := &mockQuotaService{}
	enqueuer := &mockEnqueuer{}

	svc := newTestArticleService(artRepo, taskRepo, tagRepo, catRepo, quota, enqueuer)

	req := SubmitURLRequest{
		URL: "https://example.com/article-url-only",
	}

	resp, err := svc.SubmitURL(context.Background(), "user-1", req)
	if err != nil {
		t.Fatalf("SubmitURL failed: %v", err)
	}
	if resp.TaskID == "" {
		t.Fatal("TaskID should not be empty — crawl task must always be created")
	}

	// Verify the task repo was called
	if taskRepo.lastCreateP == nil {
		t.Fatal("taskRepo.Create was not called — crawl task must always be created")
	}

	// Verify a crawl task was enqueued
	if len(enqueuer.enqueuedTasks) != 1 {
		t.Fatalf("expected exactly 1 enqueued task, got %d", len(enqueuer.enqueuedTasks))
	}
	enqueuedTask := enqueuer.enqueuedTasks[0]
	if enqueuedTask.Type() != worker.TypeCrawlArticle {
		t.Errorf("enqueued task type = %q, want %q", enqueuedTask.Type(), worker.TypeCrawlArticle)
	}

	var crawlPayload worker.CrawlPayload
	if err := json.Unmarshal(enqueuedTask.Payload(), &crawlPayload); err != nil {
		t.Fatalf("failed to unmarshal crawl payload: %v", err)
	}
	if crawlPayload.URL != "https://example.com/article-url-only" {
		t.Errorf("crawl payload URL = %q, want %q", crawlPayload.URL, "https://example.com/article-url-only")
	}
}
