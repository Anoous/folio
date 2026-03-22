package client

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"time"
)

// ResendClient sends transactional emails via the Resend API.
// When apiKey is empty, it falls back to logging the email content.
type ResendClient struct {
	apiKey     string
	fromAddr   string
	httpClient *http.Client
}

func NewResendClient(apiKey, fromAddr string) *ResendClient {
	return &ResendClient{
		apiKey:     apiKey,
		fromAddr:   fromAddr,
		httpClient: &http.Client{Timeout: 10 * time.Second},
	}
}

type resendRequest struct {
	From    string `json:"from"`
	To      []string `json:"to"`
	Subject string `json:"subject"`
	HTML    string `json:"html"`
}

func (c *ResendClient) SendVerificationCode(to, code string) error {
	if c.apiKey == "" {
		slog.Info("[EMAIL] (no Resend key, logging only)", "to", to, "code", code)
		return nil
	}

	html := fmt.Sprintf(`
<div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 400px; margin: 0 auto; padding: 40px 20px;">
  <h2 style="color: #1a1a1a; margin-bottom: 8px;">EchoLore</h2>
  <p style="color: #666; font-size: 15px;">Your verification code:</p>
  <div style="background: #f5f5f5; border-radius: 12px; padding: 24px; text-align: center; margin: 24px 0;">
    <span style="font-size: 32px; font-weight: 600; letter-spacing: 8px; color: #1a1a1a;">%s</span>
  </div>
  <p style="color: #999; font-size: 13px;">This code expires in 5 minutes. If you didn't request this, please ignore.</p>
</div>`, code)

	body := resendRequest{
		From:    c.fromAddr,
		To:      []string{to},
		Subject: fmt.Sprintf("EchoLore verification code: %s", code),
		HTML:    html,
	}

	jsonBody, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("marshal email body: %w", err)
	}

	req, err := http.NewRequest("POST", "https://api.resend.com/emails", bytes.NewReader(jsonBody))
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("send email: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		respBody, _ := io.ReadAll(resp.Body)
		slog.Error("resend API error", "status", resp.StatusCode, "body", string(respBody))
		return fmt.Errorf("resend API returned %d: %s", resp.StatusCode, string(respBody))
	}

	slog.Info("[EMAIL] verification code sent", "to", to)
	return nil
}
