"""Cross-cutting helpers: clock, change feed, audit log, errors, recovery-link tokens."""
from __future__ import annotations

import hashlib
import hmac
import os
import re
import threading
from datetime import datetime, timedelta, timezone

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.entities import AuditEvent

PKT = timezone(timedelta(hours=5))  # Pakistan Standard Time (no DST)


class Clock:
    """Injectable clock so tests can control 'now' (quiet hours, attribution windows)."""

    _override: datetime | None = None

    @classmethod
    def now(cls) -> datetime:
        return cls._override or datetime.now(timezone.utc)

    @classmethod
    def local(cls) -> datetime:
        return cls.now().astimezone(PKT)

    @classmethod
    def set(cls, dt: datetime | None) -> None:
        cls._override = dt


def as_utc(dt: datetime | None) -> datetime | None:
    """SQLite drops tzinfo on read; normalise to aware UTC."""
    if dt is None:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


class ChangeFeed:
    """Monotonic version counter; the SSE stream and polling clients watch it."""

    _lock = threading.Lock()
    version = 0

    @classmethod
    def bump(cls) -> int:
        with cls._lock:
            cls.version += 1
            return cls.version


class DomainError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status, self.code, self.message = status, code, message


PHONE_RE = re.compile(r"\+?\d[\d\s-]{7,}\d")


def redact(value):
    """Remove phone numbers from audit details; never log message bodies."""
    if isinstance(value, str):
        return PHONE_RE.sub("[redacted-phone]", value)
    if isinstance(value, dict):
        return {k: redact(v) for k, v in value.items() if k not in {"text", "phone", "body"}}
    if isinstance(value, list):
        return [redact(v) for v in value]
    return value


def audit(db: Session, tenant_id: str, type_: str, cart_id: str | None = None, detail: dict | None = None,
          idempotency_key: str | None = None, order_id: str | None = None, scenario_id: str | None = None,
          source: str = "simulated") -> bool:
    """Record an audit event (also the Green Logistics order-event log). Returns False if the
    idempotency key was already seen (duplicate)."""
    ev = AuditEvent(tenant_id=tenant_id, cart_id=cart_id, order_id=order_id, scenario_id=scenario_id, source=source,
                    type=type_, detail=redact(detail or {}), idempotency_key=idempotency_key, created_at=Clock.now())
    if idempotency_key:
        with db.begin_nested():
            try:
                db.add(ev)
                db.flush()
            except IntegrityError:
                return False
        return True
    db.add(ev)
    return True


def link_secret() -> bytes:
    return os.environ.get("LINK_SIGNING_SECRET", "dev-only-change-me").encode()


def recovery_token(cart_id: str) -> str:
    return hmac.new(link_secret(), cart_id.encode(), hashlib.sha256).hexdigest()[:20]


def verify_recovery_token(cart_id: str, token: str | None) -> bool:
    return bool(token) and hmac.compare_digest(recovery_token(cart_id), token)
