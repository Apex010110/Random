"""Shopify / WooCommerce webhook adapters.

Status: SECURED STUBS. Signatures are verified (HMAC-SHA256, base64) before anything is processed,
and events are de-duplicated by delivery id. Mapping platform payloads onto CartCloser carts is
Phase 2 work and NOT implemented. Without a configured secret the endpoints answer 503 "not connected",
so nothing ever pretends to be integrated.
"""
from __future__ import annotations

import base64
import hashlib
import hmac

from fastapi import APIRouter, Depends, Header, Request
from sqlalchemy.orm import Session

from app.config import get_settings
from app.db.session import get_db
from app.services.seed import DEMO_TENANT
from app.services.support import ChangeFeed, DomainError, audit

router = APIRouter(prefix="/integrations", tags=["integrations"])


def sign(secret: str, body: bytes) -> str:
    return base64.b64encode(hmac.new(secret.encode(), body, hashlib.sha256).digest()).decode()


def _verify(secret: str, body: bytes, signature: str | None) -> None:
    if not secret:
        raise DomainError(503, "not_connected", "Integration not connected (no webhook secret configured)")
    if not signature or not hmac.compare_digest(sign(secret, body), signature):
        raise DomainError(401, "bad_signature", "Webhook signature verification failed")


def _record(db: Session, provider: str, delivery_id: str | None, topic: str | None) -> dict:
    fresh = audit(db, DEMO_TENANT, f"{provider}_webhook_received", None, {"topic": topic or "unknown"},
                  idempotency_key=f"wh:{provider}:{delivery_id}" if delivery_id else None)
    db.commit()
    ChangeFeed.bump()
    return {"accepted": True, "duplicate": not fresh, "processed": False,
            "detail": "Signature verified and logged. Cart mapping is not implemented yet (Phase 2)."}


@router.post("/shopify/webhook")
async def shopify(request: Request, x_shopify_hmac_sha256: str | None = Header(default=None),
                  x_shopify_webhook_id: str | None = Header(default=None), x_shopify_topic: str | None = Header(default=None),
                  db: Session = Depends(get_db)):
    body = await request.body()
    _verify(get_settings().shopify_webhook_secret, body, x_shopify_hmac_sha256)
    return _record(db, "shopify", x_shopify_webhook_id, x_shopify_topic)


@router.post("/woocommerce/webhook")
async def woocommerce(request: Request, x_wc_webhook_signature: str | None = Header(default=None),
                      x_wc_webhook_delivery_id: str | None = Header(default=None), x_wc_webhook_topic: str | None = Header(default=None),
                      db: Session = Depends(get_db)):
    body = await request.body()
    _verify(get_settings().woocommerce_webhook_secret, body, x_wc_webhook_signature)
    return _record(db, "woocommerce", x_wc_webhook_delivery_id, x_wc_webhook_topic)
