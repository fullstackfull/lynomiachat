# Lynomia Commerce: Phase 2 implementation (Commerce Core + WooCommerce MVP)

Phase 2 builds the provider-neutral Commerce Core and a **read-only WooCommerce** provider.

- Security details: `08-woocommerce-security.md`.
- Real-store evidence: `09-woocommerce-e2e.md`.
- Salla, Zid and Shopify Commerce are **not** implemented. The upstream Shopify integration only received the OAuth callback fix (`security: harden Shopify OAuth callback`).

## 1. Decisions applied

| Decision | Where |
|---|---|
| WooCommerce first | `Commerce::Store::PROVIDERS = %w[woocommerce]`; registry `Commerce::Providers::REGISTRY` |
| Internal feature name `lynomia_commerce` | `config/features.yml` (column `feature_flags_ext_1`, off by default, assignable in Lynomia plans) |
| No store limit in the MVP | nothing counts stores |
| Plan-based limits later without a schema redesign | see §12 |
| Fully read-only | the HTTP client has only `get_json`; the provider has no write method (a spec asserts the public method list) |
| Code in `custom/` | everything except the integration points listed in §2 |

## 2. Files

**New, under `custom/`**

| Area | Files |
|---|---|
| Migrations | `custom/db/migrate/20260930100000_create_commerce_stores.rb`, `20260930100100_create_commerce_customer_links.rb` |
| Models | `custom/app/models/commerce/store.rb`, `customer_link.rb` |
| Core services | `custom/app/services/commerce/error.rb`, `store_url.rb`, `http_client.rb`, `phone.rb`, `customer.rb`, `order.rb`, `providers.rb`, `providers/base.rb`, `cache.rb`, `customer_matcher.rb`, `conversation_panel.rb`, `store_connection.rb`, `audit_trail.rb` |
| WooCommerce | `custom/app/services/commerce/providers/woocommerce.rb`, `providers/woocommerce/normalizer.rb` |
| Authorization | `custom/app/policies/commerce/store_policy.rb` |
| API | `custom/app/controllers/api/v1/accounts/commerce/stores_controller.rb` (settings), `custom/app/controllers/api/v1/accounts/conversations/commerce/stores_controller.rb` (panel), `custom/app/views/api/v1/accounts/commerce/stores/*.jbuilder` |

**Core integration points (changed outside `custom/`)**

| File | Change |
|---|---|
| `config/features.yml` | `lynomia_commerce` flag appended |
| `config/routes.rb` | `draw :commerce` (routes in `config/routes/commerce.rb`) |
| `db/schema.rb` | the two tables, 6 foreign keys, version bump |
| `custom/app/models/custom/account.rb` | `has_many :commerce_stores` |
| Frontend | `app/javascript/dashboard/api/commerce.js` |
| | `components/widgets/conversation/commerce/*` (panel, order card, helpers) |
| | `routes/dashboard/settings/commerce/*` (settings page) |
| | `routes/dashboard/conversation/ContactPanel.vue` (one section) |
| | `composables/useUISettings.js` (sidebar item order), `featureFlags.js`, `components-next/sidebar/Sidebar.vue` (settings entry), `settings/settings.routes.js` |
| | i18n `en`/`ar` (`commerce.json`, `settings.json` `SIDEBAR.COMMERCE`) |

**Enterprise:**
- The only Enterprise dependency is optional: audit rows go to `Enterprise::AuditLog` when it exists.
- The Community Edition keeps the `[Commerce]` log lines.
- The CE suite runs without `enterprise/` (see `09` §6).

## 3. Exactly what is stored

**`commerce_stores`** (one row per connected store; exactly one owning account):

| Column | Content |
|---|---|
| `account_id` | owner (FK, cascade on account deletion) |
| `provider` | `woocommerce` |
| `external_store_id` | normalized `host[:port]/path` of the URL the admin connected (e.g. `shop.example.com`). **Unique with `provider` installation-wide**, so a store cannot be in two accounts |
| `name`, `base_url` | display name; normalized store URL (`https://shop.example.com`) |
| `status` | `active` / `disabled` / `needs_reauth` / `disconnected` |
| `credentials` | `{"consumer_key","consumer_secret"}`, **Active Record encrypted** (non-deterministic); `NULL` after disconnect |
| `settings` | `{}` (reserved) |
| `metadata` | `{"verified_at": <last successful health check>}` |
| `created_by_id` | admin who connected it (nullified if the user is deleted) |

