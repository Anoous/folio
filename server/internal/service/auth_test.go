package service

import (
	"context"
	"errors"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"

	"folio-server/internal/client"
)

func TestSendEmailCode_ReturnsErrorWhenRedisPersistFails(t *testing.T) {
	addr := unavailableTCPAddr(t)
	rdb := redis.NewClient(&redis.Options{
		Addr:         addr,
		DialTimeout:  50 * time.Millisecond,
		ReadTimeout:  50 * time.Millisecond,
		WriteTimeout: 50 * time.Millisecond,
		MaxRetries:   0,
		PoolSize:     1,
	})
	defer rdb.Close()

	svc := &AuthService{
		rdb:    rdb,
		resend: client.NewResendClient("", "noreply@example.com"),
	}

	ctx, cancel := context.WithTimeout(context.Background(), 250*time.Millisecond)
	defer cancel()

	err := svc.SendEmailCode(ctx, SendCodeRequest{Email: "reader@example.com"})
	if err == nil {
		t.Fatal("SendEmailCode() error = nil, want redis persistence failure")
	}
	if !strings.Contains(err.Error(), "persist verification code") {
		t.Fatalf("SendEmailCode() error = %q, want persistence context", err)
	}
}

func TestSendEmailCode_RateLimitsSecondRequestForSameEmail(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	svc := &AuthService{
		rdb:    rdb,
		resend: client.NewResendClient("", "noreply@example.com"),
	}

	req := SendCodeRequest{Email: "reader@example.com"}
	if err := svc.SendEmailCode(context.Background(), req); err != nil {
		t.Fatalf("first SendEmailCode() error = %v, want nil", err)
	}

	err := svc.SendEmailCode(context.Background(), req)
	if !errors.Is(err, ErrCodeRateLimit) {
		t.Fatalf("second SendEmailCode() error = %v, want %v", err, ErrCodeRateLimit)
	}

	if got := mr.TTL(codeKey("reader@example.com")); got != emailCodeTTL {
		t.Fatalf("code TTL = %v, want %v", got, emailCodeTTL)
	}
	if got := mr.TTL(cooldownKey("reader@example.com")); got != emailCodeCooldownTTL {
		t.Fatalf("cooldown TTL = %v, want %v", got, emailCodeCooldownTTL)
	}
}

func unavailableTCPAddr(t *testing.T) string {
	t.Helper()

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	addr := listener.Addr().String()
	if err := listener.Close(); err != nil {
		t.Fatalf("close listener: %v", err)
	}
	return addr
}
