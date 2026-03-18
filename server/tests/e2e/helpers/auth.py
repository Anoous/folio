"""Authentication helpers for E2E tests."""

from __future__ import annotations

from .test_auth import test_login


def make_auth_headers(token: str) -> dict[str, str]:
    """Build an Authorization header dict from a raw JWT."""
    return {"Authorization": f"Bearer {token}"}
