# Lynomia Commerce: MVP, phases and implementation order

## 1. MVP (read-only; no financial or order mutations)

```text
Connect store (admin) → Match customer → Show orders → status · payment · items · total · shipping/tracking
→ Open order (admin link) → Track shipment (tracking link) → Send tracking link (insert into reply box; agent sends)
```

**Included**
1. Settings → Stores:
   - list, connect (per-provider flow), test connection, disable/enable and disconnect;
   - admin only;
   - several stores per account, from the same or different providers.
2. Conversation sidebar section **"Commerce"** in `ContactPanel`, gated by the `lynomia_commerce` flag and at least one active store:
   - per store: the matched customer, the last order (expanded) and up to 5 recent orders;
   - canonical status and payment badges, with the provider label shown as secondary text;
   - items (name, qty, total), total + currency;
   - carrier, shipment status and tracking number.
3. Buttons:
   - **View Order** opens `admin_order_url` in a new tab;
   - **Track Shipment** opens `tracking_url`;
   - **Send Tracking** inserts a localized text with the tracking URL into the reply editor. It does **not** auto-send, because the WhatsApp 24 h window and template rules still apply.
4. Matching as in `03`: stored link → verified phone → verified email → verified provider id → manual link (search by phone, email or order number), plus "not this customer".
5. Hybrid data (`01` §4):
   - live provider calls with a Redis cache (120 s fresh, 24 h stale fallback);
   - a refresh button;
   - error and stale states.
6. Security (`04`):
   - encrypted credentials (connect is refused without AR encryption);
   - account ownership;
   - conversation-level permission;
   - audit of store and manual-link changes;
   - lifecycle webhooks only (uninstall/authorize), verified.
7. i18n: `en.json` / `en.yml` only (Arabic via Crowdin). RTL-safe Tailwind; `components-next` style.

**Excluded from the MVP** (later, with separate permissions and audit):
- cancel, refund, change status, edit customer or shipment, create order;
- order-webhook real-time updates;
- abandoned carts;
- a Captain tool;
- a contact-page tab;
- cross-store order search;
- analytics.

## 2. Recommended provider implementation order

**Recommendation: build the core with WooCommerce first, then Salla → Zid → Shopify.**

Scores are 1 (poor) to 5 (best), taken from the evidence in `02`/`05`:

| Criterion | WooCommerce | Salla | Zid | Shopify |
|---|---|---|---|---|
| Already present in Chatwoot | 0 | 0 | 0 | Partial: reuse components, but the integration needs a security fix, multi-store, GraphQL and token work |
| Auth / token lifecycle complexity | **5**: static keys, no refresh | 2: 14-day token + single-use rotating refresh, Easy Mode via webhook | 2: two tokens + single-use refresh | 1: 1 h tokens + rotating refresh + migration before 2027-01-01 + gem 14.8 → 16.x (breaking) |
| API quality for our fields | 3: no core tracking, no phone customer search, derived payment status | **5**: customer search by mobile, shipments with tracking links, admin and customer URLs, signed webhooks | 3: rich order fields, but **unsigned webhooks** and several paths still VERIFY | 5: rich GraphQL, but PII needs approval and only 60 days of orders by default |
| Testability (real, not mocked) | **5**: a real WooCommerce in Docker, locally and in CI | 3: needs a Salla Partner account + demo store + network allowlist | 3: needs a Zid Partner account + test store + allowlist | 3: free dev stores, but production needs protected-data review and `read_all_orders` approval |
| External approvals / lead time | none | App review for public listing (a private app for pilots is possible) | Partner app review | **Protected customer data + `read_all_orders` review** |
| Reuse for later connectors | Builds the core, matching, cache, UI and HMAC webhooks | Builds OAuth + rotating-refresh infrastructure, reused by Zid and Shopify | Reuses Salla's refresh infrastructure | Reuses all of the above, plus upstream HMAC and `ShopDomain` |
| Market priority (Lynomia, Saudi) | medium | **high** | high | medium |

**Why WooCommerce is first:**
- The first connector defines the provider-neutral contract, the matching, the cache, the permissions and the sidebar.
- WooCommerce is the only provider that can be exercised **end to end against a real store** right away (a local Docker WooCommerce), with no partner approvals and no token lifecycle.
- Its weak spots (missing tracking and payment status, guest customers) force the normalized contract to handle missing data properly from day one.

**Why Salla is next:**
- It is the highest-value market connector.
- It adds the OAuth, rotating-refresh and signed-webhook infrastructure that Zid and Shopify then reuse.

**Why Zid is third:**
- It needs its webhook authentication and the exact filter semantics verified (both **VERIFY**), because its docs were not reachable here.

