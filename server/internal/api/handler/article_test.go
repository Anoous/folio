package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"unicode/utf8"

	"folio-server/internal/api/middleware"
	"folio-server/internal/domain"
	"folio-server/internal/repository"
	"folio-server/internal/service"
)

// --- Mock article service for handler tests ---

type mockArticleService struct {
	submitURLFn  func(ctx context.Context, userID string, req service.SubmitURLRequest) (*service.SubmitURLResponse, error)
	lastSubmitReq *service.SubmitURLRequest
	lastUserID   string
}

func (m *mockArticleService) SubmitURL(ctx context.Context, userID string, req service.SubmitURLRequest) (*service.SubmitURLResponse, error) {
	m.lastSubmitReq = &req
	m.lastUserID = userID
	if m.submitURLFn != nil {
		return m.submitURLFn(ctx, userID, req)
	}
	return &service.SubmitURLResponse{ArticleID: "art-1", TaskID: "task-1"}, nil
}

func (m *mockArticleService) ListByUser(ctx context.Context, params repository.ListArticlesParams) (*repository.ListArticlesResult, error) {
	return &repository.ListArticlesResult{}, nil
}

func (m *mockArticleService) GetByID(ctx context.Context, userID, articleID string) (*domain.Article, error) {
	return nil, nil
}

func (m *mockArticleService) Update(ctx context.Context, userID, articleID string, params repository.UpdateArticleParams) error {
	return nil
}

func (m *mockArticleService) Delete(ctx context.Context, userID, articleID string) error {
	return nil
}

func (m *mockArticleService) Search(ctx context.Context, userID, query string, page, perPage int) (*repository.ListArticlesResult, error) {
	return &repository.ListArticlesResult{}, nil
}

// newTestArticleHandler creates an ArticleHandler with a mock service for testing.
func newTestArticleHandler(mockSvc *mockArticleService) *ArticleHandler {
	return &ArticleHandler{articleService: mockSvc}
}

// newAuthenticatedRequest creates an HTTP request with userID injected into context
// (simulating the JWT middleware).
func newAuthenticatedRequest(method, url, body, userID string) *http.Request {
	var req *http.Request
	if body != "" {
		req = httptest.NewRequest(method, url, strings.NewReader(body))
	} else {
		req = httptest.NewRequest(method, url, nil)
	}
	req.Header.Set("Content-Type", "application/json")
	ctx := middleware.ContextWithUserID(req.Context(), userID)
	return req.WithContext(ctx)
}

func TestMaxMarkdownContentBytes_Constant(t *testing.T) {
	// Verify the constant is exactly 500 KB
	expected := 500 * 1024
	if maxMarkdownContentBytes != expected {
		t.Errorf("maxMarkdownContentBytes = %d, want %d", maxMarkdownContentBytes, expected)
	}
}

func TestMarkdownContentTruncation(t *testing.T) {
	tests := []struct {
		name       string
		inputLen   int
		wantLen    int
		shouldTrim bool
	}{
		{
			name:       "under limit - no truncation",
			inputLen:   1000,
			wantLen:    1000,
			shouldTrim: false,
		},
		{
			name:       "exactly at limit - no truncation",
			inputLen:   maxMarkdownContentBytes,
			wantLen:    maxMarkdownContentBytes,
			shouldTrim: false,
		},
		{
			name:       "over limit by 1 - truncated",
			inputLen:   maxMarkdownContentBytes + 1,
			wantLen:    maxMarkdownContentBytes,
			shouldTrim: true,
		},
		{
			name:       "well over limit - truncated",
			inputLen:   maxMarkdownContentBytes * 2,
			wantLen:    maxMarkdownContentBytes,
			shouldTrim: true,
		},
		{
			name:       "empty content - no truncation",
			inputLen:   0,
			wantLen:    0,
			shouldTrim: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			content := strings.Repeat("a", tt.inputLen)
			contentPtr := &content

			// Apply the same truncation logic as HandleSubmitURL
			if contentPtr != nil && len(*contentPtr) > maxMarkdownContentBytes {
				truncated := (*contentPtr)[:maxMarkdownContentBytes]
				contentPtr = &truncated
			}

			if len(*contentPtr) != tt.wantLen {
				t.Errorf("len(content) = %d, want %d", len(*contentPtr), tt.wantLen)
			}
		})
	}
}

