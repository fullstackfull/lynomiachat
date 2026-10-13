---
agent: 044
scope: Shopify integration — the canonical Lynomia Commerce Shopify path, and the precise current state of the retired legacy duplicate
confidence: high
---

## 1. What the feature is

Lynomia has **one** Shopify integration. It is a provider inside Lynomia Commerce, registered as `'shopify' =>
'Commerce::Providers::Shopify'` in the provider registry (`custom/app/services/commerce/providers.rb:4`) and as a
value of `Commerce::Store::PROVIDERS` (`custom/app/models/commerce/store.rb:30`). A merchant authorizes a dedicated
Shopify app — "Lynomia Commerce" — on their shop; Lynomia stores an **expiring offline** Admin API token in the
store's encrypted `credentials` column and reads customers, orders and fulfillments through the Shopify **Admin
GraphQL API**, pinned to `API_VERSION = '2026-07'` (`custom/app/services/commerce/shopify/config.rb:12`). There is
no REST path and no stored API key the merchant types.

A second, upstream-Chatwoot Shopify integration used to exist (Settings → Integrations → Shopify, with its own
Partner app, `/shopify/callback`, `/webhooks/shopify` and an `Integrations::Hook` row per shop). It was retired and
canonicalized; the design record is `docs/product-refinement/02-shopify-retirement.md`, and the record it reversed
is `docs/commerce/21-shopify-legacy-coexistence.md` (which now carries a `SUPERSEDED` header at `:3-15`). §10 of
this report states what still exists of it and what documentation must and must not say.

Three things are true of the canonical path and matter for every article:

- **No token ever reaches the browser.** The connect endpoint returns only an `authorize_url`; the code→token
  exchange is server-side (`custom/app/services/commerce/shopify/authorization.rb:15`).
- **Read-only by default.** A first connection asks exactly `read_customers,read_orders`
  (`config.rb:15`). `write_orders` is requested *only* on an administrator's explicit "Reconnect for order actions"
  (`config.rb:18`), and the callback refuses a grant that is not exactly what was asked
  (`authorization.rb:28-34`).
- **Two capabilities are built but unreachable in production.** Order actions and abandoned checkouts are both
  held by `Commerce::Switches::PRE_UAT` (`custom/app/services/commerce/switches.rb:16`), which lists `shopify`
  under both `:actions` and `:recovery`. No Super Admin switch overrides it; only the ENV-only
  `COMMERCE_ALLOW_PRE_UAT_PROVIDERS` does, and `switches.rb:10-11` says that is for staging and simulated E2E
  only.

## 2. Surfaces and routes

| Surface | Where | Citation |
|---|---|---|
| Settings → Commerce (store list, connect, reconnect, disable, disconnect) | `Index.vue` | `app/javascript/dashboard/routes/dashboard/settings/commerce/Index.vue:34,36,118-123,142-149,540-544` |
| "Add store" platform picker | `ProviderPicker.vue` | `.../commerce/ProviderPicker.vue:47-53` |
| Shopify connect / reconnect dialog | `ShopifyConnectDialog.vue` | `.../commerce/ShopifyConnectDialog.vue:34-48,86-93,104-112` |
| Conversation Commerce section (orders, order search, Customer 360) | `CommercePanel.vue` | `.../conversation/commerce/CommercePanel.vue:415` |
| Start authorization | `POST /api/v1/accounts/:account_id/commerce/shopify_connection` | `config/routes/commerce.rb:14`; `custom/app/controllers/api/v1/accounts/commerce/shopify_connections_controller.rb:22-32` |
| OAuth redirect URL | `GET /commerce/shopify/callback` | `config/routes/commerce.rb:60`; `custom/app/controllers/commerce/shopify/callbacks_controller.rb:14-23` |
| Webhook URI | `POST /webhooks/shopify_commerce` | `config/routes/commerce.rb:61`; `custom/app/controllers/webhooks/shopify_commerce_controller.rb:8-21` |
| Store list / update / destroy | `/api/v1/accounts/:id/commerce/stores` | `config/routes/commerce.rb:9` |
| Super Admin → Settings → Shopify Commerce | `config_key: 'shopify_commerce'` | `app/helpers/super_admin/features.yml:120-125`; `app/controllers/super_admin/app_configs_controller.rb:68` |
| Super Admin → Settings → Lynomia Commerce (actions/recovery switches) | `COMMERCE_CONFIGS` | `app_configs_controller.rb:55-58` |

Service layer: `Commerce::Shopify::Oauth` (`custom/app/services/commerce/shopify/oauth.rb`),
`::Authorization`, `::Tokens`, `::TokenManager`, `::Graphql`, `::ShopDomain`, `::SearchQuery`, `::Webhook`,
`::Config`; provider `Commerce::Providers::Shopify` with `::Actions`, `::Carts`, `::Normalizer`; job
`Commerce::Shopify::WebhookJob`.

