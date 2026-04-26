package worker

import (
	"context"
	"encoding/json"
	"reflect"
	"testing"
	"time"

	"github.com/hibiken/asynq"

	"folio-server/internal/domain"
)

type recordingCacheTagRepo struct {
	createCalls []struct {
		userID        string
		name          string
		isAIGenerated bool
	}
	attachCalls []struct {
		articleID string
		tagID     string
	}
}

func (r *recordingCacheTagRepo) Create(ctx context.Context, userID, name string, isAIGenerated bool) (*domain.Tag, error) {
	r.createCalls = append(r.createCalls, struct {
		userID        string
		name          string
		isAIGenerated bool
	}{userID: userID, name: name, isAIGenerated: isAIGenerated})
	return &domain.Tag{ID: "tag-" + name, Name: name}, nil
}

func (r *recordingCacheTagRepo) AttachToArticle(ctx context.Context, articleID, tagID string) error {
	r.attachCalls = append(r.attachCalls, struct {
		articleID string
		tagID     string
	}{articleID: articleID, tagID: tagID})
	return nil
}

func TestCrawlCacheHandler_FullHitCopiesResultsAndFinishesTask(t *testing.T) {
	markdown := "# Cached Article\n\nLong enough content to count as cached content."
	summary := "Cached summary"
	confidence := 0.82
	articleRepo := &mockCrawlArticleRepo{}
	taskRepo := &mockCrawlTaskRepo{}
	enqueuer := &mockCrawlEnqueuer{}
	tagRepo := &recordingCacheTagRepo{}
	handler := crawlCacheHandler{
		articleRepo:  articleRepo,
		taskRepo:     taskRepo,
		aiHandoff:    crawlAIHandoff{taskRepo: taskRepo, asynqClient: enqueuer},
		tagRepo:      tagRepo,
		categoryRepo: &mockCrawlCategoryRepo{},
	}

	handled, err := handler.handle(context.Background(), CrawlPayload{
		ArticleID: "art-1",
		TaskID:    "task-1",
		UserID:    "user-1",
	}, &domain.ContentCache{
		Title:           strPtr("Cached Title"),
		Author:          strPtr("Cached Author"),
		SiteName:        strPtr("Cached Site"),
		FaviconURL:      strPtr("https://example.com/favicon.ico"),
		CoverImageURL:   strPtr("https://example.com/cover.jpg"),
		MarkdownContent: &markdown,
		Language:        strPtr("en"),
		CategorySlug:    strPtr("tech"),
		Summary:         &summary,
		KeyPoints:       []string{"point 1", "point 2"},
		AIConfidence:    &confidence,
		AITagNames:      []string{"go", "backend"},
	}, time.Now())
	if err != nil {
		t.Fatalf("handle() error = %v", err)
	}
	if !handled {
		t.Fatal("handle() handled = false, want true")
	}

	if len(enqueuer.enqueuedTasks) != 0 {
		t.Fatalf("enqueued tasks = %d, want 0", len(enqueuer.enqueuedTasks))
	}
	if len(articleRepo.updateCrawlCalls) != 1 {
		t.Fatalf("UpdateCrawlResult calls = %d, want 1", len(articleRepo.updateCrawlCalls))
	}
	crawl := articleRepo.updateCrawlCalls[0]
	if crawl.Title != "Cached Title" || crawl.Markdown != markdown || crawl.FaviconURL != "https://example.com/favicon.ico" {
		t.Fatalf("cached crawl result = %+v, want copied cache fields", crawl)
	}

	if len(articleRepo.updateAIResultCalls) != 1 {
		t.Fatalf("UpdateAIResult calls = %d, want 1", len(articleRepo.updateAIResultCalls))
	}
	ai := articleRepo.updateAIResultCalls[0]
	if ai.CategoryID != "cat-tech" || ai.Summary != summary || ai.Confidence != confidence || ai.Language != "en" {
		t.Fatalf("cached AI result = %+v, want copied cache fields", ai)
	}
	if !reflect.DeepEqual(ai.KeyPoints, []string{"point 1", "point 2"}) {
		t.Fatalf("AI key points = %v, want cached points", ai.KeyPoints)
	}

	if len(articleRepo.updateStatusCalls) != 1 || articleRepo.updateStatusCalls[0].Status != domain.ArticleStatusReady {
		t.Fatalf("UpdateStatus calls = %+v, want ready", articleRepo.updateStatusCalls)
	}
	if !reflect.DeepEqual(taskRepo.setAIFinishedCalls, []string{"task-1"}) {
		t.Fatalf("SetAIFinished calls = %v, want [task-1]", taskRepo.setAIFinishedCalls)
	}
	if len(taskRepo.setCrawlFinishedCalls) != 0 {
		t.Fatalf("SetCrawlFinished calls = %v, want none", taskRepo.setCrawlFinishedCalls)
	}
	if len(tagRepo.createCalls) != 2 || tagRepo.createCalls[0].name != "go" || !tagRepo.createCalls[0].isAIGenerated {
		t.Fatalf("tag create calls = %+v, want generated cached tags", tagRepo.createCalls)
	}
	if len(tagRepo.attachCalls) != 2 || tagRepo.attachCalls[1].tagID != "tag-backend" {
		t.Fatalf("tag attach calls = %+v, want cached tags attached", tagRepo.attachCalls)
	}
}