func TestMarkdownContentTruncation_NilContent(t *testing.T) {
	var contentPtr *string

	// Should not panic on nil
	if contentPtr != nil && len(*contentPtr) > maxMarkdownContentBytes {
		truncated := (*contentPtr)[:maxMarkdownContentBytes]
		contentPtr = &truncated
	}

	if contentPtr != nil {
		t.Errorf("contentPtr = %v, want nil", contentPtr)
	}
}

// --- HandleSubmitURL HTTP handler tests ---

func TestHandleSubmitURL_AllFields_Returns202(t *testing.T) {
	mockSvc := &mockArticleService{}
	h := newTestArticleHandler(mockSvc)

	body := `{
		"url": "https://example.com/article",
		"tag_ids": ["tag-1"],
		"title": "Article Title",
		"author": "Author Name",
		"site_name": "Example Blog",
		"markdown_content": "# Heading\n\nSome content here.",
		"word_count": 1234
	}`

	req := newAuthenticatedRequest("POST", "/api/v1/articles", body, "user-1")
	w := httptest.NewRecorder()

	h.HandleSubmitURL(w, req)

	if w.Code != http.StatusAccepted {
		t.Errorf("status code = %d, want %d", w.Code, http.StatusAccepted)
	}

	var resp service.SubmitURLResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if resp.ArticleID != "art-1" {
		t.Errorf("ArticleID = %q, want %q", resp.ArticleID, "art-1")
	}
	if resp.TaskID != "task-1" {
		t.Errorf("TaskID = %q, want %q", resp.TaskID, "task-1")
	}

	// Verify the request was passed to the service correctly
	if mockSvc.lastUserID != "user-1" {
		t.Errorf("userID = %q, want %q", mockSvc.lastUserID, "user-1")
	}
	sr := mockSvc.lastSubmitReq
	if sr == nil {
		t.Fatal("service.SubmitURL was not called")
	}
	if sr.URL != "https://example.com/article" {
		t.Errorf("req.URL = %q, want %q", sr.URL, "https://example.com/article")
	}
	if sr.Title == nil || *sr.Title != "Article Title" {
		t.Errorf("req.Title = %v, want %q", sr.Title, "Article Title")
	}
	if sr.Author == nil || *sr.Author != "Author Name" {
		t.Errorf("req.Author = %v, want %q", sr.Author, "Author Name")
	}
	if sr.SiteName == nil || *sr.SiteName != "Example Blog" {
		t.Errorf("req.SiteName = %v, want %q", sr.SiteName, "Example Blog")
	}
	if sr.MarkdownContent == nil || *sr.MarkdownContent != "# Heading\n\nSome content here." {
		t.Errorf("req.MarkdownContent = %v, want %q", sr.MarkdownContent, "# Heading\n\nSome content here.")
	}
	if sr.WordCount == nil || *sr.WordCount != 1234 {
		t.Errorf("req.WordCount = %v, want 1234", sr.WordCount)
	}
	if len(sr.TagIDs) != 1 || sr.TagIDs[0] != "tag-1" {
		t.Errorf("req.TagIDs = %v, want [tag-1]", sr.TagIDs)
	}
}

