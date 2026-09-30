# Lynomia Commerce: provider capability matrix

- **Sources:** official docs (see the per-provider URLs in `02-provider-contracts.md`) and this repository's code. `VERIFY` = not confirmed on the official page (`00` §0).
- **"Existing code"** refers to Lynomia/Chatwoot 4.18 as it stands today.
- **Updated for Phase 3.** WooCommerce (Phase 2) and Salla (Phase 3) are implemented; the section "Implemented" below
  records what the connectors actually do. The table rows describe the platforms.

| Capability | Salla | Zid | Shopify | WooCommerce |
|---|---|---|---|---|
| **Existing code in Lynomia** | **Phase 3 connector** (read-only; docs 10–13) | none | **Partial**: upstream integration, one store per account, REST, non-expiring token, callback security flaw (`00` §2) | **Phase 2 connector** (read-only; docs 07–09) |
| **OAuth / install** | OAuth2. **Easy Mode**: tokens delivered by the `app.store.authorize` webhook; Custom Mode (callback) is for development | OAuth2 authorization code; two tokens (`Authorization` + `X-Manager-Token`); host `oauth.zid.sa` vs `api.zid.sa` **VERIFY** | OAuth2 authorization code (non-embedded) or token exchange (embedded); existing code: code grant, **needs patch** | No OAuth: `/wc-auth/v1/authorize` merchant approval POSTs consumer key/secret to our HTTPS callback; manual key entry as fallback |
| **Multiple stores** | Yes, one install per merchant; key `merchant.id` | Yes, per-store tokens; key `store_id` | Yes, one token per shop; key `*.myshopify.com`. **Existing code: 1 per account** | Yes, each site separate; key normalized `home_url` |
| **Customer lookup by phone** | Yes: `GET /customers?keyword=` (broad, so re-check exactly); local vs `966` format **VERIFY** | Orders `customer_phone` filter; customers filter **VERIFY** | Yes: `customerByIdentifier(phoneNumber)` / `customers(query:"phone:")`; **needs protected-customer-data Level 2** | **Customers API: no.** Order `search` covers billing phone (legacy storage; HPOS ≈ 9.4+ **VERIFY**) |
| **Customer lookup by email** | Yes (`keyword`) | **VERIFY** | Yes (`emailAddress`; Level 2) | Yes: `customers?email=&role=all`; guests through order `search` |
| **Orders** | Yes: `/orders?customer_id=`. Detail is "light" since 2026-09-01 (items and shipments need separate calls) | Yes: `/managers/store/orders`, `payload_type` for items; marketplace orders have masked PII | Yes: GraphQL `customer.orders` (REST legacy); **last 60 days only** unless `read_all_orders` is approved | Yes: `/wc/v3/orders` (max 100 per page) |
| **Payment status** | Only explicit: `is_pending_payment` / `payment_pending` → unpaid; nothing states "paid", so everything else is unknown (implemented) | `payment_status` field (value set **VERIFY**) | `displayFinancialStatus` | Derived (`status`, `date_paid_gmt`, `refunds[]`) |
| **Fulfillment / shipping** | Shipments API: `courier_name`, `status` | `shipping.method` (paths **VERIFY**) | `fulfillments`, `displayFulfillmentStatus` | Only `shipping_lines` (method); core "Order Fulfillments" is **beta** |
| **Tracking** | Yes: `tracking_number`, `tracking_link` (when `trackable`) | `shipping.method.tracking.{number,url}` **VERIFY** | Yes: `trackingInfo{company number url}` | **Not in core**: Shipment Tracking extension, core fulfillments beta, or plugin `meta_data`; per-store config |
| **Refunds (read)** | `order.refunded` event, transactions; no list endpoint **VERIFY** | `/orders/{id}/credit-notes` | `refunds`, `totalRefundedSet` | `/orders/{id}/refunds` |
| **Webhooks** | App events are automatic; store events via Portal or `POST /webhooks/subscribe` | Per-store `POST /v1/managers/webhooks`; lifecycle via Partner Dashboard | App-wide (`shopify.app.toml`) or `webhookSubscriptionCreate`; **compliance topics mandatory** | `/wc/v3/webhooks` (**write key needed, VERIFY**) or merchant admin UI |
| **Webhook verification** | HMAC-SHA256 `X-Salla-Signature` (Signature strategy; Token strategy is weaker) | **None documented (VERIFY)**: secret URL token + re-fetch | HMAC-SHA256 base64 `X-Shopify-Hmac-Sha256` (already implemented upstream) | HMAC-SHA256 base64 `X-WC-Webhook-Signature` (per-webhook secret) |
| **Dedup id** | None: hash of `merchant:event:body` | None: composite key | `X-Shopify-Webhook-Id` | `X-WC-Webhook-Delivery-ID` |
| **Delivery / retries** | 3 × ~5 min | 3 with backoff; degraded after 10 failures/h; recovery needs a new URL | 8 over 4 h; subscription deleted after 8 consecutive failures | **No retries**; disabled after 5 consecutive failures |
| **Token refresh** | Access token until its `expires` (absolute Unix time); **refresh single-use, rotating, never expires** (Salla agent kit); needs `offline_access` | Manager token 1 y; **refresh single-use** | **Expiring offline tokens**: 1 h access / 90 d rotating refresh; **mandatory for all public apps from 2027-01-01**; existing code: none | Not applicable (keys don't expire; revocable) |
| **Rate limits** | Per-plan leaky bucket (`X-RateLimit-*`); customers 500 per 10 min | 60 requests/min per app per store (enforced on products today) | GraphQL query cost, leaky bucket | None built in (host or WAF) |
| **Abandoned carts** | Yes: `carts.read`, `/carts/abandoned`, `abandoned.cart*` events | Yes: API + events (`abandoned_carts.read`) | Exists in the API (abandoned checkouts); not researched in this phase, **VERIFY** | Not in core (plugins) |
| **Arabic / Saudi specifics** | Default `ar` responses; `mobile` + `mobile_code` (+966); dates `Asia/Riyadh` | `Accept-Language: ar/en` | n/a | Store-configured |
| **Sandbox / testing** | Partner Portal demo stores (needs a Salla Partner account) | Partner Dashboard test stores (needs a Zid Partner account) | Free development stores (Partner account); protected data works on dev stores without review | **Local WooCommerce in Docker** (Docker Hub images; plugin from GitHub releases **VERIFY** reachability) |
| **Docs reachable from this environment** | No (proxy 403) | No | No | No (GitHub sources yes) |

## Implemented (Phase 2 and Phase 3)

| | WooCommerce (Phase 2) | Salla (Phase 3) |
|---|---|---|
| Connect | Administrator pastes a Read REST API key; health check first | *Connect with Salla*: one-time code in the app's Salla settings + Easy Mode `app.store.authorize` (doc 10) |
| Store identity | Host + path the admin connected | Salla merchant id, confirmed with `user/info` |
| Credentials | Consumer key/secret, encrypted | Access + refresh token, expiry, scope, encrypted; refreshed under a merchant lock, never reused (doc 11) |
| Customer lookup | Customers API (email) + order search, exact re-check | `GET /customers?keyword=` (national number / email), exact re-check |
| Orders | `/orders?customer=`, latest 5 | `/orders?customer_id=` (one page of 60, newest first locally), latest 5; no `expanded` |
| Payment status | Derived from status + `date_paid_gmt` + refunds | Explicit pending-payment only, else unknown |
| Shipping / tracking | Shipping line titles; no tracking (core has none) | Shipments API per shown order: carriers, shipment status, tracking number/link for trackable shipments; all shipments kept |
| Webhooks | None (not needed for read-only) | App events only: authorize, settings, updated, uninstalled; HMAC-verified; no `order.*` sync |
| Rate limits | None built in | Salla headers: back off on 429 / exhausted budget until reset |
| Provider switch | Always on | `SALLA_ENABLED` in Super Admin |
| Live E2E | Real WooCommerce 10.9.4 stores (doc 09) | **Blocked**: Salla hosts not reachable; simulated E2E with documented payloads (doc 13) |
