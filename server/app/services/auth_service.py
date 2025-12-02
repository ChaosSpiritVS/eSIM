from __future__ import annotations
from datetime import datetime, timedelta
import os
import secrets
from typing import Optional

from sqlalchemy.orm import Session
from passlib.context import CryptContext

from ..db import SessionLocal
from ..models.orm import User, Session as UserSession, PasswordResetToken, AccountDeletionLog, EmailVerificationCode
from ..models.dto import (
    UserDTO,
    RegisterBody,
    LoginBody,
    AppleLoginBody,
    ResetDTO,
    AuthResponseDTO,
    SuccessDTO,
    EmailCodeDTO,
)
from ..security.jwt import create_access_token
from ..provider.email import EmailGateway


pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")


class AuthService:
    """Auth service backed by SQLAlchemy models: users and sessions."""

    def __init__(self):
        # Initialize optional email gateway (no-op unless configured)
        self.email = EmailGateway.from_env()

    def _get_db(self) -> Session:
        return SessionLocal()

    def _hash_password(self, password: str) -> str:
        return pwd_context.hash(password)

    def _verify_password(self, password: str, password_hash: str | None) -> bool:
        if not password_hash:
            return False
        try:
            return pwd_context.verify(password, password_hash)
        except Exception:
            return False

    def _issue_tokens(self, user: User, db: Session) -> AuthResponseDTO:
        # Access token embeds subject (user id)
        access_minutes = int(os.getenv("JWT_ACCESS_MINUTES", "30"))
        refresh_days = int(os.getenv("JWT_REFRESH_DAYS", "14"))
        access_token = create_access_token(subject=user.id, expires_delta=timedelta(minutes=access_minutes))

        # Refresh token: random string stored hashed
        refresh_token = secrets.token_urlsafe(32)
        sess = UserSession(
            user_id=user.id,
            refresh_token_hash=UserSession.hash_token(refresh_token),
            expires_at=datetime.utcnow() + timedelta(days=refresh_days),
            revoked=False,
        )
        db.add(sess)
        db.commit()
        return AuthResponseDTO(
            user=UserDTO(
                id=user.id,
                name=user.name,
                lastName=user.last_name,
                email=user.email,
                hasPassword=bool(user.password_hash),
                language=user.language,
                currency=user.currency,
                country=user.country,
            ),
            accessToken=access_token,
            refreshToken=refresh_token,
        )

    def register(self, body: RegisterBody) -> AuthResponseDTO:
        email = body.email.strip().lower()
        if not email:
            raise ValueError("email is required")
        db = self._get_db()
        try:
            # 可通过环境变量启用注册邮箱强制校验
            require_email_verification = os.getenv("REGISTER_REQUIRE_EMAIL_VERIFICATION", "true").lower() in ("1", "true", "yes")
            if require_email_verification:
                self._assert_email_code_valid(db, email=email, code=(body.verificationCode or ""), purpose="register")
            existing = db.query(User).filter(User.email == email).first()
            if existing:
                # 开发模式下允许在“重新注册”时更新密码，避免用户以为新密码已生效但实际上未更新。
                # 生产环境请将 REGISTER_DEV_UPDATE_PASSWORD 设为 false 以避免凭证被覆盖。
                allow_update = os.getenv("REGISTER_DEV_UPDATE_PASSWORD", "true").lower() in ("1", "true", "yes")
                if allow_update:
                    existing.password_hash = self._hash_password(body.password)
                    db.add(existing)
                    db.commit()
                    db.refresh(existing)
                # 返回现有用户的令牌，保持流程一致
                return self._issue_tokens(existing, db)
            user = User(
                name=body.name,
                last_name=body.lastName,
                email=email,
                password_hash=self._hash_password(body.password),
            )
            db.add(user)
            db.commit()
            db.refresh(user)
            return self._issue_tokens(user, db)
        finally:
            db.close()

    def login(self, body: LoginBody) -> Optional[AuthResponseDTO]:
        email = body.email.strip().lower()
        db = self._get_db()
        try:
            user = db.query(User).filter(User.email == email).first()
            if not user:
                return None
            if not self._verify_password(body.password, user.password_hash):
                return None
            return self._issue_tokens(user, db)
        finally:
            db.close()

    def login_apple(self, body: AppleLoginBody) -> AuthResponseDTO:
        db = self._get_db()
        try:
            user = None
            if body.userId:
                user = db.query(User).filter(User.apple_id == body.userId).first()
            if not user:
                user = User(name="Apple 用户", apple_id=body.userId, email=None)
                db.add(user)
                db.commit()
                db.refresh(user)
            return self._issue_tokens(user, db)
        finally:
            db.close()

    def password_reset(self, email: str) -> ResetDTO:
        # Normalize email, lookup user, and issue a one-time reset token.
        # Always return success to avoid email enumeration leaks.
        try:
            normalized = (email or "").strip().lower()
        except Exception:
            normalized = ""
        db = self._get_db()
        try:
            user = None
            if normalized:
                user = db.query(User).filter(User.email == normalized).first()
            # Generate and persist token only if user exists and has an email
            dev_token: str | None = None
            if user and user.email:
                # Create token and store hashed with expiration (30 minutes)
                raw = secrets.token_urlsafe(32)
                token_hash = UserSession.hash_token(raw)
                expires = datetime.utcnow() + timedelta(minutes=int(os.getenv("RESET_TOKEN_MINUTES", "30")))
                rec = PasswordResetToken(user_id=user.id, token_hash=token_hash, expires_at=expires, used_at=None)
                db.add(rec)
                db.commit()
                # For development convenience, optionally expose token in response
                if os.getenv("RESET_DEV_EXPOSE_TOKEN", "true").lower() in ("1", "true", "yes"):
                    dev_token = raw
                # Build a usable link for local testing or production
                base = os.getenv("RESET_CONFIRM_BASE_URL", "simigo://reset")
                link = f"{base}?token={raw}"
                print(f"[DEV] Password reset issued for {normalized}: {link}")
                # If email gateway is enabled, send the reset email (best-effort)
                try:
                    self.email.send_password_reset(user.email, link, locale=user.language)
                except Exception:
                    # Swallow errors to avoid signal; log-only in real-world
                    pass
            return ResetDTO(success=True, devToken=dev_token)
        finally:
            db.close()

    def confirm_password_reset(self, token: str, new_password: str) -> SuccessDTO:
        # Validate token, not expired or used, then update user password and mark token used.
        if not new_password or len(new_password) < 8:
            raise ValueError("weak_password")
        if not token or len(token) < 16:
            raise ValueError("token_invalid")
        db = self._get_db()
        try:
            h = UserSession.hash_token(token)
            rec = db.query(PasswordResetToken).filter(PasswordResetToken.token_hash == h).first()
            if not rec:
                raise ValueError("token_invalid")
            if rec.used_at is not None:
                raise ValueError("token_used")
            if rec.expires_at < datetime.utcnow():
                raise ValueError("token_expired")
            user = db.query(User).filter(User.id == rec.user_id).first()
            if not user:
                raise ValueError("user_not_found")
            # Update password and mark token used
            user.password_hash = self._hash_password(new_password)
            rec.used_at = datetime.utcnow()
            db.add(user)
            db.add(rec)
            # Revoke all refresh sessions to force re-login
            db.query(UserSession).filter(UserSession.user_id == user.id, UserSession.revoked == False).update({UserSession.revoked: True})
            db.commit()
            return SuccessDTO(success=True)
        finally:
            db.close()

    def revoke_refresh_token(self, refresh_token: str) -> bool:
        db = self._get_db()
        try:
            h = UserSession.hash_token(refresh_token)
            sess = db.query(UserSession).filter(UserSession.refresh_token_hash == h).first()
            if not sess:
                return False
            sess.revoked = True
            db.add(sess)
            db.commit()
            return True
        finally:
            db.close()

    def refresh_tokens(self, refresh_token: str) -> Optional[AuthResponseDTO]:
        db = self._get_db()
        try:
            h = UserSession.hash_token(refresh_token)
            sess = db.query(UserSession).filter(UserSession.refresh_token_hash == h).first()
            if not sess or sess.revoked or sess.expires_at < datetime.utcnow():
                return None
            user = db.query(User).filter(User.id == sess.user_id).first()
            if not user:
                return None
            # Optionally rotate refresh token: revoke old and issue new one
            sess.revoked = True
            db.add(sess)
            db.commit()
            return self._issue_tokens(user, db)
        finally:
            db.close()

    # ===== Account operations =====
    def change_email(self, user_id: str, new_email: str, password: str, verification_code: Optional[str] = None) -> Optional[UserDTO]:
        email = new_email.strip().lower()
        if not email or "@" not in email:
            raise ValueError("invalid email")
        require_email_verification = os.getenv("CHANGE_EMAIL_REQUIRE_VERIFICATION", "true").lower() in ("1", "true", "yes")
        db = self._get_db()
        try:
            user = db.query(User).filter(User.id == user_id).first()
            if not user:
                return None
            if not user.password_hash:
                # Require setting a password first
                raise ValueError("password_required_for_email_change")
            if not self._verify_password(password, user.password_hash):
                raise ValueError("invalid_password")
            existing = db.query(User).filter(User.email == email).first()
            if existing and existing.id != user.id:
                raise ValueError("email_taken")
            if require_email_verification:
                self._assert_email_code_valid(db, email=email, code=(verification_code or ""), purpose="change_email")
            user.email = email
            db.add(user)
            db.commit()
            db.refresh(user)
            return UserDTO(
                id=user.id,
                name=user.name,
                lastName=user.last_name,
                email=user.email,
                hasPassword=bool(user.password_hash),
                language=user.language,
                currency=user.currency,
                country=user.country,
            )
        finally:
            db.close()

    def update_password(self, user_id: str, new_password: str, current_password: Optional[str]) -> SuccessDTO:
        if not new_password or len(new_password) < 8:
            raise ValueError("weak_password")
        db = self._get_db()
        try:
            user = db.query(User).filter(User.id == user_id).first()
            if not user:
                raise ValueError("user_not_found")
            if user.password_hash:
                if not current_password or not self._verify_password(current_password, user.password_hash):
                    raise ValueError("invalid_password")
            user.password_hash = self._hash_password(new_password)
            db.add(user)
            db.commit()
            return SuccessDTO(success=True)
        finally:
            db.close()

    # ===== Email verification code issuance & validation =====
    def request_email_code(self, email: str, purpose: str, user_id: Optional[str] = None) -> EmailCodeDTO:
        try:
            normalized = (email or "").strip().lower()
        except Exception:
            normalized = ""
        if not normalized or "@" not in normalized:
            return EmailCodeDTO(success=True, devCode=None)
        if purpose not in ("register", "change_email"):
            return EmailCodeDTO(success=True, devCode=None)
        db = self._get_db()
        try:
            code = f"{secrets.randbelow(10000):04d}"
            code_hash = EmailVerificationCode.hash_code(code)
            expires = datetime.utcnow() + timedelta(minutes=int(os.getenv("EMAIL_CODE_MINUTES", "10")))
            rec = EmailVerificationCode(user_id=user_id, email=normalized, code_hash=code_hash, purpose=purpose, expires_at=expires, used_at=None)
            db.add(rec)
            db.commit()
            dev_code = None
            if os.getenv("EMAIL_CODE_DEV_EXPOSE", "true").lower() in ("1", "true", "yes"):
                dev_code = code
            try:
                self.email.send_email_code(normalized, code)
            except Exception:
                pass
            return EmailCodeDTO(success=True, devCode=dev_code)
        finally:
            db.close()

    def _assert_email_code_valid(self, db: Session, email: str, code: str, purpose: str) -> None:
        if not code or len(code) != 4:
            raise ValueError("invalid_email_code")
        h = EmailVerificationCode.hash_code(code)
        rec = (
            db.query(EmailVerificationCode)
            .filter(EmailVerificationCode.email == email, EmailVerificationCode.code_hash == h, EmailVerificationCode.purpose == purpose)
            .order_by(EmailVerificationCode.created_at.desc())
            .first()
        )
        if not rec:
            raise ValueError("invalid_email_code")
        if rec.used_at is not None:
            raise ValueError("email_code_used")
        if rec.expires_at < datetime.utcnow():
            raise ValueError("email_code_expired")
        rec.used_at = datetime.utcnow()
        db.add(rec)
        db.commit()

    def delete_account(self, user_id: str, current_password: Optional[str], reason: Optional[str] = None, details: Optional[str] = None) -> SuccessDTO:
        db = self._get_db()
        try:
            user = db.query(User).filter(User.id == user_id).first()
            if not user:
                return SuccessDTO(success=True)
            if user.password_hash:
                if not current_password or not self._verify_password(current_password, user.password_hash):
                    raise ValueError("invalid_password")
            # Normalize and cap inputs for safety
            try:
                r = (reason or "").strip() or None
            except Exception:
                r = None
            try:
                d = (details or "").strip() or None
            except Exception:
                d = None
            if d and len(d) > 1000:
                d = d[:1000]
            # Record deletion log before removing user
            log = AccountDeletionLog(user_id=user.id, email=user.email, reason=r, details=d)
            db.add(log)
            # 解除订单关联，保留订单记录
            from ..models.orm import Order
            db.query(Order).filter(Order.user_id == user.id).update({Order.user_id: None})
            # Delete sessions first for safety; cascades may handle this but be explicit
            db.query(UserSession).filter(UserSession.user_id == user.id).delete()
            db.delete(user)
            db.commit()
            return SuccessDTO(success=True)
        finally:
            db.close()