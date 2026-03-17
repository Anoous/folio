"""AI service data models."""

from pydantic import BaseModel, field_validator


# Maximum content size: 200 KB (roughly 200K chars)
MAX_CONTENT_SIZE = 200_000


class AnalyzeRequest(BaseModel):
    title: str
    content: str
    source: str
    author: str

    @field_validator("content")
    @classmethod
    def truncate_content(cls, v: str) -> str:
        if len(v) > MAX_CONTENT_SIZE:
            return v[:MAX_CONTENT_SIZE]
        return v


class AnalyzeResponse(BaseModel):
    category: str
    category_name: str
    confidence: float
    tags: list[str]
    summary: str
    key_points: list[str]
    language: str
