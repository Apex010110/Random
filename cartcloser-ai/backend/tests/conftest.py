import os

os.environ["DATABASE_URL"] = os.environ.get("TEST_DATABASE_URL", "sqlite://")
os.environ.setdefault("APP_ENV", "demo")
os.environ["AI_PROVIDER"] = "rules"
os.environ["ANTHROPIC_API_KEY"] = ""
os.environ["SHOPIFY_WEBHOOK_SECRET"] = "test-shopify-secret"
os.environ["WOOCOMMERCE_WEBHOOK_SECRET"] = ""

from datetime import datetime, timezone  # noqa: E402

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.main import create_app  # noqa: E402
from app.services.support import Clock  # noqa: E402

# Wednesday 4 Nov 2026, 12:00 PKT (07:00 UTC): outside quiet hours.
NOON_PKT = datetime(2026, 11, 4, 7, 0, tzinfo=timezone.utc)
MERCHANT = {"Authorization": "Bearer demo-merchant-token"}
OTHER_MERCHANT = {"Authorization": "Bearer other-tenant-token"}


def shopper(sid="shp_ayesha"):
    return {"X-Shopper-Id": sid}


@pytest.fixture()
def client():
    Clock.set(NOON_PKT)
    app = create_app(run_scheduler=False)
    with TestClient(app) as c:
        c.post("/demo/reset")
        yield c
    Clock.set(None)


class Flow:
    """Helper that walks the shopper journey through the public API."""

    def __init__(self, c, sid="shp_ayesha"):
        self.c, self.h = c, shopper(sid)
        self.cart_id = None

    def cart(self, items=None):
        items = items or [{"product_id": "p_linen_kurta", "size": "M", "quantity": 1}]
        r = self.c.post("/carts", json={"items": items}, headers=self.h)
        assert r.status_code == 201, r.text
        self.cart_id = r.json()["id"]
        return r.json()

    def checkout(self, opt_in=True, city="Karachi", payment="cod"):
        r = self.c.post(f"/carts/{self.cart_id}/checkout-started", json={"city": city, "payment_method": payment, "whatsapp_opt_in": opt_in}, headers=self.h)
        assert r.status_code == 200, r.text
        return r.json()

    def abandon(self, key=None):
        r = self.c.post(f"/carts/{self.cart_id}/abandon", json={"idempotency_key": key}, headers=self.h)
        assert r.status_code == 200, r.text
        return r.json()

    def trigger(self):
        return self.c.post(f"/recovery/{self.cart_id}/trigger-demo", headers=MERCHANT)

    def say(self, text, key=None):
        r = self.c.post(f"/conversations/{self.cart_id}/messages", json={"text": text, "idempotency_key": key}, headers=self.h)
        assert r.status_code == 200, r.text
        return r.json()

    def conversation(self):
        return self.c.get(f"/conversations/{self.cart_id}", headers=self.h).json()

    def order(self, key="order-key-0001", payment="cod", cod_confirmed=True, token=None):
        body = {"cart_id": self.cart_id, "payment_method": payment, "cod_confirmed": cod_confirmed, "idempotency_key": key}
        if token:
            body["recovery_token"] = token
        return self.c.post("/orders", json=body, headers=self.h)

    def metrics(self):
        return self.c.get("/merchant/metrics", headers=MERCHANT).json()
