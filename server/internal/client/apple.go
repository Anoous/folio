package client

import (
	"context"
	"crypto/ecdsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"math/big"
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

// appleRootCAPEM is Apple Root CA - G3, used to verify the certificate chain
// in JWS payloads from App Store Server Notifications.
const appleRootCAPEM = `-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3GKhkYO5TsEwFBOLC7ABRISA
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCd7BAtljYhR0hl/gz7BYvfDYQ3YEOOmQEfF4ixdNHQxD4rvs/MNRzKpV0k
LHKDGGICMG5C8t30og64eu7Q3LyNT8LNEP693gHDPAHF7ixiKRjNPpdxBYvLGqm/
fhEzO1cjdw==
-----END CERTIFICATE-----`

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

// parseSignedTransaction verifies the JWS signature against Apple's
// certificate chain and unmarshals the payload into TransactionInfo.
func parseSignedTransaction(signed string) (*TransactionInfo, error) {
	payload, err := verifyAndDecodeJWSPayload(signed)
	if err != nil {
		return nil, fmt.Errorf("verify signed transaction: %w", err)
	}

	var raw transactionInfoRaw
	if err := json.Unmarshal(payload, &raw); err != nil {
		return nil, fmt.Errorf("unmarshal transaction info: %w", err)
	}

	return raw.toTransactionInfo(), nil
}

// parseWebhookPayload verifies the JWS signature against Apple's certificate
// chain and unmarshals the payload into WebhookEvent.
func parseWebhookPayload(signedPayload string) (*WebhookEvent, error) {
	payload, err := verifyAndDecodeJWSPayload(signedPayload)
	if err != nil {
		return nil, fmt.Errorf("verify webhook payload: %w", err)
	}

	var event WebhookEvent
	if err := json.Unmarshal(payload, &event); err != nil {
		return nil, fmt.Errorf("unmarshal webhook event: %w", err)
	}
	return &event, nil
}

// decodeJWSPayload extracts and base64-decodes the payload (second segment)
// of a JWS compact serialisation (header.payload.signature). This does NOT
// verify the signature and is only used by MockAppleClient.
func decodeJWSPayload(jws string) ([]byte, error) {
	parts := strings.SplitN(jws, ".", 3)
	if len(parts) < 2 {
		return nil, fmt.Errorf("invalid JWS: expected at least 2 dot-separated parts, got %d", len(parts))
	}
	return base64.RawURLEncoding.DecodeString(parts[1])
}

// verifyAndDecodeJWSPayload verifies the JWS signature against Apple's
// certificate chain (x5c header → intermediate → Apple Root CA G3) and
// returns the decoded payload bytes on success.
func verifyAndDecodeJWSPayload(jwsCompact string) ([]byte, error) {
	parts := strings.SplitN(jwsCompact, ".", 3)
	if len(parts) != 3 {
		return nil, fmt.Errorf("invalid JWS: expected 3 dot-separated parts, got %d", len(parts))
	}
	headerB64, payloadB64, sigB64 := parts[0], parts[1], parts[2]

	// --- 1. Parse JWS header to extract x5c and alg ---
	headerBytes, err := base64.RawURLEncoding.DecodeString(headerB64)
	if err != nil {
		return nil, fmt.Errorf("decode JWS header: %w", err)
	}

	var header struct {
		Alg string   `json:"alg"`
		X5c []string `json:"x5c"`
	}
	if err := json.Unmarshal(headerBytes, &header); err != nil {
		return nil, fmt.Errorf("parse JWS header: %w", err)
	}

	if header.Alg != "ES256" {
		return nil, fmt.Errorf("unsupported JWS algorithm: %s (expected ES256)", header.Alg)
	}
	if len(header.X5c) < 2 {
		return nil, fmt.Errorf("x5c chain too short: need at least 2 certificates, got %d", len(header.X5c))
	}

	// --- 2. Build certificate chain from x5c ---
	certs := make([]*x509.Certificate, len(header.X5c))
	for i, certB64 := range header.X5c {
		certDER, err := base64.StdEncoding.DecodeString(certB64)
		if err != nil {
			return nil, fmt.Errorf("decode x5c[%d]: %w", i, err)
		}
		cert, err := x509.ParseCertificate(certDER)
		if err != nil {
			return nil, fmt.Errorf("parse x5c[%d]: %w", i, err)
		}
		certs[i] = cert
	}

	// --- 3. Verify certificate chain against Apple Root CA G3 ---
	block, _ := pem.Decode([]byte(appleRootCAPEM))
	if block == nil {
		return nil, fmt.Errorf("failed to decode Apple Root CA PEM")
	}
	rootCert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse Apple Root CA: %w", err)
	}

	rootPool := x509.NewCertPool()
	rootPool.AddCert(rootCert)

	intermediatePool := x509.NewCertPool()
	for _, cert := range certs[1:] {
		intermediatePool.AddCert(cert)
	}

	leaf := certs[0]
	if _, err := leaf.Verify(x509.VerifyOptions{
		Roots:         rootPool,
		Intermediates: intermediatePool,
	}); err != nil {
		return nil, fmt.Errorf("certificate chain verification failed: %w", err)
	}

	// --- 4. Verify JWS ES256 signature ---
	sigBytes, err := base64.RawURLEncoding.DecodeString(sigB64)
	if err != nil {
		return nil, fmt.Errorf("decode JWS signature: %w", err)
	}

	// ES256 JWS signature is 64 bytes in IEEE P1363 format: R (32) || S (32).
	if len(sigBytes) != 64 {
		return nil, fmt.Errorf("invalid ES256 signature length: expected 64 bytes, got %d", len(sigBytes))
	}

	r := new(big.Int).SetBytes(sigBytes[:32])
	s := new(big.Int).SetBytes(sigBytes[32:])

	pubKey, ok := leaf.PublicKey.(*ecdsa.PublicKey)
	if !ok {
		return nil, fmt.Errorf("leaf certificate public key is not ECDSA")
	}

	// Signing input for JWS is ASCII(header_b64url || '.' || payload_b64url).
	signingInput := []byte(headerB64 + "." + payloadB64)
	hash := sha256.Sum256(signingInput)

	if !ecdsa.Verify(pubKey, hash[:], r, s) {
		return nil, fmt.Errorf("JWS signature verification failed")
	}

	// --- 5. Decode and return payload ---
	payload, err := base64.RawURLEncoding.DecodeString(payloadB64)
	if err != nil {
		return nil, fmt.Errorf("decode JWS payload: %w", err)
	}

	return payload, nil
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
	// Attempt decoding without signature verification — mock payloads are
	// not signed by Apple.
	payload, err := decodeJWSPayload(signedPayload)
	if err != nil {
		// Fallback: return a plausible renewal event.
		return &WebhookEvent{
			NotificationType: "DID_RENEW",
			Subtype:          "",
			Data:             WebhookData{SignedTransactionInfo: signedPayload},
		}, nil
	}
	var event WebhookEvent
	if err := json.Unmarshal(payload, &event); err != nil {
		return &WebhookEvent{
			NotificationType: "DID_RENEW",
			Subtype:          "",
			Data:             WebhookData{SignedTransactionInfo: signedPayload},
		}, nil
	}
	return &event, nil
}

func (m *MockAppleClient) ParseSignedTransaction(signedTxn string) (*TransactionInfo, error) {
	// Attempt decoding without signature verification — mock payloads are
	// not signed by Apple.
	payload, err := decodeJWSPayload(signedTxn)
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
	var raw transactionInfoRaw
	if err := json.Unmarshal(payload, &raw); err != nil {
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
	return raw.toTransactionInfo(), nil
}
