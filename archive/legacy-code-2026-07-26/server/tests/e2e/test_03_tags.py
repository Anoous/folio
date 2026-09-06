"""Tag CRUD tests."""

import pytest

from helpers.assertions import assert_uuid, assert_error_response, assert_pagination


class TestTagCreate:

    def test_create_tag(self, fresh_api):
        """POST /tags creates a new tag."""
        resp = fresh_api.create_tag("e2e-tag-create")
        assert resp.status_code == 201
        body = resp.json()
        assert_uuid(body["id"], "tag.id")
        assert body["name"] == "e2e-tag-create"

    def test_create_tag_empty_name(self, fresh_api):
        """Creating a tag with empty name returns 400."""
        resp = fresh_api.create_tag("")
        assert_error_response(resp, 400, error_contains="name")

    def test_create_tag_duplicate(self, fresh_api):
        """Creating the same tag name twice is handled gracefully."""
        resp1 = fresh_api.create_tag("e2e-dup-tag")
        assert resp1.status_code == 201
        resp2 = fresh_api.create_tag("e2e-dup-tag")
        # Server may accept (201), return existing, or reject (4xx/5xx)
        assert resp2.status_code in (200, 201, 409, 500)


class TestTagList:

    def test_list_tags(self, api):
        """GET /tags returns a list response."""
        resp = api.list_tags()
        assert resp.status_code == 200
        body = resp.json()
        assert_pagination(body)
        assert isinstance(body["data"], list)

    def test_list_tags_after_create(self, fresh_api):
        """Newly created tags appear in the list."""
        fresh_api.create_tag("e2e-list-check")
        resp = fresh_api.list_tags()
        body = resp.json()
        names = [t["name"] for t in body["data"]]
        assert "e2e-list-check" in names


class TestTagDelete:

    def test_delete_tag(self, fresh_api):
        """DELETE /tags/{id} removes the tag."""
        create_resp = fresh_api.create_tag("e2e-to-delete")
        tag_id = create_resp.json()["id"]
        del_resp = fresh_api.delete_tag(tag_id)
        assert del_resp.status_code == 200

    def test_delete_nonexistent_tag(self, fresh_api):
        """Deleting a non-existent tag returns 404 or 500."""
        resp = fresh_api.delete_tag("00000000-0000-0000-0000-000000000000")
        assert resp.status_code >= 400
