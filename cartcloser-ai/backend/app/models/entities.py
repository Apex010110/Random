"""SQLAlchemy ORM entities. All tenant-owned rows carry tenant_id; money is integer PKR."""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    JSON,
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:12]}"


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now_utc)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now_utc, onupdate=now_utc)


class Tenant(TimestampMixin, Base):
    __tablename__ = "tenants"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    currency: Mapped[str] = mapped_column(String(3), default="PKR")
    is_demo: Mapped[bool] = mapped_column(Boolean, default=True)
    # Campaign settings (delay, caps, quiet hours, templates, discount ceiling, attribution window).
    settings: Mapped[dict] = mapped_column(JSON, default=dict)


class MerchantUser(TimestampMixin, Base):
    __tablename__ = "merchant_users"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("mu"))
    tenant_id: Mapped[str] = mapped_column(ForeignKey("tenants.id"), index=True)
    email: Mapped[str] = mapped_column(String(200))
    api_token: Mapped[str] = mapped_column(String(200), unique=True)
    role: Mapped[str] = mapped_column(String(32), default="owner")


class Product(TimestampMixin, Base):
    __tablename__ = "products"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    tenant_id: Mapped[str] = mapped_column(ForeignKey("tenants.id"), index=True)
    source_id: Mapped[str | None] = mapped_column(String(128), nullable=True)  # Shopify/Woo id later
    name: Mapped[str] = mapped_column(String(200))
    category: Mapped[str] = mapped_column(String(64), index=True)
    description: Mapped[str] = mapped_column(Text)
    fit_notes: Mapped[str] = mapped_column(Text, default="")
    price_pkr: Mapped[int] = mapped_column(Integer)
    cod_eligible: Mapped[bool] = mapped_column(Boolean, default=True)
    image_key: Mapped[str] = mapped_column(String(64), default="kurta")
    color_hex: Mapped[str] = mapped_column(String(7), default="#3CE7E2")
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    variants: Mapped[list[ProductVariant]] = relationship(
        back_populates="product", cascade="all, delete-orphan", order_by="ProductVariant.position"
    )


class ProductVariant(Base):
    __tablename__ = "product_variants"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    product_id: Mapped[str] = mapped_column(ForeignKey("products.id"), index=True)
    size: Mapped[str] = mapped_column(String(16))
    position: Mapped[int] = mapped_column(Integer, default=0)
    product: Mapped[Product] = relationship(back_populates="variants")
    inventory: Mapped[Inventory] = relationship(back_populates="variant", uselist=False, cascade="all, delete-orphan")

    @property
    def stock(self) -> int:
        return self.inventory.on_hand if self.inventory else 0


class Inventory(Base):
    __tablename__ = "inventory"
    variant_id: Mapped[str] = mapped_column(ForeignKey("product_variants.id"), primary_key=True)
    on_hand: Mapped[int] = mapped_column(Integer, default=0)
    variant: Mapped[ProductVariant] = relationship(back_populates="inventory")


class StorePolicy(TimestampMixin, Base):
    """Fictional demo fulfilment and store policies. Never real shipping promises."""

    __tablename__ = "store_policies"
    tenant_id: Mapped[str] = mapped_column(ForeignKey("tenants.id"), primary_key=True)
    delivery_windows: Mapped[dict] = mapped_column(JSON)  # city -> [min_business_days, max_business_days]
    shipping_fees: Mapped[dict] = mapped_column(JSON)  # city -> PKR, "default" key
    free_shipping_threshold_pkr: Mapped[int] = mapped_column(Integer, default=6000)
    cod_cities: Mapped[list] = mapped_column(JSON)
    cod_max_order_pkr: Mapped[int] = mapped_column(Integer, default=15000)
    exchange_policy: Mapped[str] = mapped_column(Text)
    returns_policy: Mapped[str] = mapped_column(Text)
    version: Mapped[int] = mapped_column(Integer, default=1)


