"""Tests for the /api/analyze endpoint."""

import json
from unittest.mock import AsyncMock, patch, MagicMock

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

VALID_RESPONSE = {
    "category": "tech",
    "category_name": "Technology",
    "confidence": 0.85,
    "tags": ["Swift", "并发", "async/await"],
    "summary": "本文介绍了Swift 5.5引入的async/await并发编程模型。",
    "key_points": [
        "Swift 5.5引入了原生async/await支持",
        "结构化并发简化了异步代码",
        "Actor模型解决了数据竞争问题",
    ],
    "language": "zh",
}


def _mock_completion(content: dict):
    """Create a mock OpenAI chat completion response."""
    choice = MagicMock()
    choice.message.content = json.dumps(content)
    response = MagicMock()
    response.choices = [choice]
    return response


def _make_request(title="Swift并发编程", content="Swift 5.5 引入了 async/await...",
                  source="web", author="Test"):
    return {
        "title": title,
        "content": content,
        "source": source,
        "author": author,
    }


@patch.dict("os.environ", {"DEEPSEEK_API_KEY": "test-key"})
@patch("app.pipeline.AsyncOpenAI")
def test_analyze_returns_valid_response(mock_openai_cls):
    mock_client = MagicMock()
    mock_client.chat.completions.create = AsyncMock(
        return_value=_mock_completion(VALID_RESPONSE)
    )
    mock_openai_cls.return_value = mock_client

    resp = client.post("/api/analyze", json=_make_request())
    assert resp.status_code == 200
    data = resp.json()
    assert data["category"] == "tech"
    assert data["category_name"] == "Technology"
    assert data["confidence"] == 0.85
    assert len(data["tags"]) == 3
    assert data["language"] == "zh"
    assert len(data["key_points"]) == 3
    assert data["summary"] != ""


@patch.dict("os.environ", {"DEEPSEEK_API_KEY": "test-key"})
@patch("app.pipeline.AsyncOpenAI")
def test_analyze_invalid_category_fallback(mock_openai_cls):
    bad_response = {**VALID_RESPONSE, "category": "invalid_category"}
    mock_client = MagicMock()
    mock_client.chat.completions.create = AsyncMock(
        return_value=_mock_completion(bad_response)
    )
    mock_openai_cls.return_value = mock_client

    resp = client.post("/api/analyze", json=_make_request())
    assert resp.status_code == 200
    data = resp.json()
    assert data["category"] == "other"
    assert data["category_name"] == "Other"
    assert data["confidence"] <= 0.5


@patch.dict("os.environ", {"DEEPSEEK_API_KEY": "test-key"})
@patch("app.pipeline.AsyncOpenAI")
def test_analyze_confidence_clamped(mock_openai_cls):
    over_response = {**VALID_RESPONSE, "confidence": 1.5}
    mock_client = MagicMock()
    mock_client.chat.completions.create = AsyncMock(
        return_value=_mock_completion(over_response)
    )
    mock_openai_cls.return_value = mock_client

    resp = client.post("/api/analyze", json=_make_request())
    assert resp.status_code == 200
    assert resp.json()["confidence"] == 1.0


@patch.dict("os.environ", {"DEEPSEEK_API_KEY": "test-key"})
@patch("app.pipeline.AsyncOpenAI")
def test_analyze_confidence_clamped_negative(mock_openai_cls):
    neg_response = {**VALID_RESPONSE, "confidence": -0.3}
    mock_client = MagicMock()
    mock_client.chat.completions.create = AsyncMock(
        return_value=_mock_completion(neg_response)
    )
    mock_openai_cls.return_value = mock_client

    resp = client.post("/api/analyze", json=_make_request())
    assert resp.status_code == 200
    assert resp.json()["confidence"] == 0.0


@patch.dict("os.environ", {"DEEPSEEK_API_KEY": "test-key"})
@patch("app.pipeline.AsyncOpenAI")
def test_analyze_chinese_article(mock_openai_cls):
    zh_response = {**VALID_RESPONSE, "language": "zh"}
    mock_client = MagicMock()
    mock_client.chat.completions.create = AsyncMock(
        return_value=_mock_completion(zh_response)
    )
    mock_openai_cls.return_value = mock_client

    resp = client.post("/api/analyze", json=_make_request(
        title="深度学习入门", content="本文介绍深度学习基础..."
    ))
    assert resp.status_code == 200
    assert resp.json()["language"] == "zh"


@patch.dict("os.environ", {"DEEPSEEK_API_KEY": "test-key"})
@patch("app.pipeline.AsyncOpenAI")
def test_analyze_english_article(mock_openai_cls):
    en_response = {
        **VALID_RESPONSE,
        "language": "en",
        "summary": "This article covers async/await in Swift.",
        "tags": ["Swift", "concurrency", "async"],
    }
    mock_client = MagicMock()
    mock_client.chat.completions.create = AsyncMock(
        return_value=_mock_completion(en_response)
    )
    mock_openai_cls.return_value = mock_client

    resp = client.post("/api/analyze", json=_make_request(
        title="Intro to Swift Concurrency",
        content="Swift 5.5 introduced async/await...",
    ))
    assert resp.status_code == 200
    assert resp.json()["language"] == "en"


def test_analyze_empty_content():
    resp = client.post("/api/analyze", json=_make_request(content=""))
    assert resp.status_code == 422


def test_analyze_whitespace_content():
    resp = client.post("/api/analyze", json=_make_request(content="   "))
    assert resp.status_code == 422


@patch.dict("os.environ", {"DEEPSEEK_API_KEY": "test-key"})
@patch("app.pipeline.AsyncOpenAI")
def test_analyze_api_error(mock_openai_cls):
    mock_client = MagicMock()
    mock_client.chat.completions.create = AsyncMock(
        side_effect=Exception("DeepSeek API unavailable")
    )
    mock_openai_cls.return_value = mock_client

    resp = client.post("/api/analyze", json=_make_request())
    assert resp.status_code == 502
    assert "error" in resp.json()["detail"].lower() or "AI" in resp.json()["detail"]


def test_health_still_works():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}
