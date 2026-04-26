"""Subscription verification tests."""

import os
import uuid
from datetime import datetime, timedelta, timezone

import jwt

from helpers.api_client import FolioAPIClient
from helpers.assertions import assert_error_response
from helpers.test_auth import test_login


JWT_SECRET = os.environ.get(
    "E2E_JWT_SECRET",
    "e2e-test-secret-key-not-for-production",
)


def _access_token_for(user_id: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "uid": user_id,
        "type": "access",
        "iss": "folio",
        "iat": now,
        "exp": now + timedelta(hours=2),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")


class TestSubscriptionVerify:

    def test_verify_subscription_success(self, base_url):
        """Mock Apple verification activates a pro subscription."""
        client = FolioAPIClient(base_url)
        test_login(client, alias="subscription-success")

        resp = client.post(
            "/api/v1/subscription/verify",
            json={
                "transaction_id": "txn-subscription-success",
                "product_id": "com.folio.app.pro.yearly",
            },
        )

        assert resp.status_code == 200
        body = resp.json()
        assert body["subscription"] == "pro"
        assert "expires_at" in body
        client.close()

    def test_verify_subscription_rejects_product_mismatch(self, base_url):
        """Requested product_id must match Apple's verified transaction product."""
        client = FolioAPIClient(base_url)
        test_login(client, alias="subscription-product-mismatch")

        resp = client.post(
            "/api/v1/subscription/verify",
            json={
                "transaction_id": "txn-subscription-product-mismatch",
                "product_id": "com.folio.app.pro.monthly",
            },
        )

        assert_error_response(resp, 400, error_contains="invalid product")
        client.close()

    def test_verify_subscription_rejects_invalid_transaction(self, base_url):
        """Invalid Apple transaction IDs are client errors, not 500s."""
        client = FolioAPIClient(base_url)
        test_login(client, alias="subscription-invalid-transaction")

        resp = client.post(
            "/api/v1/subscription/verify",
            json={
                "transaction_id": "invalid-transaction",
                "product_id": "com.folio.app.pro.yearly",
            },
        )

        assert_error_response(resp, 400, error_contains="invalid transaction")
        client.close()

    def test_verify_subscription_rejects_unknown_user(self, base_url):
        """A valid JWT for a missing user cannot activate a subscription."""
        client = FolioAPIClient(base_url)
        client.set_token(_access_token_for(str(uuid.uuid4())))

        resp = client.post(
            "/api/v1/subscription/verify",
            json={
                "transaction_id": "txn-subscription-missing-user",
                "product_id": "com.folio.app.pro.yearly",
            },
        )

        assert_error_response(resp, 404, error_contains="not found")
        client.close()
