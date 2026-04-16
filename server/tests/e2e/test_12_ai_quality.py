"""AI quality validation tests."""

import pytest

from helpers.polling import poll_until_done
from helpers.test_urls import unique_content_url

VALID_CATEGORIES = {"tech", "business", "science", "culture", "lifestyle", "news", "education", "design", "other"}

TECH_MARKDOWN = """# Go Runtime Scheduling Notes

Go 1.22 improves loop variable semantics and reduces a class of bugs that used to appear in concurrent code.
That matters for production systems because subtle closure mistakes often survive code review and only surface under load.

The scheduler is only one part of the story. Teams that ship reliable services usually combine efficient goroutine usage,
aggressive profiling, and careful backpressure control so latency does not collapse during traffic spikes.

In practice, the real leverage comes from pairing language ergonomics with system design discipline: clear ownership,
bounded concurrency, structured observability, and predictable retry behavior.
"""


class TestAIQuality:

    @pytest.mark.slow
    def test_classification_valid_category(self, fresh_api):
        """AI assigns a valid category slug for client-provided content."""
        resp = fresh_api.submit_url(
            unique_content_url("ai-category"),
            title="Go Runtime Scheduling Notes",
            site_name="Folio E2E",
            markdown_content=TECH_MARKDOWN,
        )
        assert resp.status_code == 202

        body = resp.json()
        article_id = body["article_id"]
        task = poll_until_done(fresh_api, body["task_id"], timeout=120)
        assert task["status"] == "done"

        resp = fresh_api.get_article(article_id)
        article = resp.json()
        cat = article.get("category")
        if cat:
            assert cat["slug"] in VALID_CATEGORIES, f"unexpected category: {cat['slug']}"

    @pytest.mark.slow
    def test_tags_generated(self, fresh_api):
        """AI generates at least one tag for client-provided content."""
        resp = fresh_api.submit_url(
            unique_content_url("ai-tags"),
            title="Go Runtime Scheduling Notes",
            site_name="Folio E2E",
            markdown_content=TECH_MARKDOWN,
        )
        assert resp.status_code == 202

        body = resp.json()
        article_id = body["article_id"]
        task = poll_until_done(fresh_api, body["task_id"], timeout=120)
        assert task["status"] == "done"

        resp = fresh_api.get_article(article_id)
        article = resp.json()
        tags = article.get("tags", [])
        assert len(tags) >= 1, f"expected at least 1 tag, got {len(tags)}"

    @pytest.mark.slow
    def test_summary_meaningful(self, fresh_api):
        """AI summary is non-trivial for client-provided content."""
        resp = fresh_api.submit_url(
            unique_content_url("ai-summary"),
            title="Go Runtime Scheduling Notes",
            site_name="Folio E2E",
            markdown_content=TECH_MARKDOWN,
        )
        assert resp.status_code == 202

        body = resp.json()
        article_id = body["article_id"]
        task = poll_until_done(fresh_api, body["task_id"], timeout=120)
        assert task["status"] == "done"

        resp = fresh_api.get_article(article_id)
        article = resp.json()
        summary = article.get("summary", "")
        assert len(summary) > 20, f"summary too short ({len(summary)} chars): {summary!r}"
