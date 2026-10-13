---
agent: 046
scope: Salla integration — app install correlation, scopes, token refresh, webhooks, capabilities, errors, Arabic/Gulf specifics
confidence: high
---

## 1. What the feature is

Salla is one of four Lynomia Commerce providers (`custom/app/services/commerce/providers.rb:3`). It is a
**permanently read-only** connector over Salla's Merchant API (`https://api.salla.dev/admin/v2`, fixed in code at
`custom/app/services/commerce/providers/salla.rb:13`) plus Salla's OAuth server
(`https://accounts.salla.sa`, `custom/app/services/commerce/salla/oauth.rb:4`). Only `GET` requests exist in the
adapter.

It installs as a **published Salla app in Easy Mode**: the merchant installs from the Salla App Store and Salla
pushes the store's tokens to Lynomia's webhook in `app.store.authorize`. There is no OAuth redirect, no
`/callback`, no `state` — unlike Zid and Shopify, which both have callback controllers. Because that event names
only a Salla `merchant` id and nothing Lynomia issued, the Lynomia account is proven separately by a **one-time
connection code** that the merchant pastes into the app's settings field `lynomia_connection_code` in their Salla
dashboard; Salla returns it, signed, in `app.settings.updated`
(`custom/app/services/commerce/salla/installation.rb:13,50-64`). The two events wait for each other for 7 days
under the merchant lock (`installation.rb:12,39,88-97`).

Capability declaration, against `custom/app/services/commerce/providers/base.rb`:

| Capability | Salla | Where |
|---|---|---|
| `enabled?` | `SALLA_ENABLED` global config | `salla.rb:18`, `salla/config.rb:11-13` |
| `supports_realtime?` | **true** | `salla.rb:47` |
| `registers_webhooks?` | **false** (inherited) — Lynomia never subscribes; the Partner Portal does | `base.rb:54` |
| `supports_carts?` | **true** (`carts.read`, `/carts/abandoned`) | `salla.rb:49-62` |
| `supports_actions?` | **false** (inherited) — no order action at all | `base.rb:66` |
| `searches_orders?` | **false** (inherited) — "Find an order" reports Salla not searchable | `base.rb:30`, `order_search.rb:30` |
| `write_access_problem` | `'unsupported'` (inherited) | `base.rb:70` |
| `admin_order_url(id)` | not implemented; the admin link is Salla's own `urls.admin`, kept only when https on `s.salla.sa` | `providers/salla/normalizer.rb:23,104-109` |
| `recovery_hosts` | store host + `salla.sa` + `.salla.sa` suffix | `salla.rb:68`, `recovery_url.rb:21-23` |

Reads: customers by Salla keyword search then **exact** re-check of E.164 mobile or lowercased email (names never
match, `salla.rb:31-40`); one page of 60 of the customer's orders sorted newest-first locally (`salla.rb:42-45`);
shipments per shown order (`salla.rb:101-104`).

## 2. Surfaces and routes

