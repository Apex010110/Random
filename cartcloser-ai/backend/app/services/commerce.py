"""Core domain services: carts, consent, eligibility, recovery scheduling, conversations, orders.

Cart status machine (see docs/architecture.md):
  active_cart -> checkout_started -> abandoned -> eligible | not_eligible
  eligible -> scheduled -> message_sent -> replied -> human_handoff
  any contacted state -> recovered (order placed within attribution window) | expired | opted_out
  checkout_started/abandoned/scheduled -> ordered (purchased without a recovery contact)
"""
from __future__ import annotations

import random
import secrets
from datetime import timedelta

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.ai import rules
from app.ai.provider import get_rephraser
from app.models.entities import (
    AttributionEvent,
    Cart,
    CartItem,
    Checkout,
    ConsentRecord,
    Conversation,
    Discount,
    Message,
    Order,
    Product,
    ProductVariant,
    RecoveryAttempt,
    Shopper,
    StorePolicy,
    Tenant,
)
from app.services.support import (
    ChangeFeed,
    Clock,
    DomainError,
    as_utc,
    audit,
    recovery_token,
    verify_recovery_token,
)

PURPOSE = "checkout_reminders"
CHANNEL = "whatsapp_sim"
EDITABLE = {"active_cart", "checkout_started", "abandoned", "not_eligible", "eligible", "scheduled",
            "message_sent", "replied", "human_handoff"}
CONTACTED = {"message_sent", "replied", "human_handoff"}
CLOSED = {"recovered", "ordered", "expired"}


# ------------------------------------------------------------------ lookups
def tenant_of(db: Session, tenant_id: str) -> Tenant:
    t = db.get(Tenant, tenant_id)
    if not t:
        raise DomainError(404, "tenant_not_found", "Unknown tenant")
    return t


def policy_of(db: Session, tenant_id: str) -> StorePolicy:
    return db.get(StorePolicy, tenant_id)


def get_cart(db: Session, tenant_id: str, cart_id: str, shopper_id: str | None = None) -> Cart:
    cart = db.get(Cart, cart_id)
    if not cart or cart.tenant_id != tenant_id or (shopper_id is not None and cart.shopper_id != shopper_id):
        raise DomainError(404, "cart_not_found", "Cart not found")
    return cart


def get_shopper(db: Session, tenant_id: str, shopper_id: str) -> Shopper:
    sh = db.get(Shopper, shopper_id)
    if not sh or sh.tenant_id != tenant_id:
        raise DomainError(404, "shopper_not_found", "Unknown shopper")
    return sh


def find_variant(db: Session, tenant_id: str, product_id: str, size: str) -> ProductVariant:
    prod = db.get(Product, product_id)
    if not prod or prod.tenant_id != tenant_id or not prod.active:
        raise DomainError(404, "product_not_found", f"Product {product_id} not found")
    for v in prod.variants:
        if v.size == size:
            return v
    raise DomainError(422, "size_not_found", f"Size {size} does not exist for {prod.name}")


def catalog_dicts(db: Session, tenant_id: str) -> list[dict]:
    prods = db.scalars(select(Product).where(Product.tenant_id == tenant_id, Product.active.is_(True))).all()
    return [{"id": p.id, "name": p.name, "category": p.category, "price_pkr": p.price_pkr, "cod_eligible": p.cod_eligible,
             "fit_notes": p.fit_notes, "variants": [{"size": v.size, "stock": v.stock} for v in p.variants]} for p in prods]


# ------------------------------------------------------------------ pricing
def totals(db: Session, cart: Cart, city: str | None = None, discount_code: str | None = None) -> dict:
    pol = policy_of(db, cart.tenant_id)
    subtotal = sum(i.unit_price_pkr * i.quantity for i in cart.items)
    pct = 0
    code = discount_code if discount_code is not None else cart.promo_code
    if code:
        d = valid_discount(db, cart, code)
        pct = d.percent
    discount = round(subtotal * pct / 100)
    city = city or (cart.checkout.city if cart.checkout else get_shopper(db, cart.tenant_id, cart.shopper_id).city)
    ship = rules.shipping_fee(_policy_dict(pol), city, subtotal - discount) if cart.items else 0
    return {"subtotal_pkr": subtotal, "discount_pct": pct, "discount_pkr": discount, "shipping_pkr": ship,
            "total_pkr": subtotal - discount + ship, "city": city, "discount_code": code if pct else None}


