import os
import unittest
from fastapi import HTTPException

from server.app.main import _gateway_call


class Stub:
    class S:
        request_id = None
    state = S()


class TestGatewayCall(unittest.TestCase):
    def setUp(self):
        os.environ["GSALARY_BASE_URL"] = ""
        os.environ["GSALARY_APPID"] = "appid-demo"
        os.environ["GSALARY_CLIENT_PRIVATE_KEY_PATH"] = ""

    def test_missing_base_url(self):
        with self.assertRaises(HTTPException) as ctx:
            _gateway_call(Stub(), "GET", "/x", {})
        self.assertEqual(ctx.exception.status_code, 500)
        self.assertEqual(ctx.exception.detail, "missing base url")

    def test_missing_client_private_key(self):
        os.environ["GSALARY_BASE_URL"] = "https://example.com"
        os.environ["GSALARY_CLIENT_PRIVATE_KEY_PATH"] = "/no/such/file.pem"
        with self.assertRaises(HTTPException) as ctx:
            _gateway_call(Stub(), "GET", "/x", {})
        self.assertEqual(ctx.exception.status_code, 500)
        self.assertEqual(ctx.exception.detail, "missing client private key")

