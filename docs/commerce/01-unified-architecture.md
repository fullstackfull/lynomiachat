# Lynomia Commerce: unified architecture (Phase 1 proposal)

Design goal: **one** commerce core with four thin provider connectors. The conversation UI only knows the normalized contract (`02-provider-contracts.md`).

## 1. Shape

```text
                               Lynomia Commerce (custom/ overlay)
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │  API (account-scoped)                   Webhooks (public, verified)          │
 │  /api/v1/accounts/:id/commerce/...      /webhooks/commerce/:provider[/:token]│
 │        │                                         │                           │
 │  Policies (Pundit)                        Commerce::WebhookReceiver          │
 │        │                                   verify → resolve store → dedup    │
 │  Commerce::OrdersQuery ◄── cache (Redis) ◄── invalidate/refresh (job)        │
 │        │                                         │                           │
 │  Commerce::CustomerMatcher ── CustomerLink        │                          │
 │        │                                         │                           │
 │  Commerce::Providers::Registry ──► Base ◄──────────┘                         │
 │        ├── Salla   ├── Zid   ├── Shopify   └── WooCommerce                   │
 │  Commerce::Store (encrypted credentials, status, ownership)                  │
 │  Commerce::CredentialRefresher (lock per store, atomic rotation)             │
 └──────────────────────────────────────────────────────────────────────────────┘
        ▲                                   ▲
   ContactPanel "Commerce" section     Settings → Stores (connect / list / disable)
```

## 2. Where it lives (minimal core touch)

- **Backend: everything in `custom/`, like Lynomia billing.** `custom/app/**` is eager-loaded (`config/application.rb:52-56`), and migrations come from `custom/db/migrate`. Layout:
  - `custom/app/models/commerce/`
  - `custom/app/services/commerce/` (core + `providers/<name>/`)
  - `custom/app/controllers/api/v1/accounts/commerce/`
  - `custom/app/controllers/commerce/` (OAuth callbacks, webhooks)
  - `custom/app/policies/commerce/`
  - `custom/app/jobs/commerce/`
  - routes in `config/routes/commerce.rb` with `draw :commerce`, like `draw :billing` (`config/routes.rb:781`).
- **Core files touched (small, additive):**
  - `ContactPanel.vue`: one `v-else-if` section.
  - `useUISettings.js`: one sidebar key.
  - `config/features.yml`: one appended flag.
  - `featureFlags.js`.
  - Settings routes and sidebar: one entry.
  - `en.json` / `en.yml` strings.
- **Upstream Shopify integration:** left in place, **disabled** (it is off by default), and patched for the callback flaw (`04` §7). Lynomia Commerce does not write to `integrations_hooks`.

## 3. Conversation UI: Option A vs Option B

| | A. Dashboard App (iframe) | B. Native ContactPanel section |
|---|---|---|
| Where it shows | A **tab** in the main conversation pane (`ConversationBox.vue:42-145`) | The conversation **sidebar**, next to contact attributes and the current Shopify orders (`ContactPanel.vue:286-301`) |
| Auth to Lynomia data | None. Context is posted to `'*'` without a signed token (`Frame.vue:112-123`), so it needs its own auth and backend. | The existing session and account scope, plus Pundit |
| Hosting | A separate app visible to users, with its own URL and deployment | Inside the product |
| "Send tracking" into the reply box | Not supported by the iframe protocol (context only) | Direct: insert into the reply editor, and the agent sends |
| Dark mode, RTL, i18n | Re-implemented | Inherited |
| Core change | None | One section block and one sidebar key |

**Recommendation: B, the native "Commerce" section in `ContactPanel`**:
- It follows the exact pattern upstream uses for `shopify_orders` and `linear_issues`, so it is a small, additive change.
- New keys in `DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER` reach existing users automatically (`useUISettings.js:38-55`).
- The section is draggable and collapsible like the others.
- Dashboard Apps stay available for merchants who want their own tools.
- **Later option, not MVP:** a Commerce tab on the contact page (`ContactManageView.vue:40-53`).

