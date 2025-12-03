import os
import unittest
import httpx

from typing import Any, Dict

from server.app.provider.http import ProviderHTTP
from server.app.provider.errors import ProviderError


class StubTokenMgr:
    def __init__(self):
        self._token = "t1"
        self.fake = False
        self.refreshed = 0

    def get_token(self) -> str:
        return self._token

    def refresh(self):
        self.refreshed += 1
        self._token = "t2"


class TestProviderHTTP(unittest.TestCase):
    def setUp(self):
        os.environ["PROVIDER_HTTP_BACKOFF_MS"] = "0"
        os.environ["PROVIDER_HTTP_RETRIES"] = "1"

    def test_fake_envelope_without_base_url(self):
        os.environ["PROVIDER_BASE_URL"] = ""
        tm = StubTokenMgr()
        tm.fake = True
        http = ProviderHTTP(tm)
        env = http.post("/any", {"x": 1}, include_token=True)
        self.assertEqual(env.get("code"), 0)

    def test_401_refresh_then_success(self):
        os.environ["PROVIDER_BASE_URL"] = "https://example.com"
        tm = StubTokenMgr()
        http = ProviderHTTP(tm)

        req = httpx.Request("POST", "https://example.com/test")

        class C:
            def __init__(self):
                self.called = 0

            def post(self, url: str, json: Dict[str, Any], headers: Dict[str, str]):
                self.called += 1
                if self.called == 1:
                    resp = httpx.Response(401, request=req)
                    raise httpx.HTTPStatusError("401", request=req, response=resp)
                # second attempt succeeds
                return httpx.Response(200, request=req, json={"code": 200, "data": {}})

        http._client = C()  # type: ignore
        env = http.post("/test", {"y": 2}, include_token=True)
        self.assertEqual(env.get("code"), 200)
        self.assertEqual(tm.refreshed, 1)

    def test_500_retry_then_success(self):
        os.environ["PROVIDER_BASE_URL"] = "https://example.com"
        tm = StubTokenMgr()
        http = ProviderHTTP(tm)
        req = httpx.Request("POST", "https://example.com/x")

        class C:
            def __init__(self):
                self.called = 0

            def post(self, url: str, json: Dict[str, Any], headers: Dict[str, str]):
                self.called += 1
                if self.called == 1:
                    resp = httpx.Response(500, request=req)
                    raise httpx.HTTPStatusError("500", request=req, response=resp)
                return httpx.Response(200, request=req, json={"code": 200, "data": {}})

        http._client = C()  # type: ignore
        env = http.post("/x", {"a": 1}, include_token=False)
        self.assertEqual(env.get("code"), 200)

    def test_request_error_retry_then_provider_error(self):
        os.environ["PROVIDER_BASE_URL"] = "https://example.com"
        os.environ["PROVIDER_HTTP_RETRIES"] = "0"
        tm = StubTokenMgr()
        http = ProviderHTTP(tm)
        req = httpx.Request("POST", "https://example.com/y")

        class C:
            def post(self, url: str, json: Dict[str, Any], headers: Dict[str, str]):
                raise httpx.RequestError("conn", request=req)

        http._client = C()  # type: ignore
        with self.assertRaises(ProviderError) as ctx:
            http.post("/y", {"b": 2}, include_token=False)
        self.assertEqual(ctx.exception.http_status, 502)

    def test_envelope_error_with_err_code(self):
        os.environ["PROVIDER_BASE_URL"] = "https://example.com"
        tm = StubTokenMgr()
        http = ProviderHTTP(tm)
        req = httpx.Request("POST", "https://example.com/z")

        class C:
            def post(self, url: str, json: Dict[str, Any], headers: Dict[str, str]):
                return httpx.Response(200, request=req, json={"code": 200, "data": {"err_code": 1003, "err_msg": "bad"}, "msg": ""})

        http._client = C()  # type: ignore
        env = http.post("/z", {"c": 3}, include_token=True)
        self.assertIsNone(env)

    def test_envelope_error_411_refresh_then_success(self):
        os.environ["PROVIDER_BASE_URL"] = "https://example.com"
        tm = StubTokenMgr()
        http = ProviderHTTP(tm)
        req = httpx.Request("POST", "https://example.com/w")

        class C:
            def __init__(self):
                self.called = 0

            def post(self, url: str, json: Dict[str, Any], headers: Dict[str, str]):
                self.called += 1
                if self.called == 1:
                    return httpx.Response(200, request=req, json={"code": 411, "data": {}, "msg": "expired"})
                return httpx.Response(200, request=req, json={"code": 200, "data": {}})

        http._client = C()  # type: ignore
        env = http.post("/w", {"d": 4}, include_token=True)
        self.assertEqual(env.get("code"), 200)
        self.assertEqual(tm.refreshed, 1)
