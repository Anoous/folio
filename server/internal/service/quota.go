package service

import (
	"context"
	"time"

	"folio-server/internal/repository"
)

type QuotaService struct {
	userRepo *repository.UserRepo
}

func NewQuotaService(userRepo *repository.UserRepo) *QuotaService {
	return &QuotaService{userRepo: userRepo}
}

type QuotaInfo struct {
	Limit   int `json:"limit"`
	Used    int `json:"used"`
	ResetAt *time.Time `json:"reset_at,omitempty"`
}

func (s *QuotaService) CheckAndIncrement(ctx context.Context, userID string) error {
	newCount, err := s.userRepo.AtomicResetAndIncrement(ctx, userID)
	if err != nil {
		return err
	}
	if newCount < 0 {
		return ErrQuotaExceeded
	}
	return nil
}

// DecrementQuota rolls back one quota unit (e.g. when article creation fails after quota was consumed).
func (s *QuotaService) DecrementQuota(ctx context.Context, userID string) error {
	return s.userRepo.DecrementMonthCount(ctx, userID)
}

func (s *QuotaService) GetQuotaInfo(ctx context.Context, userID string) (*QuotaInfo, error) {
	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	if user == nil {
		return nil, ErrNotFound
	}

	return &QuotaInfo{
		Limit:   user.MonthlyQuota,
		Used:    user.CurrentMonthCount,
		ResetAt: user.QuotaResetAt,
	}, nil
}