class Shopper(TimestampMixin, Base):
    __tablename__ = "shoppers"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)  # pseudonymous id
    tenant_id: Mapped[str] = mapped_column(ForeignKey("tenants.id"), index=True)
    first_name: Mapped[str] = mapped_column(String(80))
    phone_masked: Mapped[str] = mapped_column(String(32))  # only masked phone is stored in demo
    city: Mapped[str] = mapped_column(String(64))
    # adult | under_18 | unknown. Age is only recorded when the merchant already knows it.
    age_band: Mapped[str] = mapped_column(String(16), default="unknown")
    preferred_language: Mapped[str] = mapped_column(String(8), default="en")


class ConsentRecord(Base):
    __tablename__ = "consent_records"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("con"))
    tenant_id: Mapped[str] = mapped_column(ForeignKey("tenants.id"), index=True)
    shopper_id: Mapped[str] = mapped_column(ForeignKey("shoppers.id"), index=True)
    channel: Mapped[str] = mapped_column(String(32))  # whatsapp_sim | whatsapp
    purpose: Mapped[str] = mapped_column(String(64))  # checkout_reminders
    granted: Mapped[bool] = mapped_column(Boolean)
    consent_version: Mapped[str] = mapped_column(String(16))
    consent_text: Mapped[str] = mapped_column(Text)
    source: Mapped[str] = mapped_column(String(64))  # checkout_form | stop_keyword | preferences
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now_utc)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class Cart(TimestampMixin, Base):
    __tablename__ = "carts"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("cart"))
    tenant_id: Mapped[str] = mapped_column(ForeignKey("tenants.id"), index=True)
    shopper_id: Mapped[str] = mapped_column(ForeignKey("shoppers.id"), index=True)
    status: Mapped[str] = mapped_column(String(32), default="active_cart", index=True)
    status_reason: Mapped[str | None] = mapped_column(String(64), nullable=True)
    promo_code: Mapped[str | None] = mapped_column(String(32), nullable=True)
    recovery_paused: Mapped[bool] = mapped_column(Boolean, default=False)
    holdout: Mapped[bool] = mapped_column(Boolean, default=False)
    abandoned_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    source_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    items: Mapped[list[CartItem]] = relationship(back_populates="cart", cascade="all, delete-orphan")
    checkout: Mapped[Checkout | None] = relationship(back_populates="cart", uselist=False, cascade="all, delete-orphan")
    __table_args__ = (Index("ix_carts_tenant_status", "tenant_id", "status"),)


class CartItem(Base):
    __tablename__ = "cart_items"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("ci"))
    cart_id: Mapped[str] = mapped_column(ForeignKey("carts.id"), index=True)
    product_id: Mapped[str] = mapped_column(ForeignKey("products.id"))
    variant_id: Mapped[str] = mapped_column(ForeignKey("product_variants.id"))
    quantity: Mapped[int] = mapped_column(Integer, default=1)
    unit_price_pkr: Mapped[int] = mapped_column(Integer)
    cart: Mapped[Cart] = relationship(back_populates="items")
    product: Mapped[Product] = relationship()
    variant: Mapped[ProductVariant] = relationship()
    __table_args__ = (UniqueConstraint("cart_id", "variant_id"),)


class Checkout(TimestampMixin, Base):
    __tablename__ = "checkouts"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("chk"))
    cart_id: Mapped[str] = mapped_column(ForeignKey("carts.id"), unique=True)
    city: Mapped[str] = mapped_column(String(64))
    payment_method: Mapped[str] = mapped_column(String(16), default="cod")  # cod | card_on_delivery_link
    opted_in_at_checkout: Mapped[bool] = mapped_column(Boolean, default=False)
    cart: Mapped[Cart] = relationship(back_populates="checkout")