func TestHandleSubmitURL_URLOnly_BackwardCompat_Returns202(t *testing.T) {
	mockSvc := &mockArticleService{}
	h := newTestArticleHandler(mockSvc)

	body := `{"url": "https://example.com/article"}`

	req := newAuthenticatedRequest("POST", "/api/v1/articles", body, "user-1")
	w := httptest.NewRecorder()

	h.HandleSubmitURL(w, req)

	if w.Code != http.StatusAccepted {
		t.Errorf("status code = %d, want %d", w.Code, http.StatusAccepted)
	}

	sr := mockSvc.lastSubmitReq
	if sr == nil {
		t.Fatal("service.SubmitURL was not called")
	}
	if sr.URL != "https://example.com/article" {
		t.Errorf("req.URL = %q, want %q", sr.URL, "https://example.com/article")
	}
	if sr.Title != nil {
		t.Errorf("req.Title = %v, want nil", sr.Title)
	}
	if sr.Author != nil {
		t.Errorf("req.Author = %v, want nil", sr.Author)
	}
	if sr.SiteName != nil {
		t.Errorf("req.SiteName = %v, want nil", sr.SiteName)
	}
	if sr.MarkdownContent != nil {
		t.Errorf("req.MarkdownContent = %v, want nil", sr.MarkdownContent)
	}
	if sr.WordCount != nil {
		t.Errorf("req.WordCount = %v, want nil", sr.WordCount)
	}
}

func TestHandleSubmitURL_LargeMarkdown_Truncated_Returns202(t *testing.T) {
	mockSvc := &mockArticleService{}
	h := newTestArticleHandler(mockSvc)

	// Create markdown content that exceeds 500 KB
	largeContent := strings.Repeat("x", maxMarkdownContentBytes+1000)
	bodyJSON, _ := json.Marshal(map[string]any{
		"url":              "https://example.com/long-article",
		"markdown_content": largeContent,
	})

	req := newAuthenticatedRequest("POST", "/api/v1/articles", string(bodyJSON), "user-1")
	w := httptest.NewRecorder()

	h.HandleSubmitURL(w, req)

	// Should still return 202 (truncated, not rejected)
	if w.Code != http.StatusAccepted {
		t.Errorf("status code = %d, want %d", w.Code, http.StatusAccepted)
	}

	// Verify the markdown content was truncated to exactly maxMarkdownContentBytes
	sr := mockSvc.lastSubmitReq
	if sr == nil {
		t.Fatal("service.SubmitURL was not called")
	}
	if sr.MarkdownContent == nil {
		t.Fatal("req.MarkdownContent should not be nil")
	}
	if len(*sr.MarkdownContent) != maxMarkdownContentBytes {
		t.Errorf("len(req.MarkdownContent) = %d, want %d", len(*sr.MarkdownContent), maxMarkdownContentBytes)
	}
}

func TestHandleSubmitURL_ExactlyAtLimit_NotTruncated(t *testing.T) {
	mockSvc := &mockArticleService{}
	h := newTestArticleHandler(mockSvc)

	// Create markdown content that is exactly at the limit
	exactContent := strings.Repeat("y", maxMarkdownContentBytes)
	bodyJSON, _ := json.Marshal(map[string]any{
		"url":              "https://example.com/exact",
		"markdown_content": exactContent,
	})

	req := newAuthenticatedRequest("POST", "/api/v1/articles", string(bodyJSON), "user-1")
	w := httptest.NewRecorder()

	h.HandleSubmitURL(w, req)

	if w.Code != http.StatusAccepted {
		t.Errorf("status code = %d, want %d", w.Code, http.StatusAccepted)
	}

	sr := mockSvc.lastSubmitReq
	if sr == nil {
		t.Fatal("service.SubmitURL was not called")
	}
	if sr.MarkdownContent == nil {
		t.Fatal("req.MarkdownContent should not be nil")
	}
	// Should NOT be truncated
	if len(*sr.MarkdownContent) != maxMarkdownContentBytes {
		t.Errorf("len(req.MarkdownContent) = %d, want %d", len(*sr.MarkdownContent), maxMarkdownContentBytes)
	}
}

