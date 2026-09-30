# Lynomia Commerce: Phase 1 discovery

- **Scope:** discovery only. **No code, migrations, webhooks, credentials or external API calls were added.**
- **Code base:** Chatwoot 4.18.0 plus the Lynomia overlay, at branch `claude/laughing-albattani-8yi0kh` @ `1582e04fb`.
- **Evidence:** file:line references into this repository, and the official provider docs listed in `02-provider-contracts.md`.

## 0. How provider facts were obtained

This session's network policy denies every official provider documentation host (proxy 403):
`docs.salla.dev`, `salla.dev`, `docs.zid.sa`, `docs.zid.dev`, `api.zid.sa`, `woocommerce.github.io`, `developer.woocommerce.com`, `woocommerce.com` and `shopify.dev`.

Provider facts were therefore taken from, in order of reliability:

1. **Official source repositories:**
   - WooCommerce REST API docs source and WooCommerce core, on GitHub;
   - Salla's official GitHub org `SallaApp` (`oauth2-merchant`, starter kits, `salla-partners-agent-kit`);
   - Shopify's `shopify-api-ruby` repo (CHANGELOG, `docs/usage/oauth.md`).
2. **Web-search summaries of the official pages**, with the URL recorded per fact.

- No third-party tutorials were used.
- Anything not confirmed is marked **VERIFY**, and must be confirmed on the official page before Phase 2 code depends on it.

## 1. What exists today (Chatwoot 4.18 + Lynomia)

