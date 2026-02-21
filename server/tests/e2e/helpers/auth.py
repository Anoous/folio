"""Authentication helpers for E2E tests."""

from __future__ import annotations

from .api_client import FolioAPIClient


def dev_login(client: FolioAPIClient, alias: str | None = None) -> dict:
    """Perform dev login and return the full response body.

    Also sets the access token on the client so subsequent calls are authenticated.
    """
    resp = client.dev_login(alias=alias)
    assert resp.status_code == 200, f"dev login failed ({resp.status_code}): {resp.text}"
    data = resp.json()
    client.set_token(data["access_token"])
    return data


def make_auth_headers(token: str) -> dict[str, str]:
    """Build an Authorization header dict from a raw JWT."""
    return {"Authorization": f"Bearer {token}"}
