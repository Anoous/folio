"""Smart retrieval: semantic search and related articles."""

from helpers.assertions import assert_pagination


class TestSemanticSearch:
    """Test semantic search API (mode=semantic)."""

    def test_semantic_search_returns_results(self, api, completed_article):
        """Semantic search should return 200 with pagination."""
        resp = api.search("example", mode="semantic")
        assert resp.status_code == 200
        body = resp.json()
        assert_pagination(body)

    def test_semantic_search_degrades_to_keyword(self, api):
        """Semantic search should work even with odd queries (degradation)."""
        resp = api.search("test", mode="semantic")
        assert resp.status_code == 200

    def test_keyword_search_unchanged(self, api):
        """Default mode should still work as before."""
        resp = api.search("test")
        assert resp.status_code == 200


class TestRelatedArticles:
    """Test GET /articles/{id}/related endpoint."""

    def test_related_articles_endpoint(self, api, completed_article):
        """Related articles endpoint should return (possibly empty) array."""
        article_id, _ = completed_article
        resp = api.get_related(article_id)
        assert resp.status_code == 200
        data = resp.json()
        assert "articles" in data
        assert isinstance(data["articles"], list)

    def test_related_articles_nonexistent(self, api):
        """Related articles for non-existent ID should return empty array."""
        resp = api.get_related("00000000-0000-0000-0000-000000000000")
        assert resp.status_code == 200
        assert resp.json()["articles"] == []