| # | Area | What exists | Evidence |
|---|---|---|---|
| 1 | Integration framework | **App registry and connection rows.** `config/integration/apps.yml` is loaded into `APPS_CONFIG`. `Integrations::App` wraps it: `active?`, `enabled?` and `action` are hard-coded per app. `Integrations::Hook` stores connections: `app_id`, `reference_id`, encrypted `access_token`, plaintext `settings` jsonb. `allow_multiple_hooks` controls per-account uniqueness. | `config/initializers/00_init.rb:1`; `apps.yml:1-11,257-263`; `app/models/integrations/app.rb:43-104`; `app/models/integrations/hook.rb:18-49,98-130`; `db/schema.rb:1227-1238` (**no indexes on `integrations_hooks`**) |
| 1b | OAuth base | **Two families of OAuth state.** `OauthAuthorizationController` + `OauthCallbackController` use a signed GlobalID state that expires in 15 min; Notion reuses them. Shopify and Linear have their own JWT state with **no `exp`**. | `app/controllers/api/v1/accounts/oauth_authorization_controller.rb:10-18`; `notion/callbacks_controller.rb:14-31`; `app/helpers/shopify/integration_helper.rb:8-56`; `app/helpers/linear/integration_helper.rb:6-45` |
| 1c | Token refresh and re-auth | **Linear already refreshes tokens; any integration can prompt re-auth.** Linear refreshes and saves the token back to the hook; its `refresh_token` sits in plaintext settings. `Reauthorizable` counts auth errors in Redis and emails admins. | `lib/integrations/linear/access_token_service.rb:8-75`; `app/models/concerns/reauthorizable.rb:30-97` |
| 1d | Provider template | **A per-provider base class to copy.** `Crm::BaseProcessorService` is an abstract processor with one subclass per provider. | `app/services/crm/base_processor_service.rb:1-60` |
| 2 | Dashboard Apps | **Per-account iframe apps, shown as conversation tabs.** The iframe is sent conversation, contact and agent context via `postMessage(..., '*')`, with **no signed token**. They appear as **tabs in the main conversation pane**, not in the sidebar. Admin-only CRUD. | `app/models/dashboard_app.rb:18-46`; `components/widgets/DashboardApp/Frame.vue:43-51,88-123`; `ConversationBox.vue:42-145`; `app/policies/dashboard_app_policy.rb` |
| 3 | Secret storage | **Rails `encrypts`, off by default.** It is only active when the `ACTIVE_RECORD_ENCRYPTION_*` ENV keys exist. `InstallationConfig` values are **not** encrypted at rest; `type: secret` is write-only in Super Admin (Lynomia Phase 4). `Redis::SecureStorage` holds short-lived AES-GCM values. | `config/application.rb:83-93,109-116`; `hook.rb:26`; `lib/redis/secure_storage.rb:18-35`; `app/models/installation_config.rb:35,48-51` |
| 4 | Inbound webhooks | **Existing patterns to copy.** Routes are `/webhooks/<provider>`, served by `ActionController::API` controllers. HMAC is checked as in `MetaTokenVerifyConcern` (hardened in Phase 4 commit A) and in the Shopify controller (base64 HMAC-SHA256 + `secure_compare`). Handlers call `perform_later(...)`. Dedup uses Redis `SET NX EX`. **No `/webhooks` throttle**, only the global per-IP limit. | `config/routes.rb:672-682`; `app/controllers/concerns/meta_token_verify_concern.rb`; `app/controllers/webhooks/shopify_controller.rb:30-42`; `app/services/whatsapp/message_dedup_lock.rb:5-18`; `lib/redis/alfred.rb:10-42`; `config/initializers/rack_attack.rb:71` |
| 5 | Tenant isolation | **Account scoping is manual, per request.** `Current.account` is a thread-local, and jobs must pass the account explicitly. `EnsureCurrentAccountHelper` sets it; lookups go through `Current.account.*`. Lynomia's `Billing::AccessGuard` returns 402 on account APIs (not on `/webhooks`). | `lib/current.rb:1-17`; `app/controllers/concerns/ensure_current_account_helper.rb:4-34`; `custom/app/controllers/billing/access_guard.rb:14-35` |
| 6 | Permissions | **Pundit policies, plus Enterprise custom roles.** `HookPolicy` makes changes admin-only. `ConversationPolicy#show?` is admin, bot, or an agent who can view the conversation. Enterprise custom-role permissions: `conversation_manage`, `conversation_unassigned_manage`, `conversation_participating_manage`, `contact_manage`, … | `app/policies/hook_policy.rb:2-16`; `app/policies/conversation_policy.rb:10-12`; `enterprise/app/models/custom_role.rb:35-45` |
| 7 | Audit / logging | **Enterprise audit log, but hooks are not audited.** The `audited` gem feeds the Enterprise `AuditLog`. Audited models include account, inbox, webhook, user, … Lynomia uses tagged `Rails.logger` lines. | `Gemfile:184`; `enterprise/app/models/enterprise/audit_log.rb:29`; `enterprise/app/models/enterprise/audit/*.rb` |
| 8 | Background jobs | **Sidekiq with lock and retry helpers.** `max_retries: 3`; `MutexApplicationJob` provides `with_lock`; retry patterns exist for external rate limits; sidekiq-cron schedules. | `config/sidekiq.yml:9,17-33`; `app/jobs/mutex_application_job.rb:14-61`; `app/jobs/data_imports/freshdesk/base_job.rb:4-12`; `config/schedule.yml` |
| 9 | Caching | **No shared Rails cache in production.** Production has no cache store configured, so Rails falls back to a **per-host file store**. Shared Redis goes through `Redis::Alfred`. **Nothing caches Shopify order responses.** | `config/environments/production.rb:55-56`; `config/initializers/01_redis.rb:8-12`; `lib/redis/redis_keys.rb` |
| 10 | Contacts | **Email, phone and identifier are unique per account; phone must already be E.164 and is not normalized.** `ContactIdentifyAction` matches identifier → email → phone. `ContactMergeAction` merges contacts. The `telephone_number` gem is used ad hoc. `contact_inboxes.source_id` holds the channel identity (for example the WhatsApp `wa_id`); `hmac_verified` marks widget identity verification. | `app/models/contact.rb:33-56,189-226`; `app/actions/contact_identify_action.rb:12-70`; `app/actions/contact_merge_action.rb:5-66`; `Gemfile:22`; `db/schema.rb:825-835` |
| 11 | Conversation context | **Sidebar sections are hard-coded, but new ones reach existing users automatically.** `ContactPanel.vue` renders a draggable list of hard-coded `v-else-if` sections, including `linear_issues` and `shopify_orders`. `DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER` auto-appends new keys for existing users. | `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue:151-326` (Shopify 286-301); `composables/useUISettings.js:5-55` |
| 12 | Contact page | **Hard-coded tabs.** `ContactManageView.vue` has a fixed tab list (attributes, history, notes, media, merge). | `routes/dashboard/contacts/pages/ContactManageView.vue:40-53,171-184` |
| 13 | Captain (AI) | **HTTP tools and a Linear copilot tool to copy.** `Captain::CustomTool` supports per-account HTTP tools through `SafeFetch`. The copilot tool `search_linear_issues_service.rb` is a template for a future `get_customer_orders` tool. | `enterprise/app/models/captain/custom_tool.rb:26-72`; `enterprise/app/services/captain/tools/copilot/search_linear_issues_service.rb:1-30`; `lib/safe_fetch.rb:26-37` |
| 14 | E-commerce code | **Shopify only.** There is no Salla, Zid, WooCommerce, order or cart code. Shopify is the only store integration (§2). Stripe code is Lynomia's billing, not commerce. | `grep` of app/, enterprise/, custom/ |
| 15 | Plans and flags | **New flags can be sold through plans, if appended correctly.** New flags must be appended with `column: feature_flags_ext_1` (bit positions). Non-internal flags are automatically assignable in Lynomia plans. `Billing::FeatureSync` switches off features that aren't in the plan. Plan limits cover agents and inboxes; a "stores" limit can follow `inbox_limit.rb`. | `app/models/concerns/featurable.rb:4-28`; `config/features.yml:251-281`; `custom/app/models/billing_plan.rb:8,34-40`; `custom/app/services/billing/feature_sync.rb:18-26`; `custom/app/services/billing/inbox_limit.rb:8-19` |