How the target panel maps onto existing UI:

```text
ContactPanel (existing)
├── Conversation actions / info / contact attributes ... (existing)
├── Commerce  ◄── new AccordionItem, key "commerce_orders", gated by feature flag + ≥1 enabled store
│   ├── Customer card (name, phone, store badge "Salla · Store 1")  ← normalized CommerceCustomer
│   ├── Last order card (#number, total+currency, payment badge, status badge, shipment + tracking)
│   ├── Buttons: View Order (admin_order_url) · Track Shipment (tracking_url) · Send Tracking (insert into reply)
│   ├── "More orders" list (last 5)
│   └── States: not matched → "Link customer" · several candidates → "Choose" · store error → retry
└── ... (existing sections)
```

## 4. Data strategy

| Option | Pros | Cons |
|---|---|---|
| A. Live lookup on every sidebar open | No duplicated data; always fresh | Slow when the provider is slow; hits rate limits (Zid 60 req/min, Salla per-plan, Shopify query cost); breaks when the provider is down |
| B. Local synchronized order database | Fast; searchable | A full e-commerce copy inside Chatwoot; sync bugs; PII duplication; big migrations; four sync engines |
| **C. Hybrid (recommended)** | Fast, fresh enough, resilient, minimal data | Cache invalidation logic |

**Hybrid, concretely:**

**Persisted in Postgres (small):**
- `commerce_stores`: the connection, with encrypted credentials.
- `commerce_customer_links`: contact ↔ external customer, per store.
- **No orders, items or addresses.**

**Cached in Redis (shared across hosts; `Rails.cache` is per-host in production):**
- Normalized order summaries per `(store, customer)`, key `commerce:v1:s:{store_id}:c:{customer_ref}:orders`, **fresh 120 s**.
- Order detail, key `commerce:v1:s:{store_id}:o:{external_order_id}`, **fresh 60 s**.
- Both are kept up to **24 h as a stale fallback**.
- Stale-while-revalidate:
  - the sidebar returns cached data immediately, tagged `stale: true, fetched_at`;
  - a `Commerce::RefreshOrdersJob` refreshes it;
  - the UI re-polls or receives an ActionCable update (existing account channel) later.
- If the provider fails, show the last known data with its age, or an error state.

**Invalidation:**
- **MVP:** TTL expiry plus a manual refresh button.
- **Later phase:** verified provider order webhooks (`order.updated`, `shipment.*`) delete or refresh the affected keys.

**Retention and privacy:**
- Only normalized fields are cached, never raw payloads.
- On disconnect, uninstall or redact, `SCAN`/`DEL` everything under `commerce:v1:s:{store_id}:*`.

## 5. Storage model (Phase 2; **not created now**)

### `commerce_stores`

| column | type | notes |
|---|---|---|
| `id` | bigint | |
| `account_id` | bigint, not null, FK | Tenant owner |
| `provider` | string, not null | `salla` \| `zid` \| `shopify` \| `woocommerce` |
| `external_store_id` | string, not null | Salla `merchant.id`, Zid `store_id`, Shopify `*.myshopify.com`, WooCommerce normalized `home_url` |
| `name`, `domain` | string | For display |
| `status` | integer enum | `active`, `disabled` (by admin), `needs_reauth`, `disconnected` |
| `credentials` | text, `encrypts` (JSON) | Provider-specific secrets; never serialized |
| `credentials_expires_at` | datetime | Access-token expiry, for proactive refresh |
| `webhook_token` | string, unique | Random, per store; used in URLs for providers without an app-level signature (Zid, WooCommerce) |
| `settings` | jsonb | Non-secret: tracking source (WooCommerce), order link template, scopes granted |
| `connected_by_id` | bigint | The admin who connected it |
| `connected_at`, `last_error_at`, `last_error`, timestamps | | |

