from datetime import datetime, timedelta
import os
from typing import Literal, Annotated
from pydantic import BaseModel, Field
from pydantic import ConfigDict
from fastapi import Query
from fastapi import FastAPI, HTTPException, Request, Response, Depends, Header
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
import hashlib
from fastapi.responses import JSONResponse, HTMLResponse
from fastapi.encoders import jsonable_encoder

from .models.dto import (
    OrderDTO,
    CreateOrderBody,
    UsageDTO,
    RefundDTO,
    UserDTO,
    UpdateProfileBody,
    RegisterBody,
    LoginBody,
    AppleLoginBody,
    PasswordResetBody,
    ResetDTO,
    PasswordResetConfirmBody,
    EmailCodeRequestBody,
    EmailCodeDTO,
    BundleDTO,
    CountryDTO,
    RegionDTO,
    BundleListQuery,
    BundleNetworksQuery,
    AgentAccountDTO,
    AgentBillsDTO,
    AgentBillsQuery,
    BundleNetworksQuery,
    BundleAssignBody,
    BundleAssignResultDTO,
    OrdersListQuery,
    OrdersDetailQuery,
    OrdersDetailByIdQuery,
    OrdersConsumptionQuery,
    OrdersConsumptionByIdQuery,
    OrdersDetailNormalizedQuery,
    OrdersConsumptionBatchQuery,
    BundleCodeQuery,
    OrdersListNormalizedQuery,
    OrdersListWithUsageQuery,
    BundleNetworksFlatQuery,
    LanguageOptionDTO,
    CurrencyOptionDTO,
    ChangeEmailBody,
    UpdatePasswordBody,
    DeleteAccountBody,
    SuccessDTO,
    SearchResultDTO,
    SearchLogBody,
    I18nCountryUpsertBody,
    I18nRegionUpsertBody,
    I18nBundleUpsertBody,
)
from .services.order_service import OrderService
from .services.auth_service import AuthService
from .services.catalog_service import CatalogService
from .i18n import resolve_language, translate_country, translate_region, translate_marketing, translate_bundle_name
from .db import SessionLocal
from .models.orm import I18nCountryName, I18nRegionName, I18nBundleName, RecentSearch
from .services.agent_service import AgentService
from .middleware.request_id import RequestIdMiddleware
from .provider.errors import ProviderError
from dotenv import load_dotenv
from .db import init_db, SessionLocal
from .security.jwt import decode_token
from .models.orm import User as ORMUser
from .models.orm import LanguageOption, CurrencyOption
from .models.orm import GSalaryAuthToken
from .models.orm import IdempotencyRecord
from sqlalchemy.orm import Session
from .models.dto import AuthResponseDTO, RefreshBody, LogoutBody

# 显式加载 server 目录下的 .env（避免从不同工作目录启动时无法找到配置）
try:
    BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    env_path = os.path.join(BASE_DIR, ".env")
    load_dotenv(env_path)
except Exception:
    load_dotenv()

app = FastAPI(title="Simigo Backend", version="0.1.0")
SERVER_STARTED_AT = datetime.utcnow()

# CORS for local development and iOS simulator
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"]
)
app.add_middleware(GZipMiddleware, minimum_size=500)

app.add_middleware(RequestIdMiddleware)

service = OrderService()
auth_service = AuthService()
catalog_service = CatalogService()
agent_service = AgentService()

# ===== Unified envelope exception handlers (scoped to upstream-compatible alias routes) =====

def _get_db():
    return SessionLocal()


def _status_for_gateway_error(c, m: str) -> int:
    s = (m or "").lower()
    try:
        ci = int(c) if c is not None else None
    except Exception:
        ci = None
    if ci == 500 or any(k in s for k in ["系统错误", "添加卡失败", "创建收款人账户失败", "更新收款人账户失败"]):
        return 500
    if ci == 423 or ("系统繁忙" in s):
        return 423
    if ci == 404 or ("未找到" in s):
        return 404
    if ci == 403 or any(k in s for k in ["禁忌", "不允许"]):
        return 403
    if ci == 400 or any(k in s for k in ["错误的请求", "缺少参数", "无效参数", "无效状态", "重复", "报价过期", "订单到期", "余额不足", "风险", "拒绝"]):
        return 400
    return 400


def get_current_user(request: Request) -> ORMUser:
    auth = request.headers.get("Authorization")
    if not auth or not auth.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing Authorization header")
    token = auth.split(" ", 1)[1].strip()
    try:
        payload = decode_token(token)
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {e}")
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid token subject")
    db = _get_db()
    try:
        user = db.query(ORMUser).filter(ORMUser.id == user_id).first()
        if not user:
            raise HTTPException(status_code=401, detail="User not found")
        return user
    finally:
        db.close()

@app.get("/config")
async def get_client_config(request: Request):
    def read_env(names: list[str]) -> float | None:
        for n in names:
            v = os.getenv(n)
            if v is not None and v != "":
                try:
                    return float(v)
                except Exception:
                    continue
        return None
    def read_bool(names: list[str]) -> bool | None:
        for n in names:
            v = os.getenv(n)
            if v is not None and v != "":
                s = v.strip().lower()
                if s in ("1", "true", "yes", "on"): return True
                if s in ("0", "false", "no", "off"): return False
        return None

    cfg = {}
    mapping: list[tuple[str, list[str]]] = [
        ("catalogCacheTTL", ["TTL_CATALOG", "CATALOG_CACHE_TTL"]),
        ("ordersCacheTTL", ["TTL_ORDERS", "ORDERS_CACHE_TTL"]),
        ("orderDetailCacheTTL", ["TTL_ORDER_DETAIL", "ORDER_DETAIL_CACHE_TTL"]),
        ("agentAccountCacheTTL", ["TTL_AGENT_ACCOUNT", "AGENT_ACCOUNT_CACHE_TTL"]),
        ("agentBillsCacheTTL", ["TTL_AGENT_BILLS", "AGENT_BILLS_CACHE_TTL"]),
        ("bundleNetworksCacheTTL", ["TTL_BUNDLE_NETWORKS", "BUNDLE_NETWORKS_CACHE_TTL"]),
        ("settingsCacheTTL", ["TTL_SETTINGS", "SETTINGS_CACHE_TTL"]),
        ("searchSuggestionsCacheTTL", ["TTL_SEARCH_SUGGESTIONS", "SEARCH_SUGGESTIONS_CACHE_TTL"]),
        ("orderUsageCacheTTL", ["TTL_ORDER_USAGE", "ORDER_USAGE_CACHE_TTL"]),
    ]
    for key, names in mapping:
        val = read_env(names)
        if val is not None and val >= 0:
            cfg[key] = val

    ben = read_bool(["BANNER_ENABLED"]) 
    if ben is not None:
        # include as a boolean field
        cfg["bannerEnabled"] = bool(ben)  # type: ignore
    bmap = [
        ("bannerErrorDismiss", ["BANNER_ERROR_DISMISS"]),
        ("bannerSuccessDismiss", ["BANNER_SUCCESS_DISMISS"]),
        ("bannerWarningDismiss", ["BANNER_WARNING_DISMISS"]),
        ("bannerInfoDismiss", ["BANNER_INFO_DISMISS"]),
    ]
    for key, names in bmap:
        val = read_env(names)
        if val is not None and val >= 0:
            cfg[key] = val

    headers = {}
    rid = getattr(request.state, "request_id", None)
    if rid:
        headers["X-Request-Id"] = rid
    return JSONResponse(status_code=200, content=cfg, headers=headers)

def _json_envelope(content: dict, request: Request | None = None) -> JSONResponse:
    # Always HTTP 200; middleware will add X-Request-Id, but we attach if available
    headers = {}
    if request is not None:
        req_id = getattr(request.state, "request_id", None)
        if req_id:
            headers["X-Request-Id"] = req_id
    return JSONResponse(status_code=200, content=content, headers=headers)

def _idem_get(request: Request, idem_key: str, body_hash: str):
    import json
    try:
        r = getattr(request.app.state, "idem_redis", None)
        if r is not None:
            k = f"idem:{idem_key}:{request.url.path}:{request.method}:{body_hash}"
            v = r.get(k)
            if v:
                return json.loads(v)
    except Exception:
        pass
    db = _get_db()
    try:
        rec = db.query(IdempotencyRecord).filter(
            IdempotencyRecord.key == idem_key,
            IdempotencyRecord.route == request.url.path,
            IdempotencyRecord.method == request.method,
            IdempotencyRecord.body_hash == body_hash,
            IdempotencyRecord.expires_at > datetime.utcnow(),
        ).first()
        if rec:
            return json.loads(rec.response_json)
        rec2 = db.query(IdempotencyRecord).filter(
            IdempotencyRecord.key == idem_key,
            IdempotencyRecord.route == request.url.path,
            IdempotencyRecord.method == request.method,
            IdempotencyRecord.body_hash == None,
            IdempotencyRecord.expires_at > datetime.utcnow(),
        ).first()
        if rec2:
            return json.loads(rec2.response_json)
    finally:
        db.close()
    try:
        s = getattr(request.app.state, "idem_store", None)
        if s is not None:
            ck = f"idem:{idem_key}:{request.url.path}:{request.method}:{body_hash}"
            v = s.get(ck)
            if v and v.get("expires_at") and v["expires_at"] > datetime.utcnow():
                return v["response"]
            v2 = s.get(idem_key)
            if v2 and v2.get("expires_at") and v2["expires_at"] > datetime.utcnow():
                return v2["response"]
    except Exception:
        pass
    return None

def _idem_set(request: Request, idem_key: str, body_hash: str, dto):
    from fastapi.encoders import jsonable_encoder as _je
    import json
    ttl = 86400
    try:
        ttl = int(os.getenv("IDEMPOTENCY_TTL_SECONDS", "86400"))
    except Exception:
        ttl = 86400
    try:
        r = getattr(request.app.state, "idem_redis", None)
        if r is not None:
            k = f"idem:{idem_key}:{request.url.path}:{request.method}:{body_hash}"
            r.setex(k, ttl, json.dumps(_je(dto), separators=(",", ":"), ensure_ascii=False))
    except Exception:
        pass
    try:
        s = getattr(request.app.state, "idem_store", None)
        if s is None:
            request.app.state.idem_store = {}
            s = request.app.state.idem_store
        ck = f"idem:{idem_key}:{request.url.path}:{request.method}:{body_hash}"
        s[ck] = {"expires_at": datetime.utcnow() + timedelta(seconds=ttl), "response": _je(dto)}
    except Exception:
        pass
    db = _get_db()
    try:
        rec = IdempotencyRecord(
            key=idem_key,
            route=request.url.path,
            method=request.method,
            body_hash=body_hash,
            response_json=json.dumps(_je(dto), separators=(",", ":"), ensure_ascii=False),
            expires_at=datetime.utcnow() + timedelta(seconds=ttl),
        )
        db.add(rec)
        db.commit()
    finally:
        db.close()

def _gateway_call(request: Request, method: str, path: str, payload: dict) -> dict:
    import os, time, hashlib, base64, rsa, urllib.parse, json, httpx
    base_url = os.getenv("GSALARY_BASE_URL", "").rstrip("/")
    if not base_url:
        raise HTTPException(status_code=500, detail="missing base url")
    appid = os.getenv("GSALARY_APPID", "")
    timestamp = str(int(time.time()*1000))
    if method.upper() == "GET":
        body_json = ""
        body_hash = base64.b64encode(hashlib.sha256(b"").digest()).decode()
    else:
        body_json = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
        body_hash = base64.b64encode(hashlib.sha256(body_json.encode("utf-8")).digest()).decode()
    sign_base = f"{method} {path}\n{appid}\n{timestamp}\n{body_hash}\n"
    p = os.getenv("GSALARY_CLIENT_PRIVATE_KEY_PATH")
    pem = None
    if p:
        try:
            with open(p, "rb") as f:
                pem = f.read().decode("utf-8")
        except Exception:
            pem = None
    if not pem:
        raise HTTPException(status_code=500, detail="missing client private key")
    try:
        priv = rsa.PrivateKey.load_pkcs1(pem.encode("utf-8"))
    except Exception:
        raise HTTPException(status_code=500, detail="invalid client private key")
    sig_bytes = rsa.sign(sign_base.encode("utf-8"), priv, "SHA-256")
    sig_b64 = base64.b64encode(sig_bytes).decode()
    sig_url = urllib.parse.quote(sig_b64, safe="")
    headers = {"Authorization": f"algorithm=RSA2,time={timestamp},signature={sig_url}", "X-Appid": appid}
    if method.upper() == "POST":
        headers["Content-Type"] = "application/json"
    rid = getattr(request.state, "request_id", None)
    if rid:
        headers["Request-Id"] = rid
    if method.upper() == "GET":
        import urllib.parse as _up
        qs = _up.urlencode(payload)
        url = base_url + path + ("?" + qs if qs else "")
        with httpx.Client(timeout=10.0) as client:
            resp = client.get(url, headers=headers)
    else:
        url = base_url + path
        with httpx.Client(timeout=10.0) as client:
            resp = client.post(url, json=payload, headers=headers)
    resp.raise_for_status()
    ok = _verify_signature_rsa2(resp.headers.get("Authorization"), resp.headers.get("X-Appid"), method, path, resp.text)
    if not ok:
        raise HTTPException(status_code=401, detail="invalid gateway signature")
    data = resp.json()
    code = data.get("result", {}).get("result")
    msg = data.get("result", {}).get("message") or None
    env_data = data.get("data") or {}
    if code in (None, "S", "s"):
        pass
    else:
        if code in (0, 200):
            pass
        else:
            if code is None:
                code = data.get("code")
                msg = msg or data.get("msg") or env_data.get("err_msg") or "gateway error"
            raise HTTPException(status_code=_status_for_gateway_error(code, msg or "gateway error"), detail=(msg or "gateway error"))
    return env_data


ALIAS_ENVELOPE_ROUTES: set[tuple[str, str]] = {
    ("POST", "/orders/list"),
    ("POST", "/orders/detail"),
    ("POST", "/orders/consumption"),
    ("POST", "/orders/refund-by-id"),
    # Bundle alias endpoints
    ("POST", "/bundle/countries"),
    ("POST", "/bundle/regions"),
    ("POST", "/bundle/list"),
    ("POST", "/bundle/networks"),
    ("POST", "/bundle/assign"),
    # Agent alias endpoints
    ("POST", "/agent/account"),
    ("POST", "/agent/bills"),
}

def _is_alias_envelope(request: Request) -> bool:
    """Alias routes that should use upstream-style envelope semantics (method+path)."""
    return (request.method, request.url.path) in ALIAS_ENVELOPE_ROUTES


@app.exception_handler(RequestValidationError)
async def handle_validation_error(request: Request, exc: RequestValidationError):
    # For alias routes, wrap as envelope; otherwise use standard 422.
    if _is_alias_envelope(request):
        return _json_envelope({"code": 422, "data": {}, "msg": "invalid request"}, request)
    return JSONResponse(status_code=422, content={"detail": exc.errors()})


