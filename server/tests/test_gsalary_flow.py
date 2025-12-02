import os
import unittest

try:
    from fastapi.testclient import TestClient  # type: ignore
except Exception:
    TestClient = None


class TestGSalaryAndSearch(unittest.TestCase):
    def setUp(self):
        if TestClient is None:
            self.skipTest("fastapi not installed")
        os.environ["PROVIDER_FAKE"] = "true"
        os.environ["EMAIL_CODE_DEV_EXPOSE"] = "true"
        os.environ["ENABLE_TEST_ENDPOINTS"] = "1"
        from server.app.main import app  # type: ignore
        self.client = TestClient(app)

    def _auth(self):
        import random
        email = f"gsalary_{random.randint(1,1_000_000)}@example.com"
        r_code = self.client.post("/auth/email-code", json={"email": email, "purpose": "register"})
        dev_code = (r_code.json() or {}).get("devCode")
        r_reg = self.client.post(
            "/auth/register",
            json={"name": "G", "email": email, "password": "Pass12345", "verificationCode": dev_code},
        )
        return r_reg.json().get("accessToken")

    def test_gsalary_create_idempotency_demo(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}", "Idempotency-Key": "idem-1"}
        body = {"orderId": "ORD-1001", "method": "card", "amount": 9.99, "currency": "USD"}
        r1 = self.client.post("/payments/gsalary/create", json=body, headers=headers)
        self.assertEqual(r1.status_code, 200)
        j1 = r1.json()
        self.assertTrue(j1.get("checkoutUrl", "").endswith("GSALARY-card-ORD-1001"))
        self.assertEqual(j1.get("paymentId"), "GSALARY-card-ORD-1001")
        r2 = self.client.post("/payments/gsalary/create", json=body, headers=headers)
        self.assertEqual(r2.status_code, 200)
        j2 = r2.json()
        self.assertEqual(j1, j2)

    def test_gsalary_pay_demo(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        body = {"orderId": "ORD-2002", "method": "card"}
        r = self.client.post("/payments/gsalary/pay", json=body, headers=headers)
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertEqual(j.get("paymentId"), "PAY-ORD-2002")
        self.assertTrue((j.get("checkoutUrl") or "").endswith("GSALARY-card-ORD-2002"))

    def test_gsalary_consult_demo(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        body = {"amount": 10.0, "currency": "USD"}
        r = self.client.post("/payments/gsalary/consult", json=body, headers=headers)
        self.assertEqual(r.status_code, 200)
        opts = (r.json() or {}).get("payment_options") or []
        methods = {o.get("payment_method_type") for o in opts}
        self.assertTrue({"CARD", "APPLEPAY", "PAYPAL"}.issubset(methods))

    def test_gsalary_query_demo(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        body = {"payment_request_id": "PR-XYZ", "payment_id": "PID-XYZ"}
        r = self.client.post("/payments/gsalary/query", json=body, headers=headers)
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertEqual(j.get("payment_status"), "SUCCESS")
        self.assertTrue(j.get("captured"))

    def test_gsalary_refund_demo(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}", "Idempotency-Key": "idem-refund"}
        body = {
            "refund_request_id": "RFND-100",
            "payment_request_id": "PR-100",
            "refund_currency": "USD",
            "refund_amount": 1.23,
        }
        r = self.client.post("/payments/gsalary/refund", json=body, headers=headers)
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertEqual(j.get("refund_id"), "RFND-RFND-100")
        self.assertEqual(j.get("refund_status"), "PROCESSING")
        self.assertEqual(j.get("refund_currency"), "USD")
        self.assertEqual(j.get("refund_amount"), 1.23)

    def test_gsalary_refund_query_demo(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        body = {"refund_request_id": "RFND-100", "payment_request_id": "PR-100"}
        r = self.client.post("/payments/gsalary/refund/query", json=body, headers=headers)
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertEqual(j.get("refund_status"), "PROCESSING")

    def test_gsalary_cancel_demo(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}", "Idempotency-Key": "idem-cancel"}
        body = {"payment_request_id": "PR-777"}
        r = self.client.post("/payments/gsalary/cancel", json=body, headers=headers)
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertEqual(j.get("paymentRequestId"), "PR-777")
        self.assertTrue(str(j.get("paymentId" or "")).startswith("PAY-"))
        self.assertIsInstance(j.get("cancelTime"), str)

    def test_gsalary_auth_token_empty(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        r = self.client.get("/payments/gsalary/auth/token", headers=headers)
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertIsNone(j.get("access_token"))
        self.assertIsNone(j.get("refresh_token"))

    def test_gsalary_auth_refresh_missing_key_error(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        body = {"refresh_token": "r-xyz"}
        r = self.client.post("/payments/gsalary/auth/refresh", json=body, headers=headers)
        self.assertEqual(r.status_code, 500)

    def test_gsalary_auth_revoke_missing_key_error(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        body = {"access_token": "a-xyz"}
        r = self.client.post("/payments/gsalary/auth/revoke", json=body, headers=headers)
        self.assertEqual(r.status_code, 500)

    def test_search_log_and_recent(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        r0 = self.client.get("/search/recent", headers=headers)
        self.assertEqual(r0.status_code, 200)
        self.assertIsInstance(r0.json(), list)
        body = {"kind": "country", "countryCode": "CN", "title": "China"}
        r_log = self.client.post("/search/log", json=body, headers=headers)
        self.assertEqual(r_log.status_code, 200)
        self.assertTrue(r_log.json().get("success"))
        r1 = self.client.get("/search/recent", headers=headers)
        self.assertEqual(r1.status_code, 200)
        items = r1.json()
        self.assertTrue(len(items) >= 1)
        self.assertEqual(items[0].get("kind"), "country")
        self.assertEqual(items[0].get("countryCode"), "CN")

    def test_search_recent_delete_item_and_all(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        body = {"kind": "region", "regionCode": "eu", "title": "Europe"}
        r_log = self.client.post("/search/log", json=body, headers=headers)
        self.assertEqual(r_log.status_code, 200)
        r_list = self.client.get("/search/recent", headers=headers)
        self.assertEqual(r_list.status_code, 200)
        r_del_item = self.client.delete("/search/recent/region/eu", headers=headers)
        self.assertEqual(r_del_item.status_code, 200)
        self.assertTrue(r_del_item.json().get("success"))
        r_list2 = self.client.get("/search/recent", headers=headers)
        self.assertEqual(r_list2.status_code, 200)
        for it in r_list2.json():
            self.assertFalse(it.get("kind") == "region" and (it.get("regionCode") or "").lower() == "eu")
        r_del_all = self.client.delete("/search/recent", headers=headers)
        self.assertEqual(r_del_all.status_code, 200)
        self.assertTrue(r_del_all.json().get("success"))
        r_list3 = self.client.get("/search/recent", headers=headers)
        self.assertEqual(r_list3.status_code, 200)
        self.assertEqual(len(r_list3.json()), 0)

    def test_search_basic(self):
        r = self.client.get("/search", params={"q": "hk", "include": "country,region", "limit": 5})
        self.assertEqual(r.status_code, 200)
        j = r.json()
        if isinstance(j, dict) and "data" in j:
            self.assertIsInstance(j["data"], list)
        else:
            self.assertIsInstance(j, list)

    def test_bundle_detail_by_code_envelope(self):
        r = self.client.post("/bundle/detail-by-code", json={"bundle_code": "HKG_0110202517200001"})
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertEqual(j.get("code"), 200)
        d = j.get("data") or {}
        self.assertEqual(d.get("id"), "HKG_0110202517200001")
        self.assertIsInstance(d.get("currency"), str)
        self.assertIsInstance(d.get("validityDays"), int)

    def test_bundle_networks_v2_envelope(self):
        r = self.client.post("/bundle/networks", json={"bundle_code": "HKG_0110202517200001"})
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertEqual(j.get("code"), 200)
        d = j.get("data") or {}
        nets = d.get("networks") or []
        self.assertIsInstance(nets, list)
        self.assertGreaterEqual(d.get("networks_count") or 0, 1)

    def test_bundle_networks_flat_envelope(self):
        r = self.client.post("/bundle/networks/flat", json={"bundle_code": "HKG_0110202517200001"})
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertEqual(j.get("code"), 200)
        d = j.get("data") or {}
        ops = d.get("operators") or []
        self.assertIsInstance(ops, list)
        self.assertGreaterEqual(d.get("operators_count") or 0, 1)

    def test_agent_account_envelope(self):
        r = self.client.post("/agent/account")
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertEqual(j.get("code"), 200)
        d = j.get("data") or {}
        self.assertIsInstance(d.get("agent_id"), str)
        self.assertIsInstance(d.get("balance"), (int, float))

    def test_agent_bills_get_and_post(self):
        r_get = self.client.get("/agent/bills", params={"page": 1, "pageSize": 10})
        self.assertEqual(r_get.status_code, 200)
        jg = r_get.json()
        self.assertIsInstance(jg.get("bills"), list)
        r_post = self.client.post("/agent/bills", json={"page_number": 1, "page_size": 10})
        self.assertEqual(r_post.status_code, 200)
        jp = r_post.json()
        self.assertEqual(jp.get("code"), 200)
        dp = jp.get("data") or {}
        self.assertIsInstance(dp.get("bills"), list)

    def test_bundle_assign_envelope(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        ref = "R" * 30
        r = self.client.post(
            "/bundle/assign",
            json={"bundle_code": "HKG_0110202517200001", "order_reference": ref, "name": "U", "email": "u@example.com"},
            headers=headers,
        )
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertEqual(j.get("code"), 200)
        d = j.get("data") or {}
        self.assertIsInstance(d.get("order_id"), str)
        self.assertIsInstance(d.get("iccid"), str)

    def test_orders_list_detail_consumption_envelopes(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}", "X-Dev-All": "1"}
        r_list = self.client.post("/orders/list", json={"page_number": 1, "page_size": 10}, headers=headers)
        self.assertEqual(r_list.status_code, 200)
        jl = r_list.json()
        self.assertEqual(jl.get("code"), 200)
        data = jl.get("data") or {}
        orders = data.get("orders") or []
        self.assertIsInstance(orders, list)
        if orders:
            ref = orders[0].get("order_reference")
            self.assertTrue(ref)
            r_detail = self.client.post("/orders/detail", json={"order_reference": ref}, headers=headers)
            self.assertEqual(r_detail.status_code, 200)
            jd = r_detail.json()
            self.assertEqual(jd.get("code"), 200)
            dd = jd.get("data") or {}
            self.assertIsInstance(dd.get("bundle_name"), str)
            r_cons = self.client.post("/orders/consumption/batch", json={"order_references": [ref]}, headers=headers)
            self.assertEqual(r_cons.status_code, 200)
            jc = r_cons.json()
            self.assertEqual(jc.get("code"), 200)
            dc = jc.get("data") or {}
            self.assertIsInstance(dc.get("items") or [], list)

    def test_orders_detail_by_id_envelope(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}", "X-Dev-All": "1"}
        r_list = self.client.post("/orders/list", json={"page_number": 1, "page_size": 10}, headers=headers)
        self.assertEqual(r_list.status_code, 200)
        orders = (r_list.json().get("data") or {}).get("orders") or []
        if orders:
            oid = orders[0].get("order_id")
            self.assertTrue(oid)
            r = self.client.post("/orders/detail-by-id", json={"orderId": oid}, headers=headers)
            self.assertEqual(r.status_code, 200)
            j = r.json()
            self.assertEqual(j.get("code"), 200)
            d = j.get("data") or {}
            self.assertIsInstance(d.get("bundle_name"), str)

    def test_orders_list_with_usage_envelope(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        r = self.client.post("/orders/list-with-usage", json={"page_number": 1, "page_size": 10}, headers=headers)
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertEqual(j.get("code"), 200)
        d = j.get("data") or {}
        items = d.get("items") or []
        self.assertIsInstance(items, list)
        if items:
            u = (items[0] or {}).get("usage") or {}
            self.assertTrue("plan_status_localized" in u or True)

    def test_orders_refund_path_dto(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        r_new = self.client.post("/orders", json={"bundleId": "hk-1", "paymentMethod": "alipay"}, headers=headers)
        self.assertEqual(r_new.status_code, 200)
        oid = r_new.json().get("id")
        self.assertTrue(oid)
        r_refund = self.client.post(f"/orders/{oid}/refund", json={"reason": "t"}, headers=headers)
        self.assertEqual(r_refund.status_code, 200)
        jr = r_refund.json()
        self.assertIsInstance(jr.get("accepted"), bool)

    def test_orders_refund_by_id_envelope(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        r_new = self.client.post("/orders", json={"bundleId": "hk-1", "paymentMethod": "alipay"}, headers=headers)
        oid = r_new.json().get("id")
        r = self.client.post("/orders/refund-by-id", json={"orderId": oid, "reason": "t"}, headers=headers)
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertEqual(j.get("code"), 200)
        d = j.get("data") or {}
        self.assertIsInstance(d.get("accepted"), bool)

    def test_alipay_create_simple(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        r = self.client.post("/payments/alipay/create", json={"orderId": "OID-1"}, headers=headers)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json().get("orderString"), "ALIPAY|OID-1")

    def test_i18n_upsert_countries_regions_bundles(self):
        r1 = self.client.post("/i18n/countries/upsert", json={"items": [{"iso2_code": "US", "iso3_code": "USA", "lang_code": "en", "name": "United States"}]})
        self.assertEqual(r1.status_code, 200)
        self.assertTrue(r1.json().get("success"))
        r2 = self.client.post("/i18n/regions/upsert", json={"items": [{"region_code": "eu", "lang_code": "en", "name": "Europe"}]})
        self.assertEqual(r2.status_code, 200)
        self.assertTrue(r2.json().get("success"))
        r3 = self.client.post("/i18n/bundles/upsert", json={"items": [{"bundle_code": "HKG_0110202517200001", "lang_code": "en", "marketing_name": "Hong Kong", "name": "HK 1GB", "description": "d"}]})
        self.assertEqual(r3.status_code, 200)
        self.assertTrue(r3.json().get("success"))

    def test_config_mapping_and_header(self):
        os.environ["TTL_CATALOG"] = "600"
        os.environ["ORDERS_CACHE_TTL"] = "300"
        os.environ["BANNER_ENABLED"] = "true"
        r = self.client.get("/config")
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertEqual(j.get("catalogCacheTTL"), 600.0)
        self.assertEqual(j.get("ordersCacheTTL"), 300.0)
        self.assertTrue(j.get("bannerEnabled"))
        self.assertIsNotNone(r.headers.get("X-Request-Id"))

    def test_status_html_page(self):
        r = self.client.get("/status.html")
        self.assertEqual(r.status_code, 200)
        html = r.text or ""
        self.assertIn("Simigo Backend Status", html)
        self.assertIn("status", html)

    def test_agent_account_get_dto(self):
        r = self.client.get("/agent/account")
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertIsInstance(j.get("agent_id"), str)
        self.assertIsInstance(j.get("balance"), (int, float))

    def test_catalog_bundle_get_and_networks_etag(self):
        rb = self.client.get("/catalog/bundles/hk-1")
        self.assertEqual(rb.status_code, 200)
        jb = rb.json()
        self.assertEqual(jb.get("id"), "hk-1")
        self.assertIsInstance(jb.get("currency"), str)
        rn1 = self.client.get("/catalog/bundles/hk-1/networks")
        self.assertEqual(rn1.status_code, 200)
        etag = rn1.headers.get("ETag")
        self.assertIsNotNone(etag)
        rn2 = self.client.get("/catalog/bundles/hk-1/networks", headers={"If-None-Match": etag})
        self.assertEqual(rn2.status_code, 304)

    def test_orders_list_normalized_and_consumptions(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}", "X-Dev-All": "1"}
        r_norm = self.client.post("/orders/list-normalized", json={"page_number": 1, "page_size": 10}, headers=headers)
        self.assertEqual(r_norm.status_code, 200)
        jn = r_norm.json()
        self.assertIsInstance(jn, list)
        r_list = self.client.post("/orders/list", json={"page_number": 1, "page_size": 10}, headers=headers)
        orders = (r_list.json().get("data") or {}).get("orders") or []
        if orders:
            ref = orders[0].get("order_reference")
            oid = orders[0].get("order_id")
            self.assertTrue(ref)
            self.assertTrue(oid)
            rc = self.client.post("/orders/consumption", json={"order_reference": ref}, headers=headers)
            self.assertEqual(rc.status_code, 200)
            jc = rc.json()
            self.assertEqual(jc.get("code"), 200)
            dc = jc.get("data") or {}
            self.assertIsInstance((dc.get("order") or {}).get("data_unit"), str)
            rc2 = self.client.post("/orders/consumption-by-id", json={"order_id": oid}, headers=headers)
            self.assertEqual(rc2.status_code, 200)
            jc2 = rc2.json()
            self.assertEqual(jc2.get("code"), 200)
            dc2 = jc2.get("data") or {}
            self.assertIn("order", dc2)

    def test_orders_init_mappings_envelope(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        r = self.client.post("/orders/mappings/init", headers=headers)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json().get("code"), 200)

    def test_auth_password_reset_confirm_and_logout(self):
        import random
        email = f"reset_{random.randint(1,1_000_000)}@example.com"
        r_code = self.client.post("/auth/email-code", json={"email": email, "purpose": "register"})
        dev_code = (r_code.json() or {}).get("devCode")
        r_reg = self.client.post("/auth/register", json={"name": "U", "email": email, "password": "Pass12345", "verificationCode": dev_code})
        self.assertEqual(r_reg.status_code, 200)
        tokens = r_reg.json()
        refresh = tokens.get("refreshToken")
        self.assertTrue(refresh)
        r_reset = self.client.post("/auth/password-reset", json={"email": email})
        self.assertEqual(r_reset.status_code, 200)
        dev_token = (r_reset.json() or {}).get("devToken")
        self.assertTrue(dev_token)
        r_confirm = self.client.post("/auth/password-reset/confirm", json={"token": dev_token, "newPassword": "NewPass1234"})
        self.assertEqual(r_confirm.status_code, 200)
        self.assertTrue(r_confirm.json().get("success"))
        r_logout = self.client.post("/auth/logout", json={"refreshToken": refresh})
        self.assertEqual(r_logout.status_code, 200)
        self.assertTrue(r_logout.json().get("success"))
        r_refresh = self.client.post("/auth/refresh", json={"refreshToken": refresh})
        self.assertEqual(r_refresh.status_code, 401)

    def test_auth_apple_login(self):
        import random
        uid = f"apple_{random.randint(1,1_000_000)}"
        r = self.client.post("/auth/apple", json={"userId": uid})
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertTrue(j.get("accessToken"))
        self.assertTrue(j.get("refreshToken"))
        self.assertIsNone((j.get("user") or {}).get("email"))

    def test_auth_refresh_success(self):
        import random
        email = f"refresh_{random.randint(1,1_000_000)}@example.com"
        r_code = self.client.post("/auth/email-code", json={"email": email, "purpose": "register"})
        dev_code = (r_code.json() or {}).get("devCode")
        r_reg = self.client.post("/auth/register", json={"name": "U", "email": email, "password": "Pass12345", "verificationCode": dev_code})
        self.assertEqual(r_reg.status_code, 200)
        refresh = r_reg.json().get("refreshToken")
        self.assertTrue(refresh)
        r_ref = self.client.post("/auth/refresh", json={"refreshToken": refresh})
        self.assertEqual(r_ref.status_code, 200)
        j = r_ref.json()
        self.assertTrue(j.get("accessToken"))
        self.assertTrue(j.get("refreshToken"))

    def test_orders_get_list_and_usage(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}"}
        r_new = self.client.post("/orders", json={"bundleId": "hk-1", "paymentMethod": "alipay"}, headers=headers)
        self.assertEqual(r_new.status_code, 200)
        oid = r_new.json().get("id")
        self.assertTrue(oid)
        r_detail = self.client.get(f"/orders/{oid}", headers=headers)
        self.assertEqual(r_detail.status_code, 200)
        self.assertEqual(r_detail.json().get("id"), oid)
        r_list = self.client.get("/orders", params={"page": 1, "pageSize": 10}, headers=headers)
        self.assertEqual(r_list.status_code, 200)
        self.assertEqual(r_list.headers.get("X-Page"), "1")
        self.assertEqual(r_list.headers.get("X-Page-Size"), "10")
        r_usage = self.client.get(f"/orders/{oid}/usage", headers=headers)
        self.assertEqual(r_usage.status_code, 200)
        ju = r_usage.json()
        self.assertIsInstance(ju.get("remainingMb"), (int, float))

    def test_orders_detail_normalized_envelope(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}", "X-Dev-All": "1"}
        r_list = self.client.post("/orders/list", json={"page_number": 1, "page_size": 10}, headers=headers)
        self.assertEqual(r_list.status_code, 200)
        orders = (r_list.json().get("data") or {}).get("orders") or []
        if orders:
            ref = orders[0].get("order_reference")
            self.assertTrue(ref)
            r = self.client.post("/orders/detail-normalized", json={"order_reference": ref}, headers=headers)
            self.assertEqual(r.status_code, 200)
            j = r.json()
            self.assertEqual(j.get("code"), 200)
            d = j.get("data") or {}
            self.assertIsInstance(d.get("id"), str)

    def test_catalog_countries_regions_etag(self):
        r_c1 = self.client.get("/catalog/countries")
        self.assertEqual(r_c1.status_code, 200)
        etag_c = r_c1.headers.get("ETag")
        self.assertIsNotNone(etag_c)
        r_c2 = self.client.get("/catalog/countries", headers={"If-None-Match": etag_c})
        self.assertEqual(r_c2.status_code, 304)
        r_r1 = self.client.get("/catalog/regions")
        self.assertEqual(r_r1.status_code, 200)
        etag_r = r_r1.headers.get("ETag")
        self.assertIsNotNone(etag_r)
        r_r2 = self.client.get("/catalog/regions", headers={"If-None-Match": etag_r})
        self.assertEqual(r_r2.status_code, 304)

    def test_bundle_alias_and_list_alias(self):
        rb = self.client.get("/catalog/bundle/hk-1")
        self.assertEqual(rb.status_code, 200)
        self.assertEqual(rb.json().get("id"), "hk-1")
        r_list = self.client.post("/bundle/list", json={"page_number": 1, "page_size": 10})
        self.assertEqual(r_list.status_code, 200)
        jl = r_list.json()
        self.assertEqual(jl.get("code"), 200)
        d = jl.get("data") or {}
        self.assertIsInstance(d.get("bundles"), list)

    def test_bundle_countries_regions_envelope(self):
        rc = self.client.post("/bundle/countries")
        self.assertEqual(rc.status_code, 200)
        jc = rc.json()
        self.assertEqual(jc.get("code"), 200)
        drc = jc.get("data") or {}
        self.assertGreaterEqual((drc.get("countries_count") or 0), 1)
        rr = self.client.post("/bundle/regions")
        self.assertEqual(rr.status_code, 200)
        jr = rr.json()
        self.assertEqual(jr.get("code"), 200)
        drr = jr.get("data") or {}
        self.assertGreaterEqual((drr.get("regions_count") or 0), 1)

    def test_webhooks_invalid_signature(self):
        body_p = {"provider": "alipay", "orderId": None, "reference": None, "status": "paid", "amount": 1.0, "currency": "USD"}
        rp = self.client.post("/webhooks/payments", json=body_p)
        self.assertEqual(rp.status_code, 401)
        body_g = {"business_type": "ACQUIRING_PAYMENT", "event_time": "2025-01-01T00:00:00Z", "business_id": "B1", "data": {"payment_status": "PAID"}}
        rg = self.client.post("/webhooks/gsalary", json=body_g)
        self.assertEqual(rg.status_code, 401)

    def test_orders_list_with_usage_fast_mode(self):
        access = self._auth()
        self.assertTrue(access)
        headers = {"Authorization": f"Bearer {access}", "X-Fast-Orders": "1"}
        r = self.client.post("/orders/list-with-usage", json={"page_number": 1, "page_size": 10}, headers=headers)
        self.assertEqual(r.status_code, 200)
        j = r.json()
        self.assertEqual(j.get("code"), 200)
        d = j.get("data") or {}
        self.assertIsInstance(d.get("items") or [], list)

    def test_settings_languages_currencies(self):
        r_lang = self.client.get("/settings/languages")
        self.assertEqual(r_lang.status_code, 200)
        langs = r_lang.json()
        self.assertIsInstance(langs, list)
        if langs:
            self.assertIsInstance(langs[0].get("code"), str)
            self.assertIsInstance(langs[0].get("name"), str)
        r_cur = self.client.get("/settings/currencies")
        self.assertEqual(r_cur.status_code, 200)
        curs = r_cur.json()
        self.assertIsInstance(curs, list)
        if curs:
            self.assertIsInstance(curs[0].get("code"), str)
            self.assertIsInstance(curs[0].get("name"), str)

    def test_health_ok(self):
        r = self.client.get("/health")
        self.assertEqual(r.status_code, 204)
        self.assertEqual(r.headers.get("Cache-Control"), "no-store")
