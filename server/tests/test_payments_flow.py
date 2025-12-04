import os
import unittest

try:
    from fastapi.testclient import TestClient  # type: ignore
except Exception:
    TestClient = None


class TestPaymentsMainFlow(unittest.TestCase):
    def setUp(self):
        if TestClient is None:
            self.skipTest("fastapi not installed")
        os.environ["PROVIDER_FAKE"] = "true"
        os.environ["EMAIL_CODE_DEV_EXPOSE"] = "true"
        os.environ["ENABLE_TEST_ENDPOINTS"] = "1"
        from server.app.main import app  # type: ignore
        self.client = TestClient(app)

    def _auth(self):
        import random
        email = f"pay_{random.randint(1,1_000_000)}@example.com"
        r_code = self.client.post("/auth/email-code", json={"email": email, "purpose": "register"})
        dev_code = (r_code.json() or {}).get("devCode")
        r_reg = self.client.post(
            "/auth/register",
            json={"name": "P", "email": email, "password": "Pass12345", "verificationCode": dev_code},
        )
        return r_reg.json().get("accessToken")

    def test_gsalary_pay(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        body = {"orderId": "ORD-2002", "method": "card"}
        r = self.client.post("/payments/gsalary/pay", json=body, headers=headers)
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertEqual(j.get("paymentId"), "PAY-ORD-2002")
        self.assertTrue((j.get("checkoutUrl") or "").endswith("GSALARY-card-ORD-2002"))

    def test_gsalary_consult(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        body = {"amount": 10.0, "currency": "USD"}
        r = self.client.post("/payments/gsalary/consult", json=body, headers=headers)
        self.assertEqual(r.status_code, 200)
        opts = (r.json() or {}).get("payment_options") or []
        methods = {o.get("payment_method_type") for o in opts}
        self.assertTrue({"CARD", "APPLEPAY", "PAYPAL"}.issubset(methods))

    def test_search_basic(self):
        r = self.client.get("/search", params={"q": "hk", "include": "country,region", "limit": 5})
        self.assertEqual(r.status_code, 200)
        j = r.json()
        if isinstance(j, dict) and "data" in j:
            self.assertIsInstance(j["data"], list)
        else:
            self.assertIsInstance(j, list)

    def test_webhooks_invalid_signature(self):
        body = {
            "provider": "paypal",
            "orderId": "OID-Z",
            "reference": "R-Z",
            "status": "paid",
            "amount": 9.9,
            "currency": "USD",
        }
        r = self.client.post("/webhooks/payments", json=body, headers={"X-Appid": "x", "Authorization": "bad"})
        self.assertEqual(r.status_code, 401)