func TestHandleSubmitURL_MissingURL_ReturnsBadRequest(t *testing.T) {
	mockSvc := &mockArticleService{}
	h := newTestArticleHandler(mockSvc)

	body := `{"title": "No URL provided"}`

	req := newAuthenticatedRequest("POST", "/api/v1/articles", body, "user-1")
	w := httptest.NewRecorder()

	h.HandleSubmitURL(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("status code = %d, want %d", w.Code, http.StatusBadRequest)
	}

	var errResp map[string]string
	if err := json.NewDecoder(w.Body).Decode(&errResp); err != nil {
		t.Fatalf("failed to decode error response: %v", err)
	}
	if errResp["error"] != "url is required" {
		t.Errorf("error = %q, want %q", errResp["error"], "url is required")
	}

	// Service should NOT have been called
	if mockSvc.lastSubmitReq != nil {
		t.Error("service.SubmitURL should not have been called when URL is missing")
	}
}

func TestHandleSubmitURL_EmptyURL_ReturnsBadRequest(t *testing.T) {
	mockSvc := &mockArticleService{}
	h := newTestArticleHandler(mockSvc)

	body := `{"url": ""}`

	req := newAuthenticatedRequest("POST", "/api/v1/articles", body, "user-1")
	w := httptest.NewRecorder()

	h.HandleSubmitURL(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("status code = %d, want %d", w.Code, http.StatusBadRequest)
	}

	var errResp map[string]string
	if err := json.NewDecoder(w.Body).Decode(&errResp); err != nil {
		t.Fatalf("failed to decode error response: %v", err)
	}
	if errResp["error"] != "url is required" {
		t.Errorf("error = %q, want %q", errResp["error"], "url is required")
	}
}

func TestHandleSubmitURL_InvalidJSON_ReturnsBadRequest(t *testing.T) {
	mockSvc := &mockArticleService{}
	h := newTestArticleHandler(mockSvc)

	body := `{invalid json}`

	req := newAuthenticatedRequest("POST", "/api/v1/articles", body, "user-1")
	w := httptest.NewRecorder()

	h.HandleSubmitURL(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("status code = %d, want %d", w.Code, http.StatusBadRequest)
	}

	var errResp map[string]string
	if err := json.NewDecoder(w.Body).Decode(&errResp); err != nil {
		t.Fatalf("failed to decode error response: %v", err)
	}
	if errResp["error"] != "invalid request body" {
		t.Errorf("error = %q, want %q", errResp["error"], "invalid request body")
	}
}

func TestHandleSubmitURL_EmptyBody_ReturnsBadRequest(t *testing.T) {
	mockSvc := &mockArticleService{}
	h := newTestArticleHandler(mockSvc)

	req := newAuthenticatedRequest("POST", "/api/v1/articles", "", "user-1")
	w := httptest.NewRecorder()

	h.HandleSubmitURL(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("status code = %d, want %d", w.Code, http.StatusBadRequest)
	}
}

func TestHandleSubmitURL_QuotaExceeded_Returns429(t *testing.T) {
	mockSvc := &mockArticleService{
		submitURLFn: func(ctx context.Context, userID string, req service.SubmitURLRequest) (*service.SubmitURLResponse, error) {
			return nil, service.ErrQuotaExceeded
		},
	}
	h := newTestArticleHandler(mockSvc)

	body := `{"url": "https://example.com"}`

	req := newAuthenticatedRequest("POST", "/api/v1/articles", body, "user-1")
	w := httptest.NewRecorder()

	h.HandleSubmitURL(w, req)

	if w.Code != http.StatusTooManyRequests {
		t.Errorf("status code = %d, want %d", w.Code, http.StatusTooManyRequests)
	}

	var errResp map[string]string
	if err := json.NewDecoder(w.Body).Decode(&errResp); err != nil {
		t.Fatalf("failed to decode error response: %v", err)
	}
	if errResp["error"] != "monthly quota exceeded" {
		t.Errorf("error = %q, want %q", errResp["error"], "monthly quota exceeded")
	}
}

