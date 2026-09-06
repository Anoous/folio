"""Thin httpx wrapper for Folio API calls."""

import json

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

    def refresh_token(self, refresh_token: str) -> httpx.Response:
        return self.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token}, authenticated=False)

    def logout(self, refresh_token: str) -> httpx.Response:
        return self.post("/api/v1/auth/logout", json={"refresh_token": refresh_token}, authenticated=False)

    def submit_url(
        self,
        url: str,
        tag_ids: list[str] | None = None,
        *,
        title: str | None = None,
        author: str | None = None,
        site_name: str | None = None,
        markdown_content: str | None = None,
        word_count: int | None = None,
    ) -> httpx.Response:
        body: dict = {"url": url}
        if tag_ids:
            body["tag_ids"] = tag_ids
        if title is not None:
            body["title"] = title
        if author is not None:
            body["author"] = author
        if site_name is not None:
            body["site_name"] = site_name
        if markdown_content is not None:
            body["markdown_content"] = markdown_content
        if word_count is not None:
            body["word_count"] = word_count
        return self.post("/api/v1/articles", json=body)

    def submit_manual(
        self,
        content: str,
        title: str | None = None,
        tag_ids: list[str] | None = None,
        source_type: str | None = None,
    ) -> httpx.Response:
        """Submit manual content (no URL)."""
        payload: dict = {"content": content}
        if title:
            payload["title"] = title
        if tag_ids:
            payload["tag_ids"] = tag_ids
        if source_type:
            payload["source_type"] = source_type
        return self.post("/api/v1/articles/manual", json=payload)

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

    def get_related(self, article_id: str) -> httpx.Response:
        return self.get(f"/api/v1/articles/{article_id}/related")

    def rag_query(self, question: str, conversation_id: str | None = None) -> httpx.Response:
        payload = {"question": question}
        if conversation_id is not None:
            payload["conversation_id"] = conversation_id
        return self.post("/api/v1/rag/query", json=payload)

    def rag_query_stream(self, question: str, conversation_id: str | None = None) -> list[tuple[str, dict]]:
        payload = {"question": question}
        if conversation_id is not None:
            payload["conversation_id"] = conversation_id

        events: list[tuple[str, dict]] = []
        event_type: str | None = None
        data_lines: list[str] = []

        def flush_event():
            nonlocal event_type, data_lines
            if event_type is not None and data_lines:
                events.append((event_type, json.loads("\n".join(data_lines))))
            event_type = None
            data_lines = []

        with self.client.stream(
            "POST",
            "/api/v1/rag/query/stream",
            json=payload,
            headers=self._headers(),
        ) as response:
            response.raise_for_status()
            for line in response.iter_lines():
                if line.startswith("event: "):
                    flush_event()
                    event_type = line.removeprefix("event: ")
                elif line.startswith("data: "):
                    data_lines.append(line.removeprefix("data: "))
                elif line == "":
                    flush_event()
            flush_event()

        return events

    def knowledge_spark(self, prompt: str | None = None) -> httpx.Response:
        payload = {"prompt": prompt or ""}
        return self.post("/api/v1/knowledge/spark", json=payload)

    def knowledge_learn(self, prompt: str | None = None) -> httpx.Response:
        payload = {"prompt": prompt or ""}
        return self.post("/api/v1/knowledge/learn", json=payload)

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
