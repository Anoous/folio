package service

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

type AuthService struct {
	userRepo  *repository.UserRepo
	jwtSecret []byte
}

func NewAuthService(userRepo *repository.UserRepo, jwtSecret string) *AuthService {
	return &AuthService{
		userRepo:  userRepo,
		jwtSecret: []byte(jwtSecret),
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
		return nil, fmt.Errorf("invalid apple token: %w", err)
	}

	// Find or create user
	user, err := s.userRepo.GetByAppleID(ctx, appleUserID)
	if err != nil {
		return nil, fmt.Errorf("lookup user: %w", err)
	}

	if user == nil {
		user, err = s.userRepo.Create(ctx, repository.CreateUserParams{
			AppleID:  appleUserID,
			Email:    req.Email,
			Nickname: req.Nickname,
		})
		if err != nil {
			return nil, fmt.Errorf("create user: %w", err)
		}
	}

	return s.issueTokenPair(user)
}

func (s *AuthService) DevLogin(ctx context.Context) (*AuthResponse, error) {
	devAppleID := "dev-user-local"
	devEmail := "dev@folio.local"
	devNickname := "Dev User"

	user, err := s.userRepo.GetByAppleID(ctx, devAppleID)
	if err != nil {
		return nil, fmt.Errorf("lookup dev user: %w", err)
	}
	if user == nil {
		user, err = s.userRepo.Create(ctx, repository.CreateUserParams{
			AppleID:  devAppleID,
			Email:    &devEmail,
			Nickname: &devNickname,
		})
		if err != nil {
			return nil, fmt.Errorf("create dev user: %w", err)
		}
	}
	return s.issueTokenPair(user)
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
		return nil, ErrForbidden
	}
	if claims.TokenType != "refresh" {
		return nil, ErrForbidden
	}

	user, err := s.userRepo.GetByID(ctx, claims.UserID)
	if err != nil {
		return nil, err
	}
	if user == nil {
		return nil, ErrNotFound
	}

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

	// Verify the token with the public key
	claims := &jwt.RegisteredClaims{}
	verified, err := jwt.ParseWithClaims(tokenString, claims, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return publicKey, nil
	}, jwt.WithIssuer("https://appleid.apple.com"))
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

	resp, err := http.Get("https://appleid.apple.com/auth/keys")
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
