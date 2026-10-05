# 04 — Permissions, tenancy, audit and the conventions a new Lynomia surface must follow

Read with `00-current-system.md` (what exists) and `02-local-record-design.md` (the record).
Every rule here is an existing rule of this codebase. P3 introduces **no second authorization model** (PART 17) and
**no new audit system** (PART 18).

---

## 1. Who may do what

| Action | Rule | Precedent it copies |
|---|---|---|
| See the template list / a template's detail | **administrator** | the existing page is already admin-only: `templates.routes.js:17` `meta: { permissions: ['administrator'] }` |
| Create / edit / submit / delete / duplicate a template | **administrator** | `InboxPolicy#sync_templates?` (`app/policies/inbox_policy.rb:71-73`), `InboxPolicy#create?/update?/destroy?` (`:51-61`), `CampaignPolicy` (every action, `app/policies/campaign_policy.rb:14-16`) |
| Sync from WhatsApp | **administrator**, unchanged | `InboxPolicy#sync_templates?` |
| Pick an approved template when writing a reply, a campaign or a flow | **unchanged from today** — any inbox member in the composer, administrator for campaigns and flows | `InboxPolicy#message_templates?` (`:43-45`), `CampaignPolicy` |

**Why administrator, and not a new custom-role permission key.** `CustomRole::PERMISSIONS`
(`enterprise/app/models/custom_role.rb:37-45`) is `conversation_manage`, `conversation_unassigned_manage`,
`conversation_participating_manage`, `contact_manage`, `report_manage`, `knowledge_base_manage` and Lynomia's
`commerce_order_manage`. **There is no key for inboxes, channels, campaigns or templates.** Adding one would need
three coordinated edits (the `PERMISSIONS` constant validated by `inclusion:` at `:48`, the frontend mirror at
`app/javascript/dashboard/constants/permissions.js:1-9`, and the policy module that consumes it) and would be a second
authorization model for a capability whose neighbours — inbox creation, campaign creation, template sync — are all
plain `administrator?`. Template management writes to Meta under the account's own credentials; it belongs with those.

**Why no new feature flag.** `config/features.yml`'s `feature_flags` column is full at 63/63, so a new flag must go in
`feature_flags_ext_1` and be appended at the end, because bit positions are persisted per column
(`app/models/concerns/featurable.rb:5-6, 15-35`). More to the point: the read-only template page is live and unflagged
today, so flagging the manager would hide from an account a screen it can already see. P3 extends an unflagged
surface and stays unflagged. (`lynomia_commerce` and `lynomia_flow_builder` are flagged because they are whole new
products; this is not.)

**What must not be "fixed".** `InboxPolicy#message_templates?` returns `true` unconditionally, with a comment at
`:37-42` explaining why. `check_authorization` authorizes the **Inbox class**, not an instance
(`app/controllers/api/base_controller.rb:14-18`), so `Current.user.assigned_inboxes.include?(Inbox)` is always false
and a "membership check" there would lock out administrators. Leave it alone.

**Where the policy lives.** `app/policies/inbox_policy.rb` has **no `prepend_mod_with` tail** — unlike
`ContactPolicy` and friends — so an `enterprise/` or `custom/` `InboxPolicy` override would be silently ignored. The
new resource therefore gets its **own** policy class, following the Lynomia precedent
`custom/app/policies/commerce/store_policy.rb` (`class Commerce::StorePolicy < ApplicationPolicy`), authorized with
the inline-lambda convention `before_action -> { authorize(::Whatsapp::MessageTemplate) }`.

**Ordering inside the controller**, copying the deliberate choice in
`app/controllers/api/v1/accounts/inbox_csat_templates_controller.rb:12-15`: the role check runs **before** any record
fetch, so a non-administrator gets a 401 instead of learning from a 404 whether a template exists.

---

## 2. Tenancy

Three boundaries, each enforced by something structural rather than by a filter someone can forget.

1. **Account.** Every row carries `account_id` (`null: false`, FK cascade) and every query is scoped through
   `Current.account`. `account_id` leads the identity index
   (`index_whatsapp_message_templates_on_identity`), so one tenant's rows cannot collide with another's, and the
   partial unique index on `(account_id, meta_template_id)` is account-scoped rather than global — two Lynomia
   accounts connected to the same WABA each manage their own view of it.
