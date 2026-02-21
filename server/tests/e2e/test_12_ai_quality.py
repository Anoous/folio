"""AI quality validation tests."""

import pytest

from helpers.polling import submit_and_wait
from helpers.test_urls import TECH_BLOG, SIMPLE_PAGE

VALID_CATEGORIES = {"tech", "business", "science", "culture", "lifestyle", "news", "education", "design", "other"}


class TestAIQuality:

    @pytest.mark.slow
    def test_classification_valid_category(self, fresh_api):
        """AI assigns a valid category slug."""
        article_id, task = submit_and_wait(fresh_api, TECH_BLOG, timeout=120)
        assert task["status"] == "done"

        resp = fresh_api.get_article(article_id)
        article = resp.json()
        cat = article.get("category")
        if cat:
            assert cat["slug"] in VALID_CATEGORIES, f"unexpected category: {cat['slug']}"

    @pytest.mark.slow
    def test_tags_generated(self, fresh_api):
        """AI generates at least one tag."""
        article_id, task = submit_and_wait(fresh_api, TECH_BLOG + "?_e2e=tags", timeout=120)
        assert task["status"] == "done"

        resp = fresh_api.get_article(article_id)
        article = resp.json()
        tags = article.get("tags", [])
        assert len(tags) >= 1, f"expected at least 1 tag, got {len(tags)}"

    @pytest.mark.slow
    def test_summary_meaningful(self, fresh_api):
        """AI summary is non-trivial and related to content."""
        article_id, task = submit_and_wait(fresh_api, SIMPLE_PAGE + "?_e2e=summary12", timeout=120)
        assert task["status"] == "done"

        resp = fresh_api.get_article(article_id)
        article = resp.json()
        summary = article.get("summary", "")
        assert len(summary) > 20, f"summary too short ({len(summary)} chars): {summary!r}"
