package service

import (
	"context"

	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

type TagService struct {
	tagRepo *repository.TagRepo
}

func NewTagService(tagRepo *repository.TagRepo) *TagService {
	return &TagService{tagRepo: tagRepo}
}

func (s *TagService) ListByUser(ctx context.Context, userID string) ([]domain.Tag, error) {
	return s.tagRepo.ListByUser(ctx, userID)
}

func (s *TagService) Create(ctx context.Context, userID, name string) (*domain.Tag, error) {
	return s.tagRepo.Create(ctx, userID, name, false)
}

func (s *TagService) Delete(ctx context.Context, userID, tagID string) error {
	tag, err := s.tagRepo.GetByID(ctx, tagID)
	if err != nil {
		return err
	}
	if tag == nil {
		return ErrNotFound
	}
	if tag.UserID == nil || *tag.UserID != userID {
		return ErrForbidden
	}
	return s.tagRepo.Delete(ctx, tagID)
}