def _policy_dict(pol: StorePolicy) -> dict:
    return {"delivery_windows": pol.delivery_windows, "shipping_fees": pol.shipping_fees,
            "free_shipping_threshold_pkr": pol.free_shipping_threshold_pkr, "cod_cities": pol.cod_cities,
            "cod_max_order_pkr": pol.cod_max_order_pkr, "exchange_policy": pol.exchange_policy,
            "returns_policy": pol.returns_policy}


def valid_discount(db: Session, cart: Cart, code: str) -> Discount:
    d = db.get(Discount, code.strip().upper())
    t = tenant_of(db, cart.tenant_id)
    if not d or d.tenant_id != cart.tenant_id:
        raise DomainError(422, "invalid_discount", "Discount code not valid")
    if d.cart_id and d.cart_id != cart.id:
        raise DomainError(422, "invalid_discount", "Discount code belongs to another cart")
    if d.single_use and d.used:
        raise DomainError(422, "discount_used", "Discount code already used")
    if d.percent > int(t.settings.get("discount_ceiling_pct", 0)) and d.issued_by == "ai":
        raise DomainError(422, "discount_over_ceiling", "Discount exceeds the merchant ceiling")
    return d


# ------------------------------------------------------------------ carts
def _apply_items(db: Session, cart: Cart, items: list[dict]) -> None:
    merged: dict[str, int] = {}
    variants: dict[str, ProductVariant] = {}
    for it in items:
        v = find_variant(db, cart.tenant_id, it["product_id"], it["size"])
        merged[v.id] = merged.get(v.id, 0) + int(it["quantity"])
        variants[v.id] = v
    for vid, qty in merged.items():
        v = variants[vid]
        if qty < 1:
            raise DomainError(422, "invalid_quantity", "Quantity must be at least 1")
        if qty > v.stock:
            raise DomainError(409, "insufficient_stock", f"Only {v.stock} left of {v.product.name} ({v.size})")
    cart.items.clear()
    db.flush()
    for vid, qty in merged.items():
        v = variants[vid]
        cart.items.append(CartItem(product_id=v.product_id, variant_id=v.id, quantity=qty, unit_price_pkr=v.product.price_pkr))


def create_cart(db: Session, tenant_id: str, shopper_id: str, items: list[dict], idempotency_key: str | None = None) -> Cart:
    get_shopper(db, tenant_id, shopper_id)
    if idempotency_key:
        existing = db.scalar(select(Cart).where(Cart.tenant_id == tenant_id, Cart.source_id == f"idem:{idempotency_key}"))
        if existing:
            return existing
    cart = Cart(tenant_id=tenant_id, shopper_id=shopper_id, source_id=f"idem:{idempotency_key}" if idempotency_key else None,
                created_at=Clock.now())
    db.add(cart)
    db.flush()
    _apply_items(db, cart, items)
    audit(db, tenant_id, "cart_created", cart.id, {"items": len(items)})
    _commit(db)
    return cart


def update_cart(db: Session, cart: Cart, items: list[dict] | None, promo_code: str | None) -> Cart:
    if cart.status not in EDITABLE:
        raise DomainError(409, "cart_closed", f"Cart is {cart.status} and can no longer be edited")
    if items is not None:
        _apply_items(db, cart, items)
    if promo_code is not None:
        if promo_code == "":
            cart.promo_code = None
        else:
            valid_discount(db, cart, promo_code)
            cart.promo_code = promo_code.strip().upper()
    audit(db, cart.tenant_id, "cart_updated", cart.id)
    _commit(db)
    return cart


