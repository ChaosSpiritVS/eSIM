import unittest

try:
    from fastapi.testclient import TestClient  # type: ignore
except Exception:
    TestClient = None


class TestOrdersFlow(unittest.TestCase):
    def setUp(self):
        if TestClient is None:
            self.skipTest("fastapi not installed")
        import os
        os.environ["PROVIDER_FAKE"] = "true"
        from server.app.main import app  # type: ignore
        self.client = TestClient(app)

    def _auth(self):
        # Register a quick user via email code
        import os, random
        os.environ["EMAIL_CODE_DEV_EXPOSE"] = "true"
        email = f"orders_{random.randint(1,1_000_000)}@example.com"
        r_code = self.client.post("/auth/email-code", json={"email": email, "purpose": "register"})
        dev_code = (r_code.json() or {}).get("devCode")
        r_reg = self.client.post("/auth/register", json={"name": "O", "email": email, "password": "Pass12345", "verificationCode": dev_code})
        return r_reg.json().get("accessToken")

    def test_create_and_list_order(self):
        access = self._auth()
        self.assertTrue(access)
        # create order
        r_new = self.client.post("/orders", json={"bundleId": "hk-1", "paymentMethod": "alipay"}, headers={"Authorization": f"Bearer {access}"})
        self.assertEqual(r_new.status_code, 200)
        oid = r_new.json().get("id")
        self.assertTrue(oid)
        # list orders
        r_list = self.client.get("/orders", headers={"Authorization": f"Bearer {access}"})
        self.assertEqual(r_list.status_code, 200)
        ids = [o.get("id") for o in r_list.json()]
        self.assertIn(oid, ids)
        # get order by id
        r_get = self.client.get(f"/orders/{oid}", headers={"Authorization": f"Bearer {access}"})
        self.assertEqual(r_get.status_code, 200)
        self.assertEqual(r_get.json().get("id"), oid)
