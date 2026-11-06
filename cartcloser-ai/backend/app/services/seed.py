"""Demo reset + seed from the shared seed/demo_seed.json."""
from __future__ import annotations

import json
from pathlib import Path

from sqlalchemy.orm import Session

from app.config import get_settings
from app.db.session import Base
from app.models.entities import (
    Discount,
    IntegrationConnection,
    Inventory,
    MerchantUser,
    Product,
    ProductVariant,
    Scenario,
    Shopper,
    StorePolicy,
    Tenant,
)
from app.seed_paths import DEMO_SEED_PATH
from app.services.support import ChangeFeed, audit

SEED: dict = json.loads(Path(DEMO_SEED_PATH).read_text(encoding="utf-8"))
DEMO_TENANT = SEED["tenant"]["id"]


def wipe(db: Session) -> None:
    for table in reversed(Base.metadata.sorted_tables):
        db.execute(table.delete())


def seed(db: Session) -> None:
    s = get_settings()
    for t, token, email in ((SEED["tenant"], s.demo_merchant_token, "owner@urbanthread.example"),
                            (SEED["other_tenant"], s.demo_other_tenant_token, "owner@other.example")):
        db.add(Tenant(id=t["id"], name=t["name"], currency=t["currency"], is_demo=True, settings=dict(SEED["settings"])))
        db.flush()
        db.add(Scenario(id=f"{t['id']}:live", tenant_id=t["id"], name="Live demo", assumptions={
            "assumed_failure_probability_without_intervention": None,
            "assumed_km_per_avoided_attempt": None,
            "assumed_kgco2e_per_km": None,
            "assumed_packaging_units_per_repack_event": None,
        }))
        db.add(MerchantUser(tenant_id=t["id"], email=email, api_token=token))
        db.add(StorePolicy(tenant_id=t["id"], **SEED["policy"]))
        for provider, status, detail in (
            ("simulator", "connected", "Built-in WhatsApp-style simulator (no real messages are sent)."),
            ("shopify", "not_connected", "Not connected. Needs app install, OAuth and webhook secret."),
            ("woocommerce", "not_connected", "Not connected. Needs REST keys and webhook secret."),
            ("whatsapp", "not_connected", "Not connected. Needs WhatsApp Business Platform verification, approved templates and credentials."),
        ):
            db.add(IntegrationConnection(tenant_id=t["id"], provider=provider, status=status, detail=detail))

    t_id = DEMO_TENANT
    for p in SEED["products"]:
        prod = Product(id=p["id"], tenant_id=t_id, name=p["name"], category=p["category"], description=p["description"],
                       fit_notes=p["fit_notes"], price_pkr=p["price_pkr"], cod_eligible=p["cod_eligible"],
                       image_key=p["image_key"], color_hex=p["color_hex"])
        for i, (size, stock) in enumerate(p["variants"]):
            v = ProductVariant(id=f"{p['id']}__{size.replace(' ', '_').lower()}", size=size, position=i)
            v.inventory = Inventory(on_hand=stock)
            prod.variants.append(v)
        db.add(prod)
    # One product in the other tenant to prove isolation.
    other = Product(id="p_other_tee", tenant_id=SEED["other_tenant"]["id"], name="Other Store Tee", category="Men",
                    description="Isolation test product.", price_pkr=999, image_key="shirt")
    v = ProductVariant(id="p_other_tee__m", size="M", position=0)
    v.inventory = Inventory(on_hand=5)
    other.variants.append(v)
    db.add(other)

    for sh in SEED["personas"]:
        db.add(Shopper(id=sh["id"], tenant_id=t_id, first_name=sh["first_name"], phone_masked=sh["phone_masked"],
                       city=sh["city"], age_band=sh["age_band"]))
    for d in SEED["discount_codes"]:
        db.add(Discount(code=d["code"], tenant_id=t_id, percent=d["percent"], single_use=d["single_use"], issued_by="merchant"))
    audit(db, t_id, "demo_seeded")


def reset_and_seed(db: Session) -> None:
    wipe(db)
    db.flush()
    seed(db)
    db.commit()
    ChangeFeed.bump()
