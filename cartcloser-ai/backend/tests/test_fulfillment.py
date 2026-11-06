"""Green Logistics fulfillment state machine, via the HTTP API (MRD section 14 acceptance tests)."""
from tests.conftest import MERCHANT, Flow


def _place_cod_order(client, key="ful-0001"):
    f = Flow(client)
    f.cart()
    f.checkout(opt_in=False, payment="cod")
    r = f.order(key=key, payment="cod", cod_confirmed=True)
    assert r.status_code == 200, r.text
    return f, r.json()


def test_new_cod_order_needs_confirmation_before_dispatch(client):
    f, order = _place_cod_order(client)
    assert order["fulfillment_status"] == "pending_confirmation"
    assert order["cod_predispatch_confirmed"] is False

    # Acceptance test: cannot dispatch while confirmation is pending.
    r = client.post(f"/orders/{order['id']}/dispatch", headers=MERCHANT)
    assert r.status_code == 409 and r.json()["error"] == "illegal_transition"


def test_confirm_then_dispatch_then_deliver(client):
    f, order = _place_cod_order(client)
    oid = order["id"]

    r = client.post(f"/orders/{oid}/confirm-cod", json={"confirmed": True}, headers=MERCHANT)
    assert r.status_code == 200 and r.json()["fulfillment_status"] == "ready_to_dispatch"
    assert r.json()["cod_predispatch_confirmed"] is True

    r = client.post(f"/orders/{oid}/dispatch", headers=MERCHANT)
    assert r.status_code == 200 and r.json()["fulfillment_status"] == "dispatched"

    r = client.post(f"/orders/{oid}/delivered", headers=MERCHANT)
    assert r.status_code == 200 and r.json()["fulfillment_status"] == "delivered"
    assert r.json()["ever_delivered"] is True


def test_rejecting_confirmation_holds_not_cancels_by_default(client):
    f, order = _place_cod_order(client)
    oid = order["id"]
    r = client.post(f"/orders/{oid}/confirm-cod", json={"confirmed": False}, headers=MERCHANT)
    assert r.status_code == 200
    assert r.json()["fulfillment_status"] == "hold"
    assert r.json()["cod_predispatch_confirmed"] is False  # never auto-marked confirmed


def test_address_correction_then_merchant_release(client):
    f, order = _place_cod_order(client)
    oid = order["id"]
    client.post(f"/orders/{oid}/confirm-cod", json={"confirmed": False}, headers=MERCHANT)

    r = client.post(f"/orders/{oid}/correct-address", json={"address_redacted": "House 12, Block 3", "delivery_zone": "Karachi"}, headers=MERCHANT)
    assert r.status_code == 200
    assert r.json()["delivery_zone"] == "Karachi" and r.json()["address_redacted"] == "House 12, Block 3"
    assert r.json()["fulfillment_status"] == "hold"  # correction does not auto-release

    r = client.post(f"/orders/{oid}/release", headers=MERCHANT)
    assert r.status_code == 200 and r.json()["fulfillment_status"] == "ready_to_dispatch"

    events = client.get("/merchant/events", params={"order_id": oid}, headers=MERCHANT).json()["items"]
    assert any(e["type"] == "address_corrected" for e in events)


def test_duplicate_confirmation_does_not_double_count(client):
    f, order = _place_cod_order(client)
    oid = order["id"]
    client.post(f"/orders/{oid}/confirm-cod", json={"confirmed": True}, headers=MERCHANT)
    m1 = f.metrics()["green"]["counts"]["cod_confirmed"]
    r = client.post(f"/orders/{oid}/confirm-cod", json={"confirmed": True}, headers=MERCHANT)
    assert r.status_code == 409 and r.json()["error"] == "illegal_transition"
    m2 = f.metrics()["green"]["counts"]["cod_confirmed"]
    assert m1 == m2 == 1


def test_returns_and_failed_attempts_are_distinct(client):
    f1, o1 = _place_cod_order(client, key="ful-fail")
    client.post(f"/orders/{o1['id']}/confirm-cod", json={"confirmed": True}, headers=MERCHANT)
    client.post(f"/orders/{o1['id']}/dispatch", headers=MERCHANT)
    r = client.post(f"/orders/{o1['id']}/failed-attempt", json={"reason": "no answer"}, headers=MERCHANT)
    assert r.status_code == 200 and r.json()["fulfillment_status"] == "failed_attempt"

    f2, o2 = _place_cod_order(client, key="ful-return")
    client.post(f"/orders/{o2['id']}/confirm-cod", json={"confirmed": True}, headers=MERCHANT)
    client.post(f"/orders/{o2['id']}/dispatch", headers=MERCHANT)
    client.post(f"/orders/{o2['id']}/delivered", headers=MERCHANT)
    r = client.post(f"/orders/{o2['id']}/returned", json={"reason": "wrong size"}, headers=MERCHANT)
    assert r.status_code == 200 and r.json()["fulfillment_status"] == "returned"

    g = f1.metrics()["green"]
    assert g["counts"]["failed_attempt"] == 1
    assert g["counts"]["returned"] == 1
    assert g["rates"]["failed_delivery_rate"]["numerator"] == 1
    assert g["rates"]["return_rate"]["numerator"] == 1


def test_online_demo_orders_skip_cod_confirmation(client):
    f = Flow(client)
    f.cart()
    f.checkout(opt_in=False, payment="online_demo")
    r = f.order(key="ful-online", payment="online_demo", cod_confirmed=False)
    assert r.status_code == 200, r.text
    assert r.json()["fulfillment_status"] == "ready_to_dispatch"


def test_illustrative_estimate_requires_explicit_assumption_and_never_moves_observed_counts(client):
    f, order = _place_cod_order(client)
    client.post(f"/orders/{order['id']}/confirm-cod", json={"confirmed": False}, headers=MERCHANT)  # -> hold

    g = f.metrics()["green"]
    assert g["counts"]["held_or_cancelled"] == 1
    assert g["estimates"]["estimated_avoided_attempts"] is None  # no assumption set yet

    r = client.post("/merchant/assumptions", json={"assumed_failure_probability_without_intervention": 0.4}, headers=MERCHANT)
    assert r.status_code == 200

    g2 = f.metrics()["green"]
    assert g2["estimates"]["estimated_avoided_attempts"] == 0.4  # 1 held order x 0.4
    assert g2["counts"]["held_or_cancelled"] == 1  # observed count unchanged by the assumption


def test_size_question_tracked_on_order(client):
    f = Flow(client)
    f.cart()
    f.say("What size should I get?")
    f.checkout(opt_in=False, payment="cod")
    r = f.order(key="ful-size", payment="cod", cod_confirmed=True)
    assert r.status_code == 200, r.text
    assert r.json()["size_question_resolved"] is True


def test_order_tabs_match_mrd_tab_list(client):
    """GET /merchant/orders?fulfillment_status= backs the 7 required merchant tabs."""
    f, order = _place_cod_order(client)
    for status in ("pending_confirmation", "ready_to_dispatch", "hold", "cancelled", "delivered", "returned", "failed_attempt"):
        r = client.get("/merchant/orders", params={"fulfillment_status": status}, headers=MERCHANT)
        assert r.status_code == 200
    r = client.get("/merchant/orders", params={"fulfillment_status": "pending_confirmation"}, headers=MERCHANT)
    assert r.json()["total"] == 1 and r.json()["items"][0]["id"] == order["id"]
