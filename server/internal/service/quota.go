package service

import (
	"context"
	"log/slog"

	"folio-server/internal/repository"
)

type QuotaService struct {
	userRepo *repository.UserRepo
}

func NewQuotaService(userRepo *repository.UserRepo) *QuotaService {
	return &QuotaService{userRepo: userRepo}
}

func (s *QuotaService) CheckAndIncrement(ctx context.Context, userID string) error {
	newCount, err := s.userRepo.AtomicResetAndIncrement(ctx, userID)
	if err != nil {
		slog.Error("quota check failed", "user_id", userID, "error", err)
		return err
	}
	if newCount < 0 {
		slog.Info("quota exceeded", "user_id", userID)
		return ErrQuotaExceeded
	}
	slog.Debug("quota incremented", "user_id", userID, "new_count", newCount)
	return nil
}

// DecrementQuota rolls back one quota unit (e.g. when article creation fails after quota was consumed).
func (s *QuotaService) DecrementQuota(ctx context.Context, userID string) error {
	return s.userRepo.DecrementMonthCount(ctx, userID)
}
