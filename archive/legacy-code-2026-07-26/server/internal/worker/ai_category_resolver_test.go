package worker

import (
	"context"
	"errors"
	"testing"

	"folio-server/internal/client"
	"folio-server/internal/domain"
)

type scriptedCategoryFinder struct {
	calls  []string
	errs   map[string]error
	result map[string]*domain.Category
}

func (s *scriptedCategoryFinder) FindOrCreate(ctx context.Context, slug, nameZH, nameEN string) (*domain.Category, error) {
	s.calls = append(s.calls, slug)
	if err := s.errs[slug]; err != nil {
		return nil, err
	}
	if cat := s.result[slug]; cat != nil {
		return cat, nil
	}
	return &domain.Category{ID: "cat-" + slug, Slug: slug, NameZH: nameZH, NameEN: nameEN}, nil
}

func TestAICategoryResolver_PrimarySuccess(t *testing.T) {
	finder := &scriptedCategoryFinder{
		errs:   map[string]error{},
		result: map[string]*domain.Category{},
	}
	resolver := aiCategoryResolver{categoryRepo: finder}

	cat, err := resolver.resolve(context.Background(), categoryResolverTestPayload(), &client.AnalyzeResponse{
		Category:     "tech",
		CategoryName: "Technology",
	})
	if err != nil {
		t.Fatalf("resolve() error = %v", err)
	}
	if cat.ID != "cat-tech" {
		t.Fatalf("category = %+v, want tech category", cat)
	}
	if len(finder.calls) != 1 || finder.calls[0] != "tech" {
		t.Fatalf("calls = %v, want primary only", finder.calls)
	}
}

func TestAICategoryResolver_FallsBackToOther(t *testing.T) {
	finder := &scriptedCategoryFinder{
		errs: map[string]error{
			"tech": errors.New("primary failed"),
		},
		result: map[string]*domain.Category{},
	}
	resolver := aiCategoryResolver{categoryRepo: finder}

	cat, err := resolver.resolve(context.Background(), categoryResolverTestPayload(), &client.AnalyzeResponse{
		Category:     "tech",
		CategoryName: "Technology",
	})
	if err != nil {
		t.Fatalf("resolve() error = %v", err)
	}
	if cat.ID != "cat-other" {
		t.Fatalf("category = %+v, want fallback category", cat)
	}
	if len(finder.calls) != 2 || finder.calls[0] != "tech" || finder.calls[1] != "other" {
		t.Fatalf("calls = %v, want primary then other", finder.calls)
	}
}

func TestAICategoryResolver_ReturnsFallbackError(t *testing.T) {
	finder := &scriptedCategoryFinder{
		errs: map[string]error{
			"tech":  errors.New("primary failed"),
			"other": errors.New("fallback failed"),
		},
		result: map[string]*domain.Category{},
	}
	resolver := aiCategoryResolver{categoryRepo: finder}

	_, err := resolver.resolve(context.Background(), categoryResolverTestPayload(), &client.AnalyzeResponse{
		Category:     "tech",
		CategoryName: "Technology",
	})
	if err == nil || err.Error() != "fallback failed" {
		t.Fatalf("resolve() error = %v, want fallback error", err)
	}
	if len(finder.calls) != 2 || finder.calls[0] != "tech" || finder.calls[1] != "other" {
		t.Fatalf("calls = %v, want primary then other", finder.calls)
	}
}

func categoryResolverTestPayload() AIProcessPayload {
	return AIProcessPayload{
		ArticleID: "art-1",
		TaskID:    "task-1",
		UserID:    "user-1",
	}
}
