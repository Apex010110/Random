"""Merchant metrics computed from stored events only (never hardcoded).

Definitions (shown in the dashboard too):
  opt_in_rate              = opted-in checkout shoppers / checkout shoppers
  contact_rate             = contacted carts / eligible opted-in abandoned carts
  reply_rate               = carts with a shopper reply after contact / contacted carts
  observed_recovery_rate   = recovered carts / contacted carts
  attributed_recovered_sales = sum of non-canceled/refunded order totals attributed to a recovery contact
  incremental_lift         = treatment recovery rate - holdout recovery rate, only when both arms >= 30 carts
"""
from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.entities import (
    AttributionEvent,
    AuditEvent,
    Cart,
    ConsentRecord,
    Conversation,
    Message,
    Order,
    RecoveryAttempt,
)
from app.services import fulfillment
from app.services.commerce import tenant_of
from app.services.support import Clock, as_utc

MIN_ARM = 30

DEFINITIONS = {
    "opt_in_rate": "Opted-in checkout shoppers / checkout shoppers",
    "contact_rate": "Contacted carts / eligible opted-in abandoned carts",
    "reply_rate": "Carts with a shopper reply after contact / contacted carts",
    "observed_recovery_rate": "Recovered carts / contacted carts (not incremental)",
    "attributed_recovered_sales": "Sum of completed order totals placed within the attribution window after a recovery contact; excludes canceled/refunded",
    "incremental_lift": "Treatment minus holdout recovery rate. Needs a randomized holdout with at least 30 carts per arm",
}

GREEN_DEFINITIONS = {
    "cod_confirmation_rate": "Confirmed COD orders / COD orders requiring pre-dispatch confirmation",
    "failed_delivery_rate": "Orders with a failed first attempt / dispatched orders",
    "return_rate": "Returned orders / orders ever delivered",
    "consolidation_rate": "Not implemented in this demo (P1): eligible orders selecting consolidation / eligible orders offered it",
    "estimated_avoided_attempts": "eligible_orders_held_or_cancelled x assumed_failure_probability_without_intervention (illustrative; no estimate until an assumption is set)",
    "illustrative_co2e_kg": "estimated_avoided_attempts x assumed_km_per_avoided_attempt x assumed_kgco2e_per_km (assumption-driven, not a measured saving)",
    "illustrative_packaging_units": "verified_avoided_repack_events x assumed_packaging_units_per_repack_event (0 until a real avoided-repack signal exists; never inferred from unshipped orders)",
}


def _rate(n: int, d: int) -> dict:
    return {"numerator": n, "denominator": d, "value": (n / d) if d else None}


