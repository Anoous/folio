package service

import (
	"context"
	"testing"
	"time"

	"folio-server/internal/domain"
)

type fakeEchoStore struct {
	dueCards       []domain.EchoCard
	getDueCalls    int
	lastDueLimit   int
	resetCalls     int
	lastNextReset  time.Time
	weeklyRemember int
	weeklyTotal    int
	consecutive    int
}

func (s *fakeEchoStore) GetDueCards(_ context.Context, _ string, limit int) ([]domain.EchoCard, error) {
	s.getDueCalls++
	s.lastDueLimit = limit
	if limit > len(s.dueCards) {
		limit = len(s.dueCards)
	}
	return append([]domain.EchoCard(nil), s.dueCards[:limit]...), nil
}

func (s *fakeEchoStore) GetCardByID(_ context.Context, _, _ string) (*domain.EchoCard, error) {
	return nil, nil
}

func (s *fakeEchoStore) UpdateCard(_ context.Context, _ *domain.EchoCard) error {
	return nil
}

func (s *fakeEchoStore) CreateReview(_ context.Context, _ *domain.EchoReview) error {
	return nil
}

func (s *fakeEchoStore) IncrementEchoWeekCount(_ context.Context, _ string) error {
	return nil
}

func (s *fakeEchoStore) ResetEchoWeekCount(_ context.Context, _ string, nextReset time.Time) error {
	s.resetCalls++
	s.lastNextReset = nextReset
	return nil
}

func (s *fakeEchoStore) GetWeeklyStats(_ context.Context, _ string) (int, int, error) {
	return s.weeklyRemember, s.weeklyTotal, nil
}

func (s *fakeEchoStore) GetConsecutiveDays(_ context.Context, _ string) (int, error) {
	return s.consecutive, nil
}

type fakeEchoUserStore struct {
	user *domain.User
}

func (s *fakeEchoUserStore) GetByID(_ context.Context, _ string) (*domain.User, error) {
	return s.user, nil
}

func TestEchoServiceGetTodayCardsCapsFreeUserCardsAtRemainingQuota(t *testing.T) {
	resetAt := thisWeekMonday().AddDate(0, 0, 7)
	echoRepo := &fakeEchoStore{dueCards: []domain.EchoCard{
		{ID: "card-1"},
		{ID: "card-2"},
		{ID: "card-3"},
	}}
	users := &fakeEchoUserStore{user: &domain.User{
		ID:                "user-1",
		Subscription:      domain.SubscriptionFree,
		EchoCountThisWeek: 2,
		EchoWeekResetAt:   &resetAt,
	}}
	svc := &EchoService{echoRepo: echoRepo, userRepo: users}

	cards, remaining, weeklyCount, weeklyLimit, err := svc.GetTodayCards(context.Background(), "user-1", 5)
	if err != nil {
		t.Fatalf("GetTodayCards() error = %v", err)
	}

	if len(cards) != 1 || cards[0].ID != "card-1" {
		t.Fatalf("cards = %+v, want one due card", cards)
	}
	if echoRepo.lastDueLimit != 1 {
		t.Fatalf("due card limit = %d, want 1", echoRepo.lastDueLimit)
	}
	if remaining != 1 || weeklyCount != 2 {
		t.Fatalf("quota = remaining %d count %d, want 1 and 2", remaining, weeklyCount)
	}
	if weeklyLimit == nil || *weeklyLimit != echoFreeWeeklyLimit {
		t.Fatalf("weeklyLimit = %v, want %d", weeklyLimit, echoFreeWeeklyLimit)
	}
}

