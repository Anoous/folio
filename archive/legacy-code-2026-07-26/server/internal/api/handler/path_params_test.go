package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func assertErrorResponse(t *testing.T, recorder *httptest.ResponseRecorder, wantStatus int, wantError string) {
	t.Helper()

	if recorder.Code != wantStatus {
		t.Fatalf("status code = %d, want %d", recorder.Code, wantStatus)
	}

	var body map[string]string
	if err := json.NewDecoder(recorder.Body).Decode(&body); err != nil {
		t.Fatalf("decode error response: %v", err)
	}
	if body["error"] != wantError {
		t.Fatalf("error = %q, want %q", body["error"], wantError)
	}
}

func TestHandleGetArticle_InvalidUUID_ReturnsBadRequest(t *testing.T) {
	h := &ArticleHandler{userRepo: &mockUserGetter{}}
	req := newAuthenticatedRequest(http.MethodGet, "/api/v1/articles/not-a-uuid", "", "user-1")
	req = withURLParam(req, "id", "not-a-uuid")
	w := httptest.NewRecorder()

	h.HandleGetArticle(w, req)

	assertErrorResponse(t, w, http.StatusBadRequest, "invalid article id")
}

func TestHandleUpdateArticle_InvalidUUID_ReturnsBadRequest(t *testing.T) {
	h := &ArticleHandler{userRepo: &mockUserGetter{}}
	req := newAuthenticatedRequest(http.MethodPut, "/api/v1/articles/not-a-uuid", `{"is_favorite":true}`, "user-1")
	req = withURLParam(req, "id", "not-a-uuid")
	w := httptest.NewRecorder()

	h.HandleUpdateArticle(w, req)

	assertErrorResponse(t, w, http.StatusBadRequest, "invalid article id")
}

func TestHandleDeleteArticle_InvalidUUID_ReturnsBadRequest(t *testing.T) {
	h := &ArticleHandler{userRepo: &mockUserGetter{}}
	req := newAuthenticatedRequest(http.MethodDelete, "/api/v1/articles/not-a-uuid", "", "user-1")
	req = withURLParam(req, "id", "not-a-uuid")
	w := httptest.NewRecorder()

	h.HandleDeleteArticle(w, req)

	assertErrorResponse(t, w, http.StatusBadRequest, "invalid article id")
}

func TestHandleRetryArticle_InvalidUUID_ReturnsBadRequest(t *testing.T) {
	h := &ArticleHandler{userRepo: &mockUserGetter{}}
	req := newAuthenticatedRequest(http.MethodPost, "/api/v1/articles/not-a-uuid/retry", "", "user-1")
	req = withURLParam(req, "id", "not-a-uuid")
	w := httptest.NewRecorder()

	h.HandleRetryArticle(w, req)

	assertErrorResponse(t, w, http.StatusBadRequest, "invalid article id")
}

func TestHandleGetTask_InvalidUUID_ReturnsBadRequest(t *testing.T) {
	h := &TaskHandler{}
	req := newAuthenticatedRequest(http.MethodGet, "/api/v1/tasks/not-a-uuid", "", "user-1")
	req = withURLParam(req, "id", "not-a-uuid")
	w := httptest.NewRecorder()

	h.HandleGetTask(w, req)

	assertErrorResponse(t, w, http.StatusBadRequest, "invalid task id")
}

func TestHandleGetRelated_InvalidUUID_ReturnsBadRequest(t *testing.T) {
	h := &RelationHandler{}
	req := newAuthenticatedRequest(http.MethodGet, "/api/v1/articles/not-a-uuid/related", "", "user-1")
	req = withURLParam(req, "id", "not-a-uuid")
	w := httptest.NewRecorder()

	h.HandleGetRelated(w, req)

	assertErrorResponse(t, w, http.StatusBadRequest, "invalid article id")
}

func TestHandleDeleteTag_InvalidUUID_ReturnsBadRequest(t *testing.T) {
	h := &TagHandler{}
	req := newAuthenticatedRequest(http.MethodDelete, "/api/v1/tags/not-a-uuid", "", "user-1")
	req = withURLParam(req, "id", "not-a-uuid")
	w := httptest.NewRecorder()

	h.HandleDeleteTag(w, req)

	assertErrorResponse(t, w, http.StatusBadRequest, "invalid tag id")
}

func TestHandleCreateHighlight_InvalidUUID_ReturnsBadRequest(t *testing.T) {
	h := &HighlightHandler{}
	req := newAuthenticatedRequest(http.MethodPost, "/api/v1/articles/not-a-uuid/highlights", `{"text":"x","start_offset":0,"end_offset":1}`, "user-1")
	req = withURLParam(req, "id", "not-a-uuid")
	w := httptest.NewRecorder()

	h.HandleCreateHighlight(w, req)

	assertErrorResponse(t, w, http.StatusBadRequest, "invalid article id")
}

func TestHandleGetHighlights_InvalidUUID_ReturnsBadRequest(t *testing.T) {
	h := &HighlightHandler{}
	req := newAuthenticatedRequest(http.MethodGet, "/api/v1/articles/not-a-uuid/highlights", "", "user-1")
	req = withURLParam(req, "id", "not-a-uuid")
	w := httptest.NewRecorder()

	h.HandleGetHighlights(w, req)

	assertErrorResponse(t, w, http.StatusBadRequest, "invalid article id")
}

func TestHandleDeleteHighlight_InvalidUUID_ReturnsBadRequest(t *testing.T) {
	h := &HighlightHandler{}
	req := newAuthenticatedRequest(http.MethodDelete, "/api/v1/highlights/not-a-uuid", "", "user-1")
	req = withURLParam(req, "id", "not-a-uuid")
	w := httptest.NewRecorder()

	h.HandleDeleteHighlight(w, req)

	assertErrorResponse(t, w, http.StatusBadRequest, "invalid highlight id")
}

func TestHandleSubmitReview_InvalidUUID_ReturnsBadRequest(t *testing.T) {
	h := &EchoHandler{}
	req := newAuthenticatedRequest(http.MethodPost, "/api/v1/echo/not-a-uuid/review", `{"result":"remembered"}`, "user-1")
	req = withURLParam(req, "id", "not-a-uuid")
	w := httptest.NewRecorder()

	h.HandleSubmitReview(w, req)

	assertErrorResponse(t, w, http.StatusBadRequest, "invalid card id")
}