**Why Shopify is last:**
- It needs the upstream security fix, gem 16.x and a GraphQL rewrite, plus Shopify's app reviews.
- It must be done **before 2027-01-01** only if Lynomia wants Shopify at all.

**Alternative (if Salla must ship first for business reasons):**
- Salla-first is feasible if the Salla Partner app, a demo store and a network allowlist for `accounts.salla.sa`, `api.salla.dev` and `docs.salla.dev` are provided up front.
- The core would then be designed around Salla, with WooCommerce's missing-data cases added in the second step.

## 3. Phases

| Phase | Content | Exit criteria |
|---|---|---|
| **0. Pre-conditions** | Patch the upstream Shopify callback (`04` §7) or confirm the `SHOPIFY_CLIENT_*` settings stay empty. Confirm AR encryption keys in staging and production. Get provider partner accounts and a network allowlist. Decide the plan/feature and the `stores` limit. | Security patch merged with specs; environment checklist signed off |
| **2. Core + WooCommerce** | See the files in §4 | Real WooCommerce end to end: connect via wc-auth; guest and registered customers; phone and email matching; tracking via Shipment Tracking and fulfillments; cache; permission and tenancy specs; UI screenshots in ar/en |
| **3. Salla** | Easy Mode install, app-level signed webhook, token refresh with lock, shipments, light-format handling | Real Salla demo store: install → match → orders → tracking → uninstall |
| **4. Zid** | OAuth + two tokens, per-store webhook token, credit notes | Real Zid test store end to end; webhook authentication decided from the verified docs |
| **5. Shopify** | Lynomia connector reusing the upstream pieces; `shopify_api` 16.x upgrade (check upstream billing code); GraphQL; expiring tokens; compliance webhooks; approvals | Dev store end to end; approvals granted; before 2027-01-01 |
| **6. Real time + extras** | Order webhooks → cache invalidation + ActionCable refresh; Captain copilot tool `get_customer_orders` (template `search_linear_issues_service.rb`); abandoned carts (read); contact-page tab | Per feature |
| **7. Write actions** | Cancel, refund, status and shipment edits: separate permission, confirmation and audit | Separate security review |

**Phase 2 status (2026-09-30): implemented** per the approved Phase 2 brief. See `07-phase2-implementation.md`, `08-woocommerce-security.md` and `09-woocommerce-e2e.md`.

Changes from the exit criteria above, all decided in that brief:
- stores connect with manually entered **Read** keys, not `wc-auth`;
- no plugin-specific tracking, because WooCommerce core has none;
- no webhooks;
- Arabic strings are included.

**Phase 6 gate (2026-09-30): PARTIAL GO** (doc 23). WooCommerce GO with a pilot; Salla, Zid and Shopify NO-GO with their switches off until their real UAT (and, for Shopify, the protected customer data approval).

**Phases 3–5 status (2026-09-30): implemented, real UAT blocked.** Salla (docs 10–13), Zid (docs 14–17) and Shopify (docs 18–22) are built on the same core. Each passed a simulated-provider E2E; `REAL_*_UAT = BLOCKED` for all three, since provider hosts are unreachable here and no partner accounts exist.

Shopify differs from the row above:
- **A dedicated Shopify app** (`SHOPIFY_COMMERCE_*`). It does not reuse the upstream pieces beyond the hardened `Shopify::ShopDomain`. The legacy integration is left unchanged and nothing is migrated (doc 21).
- **No `shopify_api` 16.x upgrade.** The connector talks to Shopify through `Commerce::HttpClient`, so the upstream gem and its billing code are untouched.
- **Exit criteria still open:** the development-store run and Shopify's protected customer data approval (doc 22 §6).

## 4. Files likely to change in Phase 2 (core + WooCommerce)

**New (Lynomia-owned, `custom/`)**

- `custom/db/migrate/*_create_commerce_stores.rb`, `*_create_commerce_customer_links.rb`
- `custom/app/models/commerce/store.rb`, `commerce/customer_link.rb`
- `custom/app/services/commerce/`:
  - value objects: `order.rb`, `customer.rb`, `shipment.rb`, `order_item.rb`, `refund.rb`;
  - `errors.rb`, `customer_matcher.rb`, `orders_query.rb`, `cache.rb`, `phone.rb`, `credential_refresher.rb`;
  - `providers/base.rb`, `providers/registry.rb`;
  - `providers/woocommerce/{client,connector,order_mapper,tracking_resolver}.rb`.
