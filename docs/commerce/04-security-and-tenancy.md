# Lynomia Commerce: security and tenancy

## 1. Tenant and store ownership

```text
Account (tenant)
└── Commerce::Store  (account_id NOT NULL; unique (provider, external_store_id) installation-wide)
    ├── status: active | disabled | needs_reauth | disconnected
    ├── encrypted credentials (per store)
    └── Commerce::CustomerLink  (account_id = store.account_id = contact.account_id)
```

- **Multi-store:**
  - An account can have any number of stores, across providers and within one provider (Tenant A: Salla ×2 + WooCommerce + Shopify).
  - The only cap is the optional plan limit `stores`.
- **One owner per store:**
  - A store (for example a Salla merchant id or a myshopify domain) belongs to **exactly one** account at a time.
  - Connecting a store already owned by another account fails with a clear error. It must be disconnected there first.
  - This matches upstream's Shopify rule (`hook.rb:31-34`) and makes webhook routing unambiguous.
- **Scoping:**
  - Every API lookup goes through `Current.account.commerce_stores`.
  - Every job receives `store_id` and re-loads the store, checking its `account_id` (`Current` is thread-local, `lib/current.rb`).
  - A link is valid only if `link.account_id == store.account_id == contact.account_id`, enforced by a model validation.
- **Enable/disable per store:**
  - An admin can **disable** a store: credentials are kept, it is hidden from the panel, and its webhooks are acknowledged but ignored.
  - Or **disconnect** it: the provider revoke is attempted, then credentials, links and cache are deleted.
- **Per provider:** a global switch `COMMERCE_<PROVIDER>_ENABLED`. **Per account:** the feature flag `lynomia_commerce`, which plans can grant.

## 2. Secrets

- **Store credentials:**
  - One `encrypts :credentials` JSON column, holding for example: Salla access + refresh token; Zid authorization + manager token + refresh; Shopify access + refresh; WooCommerce key + secret + our webhook secret.
  - **Never** serialized, never logged, never sent to the browser.
  - **Connecting fails if `Chatwoot.encryption_configured?` is false** (loud failure, no plaintext fallback). The production gate must confirm the `ACTIVE_RECORD_ENCRYPTION_*` keys are set.
- **App credentials** (Salla/Zid/Shopify client id and secret, Salla webhook secret):
  - `installation_config.yml` entries with `type: secret`, write-only in Super Admin since Phase 4.
  - The existing `filter_parameters` (`:secret`, `_key`, `token`) keep them out of request logs.
- **Rotation:**
  - Refresh-token rotation happens under a per-store Redis lock (`Redis::LockManager`/`MutexApplicationJob`).
  - The new pair is written in one `UPDATE`, **before** the new access token is used.
  - On `invalid_grant` the store is marked `needs_reauth` and admins get the `Reauthorizable` email. Salla, Zid and Shopify all rotate or invalidate the old refresh token, so a lost update means the merchant must reinstall.

## 3. Outbound calls

- **Merchant-supplied hosts (WooCommerce `home_url`):**
  - Only HTTPS.
  - Resolved and checked through `SafeFetch` (`lib/safe_fetch.rb`): no private, loopback or link-local addresses, and the check is repeated on every redirect.
  - The URL is normalized once at connect time and stored in `external_store_id`.
- **Fixed hosts:** Salla `api.salla.dev`, Zid `api.zid.sa`, Shopify `{shop}.myshopify.com`. The Shopify shop must pass `Shopify::ShopDomain` validation **before** any request.
- **Limits and retries:**
  - Timeouts: connect 3 s, read 8 s.
  - At most 1 retry on 5xx or timeouts, and only from jobs.
  - `429` is honoured through `Retry-After` / `X-RateLimit-*` (Salla) or `throttleStatus` (Shopify).

## 4. Webhook design

### 4.1 Routing

Follows the existing `/webhooks/<provider>` convention (`config/routes.rb:672-682`):

```text
POST /webhooks/commerce/salla                    app-level, HMAC with SALLA webhook secret, store = payload.merchant
POST /webhooks/commerce/shopify                  app-level, HMAC with commerce Shopify client secret, store = X-Shopify-Shop-Domain
POST /webhooks/commerce/woocommerce/:token       per-store secret HMAC, store = webhook_token (also cross-check X-WC-Webhook-Source)
POST /webhooks/commerce/zid/:token               per-store unguessable token (Zid documents no signature), store = webhook_token
```

- The upstream `/webhooks/shopify` stays with the upstream integration.
- `webhook_token` is 32 random bytes in URL-safe form, unique, and replaced after a Zid "broken webhook" recovery (Zid requires a new `target_url`).

### 4.2 Verification (reject before any lookup side effect)

| Provider | Rule | On failure |
|---|---|---|
| Salla | `X-Salla-Security-Strategy` must be `Signature`; `X-Salla-Signature` = hex HMAC-SHA256(raw body, secret); `secure_compare`. The `Token` or `none` strategies are **rejected**. | 401 |
| Shopify | `X-Shopify-Hmac-Sha256` (also `Shopify-Hmac-Sha256`) = base64 HMAC-SHA256(raw body, client secret); `secure_compare` (the upstream implementation at `webhooks/shopify_controller.rb:30-42`) | 401 |
| WooCommerce | `X-WC-Webhook-Signature` = base64 HMAC-SHA256(raw body, **per-store secret we generated**). The unsigned creation ping (`webhook_id=<n>` form body) gets 200 with no processing. | 401 |
| Zid | Unknown `:token` → 404. Payload is treated as a **hint only**: the order is always re-fetched with the store's own tokens and payload data is never displayed directly. App lifecycle events carry a Partner Dashboard custom header secret. | 404 / 401 |

