"""Curated test URLs for various E2E scenarios."""

import time

# ---- reliable public pages (lightweight, fast to crawl) ----

SIMPLE_PAGE = "https://example.com/"
SIMPLE_PAGE_2 = "https://example.org/"

# Tech blog post (for AI classification tests)
TECH_BLOG = "https://go.dev/blog/go1.22"

# Non-English page
CHINESE_PAGE = "https://cn.bing.com/"

# WeChat public account article (for scrape quality tests)
WECHAT_ARTICLE = "https://mp.weixin.qq.com/s/dLNfvdobYRPLziWqwYXI8Q"

# ---- dynamic URLs (unique per test run to avoid duplicate collisions) ----

def unique_url(prefix: str = "test") -> str:
    """Generate a URL guaranteed to be unique within this test run."""
    ts = int(time.time() * 1000)
    return f"https://example.com/{prefix}-{ts}"


def unique_urls(n: int, prefix: str = "test") -> list[str]:
    """Generate *n* unique URLs."""
    ts = int(time.time() * 1000)
    return [f"https://example.com/{prefix}-{ts}-{i}" for i in range(n)]


# ---- edge-case URLs ----

VERY_LONG_URL = "https://example.com/" + "a" * 2000
UNICODE_URL = "https://example.com/文章/测试"
URL_WITH_PARAMS = "https://example.com/page?foo=bar&baz=qux#section"
INVALID_URL = "not-a-url"
EMPTY_URL = ""
