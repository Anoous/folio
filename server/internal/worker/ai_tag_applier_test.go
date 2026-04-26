package worker

import (
	"context"
	"errors"
	"testing"

	"folio-server/internal/domain"
)

type recordingAITagRepo struct {
	createCalls []struct {
		userID        string
		name          string
		isAIGenerated bool
	}
	attachCalls []struct {
		articleID string
		tagID     string
	}
	createErrs map[string]error
	attachErrs map[string]error
}

func (r *recordingAITagRepo) Create(ctx context.Context, userID, name string, isAIGenerated bool) (*domain.Tag, error) {
	r.createCalls = append(r.createCalls, struct {
		userID        string
		name          string
		isAIGenerated bool
	}{userID: userID, name: name, isAIGenerated: isAIGenerated})
	if err := r.createErrs[name]; err != nil {
		return nil, err
	}
	return &domain.Tag{ID: "tag-" + name, Name: name}, nil
}

func (r *recordingAITagRepo) AttachToArticle(ctx context.Context, articleID, tagID string) error {
	r.attachCalls = append(r.attachCalls, struct {
		articleID string
		tagID     string
	}{articleID: articleID, tagID: tagID})
	return r.attachErrs[tagID]
}

func TestAITagApplier_CreatesAndAttachesGeneratedTags(t *testing.T) {
	tagRepo := &recordingAITagRepo{
		createErrs: map[string]error{},
		attachErrs: map[string]error{},
	}
	applier := aiTagApplier{tagRepo: tagRepo}

	applier.apply(context.Background(), tagApplierTestPayload(), []string{"go", "backend"})

	if len(tagRepo.createCalls) != 2 {
		t.Fatalf("create calls = %d, want 2", len(tagRepo.createCalls))
	}
	if tagRepo.createCalls[0].userID != "user-1" || tagRepo.createCalls[0].name != "go" || !tagRepo.createCalls[0].isAIGenerated {
		t.Fatalf("first create call = %+v, want generated user tag", tagRepo.createCalls[0])
	}
	if len(tagRepo.attachCalls) != 2 {
		t.Fatalf("attach calls = %d, want 2", len(tagRepo.attachCalls))
	}
	if tagRepo.attachCalls[1].articleID != "art-1" || tagRepo.attachCalls[1].tagID != "tag-backend" {
		t.Fatalf("second attach call = %+v, want backend attached", tagRepo.attachCalls[1])
	}
}

func TestAITagApplier_SkipsAttachWhenCreateFails(t *testing.T) {
	tagRepo := &recordingAITagRepo{
		createErrs: map[string]error{
			"bad": errors.New("create failed"),
		},
		attachErrs: map[string]error{},
	}
	applier := aiTagApplier{tagRepo: tagRepo}

	applier.apply(context.Background(), tagApplierTestPayload(), []string{"bad", "good"})

	if len(tagRepo.createCalls) != 2 {
		t.Fatalf("create calls = %d, want 2 attempts", len(tagRepo.createCalls))
	}
	if len(tagRepo.attachCalls) != 1 || tagRepo.attachCalls[0].tagID != "tag-good" {
		t.Fatalf("attach calls = %+v, want only successful tag attached", tagRepo.attachCalls)
	}
}

func TestAITagApplier_AttachErrorsAreNonFatal(t *testing.T) {
	tagRepo := &recordingAITagRepo{
		createErrs: map[string]error{},
		attachErrs: map[string]error{
			"tag-go": errors.New("attach failed"),
		},
	}
	applier := aiTagApplier{tagRepo: tagRepo}

	applier.apply(context.Background(), tagApplierTestPayload(), []string{"go", "backend"})

	if len(tagRepo.attachCalls) != 2 {
		t.Fatalf("attach calls = %d, want both attach attempts", len(tagRepo.attachCalls))
	}
}

func tagApplierTestPayload() AIProcessPayload {
	return AIProcessPayload{
		ArticleID: "art-1",
		UserID:    "user-1",
	}
}