**`commerce_customer_links`** (one per store and contact):

| Column | Content |
|---|---|
| `account_id` | must equal `store.account_id` and `contact.account_id` (validated) |
| `commerce_store_id`, `contact_id` | unique together |
| `external_customer_id` | WooCommerce customer id, or `guest:<email>` / `guest:<E.164>`. **Deterministically encrypted** because guest ids carry an email or phone |
| `match_source` | `verified_phone` (automatic) or `manual`. `verified_email` and `external_id` are defined for later providers and unused by WooCommerce |
| `confirmed_by_id` | agent who linked manually (nullified if the user is deleted) |

**Not stored:**
- no order table;
- no customer profile;
- no address.

Orders live only in the Redis cache (≤ 24 h, §8).

## 4. Feature flag

- `lynomia_commerce` is off by default.
- It is enabled or disabled per account through the existing feature and plan infrastructure (Super Admin account features, or `BillingPlan` features synced by `Billing::FeatureSync`).
- **When off:**
  - both APIs answer 401 (`Pundit::NotAuthorizedError`, as other feature-gated Chatwoot APIs do);
  - the ContactPanel section is not rendered;
  - the Settings → Commerce entry and route are hidden.
- **Nothing else changes.** Verified in `09` (E2E "feature off") and by the unchanged full suites.

## 5. Provider contract and WooCommerce

`Commerce::Providers::Base` defines the contract. Every method returns provider-neutral values or raises `Commerce::Error`.

