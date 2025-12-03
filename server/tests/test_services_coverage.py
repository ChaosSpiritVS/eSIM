import unittest
from typing import Any, Dict, List, Optional

from server.app.db import init_db
from server.app.services.catalog_service import CatalogService
from server.app.services.order_service import OrderService
from server.app.db import SessionLocal
from server.app.models.orm import I18nCountryName, I18nRegionName


class TestCatalogServiceCoverage(unittest.TestCase):
    def setUp(self):
        init_db()

    def test_countries_fallback_on_provider_error(self):
        svc = CatalogService()
        def raise_err(*args, **kwargs):
            raise Exception("upstream error")
        svc.provider.get_countries = raise_err  # type: ignore
        db = SessionLocal()
        try:
            if db.query(I18nCountryName).filter(I18nCountryName.lang_code == "en").count() == 0:
                db.add(I18nCountryName(iso2_code="US", iso3_code="USA", lang_code="en", name="United States", logo=None))
                db.commit()
        finally:
            db.close()
        items = svc.get_countries()
        self.assertIsInstance(items, list)

    def test_countries_alias_skip_invalid_and_cache_hit(self):
        svc = CatalogService()
        def fake_countries(*args, **kwargs) -> List[Dict[str, Any]]:
            return [
                {"iso2_code": "US", "iso3_code": None, "country_name": "United States"},
                {"iso2_code": "GB", "iso3_code": "GBR", "country_name": "United Kingdom"},
            ]
        svc.provider.get_countries = fake_countries  # type: ignore
        first = svc.get_countries_alias()
        self.assertEqual(first.countries_count, 1)
        second = svc.get_countries_alias()
        self.assertIs(second, svc._countries_alias_cache)

    def test_regions_fallback_on_provider_error(self):
        svc = CatalogService()
        def raise_err(*args, **kwargs):
            raise Exception("upstream error")
        svc.provider.get_regions = raise_err  # type: ignore
        db = SessionLocal()
        try:
            if db.query(I18nRegionName).filter(I18nRegionName.lang_code == "en").count() == 0:
                db.add(I18nRegionName(region_code="eu", lang_code="en", name="Europe"))
                db.commit()
        finally:
            db.close()
        items = svc.get_regions()
        self.assertIsInstance(items, list)
        self.assertGreater(len(items), 0)


