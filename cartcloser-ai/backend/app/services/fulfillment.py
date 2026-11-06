"""Green Logistics fulfillment state machine (see docs/green_logistics.md and the MRD).

Order fulfillment lifecycle (separate from Order.status, which is the existing placed/canceled/refunded
cart-recovery lifecycle):

  pending_confirmation --confirm(ok)--> ready_to_dispatch
  pending_confirmation --confirm(reject/no evidence)--> hold | cancelled   (merchant policy decides; never
                                                                             auto-marked as a prevented failure)
  hold --release--> ready_to_dispatch
  hold --cancel--> cancelled
  ready_to_dispatch --dispatch--> dispatched
  ready_to_dispatch --hold--> hold
  dispatched --mark_delivered--> delivered
  dispatched --mark_failed_attempt--> failed_attempt
  failed_attempt --retry_dispatch--> ready_to_dispatch
  failed_attempt --mark_returned--> returned
  delivered --mark_returned--> returned
  {pending_confirmation, hold, ready_to_dispatch} --cancel--> cancelled

All transitions are guarded: calling one from a status that doesn't allow it raises illegal_transition
(this also makes duplicate confirmation a no-op/error instead of double counting metrics).
"""
from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.entities import Conversation, Order, Tenant
from app.services.support import DomainError, audit

PENDING = "pending_confirmation"
HOLD = "hold"
READY = "ready_to_dispatch"
DISPATCHED = "dispatched"
DELIVERED = "delivered"
FAILED = "failed_attempt"
RETURNED = "returned"
CANCELLED = "cancelled"

ALL_STATUSES = (PENDING, HOLD, READY, DISPATCHED, DELIVERED, FAILED, RETURNED, CANCELLED)
TERMINAL = {RETURNED, CANCELLED}

_ALLOWED: dict[str, set[str]] = {
    PENDING: {READY, HOLD, CANCELLED},
    HOLD: {READY, CANCELLED},
    READY: {DISPATCHED, HOLD, CANCELLED},
    DISPATCHED: {DELIVERED, FAILED},
    FAILED: {READY, RETURNED, CANCELLED},
    DELIVERED: {RETURNED},
    RETURNED: set(),
    CANCELLED: set(),
}


def _move(db: Session, order: Order, target: str, event_type: str, detail: dict | None = None) -> Order:
    if target not in _ALLOWED.get(order.fulfillment_status, set()):
        raise DomainError(409, "illegal_transition", f"Cannot move order from {order.fulfillment_status} to {target}")
    order.fulfillment_status = target
    audit(db, order.tenant_id, event_type, order_id=order.id, scenario_id=order.scenario_id, detail=detail or {})
    return order


def requires_predispatch_confirmation(tenant: Tenant, order: Order) -> bool:
    return order.payment_method == "cod" and bool(tenant.settings.get("cod_predispatch_confirmation_required", True))


def _size_question_resolved(db: Session, cart_id: str) -> bool:
    """A shopper asked (and the assistant answered from real catalog data) before this order existed."""
    conv = db.scalar(select(Conversation).where(Conversation.cart_id == cart_id))
    if not conv:
        return False
    return any(m.role == "ai" and m.intent in ("size", "stock") for m in conv.messages)


def init_fulfillment(db: Session, tenant: Tenant, order: Order, scenario_id: str | None, consent_active: bool) -> Order:
    """Called once, right after an order is placed. Decides the initial fulfillment status."""
    order.scenario_id = scenario_id
    order.delivery_zone = order.city
    order.size_question_resolved = _size_question_resolved(db, order.cart_id)
    if requires_predispatch_confirmation(tenant, order):
        order.fulfillment_status = PENDING
        channel = "whatsapp_sim" if consent_active else "onsite"
        audit(db, order.tenant_id, "cod_confirmation_requested", order_id=order.id, scenario_id=scenario_id,
              detail={"channel": channel})
    else:
        order.fulfillment_status = READY
        audit(db, order.tenant_id, "fulfillment_ready", order_id=order.id, scenario_id=scenario_id)
    return order


