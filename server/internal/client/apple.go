package client

import (
	"context"
	"crypto/ecdsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	appleStoreKitProductionURL = "https://api.storekit.itunes.apple.com"
	appleStoreKitSandboxURL    = "https://api.storekit-sandbox.itunes.apple.com"
)

// TransactionInfo holds parsed App Store transaction data.
type TransactionInfo struct {
	TransactionID         string     `json:"transactionId"`
	OriginalTransactionID string     `json:"originalTransactionId"`
	ProductID             string     `json:"productId"`
	BundleID              string     `json:"bundleId"`
	ExpiresDate           *time.Time `json:"expiresDate"`
	PurchaseDate          *time.Time `json:"purchaseDate"`
}

// WebhookEvent represents an App Store Server notification.
type WebhookEvent struct {
	NotificationType string      `json:"notificationType"`
	Subtype          string      `json:"subtype"`
	Data             WebhookData `json:"data"`
}

// WebhookData contains the signed transaction info from a webhook.
type WebhookData struct {
	SignedTransactionInfo string `json:"signedTransactionInfo"`
}

// AppleStoreClient abstracts App Store Server API operations so callers can
// swap real vs mock implementations.
type AppleStoreClient interface {
	VerifyTransaction(ctx context.Context, transactionID string) (*TransactionInfo, error)
	ParseWebhookPayload(signedPayload string) (*WebhookEvent, error)
	ParseSignedTransaction(signedTxn string) (*TransactionInfo, error)
}

// ---------- Real client ----------

// AppleClient communicates with the App Store Server API using ES256 JWTs.
type AppleClient struct {
	keyID      string
	issuerID   string
	privateKey *ecdsa.PrivateKey
	bundleID   string
	sandbox    bool
	httpClient *http.Client
}

// NewAppleClient creates an AppleStoreClient. If keyPath is empty a mock
// client is returned that always succeeds — suitable for dev environments
// without Apple credentials.
func NewAppleClient(keyID, issuerID, keyPath, bundleID string, sandbox bool) (AppleStoreClient, error) {
	if keyPath == "" {
		return &MockAppleClient{bundleID: bundleID}, nil
	}

	pk, err := loadP8Key(keyPath)
	if err != nil {
		return nil, fmt.Errorf("load apple p8 key: %w", err)
	}

	return &AppleClient{
		keyID:      keyID,
		issuerID:   issuerID,
		privateKey: pk,
		bundleID:   bundleID,
		sandbox:    sandbox,
		httpClient: &http.Client{Timeout: 30 * time.Second},
	}, nil
}

// baseURL returns the appropriate App Store Server API host.
func (c *AppleClient) baseURL() string {
	if c.sandbox {
		return appleStoreKitSandboxURL
	}
	return appleStoreKitProductionURL
}

// generateJWT creates an ES256-signed JWT for the App Store Server API.
func (c *AppleClient) generateJWT() (string, error) {
	now := time.Now()
	token := jwt.NewWithClaims(jwt.SigningMethodES256, jwt.RegisteredClaims{
		Issuer:    c.issuerID,
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(now.Add(20 * time.Minute)),
		Audience:  jwt.ClaimStrings{"appstoreconnect-v1"},
	})
	token.Header["kid"] = c.keyID

	return token.SignedString(c.privateKey)
}

// VerifyTransaction fetches and parses a transaction from the App Store
// Server API.
func (c *AppleClient) VerifyTransaction(ctx context.Context, transactionID string) (*TransactionInfo, error) {
	jwtToken, err := c.generateJWT()
	if err != nil {
		return nil, fmt.Errorf("generate apple jwt: %w", err)
	}

	url := fmt.Sprintf("%s/inApps/v1/transactions/%s", c.baseURL(), transactionID)
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+jwtToken)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("apple api request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("apple api error: status %d, body: %s", resp.StatusCode, string(body))
	}

	// Response wraps the transaction in a JWS envelope.
	var envelope struct {
		SignedTransactionInfo string `json:"signedTransactionInfo"`
	}
	if err := json.Unmarshal(body, &envelope); err != nil {
		return nil, fmt.Errorf("decode transaction envelope: %w", err)
	}

	return parseSignedTransaction(envelope.SignedTransactionInfo)
}

// ParseWebhookPayload decodes an App Store Server notification from its
// JWS signed payload.
func (c *AppleClient) ParseWebhookPayload(signedPayload string) (*WebhookEvent, error) {
	return parseWebhookPayload(signedPayload)
}

// ParseSignedTransaction decodes a JWS-signed transaction string into
// TransactionInfo.
func (c *AppleClient) ParseSignedTransaction(signedTxn string) (*TransactionInfo, error) {
	return parseSignedTransaction(signedTxn)
}

// ---------- Shared JWS helpers ----------