class Conversation(TimestampMixin, Base):
    __tablename__ = "conversations"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("conv"))
    tenant_id: Mapped[str] = mapped_column(ForeignKey("tenants.id"), index=True)
    cart_id: Mapped[str] = mapped_column(ForeignKey("carts.id"), unique=True)
    channel: Mapped[str] = mapped_column(String(32), default="whatsapp_sim")  # whatsapp_sim | onsite_chat
    human_takeover: Mapped[bool] = mapped_column(Boolean, default=False)
    escalated: Mapped[bool] = mapped_column(Boolean, default=False)
    messages: Mapped[list[Message]] = relationship(
        back_populates="conversation", cascade="all, delete-orphan", order_by="Message.seq"
    )


class Message(Base):
    __tablename__ = "messages"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("msg"))
    conversation_id: Mapped[str] = mapped_column(ForeignKey("conversations.id"), index=True)
    seq: Mapped[int] = mapped_column(Integer)
    role: Mapped[str] = mapped_column(String(16))  # shopper | ai | human | system
    text: Mapped[str] = mapped_column(Text)
    intent: Mapped[str | None] = mapped_column(String(32), nullable=True)
    confidence: Mapped[float | None] = mapped_column(nullable=True)
    language: Mapped[str | None] = mapped_column(String(8), nullable=True)
    source: Mapped[str | None] = mapped_column(String(16), nullable=True)  # rules | llm | template | human
    meta: Mapped[dict] = mapped_column(JSON, default=dict)  # e.g. checkout link, coupon code
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now_utc)
    conversation: Mapped[Conversation] = relationship(back_populates="messages")


class RecoveryAttempt(TimestampMixin, Base):
    __tablename__ = "recovery_attempts"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("rec"))
    tenant_id: Mapped[str] = mapped_column(ForeignKey("tenants.id"), index=True)
    cart_id: Mapped[str] = mapped_column(ForeignKey("carts.id"), index=True)
    idempotency_key: Mapped[str] = mapped_column(String(128), unique=True)
    status: Mapped[str] = mapped_column(String(16))  # scheduled | sent | cancelled | blocked
    reason: Mapped[str | None] = mapped_column(String(64), nullable=True)
    channel: Mapped[str] = mapped_column(String(32), default="whatsapp_sim")
    scheduled_for: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    est_cost_pkr: Mapped[int] = mapped_column(Integer, default=0)


class Discount(TimestampMixin, Base):
    __tablename__ = "discounts"
    code: Mapped[str] = mapped_column(String(32), primary_key=True)
    tenant_id: Mapped[str] = mapped_column(ForeignKey("tenants.id"), index=True)
    percent: Mapped[int] = mapped_column(Integer)
    cart_id: Mapped[str | None] = mapped_column(ForeignKey("carts.id"), nullable=True)  # null = public code
    single_use: Mapped[bool] = mapped_column(Boolean, default=True)
    used: Mapped[bool] = mapped_column(Boolean, default=False)
    issued_by: Mapped[str] = mapped_column(String(16), default="merchant")  # merchant | ai


class Scenario(TimestampMixin, Base):
    """A named set of merchant-editable counterfactual assumptions (see docs/green_logistics.md).

    One 'live' scenario per tenant is created at seed time; its assumptions default to None
    (no numeric estimate shown) until a merchant explicitly sets them via POST /merchant/assumptions.
    """

    __tablename__ = "scenarios"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    tenant_id: Mapped[str] = mapped_column(ForeignKey("tenants.id"), index=True)
    name: Mapped[str] = mapped_column(String(120))
    assumptions: Mapped[dict] = mapped_column(JSON, default=dict)


