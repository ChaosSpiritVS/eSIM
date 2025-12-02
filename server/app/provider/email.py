from __future__ import annotations
import os
from typing import Optional


class EmailGateway:
    """Generic email gateway interface. Use from_env() to construct.

    Implementations should be best-effort and never raise to callers for normal failures.
    """

    def send_password_reset(self, to_email: str, reset_link: str, locale: Optional[str] = None) -> None:  # pragma: no cover
        # Default: no-op
        return

    def send_email_code(self, to_email: str, code: str, locale: Optional[str] = None) -> None:  # pragma: no cover
        # Default: no-op
        return

    @staticmethod
    def from_env() -> "EmailGateway":
        enabled = os.getenv("EMAIL_ENABLED", "").lower() in ("1", "true", "yes")
        provider = os.getenv("EMAIL_PROVIDER", "ses").lower()
        if not enabled:
            return NoopEmailGateway()
        if provider == "ses":
            region = os.getenv("SES_REGION") or os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION")
            sender = os.getenv("SES_SENDER")
            configuration_set = os.getenv("SES_CONFIGURATION_SET")
            if not region or not sender:
                return NoopEmailGateway()
            return SESGateway(region=region, sender=sender, configuration_set=configuration_set)
        # Unknown provider: fall back to no-op
        return NoopEmailGateway()


class NoopEmailGateway(EmailGateway):
    def send_password_reset(self, to_email: str, reset_link: str, locale: Optional[str] = None) -> None:  # pragma: no cover
        # Intentionally do nothing in development/default mode
        return


class SESGateway(EmailGateway):
    def __init__(self, region: str, sender: str, configuration_set: Optional[str] = None):
        self.region = region
        self.sender = sender
        self.configuration_set = configuration_set
        self._ses = None  # lazy

    def _client(self):
        if self._ses is None:
            try:
                import boto3  # type: ignore
            except Exception:
                # If boto3 is missing, degrade gracefully
                self._ses = None
                return None
            self._ses = boto3.client("ses", region_name=self.region)
        return self._ses

    def _subject(self, locale: Optional[str]) -> str:
        loc = (locale or "en").lower()
        if loc.startswith("zh"):
            return "重置您的 Simigo 密码"
        return "Reset your Simigo password"

    def _html(self, reset_link: str, locale: Optional[str]) -> str:
        loc = (locale or "en").lower()
        if loc.startswith("zh"):
            return f"""
            <html>
              <body style=\"font-family: -apple-system, Helvetica, Arial, sans-serif;\">
                <p>我们收到了您的密码重置请求。</p>
                <p>请点击下面的按钮完成重置（30 分钟内有效）：</p>
                <p>
                  <a href=\"{reset_link}\" style=\"background:#0a84ff;color:#fff;padding:10px 16px;border-radius:6px;text-decoration:none;\">重置密码</a>
                </p>
                <p>如果不是您本人操作，请忽略本邮件。</p>
              </body>
            </html>
            """
        return f"""
        <html>
          <body style=\"font-family: -apple-system, Helvetica, Arial, sans-serif;\">
            <p>We received a request to reset your password.</p>
            <p>Please click the button below to complete the reset (valid for 30 minutes):</p>
            <p>
              <a href=\"{reset_link}\" style=\"background:#0a84ff;color:#fff;padding:10px 16px;border-radius:6px;text-decoration:none;\">Reset Password</a>
            </p>
            <p>If you didn't request this, you can safely ignore this email.</p>
          </body>
        </html>
        """

    def send_password_reset(self, to_email: str, reset_link: str, locale: Optional[str] = None) -> None:
        client = self._client()
        if client is None:
            return
        subject = self._subject(locale)
        html = self._html(reset_link, locale)
        msg = {
            "Subject": {"Data": subject, "Charset": "UTF-8"},
            "Body": {"Html": {"Data": html, "Charset": "UTF-8"}},
        }
        kwargs = {
            "Source": self.sender,
            "Destination": {"ToAddresses": [to_email]},
            "Message": msg,
        }
        if self.configuration_set:
            kwargs["ConfigurationSetName"] = self.configuration_set
        try:
            client.send_email(**kwargs)
        except Exception:
            # Swallow errors to avoid leaking existence of accounts; log-only
            # In a real setup, we would log with request-id and context
            return

    def send_email_code(self, to_email: str, code: str, locale: Optional[str] = None) -> None:
        client = self._client()
        if client is None:
            return
        subject = ("验证邮箱" if (locale or "zh").startswith("zh") else "Verify your email")
        html = (
            f"<h3>{subject}</h3>\n<p>您的验证码是：<strong>{code}</strong>，10 分钟内有效。</p>"
        )
        msg = {
            "Subject": {"Data": subject, "Charset": "UTF-8"},
            "Body": {"Html": {"Data": html, "Charset": "UTF-8"}},
        }
        kwargs = {
            "Source": self.sender,
            "Destination": {"ToAddresses": [to_email]},
            "Message": msg,
        }
        if self.configuration_set:
            kwargs["ConfigurationSetName"] = self.configuration_set
        try:
            client.send_email(**kwargs)
        except Exception:
            return