"""Subscription verification tests."""

from helpers.api_client import FolioAPIClient
from helpers.assertions import assert_error_response
from helpers.test_auth import test_login


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