func TestEchoServiceGetTodayCardsReturnsEmptyWhenFreeQuotaExhausted(t *testing.T) {
	resetAt := thisWeekMonday().AddDate(0, 0, 7)
	echoRepo := &fakeEchoStore{dueCards: []domain.EchoCard{{ID: "card-1"}}}
	users := &fakeEchoUserStore{user: &domain.User{
		ID:                "user-1",
		Subscription:      domain.SubscriptionFree,
		EchoCountThisWeek: echoFreeWeeklyLimit,
		EchoWeekResetAt:   &resetAt,
	}}
	svc := &EchoService{echoRepo: echoRepo, userRepo: users}

	cards, remaining, weeklyCount, weeklyLimit, err := svc.GetTodayCards(context.Background(), "user-1", 5)
	if err != nil {
		t.Fatalf("GetTodayCards() error = %v", err)
	}

	if len(cards) != 0 {
		t.Fatalf("cards = %+v, want empty", cards)
	}
	if echoRepo.getDueCalls != 0 {
		t.Fatalf("GetDueCards calls = %d, want 0", echoRepo.getDueCalls)
	}
	if remaining != 0 || weeklyCount != echoFreeWeeklyLimit {
		t.Fatalf("quota = remaining %d count %d, want 0 and limit", remaining, weeklyCount)
	}
	if weeklyLimit == nil || *weeklyLimit != echoFreeWeeklyLimit {
		t.Fatalf("weeklyLimit = %v, want %d", weeklyLimit, echoFreeWeeklyLimit)
	}
}

func TestEchoServiceGetTodayCardsResetsExpiredFreeWeek(t *testing.T) {
	expiredReset := thisWeekMonday().Add(-time.Hour)
	echoRepo := &fakeEchoStore{dueCards: []domain.EchoCard{
		{ID: "card-1"},
		{ID: "card-2"},
		{ID: "card-3"},
		{ID: "card-4"},
	}}
	users := &fakeEchoUserStore{user: &domain.User{
		ID:                "user-1",
		Subscription:      domain.SubscriptionFree,
		EchoCountThisWeek: echoFreeWeeklyLimit,
		EchoWeekResetAt:   &expiredReset,
	}}
	svc := &EchoService{echoRepo: echoRepo, userRepo: users}

	cards, remaining, weeklyCount, _, err := svc.GetTodayCards(context.Background(), "user-1", 5)
	if err != nil {
		t.Fatalf("GetTodayCards() error = %v", err)
	}

	if echoRepo.resetCalls != 1 {
		t.Fatalf("reset calls = %d, want 1", echoRepo.resetCalls)
	}
	if len(cards) != echoFreeWeeklyLimit {
		t.Fatalf("cards = %d, want weekly limit", len(cards))
	}
	if echoRepo.lastDueLimit != echoFreeWeeklyLimit {
		t.Fatalf("due card limit = %d, want %d", echoRepo.lastDueLimit, echoFreeWeeklyLimit)
	}
	if remaining != echoFreeWeeklyLimit || weeklyCount != 0 {
		t.Fatalf("quota = remaining %d count %d, want reset values", remaining, weeklyCount)
	}
}

func TestEchoServiceGetTodayCardsDoesNotCapProUsers(t *testing.T) {
	echoRepo := &fakeEchoStore{dueCards: []domain.EchoCard{
		{ID: "card-1"},
		{ID: "card-2"},
		{ID: "card-3"},
		{ID: "card-4"},
	}}
	users := &fakeEchoUserStore{user: &domain.User{ID: "user-1", Subscription: domain.SubscriptionPro}}
	svc := &EchoService{echoRepo: echoRepo, userRepo: users}

	cards, remaining, weeklyCount, weeklyLimit, err := svc.GetTodayCards(context.Background(), "user-1", 5)
	if err != nil {
		t.Fatalf("GetTodayCards() error = %v", err)
	}

	if len(cards) != 4 {
		t.Fatalf("cards = %d, want all due cards", len(cards))
	}
	if echoRepo.lastDueLimit != 5 {
		t.Fatalf("due card limit = %d, want requested limit", echoRepo.lastDueLimit)
	}
	if remaining != 4 || weeklyCount != 0 || weeklyLimit != nil {
		t.Fatalf("quota = remaining %d count %d limit %v, want pro values", remaining, weeklyCount, weeklyLimit)
	}
}
