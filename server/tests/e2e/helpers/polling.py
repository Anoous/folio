"""Polling utilities for async pipeline tests."""

from __future__ import annotations

import time

from .api_client import FolioAPIClient

TERMINAL_STATUSES = {"done", "failed"}


def poll_until_done(
    client: FolioAPIClient,
    task_id: str,
    *,
    timeout: float = 90.0,
    interval: float = 2.0,
) -> dict:
    """Poll GET /tasks/{id} until the task reaches a terminal status.

    Returns the final task JSON body.
    Raises AssertionError with diagnostic info on timeout or failure.
    """
    deadline = time.monotonic() + timeout
    last_status = None

    while time.monotonic() < deadline:
        resp = client.get_task(task_id)
        assert resp.status_code == 200, (
            f"GET /tasks/{task_id} returned {resp.status_code}: {resp.text}\n"
            "Hint: is the task ID valid? Was the article submitted correctly?"
        )
        body = resp.json()
        last_status = body.get("status")

        if last_status in TERMINAL_STATUSES:
            return body

        time.sleep(interval)

    raise AssertionError(
        f"Task {task_id} did not complete within {timeout}s. "
        f"Last status: {last_status}\n"
        "Possible causes:\n"
        "  - Reader service is down or unreachable\n"
        "  - AI service is down or unreachable\n"
        "  - Redis/asynq worker is not running\n"
        "  - The URL being crawled is unreachable or very slow\n"
        "Hint: check docker compose logs for the api, reader, and ai services."
    )


def poll_many_until_done(
    client: FolioAPIClient,
    task_ids: list[str],
    *,
    timeout: float = 180.0,
    interval: float = 2.0,
) -> dict[str, dict]:
    """Poll multiple tasks until all of them reach a terminal status."""
    pending = set(task_ids)
    results: dict[str, dict] = {}
    last_status: dict[str, str | None] = {task_id: None for task_id in task_ids}
    deadline = time.monotonic() + timeout

    while pending and time.monotonic() < deadline:
        for task_id in list(pending):
            resp = client.get_task(task_id)
            assert resp.status_code == 200, (
                f"GET /tasks/{task_id} returned {resp.status_code}: {resp.text}\n"
                "Hint: is the task ID valid? Was the article submitted correctly?"
            )
            body = resp.json()
            status = body.get("status")
            last_status[task_id] = status

            if status in TERMINAL_STATUSES:
                results[task_id] = body
                pending.remove(task_id)

        if pending:
            time.sleep(interval)

    if pending:
        remaining = {task_id: last_status[task_id] for task_id in sorted(pending)}
        raise AssertionError(
            f"{len(pending)} task(s) did not complete within {timeout}s. "
            f"Last statuses: {remaining}\n"
            "Possible causes:\n"
            "  - AI worker throughput is lower than expected for the benchmark corpus\n"
            "  - Redis/asynq worker is not running\n"
            "  - AI service is down or unreachable\n"
            "Hint: check docker compose logs for the api and worker."
        )

    return results


def submit_and_wait(
    client: FolioAPIClient,
    url: str,
    *,
    timeout: float = 90.0,
    interval: float = 2.0,
) -> tuple[str, dict]:
    """Submit a URL and poll until the pipeline finishes.

    Returns (article_id, final_task_body).
    """
    resp = client.submit_url(url)
    assert resp.status_code == 202, f"submit_url failed ({resp.status_code}): {resp.text}"
    data = resp.json()
    article_id = data["article_id"]
    task_id = data["task_id"]

    task = poll_until_done(client, task_id, timeout=timeout, interval=interval)
    return article_id, task
