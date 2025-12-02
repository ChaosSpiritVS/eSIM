from __future__ import annotations
import os
import time
import uuid
from typing import Optional, Dict, Any
import httpx


class TokenManager:
    """简单的令牌管理器：使用内存存储，并支持可选的假数据模式。"""

    def __init__(self):
        self._token: Optional[str] = os.getenv("PROVIDER_ACCESS_TOKEN")
        # 若未提供明确的过期时间，默认 24 小时
        self._expires_at: float = time.time() + 86400 if self._token else 0
        self._refresh_token: Optional[str] = None
        self._refresh_expires_at: float = 0
        self.fake: bool = os.getenv("PROVIDER_FAKE", "true").lower() in ("1", "true", "yes")

    def get_token(self) -> str:
        if self.fake:
            return self._token or "fake-access-token"
        if not self._token or time.time() > self._expires_at:
            self.refresh()
        return self._token or ""

    def refresh(self):
        """
        通过调用上游的登录/刷新接口来刷新令牌。
        在假数据模式下，仅设置一个新的本地令牌即可。
        """
        if self.fake:
            self._token = "fake-access-token"
            # 假数据模式下的默认过期时间：24 小时
            self._expires_at = time.time() + 86400
            return
        # 真实模式：优先使用已存储的 refresh_token 进行刷新；失败则回退到登录
        try:
            if self._refresh_token and time.time() < (self._refresh_expires_at or 0):
                self._agent_refresh()
            else:
                self._agent_login()
        except Exception:
            # 刷新失败（如 401/过期）时，尝试重新登录。
            try:
                self._agent_login()
                return
            except Exception:
                # 最终回退：若环境变量中已有令牌，则使用该令牌
                existing = os.getenv("PROVIDER_ACCESS_TOKEN")
                if existing:
                    self._token = existing
                    # 环境令牌默认过期时间：24 小时
                    self._expires_at = time.time() + 86400
                else:
                    raise

    def _agent_login(self):
        base_url = os.getenv("PROVIDER_BASE_URL", "").rstrip("/")
        username = os.getenv("PROVIDER_AGENT_USERNAME")
        password = os.getenv("PROVIDER_AGENT_PASSWORD")
        if not base_url or not username or not password:
            raise RuntimeError("Missing PROVIDER_BASE_URL/PROVIDER_AGENT_USERNAME/PROVIDER_AGENT_PASSWORD")
        login_path = os.getenv("PROVIDER_LOGIN_PATH", "/agent/login")
        url = base_url + login_path
        headers = {
            "Content-Type": "application/json",
            # 若未显式提供，则为上游登录生成一个 Request-Id
            "Request-Id": uuid.uuid4().hex,
        }
        payload: Dict[str, Any] = {"username": username, "password": password}
        with httpx.Client(timeout=10.0) as client:
            resp = client.post(url, json=payload, headers=headers)
            resp.raise_for_status()
            envelope = resp.json()
            code = envelope.get("code")
            data = envelope.get("data") or {}
            # 成功条件：code 为 200 或 0，且返回中包含 access_token
            if (code in (0, 200)) and data.get("access_token"):
                self._token = data.get("access_token")
                # 优先使用 expires_at；否则退回到 expires_in
                expires_at = data.get("expires_at")
                expires_in = data.get("expires_in")
                if isinstance(expires_at, (int, float)) and expires_at > time.time():
                    self._expires_at = float(expires_at)
                elif isinstance(expires_in, (int, float)) and expires_in > 0:
                    self._expires_at = time.time() + float(expires_in)
                else:
                    # 上游未提供过期参数时的默认：24 小时
                    self._expires_at = time.time() + 86400
                self._refresh_token = data.get("refresh_token")
                r_expires_in = data.get("refresh_expires_in")
                if isinstance(r_expires_in, (int, float)) and r_expires_in > 0:
                    self._refresh_expires_at = time.time() + float(r_expires_in)
                return
            # 错误处理：优先读取 data 内的 err_code/err_msg
            err_code = None
            err_msg = None
            if isinstance(data, dict):
                err_code = data.get("err_code")
                err_msg = data.get("err_msg")
            if err_code is None:
                err_code = envelope.get("code")
                err_msg = envelope.get("msg", "")
            raise RuntimeError(f"agent login failed: code={err_code}, msg={err_msg}")

    def _agent_refresh(self):
        base_url = os.getenv("PROVIDER_BASE_URL", "").rstrip("/")
        if not base_url or not self._refresh_token:
            raise RuntimeError("Missing PROVIDER_BASE_URL or refresh_token for agent refresh")
        refresh_path = os.getenv("PROVIDER_REFRESH_PATH", "/agent/refreshToken")
        url = base_url + refresh_path
        headers = {
            "Content-Type": "application/json",
            "Request-Id": uuid.uuid4().hex,
        }
        payload: Dict[str, Any] = {"refresh_token": self._refresh_token}
        with httpx.Client(timeout=10.0) as client:
            resp = client.post(url, json=payload, headers=headers)
            resp.raise_for_status()
            envelope = resp.json()
            code = envelope.get("code")
            data = envelope.get("data") or {}
            if (code in (0, 200)) and data.get("access_token"):
                self._token = data.get("access_token")
                expires_at = data.get("expires_at")
                expires_in = data.get("expires_in")
                if isinstance(expires_at, (int, float)) and expires_at > time.time():
                    self._expires_at = float(expires_at)
                elif isinstance(expires_in, (int, float)) and expires_in > 0:
                    self._expires_at = time.time() + float(expires_in)
                else:
                    # 上游未提供过期参数时的默认：24 小时
                    self._expires_at = time.time() + 86400
                new_refresh = data.get("refresh_token")
                r_expires_in = data.get("refresh_expires_in")
                if new_refresh:
                    self._refresh_token = new_refresh
                if isinstance(r_expires_in, (int, float)) and r_expires_in > 0:
                    self._refresh_expires_at = time.time() + float(r_expires_in)
                return
            err_code = None
            err_msg = None
            if isinstance(data, dict):
                err_code = data.get("err_code")
                err_msg = data.get("err_msg")
            if err_code is None:
                err_code = envelope.get("code")
                err_msg = envelope.get("msg", "")
            raise RuntimeError(f"agent refresh failed: code={err_code}, msg={err_msg}")