func TestHandleSubmitURL_NilMarkdownContent_NotTruncated(t *testing.T) {
	mockSvc := &mockArticleService{}
	h := newTestArticleHandler(mockSvc)

	// Request with no markdown_content field at all
	body := `{"url": "https://example.com", "title": "Title"}`

	req := newAuthenticatedRequest("POST", "/api/v1/articles", body, "user-1")
	w := httptest.NewRecorder()

	h.HandleSubmitURL(w, req)

	if w.Code != http.StatusAccepted {
		t.Errorf("status code = %d, want %d", w.Code, http.StatusAccepted)
	}

	sr := mockSvc.lastSubmitReq
	if sr == nil {
		t.Fatal("service.SubmitURL was not called")
	}
	if sr.MarkdownContent != nil {
		t.Errorf("req.MarkdownContent = %v, want nil", sr.MarkdownContent)
	}
}

func TestHandleSubmitURL_ResponseContentType(t *testing.T) {
	mockSvc := &mockArticleService{}
	h := newTestArticleHandler(mockSvc)

	body := `{"url": "https://example.com"}`

	req := newAuthenticatedRequest("POST", "/api/v1/articles", body, "user-1")
	w := httptest.NewRecorder()

	h.HandleSubmitURL(w, req)

	contentType := w.Header().Get("Content-Type")
	if contentType != "application/json" {
		t.Errorf("Content-Type = %q, want %q", contentType, "application/json")
	}
}

func TestHandleSubmitURL_UserIDFromContext(t *testing.T) {
	mockSvc := &mockArticleService{}
	h := newTestArticleHandler(mockSvc)

	body := `{"url": "https://example.com"}`

	// Use a specific user ID
	req := newAuthenticatedRequest("POST", "/api/v1/articles", body, "test-user-42")
	w := httptest.NewRecorder()

	h.HandleSubmitURL(w, req)

	if w.Code != http.StatusAccepted {
		t.Errorf("status code = %d, want %d", w.Code, http.StatusAccepted)
	}
	if mockSvc.lastUserID != "test-user-42" {
		t.Errorf("userID = %q, want %q", mockSvc.lastUserID, "test-user-42")
	}
}

func TestMarkdownTruncation_PreservesRuneCount(t *testing.T) {
	// Verify that the truncated content's rune count matches len([]rune(truncated)).
	// This documents that truncation operates on byte boundaries (not rune boundaries),
	// so the resulting rune count may be less than what a rune-based word_count expects.
	tests := []struct {
		name    string
		content string
	}{
		{
			name:    "ASCII only",
			content: strings.Repeat("a", maxMarkdownContentBytes+100),
		},
		{
			name:    "Chinese characters (3 bytes each)",
			content: strings.Repeat("\u4e16\u754c", maxMarkdownContentBytes/3+100), // 世界 repeated
		},
		{
			name:    "Emoji (4 bytes each)",
			content: strings.Repeat("\U0001F600", maxMarkdownContentBytes/4+100), // 😀 repeated
		},
		{
			name: "Mixed ASCII and Chinese at boundary",
			// Fill with ASCII, then add Chinese characters to exceed limit
			content: strings.Repeat("x", maxMarkdownContentBytes-10) + strings.Repeat("\u4e16", 10), // 世 x10 = 30 bytes
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Apply the same truncation logic as HandleSubmitURL
			contentPtr := &tt.content
			if contentPtr != nil && len(*contentPtr) > maxMarkdownContentBytes {
				truncated := (*contentPtr)[:maxMarkdownContentBytes]
				for len(truncated) > 0 && !utf8.ValidString(truncated) {
					truncated = truncated[:len(truncated)-1]
				}
				contentPtr = &truncated
			}

			truncated := *contentPtr

			// The truncated result must be valid UTF-8
			if !utf8.ValidString(truncated) {
				t.Errorf("truncated content is not valid UTF-8")
			}

			// Verify rune count consistency: len([]rune(truncated)) must equal
			// utf8.RuneCountInString(truncated)
			runeSliceLen := len([]rune(truncated))
			runeCountLen := utf8.RuneCountInString(truncated)
			if runeSliceLen != runeCountLen {
				t.Errorf("rune count mismatch: len([]rune()) = %d, RuneCountInString() = %d",
					runeSliceLen, runeCountLen)
			}

			// Byte length must not exceed the limit
			if len(truncated) > maxMarkdownContentBytes {
				t.Errorf("truncated byte length %d exceeds max %d", len(truncated), maxMarkdownContentBytes)
			}
		})
	}
}

