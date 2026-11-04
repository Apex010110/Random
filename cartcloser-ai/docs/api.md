# CartCloser AI API

Generated from the live FastAPI app (`python -m app.cli openapi`). Full machine-readable spec: [`openapi.json`](openapi.json).
Interactive docs while the server runs: <http://localhost:8000/docs> (Swagger UI) and `/redoc`.

## Conventions
- **Errors** are always `{"error": "<code>", "message": "<human text>"}` with a meaningful status:
  `401 unauthorized`, `403 forbidden/invalid_link/demo_only`, `404 *_not_found`, `409 conflicts` (e.g. `not_eligible`, `already_ordered`, `insufficient_stock`),
  `422 validation_error` (includes `details[]`), `503 not_connected` (integrations without credentials).
- **Tenant isolation**: merchant tokens map to exactly one tenant; every merchant query filters by it (another tenant's cart returns 404).
- **Shopper scope**: `X-Shopper-Id` (pseudonymous) + optional `X-Tenant-Id`; shoppers only see their own carts, chats and orders.
- **Idempotency**: `POST /carts` (`idempotency_key`), `POST /carts/{id}/abandon` (`idempotency_key`), messages (`idempotency_key`), orders (`idempotency_key`, required). Recovery sends use an atomic `scheduled -> sent` claim plus a unique key per attempt.
- **Pagination**: list endpoints take `limit` / `offset` and return `{items,total,limit,offset}`.
- **Money** is integer PKR.

## Endpoints (41)
| Method | Path | Summary | Auth | Body | Query | Status codes |
|---|---|---|---|---|---|---|
| `GET` | `/health` | Health | None (public / demo) | — | — | 200 |
| `GET` | `/products` | List Products | None (public / demo) | — | category, q, limit, offset, tenant_id | 200, 422 |
| `GET` | `/products/{product_id}` | Get Product | None (public / demo) | — | tenant_id | 200, 401, 404, 409, 422 |
| `GET` | `/store` | Store Info | None (public / demo) | — | tenant_id | 200, 422 |
| `POST` | `/carts` | Create Cart | X-Shopper-Id | CartCreate | — | 201, 401, 404, 409, 422 |
| `GET` | `/carts/{cart_id}` | Read Cart | X-Shopper-Id | — | — | 200, 401, 404, 409, 422 |
| `PATCH` | `/carts/{cart_id}` | Patch Cart | X-Shopper-Id | CartPatch | — | 200, 401, 404, 409, 422 |
| `POST` | `/carts/{cart_id}/checkout-started` | Checkout Started | X-Shopper-Id | CheckoutStartedIn | — | 200, 401, 404, 409, 422 |
| `POST` | `/carts/{cart_id}/abandon` | Abandon | X-Shopper-Id | — | — | 200, 401, 404, 409, 422 |
| `GET` | `/r/{cart_id}` | Open Recovery Link | Signed link token | — | t, tenant_id | 200, 401, 404, 409, 422 |
| `POST` | `/consents` | Grant | X-Shopper-Id | ConsentIn | — | 201, 401, 404, 409, 422 |
| `POST` | `/consents/revoke` | Revoke | X-Shopper-Id | ConsentRevokeIn | — | 200, 401, 404, 409, 422 |
| `GET` | `/consents/me` | My Consent | X-Shopper-Id | — | — | 200, 422 |
| `POST` | `/recovery/{cart_id}/schedule` | Schedule | Merchant bearer token | — | — | 200, 401, 404, 409, 422 |
| `POST` | `/recovery/{cart_id}/trigger-demo` | Trigger Demo | Merchant bearer token | — | — | 200, 401, 404, 409, 422 |
| `GET` | `/conversations/{cart_id}` | Get Conversation | X-Shopper-Id | — | — | 200, 401, 404, 409, 422 |
| `POST` | `/conversations/{cart_id}/messages` | Post Message | X-Shopper-Id | MessageIn | — | 200, 401, 404, 409, 422 |
| `POST` | `/orders` | Create Order | None (public / demo) | OrderIn | tenant_id | 200, 401, 404, 409, 422 |
| `GET` | `/orders/{order_id}` | Get Order | X-Shopper-Id | — | — | 200, 401, 404, 409, 422 |
| `GET` | `/merchant/metrics` | Merchant Metrics | Merchant bearer token | — | days | 200, 401, 404, 409, 422 |
| `GET` | `/merchant/carts` | Merchant Carts | Merchant bearer token | — | status, limit, offset | 200, 401, 404, 409, 422 |
| `GET` | `/merchant/carts/{cart_id}` | Merchant Cart | Merchant bearer token | — | — | 200, 401, 404, 409, 422 |
| `POST` | `/merchant/carts/{cart_id}/pause` | Pause Cart | Merchant bearer token | FlagIn | — | 200, 401, 404, 409, 422 |
| `GET` | `/merchant/conversations` | Merchant Conversations | Merchant bearer token | — | escalated, limit, offset | 200, 401, 404, 409, 422 |
| `POST` | `/merchant/conversations/{cart_id}/reply` | Merchant Reply | Merchant bearer token | HumanReplyIn | — | 200, 401, 404, 409, 422 |
| `POST` | `/merchant/conversations/{cart_id}/takeover` | Takeover | Merchant bearer token | FlagIn | — | 200, 401, 404, 409, 422 |
| `GET` | `/merchant/settings` | Get Settings  | Merchant bearer token | — | — | 200, 401, 404, 409, 422 |
| `PATCH` | `/merchant/settings` | Patch Settings | Merchant bearer token | SettingsPatch | — | 200, 401, 404, 409, 422 |
| `GET` | `/merchant/catalog` | Get Catalog | Merchant bearer token | — | — | 200, 401, 404, 409, 422 |
| `PATCH` | `/merchant/catalog` | Patch Catalog | Merchant bearer token | CatalogPatch | — | 200, 401, 404, 409, 422 |
| `GET` | `/merchant/orders` | Merchant Orders | Merchant bearer token | — | limit, offset | 200, 401, 404, 409, 422 |
| `GET` | `/merchant/integrations` | Integrations | Merchant bearer token | — | — | 200, 401, 404, 409, 422 |
| `GET` | `/merchant/export` | Export | Merchant bearer token | — | — | 200, 401, 404, 409, 422 |
| `DELETE` | `/merchant/shoppers/{shopper_id}` | Delete Shopper Data | Merchant bearer token | — | — | 200, 401, 404, 409, 422 |
| `GET` | `/merchant/stream` | Stream | Merchant bearer token | — | — | 200, 422 |
| `GET` | `/changes` | Changes | None (public / demo) | — | — | 200 |
| `POST` | `/demo/reset` | Demo Reset | None (public / demo) | — | — | 200 |
| `POST` | `/demo/seed` | Demo Seed | None (public / demo) | — | — | 200 |
| `POST` | `/demo/tick` | Demo Tick | None (public / demo) | — | — | 200 |
| `POST` | `/integrations/shopify/webhook` | Shopify | HMAC signature | — | — | 200, 422 |
| `POST` | `/integrations/woocommerce/webhook` | Woocommerce | HMAC signature | — | — | 200, 422 |

## Live updates
- `GET /merchant/stream` (Server-Sent Events, `event: change`, `data: {"version": n}`) — EventSource clients may pass `?token=`.
- `GET /changes` — polling fallback used by the Flutter app (refetches when `version` changes).
