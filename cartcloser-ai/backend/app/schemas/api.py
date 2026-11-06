"""Typed request/response schemas (documented in OpenAPI at /docs and /openapi.json)."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


class ErrorOut(BaseModel):
    error: str
    message: str


class VariantOut(BaseModel):
    size: str
    stock: int


class ProductOut(BaseModel):
    id: str
    name: str
    category: str
    description: str
    fit_notes: str
    price_pkr: int
    cod_eligible: bool
    image_key: str
    color_hex: str
    active: bool
    variants: list[VariantOut]


class PolicyOut(BaseModel):
    delivery_windows: dict[str, list[int]]
    shipping_fees: dict[str, int]
    free_shipping_threshold_pkr: int
    cod_cities: list[str]
    cod_max_order_pkr: int
    exchange_policy: str
    returns_policy: str


class Page(BaseModel):
    total: int
    limit: int
    offset: int


class ProductPage(Page):
    items: list[ProductOut]


class CartItemIn(BaseModel):
    product_id: str = Field(min_length=1, max_length=64)
    size: str = Field(min_length=1, max_length=16)
    quantity: int = Field(ge=1, le=10)


class CartCreate(BaseModel):
    items: list[CartItemIn] = Field(min_length=1, max_length=20)
    idempotency_key: str | None = Field(default=None, max_length=100)


class CartPatch(BaseModel):
    items: list[CartItemIn] | None = Field(default=None, max_length=20)
    promo_code: str | None = Field(default=None, max_length=32)


class CheckoutStartedIn(BaseModel):
    city: str = Field(min_length=2, max_length=64)
    payment_method: Literal["cod", "online_demo"] = "cod"
    # Must be an explicit, unbundled, unchecked-by-default choice in the UI.
    whatsapp_opt_in: bool = False


class AbandonIn(BaseModel):
    idempotency_key: str | None = Field(default=None, max_length=100)


class CartLineOut(BaseModel):
    product_id: str
    name: str
    size: str
    quantity: int
    unit_price_pkr: int
    cod_eligible: bool


class TotalsOut(BaseModel):
    subtotal_pkr: int
    discount_pct: int
    discount_pkr: int
    shipping_pkr: int
    total_pkr: int
    city: str
    discount_code: str | None


class CartOut(BaseModel):
    id: str
    shopper_id: str
    status: str
    status_reason: str | None
    items: list[CartLineOut]
    totals: TotalsOut
    promo_code: str | None
    checkout: dict | None
    consent: dict | None
    recovery_paused: bool
    holdout: bool
    abandoned_at: datetime | None
    created_at: datetime
    recovery_attempts: list[dict]
    order_id: str | None
    recovery_link: str | None


class ConsentIn(BaseModel):
    shopper_id: str
    source: Literal["checkout_form", "preferences"] = "preferences"
    affirmative: Literal[True] = Field(description="Must be true: consent is an explicit affirmative action")


class ConsentRevokeIn(BaseModel):
    shopper_id: str
    source: Literal["preferences", "stop_keyword", "merchant"] = "preferences"


class ConsentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    shopper_id: str
    channel: str
    purpose: str
    granted: bool
    consent_version: str
    consent_text: str
    source: str
    created_at: datetime
    revoked_at: datetime | None


class MessageIn(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    idempotency_key: str | None = Field(default=None, max_length=100)


class MessageOut(BaseModel):
    id: str
    seq: int
    role: str
    text: str
    intent: str | None
    confidence: float | None
    language: str | None
    source: str | None
    meta: dict
    created_at: datetime


class ConversationOut(BaseModel):
    cart_id: str
    channel: str
    human_takeover: bool
    escalated: bool
    messages: list[MessageOut]


class OrderIn(BaseModel):
    cart_id: str
    payment_method: Literal["cod", "online_demo"]
    cod_confirmed: bool = False
    discount_code: str | None = Field(default=None, max_length=32)
    recovery_token: str | None = Field(default=None, max_length=64, description="Present when the order came from a recovery link")
    idempotency_key: str = Field(min_length=8, max_length=100)


class OrderOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    cart_id: str
    status: str
    payment_method: str
    cod_confirmed: bool
    city: str
    subtotal_pkr: int
    discount_pkr: int
    shipping_pkr: int
    total_pkr: int
    discount_code: str | None
    via_recovery_link: bool
    lines: list[dict]
    created_at: datetime
    attributed: bool = False
    # Green Logistics fulfillment lifecycle
    fulfillment_status: str
    delivery_zone: str | None
    address_redacted: str | None
    size_question_resolved: bool
    cod_predispatch_confirmed: bool
    had_failed_attempt: bool
    ever_delivered: bool
    was_held: bool
    delivery_consolidation_selected: bool
    scenario_id: str | None


class ConfirmCodIn(BaseModel):
    confirmed: bool
    delivery_zone_ok: bool = True
    availability_ok: bool = True


class CorrectAddressIn(BaseModel):
    address_redacted: str = Field(min_length=1, max_length=120)
    delivery_zone: str = Field(min_length=1, max_length=64)


class HoldIn(BaseModel):
    reason: str = Field(default="", max_length=120)


class ReasonIn(BaseModel):
    reason: str = Field(default="", max_length=120)


class AssumptionsPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    assumed_failure_probability_without_intervention: float | None = Field(default=None, ge=0, le=1)
    assumed_km_per_avoided_attempt: float | None = Field(default=None, ge=0, le=500)
    assumed_kgco2e_per_km: float | None = Field(default=None, ge=0, le=10)
    assumed_packaging_units_per_repack_event: float | None = Field(default=None, ge=0, le=20)


class SettingsPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    campaign_enabled: bool | None = None
    delay_minutes: int | None = Field(default=None, ge=1, le=1440)
    demo_delay_seconds: int | None = Field(default=None, ge=1, le=120)
    accelerated_demo: bool | None = None
    max_messages_per_cart: int | None = Field(default=None, ge=0, le=3)
    quiet_hours_enabled: bool | None = None
    quiet_start_hour: int | None = Field(default=None, ge=0, le=23)
    quiet_end_hour: int | None = Field(default=None, ge=0, le=23)
    discount_enabled: bool | None = None
    discount_ceiling_pct: int | None = Field(default=None, ge=0, le=30)
    attribution_window_days: int | None = Field(default=None, ge=1, le=30)
    holdout_pct: float | None = Field(default=None, ge=0, le=50)
    est_cost_per_message_pkr: int | None = Field(default=None, ge=0, le=1000)
    template_recovery: str | None = Field(default=None, min_length=10, max_length=500)


class VariantPatch(BaseModel):
    size: str
    stock: int = Field(ge=0, le=100000)


class ProductPatch(BaseModel):
    id: str
    price_pkr: int | None = Field(default=None, ge=1, le=10_000_000)
    cod_eligible: bool | None = None
    active: bool | None = None
    fit_notes: str | None = Field(default=None, max_length=500)
    variants: list[VariantPatch] | None = None


class PolicyPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    delivery_windows: dict[str, list[int]] | None = None
    shipping_fees: dict[str, int] | None = None
    free_shipping_threshold_pkr: int | None = Field(default=None, ge=0)
    cod_cities: list[str] | None = None
    cod_max_order_pkr: int | None = Field(default=None, ge=0)
    exchange_policy: str | None = Field(default=None, max_length=1000)
    returns_policy: str | None = Field(default=None, max_length=1000)


class CatalogPatch(BaseModel):
    products: list[ProductPatch] = []
    policy: PolicyPatch | None = None


class HumanReplyIn(BaseModel):
    text: str = Field(min_length=1, max_length=500)


class FlagIn(BaseModel):
    on: bool


class Metrics(BaseModel):
    model_config = ConfigDict(extra="allow")
    tenant_id: str
    is_demo_data: bool
    counts: dict[str, int]
    rates: dict[str, Any]
    money: dict[str, Any]
    incremental_lift: dict[str, Any]
    funnel: list[dict]
    definitions: dict[str, str]
    green: dict[str, Any] | None = None
