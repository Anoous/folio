"""Error handling tests."""

import pytest

from helpers.assertions import assert_error_response


class TestErrors:

    def test_400_missing_required_field(self, api):
        """POST /articles without URL returns 400."""
        resp = api.post("/api/v1/articles", json={})
        assert_error_response(resp, 400)

    def test_400_invalid_json(self, api):
        """POST with invalid JSON returns 400."""
        resp = api.client.post(
            "/api/v1/articles",
            content=b"not json",
            headers={"Authorization": f"Bearer {api.token}", "Content-Type": "application/json"},
        )
        assert resp.status_code == 400

    def test_401_no_token(self, unauthed_api):
        """Accessing protected route without token returns 401."""
        resp = unauthed_api.list_articles()
        assert resp.status_code == 401

    def test_401_bad_token(self, base_url):
        """Accessing protected route with bad token returns 401."""
        from helpers.api_client import FolioAPIClient
        client = FolioAPIClient(base_url)
        client.set_token("invalid.jwt.token")
        resp = client.list_articles()
        assert resp.status_code == 401
        client.close()

    def test_404_nonexistent_article(self, api):
        """GET /articles/{bad-id} returns 404."""
        resp = api.get_article("00000000-0000-0000-0000-000000000000")
        assert resp.status_code == 404

    def test_404_nonexistent_task(self, api):
        """GET /tasks/{bad-id} returns 404."""
        resp = api.get_task("00000000-0000-0000-0000-000000000000")
        assert resp.status_code == 404

    def test_405_wrong_method(self, api):
        """PATCH on articles endpoint returns 405."""
        resp = api.patch("/api/v1/articles")
        assert resp.status_code == 405
