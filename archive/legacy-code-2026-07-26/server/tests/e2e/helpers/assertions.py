"""Reusable assertion helpers for E2E tests."""

from __future__ import annotations

import re

UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")


def assert_uuid(value: str, label: str = "value"):
    """Assert that *value* looks like a valid UUID v4."""
    assert isinstance(value, str), f"{label} is not a string: {value!r}"
    assert UUID_RE.match(value), f"{label} is not a valid UUID: {value!r}"


def assert_pagination(body: dict, *, min_total: int = 0):
    """Assert the response contains a valid pagination envelope."""
    assert "pagination" in body, f"missing 'pagination' key in response: {list(body.keys())}"
    p = body["pagination"]
    assert "page" in p and isinstance(p["page"], int), f"bad pagination.page: {p}"
    assert "per_page" in p and isinstance(p["per_page"], int), f"bad pagination.per_page: {p}"
    assert "total" in p and isinstance(p["total"], int), f"bad pagination.total: {p}"
    assert p["total"] >= min_total, f"expected total >= {min_total}, got {p['total']}"
    assert "data" in body, f"missing 'data' key in response: {list(body.keys())}"


def assert_error_response(resp, expected_status: int, *, error_contains: str | None = None):
    """Assert a response is an error with the expected status code."""
    assert resp.status_code == expected_status, (
        f"expected status {expected_status}, got {resp.status_code}: {resp.text}"
    )
    body = resp.json()
    assert "error" in body, f"error response missing 'error' key: {body}"
    if error_contains:
        assert error_contains.lower() in body["error"].lower(), (
            f"expected error containing '{error_contains}', got: {body['error']}"
        )
