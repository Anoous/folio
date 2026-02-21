"""Health-check tests for all Folio services."""

import httpx
import pytest


@pytest.fixture(scope="module")
def http():
    """HTTP client that bypasses system proxy."""
    with httpx.Client(trust_env=False) as client:
        yield client


class TestHealth:

    @pytest.mark.smoke
    def test_api_health(self, http, base_url):
        """GET /health returns 200 with status ok."""
        resp = http.get(f"{base_url}/health")
        assert resp.status_code == 200
        body = resp.json()
        assert body["status"] == "ok"

    def test_reader_health(self, http, reader_url):
        """Reader service /health returns 200."""
        resp = http.get(f"{reader_url}/health")
        assert resp.status_code == 200

    def test_ai_health(self, http, ai_url):
        """AI service /health returns 200."""
        resp = http.get(f"{ai_url}/health")
        assert resp.status_code == 200
        body = resp.json()
        assert body["status"] == "ok"
