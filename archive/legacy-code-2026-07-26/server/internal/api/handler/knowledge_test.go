package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"folio-server/internal/service"
)

type mockKnowledgeService struct {
	lastUserID string
	lastPrompt string
}

func (m *mockKnowledgeService) Spark(ctx context.Context, userID, prompt string) (*service.KnowledgeSparkResult, error) {
	m.lastUserID = userID
	m.lastPrompt = prompt
	return &service.KnowledgeSparkResult{
		Insights: []service.KnowledgeSparkInsight{
			{
				Insight:          "Insight one",
				WhyItMatters:     "Why one",
				SourceIDs:        []string{"a1", "a2"},
				FollowupQuestion: "Follow one?",
			},
		},
	}, nil
}

func (m *mockKnowledgeService) Learn(ctx context.Context, userID, prompt string) (*service.KnowledgeLearnResult, error) {
	m.lastUserID = userID
	m.lastPrompt = prompt
	return &service.KnowledgeLearnResult{
		Summary: "Learn summary",
		Items: []service.KnowledgeLearnItem{
			{
				Type:      "concept",
				Title:     "Concept one",
				Content:   "Content one",
				SourceIDs: []string{"a1"},
			},
		},
	}, nil
}

func TestHandleSpark_ReturnsStructuredResponse(t *testing.T) {
	mockSvc := &mockKnowledgeService{}
	h := NewKnowledgeHandler(mockSvc)

	req := newAuthenticatedRequest(http.MethodPost, "/api/v1/knowledge/spark", `{"prompt":"找灵感"}`, "user-1")
	w := httptest.NewRecorder()

	h.HandleSpark(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}
	if mockSvc.lastUserID != "user-1" {
		t.Fatalf("lastUserID = %q, want %q", mockSvc.lastUserID, "user-1")
	}
	if mockSvc.lastPrompt != "找灵感" {
		t.Fatalf("lastPrompt = %q, want %q", mockSvc.lastPrompt, "找灵感")
	}

	var resp struct {
		Insights []struct {
			Insight          string   `json:"insight"`
			WhyItMatters     string   `json:"why_it_matters"`
			SourceIDs        []string `json:"source_ids"`
			FollowupQuestion string   `json:"followup_question"`
		} `json:"insights"`
	}
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if len(resp.Insights) != 1 {
		t.Fatalf("insight count = %d, want 1", len(resp.Insights))
	}
	if resp.Insights[0].Insight != "Insight one" {
		t.Fatalf("insight = %q, want %q", resp.Insights[0].Insight, "Insight one")
	}
}

func TestHandleLearn_ReturnsStructuredResponse(t *testing.T) {
	mockSvc := &mockKnowledgeService{}
	h := NewKnowledgeHandler(mockSvc)

	req := newAuthenticatedRequest(http.MethodPost, "/api/v1/knowledge/learn", `{"prompt":"帮我复习"}`, "user-1")
	w := httptest.NewRecorder()

	h.HandleLearn(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}
	if mockSvc.lastPrompt != "帮我复习" {
		t.Fatalf("lastPrompt = %q, want %q", mockSvc.lastPrompt, "帮我复习")
	}

	var resp struct {
		Summary string `json:"summary"`
		Items   []struct {
			Type      string   `json:"type"`
			Title     string   `json:"title"`
			Content   string   `json:"content"`
			SourceIDs []string `json:"source_ids"`
		} `json:"items"`
	}
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if resp.Summary != "Learn summary" {
		t.Fatalf("summary = %q, want %q", resp.Summary, "Learn summary")
	}
	if len(resp.Items) != 1 {
		t.Fatalf("item count = %d, want 1", len(resp.Items))
	}
}

func TestHandleSpark_InvalidBody_Returns400(t *testing.T) {
	mockSvc := &mockKnowledgeService{}
	h := NewKnowledgeHandler(mockSvc)

	req := newAuthenticatedRequest(http.MethodPost, "/api/v1/knowledge/spark", `{`, "user-1")
	w := httptest.NewRecorder()

	h.HandleSpark(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusBadRequest)
	}
}
