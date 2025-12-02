from __future__ import annotations
import os
from datetime import datetime, timedelta, timezone
from typing import Any, Dict

from jose import jwt, JWTError


ALGORITHM = "HS256"


def _secret() -> str:
    sec = os.getenv("JWT_SECRET")
    if not sec:
        # Development default; strongly recommend setting JWT_SECRET in production
        sec = "dev-secret-change-me"
    return sec


def create_access_token(subject: str, expires_delta: timedelta | None = None, extra: Dict[str, Any] | None = None) -> str:
    to_encode: Dict[str, Any] = {"sub": subject}
    if extra:
        to_encode.update(extra)
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(minutes=30))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, _secret(), algorithm=ALGORITHM)


def decode_token(token: str) -> Dict[str, Any]:
    try:
        return jwt.decode(token, _secret(), algorithms=[ALGORITHM])
    except JWTError as e:
        raise ValueError(str(e))