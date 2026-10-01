# Lynomia Commerce: real UAT and the production gate (Phase 6)

**Nothing was deployed to production.** This page records the Phase 6 gate. Everything ran on one final build: the provider runs, the full suites, the deploy and rollback rehearsal, and the leak scan. The page ends with each provider's verdict and the overall one (§1, §11).

## 1. Verdict

| Provider | Real UAT | Verdict | In production |
|---|---|---|---|
| **WooCommerce** | **Real**: three WooCommerce 10.9.4 stores, 41/41 on the final image | **GO**, with a pilot: the first production store is the smoke of §12 step 10 | Offered (WooCommerce has no switch). Commerce stays off for every account until an account is chosen for it (§12) |
| **Salla** | **BLOCKED**: no route to Salla, no Partner account, no public HTTPS staging | **NO-GO** | `SALLA_ENABLED` **off** |
| **Zid** | **BLOCKED**: same; the `state` round-trip is unconfirmed (STOP condition 1) | **NO-GO** | `ZID_ENABLED` **off** |
| **Shopify** | **BLOCKED**: same; protected customer data **not approved** | **NO-GO** | `SHOPIFY_COMMERCE_ENABLED` **off** |

**Overall: PARTIAL GO.** The release may be deployed with the three provider switches off (their default), so only WooCommerce can be connected. No global GO is given, because three providers remain unproven against their real services. Salla, Zid and Shopify become candidates only after their real UAT (§4) and, for Shopify, the protected customer data approval.

## 2. The final build

| | |
|---|---|
| Branch | `claude/laughing-albattani-8yi0kh` |
| Build commit | `f842e12ec7cf3924d65bafda874562269c52a905`. The commits after it change only `docs/`: this page, the result files, notes in docs 02–22 and the harness check of §10. No runtime file |
| Image | `lynomia/staging:final-f842e12e`, id `sha256:2c556fe0f7062cf342a33a68fa83b02e6aca52680d1b70ad0425ae9451b5fe8f`, label `org.opencontainers.image.revision=f842e12e…` |
| Recipe | `git archive` of the commit on the Ruby 3.4.4 / Node 24 base (`sha256:4814b1e3…`) with `docker/Dockerfile`'s production steps: `RAILS_ENV=production`, `assets:precompile`, then `spec`, `node_modules` and `tmp/cache` removed (as in `../chatwoot-upgrade/06-target-runtime-and-staging-rehearsal.md` §4) |
| Runtime | Ruby 3.4.4, Node v24.13.0, pnpm 10.2.0, Bundler 2.5.16; Postgres 16.15, Redis 7.0.15 |
| Locks | `Gemfile.lock` sha256 `b9efc099…b66359`; `pnpm-lock.yaml` sha256 `3330795c…e34946`. Neither changed since the Phase 4 release `e1cd4c53` |
| Migration level | 186 migrations, latest `20260930100100_create_commerce_customer_links`. The release adds 2 migrations over `e1cd4c53`: `commerce_stores` and `commerce_customer_links` |
| Contents | `custom/` 120 files, `enterprise/` 557 files, Vite manifest and 298 compiled assets |

**Every provider run in this phase used this image.** The Commerce E2E servers and runner commands ran inside it (§5), and so did the rehearsal's web, worker, migrations and harness (§10). The only things mounted were the test fixtures (`spec/fixtures`, not in the image) and `tmp` for logs. The RSpec suites ran on the same commit in the base image, as in every phase (§8).

The production image itself (`docker/Dockerfile`, Alpine) cannot be built here: `dl-cdn.alpinelinux.org` answers 403. It is built from the same commit in the deploy (§12 step 1).

## 3. Staging and access to the real providers

| Requirement | Status |
|---|---|
| Production-mode staging on the final image: Postgres, Redis, Puma, Sidekiq, Active Record encryption keys, production assets | **Done**, in containers on this host (§10) |
| Public HTTPS URL with real callback and webhook URLs | **Not available** to this session: no inbound network, no domain, no certificate |
| Provider hosts | **Refused** by the egress proxy (`CONNECT` 403, `e2e/results/phase6/provider_reachability.txt`): `accounts.salla.sa`, `api.salla.dev`, `s.salla.sa`, `oauth.zid.sa`, `api.zid.sa`, `docs.zid.sa`, `*.myshopify.com`, `admin.shopify.com`, `shopify.dev`, `partners.shopify.com` |
| Salla Partner app + demo store; Zid Partner app + test store; Shopify Partner app + development store | **None** available |
| WooCommerce | **Real**: WooCommerce 10.9.4 from the official source tag, HPOS on, three stores in Docker (doc 09) |

So only WooCommerce has a real UAT. The Salla, Zid and Shopify runs below use the simulated providers of docs 13, 17 and 22. **They prove Lynomia's side of each contract and do not count as real UAT.** No code was adapted to a provider in this phase, since no real evidence exists to adapt to.

## 4. Per provider

### 4.1 WooCommerce: real, 41/41

