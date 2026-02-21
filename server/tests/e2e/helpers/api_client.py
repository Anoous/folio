"""Thin httpx wrapper for Folio API calls."""

import httpx


class FolioAPIClient:
    """Convenience wrapper around httpx.Client for the Folio API."""

    def __init__(self, base_url: str, timeout: float = 30.0):
        self.base_url = base_url.rstrip("/")
        self.client = httpx.Client(base_url=self.base_url, timeout=timeout, trust_env=False)
        self.token: str | None = None

    # -- auth helpers ----------------------------------------------------------

    def set_token(self, token: str):
        self.token = token

    def _headers(self, authenticated: bool = True) -> dict:
        h: dict[str, str] = {}
        if authenticated and self.token:
            h["Authorization"] = f"Bearer {self.token}"
        return h

    # -- generic verbs ---------------------------------------------------------

    def get(self, path: str, *, params: dict | None = None, authenticated: bool = True) -> httpx.Response:
        return self.client.get(path, params=params, headers=self._headers(authenticated))

    def post(self, path: str, *, json: dict | None = None, authenticated: bool = True) -> httpx.Response:
        return self.client.post(path, json=json, headers=self._headers(authenticated))

    def put(self, path: str, *, json: dict | None = None, authenticated: bool = True) -> httpx.Response:
        return self.client.put(path, json=json, headers=self._headers(authenticated))

    def delete(self, path: str, *, authenticated: bool = True) -> httpx.Response:
        return self.client.delete(path, headers=self._headers(authenticated))

    def patch(self, path: str, *, json: dict | None = None, authenticated: bool = True) -> httpx.Response:
        return self.client.patch(path, json=json, headers=self._headers(authenticated))

    # -- shortcuts -------------------------------------------------------------

    def health(self) -> httpx.Response:
        return self.get("/health", authenticated=False)

    def dev_login(self, alias: str | None = None) -> httpx.Response:
        body = {"alias": alias} if alias else None
        return self.post("/api/v1/auth/dev", json=body, authenticated=False)

    def refresh_token(self, refresh_token: str) -> httpx.Response:
        return self.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token}, authenticated=False)

    def submit_url(self, url: str, tag_ids: list[str] | None = None) -> httpx.Response:
        body: dict = {"url": url}
        if tag_ids:
            body["tag_ids"] = tag_ids
        return self.post("/api/v1/articles", json=body)

    def list_articles(self, **params) -> httpx.Response:
        return self.get("/api/v1/articles", params=params)

    def get_article(self, article_id: str) -> httpx.Response:
        return self.get(f"/api/v1/articles/{article_id}")

    def update_article(self, article_id: str, **fields) -> httpx.Response:
        return self.put(f"/api/v1/articles/{article_id}", json=fields)

    def delete_article(self, article_id: str) -> httpx.Response:
        return self.delete(f"/api/v1/articles/{article_id}")

    def search(self, q: str, **params) -> httpx.Response:
        params["q"] = q
        return self.get("/api/v1/articles/search", params=params)

    def list_tags(self) -> httpx.Response:
        return self.get("/api/v1/tags")

    def create_tag(self, name: str) -> httpx.Response:
        return self.post("/api/v1/tags", json={"name": name})

    def delete_tag(self, tag_id: str) -> httpx.Response:
        return self.delete(f"/api/v1/tags/{tag_id}")

    def list_categories(self) -> httpx.Response:
        return self.get("/api/v1/categories")

    def get_task(self, task_id: str) -> httpx.Response:
        return self.get(f"/api/v1/tasks/{task_id}")

    def close(self):
        self.client.close()
