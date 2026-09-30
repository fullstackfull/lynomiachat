# Lynomia Commerce: Shopify OAuth and expiring offline tokens (Phase 5)

Shopify is the fourth provider on the Commerce core, after WooCommerce (docs 07–09), Salla (docs 10–13) and Zid (docs 14–17). It reuses:
- the store model, `StoreConnection` ownership rules and customer links;
- the matcher, the cache, the panel, the permissions and the audit trail;
- the OAuth state of Zid, now shared (`Commerce::OauthState`);
- the token lifecycle of Zid, now shared (`Commerce::TokenManager`).

It is a **new, separate path**. The Chatwoot 4.18 Shopify integration stays as it is (doc 21).

This document covers how a Shopify store is connected and how its token is kept usable. The GraphQL provider is covered in doc 19, webhooks and the privacy topics in doc 20, coexistence with the legacy integration in doc 21, and the E2E in doc 22.

## 0. Sources

Shopify's documentation and API hosts are blocked by this environment's egress proxy. The contract below comes from:

| Source | What it gives | Version |
|---|---|---|
| **@shopify/shopify-api** (npm), Shopify's official Node library | Callback HMAC canonical form and 90 s timestamp window (`lib/utils/hmac-validator`, `processed-query`); code exchange with `expiring`, refresh grant, offline vs online session (`lib/auth/oauth/*`) | 15.0.0 |
| **shopify_api** (RubyGems), Shopify's official Ruby library | Callback signable string (`AuthQuery#to_signable_string`, form-encoded); supported Admin API versions | 16.3.0 |
| **@shopify/dev-mcp** (npm), Shopify's official developer MCP server | The published Admin GraphQL schemas `admin_2026-04/07/10.json.gz` with each type's required access; `supported-versions` (2026-07 = latest stable, 2026-10 = release candidate) | 1.16.0 |
| shopify.dev pages and the Shopify developer changelog, through web search | Expiring offline tokens (1 h access, 90 d refresh, mandatory for new public apps from 2026-04-01 and all public apps from 2027-01-01); refresh resilience (a repeated refresh returns the same pair for 1 h; the previous refresh token is kept until the new access token is used); webhook headers; app-specific webhook subscriptions and compliance topics in `shopify.app.toml`; protected customer data errors; GraphQL cost throttling | read 2026-09-30 |

Anything these do not settle is marked **VERIFY** and listed in §9. It is resolved in the real UAT (doc 22 §6).

## 1. Super Admin: Settings → Shopify Commerce

| Field | Type | Why it is here |
|---|---|---|
| Enable Shopify Commerce (`SHOPIFY_COMMERCE_ENABLED`) | boolean | The installation's provider switch. It is separate from the `lynomia_commerce` plan feature, and both are required to connect or read a Shopify store. It is also separate from the legacy `ENABLE_SHOPIFY_INTEGRATION`. |
| Shopify Commerce Client ID (`SHOPIFY_COMMERCE_CLIENT_ID`) | plain | The Lynomia Commerce Shopify app's client id. |
| Shopify Commerce Client Secret (`SHOPIFY_COMMERCE_CLIENT_SECRET`) | `secret` | Used only server-side: the token requests and the HMAC key of the OAuth callback and of webhooks. Write-only: masked, never rendered, a blank field keeps the stored value, filtered from logs. |

- The names are distinct from the legacy integration's `SHOPIFY_*` settings. Saving one page never changes the other, and the legacy Partner API validation (`shopify_partner_config_errors`) runs only for the legacy page (spec `super_admin/shopify_commerce_app_config_spec.rb`).
- There is no redirect-URL setting: it is always `<FRONTEND_URL>/commerce/shopify/callback` (`Commerce::Shopify::Config.redirect_uri`), allowed once in the app's configuration.
- No merchant token is ever stored in Super Admin.

### Which Shopify app: a dedicated app, not the legacy one

The legacy app's credentials are **not** reused. Reuse is not safe:

