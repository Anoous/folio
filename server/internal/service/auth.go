package service

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"folio-server/internal/domain"
)

type AuthService struct {
	userRepo      authUserStore
	sessionRepo   refreshSessionStore
	jwtSecret     []byte
	appleBundleID string
	resend        verificationCodeSender
	rdb           *redis.Client
}

type authUserStore interface {
	GetByID(ctx context.Context, id string) (*domain.User, error)
	UpsertByAppleID(ctx context.Context, appleID string, email *string, nickname *string) (*domain.User, error)
	UpsertByEmail(ctx context.Context, email string) (*domain.User, error)
}

type refreshSessionStore interface {
	Create(ctx context.Context, session *domain.RefreshSession) error
	GetByID(ctx context.Context, sessionID string) (*domain.RefreshSession, error)
	Rotate(ctx context.Context, sessionID, currentTokenHash, newTokenHash string, expiresAt, now time.Time) (*domain.RefreshSession, error)
	Revoke(ctx context.Context, sessionID, tokenHash string, now time.Time) error
}

type verificationCodeSender interface {
	SendVerificationCode(to, code string) error
}

func NewAuthService(userRepo authUserStore, sessionRepo refreshSessionStore, jwtSecret string, appleBundleID string, resend verificationCodeSender, rdb *redis.Client) *AuthService {
	return &AuthService{
		userRepo:      userRepo,
		sessionRepo:   sessionRepo,
		jwtSecret:     []byte(jwtSecret),
		appleBundleID: appleBundleID,
		resend:        resend,
		rdb:           rdb,
	}
}

type TokenClaims struct {
	jwt.RegisteredClaims
	UserID    string `json:"uid"`
	SessionID string `json:"sid,omitempty"`
	TokenType string `json:"type"`
}

type AppleAuthRequest struct {
	IdentityToken string  `json:"identity_token"`
	Email         *string `json:"email,omitempty"`
	Nickname      *string `json:"nickname,omitempty"`
}

type AuthResponse struct {
	AccessToken  string       `json:"access_token"`
	RefreshToken string       `json:"refresh_token"`
	ExpiresIn    int          `json:"expires_in"`
	User         *domain.User `json:"user"`
}

// Redis key helpers for verification codes
func codeKey(email string) string     { return "auth:code:" + email }
func cooldownKey(email string) string { return "auth:cooldown:" + email }
func attemptsKey(email string) string { return "auth:attempts:" + email }

type SendCodeRequest struct {
	Email string `json:"email"`
}

type VerifyCodeRequest struct {
	Email string `json:"email"`
	Code  string `json:"code"`
}

const (
	emailCodeTTL          = 5 * time.Minute
	emailCodeCooldownTTL  = 60 * time.Second
	emailCodeWatchRetries = 3
	accessTokenTTL        = 2 * time.Hour
	refreshSessionTTL     = 90 * 24 * time.Hour
	refreshSecretBytes    = 32
)

// Apple JWKS cache
var (
	appleJWKS      *AppleJWKSResponse
	appleJWKSMu    sync.RWMutex
	appleJWKSFetch time.Time
)

type AppleJWKSResponse struct {
	Keys []AppleJWK `json:"keys"`
}

