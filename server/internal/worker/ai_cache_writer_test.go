package worker

import (
	"context"
	"strings"
	"testing"

	"folio-server/internal/client"
	"folio-server/internal/domain"
)

type recordingAIContentCacheRepo struct {
	upserts []*domain.ContentCache
}

func (r *recordingAIContentCacheRepo) Upsert(ctx context.Context, cache *domain.ContentCache) error {
	r.upserts = append(r.upserts, cache)
	return nil
}

func TestAICacheWriter_WritesCacheForWorthyArticle(t *testing.T) {
	stringPtr := func(s string) *string { return &s }
	articleRepo := newMockAIArticleRepo()
	markdown := strings.Repeat("cache-worthy content ", 12)
	articleRepo.articles["art-1"] = &domain.Article{
		ID:              "art-1",
		URL:             stringPtr("https://example.com/article"),
		Title:           stringPtr("Article Title"),
		Author:          stringPtr("Author"),
		SiteName:        stringPtr("Example"),
		FaviconURL:      stringPtr("https://example.com/favicon.ico"),
		CoverImageURL:   stringPtr("https://example.com/cover.jpg"),
		MarkdownContent: &markdown,
		WordCount:       42,
		Language:        stringPtr("en"),
	}
	cacheRepo := &recordingAIContentCacheRepo{}
	writer := aiCacheWriter{articleRepo: articleRepo, cacheRepo: cacheRepo}

	writer.write(context.Background(), AIProcessPayload{
		ArticleID: "art-1",
	}, &client.AnalyzeResponse{
		Category:   "tech",
		Summary:    "Summary",
		KeyPoints:  []string{"point 1", "point 2"},
		Confidence: 0.91,
		Tags:       []string{"go", "backend"},
	})

	if len(cacheRepo.upserts) != 1 {
		t.Fatalf("cache upserts = %d, want 1", len(cacheRepo.upserts))
	}
	cache := cacheRepo.upserts[0]
	if cache.URL != "https://example.com/article" || cache.WordCount != 42 {
		t.Fatalf("cache article fields = %+v, want article mapping", cache)
	}
	if cache.CategorySlug == nil || *cache.CategorySlug != "tech" {
		t.Fatalf("CategorySlug = %v, want tech", cache.CategorySlug)
	}
	if cache.Summary == nil || *cache.Summary != "Summary" {
		t.Fatalf("Summary = %v, want Summary", cache.Summary)
	}
	if cache.AIConfidence == nil || *cache.AIConfidence != 0.91 {
		t.Fatalf("AIConfidence = %v, want 0.91", cache.AIConfidence)
	}
	if len(cache.AITagNames) != 2 || cache.AITagNames[1] != "backend" {
		t.Fatalf("AITagNames = %v, want AI tags", cache.AITagNames)
	}
	if cache.AIAnalyzedAt == nil {
		t.Fatal("AIAnalyzedAt should be set")
	}
}

func TestAICacheWriter_SkipsShortContent(t *testing.T) {
	stringPtr := func(s string) *string { return &s }
	articleRepo := newMockAIArticleRepo()
	markdown := "too short"
	articleRepo.articles["art-1"] = &domain.Article{
		ID:              "art-1",
		URL:             stringPtr("https://example.com/article"),
		MarkdownContent: &markdown,
	}
	cacheRepo := &recordingAIContentCacheRepo{}
	writer := aiCacheWriter{articleRepo: articleRepo, cacheRepo: cacheRepo}

	writer.write(context.Background(), AIProcessPayload{
		ArticleID: "art-1",
	}, &client.AnalyzeResponse{Confidence: 0.91})

	if len(cacheRepo.upserts) != 0 {
		t.Fatalf("cache upserts = %d, want 0", len(cacheRepo.upserts))
	}
}

func TestAICacheWriter_NilCacheRepoIsNoop(t *testing.T) {
	writer := aiCacheWriter{articleRepo: newMockAIArticleRepo()}

	writer.write(context.Background(), AIProcessPayload{
		ArticleID: "art-1",
	}, &client.AnalyzeResponse{Confidence: 0.91})
}