func TestMarkdownTruncation_BoundaryWithMixedContent(t *testing.T) {
	// Mix of ASCII and Chinese at the 500KB boundary.
	// Verifies valid UTF-8 output and correct length calculation.
	tests := []struct {
		name            string
		buildContent    func() string
		minExpectedLen  int // minimum expected byte length after truncation
	}{
		{
			name: "ASCII then Chinese at exact boundary",
			buildContent: func() string {
				// ASCII fills most of the space, Chinese chars straddle the boundary
				asciiPart := strings.Repeat("a", maxMarkdownContentBytes-5)
				// 3 Chinese chars = 9 bytes total, so total = maxMarkdownContentBytes + 4
				chinesePart := "\u4e16\u754c\u4f60" // 世界你 = 9 bytes
				return asciiPart + chinesePart
			},
			// After truncation: at most maxMarkdownContentBytes bytes, but may lose
			// up to 2 bytes from the last incomplete Chinese char
			minExpectedLen: maxMarkdownContentBytes - 2,
		},
		{
			name: "Chinese then ASCII at boundary",
			buildContent: func() string {
				// Fill with Chinese chars (3 bytes each), then ASCII to cross boundary
				numChineseChars := (maxMarkdownContentBytes - 10) / 3
				chinesePart := strings.Repeat("\u4e16", numChineseChars)
				asciiPart := strings.Repeat("z", 20) // push well over the limit
				return chinesePart + asciiPart
			},
			minExpectedLen: maxMarkdownContentBytes - 2,
		},
		{
			name: "Alternating ASCII and Chinese throughout",
			buildContent: func() string {
				// Pattern: "aaa世aaa世aaa世..." to create many multi-byte boundaries
				unit := "aaa\u4e16" // 3 + 3 = 6 bytes
				repeats := maxMarkdownContentBytes/6 + 10
				return strings.Repeat(unit, repeats)
			},
			minExpectedLen: maxMarkdownContentBytes - 2,
		},
		{
			name: "Mixed emoji and Chinese",
			buildContent: func() string {
				// 4-byte emoji + 3-byte Chinese chars
				unit := "\U0001F600\u4e16" // 4 + 3 = 7 bytes
				repeats := maxMarkdownContentBytes/7 + 10
				return strings.Repeat(unit, repeats)
			},
			minExpectedLen: maxMarkdownContentBytes - 3, // up to 3 bytes lost for emoji boundary
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			content := tt.buildContent()

			// Verify input exceeds limit
			if len(content) <= maxMarkdownContentBytes {
				t.Fatalf("test content should exceed limit, got %d bytes", len(content))
			}

			mockSvc := &mockArticleService{}
			h := newTestArticleHandler(mockSvc)

			bodyJSON, _ := json.Marshal(map[string]any{
				"url":              "https://example.com/mixed-boundary",
				"markdown_content": content,
			})

			req := newAuthenticatedRequest("POST", "/api/v1/articles", string(bodyJSON), "user-1")
			w := httptest.NewRecorder()

			h.HandleSubmitURL(w, req)

			if w.Code != http.StatusAccepted {
				t.Fatalf("status code = %d, want %d", w.Code, http.StatusAccepted)
			}

			sr := mockSvc.lastSubmitReq
			if sr == nil {
				t.Fatal("service.SubmitURL was not called")
			}
			if sr.MarkdownContent == nil {
				t.Fatal("MarkdownContent should not be nil")
			}

			truncated := *sr.MarkdownContent

			// Must be valid UTF-8
			if !utf8.ValidString(truncated) {
				t.Errorf("truncated content is not valid UTF-8 (len=%d)", len(truncated))
			}

			// Must not exceed byte limit
			if len(truncated) > maxMarkdownContentBytes {
				t.Errorf("truncated byte length %d exceeds max %d", len(truncated), maxMarkdownContentBytes)
			}

			// Must be close to the limit (not losing too many bytes)
			if len(truncated) < tt.minExpectedLen {
				t.Errorf("truncated byte length %d is below minimum expected %d", len(truncated), tt.minExpectedLen)
			}

			// Rune count must be self-consistent
			runeCount := utf8.RuneCountInString(truncated)
			runeSliceCount := len([]rune(truncated))
			if runeCount != runeSliceCount {
				t.Errorf("rune count inconsistency: RuneCountInString=%d, len([]rune())=%d",
					runeCount, runeSliceCount)
			}
		})
	}
}

