from __future__ import annotations
from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy.orm import Session

from ..db import SessionLocal
from ..models.dto import (
    OrderDTO,
    InstallationDTO,
    CreateOrderBody,
    UsageDTO,
    BundleAssignResultDTO,
    OrdersListQuery,
    OrdersDetailQuery,
    OrdersConsumptionQuery,
    OrdersConsumptionByIdQuery,
    OrdersDetailNormalizedQuery,
    OrdersConsumptionBatchQuery,
    OrdersListNormalizedQuery,
    OrdersListWithUsageQuery,
)
from ..models.orm import Order, OrderReferenceEmail, RefundRequest
from ..provider.client import ProviderClient


class OrderService:
    def __init__(self):
        self.provider = ProviderClient()
        # simple in-memory cache for upstream reflection
        self._orders: dict[str, OrderDTO] = {}
        self._order_email_by_ref: dict[str, str] = {}
        self._oid_ref_cache: dict[str, tuple[str, float]] = {}
        self._ref_item_cache: dict[str, tuple[dict, float]] = {}
        self._oid_item_cache: dict[str, tuple[dict, float]] = {}
        self._ref_usage_cache: dict[str, tuple[dict, float]] = {}
        self._ref_detail_cache: dict[str, tuple[dict, float]] = {}

    def _get_db(self) -> Session:
        return SessionLocal()

    def _cache_get(self, cache: dict, key: str):
        import time
        v = cache.get(key)
        if not v:
            return None
        val, exp = v
        if exp < time.time():
            try:
                del cache[key]
            except Exception:
                pass
            return None
        return val

    def _cache_put(self, cache: dict, key: str, val, ttl: float):
        import time
        cache[key] = (val, time.time() + ttl)

    def _lookup_ref_by_oid(self, oid: str, request_id: Optional[str] = None) -> tuple[str, dict]:
        ref = self._cache_get(self._oid_ref_cache, oid)
        item = self._cache_get(self._oid_item_cache, oid)
        if ref and item:
            return ref, item
        listing = self.provider.list_orders_v2(page_number=1, page_size=10, filters={"order_id": oid}, request_id=request_id)
        orders = listing.get("orders", [])
        if orders:
            o = orders[0]
            ref = str(o.get("order_reference") or "")
            if ref:
                self._cache_put(self._oid_ref_cache, oid, ref, 300)
                self._cache_put(self._ref_item_cache, ref, o, 120)
            self._cache_put(self._oid_item_cache, oid, o, 120)
            return ref, o
        return "", {}

    def _lookup_item_by_ref(self, ref: str, request_id: Optional[str] = None) -> dict:
        item = self._cache_get(self._ref_item_cache, ref)
        if item:
            return item
        listing = self.provider.list_orders_v2(page_number=1, page_size=10, filters={"order_reference": ref}, request_id=request_id)
        orders = listing.get("orders", [])
        if orders:
            o = orders[0]
            self._cache_put(self._ref_item_cache, ref, o, 120)
            oid = str(o.get("order_id") or "")
            if oid:
                self._cache_put(self._oid_item_cache, oid, o, 120)
                self._cache_put(self._oid_ref_cache, oid, ref, 300)
            return o
        return {}

    def _get_usage_by_ref(self, ref: str, request_id: Optional[str] = None) -> dict:
        cached = self._cache_get(self._ref_usage_cache, ref)
        if cached:
            return cached
        try:
            usage = self.provider.get_order_consumption_v2(order_reference=ref, request_id=request_id)
        except Exception:
            usage = {}
        self._cache_put(self._ref_usage_cache, ref, usage, 60)
        return usage

    def _get_detail_by_ref(self, ref: str, request_id: Optional[str] = None) -> dict:
        cached = self._cache_get(self._ref_detail_cache, ref)
        if cached:
            return cached
        detail = self.provider.get_order_detail_v2(order_reference=ref, request_id=request_id)
        self._cache_put(self._ref_detail_cache, ref, detail or {}, 120)
        return detail or {}

    def create_order(self, body: CreateOrderBody, user_id: str | None = None) -> OrderDTO:
        if not body.bundleId:
            raise ValueError("bundleId is required")
        if not body.paymentMethod:
            raise ValueError("paymentMethod is required")
        allowed = {"alipay", "card", "applepay", "paypal"}
        if str(body.paymentMethod).strip().lower() not in allowed:
            raise ValueError("unsupported payment method")

        now = datetime.utcnow()
        new_id = self.provider.generate_order_id()
        installation = None
        # For paid methods, assume immediate payment success in demo and return 'paid'
        status = "created"

        dto = OrderDTO(
            id=new_id,
            bundleId=body.bundleId,
            amount=self.provider.estimate_bundle_price(body.bundleId),
            currency="GBP",
            createdAt=now,
            status=status,
            paymentMethod=body.paymentMethod,
            installation=installation,
        )
        self._orders[new_id] = dto
        # Persist locally with user association
        db = self._get_db()
        try:
            rec = Order(
                id=new_id,
                user_id=user_id,
                provider_order_id=None,
                bundle_id=body.bundleId,
                amount=dto.amount,
                currency=dto.currency,
                status=dto.status,
                created_at=now,
            )
            db.add(rec)
            db.commit()
        finally:
            db.close()
        return dto

    def list_orders(
        self,
        user_id: str,
        page: int = 1,
        page_size: int = 20,
        sort_by: str | None = None,
        sort_dir: str | None = None,
    ) -> list[OrderDTO]:
        # Return locally persisted orders for the current user
        db = self._get_db()
        try:
            q = db.query(Order).filter(Order.user_id == user_id).order_by(Order.created_at.desc())
            # Simple pagination
            q = q.offset((page - 1) * page_size).limit(page_size)
            rows = list(q)
            results: list[OrderDTO] = [
                OrderDTO(
                    id=row.id,
                    bundleId=row.bundle_id,
                    amount=float(row.amount),
                    currency=row.currency,
                    createdAt=row.created_at,
                    status=row.status,
                    paymentMethod="agent",  # local orders default
                    installation=None,
                )
                for row in rows
            ]
            if sort_by:
                reverse = (sort_dir or "desc").lower() == "desc"
                if sort_by == "createdAt":
                    results.sort(key=lambda r: r.createdAt, reverse=reverse)
                elif sort_by == "amount":
                    results.sort(key=lambda r: r.amount, reverse=reverse)
                elif sort_by == "status":
                    results.sort(key=lambda r: r.status, reverse=reverse)
            return results
        finally:
            db.close()

    def get_order(self, order_id: str, user_id: str | None = None, request_id: str | None = None) -> Optional[OrderDTO]:
        # Try local first
        if order_id in self._orders:
            return self._orders[order_id]
        db = self._get_db()
        try:
            if user_id:
                row = db.query(Order).filter(Order.id == order_id, Order.user_id == user_id).first()
                if row:
                    dto = OrderDTO(
                        id=row.id,
                        bundleId=row.bundle_id,
                        amount=float(row.amount),
                        currency=row.currency,
                        createdAt=row.created_at,
                        status=row.status,
                        paymentMethod="agent",
                        installation=None,
                    )
                    self._orders[dto.id] = dto
                    return dto
        finally:
            db.close()
        # Fallback to provider for demo
        provider_order = self.provider.get_order(order_id, request_id=request_id)
        if provider_order:
            dto = OrderDTO(
                id=provider_order["id"],
                bundleId=provider_order["bundle_id"],
                amount=float(provider_order["bundle_sale_price"]),
                currency=provider_order.get("currency", "GBP"),
                createdAt=provider_order["created_at"],
                status=provider_order.get("status", "paid"),
                paymentMethod=provider_order.get("payment_method", "paypal"),
                installation=self._map_installation(provider_order),
            )
            self._orders[dto.id] = dto
            return dto
        return None

    def apply_payment_webhook(
        self,
        provider: str,
        provider_order_id: Optional[str] = None,
        order_reference: Optional[str] = None,
        status: str = "paid",
        amount: Optional[float] = None,
        currency: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> int:
        updated = 0
        db = self._get_db()
        try:
            if provider_order_id:
                rec = db.query(Order).filter(Order.provider_order_id == provider_order_id).first()
                if rec:
                    if status and rec.status != status:
                        rec.status = status
                    if amount is not None:
                        rec.amount = amount
                    if currency is not None:
                        rec.currency = currency
                    db.add(rec)
                    db.commit()
                    updated = 1
                    self._orders[rec.id] = OrderDTO(
                        id=rec.id,
                        bundleId=rec.bundle_id,
                        amount=float(rec.amount),
                        currency=rec.currency,
                        createdAt=rec.created_at,
                        status=rec.status,
                        paymentMethod="agent",
                        installation=None,
                    )
                    return updated

            if order_reference:
                rows = db.query(Order).all()
                for r in rows:
                    if r.id.startswith(order_reference):
                        if provider_order_id and (not r.provider_order_id):
                            r.provider_order_id = provider_order_id
                        if status and r.status != status:
                            r.status = status
                        if amount is not None:
                            r.amount = amount
                        if currency is not None:
                            r.currency = currency
                        db.add(r)
                        db.commit()
                        updated = 1
                        try:
                            rec = db.query(OrderReferenceEmail).filter(OrderReferenceEmail.order_reference == order_reference).first()
                            if rec:
                                rec.provider_order_id = provider_order_id or rec.provider_order_id
                                rec.updated_at = datetime.utcnow()
                                db.add(rec)
                                db.commit()
                        except Exception:
                            pass
                        self._orders[r.id] = OrderDTO(
                            id=r.id,
                            bundleId=r.bundle_id,
                            amount=float(r.amount),
                            currency=r.currency,
                            createdAt=r.created_at,
                            status=r.status,
                            paymentMethod="agent",
                            installation=None,
                        )
                        break
        finally:
            db.close()
        return updated

    def get_usage(self, order_id: str, request_id: str | None = None) -> Optional[UsageDTO]:
        # Prefer consumption via order_reference for real upstream compatibility
        data = self.orders_consumption_by_id_v2(OrdersConsumptionByIdQuery(order_id=order_id), request_id=request_id)
        order = data.get("order") if isinstance(data, dict) else {}
        if order:
            try:
                rem = float(order.get("data_remaining", 0.0))
            except Exception:
                rem = 0.0
            from datetime import datetime as _dt
            exp_raw = order.get("bundle_expiry_date")
            exp_dt = None
            if isinstance(exp_raw, str) and exp_raw.strip():
                s = exp_raw.strip().replace("T", " ")
                for fmt in ("%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S"):
                    try:
                        exp_dt = _dt.strptime(s, fmt)
                        break
                    except Exception:
                        continue
            return UsageDTO(
                remainingMb=rem,
                expiresAt=exp_dt,
                lastUpdated=None,
            )
        usage = self.provider.get_usage(order_id, request_id=request_id)
        if not usage:
            return None
        return UsageDTO(
            remainingMb=float(usage.get("data_remaining", 0.0)),
            expiresAt=usage.get("expires_at"),
            lastUpdated=usage.get("last_updated"),
        )

    def refund_order(self, order_id: str, reason: Optional[str] = None, user_id: Optional[str] = None, request_id: Optional[str] = None) -> dict:
        now = datetime.utcnow()
        ref, _item = self._lookup_ref_by_oid(order_id, request_id=request_id)
        detail = {}
        usage = {}
        if ref:
            detail = self._get_detail_by_ref(ref, request_id=request_id)
            usage = self._get_usage_by_ref(ref, request_id=request_id)
        else:
            try:
                detail = self.provider.get_order(order_id, request_id=request_id) or {}
            except Exception:
                detail = {}
            try:
                listing = self.provider.list_orders_v2(page_number=1, page_size=10, filters={"order_id": order_id}, request_id=request_id)
                orders = listing.get("orders", [])
                r = None
                for o in orders:
                    r = str(o.get("order_reference") or "")
                    if r:
                        break
                if r:
                    usage = self._get_usage_by_ref(r, request_id=request_id)
            except Exception:
                usage = {}
        raw_status = str(detail.get("order_status") or detail.get("plan_status") or "").lower()
        paid = ("paid" in raw_status) or ("success" in raw_status) or ("active" in raw_status)
        plan_status = str(usage.get("plan_status") or detail.get("plan_status") or "")
        not_started = ("not started" in plan_status.lower())
        try:
            used = float(usage.get("data_used", 0.0))
        except Exception:
            used = 0.0
        allowed = paid and not_started and (used <= 0.0001)
        if user_id:
            db = self._get_db()
            try:
                existing = db.query(RefundRequest).filter(RefundRequest.order_id == order_id, RefundRequest.user_id == user_id).first()
                if existing:
                    try:
                        import json as _json
                        steps = _json.loads(existing.steps_json) if existing.steps_json else []
                    except Exception:
                        steps = []
                    return {"accepted": existing.state != "rejected", "state": existing.state, "steps": steps}
                import json as _json
                if allowed:
                    steps = [
                        {"state": "requested", "updatedAt": now, "note": (reason or "")},
                        {"state": "reviewing", "updatedAt": now + timedelta(seconds=1), "note": None},
                    ]
                    state = "reviewing"
                else:
                    steps = [
                        {"state": "requested", "updatedAt": now, "note": (reason or "")},
                        {"state": "rejected", "updatedAt": now + timedelta(seconds=1), "note": None},
                    ]
                    state = "rejected"
                rec = RefundRequest(
                    order_id=order_id,
                    user_id=user_id,
                    reason=(reason or None),
                    state=state,
                    steps_json=_json.dumps([
                        {"state": steps[0]["state"], "updatedAt": (steps[0]["updatedAt"].isoformat() if hasattr(steps[0]["updatedAt"], "isoformat") else str(steps[0]["updatedAt"])), "note": steps[0]["note"]},
                        {"state": steps[1]["state"], "updatedAt": (steps[1]["updatedAt"].isoformat() if hasattr(steps[1]["updatedAt"], "isoformat") else str(steps[1]["updatedAt"])), "note": steps[1]["note"]},
                    ]),
                    updated_at=now,
                )
                db.add(rec)
                db.commit()
            finally:
                db.close()
        else:
            if allowed:
                steps = [
                    {"state": "requested", "updatedAt": now, "note": (reason or "")},
                    {"state": "reviewing", "updatedAt": now + timedelta(seconds=1), "note": None},
                ]
                return {"accepted": True, "state": "reviewing", "steps": steps}
            steps = [
                {"state": "requested", "updatedAt": now, "note": (reason or "")},
                {"state": "rejected", "updatedAt": now + timedelta(seconds=1), "note": None},
            ]
            return {"accepted": False, "state": "rejected", "steps": steps}
        try:
            import json as _json
            return {"accepted": state != "rejected", "state": state, "steps": _json.loads(rec.steps_json)}
        except Exception:
            return {"accepted": state != "rejected", "state": state, "steps": steps}

    def assign_bundle(
        self,
        bundle_code: str,
        order_reference: str,
        name: Optional[str] = None,
        email: Optional[str] = None,
        request_id: Optional[str] = None,
        user_id: Optional[str] = None,
    ) -> BundleAssignResultDTO:
        data = self.provider.assign_bundle(
            bundle_code=bundle_code,
            order_reference=order_reference,
            name=name,
            email=email,
            request_id=request_id,
        )
        # Persist mapping into memory and DB for durability and stable association
        self._order_email_by_ref[order_reference] = (email or "").strip().lower()
        provider_order_id = str(data.get("order_id")) if data.get("order_id") is not None else None
        db = self._get_db()
        try:
            # Upsert-like behavior: update if exists, else insert
            rec = db.query(OrderReferenceEmail).filter(OrderReferenceEmail.order_reference == order_reference).first()
            if rec:
                rec.email = (email or "").strip().lower()
                rec.user_id = (user_id or rec.user_id)
                rec.provider_order_id = provider_order_id or rec.provider_order_id
                rec.request_id = request_id
                rec.assigned_at = datetime.utcnow()
                rec.updated_at = datetime.utcnow()
            else:
                rec = OrderReferenceEmail(
                    order_reference=order_reference,
                    email=(email or "").strip().lower(),
                    user_id=(user_id or ""),
                    provider_order_id=provider_order_id,
                    request_id=request_id,
                    assigned_at=datetime.utcnow(),
                    updated_at=datetime.utcnow(),
                )
                db.add(rec)
            db.commit()
        finally:
            db.close()
        # Optionally cache minimal order info
        oid = str(data.get("order_id"))
        if oid:
            self._orders[oid] = OrderDTO(
                id=oid,
                bundleId=bundle_code,
                amount=self.provider.estimate_bundle_price(bundle_code),
                currency="GBP",
                createdAt=datetime.utcnow(),
                status="paid",
                paymentMethod="agent",
                installation=None,
            )
            # Backfill local order's provider_order_id using order_reference prefix match
            if user_id:
                db2 = self._get_db()
                try:
                    # local order id is a 32-hex; order_reference is first 30 chars
                    q = db2.query(Order).filter(Order.user_id == user_id)
                    rows = q.all()
                    for r in rows:
                        loc_id = (r.id or "")
                        ref30 = loc_id[:30]
                        if ref30 == order_reference:
                            r.provider_order_id = oid
                            r.status = "paid"
                            db2.add(r)
                            db2.commit()
                            break
                finally:
                    db2.close()
        return BundleAssignResultDTO(orderId=oid, iccid=str(data.get("iccid")))

    def init_mappings_for_user(self, user_id: str, request_id: Optional[str] = None) -> dict:
        db = self._get_db()
        updated = 0
        checked = 0
        try:
            rows = db.query(Order).filter(Order.user_id == user_id).all()
            for r in rows:
                checked += 1
                loc_id = (r.id or "")
                ref = loc_id[:30]
                try:
                    detail = self.provider.get_order_detail_v2(order_reference=ref, request_id=request_id)
                except Exception:
                    continue
                oid = detail.get("order_id")
                if not oid:
                    continue
                oid = str(oid)
                # upsert mapping
                rec = db.query(OrderReferenceEmail).filter(OrderReferenceEmail.order_reference == ref).first()
                if rec:
                    rec.provider_order_id = oid
                    rec.user_id = user_id
                    rec.updated_at = datetime.utcnow()
                else:
                    rec = OrderReferenceEmail(order_reference=ref, provider_order_id=oid, user_id=user_id, email=None, updated_at=datetime.utcnow())
                    db.add(rec)
                # backfill local order
                r.provider_order_id = oid
                db.add(r)
                db.commit()
                updated += 1
        finally:
            db.close()
        return {"checked": checked, "updated": updated}

    def orders_list_v2(self, body: OrdersListQuery, request_id: Optional[str] = None, user_email: Optional[str] = None, user_id: Optional[str] = None, dev_all: Optional[bool] = None) -> dict:
        """Compat upstream '/orders/list': returns {orders, orders_count}.

        Accepts OrdersListQuery body and forwards filters to provider, along with Request-Id.
        """
        data = self.provider.list_orders_v2(
            page_number=body.page_number,
            page_size=body.page_size,
            filters={
                "bundle_code": body.bundle_code,
                "order_id": body.order_id,
                "order_reference": body.order_reference,
                "start_date": body.start_date,
                "end_date": body.end_date,
                "iccid": body.iccid,
            },
            request_id=request_id,
        )
        orders = data.get("orders", [])
        ue = (user_email or "").strip().lower()
        uid = (user_id or "").strip()
        if (uid or ue) and not bool(dev_all):
            def _lower(s: Optional[str]) -> str:
                return (s or "").strip().lower()
            # Load mappings for current batch
            refs = [str(o.get("order_reference")) for o in orders if o.get("order_reference")]
            oids = [str(o.get("order_id")) for o in orders if o.get("order_id")]
            uid_by_ref: dict[str, str] = {}
            uid_by_oid: dict[str, str] = {}
            email_by_ref: dict[str, str] = {}
            db = self._get_db()
            try:
                if refs:
                    rows = db.query(OrderReferenceEmail).filter(OrderReferenceEmail.order_reference.in_(refs)).all()
                    for r in rows:
                        uid_by_ref[r.order_reference] = (r.user_id or "").strip()
                        email_by_ref[r.order_reference] = (r.email or "").strip().lower()
                if oids:
                    rows2 = db.query(OrderReferenceEmail).filter(OrderReferenceEmail.provider_order_id.in_(oids)).all()
                    for r in rows2:
                        uid_by_oid[r.provider_order_id or ""] = (r.user_id or "").strip()
            finally:
                db.close()
            orders = [
                o for o in orders
                if (
                    (uid and (uid_by_ref.get(str(o.get("order_reference"))) == uid or uid_by_oid.get(str(o.get("order_id"))) == uid))
                    or (ue and (_lower(o.get("client_email")) == ue or _lower(self._order_email_by_ref.get(str(o.get("order_reference")))) == ue or _lower(email_by_ref.get(str(o.get("order_reference")))) == ue))
                )
            ]
        return {"orders": orders, "orders_count": len(orders)}

    def orders_detail_v2(self, body: OrdersDetailQuery, request_id: Optional[str] = None) -> dict:
        """Compat upstream '/orders/detail': returns order detail data dict.

        Accepts OrdersDetailQuery body and forwards order_reference to provider with Request-Id.
        """
        data = self._get_detail_by_ref(body.order_reference, request_id=request_id)
        return data

    def orders_detail_by_id_v2(self, order_id: str, request_id: Optional[str] = None) -> dict:
        """Bridge detail by order_id: find order_reference then fetch detail."""
        listing = self.provider.list_orders_v2(
            page_number=1,
            page_size=10,
            filters={
                "order_id": order_id,
            },
            request_id=request_id,
        )
        orders = listing.get("orders", [])
        ref = None
        for o in orders:
            r = str(o.get("order_reference") or "")
            if r:
                ref = r
                break
        if not ref:
            return {}
        return self._get_detail_by_ref(ref, request_id=request_id)

    def orders_consumption_v2(self, body: OrdersConsumptionQuery, request_id: Optional[str] = None) -> dict:
        """Compat upstream '/orders/consumption': returns {order: {...}}.

        Accepts OrdersConsumptionQuery body and forwards order_reference to provider with Request-Id.
        """
        order = self.provider.get_order_consumption_v2(order_reference=body.order_reference, request_id=request_id)
        return {"order": order}

    def orders_consumption_by_id_v2(self, body: OrdersConsumptionByIdQuery, request_id: Optional[str] = None) -> dict:
        ref, _item = self._lookup_ref_by_oid(body.order_id, request_id=request_id)
        if not ref:
            return {"order": {}}
        order = self._get_usage_by_ref(ref, request_id=request_id)
        return {"order": order}

    def orders_detail_normalized(self, body: OrdersDetailNormalizedQuery, request_id: Optional[str] = None) -> OrderDTO:
        ref = (body.order_reference or "").strip()
        oid = (body.order_id or "").strip()
        detail: dict = {}
        list_item: dict = {}
        if ref:
            list_item = self._lookup_item_by_ref(ref, request_id=request_id)
            detail = self._get_detail_by_ref(ref, request_id=request_id)
        elif oid:
            bridged_ref, item = self._lookup_ref_by_oid(oid, request_id=request_id)
            ref = bridged_ref
            list_item = item
            if ref:
                detail = self._get_detail_by_ref(ref, request_id=request_id)
        if not detail:
            raise ValueError("order_not_found")
        def _parse_dt(v: Optional[str]) -> datetime:
            if v is None:
                return datetime.utcnow()
            s = str(v).strip()
            try:
                from datetime import datetime as _dt
                return _dt.fromisoformat(s.replace("Z", "+00:00"))
            except Exception:
                try:
                    return datetime.utcfromtimestamp(int(float(s)))
                except Exception:
                    return datetime.utcnow()
        created_at = _parse_dt(detail.get("date_created"))
        raw_status = str(detail.get("order_status") or detail.get("plan_status") or "").lower()
        if any(k in raw_status for k in ("paid", "success", "active")):
            status = "paid"
        elif "fail" in raw_status:
            status = "failed"
        else:
            status = "created"
        cur = "USD"
        price = 0.0
        if list_item:
            cur = str(list_item.get("currency_code") or cur)
            try:
                price = float(list_item.get("reseller_retail_price", list_item.get("bundle_sale_price", 0.0)) or 0.0)
            except Exception:
                price = 0.0
        install = self._map_installation({
            "activation_code": detail.get("activation_code"),
            "smdp_address": detail.get("smdp_address"),
            "qr_code_url": detail.get("qr_code_url"),
            "instructions": detail.get("instructions"),
            "profile_url": detail.get("profile_url"),
        })
        return OrderDTO(
            id=str(detail.get("order_id") or oid or ref),
            bundleId=str(detail.get("bundle_code") or ""),
            amount=price,
            currency=cur,
            createdAt=created_at,
            status=status,
            paymentMethod="alipay",
            installation=install,
        )

    def orders_consumption_batch(self, body: OrdersConsumptionBatchQuery, request_id: Optional[str] = None) -> dict:
        refs = list(set([str(r).strip() for r in (body.order_references or []) if str(r).strip()]))
        ids = list(set([str(i).strip() for i in (body.order_ids or []) if str(i).strip()]))
        if ids and not refs:
            for oid in ids:
                listing = self.provider.list_orders_v2(page_number=1, page_size=10, filters={"order_id": oid}, request_id=request_id)
                orders = listing.get("orders", [])
                for o in orders:
                    r = str(o.get("order_reference") or "")
                    if r:
                        refs.append(r)
                        break
        items: list[dict] = []
        if not refs:
            return {"items": items}
        try:
            import concurrent.futures as _f, os as _os
            try:
                _c = int(_os.getenv("ORDERS_USAGE_CONCURRENCY", "5"))
            except Exception:
                _c = 5
            workers = min(max(1, _c), max(1, len(refs)))
            with _f.ThreadPoolExecutor(max_workers=workers) as ex:
                futs = {ex.submit(self._get_usage_by_ref, r, request_id): r for r in refs}
                for fut, r in list(futs.items()):
                    try:
                        usage = fut.result()
                    except Exception:
                        usage = {}
                    items.append({"order_reference": r, "usage": usage})
        except Exception:
            for r in refs:
                usage = self._get_usage_by_ref(r, request_id=request_id)
                items.append({"order_reference": r, "usage": usage})
        return {"items": items}

    def orders_list_normalized(self, body: OrdersListNormalizedQuery, request_id: Optional[str] = None, user_email: Optional[str] = None, user_id: Optional[str] = None, dev_all: Optional[bool] = None) -> list[OrderDTO]:
        data = self.provider.list_orders_v2(
            page_number=body.page_number,
            page_size=body.page_size,
            filters={
                "bundle_code": body.bundle_code,
                "order_id": body.order_id,
                "order_reference": body.order_reference,
                "start_date": body.start_date,
                "end_date": body.end_date,
                "iccid": body.iccid,
            },
            request_id=request_id,
        )
        orders = data.get("orders", [])
        ue = (user_email or "").strip().lower()
        uid = (user_id or "").strip()
        if (uid or ue) and not bool(dev_all):
            def _lower(s: Optional[str]) -> str:
                return (s or "").strip().lower()
            refs = [str(o.get("order_reference")) for o in orders if o.get("order_reference")]
            oids = [str(o.get("order_id")) for o in orders if o.get("order_id")]
            uid_by_ref: dict[str, str] = {}
            uid_by_oid: dict[str, str] = {}
            email_by_ref: dict[str, str] = {}
            db = self._get_db()
            try:
                if refs:
                    rows = db.query(OrderReferenceEmail).filter(OrderReferenceEmail.order_reference.in_(refs)).all()
                    for r in rows:
                        uid_by_ref[r.order_reference] = (r.user_id or "").strip()
                        email_by_ref[r.order_reference] = (r.email or "").strip().lower()
                if oids:
                    rows2 = db.query(OrderReferenceEmail).filter(OrderReferenceEmail.provider_order_id.in_(oids)).all()
                    for r in rows2:
                        uid_by_oid[r.provider_order_id or ""] = (r.user_id or "").strip()
            finally:
                db.close()
            orders = [
                o for o in orders
                if (
                    (uid and (uid_by_ref.get(str(o.get("order_reference"))) == uid or uid_by_oid.get(str(o.get("order_id"))) == uid))
                    or (ue and (_lower(o.get("client_email")) == ue or _lower(self._order_email_by_ref.get(str(o.get("order_reference")))) == ue or _lower(email_by_ref.get(str(o.get("order_reference")))) == ue))
                )
            ]
        def normalize_item(o: dict) -> OrderDTO:
            if not bool(dev_all):
                body = OrdersDetailNormalizedQuery(order_id=str(o.get("order_id")), order_reference=str(o.get("order_reference")))
                try:
                    dto = self.orders_detail_normalized(body, request_id=request_id)
                    return dto
                except Exception:
                    pass
            from datetime import datetime as _dt
            v = o.get("created_at")
            if v is None:
                created_at = datetime.utcnow()
            else:
                s = str(v).strip()
                parsed = None
                if s.isdigit():
                    try:
                        parsed = _dt.utcfromtimestamp(int(float(s)))
                    except Exception:
                        parsed = None
                if parsed is None:
                    for fmt in ("%b %d, %Y at %H:%M:%S", "%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S"):
                        try:
                            parsed = _dt.strptime(s.replace("T", " "), fmt)
                            break
                        except Exception:
                            continue
                created_at = parsed or datetime.utcnow()
            raw_status = str(o.get("order_status") or o.get("plan_status") or "").lower()
            if any(k in raw_status for k in ("paid", "success", "active")):
                status = "paid"
            elif "fail" in raw_status:
                status = "failed"
            else:
                status = "created"
            cur = str(o.get("currency_code") or "USD")
            try:
                price = float(o.get("reseller_retail_price", o.get("bundle_sale_price", 0.0)) or 0.0)
            except Exception:
                price = 0.0
            return OrderDTO(
                id=str(o.get("order_id") or o.get("order_reference") or ""),
                bundleId=str(o.get("bundle_code") or ""),
                amount=price,
                currency=cur,
                createdAt=created_at,
                status=status,
                paymentMethod="alipay",
                installation=None,
            )
        return [normalize_item(o) for o in orders]

    def orders_list_with_usage(self, body: OrdersListWithUsageQuery, request_id: Optional[str] = None, user_email: Optional[str] = None, user_id: Optional[str] = None, max_usage: Optional[int] = None, dev_all: Optional[bool] = None) -> dict:
            import os
            try:
                limit = int(os.getenv("ORDERS_USAGE_LIMIT", "8"))
            except Exception:
                limit = 8
            if max_usage is not None:
                try:
                    limit = max(0, int(max_usage))
                except Exception:
                    pass
            data = self.provider.list_orders_v2(
                page_number=body.page_number,
                page_size=body.page_size,
                filters={
                    "bundle_code": body.bundle_code,
                    "order_id": body.order_id,
                    "order_reference": body.order_reference,
                    "start_date": body.start_date,
                    "end_date": body.end_date,
                    "iccid": body.iccid,
                },
                request_id=request_id,
            )
            orders = data.get("orders", [])
            ue = (user_email or "").strip().lower()
            uid = (user_id or "").strip()
            if (uid or ue) and not bool(dev_all):
                def _lower(s: Optional[str]) -> str:
                    return (s or "").strip().lower()
                refs = [str(o.get("order_reference")) for o in orders if o.get("order_reference")]
                oids = [str(o.get("order_id")) for o in orders if o.get("order_id")]
                uid_by_ref: dict[str, str] = {}
                uid_by_oid: dict[str, str] = {}
                email_by_ref: dict[str, str] = {}
                db = self._get_db()
                try:
                    if refs:
                        rows = db.query(OrderReferenceEmail).filter(OrderReferenceEmail.order_reference.in_(refs)).all()
                        for r in rows:
                            uid_by_ref[r.order_reference] = (r.user_id or "").strip()
                            email_by_ref[r.order_reference] = (r.email or "").strip().lower()
                    if oids:
                        rows2 = db.query(OrderReferenceEmail).filter(OrderReferenceEmail.provider_order_id.in_(oids)).all()
                        for r in rows2:
                            uid_by_oid[r.provider_order_id or ""] = (r.user_id or "").strip()
                finally:
                    db.close()
                orders = [
                    o for o in orders
                    if (
                        (uid and (uid_by_ref.get(str(o.get("order_reference"))) == uid or uid_by_oid.get(str(o.get("order_id"))) == uid))
                        or (ue and (_lower(o.get("client_email")) == ue or _lower(self._order_email_by_ref.get(str(o.get("order_reference")))) == ue or _lower(email_by_ref.get(str(o.get("order_reference")))) == ue))
                    )
                ]
            from datetime import datetime as _dt
            def to_dto(o: dict) -> OrderDTO:
                v = o.get("created_at")
                if v is None:
                    created_at = datetime.utcnow()
                else:
                    s = str(v).strip()
                    parsed = None
                    if s.isdigit():
                        try:
                            parsed = _dt.utcfromtimestamp(int(float(s)))
                        except Exception:
                            parsed = None
                    if parsed is None:
                        for fmt in ("%b %d, %Y at %H:%M:%S", "%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S"):
                            try:
                                parsed = _dt.strptime(s.replace("T", " "), fmt)
                                break
                            except Exception:
                                continue
                    created_at = parsed or datetime.utcnow()
                raw_status = str(o.get("order_status") or o.get("plan_status") or "").lower()
                if any(k in raw_status for k in ("paid", "success", "active")):
                    status = "paid"
                elif "fail" in raw_status:
                    status = "failed"
                else:
                    status = "created"
                cur = str(o.get("currency_code") or "USD")
                try:
                    price = float(o.get("reseller_retail_price", o.get("bundle_sale_price", 0.0)) or 0.0)
                except Exception:
                    price = 0.0
                return OrderDTO(
                    id=str(o.get("order_id") or o.get("order_reference") or ""),
                    bundleId=str(o.get("bundle_code") or ""),
                    amount=price,
                    currency=cur,
                    createdAt=created_at,
                    status=status,
                    paymentMethod="alipay",
                    installation=None,
                )
            refs_for_usage = [str(o.get("order_reference")) for o in orders if o.get("order_reference")][:max(0, int(limit))]
            usage_map: dict[str, dict] = {}
            if refs_for_usage:
                batch = self.orders_consumption_batch(OrdersConsumptionBatchQuery(order_references=refs_for_usage), request_id=request_id)
                for it in (batch.get("items") or []):
                    r = str(it.get("order_reference") or "")
                    usage_map[r] = it.get("usage") or {}
            items: list[dict] = []
            for o in orders:
                dto = to_dto(o)
                ref = str(o.get("order_reference") or "")
                usage = usage_map.get(ref, {})
                items.append({"order": dto, "usage": usage})
            # Dev fallback: if no items, try local DB orders (for testing without upstream/history)
            if not items:
                db = self._get_db()
                try:
                    q = db.query(Order)
                    if user_id:
                        q = q.filter(Order.user_id == user_id)
                    q = q.order_by(Order.created_at.desc())
                    q = q.offset(max(0, (body.page_number - 1) * int(body.page_size))).limit(int(body.page_size))
                    rows = q.all()
                    for row in rows:
                        dto = OrderDTO(
                            id=row.id,
                            bundleId=row.bundle_id,
                            amount=float(row.amount),
                            currency=row.currency,
                            createdAt=row.created_at,
                            status=row.status,
                            paymentMethod="agent",
                            installation=None,
                        )
                        items.append({"order": dto, "usage": {}})
                finally:
                    db.close()
            return {"items": items, "orders_count": len(items)}

    def _map_installation(self, provider_order: dict) -> Optional[InstallationDTO]:
        activation_code = provider_order.get("activation_code")
        smdp = provider_order.get("smdp_address")
        if not activation_code and not smdp:
            return None
        return InstallationDTO(
            qrCodeUrl=provider_order.get("qr_code_url"),
            activationCode=activation_code,
            instructions=provider_order.get("instructions"),
            profileUrl=provider_order.get("profile_url"),
            smdp=smdp,
        )
