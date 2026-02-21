#!/usr/bin/env python3
"""Minimal mock AI service for local integration testing."""

from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn


class AnalyzeRequest(BaseModel):
    title: str = ""
    content: str = ""
    source: str = ""
    author: str = ""


app = FastAPI(title="Folio Mock AI", version="0.1.0")


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

    return {
        "category": "tech",
        "category_name": "Technology",
        "confidence": 0.88,
        "tags": ["mock", "integration", "local"],
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