def checkout_started(db: Session, cart: Cart, city: str, payment_method: str, whatsapp_opt_in: bool) -> Cart:
    if cart.status in CLOSED:
        raise DomainError(409, "cart_closed", "Cart already completed")
    if not cart.items:
        raise DomainError(422, "empty_cart", "Cart is empty")
    if cart.checkout:
        cart.checkout.city, cart.checkout.payment_method = city, payment_method
        cart.checkout.opted_in_at_checkout = cart.checkout.opted_in_at_checkout or whatsapp_opt_in
    else:
        cart.checkout = Checkout(city=city, payment_method=payment_method, opted_in_at_checkout=whatsapp_opt_in)
    if whatsapp_opt_in:
        grant_consent(db, cart.tenant_id, cart.shopper_id, source="checkout_form", commit=False)
    if cart.status == "active_cart":
        cart.status = "checkout_started"
    audit(db, cart.tenant_id, "checkout_started", cart.id, {"opt_in": whatsapp_opt_in, "city": city})
    _commit(db)
    return cart


# ------------------------------------------------------------------ consent
def active_consent(db: Session, tenant_id: str, shopper_id: str) -> ConsentRecord | None:
    rec = db.scalar(select(ConsentRecord).where(ConsentRecord.tenant_id == tenant_id, ConsentRecord.shopper_id == shopper_id,
                                                ConsentRecord.purpose == PURPOSE).order_by(ConsentRecord.created_at.desc()))
    if rec and rec.granted and rec.revoked_at is None:
        return rec
    return None


def ever_revoked(db: Session, tenant_id: str, shopper_id: str) -> bool:
    return db.scalar(select(func.count()).select_from(ConsentRecord).where(
        ConsentRecord.tenant_id == tenant_id, ConsentRecord.shopper_id == shopper_id,
        ConsentRecord.revoked_at.is_not(None))) > 0


def grant_consent(db: Session, tenant_id: str, shopper_id: str, source: str, commit: bool = True) -> ConsentRecord:
    """Explicit, unbundled, affirmative opt-in. Recorded with version, text, channel, purpose, source, time."""
    get_shopper(db, tenant_id, shopper_id)
    existing = active_consent(db, tenant_id, shopper_id)
    if existing:
        return existing
    t = tenant_of(db, tenant_id)
    rec = ConsentRecord(tenant_id=tenant_id, shopper_id=shopper_id, channel=CHANNEL, purpose=PURPOSE, granted=True,
                        consent_version=t.settings.get("consent_version", "v1"), consent_text=t.settings.get("consent_text", ""),
                        source=source, created_at=Clock.now())
    db.add(rec)
    audit(db, tenant_id, "consent_granted", None, {"shopper": shopper_id, "source": source, "version": rec.consent_version})
    if commit:
        _commit(db)
    return rec


def revoke_consent(db: Session, tenant_id: str, shopper_id: str, source: str, commit: bool = True) -> None:
    """STOP / opt-out takes effect immediately: revoke, cancel pending sends, mark carts opted_out."""
    now = Clock.now()
    recs = db.scalars(select(ConsentRecord).where(ConsentRecord.tenant_id == tenant_id, ConsentRecord.shopper_id == shopper_id,
                                                  ConsentRecord.purpose == PURPOSE, ConsentRecord.revoked_at.is_(None))).all()
    for r in recs:
        r.revoked_at = now
    carts = db.scalars(select(Cart).where(Cart.tenant_id == tenant_id, Cart.shopper_id == shopper_id)).all()
    for c in carts:
        for a in db.scalars(select(RecoveryAttempt).where(RecoveryAttempt.cart_id == c.id, RecoveryAttempt.status == "scheduled")):
            a.status, a.reason = "cancelled", "opted_out"
        if c.status not in CLOSED and c.status != "active_cart":
            c.status, c.status_reason = "opted_out", "opted_out"
    audit(db, tenant_id, "consent_revoked", None, {"shopper": shopper_id, "source": source, "records": len(recs)})
    if commit:
        _commit(db)


