"""Auth / tenancy dependencies.

Demo-mode auth (documented in docs/security.md):
  * Merchant endpoints: `Authorization: Bearer <merchant api token>`; the token resolves to exactly one
    tenant and every merchant query is filtered by that tenant id (tenant isolation).
  * Shopper endpoints: `X-Shopper-Id` (pseudonymous id) + optional `X-Tenant-Id` (default demo tenant).
    Carts and conversations are only visible to their own shopper.
"""
from __future__ import annotations

from dataclasses import dataclass

from fastapi import Depends, Header, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.entities import MerchantUser
from app.services.seed import DEMO_TENANT
from app.services.support import DomainError


@dataclass
class MerchantCtx:
    tenant_id: str
    user_id: str


@dataclass
class ShopperCtx:
    tenant_id: str
    shopper_id: str


def merchant(authorization: str | None = Header(default=None), token: str | None = Query(default=None, include_in_schema=False),
             db: Session = Depends(get_db)) -> MerchantCtx:
    raw = None
    if authorization and authorization.lower().startswith("bearer "):
        raw = authorization[7:].strip()
    elif token:  # EventSource cannot set headers; allow ?token= for the SSE stream only
        raw = token
    if not raw:
        raise DomainError(401, "unauthorized", "Missing merchant bearer token")
    user = db.scalar(select(MerchantUser).where(MerchantUser.api_token == raw))
    if not user:
        raise DomainError(401, "unauthorized", "Invalid merchant token")
    return MerchantCtx(tenant_id=user.tenant_id, user_id=user.id)


def shopper(x_shopper_id: str | None = Header(default=None), x_tenant_id: str | None = Header(default=None)) -> ShopperCtx:
    if not x_shopper_id:
        raise DomainError(401, "unauthorized", "Missing X-Shopper-Id header")
    return ShopperCtx(tenant_id=x_tenant_id or DEMO_TENANT, shopper_id=x_shopper_id)


def tenant_param(tenant_id: str = Query(default=DEMO_TENANT, max_length=64)) -> str:
    return tenant_id
