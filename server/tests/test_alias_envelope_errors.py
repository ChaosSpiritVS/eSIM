import unittest

try:
    from fastapi.testclient import TestClient  # type: ignore
except Exception:
    TestClient = None


class TestAliasEnvelopeErrors(unittest.TestCase):
    def setUp(self):
        if TestClient is None:
            self.skipTest("fastapi not installed")
        from server.app import main as m  # type: ignore
        self.m = m
        self.client = TestClient(m.app)

    def test_validation_error_enveloped(self):
        # Wrong type for page_number triggers RequestValidationError (422 enveloped)
        r = self.client.post("/bundle/list", json={"page_number": "x", "page_size": 10})
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertEqual(body.get("code"), 422)
        self.assertEqual(body.get("msg"), "invalid request")

    def test_provider_error_enveloped(self):
        # Monkeypatch catalog_service to raise ProviderError on alias route
        from server.app.provider.errors import ProviderError  # type: ignore

        class FakeCatalogSvc:
            def bundle_list(self, **kwargs):
                raise ProviderError(code=1003, msg="param error", http_status=400)

        orig = self.m.catalog_service
        try:
            self.m.catalog_service = FakeCatalogSvc()
            r = self.client.post("/bundle/list", json={"page_number": 1, "page_size": 10})
            self.assertEqual(r.status_code, 200)
            body = r.json()
            self.assertEqual(body.get("code"), 200)
            data = body.get("data") or {}
            self.assertEqual(data.get("err_code"), 1003)
            self.assertIn("param", str(data.get("err_msg")))
        finally:
            self.m.catalog_service = orig

