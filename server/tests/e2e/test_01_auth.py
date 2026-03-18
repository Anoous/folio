"""Authentication and authorization tests."""

import pytest

from helpers.api_client import FolioAPIClient
from helpers.assertions import assert_uuid, assert_error_response
from helpers.test_auth import test_login


class TestRefreshToken:

    def test_refresh_token_success(self, base_url):
        """Refresh token returns a new token pair."""
        client = FolioAPIClient(base_url)
        data = test_login(client)
        resp = client.refresh_token(data["refresh_token"])
        assert resp.status_code == 200
        body = resp.json()
        assert "access_token" in body
        assert "refresh_token" in body
        client.close()

    def test_refresh_token_missing(self, base_url):
        """Empty refresh_token returns 400."""
        client = FolioAPIClient(base_url)
        resp = client.refresh_token("")
        assert_error_response(resp, 400, error_contains="refresh_token")
        client.close()

    def test_refresh_token_invalid(self, base_url):
        """Garbage refresh_token returns 403."""
        client = FolioAPIClient(base_url)
        resp = client.refresh_token("invalid.token.here")
        assert resp.status_code == 403
        client.close()


class TestUnauthorized:

    def test_no_token_returns_401(self, unauthed_api):
        """Protected endpoints return 401 without a token."""
        resp = unauthed_api.list_articles()
        assert resp.status_code == 401
