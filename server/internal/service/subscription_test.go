package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"folio-server/internal/client"
	"folio-server/internal/domain"
)

func TestVerifyAndActivate_ActivatesMatchingAppleTransaction(t *testing.T) {
	expires := time.Now().Add(24 * time.Hour)
	apple := &fakeAppleStoreClient{
		transaction: &client.TransactionInfo{
			TransactionID:         "txn-1",
			OriginalTransactionID: "orig-1",
			ProductID:             "com.folio.app.pro.monthly",
			BundleID:              "com.folio.app",
			ExpiresDate:           &expires,
		},
	}
	users := &fakeSubscriptionUserRepo{}
	svc := NewSubscriptionService(apple, users, "com.folio.app")

	result, err := svc.VerifyAndActivate(context.Background(), "user-1", "txn-1", "com.folio.app.pro.monthly")
	if err != nil {
		t.Fatalf("VerifyAndActivate() error = %v", err)
	}

	if result.Subscription != string(domain.SubscriptionPro) {
		t.Fatalf("Subscription = %q, want %q", result.Subscription, domain.SubscriptionPro)
	}
	if len(users.updates) != 1 {
		t.Fatalf("updates = %d, want 1", len(users.updates))
	}
	update := users.updates[0]
	if update.userID != "user-1" {
		t.Fatalf("updated user = %q, want user-1", update.userID)
	}
	if update.subscription != domain.SubscriptionPro {
		t.Fatalf("updated subscription = %q, want pro", update.subscription)
	}
	if update.originalTxnID == nil || *update.originalTxnID != "orig-1" {
		t.Fatalf("original transaction = %v, want orig-1", update.originalTxnID)
	}
}

func TestVerifyAndActivate_RejectsRequestedProductMismatch(t *testing.T) {
	expires := time.Now().Add(24 * time.Hour)
	apple := &fakeAppleStoreClient{
		transaction: &client.TransactionInfo{
			TransactionID:         "txn-1",
			OriginalTransactionID: "orig-1",
			ProductID:             "com.folio.app.pro.yearly",
			BundleID:              "com.folio.app",
			ExpiresDate:           &expires,
		},
	}
	users := &fakeSubscriptionUserRepo{}
	svc := NewSubscriptionService(apple, users, "com.folio.app")

	_, err := svc.VerifyAndActivate(context.Background(), "user-1", "txn-1", "com.folio.app.pro.monthly")
	if !errors.Is(err, ErrInvalidProduct) {
		t.Fatalf("VerifyAndActivate() error = %v, want %v", err, ErrInvalidProduct)
	}
	if len(users.updates) != 0 {
		t.Fatalf("updates = %d, want 0", len(users.updates))
	}
}

func TestVerifyAndActivate_MapsAppleInvalidTransaction(t *testing.T) {
	apple := &fakeAppleStoreClient{err: client.ErrAppleTransactionNotFound}
	users := &fakeSubscriptionUserRepo{}
	svc := NewSubscriptionService(apple, users, "com.folio.app")

	_, err := svc.VerifyAndActivate(context.Background(), "user-1", "missing-txn", "com.folio.app.pro.yearly")
	if !errors.Is(err, ErrInvalidTransaction) {
		t.Fatalf("VerifyAndActivate() error = %v, want %v", err, ErrInvalidTransaction)
	}
	if len(users.updates) != 0 {
		t.Fatalf("updates = %d, want 0", len(users.updates))
	}
}