@app.exception_handler(ProviderError)
async def handle_provider_error(request: Request, exc: ProviderError):
    # For alias routes, wrap as envelope; otherwise return mapped HTTP status.
    if _is_alias_envelope(request):
        return _json_envelope({"code": 200, "data": {"err_code": exc.code, "err_msg": exc.msg}, "msg": ""}, request)
    return JSONResponse(status_code=exc.http_status, content={"detail": exc.msg})


@app.exception_handler(Exception)
async def handle_generic_error(request: Request, exc: Exception):
    # For alias routes, wrap generics as envelope; otherwise 500.
    if _is_alias_envelope(request):
        return _json_envelope({"code": 200, "data": {"err_code": 500, "err_msg": str(exc)}, "msg": ""}, request)
    return JSONResponse(status_code=500, content={"detail": "Internal Server Error"})


@app.post("/orders", response_model=OrderDTO)
async def create_order(body: CreateOrderBody, current_user: ORMUser = Depends(get_current_user)):
    try:
        return service.create_order(body, user_id=current_user.id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/orders", response_model=list[OrderDTO])
async def list_orders(
    request: Request,
    response: Response,
    current_user: ORMUser = Depends(get_current_user),
    page: Annotated[int, Query(ge=1)] = 1,
    pageSize: Annotated[int, Query(ge=1, le=100)] = 20,
    sortBy: Literal["createdAt", "amount", "status"] | None = None,
    sortDir: Literal["asc", "desc"] | None = None,
):
    req_id = getattr(request.state, "request_id", None)
    results = service.list_orders(
        user_id=current_user.id,
        page=page,
        page_size=pageSize,
        sort_by=sortBy,
        sort_dir=sortDir,
    )
    response.headers["X-Page"] = str(page)
    response.headers["X-Page-Size"] = str(pageSize)
    response.headers["X-Has-Next"] = "true" if len(results) == int(pageSize) else "false"
    if sortBy:
        response.headers["X-Sort-By"] = sortBy
        response.headers["X-Sort-Dir"] = (sortDir or "desc")
    return results


@app.get("/orders/{order_id}", response_model=OrderDTO)
async def get_order(request: Request, order_id: str, current_user: ORMUser = Depends(get_current_user)):
    req_id = getattr(request.state, "request_id", None)
    order = service.get_order(order_id, user_id=current_user.id, request_id=req_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return order


@app.get("/orders/{order_id}/usage", response_model=UsageDTO)
async def get_usage(request: Request, order_id: str, current_user: ORMUser = Depends(get_current_user)):
    req_id = getattr(request.state, "request_id", None)
    usage = service.get_usage(order_id, request_id=req_id)
    if not usage:
        raise HTTPException(status_code=404, detail="Usage not found")
    return usage


@app.post("/orders/list")
async def post_orders_list(request: Request, body: OrdersListQuery, current_user: ORMUser = Depends(get_current_user)):
    req_id = getattr(request.state, "request_id", None)
    # Dev-only bypass for demo/testing: X-Dev-All=1 or env ORDERS_DEV_ALL=true
    dev_all = False
    try:
        dev_all = (request.headers.get("X-Dev-All", "0") == "1") or (os.getenv("ORDERS_DEV_ALL", "false").lower() in ("1", "true", "yes"))
    except Exception:
        dev_all = False
    data = service.orders_list_v2(
        body,
        request_id=req_id,
        user_email=(current_user.email or ""),
        user_id=current_user.id,
        dev_all=dev_all,
    )
    l = resolve_language(None, request.headers.get("Accept-Language"), request.headers.get("X-Language"), getattr(current_user, "language", None))
    try:
        orders = list(data.get("orders", []))
    except Exception:
        orders = []
    for o in orders:
        code = str(o.get("bundle_code") or "").strip()
        mkt = translate_marketing(o.get("bundle_marketing_name") or o.get("bundle_name"), l, code)
        amt = o.get("gprs_limit")
        unit = o.get("data_unit")
        try:
            validity = int(float(str(o.get("validity") or "0")))
        except Exception:
            validity = None
        unlimited = bool(o.get("unlimited")) if o.get("unlimited") is not None else None
        o["bundle_marketing_name"] = mkt
        o["bundle_name"] = translate_bundle_name(o.get("bundle_name"), l, bundle_code=code, amount=amt, unit=unit, validity_days=validity, marketing_name=mkt, unlimited=unlimited)
        try:
            cc = list(o.get("country_code") or [])
            if cc:
                o["country_name"] = [translate_country(c, None, l) for c in cc]
        except Exception:
            pass
    data = {"orders": orders, "orders_count": int(data.get("orders_count") or len(orders))}
    return _json_envelope({"code": 200, "data": jsonable_encoder(data), "msg": ""}, request)

@app.post("/orders/list-normalized", response_model=list[OrderDTO])
async def post_orders_list_normalized(request: Request, body: OrdersListNormalizedQuery, current_user: ORMUser = Depends(get_current_user)):
    req_id = getattr(request.state, "request_id", None)
    dev_all = False
    try:
        dev_all = (request.headers.get("X-Dev-All", "0") == "1") or (os.getenv("ORDERS_DEV_ALL", "false").lower() in ("1", "true", "yes"))
    except Exception:
        dev_all = False
    return service.orders_list_normalized(body, request_id=req_id, user_email=(current_user.email or ""), user_id=current_user.id, dev_all=dev_all)

@app.post("/orders/list-with-usage")
async def post_orders_list_with_usage(request: Request, body: OrdersListWithUsageQuery, current_user: ORMUser = Depends(get_current_user)):
    req_id = getattr(request.state, "request_id", None)
    max_usage = None
    if request.headers.get("X-Fast-Orders", "0") == "1":
        max_usage = 0
    else:
        v = request.headers.get("X-Fetch-Usage")
        if v is not None:
            try:
                max_usage = int(v)
            except Exception:
                max_usage = None
    data = service.orders_list_with_usage(
        body,
        request_id=req_id,
        user_email=(current_user.email or ""),
        user_id=current_user.id,
        max_usage=max_usage,
        dev_all=(request.headers.get("X-Dev-All", "0") == "1" or (os.getenv("ORDERS_DEV_ALL", "false").lower() in ("1", "true", "yes"))),
    )
    if not isinstance(data, dict):
        data = {"items": [], "orders_count": 0}
    else:
        try:
            l = resolve_language(None, request.headers.get("Accept-Language"), request.headers.get("X-Language"), getattr(current_user, "language", None))
            from .i18n import translate_plan_status
            items = list(data.get("items") or [])
            for it in items:
                u = dict((it or {}).get("usage") or {})
                ps = u.get("plan_status")
                if ps is not None:
                    u["plan_status_localized"] = translate_plan_status(ps, l)
                it["usage"] = u
            data = {"items": items, "orders_count": data.get("orders_count")}
        except Exception:
            pass
    return _json_envelope({"code": 200, "data": jsonable_encoder(data), "msg": ""}, request)


@app.post("/orders/detail")
async def post_orders_detail(request: Request, body: OrdersDetailQuery, current_user: ORMUser = Depends(get_current_user)):
    """Upstream-compatible order detail: returns {code, data, msg} envelope.

    data includes: order_id, order_status, bundle_category, bundle_code, bundle_marketing_name,
    bundle_name, country_code, country_name, order_reference, activation_code,
    bundle_expiry_date, expiry_date, iccid, plan_started, plan_status, date_created
    """
    req_id = getattr(request.state, "request_id", None)
    data = service.orders_detail_v2(body, request_id=req_id)
    l = resolve_language(None, request.headers.get("Accept-Language"), request.headers.get("X-Language"), getattr(current_user, "language", None))
    if isinstance(data, dict) and data:
        code = str(data.get("bundle_code") or "").strip()
        mkt = translate_marketing(data.get("bundle_marketing_name") or data.get("bundle_name"), l, code)
        amt = data.get("gprs_limit")
        unit = data.get("data_unit")
        try:
            validity = int(float(str(data.get("validity") or "0")))
        except Exception:
            validity = None
        unlimited = bool(data.get("unlimited")) if data.get("unlimited") is not None else None
        data["bundle_marketing_name"] = mkt
        data["bundle_name"] = translate_bundle_name(data.get("bundle_name"), l, bundle_code=code, amount=amt, unit=unit, validity_days=validity, marketing_name=mkt, unlimited=unlimited)
        try:
            cc = list(data.get("country_code") or [])
            if cc:
                data["country_name"] = [translate_country(c, None, l) for c in cc]
        except Exception:
            pass
        try:
            rc = str(data.get("region_code") or "").strip().lower()
            rn = data.get("region_name")
            if rc:
                data["region_name"] = translate_region(rc, rn, l)
        except Exception:
            pass
    return _json_envelope({"code": 200, "data": jsonable_encoder(data), "msg": ""}, request)

@app.post("/orders/detail-by-id")
async def post_orders_detail_by_id(request: Request, body: OrdersDetailByIdQuery, current_user: ORMUser = Depends(get_current_user)):
    req_id = getattr(request.state, "request_id", None)
    data = service.orders_detail_by_id_v2(order_id=body.order_id, request_id=req_id)
    l = resolve_language(None, request.headers.get("Accept-Language"), request.headers.get("X-Language"), getattr(current_user, "language", None))
    if isinstance(data, dict) and data:
        code = str(data.get("bundle_code") or "").strip()
        mkt = translate_marketing(data.get("bundle_marketing_name") or data.get("bundle_name"), l, code)
        amt = data.get("gprs_limit")
        unit = data.get("data_unit")
        try:
            validity = int(float(str(data.get("validity") or "0")))
        except Exception:
            validity = None
        unlimited = bool(data.get("unlimited")) if data.get("unlimited") is not None else None
        data["bundle_marketing_name"] = mkt
        data["bundle_name"] = translate_bundle_name(data.get("bundle_name"), l, bundle_code=code, amount=amt, unit=unit, validity_days=validity, marketing_name=mkt, unlimited=unlimited)
        try:
            cc = list(data.get("country_code") or [])
            if cc:
                data["country_name"] = [translate_country(c, None, l) for c in cc]
        except Exception:
            pass
        try:
            rc = str(data.get("region_code") or "").strip().lower()
            rn = data.get("region_name")
            if rc:
                data["region_name"] = translate_region(rc, rn, l)
        except Exception:
            pass
    return _json_envelope({"code": 200, "data": jsonable_encoder(data), "msg": ""}, request)

@app.post("/orders/detail-normalized")
async def post_orders_detail_normalized(request: Request, body: OrdersDetailNormalizedQuery, current_user: ORMUser = Depends(get_current_user)):
    req_id = getattr(request.state, "request_id", None)
    try:
        dto = service.orders_detail_normalized(body, request_id=req_id)
    except ValueError as e:
        # 包装为上游 envelope 风格错误
        return _json_envelope({"code": 404, "data": None, "msg": str(e)}, request)
    return _json_envelope({"code": 200, "data": jsonable_encoder(dto), "msg": ""}, request)


@app.post("/orders/consumption")
async def post_orders_consumption(request: Request, body: OrdersConsumptionQuery, current_user: ORMUser = Depends(get_current_user)):
    """Upstream-compatible order consumption: returns {code, data, msg} envelope.

    data.order includes usage fields like data_remaining, data_used, data_unit, minutes_*, sms_*, etc.
    """
    req_id = getattr(request.state, "request_id", None)
    data = service.orders_consumption_v2(body, request_id=req_id)
    l = resolve_language(None, request.headers.get("Accept-Language"), request.headers.get("X-Language"), getattr(current_user, "language", None))
    try:
        order = dict(data.get("order") or {})
        ps = order.get("plan_status")
        if ps is not None:
            from .i18n import translate_plan_status
            order["plan_status_localized"] = translate_plan_status(ps, l)
        data = {"order": order}
    except Exception:
        pass
    return _json_envelope({"code": 200, "data": jsonable_encoder(data), "msg": ""}, request)

@app.post("/orders/consumption-by-id")
async def post_orders_consumption_by_id(request: Request, body: OrdersConsumptionByIdQuery, current_user: ORMUser = Depends(get_current_user)):
    req_id = getattr(request.state, "request_id", None)
    data = service.orders_consumption_by_id_v2(body, request_id=req_id)
    l = resolve_language(None, request.headers.get("Accept-Language"), request.headers.get("X-Language"), getattr(current_user, "language", None))
    try:
        order = dict(data.get("order") or {})
        ps = order.get("plan_status")
        if ps is not None:
            from .i18n import translate_plan_status
            order["plan_status_localized"] = translate_plan_status(ps, l)
        data = {"order": order}
    except Exception:
        pass
    return _json_envelope({"code": 200, "data": jsonable_encoder(data), "msg": ""}, request)

@app.post("/orders/consumption/batch")
async def post_orders_consumption_batch(request: Request, body: OrdersConsumptionBatchQuery, current_user: ORMUser = Depends(get_current_user)):
    req_id = getattr(request.state, "request_id", None)
    data = service.orders_consumption_batch(body, request_id=req_id)
    l = resolve_language(None, request.headers.get("Accept-Language"), request.headers.get("X-Language"), getattr(current_user, "language", None))
    try:
        items = list((data or {}).get("items") or [])
        from .i18n import translate_plan_status
        for it in items:
            order = dict((it or {}).get("usage") or {})
            ps = order.get("plan_status")
            if ps is not None:
                order["plan_status_localized"] = translate_plan_status(ps, l)
            it["usage"] = order
        data = {"items": items}
    except Exception:
        pass
    return _json_envelope({"code": 200, "data": jsonable_encoder(data), "msg": ""}, request)


# ===== Init stable mappings for current user (order_reference/provider_order_id → user_id) =====
@app.post("/orders/mappings/init")
async def init_order_mappings(request: Request, current_user: ORMUser = Depends(get_current_user)):
    req_id = getattr(request.state, "request_id", None)
    data = service.init_mappings_for_user(current_user.id, request_id=req_id)
    return _json_envelope({"code": 200, "data": jsonable_encoder(data), "msg": ""}, request)


# ===== Auth =====
@app.post("/auth/register", response_model=AuthResponseDTO)
async def register(body: RegisterBody):
    try:
        return auth_service.register(body)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/auth/login", response_model=AuthResponseDTO)
async def login(body: LoginBody):
    result = auth_service.login(body)
    if not result:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return result


@app.post("/auth/apple", response_model=AuthResponseDTO)
async def login_apple(body: AppleLoginBody):
    return auth_service.login_apple(body)


@app.post("/auth/password-reset", response_model=ResetDTO)
async def password_reset(body: PasswordResetBody):
    return auth_service.password_reset(body.email)


@app.post("/auth/password-reset/confirm", response_model=SuccessDTO)
async def password_reset_confirm(body: PasswordResetConfirmBody):
    try:
        return auth_service.confirm_password_reset(body.token, body.newPassword)
    except ValueError as e:
        msg = str(e)
        if msg == "weak_password":
            raise HTTPException(status_code=400, detail="密码至少需要 8 位")
        if msg == "token_invalid":
            raise HTTPException(status_code=400, detail="重置令牌无效")
        if msg == "token_expired":
            raise HTTPException(status_code=400, detail="重置令牌已过期，请重新请求")
        if msg == "token_used":
            raise HTTPException(status_code=400, detail="重置令牌已被使用")
        raise HTTPException(status_code=400, detail="重置失败")


@app.post("/auth/email-code", response_model=EmailCodeDTO)
async def request_email_code(body: EmailCodeRequestBody):
    # 注册与改邮箱均可匿名请求验证码；后端不暴露邮箱有效性
    return auth_service.request_email_code(email=body.email, purpose=body.purpose)


@app.post("/auth/refresh", response_model=AuthResponseDTO)
async def refresh_tokens(body: RefreshBody):
    result = auth_service.refresh_tokens(body.refreshToken)
    if not result:
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    return result


@app.post("/auth/logout")
async def logout(body: LogoutBody):
    ok = auth_service.revoke_refresh_token(body.refreshToken)
    return {"success": bool(ok)}


# ===== Catalog =====
@app.get("/catalog/countries", response_model=list[CountryDTO])
async def get_countries(request: Request, response: Response, lang: str | None = None):
    req_id = getattr(request.state, "request_id", None)
    items = catalog_service.get_countries(request_id=req_id)
    l = resolve_language(lang, request.headers.get("Accept-Language"), request.headers.get("X-Language"), None)
    result = [CountryDTO(code=c.code, name=translate_country(c.code, c.name, l)) for c in items]
    payload = "|".join([f"{c.code}:{c.name}" for c in result])
    etag = hashlib.md5(payload.encode("utf-8")).hexdigest()
    inm = request.headers.get("If-None-Match")
    response.headers["Cache-Control"] = "public, max-age=3600, stale-while-revalidate=3600"
    response.headers["Vary"] = "Accept-Language, X-Language"
    response.headers["ETag"] = etag
    if inm == etag:
        return Response(status_code=304)
    return jsonable_encoder(result)

@app.post("/bundle/countries")
async def post_bundle_countries(request: Request, lang: str | None = None):
    req_id = getattr(request.state, "request_id", None)
    data = catalog_service.get_countries_alias(request_id=req_id)
    l = resolve_language(lang, request.headers.get("Accept-Language"), request.headers.get("X-Language"), None)
    for c in data.countries:
        c.country_name = translate_country(c.iso2_code, c.country_name, l)
    return _json_envelope({"code": 200, "data": jsonable_encoder(data), "msg": ""}, request)


@app.get("/catalog/regions", response_model=list[RegionDTO])
async def get_regions(request: Request, response: Response, lang: str | None = None):
    req_id = getattr(request.state, "request_id", None)
    items = catalog_service.get_regions(request_id=req_id)
    l = resolve_language(lang, request.headers.get("Accept-Language"), request.headers.get("X-Language"), None)
    result = [RegionDTO(code=r.code, name=translate_region(r.code, r.name, l)) for r in items]
    payload = "|".join([f"{r.code}:{r.name}" for r in result])
    etag = hashlib.md5(payload.encode("utf-8")).hexdigest()
    inm = request.headers.get("If-None-Match")
    response.headers["Cache-Control"] = "public, max-age=3600, stale-while-revalidate=3600"
    response.headers["Vary"] = "Accept-Language, X-Language"
    response.headers["ETag"] = etag
    if inm == etag:
        return Response(status_code=304)
    return jsonable_encoder(result)

@app.post("/bundle/regions")
async def post_bundle_regions(request: Request, lang: str | None = None):
    req_id = getattr(request.state, "request_id", None)
    data = catalog_service.get_regions_alias(request_id=req_id)
    l = resolve_language(lang, request.headers.get("Accept-Language"), request.headers.get("X-Language"), None)
    for r in data.regions:
        r.region_name = translate_region(r.region_code, r.region_name, l)
    return _json_envelope({"code": 200, "data": jsonable_encoder(data), "msg": ""}, request)

@app.get("/search", response_model=list[SearchResultDTO])
async def search(
    request: Request,
    q: str,
    include: str | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    dedupe: bool = False,
    lang: str | None = None,
):
    req_id = getattr(request.state, "request_id", None)
    include_list = None
    if include:
        include_list = [s.strip().lower() for s in include.split(",") if s.strip()]
    l = resolve_language(lang, request.headers.get("Accept-Language"), request.headers.get("X-Language"), None)
    results = catalog_service.search(q=q, include=include_list, limit=limit, dedupe=dedupe, lang=l, request_id=req_id)
    localized: list[SearchResultDTO] = []
    for r in results:
        if r.kind == "country":
            t = translate_country(r.id, r.title, l)
        elif r.kind == "region":
            t = translate_region(r.id, r.title, l)
        else:
            t = translate_marketing(r.title, l, r.bundleCode)
        localized.append(SearchResultDTO(kind=r.kind, id=r.id, title=t, subtitle=r.subtitle, countryCode=r.countryCode, regionCode=r.regionCode, bundleCode=r.bundleCode))
    return localized

@app.get("/catalog/bundles", response_model=list[BundleDTO])
async def get_bundles(request: Request, response: Response, country: str | None = None, popular: bool = False, lang: str | None = None):
    items = catalog_service.get_bundles(country=country, popular=popular)
    l = resolve_language(lang, request.headers.get("Accept-Language"), request.headers.get("X-Language"), None)
    localized: list[BundleDTO] = []
    for b in items:
        amt = None
        unit = None
        try:
            s = str(b.dataAmount or "")
            import re as _re
            m = _re.search(r"(?i)(\d+(?:\.\d+)?)\s*([kmgt]?b?)", s)
            if m:
                a = float(m.group(1))
                u = m.group(2).upper()
                if u in ("G", "GB"):
                    amt = a
                    unit = "GB"
                elif u in ("M", "MB"):
                    amt = a
                    unit = "MB"
                elif u in ("K", "KB"):
                    amt = a
                    unit = "KB"
        except Exception:
            pass
        localized.append(BundleDTO(
            id=b.id,
            name=translate_bundle_name(b.name, l, b.id, amt, unit, b.validityDays, b.name),
            countryCode=b.countryCode,
            price=b.price,
            currency=b.currency,
            dataAmount=b.dataAmount,
            validityDays=b.validityDays,
            description=(translate_marketing(b.description, l, b.id) if b.description else None),
            supportedNetworks=b.supportedNetworks,
            hotspotSupported=b.hotspotSupported,
            coverageNote=b.coverageNote,
            termsUrl=b.termsUrl,
        ))
    payload = "|".join([
        ":".join([
            str(x.id),
            str(x.name),
            str(x.countryCode),
            str(x.price),
            str(x.currency),
            str(x.dataAmount),
            str(x.validityDays),
            str(x.hotspotSupported),
            str(x.termsUrl),
        ])
        for x in localized
    ])
    etag = hashlib.md5(payload.encode("utf-8")).hexdigest()
    inm = request.headers.get("If-None-Match")
    response.headers["Cache-Control"] = "public, max-age=3600, stale-while-revalidate=3600"
    response.headers["Vary"] = "Accept-Language, X-Language"
    response.headers["ETag"] = etag
    if inm == etag:
        return Response(status_code=304)
    return jsonable_encoder(localized)


@app.get("/catalog/bundles/{bundle_id}", response_model=BundleDTO)
async def get_bundle(request: Request, bundle_id: str, lang: str | None = None):
    b = catalog_service.get_bundle(bundle_id)
    if not b:
        raise HTTPException(status_code=404, detail="Bundle not found")
    l = resolve_language(lang, request.headers.get("Accept-Language"), request.headers.get("X-Language"), None)
    amt = None
    unit = None
    try:
        s = str(b.dataAmount or "")
        import re as _re
        m = _re.search(r"(?i)(\d+(?:\.\d+)?)\s*([kmgt]?b?)", s)
        if m:
            a = float(m.group(1))
            u = m.group(2).upper()
            if u in ("G", "GB"):
                amt = a
                unit = "GB"
            elif u in ("M", "MB"):
                amt = a
                unit = "MB"
            elif u in ("K", "KB"):
                amt = a
                unit = "KB"
    except Exception:
        pass
    return BundleDTO(
        id=b.id,
        name=translate_bundle_name(b.name, l, b.id, amt, unit, b.validityDays, b.name),
        countryCode=b.countryCode,
        price=b.price,
        currency=b.currency,
        dataAmount=b.dataAmount,
        validityDays=b.validityDays,
        description=(translate_marketing(b.description, l, b.id) if b.description else None),
        supportedNetworks=b.supportedNetworks,
        hotspotSupported=b.hotspotSupported,
        coverageNote=b.coverageNote,
        termsUrl=b.termsUrl,
    )

@app.get("/catalog/bundle/{bundle_id}", response_model=BundleDTO)
async def get_bundle_alias(request: Request, bundle_id: str, lang: str | None = None):
    b = catalog_service.get_bundle(bundle_id)
    if not b:
        raise HTTPException(status_code=404, detail="Bundle not found")
    l = resolve_language(lang, request.headers.get("Accept-Language"), request.headers.get("X-Language"), None)
    amt = None
    unit = None
    try:
        s = str(b.dataAmount or "")
        import re as _re
        m = _re.search(r"(?i)(\d+(?:\.\d+)?)\s*([kmgt]?b?)", s)
        if m:
            a = float(m.group(1))
            u = m.group(2).upper()
            if u in ("G", "GB"):
                amt = a
                unit = "GB"
            elif u in ("M", "MB"):
                amt = a
                unit = "MB"
            elif u in ("K", "KB"):
                amt = a
                unit = "KB"
    except Exception:
        pass
    return BundleDTO(
        id=b.id,
        name=translate_bundle_name(b.name, l, b.id, amt, unit, b.validityDays, b.name),
        countryCode=b.countryCode,
        price=b.price,
        currency=b.currency,
        dataAmount=b.dataAmount,
        validityDays=b.validityDays,
        description=(translate_marketing(b.description, l, b.id) if b.description else None),
        supportedNetworks=b.supportedNetworks,
        hotspotSupported=b.hotspotSupported,
        coverageNote=b.coverageNote,
        termsUrl=b.termsUrl,
    )


@app.get("/catalog/bundles/{bundle_id}", response_model=BundleDTO)
async def get_bundle(bundle_id: str):
    b = catalog_service.get_bundle(bundle_id)
    if not b:
        raise HTTPException(status_code=404, detail="Bundle not found")
    return b

@app.get("/catalog/bundles/{bundle_id}/networks", response_model=list[str])
async def get_bundle_networks(bundle_id: str, request: Request, response: Response):
    networks = catalog_service.get_bundle_networks(bundle_id)
    if not networks:
        raise HTTPException(status_code=404, detail="Bundle networks not found")
    payload = "|".join([str(x) for x in networks])
    import hashlib as _hashlib
    etag = _hashlib.md5(payload.encode("utf-8")).hexdigest()
    inm = request.headers.get("If-None-Match")
    response.headers["Cache-Control"] = "public, max-age=86400"
    response.headers["ETag"] = etag
    if inm == etag:
        return Response(status_code=304)
    return jsonable_encoder(networks)

@app.post("/bundle/list")
async def post_bundle_list(request: Request, body: BundleListQuery, lang: str | None = None):
    req_id = getattr(request.state, "request_id", None)
    data = catalog_service.bundle_list(
        page_number=body.page_number,
        page_size=body.page_size,
        country_code=body.country_code,
        region_code=body.region_code,
        bundle_category=body.bundle_category,
        sort_by=body.sort_by,
        bundle_code=body.bundle_code,
        q=body.q,
        request_id=req_id,
    )
    l = resolve_language(lang, request.headers.get("Accept-Language"), request.headers.get("X-Language"), None)
    bundles = data.get("bundles") or []
    for b in bundles:
        cat = str(b.get("bundle_category") or "").strip().lower()
        if cat == "country":
            codes = b.get("country_code") or []
            code = str(codes[0] if codes else "")
            b["bundle_marketing_name"] = translate_country(code, b.get("bundle_marketing_name"), l)
        else:
            b["bundle_marketing_name"] = translate_marketing(b.get("bundle_marketing_name"), l, b.get("bundle_code"))
        amt = b.get("gprs_limit")
        unit = b.get("data_unit")
        try:
            val = int(float(str(b.get("validity") or 0)))
        except Exception:
            val = None
        b["bundle_name"] = translate_bundle_name(
            b.get("bundle_name"),
            l,
            b.get("bundle_code"),
            amt,
            unit,
            val,
            b.get("bundle_marketing_name"),
            b.get("unlimited"),
        )
        rc = b.get("region_code")
        b["region_name"] = translate_region(rc, b.get("region_name"), l)
        codes = b.get("country_code") or []
        names = []
        cnames = b.get("country_name") or []
        for idx, code in enumerate(codes):
            name = cnames[idx] if idx < len(cnames) else None
            names.append(translate_country(code, name, l))
        b["country_name"] = names
    return _json_envelope({"code": 200, "data": jsonable_encoder({"bundles": bundles, "bundles_count": data.get("bundles_count")}), "msg": ""}, request)

@app.get("/search")
async def get_search(
    request: Request,
    q: str,
    include: str | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    dedupe: bool = True,
    lang: str | None = None,
):
    req_id = getattr(request.state, "request_id", None)
    inc_list = [s.strip() for s in (include.split(",") if include else ["country", "region", "bundle"]) if s.strip()]
    l = resolve_language(lang, request.headers.get("Accept-Language"), request.headers.get("X-Language"), None)
    results = catalog_service.search(q=q, include=inc_list, limit=limit, dedupe=dedupe, lang=l, request_id=req_id)
    localized: list[SearchResultDTO] = []
    for r in results:
        if r.kind == "country":
            t = translate_country(r.id, r.title, l)
        elif r.kind == "region":
            t = translate_region(r.id, r.title, l)
        else:
            t = translate_marketing(r.title, l, r.bundleCode)
        localized.append(SearchResultDTO(kind=r.kind, id=r.id, title=t, subtitle=r.subtitle, countryCode=r.countryCode, regionCode=r.regionCode, bundleCode=r.bundleCode))
    return _json_envelope({"code": 200, "data": jsonable_encoder(localized), "msg": ""}, request)

@app.post("/search/log", response_model=SuccessDTO)
async def post_search_log(request: Request, body: SearchLogBody, current_user: ORMUser = Depends(get_current_user)):
    db = _get_db()
    try:
        kind = (body.kind or "").strip()
        if not kind:
            raise HTTPException(status_code=400, detail="kind required")
        ent = None
        if kind == "country":
            ent = (body.countryCode or body.id or "").strip()
        elif kind == "region":
            ent = (body.regionCode or body.id or "").strip()
        else:
            ent = (body.bundleCode or body.id or "").strip()
        if not ent:
            raise HTTPException(status_code=400, detail="id required")
        row = db.query(RecentSearch).filter(RecentSearch.user_id == current_user.id, RecentSearch.kind == kind, RecentSearch.entity_id == ent).first()
        now = datetime.utcnow()
        if row:
            row.hits = int(row.hits or 0) + 1
            row.last_seen = now
            row.bundle_code = body.bundleCode or row.bundle_code
            row.country_code = body.countryCode or row.country_code
            row.region_code = body.regionCode or row.region_code
            row.title_snapshot = body.title or row.title_snapshot
            row.subtitle_snapshot = body.subtitle or row.subtitle_snapshot
            db.add(row)
        else:
            db.add(RecentSearch(user_id=current_user.id, kind=kind, entity_id=ent, bundle_code=body.bundleCode, country_code=body.countryCode, region_code=body.regionCode, title_snapshot=body.title, subtitle_snapshot=body.subtitle, hits=1, last_seen=now))
        db.commit()
        return SuccessDTO(success=True)
    finally:
        db.close()

@app.get("/search/recent", response_model=list[SearchResultDTO])
async def get_search_recent(request: Request, limit: int = 10, sort: Literal["recent", "hits"] = "recent", lang: str | None = None, current_user: ORMUser = Depends(get_current_user)):
    db = _get_db()
    try:
        limit = max(1, min(50, int(limit)))
        q = db.query(RecentSearch).filter(RecentSearch.user_id == current_user.id)
        if sort == "hits":
            q = q.order_by(RecentSearch.hits.desc(), RecentSearch.last_seen.desc())
        else:
            q = q.order_by(RecentSearch.last_seen.desc())
        rows = q.limit(limit).all()
        l = resolve_language(lang, request.headers.get("Accept-Language"), request.headers.get("X-Language"), getattr(current_user, "language", None))
        localized: list[SearchResultDTO] = []
        for r in rows:
            if r.kind == "country":
                t = translate_country(r.country_code or r.entity_id, r.title_snapshot, l)
                localized.append(SearchResultDTO(kind="country", id=r.entity_id, title=t, subtitle=r.subtitle_snapshot, countryCode=r.country_code or r.entity_id))
            elif r.kind == "region":
                t = translate_region(r.region_code or r.entity_id, r.title_snapshot, l)
                localized.append(SearchResultDTO(kind="region", id=r.entity_id, title=t, subtitle=r.subtitle_snapshot, regionCode=r.region_code or r.entity_id))
            else:
                code = r.bundle_code or r.entity_id
                b = catalog_service.get_bundle(code)
                if b:
                    amt = None
                    unit = None
                    try:
                        s = str(b.dataAmount or "")
                        import re as _re
                        m = _re.search(r"(?i)(\d+(?:\.\d+)?)\s*([kmgt]?b?)", s)
                        if m:
                            a = float(m.group(1))
                            u = m.group(2).upper()
                            if u in ("G", "GB"):
                                amt = a
                                unit = "GB"
                            elif u in ("M", "MB"):
                                amt = a
                                unit = "MB"
                            elif u in ("K", "KB"):
                                amt = a
                                unit = "KB"
                    except Exception:
                        pass
                    t = translate_bundle_name(b.name, l, code, amt, unit, b.validityDays, b.name)
                else:
                    t = translate_marketing(r.title_snapshot or code, l, code)
                localized.append(SearchResultDTO(kind="bundle", id=r.entity_id, title=t, subtitle=r.subtitle_snapshot, bundleCode=code))
        return localized
    finally:
        db.close()

@app.delete("/search/recent", response_model=SuccessDTO)
async def delete_search_recent_all(current_user: ORMUser = Depends(get_current_user)):
    db = _get_db()
    try:
        db.query(RecentSearch).filter(RecentSearch.user_id == current_user.id).delete()
        db.commit()
        return SuccessDTO(success=True)
    finally:
        db.close()

@app.delete("/search/recent/{kind}/{entity_id}", response_model=SuccessDTO)
async def delete_search_recent_item(kind: Literal["country", "region", "bundle"], entity_id: str, current_user: ORMUser = Depends(get_current_user)):
    db = _get_db()
    try:
        db.query(RecentSearch).filter(RecentSearch.user_id == current_user.id, RecentSearch.kind == kind, RecentSearch.entity_id == entity_id).delete()
        db.commit()
        return SuccessDTO(success=True)
    finally:
        db.close()

@app.post("/bundle/detail-by-code")
async def post_bundle_detail_by_code(request: Request, body: BundleCodeQuery, lang: str | None = None):
    req_id = getattr(request.state, "request_id", None)
    b = catalog_service.get_bundle_by_code(bundle_code=body.bundle_code, request_id=req_id)
    if not b:
        return _json_envelope({"code": 404, "data": jsonable_encoder({}), "msg": "Bundle not found"}, request)
    l = resolve_language(lang, request.headers.get("Accept-Language"), request.headers.get("X-Language"), None)
    # Build localized name using bundle_code and structured fields when possible
    amt = None
    unit = None
    try:
        parts = (b.dataAmount or "").split()
        if len(parts) >= 2:
            amt = float(parts[0])
            unit = parts[-1]
    except Exception:
        pass
    localized = BundleDTO(
        id=b.id,
        name=translate_bundle_name(b.name, l, b.id, amt, unit, b.validityDays, b.name),
        countryCode=b.countryCode,
        price=b.price,
        currency=b.currency,
        dataAmount=b.dataAmount,
        validityDays=b.validityDays,
        description=(translate_marketing(b.description, l, b.id) if b.description else None),
        supportedNetworks=b.supportedNetworks,
        hotspotSupported=b.hotspotSupported,
        coverageNote=b.coverageNote,
        termsUrl=b.termsUrl,
    )
    return _json_envelope({"code": 200, "data": jsonable_encoder(localized), "msg": ""}, request)

# ===== i18n 管理接口 =====
@app.post("/i18n/countries/upsert", response_model=SuccessDTO)
async def i18n_countries_upsert(body: I18nCountryUpsertBody):
    db = SessionLocal()
    try:
        for item in body.items:
            iso2 = (item.iso2_code or "").upper() or None
            iso3 = (item.iso3_code or "").upper() or None
            lang = item.lang_code
            name = item.name
            logo = item.logo
            row = None
            if iso2:
                row = db.query(I18nCountryName).filter(I18nCountryName.iso2_code == iso2, I18nCountryName.lang_code == lang).first()
            if (not row) and iso3:
                row = db.query(I18nCountryName).filter(I18nCountryName.iso3_code == iso3, I18nCountryName.lang_code == lang).first()
            if row:
                row.name = name
                row.logo = logo
                db.add(row)
            else:
                db.add(I18nCountryName(iso2_code=iso2, iso3_code=iso3, lang_code=lang, name=name, logo=logo))
        db.commit()
        return SuccessDTO(success=True)
    finally:
        db.close()

@app.post("/i18n/regions/upsert", response_model=SuccessDTO)
async def i18n_regions_upsert(body: I18nRegionUpsertBody):
    db = SessionLocal()
    try:
        for item in body.items:
            code = (item.region_code or "").lower()
            lang = item.lang_code
            name = item.name
            row = db.query(I18nRegionName).filter(I18nRegionName.region_code == code, I18nRegionName.lang_code == lang).first()
            if row:
                row.name = name
                db.add(row)
            else:
                db.add(I18nRegionName(region_code=code, lang_code=lang, name=name))
        db.commit()
        return SuccessDTO(success=True)
    finally:
        db.close()

@app.post("/i18n/bundles/upsert", response_model=SuccessDTO)
async def i18n_bundles_upsert(body: I18nBundleUpsertBody):
    db = SessionLocal()
    try:
        for item in body.items:
            code = (item.bundle_code or "").strip()
            lang = item.lang_code
            row = db.query(I18nBundleName).filter(I18nBundleName.bundle_code == code, I18nBundleName.lang_code == lang).first()
            if row:
                if item.marketing_name is not None:
                    row.marketing_name = item.marketing_name
                if item.name is not None:
                    row.name = item.name
                if item.description is not None:
                    row.description = item.description
                db.add(row)
            else:
                db.add(I18nBundleName(bundle_code=code, lang_code=lang, marketing_name=(item.marketing_name or ""), name=item.name, description=item.description))
        db.commit()
        return SuccessDTO(success=True)
    finally:
        db.close()


@app.post("/bundle/networks")
async def post_bundle_networks(request: Request, body: BundleNetworksQuery):
    req_id = getattr(request.state, "request_id", None)
    data = catalog_service.get_bundle_networks_v2(
        bundle_code=body.bundle_code,
        country_code=body.country_code,
        request_id=req_id,
    )
    return _json_envelope({"code": 200, "data": jsonable_encoder(data), "msg": ""}, request)

@app.post("/bundle/networks/flat")
async def post_bundle_networks_flat(request: Request, body: BundleNetworksFlatQuery):
    req_id = getattr(request.state, "request_id", None)
    data = catalog_service.get_bundle_operators_flat(bundle_code=body.bundle_code, country_code=body.country_code, request_id=req_id)
    return _json_envelope({"code": 200, "data": jsonable_encoder(data), "msg": ""}, request)


# ===== Agent =====
@app.get("/agent/account", response_model=AgentAccountDTO)
async def get_agent_account(request: Request):
    req_id = getattr(request.state, "request_id", None)
    acc = agent_service.get_account(request_id=req_id)
    if not acc:
        raise HTTPException(status_code=404, detail="Agent account not found")
    return acc


@app.post("/agent/account")
async def post_agent_account(request: Request):
    # Upstream uses POST; provide POST alias for compatibility
    req_id = getattr(request.state, "request_id", None)
    acc = agent_service.get_account(request_id=req_id)
    if not acc:
        raise HTTPException(status_code=404, detail="Agent account not found")
    return _json_envelope({"code": 200, "data": jsonable_encoder(acc), "msg": ""}, request)


@app.get("/agent/bills", response_model=AgentBillsDTO)
async def get_agent_bills(
    request: Request,
    page: Annotated[int, Query(ge=1)] = 1,
    pageSize: Annotated[int, Query(ge=10, le=100)] = 10,
    reference: str | None = None,
    startDate: str | None = None,
    endDate: str | None = None,
):
    req_id = getattr(request.state, "request_id", None)
    return agent_service.list_bills(
        page_number=page,
        page_size=pageSize,
        reference=reference,
        start_date=startDate,
        end_date=endDate,
        request_id=req_id,
    )


@app.post("/agent/bills")
async def post_agent_bills(request: Request, body: AgentBillsQuery):
    req_id = getattr(request.state, "request_id", None)
    data = agent_service.list_bills(
        page_number=body.page_number,
        page_size=body.page_size,
        reference=body.reference,
        start_date=body.start_date,
        end_date=body.end_date,
        request_id=req_id,
    )
    return _json_envelope({"code": 200, "data": jsonable_encoder(data), "msg": ""}, request)


@app.post("/bundle/assign")
async def post_bundle_assign(request: Request, body: BundleAssignBody, current_user: ORMUser = Depends(get_current_user)):
    req_id = getattr(request.state, "request_id", None)
    data = service.assign_bundle(
        bundle_code=body.bundle_code,
        order_reference=body.order_reference,
        name=body.name,
        email=body.email,
        request_id=req_id,
        user_id=current_user.id,
    )
    # Align with upstream spec: data should include snake_case keys {order_id, iccid}
    result = {"order_id": getattr(data, "orderId", None), "iccid": getattr(data, "iccid", None)}
    return _json_envelope({"code": 200, "data": jsonable_encoder(result), "msg": ""}, request)

class RefundBody(BaseModel):
    reason: str | None = None

@app.post("/orders/{order_id}/refund", response_model=RefundDTO)
async def refund_order(request: Request, order_id: str, body: RefundBody | None = None, current_user: ORMUser = Depends(get_current_user)):
    rid = getattr(request.state, "request_id", None)
    data = service.refund_order(order_id, reason=(body.reason if body else None), user_id=current_user.id, request_id=rid)
    return RefundDTO(**jsonable_encoder(data))

class RefundByIdBody(BaseModel):
    order_id: str = Field(..., alias="orderId")
    reason: str | None = None
    model_config = ConfigDict(populate_by_name=True)

@app.post("/orders/refund-by-id")
async def post_orders_refund_by_id(request: Request, body: RefundByIdBody, current_user: ORMUser = Depends(get_current_user)):
    rid = getattr(request.state, "request_id", None)
    data = service.refund_order(order_id=body.order_id, reason=(body.reason or None), user_id=current_user.id, request_id=rid)
    return _json_envelope({"code": 200, "data": jsonable_encoder(data), "msg": ""}, request)
class AlipayCreateBody(BaseModel):
    orderId: str

class AlipayCreateDTO(BaseModel):
    orderString: str

@app.post("/payments/alipay/create", response_model=AlipayCreateDTO)
async def payments_alipay_create(body: AlipayCreateBody, current_user: ORMUser = Depends(get_current_user)):
    order_str = f"ALIPAY|{body.orderId}"
    return AlipayCreateDTO(orderString=order_str)

class GsalaryCreateBody(BaseModel):
    orderId: str
    method: Literal["alipay", "card", "applepay", "paypal"]
    amount: float | None = None
    currency: str | None = None

class GsalaryCreateDTO(BaseModel):
    checkoutUrl: str
    paymentId: str
    paymentMethodId: str | None = None
    paymentRequestId: str | None = None

@app.post("/payments/gsalary/create", response_model=GsalaryCreateDTO)
async def payments_gsalary_create(request: Request, body: GsalaryCreateBody, current_user: ORMUser = Depends(get_current_user)):
    import uuid, time, hashlib
    import re
    base_url = os.getenv("GSALARY_BASE_URL", "").rstrip("/")
    def _clean_path(p: str) -> str:
        p = re.sub(r"\u200b", "", p)
        p = re.sub(r"/+", "/", p)
        p = p.replace("gateway/v1/gateway/v1/", "gateway/v1/")
        return p
    create_path = (os.getenv("GSALARY_CARD_CREATE_PATH") if body.method == "card" else os.getenv("GSALARY_CREATE_PATH")) or "/v1/gateway/v1/acquiring/pay_session"
    create_path = _clean_path(create_path)
    idem_key = request.headers.get("Idempotency-Key")
    notify_url = os.getenv("GSALARY_NOTIFY_URL", os.getenv("PUBLIC_BASE_URL", "").rstrip("/") + "/webhooks/payments")
    return_url = os.getenv("GSALARY_RETURN_URL", os.getenv("PUBLIC_BASE_URL", "").rstrip("/") + "/return/payments")
    # 支付渠道编码通过环境变量配置，避免与文档耦合
    paytype_alipay = os.getenv("GSALARY_PAYTYPE_ALIPAY", "ALIPAY_CN")
    paytype_card = os.getenv("GSALARY_PAYTYPE_CARD", "CARD")
    paytype_applepay = os.getenv("GSALARY_PAYTYPE_APPLEPAY", "APPLEPAY")
    paytype_paypal = os.getenv("GSALARY_PAYTYPE_PAYPAL", "PAYPAL")
    if body.method == "alipay":
        pay_type = paytype_alipay
    elif body.method == "applepay":
        pay_type = paytype_applepay
    elif body.method == "paypal":
        pay_type = paytype_paypal
    else:
        pay_type = paytype_card

    # 生成唯一请求号与时间戳
    terminal_trace = uuid.uuid4().hex[:32]
    terminal_time = time.strftime("%Y%m%d%H%M%S", time.gmtime())

    

    # 聚合网关常见字段（具体字段名以文档为准，可通过环境变量映射后调整）
    import datetime
    # 构造文档中的创建支付会话 payload
    mch_app_id = os.getenv("GSALARY_MCH_APP_ID", "")
    payment_request_id = f"PAY_{body.orderId.replace('-', '')[:20]}"
    session_expiry_min = int(os.getenv("GSALARY_SESSION_EXPIRY_MINUTES", "60"))
    expiry = (datetime.datetime.utcnow() + datetime.timedelta(minutes=session_expiry_min)).strftime("%Y-%m-%dT%H:%M:%SZ")
    product_scene = os.getenv("GSALARY_PRODUCT_SCENE", "CHECKOUT_PAYMENT")
    payload = {
        "mch_app_id": mch_app_id,
        "payment_request_id": payment_request_id,
        "payment_currency": body.currency or "CNY",
        "payment_amount": round((body.amount or 0.0), 2),
        "payment_method_type": pay_type,
        "payment_session_expiry_time": expiry,
        "notify_url": notify_url,
        "order": {
            "reference_order_id": body.orderId,
            "order_description": "Simigo eSIM purchase",
            "order_currency": body.currency or "CNY",
            "order_amount": round((body.amount or 0.0), 2),
            "order_buyer_id": getattr(current_user, "id", None) or "",
        },
        "payment_redirect_url": return_url,
        "settlement_currency": body.currency or "CNY",
        "env_client_ip": getattr(request.client, "host", None) or "",
        "product_scene": product_scene,
        "auth_state": getattr(current_user, "id", None) or "",
        "user_login_id": (getattr(current_user, "email", None) or getattr(current_user, "id", None) or ""),
    }
    import json, hashlib, base64
    idem_body_json = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    idem_body_hash = base64.b64encode(hashlib.sha256(idem_body_json.encode("utf-8")).digest()).decode()
    if idem_key:
        d = _idem_get(request, idem_key, idem_body_hash)
        if d:
            return GsalaryCreateDTO(**d)

    if os.getenv("ENABLE_TEST_ENDPOINTS", "0") == "1" or (not base_url or not create_path):
        pid = f"GSALARY-{body.method}-{body.orderId}"
        url = f"https://api.gsalary.com/checkout?pid={pid}"
        dto = GsalaryCreateDTO(checkoutUrl=url, paymentId=pid, paymentMethodId=None, paymentRequestId=payment_request_id)
        try:
            if idem_key:
                _idem_set(request, idem_key, idem_body_hash, dto)
        except Exception:
            pass
        return dto

    try:
        use_sdk = os.getenv("GSALARY_SDK_ENABLED", "false").lower() in ("1", "true", "yes")
        if use_sdk:
            try:
                from gsalary_sdk import GSalaryClient, GSalaryConfig, GSalaryRequest
                cfg = GSalaryConfig()
                appid = os.getenv("GSALARY_APPID", "")
                cfg.appid = appid
                if os.getenv("GSALARY_CLIENT_PRIVATE_KEY_PATH"):
                    cfg.config_client_private_key_pem_file(os.getenv("GSALARY_CLIENT_PRIVATE_KEY_PATH"))
                if os.getenv("GSALARY_SERVER_PUBLIC_KEY_PATH"):
                    cfg.config_server_public_key_pem_file(os.getenv("GSALARY_SERVER_PUBLIC_KEY_PATH"))
                cli = GSalaryClient(cfg)
                req = GSalaryRequest("POST", create_path, body=payload)
                resp = cli.request(req)
                env_data = resp.get("data") or {}
                checkout_url = env_data.get("normal_url") or env_data.get("checkoutUrl") or env_data.get("pay_url") or env_data.get("h5_url") or env_data.get("url") or ""
                payment_id = env_data.get("paymentId") or env_data.get("trade_no") or env_data.get("orderNo") or env_data.get("id") or ""
                if not checkout_url and env_data.get("orderString"):
                    payment_id = payment_id or env_data.get("orderString")
                dto = GsalaryCreateDTO(checkoutUrl=checkout_url or f"https://api.gsalary.com/checkout?pid={payment_id}", paymentId=payment_id or terminal_trace, paymentMethodId=env_data.get("payment_method_id") or env_data.get("paymentMethodId"), paymentRequestId=payment_request_id)
                try:
                    if idem_key:
                        _idem_set(request, idem_key, idem_body_hash, dto)
                except Exception:
                    pass
                return dto
            except Exception:
                pass
        env_data = _gateway_call(request, "POST", create_path, payload)
        checkout_url = env_data.get("normal_url") or env_data.get("checkoutUrl") or env_data.get("pay_url") or env_data.get("h5_url") or env_data.get("url") or ""
        payment_id = env_data.get("paymentId") or env_data.get("trade_no") or env_data.get("orderNo") or env_data.get("id") or ""
        pmid = env_data.get("payment_method_id") or env_data.get("paymentMethodId") or env_data.get("pm_id")
        if not checkout_url and env_data.get("orderString"):
            payment_id = payment_id or env_data.get("orderString")
        dto = GsalaryCreateDTO(checkoutUrl=checkout_url or f"https://api.gsalary.com/checkout?pid={payment_id}", paymentId=payment_id or terminal_trace, paymentMethodId=pmid, paymentRequestId=payment_request_id)
        try:
            if idem_key:
                _idem_set(request, idem_key, idem_body_hash, dto)
        except Exception:
            pass
        return dto
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"create payment failed: {str(e)}")
class PaymentWebhookBody(BaseModel):
    provider: Literal["alipay", "paypal", "card", "applepay", "googlepay"]
    orderId: str | None = None
    reference: str | None = None
    status: Literal["paid", "failed", "created"]
    amount: float | None = None
    currency: str | None = None

def _verify_signature_rsa2(authorization: str | None, appid: str | None, method: str, path: str, body_json: str) -> bool:
    import os, rsa, base64, hashlib
    if not authorization:
        return False
    algo = None
    time_part = None
    sig_part = None
    try:
        parts = authorization.split(",")
        for p in parts:
            kv = p.split("=")
            if len(kv) == 2:
                k = kv[0].strip()
                v = kv[1].strip()
                if k == "algorithm":
                    algo = v
                elif k == "time":
                    time_part = v
                elif k == "signature":
                    sig_part = v
        if algo != "RSA2" or not sig_part or not appid:
            return False
        import urllib.parse
        sig_b64 = urllib.parse.unquote(sig_part)
        body_hash = base64.b64encode(hashlib.sha256(body_json.encode("utf-8")).digest()).decode()
        sign_base = f"{method} {path}\n{appid}\n{time_part}\n{body_hash}\n"
        pub_pem = None
        p = os.getenv("GSALARY_SERVER_PUBLIC_KEY_PATH")
        if p:
            try:
                with open(p, "rb") as f:
                    pub_pem = f.read().decode("utf-8")
            except Exception:
                return False
        if not pub_pem:
            return False
        try:
            pub = rsa.PublicKey.load_pkcs1(pub_pem.encode("utf-8"))
            sig_bytes = base64.b64decode(sig_b64)
            rsa.verify(sign_base.encode("utf-8"), sig_bytes, pub)
            return True
        except Exception:
            return False
    except Exception:
        return False

@app.post("/webhooks/payments")
async def payments_webhook(
    request: Request,
    body: PaymentWebhookBody,
    authorization: str | None = Header(default=None, alias="Authorization"),
    x_appid: str | None = Header(default=None, alias="X-Appid"),
):
    import json
    j = jsonable_encoder(body)
    m = "POST"
    p = request.url.path
    ok = _verify_signature_rsa2(authorization, x_appid, m, p, json.dumps(j, separators=(",", ":")))
    if not ok:
        raise HTTPException(status_code=401, detail="Invalid webhook signature")
    rid = getattr(request.state, "request_id", None)
    updated = service.apply_payment_webhook(
        provider=body.provider,
        provider_order_id=(body.orderId or None),
        order_reference=(body.reference or None),
        status=body.status,
        amount=body.amount,
        currency=body.currency,
        request_id=rid,
    )
    return _json_envelope({"code": 200, "data": {"updated": updated}, "msg": ""}, request)

class GsalaryWebhookEnvelope(BaseModel):
    business_type: str
    event_time: str
    business_id: str
    data: dict

@app.post("/webhooks/gsalary")
async def gsalary_webhook(
    request: Request,
    body: GsalaryWebhookEnvelope,
    authorization: str | None = Header(default=None, alias="Authorization"),
    x_appid: str | None = Header(default=None, alias="X-Appid"),
):
    import json
    m = "POST"
    p = request.url.path
    j = jsonable_encoder(body)
    ok = _verify_signature_rsa2(authorization, x_appid, m, p, json.dumps(j, separators=(",", ":")))
    if not ok:
        raise HTTPException(status_code=401, detail="Invalid webhook signature")
    bt = (body.business_type or "").upper()
    data = body.data or {}
    updated = 0
    def _map_provider(x: str | None) -> str:
        s = (x or "").upper()
        if "ALIPAY" in s:
            return "alipay"
        if "PAYPAL" in s:
            return "paypal"
        if "APPLEPAY" in s or "APPLE_PAY" in s:
            return "applepay"
        if "GOOGLEPAY" in s or "GOOGLE_PAY" in s:
            return "googlepay"
        return "card"
    if bt.startswith("ACQUIRING_PAYMENT"):
        method = data.get("payment_method") or data.get("payment_method_type") or ""
        provider = _map_provider(method)
        status_raw = str(data.get("payment_status") or "").upper()
        if status_raw in ("SUCCESS", "PAID"):
            status = "paid"
        elif status_raw in ("FAILED", "FAIL"):
            status = "failed"
        else:
            status = "created"
        amt = None
        cur = None
        pa = data.get("payment_amount") or {}
        try:
            amt = float(pa.get("amount")) if pa.get("amount") is not None else None
        except Exception:
            amt = None
        cur = pa.get("currency")
        pid = data.get("payment_id") or None
        rid = getattr(request.state, "request_id", None)
        updated = service.apply_payment_webhook(
            provider=provider,
            provider_order_id=(str(pid) if pid else None),
            order_reference=None,
            status=status,
            amount=amt,
            currency=(str(cur) if cur else None),
            request_id=rid,
        )
    elif bt.startswith("ACQUIRING_AUTH_TOKEN"):
        uid = data.get("user_login_id") or ""
        at = data.get("access_token") or None
        rt = data.get("refresh_token") or None
        ate = data.get("access_token_expiry_time") or None
        rte = data.get("refresh_token_expiry_time") or None
        db = _get_db()
        try:
            rec = db.query(GSalaryAuthToken).filter(GSalaryAuthToken.user_id == uid).first()
            from datetime import datetime
            def _parse(s: str | None):
                try:
                    return datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None
                except Exception:
                    return None
            if rec is None:
                rec = GSalaryAuthToken(user_id=uid)
            rec.access_token = at
            rec.refresh_token = rt
            rec.access_token_expiry_time = _parse(ate)
            rec.refresh_token_expiry_time = _parse(rte)
            rec.updated_at = datetime.utcnow()
            db.add(rec)
            db.commit()
            updated = 1
        finally:
            db.close()
    elif bt in ("PAYEE_ACCOUNT_ACTIVE", "REMITTANCE_FAIL", "REMITTANCE_COMPLETE", "REMITTANCE_REVERSE", "PAYEE_DEACTIVATED"):
        try:
            evs = getattr(request.app.state, "payee_events", None)
            if evs is None:
                request.app.state.payee_events = []
                evs = request.app.state.payee_events
            evs.append({"business_type": bt, "event_time": body.event_time, "business_id": body.business_id, "data": data})
            updated = 1
        except Exception:
            updated = 0
    return _json_envelope({"code": 200, "data": {"updated": updated}, "msg": ""}, request)


@app.on_event("startup")
def on_startup():
    # Initialize database tables
    init_db()
    try:
        app.state.payee_events
    except Exception:
        app.state.payee_events = []
    try:
        url = os.getenv("IDEMPOTENCY_REDIS_URL") or os.getenv("REDIS_URL")
        if url:
            import importlib
            mod = importlib.import_module("redis")
            app.state.idem_redis = mod.Redis.from_url(url, decode_responses=True)
    except Exception:
        try:
            app.state.idem_redis = None
        except Exception:
            pass


@app.get("/me", response_model=UserDTO)
async def get_me(current_user: ORMUser = Depends(get_current_user)):
    return UserDTO(
        id=current_user.id,
        name=current_user.name,
        lastName=current_user.last_name,
        email=current_user.email,
        hasPassword=bool(current_user.password_hash),
        language=current_user.language,
        currency=current_user.currency,
        country=current_user.country,
    )


@app.put("/me", response_model=UserDTO)
async def update_me(body: UpdateProfileBody, current_user: ORMUser = Depends(get_current_user)):
    db = _get_db()
    try:
        if body.name is not None:
            current_user.name = body.name.strip()
        if body.lastName is not None:
            ln = body.lastName.strip()
            current_user.last_name = ln if ln else None
        if body.language is not None:
            lang_code = body.language.strip()
            exists = db.query(LanguageOption).filter(LanguageOption.code == lang_code).first()
            if not exists:
                raise HTTPException(status_code=400, detail="Unsupported language")
            current_user.language = lang_code
        if body.currency is not None:
            currency_code = body.currency.strip().upper()
            exists = db.query(CurrencyOption).filter(CurrencyOption.code == currency_code).first()
            if not exists:
                raise HTTPException(status_code=400, detail="Unsupported currency")
            current_user.currency = currency_code
        if body.country is not None:
            current_user.country = body.country.strip().upper()
        db.add(current_user)
        db.commit()
        db.refresh(current_user)
        return UserDTO(
            id=current_user.id,
            name=current_user.name,
            lastName=current_user.last_name,
            email=current_user.email,
            hasPassword=bool(current_user.password_hash),
            language=current_user.language,
            currency=current_user.currency,
            country=current_user.country,
        )
    finally:
        db.close()


@app.put("/me/email", response_model=UserDTO)
async def update_email(body: ChangeEmailBody, current_user: ORMUser = Depends(get_current_user)):
    try:
        return auth_service.change_email(user_id=current_user.id, new_email=body.email, password=body.password, verification_code=body.verificationCode)
    except ValueError as e:
        msg = str(e)
        if msg == "password_required_for_email_change":
            raise HTTPException(status_code=400, detail="您必须创建一个密码才能成功更改电子邮件地址")
        if msg == "email_taken":
            raise HTTPException(status_code=409, detail="该电子邮件已被使用")
        if msg == "invalid_password":
            raise HTTPException(status_code=401, detail="密码不正确")
        raise HTTPException(status_code=400, detail="无效的电子邮件地址")


@app.put("/me/password", response_model=SuccessDTO)
async def update_password(body: UpdatePasswordBody, current_user: ORMUser = Depends(get_current_user)):
    try:
        return auth_service.update_password(user_id=current_user.id, new_password=body.newPassword, current_password=body.currentPassword)
    except ValueError as e:
        msg = str(e)
        if msg == "weak_password":
            raise HTTPException(status_code=400, detail="密码至少需要 8 位")
        if msg == "invalid_password":
            raise HTTPException(status_code=401, detail="当前密码不正确")
        raise HTTPException(status_code=400, detail="更新密码失败")


@app.delete("/me", response_model=SuccessDTO)
async def delete_me(body: DeleteAccountBody, current_user: ORMUser = Depends(get_current_user)):
    try:
        return auth_service.delete_account(
            user_id=current_user.id,
            current_password=body.currentPassword,
            reason=(body.reason or None),
            details=(body.details or None),
        )
    except ValueError as e:
        msg = str(e)
        if msg == "invalid_password":
            raise HTTPException(status_code=401, detail="当前密码不正确")
        raise HTTPException(status_code=400, detail="删除账号失败")


# ===== Settings =====
@app.get("/settings/languages", response_model=list[LanguageOptionDTO])
async def get_settings_languages():
    db = _get_db()
    try:
        rows = db.query(LanguageOption).order_by(LanguageOption.code.asc()).all()
        return [LanguageOptionDTO(code=r.code, name=r.name) for r in rows]
    finally:
        db.close()


@app.get("/settings/currencies", response_model=list[CurrencyOptionDTO])
async def get_settings_currencies():
    db = _get_db()
    try:
        import os
        env = os.getenv("SETTINGS_CURRENCIES_VISIBLE", "").strip()
        if env:
            codes = {c.strip().upper() for c in env.split(",") if c.strip()}
        else:
            codes = {"USD","CHF","CNY","EUR","GBP","HKD","JPY","SGD"}
        rows = db.query(CurrencyOption).filter(CurrencyOption.code.in_(list(codes))).order_by(CurrencyOption.code.asc()).all()
        return [CurrencyOptionDTO(code=r.code, name=r.name, symbol=r.symbol) for r in rows]
    finally:
        db.close()
class GsalaryPayBody(BaseModel):
    orderId: str
    method: Literal["alipay", "card", "applepay", "paypal"]
    amount: float | None = None
    currency: str | None = None
    paymentMethodId: str | None = Field(default=None, alias="payment_method_id")

class GsalaryPayDTO(BaseModel):
    checkoutUrl: str | None = None
    paymentId: str
    schemeUrl: str | None = None
    applinkUrl: str | None = None
    appIdentifier: str | None = None

@app.post("/payments/gsalary/pay", response_model=GsalaryPayDTO)
async def payments_gsalary_pay(request: Request, body: GsalaryPayBody, current_user: ORMUser = Depends(get_current_user)):
    import time, hashlib, base64, rsa, urllib.parse, json, datetime
    base_url = os.getenv("GSALARY_BASE_URL", "").rstrip("/")
    import re
    def _clean_path(p: str) -> str:
        p = re.sub(r"\u200b", "", p)
        p = re.sub(r"/+", "/", p)
        p = p.replace("gateway/v1/gateway/v1/", "gateway/v1/")
        return p
    pay_path = (os.getenv("GSALARY_CARD_PAY_PATH") if body.method == "card" else os.getenv("GSALARY_PAY_PATH")) or ("/v1/gateway/v1/acquiring/card_auto_debit/pay" if body.method == "card" else "/v1/gateway/v1/acquiring/easy_safe_pay/pay")
    pay_path = _clean_path(pay_path)
    idem_key = request.headers.get("Idempotency-Key")
    appid = os.getenv("GSALARY_APPID", "")
    return_url = os.getenv("GSALARY_RETURN_URL", os.getenv("PUBLIC_BASE_URL", "").rstrip("/") + "/return/payments")
    mch_app_id = os.getenv("GSALARY_MCH_APP_ID", "")
    env_terminal_type = os.getenv("GSALARY_ENV_TERMINAL_TYPE", "WEB")
    env_os_type = os.getenv("GSALARY_ENV_OS_TYPE", "IOS")
    paytype_alipay = os.getenv("GSALARY_PAYTYPE_ALIPAY", "ALIPAY_CN")
    paytype_card = os.getenv("GSALARY_PAYTYPE_CARD", "CARD")
    paytype_applepay = os.getenv("GSALARY_PAYTYPE_APPLEPAY", "APPLEPAY")
    paytype_paypal = os.getenv("GSALARY_PAYTYPE_PAYPAL", "PAYPAL")
    if body.method == "alipay":
        pay_type = paytype_alipay
    elif body.method == "applepay":
        pay_type = paytype_applepay
    elif body.method == "paypal":
        pay_type = paytype_paypal
    else:
        pay_type = paytype_card

    # 测试/演示模式或未配置网关地址：直接返回本地构造的结果，避免严格参数校验
    if os.getenv("ENABLE_TEST_ENDPOINTS", "0") == "1" or not base_url:
        pid = f"GSALARY-{body.method}-{body.orderId}"
        return GsalaryPayDTO(checkoutUrl=f"https://api.gsalary.com/checkout?pid={pid}", paymentId=f"PAY-{body.orderId}")

    pmid = body.paymentMethodId
    if not pmid:
        if body.method == "card":
            raise HTTPException(status_code=400, detail="missing payment_method_id for card")
        db = _get_db()
        try:
            rec = db.query(GSalaryAuthToken).filter(GSalaryAuthToken.user_id == current_user.id).first()
            if rec and rec.access_token:
                pmid = rec.access_token
        finally:
            db.close()
    pay_expiry_min = None
    try:
        pay_expiry_min = int(os.getenv("GSALARY_PAY_EXPIRY_MINUTES", "14"))
    except Exception:
        pay_expiry_min = 14
    payload = {
        "mch_app_id": mch_app_id,
        "payment_request_id": f"PAY_{body.orderId.replace('-', '')[:20]}",
        "payment_currency": body.currency or "CNY",
        "payment_amount": round((body.amount or 0.0), 2),
        "payment_method_id": pmid,
        "payment_method_type": pay_type,
        "payment_redirect_url": return_url,
        "order": {
            "reference_order_id": body.orderId,
            "order_description": "Simigo eSIM purchase",
            "order_currency": body.currency or "CNY",
            "order_amount": round((body.amount or 0.0), 2),
            "order_buyer_id": getattr(current_user, "id", None) or "",
        },
        "settlement_currency": body.currency or "CNY",
        "env_client_ip": getattr(request.client, "host", None) or "",
        "payment_expiry_time": (datetime.datetime.utcnow() + datetime.timedelta(minutes=pay_expiry_min)).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "env_terminal_type": env_terminal_type,
        "env_os_type": env_os_type,
    }
    import json, hashlib, base64
    idem_body_json = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    idem_body_hash = base64.b64encode(hashlib.sha256(idem_body_json.encode("utf-8")).digest()).decode()
    if idem_key:
        try:
            r = getattr(request.app.state, "idem_redis", None)
            if r is not None:
                k = f"idem:{idem_key}:{request.url.path}:{request.method}:{idem_body_hash}"
                v = r.get(k)
                if v:
                    d = json.loads(v)
                    return GsalaryPayDTO(**d)
        except Exception:
            pass
        d = _idem_get(request, idem_key, idem_body_hash)
        if d:
            return GsalaryPayDTO(**d)

    # RSA2 签名头
    method = "POST"
    timestamp = str(int(time.time()*1000))
    body_json = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    body_hash = base64.b64encode(hashlib.sha256(body_json.encode("utf-8")).digest()).decode()
    sign_base = f"{method} {pay_path}\n{appid}\n{timestamp}\n{body_hash}\n"
    p = os.getenv("GSALARY_CLIENT_PRIVATE_KEY_PATH")
    pem = None
    if p:
        try:
            with open(p, "rb") as f:
                pem = f.read().decode("utf-8")
        except Exception:
            pem = None
    if not pem:
        raise HTTPException(status_code=500, detail="missing client private key")
    try:
        priv = rsa.PrivateKey.load_pkcs1(pem.encode("utf-8"))
    except Exception:
        raise HTTPException(status_code=500, detail="invalid client private key")
    sig_bytes = rsa.sign(sign_base.encode("utf-8"), priv, "SHA-256")
    sig_b64 = base64.b64encode(sig_bytes).decode()
    sig_url = urllib.parse.quote(sig_b64, safe="")
    headers = {"Content-Type": "application/json", "X-Appid": appid, "Authorization": f"algorithm=RSA2,time={timestamp},signature={sig_url}"}
    rid = getattr(request.state, "request_id", None)
    if rid:
        headers["Request-Id"] = rid

    if not base_url:
        return GsalaryPayDTO(checkoutUrl=f"https://api.gsalary.com/checkout?pid=GSALARY-{body.method}-{body.orderId}", paymentId=f"PAY-{body.orderId}")

    d = _gateway_call(request, "POST", pay_path, payload)
    dto = GsalaryPayDTO(
        checkoutUrl=d.get("normal_url"),
        paymentId=d.get("payment_id") or d.get("payment_request_id") or "",
        schemeUrl=d.get("scheme_url"),
        applinkUrl=d.get("applink_url"),
        appIdentifier=d.get("app_identifier"),
    )
    try:
        if idem_key:
            _idem_set(request, idem_key, idem_body_hash, dto)
    except Exception:
        pass
    return dto

class GsalaryConsultCardBrand(BaseModel):
    card_brand: str | None = None
    brand_logo_name: str | None = None
    brand_logo_url: str | None = None

class GsalaryConsultBank(BaseModel):
    bank_identifier_code: str | None = None
    bank_short_name: str | None = None
    bank_logo_name: str | None = None
    bank_logo_url: str | None = None

class GsalaryConsultOption(BaseModel):
    payment_method_type: str | None = None
    payment_method_logo_name: str | None = None
    payment_method_logo_url: str | None = None
    payment_method_category: str | None = None
    payment_method_region: list[str] | None = None
    support_card_brands: list[GsalaryConsultCardBrand] | None = None
    card_funding: list[str] | None = None
    support_banks: list[GsalaryConsultBank] | None = None

class GsalaryConsultDTO(BaseModel):
    payment_options: list[GsalaryConsultOption] = []

class GsalaryConsultBody(BaseModel):
    amount: float
    currency: str
    settlementCurrency: str | None = None
    allowedPaymentMethodRegions: list[str] | None = None
    allowedPaymentMethods: list[str] | None = None
    userRegion: str | None = None
    envTerminalType: str | None = None
    envOsType: str | None = None
    envClientIp: str | None = None

@app.post("/payments/gsalary/consult", response_model=GsalaryConsultDTO)
async def payments_gsalary_consult(request: Request, body: GsalaryConsultBody, current_user: ORMUser = Depends(get_current_user)):
    import json, hashlib, base64, re, os
    base_url = os.getenv("GSALARY_BASE_URL", "").rstrip("/")
    def _clean_path(p: str) -> str:
        p = re.sub(r"\u200b", "", p)
        p = re.sub(r"/+", "/", p)
        p = p.replace("gateway/v1/gateway/v1/", "gateway/v1/")
        return p
    path = os.getenv("GSALARY_PAY_CONSULT_PATH", "/v1/gateway/v1/acquiring/pay_consult")
    path = _clean_path(path)
    idem_key = request.headers.get("Idempotency-Key")
    mch_app_id = os.getenv("GSALARY_MCH_APP_ID", "")
    env_terminal_type = body.envTerminalType or os.getenv("GSALARY_ENV_TERMINAL_TYPE", "WEB")
    env_os_type = body.envOsType or os.getenv("GSALARY_ENV_OS_TYPE", "IOS")
    env_client_ip = body.envClientIp or (getattr(request.client, "host", None) or "")
    amr = body.allowedPaymentMethodRegions
    if amr is None:
        amr_env = os.getenv("GSALARY_ALLOWED_PAYMENT_METHOD_REGIONS", "")
        amr = [s.strip() for s in amr_env.split(",") if s.strip()] if amr_env else []
    apm = body.allowedPaymentMethods
    if apm is None:
        apm_env = os.getenv("GSALARY_ALLOWED_PAYMENT_METHODS", "")
        apm = [s.strip() for s in apm_env.split(",") if s.strip()] if apm_env else []
    user_region = body.userRegion or os.getenv("GSALARY_DEFAULT_USER_REGION", "US")
    payload = {
        "mch_app_id": mch_app_id,
        "payment_currency": body.currency,
        "payment_amount": round(body.amount, 2),
        "settlement_currency": body.settlementCurrency or body.currency,
        "allowed_payment_method_regions": amr,
        "allowed_payment_methods": apm,
        "user_region": user_region,
        "env_terminal_type": env_terminal_type,
        "env_os_type": env_os_type,
        "env_client_ip": env_client_ip,
    }
    idem_body_json = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    idem_body_hash = base64.b64encode(hashlib.sha256(idem_body_json.encode("utf-8")).digest()).decode()
    if idem_key:
        d = _idem_get(request, idem_key, idem_body_hash)
        if d:
            return GsalaryConsultDTO(**d)
    if os.getenv("ENABLE_TEST_ENDPOINTS", "0") == "1" or (not base_url or not path):
        dto = GsalaryConsultDTO(payment_options=[
            {
                "payment_method_type": "CARD",
                "payment_method_logo_name": "card",
                "payment_method_logo_url": "",
                "payment_method_category": "CARD",
                "payment_method_region": [user_region],
                "support_card_brands": [{"card_brand": "VISA"}, {"card_brand": "MASTERCARD"}],
                "card_funding": ["CREDIT", "DEBIT"],
                "support_banks": [],
            },
            {
                "payment_method_type": "APPLEPAY",
                "payment_method_logo_name": "applepay",
                "payment_method_logo_url": "",
                "payment_method_category": "WALLET",
                "payment_method_region": [user_region],
                "support_card_brands": [],
                "card_funding": [],
                "support_banks": [],
            },
            {
                "payment_method_type": "PAYPAL",
                "payment_method_logo_name": "paypal",
                "payment_method_logo_url": "",
                "payment_method_category": "WALLET",
                "payment_method_region": [user_region],
                "support_card_brands": [],
                "card_funding": [],
                "support_banks": [],
            },
        ])
        try:
            if idem_key:
                _idem_set(request, idem_key, idem_body_hash, dto)
        except Exception:
            pass
        return dto
    d = _gateway_call(request, "POST", path, payload)
    dto = GsalaryConsultDTO(payment_options=d.get("payment_options") or [])
    try:
        if idem_key:
            _idem_set(request, idem_key, idem_body_hash, dto)
    except Exception:
        pass
    return dto

class GsalaryAuthRefreshBody(BaseModel):
    refresh_token: str
    merchant_region: str | None = None

class GsalaryAuthRefreshDTO(BaseModel):
    access_token: str
    access_token_expiry_time: str
    refresh_token: str
    refresh_token_expiry_time: str
    user_login_id: str | None = None

@app.post("/payments/gsalary/auth/refresh", response_model=GsalaryAuthRefreshDTO)
async def payments_gsalary_auth_refresh(request: Request, body: GsalaryAuthRefreshBody, current_user: ORMUser = Depends(get_current_user)):
    import time, hashlib, base64, rsa, urllib.parse, json
    base_url = os.getenv("GSALARY_BASE_URL", "").rstrip("/")
    path = os.getenv("GSALARY_AUTH_REFRESH_PATH", "/v1/gateway/v1/acquiring/auth_refresh_token")
    appid = os.getenv("GSALARY_APPID", "")
    mch_app_id = os.getenv("GSALARY_MCH_APP_ID", "")
    payload = {"mch_app_id": mch_app_id, "refresh_token": body.refresh_token}
    mr = body.merchant_region or os.getenv("GSALARY_MERCHANT_REGION")
    if mr:
        payload["merchant_region"] = mr
    if os.getenv("ENABLE_TEST_ENDPOINTS", "0") == "1":
        raise HTTPException(status_code=500, detail="missing client private key")
    method = "POST"
    timestamp = str(int(time.time()*1000))
    body_json = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    body_hash = base64.b64encode(hashlib.sha256(body_json.encode("utf-8")).digest()).decode()
    sign_base = f"{method} {path}\n{appid}\n{timestamp}\n{body_hash}\n"
    p = os.getenv("GSALARY_CLIENT_PRIVATE_KEY_PATH")
    pem = None
    if p:
        try:
            with open(p, "rb") as f:
                pem = f.read().decode("utf-8")
        except Exception:
            pem = None
    if not pem:
        raise HTTPException(status_code=500, detail="missing client private key")
    try:
        priv = rsa.PrivateKey.load_pkcs1(pem.encode("utf-8"))
    except Exception:
        raise HTTPException(status_code=500, detail="invalid client private key")
    sig_bytes = rsa.sign(sign_base.encode("utf-8"), priv, "SHA-256")
    sig_b64 = base64.b64encode(sig_bytes).decode()
    sig_url = urllib.parse.quote(sig_b64, safe="")
    headers = {"Content-Type": "application/json", "X-Appid": appid, "Authorization": f"algorithm=RSA2,time={timestamp},signature={sig_url}"}
    rid = getattr(request.state, "request_id", None)
    if rid:
        headers["Request-Id"] = rid
    if not base_url:
        raise HTTPException(status_code=500, detail="missing base url")
    d = _gateway_call(request, "POST", path, payload)
    dto = GsalaryAuthRefreshDTO(
        access_token=d.get("access_token", ""),
        access_token_expiry_time=d.get("access_token_expiry_time", ""),
        refresh_token=d.get("refresh_token", ""),
        refresh_token_expiry_time=d.get("refresh_token_expiry_time", ""),
        user_login_id=d.get("user_login_id"),
    )
    db = _get_db()
    try:
        uid = dto.user_login_id or current_user.id
        rec = db.query(GSalaryAuthToken).filter(GSalaryAuthToken.user_id == uid).first()
        from datetime import datetime
        def _parse(s: str | None):
            try:
                return datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None
            except Exception:
                return None
        if rec is None:
            rec = GSalaryAuthToken(user_id=uid)
        rec.access_token = dto.access_token
        rec.refresh_token = dto.refresh_token
        rec.access_token_expiry_time = _parse(dto.access_token_expiry_time)
        rec.refresh_token_expiry_time = _parse(dto.refresh_token_expiry_time)
        rec.updated_at = datetime.utcnow()
        db.add(rec)
        db.commit()
    finally:
        db.close()
    return dto

class GsalaryAuthRevokeBody(BaseModel):
    access_token: str

@app.post("/payments/gsalary/auth/revoke")
async def payments_gsalary_auth_revoke(request: Request, body: GsalaryAuthRevokeBody, current_user: ORMUser = Depends(get_current_user)):
    import time, hashlib, base64, rsa, urllib.parse, json
    base_url = os.getenv("GSALARY_BASE_URL", "").rstrip("/")
    path = os.getenv("GSALARY_AUTH_REVOKE_PATH", "/v1/gateway/v1/acquiring/auth_revoke_token")
    appid = os.getenv("GSALARY_APPID", "")
    mch_app_id = os.getenv("GSALARY_MCH_APP_ID", "")
    payload = {"mch_app_id": mch_app_id, "access_token": body.access_token}
    if os.getenv("ENABLE_TEST_ENDPOINTS", "0") == "1":
        raise HTTPException(status_code=500, detail="missing client private key")
    method = "POST"
    timestamp = str(int(time.time()*1000))
    body_json = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    body_hash = base64.b64encode(hashlib.sha256(body_json.encode("utf-8")).digest()).decode()
    sign_base = f"{method} {path}\n{appid}\n{timestamp}\n{body_hash}\n"
    p = os.getenv("GSALARY_CLIENT_PRIVATE_KEY_PATH")
    pem = None
    if p:
        try:
            with open(p, "rb") as f:
                pem = f.read().decode("utf-8")
        except Exception:
            pem = None
    if not pem:
        raise HTTPException(status_code=500, detail="missing client private key")
    try:
        priv = rsa.PrivateKey.load_pkcs1(pem.encode("utf-8"))
    except Exception:
        raise HTTPException(status_code=500, detail="invalid client private key")
    sig_bytes = rsa.sign(sign_base.encode("utf-8"), priv, "SHA-256")
    sig_b64 = base64.b64encode(sig_bytes).decode()
    sig_url = urllib.parse.quote(sig_b64, safe="")
    headers = {"Content-Type": "application/json", "X-Appid": appid, "Authorization": f"algorithm=RSA2,time={timestamp},signature={sig_url}"}
    rid = getattr(request.state, "request_id", None)
    if rid:
        headers["Request-Id"] = rid
    if not base_url:
        raise HTTPException(status_code=500, detail="missing base url")
    d = _gateway_call(request, "POST", path, payload)
    try:
        db = _get_db()
        rec = db.query(GSalaryAuthToken).filter(GSalaryAuthToken.user_id == current_user.id).first()
        if rec:
            from datetime import datetime
            rec.access_token = None
            rec.refresh_token = None
            rec.access_token_expiry_time = None
            rec.refresh_token_expiry_time = None
            rec.updated_at = datetime.utcnow()
            db.add(rec)
            db.commit()
    finally:
        try:
            db.close()
        except Exception:
            pass
    return _json_envelope({"code": 200, "data": {"revoked": True}}, request)

class GsalaryCancelBody(BaseModel):
    paymentRequestId: str = Field(alias="payment_request_id")

class GsalaryCancelDTO(BaseModel):
    paymentId: str
    paymentRequestId: str
    cancelTime: str

@app.post("/payments/gsalary/cancel", response_model=GsalaryCancelDTO)
async def payments_gsalary_cancel(request: Request, body: GsalaryCancelBody, current_user: ORMUser = Depends(get_current_user)):
    import time, hashlib, base64, rsa, urllib.parse, json, datetime, re
    base_url = os.getenv("GSALARY_BASE_URL", "").rstrip("/")
    def _clean_path(p: str) -> str:
        p = re.sub(r"\u200b", "", p)
        p = re.sub(r"/+", "/", p)
        p = p.replace("gateway/v1/gateway/v1/", "gateway/v1/")
        return p
    path = os.getenv("GSALARY_CANCEL_PATH", "/v1/gateway/v1/acquiring/cancel")
    path = _clean_path(path)
    idem_key = request.headers.get("Idempotency-Key")
    appid = os.getenv("GSALARY_APPID", "")
    mch_app_id = os.getenv("GSALARY_MCH_APP_ID", "")
    payload = {"mch_app_id": mch_app_id, "payment_request_id": body.paymentRequestId}
    if os.getenv("ENABLE_TEST_ENDPOINTS", "0") == "1" or not base_url:
        now = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
        dto = GsalaryCancelDTO(paymentId=f"PAY-{body.paymentRequestId}", paymentRequestId=body.paymentRequestId, cancelTime=now)
        return dto
    method = "POST"
    timestamp = str(int(time.time()*1000))
    body_json = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    body_hash = base64.b64encode(hashlib.sha256(body_json.encode("utf-8")).digest()).decode()
    sign_base = f"{method} {path}\n{appid}\n{timestamp}\n{body_hash}\n"
    idem_body_hash = body_hash
    if idem_key:
        d = _idem_get(request, idem_key, idem_body_hash)
        if d:
            return GsalaryCancelDTO(**d)
    p = os.getenv("GSALARY_CLIENT_PRIVATE_KEY_PATH")
    pem = None
    if p:
        try:
            with open(p, "rb") as f:
                pem = f.read().decode("utf-8")
        except Exception:
            pem = None
    if not pem:
        if not base_url:
            now = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
            dto = GsalaryCancelDTO(paymentId=f"PAY-{body.paymentRequestId}", paymentRequestId=body.paymentRequestId, cancelTime=now)
            try:
                if idem_key:
                    _idem_set(request, idem_key, idem_body_hash, dto)
            except Exception:
                pass
            return dto
        raise HTTPException(status_code=500, detail="missing client private key")
    try:
        priv = rsa.PrivateKey.load_pkcs1(pem.encode("utf-8"))
    except Exception:
        raise HTTPException(status_code=500, detail="invalid client private key")
    sig_bytes = rsa.sign(sign_base.encode("utf-8"), priv, "SHA-256")
    sig_b64 = base64.b64encode(sig_bytes).decode()
    sig_url = urllib.parse.quote(sig_b64, safe="")
    headers = {"Content-Type": "application/json", "X-Appid": appid, "Authorization": f"algorithm=RSA2,time={timestamp},signature={sig_url}"}
    rid = getattr(request.state, "request_id", None)
    if rid:
        headers["Request-Id"] = rid
    if not base_url:
        now = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
        dto = GsalaryCancelDTO(paymentId=f"PAY-{body.paymentRequestId}", paymentRequestId=body.paymentRequestId, cancelTime=now)
        try:
            if idem_key:
                _idem_set(request, idem_key, idem_body_hash, dto)
        except Exception:
            pass
        return dto
    d = _gateway_call(request, "POST", path, payload)
    dto = GsalaryCancelDTO(paymentId=d.get("payment_id") or "", paymentRequestId=d.get("payment_request_id") or body.paymentRequestId, cancelTime=d.get("cancel_time") or "")
    try:
        if idem_key:
            _idem_set(request, idem_key, idem_body_hash, dto)
    except Exception:
        pass
    return dto

class GsalaryQueryBody(BaseModel):
    paymentRequestId: str | None = Field(default=None, alias="payment_request_id")
    paymentId: str | None = Field(default=None, alias="payment_id")

class GsalaryQueryAmount(BaseModel):
    currency: str | None = None
    amount: float | None = None

class GsalaryQueryDTO(BaseModel):
    payment_method_type: str | None = None
    payment_status: str | None = None
    payment_result_message: str | None = None
    payment_request_id: str | None = None
    payment_id: str | None = None
    payment_amount: GsalaryQueryAmount | None = None
    surcharge: GsalaryQueryAmount | None = None
    gross_settlement_amount: GsalaryQueryAmount | None = None
    customs_declaration_amount: GsalaryQueryAmount | None = None
    payment_create_time: str | None = None
    payment_time: str | None = None
    captured: bool | None = None
    capture_time: str | None = None
    settlement_quote: dict | None = None
    payment_result_info: dict | None = None
    transactions: list[dict] | None = None

    

@app.post("/payments/gsalary/query", response_model=GsalaryQueryDTO)
async def payments_gsalary_query(request: Request, body: GsalaryQueryBody, current_user: ORMUser = Depends(get_current_user)):
    import time, hashlib, base64, rsa, urllib.parse, json, re, os
    if os.getenv("ENABLE_TEST_ENDPOINTS", "0") == "1":
        return GsalaryQueryDTO(
            payment_method_type="CARD",
            payment_status="SUCCESS",
            payment_result_message=None,
            payment_request_id=(body.paymentRequestId or None),
            payment_id=(body.paymentId or None),
            payment_amount=GsalaryQueryAmount(currency="GBP", amount=0.0),
            surcharge=None,
            gross_settlement_amount=None,
            customs_declaration_amount=None,
            payment_create_time=None,
            payment_time=None,
            captured=True,
            capture_time=None,
            settlement_quote=None,
            payment_result_info={"card_brand": "VISA", "last_four": "4242", "pm_id": "pm_test_4242"},
            transactions=[],
        )
    base_url = os.getenv("GSALARY_BASE_URL", "").rstrip("/")
    def _clean_path(p: str) -> str:
        p = re.sub(r"\u200b", "", p)
        p = re.sub(r"/+", "/", p)
        p = p.replace("gateway/v1/gateway/v1/", "gateway/v1/")
        return p
    path = os.getenv("GSALARY_QUERY_PAY_PATH", "/v1/gateway/v1/acquiring/pay")
    path = _clean_path(path)
    appid = os.getenv("GSALARY_APPID", "")
    mch_app_id = os.getenv("GSALARY_MCH_APP_ID", "")
    payload = {"mch_app_id": mch_app_id}
    if body.paymentRequestId:
        payload["payment_request_id"] = body.paymentRequestId
    if body.paymentId:
        payload["payment_id"] = body.paymentId
    method = "GET"
    timestamp = str(int(time.time()*1000))
    body_hash = base64.b64encode(hashlib.sha256(b"" ).digest()).decode()
    sign_base = f"{method} {path}\n{appid}\n{timestamp}\n{body_hash}\n"
    p = os.getenv("GSALARY_CLIENT_PRIVATE_KEY_PATH")
    pem = None
    if p:
        try:
            with open(p, "rb") as f:
                pem = f.read().decode("utf-8")
        except Exception:
            pem = None
    if not pem:
        if not base_url:
            return GsalaryQueryDTO(payment_method_type=None, payment_status="PAID", payment_result_message=None, payment_request_id=(body.paymentRequestId or None), payment_id=(body.paymentId or None))
        raise HTTPException(status_code=500, detail="missing client private key")
    try:
        priv = rsa.PrivateKey.load_pkcs1(pem.encode("utf-8"))
    except Exception:
        raise HTTPException(status_code=500, detail="invalid client private key")
    sig_bytes = rsa.sign(sign_base.encode("utf-8"), priv, "SHA-256")
    sig_b64 = base64.b64encode(sig_bytes).decode()
    sig_url = urllib.parse.quote(sig_b64, safe="")
    headers = {"X-Appid": appid, "Authorization": f"algorithm=RSA2,time={timestamp},signature={sig_url}"}
    rid = getattr(request.state, "request_id", None)
    if rid:
        headers["Request-Id"] = rid
    if not base_url:
        return GsalaryQueryDTO(payment_method_type=None, payment_status="PAID", payment_result_message=None, payment_request_id=(body.paymentRequestId or None), payment_id=(body.paymentId or None))
    d = _gateway_call(request, "GET", path, payload)
    amt = d.get("payment_amount") or {}
    sur = d.get("surcharge") or {}
    gross = d.get("gross_settlement_amount") or {}
    decl = d.get("customs_declaration_amount") or {}
    return GsalaryQueryDTO(
        payment_method_type=d.get("payment_method_type"),
        payment_status=d.get("payment_status"),
        payment_result_message=d.get("payment_result_message"),
        payment_request_id=d.get("payment_request_id"),
        payment_id=d.get("payment_id"),
        payment_amount=GsalaryQueryAmount(currency=amt.get("currency"), amount=amt.get("amount")),
        surcharge=GsalaryQueryAmount(currency=sur.get("currency"), amount=sur.get("amount")),
        gross_settlement_amount=GsalaryQueryAmount(currency=gross.get("currency"), amount=gross.get("amount")),
        customs_declaration_amount=GsalaryQueryAmount(currency=decl.get("currency"), amount=decl.get("amount")),
        payment_create_time=d.get("payment_create_time"),
        payment_time=d.get("payment_time"),
        captured=d.get("captured"),
        capture_time=d.get("capture_time"),
        settlement_quote=d.get("settlement_quote"),
        payment_result_info=d.get("payment_result_info"),
        transactions=d.get("transactions") or [],
    )

    
class GsalaryRefundBody(BaseModel):
    refundRequestId: str = Field(alias="refund_request_id")
    paymentRequestId: str = Field(alias="payment_request_id")
    refundCurrency: str = Field(alias="refund_currency")
    refundAmount: float = Field(alias="refund_amount")
    refundReason: str | None = Field(default=None, alias="refund_reason")

class GsalaryRefundDTO(BaseModel):
    refund_request_id: str
    refund_id: str
    payment_id: str | None = None
    payment_request_id: str | None = None
    refund_status: str | None = None
    refund_currency: str | None = None
    refund_amount: float | None = None
    refund_create_time: str | None = None

@app.post("/payments/gsalary/refund", response_model=GsalaryRefundDTO)
async def payments_gsalary_refund(request: Request, body: GsalaryRefundBody, current_user: ORMUser = Depends(get_current_user)):
    import time, hashlib, base64, rsa, urllib.parse, json, datetime, re
    base_url = os.getenv("GSALARY_BASE_URL", "").rstrip("/")
    def _clean_path(p: str) -> str:
        p = re.sub(r"\u200b", "", p)
        p = re.sub(r"/+", "/", p)
        p = p.replace("gateway/v1/gateway/v1/", "gateway/v1/")
        return p
    path = os.getenv("GSALARY_REFUND_PATH", "/v1/gateway/v1/acquiring/refund")
    path = _clean_path(path)
    idem_key = request.headers.get("Idempotency-Key")
    appid = os.getenv("GSALARY_APPID", "")
    mch_app_id = os.getenv("GSALARY_MCH_APP_ID", "")
    payload = {
        "mch_app_id": mch_app_id,
        "refund_request_id": body.refundRequestId,
        "payment_request_id": body.paymentRequestId,
        "refund_currency": body.refundCurrency,
        "refund_amount": body.refundAmount,
    }
    if body.refundReason is not None:
        payload["refund_reason"] = body.refundReason
    if os.getenv("ENABLE_TEST_ENDPOINTS", "0") == "1" or not base_url:
        now = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
        dto = GsalaryRefundDTO(
            refund_request_id=payload["refund_request_id"],
            refund_id=f"RFND-{payload['refund_request_id']}",
            payment_id=None,
            payment_request_id=payload["payment_request_id"],
            refund_status="PROCESSING",
            refund_currency=payload["refund_currency"],
            refund_amount=payload["refund_amount"],
            refund_create_time=now,
        )
        return dto
    method = "POST"
    timestamp = str(int(time.time()*1000))
    body_json = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    body_hash = base64.b64encode(hashlib.sha256(body_json.encode("utf-8")).digest()).decode()
    sign_base = f"{method} {path}\n{appid}\n{timestamp}\n{body_hash}\n"
    idem_body_hash = body_hash
    if idem_key:
        d = _idem_get(request, idem_key, idem_body_hash)
        if d:
            return GsalaryRefundDTO(**d)
    p = os.getenv("GSALARY_CLIENT_PRIVATE_KEY_PATH")
    pem = None
    if p:
        try:
            with open(p, "rb") as f:
                pem = f.read().decode("utf-8")
        except Exception:
            pem = None
    if not pem:
        if not base_url:
            now = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
            dto = GsalaryRefundDTO(
                refund_request_id=payload["refund_request_id"],
                refund_id=f"RFND-{payload['refund_request_id']}",
                payment_id=None,
                payment_request_id=payload["payment_request_id"],
                refund_status="PROCESSING",
                refund_currency=payload["refund_currency"],
                refund_amount=payload["refund_amount"],
                refund_create_time=now,
            )
            if idem_key:
                try:
                    _idem_set(request, idem_key, idem_body_hash, dto)
                except Exception:
                    pass
            return dto
        raise HTTPException(status_code=500, detail="missing client private key")
    try:
        priv = rsa.PrivateKey.load_pkcs1(pem.encode("utf-8"))
    except Exception:
        raise HTTPException(status_code=500, detail="invalid client private key")
    sig_bytes = rsa.sign(sign_base.encode("utf-8"), priv, "SHA-256")
    sig_b64 = base64.b64encode(sig_bytes).decode()
    sig_url = urllib.parse.quote(sig_b64, safe="")
    headers = {"Content-Type": "application/json", "X-Appid": appid, "Authorization": f"algorithm=RSA2,time={timestamp},signature={sig_url}"}
    rid = getattr(request.state, "request_id", None)
    if rid:
        headers["Request-Id"] = rid
        if not base_url:
            now = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
            dto = GsalaryRefundDTO(
                refund_request_id=payload["refund_request_id"],
                refund_id=f"RFND-{payload['refund_request_id']}",
                payment_id=None,
                payment_request_id=payload["payment_request_id"],
                refund_status="PROCESSING",
                refund_currency=payload["refund_currency"],
                refund_amount=payload["refund_amount"],
                refund_create_time=now,
            )
            if idem_key:
                try:
                    _idem_set(request, idem_key, idem_body_hash, dto)
                except Exception:
                    pass
            return dto
    d = _gateway_call(request, "POST", path, payload)
    dto = GsalaryRefundDTO(
        refund_request_id=d.get("refund_request_id") or payload["refund_request_id"],
        refund_id=d.get("refund_id") or "",
        payment_id=d.get("payment_id"),
        payment_request_id=d.get("payment_request_id") or payload["payment_request_id"],
        refund_status=d.get("refund_status"),
        refund_currency=d.get("refund_currency"),
        refund_amount=d.get("refund_amount"),
        refund_create_time=d.get("refund_create_time"),
    )
    try:
        if idem_key:
            _idem_set(request, idem_key, idem_body_hash, dto)
    except Exception:
        pass
    return dto

class GsalaryRefundQueryBody(BaseModel):
    refundRequestId: str | None = Field(default=None, alias="refund_request_id")
    refundId: str | None = Field(default=None, alias="refund_id")
    paymentRequestId: str | None = Field(default=None, alias="payment_request_id")

class GsalaryRefundQueryDTO(BaseModel):
    refund_id: str | None = None
    refund_request_id: str | None = None
    payment_id: str | None = None
    payment_request_id: str | None = None
    refund_currency: str | None = None
    refund_amount: float | None = None
    refund_status: str | None = None
    refund_time: str | None = None
    refund_create_time: str | None = None
    refund_result_message: str | None = None

@app.post("/payments/gsalary/refund/query", response_model=GsalaryRefundQueryDTO)
async def payments_gsalary_refund_query(request: Request, body: GsalaryRefundQueryBody, current_user: ORMUser = Depends(get_current_user)):
    import time, hashlib, base64, rsa, urllib.parse, json, re
    base_url = os.getenv("GSALARY_BASE_URL", "").rstrip("/")
    def _clean_path(p: str) -> str:
        p = re.sub(r"\u200b", "", p)
        p = re.sub(r"/+", "/", p)
        p = p.replace("gateway/v1/gateway/v1/", "gateway/v1/")
        return p
    path = (os.getenv("GSALARY_REFUND_QUERY_PATH") or os.getenv("GSALARY_REFUND_PATH") or "/v1/gateway/v1/acquiring/refund")
    path = _clean_path(path)
    appid = os.getenv("GSALARY_APPID", "")
    mch_app_id = os.getenv("GSALARY_MCH_APP_ID", "")
    payload = {"mch_app_id": mch_app_id}
    if os.getenv("ENABLE_TEST_ENDPOINTS", "0") == "1" or not base_url:
        return GsalaryRefundQueryDTO(refund_status="PROCESSING", refund_request_id=(body.refundRequestId or None), payment_request_id=(body.paymentRequestId or None))
    if body.refundRequestId:
        payload["refund_request_id"] = body.refundRequestId
    if body.refundId:
        payload["refund_id"] = body.refundId
    if body.paymentRequestId:
        payload["payment_request_id"] = body.paymentRequestId
    method = "GET"
    timestamp = str(int(time.time()*1000))
    body_hash = base64.b64encode(hashlib.sha256(b"" ).digest()).decode()
    sign_base = f"{method} {path}\n{appid}\n{timestamp}\n{body_hash}\n"
    p = os.getenv("GSALARY_CLIENT_PRIVATE_KEY_PATH")
    pem = None
    if p:
        try:
            with open(p, "rb") as f:
                pem = f.read().decode("utf-8")
        except Exception:
            pem = None
    if not pem:
        if not base_url:
            return GsalaryRefundQueryDTO(refund_id=None, refund_request_id=body.refundRequestId, payment_id=None, payment_request_id=body.paymentRequestId, refund_status="PROCESSING")
        raise HTTPException(status_code=500, detail="missing client private key")
    try:
        priv = rsa.PrivateKey.load_pkcs1(pem.encode("utf-8"))
    except Exception:
        raise HTTPException(status_code=500, detail="invalid client private key")
    sig_bytes = rsa.sign(sign_base.encode("utf-8"), priv, "SHA-256")
    sig_b64 = base64.b64encode(sig_bytes).decode()
    sig_url = urllib.parse.quote(sig_b64, safe="")
    headers = {"X-Appid": appid, "Authorization": f"algorithm=RSA2,time={timestamp},signature={sig_url}"}
    rid = getattr(request.state, "request_id", None)
    if rid:
        headers["Request-Id"] = rid
    if not base_url:
        return GsalaryRefundQueryDTO(refund_id=None, refund_request_id=body.refundRequestId, payment_id=None, payment_request_id=body.paymentRequestId, refund_status="PROCESSING")
    d = _gateway_call(request, "GET", path, payload)
    return GsalaryRefundQueryDTO(
        refund_id=d.get("refund_id"),
        refund_request_id=d.get("refund_request_id"),
        payment_id=d.get("payment_id"),
        payment_request_id=d.get("payment_request_id"),
        refund_currency=d.get("refund_currency"),
        refund_amount=d.get("refund_amount"),
        refund_status=d.get("refund_status"),
        refund_time=d.get("refund_time"),
        refund_create_time=d.get("refund_create_time"),
        refund_result_message=d.get("refund_result_message"),
    )

class GsalaryAuthTokenDTO(BaseModel):
    access_token: str | None = None
    access_token_expiry_time: str | None = None
    refresh_token: str | None = None
    refresh_token_expiry_time: str | None = None

@app.get("/payments/gsalary/auth/token", response_model=GsalaryAuthTokenDTO)
async def payments_gsalary_auth_token(current_user: ORMUser = Depends(get_current_user)):
    db = _get_db()
    try:
        rec = db.query(GSalaryAuthToken).filter(GSalaryAuthToken.user_id == current_user.id).first()
        if not rec:
            return GsalaryAuthTokenDTO()
        def _fmt(dt):
            try:
                return dt.isoformat() if dt else None
            except Exception:
                return None
        return GsalaryAuthTokenDTO(
            access_token=rec.access_token,
            access_token_expiry_time=_fmt(rec.access_token_expiry_time),
            refresh_token=rec.refresh_token,
            refresh_token_expiry_time=_fmt(rec.refresh_token_expiry_time),
        )
    finally:
        db.close()
# ===== Health & Status =====
@app.get("/health")
async def health(response: Response):
    return Response(status_code=204, headers={"Cache-Control": "no-store"})


@app.head("/health")
async def health_head(response: Response):
    return Response(status_code=204, headers={"Cache-Control": "no-store"})


@app.get("/status")
async def status():
    now = datetime.utcnow()
    uptime = int((now - SERVER_STARTED_AT).total_seconds())
    def _safe_len(x):
        try:
            return len(x) if x is not None else 0
        except Exception:
            return 0
    data = {
        "status": "ok",
        "version": app.version,
        "time": now.isoformat() + "Z",
        "uptimeSeconds": uptime,
        "caches": {
            "countries": _safe_len(getattr(catalog_service, "_countries_cache", None)),
            "regions": _safe_len(getattr(catalog_service, "_regions_cache", None)),
            "bundleListKeys": _safe_len(getattr(catalog_service, "_bundle_list_cache", {})),
            "bundleNetworksV2Keys": _safe_len(getattr(catalog_service, "_bundle_networks_v2_cache", {})),
            "ttlSeconds": int(getattr(catalog_service, "_list_ttl_seconds", 0)),
        },
    }
    return JSONResponse(content=jsonable_encoder(data))


@app.get("/status.html")
async def status_html():
    now = datetime.utcnow().isoformat() + "Z"
    uptime = int((datetime.utcnow() - SERVER_STARTED_AT).total_seconds())
    countries = len(getattr(catalog_service, "_countries_cache", []) or [])
    regions = len(getattr(catalog_service, "_regions_cache", []) or [])
    bundle_keys = len(getattr(catalog_service, "_bundle_list_cache", {}) or {})
    net_keys = len(getattr(catalog_service, "_bundle_networks_v2_cache", {}) or {})
    ttl = int(getattr(catalog_service, "_list_ttl_seconds", 0))
    html = f"""
    <!doctype html>
    <html>
      <head>
        <meta charset='utf-8'>
        <meta name='viewport' content='width=device-width, initial-scale=1'>
        <title>Simigo Status</title>
        <style>
          body {{ font-family: -apple-system, system-ui, Segoe UI, Roboto, Helvetica, Arial, sans-serif; margin: 24px; color: #222; }}
          h1 {{ font-size: 20px; margin-bottom: 12px; }}
          .grid {{ display: grid; grid-template-columns: 160px auto; gap: 8px 16px; align-items: center; }}
          .key {{ color: #555; }}
          .val {{ font-weight: 600; }}
        </style>
      </head>
      <body>
        <h1>Simigo Backend Status</h1>
        <div class='grid'>
          <div class='key'>status</div><div class='val'>ok</div>
          <div class='key'>version</div><div class='val'>{app.version}</div>
          <div class='key'>time</div><div class='val'>{now}</div>
          <div class='key'>uptimeSeconds</div><div class='val'>{uptime}</div>
          <div class='key'>countriesCache</div><div class='val'>{countries}</div>
          <div class='key'>regionsCache</div><div class='val'>{regions}</div>
          <div class='key'>bundleListKeys</div><div class='val'>{bundle_keys}</div>
          <div class='key'>bundleNetworksV2Keys</div><div class='val'>{net_keys}</div>
          <div class='key'>ttlSeconds</div><div class='val'>{ttl}</div>
        </div>
      </body>
    </html>
    """
    return HTMLResponse(content=html)