# ------------------------------------------------------------------ eligibility & recovery
def _in_quiet_hours(settings: dict) -> bool:
    if not settings.get("quiet_hours_enabled"):
        return False
    h = Clock.local().hour
    start, end = int(settings["quiet_start_hour"]), int(settings["quiet_end_hour"])
    return (start <= h or h < end) if start > end else (start <= h < end)


def _quiet_end(settings: dict):
    loc = Clock.local()
    end = loc.replace(hour=int(settings["quiet_end_hour"]), minute=0, second=0, microsecond=0)
    if end <= loc:
        end += timedelta(days=1)
    return end


def eligibility(db: Session, cart: Cart) -> str | None:
    """Return a block reason, or None if an outbound recovery message may be sent now-ish."""
    t = tenant_of(db, cart.tenant_id)
    st = t.settings
    shopper = get_shopper(db, cart.tenant_id, cart.shopper_id)
    if db.scalar(select(Order).where(Order.cart_id == cart.id)):
        return "already_purchased"
    if not cart.items:
        return "empty_cart"
    if not active_consent(db, cart.tenant_id, cart.shopper_id):
        return "opted_out" if ever_revoked(db, cart.tenant_id, cart.shopper_id) else "no_consent"
    if shopper.age_band == "under_18":
        return "under_18_safeguard"
    if not st.get("campaign_enabled", True):
        return "campaign_paused"
    if cart.recovery_paused:
        return "cart_paused"
    sent = db.scalar(select(func.count()).select_from(RecoveryAttempt).where(
        RecoveryAttempt.cart_id == cart.id, RecoveryAttempt.status == "sent"))
    if sent >= int(st.get("max_messages_per_cart", 1)):
        return "contact_cap"
    return None


def abandon(db: Session, cart: Cart, idempotency_key: str | None = None) -> Cart:
    """Explicit abandonment event (demo action or platform webhook). Never triggered by just viewing a cart."""
    key = f"abandon:{cart.id}:{idempotency_key or 'default'}"
    if not audit(db, cart.tenant_id, "cart_abandoned", cart.id, {}, idempotency_key=key):
        return cart  # duplicate event: no-op
    if cart.status in CLOSED or cart.status == "opted_out":
        _commit(db)
        return cart
    if cart.status not in ("checkout_started", "active_cart"):
        _commit(db)
        return cart
    if cart.status == "active_cart":
        raise DomainError(409, "checkout_not_started", "Only carts that reached checkout can be abandoned")
    cart.status, cart.abandoned_at = "abandoned", Clock.now()
    reason = eligibility(db, cart)
    t = tenant_of(db, cart.tenant_id)
    if reason:
        cart.status, cart.status_reason = "not_eligible", reason
        audit(db, cart.tenant_id, "recovery_blocked", cart.id, {"reason": reason})
    else:
        cart.status, cart.status_reason = "eligible", None
        if random.random() * 100 < float(t.settings.get("holdout_pct", 0)):
            cart.holdout, cart.status_reason = True, "holdout_control"
            audit(db, cart.tenant_id, "holdout_assigned", cart.id)
        else:
            _schedule(db, cart, t.settings)
    _commit(db)
    return cart


def _schedule(db: Session, cart: Cart, settings: dict, when=None) -> RecoveryAttempt:
    existing = db.scalar(select(RecoveryAttempt).where(RecoveryAttempt.cart_id == cart.id, RecoveryAttempt.status == "scheduled"))
    if existing:
        return existing
    n = db.scalar(select(func.count()).select_from(RecoveryAttempt).where(RecoveryAttempt.cart_id == cart.id)) + 1
    if when is None:
        if settings.get("accelerated_demo"):
            when = Clock.now() + timedelta(seconds=int(settings.get("demo_delay_seconds", 5)))
        else:
            when = Clock.now() + timedelta(minutes=int(settings.get("delay_minutes", 20)))
    att = RecoveryAttempt(tenant_id=cart.tenant_id, cart_id=cart.id, idempotency_key=f"send:{cart.id}:{n}", status="scheduled",
                          scheduled_for=when, channel=CHANNEL)
    db.add(att)
    cart.status = "scheduled"
    audit(db, cart.tenant_id, "recovery_scheduled", cart.id, {"scheduled_for": when.isoformat()})
    return att