func TestValidateSubscriptionActivation(t *testing.T) {
	now := time.Date(2026, 4, 26, 10, 0, 0, 0, time.UTC)
	future := now.Add(time.Hour)
	past := now.Add(-time.Hour)

	tests := []struct {
		name      string
		txn       *client.TransactionInfo
		requested string
		bundleID  string
		wantErr   error
	}{
		{
			name: "valid",
			txn: &client.TransactionInfo{
				TransactionID:         "txn-1",
				OriginalTransactionID: "orig-1",
				ProductID:             "com.folio.app.pro.yearly",
				BundleID:              "com.folio.app",
				ExpiresDate:           &future,
			},
			requested: "com.folio.app.pro.yearly",
			bundleID:  "com.folio.app",
		},
		{
			name:      "nil transaction",
			txn:       nil,
			requested: "com.folio.app.pro.yearly",
			bundleID:  "com.folio.app",
			wantErr:   ErrInvalidTransaction,
		},
		{
			name: "missing original transaction",
			txn: &client.TransactionInfo{
				TransactionID: "txn-1",
				ProductID:     "com.folio.app.pro.yearly",
				BundleID:      "com.folio.app",
				ExpiresDate:   &future,
			},
			requested: "com.folio.app.pro.yearly",
			bundleID:  "com.folio.app",
			wantErr:   ErrInvalidTransaction,
		},
		{
			name: "unknown product",
			txn: &client.TransactionInfo{
				TransactionID:         "txn-1",
				OriginalTransactionID: "orig-1",
				ProductID:             "com.folio.app.pro.weekly",
				BundleID:              "com.folio.app",
				ExpiresDate:           &future,
			},
			requested: "com.folio.app.pro.weekly",
			bundleID:  "com.folio.app",
			wantErr:   ErrInvalidProduct,
		},
		{
			name: "bundle mismatch",
			txn: &client.TransactionInfo{
				TransactionID:         "txn-1",
				OriginalTransactionID: "orig-1",
				ProductID:             "com.folio.app.pro.yearly",
				BundleID:              "other.bundle",
				ExpiresDate:           &future,
			},
			requested: "com.folio.app.pro.yearly",
			bundleID:  "com.folio.app",
			wantErr:   ErrInvalidBundleID,
		},
		{
			name: "expired",
			txn: &client.TransactionInfo{
				TransactionID:         "txn-1",
				OriginalTransactionID: "orig-1",
				ProductID:             "com.folio.app.pro.yearly",
				BundleID:              "com.folio.app",
				ExpiresDate:           &past,
			},
			requested: "com.folio.app.pro.yearly",
			bundleID:  "com.folio.app",
			wantErr:   ErrSubscriptionExpired,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validateSubscriptionActivation(tt.txn, tt.requested, tt.bundleID, now)
			if !errors.Is(err, tt.wantErr) {
				t.Fatalf("validateSubscriptionActivation() error = %v, want %v", err, tt.wantErr)
			}
		})
	}
}

type fakeAppleStoreClient struct {
	transaction *client.TransactionInfo
	err         error
}

func (c *fakeAppleStoreClient) VerifyTransaction(_ context.Context, _ string) (*client.TransactionInfo, error) {
	if c.err != nil {
		return nil, c.err
	}
	return c.transaction, nil
}

func (c *fakeAppleStoreClient) ParseWebhookPayload(_ string) (*client.WebhookEvent, error) {
	return nil, nil
}

func (c *fakeAppleStoreClient) ParseSignedTransaction(_ string) (*client.TransactionInfo, error) {
	return nil, nil
}

type fakeSubscriptionUserRepo struct {
	updates []subscriptionUpdate
}

type subscriptionUpdate struct {
	userID        string
	subscription  domain.Subscription
	expiresAt     *time.Time
	originalTxnID *string
}

func (r *fakeSubscriptionUserRepo) UpdateSubscription(_ context.Context, userID string, subscription domain.Subscription, expiresAt *time.Time, originalTxnID *string) error {
	r.updates = append(r.updates, subscriptionUpdate{
		userID:        userID,
		subscription:  subscription,
		expiresAt:     expiresAt,
		originalTxnID: originalTxnID,
	})
	return nil
}

func (r *fakeSubscriptionUserRepo) GetByOriginalTransactionID(_ context.Context, _ string) (*domain.User, error) {
	return nil, nil
}
