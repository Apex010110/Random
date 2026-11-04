# Test report

Environment: Linux container, Python 3.13.18, Flutter 3.47.9 (Dart 3.13.7), OpenJDK 21, Android SDK 36, PostgreSQL 16, Chromium (Playwright). Date: 2026-11-04.

## Backend (FastAPI)
```
$ ruff check app tests scripts
All checks passed!
$ python -m pytest -q                       # SQLite in-memory
46 passed in 6.53s
$ TEST_DATABASE_URL=postgresql+psycopg://postgres@/cartcloser?host=/tmp&port=5433 python -m pytest -q
46 passed in 8.82s
$ DATABASE_URL=postgresql+psycopg://... python -m app.cli migrate && alembic check
No new upgrade operations detected.
```
| File | Covers |
|---|---|
| `tests/test_scenarios.py` (10) | MRD scenarios **A–H** end-to-end over HTTP, revoke-before-send, background-scheduler delay |
| `tests/test_units.py` (31) | language detection (EN / Urdu script / Roman Urdu, no Hindi script), business-day maths, delivery never guaranteed, COD rules, discount ceiling, injection guard, pricing/free shipping, invalid promo, single-use AI codes, COD confirmation, stock decrement, attribution window, consent record fields, affirmative-only consent, quiet hours, campaign pause, auth (401), **tenant isolation**, shopper isolation, signed recovery links, validation errors, **webhook HMAC + dedupe + 503 when not connected**, honest integration status, audit redaction, metrics == events, data deletion, OpenAPI contract |
| `tests/test_llm_adapter.py` (5) | stubbed Anthropic client: valid rephrase used (`source=llm`, `claude-opus-5-5`, server-side fallbacks); invented numbers → rules; dropped "no guarantee" → rules; timeout & refusal → rules; STOP/handoff/discount never sent to the LLM |

Live server smoke test (uvicorn + background scheduler): with accelerated demo timing (2 s) the scheduler delivered the recovery message on its own; the SSE stream emitted `event: change`.

## Flutter
```
$ flutter analyze
No issues found!
$ CARTCLOSER_BACKEND=http://localhost:8000 flutter test --timeout 120s
00:21 +25: All tests passed!
```
| File | Covers |
|---|---|
| `test/parity_test.dart` (2) | seed assets == `/seed`; **Dart assistant == Python assistant on 384 fixtures** (intent, language, action, confidence, exact text; 4 carts × 3 dates × 28 questions) |
| `test/engine_test.dart` (14) | offline engine scenarios **A–H**, scheduler/quiet hours, pricing/promo/COD/discount ceiling, consent fields, link tokens, metrics/redaction, settings validation/reset |
| `test/widget_test.dart` (7) | welcome labels, storefront + search, sold-out sizes disabled, cart badge/quantity/free shipping, judge scenario **E**, judge scenario **A** (13 steps → recovered), integrations "Not connected" |
| `test/acceptance_test.dart` (1) | **MRD acceptance demo through real taps**: shopper → kurta → cart → checkout (opt-in box verified *unchecked*) → tick → leave → merchant sees eligible cart → trigger → inbox → "Will it arrive in Karachi by Friday?" (can't-guarantee answer) → "Can I pay COD?" → link → confirm COD → receipt → dashboard PKR 4,690; then **repeat without opt-in** (Bilal): no outbound message exists |
| `test/api_repository_test.dart` (1) | the app's `ApiRepository` against the **live backend**: full recovery path, Roman Urdu reply, live snapshot metrics, no-consent block |
| `integration_test/app_test.dart` | same acceptance flow for emulator / simulator / Chrome. **Not run here** (no emulator or iOS simulator in this container) |

### Browser verification (Flutter web release build, Chromium via Playwright)
Scenario A was clicked through step by step in the real web build. This found and fixed two bugs the VM tests could not catch: `Random().nextInt(1 << 32)` (which is 0 in JavaScript) crashing idempotency-key generation, and snackbars with actions not auto-dismissing. Screenshots in [`screenshots/`](screenshots/), including a live Urdu-script delivery answer.

## Build outputs
| Output | Result |
|---|---|
| Flutter web (`flutter build web --release --no-web-resources-cdn`) | **Built**, served offline and browser-tested |
| Android APK (`flutter build apk --release`) | **Built**: `app-release.apk`, 60.4 MB, `pk.cartcloser.cartcloser_ai` 1.0.0, minSdk 24, arm64-v8a / armeabi-v7a / x86_64, label "CartCloser AI", INTERNET permission (backend mode only). Signed with the Flutter **debug key** (fine for sideloading at the summit; not Play-Store-ready). Installed-on-device test **not performed** (no emulator here). The first attempts failed with HTTP 429 from Maven Central; fixed by adding Google's Maven Central mirror to `android/settings.gradle.kts` / `build.gradle.kts` |
| iOS | **Not built** (requires macOS + Xcode). Instructions in README |
| Docker image / compose | **Not built** (no Docker daemon in this container). The Postgres path was verified with a local PostgreSQL 16 instead |
| OpenAPI | `docs/openapi.json` (41 operations) |

## Not verified / known gaps
- Real Anthropic API calls (no key in this environment; adapter tested with a stub).
- Android emulator, physical phone and iPhone simulator runs.
- Shopify / WooCommerce / WhatsApp: intentionally not connected (see README limitations).