2. **WABA.** `business_account_id` is part of the identity key, so a template named `order_update` in language `en_US`
   on WABA A and the same on WABA B are two independent rows. **One WABA can never overwrite another's same-named
   template** (PART 1.3), and nothing is duplicated across unrelated WABAs (PART 16).
3. **Inbox.** Not a boundary for a template, deliberately: several inboxes can share one WABA
   (`00-current-system.md §4.2`), and Meta's template is a property of the WABA. The manager presents a template with
   the inboxes that can send it, which is how `templateUtils.js:38-47` already groups the read-only page.

**Multi-WABA is the normal case, not an edge case.** `business_account_id` lives in the `provider_config` jsonb with
no uniqueness, no index and no validation (`00-current-system.md §4.2`); the repo already queries WABA siblings with
`Channel::Whatsapp.where("provider_config->>'business_account_id' = ?", waba_id)`
(`app/services/whatsapp/webhook_setup_service.rb:100`), and `Whatsapp::WebhookSetupService#calls_enabled_on_waba?`
exists precisely because one WABA spans channels. P3 uses that same query wherever it needs a channel for a WABA.

**Coexistence** (`provider_config['is_coexistence']`) changes nothing here: a coexistence inbox is an ordinary
`Channel::Whatsapp` with a WABA, so its templates are managed by the same one manager (PART 15). The only
coexistence-specific rule already in the code is `Whatsapp::AuthenticationTemplateGuard`, which blocks an
AUTHENTICATION-category template to a BSUID-only recipient (`authentication_template_guard.rb:12-18`) — and P3 does
not author authentication templates at all (`01-meta-api-contract.md §5`).

**Secrets never cross the boundary.** The record stores no token (`02-local-record-design.md §2`). Writes to Meta use
`Channel::Whatsapp#template_access_token` (`app/models/channel/whatsapp.rb:85-89`) — the same selector the sync uses,
not the raw `provider_config['api_key']` the CSAT service uses, which would fail every write on an embedded-signup
cloud install (`00-current-system.md §4.3`). `SECRET_PROVIDER_CONFIG_KEYS` keeps credentials out of inbox payloads
(`app/models/channel/whatsapp.rb:34`), and the new jbuilder partial follows the Commerce convention of an **explicit
allow-list** rather than a serializer exclusion (`custom/app/views/api/v1/accounts/commerce/stores/_store.json.jbuilder`).

**No browser ever holds a Meta token and no browser ever calls Meta** (PART 7). The browser calls Lynomia; Lynomia
calls Graph.

---

## 3. Audit

**The mechanism already exists and is reused unchanged.** The `audited` gem (`Gemfile:184`) with
`Audited.config.audit_class = 'Enterprise::AuditLog'` (`config/initializers/audited.rb:3-5`), whose sweeper is an
`around_action` on every controller and captures the acting user, remote address and request uuid.

**How the new model opts in.** The OSS pattern is a two-step — an OSS model file calling
`include_mod_with('Audit::<Model>')` plus an overlay concern — because EE code must stay out of OSS files. The new
model lives entirely under `custom/`, so there is no OSS file to amend and no reason for the indirection: it declares

```ruby
audited associated_with: :account if defined?(Enterprise::AuditLog)
```

in its own class body, with the same `defined?` guard as the Lynomia precedent
`custom/app/models/custom/audit/custom_filter.rb`. That gives create, update and destroy rows with the actor,
which is **why the record needs no `created_by_id` column** (`02-local-record-design.md §2`).

**Two consequences that are easy to miss:**

1. **A new auditable type renders unlabelled in the UI** unless keys are added to
   `app/javascript/dashboard/helper/auditlogHelper.js:12-44`. The key is
   `` `${auditable_type.toLowerCase()}:${action.toLowerCase()}` `` (`:218-228`), so for `Whatsapp::MessageTemplate`
   the three keys are `whatsapp::messagetemplate:create` / `:update` / `:destroy`, mapped to new
   `AUDIT_LOGS.WHATSAPP_TEMPLATE.{ADD,EDIT,DELETE}` strings in
   `app/javascript/dashboard/i18n/locale/en/auditLogs.json` (EN and AR, per PART 23). The type is also added to
   `EVENT_TYPE_GROUPS` (`:230+`) so the log can be filtered by it. This is exactly what P2 did for
   `customfilter:*` → `AUDIT_LOGS.AUDIENCE.*` (`auditlogHelper.js:29-31`, `auditLogs.json:95-99`).
