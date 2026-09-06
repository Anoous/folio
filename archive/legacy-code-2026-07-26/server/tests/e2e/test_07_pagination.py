"""Pagination and filtering tests."""

import pytest

from helpers.assertions import assert_pagination
from helpers.test_urls import unique_urls


class TestPagination:

    def test_page_1(self, api):
        """Page 1 returns valid pagination."""
        resp = api.list_articles(page=1, per_page=5)
        assert resp.status_code == 200
        body = resp.json()
        assert_pagination(body)
        assert body["pagination"]["page"] == 1
        assert body["pagination"]["per_page"] == 5

    def test_page_2(self, api):
        """Page 2 returns valid pagination."""
        resp = api.list_articles(page=2, per_page=5)
        assert resp.status_code == 200
        body = resp.json()
        assert body["pagination"]["page"] == 2

    def test_per_page_limit(self, api):
        """Data array length does not exceed per_page."""
        resp = api.list_articles(page=1, per_page=3)
        assert resp.status_code == 200
        body = resp.json()
        assert len(body["data"]) <= 3

    def test_large_page_returns_empty(self, api):
        """Requesting a page beyond total returns empty data."""
        resp = api.list_articles(page=9999, per_page=10)
        assert resp.status_code == 200
        body = resp.json()
        assert len(body["data"]) == 0


class TestFilters:

    def test_filter_by_status_pending(self, api):
        """Filter articles by status=pending."""
        resp = api.list_articles(status="pending")
        assert resp.status_code == 200
        body = resp.json()
        assert_pagination(body)
        for art in body["data"]:
            assert art["status"] == "pending"

    def test_filter_by_status_ready(self, api, completed_article):
        """Filter articles by status=ready returns completed articles."""
        resp = api.list_articles(status="ready")
        assert resp.status_code == 200
        body = resp.json()
        assert_pagination(body)
        for art in body["data"]:
            assert art["status"] == "ready"

    def test_filter_by_favorite(self, api, submitted_article):
        """Filter by favorite=true."""
        # First mark an article as favorite
        article_id = submitted_article["article_id"]
        api.update_article(article_id, is_favorite=True)

        resp = api.list_articles(favorite="true")
        assert resp.status_code == 200
        body = resp.json()
        assert_pagination(body)
        for art in body["data"]:
            assert art["is_favorite"] is True
