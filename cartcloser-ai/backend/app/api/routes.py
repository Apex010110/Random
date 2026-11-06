from __future__ import annotations

import asyncio
import json

from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import StreamingResponse
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api import serialize as ser
from app.api.deps import MerchantCtx, ShopperCtx, merchant, shopper, tenant_param
from app.config import get_settings
from app.db.session import get_db
from app.models.entities import (
    Cart,
    Conversation,
    IntegrationConnection,
    Order,
    Product,
    Shopper,
    StorePolicy,
    Tenant,
)
from app.schemas import api as S
from app.services import commerce as svc
from app.services import fulfillment as ful
from app.services import metrics as metrics_svc
from app.services.seed import reset_and_seed
from app.services.support import ChangeFeed, DomainError, verify_recovery_token

router = APIRouter()
ERR = {401: {"model": S.ErrorOut}, 404: {"model": S.ErrorOut}, 409: {"model": S.ErrorOut}, 422: {"model": S.ErrorOut}}


@router.get("/health", tags=["system"])
def health(db: Session = Depends(get_db)):
    s = get_settings()
    db.execute(select(1))
    return {"status": "ok", "mode": s.app_env, "ai": "llm+rules" if (s.ai_provider == "anthropic" and s.anthropic_api_key) else "rules",
            "messaging": "simulator", "version": ChangeFeed.version}


# ------------------------------------------------------------------ catalog (public)
@router.get("/products", response_model=S.ProductPage, tags=["catalog"])
def list_products(tenant_id: str = Depends(tenant_param), category: str | None = None, q: str | None = Query(default=None, max_length=60),
                  limit: int = Query(default=50, ge=1, le=100), offset: int = Query(default=0, ge=0), db: Session = Depends(get_db)):
    stmt = select(Product).where(Product.tenant_id == tenant_id, Product.active.is_(True))
    if category:
        stmt = stmt.where(Product.category == category)
    if q:
        stmt = stmt.where(Product.name.ilike(f"%{q}%"))
    total = db.scalar(select(func.count()).select_from(stmt.subquery()))
    items = db.scalars(stmt.order_by(Product.id).limit(limit).offset(offset)).all()
    return {"items": [ser.product(p) for p in items], "total": total, "limit": limit, "offset": offset}


@router.get("/products/{product_id}", response_model=S.ProductOut, responses=ERR, tags=["catalog"])
def get_product(product_id: str, tenant_id: str = Depends(tenant_param), db: Session = Depends(get_db)):
    p = db.get(Product, product_id)
    if not p or p.tenant_id != tenant_id:
        raise DomainError(404, "product_not_found", "Product not found")
    return ser.product(p)


@router.get("/store", tags=["catalog"])
def store_info(tenant_id: str = Depends(tenant_param), db: Session = Depends(get_db)):
    t = svc.tenant_of(db, tenant_id)
    return {"tenant_id": t.id, "name": t.name, "currency": t.currency, "is_demo": t.is_demo,
            "policy": ser.policy(db.get(StorePolicy, t.id)), "consent_text": t.settings.get("consent_text"),
            "consent_version": t.settings.get("consent_version"), "discount_ceiling_pct": t.settings.get("discount_ceiling_pct")}


# ------------------------------------------------------------------ carts (shopper)
@router.post("/carts", response_model=S.CartOut, status_code=201, responses=ERR, tags=["carts"])
def create_cart(body: S.CartCreate, who: ShopperCtx = Depends(shopper), db: Session = Depends(get_db)):
    c = svc.create_cart(db, who.tenant_id, who.shopper_id, [i.model_dump() for i in body.items], body.idempotency_key)
    return ser.cart(db, c)


@router.get("/carts/{cart_id}", response_model=S.CartOut, responses=ERR, tags=["carts"])
def read_cart(cart_id: str, who: ShopperCtx = Depends(shopper), db: Session = Depends(get_db)):
    return ser.cart(db, svc.get_cart(db, who.tenant_id, cart_id, who.shopper_id))


@router.patch("/carts/{cart_id}", response_model=S.CartOut, responses=ERR, tags=["carts"])
def patch_cart(cart_id: str, body: S.CartPatch, who: ShopperCtx = Depends(shopper), db: Session = Depends(get_db)):
    c = svc.get_cart(db, who.tenant_id, cart_id, who.shopper_id)
    items = [i.model_dump() for i in body.items] if body.items is not None else None
    return ser.cart(db, svc.update_cart(db, c, items, body.promo_code))


