from __future__ import annotations
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response
import uuid


class RequestIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        req_id = request.headers.get("X-Request-Id") or request.headers.get("Request-Id") or uuid.uuid4().hex
        # Attach to request state for downstream access (service/provider forwarding)
        try:
            request.state.request_id = req_id
        except Exception:
            # state may not exist in some contexts; ignore silently
            pass
        response: Response = await call_next(request)
        response.headers["X-Request-Id"] = req_id
        return response