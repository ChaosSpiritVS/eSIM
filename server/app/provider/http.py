from __future__ import annotations
import os
from typing import Any, Dict
import httpx
import time
import random

from .auth import TokenManager
from .errors import raise_for_provider


class ProviderHTTP:
    def __init__(self, token_mgr: TokenManager):
        self.token_mgr = token_mgr
        self.base_url = os.getenv("PROVIDER_BASE_URL", "")
        try:
            timeout_s = float(os.getenv("PROVIDER_HTTP_TIMEOUT", "15"))
        except Exception:
            timeout_s = 15.0
        ct = os.getenv("PROVIDER_HTTP_CONNECT_TIMEOUT")
        rt = os.getenv("PROVIDER_HTTP_READ_TIMEOUT")
        wt = os.getenv("PROVIDER_HTTP_WRITE_TIMEOUT")
        try:
            connect_timeout = float(ct) if ct else None
        except Exception:
            connect_timeout = None
        try:
            read_timeout = float(rt) if rt else None
        except Exception:
            read_timeout = None
        try:
            write_timeout = float(wt) if wt else None
        except Exception:
            write_timeout = None
        timeout: httpx.Timeout | float
        if connect_timeout or read_timeout or write_timeout:
            timeout = httpx.Timeout(
                connect=connect_timeout or timeout_s,
                read=read_timeout or timeout_s,
                write=write_timeout or timeout_s,
                pool=None,
            )
        else:
            timeout = timeout_s
        try:
            max_conns = int(os.getenv("PROVIDER_HTTP_MAX_CONNECTIONS", "100"))
        except Exception:
            max_conns = 100
        try:
            max_keepalive = int(os.getenv("PROVIDER_HTTP_MAX_KEEPALIVE", "20"))
        except Exception:
            max_keepalive = 20
        limits = httpx.Limits(max_connections=max_conns, max_keepalive_connections=max_keepalive)
        self._client = httpx.Client(timeout=timeout, limits=limits)

    def post(self, path: str, json: Dict[str, Any], extra_headers: Dict[str, str] | None = None, include_token: bool = True) -> Dict[str, Any]:
        """
        Calls upstream POST and handles unified response: {code, data, msg}
        In fake mode or missing base_url, returns an empty success envelope.
        """
        headers = {
            "Content-Type": "application/json",
        }
        if include_token:
            token = self.token_mgr.get_token()
            headers["Access-Token"] = token
        # Merge extra headers (e.g., X-Request-Id) if provided
        if extra_headers:
            headers.update({k: v for k, v in extra_headers.items() if v is not None})
        if not self.base_url or self.token_mgr.fake:
            # Fake envelope
            return {"code": 0, "data": {}, "msg": "ok"}

        url = self.base_url.rstrip("/") + path
        client = self._client
        try:
            retries = int(os.getenv("PROVIDER_HTTP_RETRIES", "2"))
        except Exception:
            retries = 2
        try:
            backoff_ms = float(os.getenv("PROVIDER_HTTP_BACKOFF_MS", "200"))
        except Exception:
            backoff_ms = 200.0
        attempt = 0
        while True:
            try:
                resp = client.post(url, json=json, headers=headers)
                resp.raise_for_status()
            except httpx.HTTPStatusError as e:
                status_code = e.response.status_code if e.response is not None else None
                if status_code == 401 and include_token:
                    try:
                        self.token_mgr.refresh()
                        headers["Access-Token"] = self.token_mgr.get_token()
                        resp = client.post(url, json=json, headers=headers)
                        resp.raise_for_status()
                    except Exception:
                        pass
                else:
                    if status_code and status_code >= 500 and attempt < retries:
                        delay = (backoff_ms / 1000.0) * (2 ** attempt) + (random.random() * 0.05)
                        time.sleep(delay)
                        attempt += 1
                        continue
                    raise_for_provider(-1, "upstream http error")
            except httpx.RequestError:
                if attempt < retries:
                    delay = (backoff_ms / 1000.0) * (2 ** attempt) + (random.random() * 0.05)
                    time.sleep(delay)
                    attempt += 1
                    continue
                raise_for_provider(-1, "network error")
            try:
                envelope = resp.json()
            except Exception:
                if attempt < retries:
                    delay = (backoff_ms / 1000.0) * (2 ** attempt) + (random.random() * 0.05)
                    time.sleep(delay)
                    attempt += 1
                    continue
                raise_for_provider(-1, "invalid response")
            break
        code = envelope.get("code")
        msg = envelope.get("msg", "")
        data = envelope.get("data") or {}
        success = (code in (None, 0, 200)) and not (
            isinstance(data, dict) and data.get("err_code")
        )
        if success:
            return envelope
        err_code = None
        err_msg = None
        if isinstance(data, dict):
            err_code = data.get("err_code")
            err_msg = data.get("err_msg", msg)
        if err_code is None:
            err_code = code if code not in (0, 200) else None
            err_msg = msg
            # Try refresh on 411
            if err_code == 411 and include_token:
                self.token_mgr.refresh()
                headers["Access-Token"] = self.token_mgr.get_token()
                resp = client.post(url, json=json, headers=headers)
                resp.raise_for_status()
                envelope = resp.json()
                code = envelope.get("code")
                msg = envelope.get("msg", "")
                data = envelope.get("data") or {}
                success = (code in (None, 0, 200)) and not (
                    isinstance(data, dict) and data.get("err_code")
                )
                if success:
                    return envelope
                # Fall through to raise with new error info
                if isinstance(data, dict):
                    err_code = data.get("err_code")
                    err_msg = data.get("err_msg", msg)
                else:
                    err_code = code
                    err_msg = msg
            raise_for_provider(err_code or -1, err_msg or "provider error")