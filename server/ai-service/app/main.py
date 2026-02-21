"""Folio AI Service — article analysis via DeepSeek."""

import logging

from fastapi import FastAPI, HTTPException

from app.models import AnalyzeRequest, AnalyzeResponse
from app.pipeline import analyze_article

logger = logging.getLogger(__name__)

app = FastAPI(title="Folio AI Service", version="0.1.0")


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/api/analyze")
async def analyze(request: AnalyzeRequest) -> AnalyzeResponse:
    if not request.content or not request.content.strip():
        raise HTTPException(status_code=422, detail="content must not be empty")

    try:
        return await analyze_article(request)
    except Exception as e:
        logger.exception("AI analysis failed")
        raise HTTPException(status_code=502, detail=f"AI service error: {e}")