- **Unsigned events are never accepted** from a provider that offers signing.
- Missing secrets (misconfiguration) → 401 and an error log. It fails loudly.

### 4.3 Dedup, idempotency, replay

- **Dedup key per provider:**
  - Shopify `X-Shopify-Webhook-Id`;
  - WooCommerce `X-WC-Webhook-Delivery-ID`;
  - Salla `merchant:event:sha256(body)` (Salla's recommendation);
  - Zid `store:event:order_id:status:updated_at`.
- **Mechanism:** `Redis::Alfred.set(key, 1, nx: true, ex: 3.days)` (pattern `whatsapp/message_dedup_lock.rb`). A duplicate gets 200 and is ignored.
- **Idempotent handlers:** handlers only invalidate or refresh caches and set store status. Re-running one is harmless.
- **Stale events:**
  - Lifecycle events older than `store.connected_at` are ignored: Shopify `X-Shopify-Triggered-At` (as upstream does), Salla `created_at`.
  - Events are never trusted for ordering; data is re-fetched.
- **Speed:** respond 200 in under 1 s (Shopify allows 5 s). All work goes to `Commerce::WebhookJob` on the `low` queue, serialized per store with `MutexApplicationJob`.
- **Throttling:** a Rack::Attack rule for `/webhooks/commerce/*` per IP and per token. Today no webhook-specific rule exists (`rack_attack.rb:71`).

## 5. Permissions

| Action | Who | Mechanism |
|---|---|---|
| Connect, disconnect, enable, disable stores; edit store settings | **Administrator** | `Commerce::StorePolicy` (admin), same as `HookPolicy` and `InboxPolicy#create?` |
| See the Commerce panel for a conversation | Anyone who can view that conversation: admins, and agents with inbox access or a matching custom-role permission | `authorize conversation, :show?` (`conversation_policy.rb:10-12`) before any store call; store must be in `Current.account` |
| Search a store / create or remove a manual link | Admins; agents who can view the conversation; custom roles with `contact_manage` or `conversation_manage` | `Commerce::CustomerLinkPolicy`, audited |
| Send tracking link | Anyone who can reply in the conversation | It only inserts text into the existing reply editor; sending uses the normal message permissions |
| Anything that writes to the store (cancel, refund, status, edit) | **Not in MVP** | Needs its own permission and audit later |
| API-token callers | As above, plus `api_and_webhooks_enabled?` | Existing `Api::V1::Accounts::BaseController` |
| Billing | Accounts without a usable subscription get 402 on Commerce APIs as on all account APIs | `Billing::AccessGuard`. Webhooks are not blocked, so lifecycle events are still handled. |

## 6. Audit

- `Commerce::Store`: audited with `audited` (the gem at `Gemfile:184`, as the Enterprise audit modules do) for create, status changes and destroy. `credentials` is excluded from the audit.
- `Commerce::CustomerLink`: audited for manual link and unlink, and for reject.
- Webhook verification failures: an aggregated log line and a counter, never the payload.
- Tagged logs `[Commerce]`, `[Commerce:<provider>]`. Never tokens, raw payloads, phone numbers or emails; ids only.

## 7. Pre-condition: upstream Shopify OAuth callback flaw (found in Phase 1)

`app/controllers/shopify/callbacks_controller.rb` (identical to upstream v4.18.0):

1. **Line 51:** `site: "https://#{params[:shop]}"`. `shop` comes from the query and is not validated before the token exchange at lines 7-10. oauth2 2.0.22 sends `client_id:client_secret` by Basic auth, so **the Shopify client secret is sent to any host the caller names**.
2. **State:** the JWT (`app/helpers/shopify/integration_helper.rb:8-22`) has no `exp`, is reusable, and is not bound to a shop. Any account user, agents included, can mint one via `POST /integrations/shopify/auth` (`shopify_controller.rb:5,8-23`).
3. **No HMAC check** of Shopify's callback query, and no feature-gate check.

- **Impact:** once `SHOPIFY_CLIENT_ID` and `SHOPIFY_CLIENT_SECRET` are configured, a signed-in user of any account can exfiltrate the client secret. With it they can forge Shopify webhooks and impersonate the app.
- **Exposure today:** only if those settings are filled (the integration itself is off by default).
- **Fix:** a small upstream-file patch, done before any Shopify credential is configured.
  - Validate `params[:shop]` with `Shopify::ShopDomain` and bind it to the state.
  - Verify the callback `hmac`.
  - Add `exp` (10 min) and single-use (Redis `SET NX`).
  - Require admin on `auth`.
  - Check `Shopify::FeatureGate`.
  - The same state weakness exists in `Linear::IntegrationHelper` (no `exp`); lower impact, fix alongside.

## 8. Privacy and retention

- **Stored in Postgres:** only store connections and link rows with SHA-256 match digests. No orders, items or addresses.
- **Cache:** the Redis cache holds normalized order data (it includes names, items and, for some providers, the shipping city) for at most 24 h. It is purged on disconnect, uninstall and redact.
- **Shopify compliance topics** (Lynomia must honour them if it lists a public app):
  - `customers/redact`: delete links and cache for that customer;
  - `shop/redact`: delete the store, its links and cache;
  - `customers/data_request`: reply with what is stored (link rows only).
- **Masking:**
  - Candidate lists show masked phone and email until a link exists.
  - Agents without conversation access never trigger a store lookup.
- **Retention policy:** a document for Lynomia's data-processing terms (Saudi PDPL / GDPR-style obligations) is needed before production. This design keeps the stored footprint minimal. Not legal advice.