class Order(TimestampMixin, Base):
    __tablename__ = "orders"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("ord"))
    tenant_id: Mapped[str] = mapped_column(ForeignKey("tenants.id"), index=True)
    cart_id: Mapped[str] = mapped_column(ForeignKey("carts.id"), unique=True)
    idempotency_key: Mapped[str] = mapped_column(String(128), unique=True)
    status: Mapped[str] = mapped_column(String(16), default="placed")  # placed | canceled | refunded
    payment_method: Mapped[str] = mapped_column(String(16))
    cod_confirmed: Mapped[bool] = mapped_column(Boolean, default=False)
    city: Mapped[str] = mapped_column(String(64))
    subtotal_pkr: Mapped[int] = mapped_column(Integer)
    discount_pkr: Mapped[int] = mapped_column(Integer, default=0)
    shipping_pkr: Mapped[int] = mapped_column(Integer, default=0)
    total_pkr: Mapped[int] = mapped_column(Integer)
    discount_code: Mapped[str | None] = mapped_column(String(32), nullable=True)
    via_recovery_link: Mapped[bool] = mapped_column(Boolean, default=False)
    lines: Mapped[list] = mapped_column(JSON, default=list)

    # ---- Green Logistics fulfillment lifecycle (see app/services/fulfillment.py) ----
    # pending_confirmation | hold | ready_to_dispatch | dispatched | delivered | failed_attempt | returned | cancelled
    fulfillment_status: Mapped[str] = mapped_column(String(32), default="ready_to_dispatch", index=True)
    delivery_zone: Mapped[str | None] = mapped_column(String(64), nullable=True)
    address_redacted: Mapped[str | None] = mapped_column(String(120), nullable=True)
    scenario_id: Mapped[str | None] = mapped_column(ForeignKey("scenarios.id"), nullable=True, index=True)
    # Tracked independently of status (which can move on); never used to infer a return was "prevented".
    size_question_resolved: Mapped[bool] = mapped_column(Boolean, default=False)
    # Set exactly once by the corresponding fulfillment transition; never inferred after the fact.
    cod_predispatch_confirmed: Mapped[bool] = mapped_column(Boolean, default=False)
    had_failed_attempt: Mapped[bool] = mapped_column(Boolean, default=False)
    ever_delivered: Mapped[bool] = mapped_column(Boolean, default=False)
    was_held: Mapped[bool] = mapped_column(Boolean, default=False)
    delivery_consolidation_selected: Mapped[bool] = mapped_column(Boolean, default=False)  # P1: always False for now


class AttributionEvent(Base):
    __tablename__ = "attribution_events"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("att"))
    tenant_id: Mapped[str] = mapped_column(ForeignKey("tenants.id"), index=True)
    order_id: Mapped[str] = mapped_column(ForeignKey("orders.id"), unique=True)  # no double counting
    cart_id: Mapped[str] = mapped_column(ForeignKey("carts.id"))
    recovery_attempt_id: Mapped[str] = mapped_column(ForeignKey("recovery_attempts.id"))
    revenue_pkr: Mapped[int] = mapped_column(Integer)
    model: Mapped[str] = mapped_column(String(32), default="last_contact_window")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now_utc)


class AuditEvent(Base):
    """Also serves as the Green Logistics OrderEvent log (order_id/scenario_id/source added for it)."""

    __tablename__ = "audit_events"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("aud"))
    tenant_id: Mapped[str] = mapped_column(String(64), index=True)
    cart_id: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    order_id: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    scenario_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    source: Mapped[str] = mapped_column(String(16), default="simulated")  # simulated | actual
    type: Mapped[str] = mapped_column(String(64), index=True)
    detail: Mapped[dict] = mapped_column(JSON, default=dict)  # PII-redacted
    idempotency_key: Mapped[str | None] = mapped_column(String(160), unique=True, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now_utc, index=True)


class IntegrationConnection(TimestampMixin, Base):
    __tablename__ = "integration_connections"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("int"))
    tenant_id: Mapped[str] = mapped_column(ForeignKey("tenants.id"), index=True)
    provider: Mapped[str] = mapped_column(String(32))  # simulator | shopify | woocommerce | whatsapp
    status: Mapped[str] = mapped_column(String(32))  # connected | not_connected
    detail: Mapped[str] = mapped_column(Text, default="")
    last_test_ok_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    __table_args__ = (UniqueConstraint("tenant_id", "provider"),)
