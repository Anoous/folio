"""Multi-user data isolation tests."""

import pytest

from helpers.api_client import FolioAPIClient
from helpers.auth import dev_login
from helpers.test_urls import unique_url


class TestMultiUser:

    def test_users_have_different_ids(self, base_url):
        """Two aliased dev logins produce different user IDs."""
        c1 = FolioAPIClient(base_url)
        c2 = FolioAPIClient(base_url)
        d1 = dev_login(c1, alias="iso-a")
        d2 = dev_login(c2, alias="iso-b")
        assert d1["user"]["id"] != d2["user"]["id"]
        c1.close()
        c2.close()

    def test_article_isolation(self, base_url):
        """User A's articles are not visible to User B."""
        c1 = FolioAPIClient(base_url)
        c2 = FolioAPIClient(base_url)
        dev_login(c1, alias="iso-art-a")
        dev_login(c2, alias="iso-art-b")

        # User A submits an article
        url = unique_url("iso-article")
        resp = c1.submit_url(url)
        assert resp.status_code == 202
        article_id = resp.json()["article_id"]

        # User B cannot see it
        resp = c2.get_article(article_id)
        assert resp.status_code in (403, 404)

        c1.close()
        c2.close()

    def test_tag_isolation(self, base_url):
        """User A's tags are not visible to User B."""
        c1 = FolioAPIClient(base_url)
        c2 = FolioAPIClient(base_url)
        dev_login(c1, alias="iso-tag-a")
        dev_login(c2, alias="iso-tag-b")

        # User A creates a tag
        c1.create_tag("iso-only-for-a")

        # User B should not see it
        resp = c2.list_tags()
        names = [t["name"] for t in resp.json()["data"]]
        assert "iso-only-for-a" not in names

        c1.close()
        c2.close()

    def test_task_isolation(self, base_url):
        """User A's tasks are not accessible by User B."""
        c1 = FolioAPIClient(base_url)
        c2 = FolioAPIClient(base_url)
        dev_login(c1, alias="iso-task-a")
        dev_login(c2, alias="iso-task-b")

        url = unique_url("iso-task")
        resp = c1.submit_url(url)
        task_id = resp.json()["task_id"]

        # User B cannot see the task
        resp = c2.get_task(task_id)
        assert resp.status_code in (403, 404)

        c1.close()
        c2.close()
