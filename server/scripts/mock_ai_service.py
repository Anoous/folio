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
import re
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

# Stop words excluded from tag extraction
_STOP_WORDS = {
    "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
    "have", "has", "had", "do", "does", "did", "will", "would", "could",
    "should", "may", "might", "shall", "can", "to", "of", "in", "for",
    "on", "with", "at", "by", "from", "as", "into", "about", "between",
    "through", "after", "before", "and", "but", "or", "not", "no", "so",
    "if", "than", "too", "very", "just", "how", "what", "why", "when",
    "where", "who", "which", "that", "this", "these", "those", "it", "its",
    "my", "your", "his", "her", "our", "their", "all", "each", "every",
    "up", "out", "new", "old", "use", "using", "used",
    # Common Chinese particles
    "的", "了", "在", "是", "我", "有", "和", "就", "不", "人", "都", "一",
    "一个", "上", "也", "而", "到", "说", "要", "会", "对", "与",
}


def _pick_category(source: str) -> tuple[str, str]:
    """Deterministic category based on source URL."""
    source_lower = source.lower()
    for pattern, slug, name in CATEGORY_RULES:
        if pattern in source_lower:
            return slug, name
    return "tech", "Technology"


def _extract_tags(title: str, content: str = "") -> list[str]:
    """Extract meaningful keywords from title as tags (3-5 tags)."""
    text = title
    # Also take first sentence of content if title is short
    if len(title) < 20 and content:
        first_line = content.split("\n")[0].strip("# ").strip()
        text = f"{title} {first_line}"

    # Remove markdown syntax
    text = re.sub(r"\[([^\]]*)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"[#*`~>\[\](){}|]", " ", text)

    # Split into words (handles both English and Chinese by splitting on non-alphanumeric)
    words = re.findall(r"[A-Za-z][A-Za-z0-9+#.]{1,}", text)  # English words (2+ chars)
    # Also extract Chinese segments (2+ chars)
    zh_segments = re.findall(r"[\u4e00-\u9fff]{2,4}", text)

    tags = []
    seen = set()
    for w in words + zh_segments:
        lower = w.lower()
        if lower in _STOP_WORDS or lower in seen or len(lower) < 2:
            continue
        seen.add(lower)
        tags.append(w if w[0].isupper() or not w.isascii() else w.lower())
        if len(tags) >= 5:
            break

    # Fallback: at least return the category-like tag
    if len(tags) < 2:
        tags.append("article")
    return tags[:5]


@app.get("/health")
def health():
    return {"status": "ok"}


def _clean_for_summary(text: str) -> str:
    """Remove URLs, markdown links, and noise from content before summarizing."""
    # Remove markdown links but keep text: [text](url) → text
    text = re.sub(r"\[([^\]]*)\]\([^)]+\)", r"\1", text)
    # Remove bare URLs (http/https/protocol-relative)
    text = re.sub(r"(?:https?:)?//[^\s)]+", "", text)
    # Remove markdown image syntax
    text = re.sub(r"!\[[^\]]*\]\([^)]+\)", "", text)
    # Collapse whitespace
    text = re.sub(r"\s+", " ", text).strip()
    return text


@app.post("/api/analyze")
def analyze(req: AnalyzeRequest):
    title = (req.title or "").strip() or "Untitled"
    summary = _clean_for_summary((req.content or "").strip())
    if len(summary) > 120:
        summary = summary[:120] + "..."
    if not summary:
        summary = "Mock summary generated for local integration."

    cat_slug, cat_name = _pick_category(req.source)
    tags = _extract_tags(title, req.content)

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