def confirm_cod(db: Session, tenant: Tenant, order: Order, confirmed: bool, delivery_zone_ok: bool = True,
                availability_ok: bool = True) -> Order:
    if order.fulfillment_status != PENDING:
        raise DomainError(409, "illegal_transition",
                          f"Order is {order.fulfillment_status}; no confirmation is pending")
    ok = confirmed and delivery_zone_ok and availability_ok
    if ok:
        order.cod_predispatch_confirmed = True
        return _move(db, order, READY, "cod_confirmed", {"delivery_zone_ok": delivery_zone_ok, "availability_ok": availability_ok})
    policy = tenant.settings.get("cod_rejection_policy", "hold")
    reason = "rejected" if not confirmed else ("delivery_zone_not_ok" if not delivery_zone_ok else "not_available")
    target = CANCELLED if policy == "cancel" else HOLD
    if target == HOLD:
        order.was_held = True
    return _move(db, order, target, "cod_not_confirmed", {"reason": reason, "policy": policy})


def correct_address(db: Session, order: Order, address_redacted: str, delivery_zone: str) -> Order:
    if order.fulfillment_status not in (PENDING, HOLD):
        raise DomainError(409, "illegal_transition", f"Order is {order.fulfillment_status}; address can only be corrected while pending confirmation or on hold")
    order.address_redacted = address_redacted
    order.delivery_zone = delivery_zone
    audit(db, order.tenant_id, "address_corrected", order_id=order.id, scenario_id=order.scenario_id,
          detail={"delivery_zone": delivery_zone})
    return order


def hold(db: Session, order: Order, reason: str) -> Order:
    order.was_held = True
    return _move(db, order, HOLD, "order_held", {"reason": reason})


def release(db: Session, order: Order) -> Order:
    return _move(db, order, READY, "order_released")


def dispatch(db: Session, order: Order) -> Order:
    return _move(db, order, DISPATCHED, "dispatch_authorized")


def retry_dispatch(db: Session, order: Order) -> Order:
    return _move(db, order, READY, "retry_scheduled")


def mark_delivered(db: Session, order: Order) -> Order:
    order.ever_delivered = True
    return _move(db, order, DELIVERED, "order_delivered")


def mark_failed_attempt(db: Session, order: Order, reason: str = "") -> Order:
    order.had_failed_attempt = True
    return _move(db, order, FAILED, "delivery_attempt_failed", {"reason": reason})


def mark_returned(db: Session, order: Order, reason: str = "") -> Order:
    return _move(db, order, RETURNED, "order_returned", {"reason": reason})


def cancel(db: Session, order: Order, reason: str = "") -> Order:
    return _move(db, order, CANCELLED, "order_cancelled", {"reason": reason})


def resolve_size_question(db: Session, order: Order) -> Order:
    if not order.size_question_resolved:
        order.size_question_resolved = True
        audit(db, order.tenant_id, "size_clarified", order_id=order.id, scenario_id=order.scenario_id)
    return order


def default_scenario(db: Session, tenant_id: str):
    from app.models.entities import Scenario

    return db.scalar(select(Scenario).where(Scenario.tenant_id == tenant_id, Scenario.id == f"{tenant_id}:live"))


def patch_assumptions(db: Session, tenant_id: str, patch: dict) -> dict:
    scen = default_scenario(db, tenant_id)
    if scen is None:
        from app.models.entities import Scenario

        scen = Scenario(id=f"{tenant_id}:live", tenant_id=tenant_id, name="Live demo", assumptions={})
        db.add(scen)
    scen.assumptions = {**scen.assumptions, **patch}
    audit(db, tenant_id, "assumptions_updated", scenario_id=scen.id, detail={"keys": sorted(patch)})
    return scen.assumptions