| Contract method | WooCommerce implementation (REST `wc/v3`, HTTP Basic with a Read key) |
|---|---|
| `health` | 1. `GET /wp-json/wc/v3?_fields=namespace` must return `wc/v3`.<br>2. `GET /orders?per_page=1&_fields=id` must be readable.<br>3. `GET /customers?per_page=1&role=all&_fields=id` must be readable.<br>A 404 means `STORE_UNAVAILABLE/woocommerce_api_not_found`. |
| `store_identity` | `{ external_store_id: host[:port]/path we connected to, name: host }`. Store-declared identifiers (WordPress `home`, store UUID) are ignored: a site can claim any value, and staging clones share them. |
| `find_customers(email:)` | 1. `GET /customers?email=&role=all` (account email, exact).<br>2. `GET /orders?search=<email>&per_page=20`.<br>Only orders whose billing email equals the normalized email are kept. Candidates are merged by id; a guest becomes `guest:<email>`. |
| `find_customers(phone:)` | `GET /orders?search=<national significant number>&per_page=20` (WooCommerce's customer search does not cover phones). Only orders whose billing or shipping phone, normalized to E.164 with the order's billing country, **equals** the phone are kept. A guest becomes `guest:<E.164>`. |
| `list_customer_orders(id, limit: 5)` | **Registered:** `GET /orders?customer=<id>&per_page=5&orderby=date&order=desc`.<br>**Guest:** `GET /orders?search=…&customer=0&per_page=20`, then the same exact re-check, first 5. |
| `get_order(id)` | `GET /orders/<numeric id>` |
| `admin_order_url(id)` | `"#{store.base_url}/wp-admin/admin.php?action=edit&id=<positive integer>&page=wc-orders"`. The HPOS screen; WooCommerce redirects it to `post.php` when HPOS is off. Never taken from a response (`_links` is ignored). |
| `normalize_customer`, `normalize_order` | `Commerce::Providers::Woocommerce::Normalizer` |

No webhooks are implemented. The contract stays ready: handlers would only invalidate the cache, as in `04` §4.

## 6. Normalized order

The UI and the cache only see this shape (`custom/app/services/commerce/order.rb`), never WooCommerce JSON:

```text
provider, external_order_id, order_number, status, provider_status, payment_status, currency, total,
created_at, updated_at, items[{name, quantity, total}], item_count, customer{external_id, name},
shipping{method, total} | null, tracking{number, url} | null, admin_order_url, customer_order_url (null)
```

- `status`: `pending`, `processing`, `on_hold`, `completed`, `cancelled`, `refunded`, `failed`, `draft`, else `other` (with the raw `provider_status`).
- **Payment status.** WooCommerce has no payment-status field, so it is derived in this order:

| Condition | `payment_status` |
|---|---|
| status `refunded`, or refunds ≥ total | `refunded` |
| any refund | `partially_refunded` (a refund is evidence of payment) |
| status `processing`/`completed` **and** `date_paid_gmt` set | `paid` |
| status `pending` | `unpaid` |
| status `failed` | `failed` |
| anything else: on-hold (bank transfer awaited), cash on delivery before completion, cancelled, custom statuses, missing data | `unknown` ("Payment not confirmed") |

  WooCommerce sets `date_paid` when a gateway confirms payment, or when the merchant moves the order to its paid status.

- **Shipping:** the shipping-line method titles and the shipping total. `null` when the order has no shipping line (virtual products).
- **Tracking:**
  - Always `null` for WooCommerce: core has no tracking.
  - Plugin metadata (e.g. `_wc_shipment_tracking_items`) is **not** read; a spec and the E2E prove it is ignored.
- **`customer_order_url`:** always `null`. WooCommerce only exposes `payment_url`, which embeds the order key, and the My Account slug is configurable.
- **Malformed data** (missing keys, non-numeric totals or ids, bad dates) raises `INVALID_RESPONSE`, never a partial order.

## 7. Customer matching

`Commerce::CustomerMatcher`, in order:

1. **Existing link** for (store, contact). No provider call.
2. **Verified phone:** the phone of the conversation's own channel identity (`conversation.contact_inbox.source_id`):
   - WhatsApp Cloud and واتساب بزنس: a digits source id becomes `+<digits>`;
   - a WhatsApp username identity (BSUID) has **no** phone;
   - SMS: E.164 source id;
   - Twilio SMS/WhatsApp: `whatsapp:` prefix removed.
   
   Outcome:
   - **exactly one** store customer → linked automatically (`verified_phone`, audited);
   - **several** → offered for manual selection, nothing linked;
   - **none** → continue.
3. **Suggestions only:** the contact's email, then its phone number. Agents can edit these, so they never auto-link.
4. **Manual:** "Link customer" searches by exact email, or by a phone in international format (`+966…`/`00966…`). Names are never searched; the API answers `INVALID_QUERY`.

**Details:**
- **Phone normalization:** `telephone_number` gem, the same one the app uses for WhatsApp and SMS. Numbers starting with `+`/`00` are parsed alone; local numbers only with the order's billing country; invalid numbers never match.
- **Email:** trim + downcase, exact.
- **Signed widget identity:** Chatwoot's HMAC covers only the website's user identifier, not the email or phone sent with it (a visitor can pair their own valid hash with someone else's email). So it does not auto-link.
- **Candidates:**
  - They reach the browser masked (`om***@example.com`, `+966*******33`) with an **encrypted, 15-minute token** bound to (store, contact, customer).
  - `POST …/link` accepts only such a token, so an agent cannot forge a customer id to read another customer's orders.
- **Audit:** manual link create/change/remove.
- **Discovery is cached** (§8), so reopening a panel does not search the store again.

## 8. Cache

`Commerce::Cache`, Redis through `Redis::Alfred`:

- **Keys:** `COMMERCE::V1::ACCOUNT::<account_id>::STORE::<store_id>::<ORDERS|CANDIDATES>::<HMAC-SHA256(secret_key_base, identifier)>`. Emails and phones never appear in a key.
- **Values:** `{value, fetched_at}` with provider-neutral JSON only, never credentials. TTL 24 h.
- **Flow:**
  1. Fresh (< 120 s): return it.
  2. Otherwise fetch → normalize → cache.
  3. On `STORE_UNAVAILABLE`, `TIMEOUT`, `RATE_LIMITED` or `INVALID_RESPONSE`, serve the previous value marked `stale: true` with its `fetched_at` and the error code. The UI shows "Couldn't refresh store data right now · Last updated 18 minutes ago".
- **`AUTH_INVALID` is never hidden behind stale data:**
  - the store becomes `needs_reauth`;
  - its cache is purged;
  - the event is audited.
- **Purged** on disable, disconnect, key rotation and `needs_reauth`.

## 9. API

**Settings (administrators, `Commerce::StorePolicy`)** under `/api/v1/accounts/:account_id/commerce/stores`:

| Request | Action |
|---|---|
| `GET` | list (id, provider, name, base_url, status, verified_at, created_at; never credentials) |
| `POST` | connect: `provider=woocommerce`, `base_url`, `consumer_key` (`ck_` + 40 hex), `consumer_secret` (`cs_` + 40 hex), optional `name`. Health check first; nothing is saved on failure. |
| `PATCH /:id` | `name`; `status=active\|disabled` (enable re-runs the health check); `consumer_key` + `consumer_secret` (rotation, health-checked) |
| `DELETE /:id` | disconnect: credentials and links deleted, cache purged, row kept as `disconnected` (reconnect = new keys) |

**Conversation panel (anyone who can view the conversation, `ConversationPolicy#show?`)** under `/api/v1/accounts/:account_id/conversations/:conversation_id/commerce/stores`:

| Request | Action |
|---|---|
| `GET` | active stores of the account and whether this contact is linked in each |
| `GET /:id` | panel: `state` = `linked` \| `suggested` \| `multiple` \| `not_found` \| `unavailable`, with `link`, `candidates`, `orders`, `fetched_at`, `stale`, `error` |
| `GET /:id/customers?query=` | manual search |
| `POST /:id/link` `{token}`, `DELETE /:id/link` | link or unlink |

**Errors:**
- JSON `{"error": {"code": …, "reason": …}}` with HTTP 422.
- Codes: `STORE_UNAVAILABLE`, `AUTH_INVALID`, `PERMISSION_DENIED`, `RATE_LIMITED`, `TIMEOUT`, `INVALID_RESPONSE`, plus `NOT_FOUND`, `INVALID_STORE_URL` (with a `reason`), `INVALID_QUERY`, `ENCRYPTION_NOT_CONFIGURED`, `STORE_ALREADY_CONNECTED`.
- Provider messages, hosts' pages and exceptions never reach the response.
- Store errors are 422, not 401/403, so the dashboard does not treat a store's rejection as the agent's session failing.

## 10. UI

**ContactPanel section "Commerce" / "المتجر"** (native component, no Dashboard App iframe):

| Element | Behaviour |
|---|---|
| Store selector | shown with 2+ active stores; the linked store is preferred; stores are never mixed |
| Linked | customer name, how it was matched, Change / Unlink, latest 5 orders |
| Order card | `#number`, total in the order currency, status and payment badges, date, item count, shipping method, **View order** (validated http(s) URL built by the backend) |
| Track shipment | only for a validated `https` `tracking_url` without credentials |
| Send tracking | emits `BUS_EVENTS.INSERT_INTO_RICH_EDITOR`, the same path as Copilot's "Use this": text is **inserted into the reply box, never sent**. No new message sender. |
| Suggested / multiple | masked candidates with Link |
| Not found | "لم يتم العثور على العميل في هذا المتجر" + [ربط العميل] and the search form |
| Stale / unavailable | "تعذر تحديث البيانات حاليًا" + "آخر تحديث: قبل 18 دقيقة", or a safe per-code message |
| No stores | message (administrators get a hint to Settings → Commerce) |

Requests use `useAbortableRequest`, so a newer conversation or store always wins over a slower older response.

**Settings → Commerce** (administrators):
- store list with status, WooCommerce URL and last verification;
- Add store (URL, consumer key and secret as password fields cleared on close, optional name);
- Disable / Enable, Replace keys (or Reconnect), Disconnect with confirmation;
- error messages per code and URL-policy reason.

**i18n:**
- `en` and `ar` (you asked for the Arabic strings). Other locales fall back to English through Crowdin as usual.
- The Phase 1 plan (`06`) said English only; this was changed on request.

## 11. Audit events

These go to `Enterprise::AuditLog` (`comment` = event, `action` create/update/destroy) and a `[Commerce]` log line. **Credentials are never in a payload.**

| Event | Changes recorded |
|---|---|
| `commerce.store_connected` | provider, external_store_id |
| `commerce.store_enabled` / `commerce.store_disabled` | status from → to |
| `commerce.store_needs_reauth` | (none) |
| `commerce.credentials_rotated` | status from → to |
| `commerce.store_disconnected` | number of links removed |
| `commerce.customer_link_created` | match_source |
| `commerce.customer_link_changed` | match_source from → to |
| `commerce.customer_link_removed` | match_source |

For an automatic `verified_phone` link:
- `confirmed_by` stays empty;
- the audit `user` is the agent whose panel load triggered the link (set by `audited` from the request).

## 12. Plan limits (done, no schema change)

Done in [35-stores-on-plans.md](35-stores-on-plans.md): `stores` is a plan limit next to agents and inboxes, enforced in
`Commerce::StoreConnection#attach` and `#rotate_credentials` (every provider's connections pass through them), with
`STORE_LIMIT_REACHED`.

## 13. Tests

| Suite | Count | Result |
|---|---|---|
| Ruby (Commerce): models, URL parsing, HTTP client/SSRF, WooCommerce provider on real payloads, matcher, cache, store connection, both APIs | 161 examples | pass |
| Vitest: helpers, order card, panel states (incl. Arabic) | 25 tests | pass |
| Real WooCommerce E2E | 41 checks + 17 API checks | pass (see `09`) |

Full-suite regression is in `09` §6.

**Coverage by requested area:**

| Area | Covered |
|---|---|
| Security | encryption at rest (raw column), secrets absent from every API response, SSRF matrix (11 address classes, DNS, redirect to metadata), cross-tenant, agent/admin |
| Matching | exact phone (local format stored), exact email (case), duplicate phone, duplicate email, manual data suggestion-only, no match, manual selection, name search refused, forged/foreign/expired token |
| Orders | none, one, five-plus (7 → 5), missing shipping, missing tracking, unknown payment, malformed (5 variants), non-list response |
| Cache | hit, miss, refresh after 120 s, stale fallback with age, provider unavailable with/without cache, revoked keys not hidden, 24 h TTL, tenant/store isolation, no identifiers or credentials in Redis |
| UI | feature disabled, no stores, unavailable, not found, suggested, multiple, linked, multi-store, Arabic, English, mobile (E2E) |

## 14. Known limitations

1. **No tracking:** WooCommerce core has none, so Track shipment and Send tracking never appear for WooCommerce. Both are implemented and tested for providers that return tracking.
2. **Formatted phones:**
   - WooCommerce searches the phone text as typed.
   - Phones stored with spaces or dashes (`055 111 2233`) are not found by phone (email and manual search still work).
   - The search term is the national significant number, which matches `+966…`, `966…`, `00966…` and `05…`.
3. **Guest orders before registration:** a registered customer's panel shows orders assigned to that customer id. Guest orders placed before registering appear as a separate guest candidate.
4. Discovery looks at the 20 most recent search hits per query.
5. **Read-only keys:** a Read key cannot be told apart from a Read/Write key without attempting a write, which Lynomia never does. The UI asks for Read keys.
6. **Stripped `Authorization` header:** hosts that strip it (some Apache/CGI setups) fail with `AUTH_INVALID`, and must be fixed on the server. Query-string keys are not used, because they would put secrets in URLs and logs.
7. **Permalinks:** plain permalinks (`?rest_route=`) are not supported; `/wp-json/` is required, as WooCommerce documents.
8. **Redirects:** redirects are never followed, so the admin must enter the final URL (apex vs `www`, http → https).
9. **Unlinking an automatic link:** after unlinking a verified-phone link, the next panel load links it again, because the verified phone still matches exactly one customer. Use **Change** to choose another customer.
10. **WordPress in a subdirectory:** the admin link is built from the store URL and may not resolve.
11. **No refresh button:** data refreshes when the panel is reopened after 120 s.
12. **No order-number search** (not in the Phase 2 scope).
13. **Community Edition:** no audit rows (no `Enterprise::AuditLog`), only log lines.
14. **Send tracking language:** the text follows the agent's UI language.
15. **RTL phones:** the stock off-canvas sidebar widens the page in Arabic on phones. This is pre-existing and also happens on the dashboard; the Commerce panel itself stays inside the viewport.
16. **No store limit** (by decision; §12).

## 15. Reuse for Salla (Phase 3)

**Reusable as is:**

| Area | Files |
|---|---|
| Schema and models | `commerce_stores` (with `external_store_id = merchant.id`), `commerce_customer_links` |
| Core services | `Commerce::Error`, `Commerce::Cache`, `Commerce::CustomerMatcher` (provider-agnostic: it calls `find_customers(phone:/email:)`), `Commerce::ConversationPanel`, `Commerce::AuditTrail`, `Commerce::Phone`, `Commerce::Customer`, `Commerce::Order`, `Commerce::Providers::Base` + registry |
| Authorization and API | `Commerce::StorePolicy`; the conversation API controller; the settings list, update and destroy actions; jbuilder views |
| UI | the whole ContactPanel section, including tracking. Salla returns `tracking_number`/`tracking_link`, so Track shipment and Send tracking light up with no UI change. The settings list. |
| Specs | the matcher, cache, panel and conversation-API specs as templates |

**Exact changes for Salla:**

1. `Commerce::Store::PROVIDERS << 'salla'`, and `REGISTRY['salla'] = 'Commerce::Providers::Salla'`.
2. **`Commerce::HttpClient`:** take the `Authorization` header value instead of Basic credentials (`Bearer <access_token>` for Salla). Salla's host is fixed (`api.salla.dev`), so `StoreUrl` is not used for the API host. SsrfFilter stays.
3. **Salla OAuth (new):**
   - Easy Mode installs through the `app.store.authorize` webhook: `POST /webhooks/commerce/salla`, HMAC `X-Salla-Signature` with `Signature` strategy only (`04` §4), dedup and a Rack::Attack rule.
   - A Custom Mode callback is for development.
   - `installation_config` entries `SALLA_CLIENT_ID`/`SALLA_CLIENT_SECRET`/`SALLA_WEBHOOK_SECRET` (`type: secret`).
4. **Token lifecycle (new):**
   - access token 14 d;
   - single-use rotating refresh under `Redis::LockManager`;
   - the new pair is written before use;
   - `invalid_grant` → `needs_reauth` (the existing status and UI state) plus an admin email;
   - `credentials` holds `{access_token, refresh_token, expires_at}`.
5. **`Commerce::Providers::Salla`:**
   - `health` (merchant info);
   - `store_identity` (`merchant.id`, store name, store domain for `base_url`);
   - `find_customers` via `GET /customers?keyword=` with the same exact re-check (`mobile_code` + `mobile` → E.164);
   - `list_customer_orders` via `/orders?customer_id=`, with items and shipments by separate calls (the light order format from 2026-09-01);
   - `admin_order_url` from a validated `*.salla.sa` host or a fixed pattern, never a raw response URL.
6. **Salla normalizer:**
   - status slugs → canonical;
   - payment status from Salla's evidence fields (`VERIFY` in `02`);
   - tracking from shipments, validated https.
7. **Rate limits:** read `X-RateLimit-*` and `Retry-After` into `RATE_LIMITED`, with backoff in jobs only.
8. **Settings UI:** a provider picker plus "Connect with Salla" (OAuth) next to the WooCommerce key form; `StoresController#create` dispatches per provider.
9. **Switch:** a per-provider env `COMMERCE_SALLA_ENABLED`, as in `04` §1.
10. **Specs and E2E:** specs on recorded Salla payloads, and an E2E on a Salla demo store (needs a Salla Partner account and a network allowlist).
