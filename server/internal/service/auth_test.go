package service

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"

	"folio-server/internal/client"
	"folio-server/internal/domain"
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

func TestGenerateEmailCode_FormatsSixDigits(t *testing.T) {
	code, err := generateEmailCode(bytes.NewReader([]byte{0, 0, 42}))
	if err != nil {
		t.Fatalf("generateEmailCode() error = %v", err)
	}
	if code != "000042" {
		t.Fatalf("generateEmailCode() = %q, want %q", code, "000042")
	}
}

func TestGenerateEmailCode_ReturnsEntropyErrors(t *testing.T) {
	_, err := generateEmailCode(failingReader{})
	if err == nil {
		t.Fatal("generateEmailCode() error = nil, want entropy error")
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

type failingReader struct{}

func (failingReader) Read(_ []byte) (int, error) {
	return 0, errors.New("entropy unavailable")
}

func TestIssueTokenPair_PersistsRefreshSession(t *testing.T) {
	userRepo := &fakeAuthUserRepo{}
	sessionRepo := newFakeRefreshSessionRepo()
	svc := &AuthService{
		userRepo:    userRepo,
		sessionRepo: sessionRepo,
		jwtSecret:   []byte("01234567890123456789012345678901"),
		resend:      client.NewResendClient("", "noreply@example.com"),
	}

	user := &domain.User{ID: "user-1"}

	resp, err := svc.issueTokenPair(context.Background(), user)
	if err != nil {
		t.Fatalf("issueTokenPair() error = %v", err)
	}

	if resp.RefreshToken == "" {
		t.Fatal("issueTokenPair() returned empty refresh token")
	}

	sessionID, tokenHash := mustParseRefreshToken(t, resp.RefreshToken)
	session, ok := sessionRepo.sessions[sessionID]
	if !ok {
		t.Fatalf("session %q not persisted", sessionID)
	}

	if session.UserID != user.ID {
		t.Fatalf("session user_id = %q, want %q", session.UserID, user.ID)
	}
	if session.TokenHash != tokenHash {
		t.Fatalf("session token_hash = %q, want %q", session.TokenHash, tokenHash)
	}
	if _, err := svc.ValidateAccessToken(resp.AccessToken); err != nil {
		t.Fatalf("ValidateAccessToken() error = %v", err)
	}
}

func TestRefreshToken_RotatesSessionAndRevokesOnReuse(t *testing.T) {
	userRepo := &fakeAuthUserRepo{
		users: map[string]*domain.User{
			"user-1": {ID: "user-1"},
		},
	}
	sessionRepo := newFakeRefreshSessionRepo()
	svc := &AuthService{
		userRepo:    userRepo,
		sessionRepo: sessionRepo,
		jwtSecret:   []byte("01234567890123456789012345678901"),
	}

	initial, err := svc.issueTokenPair(context.Background(), userRepo.users["user-1"])
	if err != nil {
		t.Fatalf("issueTokenPair() error = %v", err)
	}

	rotated, err := svc.RefreshToken(context.Background(), initial.RefreshToken)
	if err != nil {
		t.Fatalf("RefreshToken() first error = %v", err)
	}
	if rotated.RefreshToken == initial.RefreshToken {
		t.Fatal("RefreshToken() did not rotate refresh token")
	}

	if _, err := svc.RefreshToken(context.Background(), initial.RefreshToken); !errors.Is(err, ErrForbidden) {
		t.Fatalf("RefreshToken() with stale token error = %v, want %v", err, ErrForbidden)
	}

	if _, err := svc.RefreshToken(context.Background(), rotated.RefreshToken); !errors.Is(err, ErrForbidden) {
		t.Fatalf("RefreshToken() after reuse revoke error = %v, want %v", err, ErrForbidden)
	}
}

func TestRefreshToken_WrongSecretForKnownSessionDoesNotRevoke(t *testing.T) {
	userRepo := &fakeAuthUserRepo{
		users: map[string]*domain.User{
			"user-1": {ID: "user-1"},
		},
	}
	sessionRepo := newFakeRefreshSessionRepo()
	svc := &AuthService{
		userRepo:    userRepo,
		sessionRepo: sessionRepo,
		jwtSecret:   []byte("01234567890123456789012345678901"),
	}

	initial, err := svc.issueTokenPair(context.Background(), userRepo.users["user-1"])
	if err != nil {
		t.Fatalf("issueTokenPair() error = %v", err)
	}

	sessionID, _ := mustParseRefreshToken(t, initial.RefreshToken)
	wrongToken, _, err := generateRefreshToken(sessionID)
	if err != nil {
		t.Fatalf("generateRefreshToken() error = %v", err)
	}

	if _, err := svc.RefreshToken(context.Background(), wrongToken); !errors.Is(err, ErrForbidden) {
		t.Fatalf("RefreshToken() with wrong secret error = %v, want %v", err, ErrForbidden)
	}
	if sessionRepo.sessions[sessionID].RevokedAt != nil {
		t.Fatal("RefreshToken() with wrong secret revoked the session")
	}

	if _, err := svc.RefreshToken(context.Background(), initial.RefreshToken); err != nil {
		t.Fatalf("RefreshToken() with original token after wrong secret error = %v", err)
	}
}

func TestRefreshToken_RejectsExpiredSession(t *testing.T) {
	userRepo := &fakeAuthUserRepo{
		users: map[string]*domain.User{
			"user-1": {ID: "user-1"},
		},
	}
	sessionRepo := newFakeRefreshSessionRepo()
	svc := &AuthService{
		userRepo:    userRepo,
		sessionRepo: sessionRepo,
		jwtSecret:   []byte("01234567890123456789012345678901"),
	}

	initial, err := svc.issueTokenPair(context.Background(), userRepo.users["user-1"])
	if err != nil {
		t.Fatalf("issueTokenPair() error = %v", err)
	}

	sessionID, _ := mustParseRefreshToken(t, initial.RefreshToken)
	session := sessionRepo.sessions[sessionID]
	expiredAt := time.Now().Add(-time.Minute)
	session.ExpiresAt = expiredAt
	sessionRepo.sessions[sessionID] = session

	if _, err := svc.RefreshToken(context.Background(), initial.RefreshToken); !errors.Is(err, ErrForbidden) {
		t.Fatalf("RefreshToken() error = %v, want %v", err, ErrForbidden)
	}
}

func TestLogout_RevokesRefreshSession(t *testing.T) {
	userRepo := &fakeAuthUserRepo{
		users: map[string]*domain.User{
			"user-1": {ID: "user-1"},
		},
	}
	sessionRepo := newFakeRefreshSessionRepo()
	svc := &AuthService{
		userRepo:    userRepo,
		sessionRepo: sessionRepo,
		jwtSecret:   []byte("01234567890123456789012345678901"),
	}

	initial, err := svc.issueTokenPair(context.Background(), userRepo.users["user-1"])
	if err != nil {
		t.Fatalf("issueTokenPair() error = %v", err)
	}

	if err := svc.Logout(context.Background(), initial.RefreshToken); err != nil {
		t.Fatalf("Logout() error = %v", err)
	}

	if _, err := svc.RefreshToken(context.Background(), initial.RefreshToken); !errors.Is(err, ErrForbidden) {
		t.Fatalf("RefreshToken() after logout error = %v, want %v", err, ErrForbidden)
	}
}

func mustParseRefreshToken(t *testing.T, token string) (string, string) {
	t.Helper()

	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		t.Fatalf("refresh token format = %q, want <session>.<secret>", token)
	}

	secretBytes, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		t.Fatalf("decode refresh secret: %v", err)
	}

	sum := sha256.Sum256(secretBytes)
	return parts[0], hex.EncodeToString(sum[:])
}

