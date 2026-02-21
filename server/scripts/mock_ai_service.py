#!/usr/bin/env python3
"""Mock AI service for local integration and E2E testing.

Features:
- Deterministic category selection based on URL patterns
- Variable tag counts for realistic test coverage
- Consistent results for the same input (idempotent)
"""

from fastapi import FastAPI
from pydantic import BaseModel
import hashlib
import uvicorn


class AnalyzeRequest(BaseModel):
    title: str = ""
    content: str = ""
    source: str = ""
    author: str = ""


app = FastAPI(title="Folio Mock AI", version="0.2.0")

# URL-pattern → category mapping for variety
CATEGORY_RULES = [
    ("github.com", "tech", "Technology"),
    ("go.dev", "tech", "Technology"),
    ("dev.to", "tech", "Technology"),
    ("stackoverflow", "tech", "Technology"),
    ("arxiv.org", "science", "Science"),
    ("nature.com", "science", "Science"),
    ("bbc.com", "news", "News"),
    ("cnn.com", "news", "News"),
    ("reuters.com", "news", "News"),
    ("medium.com", "culture", "Culture"),
    ("dribbble.com", "design", "Design"),
    ("figma.com", "design", "Design"),
    ("zhihu.com", "education", "Education"),
    ("bloomberg.com", "business", "Business"),
    ("techcrunch.com", "business", "Business"),
    ("youtube.com", "lifestyle", "Lifestyle"),
]

TAG_POOL = [
    ["mock", "integration", "local"],
    ["web", "article", "saved"],
    ["reading", "bookmark", "content"],
    ["analysis", "ai", "processed"],
]


def _pick_category(source: str) -> tuple[str, str]:
    """Deterministic category based on source URL."""
    source_lower = source.lower()
    for pattern, slug, name in CATEGORY_RULES:
        if pattern in source_lower:
            return slug, name
    return "tech", "Technology"


def _pick_tags(source: str) -> list[str]:
    """Deterministic tag set based on source URL hash."""
    h = int(hashlib.md5(source.encode()).hexdigest(), 16)
    idx = h % len(TAG_POOL)
    return TAG_POOL[idx]


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/api/analyze")
def analyze(req: AnalyzeRequest):
    title = (req.title or "").strip() or "Untitled"
    summary = (req.content or "").strip()
    if len(summary) > 120:
        summary = summary[:120] + "..."
    if not summary:
        summary = "Mock summary generated for local integration."

    cat_slug, cat_name = _pick_category(req.source)
    tags = _pick_tags(req.source)

    return {
        "category": cat_slug,
        "category_name": cat_name,
        "confidence": 0.88,
        "tags": tags,
        "summary": summary,
        "key_points": [
            f"Mock analysis for: {title}",
            f"Source: {req.source or 'web'}",
            f"Author: {req.author or 'unknown'}",
        ],
        "language": "en",
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="warning")
