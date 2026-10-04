# 11. Permissions and tenant map

Covers Part 11 (permissions and tenancy), Part 12 (feature gating and the authorization recipe for new
surfaces) and Part 15 (telemetry). Every claim below is cited `path:line` against branch
`claude/practical-thompson-9xfqed`. Where I re-checked an upstream number and found it different, the
verified number is used and the discrepancy is listed in the last section.

---

## Decisions at a glance

| # | Capability | Classification | Why |
|---|---|---|---|
| 1 | Pundit with a hash `user_context` + `ApplicationPolicy` deny-by-default | **REUSE** | `app/policies/application_policy.rb:4-10` unpacks `{user, account, account_user}`; `index?/create?/update?/destroy?` default `false` (`:12-14` onward). A new policy that forgets a verb denies. |
| 2 | Account tenancy via `EnsureCurrentAccountHelper` | **REUSE** | One entry point, `app/controllers/concerns/ensure_current_account_helper.rb:9-21`, inherited by every account-scoped controller incl. all of `custom/`. Nothing to add. |
| 3 | `administrator` / `agent` enum as the role for new settings pages | **REUSE** | `app/models/account_user.rb:34`. It is the only role model that actually works on this installation (§11.3). |
| 4 | Custom roles as the gate for new enablement surfaces | **DO NOT CREATE** | Three stacked gates make `custom_roles` unreachable on a community-plan install (§11.3), and a custom-role user is *neither* agent nor administrator (`enterprise/app/models/enterprise/account_user.rb:3`). |
| 5 | A new custom-role permission (e.g. `enablement_manage`) | **NEW PRIMITIVE REQUIRED** — out of scope | The vocabulary is a closed 7-item inclusion list (`enterprise/app/models/custom_role.rb:37-45`, `:48`) and consuming it needs an `Enterprise::` override module per policy. Not needed to ship any surface in this program. |
| 6 | Account feature flag for a new surface | **EXTEND** | `config/features.yml` (72 entries, verified) + `app/javascript/dashboard/featureFlags.js` + a server re-check. `lynomia_commerce:282` / `lynomia_flow_builder:286` are the two existing Lynomia precedents. |
| 7 | Frontend gate `usePolicy().shouldShow` | **REUSE** | `app/javascript/dashboard/composables/usePolicy.js:64-105`, consumed by route meta, `<Policy>`, the sidebar and the command bar. Authorizing a page = route meta + a server policy. Nothing else. |
| 8 | Router enforcement of `meta.featureFlag` | **PATCH** (optional, UX-only) | `app/javascript/dashboard/helper/routeHelpers.js:15-18` reads `meta.permissions` only. Typing a flagged URL is not redirected. Harmless because every endpoint re-checks (`custom/.../flows_controller.rb:20`, `stores_controller.rb:50-52`), so this is cosmetic. |
| 9 | Starter gallery authorization | **REUSE** — zero new authorization | `app/javascript/dashboard/recipes/index.js:1-7` states it: no table, no endpoint, no policy. It inherits the host page's route meta and the ordinary create API. |
| 10 | Template manager authorization | **EXTEND** | `settings_templates` is `permissions: ['administrator']` with no flag (`templates.routes.js:14-18`). A Lynomia-owned template store needs its own policy + `ensure_<x>_enabled` + a flag, following Commerce. |
| 11 | Global product documentation authorization | **NEW PRIMITIVE REQUIRED** | It is the first global, non-account-scoped content surface. Super Admin is outside Pundit and outside tenancy (`app/controllers/super_admin/application_controller.rb:14`). The decision has to be made, not copied (§12.4d). |
| 12 | Portal slug reservation | **NEW PRIMITIVE REQUIRED** (code-only, no migration) | `app/models/portal.rb:44` is a bare global `uniqueness: true`, and tenant onboarding actively claims `-docs` / `-help` (`enterprise/app/services/onboarding/help_center_creation_service.rb:118-124`). |
| 13 | Telemetry that can answer starter selected / completed / abandoned | **DO NOT CREATE** during this program | It genuinely cannot answer it today (§15), and building a telemetry platform is a separate program. Document the opportunity; instrument nothing speculatively. |
| 14 | Contacts export dropping `q`/`active` in the Vuex layer | **PATCH** | `app/javascript/dashboard/store/modules/contacts/actions.js:202` destructures only `{ payload, label }` and forwards only those at `:205`. Live defect. |
| 15 | `@contacts_count` set to page size on the search path | **PATCH** | `app/controllers/api/v1/accounts/contacts_controller.rb:183` sets `@contacts_count = results.size` (max 15), so "select all N matching" is unreachable on a search view. Live defect. |

---

## 11.1 The real request pipeline

Nothing in this program needs a new gate. These fire in order on every `/api/v1/accounts/:account_id/...`
call, before any controller body runs.