func TestCrawlCacheHandler_PartialHitCopiesContentAndRoutesToAI(t *testing.T) {
	markdown := "# Cached Article\n\nContent exists but AI has not run yet."
	events := []string{}
	articleRepo := &mockCrawlArticleRepo{}
	taskRepo := &mockCrawlTaskRepo{
		setCrawlFinishedFn: func(ctx context.Context, id string) error {
			events = append(events, "finish:"+id)
			return nil
		},
	}
	enqueuer := &mockCrawlEnqueuer{
		enqueueFn: func(ctx context.Context, task *asynq.Task, opts ...asynq.Option) (*asynq.TaskInfo, error) {
			events = append(events, "enqueue:"+task.Type())
			return &asynq.TaskInfo{}, nil
		},
	}
	handler := crawlCacheHandler{
		articleRepo: articleRepo,
		taskRepo:    taskRepo,
		aiHandoff:   crawlAIHandoff{taskRepo: taskRepo, asynqClient: enqueuer},
	}

	handled, err := handler.handle(context.Background(), CrawlPayload{
		ArticleID: "art-1",
		TaskID:    "task-1",
		UserID:    "user-1",
	}, &domain.ContentCache{
		Title:           strPtr("Cached Title"),
		Author:          strPtr("Cached Author"),
		SiteName:        strPtr("Cached Site"),
		MarkdownContent: &markdown,
		Language:        strPtr("en"),
	}, time.Now())
	if err != nil {
		t.Fatalf("handle() error = %v", err)
	}
	if !handled {
		t.Fatal("handle() handled = false, want true")
	}

	if len(articleRepo.updateCrawlCalls) != 1 {
		t.Fatalf("UpdateCrawlResult calls = %d, want 1", len(articleRepo.updateCrawlCalls))
	}
	if len(articleRepo.updateAIResultCalls) != 0 {
		t.Fatalf("UpdateAIResult calls = %d, want 0", len(articleRepo.updateAIResultCalls))
	}
	if len(articleRepo.updateStatusCalls) != 0 {
		t.Fatalf("UpdateStatus calls = %d, want 0", len(articleRepo.updateStatusCalls))
	}
	if !reflect.DeepEqual(events, []string{"finish:task-1", "enqueue:" + TypeAIProcess}) {
		t.Fatalf("events = %v, want finish before enqueue", events)
	}
	if len(enqueuer.enqueuedTasks) != 1 {
		t.Fatalf("enqueued tasks = %d, want 1", len(enqueuer.enqueuedTasks))
	}

	var payload AIProcessPayload
	if err := json.Unmarshal(enqueuer.enqueuedTasks[0].Payload(), &payload); err != nil {
		t.Fatalf("unmarshal AI payload: %v", err)
	}
	if payload.Title != "Cached Title" || payload.Markdown != markdown || payload.Source != "Cached Site" || payload.Author != "Cached Author" {
		t.Fatalf("AI payload = %+v, want cached content fields", payload)
	}
	if len(taskRepo.setAIFinishedCalls) != 0 {
		t.Fatalf("SetAIFinished calls = %v, want none", taskRepo.setAIFinishedCalls)
	}
}

func TestCrawlCacheHandler_EmptyCacheEntryIsNotHandled(t *testing.T) {
	articleRepo := &mockCrawlArticleRepo{}
	taskRepo := &mockCrawlTaskRepo{}
	enqueuer := &mockCrawlEnqueuer{}
	handler := crawlCacheHandler{
		articleRepo: articleRepo,
		taskRepo:    taskRepo,
		aiHandoff:   crawlAIHandoff{taskRepo: taskRepo, asynqClient: enqueuer},
	}

	handled, err := handler.handle(context.Background(), CrawlPayload{
		ArticleID: "art-1",
		TaskID:    "task-1",
		UserID:    "user-1",
	}, &domain.ContentCache{URL: "https://example.com/empty"}, time.Now())
	if err != nil {
		t.Fatalf("handle() error = %v", err)
	}
	if handled {
		t.Fatal("handle() handled = true, want false")
	}
	if len(articleRepo.updateCrawlCalls) != 0 || len(enqueuer.enqueuedTasks) != 0 || len(taskRepo.setAIFinishedCalls) != 0 {
		t.Fatalf("unexpected side effects: crawl=%d enqueued=%d aiFinished=%d",
			len(articleRepo.updateCrawlCalls), len(enqueuer.enqueuedTasks), len(taskRepo.setAIFinishedCalls))
	}
}