2. **The `audit_logs` feature flag gates reads only** (`config/features.yml:111-115`;
   `enterprise/app/controllers/api/v1/accounts/audit_logs_controller.rb:19-23` returns `.none` when disabled).
   Rows are written on every installation that has `Enterprise::AuditLog` defined. That is the existing behaviour for
   every audited model and is not changed here.

**Submit, edit and delete are model writes**, so the gem records them without a bespoke event. Where a lifecycle fact
is not a model write — nothing in P3 currently needs one — the precedent would be `custom/app/services/flows/audit.rb`
or `custom/app/services/commerce/audit_trail.rb`, which create `Enterprise::AuditLog` rows directly behind a
`defined?` guard. **No new audit table, no new audit service** (PART 18).

**What is never logged** (PART 18, PART 19): tokens, `provider_config` secrets, `business_management_token`, or any
Meta credential. `submission_error` holds the safe structured message only; the full Graph response goes to
`Rails.logger` with the credential stripped, which is the same discipline
`Whatsapp::Providers::BaseService#handle_error` already follows.

---

## 4. Conventions a new Lynomia surface must follow

Verified at this HEAD, so the implementation has nothing to guess.

### Migrations

- `custom/db/migrate` is appended to the migration path at `config/application.rb:56`, so the ordinary
  `rails db:migrate` runs it. There is no separate task and **no `custom/db/schema.rb`** — `db/schema.rb` is the
  single generated schema for both trees, and its current version `2026_10_04_110000` is itself a custom migration.
- **A new custom migration must land with a regenerated `db/schema.rb` in the same change**, or the next
  `db:schema:load` silently omits the table.
- Style: one `create_table` in `change`; a comment above the class naming the doc it implements;
  `ActiveRecord::Migration[7.2]`; `t.references … null: false, foreign_key: { on_delete: :cascade }`;
  `index: false` when a composite index supersedes the default one. The model carries an `annotaterb` schema header.
- Online/data migrations use `disable_ddl_transaction!` + `algorithm: :concurrently` + an explicit
  `SET statement_timeout = '0'` and `up`/`down` — see
  `custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb`. **P3's migration needs none of
  that**: it creates an empty table (`02-local-record-design.md §4`).

### Models

- `custom/app/models/<namespace>/<name>.rb`, autoloaded via
  `config.eager_load_paths += Dir["#{Rails.root}/custom/app/**"]` (`config/application.rb:52-54`).
- `< ApplicationRecord`, an **explicit `self.table_name`** (a `Whatsapp::` prefix is not a Rails
  table-name-prefixed module, so without it Rails would look for `message_templates`), frozen constant allow-lists
  with `validates … inclusion:`, `belongs_to :account` on every tenant row, and explicit
  `class_name:`/`foreign_key:`/`inverse_of:` on cross-namespace associations.
  Reference: `custom/app/models/commerce/store.rb`.
- Associating onto a core model goes through the overlay (`custom/app/models/custom/account.rb` via
  `Account.prepend_mod_with('Account')`), **never** by editing `app/models/account.rb` or `app/models/inbox.rb`.

### Routes and controllers

- There is no `custom/config/routes.rb`. A Lynomia route file lives in the OSS `config/routes/` directory and is
  pulled in with `draw :<name>` at `config/routes.rb:787-790` (today: `billing`, `commerce`, `flows`,
  `campaign_audiences`). Each file re-opens
  `namespace :api → namespace :v1 → resources :accounts, only: [] → scope module: :accounts`. Reference:
  `config/routes/flows.rb`.
- Controllers live at `custom/app/controllers/api/v1/accounts/…` and inherit
  `Api::V1::Accounts::BaseController`. The shape is: a header comment listing each route and its params, feature
  guard first (none here, §1), then `before_action -> { authorize(::Model) }`, then the record fetch, with
  `rescue_from` mapping a domain error to 422. Reference:
  `custom/app/controllers/api/v1/accounts/commerce/stores_controller.rb:1-20`.