## 2. Existing Shopify integration (upstream Chatwoot, unchanged by Lynomia)

**Overall classification: PARTIAL.** Reuse its components; do not extend it in place.

| Capability | Status | Evidence |
|---|---|---|
| OAuth / install | **NEEDS PATCH (security)** | Authorization-code grant with offline token (`shopify_controller.rb:8-23`, `shopify/callbacks_controller.rb:4-56`). Five problems:<br>• **`params[:shop]` is not validated before the token exchange** (`callbacks_controller.rb:51`: `site: "https://#{params[:shop]}"`). oauth2 2.0.22 sends client id/secret via Basic auth, so the **client secret is sent to any host the caller names**.<br>• No Shopify `hmac` check on the callback.<br>• The JWT state has no `exp`, is reusable and is not bound to the shop.<br>• `auth` is callable by agents.<br>• No feature-gate check on `auth`/`orders`/`callback`.<br>Identical to upstream `v4.18.0`. |
| Token storage | READY TO REUSE (conditional) | `encrypts :access_token, deterministic: true` only if AR encryption is configured (`hook.rb:25-26`); never serialized. |
| Token refresh / expiry | **NOT PRESENT** | No `expiring=1`, `refresh_token` or `expires_in` anywhere. Shopify rejects non-expiring offline tokens for **all public apps from 2027-01-01**; see `02-provider-contracts.md` §Shopify. |
| API style / version | **NEEDS PATCH** | REST Admin (legacy since 2024-10). `api_version: '2025-01'` hard-coded (`shopify_controller.rb:91`), outside Shopify's 12-month support window. Gem `shopify_api 14.8.0` (`Gemfile.lock:898`); expiring-token helpers exist from 16.0.0. |
| Customer lookup | PARTIAL | REST `customers/search.json`, `email OR phone` unescaped, takes the first hit (`shopify_controller.rb:56-68`). |
| Order lookup | PARTIAL | REST `orders.json`, one page, 7 fields, no order name, no line items, no pagination, no caching (`:70-83`). |
| Tracking / fulfillment | PARTIAL (tracking NOT PRESENT) | Only the `fulfillment_status` string, although `read_fulfillments` is granted. The UI's `partial` i18n key is broken (`ShopifyOrderItem.vue:55`). |
| Webhooks | PARTIAL | Correct HMAC (`webhooks/shopify_controller.rb:30-42`). `app/uninstalled` and `shop/redact` are handled, with stale-event protection. `customers/data_request` and `customers/redact` are only acknowledged. No order topics; no registration code. |
| Sidebar UI | READY TO REUSE (slot) / NEEDS PATCH (content) | Draggable section with persisted order (`ContactPanel.vue:286-301`, `useUISettings.js:5-55`). Bugs: untranslated error key; no re-fetch when the email or phone changes. |
| Permissions | NEEDS PATCH | Disconnect is admin-only (`hook_policy.rb:14-16`). Connect and orders are open to any account user; no conversation-access check. |
| Multi-store per account | **NOT PRESENT** | `allow_multiple_hooks: false` (`apps.yml:262`) plus the uniqueness rule at `hook.rb:39`. Every lookup assumes one hook: `find_by!(app_id: 'shopify')` (`shopify_controller.rb:53`), and the Enterprise billing code (`subscription_fetcher.rb:32`, `shopify_app_pricing_url.rb:44`). A shop belongs to at most one account (`hook.rb:31-34`). |
| Gating | Present, off | `Shopify::FeatureGate` = `ENABLE_SHOPIFY_INTEGRATION` (default false) AND the `shopify_integration` flag, which is `chatwoot_internal`. So no Lynomia plan can grant it (`feature_gate.rb:5-14`; `features.yml:163-166`). |
| Shopify billing | Separate, dormant | Chatwoot Cloud's own App-Pricing billing reuses the same hook (`enterprise/.../billing/shopify_*`). It is dormant in Lynomia (no code sets `signup_source = 'shopify'`). |