The webhook path is rate-limited as an app-level (not per-store) path:
`COMMERCE_WEBHOOK_APP_PATHS = %r{\A/webhooks/(?<provider>salla|shopify_commerce)\z}`, 600/min default
(`config/initializers/rack_attack.rb:345-347`).

## 3. User-visible states

**Picker.** Every platform is listed so a merchant finds theirs; one the installation does not offer is rendered
disabled (`ProviderPicker.vue:54-57,85`). Shopify is offered only when `Commerce::Shopify::Config.enabled?`, i.e.
`SHOPIFY_COMMERCE_ENABLED` is true (`config.rb:21-23`, via `Commerce::Providers.enabled?`,
`providers.rb:11-13`).

**Store statuses.** `Commerce::Store` has exactly four: `active`, `disabled`, `needs_reauth`, `disconnected`
(`custom/app/models/commerce/store.rb:42`), labelled "Active", "Disabled", "Needs re-authorization",
"Disconnected" (`en/commerce.json` → `COMMERCE.SETTINGS.STATUS.*`).

**Connect round trip.** The browser leaves for `https://<shop>/admin/oauth/authorize` (`oauth.rb:14-18`) and
returns to `…/settings/commerce?shopify=connected` or `?shopify_error=<code>`
(`callbacks_controller.rb:36,38,49-51`); `Index.vue:158-172` turns that into a success or error toast and strips
the query. A callback that fails HMAC, state or shop-match redirects to `/app` and names no account
(`callbacks_controller.rb:15,19`) — the merchant simply lands in the dashboard with nothing changed.

**Order-actions row (per store).** `Commerce::OrderActions.store_status` is serialized as
`order_actions_status` (`custom/app/views/api/v1/accounts/commerce/stores/_store.json.jbuilder:14`) and computed
by `store_blocker` in this order: `unsupported` → `actions_disabled` → `provider_actions_disabled` →
`store_actions_off` → `write_access_problem` (`custom/app/services/commerce/order_actions.rb:103-110`). For
Shopify in production the third branch fires, because `Commerce::Switches.provider_actions_enabled?('shopify')`
is false through `PRE_UAT` (`switches.rb:16,22`). So the store row reads **"Order actions are switched off on
this installation."** (`Index.vue:227-229`), the toggle is hidden (it needs `available`, `Index.vue:448-451`) and
so is **"Reconnect for order actions"** (it needs `missing_scope`, `Index.vue:464-476`).
`ORDER_ACTIONS_MISSING_SCOPE` and `RECONNECT_FOR_ACTIONS` are therefore **strings a Shopify merchant cannot see
today**.

**Needs-reauth hint.** `COMMERCE.SETTINGS.SHOPIFY.REAUTH_HINT` — "Shopify needs you to authorize the
{installationName} Commerce app again. Use Reconnect." (`Index.vue:120-122`).

**Provider switched off.** `COMMERCE.SETTINGS.SHOPIFY.PROVIDER_OFF` — "Shopify is turned off on this
installation. The store is kept but not read." (`Index.vue:118-119`).

**Degraded read.** A `THROTTLED` answer, or a cost budget too low for another query like the last one, records a
backoff for the store (`custom/app/services/commerce/shopify/graphql.rb:44-51`; provider `backoff_key`,
`providers/shopify.rb:215,224`) and the panel serves its cache labelled with its time rather than failing
(`providers/shopify.rb:15-16`).

**Protected Customer Data not approved.** Shopify answers `ACCESS_DENIED` with a "not approved to use/access"
message; mapped to `PROTECTED_DATA_NOT_APPROVED` (`graphql.rb:11,62-65`). The store connects and reads orders but
customers cannot be matched.

## 4. Errors and validation messages

Every API refusal is `{ error: { code, reason? } }` (`custom/app/services/commerce/error.rb:22-24`), rendered 422
by the connect endpoint (`shopify_connections_controller.rb:18-20`). The UI maps `code` (and, for
`INVALID_STORE_URL`, `reason`) to a string and never shows a provider response
(`app/javascript/dashboard/components/widgets/conversation/commerce/useCommerceLabels.js:92-107`; `error.rb:1-2`).