@router.post("/carts/{cart_id}/checkout-started", response_model=S.CartOut, responses=ERR, tags=["carts"])
def checkout_started(cart_id: str, body: S.CheckoutStartedIn, who: ShopperCtx = Depends(shopper), db: Session = Depends(get_db)):
    c = svc.get_cart(db, who.tenant_id, cart_id, who.shopper_id)
    return ser.cart(db, svc.checkout_started(db, c, body.city, body.payment_method, body.whatsapp_opt_in))


@router.post("/carts/{cart_id}/abandon", response_model=S.CartOut, responses=ERR, tags=["carts"])
def abandon(cart_id: str, body: S.AbandonIn | None = None, who: ShopperCtx = Depends(shopper), db: Session = Depends(get_db)):
    c = svc.get_cart(db, who.tenant_id, cart_id, who.shopper_id)
    return ser.cart(db, svc.abandon(db, c, body.idempotency_key if body else None))


@router.get("/r/{cart_id}", response_model=S.CartOut, responses=ERR, tags=["carts"])
def open_recovery_link(cart_id: str, t: str, tenant_id: str = Depends(tenant_param), db: Session = Depends(get_db)):
    """Recovery deep link: a signed token instead of shopper auth. Opening it is NOT counted as recovery."""
    if not verify_recovery_token(cart_id, t):
        raise DomainError(403, "invalid_link", "Recovery link is invalid")
    return ser.cart(db, svc.get_cart(db, tenant_id, cart_id), include_link=True)


# ------------------------------------------------------------------ consent
@router.post("/consents", response_model=S.ConsentOut, status_code=201, responses=ERR, tags=["consent"])
def grant(body: S.ConsentIn, who: ShopperCtx = Depends(shopper), db: Session = Depends(get_db)):
    if body.shopper_id != who.shopper_id:
        raise DomainError(403, "forbidden", "Shoppers can only manage their own consent")
    return svc.grant_consent(db, who.tenant_id, who.shopper_id, body.source)


@router.post("/consents/revoke", responses=ERR, tags=["consent"])
def revoke(body: S.ConsentRevokeIn, who: ShopperCtx = Depends(shopper), db: Session = Depends(get_db)):
    if body.shopper_id != who.shopper_id:
        raise DomainError(403, "forbidden", "Shoppers can only manage their own consent")
    svc.revoke_consent(db, who.tenant_id, who.shopper_id, body.source)
    return {"revoked": True}


@router.get("/consents/me", tags=["consent"])
def my_consent(who: ShopperCtx = Depends(shopper), db: Session = Depends(get_db)):
    rec = svc.active_consent(db, who.tenant_id, who.shopper_id)
    return {"opted_in": rec is not None, "record": S.ConsentOut.model_validate(rec).model_dump() if rec else None}


