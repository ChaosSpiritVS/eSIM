import os
import unittest

try:
    from fastapi.testclient import TestClient  # type: ignore
except Exception:
    TestClient = None


class TestHealthStatus(unittest.TestCase):
    def setUp(self):
        if TestClient is None:
            self.skipTest("fastapi not installed")
        os.environ["SETTINGS_CURRENCIES_VISIBLE"] = "USD,CHF,CNY,EUR,GBP,HKD,JPY,SGD"
        from server.app.main import app  # type: ignore
        self.client = TestClient(app)

    def test_health_get(self):
        r = self.client.get("/health")
        self.assertEqual(r.status_code, 204)
        self.assertEqual(r.headers.get("Cache-Control"), "no-store")

    def test_health_head(self):
        r = self.client.head("/health")
        self.assertEqual(r.status_code, 204)
        self.assertEqual(r.headers.get("Cache-Control"), "no-store")

    def test_status_json(self):
        r = self.client.get("/status")
        self.assertEqual(r.status_code, 200)
        d = r.json()
        self.assertEqual(d.get("status"), "ok")
        self.assertIsInstance(d.get("version"), str)
        self.assertIsInstance(d.get("uptimeSeconds"), int)
        self.assertIn("caches", d)