| Code / reason | i18n key | String (EN) | Raised at |
|---|---|---|---|
| `INVALID_STORE_URL` / `shopify_domain` | `COMMERCE.URL_ERRORS.SHOPIFY_DOMAIN` | "Enter the store's myshopify.com domain, like your-store.myshopify.com." | `shopify_connections_controller.rb:26` |
| `ENCRYPTION_NOT_CONFIGURED` | `COMMERCE.ERRORS.ENCRYPTION_NOT_CONFIGURED` | "Store credentials can't be saved: encryption is not configured on this installation." | `shopify_connections_controller.rb:23` |
| `PROVIDER_DISABLED` | `COMMERCE.ERRORS.PROVIDER_DISABLED` | "This store platform is turned off on this installation." | `shopify_connections_controller.rb:41`; `callbacks_controller.rb:32` |
| `ACTIONS_DISABLED` / `provider_actions_disabled` | `COMMERCE.ERRORS.ACTIONS_DISABLED` | "Order actions are off for this store." | `shopify_connections_controller.rb:55` |
| `PERMISSION_DENIED` | `COMMERCE.ERRORS.PERMISSION_DENIED` | "The store refused access to its orders or customers. An administrator needs to check the store's permissions." | `callbacks_controller.rb:31`; `authorization.rb:33` (`reason: shopify_scopes`); `graphql.rb:64` |
| `AUTH_INVALID` / `shopify_authorization_denied` | `COMMERCE.ERRORS.AUTH_INVALID` | "The store rejected {installationName}'s credentials. An administrator needs to reconnect the store." | `callbacks_controller.rb:33` |
| `AUTH_INVALID` / `shopify_code_http_<status>` | same | same | `authorization.rb:16` |
| `AUTH_INVALID` / `shopify_shop_mismatch` | same | same | `oauth.rb:46` |
| `AUTH_INVALID` (token invalid for shop) | same | same | `providers/shopify.rb:64` |
| `INVALID_RESPONSE` / `shopify_tokens` | `COMMERCE.ERRORS.INVALID_RESPONSE` | "The store sent a response {installationName} could not read." | `custom/app/services/commerce/shopify/tokens.rb:10` |
| `INVALID_RESPONSE` / `shopify_shop` | same | same | `oauth.rb:42,45` |
| `INVALID_RESPONSE` / `unexpected_shape`, `graphql_error` | same | same | `graphql.rb:23,27,59`; `providers/shopify.rb:209` |
| `RATE_LIMITED` (THROTTLED) | `COMMERCE.ERRORS.RATE_LIMITED` | "The store is limiting requests. Try again in a moment." | `graphql.rb:55` |
| `STORE_UNAVAILABLE` / `shopify_internal_error` | `COMMERCE.ERRORS.STORE_UNAVAILABLE` | "The store is not reachable right now." | `graphql.rb:57` |
| `PROTECTED_DATA_NOT_APPROVED` | `COMMERCE.ERRORS.PROTECTED_DATA_NOT_APPROVED` | "Shopify has not approved {installationName} to read this store's customer data (email and phone) yet, so customers can't be matched." | `graphql.rb:64` |
| `NOT_FOUND` | `COMMERCE.ERRORS.NOT_FOUND` | "This link request expired. Search again." | `providers/shopify.rb:97,246` |
| `STORE_ALREADY_CONNECTED` | `COMMERCE.ERRORS.STORE_ALREADY_CONNECTED` | "This store is already connected." | `Commerce::StoreConnection` (unique index `(provider, external_store_id)`) |
| `STORE_LIMIT_REACHED` | `COMMERCE.ERRORS.STORE_LIMIT_REACHED` | "You've connected all the stores your plan allows…" | plan limit, `docs/commerce/35-stores-on-plans.md` |

`LEGACY_SHOPIFY_CONNECTED` / `reason: legacy_shopify_integration` **no longer exists** in code or in either
locale: the only surviving mention is a comment,
`app/javascript/dashboard/routes/dashboard/settings/commerce/specs/ShopifyConnectDialog.spec.js:166`.

Domain validation is `Commerce::Shopify::ShopDomain::FORMAT`
(`custom/app/services/commerce/shopify/shop_domain.rb:17`), which accepts `*.myshopify.com` and `*.myshopify.io`
(the development-store suffix, `:19`) and nothing else — no custom storefront domain, no scheme, port, path, query
or fragment. `:13-15` gives the product reason: a store may have several custom domains, so accepting one would
let the same store be connected twice.

Webhook refusals are HTTP-only, no body: bad HMAC → `401` plus a
`commerce.webhook.rejected` metric (`webhooks/shopify_commerce_controller.rb:10-13`); missing
`X-Shopify-Webhook-Id` or an invalid shop domain → `400` (`:17`); an unsubscribed topic → `200` and dropped
(`:26-27`).

## 5. Failure paths

