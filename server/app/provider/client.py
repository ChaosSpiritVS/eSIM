from __future__ import annotations
from datetime import datetime, timedelta, timezone
import os
import uuid
from typing import Any, Dict, List, Optional

from .auth import TokenManager
from .http import ProviderHTTP


class ProviderClient:
    """
    上游代理接口整合客户端。
    当环境未配置时自动回退到假数据模式（便于开发与演示）。
    """

    def __init__(self):
        self.token_mgr = TokenManager()
        self.http = ProviderHTTP(self.token_mgr)

    def generate_order_id(self) -> str:
        return uuid.uuid4().hex

    def estimate_bundle_price(self, bundle_id: str) -> float:
        if bundle_id.startswith("hk"):
            return 3.50
        if bundle_id.startswith("cn"):
            return 3.00
        return 5.00

    # 上游接口：POST /bundle/assign
    def assign_bundle(
        self,
        bundle_code: str,
        order_reference: str,
        name: Optional[str] = None,
        email: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """为用户分配套餐，返回 `order_id` 与 `iccid`。

        在假数据模式下返回可预测的演示数据；在真实模式下会携带令牌与 `Request-Id`
        转发到上游 `/bundle/assign`，并返回其 envelope 的 `data` 字段。
        """
        if self.token_mgr.fake:
            # 生成模拟的订单号与类 iccid 号码
            oid = self.generate_order_id()
            iccid = "891039" + uuid.uuid4().hex[:14]
            return {"order_id": oid, "iccid": iccid}
        payload: Dict[str, Any] = {
            "bundle_code": bundle_code,
            "order_reference": order_reference,
        }
        if name:
            payload["name"] = name
        if email:
            payload["email"] = email
        envelope = self.http.post(
            "/bundle/assign",
            payload,
            extra_headers={"Request-Id": request_id, "X-Request-Id": request_id},
            include_token=True,
        )
        data = envelope.get("data") or {}
        # 期望返回结构：{order_id, iccid}
        return {"order_id": data.get("order_id"), "iccid": data.get("iccid")}

    # 上游接口：POST /orders/list
    def list_orders(self, page: int = 1, page_size: int = 20, filters: Dict[str, Any] | None = None, request_id: Optional[str] = None) -> List[Dict[str, Any]]:
        if self.token_mgr.fake:
            now = datetime.utcnow()
            items = [
                {
                    "id": uuid.uuid4().hex,
                    "bundle_id": "hk-1",
                    "bundle_sale_price": 3.50,
                    "currency": "GBP",
                    "created_at": now - timedelta(hours=1),
                    "status": "paid",
                    "payment_method": "alipay",
                },
                {
                    "id": uuid.uuid4().hex,
                    "bundle_id": "cn-1",
                    "bundle_sale_price": 3.00,
                    "currency": "GBP",
                    "created_at": now - timedelta(hours=2),
                    "status": "created",
                    "payment_method": "alipay",
                },
            ]
            f = filters or {}
            oid = f.get("order_id")
            bundle_code = f.get("bundle_code")
            order_status = f.get("order_status")
            from_dt = f.get("create_time_from")
            to_dt = f.get("create_time_to")
            sort_by = f.get("sort_by")
            sort_order = (f.get("sort_order") or "desc").lower()
            if oid:
                # return a single matching order mock
                return [{
                    "id": oid,
                    "bundle_id": bundle_code or "hk-1",
                    "bundle_sale_price": 3.50,
                    "currency": "GBP",
                    "created_at": now - timedelta(hours=1),
                    "status": "paid",
                    "payment_method": "alipay",
                }]
            if bundle_code:
                items = [i for i in items if i.get("bundle_id") == bundle_code]
            if order_status:
                items = [i for i in items if i.get("status") == order_status]
            # 将带时区的时间标准化为无时区的 UTC，便于与演示数据（无时区）进行比较
            def to_naive_utc(dt: datetime | None) -> datetime | None:
                if not dt:
                    return None
                if dt.tzinfo is None:
                    return dt
                return dt.astimezone(timezone.utc).replace(tzinfo=None)
            from_dt = to_naive_utc(from_dt)
            to_dt = to_naive_utc(to_dt)
            if from_dt:
                items = [i for i in items if i.get("created_at") and i.get("created_at") >= from_dt]
            if to_dt:
                items = [i for i in items if i.get("created_at") and i.get("created_at") <= to_dt]
            # 假数据模式下的本地排序
            if sort_by:
                reverse = sort_order == "desc"
                if sort_by == "createdAt":
                    items.sort(key=lambda i: i.get("created_at"), reverse=reverse)
                elif sort_by == "amount":
                    items.sort(key=lambda i: i.get("bundle_sale_price"), reverse=reverse)
                elif sort_by == "status":
                    items.sort(key=lambda i: i.get("status"), reverse=reverse)
            return items[:page_size]

        payload: Dict[str, Any] = {"page": page, "page_size": page_size}
        if filters:
            # Normalize datetime fields to ISO 8601 strings
            for k in ["create_time_from", "create_time_to"]:
                if filters.get(k) and hasattr(filters.get(k), "isoformat"):
                    payload[k] = filters[k].isoformat()
            for k in ["order_id", "order_reference", "bundle_code", "order_status"]:
                if filters.get(k) is not None:
                    payload[k] = filters[k]
            # Forward sort options if provided
            if filters.get("sort_by"):
                payload["sort_by"] = filters["sort_by"]
            if filters.get("sort_order"):
                payload["sort_order"] = filters["sort_order"]

        envelope = self.http.post(
            "/orders/list",
            payload,
            extra_headers={"X-Request-Id": request_id, "Request-Id": request_id},
        )
        data = envelope.get("data") or {}
        return data.get("orders", [])

    # 上游接口：POST /orders/list（兼容版 envelope：返回 orders + orders_count）
    def list_orders_v2(
        self,
        page_number: int,
        page_size: int,
        filters: Dict[str, Any] | None = None,
        request_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """调用上游 `/orders/list`，按原样返回 `{orders, orders_count}`。

        该方法用于兼容上游的响应结构（envelope 形态）。
        """
        f = filters or {}
        if self.token_mgr.fake:
            now = datetime.utcnow()
            oid = f.get("order_id")
            oref = f.get("order_reference")
            bcode = f.get("bundle_code")
            def gen_order(order_id: Optional[str] = None, order_reference: Optional[str] = None,
                           bundle_code: str = "08232023231000_01032_5",
                           bundle_name: str = "Europe 1GB 7days",
                           country_code: list[str] = ["ALB"],
                           created_at: Optional[int] = None) -> Dict[str, Any]:
                return {
                    "order_id": (order_id or uuid.uuid4().hex[:24]),
                    "order_reference": (order_reference or ("REF-" + uuid.uuid4().hex[:12])),
                    "previous_order_reference": "",
                    "client_name": "",
                    "client_email": "",
                    "bundle_code": bundle_code,
                    "bundle_name": bundle_name,
                    "country_code": country_code,
                    "reseller_retail_price": 0.76,
                    "bundle_sale_price": 0.9,
                    "currency_code": "USD",
                    "created_at": created_at if created_at is not None else int(now.timestamp()),
                    "order_status": "Successful",
                }
            if oid:
                demo = [gen_order(order_id=str(oid), order_reference=(oref or None), bundle_code=(bcode or "08232023231000_01032_5"))]
            else:
                demo = [
                    gen_order(order_reference=(oref or None), bundle_code=(bcode or "TUR_0108202509350154"), bundle_name="Turkey 0.5GB7Days", country_code=["TUR"], created_at=int(now.timestamp())),
                    gen_order(order_reference=(oref or None), bundle_code=(bcode or "08232023231000_01032_5"), bundle_name="Europe 1GB 7days", country_code=["ALB"], created_at=int((now - timedelta(hours=4)).timestamp())),
                ]
            # 应用简单过滤条件
            # 注意：可能已基于 order_id 定制 demo；此处筛选保持稳健
            oid = f.get("order_id")
            bcode = f.get("bundle_code")
            oref = f.get("order_reference")
            iccid = f.get("iccid")
            start = f.get("start_date")
            end = f.get("end_date")
            filtered = demo
            if oid:
                filtered = [d for d in filtered if str(d.get("order_id")) == str(oid)]
            if bcode:
                filtered = [d for d in filtered if d.get("bundle_code") == bcode]
            if oref:
                filtered = [d for d in filtered if d.get("order_reference") == oref]
            if iccid:
                # 演示数据不包含 iccid，筛空表示无匹配项
                filtered = []
            # 日期筛选（格式：YYYY/MM/DD HH:MM:SS）
            def parse_dt(s: Optional[str]) -> Optional[int]:
                if not s:
                    return None
                try:
                    # 朴素解析，必须包含秒
                    y, rest = s.split("/", 1)
                    # 使用 strptime 保证解析可靠
                    from datetime import datetime as _dt
                    return int(_dt.strptime(s, "%Y/%m/%d %H:%M:%S").timestamp())
                except Exception:
                    return None
            start_ts = parse_dt(start)
            end_ts = parse_dt(end)
            if start_ts is not None:
                filtered = [d for d in filtered if int(d.get("created_at", 0)) >= start_ts]
            if end_ts is not None:
                filtered = [d for d in filtered if int(d.get("created_at", 0)) <= end_ts]
            # 分页计算
            begin = max(0, (page_number - 1) * page_size)
            end_i = begin + page_size
            page_items = filtered[begin:end_i]
            return {"orders": page_items, "orders_count": len(filtered)}

        payload: Dict[str, Any] = {
            "page_number": page_number,
            "page_size": page_size,
        }
        # 按上游规范原样透传支持的过滤字段
        for key in ("bundle_code", "order_id", "order_reference", "start_date", "end_date", "iccid"):
            val = f.get(key)
            if val:
                payload[key] = val
        envelope = self.http.post(
            "/orders/list",
            payload,
            extra_headers={"X-Request-Id": request_id, "Request-Id": request_id},
            include_token=True,
        )
        data = envelope.get("data") or {}
        # 期望返回结构：{orders: [...], orders_count: int}
        return {"orders": data.get("orders", []), "orders_count": int(data.get("orders_count", 0))}

    def get_order_detail_v2(self, order_reference: str, request_id: Optional[str] = None) -> Dict[str, Any]:
        """上游接口：POST /orders/detail（通过 order_reference 查询）

        返回兼容上游的字典数据，包含字段：
        order_id、order_status、bundle_category、bundle_code、bundle_marketing_name、
        bundle_name、country_code、country_name、order_reference、activation_code、
        bundle_expiry_date、expiry_date、iccid、plan_started、plan_status、date_created。
        """
        if self.token_mgr.fake:
            now = datetime.utcnow()
            demo = {
                "order_id": uuid.uuid4().hex[:24],
                "order_status": "Successful",
                "bundle_category": "region",
                "bundle_code": "08232023231000_01032_5",
                "bundle_marketing_name": "Europe+",
                "bundle_name": "Europe 1GB 7days",
                "country_code": ["ALB"],
                "country_name": ["Albania"],
                "order_reference": order_reference,
                "activation_code": "LPA:1$consumer.rsp.world$" + uuid.uuid4().hex.upper()[:24],
                "bundle_expiry_date": (now + timedelta(days=90)).isoformat() + "Z",
                "expiry_date": "",
                "iccid": "891039" + uuid.uuid4().hex[:14],
                "plan_started": False,
                "plan_status": "Pending",
                "date_created": (now - timedelta(days=60)).isoformat() + "Z",
            }
            return demo

        envelope = self.http.post(
            "/orders/detail",
            {"order_reference": order_reference},
            extra_headers={"X-Request-Id": request_id, "Request-Id": request_id},
            include_token=True,
        )
        data = envelope.get("data") or {}
        return data

    def get_order_consumption_v2(self, order_reference: str, request_id: Optional[str] = None) -> Dict[str, Any]:
        """上游接口：POST /orders/consumption（通过 order_reference 查询）

        返回与上游兼容的订单用量对象，字段包括：
        bundle_expiry_date、iccid、plan_status、data_allocated、data_remaining、
        data_used、data_unit、minutes_allocated、minutes_remaining、minutes_used、
        sms_allocated、sms_remaining、sms_used、supports_calls_sms、unlimited
        """
        if self.token_mgr.fake:
            now = datetime.utcnow()
            demo_order = {
                "bundle_expiry_date": (now + timedelta(days=20)).strftime("%Y-%m-%d %H:%M:%S.%f"),
                "data_allocated": 1024.0,
                "data_remaining": 1024.0,
                "data_unit": "MB",
                "data_used": 0.0,
                "iccid": "891039" + uuid.uuid4().hex[:13],
                "minutes_allocated": 0.0,
                "minutes_remaining": 0.0,
                "minutes_used": 0.0,
                "plan_status": "Plan Not Started",
                "sms_allocated": 0.0,
                "sms_remaining": 0.0,
                "sms_used": 0.0,
                "supports_calls_sms": False,
                "unlimited": False,
            }
            return demo_order

        envelope = self.http.post(
            "/orders/consumption",
            {"order_reference": order_reference},
            extra_headers={"X-Request-Id": request_id, "Request-Id": request_id},
            include_token=True,
        )
        data = envelope.get("data") or {}
        order = data.get("order") or {}
        return order

    # 上游接口：POST /orders/detail
    def get_order(self, order_id: str, request_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
        if self.token_mgr.fake:
            return {
                "id": order_id,
                "bundle_id": "hk-1",
                "bundle_sale_price": 3.50,
                "currency": "GBP",
                "created_at": datetime.utcnow() - timedelta(hours=1),
                "status": "paid",
                "payment_method": "alipay",
                "activation_code": "ABCDEF-123456",
                "smdp_address": "smdp.example.com",
                "qr_code_url": "https://example.com/qr/demo.png",
                "instructions": [
                    "在设置中选择‘蜂窝移动网络’→‘添加 eSIM’",
                    "扫描二维码或输入激活码",
                    "确认并启用数据网络",
                ],
                "profile_url": "https://example.com/esim-profile.mobileconfig",
            }
        envelope = self.http.post(
            "/orders/detail",
            {"order_id": order_id},
            extra_headers={"X-Request-Id": request_id, "Request-Id": request_id},
        )
        return envelope.get("data")

    # 上游接口：POST /orders/consumption
    def get_usage(self, order_id: str, request_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
        if self.token_mgr.fake:
            return {
                "data_remaining": 512.0,
                "expires_at": datetime.utcnow() + timedelta(days=9),
                "last_updated": datetime.utcnow(),
            }
        envelope = self.http.post(
            "/orders/consumption",
            {"order_id": order_id},
            extra_headers={"X-Request-Id": request_id, "Request-Id": request_id},
        )
        return envelope.get("data")

    # ===== Catalog (Countries/Regions/Bundles) =====
    def get_countries(self, request_id: Optional[str] = None) -> List[Dict[str, Any]]:
        if self.token_mgr.fake:
            return [
                {
                    "code": "HK",
                    "name": "中国香港",
                    "iso2_code": "HK",
                    "iso3_code": "HKG",
                    "country_name": "中国香港",
                },
                {
                    "code": "CN",
                    "name": "中国大陆",
                    "iso2_code": "CN",
                    "iso3_code": "CHN",
                    "country_name": "中国大陆",
                },
                {
                    "code": "GB",
                    "name": "英国",
                    "iso2_code": "GB",
                    "iso3_code": "GBR",
                    "country_name": "英国",
                },
            ]
        envelope = self.http.post(
            "/bundle/countries",
            {},
            extra_headers={"Request-Id": request_id, "X-Request-Id": request_id},
            include_token=True,
        )
        data = envelope.get("data") or {}
        countries = data.get("countries", [])
        normalized: List[Dict[str, Any]] = []
        for c in countries:
            iso2 = c.get("iso2_code") or c.get("code")
            iso3 = c.get("iso3_code")
            name = c.get("country_name") or c.get("name")
            if iso2 and name:
                normalized.append(
                    {
                        "code": iso2,
                        "name": name,
                        "iso2_code": iso2,
                        "iso3_code": iso3,
                        "country_name": name,
                    }
                )
        return normalized

    def get_regions(self, request_id: Optional[str] = None) -> List[Dict[str, Any]]:
        if self.token_mgr.fake:
            return [
                {"code": "af", "name": "Africa", "region_code": "af", "region_name": "Africa"},
                {"code": "as", "name": "Asia", "region_code": "as", "region_name": "Asia"},
                {"code": "eu", "name": "Europe", "region_code": "eu", "region_name": "Europe"},
                {"code": "me", "name": "Middle East", "region_code": "me", "region_name": "Middle East"},
                {"code": "na", "name": "North America", "region_code": "na", "region_name": "North America"},
                {"code": "sa", "name": "South America", "region_code": "sa", "region_name": "South America"},
            ]
        envelope = self.http.post(
            "/bundle/regions",
            {},
            extra_headers={"Request-Id": request_id, "X-Request-Id": request_id},
            include_token=True,
        )
        data = envelope.get("data") or {}
        regions = data.get("regions", [])
        normalized: List[Dict[str, Any]] = []
        for r in regions:
            code = r.get("region_code") or r.get("code")
            name = r.get("region_name") or r.get("name")
            if code and name:
                normalized.append({"code": code, "name": name, "region_code": code, "region_name": name})
        return normalized

    def get_bundles(self, country_code: Optional[str] = None, popular: bool = False) -> List[Dict[str, Any]]:
        if self.token_mgr.fake:
            base = [
                {
                    "id": "hk-1",
                    "name": "香港 1GB 3天",
                    "country_code": "HK",
                    "price": 3.50,
                    "currency": "GBP",
                    "data_amount": "1 GB",
                    "validity_days": 3,
                    "description": "香港本地数据套餐",
                    "supported_networks": ["CSL", "HKT"],
                    "hotspot_supported": True,
                    "coverage_note": "香港全境覆盖",
                    "terms_url": "https://example.com/terms",
                },
                {
                    "id": "cn-1",
                    "name": "中国大陆 1GB 3天",
                    "country_code": "CN",
                    "price": 3.00,
                    "currency": "GBP",
                    "data_amount": "1 GB",
                    "validity_days": 3,
                    "description": "大陆数据套餐",
                    "supported_networks": ["China Mobile", "China Unicom"],
                    "hotspot_supported": True,
                    "coverage_note": "主要城市覆盖",
                    "terms_url": "https://example.com/terms",
                },
            ]
            if country_code:
                base = [b for b in base if b["country_code"].lower() == country_code.lower()]
            if popular:
                # In demo, treat first item as popular
                base = base[:1]
            return base
        payload: Dict[str, Any] = {}
        if country_code:
            payload["country"] = country_code
        if popular:
            payload["popular"] = True
        envelope = self.http.post("/catalog/bundles", payload, extra_headers=None)
        data = envelope.get("data") or {}
        return data.get("bundles", [])

    def get_bundle_list(
        self,
        page_number: int,
        page_size: int,
        country_code: Optional[str] = None,
        region_code: Optional[str] = None,
        bundle_category: Optional[str] = None,
        sort_by: Optional[str] = None,
        bundle_code: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """调用上游 /bundle/list 并返回与文档一致的字段。"""
        if self.token_mgr.fake:
            demo = [
                {
                    "bundle_category": "country",
                    "bundle_code": "HKG_0110202517200001",
                    "bundle_marketing_name": "Hong Kong",
                    "bundle_name": "Hong Kong 1GB3Days",
                    "country_code": ["HKG"],
                    "country_name": ["Hong Kong"],
                    "data_unit": "GB",
                    "gprs_limit": 1,
                    "is_active": True,
                    "region_code": "",
                    "region_name": "",
                    "service_type": "DATA",
                    "sms_amount": 0,
                    "support_topup": False,
                    "supports_calls_sms": False,
                    "unlimited": False,
                    "validity": 3,
                    "voice_amount": 0,
                    "reseller_retail_price": 0.7,
                    "bundle_price_final": 0.84,
                },
                {
                    "bundle_category": "country",
                    "bundle_code": "CHN_0110202517200002",
                    "bundle_marketing_name": "China Mainland",
                    "bundle_name": "China 1GB3Days",
                    "country_code": ["CHN"],
                    "country_name": ["China"],
                    "data_unit": "GB",
                    "gprs_limit": 1,
                    "is_active": True,
                    "region_code": "",
                    "region_name": "",
                    "service_type": "DATA",
                    "sms_amount": 0,
                    "support_topup": False,
                    "supports_calls_sms": False,
                    "unlimited": False,
                    "validity": 3,
                    "voice_amount": 0,
                    "reseller_retail_price": 0.6,
                    "bundle_price_final": 0.75,
                },
                {
                    "bundle_category": "region",
                    "bundle_code": "EUR_0110202517200004",
                    "bundle_marketing_name": "Europe",
                    "bundle_name": "Europe 1GB7Days",
                    "country_code": ["FRA", "DEU", "ESP", "ITA"],
                    "country_name": ["France", "Germany", "Spain", "Italy"],
                    "data_unit": "GB",
                    "gprs_limit": 1,
                    "is_active": True,
                    "region_code": "eu",
                    "region_name": "Europe",
                    "service_type": "DATA",
                    "sms_amount": 0,
                    "support_topup": False,
                    "supports_calls_sms": False,
                    "unlimited": False,
                    "validity": 7,
                    "voice_amount": 0,
                    "reseller_retail_price": 1.8,
                    "bundle_price_final": 2.4,
                },
                {
                    "bundle_category": "global",
                    "bundle_code": "GLB_0110202517200003",
                    "bundle_marketing_name": "Global",
                    "bundle_name": "Global 3GB7Days",
                    "country_code": [],
                    "country_name": [],
                    "data_unit": "GB",
                    "gprs_limit": 3,
                    "is_active": True,
                    "region_code": "",
                    "region_name": "",
                    "service_type": "DATA",
                    "sms_amount": 0,
                    "support_topup": False,
                    "supports_calls_sms": False,
                    "unlimited": False,
                    "validity": 7,
                    "voice_amount": 0,
                    "reseller_retail_price": 6.5,
                    "bundle_price_final": 9.0,
                },
                {
                    "bundle_category": "cruise",
                    "bundle_code": "CRS_0110202517200005",
                    "bundle_marketing_name": "Cruise",
                    "bundle_name": "Cruise 1GB3Days",
                    "country_code": [],
                    "country_name": [],
                    "data_unit": "GB",
                    "gprs_limit": 1,
                    "is_active": True,
                    "region_code": "",
                    "region_name": "",
                    "service_type": "DATA",
                    "sms_amount": 0,
                    "support_topup": False,
                    "supports_calls_sms": False,
                    "unlimited": False,
                    "validity": 3,
                    "voice_amount": 0,
                    "reseller_retail_price": 1.2,
                    "bundle_price_final": 1.5,
                },
            ]
            # Filters
            filtered = demo
            if bundle_category:
                bc = str(bundle_category).lower()
                filtered = [b for b in filtered if str(b.get("bundle_category") or "").lower() == bc]
            if country_code:
                filtered = [
                    b for b in filtered
                    if (country_code.upper() in [c.upper() for c in (b.get("country_code") or [])])
                ]
            if region_code:
                rc = region_code.lower()
                filtered = [b for b in filtered if str(b.get("region_code") or "").lower() == rc]
            if bundle_code:
                filtered = [b for b in filtered if str(b.get("bundle_code") or "") == str(bundle_code)]
            # Helper: normalize data amount to MB for correct sorting across units
            def _data_in_mb(b: Dict[str, Any]) -> float:
                try:
                    val = float(b.get("gprs_limit", 0.0) or 0.0)
                except Exception:
                    val = 0.0
                unit = str(b.get("data_unit") or "").strip().upper()
                # Unlimited plans should be treated as very large for ascending (push to end)
                if bool(b.get("unlimited")):
                    return 9e12
                if unit in ("GB", "G", "GIB"):
                    return val * 1024.0
                if unit in ("MB", "M", "MIB"):
                    return val
                if unit in ("KB", "K", "KIB"):
                    return val / 1024.0
                if unit in ("TB", "T", "TIB"):
                    return val * 1024.0 * 1024.0
                if unit in ("B", "BYTE", "BYTES"):
                    return val / (1024.0 * 1024.0)
                # Fallback: assume MB
                return val

            # Sorting
            if sort_by == "price_asc":
                filtered.sort(key=lambda b: float(b.get("bundle_price_final", 0.0)))
            elif sort_by == "price_dsc":
                filtered.sort(key=lambda b: float(b.get("bundle_price_final", 0.0)), reverse=True)
            elif sort_by == "bundle_name":
                filtered.sort(key=lambda b: str(b.get("bundle_name", "")))
            elif sort_by == "data_asc":
                # 使用单位归一化后的数据量（MB）进行排序，避免 GB/MB 混排导致错误
                filtered.sort(key=lambda b: _data_in_mb(b))
            elif sort_by == "data_dsc":
                filtered.sort(key=lambda b: _data_in_mb(b), reverse=True)
            elif sort_by == "sms_asc":
                filtered.sort(key=lambda b: float(b.get("sms_amount", 0.0)))
            elif sort_by == "sms_dsc":
                filtered.sort(key=lambda b: float(b.get("sms_amount", 0.0)), reverse=True)
            elif sort_by == "voice_asc":
                filtered.sort(key=lambda b: float(b.get("voice_amount", 0.0)))
            elif sort_by == "voice_dsc":
                filtered.sort(key=lambda b: float(b.get("voice_amount", 0.0)), reverse=True)
            start = max(0, (page_number - 1) * page_size)
            end = start + page_size
            page_items = filtered[start:end]
            return {"bundles": page_items, "bundles_count": len(filtered)}

        payload: Dict[str, Any] = {
            "page_number": page_number,
            "page_size": page_size,
        }
        # Upstream requires string type; send empty string when not provided
        payload["country_code"] = (country_code or "").upper()
        payload["region_code"] = (region_code or "").lower()
        payload["bundle_category"] = (bundle_category or "").lower()
        payload["sort_by"] = sort_by or ""
        payload["bundle_code"] = bundle_code or ""
        envelope = self.http.post(
            "/bundle/list",
            payload,
            extra_headers={"Request-Id": request_id, "X-Request-Id": request_id},
            include_token=True,
        )
        data = envelope.get("data") or {}
        bundles = data.get("bundles") or []
        if sort_by in ("data_asc", "data_dsc"):
            reverse = (sort_by == "data_dsc")
            def _data_in_mb_upstream(b: Dict[str, Any]) -> float:
                try:
                    val = float(b.get("gprs_limit", 0.0) or 0.0)
                except Exception:
                    val = 0.0
                unit = str(b.get("data_unit") or "").strip().upper()
                if bool(b.get("unlimited")):
                    return 9e12
                if unit in ("GB", "G", "GIB"):
                    return val * 1024.0
                if unit in ("MB", "M", "MIB"):
                    return val
                if unit in ("KB", "K", "KIB"):
                    return val / 1024.0
                if unit in ("TB", "T", "TIB"):
                    return val * 1024.0 * 1024.0
                if unit in ("B", "BYTE", "BYTES"):
                    return val / (1024.0 * 1024.0)
                return val
            bundles = sorted(bundles, key=_data_in_mb_upstream, reverse=reverse)
        upstream_count = data.get("bundles_count") or data.get("total") or data.get("count")
        try:
            bundles_count = int(float(str(upstream_count))) if upstream_count is not None else len(bundles)
        except Exception:
            bundles_count = len(bundles)
        return {"bundles": bundles, "bundles_count": int(bundles_count)}

    def get_bundle(self, bundle_id: str) -> Optional[Dict[str, Any]]:
        if self.token_mgr.fake:
            for b in self.get_bundles():
                if b["id"] == bundle_id:
                    return b
            return None
        envelope = self.http.post("/catalog/bundle/detail", {"bundle_id": bundle_id}, extra_headers=None)
        return envelope.get("data")

    def get_bundle_networks(self, bundle_id: str) -> List[str]:
        if self.token_mgr.fake:
            b = self.get_bundle(bundle_id)
            return (b or {}).get("supported_networks", [])
        envelope = self.http.post("/catalog/bundle/networks", {"bundle_id": bundle_id}, extra_headers=None)
        data = envelope.get("data") or {}
        return data.get("networks", [])

    def get_bundle_networks_v2(
        self,
        bundle_code: str,
        country_code: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """调用上游 /bundle/networks 并返回与文档一致的字段。

        返回对象：{"networks": [{"country_code": str, "operator_list": [str]}], "networks_count": int}
        若提供 country_code，仅返回对应国家的一条记录（如存在）。
        """
        if self.token_mgr.fake:
            code = (bundle_code or "").upper()
            demo_all = [
                {"country_code": "HKG", "operator_list": ["CSL", "HKT"]},
                {"country_code": "CHN", "operator_list": ["China Mobile", "China Unicom"]},
                {"country_code": "TUR", "operator_list": ["TURKTELEKOM", "TURKCELL"]},
            ]
            base = demo_all
            if code.startswith("HKG"):
                base = [demo_all[0]]
            elif code.startswith("CHN"):
                base = [demo_all[1]]
            elif code.startswith("TUR"):
                base = [demo_all[2]]
            if country_code:
                cc = country_code.upper()
                base = [n for n in base if (n.get("country_code") or "").upper() == cc]
            return {"networks": base, "networks_count": len(base)}

        payload: Dict[str, Any] = {"bundle_code": bundle_code}
        payload["country_code"] = country_code or ""
        envelope = self.http.post(
            "/bundle/networks",
            payload,
            extra_headers={"Request-Id": request_id, "X-Request-Id": request_id},
            include_token=True,
        )
        data = envelope.get("data") or {}
        networks = data.get("networks") or []
        if country_code:
            cc = (country_code or "").upper()
            networks = [n for n in networks if (n.get("country_code") or "").upper() == cc]
        count = data.get("networks_count")
        try:
            networks_count = int(float(str(count))) if count is not None else len(networks)
        except Exception:
            networks_count = len(networks)
        return {"networks": networks, "networks_count": int(networks_count)}

    # ===== Agent =====
    def get_agent_account(self, request_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
        if self.token_mgr.fake:
            return {
                "agent_id": uuid.uuid4().hex,
                "username": "demo-agent",
                "name": "Demo Agent",
                "balance": 1007.6,
                "revenue_rate": 20,
                "status": 1,
                "created_at": int((datetime.now(tz=timezone.utc) - timedelta(days=30)).timestamp()),
            }
        envelope = self.http.post(
            "/agent/account",
            {},
            extra_headers={"Request-Id": request_id, "X-Request-Id": request_id},
            include_token=True,
        )
        return envelope.get("data")

    def get_agent_bills(
        self,
        page_number: int,
        page_size: int,
        reference: Optional[str] = None,
        start_date: Optional[str] = None,
        end_date: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        if self.token_mgr.fake:
            bills = [
                {
                    "bill_id": uuid.uuid4().hex,
                    "trade": 10,
                    "amount": 1000,
                    "reference": "S250915353862TYNMG2",
                    "description": "topup balance",
                    "created_at": int((datetime.now(tz=timezone.utc) - timedelta(days=9)).timestamp()),
                },
                {
                    "bill_id": uuid.uuid4().hex,
                    "trade": 20,
                    "amount": -0.6,
                    "reference": "OR20250908966X9497001",
                    "description": "assign bundle",
                    "created_at": int((datetime.now(tz=timezone.utc) - timedelta(days=12)).timestamp()),
                },
            ]
            return {"bills": bills[:page_size], "bills_count": len(bills)}

        payload: Dict[str, Any] = {
            "page_number": page_number,
            "page_size": page_size,
            "reference": reference or "",
            "start_date": start_date or "",
            "end_date": end_date or "",
        }
        envelope = self.http.post(
            "/agent/bills",
            payload,
            extra_headers={"Request-Id": request_id, "X-Request-Id": request_id},
            include_token=True,
        )
        data = envelope.get("data") or {}
        return data