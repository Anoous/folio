"""Authentication and authorization tests."""

import base64
import os

from helpers.api_client import FolioAPIClient
from helpers.assertions import assert_error_response
from helpers.test_auth import test_login


def _refresh_token_with_wrong_secret(refresh_token: str) -> str:
    session_id, _ = refresh_token.split(".", 1)
    secret = base64.urlsafe_b64encode(os.urandom(32)).rstrip(b"=").decode()
    return f"{session_id}.{secret}"


def _client(base_url: str, forwarded_for: str) -> FolioAPIClient:
    client = FolioAPIClient(base_url)
    client.client.headers["X-Forwarded-For"] = forwarded_for
    return client


class TestRefreshToken:

    def test_refresh_token_success(self, base_url):
        """Refresh token returns a new token pair."""
        client = _client(base_url, "198.51.100.11")
        data = test_login(client)
        resp = client.refresh_token(data["refresh_token"])
        assert resp.status_code == 200
        body = resp.json()
        assert "access_token" in body
        assert "refresh_token" in body
        client.close()

    def test_reused_rotated_refresh_token_revokes_session(self, base_url):
        """Reusing an already-rotated refresh token revokes the session."""
        client = _client(base_url, "198.51.100.12")
        data = test_login(client, alias="refresh-reuse")

        rotated_resp = client.refresh_token(data["refresh_token"])
        assert rotated_resp.status_code == 200
        rotated = rotated_resp.json()

        reuse_resp = client.refresh_token(data["refresh_token"])
        assert reuse_resp.status_code == 403

        current_resp = client.refresh_token(rotated["refresh_token"])
        assert current_resp.status_code == 403
        client.close()

    def test_wrong_secret_for_known_session_does_not_revoke(self, base_url):
        """A wrong secret for a real session is rejected without revocation."""
        client = _client(base_url, "198.51.100.13")
        data = test_login(client, alias="refresh-wrong-secret")

        wrong_token = _refresh_token_with_wrong_secret(data["refresh_token"])
        wrong_resp = client.refresh_token(wrong_token)
        assert wrong_resp.status_code == 403

        valid_resp = client.refresh_token(data["refresh_token"])
        assert valid_resp.status_code == 200
        client.close()

    def test_refresh_token_missing(self, base_url):
        """Empty refresh_token returns 400."""
        client = _client(base_url, "198.51.100.14")
        resp = client.refresh_token("")
        assert_error_response(resp, 400, error_contains="refresh_token")
        client.close()

    def test_refresh_token_invalid(self, base_url):
        """Garbage refresh_token returns 403."""
        client = _client(base_url, "198.51.100.15")
        resp = client.refresh_token("invalid.token.here")
        assert resp.status_code == 403
        client.close()

    def test_logout_revokes_refresh_session(self, base_url):
        """Logout revokes the refresh session so it can no longer refresh."""
        client = _client(base_url, "198.51.100.16")
        data = test_login(client, alias="logout")

        logout_resp = client.logout(data["refresh_token"])
        assert logout_resp.status_code == 204

        refresh_resp = client.refresh_token(data["refresh_token"])
        assert refresh_resp.status_code == 403
        client.close()


class TestUnauthorized:

    def test_no_token_returns_401(self, unauthed_api):
        """Protected endpoints return 401 without a token."""
        resp = unauthed_api.list_articles()
        assert resp.status_code == 401
