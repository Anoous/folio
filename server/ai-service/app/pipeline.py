"""AI processing pipeline using DeepSeek API."""

import json
import os

from openai import AsyncOpenAI

from app.models import AnalyzeRequest, AnalyzeResponse
from app.prompts.combined import (
    CATEGORIES,
    SYSTEM_PROMPT,
    VALID_SLUGS,
    build_user_prompt,
)

MODEL = "deepseek-chat"
TEMPERATURE = 0.3
MAX_TOKENS = 1024
MAX_RETRIES = 1


def _get_client() -> AsyncOpenAI:
    return AsyncOpenAI(
        api_key=os.environ["DEEPSEEK_API_KEY"],
        base_url="https://api.deepseek.com",
    )


def _validate_response(raw: dict) -> dict:
    """Validate and sanitize the raw LLM response."""
    # Validate category slug
    category = raw.get("category", "other")
    if category not in VALID_SLUGS:
        category = "other"
        raw["confidence"] = min(raw.get("confidence", 0.5), 0.5)
    raw["category"] = category
    raw["category_name"] = CATEGORIES[category][1]

    # Clamp confidence to [0, 1]
    confidence = raw.get("confidence", 0.5)
    raw["confidence"] = max(0.0, min(1.0, float(confidence)))

    # Ensure tags is a list of 3-5 strings
    tags = raw.get("tags", [])
    if not isinstance(tags, list):
        tags = []
    raw["tags"] = [str(t) for t in tags[:5]] or ["untagged"]

    # Ensure key_points is a list
    key_points = raw.get("key_points", [])
    if not isinstance(key_points, list):
        key_points = []
    raw["key_points"] = [str(p) for p in key_points[:5]] or ["N/A"]

    # Ensure summary is a string
    raw["summary"] = str(raw.get("summary", ""))

    # Validate language
    language = raw.get("language", "en")
    if language not in ("zh", "en"):
        language = "en"
    raw["language"] = language

    return raw


async def _call_deepseek(user_prompt: str) -> dict:
    """Call DeepSeek API and return parsed JSON."""
    client = _get_client()
    response = await client.chat.completions.create(
        model=MODEL,
        response_format={"type": "json_object"},
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
        temperature=TEMPERATURE,
        max_tokens=MAX_TOKENS,
    )
    content = response.choices[0].message.content
    return json.loads(content)


async def analyze_article(request: AnalyzeRequest) -> AnalyzeResponse:
    """Analyze an article using DeepSeek API."""
    user_prompt = build_user_prompt(
        title=request.title,
        content=request.content,
        source=request.source,
        author=request.author,
    )

    last_error = None
    for attempt in range(MAX_RETRIES + 1):
        try:
            raw = await _call_deepseek(user_prompt)
            validated = _validate_response(raw)
            return AnalyzeResponse(**validated)
        except json.JSONDecodeError as e:
            last_error = e
            if attempt < MAX_RETRIES:
                continue
            raise
        except (KeyError, TypeError, ValueError) as e:
            last_error = e
            if attempt < MAX_RETRIES:
                continue
            raise

    raise last_error  # unreachable but satisfies type checker