def compute_green(db: Session, tenant_id: str, orders: list[Order]) -> dict:
    """Green Logistics metrics. Every count comes from Order/fulfillment state actually reached;
    every estimate is gated behind an explicit, editable, merchant-set assumption (defaults to None)."""
    scen = fulfillment.default_scenario(db, tenant_id)
    assumptions = dict(scen.assumptions) if scen else {}

    cod_requiring_confirmation = [o for o in orders if o.payment_method == "cod"]
    confirmed = [o for o in cod_requiring_confirmation if o.cod_predispatch_confirmed]
    dispatched_ever = [o for o in orders if o.fulfillment_status in
                       (fulfillment.DISPATCHED, fulfillment.DELIVERED, fulfillment.FAILED, fulfillment.RETURNED)]
    failed = [o for o in orders if o.had_failed_attempt]
    ever_delivered = [o for o in orders if o.ever_delivered]
    returned = [o for o in orders if o.fulfillment_status == fulfillment.RETURNED]
    held_or_cancelled = [o for o in orders if o.was_held or o.fulfillment_status == fulfillment.CANCELLED]
    consolidated = [o for o in orders if o.delivery_consolidation_selected]
    size_resolved = [o for o in orders if o.size_question_resolved]

    p = assumptions.get("assumed_failure_probability_without_intervention")
    estimated_avoided_attempts = None
    sensitivity = None
    if p is not None:
        base = len(held_or_cancelled) * p
        estimated_avoided_attempts = base
        sensitivity = {"low": len(held_or_cancelled) * max(0.0, p * 0.5), "high": len(held_or_cancelled) * min(1.0, p * 1.5)}

    km = assumptions.get("assumed_km_per_avoided_attempt")
    co2_per_km = assumptions.get("assumed_kgco2e_per_km")
    illustrative_co2e_kg = estimated_avoided_attempts * km * co2_per_km if (estimated_avoided_attempts is not None and km and co2_per_km) else None

    # No "avoided repack" signal is produced anywhere in this demo yet, so this is honestly 0,
    # never inferred from orders that simply weren't shipped.
    verified_avoided_repack_events = 0
    pack_units = assumptions.get("assumed_packaging_units_per_repack_event")
    illustrative_packaging_units = verified_avoided_repack_events * pack_units if pack_units else None

    return {
        "scenario_id": scen.id if scen else None,
        "assumptions": assumptions,
        "counts": {
            "cod_orders": len(cod_requiring_confirmation),
            "cod_confirmed": len(confirmed),
            "dispatched": len(dispatched_ever),
            "failed_attempt": len(failed),
            "ever_delivered": len(ever_delivered),
            "returned": len(returned),
            "held_or_cancelled": len(held_or_cancelled),
            "size_questions_resolved": len(size_resolved),
            "consolidated": len(consolidated),
        },
        "rates": {
            "cod_confirmation_rate": _rate(len(confirmed), len(cod_requiring_confirmation)),
            "failed_delivery_rate": _rate(len(failed), len(dispatched_ever)),
            "return_rate": _rate(len(returned), len(ever_delivered)),
            "consolidation_rate": {"numerator": 0, "denominator": 0, "value": None, "label": "Not implemented (P1)"},
        },
        "estimates": {
            "estimated_avoided_attempts": estimated_avoided_attempts,
            "estimated_avoided_attempts_sensitivity": sensitivity,
            "illustrative_co2e_kg": illustrative_co2e_kg,
            "illustrative_packaging_units": illustrative_packaging_units,
        },
        "definitions": GREEN_DEFINITIONS,
        "banner": "Simulation only — no verified environmental impact or pilot outcomes.",
    }


