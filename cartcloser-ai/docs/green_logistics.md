# Green Logistics extension

Adds pre-dispatch order confirmation and a failed-delivery-prevention state machine on top of the
existing cart-recovery product (which is unchanged). Built from the "CartCloser AI — Green
Logistics Extension MRD v1.0". **Proposed enhancement, not a validated environmental result** — see
Guardrails below.

## What it demonstrates

A COD order is not dispatched blindly: the merchant (or the shopper, in a real deployment) confirms
the order, the delivery area and availability before a courier is ever sent. Address problems get
corrected and held for manual review, not silently retried. Every count on the dashboard comes from
an event that actually happened in this demo session; every environmental or "avoided delivery"
number is an **illustrative estimate** that only appears once a merchant explicitly sets the
assumption behind it, with a visible sensitivity range.

## Fulfillment state machine

`Order.fulfillment_status` (separate from the existing cart-recovery `Order.status`):

```
pending_confirmation --confirm(ok)--------> ready_to_dispatch
pending_confirmation --confirm(reject)----> hold | cancelled      (merchant policy: cod_rejection_policy)
hold                 --release------------> ready_to_dispatch
hold                 --cancel--------------> cancelled
ready_to_dispatch    --dispatch-----------> dispatched
ready_to_dispatch     --hold---------------> hold
dispatched           --mark_delivered-----> delivered
dispatched           --mark_failed_attempt-> failed_attempt
failed_attempt       --retry_dispatch-----> ready_to_dispatch
failed_attempt        --mark_returned------> returned
delivered             --mark_returned------> returned
{pending_confirmation, hold, ready_to_dispatch} --cancel--> cancelled
```

Every transition is guarded (`app/services/fulfillment.py`, mirrored in
`flutter_app/lib/core/engine/demo_engine.dart`): calling one from a status that doesn't allow it
raises `illegal_transition` instead of silently succeeding. That's also how duplicate confirmation
is rejected rather than double-counted (MRD acceptance test).

A COD order starts in `pending_confirmation` only when the tenant setting
`cod_predispatch_confirmation_required` is true (default). Non-COD (`online_demo`) orders skip
straight to `ready_to_dispatch` — there is nothing to confirm.

## Metrics (`GET /merchant/metrics` → `green`)

| Field | Formula |
|---|---|
| `cod_confirmation_rate` | confirmed COD orders / COD orders requiring confirmation |
| `failed_delivery_rate` | orders with a failed attempt / dispatched orders |
| `return_rate` | returned orders / orders ever delivered |
| `consolidation_rate` | **Not implemented (P1)** — always shows "Not implemented" |
| `estimated_avoided_attempts` | `held_or_cancelled x assumed_failure_probability_without_intervention` — `null` until that assumption is set |
| `illustrative_co2e_kg` | `estimated_avoided_attempts x assumed_km_per_avoided_attempt x assumed_kgco2e_per_km` |
| `illustrative_packaging_units` | `verified_avoided_repack_events x assumed_packaging_units_per_repack_event` — `verified_avoided_repack_events` is honestly `0` in this demo (no such signal exists yet); never inferred from orders that simply weren't shipped |

Assumptions are stored per-tenant on a `Scenario` row (`POST /merchant/assumptions`) and default to
`null` (no numeric estimate shown). Changing an assumption recalculates the estimate but never
changes an observed count.

## API

`POST /orders/{id}/confirm-cod · correct-address · hold · release · dispatch · retry-dispatch · delivered · failed-attempt · returned · cancel`
`GET /merchant/orders?fulfillment_status=` (the 7 MRD tabs) · `GET /merchant/events?order_id=` · `POST /merchant/assumptions`

All are merchant-authenticated demo controls (same bearer token as the rest of `/merchant/*`) — in
this demo, one operator drives both the "shopper confirms" and "merchant dispatches" sides, same as
the existing "Trigger recovery now (demo)" button simulates an outbound send.

## Guardrails (MRD §16)

- No fabricated sustainability statistics, compliance approval, real WhatsApp/courier integration,
  or validated cart-recovery rates.
- COD confirmation alone is never claimed to guarantee an emissions reduction.
- Rejection/no-response is never auto-labelled a "prevented failed delivery" — it only moves to
  `hold`/`cancelled` per merchant policy; the counterfactual estimate above is the only place an
  avoided-attempt number appears, and it's explicitly assumption-driven.
- Size clarification reuses the existing grounded, catalog-only assistant (`size`/`stock` intents);
  it is tracked (`size_question_resolved`) but never used to assert a return was prevented.

## Known limitations (deferred per MRD §3 priority order)

- **P1, not built**: delivery consolidation (eligibility + shopper opt-in), merchant settings UI for
  the two new policy toggles, a dedicated side-by-side Scenario Compare screen (the baseline number
  shows inline on the Green Logistics dashboard instead).
- **P2, not built**: real courier APIs, live WhatsApp Cloud API, live LLM-driven confirmation,
  Shopify/WooCommerce plugins, carbon accounting with verified courier data.
- The existing guided **Judge demo** tour (scenarios A–H) was not extended with scripted Green
  Logistics steps in this pass. The module is reached manually: place a COD order as a shopper,
  then **Merchant → Orders** to confirm/hold/dispatch it, and **Merchant → Green Logistics** for
  the dashboard. A scripted walkthrough is a reasonable next addition, not yet done.
