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

    def test_register_login_me_update_delete(self):
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

        # update profile (language & currency)
        r_upd = self.client.put("/me", json={"language": "en", "currency": "USD"}, headers={"Authorization": f"Bearer {access}"})
        self.assertEqual(r_upd.status_code, 200)
        j = r_upd.json()
        self.assertEqual(j.get("language"), "en")
        self.assertEqual(j.get("currency"), "USD")

        # update password (requires currentPassword if exists)
        r_pwd = self.client.put("/me/password", json={"currentPassword": "Password123", "newPassword": "NewPwd1234"}, headers={"Authorization": f"Bearer {access}"})
        self.assertEqual(r_pwd.status_code, 200)

        # login with new password
        r_login = self.client.post("/auth/login", json={"email": email, "password": "NewPwd1234"})
        self.assertEqual(r_login.status_code, 200)
        access2 = r_login.json().get("accessToken")
        refresh2 = r_login.json().get("refreshToken")
        self.assertTrue(access2 and refresh2)

        # refresh tokens
        r_ref = self.client.post("/auth/refresh", json={"refreshToken": refresh2})
        self.assertEqual(r_ref.status_code, 200)
        self.assertTrue(r_ref.json().get("accessToken"))

        # change email (requires email code)
        new_email = _rand_email("new")
        r_code2 = self.client.post("/auth/email-code", json={"email": new_email, "purpose": "change_email"})
        self.assertEqual(r_code2.status_code, 200)
        dev_code2 = (r_code2.json() or {}).get("devCode")
        self.assertTrue(dev_code2 and len(dev_code2) == 4)
        r_ch = self.client.put("/me/email", json={"email": new_email, "password": "NewPwd1234", "verificationCode": dev_code2}, headers={"Authorization": f"Bearer {access2}"})
        self.assertEqual(r_ch.status_code, 200)
        self.assertEqual(r_ch.json().get("email"), new_email)

        # delete account
        r_del = self.client.request("DELETE", "/me", json={"currentPassword": "NewPwd1234", "reason": "test", "details": "cleanup"}, headers={"Authorization": f"Bearer {access2}"})
        self.assertEqual(r_del.status_code, 200)
        self.assertTrue(r_del.json().get("success"))