def compute(db: Session, tenant_id: str, days: int | None = None) -> dict:
    t = tenant_of(db, tenant_id)
    since = Clock.now() - timedelta(days=days) if days else None
    carts = [c for c in db.scalars(select(Cart).where(Cart.tenant_id == tenant_id)).all()
             if since is None or as_utc(c.created_at) >= since]
    ids = {c.id for c in carts}
    checkout = [c for c in carts if c.checkout is not None]
    opted = [c for c in checkout if c.checkout.opted_in_at_checkout]
    abandoned = [c for c in carts if c.abandoned_at is not None]
    attempts = [a for a in db.scalars(select(RecoveryAttempt).where(RecoveryAttempt.tenant_id == tenant_id)).all() if a.cart_id in ids]
    sent_by_cart: dict[str, object] = {}
    for a in attempts:
        if a.status == "sent":
            sent_by_cart.setdefault(a.cart_id, as_utc(a.sent_at))
    contacted = set(sent_by_cart)
    eligible_opted_abandoned = {c.id for c in abandoned if c.status_reason not in
                                {"no_consent", "under_18_safeguard", "opted_out"} and not c.holdout} | contacted

    replied = set()
    for conv in db.scalars(select(Conversation).where(Conversation.tenant_id == tenant_id)).all():
        if conv.cart_id in contacted:
            sent_at = sent_by_cart[conv.cart_id]
            if any(m.role == "shopper" and as_utc(m.created_at) >= sent_at for m in conv.messages):
                replied.add(conv.cart_id)

    atts = [e for e in db.scalars(select(AttributionEvent).where(AttributionEvent.tenant_id == tenant_id)).all() if e.cart_id in ids]
    orders = {o.id: o for o in db.scalars(select(Order).where(Order.tenant_id == tenant_id)).all()}
    valid_atts = [e for e in atts if orders[e.order_id].status not in ("canceled", "refunded")]
    recovered = {e.cart_id for e in valid_atts}
    all_orders = [o for o in orders.values() if o.cart_id in ids]

    blocked: dict[str, int] = {}
    for c in carts:
        if c.status == "not_eligible" and c.status_reason:
            blocked[c.status_reason] = blocked.get(c.status_reason, 0) + 1
    for a in attempts:
        if a.status in ("blocked", "cancelled") and a.reason:
            blocked[a.reason] = blocked.get(a.reason, 0) + 1

    opt_outs = len([r for r in db.scalars(select(ConsentRecord).where(ConsentRecord.tenant_id == tenant_id,
                                                                     ConsentRecord.revoked_at.is_not(None))).all()
                    if since is None or as_utc(r.revoked_at) >= since])
    messages_sent = len([a for a in attempts if a.status == "sent"])
    ai_msgs = db.scalars(select(Message).join(Conversation).where(Conversation.tenant_id == tenant_id, Message.role == "ai")).all()
    est_cost = sum(a.est_cost_pkr for a in attempts if a.status == "sent")

    holdout = [c for c in carts if c.holdout]
    treated = [c for c in carts if c.id in contacted]
    if len(holdout) >= MIN_ARM and len(treated) >= MIN_ARM:
        h_rate = len([c for c in holdout if c.status in ("ordered", "recovered")]) / len(holdout)
        tr_rate = len(recovered) / len(treated)
        lift = {"measured": True, "value": tr_rate - h_rate, "holdout_carts": len(holdout), "treated_carts": len(treated)}
    else:
        lift = {"measured": False, "value": None, "label": "Not measured", "holdout_carts": len(holdout), "treated_carts": len(treated)}

    attributed_sales = sum(e.revenue_pkr for e in valid_atts)
    return {
        "tenant_id": tenant_id, "is_demo_data": t.is_demo, "window_days": days,
        "generated_at": Clock.now().isoformat(),
        "counts": {
            "carts_created": len(carts), "checkouts_started": len(checkout), "opted_in": len(opted),
            "abandoned": len(abandoned), "eligible_abandoned": len(eligible_opted_abandoned), "contacted": len(contacted),
            "replied": len(replied), "recovered": len(recovered), "orders_total": len(all_orders),
            "opt_outs": opt_outs, "messages_sent": messages_sent, "ai_replies": len(ai_msgs),
            "human_handoffs": len([c for c in carts if c.status == "human_handoff"]),
            "blocked_or_cancelled": sum(blocked.values()),
        },
        "blocked_reasons": blocked,
        "rates": {
            "opt_in_rate": _rate(len(opted), len(checkout)),
            "contact_rate": _rate(len(contacted), len(eligible_opted_abandoned)),
            "reply_rate": _rate(len(replied), len(contacted)),
            "observed_recovery_rate": _rate(len(recovered), len(contacted)),
        },
        "money": {
            "currency": "PKR",
            "attributed_recovered_sales_pkr": attributed_sales,
            "all_order_sales_pkr": sum(o.total_pkr for o in all_orders if o.status == "placed"),
            "estimated_messaging_cost_pkr": est_cost,
            "cost_assumption": f"PKR {t.settings.get('est_cost_per_message_pkr', 0)} per sent message (merchant-set assumption, not a quote)",
            "note": "Attributed sales are gross order totals, not profit and not proven incremental.",
        },
        "incremental_lift": lift,
        "funnel": [
            {"stage": "cart_created", "label": "Cart created", "count": len(carts)},
            {"stage": "abandoned", "label": "Abandoned at checkout", "count": len(abandoned)},
            {"stage": "opted_in", "label": "Opted in (of abandoned)", "count": len([c for c in abandoned if c.checkout and c.checkout.opted_in_at_checkout])},
            {"stage": "contacted", "label": "Contacted", "count": len(contacted)},
            {"stage": "replied", "label": "Replied", "count": len(replied)},
            {"stage": "recovered", "label": "Recovered (order placed)", "count": len(recovered)},
        ],
        "definitions": DEFINITIONS,
        "green": compute_green(db, tenant_id, all_orders),
        "recent_events": [
            {"type": e.type, "cart_id": e.cart_id, "at": as_utc(e.created_at).isoformat(), "detail": e.detail}
            for e in db.scalars(select(AuditEvent).where(AuditEvent.tenant_id == tenant_id)
                                .order_by(AuditEvent.created_at.desc()).limit(25)).all()
        ],
    }