- **Validate at the boundary.** Malformed input raises `ActionController::ParameterMissing`, which
  `app/controllers/concerns/request_exception_handler.rb:11-12` turns into **422**, so bad client input never reaches
  a model or Sentry — the rule CLAUDE.md states and the Commerce controller follows.
- Views: `custom/app/views` is prepended at `config/application.rb:55`; a `_<resource>.json.jbuilder` partial with an
  explicit allow-list plus thin `index`/`show`.
- **The existing endpoints keep their contracts.** `GET /inboxes/:id/message_templates` and
  `POST /inboxes/:id/sync_templates` are not changed, not re-scoped and not deprecated this phase
  (`00-current-system.md §5`), because the composer, the campaign form, the flow editor and the mobile app read them.

### Frontend

- **`custom/` contains no frontend files at all.** Every Vue/JS change goes in `app/javascript`.
- The manager extends `app/javascript/dashboard/routes/dashboard/settings/templates/` — the existing route
  `settings_templates`, `Index.vue`, `TemplateCard.vue`, `TemplatePreviewDrawer.vue`, `templateUtils.js` — and reuses
  `components-next/template-preview/` for the live preview. No second page, no new design system, no scoped CSS
  (PART 21).
- i18n: the `WHATSAPP_TEMPLATE_MGMT` namespace already exists
  (`app/javascript/dashboard/i18n/locale/en/whatsappTemplateMgmt.json`), already reserves
  `STATUSES.UNSUBMITTED` with no producer (`:22`), and gets its new keys in **EN and AR** only — every other locale
  is Crowdin's (CLAUDE.md). UI locale is never confused with a template's language (PART 23): the template's language
  is data on the record, rendered as a language name, and a right-to-left template body is previewed right-to-left
  whatever the dashboard locale is.

---

## 5. Super Admin

There is **no Super Admin dashboard for Inbox, Channel, Campaign or template data**, so no super-admin surface is
added. What a Super Admin can already do that touches this area is indirect and unchanged: toggle an account's feature
flags, set account limits, set installation-wide WhatsApp credentials
(`WHATSAPP_APP_ID`, `WHATSAPP_APP_SECRET`, `WHATSAPP_API_VERSION`, `INACTIVE_WHATSAPP_NUMBERS`), grant the
administrator role, seed or delete an account, and watch `Channels::Whatsapp::TemplatesSyncJob` in Sidekiq Web.

One of those is a genuine P3 prerequisite and belongs in the operator documentation, and it is two values:

1. **`WHATSAPP_APP_WEBHOOK_VERIFY_TOKEN`**, set in Super Admin → Installation Configs, which is what Meta's
   subscription handshake on the app-level callback is checked against. The same store already holds
   `WHATSAPP_APP_ID`, `WHATSAPP_APP_SECRET` and `WHATSAPP_API_VERSION`, so this is one more key there, not a new
   credential store.
2. The **Meta App Dashboard's default callback URL**, which must point at `{FRONTEND_URL}/webhooks/whatsapp`, because
   Meta never delivers a template webhook to a phone-level or WABA-level override
   (`01-meta-api-contract.md §8`). That one is Meta-side configuration, not a setting in this product.

Nothing breaks without either: status still moves on the existing sync and on the manual sync button
(`03-sync-and-lifecycle.md §4.4`).

---

## 6. The authorization surface, end to end

```
browser (administrator session)
  │  no Meta token, never calls Meta
  ▼
Api::V1::Accounts::Whatsapp::MessageTemplatesController  < Api::V1::Accounts::BaseController
  │  before_action -> { authorize(::Whatsapp::MessageTemplate) }   (role check BEFORE any fetch)
  │  Current.account scopes every query
  ▼
Whatsapp::MessageTemplate   (account_id + business_account_id in the identity index; audited)
  │
  ▼
the WABA's channel, found with provider_config->>'business_account_id'
  │  Channel::Whatsapp#template_access_token
  ▼
Graph API v24.0
```

Nothing in that chain is new except the controller, the policy and the model. The credential selection, the account
scoping, the audit sweeper, the 422 boundary and the Graph client are all existing machinery.