func TestHandleSubmitURL_LargeMarkdown_UTF8Safe(t *testing.T) {
	// Chinese characters are 3 bytes each in UTF-8.
	// Build content: fill up to just under the limit with ASCII, then place multi-byte
	// characters right at the 500KB boundary so a naive byte slice would split a character.

	tests := []struct {
		name    string
		content string // content to build that straddles the boundary
	}{
		{
			name: "Chinese characters at boundary",
			// Fill with ASCII 'a' up to (maxMarkdownContentBytes - 2), then add a
			// 3-byte Chinese character. Total = maxMarkdownContentBytes + 1 byte,
			// so it triggers truncation. Naive [:maxMarkdownContentBytes] would cut
			// the 3-byte char after 2 bytes, producing invalid UTF-8.
			content: strings.Repeat("a", maxMarkdownContentBytes-2) + "\u4e16", // 世 = 3 bytes
		},
		{
			name: "Emoji at boundary (4-byte character)",
			// Fill with ASCII 'b' up to (maxMarkdownContentBytes - 3), then a 4-byte emoji.
			// Total = maxMarkdownContentBytes + 1. Naive cut splits the emoji.
			content: strings.Repeat("b", maxMarkdownContentBytes-3) + "\U0001F600", // 😀 = 4 bytes
		},
		{
			name: "Many Chinese characters exceeding limit",
			// Each Chinese char is 3 bytes. This creates content well over the limit
			// composed entirely of multi-byte characters.
			content: strings.Repeat("\u4e16\u754c\u4f60\u597d", maxMarkdownContentBytes/4+100), // 世界你好 repeated
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockSvc := &mockArticleService{}
			h := newTestArticleHandler(mockSvc)

			bodyJSON, _ := json.Marshal(map[string]any{
				"url":              "https://example.com/utf8-test",
				"markdown_content": tt.content,
			})

			req := newAuthenticatedRequest("POST", "/api/v1/articles", string(bodyJSON), "user-1")
			w := httptest.NewRecorder()

			h.HandleSubmitURL(w, req)

			if w.Code != http.StatusAccepted {
				t.Fatalf("status code = %d, want %d", w.Code, http.StatusAccepted)
			}

			sr := mockSvc.lastSubmitReq
			if sr == nil {
				t.Fatal("service.SubmitURL was not called")
			}
			if sr.MarkdownContent == nil {
				t.Fatal("MarkdownContent should not be nil after truncation")
			}

			truncated := *sr.MarkdownContent

			// The truncated result must be valid UTF-8
			if !utf8.ValidString(truncated) {
				t.Errorf("truncated content is not valid UTF-8 (len=%d)", len(truncated))
			}

			// The truncated result must not exceed the byte limit
			if len(truncated) > maxMarkdownContentBytes {
				t.Errorf("truncated content length %d exceeds max %d", len(truncated), maxMarkdownContentBytes)
			}

			// The truncated result should be close to the limit (at most 3 bytes less
			// for a 4-byte char boundary adjustment)
			if len(truncated) < maxMarkdownContentBytes-3 {
				t.Errorf("truncated content length %d is too far below max %d (lost more than 3 bytes)", len(truncated), maxMarkdownContentBytes)
			}
		})
	}
}
