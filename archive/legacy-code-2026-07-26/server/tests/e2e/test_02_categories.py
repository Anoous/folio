"""Category listing tests."""

import pytest

from helpers.assertions import assert_pagination, assert_uuid

EXPECTED_SLUGS = {"tech", "business", "science", "culture", "lifestyle", "news", "education", "design", "other"}


class TestCategories:

    @pytest.mark.smoke
    def test_list_categories(self, api):
        """GET /categories returns all 9 built-in categories."""
        resp = api.list_categories()
        assert resp.status_code == 200
        body = resp.json()
        assert_pagination(body, min_total=9)
        slugs = {c["slug"] for c in body["data"]}
        assert slugs == EXPECTED_SLUGS

    def test_category_fields(self, api):
        """Each category has required fields."""
        resp = api.list_categories()
        body = resp.json()
        for cat in body["data"]:
            assert_uuid(cat["id"], "category.id")
            assert isinstance(cat["slug"], str) and len(cat["slug"]) > 0
            assert isinstance(cat["name_zh"], str) and len(cat["name_zh"]) > 0
            assert isinstance(cat["name_en"], str) and len(cat["name_en"]) > 0
            assert isinstance(cat["sort_order"], int)

    def test_categories_sorted_by_order(self, api):
        """Categories are returned in sort_order."""
        resp = api.list_categories()
        cats = resp.json()["data"]
        orders = [c["sort_order"] for c in cats]
        assert orders == sorted(orders), f"categories not sorted: {orders}"

    def test_category_bilingual_names(self, api):
        """Each category has both Chinese and English names."""
        resp = api.list_categories()
        for cat in resp.json()["data"]:
            assert cat["name_zh"], f"missing name_zh for {cat['slug']}"
            assert cat["name_en"], f"missing name_en for {cat['slug']}"