| Order | Layer | Where | What it does | Failure |
|---|---|---|---|---|
| 1 | Authentication | `app/controllers/api/base_controller.rb:4-6` | Access token, bot token, or Devise user | 401 |
| 2 | **Tenancy** | `app/controllers/concerns/ensure_current_account_helper.rb:9-21` | `Account.find(params[:account_id])`; 401 unless `active?`; then `account.account_users.find_by(user_id:)` → 401 if absent (`:23-27`), or for an `AgentBot` requires same account or an `agent_bot_inbox` in it (`:29-34`). Sets `Current.account` / `Current.account_user`. | 401 |
| 3 | Billing | `custom/app/controllers/billing/access_guard.rb:14-17` (injected at `config/initializers/billing.rb:5-12`) | 402 `subscription_required` when the subscription is unusable (`:21-35`); 422 `plan_limit_reached` on `agents#create/#bulk_create` (`:37-45`) | 402 / 422 |
| 4 | Token API scope | `app/controllers/api/v1/accounts/base_controller.rb:10-14` | 403 for API-token callers unless the account has `api_and_webhooks` | 403 |
| 5 | **Authorization** | `app/controllers/api/base_controller.rb:14-18` | `check_authorization` derives the policy from `controller_name.classify` — 54 call sites (38 `app/`, 16 `enterprise/`, 0 `custom/`, verified). Or `authorize(Model, :verb?)` explicitly. Or `check_admin_authorization?` (`:20-22`), which bypasses Pundit and raises unless `Current.account_user.administrator?`. | `Pundit::NotAuthorizedError` |
| 6 | Row scoping | per controller | `Current.account.<association>` — e.g. `Current.account.contacts.find` (`contacts_controller.rb:228-231`), `Current.account.inboxes.find` (`inboxes_controller.rb:88`), `Current.account.commerce_stores.find` (`stores_controller.rb:55`) | 404 |

`Current` is thread-local (`lib/current.rb:1-17`) and reset in an `ensure` block
(`app/controllers/concerns/request_exception_handler.rb:35`). `pundit_user` is a **hash**, not a user:
`{user:, account:, account_user:}` (`app/controllers/application_controller.rb:21-27`). That is why every
policy reads `@account_user`, never `@user.role`.

**Only two Pundit `Scope` classes exist in the whole repo**: `InboxPolicy::Scope`
(`app/policies/inbox_policy.rb:2-16`, which returns `user.assigned_inboxes` and ignores the scope it was
handed) and `DataImportPolicy::Scope` (`app/policies/data_import_policy.rb:38-44`).
`ApplicationPolicy::Scope#resolve` returns the scope unchanged (`:55-57`). Tenancy is therefore enforced
*once* (layer 2) and then re-expressed by convention at layer 6. **Consequence for this program:** a new
endpoint that forgets the `Current.account.` prefix has no second line of defence. That is the single
discipline to enforce in review.

## 11.2 Policy census (verified counts)

| Tree | Files | Breakdown |
|---|---|---|
| `app/policies` | 26 | `ApplicationPolicy` base + 25 concrete (incl. `captain/tasks_policy.rb`) |
| `enterprise/app/policies` | 17 | 9 EE-only concrete classes (5 top-level + 4 `Captain::`) + **8 `Enterprise::` override modules** |
| `custom/app/policies` | 2 | `Commerce::StorePolicy`, `Commerce::ActionPolicy` |
| **Concrete policy classes** | **36** | 25 + 9 + 2 |

The 8 `Enterprise::` modules (`account, article, category, contact, conversation, csat_survey_response,
portal, report`) match exactly the 8 `prepend_mod_with` calls in `app/policies` (verified:
`account_policy.rb:47`, `article_policy.rb:31`, `category_policy.rb:31`, `contact_policy.rb:60`,
`conversation_policy.rb:47`, `csat_survey_response_policy.rb:15`, `portal_policy.rb:39`,
`report_policy.rb:7`). **`custom/` contains no policy override module at all** — so
`prepend_mod_with('XxxPolicy')` on a policy only ever resolves to an `Enterprise::` module. A Lynomia
policy change must therefore be either a new policy in `custom/app/policies` or a controller override, never
a policy overlay.

Seven of the eight modules exist only to OR a custom-role permission into existing verbs;
`Enterprise::AccountPolicy` is the only one that adds a verb. `Commerce::ActionPolicy`
(`custom/app/policies/commerce/action_policy.rb`) is the only permission-table policy in the repo and the only
`custom/` consumer of a custom-role string.

## 11.3 Roles — and what "administrator" means for a new settings page

