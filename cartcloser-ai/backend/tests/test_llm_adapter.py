"""LLM adapter with a stubbed Anthropic client (no network, no key): grounding validation + fallbacks."""
from types import SimpleNamespace

import pytest

from app.ai import provider
from tests.conftest import Flow


class FakeMessages:
    def __init__(self, text=None, exc=None, stop="end_turn"):
        self.text, self.exc, self.stop, self.calls = text, exc, stop, []

    def create(self, **kw):
        self.calls.append(kw)
        if self.exc:
            raise self.exc
        return SimpleNamespace(stop_reason=self.stop, content=[SimpleNamespace(type="text", text=self.text)])


def use_fake(monkeypatch, fake):
    r = provider.LlmRephraser.__new__(provider.LlmRephraser)
    r.enabled, r.model = True, "claude-opus-5-5"
    r._client = SimpleNamespace(beta=SimpleNamespace(messages=fake))
    monkeypatch.setattr(provider, "_rephraser", r)
    return r


@pytest.fixture()
def sent(client):
    f = Flow(client)
    f.cart()
    f.checkout()
    f.abandon()
    f.trigger()
    return f


def test_valid_rephrase_is_used_and_marked_llm(monkeypatch, sent):
    fake = FakeMessages("Yes, COD works in Karachi for this order (limit PKR 15,000). Confirm it on your checkout link!")
    use_fake(monkeypatch, fake)
    reply = sent.say("Can I pay COD?")[-1]
    assert reply["source"] == "llm" and "COD works" in reply["text"]
    call = fake.calls[0]
    assert call["model"] == "claude-opus-5-5" and call["fallbacks"] == "default"
    assert "<facts>" in call["messages"][0]["content"]  # grounded facts passed, shopper text delimited


def test_invented_number_falls_back_to_rules(monkeypatch, sent):
    use_fake(monkeypatch, FakeMessages("Yes! COD is available and we'll waive the PKR 200 fee, limit PKR 20,000."))
    reply = sent.say("Can I pay COD?")[-1]
    assert reply["source"] == "rules" and "15,000" in reply["text"]


def test_dropped_no_guarantee_falls_back(monkeypatch, sent):
    use_fake(monkeypatch, FakeMessages("It will arrive Fri 6 Nov for sure."))
    reply = sent.say("Will it arrive in Karachi by Friday?")[-1]
    assert reply["source"] == "rules" and "can't guarantee" in reply["text"]


def test_timeout_and_refusal_fall_back(monkeypatch, sent):
    import anthropic

    use_fake(monkeypatch, FakeMessages(exc=anthropic.APITimeoutError(request=None)))
    assert sent.say("COD?")[-1]["source"] == "rules"
    use_fake(monkeypatch, FakeMessages("x", stop="refusal"))
    assert sent.say("COD?")[-1]["source"] == "rules"


def test_actions_never_delegated_to_llm(monkeypatch, sent):
    fake = FakeMessages("ignored")
    use_fake(monkeypatch, fake)
    assert sent.say("STOP")[-1]["intent"] == "opt_out"
    assert fake.calls == []  # opt-out, handoff and discounts are decided by rules only
