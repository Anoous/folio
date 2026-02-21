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
	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return err
	}
	if user == nil {
		return ErrNotFound
	}

	// Reset if new month
	if user.QuotaResetAt != nil {
		now := time.Now()
		resetAt := *user.QuotaResetAt
		if now.Year() != resetAt.Year() || now.Month() != resetAt.Month() {
			if err := s.userRepo.ResetMonthCount(ctx, userID); err != nil {
				return err
			}
			user.CurrentMonthCount = 0
		}
	}

	if user.CurrentMonthCount >= user.MonthlyQuota {
		return ErrQuotaExceeded
	}

	return s.userRepo.IncrementMonthCount(ctx, userID)
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