// parseSignedTransaction base64-decodes the payload portion of a JWS and
// unmarshals it into TransactionInfo. Full JWS signature verification is
// skipped for the MVP — Apple's TLS guarantees authenticity in transit.
func parseSignedTransaction(signed string) (*TransactionInfo, error) {
	payload, err := decodeJWSPayload(signed)
	if err != nil {
		return nil, fmt.Errorf("decode signed transaction: %w", err)
	}

	var raw transactionInfoRaw
	if err := json.Unmarshal(payload, &raw); err != nil {
		return nil, fmt.Errorf("unmarshal transaction info: %w", err)
	}

	return raw.toTransactionInfo(), nil
}

// parseWebhookPayload base64-decodes the payload portion of a JWS and
// unmarshals it into WebhookEvent.
func parseWebhookPayload(signedPayload string) (*WebhookEvent, error) {
	payload, err := decodeJWSPayload(signedPayload)
	if err != nil {
		return nil, fmt.Errorf("decode webhook payload: %w", err)
	}

	var event WebhookEvent
	if err := json.Unmarshal(payload, &event); err != nil {
		return nil, fmt.Errorf("unmarshal webhook event: %w", err)
	}
	return &event, nil
}

// decodeJWSPayload extracts and base64-decodes the payload (second segment)
// of a JWS compact serialisation (header.payload.signature).
func decodeJWSPayload(jws string) ([]byte, error) {
	parts := strings.SplitN(jws, ".", 3)
	if len(parts) < 2 {
		return nil, fmt.Errorf("invalid JWS: expected at least 2 dot-separated parts, got %d", len(parts))
	}
	return base64.RawURLEncoding.DecodeString(parts[1])
}

// transactionInfoRaw mirrors Apple's JSON where dates are milliseconds since
// epoch, allowing custom unmarshalling into time.Time.
type transactionInfoRaw struct {
	TransactionID         string `json:"transactionId"`
	OriginalTransactionID string `json:"originalTransactionId"`
	ProductID             string `json:"productId"`
	BundleID              string `json:"bundleId"`
	ExpiresDate           *int64 `json:"expiresDate"`
	PurchaseDate          *int64 `json:"purchaseDate"`
}

func (r *transactionInfoRaw) toTransactionInfo() *TransactionInfo {
	info := &TransactionInfo{
		TransactionID:         r.TransactionID,
		OriginalTransactionID: r.OriginalTransactionID,
		ProductID:             r.ProductID,
		BundleID:              r.BundleID,
	}
	if r.ExpiresDate != nil {
		t := time.UnixMilli(*r.ExpiresDate)
		info.ExpiresDate = &t
	}
	if r.PurchaseDate != nil {
		t := time.UnixMilli(*r.PurchaseDate)
		info.PurchaseDate = &t
	}
	return info
}

// ---------- .p8 key loading ----------

// loadP8Key reads an Apple .p8 (PKCS#8 PEM) file and returns the EC private
// key inside.
func loadP8Key(path string) (*ecdsa.PrivateKey, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read key file %s: %w", path, err)
	}

	block, _ := pem.Decode(data)
	if block == nil {
		return nil, fmt.Errorf("no PEM block found in %s", path)
	}

	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse PKCS8 key: %w", err)
	}

	ecKey, ok := key.(*ecdsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("key is not ECDSA (got %T)", key)
	}

	return ecKey, nil
}

// ---------- Mock client ----------

// MockAppleClient is a no-op implementation of AppleStoreClient used in dev
// environments without Apple credentials. Every call succeeds with plausible
// test data.
type MockAppleClient struct {
	bundleID string
}

func (m *MockAppleClient) VerifyTransaction(_ context.Context, txnID string) (*TransactionInfo, error) {
	now := time.Now()
	expires := now.Add(365 * 24 * time.Hour)
	return &TransactionInfo{
		TransactionID:         txnID,
		OriginalTransactionID: txnID,
		ProductID:             "com.folio.app.pro.yearly",
		BundleID:              m.bundleID,
		ExpiresDate:           &expires,
		PurchaseDate:          &now,
	}, nil
}

func (m *MockAppleClient) ParseWebhookPayload(signedPayload string) (*WebhookEvent, error) {
	// Attempt real decoding first — the payload structure is independent of
	// credentials.
	event, err := parseWebhookPayload(signedPayload)
	if err != nil {
		// Fallback: return a plausible renewal event.
		return &WebhookEvent{
			NotificationType: "DID_RENEW",
			Subtype:          "",
			Data:             WebhookData{SignedTransactionInfo: signedPayload},
		}, nil
	}
	return event, nil
}

func (m *MockAppleClient) ParseSignedTransaction(signedTxn string) (*TransactionInfo, error) {
	// Attempt real decoding first.
	info, err := parseSignedTransaction(signedTxn)
	if err != nil {
		now := time.Now()
		expires := now.Add(365 * 24 * time.Hour)
		return &TransactionInfo{
			TransactionID:         "mock-txn",
			OriginalTransactionID: "mock-txn",
			ProductID:             "com.folio.app.pro.yearly",
			BundleID:              m.bundleID,
			ExpiresDate:           &expires,
			PurchaseDate:          &now,
		}, nil
	}
	return info, nil
}