def schedule(db: Session, cart: Cart) -> RecoveryAttempt:
    if cart.status not in ("eligible", "scheduled"):
        raise DomainError(409, "not_eligible", f"Cart is {cart.status} ({cart.status_reason or 'n/a'}); cannot schedule")
    reason = eligibility(db, cart)
    if reason:
        raise DomainError(409, "not_eligible", f"Blocked: {reason}")
    att = _schedule(db, cart, tenant_of(db, cart.tenant_id).settings)
    _commit(db)
    return att


def trigger_demo(db: Session, cart: Cart, demo_mode: bool) -> RecoveryAttempt:
    """Demo only: bypass the wait (never the consent / safety checks)."""
    if not demo_mode:
        raise DomainError(403, "demo_only", "Trigger-now is only available in demo mode")
    att = db.scalar(select(RecoveryAttempt).where(RecoveryAttempt.cart_id == cart.id, RecoveryAttempt.status == "scheduled"))
    if att is None:
        if cart.status == "eligible":
            att = _schedule(db, cart, tenant_of(db, cart.tenant_id).settings, when=Clock.now())
        else:
            reason = cart.status_reason or eligibility(db, cart) or cart.status
            raise DomainError(409, "not_eligible", f"No outbound message: {reason}")
    att.scheduled_for = Clock.now()
    db.flush()
    deliver(db, att)
    _commit(db)
    return att


def deliver(db: Session, att: RecoveryAttempt) -> str:
    """Send one scheduled attempt. All checks are repeated at send time. Returns resulting status."""
    cart = db.get(Cart, att.cart_id)
    t = tenant_of(db, cart.tenant_id)
    reason = eligibility(db, cart)
    if reason == "already_purchased":
        att.status, att.reason = "cancelled", reason
        audit(db, cart.tenant_id, "recovery_cancelled", cart.id, {"reason": reason})
        return att.status
    if reason:
        att.status, att.reason = "blocked", reason
        if cart.status not in CLOSED:
            cart.status, cart.status_reason = ("opted_out" if reason == "opted_out" else "not_eligible"), reason
        audit(db, cart.tenant_id, "recovery_blocked", cart.id, {"reason": reason})
        return att.status
    if _in_quiet_hours(t.settings):
        att.scheduled_for = _quiet_end(t.settings)
        audit(db, cart.tenant_id, "recovery_deferred_quiet_hours", cart.id, {"until": att.scheduled_for.isoformat()})
        return att.status
    # Atomic claim: only one worker can move scheduled -> sent (duplicate-send prevention).
    claimed = db.execute(update(RecoveryAttempt).where(RecoveryAttempt.id == att.id, RecoveryAttempt.status == "scheduled")
                         .values(status="sent", sent_at=Clock.now(), est_cost_pkr=int(t.settings.get("est_cost_per_message_pkr", 0))))
    if claimed.rowcount != 1:
        return "duplicate"
    db.refresh(att)
    shopper = get_shopper(db, cart.tenant_id, cart.shopper_id)
    conv = _conversation(db, cart, CHANNEL)
    item = cart.items[0].product.name if cart.items else "item"
    text = t.settings["template_recovery"].format(first_name=shopper.first_name, store=t.name, item=item)
    _add_message(db, conv, "ai", text, intent="recovery_template", source="template", language="en", confidence=1.0,
                 meta={"checkout_link": True, "link_label": "Complete checkout", "token": recovery_token(cart.id)})
    cart.status, cart.status_reason = "message_sent", None
    audit(db, cart.tenant_id, "recovery_sent", cart.id, {"channel": CHANNEL, "attempt": att.id})
    return "sent"


