"""End-to-end scenarios A-H from the MRD, via the HTTP API."""
from tests.conftest import MERCHANT, Flow


def test_a_opted_in_recovery_counts(client):
    f = Flow(client)
    f.cart()
    f.checkout(opt_in=True)
    cart = f.abandon()
    assert cart["status"] == "scheduled"
    assert f.metrics()["counts"]["eligible_abandoned"] == 1

    r = f.trigger()
    assert r.status_code == 200 and r.json()["status"] == "sent", r.text
    conv = f.conversation()
    assert conv["channel"] == "whatsapp_sim"
    assert "Reply STOP" in conv["messages"][0]["text"]

    reply = f.say("Will it arrive in Karachi by Friday?")[-1]
    assert reply["intent"] == "delivery"
    assert "can't guarantee Friday" in reply["text"]
    assert reply["meta"]["guaranteed"] is False

    reply = f.say("Can I pay COD?")[-1]
    assert reply["intent"] == "cod" and reply["meta"]["cod_result"] == "cod_yes"
    token = reply["meta"]["token"]

    # opening the link and replying are NOT recovery
    assert f.metrics()["counts"]["recovered"] == 0
    r = client.get(f"/r/{f.cart_id}", params={"t": token})
    assert r.status_code == 200
    assert f.metrics()["counts"]["recovered"] == 0

    r = f.order(token=token)
    assert r.status_code == 200, r.text
    order = r.json()
    assert order["attributed"] and order["via_recovery_link"] and order["cod_confirmed"]
    assert order["total_pkr"] == 4490 + 200

    m = f.metrics()
    assert m["counts"]["recovered"] == 1 and m["counts"]["contacted"] == 1 and m["counts"]["replied"] == 1
    assert m["money"]["attributed_recovered_sales_pkr"] == 4690
    assert m["rates"]["observed_recovery_rate"] == {"numerator": 1, "denominator": 1, "value": 1.0}
    assert m["incremental_lift"]["measured"] is False


def test_b_no_opt_in_no_outbound_but_onsite_chat_works(client):
    f = Flow(client)
    f.cart()
    f.checkout(opt_in=False)
    cart = f.abandon()
    assert cart["status"] == "not_eligible" and cart["status_reason"] == "no_consent"
    r = f.trigger()
    assert r.status_code == 409
    assert f.conversation()["messages"] == []
    # shopper-initiated on-site chat still works
    reply = f.say("Is COD available?")[-1]
    assert reply["intent"] == "cod"
    assert f.conversation()["channel"] == "onsite_chat"
    m = f.metrics()
    assert m["counts"]["contacted"] == 0 and m["blocked_reasons"].get("no_consent") == 1


def test_c_stop_blocks_future_sends(client):
    f = Flow(client)
    f.cart()
    f.checkout(opt_in=True)
    f.abandon()
    assert f.trigger().json()["status"] == "sent"
    reply = f.say("STOP")[-1]
    assert reply["intent"] == "opt_out"
    assert client.get("/consents/me", headers=f.h).json()["opted_in"] is False
    # a new cart from the same shopper cannot be contacted
    g = Flow(client)
    g.cart([{"product_id": "p_waistcoat", "size": "M", "quantity": 1}])
    g.checkout(opt_in=False)
    assert g.abandon()["status_reason"] == "opted_out"
    assert g.trigger().status_code == 409
    assert f.metrics()["counts"]["opt_outs"] == 1


def test_c2_revoke_before_send_cancels_at_send_time(client):
    f = Flow(client)
    f.cart()
    f.checkout(opt_in=True)
    f.abandon()
    client.post("/consents/revoke", json={"shopper_id": "shp_ayesha"}, headers=f.h)
    assert f.trigger().status_code == 409
    assert f.conversation()["messages"] == []


