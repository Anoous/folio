"""Echo review quota E2E tests."""

import os

import psycopg2

from helpers.api_client import FolioAPIClient
from helpers.test_auth import test_login


DATABASE_URL = os.environ.get(
    "E2E_DATABASE_URL",
    "postgresql://folio:folio_test@localhost:15432/folio_test",
)


def _set_echo_week_count(user_id: str, count: int):
    conn = psycopg2.connect(DATABASE_URL)
    try:
        with conn.cursor() as cur:
            cur.execute(
                """UPDATE users
                   SET subscription = 'free',
                       echo_count_this_week = %s,
                       echo_week_reset_at = NOW() + INTERVAL '7 days'
                   WHERE id = %s""",
                (count, user_id),
            )
            conn.commit()
    finally:
        conn.close()


def _insert_due_echo_cards(user_id: str, article_id: str, count: int):
    conn = psycopg2.connect(DATABASE_URL)
    try:
        with conn.cursor() as cur:
            for index in range(count):
                cur.execute(
                    """INSERT INTO echo_cards (
                           user_id, article_id, card_type, question, answer, next_review_at
                       )
                       VALUES (%s, %s, 'insight', %s, %s, NOW() - INTERVAL '1 minute')""",
                    (user_id, article_id, f"Question {index}", f"Answer {index}"),
                )
            conn.commit()
    finally:
        conn.close()


class TestEcho:
    def test_today_cards_are_capped_by_remaining_free_weekly_quota(self, base_url):
        client = FolioAPIClient(base_url)
        try:
            data = test_login(client, alias="echo-quota-cap")
            article_resp = client.submit_manual(
                "Echo cards should respect the remaining weekly quota.",
                title="Echo Quota",
            )
            assert article_resp.status_code == 202, article_resp.text
            article_id = article_resp.json()["article_id"]

            _set_echo_week_count(data["user"]["id"], 2)
            _insert_due_echo_cards(data["user"]["id"], article_id, 3)

            today = client.get("/api/v1/echo/today", params={"limit": 5})
            assert today.status_code == 200, today.text
            body = today.json()

            assert body["weekly_limit"] == 3
            assert body["weekly_count"] == 2
            assert body["remaining_today"] == 1
            assert len(body["data"]) == 1
        finally:
            client.close()
