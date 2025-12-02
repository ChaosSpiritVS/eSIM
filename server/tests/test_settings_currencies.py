import os
import unittest

try:
    from fastapi.testclient import TestClient  # type: ignore
except Exception:
    TestClient = None


class TestSettingsCurrencies(unittest.TestCase):
    def setUp(self):
        if TestClient is None:
            self.skipTest("fastapi not installed")
        os.environ["SETTINGS_CURRENCIES_VISIBLE"] = "USD,CHF,CNY,EUR,GBP,HKD,JPY,SGD"
        from server.app.main import app  # type: ignore
        self.client = TestClient(app)

    def test_visible_eight(self):
        r = self.client.get("/settings/currencies")
        self.assertEqual(r.status_code, 200)
        codes = [x["code"].upper() for x in r.json()]
        self.assertEqual(set(codes), {"USD","CHF","CNY","EUR","GBP","HKD","JPY","SGD"})
        self.assertEqual(len(codes), 8)