| Conflict | Legacy app | Commerce app |
|---|---|---|
| Callback | `/shopify/callback`, JWT state, `Integrations::Hook` | `/commerce/shopify/callback`, `Commerce::OauthState`, `commerce_stores` |
| Webhooks | App-level subscriptions to `/webhooks/shopify`, handled by `Webhooks::ShopifyController` (uninstall, shop redaction tied to hooks and billing) | App-specific subscriptions to `/webhooks/shopify_commerce` |
| Tokens | One installation per shop per app. A second authorization by the same app would hand the shop's token to whichever path ran last | Its own installation, so its own token |
| Token type | Non-expiring offline token, embedded app, `latest` API version | Expiring offline token, non-embedded, API pinned to 2026-07 |
| Billing | Partner API billing (`Shopify::PartnerClient`) | None |

So Shopify Commerce needs **its own Shopify app** (Partner Dashboard or `shopify app` CLI), with the settings in `docs/commerce/shopify.app.toml.example`.

## 2. Connect flow (OAuth 2.0 authorization code grant, server-side)

```
Admin: Settings → Commerce → Add store → Shopify → <shop>.myshopify.com → [Connect with Shopify]
  POST /api/v1/accounts/:id/commerce/shopify_connection { shop }
       (administrator, lynomia_commerce, Shopify Commerce enabled, encryption configured)
    shop: Shopify::ShopDomain (hardened in Phase 2): <name>.myshopify.com only, normalized (strip, downcase)
    shop already shown by this account's legacy integration → 422 STORE_ALREADY_CONNECTED (legacy_shopify_integration)
    → { authorize_url } + Set-Cookie lynomia_shopify_oauth (encrypted, HttpOnly, SameSite=Lax, Path=/commerce/shopify/callback, 10 min)
Browser → https://<shop>/admin/oauth/authorize?client_id=…&scope=read_customers,read_orders&redirect_uri=<FRONTEND_URL>/commerce/shopify/callback&state=…
         (no grant_options[]=per-user: an offline token)
Merchant approves → Shopify redirects to /commerce/shopify/callback?code=…&hmac=…&host=…&shop=…&state=…&timestamp=…
GET /commerce/shopify/callback  (Commerce::Shopify::CallbacksController)
  1. HMAC: Shopify signed this exact query (§4), timestamp within 90 s. Otherwise: nothing is touched, not even the state cookie → /app
  2. state: Commerce::OauthState.consume('shopify', state, cookie nonce): signature, expiry, one use, same browser → else /app
  3. shop: the signed `shop` equals the shop in the state → else /app
  4. account and user from the state only; user still an administrator (StorePolicy#create?), lynomia_commerce, provider enabled
  5. code present
  6. POST https://<shop>/admin/oauth/access_token {client_id, client_secret, code, expiring: "1"} (JSON, once, never retried)
  7. only an expiring offline token is accepted (§5); granted scopes ⊇ read_customers,read_orders and read-only (§7)
  8. GraphQL `shop { id name myshopifyDomain }` with the new token: id = gid://shopify/Shop/<n>, myshopifyDomain == shop
  9. under Commerce::StoreLock('shopify', <n>): new store through StoreConnection#attach, or new token for this account's own store
→ 302 <FRONTEND_URL>/app/accounts/:id/settings/commerce?shopify=connected | ?shopify_error=<CODE>
```

- **Store identity** is the numeric shop id from the shop GID (`external_store_id`), not the domain. `base_url` is `https://<myshopify domain>`, the only host any request for the store goes to. Metadata keeps `verified_at` only: the shop name is the store name, and nothing else is needed.
- **Ownership** is `StoreConnection#attach`'s (`claim`):
  - A shop connected to another account is never moved (`STORE_ALREADY_CONNECTED`). The token that attempt obtained is discarded, not stored.
  - A disconnected row is reused, or released to the new account.
  - The account's own store (active, disabled or needs_reauth) takes the new token in place, with its `base_url` refreshed. A disabled store stays disabled.
- **Installs started from Shopify** (App Store, a development-store install link) reach the callback without a Lynomia state and are refused. Stores are connected from Lynomia, where the account is known. The app's `application_url` should point merchants to the Lynomia dashboard.
- **Declined or failed authorization:** no code or a rejected code → `shopify_error=AUTH_INVALID`, nothing saved.

## 3. State