def test_d_out_of_stock_no_fabrication(client):
    f = Flow(client)
    f.cart()
    f.checkout()
    f.abandon()
    f.trigger()
    reply = f.say("Is the dupatta in stock?")[-1]
    assert "out of stock" in reply["text"] and "can't promise a restock" in reply["text"]
    assert reply["meta"].get("alternative_product_id")
    reply = f.say("Is L available?")[-1]
    assert "L is out of stock" in reply["text"] or "in L is out of stock" in reply["text"]
    # cannot buy an out-of-stock item
    r = client.post("/carts", json={"items": [{"product_id": "p_dupatta", "size": "One size", "quantity": 1}]}, headers=f.h)
    assert r.status_code == 409 and r.json()["error"] == "insufficient_stock"


def test_e_teen_safeguard_blocks_outbound(client):
    f = Flow(client, "shp_zara")
    f.cart()
    f.checkout(opt_in=True, city="Islamabad")
    cart = f.abandon()
    assert cart["status"] == "not_eligible" and cart["status_reason"] == "under_18_safeguard"
    assert f.trigger().status_code == 409
    assert f.conversation()["messages"] == []


def test_f_purchase_before_send_cancels(client):
    f = Flow(client)
    f.cart()
    f.checkout(opt_in=True)
    assert f.abandon()["status"] == "scheduled"
    r = f.order()
    assert r.status_code == 200 and r.json()["attributed"] is False
    cart = client.get(f"/carts/{f.cart_id}", headers=f.h).json()
    assert cart["status"] == "ordered"
    assert cart["recovery_attempts"][0]["status"] == "cancelled"
    assert cart["recovery_attempts"][0]["reason"] == "already_purchased"
    assert client.post("/demo/tick").json()["delivered"] == 0
    m = f.metrics()
    assert m["counts"]["recovered"] == 0 and m["money"]["attributed_recovered_sales_pkr"] == 0


def test_g_human_handoff(client):
    f = Flow(client)
    f.cart()
    f.checkout()
    f.abandon()
    f.trigger()
    reply = f.say("Can you embroider my name on the sleeve?")[-1]
    assert reply["intent"] == "unknown" and reply["confidence"] < 0.5
    detail = client.get(f"/merchant/carts/{f.cart_id}", headers=MERCHANT).json()
    assert detail["status"] == "human_handoff" and detail["conversation"]["escalated"] is True
    client.post(f"/merchant/conversations/{f.cart_id}/reply", json={"text": "Hi Ayesha, yes for PKR 300 extra."}, headers=MERCHANT)
    msgs = f.say("Great, thanks")
    assert len(msgs) == 1  # human took over: no AI reply
    assert f.conversation()["human_takeover"] is True


def test_h_duplicate_events_no_duplicates(client):
    f = Flow(client)
    f.cart()
    f.checkout()
    f.abandon("evt-1")
    f.abandon("evt-1")
    f.abandon("evt-1")
    cart = client.get(f"/carts/{f.cart_id}", headers=f.h).json()
    assert len(cart["recovery_attempts"]) == 1
    assert f.trigger().json()["status"] == "sent"
    assert f.trigger().status_code == 409  # contact cap: no second message
    assert client.post("/demo/tick").json()["delivered"] == 0
    assert len([m for m in f.conversation()["messages"] if m["intent"] == "recovery_template"]) == 1
    f.say("COD?", key="m1")
    f.say("COD?", key="m1")
    assert len([m for m in f.conversation()["messages"] if m["role"] == "shopper"]) == 1
    a = f.order(key="dup-order-1")
    b = f.order(key="dup-order-1")
    assert a.status_code == b.status_code == 200 and a.json()["id"] == b.json()["id"]
    c = f.order(key="dup-order-2")
    assert c.status_code == 409
    assert f.metrics()["counts"]["recovered"] == 1


def test_scheduler_sends_after_delay(client):
    from datetime import timedelta

    from app.services.support import Clock

    f = Flow(client)
    f.cart()
    f.checkout()
    f.abandon()
    assert client.post("/demo/tick").json()["delivered"] == 0
    Clock.set(Clock.now() + timedelta(minutes=21))
    assert client.post("/demo/tick").json()["delivered"] == 1
    assert client.get(f"/carts/{f.cart_id}", headers=f.h).json()["status"] == "message_sent"
