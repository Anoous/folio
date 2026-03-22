package service

import (
	"context"
	"fmt"
	"math"
	"time"

	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

const echoFreeWeeklyLimit = 3

type EchoService struct {
	echoRepo *repository.EchoRepo
	userRepo *repository.UserRepo
}

func NewEchoService(echoRepo *repository.EchoRepo, userRepo *repository.UserRepo) *EchoService {
	return &EchoService{
		echoRepo: echoRepo,
		userRepo: userRepo,
	}
}

// GetTodayCards returns due echo cards for the user, applying Free-tier weekly quota.
// Returns cards, remaining quota, weeklyCount, and weeklyLimit (nil = unlimited).
func (s *EchoService) GetTodayCards(ctx context.Context, userID string, limit int) (
	cards []domain.EchoCard, remaining int, weeklyCount int, weeklyLimit *int, err error,
) {
	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return nil, 0, 0, nil, fmt.Errorf("get user: %w", err)
	}
	if user == nil {
		return nil, 0, 0, nil, ErrNotFound
	}

	isFree := user.Subscription == domain.SubscriptionFree

	if isFree {
		// Check if weekly quota needs resetting
		thisMonday := thisWeekMonday()
		if user.EchoWeekResetAt == nil || user.EchoWeekResetAt.Before(thisMonday) {
			nextMonday := thisMonday.AddDate(0, 0, 7)
			if resetErr := s.echoRepo.ResetEchoWeekCount(ctx, userID, nextMonday); resetErr != nil {
				return nil, 0, 0, nil, fmt.Errorf("reset echo week count: %w", resetErr)
			}
			user.EchoCountThisWeek = 0
		}

		if user.EchoCountThisWeek >= echoFreeWeeklyLimit {
			wl := echoFreeWeeklyLimit
			return []domain.EchoCard{}, 0, user.EchoCountThisWeek, &wl, nil
		}
	}

	cards, err = s.echoRepo.GetDueCards(ctx, userID, limit)
	if err != nil {
		return nil, 0, 0, nil, fmt.Errorf("get due cards: %w", err)
	}

	if isFree {
		wl := echoFreeWeeklyLimit
		remaining = echoFreeWeeklyLimit - user.EchoCountThisWeek
		return cards, remaining, user.EchoCountThisWeek, &wl, nil
	}

	// Pro: unlimited
	return cards, len(cards), 0, nil, nil
}

// ReviewResult holds the outcome of a single SM-2 review submission.
type ReviewResult struct {
	NextReviewAt time.Time
	IntervalDays int
	ReviewCount  int
	CorrectCount int
	Streak       domain.EchoStreak
}

// SubmitReview applies SM-2 to the card, records the review, increments weekly quota,
// and returns the updated review result with streak info.
func (s *EchoService) SubmitReview(ctx context.Context, userID, cardID string,
	result domain.EchoReviewResult, responseTimeMs *int) (*ReviewResult, error) {

	// 1. Get card (verifies ownership)
	card, err := s.echoRepo.GetCardByID(ctx, cardID, userID)
	if err != nil {
		return nil, fmt.Errorf("get card: %w", err)
	}
	if card == nil {
		return nil, ErrNotFound
	}

	// 2. Apply SM-2 algorithm
	updateSM2(card, result)

	// 3. Persist updated card
	if err := s.echoRepo.UpdateCard(ctx, card); err != nil {
		return nil, fmt.Errorf("update card: %w", err)
	}

	// 4. Record review
	review := &domain.EchoReview{
		CardID:         cardID,
		UserID:         userID,
		Result:         result,
		ResponseTimeMs: responseTimeMs,
	}
	if err := s.echoRepo.CreateReview(ctx, review); err != nil {
		return nil, fmt.Errorf("create review: %w", err)
	}

	// 5. Increment weekly count (best-effort; don't fail the review on quota error)
	if incrErr := s.echoRepo.IncrementEchoWeekCount(ctx, userID); incrErr != nil {
		// Non-fatal: log if a logger is available; for now just continue.
		_ = incrErr
	}

	// 6. Build streak
	streak, err := s.buildStreak(ctx, userID)
	if err != nil {
		// Non-fatal: return empty streak rather than failing the review
		streak = domain.EchoStreak{}
	}

	return &ReviewResult{
		NextReviewAt: card.NextReviewAt,
		IntervalDays: card.IntervalDays,
		ReviewCount:  card.ReviewCount,
		CorrectCount: card.CorrectCount,
		Streak:       streak,
	}, nil
}

// buildStreak fetches weekly stats and consecutive days, then formats the display string.
func (s *EchoService) buildStreak(ctx context.Context, userID string) (domain.EchoStreak, error) {
	remembered, total, err := s.echoRepo.GetWeeklyStats(ctx, userID)
	if err != nil {
		return domain.EchoStreak{}, fmt.Errorf("get weekly stats: %w", err)
	}

	days, err := s.echoRepo.GetConsecutiveDays(ctx, userID)
	if err != nil {
		return domain.EchoStreak{}, fmt.Errorf("get consecutive days: %w", err)
	}

	rate := 0
	if total > 0 {
		rate = remembered * 100 / total
	}

	display := fmt.Sprintf("本周回忆率 %d%% · 已连续 %d 天", rate, days)

	return domain.EchoStreak{
		WeeklyRate:      rate,
		ConsecutiveDays: days,
		Display:         display,
	}, nil
}

// updateSM2 applies the SM-2 spaced repetition algorithm to a card in place.
func updateSM2(card *domain.EchoCard, result domain.EchoReviewResult) {
	card.ReviewCount++
	if result == domain.EchoRemembered {
		card.CorrectCount++
		switch card.ReviewCount {
		case 1:
			card.IntervalDays = 1
		case 2:
			card.IntervalDays = 3
		default:
			card.IntervalDays = int(math.Round(float64(card.IntervalDays) * card.EaseFactor))
		}
		card.EaseFactor = math.Min(3.0, card.EaseFactor+0.1)
	} else {
		card.IntervalDays = 1
		card.EaseFactor = math.Max(1.3, card.EaseFactor-0.2)
	}
	card.NextReviewAt = time.Now().Add(time.Duration(card.IntervalDays) * 24 * time.Hour)
}

// thisWeekMonday returns Monday 00:00:00 UTC of the current week.
func thisWeekMonday() time.Time {
	now := time.Now().UTC()
	weekday := int(now.Weekday())
	if weekday == 0 {
		weekday = 7 // treat Sunday as 7
	}
	daysBack := weekday - 1
	return time.Date(now.Year(), now.Month(), now.Day()-daysBack, 0, 0, 0, 0, time.UTC)
}
