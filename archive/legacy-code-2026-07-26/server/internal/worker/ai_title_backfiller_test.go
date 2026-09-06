package worker

import (
	"context"
	"strings"
	"testing"

	"folio-server/internal/client"
	"folio-server/internal/domain"
)

func TestAITitleBackfiller_UsesFirstKeyPointForManualArticleWithoutTitle(t *testing.T) {
	articleRepo := newMockAIArticleRepo()
	articleRepo.articles["art-1"] = &domain.Article{
		ID:         "art-1",
		SourceType: domain.SourceManual,
	}
	backfiller := aiTitleBackfiller{articleRepo: articleRepo}

	backfiller.backfill(context.Background(), AIProcessPayload{
		ArticleID: "art-1",
	}, &client.AnalyzeResponse{
		Summary:   "Summary fallback",
		KeyPoints: []string{"Generated from first key point", "Second point"},
	})

	if got := articleRepo.updatedTitles["art-1"]; got != "Generated from first key point" {
		t.Fatalf("updated title = %q, want first key point", got)
	}
}

func TestAITitleBackfiller_UsesTruncatedSummaryWhenNoKeyPoints(t *testing.T) {
	articleRepo := newMockAIArticleRepo()
	empty := ""
	articleRepo.articles["art-1"] = &domain.Article{
		ID:         "art-1",
		SourceType: domain.SourceManual,
		Title:      &empty,
	}
	backfiller := aiTitleBackfiller{articleRepo: articleRepo}
	summary := strings.Repeat("字", 60)

	backfiller.backfill(context.Background(), AIProcessPayload{
		ArticleID: "art-1",
	}, &client.AnalyzeResponse{Summary: summary})

	got := articleRepo.updatedTitles["art-1"]
	if len([]rune(got)) != 50 {
		t.Fatalf("updated title length = %d, want 50 runes", len([]rune(got)))
	}
}

func TestAITitleBackfiller_SkipsNonManualArticle(t *testing.T) {
	articleRepo := newMockAIArticleRepo()
	articleRepo.articles["art-1"] = &domain.Article{
		ID:         "art-1",
		SourceType: domain.SourceWeb,
	}
	backfiller := aiTitleBackfiller{articleRepo: articleRepo}

	backfiller.backfill(context.Background(), AIProcessPayload{
		ArticleID: "art-1",
	}, &client.AnalyzeResponse{
		KeyPoints: []string{"Generated"},
	})

	if _, ok := articleRepo.updatedTitles["art-1"]; ok {
		t.Fatal("title should not be updated for non-manual article")
	}
}

func TestAITitleBackfiller_SkipsManualArticleWithExistingTitle(t *testing.T) {
	articleRepo := newMockAIArticleRepo()
	title := "User title"
	articleRepo.articles["art-1"] = &domain.Article{
		ID:         "art-1",
		SourceType: domain.SourceManual,
		Title:      &title,
	}
	backfiller := aiTitleBackfiller{articleRepo: articleRepo}

	backfiller.backfill(context.Background(), AIProcessPayload{
		ArticleID: "art-1",
	}, &client.AnalyzeResponse{
		KeyPoints: []string{"Generated"},
	})

	if _, ok := articleRepo.updatedTitles["art-1"]; ok {
		t.Fatal("title should not be updated when user title exists")
	}
}
