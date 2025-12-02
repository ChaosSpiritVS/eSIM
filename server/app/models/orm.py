from __future__ import annotations
from datetime import datetime, timedelta
import hashlib
import uuid
from typing import Optional

from sqlalchemy import (
    Column,
    String,
    DateTime,
    Boolean,
    Float,
    ForeignKey,
    Integer,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship, Mapped, mapped_column

from ..db import Base


def _uuid() -> str:
    return uuid.uuid4().hex


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    name: Mapped[str] = mapped_column(String(200))
    # Optional last name (family name)
    last_name: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    email: Mapped[Optional[str]] = mapped_column(String(255), unique=True, index=True, nullable=True)
    password_hash: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    apple_id: Mapped[Optional[str]] = mapped_column(String(255), unique=True, index=True, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    # Profile fields
    language: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)
    currency: Mapped[Optional[str]] = mapped_column(String(8), nullable=True)
    country: Mapped[Optional[str]] = mapped_column(String(2), nullable=True)

    sessions: Mapped[list[Session]] = relationship("Session", back_populates="user", cascade="all, delete-orphan")
    # 保留订单记录：移除 delete-orphan 级联，避免在删除用户时误删订单
    orders: Mapped[list[Order]] = relationship("Order", back_populates="user")


class Session(Base):
    __tablename__ = "sessions"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    refresh_token_hash: Mapped[str] = mapped_column(String(64), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    revoked: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    user: Mapped[User] = relationship("User", back_populates="sessions")

    @staticmethod
    def hash_token(token: str) -> str:
        return hashlib.sha256(token.encode("utf-8")).hexdigest()


class Order(Base):
    __tablename__ = "orders"
    __table_args__ = (
        UniqueConstraint("provider_order_id", name="uq_orders_provider_order_id"),
    )

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id", ondelete="SET NULL"), index=True, nullable=True)
    provider_order_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    bundle_id: Mapped[str] = mapped_column(String(64))
    amount: Mapped[float] = mapped_column(Float)
    currency: Mapped[str] = mapped_column(String(8), default="GBP")
    status: Mapped[str] = mapped_column(String(32), default="created")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    user: Mapped[Optional[User]] = relationship("User", back_populates="orders")


class OrderReferenceEmail(Base):
    __tablename__ = "order_reference_emails"
    __table_args__ = (
        UniqueConstraint("order_reference", name="uq_order_ref_email_reference"),
        UniqueConstraint("provider_order_id", name="uq_order_ref_email_provider_order_id"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    # 上游订单引用（来自客户端传入），用于回查与过滤
    order_reference: Mapped[str] = mapped_column(String(64), index=True)
    # 上游订单ID（assign成功后返回），用于稳定过滤
    provider_order_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True, index=True)
    # 用户ID（稳定主键），用于关联而非依赖易变邮箱
    user_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    # 当时的邮箱快照（仅作为辅助展示/回退）
    email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True, index=True)
    request_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    assigned_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    updated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class LanguageOption(Base):
    __tablename__ = "settings_languages"

    code: Mapped[str] = mapped_column(String(32), primary_key=True)
    name: Mapped[str] = mapped_column(String(200))


class CurrencyOption(Base):
    __tablename__ = "settings_currencies"

    code: Mapped[str] = mapped_column(String(16), primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    symbol: Mapped[Optional[str]] = mapped_column(String(8), nullable=True)


class I18nCountryName(Base):
    __tablename__ = "i18n_country_names"
    __table_args__ = (
        UniqueConstraint("iso2_code", "lang_code", name="uq_i18n_country_iso2_lang"),
        UniqueConstraint("iso3_code", "lang_code", name="uq_i18n_country_iso3_lang"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    iso2_code: Mapped[Optional[str]] = mapped_column(String(2), nullable=True, index=True)
    iso3_code: Mapped[Optional[str]] = mapped_column(String(3), nullable=True, index=True)
    lang_code: Mapped[str] = mapped_column(String(32), index=True)
    name: Mapped[str] = mapped_column(String(200))
    logo: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)


class I18nRegionName(Base):
    __tablename__ = "i18n_region_names"
    __table_args__ = (
        UniqueConstraint("region_code", "lang_code", name="uq_i18n_region_code_lang"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    region_code: Mapped[str] = mapped_column(String(16), index=True)
    lang_code: Mapped[str] = mapped_column(String(32), index=True)
    name: Mapped[str] = mapped_column(String(200))


class I18nBundleName(Base):
    __tablename__ = "i18n_bundle_names"
    __table_args__ = (
        UniqueConstraint("bundle_code", "lang_code", name="uq_i18n_bundle_code_lang"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    bundle_code: Mapped[str] = mapped_column(String(64), index=True)
    lang_code: Mapped[str] = mapped_column(String(32), index=True)
    marketing_name: Mapped[str] = mapped_column(String(200))
    name: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    description: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)


class RecentSearch(Base):
    __tablename__ = "recent_searches"
    __table_args__ = (
        UniqueConstraint("user_id", "kind", "entity_id", name="uq_recent_user_kind_entity"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    kind: Mapped[str] = mapped_column(String(16), index=True)
    entity_id: Mapped[str] = mapped_column(String(128), index=True)
    bundle_code: Mapped[Optional[str]] = mapped_column(String(64), nullable=True, index=True)
    country_code: Mapped[Optional[str]] = mapped_column(String(3), nullable=True, index=True)
    region_code: Mapped[Optional[str]] = mapped_column(String(16), nullable=True, index=True)
    title_snapshot: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    subtitle_snapshot: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    hits: Mapped[int] = mapped_column(Integer, default=1)
    last_seen: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class PasswordResetToken(Base):
    __tablename__ = "password_reset_tokens"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    used_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    user: Mapped[User] = relationship("User")

class EmailVerificationCode(Base):
    __tablename__ = "email_verification_codes"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    # 注册时没有用户，改邮箱时可以带 user_id
    user_id: Mapped[Optional[str]] = mapped_column(String(32), ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    email: Mapped[str] = mapped_column(String(255), index=True)
    # 4 位验证码的哈希
    code_hash: Mapped[str] = mapped_column(String(64), index=True)
    purpose: Mapped[str] = mapped_column(String(32))  # register | change_email
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    used_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    @staticmethod
    def hash_code(code: str) -> str:
        return hashlib.sha256(code.encode("utf-8")).hexdigest()


class AccountDeletionLog(Base):
    __tablename__ = "account_deletion_logs"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    # Keep FK but allow user to be deleted without removing log
    user_id: Mapped[Optional[str]] = mapped_column(String(32), ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    # Snapshot email at deletion time for easier audit
    email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    # Controlled set on client; cap length for safety
    reason: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    # Free text with server limit; cap at 1000 chars
    details: Mapped[Optional[str]] = mapped_column(String(1000), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    user: Mapped[Optional[User]] = relationship("User")


class RefundRequest(Base):
    __tablename__ = "refund_requests"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    order_id: Mapped[str] = mapped_column(String(64), index=True)
    user_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    reason: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    state: Mapped[str] = mapped_column(String(16), default="requested")
    steps_json: Mapped[Optional[str]] = mapped_column(String(4000), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    user: Mapped[User] = relationship("User")


class GSalaryAuthToken(Base):
    __tablename__ = "gsalary_auth_tokens"
    __table_args__ = (
        UniqueConstraint("user_id", name="uq_gsalary_auth_tokens_user"),
    )

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    access_token: Mapped[Optional[str]] = mapped_column(String(512), nullable=True)
    access_token_expiry_time: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    refresh_token: Mapped[Optional[str]] = mapped_column(String(512), nullable=True)
    refresh_token_expiry_time: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    user: Mapped[User] = relationship("User")


    


class IdempotencyRecord(Base):
    __tablename__ = "idempotency_records"
    __table_args__ = (
        UniqueConstraint("key", "route", "method", name="uq_idem_key_route_method"),
    )

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    key: Mapped[str] = mapped_column(String(256), index=True)
    route: Mapped[str] = mapped_column(String(256))
    method: Mapped[str] = mapped_column(String(16))
    body_hash: Mapped[Optional[str]] = mapped_column(String(128), nullable=True)
    response_json: Mapped[str] = mapped_column(String(10000))
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
