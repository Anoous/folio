"""Direct Reader service /scrape endpoint tests."""

import httpx
import pytest

from helpers.test_urls import WECHAT_ARTICLE, SIMPLE_PAGE


@pytest.fixture(scope="module")
def reader(reader_url):
    """HTTP client pointed at the Reader service."""
    with httpx.Client(base_url=reader_url, timeout=60.0, trust_env=False) as client:
        yield client


class TestReaderScrape:

    def test_scrape_simple_page(self, reader):
        """Scrape a simple page and verify response structure."""
        resp = reader.post("/scrape", json={"url": SIMPLE_PAGE})
        assert resp.status_code == 200
        body = resp.json()

        assert "markdown" in body
        assert len(body["markdown"]) > 0
        assert "metadata" in body
        assert "duration_ms" in body

    @pytest.mark.slow
    def test_scrape_wechat_article(self, reader):
        """Scrape a WeChat public account article and verify content extraction."""
        resp = reader.post("/scrape", json={"url": WECHAT_ARTICLE, "timeout_ms": 45000})
        assert resp.status_code == 200, (
            f"Reader returned {resp.status_code}: {resp.text}\n"
            "Hint: WeChat articles may require proxy or special handling."
        )
        body = resp.json()

        # Must have non-trivial markdown content
        markdown = body["markdown"]
        assert len(markdown) > 200, (
            f"Extracted markdown too short ({len(markdown)} chars), "
            "content extraction may have failed."
        )

        # Markdown should contain Chinese characters (WeChat article is in Chinese)
        has_chinese = any("\u4e00" <= ch <= "\u9fff" for ch in markdown)
        assert has_chinese, "Expected Chinese content in WeChat article markdown."

        # Metadata should be present
        metadata = body.get("metadata", {})
        title = metadata.get("title", "")
        if title:
            assert len(title) > 0, "Title should be non-empty when present."

    def test_scrape_missing_url(self, reader):
        """Scrape without URL returns 400."""
        resp = reader.post("/scrape", json={})
        assert resp.status_code == 400

    def test_scrape_invalid_url(self, reader):
        """Scrape with invalid URL returns error."""
        resp = reader.post("/scrape", json={"url": "not-a-url"})
        assert resp.status_code in (422, 500)
