import os
import random
import string
import unittest

try:
    from fastapi.testclient import TestClient  # type: ignore
except Exception:
    TestClient = None


def _rand_email(prefix: str = "test") -> str:
    s = "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(8))
    return f"{prefix}_{s}@example.com"


class TestAuthFlow(unittest.TestCase):
    def setUp(self):
        if TestClient is None:
            self.skipTest("fastapi not installed")
        # Ensure dev exposure for email code and reset token
        os.environ["PROVIDER_FAKE"] = "true"
        os.environ["EMAIL_CODE_DEV_EXPOSE"] = "true"
        os.environ["REGISTER_REQUIRE_EMAIL_VERIFICATION"] = "true"
        os.environ["REGISTER_DEV_UPDATE_PASSWORD"] = "true"
        os.environ["RESET_DEV_EXPOSE_TOKEN"] = "true"
        from server.app.main import app  # type: ignore
        self.client = TestClient(app)

    def test_register_login_me_update_logout(self):
        email = _rand_email("user")
        # request email code for register
        r_code = self.client.post("/auth/email-code", json={"email": email, "purpose": "register"})
        self.assertEqual(r_code.status_code, 200)
        dev_code = (r_code.json() or {}).get("devCode")
        self.assertTrue(dev_code and len(dev_code) == 4)

        # register
        r_reg = self.client.post("/auth/register", json={
            "name": "Tester",
            "email": email,
            "password": "Password123",
            "verificationCode": dev_code,
        })
        self.assertEqual(r_reg.status_code, 200)
        jr = r_reg.json()
        access = jr.get("accessToken")
        refresh = jr.get("refreshToken")
        self.assertTrue(access and refresh)

        # get me
        r_me = self.client.get("/me", headers={"Authorization": f"Bearer {access}"})
        self.assertEqual(r_me.status_code, 200)
        self.assertEqual((r_me.json() or {}).get("email"), email)

        # update profile (basic fields only)
        r_upd = self.client.put("/me", json={"name": "Tester"}, headers={"Authorization": f"Bearer {access}"})
        self.assertEqual(r_upd.status_code, 200)
        j = r_upd.json()
        self.assertEqual(j.get("name"), "Tester")

        # login again
        r_login = self.client.post("/auth/login", json={"email": email, "password": "Password123"})
        self.assertEqual(r_login.status_code, 200)
        access2 = r_login.json().get("accessToken")
        refresh2 = r_login.json().get("refreshToken")
        self.assertTrue(access2 and refresh2)

        # refresh tokens
        r_ref = self.client.post("/auth/refresh", json={"refreshToken": refresh2})
        self.assertEqual(r_ref.status_code, 200)
        self.assertTrue(r_ref.json().get("accessToken"))

        # logout
        r_out = self.client.post("/auth/logout", json={"refreshToken": refresh2})
        self.assertEqual(r_out.status_code, 200)