The Phase 2 E2E (doc 09) ran unchanged against the final image and the three real stores. It covers:
- **Connect.** Refused for a wrong secret, an IP address, plain http and a private address.
- **Two tenants.** A second account cannot connect a store another account holds.
- **Orders.** A WhatsApp guest auto-linked by verified phone; payment statuses; latest 5 orders; the store selector and per-store orders; the "View order" link; no tracking controls.
- **Matching safety.** A shared phone or billing email offers candidates and links nothing; an email-only widget contact only gets suggestions; name search is refused.
- **Outage.** Stale orders shown with their age; a safe message when nothing is cached.
- **Arabic and mobile** layouts.
- **Permissions.** An agent without inbox access sees nothing; with the feature off there is no Commerce section.
- **Lifecycle.** Disable, re-enable, replace keys, disconnect; manual link, relink and unlink.
- **No credentials** in any of 698 API responses.

AUTH_INVALID never served stale is proven for all four providers by the gate spec (§6).

Results: `e2e/results/phase6/woocommerce_final.{json,txt}`. Tracking stays nullable: WooCommerce core has no tracking, and the card shows none (gate spec, §6). No WooCommerce code changed.

### 4.2 Salla: `REAL_SALLA_UAT = BLOCKED`, simulated 47/47

The items the brief asks to close stay open, because no real Salla evidence exists:
- the `app.settings.updated` field that carries the connection code;
- `expires` vs `expires_in`;
- the Orders API default sort.

The code keeps its fail-safe handling:
- **Connection code.** A settings event without the expected key connects nothing.
- **Token expiry.** Both `expires` (timestamp) and `expires_in` (seconds) are read. With neither, the tokens are refused and nothing is saved.
- **Order sort.** The largest page is re-sorted newest first.

Token rules are proven by specs and the simulated E2E (doc 11, doc 13):
- one refresh at a time, and a lost race never reuses a refresh token;
- reauthorization and uninstall;
- revoked tokens → needs reauth;
- no token in the browser, logs, audit or cache.

Data rules are proven the same way:
- phone and email matching; ambiguous customers never linked;
- paid and unpaid orders, shipped orders, tracking with and without a link;
- the order panel is the neutral Commerce panel; Salla adds only its connection-code dialog.

The real run is doc 13 §4, and its results close §9's S-items.

### 4.3 Zid: `REAL_ZID_UAT = BLOCKED`, simulated 49/49

- **State round-trip (doc 14 §8.1).** Unconfirmed. The callback refuses a missing or wrong `state`, and this is **not weakened**. If real Zid does not return `state`, the real UAT stops at STOP condition 1 (doc 17 §6), and Zid stays NO-GO until a correlation of the same strength exists.
- **Webhook Basic Auth field (doc 15 §8.1).** Unconfirmed. It is set in one place, `Commerce::Zid::Webhooks#subscription`, which is the only code a different real contract may change. A wrong field can only make deliveries fail (401); it can never let an unauthenticated one in.
- **Webhooks, simulated.** Proven: valid and invalid credentials; replay deduplicated; cache invalidation; one subscription set per store (delete by `original_id` before registering); no duplicates after Reconnect (doc 17 §2).

### 4.4 Shopify: `REAL_SHOPIFY_UAT = BLOCKED`, simulated 64/64

| Item | Status |
|---|---|
| Dedicated app, never the legacy app | Separate settings, callback, webhook URI and signature (doc 21 §2). The legacy app's secret is refused on the Commerce webhook, and vice versa |
| Protected customer data (Level 1 + Email + Phone) | **Not approved.** Production stays blocked until it is. Without approval, customers and guest orders answer `PROTECTED_DATA_NOT_APPROVED`. The panel then shows the approval message and no customer data, and never stale or partial identity data (the cache does not serve stale for this code; doc 19, E2E). No names or addresses are requested |
| Token lifecycle | Expiring offline tokens only (`expiring=1`). Covered with the simulated Shopify's documented semantics: refresh under a lock, a repeated refresh, revoked → needs reauth, reconnect. The real run is doc 22 §6 items 2–4 |
| GraphQL 2026-07 | The five documents validate against Shopify's published 2026-07 Admin schema, re-extracted from the final code (`e2e/results/phase6/shopify_schema_validation.txt`). No REST call exists in the connector |
| Webhooks | HMAC over the raw body; `X-Shopify-Webhook-Id` dedup for one day; cache invalidation per customer; `app/uninstalled` disconnect. The privacy topics are accepted with the switch off (doc 20) |
| Privacy (data requests) | Decision in §7.1 |
| Legacy duplicate gap | Closed in both directions (§7.2) |

## 5. How the provider runs used the final image

`e2e/results/phase6/e2e_runner.sh` (a copy of the runner):
1. Starts each E2E server from `lynomia/staging:final-f842e12e`: the Shopify and Zid simulator servers of docs 22 and 17, then plain `rails s` for WooCommerce and Salla.
2. Points every driver's `ERUN` at the same image.
3. Runs Shopify, then Zid with Shopify Commerce on, then WooCommerce, then Salla, as in Phase 5.

Server logs are kept with each result.

## 6. Cross-provider, cross-tenant, matching, cache and tracking

`spec/controllers/api/v1/accounts/conversations/commerce/production_gate_spec.rb` sets up one account with a WooCommerce, a Salla, a Zid and a Shopify store, and one WhatsApp contact known to all four. Every provider answers in its documented shapes; everything on Lynomia's side is real. **9/9 pass**, with three seeds.