**Authorization abandoned or finished in another browser.** The state nonce is also set in an encrypted, HttpOnly,
`SameSite=Lax` cookie scoped to the callback path (`shopify_connections_controller.rb:44-49`), and
`Commerce::OauthState.consume` requires it (`callbacks_controller.rb:17`). Finishing in a different browser, or
after `Commerce::OauthState::TTL`, lands the merchant on `/app` with no message at all. The dialog warns in
advance — `COMMERCE.SETTINGS.SHOPIFY.STEPS` — and the article covers it ("Shopify sent me back without
connecting"), but the **runtime gives no explanation**: this is the one connect failure with no on-screen text.

**Callback HMAC window.** `HMAC_TOLERANCE = 90` seconds (`oauth.rb:7`), checked before the signature
(`oauth.rb:25,51-53`). A badly skewed server clock silently breaks every connection with the same silent redirect.

**Merchant approves fewer scopes than asked.** `ensure_scopes!` requires every requested scope to be covered *and*
nothing granted beyond what was asked (`authorization.rb:28-34`), so a partial approval is `PERMISSION_DENIED` and
**an existing read-only connection is left untouched** — the store keeps working. A merchant who reads
"Reconnect Shopify to enable order actions" and then approves less gets a refusal that says "check the store's
permissions", which does not describe what happened.

**Token refresh.** Access token lives about an hour, refreshed `REFRESH_BEFORE = 5.minutes` before expiry
(`custom/app/services/commerce/shopify/token_manager.rb:13,19-21`). A timeout, network failure, 5xx or unreadable
answer is retried once immediately with the same refresh token (`:27-32`); if that fails the tokens stay and the
refresh waits `RETRY_AFTER = 1.minute` (`:14`). A refresh token past its own expiry sends no request at all and
goes straight to `needs_reauth` with reason `refresh_token_expired` (`:28`); a 400/401 (revoked by an uninstall)
raises `AUTH_INVALID` (`:42`). The store then shows **Needs re-authorization** plus `REAUTH_HINT`, and the status
change opens an operational incident (`custom/app/models/commerce/store.rb:61,69-70`).

**App uninstalled in Shopify.** `app/uninstalled` disconnects the store — token, customer links and cache removed
(`custom/app/jobs/commerce/shopify/webhook_job.rb:42-46`). It is ignored for a store authorized again after the
event was triggered (`:82-85`), which is what stops a late delivery from undoing a fresh reconnect.

**Compliance topics.** `customers/redact` deletes that customer's links and purges the cache; `shop/redact`
destroys the store row, links and cache; `customers/data_request` only records the link ids for the operator
(`webhook_job.rb:48-70`). All act only when the shop id in the **signed body** equals the store's
`external_store_id` (`:80`) — the headers are not signed. Contacts and conversations are never deleted (`:3`).
There is an operator export helper at `docs/commerce/ops/shopify_data_request_export.rb`.

**Shopify query-cost exhaustion.** Degrades to cache rather than failing (§3). The merchant sees a stale-labelled
panel; nothing tells them it is Shopify's cost budget.

**Order actions / abandoned checkouts.** Both are implemented (`providers/shopify/actions.rb`,
`providers/shopify/carts.rb`) and both are unreachable in production via `PRE_UAT`. The copy an administrator sees
("switched off on this installation") implies an operator could switch them on. They cannot:
`SHOPIFY_COMMERCE_ACTIONS_ENABLED` / `SHOPIFY_COMMERCE_RECOVERY_ENABLED` exist and are editable
(`config/installation_config.yml:554-559,578-583`) but have no effect while `PRE_UAT` lists `shopify`
(`switches.rb:22,30,39-41`). The installation-config descriptions do say so ("Has no effect while Shopify Commerce
is off, or before Shopify passes its real UAT"); the **merchant-facing** string does not.

## 6. Permissions

| Gate | What it controls | Citation |
|---|---|---|
| `lynomia_commerce` account feature | Commerce at all; without it the connect endpoint raises `Pundit::NotAuthorizedError` | `shopify_connections_controller.rb:36-38`; re-checked in the callback, `callbacks_controller.rb:31` |
| `Commerce::StorePolicy#create?` → `account_user.administrator?` | connect, rotate, disable, disconnect | `custom/app/policies/commerce/store_policy.rb:7-9`; `shopify_connections_controller.rb:15`; re-checked in the callback, `callbacks_controller.rb:44-47` |
| `SHOPIFY_COMMERCE_ENABLED` (installation) | whether Shopify is offered and read | `custom/app/services/commerce/shopify/config.rb:21-23`; `providers/shopify.rb:60` |
| `SHOPIFY_COMMERCE_CLIENT_ID` / `_CLIENT_SECRET` | required; absent ⇒ `KeyError`, a loud failure by design | `config.rb:25-27,34-36` |
| `COMMERCE_ACTIONS_ENABLED`, `SHOPIFY_COMMERCE_ACTIONS_ENABLED`, `PRE_UAT` | order actions | `switches.rb:13-16,19-24` |
| `COMMERCE_RECOVERY_ENABLED`, `SHOPIFY_COMMERCE_RECOVERY_ENABLED`, `PRE_UAT` | abandoned checkouts | `switches.rb:15-16,26-31` |
| Per-store administrator opt-in `settings['order_actions']` | order actions for that store | `order_actions.rb:107` |
| `Commerce::ActionPolicy` | which role may perform an action | `order_actions.rb:117-119` |
| Active Record encryption configured | a store cannot be saved without it | `custom/app/models/commerce/store.rb:47-48,81-83` |

The callback re-checks *everything* the state asserted (user still an administrator, account still has the
feature, provider still enabled) rather than trusting the signed state — `callbacks_controller.rb:31-32`.

## 7. Contextual-help opportunities

| UI location | The question a user has there | Registry key | Exists in `DOC_ARTICLES`? |
|---|---|---|---|
| `ShopifyConnectDialog.vue:115-118` | "How do I connect Shopify?" | `commerceShopify` | yes — `app/javascript/dashboard/helper/documentationLinks.js:69` |
| `ProviderPicker.vue:118` | "What does each platform support?" | `commerceProviders` | yes — `documentationLinks.js:65` |
| `CommercePanel.vue:415` | error-specific help, via `COMMERCE_ERROR_ARTICLES` | `commerceStorePermissions` for `PROTECTED_DATA_NOT_APPROVED`, `commerceStoreReconnect` for `AUTH_INVALID` | yes — `documentationLinks.js:110,121` |
| `ShopifyConnectDialog.vue:68-79` in `orderActions` mode (`ACTIONS_TITLE`/`ACTIONS_DESCRIPTION`) | "Why is Shopify asking for write access? what if I decline?" | would need a key; the dialog links only `commerceShopify` | **no dedicated key**; and the surface is unreachable today (§3) |
| `Index.vue:227-229` "Order actions are switched off on this installation." | "Who switches them on? can my operator?" | no link rendered at all | **no** |
| `Index.vue:118-119` `PROVIDER_OFF` | "Why is Shopify off? is my data gone?" | no link rendered | **no** |
| `Index.vue:120-122` `REAUTH_HINT` | "Why did it lose access?" | no link rendered; `commerceStoreReconnect` exists | key exists (`documentationLinks.js:74`), **not wired to this hint** |
| Super Admin → Settings → Shopify Commerce (`features.yml:120-125`) | "Which Shopify app? what redirect URL?" | Super Admin has no contextual-help registry | **no**; only the field `description` text |

## 8. Current documentation coverage

| File | Covers | Quality |
|---|---|---|
| `custom/db/documentation/en/commerce/connect-shopify.md` (98 lines) + `ar/` (92) | the whole canonical flow: prerequisites, steps, worked example, who can do this, limits, troubleshooting | **good**. `:11` states "This is Lynomia Chat's only Shopify integration" — no legacy path is taught anywhere. AR mirrors it (`ar/…:11`). Correctly states order actions and abandoned checkouts are unavailable and *cannot be switched on* (`:56-59,70`), which matches `PRE_UAT`. |
| `commerce/commerce-provider-support.md` | per-platform capability matrix incl. the Protected Customer Data condition (`:87`) and the 60-day window (`:97`) | good |
| `commerce/commerce-overview.md`, `commerce/customer-360.md` | what connecting a store gives; matching | adequate, Shopify mentioned once each |
| `troubleshooting/commerce-keys-cannot-do-that.md:27,34-37` | `write_orders` / `missing_scope`, protected customer data | good |
| `troubleshooting/commerce-store-needs-reconnecting.md:37` | Shopify reauth causes | good |
| `troubleshooting/commerce-store-address-refused.md:9` | says the address form is WooCommerce-only | correct |
| `integrations/integrations.md:88-89,94` + `ar/:82-83,88` | explicitly says WooCommerce/Salla/Zid/Shopify are **not** on the Integrations page and links `connect-shopify` | **correct now** — this is the fix for `MERGE_GATE.md §V2` |

The retirement's own documentation obligations (`02-shopify-retirement.md:264-282`, `MERGE_GATE.md:481`) are
discharged: every passage that taught the legacy path is gone from both locales.

## 9. Missing or stale documentation

1. **No operator documentation for `rails lynomia:shopify:legacy_audit`.** The task
   (`lib/tasks/shopify_legacy_audit.rake:66`) is the retirement's *deliverable* and the only record of where live
   legacy tokens are (`02-shopify-retirement.md:399-417`), yet `legacy_audit` appears nowhere in
   `custom/db/documentation/**` and nowhere in `docs/pre-deploy/**` (which contains **no** Shopify mention at
   all). An operator cannot find the three-step revocation order from any article.
2. **Nothing documents the retired-secret classification.** `InstallationConfig::RETIRED_SECRET_NAMES`
   (`app/models/installation_config.rb:42-46`) is the only thing keeping three stale credential rows off the
   generic Super Admin page. No article tells an operator it exists, why a stale row is invisible, or that the
   list is append-only (`:41`).
3. **"Order actions are switched off on this installation."** reads as operator-fixable and is not (§5). No
   article is linked from that row, and the string itself does not say "not available for Shopify yet".
4. **The silent callback failure** (wrong browser, expired state, clock skew) has article coverage
   (`connect-shopify.md:92-93`) but no in-product link, and the product shows no message at all.
5. **Nothing documents that `.myshopify.io` is accepted.** `shop_domain.rb:17,19` accepts the development-store
   suffix; `connect-shopify.md:18-19` and `COMMERCE.URL_ERRORS.SHOPIFY_DOMAIN` name only `myshopify.com`. Harmless
   for merchants, but a partner testing a dev store cannot learn it from the docs.
6. **`featureHelper.js:61` still maps `shopify` to an upstream Chatwoot help URL**,
   `https://chwt.app/hc/shopify` — the retired integration's upstream article. It is the non-branded fallback
   (`featureHelper.js:73-75`), so a Chatwoot-named installation would serve it. `featureFlags.js:40`
   (`SHOPIFY: 'shopify_integration'`) is likewise a retired-flag constant with no remaining consumer.

## 10. The retired path — current state, and what documentation must and must not say

### 10.1 What still exists

| Thing | State | Citation |
|---|---|---|
| `shopify_integration` account feature flag | **declared, `deprecated: true`** — deliberately not removed, because bit positions are persisted per column and deleting a line shifts every later bit | `config/features.yml:170-178`; rationale at `:174-177` and `custom/app/models/billing_plan.rb:49-62` |
| `InstallationConfig` rows for `SHOPIFY_CLIENT_ID`, `SHOPIFY_CLIENT_SECRET`, `SHOPIFY_PARTNER_ACCESS_TOKEN` | **values persist in the database** on any installation that configured legacy Shopify. `ConfigLoader` never deletes a row (`lib/config_loader.rb:40-55`), and the YAML declarations are gone | `app/models/installation_config.rb:31-46` |
| Those three names | **classified sensitive** by `RETIRED_SECRET_NAMES`, merged into `InstallationConfig.secret_names` | `installation_config.rb:42-46,70-73` |
| `Integrations::Hook` rows with `app_id = 'shopify'` | **not destroyed by the retirement**; readable, updatable, deletable | `app/models/integrations/hook.rb:22,31,33-34,84,110,121-122`; rule at `app/controllers/api/v1/accounts/integrations/hooks_controller.rb:49-60` |
| `Commerce::Shopify::ShopDomain` | relocated out of the legacy namespace and **kept** — it is the shop domain's one definition, and `Integrations::Hook` still validates a legacy `reference_id` against `FORMAT` so an unmigrated row stays valid | `custom/app/services/commerce/shopify/shop_domain.rb:1-17` |
| `rails lynomia:shopify:legacy_audit` | read-only report; selects four named columns, never `access_token`; prints `SAFE_TO_RETIRE` on zero rows | `lib/tasks/shopify_legacy_audit.rake:18-21,32,67-77` |
| `gem 'shopify_api'` | still in the Gemfile at version 14.8.0 with **zero** code references in `app custom lib config` | `Gemfile:213`; `Gemfile.lock:899` |
| `icon-shopify` | still in the Super Admin icon sprite — now used by the *Shopify Commerce* page | `app/views/super_admin/application/_icons.html.erb:177`; `app/helpers/super_admin/features.yml:124` |
| `docs/commerce/21-shopify-legacy-coexistence.md` | kept, with a `SUPERSEDED` header | `:1-15` |

### 10.2 What is disabled or gone

Verified absent from the working tree: `app/services/shopify/`, `app/controllers/shopify/`,
`app/controllers/webhooks/shopify_controller.rb`, `app/helpers/shopify/`,
`app/javascript/dashboard/routes/dashboard/settings/integrations/Shopify.vue`,
`app/javascript/dashboard/api/integrations/shopify.js`. `grep -i shopify config/routes.rb` →
no match. `grep -i shopify config/integration/apps.yml` → no match. No `SHOPIFY_CLIENT_*`,
`ENABLE_SHOPIFY_INTEGRATION`, `SHOPIFY_APP_STORE_URL`, `SHOPIFY_PARTNER_*` or `CHATWOOT_SHOPIFY_PLANS`
declaration remains in `config/installation_config.yml`. The only live references to the retired key names in
`app custom config lib` are the three entries in `RETIRED_SECRET_NAMES`.

Behavioural closures:

- `POST /api/v1/accounts/:id/integrations/hooks` with `app_id: 'shopify'` → **404**, deliberately *only* on
  `create`; `update` and `destroy` still work so an operator can clear a stale row
  (`hooks_controller.rb:4,45-47,49-61`).
- `GET /api/v1/accounts/:id/integrations/apps/shopify` → **404** (`RecordNotFound`), because `shopify` names no
  registered app (`apps_controller.rb:16-28`; asserted at `spec/models/integrations/app_spec.rb:131-136`). This
  was a 500 before the retirement forced the fix (`02-shopify-retirement.md:349-353`).
- `GET /api/v1/accounts/:id` no longer leaks the retired flag: the payload removes **every** deprecated feature,
  `json.features @account.enabled_features.except(*BillingPlan.deprecated_features)`
  (`app/views/api/v1/models/_account.json.jbuilder:36`). The retirement first shipped a
  `NameError`/500 here by deleting `Shopify::FeatureGate` while a jbuilder still referenced it
  (`02-shopify-retirement.md:302-345`); `spec/requests/accounts/deprecated_features_spec.rb` now guards it.
- The three retired keys are excluded from the generic Installation Configs listing *and* from its `show`, `edit`
  and `update` (Administrate resolves all four through the same scope):
  `resource_class.editable.where.not(name: InstallationConfig.secret_names)`
  (`app/controllers/super_admin/installation_configs_controller.rb:24-27`; asserted end to end at
  `spec/controllers/super_admin/retired_shopify_secrets_spec.rb:42-74`).
- No Super Admin form can write them: the `'shopify'` entry is gone from
  `SuperAdmin::AppConfigsController#allowed_configs` (`app_configs_controller.rb:63-82`) and `create` drops any
  key not in `@allowed_configs` (`:30`). A retired key POSTed to any config form is ignored and the stored value
  is unchanged (`retired_shopify_secrets_spec.rb:88-94`).
- Any retired-key *parameter* is filtered from logs by the generic patterns `:secret`, `:access` and the
  `/token/i` regex (`config/initializers/filter_parameter_logging.rb:5,19-22`).

### 10.3 What an operator sees today

- Super Admin → Settings lists **"Shopify Commerce"** and **"Lynomia Commerce"**. There is no "Shopify" page
  (`app/helpers/super_admin/features.yml:120-131`; `SuperAdmin::NavigationHelper#settings_pages`,
  `app/helpers/super_admin/navigation_helper.rb:6-15`).
- A **bookmarked** `/super_admin/app_config?config=shopify` still answers **200** and renders the *General*
  settings form under the heading **"Configure Settings - Shopify"**, because `allowed_configs` falls back to
  `general_configs` (`app_configs_controller.rb:82`) and the title is `@config.titleize`
  (`app/views/super_admin/app_configs/show.html.erb:1-8`). No Shopify field appears and no retired value is
  rendered (`retired_shopify_secrets_spec.rb:78-86`). It is confusing, not leaky.
- The generic Installation Configs list shows **no** Shopify credential row. It will, however, still show any
  *non-secret* retired row an operator once saved — `ENABLE_SHOPIFY_INTEGRATION`, `SHOPIFY_APP_STORE_URL`,
  `SHOPIFY_PARTNER_ORGANIZATION_ID`/`_APP_ID`/`_API_VERSION` — because those were never `type: secret` and
  `editable` only excludes `locked` rows. *Mechanism verified* (`config_loader.rb:48-55`,
  `app_configs_controller.rb:32` creates with `locked: false`, `installation_configs_controller.rb:26`);
  *presence on the live server unverified* — it needs a read of the production table, which Phase 1 must not do.
  `CHATWOOT_SHOPIFY_PLANS` was `locked: true` (`02-shopify-retirement.md:100`) so `editable` excludes it.
- `rails lynomia:shopify:legacy_audit` prints `legacy Shopify installations = 0` then `SAFE_TO_RETIRE` on
  production, which the product owner confirmed is the expected result
  (`shopify_legacy_audit.rake:69-77`; `02-shopify-retirement.md:168`). If rows ever appear it prints
  `LEGACY_RECORDS_FOUND` and refuses to recommend deletion without a human (`:103-108`).
- A merchant sees **nothing** of the legacy path: no Integrations entry, no sidebar order panel, no settings page.

### 10.4 What documentation must say

1. **One Shopify integration, named.** Lynomia Chat has exactly one, and it is **Settings → Commerce → Shopify**,
   using the Lynomia Commerce Shopify app. `connect-shopify.md:11` already says this; every Shopify-adjacent
   article should resolve to it.
2. **Shopify is not an "Integration".** It is a Commerce platform. `integrations.md:88-89` already states this
   and must keep stating it.
3. **Retired credentials are sensitive and invisible, and that is deliberate.** `SHOPIFY_CLIENT_ID`,
   `SHOPIFY_CLIENT_SECRET` and `SHOPIFY_PARTNER_ACCESS_TOKEN` may still hold values on an installation that once
   configured legacy Shopify. They are classified secret by name
   (`installation_config.rb:42-46`), hidden from every Super Admin surface, and writable by nothing. Documentation
   states that they are hidden; it never reproduces, echoes or exemplifies a value.
4. **The revocation order is the operator's, and the code cannot do it.** Deleting a Lynomia row removes *our*
   copy of a Shopify offline token and does not revoke it; revocation happens by uninstalling the legacy app in
   the shop's admin, or deleting the Partner app (`02-shopify-retirement.md:393-397,407-414`). The order is:
   audit → uninstall at Shopify → only then remove the row, by a named-id console `destroy`, never a migration.
5. **Nothing of the retirement destroyed merchant data.** No migration deletes hooks, drops a column or rewrites
   production (`docs/product-refinement/MERGE_GATE.md:83-91`).
6. **The feature flag stays declared.** `shopify_integration` is `deprecated: true` and must never be removed,
   because bit positions are persisted (`config/features.yml:174-177`).
7. **Capability honesty.** Shopify order actions and abandoned checkouts exist in code and cannot be enabled on
   this installation; Shopify reading additionally depends on Shopify's **Protected Customer Data** approval,
   which is an external dependency nothing in Lynomia can satisfy.

### 10.5 What documentation must not say

1. **Never render, echo, log or serialize a retired secret value**, nor publish a realistic example of one. The
   values in `spec/controllers/super_admin/retired_shopify_secrets_spec.rb:11-13` are fixtures and must not be
   copied into any article as a "format example".
2. **Never tell an operator how to read a retired key back.** In particular, never suggest adding a
   `'shopify'` entry to `SuperAdmin::AppConfigsController#allowed_configs`, re-declaring the keys in
   `config/installation_config.yml`, removing a name from `RETIRED_SECRET_NAMES`, or inspecting the row in the
   console. The generic app-config view renders any non-`secret`-typed key as a **plain text field with its
   value** (`show.html.erb:64-66`), so a re-added mapping entry would print the stored secret — the two defences
   are the mapping's absence and `RETIRED_SECRET_NAMES`, and neither is a "setting".
3. **Never re-declare the keys as tombstones in the YAML.** `ConfigLoader` creates a row for every declaration and
   with `reconcile_only_new: false` overwrites an existing value with the declaration's default — a tombstone
   would either resurrect the key as configuration or destroy the value it was meant to protect
   (`installation_config.rb:37-39`).
4. **No article may teach, mention as available, or link to the legacy Shopify integration**, its Super Admin
   page, `/shopify/callback`, `/webhooks/shopify`, `api/v1/accounts/:id/integrations/shopify`, the Shopify
   Partner/App-Store subscription path, or the legacy conversation order panel. All are gone.
5. **Never instruct a merchant to "disconnect it under Integrations first"** — that page 404s. The
   `LEGACY_SHOPIFY_CONNECTED` string that produced that instruction no longer exists.
6. **Never present a migration or re-authorization workflow as a product feature.** There is deliberately no
   migration UI and no transition process, because production has zero legacy stores
   (`02-shopify-retirement.md:170-175`).
7. **Never describe the legacy audit as a cleanup task.** It never deletes and there is no counterpart that does
   (`shopify_legacy_audit.rake:16`).
8. **Never say Shopify order actions can be turned on by an operator** on this installation.

## 11. Doc claims not proven by code

| Claim | Where asserted | Code | Verdict |
|---|---|---|---|
| The audit recommends one of `migrate`, `already_migrated`, `reauthorize` | `docs/product-refinement/02-shopify-retirement.md:222` | `recommendation_for` returns only `already_migrated` or `migrate` (`lib/tasks/shopify_legacy_audit.rake:59-63`), and the printed legend lists only those two (`:119-122`) | **wrong** — `reauthorize` is never produced. Minor, but it is in the retirement's own record |
| "The legacy Shopify integration keeps its own `/shopify/callback`" | `custom/app/controllers/commerce/shopify/callbacks_controller.rb:2` | that route does not exist (`grep -i shopify config/routes.rb` → no match) | **stale comment** |
| "The legacy Shopify integration keeps `/webhooks/shopify`, its own subscriptions and its own secret" | `custom/app/services/commerce/shopify/webhook.rb:3-4`; and "The legacy integration's `/webhooks/shopify` is separate", `custom/app/controllers/webhooks/shopify_commerce_controller.rb:2` | route gone | **stale comments** (×2) |
| "separate from the legacy Shopify integration and its `SHOPIFY_*` settings" | `custom/app/services/commerce/shopify/config.rb:2-3` | no `SHOPIFY_*` legacy declaration exists | **stale** |
| "separate from the legacy Shopify integration **above** (`SHOPIFY_*`)" | `config/installation_config.yml:510-511`; also "The legacy Shopify integration is not affected." (`:515`) and "not the legacy Shopify integration app" (`:520`) | nothing is "above"; `:515` is operator-visible field **description text**, not a comment | **stale, and one of them is rendered to an operator** |
| "the retirement reports installations for **re-authorization**" | `docs/commerce/21-shopify-legacy-coexistence.md:13-15` | the task emits `migrate`, whose legend does say reauthorization is required (`:119-120`) | consistent in substance, inconsistent in vocabulary |
| `FEATURE_FLAGS.SHOPIFY = 'shopify_integration'` is live | `app/javascript/dashboard/featureFlags.js:40` | no consumer anywhere in `app/javascript` | **dead constant** |
| `shopify` has a help URL | `app/javascript/dashboard/helper/featureHelper.js:61` | points at upstream Chatwoot's retired-integration article | **stale external link**, served on a non-branded install |
| Non-secret retired config rows are still listed in Super Admin | reasoned from `config_loader.rb:48-55` + `installation_configs_controller.rb:26` | mechanism verified; **presence on the live server unverified** | needs a production read, which Phase 1 forbids |

## 12. Not checked

- The live production `installation_configs` table (whether any retired Shopify row exists at all, secret or
  not), and the live `integrations_hooks` count. Both would require touching production data.
- Whether the legacy Shopify Partner app registration still exists at Shopify and still has `app/uninstalled` and
  the three compliance topics POSTing to a now-404 route. `02-shopify-retirement.md:419-424` records this as
  open and operator-owned; it is not observable from the repository.
- No spec, task or build was executed; every claim here is from reading files.
