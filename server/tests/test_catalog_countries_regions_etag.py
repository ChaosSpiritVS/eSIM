import unittest

try:
    from fastapi.testclient import TestClient  # type: ignore
except Exception:
    TestClient = None


class TestCatalogCountriesRegionsEtag(unittest.TestCase):
    def setUp(self):
        if TestClient is None:
            self.skipTest("fastapi not installed")
        from server.app.main import app  # type: ignore
        self.client = TestClient(app)

    def test_countries_etag(self):
        r1 = self.client.get("/catalog/countries")
        self.assertEqual(r1.status_code, 200)
        etag = r1.headers.get("ETag")
        self.assertIsNotNone(etag)
        r2 = self.client.get("/catalog/countries", headers={"If-None-Match": etag})
        self.assertEqual(r2.status_code, 304)

    def test_regions_etag(self):
        r1 = self.client.get("/catalog/regions")
        self.assertEqual(r1.status_code, 200)
        etag = r1.headers.get("ETag")
        self.assertIsNotNone(etag)
        r2 = self.client.get("/catalog/regions", headers={"If-None-Match": etag})
        self.assertEqual(r2.status_code, 304)

