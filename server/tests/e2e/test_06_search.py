"""Search endpoint tests."""

import pytest

from helpers.assertions import assert_pagination, assert_error_response
from helpers.polling import poll_until_done


class TestSearch:

    def test_search_requires_query(self, api):
        """GET /articles/search without q returns 400."""
        resp = api.search("")
        # The handler checks for empty q
        assert_error_response(resp, 400)

    @pytest.mark.smoke
    def test_search_returns_results(self, api, completed_article):
        """Search for a completed article returns at least one result."""
        article_id, _ = completed_article
        # Get the article to find its URL/title for searching
        art = api.get_article(article_id).json()
        # Search by a broad term — "example" or "completed" should work
        resp = api.search("example", page=1, per_page=10)
        assert resp.status_code == 200
        body = resp.json()
        assert_pagination(body)

    def test_search_no_results(self, api):
        """Search for gibberish returns empty data array."""
        resp = api.search("xyznonexistent99999")
        assert resp.status_code == 200
        body = resp.json()
        assert_pagination(body)
        assert len(body["data"]) == 0

    def test_search_pagination_params(self, api):
        """Search respects page and per_page."""
        resp = api.search("test", page=1, per_page=5)
        assert resp.status_code == 200
        body = resp.json()
        assert body["pagination"]["page"] == 1
        assert body["pagination"]["per_page"] == 5

    def test_search_falls_back_to_evidence_retrieval(self, fresh_api):
        """Default search should still find evidence that only exists in the body."""
        content = (
            "Routine operations note for the team. "
            "The hidden anchor phrase is lunar spool latency pattern."
        )
        resp = fresh_api.submit_manual(content, title="Operations note")
        assert resp.status_code == 202
        payload = resp.json()
        poll_until_done(fresh_api, payload["task_id"], timeout=60)

        search_resp = fresh_api.search("lunar spool latency pattern")
        assert search_resp.status_code == 200
        body = search_resp.json()
        assert_pagination(body)
        hits = [article for article in body["data"] if article["id"] == payload["article_id"]]
        assert hits
        assert "lunar spool latency pattern" in hits[0].get("search_snippet", "")
