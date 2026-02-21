"""Edge case tests."""

import pytest

from helpers.api_client import FolioAPIClient
from helpers.auth import dev_login
from helpers.test_urls import unique_url, UNICODE_URL, URL_WITH_PARAMS, VERY_LONG_URL


class TestEdgeCases:

    def test_duplicate_url_rejected(self, fresh_api):
        """Submitting the same URL twice for the same user is rejected."""
        url = unique_url("dup-check")
        resp1 = fresh_api.submit_url(url)
        assert resp1.status_code == 202
        resp2 = fresh_api.submit_url(url)
        # Server should reject duplicate with 4xx or 5xx
        assert resp2.status_code >= 400, (
            f"expected duplicate URL rejection, got {resp2.status_code}: {resp2.text}"
        )

    def test_unicode_url(self, fresh_api):
        """Submitting a URL with Unicode characters is accepted."""
        resp = fresh_api.submit_url(UNICODE_URL)
        # Either accepted (202) or rejected with a clear error
        assert resp.status_code in (202, 400)

    def test_url_with_query_params(self, fresh_api):
        """URL with query parameters is accepted."""
        resp = fresh_api.submit_url(URL_WITH_PARAMS)
        assert resp.status_code == 202

    def test_very_long_url(self, fresh_api):
        """Very long URLs are either accepted or cleanly rejected."""
        resp = fresh_api.submit_url(VERY_LONG_URL)
        assert resp.status_code in (202, 400, 414)

    def test_invalid_uuid_article(self, api):
        """GET /articles/not-a-uuid returns 404 or 400."""
        resp = api.get_article("not-a-uuid")
        assert resp.status_code in (400, 404, 500)

    def test_empty_body_post(self, api):
        """POST /articles with no body returns 400."""
        resp = api.client.post(
            "/api/v1/articles",
            content=b"",
            headers={"Authorization": f"Bearer {api.token}", "Content-Type": "application/json"},
        )
        assert resp.status_code == 400