`Commerce::OauthState` (Zid's state, generalized per provider) answers "never trust query parameters alone for tenant ownership":

| Property | How |
|---|---|
| Signed | `Rails.application.message_verifier('commerce_shopify_oauth')`: a key derived from `secret_key_base`, purpose-bound per provider, so a Zid state is never accepted by the Shopify callback (and the reverse). Not signed with the Shopify client secret, which Shopify also knows. |
| Account-bound, user-bound | `account_id`, `user_id` in the payload; the account comes only from the state; the user is re-checked as an administrator at the callback. |
| Shop-bound | `shop` claim: the callback's signed `shop` must equal it. |
| Nonce-protected, single-use | 256-bit nonce; `COMMERCE::SHOPIFY::OAUTH_STATE::<sha256(nonce)>` in Redis for 10 min, deleted on first use. |
| Short-lived | 10 min in the signed message, the nonce and the cookie. |
| Browser-bound | The nonce is also in the encrypted HttpOnly cookie, compared in constant time; a state replayed from another browser (for example an agent's) is refused. |

The `code` and `state` parameters are filtered from request logs (exact-key match, `filter_parameter_logging.rb`).

## 4. Callback HMAC

`Commerce::Shopify::Oauth.valid_callback?`, the canonical form of Shopify's official libraries:
1. every query parameter except `hmac` and `signature`, each a single string (a repeated or nested parameter fails);
2. sorted by name, form-encoded (`URI.encode_www_form`, the same characters as `URLSearchParams`), with `+` written as `%20`;
3. HMAC-SHA256 with the **Commerce** client secret, hex, compared with `ActiveSupport::SecurityUtils.secure_compare`;
4. `timestamp` within 90 s of now.

It runs before the state is consumed, the code is read or anything is sent to the shop. An unsigned request does not even clear the browser's state cookie, so a forged callback cannot cancel an administrator's authorization in progress.

The canonical form is tested against a hand-written expected message, including `+`, `/`, `=` and spaces (`spec/services/commerce/shopify/oauth_spec.rb`). The E2E signs its callbacks with the same algorithm as `@shopify/shopify-api` (Node `URLSearchParams`), an independent implementation.

The legacy callback joins raw `k=v` pairs without encoding; it is left unchanged (doc 21).

## 5. Expiring offline token

Code exchange body: `{ client_id, client_secret, code, expiring: "1" }` (JSON, as the official library sends it). Refresh body: `{ client_id, client_secret, grant_type: "refresh_token", refresh_token }`. Both go to `https://<shop>/admin/oauth/access_token` through `Commerce::HttpClient#post_json_status`: once, never retried by the client, SSRF-filtered, no redirects.

`Commerce::Shopify::Tokens.credentials` stores only what Shopify returned:

| Stored (encrypted `commerce_stores.credentials`) | From |
|---|---|
| `access_token` | `access_token` |
| `access_token_expires_at` | now + `expires_in` |
| `refresh_token` | `refresh_token` |
| `refresh_token_expires_at` | now + `refresh_token_expires_in` |
| `scope` | `scope` |

- No lifetime is hard-coded: both expiry times come from Shopify's answer (spec: other values give other times).
- Refused as `INVALID_RESPONSE (shopify_tokens)`:
  - a response without `refresh_token`, `expires_in` or `refresh_token_expires_in` (a non-expiring token);
  - one carrying `associated_user` (an online token, bound to a staff member's session, unusable for background reads);
  - non-integer or non-positive lifetimes, empty strings.
- No new table: the token pair lives in the existing encrypted column. It never reaches the browser, logs, audit entries, the Redis order cache or error responses (specs and E2E scans).

## 6. Refresh lifecycle

`Commerce::Shopify::TokenManager` on the shared `Commerce::TokenManager`:

- **When.** The access token (about 1 h) is refreshed `REFRESH_BEFORE` = 5 min before its expiry, and when Shopify rejects it earlier (401).
- **Locking.** A refresh runs only under `Commerce::StoreLock.with('shopify', <shop id>)`:
  1. re-read the store;
  2. refresh only if still due;
  3. save the new access token, refresh token and both expiries in one write.

  Ten concurrent readers send one refresh (spec and E2E).
- **Retry rules (Shopify's, not Salla's).** Shopify documents two things: it returns the same new pair for a repeated refresh with the same refresh token for up to an hour, and it keeps the previous refresh token until the new access token is used. So:
  - A refresh that failed on a timeout, a network failure, a 5xx or an unreadable 200 is **sent again once, right away, with the same refresh token**. If that fails too, the tokens stay and the refresh waits `RETRY_AFTER` = 1 min. Meanwhile an unexpired access token keeps working. An expired one is an error, and stale data may be served (`STORE_UNAVAILABLE`/`TIMEOUT`/`INVALID_RESPONSE`).
  - A 429 is not resent right away.
- **Reauthorization.**
  - A refresh token past its own `refresh_token_expires_at` is not sent at all.
  - A refresh Shopify refuses (400/401: revoked by an uninstall, invalid) moves the store to `needs_reauth`: tokens and cached data are removed, and an administrator reconnects (Settings → Commerce → Reconnect, domain prefilled).
  - `invalid_client` means Lynomia's app credentials are wrong: `STORE_UNAVAILABLE (shopify_client_rejected)`, tokens kept.
- **Reactive 401.** One renew and one retry. Rejected again → `needs_reauth`. While a refresh has to wait after a 401 the error stays `AUTH_INVALID (shopify_refresh_pending)`, so **no stale order is shown over an auth failure**.
- **Audit:** `commerce.shopify.token_refreshed` (expiry change only), `commerce.shopify.needs_reauth` (reason).

## 7. Scopes and protected customer data

- **Requested:** `read_customers,read_orders`. Nothing else, and nothing that writes.
- **Why exactly these.** The published 2026-07 schema documents each type's access. Every type the connector touches needs only these two scopes (`docs/commerce/e2e/results/shopify_schema_validation.txt`):
  - `Order`, `LineItem`, `Fulfillment` and `FulfillmentTrackingInfo` need `read_orders`;
  - `Customer`, `CustomerEmailAddress` and `CustomerPhoneNumber` need `read_customers`.
  - `read_fulfillments` is therefore **not** requested.
- **`read_all_orders`** is not requested: Shopify returns the last 60 days of orders, enough for the last five orders of a conversation. Adding it later is a scope change plus Shopify's approval; the queries do not change.
- **Check at connect.** The granted scope must include both scopes and contain only `read_` scopes. An app configured with more is refused (`PERMISSION_DENIED (shopify_scopes)`) rather than used.
- **Protected customer data (PCD).** Reading customers needs Shopify's approval, in the Partner Dashboard (API access → Protected customer data access):
  - **Level 1**, access to the Customer object;
  - **Level 2**, the **Email** and **Phone** fields.
  - Name and Address are **not** requested and not queried.
  - Development stores work without review.
  - Until approved, Shopify answers `ACCESS_DENIED` ("This app is not approved to access the Customer object / to use the email field"). The connector reports `PROTECTED_DATA_NOT_APPROVED`, which the panel explains; it is never served from stale cache. Withheld (null) fields simply never match.
  - **No production-readiness claim is made before this approval.**

## 8. Files

- **Config and OAuth:**
  - `custom/app/services/commerce/shopify/{config,oauth,tokens,authorization,token_manager}.rb`
  - `custom/app/services/commerce/{oauth_state,token_manager}.rb` (shared with Zid)
  - `custom/app/services/commerce/http_client.rb` (`post_json_status`)
- **Controllers:**
  - `custom/app/controllers/api/v1/accounts/commerce/shopify_connections_controller.rb`
  - `custom/app/controllers/commerce/shopify/callbacks_controller.rb`
- **Routes and settings:**
  - routes: `config/routes/commerce.rb`
  - settings: `config/installation_config.yml`, `app/helpers/super_admin/features.yml`, `app/controllers/super_admin/app_configs_controller.rb`
- **Specs:**
  - `spec/services/commerce/shopify/{config,oauth,tokens,token_manager}_spec.rb`, `spec/services/commerce/oauth_state_spec.rb`
  - `spec/controllers/commerce/shopify/callbacks_controller_spec.rb`, `spec/controllers/api/v1/accounts/commerce/shopify_connections_controller_spec.rb`, `spec/controllers/super_admin/shopify_commerce_app_config_spec.rb`

## 9. VERIFY (to close in the real UAT)

Phase 6 classification of every item: doc 23 §9 (H-items).

1. The exact error body of a refresh with a revoked or expired refresh token (handled: any 400/401 except `invalid_client` → needs_reauth).
2. Whether re-running the authorization for a shop that already has the Commerce app installed invalidates the previous expiring token. It matters only when another Lynomia account tries a shop that is already connected; the attempt is refused and its token discarded.
3. The `timestamp` tolerance Shopify's own servers apply (the official libraries use 90 s; Lynomia uses 90 s).
