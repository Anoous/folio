"""Article CRUD tests."""

import pytest

from helpers.assertions import assert_uuid, assert_pagination, assert_error_response
from helpers.test_urls import unique_url


class TestSubmitURL:

    @pytest.mark.smoke
    def test_submit_url(self, fresh_api):
        """POST /articles with a URL returns 202 with article_id and task_id."""
        url = unique_url("crud-submit")
        resp = fresh_api.submit_url(url)
        assert resp.status_code == 202
        body = resp.json()
        assert_uuid(body["article_id"], "article_id")
        assert_uuid(body["task_id"], "task_id")

    def test_submit_url_missing(self, fresh_api):
        """POST /articles without url returns 400."""
        resp = fresh_api.post("/api/v1/articles", json={})
        assert_error_response(resp, 400, error_contains="url")

    def test_submit_url_empty(self, fresh_api):
        """POST /articles with empty url returns 400."""
        resp = fresh_api.post("/api/v1/articles", json={"url": ""})
        assert_error_response(resp, 400, error_contains="url")

    def test_submit_with_tags(self, fresh_api):
        """Submit with tag_ids is accepted."""
        tag_resp = fresh_api.create_tag("e2e-submit-tag")
        tag_id = tag_resp.json()["id"]
        url = unique_url("crud-tags")
        resp = fresh_api.submit_url(url, tag_ids=[tag_id])
        assert resp.status_code == 202


class TestGetArticle:

    def test_get_article(self, api, submitted_article):
        """GET /articles/{id} returns the article."""
        article_id = submitted_article["article_id"]
        resp = api.get_article(article_id)
        assert resp.status_code == 200
        body = resp.json()
        assert body["id"] == article_id

    def test_get_article_not_found(self, api):
        """GET /articles/{id} with bad ID returns 404."""
        resp = api.get_article("00000000-0000-0000-0000-000000000000")
        assert resp.status_code == 404


class TestListArticles:

    def test_list_articles(self, api):
        """GET /articles returns paginated list."""
        resp = api.list_articles(page=1, per_page=10)
        assert resp.status_code == 200
        body = resp.json()
        assert_pagination(body)

    def test_list_articles_default_pagination(self, api):
        """GET /articles without params uses defaults."""
        resp = api.list_articles()
        assert resp.status_code == 200
        body = resp.json()
        assert body["pagination"]["page"] == 1
        assert body["pagination"]["per_page"] == 20


class TestUpdateArticle:

    def test_update_article_favorite(self, api, submitted_article):
        """PUT /articles/{id} can toggle is_favorite."""
        article_id = submitted_article["article_id"]
        resp = api.update_article(article_id, is_favorite=True)
        assert resp.status_code == 200


class TestDeleteArticle:

    def test_delete_article(self, fresh_api):
        """DELETE /articles/{id} removes the article."""
        url = unique_url("crud-delete")
        submit = fresh_api.submit_url(url)
        article_id = submit.json()["article_id"]
        del_resp = fresh_api.delete_article(article_id)
        assert del_resp.status_code == 200
        # Verify it's gone
        get_resp = fresh_api.get_article(article_id)
        assert get_resp.status_code == 404