| Brief item | Proven by the gate spec |
|---|---|
| 19. Four stores, one contact | Selector lists the four stores with provider labels. Each store links its own customer (`guest:+966551112233`, `1227534533`, `90001`, `7001`) and shows only its own orders; no order number repeats across stores |
| 19. Cache isolation | A Shopify `orders/updated` webhook drops exactly one Shopify key. The other stores' keys are unchanged |
| 19 / 23. Tracking | https links only. Salla and Zid: the provider's own shipment. Shopify: an order with two shipments keeps both. WooCommerce: none. **Send tracking** only fills the reply box (UI, docs 13/17/22); nothing is sent automatically |
| 20. Cross-tenant | Another account cannot read, change or disconnect these stores (404/401, no provider call), and cannot claim them (`STORE_ALREADY_CONNECTED` for all four). It cannot reuse Zid webhook credentials (401) or reuse an OAuth state (other browser, other provider, replay). Callback replay is also refused in the connection specs of docs 14 and 18 |
| 21. Matching safety | Two Salla customers with the contact's phone → `multiple`, no link. A web contact with only an email gets suggestions from WooCommerce and Salla and `not_found` from Zid and Shopify. **No auto-link without one exact verified match** |
| 22. Cache policy | Fresh for 120 s (one call, then a second after 121 s). TTL at most 24 h. Stale at 23 h on a 503. Then, for all four providers, 401 (with refresh refused) → `orders: nil`, `AUTH_INVALID`, needs_reauth, cache purged |
| 31. Emergency switches | `ZID_ENABLED` off hides only Zid: no Zid call, other stores work, the conversation's messages load. Commerce off for the account → 401 on Commerce, messages 200, no provider call |

## 7. Phase 6 decisions and changes

Three code commits, each needed to pass the gate; everything else is documentation and evidence. No feature was added.

### 7.1 Shopify `customers/data_request`: operator-assisted, decided