def run_due(db: Session) -> int:
    """Scheduler tick: deliver due attempts, expire stale contacts. Safe to run concurrently."""
    now = Clock.now()
    due = db.scalars(select(RecoveryAttempt).where(RecoveryAttempt.status == "scheduled", RecoveryAttempt.scheduled_for <= now)).all()
    n = 0
    for att in due:
        if deliver(db, att) == "sent":
            n += 1
    for cart in db.scalars(select(Cart).where(Cart.status.in_(CONTACTED))).all():
        window = int(tenant_of(db, cart.tenant_id).settings.get("attribution_window_days", 7))
        last = db.scalar(select(func.max(RecoveryAttempt.sent_at)).where(RecoveryAttempt.cart_id == cart.id))
        if last and as_utc(last) < now - timedelta(days=window):
            cart.status = "expired"
            audit(db, cart.tenant_id, "cart_expired", cart.id)
    if due or n:
        _commit(db)
    else:
        db.commit()
    return n


# ------------------------------------------------------------------ conversations
def _conversation(db: Session, cart: Cart, channel: str) -> Conversation:
    conv = db.scalar(select(Conversation).where(Conversation.cart_id == cart.id))
    if conv is None:
        conv = Conversation(tenant_id=cart.tenant_id, cart_id=cart.id, channel=channel)
        db.add(conv)
        db.flush()
    elif channel == CHANNEL and conv.channel != CHANNEL:
        conv.channel = CHANNEL
    return conv


def _add_message(db: Session, conv: Conversation, role: str, text: str, **kw) -> Message:
    seq = (db.scalar(select(func.max(Message.seq)).where(Message.conversation_id == conv.id)) or 0) + 1
    m = Message(conversation_id=conv.id, seq=seq, role=role, text=text, created_at=Clock.now(), **kw)
    db.add(m)
    db.flush()
    return m


def get_conversation(db: Session, cart: Cart) -> Conversation | None:
    return db.scalar(select(Conversation).where(Conversation.cart_id == cart.id))


def shopper_message(db: Session, cart: Cart, text: str, idempotency_key: str | None = None) -> list[Message]:
    text = rules.sanitize(text)
    if not text:
        raise DomainError(422, "empty_message", "Message is empty")
    if idempotency_key and not audit(db, cart.tenant_id, "shopper_message", cart.id, {"len": len(text)},
                                     idempotency_key=f"msg:{cart.id}:{idempotency_key}"):
        conv = get_conversation(db, cart)
        return list(conv.messages[-2:]) if conv else []
    # A shopper may always start an inbound on-site chat; outbound WhatsApp needs consent.
    conv = get_conversation(db, cart) or _conversation(db, cart, "onsite_chat")
    out = [_add_message(db, conv, "shopper", text)]
    if cart.status == "message_sent":
        cart.status = "replied"
    if conv.human_takeover:
        _commit(db)
        return out

    t = tenant_of(db, cart.tenant_id)
    shopper = get_shopper(db, cart.tenant_id, cart.shopper_id)
    tot = totals(db, cart)
    existing = db.scalar(select(Discount).where(Discount.cart_id == cart.id, Discount.used.is_(False)))
    ctx = rules.AssistantContext(
        store_name=t.name, first_name=shopper.first_name, city=tot["city"],
        lines=[rules.Line(i.product_id, i.product.name, i.variant.size, i.quantity, i.unit_price_pkr, i.product.cod_eligible) for i in cart.items],
        subtotal_pkr=tot["subtotal_pkr"], policy=_policy_dict(policy_of(db, cart.tenant_id)), settings=t.settings,
        catalog=catalog_dicts(db, cart.tenant_id), now_local=Clock.local(),
        existing_discount=(existing.code, existing.percent) if existing else None,
        candidate_code=f"CC-{secrets.token_hex(2).upper()}",
    )
    reply = rules.answer(text, ctx)
    source, final_text = "rules", reply.text
    llm = get_rephraser().rephrase(text, reply)
    if llm:
        source, final_text = "llm", llm
    meta = dict(reply.meta)
    if meta.get("checkout_link"):
        meta["token"] = recovery_token(cart.id)

    if reply.action == "opt_out":
        revoke_consent(db, cart.tenant_id, cart.shopper_id, source="stop_keyword", commit=False)
    elif reply.action == "handoff":
        conv.escalated = True
        if cart.status not in CLOSED and cart.status != "opted_out":
            cart.status = "human_handoff"
        audit(db, cart.tenant_id, "human_handoff", cart.id, {"intent": reply.intent})
    elif reply.action == "issue_discount":
        ceiling = int(t.settings.get("discount_ceiling_pct", 0))
        pct = min(int(meta["discount_pct"]), ceiling)
        db.add(Discount(code=meta["discount_code"], tenant_id=cart.tenant_id, percent=pct, cart_id=cart.id, single_use=True, issued_by="ai"))
        cart.promo_code = meta["discount_code"]
        audit(db, cart.tenant_id, "discount_issued", cart.id, {"pct": pct})
    out.append(_add_message(db, conv, "ai", final_text, intent=reply.intent, confidence=reply.confidence,
                            language=reply.language, source=source, meta=meta))
    audit(db, cart.tenant_id, "ai_reply", cart.id, {"intent": reply.intent, "source": source, "lang": reply.language})
    _commit(db)
    return out