**Why not extend it in place:**
- Multi-store support, a second encrypted secret (the refresh token), GraphQL and tracking would each change upstream files that the upstream billing code also depends on (single hook, `find_by!`). Future upgrades would conflict.
- Upgrading the gem to 16.x is itself breaking: 15.0.0 removed `LATEST_SUPPORTED_ADMIN_VERSION`, which `app/services/shopify/api_context.rb:2` uses.

**What to reuse:**
- `Shopify::ShopDomain` (domain validation);
- the webhook HMAC check;
- the uninstall/redact semantics (stale-event guard, `UninstallationService` flow);
- `ShopifyOrdersList.vue` / `ShopifyOrderItem.vue` as UI references;
- the sidebar slot mechanism.

**Security pre-condition:**
- The upstream callback flaw is only exploitable while `SHOPIFY_CLIENT_ID` and `SHOPIFY_CLIENT_SECRET` are configured.
- It must be patched (validate `shop` against `ShopDomain` **before** the exchange, verify the query `hmac`, give the state an expiry and make it single-use, require admin, check the gate), or those settings must stay empty, before any Shopify credentials are entered on this installation. See `04-security-and-tenancy.md` §7.

## 3. Constraints that shape the design

1. **`Integrations::Hook` cannot hold commerce stores safely:**
   - only one encrypted column, while every provider needs 2–3 secrets;
   - plaintext `settings`;
   - no DB indexes or uniqueness (webhook store resolution would scan the table);
   - per-app logic hard-coded in core classes with no `prepend_mod_with` (`app.rb:43-100`);
   - upstream Shopify and billing assume one hook per account.
2. **AR encryption is optional today.** Commerce credentials must never be stored in plaintext, so connect must fail loudly when encryption is not configured.
3. **`Rails.cache` is per-host in production.** Shared caching must use Redis.
4. **Contact phone numbers are strict E.164 with no normalization.** Store phone numbers (Salla `mobile` + `mobile_code`, WooCommerce free text) need `TelephoneNumber` normalization.
5. **Dashboard Apps** post context to `'*'` with no signed token, and render as a conversation tab rather than in the sidebar. They cannot carry store credentials and cannot use Lynomia's API without their own auth.
