"""Highlight lifecycle E2E tests."""

from helpers.api_client import FolioAPIClient
from helpers.test_auth import test_login


class TestHighlights:
    def test_create_and_delete_highlight_updates_article_count(self, base_url):
        client = FolioAPIClient(base_url)
        try:
            test_login(client, alias="highlight-lifecycle")
            article_resp = client.submit_manual(
                "Highlights should keep the article counter consistent.",
                title="Highlight Lifecycle",
            )
            assert article_resp.status_code == 202, article_resp.text
            article_id = article_resp.json()["article_id"]

            before = client.get_article(article_id)
            assert before.status_code == 200, before.text
            assert before.json()["highlight_count"] == 0

            create_resp = client.post(
                f"/api/v1/articles/{article_id}/highlights",
                json={"text": "keep the article counter", "start_offset": 18, "end_offset": 42},
            )
            assert create_resp.status_code == 201, create_resp.text
            highlight_id = create_resp.json()["id"]

            listed = client.get(f"/api/v1/articles/{article_id}/highlights")
            assert listed.status_code == 200, listed.text
            assert [h["id"] for h in listed.json()["data"]] == [highlight_id]

            after_create = client.get_article(article_id)
            assert after_create.status_code == 200, after_create.text
            assert after_create.json()["highlight_count"] == 1

            delete_resp = client.delete(f"/api/v1/highlights/{highlight_id}")
            assert delete_resp.status_code == 204, delete_resp.text

            after_delete = client.get_article(article_id)
            assert after_delete.status_code == 200, after_delete.text
            assert after_delete.json()["highlight_count"] == 0

            listed_again = client.get(f"/api/v1/articles/{article_id}/highlights")
            assert listed_again.status_code == 200, listed_again.text
            assert listed_again.json()["data"] == []
        finally:
            client.close()