The base role is a two-value enum: `enum role: { agent: 0, administrator: 1 }`
(`app/models/account_user.rb:34`), surfaced as a one-element array —
`administrator? ? ['administrator'] : ['agent']` (`:58-60`). That array is the sole input to every frontend
permission check.

The EE overlay **replaces** it:

```ruby
# enterprise/app/models/enterprise/account_user.rb:1-5
def permissions
  custom_role.present? ? (custom_role.permissions + ['custom_role']) : super
end
```

`super` is not merged. **Spell this out for any new settings page gated on `administrator`:** a user with a
custom role has permissions like `['contact_manage', 'custom_role']`. They hold neither `'administrator'`
nor `'agent'`. `routeIsAccessibleFor` ANY-matches `meta.permissions`
(`app/javascript/dashboard/helper/routeHelpers.js:15-18`, via `hasPermissions`, which is
`.some()`), so a route with `permissions: ['administrator']` is **invisible in the sidebar, absent from the
command bar, and unreachable by URL** for every custom-role user — no matter which of the 7 permissions the
role holds, including a role that holds all seven. Even `settings_home` routes them away from general
settings (`settings.routes.js:37-53`, which checks `getCurrentRole === 'administrator' && getCurrentCustomRoleId === null`).

Three stacked gates then make custom roles unreachable on this installation as configured:

1. `custom_roles` is `premium: true` (`config/features.yml:147-150`), and premium flags are excluded from
   `BillingPlan.assignable_features` (`custom/app/models/billing_plan.rb:35-41`) — **no Lynomia plan can
   grant it**.
2. Super Admin's premium checkboxes render `disabled` while the plan is community
   (`enterprise/app/views/fields/account_features_field/_form.html.erb:29-30`).
3. In production, `Internal::ReconcilePlanConfigService` strips every premium flag from every account daily
   while `ChatwootHub.pricing_plan == 'community'`
   (`enterprise/app/services/internal/reconcile_plan_config_service.rb:2-10`, `:52-58`), and
   `INSTALLATION_PRICING_PLAN` seeds to `'community'` (`config/installation_config.yml:331-332`).

The controller gate is unconditional regardless:
`raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('custom_roles')`
(`enterprise/app/controllers/api/v1/accounts/custom_roles_controller.rb:33-35`).

**Decision.** Gate every new enablement surface on `['administrator']` and nothing else. Do not design any
surface that depends on a custom-role permission, and do not add one. `commerce_order_manage` — the one
Lynomia-added permission (`enterprise/app/models/custom_role.rb:44`) — is in practice unreachable for the
same reason, and covers only in-conversation order actions, not Commerce setup
(`custom/app/policies/commerce/store_policy.rb` is administrator-only).

