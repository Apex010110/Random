# Security, privacy and safety

| Area | What is implemented | Status |
|---|---|---|
| Consent | Separate, unchecked, optional checkbox; versioned consent text; record stores version, text, channel, purpose, source, timestamp; revocable; STOP revokes immediately | Implemented + tested (both engines) |
| No send without consent | Eligibility re-checked at send time; blocked reasons logged and counted | Implemented + tested (scenarios B, C, E) |
| Under-18 | Persona with `age_band=under_18` is never sent outbound promotional recovery; under-13s are not targeted; age is only stored when already known | Implemented + tested (scenario E) |
| Grounded AI | Rules engine answers only from catalog/policy; never guarantees delivery; never invents stock, prices or codes; discounts capped by merchant ceiling, single-use, cart-bound | Implemented + tested |
| Prompt injection | Injection phrases are refused; LLM gets shopper text inside `<shopper_message>` delimiters, instructed to treat it as data; LLM may only rephrase; output validated (numbers ⊆ facts, no-guarantee kept, no Devanagari) | Implemented + tested with stubbed client |
| Secrets | API keys, webhook secrets and link-signing secret live only in backend env (`.env`, never committed). Flutter client contains **no secrets** (merchant demo token is a public demo value) | Implemented |
| Tenant isolation | Merchant bearer token → one tenant; all merchant queries filter by tenant; cross-tenant access returns 404 | Implemented + tested |
| Shopper isolation | Carts/chats/orders scoped to `X-Shopper-Id`; recovery links use HMAC-SHA256 signed tokens | Implemented + tested |
| Webhooks | HMAC-SHA256 (base64) verified before processing; de-duplicated by delivery id; 503 when no secret configured | Implemented (stub: payload mapping not built) |
| Idempotency | Cart creation, abandonment, messages, orders, sends | Implemented + tested (scenario H) |
| PII minimisation | Only masked phone numbers stored in the demo; audit log never stores message bodies and redacts phone numbers | Implemented + tested |
| Data rights | Merchant export (JSON) and per-shopper deletion (carts, chats, consents; orders kept anonymised) | Implemented |
| Payment data | None collected or stored ("Online payment (demo)" only) | By design |
| Validation | Pydantic schemas with ranges/lengths; `extra=forbid` on settings; uniform error JSON | Implemented + tested |

## Not production-ready (must be done before real merchants)
- **Auth**: demo bearer tokens are static. Replace with real merchant accounts (OAuth/OIDC or Shopify session tokens), rotate secrets, scope tokens.
- **Shopper identity**: `X-Shopper-Id` is a demo convenience; production must derive identity from the platform checkout and signed sessions.
- **Rate limiting, WAF, monitoring, queue workers** for sends (the demo scheduler is an in-process loop).
- **WhatsApp Business Platform**: not integrated. Requires Meta business verification, approved templates, opt-in proof per Meta policy, 24-hour window rules and local privacy-law review (e.g. Pakistan's draft Personal Data Protection Bill). No unofficial WhatsApp automation is used or planned.
- **Guardian authorization** flow for minors is not built; minors are simply excluded from outbound.
- Legal review of consent wording, retention periods and cross-border data transfer.
