package service

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"log/slog"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"folio-server/internal/client"
	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

type AuthService struct {
	userRepo      *repository.UserRepo
	jwtSecret     []byte
	appleBundleID string
	resend        *client.ResendClient
}

func NewAuthService(userRepo *repository.UserRepo, jwtSecret string, appleBundleID string, resend *client.ResendClient) *AuthService {
	return &AuthService{
		userRepo:      userRepo,
		jwtSecret:     []byte(jwtSecret),
		appleBundleID: appleBundleID,
		resend:        resend,
	}
}

type TokenClaims struct {
	jwt.RegisteredClaims
	UserID    string `json:"uid"`
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

// Verification code in-memory storage
type emailCode struct {
	code      string
	expiresAt time.Time
	attempts  int
}

var (
	emailCodes   sync.Map // key: email, value: *emailCode
	codeCooldown sync.Map // key: email, value: time.Time
)

type SendCodeRequest struct {
	Email string `json:"email"`
}

type VerifyCodeRequest struct {
	Email string `json:"email"`
	Code  string `json:"code"`
}

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
		return nil, fmt.Errorf("invalid apple token: %w", err)
	}

	// Find or create user
	user, err := s.userRepo.GetByAppleID(ctx, appleUserID)
	if err != nil {
		return nil, fmt.Errorf("lookup user: %w", err)
	}

	isNew := user == nil
	if user == nil {
		user, err = s.userRepo.Create(ctx, repository.CreateUserParams{
			AppleID:  &appleUserID,
			Email:    req.Email,
			Nickname: req.Nickname,
		})
		if err != nil {
			return nil, fmt.Errorf("create user: %w", err)
		}
	}

	slog.Info("apple login succeeded", "user_id", user.ID, "new_user", isNew)
	return s.issueTokenPair(user)
}

func (s *AuthService) SendEmailCode(ctx context.Context, req SendCodeRequest) error {
	email := strings.TrimSpace(strings.ToLower(req.Email))
	if email == "" || !strings.Contains(email, "@") {
		return fmt.Errorf("invalid email address")
	}

	// Check 60s cooldown
	if lastSent, ok := codeCooldown.Load(email); ok {
		if time.Since(lastSent.(time.Time)) < 60*time.Second {
			return ErrCodeRateLimit
		}
	}

	// Generate 6-digit code
	code := fmt.Sprintf("%06d", cryptoRandInt(1000000))

	// Store code with 5min TTL
	emailCodes.Store(email, &emailCode{
		code:      code,
		expiresAt: time.Now().Add(5 * time.Minute),
		attempts:  0,
	})

	// Store send time for cooldown
	codeCooldown.Store(email, time.Now())

	// Send email via Resend (falls back to logging if no API key)
	if err := s.resend.SendVerificationCode(email, code); err != nil {
		slog.Error("failed to send verification email", "email", email, "error", err)
		// Still log the code so dev/test can proceed
		slog.Info("[AUTH] verification code (email failed)", "email", email, "code", code)
		return nil
	}
	return nil
}

func (s *AuthService) VerifyEmailCode(ctx context.Context, req VerifyCodeRequest) (*AuthResponse, error) {
	email := strings.TrimSpace(strings.ToLower(req.Email))

	val, ok := emailCodes.Load(email)
	if !ok {
		return nil, ErrInvalidCode
	}
	ec := val.(*emailCode)

	// Check expiry
	if time.Now().After(ec.expiresAt) {
		emailCodes.Delete(email)
		return nil, ErrInvalidCode
	}

	// Check max attempts
	if ec.attempts >= 5 {
		emailCodes.Delete(email)
		return nil, ErrInvalidCode
	}

	// Compare code
	if ec.code != req.Code {
		ec.attempts++
		return nil, ErrInvalidCode
	}

	// Success — delete code
	emailCodes.Delete(email)

	// Find or create user
	user, err := s.userRepo.GetByEmail(ctx, email)
	if err != nil {
		return nil, fmt.Errorf("lookup user by email: %w", err)
	}

	isNew := user == nil
	if user == nil {
		emailPtr := email
		user, err = s.userRepo.Create(ctx, repository.CreateUserParams{
			Email: &emailPtr,
		})
		if err != nil {
			return nil, fmt.Errorf("create user: %w", err)
		}
	}

	slog.Info("email login succeeded", "user_id", user.ID, "email", email, "new_user", isNew)
	return s.issueTokenPair(user)
}

func cryptoRandInt(max int) int {
	b := make([]byte, 4)
	_, _ = rand.Read(b)
	return int(binary.BigEndian.Uint32(b)) % max
}

func (s *AuthService) RefreshToken(ctx context.Context, refreshToken string) (*AuthResponse, error) {
	claims := &TokenClaims{}
	token, err := jwt.ParseWithClaims(refreshToken, claims, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return s.jwtSecret, nil
	})
	if err != nil || !token.Valid {
		slog.Debug("token refresh: invalid token", "error", err)
		return nil, ErrForbidden
	}
	if claims.TokenType != "refresh" {
		slog.Debug("token refresh: wrong token type", "type", claims.TokenType)
		return nil, ErrForbidden
	}

	user, err := s.userRepo.GetByID(ctx, claims.UserID)
	if err != nil {
		return nil, err
	}
	if user == nil {
		slog.Info("token refresh: user not found", "user_id", claims.UserID)
		return nil, ErrNotFound
	}

	slog.Debug("token refreshed", "user_id", user.ID)
	return s.issueTokenPair(user)
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

func (s *AuthService) issueTokenPair(user *domain.User) (*AuthResponse, error) {
	now := time.Now()

	accessClaims := TokenClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(2 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(now),
			Issuer:    "folio",
		},
		UserID:    user.ID,
		TokenType: "access",
	}
	accessToken, err := jwt.NewWithClaims(jwt.SigningMethodHS256, accessClaims).SignedString(s.jwtSecret)
	if err != nil {
		return nil, fmt.Errorf("sign access token: %w", err)
	}

	refreshClaims := TokenClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(90 * 24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(now),
			Issuer:    "folio",
		},
		UserID:    user.ID,
		TokenType: "refresh",
	}
	refreshTokenStr, err := jwt.NewWithClaims(jwt.SigningMethodHS256, refreshClaims).SignedString(s.jwtSecret)
	if err != nil {
		return nil, fmt.Errorf("sign refresh token: %w", err)
	}

	return &AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshTokenStr,
		ExpiresIn:    7200,
		User:         user,
	}, nil
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
		return nil, fmt.Errorf("fetch apple jwks: %w", err)
	}
	defer resp.Body.Close()

	var jwks AppleJWKSResponse
	if err := json.NewDecoder(resp.Body).Decode(&jwks); err != nil {
		return nil, fmt.Errorf("decode apple jwks: %w", err)
	}

	appleJWKS = &jwks
	appleJWKSFetch = time.Now()
	return appleJWKS, nil
}

func parseRSAPublicKey(jwk AppleJWK) (*rsa.PublicKey, error) {
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

	return &rsa.PublicKey{
		N: n,
		E: int(e.Int64()),
	}, nil
}
