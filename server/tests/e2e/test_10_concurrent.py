"""Concurrent operations tests."""

import concurrent.futures
import pytest

from helpers.api_client import FolioAPIClient
from helpers.auth import dev_login
from helpers.polling import poll_until_done
from helpers.test_urls import unique_urls


class TestConcurrent:

    @pytest.mark.slow
    def test_concurrent_submissions(self, base_url):
        """Submit 5 URLs concurrently; all should be accepted."""
        client = FolioAPIClient(base_url)
        dev_login(client)

        urls = unique_urls(5, prefix="concurrent")
        results = []

        def submit(url):
            resp = client.submit_url(url)
            return resp.status_code, resp.json()

        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
            futures = [pool.submit(submit, u) for u in urls]
            for f in concurrent.futures.as_completed(futures):
                status, body = f.result()
                results.append((status, body))

        # All should be 202
        for status, body in results:
            assert status == 202, f"expected 202, got {status}: {body}"

        client.close()

    @pytest.mark.slow
    def test_concurrent_pipelines(self, base_url):
        """Submit 3 URLs concurrently and verify all pipelines complete."""
        client = FolioAPIClient(base_url)
        dev_login(client)

        urls = unique_urls(3, prefix="conc-pipe")
        task_ids = []
        for u in urls:
            resp = client.submit_url(u)
            assert resp.status_code == 202
            task_ids.append(resp.json()["task_id"])

        # Poll all tasks to completion
        for tid in task_ids:
            task = poll_until_done(client, tid, timeout=120)
            assert task["status"] == "done", f"task {tid} ended with {task['status']}"

        client.close()
