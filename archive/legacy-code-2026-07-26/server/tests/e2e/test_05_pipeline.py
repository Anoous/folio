"""Full async pipeline tests (submit → crawl → AI → done)."""

import pytest

from helpers.assertions import assert_uuid
from helpers.polling import poll_until_done, submit_and_wait
from helpers.test_urls import unique_content_url, unique_url, SIMPLE_PAGE


class TestPipeline:

    @pytest.mark.smoke
    @pytest.mark.slow
    def test_full_pipeline_completes(self, fresh_api):
        """Submit a URL and verify the pipeline reaches 'done'."""
        url = unique_url("pipeline-full")
        article_id, task = submit_and_wait(fresh_api, url, timeout=90)
        assert task["status"] == "done"
        assert_uuid(article_id)

    @pytest.mark.slow
    def test_client_content_pipeline_completes(self, fresh_api):
        """Submit client-provided URL content and verify the ingestion pipeline completes."""
        markdown = (
            "# Client Supplied Note\n\n"
            "Durable ingestion pipelines keep queue handoff, retries, and article state aligned."
        )
        resp = fresh_api.submit_url(
            unique_content_url("pipeline-client-content"),
            title="Client Supplied Note",
            markdown_content=markdown,
            word_count=11,
        )
        assert resp.status_code == 202
        payload = resp.json()
        task = poll_until_done(fresh_api, payload["task_id"], timeout=90)
        assert task["status"] == "done"

        article = fresh_api.get_article(payload["article_id"]).json()
        assert article["status"] == "ready"
        assert "Durable ingestion pipelines" in article.get("markdown_content", "")

    @pytest.mark.slow
    def test_completed_article_has_ai_fields(self, api, completed_article):
        """After pipeline, article has AI-generated fields."""
        article_id, _ = completed_article
        resp = api.get_article(article_id)
        assert resp.status_code == 200
        article = resp.json()

        assert article["status"] == "ready"
        assert article.get("ai_confidence") is not None
        assert article["ai_confidence"] >= 0.3

    @pytest.mark.slow
    def test_task_timestamps(self, api, completed_article):
        """Completed task has all expected timestamps."""
        _, task = completed_article
        assert task.get("crawl_started_at") is not None
        assert task.get("crawl_finished_at") is not None
        assert task.get("ai_started_at") is not None
        assert task.get("ai_finished_at") is not None

    @pytest.mark.slow
    def test_ai_summary_quality(self, fresh_api):
        """AI summary should be meaningful."""
        article_id, task = submit_and_wait(fresh_api, SIMPLE_PAGE, timeout=120)
        assert task["status"] == "done"

        resp = fresh_api.get_article(article_id)
        article = resp.json()
        summary = article.get("summary", "")
        assert len(summary) > 20, f"summary too short: {summary!r}"