def human_reply(db: Session, cart: Cart, text: str) -> Message:
    conv = get_conversation(db, cart) or _conversation(db, cart, "onsite_chat")
    conv.human_takeover = True
    m = _add_message(db, conv, "human", rules.sanitize(text), source="human")
    audit(db, cart.tenant_id, "human_reply", cart.id)
    _commit(db)
    return m


def set_takeover(db: Session, cart: Cart, on: bool) -> Conversation:
    conv = get_conversation(db, cart) or _conversation(db, cart, "onsite_chat")
    conv.human_takeover = on
    if not on:
        conv.escalated = False
        if cart.status == "human_handoff":
            cart.status = "replied"
    _add_message(db, conv, "system", "A team member joined the chat." if on else "The AI assistant is back.", source="system")
    audit(db, cart.tenant_id, "takeover_on" if on else "takeover_off", cart.id)
    _commit(db)
    return conv


def set_cart_paused(db: Session, cart: Cart, paused: bool) -> Cart:
    cart.recovery_paused = paused
    if paused:
        for a in db.scalars(select(RecoveryAttempt).where(RecoveryAttempt.cart_id == cart.id, RecoveryAttempt.status == "scheduled")):
            a.status, a.reason = "cancelled", "cart_paused"
        if cart.status == "scheduled":
            cart.status, cart.status_reason = "eligible", "cart_paused"
    audit(db, cart.tenant_id, "cart_paused" if paused else "cart_resumed", cart.id)
    _commit(db)
    return cart