type fakeAuthUserRepo struct {
	users map[string]*domain.User
}

func (r *fakeAuthUserRepo) GetByID(_ context.Context, id string) (*domain.User, error) {
	if r.users == nil {
		return nil, nil
	}
	return r.users[id], nil
}

func (r *fakeAuthUserRepo) UpsertByAppleID(_ context.Context, appleID string, email *string, nickname *string) (*domain.User, error) {
	if r.users == nil {
		r.users = make(map[string]*domain.User)
	}
	user := &domain.User{ID: "user-" + appleID, AppleID: &appleID, Email: email, Nickname: nickname}
	r.users[user.ID] = user
	return user, nil
}

func (r *fakeAuthUserRepo) UpsertByEmail(_ context.Context, email string) (*domain.User, error) {
	if r.users == nil {
		r.users = make(map[string]*domain.User)
	}
	user := &domain.User{ID: "user-" + email, Email: &email}
	r.users[user.ID] = user
	return user, nil
}

type fakeRefreshSessionRepo struct {
	sessions map[string]*domain.RefreshSession
}

func newFakeRefreshSessionRepo() *fakeRefreshSessionRepo {
	return &fakeRefreshSessionRepo{sessions: make(map[string]*domain.RefreshSession)}
}

func (r *fakeRefreshSessionRepo) Create(_ context.Context, session *domain.RefreshSession) error {
	clone := *session
	r.sessions[session.ID] = &clone
	return nil
}

func (r *fakeRefreshSessionRepo) GetByID(_ context.Context, sessionID string) (*domain.RefreshSession, error) {
	session, ok := r.sessions[sessionID]
	if !ok {
		return nil, nil
	}
	clone := *session
	return &clone, nil
}

func (r *fakeRefreshSessionRepo) Rotate(_ context.Context, sessionID, currentTokenHash, newTokenHash string, expiresAt, now time.Time) (*domain.RefreshSession, error) {
	session, ok := r.sessions[sessionID]
	if !ok || session.RevokedAt != nil || !session.ExpiresAt.After(now) || session.TokenHash != currentTokenHash {
		return nil, nil
	}

	replacedHash := currentTokenHash
	session.TokenHash = newTokenHash
	session.ExpiresAt = expiresAt
	session.LastUsedAt = &now
	session.RotatedAt = &now
	session.ReplacedByTokenHash = &replacedHash
	session.UpdatedAt = now
	clone := *session
	return &clone, nil
}

func (r *fakeRefreshSessionRepo) Revoke(_ context.Context, sessionID, tokenHash string, now time.Time) error {
	session, ok := r.sessions[sessionID]
	if !ok || session.RevokedAt != nil {
		return nil
	}
	if tokenHash != "" && session.TokenHash != tokenHash {
		return nil
	}
	session.RevokedAt = &now
	session.UpdatedAt = now
	return nil
}
