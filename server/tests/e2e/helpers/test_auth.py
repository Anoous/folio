"""Test authentication via direct DB user creation + JWT generation.

Replaces the old dev_login endpoint with a self-contained approach:
  1. Insert a test user into PostgreSQL directly
  2. Generate a valid JWT access token using the known test secret
  3. Set the token on the API client
"""

from __future__ import annotations

import os
import uuid
from datetime import datetime, timedelta, timezone

import jwt
import psycopg2

# Defaults match run_e2e.sh / docker-compose.test.yml
DATABASE_URL = os.environ.get(
    "E2E_DATABASE_URL",
    "postgresql://folio:folio_test@localhost:15432/folio_test",
)
JWT_SECRET = os.environ.get(
    "E2E_JWT_SECRET",
    "e2e-test-secret-key-not-for-production",
)


def _ensure_user(apple_id: str, email: str, nickname: str) -> str:
    """Insert a test user if not exists, return user ID."""
    conn = psycopg2.connect(DATABASE_URL)
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE apple_id = %s", (apple_id,))
            row = cur.fetchone()
            if row:
                return str(row[0])

            user_id = str(uuid.uuid4())
            cur.execute(
                """INSERT INTO users (id, apple_id, email, nickname)
                   VALUES (%s, %s, %s, %s)""",
                (user_id, apple_id, email, nickname),
            )
            conn.commit()
            return user_id
    finally:
        conn.close()


def _make_token(user_id: str, token_type: str = "access", hours: int = 2) -> str:
    """Generate a JWT token matching the Go server's format."""
    now = datetime.now(timezone.utc)
    payload = {
        "uid": user_id,
        "type": token_type,
        "iss": "folio",
        "iat": now,
        "exp": now + timedelta(hours=hours),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")


def test_login(client, alias: str | None = None) -> dict:
    """Create a test user + JWT token pair, set token on client.

    Returns a dict matching the old AuthResponse shape for compatibility:
        {"access_token", "refresh_token", "expires_in", "user": {"id", ...}}
    """
    suffix = alias or "default"
    apple_id = f"test-user-{suffix}"
    email = f"test-{suffix}@folio.test"
    nickname = f"Test {suffix}"

    user_id = _ensure_user(apple_id, email, nickname)
    access_token = _make_token(user_id, "access", hours=2)
    refresh_token = _make_token(user_id, "refresh", hours=2160)  # 90 days

    client.set_token(access_token)

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "expires_in": 7200,
        "user": {
            "id": user_id,
            "email": email,
            "nickname": nickname,
            "apple_id": apple_id,
        },
    }