- `custom/app/controllers/api/v1/accounts/commerce/{stores,conversation_orders,customer_links,customer_search}_controller.rb`
- `custom/app/controllers/commerce/woocommerce/auth_callbacks_controller.rb` (wc-auth key POST)
- `custom/app/controllers/webhooks/commerce/woocommerce_controller.rb` (only if Phase 2 includes lifecycle or optional webhooks)
- `custom/app/policies/commerce/{store,customer_link}_policy.rb`
- `custom/app/jobs/commerce/{refresh_orders,webhook,purge_store}_job.rb`
- `custom/app/views/api/v1/accounts/commerce/*.json.jbuilder`
- `config/routes/commerce.rb`
- Specs:
  - `spec/models/commerce/*`, `spec/services/commerce/**` (mapper fixtures recorded from the real WooCommerce);
  - `spec/controllers/api/v1/accounts/commerce/*` (tenancy, permission and ownership matrix).
- Frontend:
  - `app/javascript/dashboard/components-next/Commerce/*` (panel, order card, store badge, link dialog);
  - `app/javascript/dashboard/api/commerce.js`;
  - `app/javascript/dashboard/routes/dashboard/settings/commerce/*` (store list and connect);
  - `app/javascript/dashboard/i18n/locale/en/commerce.json` plus its index registration.

**Existing files (small, additive)**

- `config/routes.rb`: `draw :commerce`
- `config/features.yml`: append `lynomia_commerce` with `column: feature_flags_ext_1`
- `app/javascript/dashboard/featureFlags.js`
- `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue`: one `v-else-if` section
- `app/javascript/dashboard/composables/useUISettings.js`: `commerce_orders` key
- Settings routes and the settings sidebar entry: `settings.routes.js`, `Sidebar.vue`, both already Lynomia-modified
- `config/locales/en.yml`: backend errors
- `config/initializers/rack_attack.rb`: a `/webhooks/commerce` throttle, if webhooks are in Phase 2
- `custom/app/models/billing_plan.rb`: optional `stores` limit key
- Phase 0 only: `app/controllers/shopify/callbacks_controller.rb`, `app/helpers/shopify/integration_helper.rb`, `app/controllers/api/v1/accounts/integrations/shopify_controller.rb`

## 5. Risks and blockers

| # | Risk / blocker | Severity | Mitigation |
|---|---|---|---|
| 1 | **Every official provider docs host and API host is blocked in this environment.** Several facts are VERIFY, and Salla, Zid and Shopify cannot be tested from here. | High (blocks Phases 3–5 here) | Network allowlist for the provider API and docs hosts, or verification by Lynomia; record real sandbox fixtures |
| 2 | Partner accounts and approvals (Salla, Zid partner apps; Shopify protected customer data + `read_all_orders`) | High (lead time) | Start the applications now; private or unlisted apps for pilots |
| 3 | Upstream Shopify callback flaw (`04` §7) | High if Shopify credentials are configured | Phase 0 patch before any Shopify setting is filled |
| 4 | Shopify non-expiring tokens rejected from **2027-01-01**; REST legacy; gem 14.8 → 16.x is breaking for upstream Shopify and billing code | High for Shopify | The Lynomia Shopify connector uses expiring tokens + GraphQL; decide the upstream integration's fate (keep disabled) |
| 5 | Single-use rotating refresh tokens (Salla, Zid, Shopify): a race or lost write forces a reinstall | High | Per-store lock, atomic persist-before-use, `needs_reauth` flow, alerting |
| 6 | Zid webhooks unsigned (VERIFY) | Medium | Secret URL token, re-fetch, never display payload data |
| 7 | WooCommerce variability: tracking plugins, phone search (HPOS version), TLS/WAF/permalinks, webhooks disabled after 5 failures | Medium | Per-store `tracking_source` detection; health check; email- and phone-based order search with exact re-check |
| 8 | SSRF through the merchant URL (WooCommerce) | High | `SafeFetch`, HTTPS only, IP checks per redirect |
| 9 | AR encryption optional today | High | Connect refused without encryption; production gate item |
| 10 | Wrong-customer exposure | High | Strict exact matching (`03`), ambiguity → manual choice, audit |
| 11 | Provider API churn (Salla light format 2026-09-01, Shopify quarterly versions) | Medium | Versioned mappers, fixture specs, pinned API versions with a quarterly review |
| 12 | Rate limits (Zid 60/min, Salla customers 500/10 min, Shopify query cost) | Medium | Cache, negative cache, one call per store per open, backoff |
| 13 | `Rails.cache` per-host in production | Medium | Redis-backed cache keys (`Redis::Alfred`) |
| 14 | Upstream merge conflicts | Low | Backend in `custom/`; core edits limited to the additive lines in §4 |
| 15 | PII retention and compliance (PDPL, Shopify redact) | Medium | Minimal storage, TTL cache, purge on disconnect/redact; retention policy doc |
