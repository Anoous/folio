"""Direct Reader service /scrape endpoint tests."""

import httpx
import pytest


@pytest.fixture(scope="module")
def reader(reader_url):
    """HTTP client pointed at the Reader service."""
    with httpx.Client(base_url=reader_url, timeout=60.0, trust_env=False) as client:
        yield client


class TestReaderScrape:

    def test_scrape_rejects_loopback_target(self, reader):
        """Reader rejects loopback targets under SSRF protection."""
        resp = reader.post("/scrape", json={"url": "http://127.0.0.1/internal"})
        assert resp.status_code == 400
        assert resp.json() == {
            "error": "url is not allowed",
            "code": "blocked_target",
            "provider": "reader",
            "retryable": False,
        }

    def test_scrape_missing_url(self, reader):
        """Scrape without URL returns 400."""
        resp = reader.post("/scrape", json={})
        assert resp.status_code == 400
        assert resp.json() == {
            "error": "url is required",
            "code": "invalid_request",
            "provider": "reader",
            "retryable": False,
        }

    def test_scrape_invalid_url(self, reader):
        """Scrape with invalid URL returns error."""
        resp = reader.post("/scrape", json={"url": "not-a-url"})
        assert resp.status_code == 400
        assert resp.json() == {
            "error": "url is not allowed",
            "code": "blocked_target",
            "provider": "reader",
            "retryable": False,
        }