class TestOrderServiceCache(unittest.TestCase):
    def setUp(self):
        init_db()

    def test_cache_get_expired_deletes_key(self):
        svc = OrderService()
        key = "k1"
        svc._cache_put(svc._oid_ref_cache, key, "V", -1)
        val = svc._cache_get(svc._oid_ref_cache, key)
        self.assertIsNone(val)
        self.assertNotIn(key, svc._oid_ref_cache)

    def test_lookup_ref_by_oid_cache_hit(self):
        svc = OrderService()
        oid = "OID123"
        ref = "REF123"
        item = {"order_id": oid, "order_reference": ref}
        svc._cache_put(svc._oid_ref_cache, oid, ref, 60)
        svc._cache_put(svc._oid_item_cache, oid, item, 60)
        r, it = svc._lookup_ref_by_oid(oid)
        self.assertEqual(r, ref)
        self.assertEqual(it.get("order_id"), oid)

    def test_lookup_ref_by_oid_populates_caches(self):
        svc = OrderService()
        oid = "OIDX"
        ref = "REFX"
        def list_orders_v2(*args, **kwargs) -> Dict[str, Any]:
            return {"orders": [{"order_id": oid, "order_reference": ref}], "orders_count": 1}
        svc.provider.list_orders_v2 = list_orders_v2  # type: ignore
        r, it = svc._lookup_ref_by_oid(oid)
        self.assertEqual(r, ref)
        self.assertEqual(it.get("order_reference"), ref)
        self.assertIn(oid, svc._oid_ref_cache)
        self.assertIn(ref, svc._ref_item_cache)
        self.assertIn(oid, svc._oid_item_cache)

    def test_bundle_list_q_filter_and_cache(self):
        svc = CatalogService()
        calls = {"n": 0}
        def fake_list(*args, **kwargs) -> Dict[str, Any]:
            calls["n"] += 1
            return {
                "bundles": [
                    {"bundle_name": "Hong Kong", "bundle_marketing_name": "Hong Kong", "country_code": ["HKG"], "gprs_limit": 1, "data_unit": "GB", "validity": 7, "unlimited": False},
                    {"bundle_name": "Europe 1GB 7d", "bundle_marketing_name": "Europe", "country_code": ["GBR"], "gprs_limit": 1024, "data_unit": "MB", "validity": "7", "unlimited": False, "region_code": "eu", "region_name": "Europe"},
                    {"bundle_name": "Asia", "bundle_marketing_name": "Asia", "country_code": ["JPN"], "gprs_limit": 0, "data_unit": "GB", "validity": "x", "unlimited": True, "region_code": "as", "region_name": "Asia"},
                ],
                "bundles_count": "3",
            }
        svc.provider.get_bundle_list = fake_list  # type: ignore
        r1 = svc.bundle_list(1, 10, q="eu")
        self.assertEqual(len(r1.get("bundles") or []), 1)
        self.assertEqual(r1.get("bundles_count"), 3)
        r2 = svc.bundle_list(1, 10, q="eu")
        self.assertEqual(calls["n"], 1)

    def test_get_bundle_by_code_price_validity_parse(self):
        svc = CatalogService()
        def fake_list(*args, **kwargs) -> Dict[str, Any]:
            return {
                "bundles": [
                    {
                        "bundle_code": "CODEX",
                        "bundle_name": "N",
                        "bundle_marketing_name": "M",
                        "country_code": ["HKG"],
                        "bundle_price_final": "xyz",
                        "currency": "GBP",
                        "gprs_limit": "x",
                        "data_unit": "GB",
                        "validity": "abc",
                        "unlimited": False,
                    }
                ]
            }
        svc.provider.get_bundle_list = fake_list  # type: ignore
        dto = svc.get_bundle_by_code("CODEX")
        self.assertIsNotNone(dto)
        self.assertEqual(dto.price, 0.0)
        self.assertEqual(dto.validityDays, 0)

    def test_bundle_networks_v2_count_parse_and_cache(self):
        svc = CatalogService()
        def fake_nets(bundle_code: str, country_code: Optional[str] = None, request_id: Optional[str] = None) -> Dict[str, Any]:
            if bundle_code == "B1":
                return {
                    "networks": [
                        {"country_code": "CHN", "operator_list": ["CM"]},
                        {"country_code": "HKG", "operator_list": ["CSL"]},
                    ],
                    "networks_count": "bad",
                }
            return {
                "networks": [{"country_code": "CHN", "operator_list": ["CM"]}],
                "networks_count": None,
            }
        svc.provider.get_bundle_networks_v2 = fake_nets  # type: ignore
        r1 = svc.get_bundle_networks_v2(bundle_code="B1")
        self.assertEqual(r1.get("networks_count"), 2)
        r2 = svc.get_bundle_networks_v2(bundle_code="B1")
        self.assertEqual(r2.get("networks_count"), 2)
        r3 = svc.get_bundle_networks_v2(bundle_code="B2")
        self.assertEqual(r3.get("networks_count"), 1)

    def test_bundle_operators_flat(self):
        svc = CatalogService()
        def fake_nets(bundle_code: str, country_code: Optional[str] = None, request_id: Optional[str] = None) -> Dict[str, Any]:
            return {
                "networks": [
                    {"country_code": "HKG", "operator_list": ["CSL"]},
                    {"country_code": "CHN", "operator_list": ["CM"]},
                ],
                "networks_count": 2,
            }
        svc.provider.get_bundle_networks_v2 = fake_nets  # type: ignore
        a = svc.get_bundle_operators_flat(bundle_code="B1", country_code="CHN")
        self.assertEqual(a.get("operators_count"), 1)
        self.assertEqual(a.get("operators")[0], "CM")
        b = svc.get_bundle_operators_flat(bundle_code="B1", country_code=None)
        self.assertEqual(b.get("operators_count"), 2)

    def test_lookup_item_by_ref_cache_hit_and_populate(self):
        svc = OrderService()
        ref = "REFY"
        item = {"order_reference": ref, "order_id": "OIDY"}
        svc._cache_put(svc._ref_item_cache, ref, item, 60)
        it = svc._lookup_item_by_ref(ref)
        self.assertEqual(it.get("order_id"), "OIDY")
        svc2 = OrderService()
        def list_orders_v2(*args, **kwargs) -> Dict[str, Any]:
            return {"orders": [{"order_id": "OIDZ", "order_reference": "REFZ"}], "orders_count": 1}
        svc2.provider.list_orders_v2 = list_orders_v2  # type: ignore
        it2 = svc2._lookup_item_by_ref("REFZ")
        self.assertEqual(it2.get("order_id"), "OIDZ")
        self.assertIn("REFZ", svc2._ref_item_cache)
        self.assertIn("OIDZ", svc2._oid_item_cache)
        self.assertEqual(svc2._cache_get(svc2._oid_ref_cache, "OIDZ"), "REFZ")

    def test_get_usage_by_ref_exception_and_cache(self):
        svc = OrderService()
        ref = "REFU"
        def raise_err(*args, **kwargs):
            raise Exception("upstream")
        svc.provider.get_order_consumption_v2 = raise_err  # type: ignore
        u1 = svc._get_usage_by_ref(ref)
        self.assertIsInstance(u1, dict)
        def ok(*args, **kwargs):
            return {"data_remaining": 1.0}
        svc.provider.get_order_consumption_v2 = ok  # type: ignore
        u2 = svc._get_usage_by_ref(ref)
        self.assertEqual(u2.get("data_remaining"), 1.0)

    def test_get_usage_by_ref_success_and_cache(self):
        svc = OrderService()
        ref = "REFS"
        def ok(*args, **kwargs):
            return {"data_remaining": 2.0, "data_unit": "MB"}
        svc.provider.get_order_consumption_v2 = ok  # type: ignore
        u1 = svc._get_usage_by_ref(ref)
        self.assertEqual(u1.get("data_remaining"), 2.0)
        u2 = svc._get_usage_by_ref(ref)
        self.assertEqual(u2.get("data_remaining"), 2.0)

    def test_refund_order_allowed_and_rejected_no_user(self):
        svc = OrderService()
        oid = "OIDR"
        ref = "REFR"
        def list_v2(*args, **kwargs):
            return {"orders": [{"order_id": oid, "order_reference": ref}], "orders_count": 1}
        svc.provider.list_orders_v2 = list_v2  # type: ignore
        def det_v2(*args, **kwargs):
            return {"order_status": "paid", "bundle_code": "B", "bundle_marketing_name": "M"}
        def cons_v2(*args, **kwargs):
            return {"plan_status": "Plan Not Started", "data_used": 0.0}
        svc.provider.get_order_detail_v2 = det_v2  # type: ignore
        svc.provider.get_order_consumption_v2 = cons_v2  # type: ignore
        r1 = svc.refund_order(order_id=oid, reason="t")
        self.assertTrue(r1.get("accepted"))
        svc2 = OrderService()
        svc2.provider.list_orders_v2 = list_v2  # type: ignore
        def cons_v2_bad(*args, **kwargs):
            return {"plan_status": "Active", "data_used": 0.2}
        svc2.provider.get_order_detail_v2 = det_v2  # type: ignore
        svc2.provider.get_order_consumption_v2 = cons_v2_bad  # type: ignore
        r2 = svc2.refund_order(order_id=oid, reason="t")
        self.assertFalse(r2.get("accepted"))

    def test_list_orders_sort_by_amount(self):
        svc = OrderService()
        db = SessionLocal()
        try:
            from server.app.models.orm import User, Order
            import datetime as _dt, uuid as _uuid
            uid = "U_SORT"
            if not db.query(User).filter(User.id == uid).first():
                u = User(id=uid, name=uid, email=None, password_hash=None, apple_id=None, created_at=_dt.datetime.utcnow(), last_name=None, language=None, currency=None, country=None)
                db.add(u)
                db.commit()
            o1 = Order(id="OID" + _uuid.uuid4().hex[:8], user_id=uid, provider_order_id=None, bundle_id="b1", amount=10.0, currency="GBP", status="paid", created_at=_dt.datetime.utcnow())
            o2 = Order(id="OID" + _uuid.uuid4().hex[:8], user_id=uid, provider_order_id=None, bundle_id="b2", amount=5.0, currency="GBP", status="paid", created_at=_dt.datetime.utcnow())
            db.add_all([o1, o2])
            db.commit()
        finally:
            db.close()
        asc = svc.list_orders(user_id="U_SORT", page=1, page_size=10, sort_by="amount", sort_dir="asc")
        self.assertEqual(asc[0].amount, 5.0)
        dsc = svc.list_orders(user_id="U_SORT", page=1, page_size=10, sort_by="amount", sort_dir="desc")
        self.assertEqual(dsc[0].amount, 10.0)

    def test_assign_bundle_upsert(self):
        svc = OrderService()
        def fake_assign(*args, **kwargs):
            return {"order_id": "OIDZ", "iccid": "8910390000000000000"}
        svc.provider.assign_bundle = fake_assign  # type: ignore
        r1 = svc.assign_bundle(bundle_code="B1", order_reference="REFA", name="U", email="u@example.com", user_id="U2")
        self.assertIsInstance(r1.orderId, str)
        self.assertEqual(svc._order_email_by_ref.get("REFA"), "u@example.com")
        r2 = svc.assign_bundle(bundle_code="B1", order_reference="REFA", name="U", email="u2@example.com", user_id="U2")
        self.assertEqual(svc._order_email_by_ref.get("REFA"), "u2@example.com")

    def test_email_gateway_noop_and_ses(self):
        from server.app.provider.email import EmailGateway, SESGateway
        import os
        os.environ["EMAIL_ENABLED"] = "false"
        g = EmailGateway.from_env()
        self.assertEqual(g.__class__.__name__, "NoopEmailGateway")
        sg = SESGateway(region="us-east-1", sender="test@example.com")
        s1 = sg._subject("zh")
        s2 = sg._subject("en")
        self.assertIn("Simigo", s1)
        self.assertIn("Reset", s2)
        h1 = sg._html("https://x", "zh")
        h2 = sg._html("https://x", "en")
        self.assertIn("重置密码", h1)
        self.assertIn("Reset Password", h2)
        class C:
            def send_email(self, **kwargs):
                raise Exception("x")
        sg._ses = C()
        sg.send_password_reset("to@example.com", "https://x", "en")
        sg.send_email_code("to@example.com", "123456", "zh")

    def test_create_order_validations(self):
        svc = OrderService()
        from server.app.models.dto import CreateOrderBody
        with self.assertRaises(ValueError):
            svc.create_order(CreateOrderBody(bundleId="", paymentMethod="alipay"))
        with self.assertRaises(ValueError):
            svc.create_order(CreateOrderBody(bundleId="b1", paymentMethod=""))
        with self.assertRaises(ValueError):
            svc.create_order(CreateOrderBody(bundleId="b1", paymentMethod="wire"))

    def test_get_order_provider_fallback_and_installation(self):
        svc = OrderService()
        def fake_get_order(order_id: str, request_id: Optional[str] = None):
            from datetime import datetime as _dt
            return {
                "id": "OIDX",
                "bundle_id": "B1",
                "bundle_sale_price": 12.5,
                "currency": "USD",
                "created_at": _dt.utcnow(),
                "status": "paid",
                "payment_method": "alipay",
                "activation_code": "ACT",
                "smdp_address": "SMDP",
                "qr_code_url": "http://x",
                "instructions": ["i1", "i2"],
                "profile_url": "http://p",
            }
        svc.provider.get_order = fake_get_order  # type: ignore
        dto = svc.get_order(order_id="OIDX")
        self.assertIsNotNone(dto)
        self.assertIsNotNone(dto.installation)
        self.assertEqual(dto.installation.activationCode, "ACT")

    def test_apply_payment_webhook_update_by_provider_order_id(self):
        from server.app.models.orm import Order, User
        import datetime as _dt
        db = SessionLocal()
        try:
            import uuid as _uuid
            poid = "P" + _uuid.uuid4().hex[:10]
            oid = "OID" + _uuid.uuid4().hex[:10]
            if not db.query(User).filter(User.id == "U3").first():
                u = User(id="U3", name="U3", email=None, password_hash=None, apple_id=None, created_at=_dt.datetime.utcnow(), last_name=None, language=None, currency=None, country=None)
                db.add(u)
                db.commit()
            o = Order(id=oid, user_id="U3", provider_order_id=poid, bundle_id="b1", amount=1.0, currency="GBP", status="created", created_at=_dt.datetime.utcnow())
            db.add(o)
            db.commit()
        finally:
            db.close()
        svc = OrderService()
        updated = svc.apply_payment_webhook(provider="p", provider_order_id=poid, status="paid", amount=2.0, currency="USD")
        self.assertEqual(updated, 1)

    def test_apply_payment_webhook_update_by_order_reference(self):
        from server.app.models.orm import Order, User
        import datetime as _dt, uuid as _uuid
        db = SessionLocal()
        try:
            uid = "U_REF"
            if not db.query(User).filter(User.id == uid).first():
                u = User(id=uid, name=uid, email=None, password_hash=None, apple_id=None, created_at=_dt.datetime.utcnow(), last_name=None, language=None, currency=None, country=None)
                db.add(u)
                db.commit()
            ref = "REF" + _uuid.uuid4().hex[:10]
            oid = ref + "ZZ"  # make local id start with reference
            o = Order(id=oid, user_id=uid, provider_order_id=None, bundle_id="b1", amount=1.0, currency="GBP", status="created", created_at=_dt.datetime.utcnow())
            db.add(o)
            db.commit()
        finally:
            db.close()
        svc = OrderService()
        updated = svc.apply_payment_webhook(provider="p", order_reference=ref, provider_order_id="PREF", status="paid", amount=3.0, currency="USD")
        self.assertEqual(updated, 1)

    def test_init_mappings_for_user_updates_mapping(self):
        from server.app.models.orm import Order, User, OrderReferenceEmail
        import datetime as _dt, uuid as _uuid
        uid = "U_MAP"
        db = SessionLocal()
        try:
            if not db.query(User).filter(User.id == uid).first():
                u = User(id=uid, name=uid, email=None, password_hash=None, apple_id=None, created_at=_dt.datetime.utcnow(), last_name=None, language=None, currency=None, country=None)
                db.add(u)
                db.commit()
            # local order id (32 hex) and reference prefix 30 chars
            loc_id = _uuid.uuid4().hex
            o = Order(id=loc_id, user_id=uid, provider_order_id=None, bundle_id="b1", amount=2.0, currency="GBP", status="paid", created_at=_dt.datetime.utcnow())
            db.add(o)
            db.commit()
            ref = loc_id[:30]
            if not db.query(OrderReferenceEmail).filter(OrderReferenceEmail.order_reference == ref).first():
                db.add(OrderReferenceEmail(order_reference=ref, user_id=uid, email=""))
                db.commit()
        finally:
            db.close()
        svc = OrderService()
        def det_v2(*args, **kwargs):
            return {}
        svc.provider.get_order_detail_v2 = det_v2  # type: ignore
        out = svc.init_mappings_for_user(user_id=uid)
        self.assertGreaterEqual(out.get("checked"), 1)

    def test_get_usage_with_orders_consumption_by_id_v2(self):
        svc = OrderService()
        oid = "OIDU"
        ref = "REFU_X"
        def list_v2(*args, **kwargs):
            return {"orders": [{"order_id": oid, "order_reference": ref}], "orders_count": 1}
        svc.provider.list_orders_v2 = list_v2  # type: ignore
        def usage_ref(*args, **kwargs):
            from datetime import datetime as _dt, timedelta as _td
            exp = (_dt.utcnow() + _td(days=1)).strftime("%Y-%m-%d %H:%M:%S.%f")
            return {"data_remaining": 5.0, "bundle_expiry_date": exp}
        svc.provider.get_order_consumption_v2 = usage_ref  # type: ignore
        u = svc.get_usage(order_id=oid)
        self.assertIsNotNone(u)
        self.assertEqual(u.remainingMb, 5.0)

    def test_orders_list_normalized_dev_all_true(self):
        svc = OrderService()
        def list_orders_v2(*args, **kwargs) -> Dict[str, Any]:
            return {"orders": [
                {"order_id": "OIDN2", "order_reference": "REFN2", "created_at": "2024-11-01 10:20:30", "order_status": "fail", "bundle_code": "BN2", "currency_code": "USD", "reseller_retail_price": "2.0"}
            ], "orders_count": 1}
        svc.provider.list_orders_v2 = list_orders_v2  # type: ignore
        from server.app.models.dto import OrdersListNormalizedQuery
        out = svc.orders_list_normalized(OrdersListNormalizedQuery(page_number=1, page_size=10), dev_all=True)
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0].status, "failed")

    def test_orders_list_with_usage_limit_override(self):
        svc = OrderService()
        def list_orders_v2(*args, **kwargs) -> Dict[str, Any]:
            return {"orders": [
                {"order_id": "OIDA1", "order_reference": "REFA1", "created_at": "2024-11-01 10:20:30", "order_status": "paid", "bundle_code": "BN1", "currency_code": "USD", "reseller_retail_price": "2.0"},
                {"order_id": "OIDA2", "order_reference": "REFA2", "created_at": "2024-11-01 10:20:30", "order_status": "paid", "bundle_code": "BN2", "currency_code": "USD", "reseller_retail_price": "3.0"},
            ], "orders_count": 2}
        svc.provider.list_orders_v2 = list_orders_v2  # type: ignore
        def batch(*args, **kwargs):
            return {"items": [{"order_reference": "REFA1", "usage": {"data_remaining": 1.0}}]}
        svc.orders_consumption_batch = batch  # type: ignore
        from server.app.models.dto import OrdersListWithUsageQuery
        out = svc.orders_list_with_usage(OrdersListWithUsageQuery(page_number=1, page_size=10), max_usage=1)
        self.assertEqual(out.get("orders_count"), 2)

    def test_orders_detail_normalized_value_error_and_success(self):
        svc = OrderService()
        from server.app.models.dto import OrdersDetailNormalizedQuery
        with self.assertRaises(ValueError):
            svc.orders_detail_normalized(OrdersDetailNormalizedQuery(order_reference=""))
        def list_orders_v2(*args, **kwargs) -> Dict[str, Any]:
            return {"orders": [{"order_id": "OIDN", "order_reference": "REFN", "reseller_retail_price": 3.5, "currency_code": "EUR"}], "orders_count": 1}
        def det_v2(*args, **kwargs):
            return {"order_id": "OIDN", "date_created": "2024-11-01T10:20:30", "order_status": "paid", "bundle_code": "BN"}
        svc.provider.list_orders_v2 = list_orders_v2  # type: ignore
        svc.provider.get_order_detail_v2 = det_v2  # type: ignore
        dto = svc.orders_detail_normalized(OrdersDetailNormalizedQuery(order_id="OIDN"))
        self.assertEqual(dto.currency, "EUR")
        self.assertEqual(dto.amount, 3.5)

    def test_orders_list_v2_filters_by_user_id_and_email(self):
        svc = OrderService()
        def list_orders_v2(*args, **kwargs) -> Dict[str, Any]:
            return {"orders": [
                {"order_id": "OIDX", "order_reference": "REFX", "client_email": "a@example.com", "order_status": "paid", "bundle_code": "b"},
                {"order_id": "OIDY", "order_reference": "REFY", "client_email": "b@example.com", "order_status": "paid", "bundle_code": "b"},
            ], "orders_count": 2}
        svc.provider.list_orders_v2 = list_orders_v2  # type: ignore
        from server.app.models.orm import OrderReferenceEmail
        db = SessionLocal()
        try:
            from server.app.models.orm import OrderReferenceEmail
            if not db.query(OrderReferenceEmail).filter(OrderReferenceEmail.order_reference == "REFX").first():
                r1 = OrderReferenceEmail(order_reference="REFX", user_id="U5", email="a@example.com")
                db.add(r1)
                db.commit()
        finally:
            db.close()
        svc._order_email_by_ref["REFY"] = "b@example.com"
        from server.app.models.dto import OrdersListQuery
        res_uid = svc.orders_list_v2(OrdersListQuery(page_number=1, page_size=10), user_id="U5")
        self.assertEqual(res_uid.get("orders_count"), 1)
        res_mail = svc.orders_list_v2(OrdersListQuery(page_number=1, page_size=10), user_email="b@example.com")
        self.assertEqual(res_mail.get("orders_count"), 1)

    def test_orders_list_with_usage_dev_fallback(self):
        svc = OrderService()
        from server.app.models.orm import Order, User
        import datetime as _dt
        db = SessionLocal()
        try:
            uid = "U_DEV"
            if not db.query(User).filter(User.id == uid).first():
                u = User(id=uid, name=uid, email=None, password_hash=None, apple_id=None, created_at=_dt.datetime.utcnow(), last_name=None, language=None, currency=None, country=None)
                db.add(u)
                db.commit()
            db.query(Order).filter(Order.user_id == uid).delete(synchronize_session=False)
            db.commit()
            import uuid as _uuid
            oid = "OID" + _uuid.uuid4().hex[:10]
            o = Order(id=oid, user_id=uid, provider_order_id=None, bundle_id="b1", amount=4.0, currency="GBP", status="paid", created_at=_dt.datetime.utcnow())
            db.add(o)
            db.commit()
        finally:
            db.close()
        def list_orders_v2(*args, **kwargs) -> Dict[str, Any]:
            return {"orders": [], "orders_count": 0}
        svc.provider.list_orders_v2 = list_orders_v2  # type: ignore
        from server.app.models.dto import OrdersListWithUsageQuery
        out = svc.orders_list_with_usage(OrdersListWithUsageQuery(page_number=1, page_size=10), user_id="U_DEV")
        self.assertEqual(out.get("orders_count"), 1)

    def test_orders_consumption_batch_basic(self):
        svc = OrderService()
        import os
        os.environ["ORDERS_USAGE_CONCURRENCY"] = "2"
        refs = ["AR1", "AR2"]
        def get_usage(ref: str, request_id: Optional[str] = None) -> dict:
            return {"data_remaining": 1.0, "ref": ref}
        svc._get_usage_by_ref = get_usage  # type: ignore
        from server.app.models.dto import OrdersConsumptionBatchQuery
        out = svc.orders_consumption_batch(OrdersConsumptionBatchQuery(order_references=refs))
        self.assertEqual(len(out.get("items") or []), 2)
