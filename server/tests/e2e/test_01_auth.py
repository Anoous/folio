"""Authentication and authorization tests."""

import pytest

from helpers.api_client import FolioAPIClient
from helpers.assertions import assert_uuid, assert_error_response


class TestDevLogin:

    @pytest.mark.smoke
    def test_dev_login_returns_tokens(self, base_url):
        """POST /auth/dev returns access_token, refresh_token, user."""
        client = FolioAPIClient(base_url)
        resp = client.dev_login()
        assert resp.status_code == 200
        body = resp.json()
        assert "access_token" in body
        assert "refresh_token" in body
        assert body["expires_in"] == 7200
        assert "user" in body
        assert_uuid(body["user"]["id"], "user.id")
        client.close()

    def test_dev_login_no_body(self, base_url):
        """Dev login works with no request body (backward compat)."""
        client = FolioAPIClient(base_url)
        resp = client.client.post("/api/v1/auth/dev", headers={})
        assert resp.status_code == 200
        body = resp.json()
        assert "access_token" in body
        client.close()

    def test_dev_login_with_alias(self, base_url):
        """Dev login with alias creates a distinct user."""
        client = FolioAPIClient(base_url)
        resp = client.dev_login(alias="alpha")
        assert resp.status_code == 200
        body = resp.json()
        assert "access_token" in body
        assert_uuid(body["user"]["id"], "user.id")
        client.close()

    def test_dev_login_idempotent(self, base_url):
        """Calling dev login twice returns the same user ID."""
        c1 = FolioAPIClient(base_url)
        c2 = FolioAPIClient(base_url)
        r1 = c1.dev_login()
        r2 = c2.dev_login()
        assert r1.json()["user"]["id"] == r2.json()["user"]["id"]
        c1.close()
        c2.close()

    def test_dev_login_alias_different_users(self, base_url):
        """Different aliases produce different user IDs."""
        c1 = FolioAPIClient(base_url)
        c2 = FolioAPIClient(base_url)
        r1 = c1.dev_login(alias="user-a")
        r2 = c2.dev_login(alias="user-b")
        assert r1.json()["user"]["id"] != r2.json()["user"]["id"]
        c1.close()
        c2.close()


class TestRefreshToken:

    def test_refresh_token_success(self, base_url):
        """Refresh token returns a new token pair."""
        client = FolioAPIClient(base_url)
        login = client.dev_login()
        refresh = login.json()["refresh_token"]
        resp = client.refresh_token(refresh)
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
