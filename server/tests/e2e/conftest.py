"""Pytest configuration and shared fixtures for Folio E2E tests."""

from __future__ import annotations

import pytest

from helpers.api_client import FolioAPIClient
from helpers.auth import dev_login
from helpers.polling import submit_and_wait
from helpers.test_urls import unique_url


# ---------------------------------------------------------------------------
# CLI options
# ---------------------------------------------------------------------------

def pytest_addoption(parser):
    parser.addoption("--base-url", default="http://localhost:18080",
                     help="Base URL of the Folio API server.")
    parser.addoption("--reader-url", default="http://localhost:13000",
                     help="Base URL of the Reader service (for direct health checks).")
    parser.addoption("--ai-url", default="http://localhost:18000",
                     help="Base URL of the AI service (for direct health checks).")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def base_url(request) -> str:
    return request.config.getoption("--base-url")


@pytest.fixture(scope="session")
def reader_url(request) -> str:
    return request.config.getoption("--reader-url")


@pytest.fixture(scope="session")
def ai_url(request) -> str:
    return request.config.getoption("--ai-url")


@pytest.fixture(scope="session")
def api(base_url) -> FolioAPIClient:
    """Session-scoped authenticated API client (default dev user)."""
    client = FolioAPIClient(base_url)
    dev_login(client)
    yield client
    client.close()


@pytest.fixture(scope="session")
def auth_data(api) -> dict:
    """Re-login to capture the full auth response (tokens + user)."""
    resp = api.dev_login()
    assert resp.status_code == 200
    return resp.json()


@pytest.fixture(scope="function")
def fresh_api(base_url) -> FolioAPIClient:
    """Function-scoped authenticated API client (fresh per test)."""
    client = FolioAPIClient(base_url)
    dev_login(client)
    yield client
    client.close()


@pytest.fixture(scope="function")
def unauthed_api(base_url) -> FolioAPIClient:
    """Function-scoped API client with NO auth token."""
    client = FolioAPIClient(base_url)
    yield client
    client.close()


@pytest.fixture(scope="session")
def submitted_article(api) -> dict:
    """Submit a unique URL and return the submit response (article_id + task_id).

    Does NOT wait for pipeline completion.
    """
    url = unique_url("submitted")
    resp = api.submit_url(url)
    assert resp.status_code == 202
    return resp.json()


@pytest.fixture(scope="session")
def completed_article(api) -> tuple[str, dict]:
    """Submit a URL, wait for pipeline to finish, return (article_id, task_body)."""
    url = unique_url("completed")
    article_id, task = submit_and_wait(api, url)
    assert task["status"] == "done", f"pipeline did not succeed: {task}"
    return article_id, task
