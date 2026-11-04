from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.entities import (
    AttributionEvent,
    Cart,
    Conversation,
    Order,
    Product,
    RecoveryAttempt,
    StorePolicy,
)
from app.services import commerce as svc
from app.services.support import as_utc, recovery_token


def product(p: Product) -> dict:
    return {"id": p.id, "name": p.name, "category": p.category, "description": p.description, "fit_notes": p.fit_notes,
            "price_pkr": p.price_pkr, "cod_eligible": p.cod_eligible, "image_key": p.image_key, "color_hex": p.color_hex,
            "active": p.active, "variants": [{"size": v.size, "stock": v.stock} for v in p.variants]}


def policy(p: StorePolicy) -> dict:
    return svc._policy_dict(p)


def cart(db: Session, c: Cart, include_link: bool = False) -> dict:
    consent = svc.active_consent(db, c.tenant_id, c.shopper_id)
    order = db.scalar(select(Order).where(Order.cart_id == c.id))
    attempts = db.scalars(select(RecoveryAttempt).where(RecoveryAttempt.cart_id == c.id).order_by(RecoveryAttempt.created_at)).all()
    try:
        tot = svc.totals(db, c)
    except svc.DomainError:  # e.g. promo code became invalid
        tot = svc.totals(db, c, discount_code="")
    return {
        "id": c.id, "shopper_id": c.shopper_id, "status": c.status, "status_reason": c.status_reason,
        "items": [{"product_id": i.product_id, "name": i.product.name, "size": i.variant.size, "quantity": i.quantity,
                   "unit_price_pkr": i.unit_price_pkr, "cod_eligible": i.product.cod_eligible} for i in c.items],
        "totals": tot, "promo_code": c.promo_code,
        "checkout": ({"city": c.checkout.city, "payment_method": c.checkout.payment_method,
                      "opted_in_at_checkout": c.checkout.opted_in_at_checkout} if c.checkout else None),
        "consent": ({"granted": True, "version": consent.consent_version, "source": consent.source,
                     "at": as_utc(consent.created_at).isoformat(), "channel": consent.channel} if consent else None),
        "recovery_paused": c.recovery_paused, "holdout": c.holdout, "abandoned_at": as_utc(c.abandoned_at),
        "created_at": as_utc(c.created_at),
        "recovery_attempts": [{"id": a.id, "status": a.status, "reason": a.reason, "channel": a.channel,
                               "scheduled_for": as_utc(a.scheduled_for).isoformat(),
                               "sent_at": as_utc(a.sent_at).isoformat() if a.sent_at else None} for a in attempts],
        "order_id": order.id if order else None,
        "recovery_link": f"/r/{c.id}?t={recovery_token(c.id)}" if include_link else None,
    }


def message(m) -> dict:
    return {"id": m.id, "seq": m.seq, "role": m.role, "text": m.text, "intent": m.intent, "confidence": m.confidence,
            "language": m.language, "source": m.source, "meta": m.meta or {}, "created_at": as_utc(m.created_at)}


def conversation(conv: Conversation | None, cart_id: str) -> dict:
    if conv is None:
        return {"cart_id": cart_id, "channel": "none", "human_takeover": False, "escalated": False, "messages": []}
    return {"cart_id": cart_id, "channel": conv.channel, "human_takeover": conv.human_takeover, "escalated": conv.escalated,
            "messages": [message(m) for m in conv.messages]}


def order(db: Session, o: Order) -> dict:
    attributed = db.scalar(select(AttributionEvent).where(AttributionEvent.order_id == o.id)) is not None
    return {"id": o.id, "cart_id": o.cart_id, "status": o.status, "payment_method": o.payment_method,
            "cod_confirmed": o.cod_confirmed, "city": o.city, "subtotal_pkr": o.subtotal_pkr, "discount_pkr": o.discount_pkr,
            "shipping_pkr": o.shipping_pkr, "total_pkr": o.total_pkr, "discount_code": o.discount_code,
            "via_recovery_link": o.via_recovery_link, "lines": o.lines, "created_at": as_utc(o.created_at), "attributed": attributed}