# ------------------------------------------------------------------ orders
def place_order(db: Session, cart: Cart, payment_method: str, cod_confirmed: bool, idempotency_key: str,
                discount_code: str | None = None, recovery_token_value: str | None = None) -> tuple[Order, bool]:
    """Create an order exactly once. Returns (order, created)."""
    existing = db.scalar(select(Order).where(Order.idempotency_key == f"{cart.tenant_id}:{idempotency_key}"))
    if existing:
        if existing.cart_id != cart.id:
            raise DomainError(409, "idempotency_conflict", "Idempotency key used for another cart")
        return existing, False
    if db.scalar(select(Order).where(Order.cart_id == cart.id)):
        raise DomainError(409, "already_ordered", "This cart already has an order")
    if cart.status == "active_cart" or not cart.checkout:
        raise DomainError(409, "checkout_not_started", "Start checkout first")
    if not cart.items:
        raise DomainError(422, "empty_cart", "Cart is empty")
    if payment_method not in ("cod", "online_demo"):
        raise DomainError(422, "invalid_payment", "payment_method must be cod or online_demo")
    via_link = recovery_token_value is not None
    if via_link and not verify_recovery_token(cart.id, recovery_token_value):
        raise DomainError(403, "invalid_link", "Recovery link is invalid")
    for i in cart.items:
        if i.quantity > i.variant.stock:
            raise DomainError(409, "insufficient_stock", f"{i.product.name} ({i.variant.size}) is no longer in stock")
    code = discount_code if discount_code is not None else cart.promo_code
    tot = totals(db, cart, discount_code=code or "")
    if payment_method == "cod":
        pol = _policy_dict(policy_of(db, cart.tenant_id))
        lines = [rules.Line(i.product_id, i.product.name, i.variant.size, i.quantity, i.unit_price_pkr, i.product.cod_eligible) for i in cart.items]
        res = rules.cod_check(pol, tot["city"], lines, tot["total_pkr"])
        if res != "cod_yes":
            raise DomainError(422, res, "Cash on delivery is not available for this order")
        if not cod_confirmed:
            raise DomainError(422, "cod_not_confirmed", "Please confirm the cash-on-delivery order")
    now = Clock.now()
    order = Order(tenant_id=cart.tenant_id, cart_id=cart.id, idempotency_key=f"{cart.tenant_id}:{idempotency_key}",
                  payment_method=payment_method, cod_confirmed=cod_confirmed and payment_method == "cod", city=tot["city"],
                  subtotal_pkr=tot["subtotal_pkr"], discount_pkr=tot["discount_pkr"], shipping_pkr=tot["shipping_pkr"],
                  total_pkr=tot["total_pkr"], discount_code=tot["discount_code"], via_recovery_link=via_link, created_at=now,
                  lines=[{"product_id": i.product_id, "name": i.product.name, "size": i.variant.size, "quantity": i.quantity,
                          "unit_price_pkr": i.unit_price_pkr} for i in cart.items])
    db.add(order)
    for i in cart.items:
        i.variant.inventory.on_hand -= i.quantity
    if tot["discount_code"]:
        d = db.get(Discount, tot["discount_code"])
        if d.single_use:
            d.used = True
    db.flush()
    # Cancel any pending send (scenario F) and attribute if a contact happened inside the window.
    for a in db.scalars(select(RecoveryAttempt).where(RecoveryAttempt.cart_id == cart.id, RecoveryAttempt.status == "scheduled")):
        a.status, a.reason = "cancelled", "already_purchased"
        audit(db, cart.tenant_id, "recovery_cancelled", cart.id, {"reason": "already_purchased"})
    window = int(tenant_of(db, cart.tenant_id).settings.get("attribution_window_days", 7))
    sent = db.scalar(select(RecoveryAttempt).where(RecoveryAttempt.cart_id == cart.id, RecoveryAttempt.status == "sent")
                     .order_by(RecoveryAttempt.sent_at.desc()))
    if sent and now - as_utc(sent.sent_at) <= timedelta(days=window):
        cart.status = "recovered"
        db.add(AttributionEvent(tenant_id=cart.tenant_id, order_id=order.id, cart_id=cart.id, recovery_attempt_id=sent.id,
                                revenue_pkr=order.total_pkr, created_at=now))
        conv = get_conversation(db, cart)
        if conv:
            _add_message(db, conv, "system", f"Order {order.id} placed. Thank you!", source="system", meta={"order_id": order.id})
    else:
        cart.status = "ordered"
    audit(db, cart.tenant_id, "order_placed", cart.id, {"order": order.id, "total": order.total_pkr, "attributed": cart.status == "recovered"})
    _commit(db)
    return order, True


def _commit(db: Session) -> None:
    db.commit()
    ChangeFeed.bump()