**Indexes:**
- unique `(provider, external_store_id)`: a store belongs to **one** Lynomia account at a time, which also resolves webhooks unambiguously;
- `(account_id, provider)`;
- unique `webhook_token`.

### `commerce_customer_links`

| column | type | notes |
|---|---|---|
| `id` | bigint | |
| `account_id` | bigint, not null | Must equal the store's and the contact's account |
| `commerce_store_id` | bigint, not null, FK | |
| `contact_id` | bigint, not null, FK | |
| `external_customer_id` | string, nullable | Null for guest-only buyers (WooCommerce guests); the match key is then used instead |
| `match_method` | integer enum | `provider_id`, `verified_phone`, `verified_email`, `manual` |
| `match_key_digest` | string | SHA-256 of the normalized phone or email used (no raw PII duplicated) |
| `linked_by_id` | bigint, nullable | The user, for manual links |
| `state` | integer enum | `linked`, `rejected` (an agent said "not this customer"; suppresses auto-suggest) |
| timestamps | | |

**Indexes:** unique `(commerce_store_id, contact_id)`, and `(commerce_store_id, external_customer_id)`.
- One contact maps to at most one customer per store.
- One store customer may map to several contacts, for example one person on WhatsApp and on email who hasn't been merged in Chatwoot.

**Deliberately not stored:** orders, items, payments, shipments, addresses, customer names. All of them come live or from the cache.

## 6. Main flows

**Sidebar open:**
1. `GET /api/v1/accounts/:id/commerce/conversations/:conversation_id/orders`
2. `authorize conversation, :show?`
3. Load the enabled stores of the account.
4. For each store, `CustomerMatcher` resolves a link (stored link, then verified identifiers). If none is linked, return `match: none` or `candidates`.
5. `OrdersQuery` reads the cache, or calls the provider (one call per store, run in parallel with bounded threads, or sequentially with a small timeout).
6. Return normalized `CommerceCustomer` + `CommerceOrder[]` per store.

**Connect (admin):** Settings → Stores → Add → pick the provider, then:

| Provider | How it connects |
|---|---|
| OAuth (Salla, Zid, Shopify) | `OauthAuthorizationController`-style start with a signed GlobalID state (15 min, account-bound), then provider consent, then callback. The callback exchanges the code, fetches the store identity, and upserts `commerce_stores` under `account.with_lock`. |
| Salla Easy Mode | Tokens arrive in the app-level webhook `app.store.authorize`. The pending install is correlated through the merchant id and a short-lived Redis `SecureStorage` record created at connect time (the upstream `Shopify::PendingInstallation` pattern). |
| WooCommerce | `/wc-auth/v1/authorize` flow, with `scope=read`. The keys are POSTed to our HTTPS callback, which is correlated by the `user_id` we pass (a random one-time token). Manual key entry is kept as a fallback. |

**Webhook:**
1. `POST /webhooks/commerce/:provider[/:webhook_token]` (see `04` §4).
2. Verify.
3. Resolve the store.
4. Dedup.
5. Respond 200 fast.
6. `Commerce::WebhookJob` handles the lifecycle (uninstall → status `disconnected` + purge; authorize → store credentials) and, later, cache invalidation.

## 7. Feature gating and billing

- Add one account feature `lynomia_commerce`, appended at the end of `config/features.yml` with `column: feature_flags_ext_1`. It is not `chatwoot_internal`, so Lynomia plans can grant it (`BillingPlan.assignable_features`).
- Optional plan limit `stores` in `BillingPlan::LIMIT_KEYS`, modeled on `billing/inbox_limit.rb`.
- Provider app credentials go in `installation_config.yml` as `type: secret` entries, write-only in Super Admin, with a Super Admin group per provider. WooCommerce needs none.
- Per-provider on/off is a global config (`COMMERCE_<PROVIDER>_ENABLED`), so a provider can be switched off installation-wide without deploying.
