import unittest

try:
    from fastapi.testclient import TestClient  # type: ignore
except Exception:
    TestClient = None


class TestCatalogBundlesEtag(unittest.TestCase):
    def setUp(self):
        if TestClient is None:
            self.skipTest("fastapi not installed")
        import os
        os.environ["PROVIDER_FAKE"] = "true"
        from server.app.main import app  # type: ignore
        self.client = TestClient(app)

    def test_etag_304(self):
        r1 = self.client.get("/catalog/bundles")
        self.assertEqual(r1.status_code, 200)
        etag = r1.headers.get("ETag")
        self.assertIsNotNone(etag)
        r2 = self.client.get("/catalog/bundles", headers={"If-None-Match": etag})
        self.assertEqual(r2.status_code, 304)
