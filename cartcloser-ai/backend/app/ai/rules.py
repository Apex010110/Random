"""Deterministic, grounded assistant.

Pure functions: no DB, no network. Every fact in a reply comes from the catalog/policy context.
The Dart offline engine (flutter_app/lib/core/engine/assistant_rules.dart) mirrors this logic and
reads the same seed/assistant_copy.json, so both answer identically.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path

from app.seed_paths import ASSISTANT_COPY_PATH

COPY: dict = json.loads(Path(ASSISTANT_COPY_PATH).read_text(encoding="utf-8"))

URDU_RE = re.compile(r"[؀-ۿ]")
WORD_RE = re.compile(r"[a-z0-9%]+")
MAX_INPUT_CHARS = 500


@dataclass
class Line:
    product_id: str
    name: str
    size: str
    quantity: int
    unit_price_pkr: int
    cod_eligible: bool


@dataclass
class AssistantContext:
    store_name: str
    first_name: str
    city: str
    lines: list[Line]
    subtotal_pkr: int
    policy: dict
    settings: dict
    catalog: list[dict]  # [{id,name,category,price_pkr,cod_eligible,fit_notes,variants:[{size,stock}]}]
    now_local: datetime
    existing_discount: tuple[str, int] | None = None  # (code, pct)
    candidate_code: str = "CC-0000"


@dataclass
class Reply:
    text: str
    intent: str
    confidence: float
    language: str
    action: str | None = None  # opt_out | handoff | issue_discount | None
    meta: dict = field(default_factory=dict)


# ------------------------------------------------------------------ helpers
def sanitize(text: str) -> str:
    text = text.replace("\x00", "")
    text = re.sub(r"[\u200b-\u200f\u202a-\u202e]", "", text)  # zero-width / bidi overrides
    return text.strip()[:MAX_INPUT_CHARS]


def detect_language(text: str) -> str:
    if URDU_RE.search(text):
        return "ur"
    words = WORD_RE.findall(text.lower())
    strong = sum(1 for w in words if w in COPY["roman_markers_strong"])
    weak = sum(1 for w in words if w in COPY["roman_markers_weak"])
    if strong >= 1 or weak >= 3:
        return "roman"
    return "en"


def _matches(spec: dict, low: str, words: set[str]) -> bool:
    if any(w in words for w in spec["words"]):
        return True
    return any(p in low for p in spec["phrases"])


def detect_intents(text: str) -> list[str]:
    low = text.lower()
    words = set(WORD_RE.findall(low))
    found = [name for name in COPY["intent_priority"] if _matches(COPY["intents"][name], low, words)]
    return found


def is_injection(text: str) -> bool:
    low = text.lower()
    return any(p in low for p in COPY["injection_patterns"])


def t(lang: str, key: str, **kw) -> str:
    template = COPY["replies"][lang][key]
    return template.format(**kw)


def fmt_date(d: date, lang: str) -> str:
    disp = COPY["display"][lang]
    return f"{disp['weekdays'][d.weekday()]} {d.day} {disp['months'][d.month - 1]}"


def add_business_days(start: date, n: int) -> date:
    """Business days are Monday-Saturday (Sunday is off) in the demo policy."""
    d = start
    added = 0
    while added < n:
        d += timedelta(days=1)
        if d.weekday() != 6:
            added += 1
    return d


def delivery_window(policy: dict, city: str, today: date) -> tuple[date, date, int, int, bool]:
    windows = policy["delivery_windows"]
    known = city in windows
    lo, hi = windows.get(city, windows["default"])
    return add_business_days(today, lo), add_business_days(today, hi), lo, hi, known


def detect_target_day(text: str, today: date) -> date | None:
    low = text.lower()
    words = set(WORD_RE.findall(low))
    wd = COPY["weekdays"]
    for idx in range(7):
        if wd["en"][idx] in words or wd["en_short"][idx] in words or wd["roman"][idx] in words or wd["ur"][idx] in text:
            delta = (idx - today.weekday()) % 7
            return today + timedelta(days=delta)
    if any(w in words for w in COPY["tomorrow_words"][:2]) or COPY["tomorrow_words"][2] in text.split():
        return today + timedelta(days=1)
    return None


def detect_city(text: str) -> str | None:
    low = text.lower()
    for alias, city in COPY["city_aliases"].items():
        if URDU_RE.search(alias):
            if alias in text:
                return city
        elif re.search(rf"\b{re.escape(alias)}\b", low):
            return city
    return None


def detect_size(text: str) -> str | None:
    low = text.lower().replace("'", "")
    words = WORD_RE.findall(low)
    for w in words:
        if w in ("xl", "small", "medium", "large"):
            return COPY["size_aliases"][w]
    m = re.search(r"\b(?:size|in)\s+(xl|s|m|l)\b", low)
    if m:
        return COPY["size_aliases"][m.group(1)]
    for w in words:  # bare size letters ("Is L available?"); apostrophes already stripped
        if w in ("s", "m", "l"):
            return COPY["size_aliases"][w]
    m2 = re.search(r"\bsize\s+(\d{1,2})\b", low)
    if m2:
        return m2.group(1)
    return None


def detect_percent(text: str) -> int | None:
    m = re.search(r"(\d{1,2})\s*%|(\d{1,2})\s*percent", text.lower())
    if m:
        return int(m.group(1) or m.group(2))
    return None


def mentioned_product(text: str, catalog: list[dict]) -> dict | None:
    low = text.lower()
    keywords = {
        "kurta": "p_linen_kurta", "linen": "p_linen_kurta", "kameez": "p_kameez_navy", "shalwar": "p_kameez_navy",
        "lawn": "p_lawn_suit", "suit": "p_lawn_suit", "waistcoat": "p_waistcoat", "dupatta": "p_dupatta",
        "chappal": "p_chappal", "bag": "p_crossbody", "crossbody": "p_crossbody", "denim": "p_denim_shirt",
        "shirt": "p_denim_shirt", "jhumka": "p_jhumka", "earrings": "p_jhumka", "sherwani": "p_sherwani",
        "کرتا": "p_linen_kurta", "دوپٹہ": "p_dupatta",
    }
    by_id = {p["id"]: p for p in catalog}
    for kw, pid in keywords.items():
        if (kw in text if URDU_RE.search(kw) else re.search(rf"\b{kw}\b", low)) and pid in by_id:
            return by_id[pid]
    return None


def in_stock_sizes(product: dict) -> list[str]:
    return [v["size"] for v in product["variants"] if v["stock"] > 0]


def alternative_for(product: dict, catalog: list[dict]) -> dict | None:
    same = [p for p in catalog if p["id"] != product["id"] and p["category"] == product["category"] and in_stock_sizes(p)]
    pool = same or [p for p in catalog if p["id"] != product["id"] and in_stock_sizes(p)]
    if not pool:
        return None
    return min(pool, key=lambda p: abs(p["price_pkr"] - product["price_pkr"]))


def shipping_fee(policy: dict, city: str, subtotal: int) -> int:
    if subtotal >= policy["free_shipping_threshold_pkr"]:
        return 0
    fees = policy["shipping_fees"]
    return fees.get(city, fees["default"])


def cod_check(policy: dict, city: str, lines: list[Line], total: int) -> str:
    """Returns cod_yes | cod_no_product | cod_no_city | cod_over_limit."""
    if any(not ln.cod_eligible for ln in lines):
        return "cod_no_product"
    if city not in policy["cod_cities"]:
        return "cod_no_city"
    if total > policy["cod_max_order_pkr"]:
        return "cod_over_limit"
    return "cod_yes"


def city_label(city: str, lang: str) -> str:
    return COPY["display"][lang].get("cities", {}).get(city, city)


def money(n: int) -> str:
    return f"{n:,}"


# ------------------------------------------------------------------ main entry
def answer(raw_text: str, ctx: AssistantContext) -> Reply:
    text = sanitize(raw_text)
    lang = detect_language(text)
    store = ctx.store_name
    link_meta = {"checkout_link": True, "link_label": COPY["replies"][lang]["link_label"]}

    intents = detect_intents(text)
    # STOP always wins, even inside an injection attempt.
    if "opt_out" in intents:
        return Reply(t(lang, "opt_out", store=store), "opt_out", 0.99, lang, action="opt_out")
    if is_injection(text):
        return Reply(t(lang, "injection"), "injection_blocked", 0.95, lang)
    if not intents:
        return Reply(t(lang, "unknown", store=store), "unknown", 0.2, lang, action="handoff")

    intent = intents[0]
    conf = 0.92 if len(intents) == 1 else 0.85
    city = detect_city(text) or ctx.city
    cityl = city_label(city, lang)
    today = ctx.now_local.date()
    product = mentioned_product(text, ctx.catalog)
    if product is None and ctx.lines:
        product = next((p for p in ctx.catalog if p["id"] == ctx.lines[0].product_id), None)

    if intent == "human":
        return Reply(t(lang, "human", store=store), "human", 0.95, lang, action="handoff")

    if intent == "discount":
        ceiling = int(ctx.settings.get("discount_ceiling_pct", 0)) if ctx.settings.get("discount_enabled") else 0
        if ctx.existing_discount:
            code, pct = ctx.existing_discount
            return Reply(t(lang, "discount_existing", code=code, pct=pct), "discount", conf, lang, meta=link_meta)
        if ceiling <= 0 or not ctx.lines:
            return Reply(t(lang, "discount_none"), "discount", conf, lang)
        req = detect_percent(text)
        parts = []
        if req is not None and req > ceiling:
            parts.append(t(lang, "discount_capped", req=req, pct=ceiling))
        pct = min(req, ceiling) if req else ceiling
        parts.append(t(lang, "discount_issued", pct=pct, code=ctx.candidate_code))
        return Reply(" ".join(parts), "discount", conf, lang, action="issue_discount",
                     meta={**link_meta, "discount_code": ctx.candidate_code, "discount_pct": pct})

    if intent == "cod":
        ship = shipping_fee(ctx.policy, city, ctx.subtotal_pkr)
        key = cod_check(ctx.policy, city, ctx.lines, ctx.subtotal_pkr + ship)
        items = ", ".join(ln.name for ln in ctx.lines if not ln.cod_eligible) or (product["name"] if product else "")
        msg = t(lang, key, city=cityl, max=money(ctx.policy["cod_max_order_pkr"]), items=items,
                total=money(ctx.subtotal_pkr + ship))
        return Reply(msg, "cod", conf, lang, meta={**link_meta, "cod_result": key})

    if intent == "shipping_fee":
        fees = ctx.policy["shipping_fees"]
        fee = fees.get(city, fees["default"])
        current = shipping_fee(ctx.policy, city, ctx.subtotal_pkr)
        cur = t(lang, "shipping_free") if current == 0 else f"PKR {money(current)}"
        msg = t(lang, "shipping_fee", city=cityl, fee=money(fee), threshold=money(ctx.policy["free_shipping_threshold_pkr"]),
                subtotal=money(ctx.subtotal_pkr), current=cur)
        return Reply(msg, "shipping_fee", conf, lang, meta=link_meta)

    if intent == "delivery":
        start, end, lo, hi, known = delivery_window(ctx.policy, city, today)
        target = detect_target_day(text, today)
        parts = []
        if target is not None:
            tname = COPY["display"][lang]["weekdays_long"][target.weekday()]
            parts.append(t(lang, "delivery_no_guarantee", target=tname))
        if not known:
            parts.append(t(lang, "delivery_default_city", city=cityl))
        parts.append(t(lang, "delivery_window", city=cityl, start=fmt_date(start, lang), end=fmt_date(end, lang), min=lo, max=hi))
        if target is not None:
            tname = COPY["display"][lang]["weekdays_long"][target.weekday()]
            if end <= target:
                parts.append(t(lang, "delivery_before", target=tname))
            elif start <= target:
                parts.append(t(lang, "delivery_possible", target=tname))
            else:
                parts.append(t(lang, "delivery_after", target=tname))
        meta = {**link_meta, "window_start": start.isoformat(), "window_end": end.isoformat(), "guaranteed": False}
        return Reply(" ".join(parts), "delivery", conf, lang, meta=meta)

    if intent == "returns":
        msg = t(lang, "returns", exchange=ctx.policy["exchange_policy"], returns=ctx.policy["returns_policy"])
        return Reply(msg, "returns", conf, lang)

    if intent in ("size", "stock"):
        if product is None:
            return Reply(t(lang, "unknown", store=store), "unknown", 0.3, lang, action="handoff")
        sizes = in_stock_sizes(product)
        size = detect_size(text)
        if not sizes:
            alt = alternative_for(product, ctx.catalog)
            if alt:
                msg = t(lang, "stock_out_all", product=product["name"], alt=alt["name"], alt_price=money(alt["price_pkr"]))
                return Reply(msg, "stock", conf, lang, meta={"alternative_product_id": alt["id"]})
            return Reply(t(lang, "stock_out_no_alt", product=product["name"]), "stock", conf, lang)
        size_list = ", ".join(sizes)
        if intent == "size":
            msg = t(lang, "size_info", product=product["name"], fit=product["fit_notes"], sizes=size_list)
            if size:
                msg += " " + t(lang, "size_requested_ok" if size in sizes else "size_requested_out", size=size)
            return Reply(msg, "size", conf, lang, meta=link_meta)
        if size and size in [v["size"] for v in product["variants"]]:
            if size in sizes:
                return Reply(t(lang, "stock_ok", product=product["name"], size=size), "stock", conf, lang, meta=link_meta)
            return Reply(t(lang, "stock_out_size", product=product["name"], size=size, sizes=size_list), "stock", conf, lang)
        return Reply(t(lang, "stock_sizes", product=product["name"], sizes=size_list), "stock", conf, lang, meta=link_meta)

    if intent == "checkout_link":
        return Reply(t(lang, "checkout_link"), "checkout_link", conf, lang, meta=link_meta)
    if intent == "thanks":
        return Reply(t(lang, "thanks"), "thanks", conf, lang)
    return Reply(t(lang, "greeting", first_name=ctx.first_name), "greeting", conf, lang)
