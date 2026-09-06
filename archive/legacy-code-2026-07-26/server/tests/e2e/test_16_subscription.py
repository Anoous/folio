"""Subscription verification tests."""

import base64
import json
import os
import uuid
from datetime import datetime, timedelta, timezone

import jwt
import psycopg2

from helpers.api_client import FolioAPIClient
from helpers.assertions import assert_error_response
from helpers.test_auth import test_login


JWT_SECRET = os.environ.get(
    "E2E_JWT_SECRET",
    "e2e-test-secret-key-not-for-production",
)
DATABASE_URL = os.environ.get(
    "E2E_DATABASE_URL",
    "postgresql://folio:folio_test@localhost:15432/folio_test",
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


def _mock_jws(payload: dict) -> str:
    encoded_header = _b64url_json({"alg": "none"})
    encoded_payload = _b64url_json(payload)
    return f"{encoded_header}.{encoded_payload}."


def _b64url_json(payload: dict) -> str:
    raw = json.dumps(payload, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def _signed_transaction(original_transaction_id: str, expires_at: datetime | None = None) -> str:
    payload = {
        "transactionId": f"txn-{uuid.uuid4().hex}",
        "originalTransactionId": original_transaction_id,
        "productId": "com.folio.app.pro.yearly",
        "bundleId": "com.7WSH9CR7KS.folio.app",
    }
    if expires_at is not None:
        payload["expiresDate"] = int(expires_at.timestamp() * 1000)
    return _mock_jws(payload)


def _webhook_payload(notification_type: str, signed_transaction: str) -> str:
    return _mock_jws(
        {
            "notificationType": notification_type,
            "subtype": "",
            "data": {"signedTransactionInfo": signed_transaction},
        }
    )


def _subscription_row(user_id: str):
    conn = psycopg2.connect(DATABASE_URL)
    try:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT subscription, subscription_expires_at, monthly_quota
                   FROM users WHERE id = %s""",
                (user_id,),
            )
            return cur.fetchone()
    finally:
        conn.close()


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


class TestSubscriptionWebhook:

    def test_webhook_renew_updates_subscription_expiry(self, base_url):
        """DID_RENEW updates the subscription expiry by original transaction ID."""
        client = FolioAPIClient(base_url)
        data = test_login(client, alias="webhook-renew")
        original_transaction_id = "txn-webhook-renew"

        verify_resp = client.post(
            "/api/v1/subscription/verify",
            json={
                "transaction_id": original_transaction_id,
                "product_id": "com.folio.app.pro.yearly",
            },
        )
        assert verify_resp.status_code == 200

        renewed_until = datetime.now(timezone.utc) + timedelta(days=400)
        signed_transaction = _signed_transaction(original_transaction_id, renewed_until)
        signed_payload = _webhook_payload("DID_RENEW", signed_transaction)

        webhook_resp = client.post(
            "/api/v1/webhook/apple",
            json={"signedPayload": signed_payload},
            authenticated=False,
        )
        assert webhook_resp.status_code == 200

        subscription, expires_at, monthly_quota = _subscription_row(data["user"]["id"])
        assert subscription == "pro"
        assert monthly_quota == 9999
        assert expires_at > datetime.now(timezone.utc) + timedelta(days=300)
        client.close()

    def test_webhook_refund_downgrades_subscription(self, base_url):
        """REFUND downgrades the user found by original transaction ID."""
        client = FolioAPIClient(base_url)
        data = test_login(client, alias="webhook-refund")
        original_transaction_id = "txn-webhook-refund"

        verify_resp = client.post(
            "/api/v1/subscription/verify",
            json={
                "transaction_id": original_transaction_id,
                "product_id": "com.folio.app.pro.yearly",
            },
        )
        assert verify_resp.status_code == 200

        signed_transaction = _signed_transaction(original_transaction_id)
        signed_payload = _webhook_payload("REFUND", signed_transaction)

        webhook_resp = client.post(
            "/api/v1/webhook/apple",
            json={"signedPayload": signed_payload},
            authenticated=False,
        )
        assert webhook_resp.status_code == 200

        subscription, expires_at, monthly_quota = _subscription_row(data["user"]["id"])
        assert subscription == "free"
        assert expires_at is None
        assert monthly_quota == 30
        client.close()