| Surface | Path |
|---|---|
| `POST/GET /api/v1/accounts/:account_id/commerce/salla_connection` | `config/routes/commerce.rb:12` → `custom/app/controllers/api/v1/accounts/commerce/salla_connections_controller.rb:17,21` |
| `POST /webhooks/salla` (the app's webhook URL) | `config/routes/commerce.rb:47` → `custom/app/controllers/webhooks/salla_controller.rb:7-19` |
| Webhook application | `custom/app/jobs/commerce/salla/webhook_job.rb:16-26` → `Commerce::Salla::Installation` / `Commerce::Realtime` |
| Connect dialog (Vue) | `app/javascript/dashboard/routes/dashboard/settings/commerce/SallaConnectDialog.vue` (polls every 5 s, `:23,72-84`) |
| Provider picker entry | `.../commerce/ProviderPicker.vue:34-37` |
| Store list, hints, disconnect copy | `.../commerce/Index.vue:31-36,102-108,144,174-178` |
| API client | `app/javascript/dashboard/api/commerce.js:11-21` |
| Super Admin settings | `config/installation_config.yml:464-487` (`SALLA_ENABLED`, `SALLA_APP_ID`, `SALLA_CLIENT_ID`, `SALLA_CLIENT_SECRET`, `SALLA_WEBHOOK_SECRET`), `:542` (`SALLA_ACTIONS_ENABLED`), `:566` (`SALLA_RECOVERY_ENABLED`) |
| Conversation panel (shared) | `custom/app/controllers/api/v1/accounts/conversations/commerce/stores_controller.rb:55` lists only `active` stores of enabled providers |

## 3. User-visible states

**Connect dialog** — one status line driven by `Commerce::Salla::ConnectionCode.status`
(`connection_code.rb:49-55`), rendered by `SallaConnectDialog.vue:44-56`:

| State | What the user sees | Produced by |
|---|---|---|
| `none` | nothing; only "Create connection code" | no progress row |
| `waiting` | "Waiting for the code from Salla…" | `create` (`connection_code.rb:23`) |
| `expired` | "This code expired. Create a new one." | `waiting` + `expires_at` past (1 h, `connection_code.rb:9,53`) |
| `claimed` | "Code received. Waiting for Salla to authorize the app…" | code redeemed (`connection_code.rb:40`) |
| `connected` | "Your Salla store is connected." + `connected` event, store list refetch | `installation.rb:96,100` |
| `conflict` | "This Salla store is connected to another … account." | `installation.rb:68-73` |
| `limit_reached` | plan store limit reached, store not connected, tokens keep waiting | `installation.rb:99-105` |

Polling stops on any non-pending state (`SallaConnectDialog.vue:76-79`). The code is rendered `dir="ltr"` in a
`<code>` element so the grouped ASCII code is not reordered in Arabic/RTL sessions
(`SallaConnectDialog.vue:158-164`) — the one place Salla's UI carries an explicit direction override.

**Store statuses** (`custom/app/models/commerce/store.rb:42`): `active | disabled | needs_reauth |
disconnected`. Salla is **not** in `REAUTHORIZED_HERE` (`Index.vue:34`), so a `needs_reauth` Salla store shows no
Reconnect button, only the hint "Salla needs to authorize the {installationName} app again…"
(`en/commerce.json:260`). A disconnected Salla store can be reconnected (`Index.vue:93-98`) but only by a fresh
install + code. With `SALLA_ENABLED` off: "Salla is turned off on this installation. The store is kept but not
read." (`en/commerce.json:261`) and Salla disappears from the picker and from conversations.

**Conversation panel** states are provider-neutral (`custom/app/services/commerce/conversation_panel.rb:63-78`):
`linked | not_found | suggested | multiple | unavailable`. Salla-specific consequences a user sees: payment always
reads "Payment not confirmed" unless Salla says pending (`normalizer.rb:74-76`), no order-actions menu, and
"Find an order" lists the Salla store as `unsupported` (`order_search.rb:30`). Under rate limiting the panel
serves its cached orders marked stale (`Commerce::Cache` `FRESH_FOR = 120.seconds`, `KEEP_FOR = 24.hours`,
`cache.rb:8-10`, fallback codes `:10`); with no cache entry it shows the error instead.

## 4. Errors and validation messages

Every Salla failure is one of the 30 `Commerce::Error` codes (`custom/app/services/commerce/error.rb:4-10`); the
UI only ever receives `code` plus a safe `reason`. Codes Salla can actually produce:

| Code | `reason` | Raised at | User-facing string (i18n key, `en/commerce.json`) |
|---|---|---|---|
| `AUTH_INVALID` | — | store identity ≠ connected store (`salla.rb:22`); `needs_reauth` or blank credentials (`token_manager.rb:32`); HTTP 401 (`http_client.rb:225`) | "The store rejected {installationName}'s credentials. An administrator needs to reconnect the store." `COMMERCE.ERRORS.AUTH_INVALID` (`:134`) |
| `AUTH_INVALID` | `refresh_interrupted`, `refresh_token_rejected`, `refresh_http_<status>`, `refresh_outcome_unknown`, `refresh_response_invalid` | `token_manager.rb:38,53,61,74,85-91` | same string; the settings page adds `COMMERCE.SETTINGS.SALLA.REAUTH_HINT` (`:260`) |
| `PERMISSION_DENIED` | `salla_write_scope` | any non-`offline_access`, non-`*.read` scope (`salla/tokens.rb:24-26`) | "The store refused access to its orders or customers…" `COMMERCE.ERRORS.PERMISSION_DENIED` (`:135`) — **never reaches a user**: raised inside the webhook job |
| `PERMISSION_DENIED` | `salla_missing_scope` | `REQUIRED_SCOPES` not all granted (`salla/tokens.rb:27`) | as above, same invisibility |
| `PERMISSION_DENIED` | `missing_scope` | `carts.read` not granted (`salla.rb:54-56`, `abandoned_carts.rb:61-63`) | as above |
| `PERMISSION_DENIED` | — | HTTP 403 (`http_client.rb:226`) | as above |
| `RATE_LIMITED` | — | `Commerce::Backoff.check!` for `COMMERCE::SALLA::MERCHANT::<id>::BACKOFF` (`salla.rb:114,123`, `backoff.rb:7`), HTTP 429 (`http_client.rb:228`), refresh 429 (`token_manager.rb:50`) | "The store is limiting requests. Try again in a moment." (`:136`) |
| `STORE_UNAVAILABLE` | `salla_unreachable`, `salla_client_rejected`, `not_sent`, `dns`, `http_5xx`, `tls`, `connection` | `token_manager.rb:51,59`, `http_client.rb:123,157,229,237` | "The store is not reachable right now." (`:133`) |
| `TIMEOUT` | — / `unknown_outcome` | `http_client.rb:125,161,205` | "The store took too long to answer." (`:137`) |
| `INVALID_RESPONSE` | `salla_user_info` | `merchant.id`/`name` wrong type (`oauth.rb:12`) | "The store sent a response {installationName} could not read." (`:138`) |
| `INVALID_RESPONSE` | `salla_tokens` | missing token field or non-bearer `token_type` (`salla/tokens.rb:15`) | as above (job-only) |
| `INVALID_RESPONSE` | `salla_merchant`, `salla_merchant_mismatch` | non-positive-integer `merchant` (`installation.rb:136`); `user/info` merchant ≠ event merchant (`installation.rb:37`) | as above (job-only) |
| `INVALID_RESPONSE` | `malformed_order`, `malformed_customer`, `malformed_shipment`, `malformed_cart`, `unexpected_shape`, `not_json`, `too_large`, `http_<status>` | `normalizer.rb:34,44,56`, `carts.rb:25`, `salla.rb:86,108,116`, `http_client.rb:204,219,230` | as above |
| `NOT_FOUND` | — | cart no longer listed (`salla.rb:65`); HTTP 404 (`http_client.rb:227`) | "This link request expired. Search again." (`:139`) — **wrong wording for a 404 order/cart** |
| `INVALID_STORE_URL` | `invalid`, `https_required`, `redirect`, … | `StoreUrl.parse(identity[:domain])` at connect (`installation.rb:110`, `store_url.rb:30-51`); any 3xx (`http_client.rb:224`) | "This store URL can't be used." (`:140`) (job-only at connect) |
| `PROVIDER_DISABLED` | — | `salla_connections_controller.rb:34` | "This store platform is turned off on this installation." (`:144`) |
| `ENCRYPTION_NOT_CONFIGURED` | — | `salla_connections_controller.rb:22` | "Store credentials can't be saved: encryption is not configured…" (`:142`) |
| `STORE_ALREADY_CONNECTED` | — | unique index race (`store_connection.rb:37`) | "This store is already connected." (`:143`) |
| `STORE_LIMIT_REACHED` | — | `store_connection.rb:31` → `limit_reached` progress | "You've connected all the stores your plan allows…" (`:165`); dialog shows `SALLA.STATUS.LIMIT_REACHED` (`:258`) |
| `RECOVERY_DISABLED` | — | `abandoned_carts.rb:58` (Salla recovery off by default + PRE_UAT) | "Abandoned carts are off for this store." (`:159`) |

Connection-code input validation is Salla-side only: `redeem` upcases and strips everything outside `A-Z0-9`
(`connection_code.rb:31`), so case, spaces and dashes are tolerated; a wrong or spent code produces **no user
message at all**, only `Rails.logger.warn` (`installation.rb:55`). The webhook returns a bare `401` with no body
for an unsigned, mis-signed, wrong-strategy or secret-less delivery (`webhooks/salla_controller.rb:12-15`).

## 5. Failure paths

**Token refresh is the dominant risk.** Salla refresh tokens are single-use; reusing one revokes the chain. The
manager refreshes when the access token expires within a day (`token_manager.rb:13,20-27`), under the merchant
lock, writing `metadata.refresh_started_at` before sending and never retrying (`:41`, `oauth.rb:19-23`,
`http_client.rb:58`). Only a 429 and a `401 invalid_client` are treated as provably unused and retried later
(`:50-51`); every other outcome — `invalid_grant`, any other 4xx/5xx, a lost answer, an unusable 200 body, or a
stale `refresh_started_at` from a crashed process — deletes the refresh token, sets `needs_reauth`, purges the
cache and audits (`:53,61,74,85-91`). The merchant must update or reinstall the app in Salla; nothing in Lynomia
can recover it.

**Silent dead ends in the install flow.** Three Commerce errors are raised inside `Commerce::Salla::WebhookJob`,
which only retries `STORE_UNAVAILABLE | TIMEOUT | RATE_LIMITED` and otherwise reports to Sentry
(`webhook_job.rb:6,22-26`). The merchant's dialog then polls forever on `waiting` or `claimed` with no
explanation:
- a token whose scope carries a write scope or lacks one of the four required ones (`salla/tokens.rb:24-27`);
- `user/info` returning a merchant id different from the event's (`installation.rb:37`);
- **`StoreUrl.parse(identity[:domain])` failing** (`installation.rb:110`). `Oauth.user_info` does not validate
  `domain` (`oauth.rb:11-14`), and doc 10 §Limitations records the shape of `domain` for stores without a custom
  domain as unverified. A `nil` or non-https `domain` therefore raises `INVALID_STORE_URL` after the code is
  already spent, leaving progress at `claimed` and requiring a new code.

**Missing installation config fails as a 500, not a Commerce error.** `Commerce::Salla::Config.required` raises
`KeyError` (`config.rb:28`). So with `SALLA_ENABLED` on but `SALLA_APP_ID` blank, `ConnectionCode.create` →
`Config.install_url` raises `KeyError`, which `rescue_from ::Commerce::Error` does not catch
(`salla_connections_controller.rb:13-15,24`): the administrator gets a 500 and the generic alert. The same holds
for a blank `SALLA_CLIENT_ID`/`SALLA_CLIENT_SECRET` during a refresh (`token_manager.rb:40`), which surfaces as a
500 on a conversation panel read. This is deliberate per CLAUDE.md ("fail loudly" for setup bugs) but it is
undocumented and indistinguishable from a bug to the person seeing it.

**Webhook secret drift.** `SALLA_WEBHOOK_SECRET` is installation-wide; rotating it in the Partner Portal without
updating Super Admin makes every delivery 401 (`webhooks/salla_controller.rb:8-15`), which silently stops
installs, uninstalls, re-authorizations and all realtime. Nothing in Lynomia surfaces this; only Salla's own
delivery log shows it.

**Realtime depends on manual Partner Portal subscription.** `supports_realtime?` is true (`salla.rb:47`) and
`order.*`/`shipment.*`/`abandoned.cart*` events are handled (`webhook_job.rb:13-14,30-44`), but
`registers_webhooks?` is false (`base.rb:54`), so Lynomia never creates the subscription. If an operator does not
subscribe the store events in the Partner Portal, Salla orders simply go stale on the 120 s / 24 h cache with no
error anywhere. `event_customer_ids` reads only `data.customer.id` and is marked `VERIFY(salla-store-events)`
(`salla.rb:70-80`); when it names nobody, **every** customer's cached orders for that store are dropped
(`realtime.rb:38`), which is correct but costs a full re-read.

**Uninstall ordering.** `app.uninstalled` disconnects the store and clears waiting tokens/claims
(`installation.rb:76-83`); an `app.store.authorize` arriving after it can leave 7-day waiting tokens that are
already revoked (doc 12 §8).

## 6. Permissions

| Gate | Where |
|---|---|
| Account administrator for create/read of the connection code | `authorize(::Commerce::Store, :create?)` `salla_connections_controller.rb:10`; `custom/app/policies/commerce/store_policy.rb:7` |
| `lynomia_commerce` plan feature | `salla_connections_controller.rb:29-31` (403 via `Pundit::NotAuthorizedError`) |
| `SALLA_ENABLED` installation switch | `salla_connections_controller.rb:33-35`; `salla/config.rb:11-13`; `providers.rb:11-13` |
| Active-record encryption configured | `salla_connections_controller.rb:22` |
| Agents see Salla data only through conversations they can access | `conversations/commerce/stores_controller.rb:49-55` |
| Order actions | blocked at `base.rb:66` → `order_actions.rb:104` `'unsupported'`; also `SALLA_ACTIONS_ENABLED` and `PRE_UAT` (`switches.rb:13-16,21-23,40`) |
| Abandoned carts / recovery | `SALLA_RECOVERY_ENABLED` default **false** + `PRE_UAT` unless ENV `COMMERCE_ALLOW_PRE_UAT_PROVIDERS` (`switches.rb:15-16,28-31,40`; `abandoned_carts.rb:19-21`) |
| Webhook endpoint | signature only, no session; 600 req/min per provider+IP (`config/initializers/rack_attack.rb:345-361`) |
| Salla OAuth scopes | `offline_access customers.read orders.read shipping.read`, write scopes refused and never stored (`salla/tokens.rb:7,22-28`) |

## 7. Contextual-help opportunities

| UI location | The question a user has there | Registry key that should link | Exists in `DOC_ARTICLES`? |
|---|---|---|---|
| `SallaConnectDialog.vue:220-223` | "How do I connect Salla?" | `commerceSalla` | **yes**, already linked (`documentationLinks.js:67`) |
| `ProviderPicker.vue:118` | "What will Salla actually give me?" | `commerceProviders` | **yes**, already linked |
| `Index.vue:104` / `en/commerce.json:260` (`REAUTH_HINT`) | "What does re-authorize in Salla mean and will I lose data?" | `commerceStoreReconnect` | key exists, **not linked here** |
| `Index.vue:103` / `:261` (`PROVIDER_OFF`) | "Who turned Salla off and what happens to my store?" | none fits | **no article** |
| `SallaConnectDialog.vue:54` / `:258` (`limit_reached`) | "Which plan allows how many stores?" | none | **no article** (only `docs/commerce/35-stores-on-plans.md`, not in the corpus) |
| `SallaConnectDialog.vue:48` / `:254` (`claimed` stuck) | "It says the code arrived but nothing happens" | would need a Salla troubleshooting article | **no article** |
| `CommercePanel.vue:415` with `PERMISSION_DENIED` | "Which permission, where?" | `commerceStorePermissions` (`documentationLinks.js:119`) | yes, but the article is key-oriented; for Salla the cause is an app scope the merchant cannot change |
| Order search `unsupported` entry (`order_search.rb:30`) | "Why can't I search this store?" | `commerceProviders` | key exists, no link at that surface |
| Super Admin Salla fields (`installation_config.yml:464-487`) | "Where do App ID / secrets / webhook URL come from?" | none | **no operator article** |

## 8. Current documentation coverage

| File | Coverage |
|---|---|
| `custom/db/documentation/en/commerce/connect-salla.md` (97 lines) | Good. Prerequisites, the 5 steps, a two-store worked example, roles, a "Limits" section that leads with the no-paid-status and no-order-actions facts, and seven named failure messages matching the real i18n strings. |
| `custom/db/documentation/ar/commerce/connect-salla.md` (90 lines) | Faithful translation, same structure and same seven failure messages. Keeps "Salla" in Latin script throughout. |
| `.../en|ar/commerce/commerce-provider-support.md` | Per-platform matrix with Salla columns; the payment-status and order-search limits restated (`:36-47`). |
| `.../en/troubleshooting/commerce-store-needs-reconnecting.md:31` | One Salla line: the app was uninstalled or its authorization lapsed; reinstall. |
| `.../en/troubleshooting/commerce-keys-cannot-do-that.md:31` | One Salla line: read-only by design. |
| `.../commerce/commerce-overview.md`, `customer-360.md` | Provider-neutral context, linked from the Salla article. |
| Design records (not in the corpus) | `docs/commerce/10-salla-install-correlation.md`, `11-salla-auth-and-token-lifecycle.md`, `12-salla-security.md`, `13-salla-e2e.md`; `docs/commerce-production/01,08`. Rich and accurate; none is merchant- or operator-facing. |

## 9. Missing or stale documentation

1. **No operator/Super Admin article for the Salla app at all.** The Partner Portal setup (public app, Easy Mode,
   webhook URL `https://<host>/webhooks/salla` with strategy **Signature**, the four scopes, the
   `lynomia_connection_code` settings field JSON, and the store-event subscription realtime needs) exists only in
   `docs/commerce/10` §"Salla Partners setup" and `13` §4. An operator who gets this wrong produces either 401 on
   every event or permanently stale orders, with nothing in the product explaining either.
2. **Nothing documents the stuck `claimed` state.** The one path with no recovery message — wrong scopes, merchant
   mismatch, unparseable `domain` — leaves "Code received. Waiting for Salla to authorize the app…" forever
   (§5). A stuck user has no article and no error.
3. **No article on the plan store limit**, although `limit_reached` is a first-class connection outcome with its
   own i18n string (`en/commerce.json:258,329`) and `docs/commerce/35-stores-on-plans.md` exists as a design doc.
4. **Arabic-specific behaviour is undocumented in both locales.** Salla returns Arabic store data; the connector
   deliberately reads machine-readable fields (`status.slug`, not `status.name`:
   `normalizer.rb:26`, fixture `spec/fixtures/files/commerce/salla/orders.json` has `"name": "تم التنفيذ"`,
   `"slug": "completed"`). So a merchant who renamed a status in Salla sees Lynomia's canonical status, not their
   own Arabic label — a predictable support question nothing answers. Conversely `courier_name` and item `name`
   are passed through as Salla returns them (`normalizer.rb:51,89`), so Arabic carrier and product names appear
   in the panel and in the tracking message inserted into the reply box.
5. **Currency and locale handling is undocumented.** Currency comes per order from Salla's
   `amounts.total.currency` (`normalizer.rb:78-81`; `SAR` in the fixtures) and is rendered with
   `Intl.NumberFormat(locale, { style: 'currency', currency })`, falling back to `"<amount> <currency>"` when the
   code is unknown (`commerceHelper.js:36-47`). Dates are normalized from Salla's
   `{ date, timezone: "Asia/Riyadh" }` to UTC (`normalizer.rb:119-122`, `carts.rb:36-41`) and then formatted in
   the viewer's UI locale (`commerceHelper.js:49-54`) — so an Arabic session renders Riyadh timestamps and SAR
   amounts in Arabic locale conventions, and an English session renders the same order differently. No article
   says so, and `docs/commerce/13` §Screenshots is the only record that Arabic/RTL was exercised at all (checks
   31-34).
6. **Phone matching is Gulf-shaped but unexplained.** Discovery uses the national significant number
   (`551112233` for `+966551112233`, `commerce/phone.rb:9-16`) because Salla stores `mobile` + `mobile_code`
   separately (`normalizer.rb:40`); matching then requires an exact E.164 hit. The panel hint says
   "international format (+966…)" (`en/commerce.json` `PANEL.SEARCH_HINT`), but nothing explains why a locally
   typed `0551112233` in a contact record will not match, which is the normal Saudi input form.

Stale/wrong wording found: `COMMERCE.ERRORS.NOT_FOUND` = "This link request expired. Search again."
(`en/commerce.json:139`) is also the message for a 404 order or a cart Salla no longer lists
(`salla.rb:65`, `http_client.rb:227`) — in those cases it is simply wrong.

## 10. Doc claims not proven by code

| Claim | Where claimed | What the code says |
|---|---|---|
| "**Abandoned carts are not available.** The feature is switched off for Salla and **cannot be turned on**." | `en/commerce/connect-salla.md` Limits; AR equivalent | Salla is the connector with the **most** cart support: `supports_carts?` true (`salla.rb:49`), a full `/carts/abandoned` reader and normalizer (`salla.rb:60-66`, `providers/salla/carts.rb`), `salla.sa` recovery hosts (`salla.rb:68`), cart events wired (`webhook_job.rb:14,38-44`) and a Super Admin switch (`installation_config.yml:566`). It is off because `SALLA_RECOVERY_ENABLED` defaults false **and** `PRE_UAT` gates it (`switches.rb:15-16,28-31`), and `uat_cleared?` is overridable by ENV `COMMERCE_ALLOW_PRE_UAT_PROVIDERS` (`switches.rb:40`). "Cannot be turned on" is a policy, not a code fact. |
| "Order actions on Salla, Zid and Shopify — **held until** each platform's writes are verified on a live store." | `en/commerce/commerce-provider-support.md:75` | Contradicts line 59 of the **same article** ("Salla has no order actions at all. None are implemented and none are planned.") and the code: `supports_actions?` is false by inheritance (`base.rb:66`) and `docs/commerce/29-salla` §5 states Salla stays read-only by design, not pending UAT. One of the two lines must go. |
| "While it is limiting, the section shows the last answer it got, labelled with the time, **instead of an error**." | `connect-salla.md` Limits; AR equivalent; `commerce-provider-support.md:95` | True only when a cache entry exists. `Commerce::Cache` serves a stale fallback for `RATE_LIMITED` (`cache.rb:10`) but entries are kept 24 h (`:9`); past that, or on a first read, the panel shows `state: 'unavailable', error: 'RATE_LIMITED'` (`conversation_panel.rb:26-27`). |
| "the store reconnects by itself, **with no new code**" after re-authorization | `connect-salla.md` / AR "إذا لم ينجح الأمر" | Confirmed: `installation.rb:40-42,115-121` reauthorizes a connected store in place. But it holds only while the store row is **not** `disconnected`; after a disconnect the merchant must reinstall and enter a new code (`en/commerce.json:291` says so in the dialog, the article does not). |
| "Guest checkouts are not matched." | `connect-salla.md` Limits | Consistent with the code — `find_customers` only reads `/customers` (`salla.rb:38`) and `Commerce::Customer` is built with `registered: true` (`normalizer.rb:41`) — but unverifiable against a live store, like everything else here. |
| doc 12 §7: "Customers API … its own tighter cap (500 per 10 minutes)" | `docs/commerce/12-salla-security.md` | No Salla-specific customers cap exists in code. There is one generic header-driven backoff keyed per merchant (`backoff.rb:12-16`, `salla.rb:114,120,123`). The number is from Salla's documentation, not from Lynomia's behaviour. |
| Every Salla payload shape | `docs/commerce/10` §Limitations, `11` §"Not yet verified", `13` §"REAL_SALLA_UAT = BLOCKED" | Honest and explicit: the fixtures are hand-authored (`docs/commerce-production/01-provider-capability-matrix.md:47`), Salla hosts are unreachable from this environment (proxy 403), and `VERIFY(salla-store-events)` is in the code itself (`salla.rb:70`). Any documentation written now must inherit that caveat; Salla is NO-GO in production (`docs/commerce/05-provider-capability-matrix.md:7`). |
