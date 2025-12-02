import unittest

try:
    from fastapi.testclient import TestClient  # type: ignore
except Exception:
    TestClient = None


class TestSettingsLanguages(unittest.TestCase):
    def setUp(self):
        if TestClient is None:
            self.skipTest("fastapi not installed")
        from server.app.main import app  # type: ignore
        self.client = TestClient(app)

    def test_languages_contains_core(self):
        r = self.client.get("/settings/languages")
        self.assertEqual(r.status_code, 200)
        codes = [x["code"] for x in r.json()]
        for c in ["en", "zh-Hans", "zh-Hant", "ja", "ko", "th", "id", "es", "pt", "ms", "vi", "ar"]:
            self.assertIn(c, codes)
        self.assertGreaterEqual(len(codes), 12)

