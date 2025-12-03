import os
import unittest
import types

from server.app.provider.auth import TokenManager, httpx


class TestTokenManager(unittest.TestCase):
    def setUp(self):
        os.environ["PROVIDER_BASE_URL"] = "https://example.com"
        os.environ["PROVIDER_AGENT_USERNAME"] = "u"
        os.environ["PROVIDER_AGENT_PASSWORD"] = "p"
        os.environ["PROVIDER_FAKE"] = "false"

    def test_fake_mode_get_token_and_refresh(self):
        os.environ["PROVIDER_FAKE"] = "true"
        tm = TokenManager()
        t1 = tm.get_token()
        tm.refresh()
        t2 = tm.get_token()
        self.assertTrue(t1)
        self.assertTrue(t2)

    def test_agent_login_success_sets_token_and_expiry(self):
        tm = TokenManager()

        class StubClient:
            def __init__(self, *args, **kwargs):
                pass

            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                pass

            def post(self, url, json, headers):
                return httpx.Response(200, request=httpx.Request("POST", url), json={
                    "code": 200,
                    "data": {
                        "access_token": "T",
                        "expires_in": 10,
                        "refresh_token": "R",
                        "refresh_expires_in": 20,
                    }
                })

        orig = httpx.Client
        try:
            httpx.Client = StubClient  # type: ignore
            tm._agent_login()
        finally:
            httpx.Client = orig  # type: ignore
        self.assertEqual(tm.get_token(), "T")

    def test_agent_login_error_uses_err_code_msg(self):
        tm = TokenManager()

        class StubClient:
            def __init__(self, *args, **kwargs):
                pass

            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                pass

            def post(self, url, json, headers):
                return httpx.Response(200, request=httpx.Request("POST", url), json={
                    "code": 200,
                    "data": {"err_code": 1003, "err_msg": "bad"}
                })

        orig = httpx.Client
        try:
            httpx.Client = StubClient  # type: ignore
            with self.assertRaises(RuntimeError) as ctx:
                tm._agent_login()
            self.assertIn("1003", str(ctx.exception))
        finally:
            httpx.Client = orig  # type: ignore

    def test_agent_refresh_success(self):
        tm = TokenManager()
        tm._refresh_token = "R0"
        tm._refresh_expires_at = 9999999999

        class StubClient:
            def __init__(self, *args, **kwargs):
                pass

            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                pass

            def post(self, url, json, headers):
                return httpx.Response(200, request=httpx.Request("POST", url), json={
                    "code": 200,
                    "data": {
                        "access_token": "T2",
                        "expires_in": 10,
                        "refresh_token": "R2",
                        "refresh_expires_in": 20,
                    }
                })

        orig = httpx.Client
        try:
            httpx.Client = StubClient  # type: ignore
            tm._agent_refresh()
        finally:
            httpx.Client = orig  # type: ignore
        self.assertEqual(tm.get_token(), "T2")