# ------------------------------------------------------------------ recovery
@router.post("/recovery/{cart_id}/schedule", responses=ERR, tags=["recovery"])
def schedule(cart_id: str, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    att = svc.schedule(db, svc.get_cart(db, m.tenant_id, cart_id))
    return {"attempt_id": att.id, "status": att.status, "scheduled_for": att.scheduled_for}


@router.post("/recovery/{cart_id}/trigger-demo", responses=ERR, tags=["recovery"])
def trigger_demo(cart_id: str, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    att = svc.trigger_demo(db, svc.get_cart(db, m.tenant_id, cart_id), get_settings().demo_mode)
    return {"attempt_id": att.id, "status": att.status, "reason": att.reason}


# ------------------------------------------------------------------ conversations (shopper)
@router.get("/conversations/{cart_id}", response_model=S.ConversationOut, responses=ERR, tags=["conversations"])
def get_conversation(cart_id: str, who: ShopperCtx = Depends(shopper), db: Session = Depends(get_db)):
    c = svc.get_cart(db, who.tenant_id, cart_id, who.shopper_id)
    return ser.conversation(svc.get_conversation(db, c), c.id)


@router.post("/conversations/{cart_id}/messages", response_model=list[S.MessageOut], responses=ERR, tags=["conversations"])
def post_message(cart_id: str, body: S.MessageIn, who: ShopperCtx = Depends(shopper), db: Session = Depends(get_db)):
    c = svc.get_cart(db, who.tenant_id, cart_id, who.shopper_id)
    return [ser.message(m) for m in svc.shopper_message(db, c, body.text, body.idempotency_key)]


# ------------------------------------------------------------------ orders
@router.post("/orders", response_model=S.OrderOut, responses=ERR, tags=["orders"])
def create_order(body: S.OrderIn, request: Request, tenant_id: str = Depends(tenant_param), db: Session = Depends(get_db)):
    """Either the shopper (X-Shopper-Id) or a valid recovery-link token must authorize the order."""
    shopper_id = request.headers.get("x-shopper-id")
    cart = svc.get_cart(db, request.headers.get("x-tenant-id") or tenant_id, body.cart_id)
    if body.recovery_token is None and shopper_id != cart.shopper_id:
        raise DomainError(404, "cart_not_found", "Cart not found")
    o, _ = svc.place_order(db, cart, body.payment_method, body.cod_confirmed, body.idempotency_key, body.discount_code, body.recovery_token)
    return ser.order(db, o)


@router.get("/orders/{order_id}", response_model=S.OrderOut, responses=ERR, tags=["orders"])
def get_order(order_id: str, who: ShopperCtx = Depends(shopper), db: Session = Depends(get_db)):
    o = db.get(Order, order_id)
    if not o or o.tenant_id != who.tenant_id or db.get(Cart, o.cart_id).shopper_id != who.shopper_id:
        raise DomainError(404, "order_not_found", "Order not found")
    return ser.order(db, o)


# ------------------------------------------------------------------ green logistics (merchant demo controls)
def _merchant_order(db: Session, m: MerchantCtx, order_id: str) -> Order:
    o = db.get(Order, order_id)
    if not o or o.tenant_id != m.tenant_id:
        raise DomainError(404, "order_not_found", "Order not found")
    return o


@router.post("/orders/{order_id}/confirm-cod", response_model=S.OrderOut, responses=ERR, tags=["fulfillment"])
def confirm_cod(order_id: str, body: S.ConfirmCodIn, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    o = _merchant_order(db, m, order_id)
    ful.confirm_cod(db, svc.tenant_of(db, m.tenant_id), o, body.confirmed, body.delivery_zone_ok, body.availability_ok)
    svc._commit(db)
    return ser.order(db, o)


@router.post("/orders/{order_id}/correct-address", response_model=S.OrderOut, responses=ERR, tags=["fulfillment"])
def correct_address(order_id: str, body: S.CorrectAddressIn, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    o = _merchant_order(db, m, order_id)
    ful.correct_address(db, o, body.address_redacted, body.delivery_zone)
    svc._commit(db)
    return ser.order(db, o)


@router.post("/orders/{order_id}/hold", response_model=S.OrderOut, responses=ERR, tags=["fulfillment"])
def hold_order(order_id: str, body: S.HoldIn, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    o = _merchant_order(db, m, order_id)
    ful.hold(db, o, body.reason)
    svc._commit(db)
    return ser.order(db, o)


@router.post("/orders/{order_id}/release", response_model=S.OrderOut, responses=ERR, tags=["fulfillment"])
def release_order(order_id: str, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    o = _merchant_order(db, m, order_id)
    ful.release(db, o)
    svc._commit(db)
    return ser.order(db, o)


@router.post("/orders/{order_id}/dispatch", response_model=S.OrderOut, responses=ERR, tags=["fulfillment"])
def dispatch_order(order_id: str, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    o = _merchant_order(db, m, order_id)
    ful.dispatch(db, o)
    svc._commit(db)
    return ser.order(db, o)


@router.post("/orders/{order_id}/retry-dispatch", response_model=S.OrderOut, responses=ERR, tags=["fulfillment"])
def retry_dispatch_order(order_id: str, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    o = _merchant_order(db, m, order_id)
    ful.retry_dispatch(db, o)
    svc._commit(db)
    return ser.order(db, o)


@router.post("/orders/{order_id}/delivered", response_model=S.OrderOut, responses=ERR, tags=["fulfillment"])
def mark_delivered(order_id: str, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    o = _merchant_order(db, m, order_id)
    ful.mark_delivered(db, o)
    svc._commit(db)
    return ser.order(db, o)


@router.post("/orders/{order_id}/failed-attempt", response_model=S.OrderOut, responses=ERR, tags=["fulfillment"])
def mark_failed_attempt(order_id: str, body: S.ReasonIn, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    o = _merchant_order(db, m, order_id)
    ful.mark_failed_attempt(db, o, body.reason)
    svc._commit(db)
    return ser.order(db, o)


@router.post("/orders/{order_id}/returned", response_model=S.OrderOut, responses=ERR, tags=["fulfillment"])
def mark_returned(order_id: str, body: S.ReasonIn, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    o = _merchant_order(db, m, order_id)
    ful.mark_returned(db, o, body.reason)
    svc._commit(db)
    return ser.order(db, o)


@router.post("/orders/{order_id}/cancel", response_model=S.OrderOut, responses=ERR, tags=["fulfillment"])
def cancel_order(order_id: str, body: S.ReasonIn, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    o = _merchant_order(db, m, order_id)
    ful.cancel(db, o, body.reason)
    svc._commit(db)
    return ser.order(db, o)


@router.get("/merchant/events", responses=ERR, tags=["merchant"])
def merchant_events(order_id: str | None = None, limit: int = Query(default=100, ge=1, le=500),
                    m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    from app.models.entities import AuditEvent

    stmt = select(AuditEvent).where(AuditEvent.tenant_id == m.tenant_id)
    if order_id:
        stmt = stmt.where(AuditEvent.order_id == order_id)
    rows = db.scalars(stmt.order_by(AuditEvent.created_at.desc()).limit(limit)).all()
    return {"items": [{"id": e.id, "type": e.type, "order_id": e.order_id, "cart_id": e.cart_id, "scenario_id": e.scenario_id,
                       "source": e.source, "detail": e.detail, "at": e.created_at.isoformat()} for e in rows]}


@router.post("/merchant/assumptions", responses=ERR, tags=["merchant"])
def patch_assumptions(body: S.AssumptionsPatch, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    out = ful.patch_assumptions(db, m.tenant_id, body.model_dump(exclude_unset=True))
    svc._commit(db)
    return {"assumptions": out}


# ------------------------------------------------------------------ merchant
@router.get("/merchant/metrics", response_model=S.Metrics, responses=ERR, tags=["merchant"])
def merchant_metrics(days: int | None = Query(default=None, ge=1, le=365), m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    return metrics_svc.compute(db, m.tenant_id, days)


@router.get("/merchant/carts", responses=ERR, tags=["merchant"])
def merchant_carts(status: str | None = None, limit: int = Query(default=50, ge=1, le=200), offset: int = Query(default=0, ge=0),
                   m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    stmt = select(Cart).where(Cart.tenant_id == m.tenant_id)
    if status:
        stmt = stmt.where(Cart.status == status)
    total = db.scalar(select(func.count()).select_from(stmt.subquery()))
    rows = db.scalars(stmt.order_by(Cart.created_at.desc()).limit(limit).offset(offset)).all()
    out = []
    for c in rows:
        d = ser.cart(db, c)
        sh = db.get(Shopper, c.shopper_id)
        d["shopper"] = {"id": sh.id, "first_name": sh.first_name, "phone_masked": sh.phone_masked, "age_band": sh.age_band}
        conv = svc.get_conversation(db, c)
        d["message_count"] = len(conv.messages) if conv else 0
        d["attribution_source"] = "recovery_contact" if c.status == "recovered" else None
        out.append(d)
    return {"items": out, "total": total, "limit": limit, "offset": offset}


@router.get("/merchant/carts/{cart_id}", responses=ERR, tags=["merchant"])
def merchant_cart(cart_id: str, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    c = svc.get_cart(db, m.tenant_id, cart_id)
    d = ser.cart(db, c)
    d["conversation"] = ser.conversation(svc.get_conversation(db, c), c.id)
    return d


@router.post("/merchant/carts/{cart_id}/pause", responses=ERR, tags=["merchant"])
def pause_cart(cart_id: str, body: S.FlagIn, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    return ser.cart(db, svc.set_cart_paused(db, svc.get_cart(db, m.tenant_id, cart_id), body.on))


@router.get("/merchant/conversations", responses=ERR, tags=["merchant"])
def merchant_conversations(escalated: bool | None = None, limit: int = Query(default=50, ge=1, le=200), offset: int = Query(default=0, ge=0),
                           m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    stmt = select(Conversation).where(Conversation.tenant_id == m.tenant_id)
    if escalated is not None:
        stmt = stmt.where(Conversation.escalated.is_(escalated))
    total = db.scalar(select(func.count()).select_from(stmt.subquery()))
    rows = db.scalars(stmt.order_by(Conversation.updated_at.desc()).limit(limit).offset(offset)).all()
    return {"items": [ser.conversation(c, c.cart_id) for c in rows], "total": total, "limit": limit, "offset": offset}


@router.post("/merchant/conversations/{cart_id}/reply", response_model=S.MessageOut, responses=ERR, tags=["merchant"])
def merchant_reply(cart_id: str, body: S.HumanReplyIn, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    return ser.message(svc.human_reply(db, svc.get_cart(db, m.tenant_id, cart_id), body.text))


@router.post("/merchant/conversations/{cart_id}/takeover", responses=ERR, tags=["merchant"])
def takeover(cart_id: str, body: S.FlagIn, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    c = svc.get_cart(db, m.tenant_id, cart_id)
    return ser.conversation(svc.set_takeover(db, c, body.on), c.id)


@router.get("/merchant/settings", responses=ERR, tags=["merchant"])
def get_settings_(m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    t = db.get(Tenant, m.tenant_id)
    return {"tenant_id": t.id, "name": t.name, "is_demo": t.is_demo, "settings": t.settings}


@router.patch("/merchant/settings", responses=ERR, tags=["merchant"])
def patch_settings(body: S.SettingsPatch, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    t = db.get(Tenant, m.tenant_id)
    new = dict(t.settings)
    new.update(body.model_dump(exclude_none=True))
    t.settings = new
    svc.audit(db, t.id, "settings_updated", None, {"keys": sorted(body.model_dump(exclude_none=True))})
    svc._commit(db)
    return {"tenant_id": t.id, "name": t.name, "is_demo": t.is_demo, "settings": t.settings}


@router.get("/merchant/catalog", responses=ERR, tags=["merchant"])
def get_catalog(m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    prods = db.scalars(select(Product).where(Product.tenant_id == m.tenant_id).order_by(Product.id)).all()
    return {"products": [ser.product(p) for p in prods], "policy": ser.policy(db.get(StorePolicy, m.tenant_id))}


@router.patch("/merchant/catalog", responses=ERR, tags=["merchant"])
def patch_catalog(body: S.CatalogPatch, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    for pp in body.products:
        p = db.get(Product, pp.id)
        if not p or p.tenant_id != m.tenant_id:
            raise DomainError(404, "product_not_found", f"Product {pp.id} not found")
        for field in ("price_pkr", "cod_eligible", "active", "fit_notes"):
            val = getattr(pp, field)
            if val is not None:
                setattr(p, field, val)
        for vp in pp.variants or []:
            v = next((v for v in p.variants if v.size == vp.size), None)
            if not v:
                raise DomainError(422, "size_not_found", f"Size {vp.size} not found on {p.id}")
            v.inventory.on_hand = vp.stock
    if body.policy:
        pol = db.get(StorePolicy, m.tenant_id)
        for k, v in body.policy.model_dump(exclude_none=True).items():
            setattr(pol, k, v)
        pol.version += 1
    svc.audit(db, m.tenant_id, "catalog_updated", None, {"products": len(body.products), "policy": body.policy is not None})
    svc._commit(db)
    return get_catalog(m, db)


@router.get("/merchant/orders", responses=ERR, tags=["merchant"])
def merchant_orders(fulfillment_status: str | None = None, limit: int = Query(default=100, ge=1, le=500),
                    offset: int = Query(default=0, ge=0), m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    stmt = select(Order).where(Order.tenant_id == m.tenant_id)
    if fulfillment_status:
        stmt = stmt.where(Order.fulfillment_status == fulfillment_status)
    total = db.scalar(select(func.count()).select_from(stmt.subquery()))
    rows = db.scalars(stmt.order_by(Order.created_at.desc()).limit(limit).offset(offset)).all()
    return {"items": [ser.order(db, o) for o in rows], "total": total, "limit": limit, "offset": offset}


@router.get("/merchant/integrations", responses=ERR, tags=["merchant"])
def integrations(m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    rows = db.scalars(select(IntegrationConnection).where(IntegrationConnection.tenant_id == m.tenant_id)).all()
    return [{"provider": r.provider, "status": r.status, "detail": r.detail} for r in rows]


@router.get("/merchant/export", responses=ERR, tags=["merchant"])
def export(m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    """Data export for the tenant (no payment data exists; phones are masked)."""
    carts = db.scalars(select(Cart).where(Cart.tenant_id == m.tenant_id)).all()
    return {"tenant_id": m.tenant_id, "carts": [ser.cart(db, c) for c in carts],
            "conversations": [ser.conversation(svc.get_conversation(db, c), c.id) for c in carts],
            "orders": [ser.order(db, o) for o in db.scalars(select(Order).where(Order.tenant_id == m.tenant_id))]}


@router.delete("/merchant/shoppers/{shopper_id}", responses=ERR, tags=["merchant"])
def delete_shopper_data(shopper_id: str, m: MerchantCtx = Depends(merchant), db: Session = Depends(get_db)):
    """Erase a shopper's carts, messages and consent records (orders are kept anonymised for accounting)."""
    from app.models.entities import (
        AttributionEvent,
        CartItem,
        Checkout,
        ConsentRecord,
        Discount,
        Message,
        RecoveryAttempt,
    )

    sh = svc.get_shopper(db, m.tenant_id, shopper_id)
    carts = db.scalars(select(Cart).where(Cart.shopper_id == sh.id)).all()
    ids = [c.id for c in carts]
    for conv in db.scalars(select(Conversation).where(Conversation.cart_id.in_(ids))):
        db.query(Message).filter(Message.conversation_id == conv.id).delete()
        db.delete(conv)
    db.query(ConsentRecord).filter(ConsentRecord.shopper_id == sh.id).delete()
    kept_orders = 0
    for c in carts:
        if db.scalar(select(Order).where(Order.cart_id == c.id)):
            kept_orders += 1
            c.items.clear()
            continue
        db.query(RecoveryAttempt).filter(RecoveryAttempt.cart_id == c.id).delete()
        db.query(Discount).filter(Discount.cart_id == c.id).delete()
        db.query(CartItem).filter(CartItem.cart_id == c.id).delete()
        db.query(Checkout).filter(Checkout.cart_id == c.id).delete()
        db.delete(c)
    _ = AttributionEvent
    sh.first_name, sh.phone_masked = "Deleted", "deleted"
    svc.audit(db, m.tenant_id, "shopper_data_deleted", None, {"carts": len(ids), "orders_kept": kept_orders})
    svc._commit(db)
    return {"deleted_carts": len(ids) - kept_orders, "orders_kept_anonymised": kept_orders}


@router.get("/merchant/stream", tags=["merchant"])
async def stream(request: Request, m: MerchantCtx = Depends(merchant)):
    """Server-sent events: emits {"version": n} whenever demo data changes. Clients then refetch."""
    async def gen():
        last = -1
        while not await request.is_disconnected():
            if ChangeFeed.version != last:
                last = ChangeFeed.version
                yield f"event: change\ndata: {json.dumps({'version': last, 'tenant': m.tenant_id})}\n\n"
            await asyncio.sleep(0.5)
    return StreamingResponse(gen(), media_type="text/event-stream")


@router.get("/changes", tags=["system"])
def changes():
    """Polling fallback for live updates: returns the change-feed version."""
    return {"version": ChangeFeed.version}


# ------------------------------------------------------------------ demo
@router.post("/demo/reset", tags=["demo"])
def demo_reset(db: Session = Depends(get_db)):
    if not get_settings().demo_mode:
        raise DomainError(403, "demo_only", "Reset is only available in demo mode")
    reset_and_seed(db)
    return {"reset": True}


@router.post("/demo/seed", tags=["demo"])
def demo_seed(db: Session = Depends(get_db)):
    if not get_settings().demo_mode:
        raise DomainError(403, "demo_only", "Seeding is only available in demo mode")
    if db.get(Tenant, "urbanthread-pk") is None:
        reset_and_seed(db)
        return {"seeded": True}
    return {"seeded": False, "detail": "Already seeded; use /demo/reset to start over"}


@router.post("/demo/tick", tags=["demo"])
def demo_tick(db: Session = Depends(get_db)):
    """Run one scheduler tick now (the background scheduler also runs every second)."""
    return {"delivered": svc.run_due(db)}