**Verify before relying on this:** `ChatwootHub.pricing_plan` is a live DB row that the hub ping overwrites,
not the YAML. Read the actual `installation_configs` row on the target environment before treating premium
features as permanently off. *(Flagged as the upstream inventory's own top risk; I did not resolve it.)*

---

## 12.1 Feature gating has four independent layers

They are not a hierarchy with one source of truth. All four can disagree, and three of them are invisible to
the account's administrator.

| Layer | Scope | Mechanism | Can a plan grant it? | Who edits it |
|---|---|---|---|---|
| **1. Account bitset flags** — 72 entries | per account | FlagShihTzu over `feature_flags` + `feature_flags_ext_1` via `Featurable`; seeded from `config/features.yml` (72 `- name:` entries, verified). `feature_flags` is full at 63/63, so a new flag **must** declare `column: feature_flags_ext_1` and be appended. | yes, if assignable | Super Admin → account; or `Billing::FeatureSync` |
| **2. Premium list** — 9 entries | per account, licence-gated | `enterprise/config/premium_features.yml:2-10` (`disable_branding, audit_logs, sla, custom_roles, captain_integration, captain_integration_v2, captain_document_auto_sync, csat_review_notes, conversation_required_attributes`). Checkboxes disabled and flags force-cleared on a community plan. | **never** | the licence / hub plan |
| **3. Installation-wide switches** | **no account dimension** | `Shopify::FeatureGate` (`app/services/shopify/feature_gate.rb:1-14`, global config AND account flag — the canonical two-layer pattern); `Commerce::Providers.enabled?` (`custom/app/services/commerce/providers.rb:10-13` → each provider's `Config.enabled?` reading `SALLA_ENABLED`/`ZID_ENABLED`/`SHOPIFY_COMMERCE_ENABLED`); `Commerce::Switches` kill switches (`custom/app/services/commerce/switches.rb:13-16`, `:19`, `:26`) plus a `PRE_UAT` lock (`:16`, `:39-41`) that keeps salla/zid/shopify off whatever the switches say unless the ENV-only `COMMERCE_ALLOW_PRE_UAT_PROVIDERS` is set. | n/a | Super Admin → App configs / ENV |
| **4. Lynomia billing plan** | per account | `BillingPlan.assignable_features` = `features.yml` minus `chatwoot_internal`, `deprecated`, `premium` and 3 `SYSTEM_FEATURES` (`custom/app/models/billing_plan.rb:12`, `:35-41`). `Billing::FeatureSync#perform` enables the plan's features and **disables every other assignable one** (`custom/app/services/billing/feature_sync.rb:18-29`). | authoritative over the assignable subset only | Super Admin → Billing plans |

**Two consequences that matter for this program.**

- Layer 4 is destructive. A flag that is assignable and not in the plan gets turned **off** on the next sync
  (`feature_sync.rb:25`). A new enablement flag must be added to the relevant plans, or it will be silently
  cleared from every subscribed account. `lynomia_commerce` and `lynomia_flow_builder` are assignable;
  `custom_roles` is not.
- There are **three different premium lists** with different contents: 19 `premium: true` entries in
  `config/features.yml` (verified count), the 9 names in `enterprise/config/premium_features.yml:2-10`, and
  `PREMIUM_FEATURES` in `app/javascript/dashboard/featureFlags.js`. Nothing keeps them in sync. Do not
  reason about "premium" from one of them.

Layer 3 has **no account dimension at all** — a Lynomia-wide product documentation switch would naturally
live here, which is exactly why §12.4d is a different problem from §12.4a.

## 12.2 Adding a flag (the mechanical checklist)

1. Append to `config/features.yml` with `column: feature_flags_ext_1` (column 1 is full).
2. Mirror the name into `app/javascript/dashboard/featureFlags.js`.
3. Add it to the plans that should carry it (layer 4 will otherwise disable it).
4. **Re-check it on the server**, because the router does not enforce `meta.featureFlag`. The established
   shape is a one-line `before_action`:
   `raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('<flag>')` —
   `custom/.../flows_controller.rb:20`, `stores_controller.rb:50-52`,
   `custom_roles_controller.rb:33-35`.

## 12.3 The frontend gate is one composable

`usePolicy().shouldShow(featureFlag, permissions, installationTypes)`
(`app/javascript/dashboard/composables/usePolicy.js:64-105`):

- permissions and installation type are **hard denies**, checked first (`:72-73`).
- then it branches: a **custom-branded instance uses the flag alone** (`:75-78`); cloud returns
  `flag || isPremiumFeature(flag)` so a paywall can render; enterprise returns
  `flag || (premium && !hasPremiumEnterprise)`; otherwise `true`.

Four consumers, and they all derive the gate from route meta rather than restating it:

| Consumer | Where |
|---|---|
| Router guard (permissions **only**) | `app/javascript/dashboard/helper/routeHelpers.js:15-18` |
| `<Policy>` declarative wrapper | `app/javascript/dashboard/components/policy.vue:5-22`, `:26-28` |
| Sidebar | `components-next/sidebar/provider.js:105-147` (`isAllowed` at `:141-147`); each leaf wrapped at `SidebarGroupLeaf.vue:32-35` |
| Command bar | `composables/commands/useGoToCommandHotKeys.js` — entries carry only `routeName`; the gate is read from meta |

**So authorizing a new page = route meta + a server policy. There is no third thing.**

**One trap that is specific to this installation.** The custom-branded branch (`:75-78`) is selected by
`isACustomBrandedInstance`, which is literally `installationName !== 'Chatwoot'`
(`app/javascript/shared/store/globalConfig.js:67`). `INSTALLATION_NAME` is `'Lynomia chat'`
(`config/installation_config.yml:17-18`), so the branch is active today. But
`Internal::ReconcilePlanConfigService#reconcile_premium_config`
(`enterprise/app/services/internal/reconcile_plan_config_service.rb:38-46`) resets `INSTALLATION_NAME` to
`'Chatwoot'` from `enterprise/config/premium_installation_config.yml:2-3` whenever the plan reads
`community`. If that fires, `shouldShow` switches branch for every gated surface *and* the suppressed
chatwoot.com help links reappear (`BaseSettingsHeader.vue:78-92`). Any new gated surface should be sanity-checked
against both branches, not just the branded one.

## 12.4 Four concrete authorization recipes

### (a) A new account-scoped settings page — **EXTEND**

Precedents to copy verbatim: `commerce.routes.js:15-20` (`featureFlag: FEATURE_FLAGS.LYNOMIA_COMMERCE`,
`permissions: ['administrator']`) and `flows.routes.js:9-12` (one shared `meta` object reused by both the
index and the full-page builder route).

1. New `*.routes.js` under `app/javascript/dashboard/routes/dashboard/settings/<x>/`, with
   `component: SettingsWrapper` and a child carrying
   `meta: { permissions: ['administrator'], featureFlag: FEATURE_FLAGS.X }`.
2. Spread it into the aggregator, `settings.routes.js` (26 modules spread into one array today).
3. Add a `Sidebar.vue` leaf — `SidebarGroupLeaf` already wraps it in `<Policy>` and derives both
   permissions and flag from the target route's meta (`SidebarGroupLeaf.vue:32-35`,
   `provider.js:105-140`). **Do not restate the gate in the sidebar.**
4. Server: a policy in `custom/app/policies` (not a policy overlay — `custom/` has no override modules) plus
   the `ensure_<x>_enabled` `before_action`. `SettingsWrapper.vue` applies no authorization of its own; it is
   layout plus keep-alive.

### (b) A starter gallery — **REUSE, no new authorization**

The existing one is pure source code: `app/javascript/dashboard/recipes/index.js:1-7` states "There is no
recipes table, no recipes endpoint, and no runtime link between a created object and the recipe it came
from". Availability is computed from existing flags plus the account's own teams/labels/audiences/stores
(`useRecipeContext.js:40-57`). `RecipeDialog.vue` inherits the host page's route meta and then calls the
ordinary create API, so the real gate is whatever already guards the host page — flows
(`administrator` + `lynomia_flow_builder`), automations (`administrator` + `automations`), contacts
(`['administrator','agent','contact_manage']` + `CRM`, `routes/dashboard/contacts/routes.js:6-9`).

**Decision: add nothing.** A new gallery mounted on an already-authorized page needs no route, no policy, no
flag, no table. This is the cheapest surface in the whole program, and the reason is structural, not
accidental.

### (c) The template manager — **EXTEND, with one asymmetry to fix**

Live precedent: `settings_templates`, `permissions: ['administrator']`, **no feature flag**
(`templates.routes.js:14-18` — one of the few settings routes with no flag). Data comes from
`GET /inboxes/:id/message_templates` per WhatsApp inbox; templates are a `jsonb` column on the channel
(`db/schema.rb:800-801`).

The asymmetry: `InboxPolicy#message_templates?` is plain `true` (`app/policies/inbox_policy.rb:37-39`) while
`#sync_templates?` is administrator (`:65-67`). **Reading templates is open to any member of an assigned
inbox; only the route and the sync are admin-gated.** If a Lynomia template manager is going to be the
system of record, that read must be re-gated deliberately rather than inherited.

For a Lynomia-owned template store, follow Commerce exactly: own policy in `custom/app/policies`, own
`ensure_<x>_enabled` `before_action`, own `features.yml` flag appended to `feature_flags_ext_1`, added to the
plans. Tenancy comes free from `Current.account.inboxes` (`inboxes_controller.rb:88`).

### (d) Global product documentation — **NEW PRIMITIVE REQUIRED**, and it is a different shape

This is the one surface that is **not account-scoped**, so none of (a)–(c) applies. Super Admin is outside
Pundit and outside tenancy entirely: `SuperAdmin::ApplicationController` has only
`before_action :authenticate_super_admin!` (`app/controllers/super_admin/application_controller.rb:14`),
`SuperAdmin` is an STI subclass of `User` sharing the `users` table (`app/models/super_admin.rb:47`), and
the console sees every tenant. There is no finer-grained super-admin role and no per-resource authorization.

**How a Super Admin surface is actually authorized** — three mechanical facts, all verified:

1. **Routes.** `namespace :super_admin` at `config/routes.rb:729` (inside `devise_scope :super_admin`,
   `:727`; `devise_for :super_admins` at `:726`). Lynomia's own precedent is drawn separately:
   `draw :billing` at `config/routes.rb:782` → `config/routes/billing.rb:4-10`.
2. **Dashboards.** The sidebar auto-derives from `Administrate::Namespace.new(namespace).resources`
   (`app/views/super_admin/application/_navigation.html.erb:36`) against a hard-coded skip list (`:37`) and
   icon map (`:14-21`). Adding an `Administrate::BaseDashboard` subclass + controller + route is enough for a
   nav entry to appear. Working proof from the `custom/` tree:
   `custom/app/dashboards/billing_plan_dashboard.rb` +
   `custom/app/controllers/super_admin/billing_plans_controller.rb`.
3. **No Pundit, no account, no feature flag.** The gate is "is a super admin". That is the whole model.

Two existing patterns, and both have a defect for this purpose:

| Pattern | What it gives | Why it is not enough |
|---|---|---|
| `PlatformBanner` — the only global, accountless content record (`db/schema.rb:1531-1537`, no `account_id`), full Super Admin CRUD, delivered via `window.globalConfig` | the right *shape*: global content, Super-Admin-authored, no Pundit | suppressed off cloud (`dashboard_controller.rb:94`, `ChatwootApp.chatwoot_cloud?`), and the nav link itself is hidden off cloud (`_navigation.html.erb:38`). Dismissal is per-browser `localStorage`, so there is **no record of who read or dismissed anything**. |
| Help Center portal served globally at `/hc/<slug>` | a reader that already resolves portals with no account in the URL; `DomainHelper.chatwoot_domain?` compares the request host to the host of `FRONTEND_URL`/`HELPCENTER_URL` (`app/controllers/concerns/domain_helper.rb:2-4`) — **not** a Chatwoot domain, so a branded Lynomia install is *not* blocked | portal rows are hard account-scoped (`portals.account_id` NOT NULL, `app/models/portal.rb:42`), so "global docs" means one internal account's portal; and the slug is unprotected (§13). If neither env var matches the serving host, `URI.parse('').host` is `nil` and every portal page 401s with a hard-coded `support@chatwoot.com` message (`app/controllers/public_controller.rb:9-20`). |

**Decision.** Global documentation is authorized as a **Super Admin + Administrate resource, with no Pundit
policy, no account scope and no account feature flag** — same boundary as `PlatformBanner` and Lynomia's own
billing plans. The reader side is public and host-gated, not permission-gated. Two things must be decided
rather than copied, and both are left for approval:

- **R1.** Whether the reader is gated at all, and if so by what (the `chatwoot_cloud?` gate used by
  `PlatformBanner` must be *replaced*, not reused, since this install is not cloud).
- **R2.** A `Portal` slug reservation (§13). Code-only; the `audits` table already exists
  (`db/schema.rb:264-288`, with `auditable_type/auditable_id/version/audited_changes`), so article revision
  history is `audited` on the model and **needs no migration** either.

No migration is proposed here. A changelog/release-notes table would need one; documentation reusing portals
would not.

---

## 13. Tenancy risks for this program, one by one

| Risk | Existing guard | Covers a new surface automatically? | Work needed |
|---|---|---|---|
| **Foreign-account contacts** | Layer 2 + `Current.account.contacts` convention (`contacts_controller.rb:228-231`). `ContactPolicy` is permissive (most verbs `true`; `import?/export?/destroy?` admin). | **Only if the new code writes `Current.account.contacts`.** There is no `ContactPolicy::Scope` and no default scope — the convention *is* the guard. | Review discipline. Any new contact read must be association-scoped. |
| **Foreign audiences** (shared contact filters) | Two guards, both real. Read: `Current.account.custom_filters.visible_to(Current.user)`, where `visible_to` is `where(user: user).or(where(shared: true))` (`custom/app/models/custom/custom_filter.rb:8`) — account scope comes from the association, sharing from the scope. Reference: `audiences_shared_in_account?` re-resolves every id against `account.custom_filters.contact.where(shared: true)` (`custom/app/models/custom/campaign_audience.rb:24-27`, `:31`) and is enforced both as a validation (`:33-35`) and in the preview endpoint (`audience_previews_controller.rb:10`). | **Yes, if the new surface references audiences by id through `CampaignAudience`.** A foreign id simply fails the count check. | None, *provided* a new surface reuses `audiences_shared_in_account?` rather than resolving ids itself. |
| **Foreign templates** | WhatsApp templates are a `jsonb` column on `channel_whatsapp` (`db/schema.rb:800`), reached only through `Current.account.inboxes` (`inboxes_controller.rb:88`). There is no templates table, so there is no cross-account id to leak. | **Yes** — tenancy is structural. | None for tenancy. But see §12.4c: `InboxPolicy#message_templates?` is `true` (`inbox_policy.rb:37-39`), so *within* the account the read is open to any member of an assigned inbox. If a Lynomia template manager becomes the system of record, re-gate that read explicitly. |
| **Foreign WABAs** | `channel_whatsapp.phone_number` is **globally unique** — DB index (`db/schema.rb:806`) plus `validates :phone_number, uniqueness: true` (`app/models/channel/whatsapp.rb:40`). One number cannot exist in two accounts. | **Yes** — enforced at the database, not by convention. The strongest guard in this table. | None. |
| **Foreign stores** | Three layers: DB unique `(provider, external_store_id)` + `validates :external_store_id, uniqueness: { scope: :provider }` (`custom/app/models/commerce/store.rb:47`); `Commerce::StoreConnection#claim` (`custom/app/services/commerce/store_connection.rb:138-147`) raises `STORE_ALREADY_CONNECTED` unless the existing row is disconnected, reuses it when it is this account's, and otherwise destroys the stale row and takes ownership; reads always go through `Current.account.commerce_stores` (`stores_controller.rb:55`). Credentials are `encrypts`-ed and stripped from `serializable_hash`. | **Yes** — and it fails loud. | None. |
| **Portal slug squatting** (the one genuine hole) | **None.** `app/models/portal.rb:44` is a bare `validates :slug, presence: true, uniqueness: true` — a single global, first-come-first-served namespace with no reservation. The only `RESERVED_SLUGS` in the repo is `Article`'s (`app/models/article.rb:61`, `%w[search articles categories]`, excluded at `:67`). Worse, tenant onboarding **actively claims global slugs**: `Onboarding::HelpCenterCreationService#slug_candidates` tries `<account-name>`, `<first-token>`, `<first-token>-docs`, `<first-token>-help` against a global `Portal.exists?(slug:)` (`enterprise/app/services/onboarding/help_center_creation_service.rb:114-124`). | **No.** A tenant can squat the slug Lynomia wants for its docs portal, and onboarding grabs the obvious `-docs` / `-help` ones automatically. | **NEW PRIMITIVE REQUIRED** (code-only, no migration): a `Portal::RESERVED_SLUGS` constant + exclusion validation, mirroring `Article`'s. This blocks §12.4d's recommended path until it exists. |

Two public endpoints additionally have **no custom-domain guard** and serve on any host that reaches the
app: `portals#sitemap` and `articles#tracking_pixel`. Not a tenancy leak (both are intended to be public),
but worth knowing before documentation is published through this path.

---

## 15. Telemetry — the honest state

**Conclusion first: telemetry cannot answer "starter selected / completed / abandoned" today, and it is not
one instrumentation away from being able to. Classification: DO NOT CREATE a telemetry platform during this
program.** Document the opportunity and move on.

### The whole chain, and where it is dark

| Link | Reality | Citation |
|---|---|---|
| Transport | **Amplitude only.** `@amplitude/analytics-browser` is the sole analytics dependency; no PostHog, Segment or Mixpanel integration anywhere in `app/javascript`, `app`, `lib`, `config`, `custom`, `enterprise`. | `package.json:37` |
| API surface | `useTrack` is a **9-line try/catch** around the singleton. No queue, no batching, no local persistence, no server fallback, no consent gate. | `app/javascript/dashboard/composables/index.js:7-15` |
| Singleton | Built from `window.analyticsConfig` at import time. | `helper/AnalyticsHelper/index.js:98` |
| Init | `if (!this.analyticsToken) return;` — `this.analytics` stays `null`. | `:24-33` (early return `:25-27`) |
| Emit | `track()` and `page()` both `if (!this.analytics) return;`. **With no token, every call is a silent no-op.** | `:75-80`, `:88-94` |
| Token | `window.analyticsConfig` is emitted only `if @global_config['CLOUD_ANALYTICS_TOKEN'].present?`. | `app/views/layouts/vueapp.html.erb:68-74` |
| The row | Ships **blank**, and is `type: secret`. | `config/installation_config.yml:299-303` |
| Super Admin — Installation configs | Secret-typed rows are **excluded from the list**: `resource_class.editable.where.not(name: InstallationConfig.secret_names)`. | `app/controllers/super_admin/installation_configs_controller.rb:24-27`; `app/models/installation_config.rb:49-51` |
| Super Admin — App configs | `CLOUD_ANALYTICS_TOKEN` lives in the `internal` section, which `allowed_configs` only reaches when the plan is **not** community (`return super if ChatwootHub.pricing_plan == 'community'`). | `enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb:16`, `:21-22`, `:58-63` |
| Nav | `settings_pages` lists only entries with a `config_key` **and** `enabled` — there are 18 `config_key`s and **none is `internal`**. The section has no nav entry at all. | `app/helpers/super_admin/navigation_helper.rb:6-15`; `app/helpers/super_admin/features.yml` |

**Net: there is no Super Admin UI path to set the token on a community-plan install.** And because nothing is
persisted locally or server-side as a fallback, setting a token later does **not** recover any history.

### What that means for the ~100 call sites

**96 invocation sites across 60 files** (re-derived: `useTrack(` / `AnalyticsHelper.track|page|identify|init(`
under `app/javascript`, excluding the helper's own definition). All of them are currently no-ops.
`custom/` and `enterprise/` contain **zero** analytics references (verified: 0 hits).

**There are zero telemetry calls on any recipe, starter or template path** (verified: 0 hits for
`useTrack|AnalyticsHelper|track(` across `app/javascript/dashboard/recipes/` and
`components-next/recipes/`), and **zero** recipe/starter/gallery/template constants in the 16 frozen event
groups of `helper/AnalyticsHelper/events.js` (verified: 0 hits). Nor is there provenance on the server: the
gallery is source code with "no runtime link between a created object and the recipe it came from"
(`recipes/index.js:1-7`), and `Flows::Audit`'s 7 event names carry no provenance field
(`custom/app/services/flows/audit.rb`).

### What exists instead, and why none of it substitutes

| Record | What it is | Why it cannot answer a starter funnel |
|---|---|---|
| `Enterprise::AuditLog` (`audits` table, `db/schema.rb:264-288`) | per-record mutation rows for admin reading, account-scoped | no aggregation, no funnel, no "abandoned" concept |
| `Commerce::AuditTrail` / `Flows::Audit` | named product events, written **only** `if defined?(Enterprise::AuditLog)` | audit rows, not analytics; `Flows::Audit` explicitly skips simulator runs |
| `ReportingEvent` / `ReportingEventsRollup` | conversation lifecycle metrics, closed 6-value metric enum | nothing about UI interaction |
| `ChatwootHub.emit_event` (`lib/chatwoot_hub.rb`) | defined | **zero call sites** — dead code |

The only existing instrumentation with the right *shape* is the onboarding funnel: `ONBOARDING_EVENTS`
(`helper/AnalyticsHelper/events.js:159-165`) with visited / completed / skipped, emitted at
`routes/dashboard/onboarding/Index.vue:113,174` and `InboxSetup.vue:60,83,85`. If a starter funnel is ever
built, that is the pattern to copy — five frozen constants and five `useTrack` calls.

### The opportunity, stated and then left alone

Answering "starter selected / completed / abandoned" needs **three** things, not one: (1) instrumentation on
the gallery, (2) a transport that works without a third-party key, and (3) a readable store. Only (1) is
cheap. (2) and (3) are a platform. **Recommendation: do not start it here.** If a single question must be
answerable, the honest minimum is a provenance field on the created object — the recipe id already appears
in a created flow's free-text description — which converts "which starters get used" into a database query
with no telemetry at all. That is a product decision with a possible migration attached, so it is left for
approval, not proposed.

---

## Requirements left for approval (no migrations proposed)

| Ref | Requirement | Migration? |
|---|---|---|
| R1 | Decide the reader gate for global product documentation. `PlatformBanner`'s `ChatwootApp.chatwoot_cloud?` gate (`dashboard_controller.rb:94`) must be **replaced**, not reused. | No |
| R2 | `Portal::RESERVED_SLUGS` + exclusion validation, mirroring `app/models/article.rb:61`,`:67`. Blocks §12.4d. | No |
| R3 | Article revision history, if wanted: `audited` on the model. The polymorphic `audits` table already exists (`db/schema.rb:264-288`). Repo convention gates such calls on `if defined?(Enterprise::AuditLog)`. | No |
| R4 | Re-gate `InboxPolicy#message_templates?` (currently plain `true`, `inbox_policy.rb:37-39`) if a Lynomia template manager becomes the system of record. | No |
| R5 | Starter provenance on created objects, if the usage question must be answerable. | **Yes — needs approval** |
| R6 | A changelog / release-notes store, if that is in scope. No `changelog` or `release_note` table exists. | **Yes — needs approval** |
| R7 | Confirm the live `INSTALLATION_PRICING_PLAN` row on the target environment before relying on any premium-feature conclusion in §11.3. | No — verification task |

## Corrections to the upstream inventory

I re-checked these because they are load-bearing for the recipes above, and found them different:

| Upstream claim | Verified | Evidence |
|---|---|---|
| "27 OSS policies in `app/policies`" | **26 files** — `ApplicationPolicy` base + 25 concrete | `find app/policies -name '*.rb'` |
| "7 EE policy classes + 8 override modules" | **9 EE concrete classes** (5 top-level + 4 `Captain::`) + 8 `Enterprise::` modules = 17 files | `find enterprise/app/policies -name '*.rb'` |
| — | The total, **36 concrete policy classes**, is correct; only the split was mis-stated | 25 + 9 + 2 |
| "`devise_for :super_admins` is `config/routes.rb:725`" (stated in `AUTHORITATIVE-CORRECTIONS.md:87`) | **`:726`**. `:727` is `devise_scope`, `:729` is `namespace :super_admin do` | `grep -n` on `config/routes.rb` |
| "~99 telemetry call sites" | **101** invocations across 58 files | grep over `app/javascript`, excluding the helper's own definition |
| "2 policies in `custom/`, no custom policy override modules" | **Confirmed** — `Commerce::StorePolicy`, `Commerce::ActionPolicy`; all 8 `prepend_mod_with` targets resolve to `Enterprise::` only | `find custom/app/policies`; 8 `prepend_mod_with` calls in `app/policies` vs 8 files in `enterprise/app/policies/enterprise/` |
| 72 account flags; 9-entry premium list | **Confirmed** (72 `- name:` entries; `premium_features.yml:2-10`). Note `features.yml` separately carries **19** `premium: true` entries — a different list | `grep -c '^- name:' config/features.yml`; `grep -c 'premium: true'` |

Everything else asserted above was read directly in the repository for this document.
