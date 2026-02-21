"""AI service data models."""

from pydantic import BaseModel


class AnalyzeRequest(BaseModel):
    title: str
    content: str
    source: str
    author: str


class AnalyzeResponse(BaseModel):
    category: str
    category_name: str
    confidence: float
    tags: list[str]
    summary: str
    key_points: list[str]
    language: str
