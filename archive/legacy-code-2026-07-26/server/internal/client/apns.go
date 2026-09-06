package client

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/net/http2"
)

const (
	apnsProductionHost = "https://api.push.apple.com"
	apnsSandboxHost    = "https://api.sandbox.push.apple.com"
	// APNs tokens are valid for up to 60 minutes; we refresh at 50 minutes.
	apnsTokenTTL = 50 * time.Minute
)

// APNSClient sends push notifications via the Apple Push Notification service
// HTTP/2 API.
type APNSClient struct {
	keyID      string
	teamID     string
	privateKey *ecdsa.PrivateKey
	sandbox    bool
	httpClient *http.Client

	// JWT caching
	mu           sync.Mutex
	cachedToken  string
	tokenExpires time.Time
}

// NewAPNSClient creates an APNSClient. If keyPath is empty, a mock client
// is returned that logs pushes without actually sending them.
func NewAPNSClient(keyID, teamID, keyPath string, sandbox bool) (*APNSClient, error) {
	if keyPath == "" {
		slog.Warn("APNS_KEY_PATH not set, using mock APNs client (pushes will be logged only)")
		return &APNSClient{sandbox: sandbox}, nil
	}

	pk, err := loadP8Key(keyPath)
	if err != nil {
		return nil, fmt.Errorf("load APNs p8 key: %w", err)
	}

	transport := &http2.Transport{}
	httpClient := &http.Client{
		Transport: transport,
		Timeout:   30 * time.Second,
	}

	return &APNSClient{
		keyID:      keyID,
		teamID:     teamID,
		privateKey: pk,
		sandbox:    sandbox,
		httpClient: httpClient,
	}, nil
}

// IsMock returns true when the client has no private key and will only log
// pushes instead of sending them.
func (c *APNSClient) IsMock() bool {
	return c.privateKey == nil
}

// host returns the APNs endpoint based on sandbox mode.
func (c *APNSClient) host() string {
	if c.sandbox {
		return apnsSandboxHost
	}
	return apnsProductionHost
}

// getToken returns a cached or freshly generated ES256 JWT for APNs.
func (c *APNSClient) getToken() (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.cachedToken != "" && time.Now().Before(c.tokenExpires) {
		return c.cachedToken, nil
	}

	now := time.Now()
	token := jwt.NewWithClaims(jwt.SigningMethodES256, jwt.MapClaims{
		"iss": c.teamID,
		"iat": now.Unix(),
	})
	token.Header["kid"] = c.keyID

	signed, err := token.SignedString(c.privateKey)
	if err != nil {
		return "", fmt.Errorf("sign APNs JWT: %w", err)
	}

	c.cachedToken = signed
	c.tokenExpires = now.Add(apnsTokenTTL)
	return signed, nil
}

// apnsPayload is the JSON body sent to APNs.
type apnsPayload struct {
	APS apnsAPS `json:"aps"`
}

type apnsAPS struct {
	Alert apnsAlert `json:"alert"`
	Sound string    `json:"sound"`
	Badge int       `json:"badge"`
}

type apnsAlert struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

// SendPush sends a push notification to the given device token.
func (c *APNSClient) SendPush(ctx context.Context, deviceToken, title, body, bundleID string) error {
	// Mock mode: just log the push.
	if c.IsMock() {
		slog.Info("mock APNs push",
			"token", deviceToken[:min(16, len(deviceToken))]+"...",
			"title", title,
			"body", body,
		)
		return nil
	}

	jwtToken, err := c.getToken()
	if err != nil {
		return err
	}

	payload := apnsPayload{
		APS: apnsAPS{
			Alert: apnsAlert{Title: title, Body: body},
			Sound: "default",
			Badge: 1,
		},
	}

	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal APNs payload: %w", err)
	}

	url := fmt.Sprintf("%s/3/device/%s", c.host(), deviceToken)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payloadBytes))
	if err != nil {
		return fmt.Errorf("create APNs request: %w", err)
	}

	req.Header.Set("authorization", "bearer "+jwtToken)
	req.Header.Set("apns-topic", bundleID)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "10")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("APNs request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		return nil
	}

	respBody, _ := io.ReadAll(resp.Body)
	return fmt.Errorf("APNs error: status %d, body: %s", resp.StatusCode, string(respBody))
}