Shopify's contract has three parts ([privacy law compliance](https://shopify.dev/docs/apps/build/compliance/privacy-law-compliance)):
1. declare the topic;
2. answer 200 to a genuine delivery and 401 to a bad HMAC (Shopify's automated review checks this);
3. provide the data to the store owner within 30 days.

Shopify prescribes **no automated response** for part 3.

**Decision:** operator-assisted fulfilment satisfies the contract for App Store and custom distribution alike.
- Parts 1 and 2 are automatic (doc 20 §2).
- For part 3, the job now records the ids of the customer's links in the audit entry, still without email, phone or customer number, so the export stays possible after the payload is gone (`1ff8f9d36`).
- `docs/commerce/ops/shopify_data_request_export.rb <data_request_id>` prints the export for the merchant (doc 20 §4).

This is reviewed and recorded here, so no compliance assumption is left open. If a future App Store review asks for more, it is a Shopify-side finding for the real UAT; Shopify stays NO-GO until then regardless.

### 7.2 Legacy Shopify duplicate gap: closed

`9b46b32f2` adds one guard at the legacy connect start (`POST …/integrations/shopify/auth`). It refuses a shop this account has as a Commerce store in any status but disconnected: 422, no state issued. No legacy token, hook, webhook, billing or callback behaviour changed, and nothing is migrated.

- Legacy → existing Commerce shop: **refused** (`spec/controllers/api/v1/accounts/integrations/shopify_controller_spec.rb`: active, needs_reauth and disabled refused; disconnected, another account and another shop allowed).
- Commerce → existing legacy shop: **refused** (Phase 5 spec and E2E check 6).

No account can hold one shop through both paths (doc 21 §2).

### 7.3 Gate spec

`f842e12ec` adds the gate spec of §6.

## 8. Tests, security review and leak scan on the final commit

### 8.1 Tests

| Suite | Result |
|---|---|
| Backend RSpec, Enterprise (how Lynomia runs), 4 shards | **10,097 examples, 2 failures, 67 pending**: both known, see below |
| Backend RSpec, Community (`enterprise/` removed), 4 shards | **7,396 examples, 0 failures, 69 pending** |
| Frontend Vitest | **457 files, 4,717 tests, all passed** |
| ESLint | **0 errors**, 444 warnings (same count as Phase 4; none mentions Commerce) |
| RuboCop (repo config) | 3,218 files, **54 offenses**, all in 9 upstream files byte-identical to `v4.18.0` (`git diff v4.18.0` over them is empty); 0 in Lynomia files |
| Brakeman | 38 warnings vs **36 on clean `v4.18.0`**; the 2 extra are false positives in the E2E simulators (§8.2); **0 in `custom/` or any Lynomia-changed app file** |
| WooCommerce E2E (real stores, final image) | 41/41 |
| Salla E2E (simulated, final image) | 47/47 |
| Zid E2E (simulated, final image) | 49/49 |
| Shopify E2E (simulated, final image) | 64/64 |
| Shopify GraphQL documents vs the 2026-07 schema | **5/5 valid**, documents re-extracted from the final image, identical to the committed ones; no mutation, no REST call |
| WhatsApp API harness (existing numbers), final image | **41/41 at every rehearsal step**: before the release, deployed, both rollbacks, rollback over live Commerce data, roll forward, direct path |
| Lynomia harness, final image | **17/17** |
| WhatsApp Business (واتساب بزنس) harness, final image | **54/54** |
| Commerce switches harness, final image | **19/19** (§10 step 9) |
| Production gate spec | 9/9 |

The two EE failures:
- `spec/enterprise/services/voice/call_transcription_service_spec.rb:77` fails identically on clean upstream `v4.18.0`. It needs OpenSearch (`../chatwoot-upgrade/07-production-gate.md` §2).
- `spec/models/conversation_spec.rb:1144` is the known intermittent upstream spec (a 1-second tolerance across inline jobs; doc 22 §4). Rerun on its own: 3/3 passed, and the whole file 119/119 (`e2e/results/phase6/rerun_conversation_spec_1144.txt`).

Raw logs: `e2e/results/phase6/` (`rspec_*.txt`, `vitest.txt`, `eslint.txt`, `rubocop.txt`, `brakeman*.json`).

### 8.2 Security review

- **Phase 6 runtime changes (2 files).**
  - The legacy guard is a read-only `exists?` on `Current.account.commerce_stores`. It runs after the existing domain validation, uses bound parameters and sits behind the existing administrator policy.
  - The data-request audit records ids only: no email, phone or customer number.
  - The export script is operator-only (`rails runner`). It writes nothing, and prints only what the merchant is owed.
- **Unchanged since Phase 5, re-checked by the gate spec (§6):**
  - ownership and claims, OAuth state, webhook authentication (HMAC, Salla Signature, Zid Basic);
  - the SSRF guard, encryption at rest, the cache keys and TTLs, the matcher.
  - Doc refs: docs 04, 08, 12, 15, 18, 20.
- **Brakeman** on the final tree: 38 warnings, 0 errors (Brakeman 8.0.5). Clean `v4.18.0` has 36, and those 36 are identical here. The 2 extra are "possible SQL injection" in `docs/commerce/e2e/{shopify/shopify_sim,zid/zid_sim}.rb`: a Redis `hincrby` helper named `count` in the E2E simulators, which the app never loads. **No warning in `custom/` or in any app file Lynomia changed.**
- **Accepted residuals, not Commerce-specific:**
  - Super Admin app secrets live in `installation_configs` in plaintext, as all upstream Chatwoot settings do. They are typed `secret`: write-only, masked, filtered from logs (doc 00 #3, doc 12).
  - WhatsApp `provider_config.api_key` at rest (`../whatsapp-business/SECURITY-BACKLOG.md` §2).

### 8.3 Credential-leak scan

`e2e/results/phase6/leak_scan.txt`. The scan looks for every known test secret, in plaintext:
- the E2E and rehearsal `SECRET_KEY_BASE` and Active Record encryption keys;
- the Salla, Zid and Shopify client and webhook secrets;
- the four WooCommerce key pairs;
- every token the simulators issue: access, refresh, manager and authorization tokens, and codes.

It searches:
- both databases (E2E and rehearsal; `installation_configs` checked separately);
- both Redis databases, except the simulators' own `E2E::*` state;
- every server, simulator, runner and harness log and E2E result of this phase;
- the final image's `/app`.

| Target | Secret hits | Token hits |
|---|---|---|
| E2E database dump (350 KB) | 0 | 0 |
| Rehearsal database dump (325 KB) | 0 | 0 |
| Redis db 12 (E2E) and 13 (rehearsal) | 0 | 0 |
| 145 log and result files (34 MB): E2E servers, simulators, runners, rehearsal, harness, UI smoke | 0 | 0 |
| Final image `/app` | 0 files | n/a |

**0 plaintext credential leaks.**
- **Positive controls.** Every `commerce_stores.credentials` value is Active Record ciphertext (5 stores in the E2E database, 1 in the rehearsal). The simulators' own state, which is the provider's side and was excluded, holds 23 values matching the token pattern, so the pattern does catch real issued tokens. None of them appears anywhere on Lynomia's side.
- **`installation_configs`.** The app secrets appear only in their own rows: `SALLA_CLIENT_SECRET`, `SALLA_WEBHOOK_SECRET`, `ZID_CLIENT_SECRET` and `SHOPIFY_COMMERCE_CLIENT_SECRET`. That is where they are stored (§8.2), not a leak.
- **UI smoke.** The page source of each provider's Super Admin page does not contain its stored secret (§10 step 10).

## 9. VERIFY closure

These are all the VERIFY items (and "not yet verified" or "must confirm" items) in docs 00–22. Categories:
- **CONFIRMED**: settled by a real system or by the provider's normative source.
- **REJECTED / IMPLEMENTATION CHANGED**: the assumption was dropped, and the code does not depend on it.
- **STILL BLOCKED**: only the real provider can settle it. Every one belongs to Salla, Zid or Shopify, which are all NO-GO; each gates that provider's GO.
- **NOT APPLICABLE**: the feature is not in this release.

**No open item belongs to WooCommerce, the only GO provider.**

### WooCommerce

| # | Item (source) | Status | Evidence |
|---|---|---|---|
| W1 | `search` covers billing email and phone with HPOS (02 §5) | **CONFIRMED** | Real WooCommerce 10.9.4, HPOS on: guests found by phone and by email (doc 09; 41/41 on the final image) |
| W2 | Webhook creation needs a write key (02 §5) | **NOT APPLICABLE** | No WooCommerce webhooks; orders refresh after 120 s (doc 06 §3) |
| W3 | `my-account/view-order` slug (02 §5) | **NOT APPLICABLE** | No customer order link is shown (`customer_order_url: nil`) |

### Salla

| # | Item (source) | Status | Evidence / behaviour until confirmed |
|---|---|---|---|
| S1 | `app.settings.updated` carries the code under the field id `lynomia_connection_code` (10, 13 §4) | **STILL BLOCKED** | Without the key nothing connects (fail closed; doc 10 spec) |
| S2 | Token expiry `expires` vs `expires_in` (11) | **STILL BLOCKED** | Both read; with neither, the tokens are refused (`INVALID_RESPONSE`) and nothing is saved |
| S3 | Orders API default sort (13 §4) | **STILL BLOCKED** | The largest page is re-sorted newest first. A customer with more orders than one page could show older orders if Salla sorts ascending: real check needed |
| S4 | Refresh response may omit `scope` (11) | **STILL BLOCKED** | Previous scope kept |
| S5 | `invalid_client` is HTTP 401 (11) | **STILL BLOCKED** | Treated as an installation problem, not the store's (`STORE_UNAVAILABLE`, `salla_client_rejected`) |
| S6 | Refresh-token lifetime of one month (02 §3) | **STILL BLOCKED** | A refused refresh → needs_reauth |
| S7 | `keyword` matches the national number / `966` form (03, 05, 13 §4) | **STILL BLOCKED** | Exact E.164 re-check after the search. A broad or missed search can only miss, never mis-link |
| S8 | `user/info` `domain` shape for stores without a custom domain (10) | **STILL BLOCKED** | Parsed by `Commerce::StoreUrl` (https, default port, no IP); anything else fails the connection loudly |
| S9 | Order list `items` and `date`; shipment `status` and `tracking_link` (13 §4) | **STILL BLOCKED** | `item_count` is null when items are absent. Tracking link only when `trackable` and https |
| S10 | Order items path, "List Order Items" (02 §3) | **REJECTED / IMPLEMENTATION CHANGED** | No items endpoint is called; items come from the order list when present (S9) |
| S11 | `customer` present in the light order format (02 §3) | **REJECTED / IMPLEMENTATION CHANGED** | Identity comes from `GET /customers` (matcher), not from orders |
| S12 | Payment status from evidence fields and transactions (02 §3, 07) | **REJECTED / IMPLEMENTATION CHANGED** | Unpaid only when Salla says so (`is_pending_payment`, `payment_pending`); otherwise "Payment not confirmed". No transactions call |
| S13 | `updated_at` source (02 §3) | **REJECTED / IMPLEMENTATION CHANGED** | Not used (`updated_at: nil`); `created_at` from `date.date` + `date.timezone` (S9) |
| S14 | `restored` → refunded (02 §3) | **STILL BLOCKED** | The mapping follows Salla's status docs; the raw slug is kept as `provider_status` |
| S15 | Order and headers of `app.store.authorize` / `app.settings.updated` (13 §4) | **STILL BLOCKED** | Both orders are handled (doc 10, specs) |
| S16 | Refunds list endpoint (05) | **NOT APPLICABLE** | Refunds are not read in this release |

### Zid

| # | Item (source) | Status | Evidence / behaviour until confirmed |
|---|---|---|---|
| Z1 | `state` returned unchanged (14 §8.1) | **STILL BLOCKED** (STOP condition) | Fail closed; never weakened (§4.3) |
| Z2 | Basic Auth field of the webhook subscription (15 §1, §8.1) | **STILL BLOCKED** | Only `Commerce::Zid::Webhooks#subscription` may change. A wrong field fails closed (401) |
| Z3 | `order.payment_status.update` is subscribable (02 §4, 15 §8.2) | **STILL BLOCKED** | A refused event fails the registration job, which is reported |
| Z4 | Delivery id header (15 §8.3) | **STILL BLOCKED** | Dedup by body hash works without it |
| Z5 | Delivery body shape (15 §8.4) | **STILL BLOCKED** | Only `store_id` and `customer.id` are read; anything else is ignored |
| Z6 | `expires_in` is an integer (14 §8.2) | **STILL BLOCKED** | A missing or non-integer value stores no expiry; the token is then refreshed when Zid rejects it (401 → refresh) |
| Z7 | Refresh rotation / reuse answer (14 §8.3) | **STILL BLOCKED** | A refresh token is never sent twice (lock) |
| Z8 | Profile `user.store.id/title/url/timezone` live values (14 §8.4) | **STILL BLOCKED** | Shape from the official SDK model; a missing or non-numeric id, title or url refuses the connection (`INVALID_RESPONSE`) |
| Z9 | Scope identifiers, and whether the profile needs one (02 §4, 14 §6, §8.5) | **STILL BLOCKED** | Set in the Partner Dashboard at UAT |
| Z10 | `Store-Id` / `Role` headers (02 §4) | **STILL BLOCKED** | Official SDK sends `Authorization` + `X-Manager-Token` only, as Lynomia does. A missing header fails the connect-time profile call |
| Z11 | `search_term` matches the national number (02, 03, 16 §11.1) | **STILL BLOCKED** | `customer_phone` is not used; exact E.164 re-check after the search |
| Z12 | `created_at` zone (02, 16 §4, §11.2) | **STILL BLOCKED** | Store time zone from the profile, else `Asia/Riyadh` |
| Z13 | `sort_by=desc` sorts by creation (16 §11.3) | **STILL BLOCKED** | Re-sorted locally within the page of 50 |
| Z14 | `payment_status` values beyond the SDK's four (02, 16 §11.4) | **STILL BLOCKED** | Unknown values shown as unknown |
| Z15 | `order_number` = `id` vs `invoice_number` / `code` (02 §4) | **STILL BLOCKED** | `id` shown |
| Z16 | Shipment path `shipping.method.tracking` (02 §4) | **STILL BLOCKED** | Official SDK model; also reads `waybill`; https links only |
| Z17 | Marketplace orders masked (17 §6.7) | **STILL BLOCKED** | Masked data cannot match; "Customer not found" |
| Z18 | Host `oauth.zid.sa` vs `api.zid.sa` (02 §4) | **CONFIRMED** (normative source) | Official SDK and agent skill: OAuth on `oauth.zid.sa`, Merchant API on `api.zid.sa` (doc 14 §1) |
| Z19 | Webhooks unsigned (06 §2 risk 6) | **REJECTED / IMPLEMENTATION CHANGED** | Basic Authentication is mandatory from 2026-09-30 (Zid changelog 57336); implemented per store (doc 15) |
| Z20 | Customers endpoint filter (02 §4) | **NOT APPLICABLE** | Customers endpoint not used (orders search) |
| Z21 | Customer events (02 §4) | **NOT APPLICABLE** | Not subscribed |
| Z22 | Admin order URL pattern (02, 16 §11.5) | **NOT APPLICABLE** | No admin link |
| Z23 | App Market install deep link (14 §8.6) | **NOT APPLICABLE** | The connection starts in Lynomia |

### Shopify

| # | Item (source) | Status | Evidence / behaviour until confirmed |
|---|---|---|---|
| H1 | Real authorization and HMAC on `/commerce/shopify/callback` (22 §6.1) | **STILL BLOCKED** | Verified the way `@shopify/shopify-api` does, in an independent implementation (doc 22) |
| H2 | `expires_in` / `refresh_token_expires_in` returned (22 §6.2) | **STILL BLOCKED** | A grant without expiries is refused |
| H3 | Granted scope `read_customers,read_orders` (22 §6.3) | **STILL BLOCKED** | A missing requested scope, or any non-`read_` scope, is refused |
| H4 | Refresh after about an hour, repeated refresh, revoked refresh (22 §6.4, 18 §9.1) | **STILL BLOCKED** | Any 400/401 except `invalid_client` → needs_reauth |
| H5 | Real data on a development store; `PROTECTED_DATA_NOT_APPROVED` before approval and matches after (22 §6.5) | **STILL BLOCKED** | Approval not requested yet (§4.4) |
| H6 | Throttling (`extensions.cost`) under load (22 §6.6) | **STILL BLOCKED** | Backoff on `THROTTLED` (doc 19) |
| H7 | Webhooks from the app configuration, test tools, retries (22 §6.7) | **STILL BLOCKED** | HMAC and dedup proven over HTTP (doc 22) |
| H8 | Legacy integration on the same installation (22 §6.8) | **STILL BLOCKED** | Separation proven with the legacy code's own specs and E2E (doc 21 §3) |
| H9 | Re-authorization by another account invalidates the first token? (18 §9.2, 22 §7) | **STILL BLOCKED** | The second account is refused and its token discarded |
| H10 | Callback `timestamp` tolerance (18 §9.3) | **STILL BLOCKED** | 90 s, as Shopify's libraries |
| H11 | Admin link `admin.shopify.com/store/{handle}/…` (02 §6) | **REJECTED / IMPLEMENTATION CHANGED** | `https://<shop>.myshopify.com/admin/orders/<id>`, built from the verified shop domain; the redirect is checked in H5 |
| H12 | Abandoned checkouts (05) | **NOT APPLICABLE** | Not in scope |

### Across providers

| # | Item (source) | Status |
|---|---|---|
| X1 | Provider hosts blocked here (06 §5 risk 1) | **STILL BLOCKED**: environment; this is why S, Z and H stay open |
| X2 | Active Record encryption keys in production (04, 06) | Deploy precondition, §12 step 2. The rehearsal proves adding keys to a database that had none keeps every WhatsApp check passing (§10) |

**No VERIFY is hidden:** every item of docs 00–22 is in these tables, and each open one names the real check that closes it (docs 13 §4, 17 §6, 22 §6).

## 10. Deploy and rollback rehearsal on the final image

`e2e/results/phase6/rehearsal/` (script `rehearsal.sh`). "Production before the release" is the last approved image `lynomia/staging:4.18-e1cd4c53` on the Phase 4 pre-deploy backup.

| Step | What | Result |
|---|---|---|
| 0 | Production before the release: the previous image migrates the Phase 4 pre-deploy backup | exit 0; 184 migrations; WhatsApp harness 41/41 |
| 1 | Backup (`pg_dump -Fc`) | sha256 `123f71cc…22891a79` |
| 2 | Migrate with the new image; encryption keys added to the environment | exit 0 in **14 s**. 184 → 186 migrations, 0 down, 0 invalid indexes. WhatsApp `provider_config` fingerprints unchanged. The 2 Commerce tables created |
| 3 | Web and worker from the new image, HTTP smoke | `/app/login`, `/api`, `/super_admin/sign_in` and a Vite asset: 200. Unsigned `POST /webhooks/shopify_commerce`, `/webhooks/salla`, `/webhooks/zid/1`: **401**. Both OAuth callbacks without parameters: 302, no 5xx. Worker booted |
| 4 | Harness on the new image | WhatsApp 41/41, Lynomia 17/17, WhatsApp Business 54/54 |
| 5 | **Rollback B**: previous image on the migrated database, keys kept | 41/41 in **27 s**. Login 200. `POST /webhooks/shopify_commerce` answers 404 (the old code has no such route) |
| 6 | **Rollback A**: restore the backup, then the previous image | 184 migrations, Commerce tables gone, fingerprints unchanged; 41/41 in **26 s** |
| 7 | Roll forward | exit 0; 186 migrations; 41/41 in 38 s |
| 8 | Direct path: the pre-4.18 backup migrated by the new image in one step | exit 0 in **15 s**; 186 migrations; 41/41 |
| 9 | **Commerce and provider switches** on the new image, with a real WooCommerce store | **19/19**: see the list after this table |
| 10 | UI smoke on the new image | **25/25**: see the list after this table |
| 11 | **Rollback B over live Commerce data** (1 connected store, Commerce on for a tenant) | previous image 41/41; `/app/login` and `/api` 200. Its only log errors are the `RoutingError` for the Commerce webhook route |

Step 9 checks:
- after the deploy, no account has Commerce and only WooCommerce is offered;
- Commerce API 401 while Commerce is off;
- a real store connects, with no credentials in the response;
- `ZID_ENABLED` on/off changes only the offer, and the WooCommerce store keeps reading;
- after the emergency off for every account: Commerce 401, the store and its encrypted credentials kept;
- switching back on restores reading;
- WhatsApp inbound and agent reply at each of five steps.

Step 10 checks:
- login and WebSocket;
- Calls hidden;
- the WhatsApp Business option;
- no `api_key` in the inbox API;
- the subscription page;
- no page errors;
- the Super Admin pages, including Salla, Zid and Shopify Commerce: secrets are password fields, and the stored secrets are absent from the page.

Three first runs were repeated, and none was a product failure:
- **Commerce switches, first run 18/19.** The check re-enabled Commerce on a stale in-memory account, so nothing was saved and the API correctly kept answering 401. The check was fixed (`1f0b037ff`, reload first) and passed 19/19.
- **UI smoke, first run 17/21.** The pre-deploy backup has no Super Admin, so those pages showed the sign-in page. A Super Admin was created as test data, and the script now fails any page that lands on sign-in.
- **E2E set.** The container was restarted during Zid, after Shopify had passed 64/64. The whole set was run again in one pass: 64/64, 49/49, 41/41, 47/47 (`e2e_runner.log`).

## 11. Readiness matrix

| Area | WooCommerce | Salla | Zid | Shopify |
|---|---|---|---|---|
| Real UAT on the final build | **PASS** (real stores, 41/41) | BLOCKED | BLOCKED | BLOCKED |
| Simulated E2E on the final build | n/a | 47/47 | 49/49 | 64/64 |
| Open VERIFY items | 0 | S1–S9, S14, S15 | Z1–Z17 | H1–H10 |
| Provider-side prerequisites | none | No Salla Partner app created | No Zid Partner app created | No Commerce app created; protected customer data **not approved** |
| Cross-tenant / matching / cache / tracking | PASS (gate spec) | PASS (gate spec) | PASS (gate spec) | PASS (gate spec) |
| Credential leaks | 0 | 0 | 0 | 0 |
| Emergency switch | Commerce feature (account) | `SALLA_ENABLED` | `ZID_ENABLED` | `SHOPIFY_COMMERCE_ENABLED` |
| **Verdict** | **GO** (pilot) | **NO-GO** | **NO-GO** | **NO-GO** |

**Overall: PARTIAL GO.**

## 12. Production deployment procedure (do not run before approval)

This builds on `../chatwoot-upgrade/07-production-gate.md` §3.
- If production already runs the approved 4.18 release (`e1cd4c53`), this release adds 2 migrations.
- If production is still on 4.14, run that procedure with **this** image instead: its pre-checks and checks all apply, and the migrate step runs both sets. The rehearsal's direct path (§10 step 8) covers it.

1. **Build and record.**

   ```bash
   git checkout <release-sha>          # f842e12ec, or a later docs-only commit
   docker build -f docker/Dockerfile -t <registry>/lynomiachat:<release-sha> .
   docker push <registry>/lynomiachat:<release-sha>        # record the digest
   docker run --rm <registry>/lynomiachat:<release-sha> sh -c 'cat .git_sha; ls custom/app/services/commerce >/dev/null && echo commerce-ok'
   ```

   Record the running image as `<previous-image>`.
2. **Secrets and switches, before starting anything.**
   - `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `…_DETERMINISTIC_KEY` and `…_KEY_DERIVATION_SALT` must be set for web **and** worker. If production has none yet, generate them once (`bin/rails db:encryption:init`) and keep them in the secret store. **Never remove or change them afterwards**: rows encrypted with them become unreadable without them.
   - `COMMERCE_TRUSTED_STORE_HOSTS` must be **unset** in production.
   - `SALLA_ENABLED`, `ZID_ENABLED` and `SHOPIFY_COMMERCE_ENABLED` stay **false** (their default). Leave their client ids and secrets empty.
3. **Read-only pre-checks:**
   - `SELECT max(version), count(*) FROM schema_migrations;`
   - WhatsApp `provider_config` fingerprints (07 §3 step 2).
4. **Maintenance window:** stop web, drain Sidekiq (queues and retry set empty), stop workers.
5. **Backup and restore proof:**

   ```bash
   pg_dump -Fc "$DATABASE_URL" -f pre_commerce.dump && sha256sum pre_commerce.dump
   ```

   Restore it on another host once.
6. **Migrate** with the new image (`POSTGRES_STATEMENT_TIMEOUT=0 bundle exec rails db:migrate`). Then check:
   - invalid indexes → 0;
   - `schema_migrations` +2, latest `20260930100100`;
   - fingerprints unchanged;
   - `commerce_stores` and `commerce_customer_links` exist and are empty;
   - no account has Commerce: `bundle exec rails runner "p Account.all.count { |a| a.feature_enabled?('lynomia_commerce') }"` → 0.
7. **Assets:** inside the image (Vite manifest, 298 assets). Nothing to run.
8. **Start** web and worker from the new image.
9. **Smoke (§10 step 3):**
   - `/api` ok; login, Super Admin and WebSocket work;
   - Super Admin → Salla, Zid and Shopify Commerce pages show the switches **off**, with secrets as password fields;
   - `POST /webhooks/shopify_commerce`, `/webhooks/salla` and `/webhooks/zid/1` unsigned → 401;
   - send and receive on one WhatsApp number.
10. **WooCommerce pilot, the provider smoke:**
    1. Enable `lynomia_commerce` for one Lynomia-owned account.
    2. Connect one real HTTPS WooCommerce store with Read keys.
    3. Open a conversation of a known customer: orders appear, and "Refresh" works.
    4. Disconnect and reconnect once.
    5. Wrong keys → "Check the keys".

    Only then enable the feature for customer accounts, through their plans.
11. **Monitoring, 24 h:**
    - `[Commerce]` log lines; `commerce.*` audit events;
    - 401/422/500 rates on `/api/v1/accounts/*/commerce/*` and `…/conversations/*/commerce/*`;
    - Sidekiq retries of `Commerce::*` jobs;
    - Redis memory for `COMMERCE::*` keys (24 h TTL);
    - plus the WhatsApp items of 07 §3 step 8.

A provider is switched on only after its real UAT is passed on a later gate. Its switch is the last step of that gate, not of this deploy.

## 13. Rollback procedure

| Situation | Action | Proven |
|---|---|---|
| One provider misbehaves | Super Admin → that provider → switch off. Takes effect on the next request (the config cache is cleared on save). Its stores disappear from settings and conversations; no call is made to it. Tokens and links are kept; switching back on restores them. Chatwoot channels are not touched | Gate spec (§6); rehearsal §10 step 4 (`ZID_ENABLED`) |
| Commerce misbehaves | Switch the feature off for every account: `bundle exec rails runner "Account.find_each { \|a\| a.disable_features!('lynomia_commerce') }"`. **Also remove `lynomia_commerce` from every billing plan**, or the next plan sync re-enables it. Commerce API → 401, the panel is hidden; conversations, WhatsApp and every channel keep working. Store rows and encrypted credentials are kept; enabling again restores everything | Rehearsal §10 step 4; gate spec |
| Code must go back, data kept | Start `<previous-image>` on the migrated database; the two Commerce tables are ignored by the old code. **Keep the encryption keys** | Rehearsal §10 step 5 |
| Full release rollback | Stop web and worker; restore `pre_commerce.dump` into a fresh database; start `<previous-image>`; check `/api`, login, one WhatsApp send/receive. Loses data written since the deploy | Rehearsal §10 step 6 |
| Roll forward after a rollback | Migrate again with the new image; start it | Rehearsal §10 step 7 |

## 14. What each NO-GO provider needs before a later gate

| Provider | Needed |
|---|---|
| Salla | Public HTTPS staging on this image. A Salla Partner app in Easy Mode with the webhook URL, Signature strategy and the settings field. A demo store. Then doc 13 §4 steps 1–7, closing S1–S9, S14 and S15. Any code change only where real evidence differs, then rerun that provider's specs and E2E on a new final build |
| Zid | Public HTTPS staging. A Zid Partner app with the callback and scopes. A test store. Then doc 17 §6 in order, stopping at the first mismatch (STOP 1: `state`; STOP 4: no per-webhook credentials) |
| Shopify | Public HTTPS staging. The Lynomia Commerce app deployed from `shopify.app.toml.example`. A development store. Then doc 22 §6, and **Shopify's protected customer data approval** (Level 1 + Email + Phone) before any production store |