type AppleJWK struct {
	Kty string `json:"kty"`
	Kid string `json:"kid"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	N   string `json:"n"`
	E   string `json:"e"`
}

func (s *AuthService) LoginWithApple(ctx context.Context, req AppleAuthRequest) (*AuthResponse, error) {
	// Parse and verify the Apple identity token
	appleUserID, err := s.verifyAppleToken(req.IdentityToken)
	if err != nil {
		slog.Info("apple login: token verification failed", "error", err)
		return nil, ErrForbidden
	}

	// Atomically find-or-create user (handles existing Apple user, email linking, new user)
	user, err := s.userRepo.UpsertByAppleID(ctx, appleUserID, req.Email, req.Nickname)
	if err != nil {
		return nil, fmt.Errorf("upsert user by apple_id: %w", err)
	}

	slog.Info("apple login succeeded", "user_id", user.ID)
	return s.issueTokenPair(ctx, user)
}

func (s *AuthService) SendEmailCode(ctx context.Context, req SendCodeRequest) error {
	email := strings.TrimSpace(strings.ToLower(req.Email))
	if email == "" || !strings.Contains(email, "@") {
		return fmt.Errorf("invalid email address")
	}

	// Generate 6-digit code
	code, err := generateEmailCode(rand.Reader)
	if err != nil {
		return fmt.Errorf("generate verification code: %w", err)
	}

	if err := s.reserveEmailCode(ctx, email, code); err != nil {
		slog.Error("failed to persist verification code", "email", email, "error", err)
		return err
	}

	// Send email via Resend
	if err := s.resend.SendVerificationCode(email, code); err != nil {
		slog.Error("failed to send verification email", "email", email, "error", err)
		slog.Warn("[AUTH] verification email send failed — code stored, user can retry", "email", email)
		return fmt.Errorf("send verification email: %w", err)
	}
	return nil
}

func (s *AuthService) reserveEmailCode(ctx context.Context, email, code string) error {
	for range emailCodeWatchRetries {
		err := s.rdb.Watch(ctx, func(tx *redis.Tx) error {
			exists, err := tx.Exists(ctx, cooldownKey(email)).Result()
			if err != nil {
				return fmt.Errorf("check verification cooldown: %w", err)
			}
			if exists > 0 {
				return ErrCodeRateLimit
			}

			_, err = tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
				pipe.Set(ctx, codeKey(email), code, emailCodeTTL)
				pipe.Del(ctx, attemptsKey(email))
				pipe.Set(ctx, cooldownKey(email), "1", emailCodeCooldownTTL)
				return nil
			})
			if err != nil {
				return fmt.Errorf("persist verification code: %w", err)
			}
			return nil
		}, cooldownKey(email))

		switch {
		case err == nil:
			return nil
		case errors.Is(err, ErrCodeRateLimit):
			return err
		case errors.Is(err, redis.TxFailedErr):
			continue
		default:
			return fmt.Errorf("persist verification code: %w", err)
		}
	}

	return ErrCodeRateLimit
}

func (s *AuthService) VerifyEmailCode(ctx context.Context, req VerifyCodeRequest) (*AuthResponse, error) {
	email := strings.TrimSpace(strings.ToLower(req.Email))

	// Retrieve stored code from Redis
	storedCode, err := s.rdb.Get(ctx, codeKey(email)).Result()
	if err != nil {
		return nil, ErrInvalidCode
	}

	// Check attempt count (max 5)
	attempts, _ := s.rdb.Incr(ctx, attemptsKey(email)).Result()
	if attempts > 5 {
		s.rdb.Del(ctx, codeKey(email), attemptsKey(email))
		return nil, ErrInvalidCode
	}

	if storedCode != req.Code {
		return nil, ErrInvalidCode
	}

	// Success — delete code and attempts
	s.rdb.Del(ctx, codeKey(email), attemptsKey(email), cooldownKey(email))

	// Atomically find-or-create user
	user, err := s.userRepo.UpsertByEmail(ctx, email)
	if err != nil {
		return nil, fmt.Errorf("upsert user by email: %w", err)
	}

	slog.Info("email login succeeded", "user_id", user.ID, "email", email)
	return s.issueTokenPair(ctx, user)
}

func generateEmailCode(reader io.Reader) (string, error) {
	n, err := rand.Int(reader, big.NewInt(1000000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

func (s *AuthService) RefreshToken(ctx context.Context, refreshToken string) (*AuthResponse, error) {
	sessionID, presentedHash, err := parseRefreshToken(refreshToken)
	if err != nil {
		slog.Debug("token refresh: invalid token", "error", err)
		return nil, ErrForbidden
	}

	now := time.Now()
	newRefreshToken, newTokenHash, err := generateRefreshToken(sessionID)
	if err != nil {
		return nil, fmt.Errorf("generate refresh token: %w", err)
	}

	session, err := s.sessionRepo.Rotate(ctx, sessionID, presentedHash, newTokenHash, now.Add(refreshSessionTTL), now)
	if err != nil {
		return nil, fmt.Errorf("rotate refresh session: %w", err)
	}
	if session == nil {
		existing, lookupErr := s.sessionRepo.GetByID(ctx, sessionID)
		if lookupErr != nil {
			return nil, fmt.Errorf("lookup refresh session: %w", lookupErr)
		}
		if shouldRevokeRefreshSessionReuse(existing, presentedHash, now) {
			if revokeErr := s.sessionRepo.Revoke(ctx, sessionID, "", now); revokeErr != nil {
				slog.Error("token refresh: revoke reused session failed", "session_id", sessionID, "error", revokeErr)
			}
		}
		slog.Debug("token refresh: session rejected", "session_id", sessionID)
		return nil, ErrForbidden
	}

	user, err := s.userRepo.GetByID(ctx, session.UserID)
	if err != nil {
		return nil, err
	}
	if user == nil {
		slog.Info("token refresh: user not found", "user_id", session.UserID)
		return nil, ErrNotFound
	}

	slog.Debug("token refreshed", "user_id", user.ID, "session_id", sessionID)
	return s.buildAuthResponse(user, sessionID, newRefreshToken, now)
}

func shouldRevokeRefreshSessionReuse(session *domain.RefreshSession, presentedHash string, now time.Time) bool {
	return session != nil &&
		session.RevokedAt == nil &&
		session.ExpiresAt.After(now) &&
		session.ReplacedByTokenHash != nil &&
		*session.ReplacedByTokenHash == presentedHash
}

func (s *AuthService) Logout(ctx context.Context, refreshToken string) error {
	sessionID, tokenHash, err := parseRefreshToken(refreshToken)
	if err != nil {
		return ErrForbidden
	}

	if err := s.sessionRepo.Revoke(ctx, sessionID, tokenHash, time.Now()); err != nil {
		return fmt.Errorf("revoke refresh session: %w", err)
	}
	return nil
}

func (s *AuthService) ValidateAccessToken(tokenString string) (string, error) {
	claims := &TokenClaims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return s.jwtSecret, nil
	})
	if err != nil || !token.Valid {
		return "", ErrForbidden
	}
	if claims.TokenType != "access" {
		return "", ErrForbidden
	}
	return claims.UserID, nil
}

func (s *AuthService) issueTokenPair(ctx context.Context, user *domain.User) (*AuthResponse, error) {
	now := time.Now()
	sessionID := uuid.NewString()
	refreshTokenStr, tokenHash, err := generateRefreshToken(sessionID)
	if err != nil {
		return nil, fmt.Errorf("generate refresh token: %w", err)
	}

	if err := s.sessionRepo.Create(ctx, &domain.RefreshSession{
		ID:        sessionID,
		UserID:    user.ID,
		TokenHash: tokenHash,
		ExpiresAt: now.Add(refreshSessionTTL),
		CreatedAt: now,
		UpdatedAt: now,
	}); err != nil {
		return nil, fmt.Errorf("create refresh session: %w", err)
	}

	return s.buildAuthResponse(user, sessionID, refreshTokenStr, now)
}

func (s *AuthService) buildAuthResponse(user *domain.User, sessionID, refreshToken string, now time.Time) (*AuthResponse, error) {
	accessToken, err := s.signAccessToken(user, sessionID, now)
	if err != nil {
		return nil, err
	}

	return &AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    int(accessTokenTTL.Seconds()),
		User:         user,
	}, nil
}

func (s *AuthService) signAccessToken(user *domain.User, sessionID string, now time.Time) (string, error) {
	accessClaims := TokenClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(accessTokenTTL)),
			IssuedAt:  jwt.NewNumericDate(now),
			Issuer:    "folio",
		},
		UserID:    user.ID,
		SessionID: sessionID,
		TokenType: "access",
	}

	accessToken, err := jwt.NewWithClaims(jwt.SigningMethodHS256, accessClaims).SignedString(s.jwtSecret)
	if err != nil {
		return "", fmt.Errorf("sign access token: %w", err)
	}
	return accessToken, nil
}

func generateRefreshToken(sessionID string) (string, string, error) {
	secret := make([]byte, refreshSecretBytes)
	if _, err := rand.Read(secret); err != nil {
		return "", "", fmt.Errorf("read random bytes: %w", err)
	}

	encodedSecret := base64.RawURLEncoding.EncodeToString(secret)
	sum := sha256.Sum256(secret)
	return sessionID + "." + encodedSecret, hex.EncodeToString(sum[:]), nil
}

func parseRefreshToken(refreshToken string) (string, string, error) {
	parts := strings.Split(refreshToken, ".")
	if len(parts) != 2 {
		return "", "", fmt.Errorf("invalid refresh token format")
	}
	if _, err := uuid.Parse(parts[0]); err != nil {
		return "", "", fmt.Errorf("parse session id: %w", err)
	}

	secret, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return "", "", fmt.Errorf("decode refresh secret: %w", err)
	}

	sum := sha256.Sum256(secret)
	return parts[0], hex.EncodeToString(sum[:]), nil
}

func (s *AuthService) verifyAppleToken(tokenString string) (string, error) {
	// Parse the token header to get the kid
	parser := jwt.NewParser()
	token, _, err := parser.ParseUnverified(tokenString, &jwt.RegisteredClaims{})
	if err != nil {
		return "", fmt.Errorf("parse token: %w", err)
	}

	kid, ok := token.Header["kid"].(string)
	if !ok {
		return "", fmt.Errorf("missing kid in token header")
	}

	// Get Apple's public key
	publicKey, err := getApplePublicKey(kid)
	if err != nil {
		return "", err
	}

	// Verify the token with the public key (issuer + audience)
	claims := &jwt.RegisteredClaims{}
	verified, err := jwt.ParseWithClaims(tokenString, claims, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return publicKey, nil
	}, jwt.WithIssuer("https://appleid.apple.com"),
		jwt.WithAudience(s.appleBundleID),
	)
	if err != nil || !verified.Valid {
		return "", fmt.Errorf("token verification failed: %w", err)
	}

	sub, err := claims.GetSubject()
	if err != nil || sub == "" {
		return "", fmt.Errorf("missing subject in token")
	}

	return sub, nil
}

func getApplePublicKey(kid string) (*rsa.PublicKey, error) {
	jwks, err := fetchAppleJWKS()
	if err != nil {
		return nil, err
	}

	for _, key := range jwks.Keys {
		if key.Kid == kid {
			return parseRSAPublicKey(key)
		}
	}
	return nil, fmt.Errorf("key %s not found in Apple JWKS", kid)
}

func fetchAppleJWKS() (*AppleJWKSResponse, error) {
	appleJWKSMu.RLock()
	if appleJWKS != nil && time.Since(appleJWKSFetch) < 24*time.Hour {
		defer appleJWKSMu.RUnlock()
		return appleJWKS, nil
	}
	appleJWKSMu.RUnlock()

	appleJWKSMu.Lock()
	defer appleJWKSMu.Unlock()

	// Double-check after acquiring write lock
	if appleJWKS != nil && time.Since(appleJWKSFetch) < 24*time.Hour {
		return appleJWKS, nil
	}

	httpClient := &http.Client{Timeout: 10 * time.Second}
	resp, err := httpClient.Get("https://appleid.apple.com/auth/keys")
	if err != nil {
		// Grace period: return stale JWKS if available (up to 48h)
		if appleJWKS != nil && time.Since(appleJWKSFetch) < 48*time.Hour {
			slog.Warn("apple JWKS fetch failed, using stale cache", "age", time.Since(appleJWKSFetch), "error", err)
			return appleJWKS, nil
		}
		return nil, fmt.Errorf("fetch apple jwks: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		// Grace period: return stale JWKS if available (up to 48h)
		if appleJWKS != nil && time.Since(appleJWKSFetch) < 48*time.Hour {
			slog.Warn("apple JWKS fetch returned non-2xx, using stale cache", "age", time.Since(appleJWKSFetch), "status", resp.StatusCode)
			return appleJWKS, nil
		}
		return nil, fmt.Errorf("fetch apple jwks: unexpected status %d", resp.StatusCode)
	}

	var jwks AppleJWKSResponse
	if err := json.NewDecoder(resp.Body).Decode(&jwks); err != nil {
		// Grace period: return stale JWKS if available (up to 48h)
		if appleJWKS != nil && time.Since(appleJWKSFetch) < 48*time.Hour {
			slog.Warn("apple JWKS decode failed, using stale cache", "age", time.Since(appleJWKSFetch), "error", err)
			return appleJWKS, nil
		}
		return nil, fmt.Errorf("decode apple jwks: %w", err)
	}

	appleJWKS = &jwks
	appleJWKSFetch = time.Now()
	return appleJWKS, nil
}

func parseRSAPublicKey(jwk AppleJWK) (*rsa.PublicKey, error) {
	if jwk.Kty != "RSA" {
		return nil, fmt.Errorf("unexpected apple JWK key type %q", jwk.Kty)
	}
	if jwk.Use != "sig" {
		return nil, fmt.Errorf("unexpected apple JWK use %q", jwk.Use)
	}
	if jwk.Alg != "RS256" {
		return nil, fmt.Errorf("unexpected apple JWK algorithm %q", jwk.Alg)
	}

	nBytes, err := base64.RawURLEncoding.DecodeString(jwk.N)
	if err != nil {
		return nil, fmt.Errorf("decode modulus: %w", err)
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(jwk.E)
	if err != nil {
		return nil, fmt.Errorf("decode exponent: %w", err)
	}

	n := new(big.Int).SetBytes(nBytes)
	e := new(big.Int).SetBytes(eBytes)
	if n.Sign() <= 0 {
		return nil, fmt.Errorf("invalid RSA modulus")
	}
	if !e.IsInt64() {
		return nil, fmt.Errorf("invalid RSA exponent")
	}
	exponent := e.Int64()
	if exponent < 3 || exponent%2 == 0 || exponent > int64(^uint(0)>>1) {
		return nil, fmt.Errorf("invalid RSA exponent")
	}

	return &rsa.PublicKey{
		N: n,
		E: int(exponent),
	}, nil
}
