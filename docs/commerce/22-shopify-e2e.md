# Lynomia Commerce: Shopify E2E and regression (Phase 5)

**`REAL_SHOPIFY_UAT = BLOCKED`.** No real Shopify store could be used:
- this environment's egress proxy refuses every Shopify host (`*.myshopify.com`, `shopify.dev`, `partners.shopify.com`);
- there is no Shopify Partner account, Commerce app or development store.

The E2E below runs the real Lynomia application against a **simulated Shopify** built from Shopify's official libraries and published 2026-07 schema. It proves Lynomia's side of the contract. It does **not** prove Shopify's side (§6), and nothing here claims production readiness, which also waits for Shopify's protected customer data approval (doc 18 §7).

## 1. What is real and what is simulated

| Real | Simulated |
|---|---|
| Lynomia production build (Rails / Puma, Vite production assets), Postgres, Redis, Sidekiq queueing | Every `<shop>.myshopify.com` host: answered in-process by `docs/commerce/e2e/shopify/shopify_sim.rb` (WebMock) inside the Lynomia server and the job runner |
| OAuth start endpoint, shop-domain validation, legacy-conflict check, state issue and consumption, cookie binding, callback HMAC, server-side code exchange with `expiring=1`, scope check, shop identity query, encrypted storage | Shopify's authorization page: Playwright answers `https://<shop>/admin/oauth/authorize` with Shopify's redirect to the callback, the query signed with the E2E client secret **the way `@shopify/shopify-api` verifies it** (Node `URLSearchParams`, an implementation independent of Lynomia's Ruby) |
| Token manager (lock, refresh, retry, needs_reauth), GraphQL client and provider, normalizer, matcher, cache, panel, settings UI, Super Admin | Shopify's token and GraphQL answers in the 2026-07 shapes (fixtures under `spec/fixtures/files/commerce/shopify`), stateful in Redis (`E2E::SHOPIFYSIM::*`): single-use codes; issued tokens with their expiry; Shopify's documented refresh semantics (the same pair for a repeated refresh, previous refresh token kept until the new access token is used); revocation; order changes; request and operation log (a mutation would be recorded and refused) |
| Webhook endpoint with HMAC over HTTP, deduplication, encrypted queueing, the webhook job, the privacy topics | Shopify delivering a webhook: sent from the E2E, signed with the E2E client secret as Shopify signs it |
| WooCommerce, Salla and Zid stores in the same account; the legacy Shopify integration's settings, hooks and webhook endpoint | |

- **How the server runs.** `bundle exec rails runner docs/commerce/e2e/shopify/server.rb` boots the app in production mode, installs `ShopifySim` (WebMock for `*.myshopify.com` only; every other host untouched) and serves it with Puma on port 3100.
- **Nothing in the app is changed for the E2E.** No DNS or TLS interception is used.

Files:
- `docs/commerce/e2e/shopify/shopify_sim.rb` (the simulated Shopify);
- `server.rb` (E2E server);
- `sim.rb` (runner controls: configure, legacy fingerprint and hook, reset, jobs, requests, grant/refresh/GraphQL modes, expire, invalidate, refresh race, revoke, order change, cache age, state);
- `e2e_shopify.js` (Playwright, 64 checks);
- `schema/` (graphql-js validation of the connector's documents against Shopify's published schemas).
- Results: `docs/commerce/e2e/results/shopify_e2e_results.json`, `shopify_e2e_run.txt`, `shopify_schema_validation.txt`.
- Screenshots: `docs/commerce/screenshots/shopify/`.

## 2. Result: 64/64 passed

The first full run passed 64/64 as well. Its screenshots showed the domain hint cut off on mobile and in Arabic. The hint was shortened (`9c04881eb`) and everything was run again on that final build: Shopify 64/64, then the Zid, WooCommerce and Salla regressions (§4).

| # | Check | Result |
|---|---|---|
| 1–2 | Super Admin: Enable Shopify Commerce, Client ID, masked empty Client Secret, no merchant-token field; the legacy Shopify page unchanged, with no Commerce field | PASS |
| 3–5 | Add store offers WooCommerce, Salla, Zid and Shopify; Connect with Shopify asks only for the myshopify.com domain; `evil.example.com`, `https://…`, `…myshopify.com.evil.com`, `127.0.0.1` and `user@…` refused before any redirect | PASS |
| 6 | **Legacy conflict**: a shop this account shows through the legacy integration is refused with an explanation; the legacy hook untouched | PASS |
| 7 | Browser sent to `https://<shop>/admin/oauth/authorize`: `client_id`, `scope=read_customers,read_orders`, the redirect URL, a state; no `grant_options[]=per-user`; no secret in the URL | PASS |
| 8–12 | Back in Settings → Commerce (`shopify=connected`): store connected to account A with shop id `68210001`, name and myshopify.com URL; one server-side exchange with `expiring=1`; credentials exactly `access_token, access_token_expires_at, refresh_token, refresh_token_expires_at, scope` with both expiries from Shopify's answer; identity by GraphQL `shop`; no mutation; list shows name, Shopify, Active | PASS |
| 13–19 | **Callback security**:<br>• replayed callback;<br>• unsigned, wrong-secret, modified, 5-minute-old and other-shop callbacks;<br>• forged state;<br>• a signed callback from another (agent's) browser;<br>• → no code exchange and no store in every case.<br>Agent cannot start (401); a non-expiring token and a write-scope token refused, nothing stored; account B authorizing A's shop → `STORE_ALREADY_CONNECTED`, shop stays with A | PASS |
| 20–21 | **Multi-store**: a second Shopify shop in the same account; one conversation lists WooCommerce, Salla and both Shopify shops | PASS |
| 22–28 | **Panel**:<br>• verified-WhatsApp-phone auto-link, last five orders newest first;<br>• multi-fulfillment order → Delivered, Paid, Aramex, Track shipment, Send tracking;<br>• partially fulfilled + pending → Processing, Unpaid, In transit (DHL);<br>• fulfilled without tracking → Shipped, Partially refunded, Out for delivery, nothing to track;<br>• cancelled + refunded; on hold + partially paid;<br>• https tracking link and the admin link built from the shop domain;<br>• Send tracking fills the reply box | PASS |
| 29–33 | **Matching**:<br>• a guest checkout suggested by the contact email (never auto-linked), then linked, tracking from the active fulfillment only;<br>• the same email as a registered customer and as a guest → several matches, the agent chooses;<br>• no match by email; a phone with no customer → not found, no guest guessed by phone | PASS |
| 34–35 | **Protected customer data not approved** → the panel says so, invents no match, serves nothing stale. **Throttled** → cached orders served, marked as not refreshed | PASS |
| 36–40 | **Webhooks**:<br>• missing, wrong, other-secret and hex signatures → 401, nothing queued;<br>• a signed delivery → 200, its retry (same webhook id) queued once;<br>• the order event drops the cache and the panel shows the new status at once;<br>• the legacy endpoint refuses a Commerce-signed delivery | PASS |
| 41–47 | **Token lifecycle**:<br>• 10 concurrent readers → one refresh, one new pair;<br>• expired access token → refreshed before use, new access **and** refresh token stored;<br>• early 401 → one controlled refresh and retry;<br>• a refresh lost to a timeout → resent once with the same refresh token, same pair returned;<br>• refused refresh → needs_reauth, tokens removed, nothing stale;<br>• settings explain and offer Reconnect;<br>• Reconnect (domain prefilled) re-authorizes in place | PASS |
| 48–50 | **Privacy and uninstall**:<br>• `customers/data_request` and `customers/redact` → 200, the customer's links in that shop removed, recorded without personal data;<br>• `app/uninstalled` → disconnected, token, links and cache removed, contacts and conversations unchanged;<br>• `shop/redact` → store row deleted, account audit keeps the store id | PASS |
| 51–55 | **Switches**:<br>• Shopify off: stores kept and explained, no Shopify in Add store, `PROVIDER_DISABLED`, privacy webhook still accepted;<br>• Commerce off for the account: no Commerce in settings, no authorization (401) | PASS |
| 56 | **Legacy**: the legacy Shopify settings (fingerprint of hashed values) and hook count identical before and after the whole run | PASS |
| 57–58 | Arabic picker and dialog (الربط مع Shopify); mobile dialog fits the screen | PASS |
| 59–64 | **Audit and secrets**:<br>• audit has `commerce.shopify.connected`, `token_refreshed`, `needs_reauth`, `reauthorized`, `uninstalled`, `shop_redacted`;<br>• only `query` operations reached Shopify (`LynomiaShop`, `LynomiaCustomers`, `LynomiaOrders`, `LynomiaGuestOrders`);<br>• no token, code or secret in audit entries or in any of the 1,227 app and API responses;<br>• no token, code, state or secret in the server or job logs;<br>• no uncaught page errors | PASS |

Scenario coverage asked for in Phase 5:
- **Matching:** phone (22), email (29, 31), guest (29–30), duplicate identity (31), no match (32–33).
- **Payment and fulfillment:** paid (23), pending (24), refunded (26), fulfilled (23, 25), partially fulfilled (24), multi-fulfillment (23), tracking URL (27), no tracking (25).
- **Lifecycle and webhooks:** uninstall (49), token refresh (41–47), webhook duplicate (38), protected data denied (34).

Token refresh used clock manipulation instead of waiting an hour:
- `sim.rb expire` puts both Lynomia's expiry and the simulated Shopify's token expiry in the past;
- `invalidate_access` makes Shopify reject a token Lynomia still believes valid.

## 3. Screenshots (`docs/commerce/screenshots/shopify/`)

| File | Shows |
|---|---|
| `shopify-01-super-admin.png` | Super Admin → Shopify Commerce: switch, Client ID, masked secret |
| `shopify-02-provider-picker.png` | Add store: WooCommerce, Salla, Zid, Shopify |
| `shopify-03-connect-dialog.png` | Connect with Shopify: domain only |
| `shopify-04-invalid-domain.png` | A domain that is not myshopify.com refused |
| `shopify-05-legacy-conflict.png` | A shop already shown by the legacy integration refused |
| `shopify-06-connected.png` | Store connected, settings list |
| `shopify-07-already-connected.png` | Account B: the shop belongs to another account |
| `shopify-08-settings-all-providers.png` | WooCommerce, Salla, Zid and two Shopify shops in one account |
| `shopify-09-panel-orders.png` | Panel: verified-phone link, five orders, statuses, payment, carriers, tracking |
| `shopify-10-guest-suggested.png` | A guest checkout suggested by email |
| `shopify-11-multiple-matches.png` | Registered + guest with the same email: agent chooses |
| `shopify-12-protected-data.png` | Protected customer data not approved |
| `shopify-13-throttled-stale.png` | Throttled: cached orders marked as not refreshed |
| `shopify-14-after-webhook.png` | Order event: new status at once |
| `shopify-15-needs-reauth.png` | Needs re-authorization, Reconnect |
| `shopify-16-uninstalled.png` | After `app/uninstalled` |
| `shopify-17-provider-off.png` | Shopify switched off: stores kept and explained |
| `shopify-18-picker-arabic.png`, `shopify-19-connect-dialog-arabic.png`, `shopify-20-panel-arabic.png` | Arabic |
| `shopify-21-mobile-connect-dialog.png` | Mobile (390 px) |

## 4. Regression

**End-to-end.** The production build of HEAD `9c04881eb` ran all four E2Es in sequence. Results are in `docs/commerce/e2e/results/`.

| E2E | Result | Notes |
|---|---|---|
| Shopify (simulated Shopify) | **64/64** | `shopify_e2e_results.json`, `shopify_e2e_run.txt` |
| Zid (simulated Zid) | **49/49** | `zid_regression_phase5.json`; Shopify Commerce **on**, two Shopify stores in the same account |
| WooCommerce (real WooCommerce 10.9.4 stores) | **41/41** | `woocommerce_regression_phase5.json`; plain `rails s` server |
| Salla (simulated Salla) | **47/47** | `salla_regression_phase5.json`; same server |

- **Switched off for WooCommerce and Salla.** As in Phase 4, Salla, Zid and now Shopify Commerce are off for these two runs. They were written for an installation where Add store goes straight to WooCommerce's form, and where Salla's "provider off" check expects WooCommerce alone. The picker with every provider is covered by the Shopify and Zid E2Es.
- **Sessions** of the E2E users are ended before each E2E (upstream's concurrent-session limit, doc 17 §4).
- **WhatsApp and واتساب بزنس** are unchanged: Phase 5 touches no channel code, the full suites below include the WhatsApp specs, and every E2E conversation arrives on the واتساب بزنس inbox.
- **Legacy Shopify** is unchanged (doc 21 §3):
  - no legacy file changed;
  - legacy specs green;
  - the E2E's legacy fingerprint is identical before and after.

**Full suites.** Test assets were built once per tree (`RAILS_ENV=test bin/vite build`). Every shard ran with `VITE_RUBY_AUTO_BUILD=false`, 4 shards per tree.

| Suite | Examples | Failures | Pending | Phase 4 |
|---|---|---|---|---|
| Enterprise | 10086 | 1 | 67 | 9957 / 1 / 67 |
| Community | 7385 | 1 | 69 | 7256 / 1 / 69 |
| Vitest | 457 files, 4717 tests | 0 | | 456 files, 4709 tests |
| ESLint (`app/**/*.{js,vue}`) | | 0 errors | | no warnings in Commerce files |

- Both suites grew by the Phase 5 specs (129 examples each).
- **No failure comes from Commerce, Shopify, Zid, Salla, WooCommerce or Lynomia.** Both failures are the specs already classified UPSTREAM (doc 13 §5, doc 17 §4):
  - `spec/enterprise/services/voice/call_transcription_service_spec.rb:77`: `reindex` exists only with `OPENSEARCH_URL`.
  - `spec/models/conversation_spec.rb:1144`: a 1-second tolerance across inline jobs. It fails intermittently on clean `v4.18.0`, and passed in the first run.
- **First run** (HEAD `61cda7f36`) found three failures in the new Shopify specs, all spec-only; the code under test was right in each case. Fixed in `9b7b73afc`, then both suites were run again.
  - Two token expectations used `90.days.from_now`, a calendar duration. With a time zone that has daylight saving left set by an earlier spec, it is an hour away from Shopify's exact `refresh_token_expires_in` seconds, which the code adds as seconds. Reproduced by forcing a DST zone; the expectations now use seconds.
  - One callback spec read `Enterprise::AuditLog` without the `defined?` guard, so it failed in the Community tree.
- **Legacy Shopify specs green in both trees:**
  - `spec/controllers/shopify`, `spec/controllers/webhooks/shopify_controller_spec.rb`, `spec/services/shopify`, `spec/controllers/api/v1/accounts/integrations/shopify_controller_spec.rb`;
  - the Enterprise Shopify billing specs.

## 5. How to run

1. `docs/commerce/e2e/e2e.env` (from `e2e.env.example`, with `E2E_SHOPIFY_CLIENT_SECRET`), seed data `docs/commerce/e2e/rails/seed.rb`.
2. Production assets: `erun.sh "bin/vite build --force"`.
3. End the E2E users' sessions (doc 17 §5 step 7).
4. Server: `bundle exec rails runner docs/commerce/e2e/shopify/server.rb` on port 3100.
5. `ERUN=… CHROMIUM_PATH=… node docs/commerce/e2e/shopify/e2e_shopify.js <out>`.
6. Regression: the Zid E2E on `docs/commerce/e2e/zid/server.rb` with Shopify Commerce on. Then the WooCommerce and Salla E2Es on the plain `rails s` server, with Salla, Zid and Shopify Commerce switched off (`sim.rb configure off` of each).
7. GraphQL documents against Shopify's published schemas (from `@shopify/dev-mcp`, `dist/data/admin_<version>.json.gz`), with graphql-js:
   - `cd docs/commerce/e2e/shopify/schema && npm install graphql@16`
   - `node validate.js <schema> documents.json`
   - `node access.js <schema> documents.json`
   - `documents.json` is the five documents as the code defines them (`Commerce::Shopify::Oauth::SHOP_QUERY` and the provider's `*_QUERY` constants).

## 6. `REAL_SHOPIFY_UAT = BLOCKED`: what the real UAT must confirm

Blocked because:
- this environment's egress proxy refuses every Shopify host;
- there is no Shopify Partner account, Commerce app or development store here.

To run it:
1. Create the Lynomia Commerce app from `docs/commerce/shopify.app.toml.example` and deploy it with `shopify app deploy`.
2. Set its Client ID and Client Secret in Super Admin → Settings → Shopify Commerce.
3. Create a development store with orders, customers and a guest checkout.

The real UAT must confirm:
1. Authorization lands on `/commerce/shopify/callback` with Shopify's real signature; Lynomia's canonical HMAC accepts it (doc 18 §4).
2. The code exchange with `expiring=1` returns `expires_in` and `refresh_token_expires_in`; the stored expiries match.
3. The granted `scope` string is `read_customers,read_orders`.
4. A refresh after about an hour: new pair saved. A repeated refresh (network cut) returns the same pair. Refreshing with a revoked token (after an uninstall) → needs_reauth (doc 18 §9.1).
5. Customers by exact email and E.164 phone, guest orders by email, and last-five orders with fulfillments and tracking, on a development store. Then on a non-development store **before and after protected customer data approval**: `PROTECTED_DATA_NOT_APPROVED` before, matches after.
6. Throttling: `extensions.cost` on real answers; the backoff under load.
7. Webhooks from the app configuration: `orders/updated` invalidates; `app/uninstalled` on uninstall; the compliance topics via Shopify's test tools. Signature, `X-Shopify-Webhook-Id` retries.
8. The legacy integration on the same installation, untouched: its callback, webhooks, orders sidebar and billing.

**No production readiness is claimed** before this UAT and the protected customer data approval (Level 1 + Email + Phone).

## 7. Known limitations

- **Guests by phone.** The 2026-07 `orders` search has no phone filter, so guest checkouts are found by email only. Registered customers are found by email or phone.
- **Tracking-only updates.** `fulfillments/*` topics need `read_fulfillments`, which is not requested. A tracking change that does not update the order shows after the 120 s cache.
- **Order history.** Only the last 60 days of orders without `read_all_orders`. The architecture allows adding it later (scope + approval, no query change).
- **Idle stores.** Refresh is lazy (on use). A store not read for longer than the refresh token's life (about 90 days) needs Reconnect.
- **Legacy the other way round.** The legacy connect flow does not know about Commerce (doc 21 §2): connecting a shop through legacy after Commerce shows its orders in both sections. Legacy is protected, so this is documented, not changed.
- **Disconnect** removes Lynomia's access but leaves the app installed in Shopify (the connector is read-only and sends no mutation). The merchant uninstalls it in Shopify admin, which Lynomia then receives as `app/uninstalled`.
- **Data requests** (`customers/data_request`) are recorded for the operator, not answered automatically (doc 20 §4).
- **One shop in two accounts.** Another account's authorization attempt for a shop already connected is refused, but Shopify may have issued it a token (discarded). Whether that affects the first account's token is VERIFY (doc 18 §9.2).
