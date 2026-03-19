"""Tests for manual content submission (no URL)."""

from helpers.assertions import assert_uuid, assert_error_response
from helpers.polling import poll_until_done


class TestManualContentSubmission:
    """Test POST /api/v1/articles/manual."""

    def test_submit_short_thought(self, fresh_api):
        resp = fresh_api.submit_manual("This is a quick thought about knowledge management")
        assert resp.status_code == 202
        body = resp.json()
        assert_uuid(body["article_id"], "article_id")
        assert_uuid(body["task_id"], "task_id")

    def test_submit_long_content(self, fresh_api):
        content = "Deep learning fundamentals. " * 100
        resp = fresh_api.submit_manual(content, title="Deep Learning Notes")
        assert resp.status_code == 202

    def test_submit_with_title(self, fresh_api):
        resp = fresh_api.submit_manual(
            content="Some thoughts here",
            title="My Custom Title"
        )
        assert resp.status_code == 202
        body = resp.json()
        article = fresh_api.get_article(body["article_id"]).json()
        assert article["title"] == "My Custom Title"

    def test_submit_empty_content_rejected(self, fresh_api):
        resp = fresh_api.submit_manual("")
        assert_error_response(resp, 400, error_contains="content")

    def test_submit_whitespace_only_rejected(self, fresh_api):
        resp = fresh_api.submit_manual("   \n\t  ")
        assert_error_response(resp, 400, error_contains="content")

    def test_source_type_is_manual(self, fresh_api):
        resp = fresh_api.submit_manual("Testing source type")
        body = resp.json()
        article = fresh_api.get_article(body["article_id"]).json()
        assert article["source_type"] == "manual"

    def test_no_url_in_article(self, fresh_api):
        resp = fresh_api.submit_manual("A thought without URL")
        body = resp.json()
        article = fresh_api.get_article(body["article_id"]).json()
        assert article.get("url") is None or article.get("url") == ""


class TestManualContentPipeline:
    """Test AI pipeline for manual content."""

    def test_ai_processes_manual_content(self, api):
        resp = api.submit_manual("Artificial intelligence and machine learning are transforming software development")
        body = resp.json()
        task = poll_until_done(api, body["task_id"], timeout=60)
        assert task["status"] == "done"
        article = api.get_article(body["article_id"]).json()
        assert article["status"] == "ready"
        assert article.get("category") is not None
        assert article.get("summary") is not None

    def test_title_backfill_when_no_title(self, api):
        resp = api.submit_manual("The future of distributed systems lies in consensus algorithms")
        body = resp.json()
        poll_until_done(api, body["task_id"], timeout=60)
        article = api.get_article(body["article_id"]).json()
        assert article.get("title") is not None
        assert len(article["title"]) > 0

    def test_title_not_overwritten_when_provided(self, api):
        resp = api.submit_manual(
            content="Some content about technology",
            title="My Original Title"
        )
        body = resp.json()
        poll_until_done(api, body["task_id"], timeout=60)
        article = api.get_article(body["article_id"]).json()
        assert article["title"] == "My Original Title"


class TestManualContentDuplication:

    def test_duplicate_content_allowed(self, fresh_api):
        content = "Repeated thought about productivity"
        resp1 = fresh_api.submit_manual(content)
        resp2 = fresh_api.submit_manual(content)
        assert resp1.status_code == 202
        assert resp2.status_code == 202
        assert resp1.json()["article_id"] != resp2.json()["article_id"]
