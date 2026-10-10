# Integration contract

**Audience: the clean-room implementer.**

Everything in this document is a **currently live public contract** of the running product: a URL, a response
key, a column, a capability name, or a method that clean code outside your five packages already calls. None of
it describes how anything was previously implemented; all of it is observable from the workspace you were
given.

## How to read this

| marking | meaning |
|---|---|
| **MUST REMAIN COMPATIBLE** | something outside your five packages depends on this exactly as written. Changing it breaks working code, a shipped frontend, or production data |
| **MAY BE REDESIGNED** | internal to the five packages. Nothing outside them depends on it. Your call, entirely |

Where a row says MUST REMAIN COMPATIBLE and you believe it is wrong, the answer is to raise it, not to change
it quietly: the thing that depends on it is in the workspace and will keep calling it.

---

## 1. Routes — MUST REMAIN COMPATIBLE

All of these already exist in `config/routes.rb` and are already called by the shipped frontend. The paths,
the HTTP verbs and the parameter names are the contract.

| route | verb | file:line | caller |
|---|---|---|---|
| `/api/v1/accounts/:account_id/audit_logs` | `GET` | `config/routes.rb:84` (a singular `resource`, so it maps to `#show`) | `dashboard/api/auditLogs.js` |
| `/api/v1/accounts/:account_id/custom_roles` | `GET`, `POST` | `config/routes.rb:100` | `dashboard/api/customRole.js` |
| `/api/v1/accounts/:account_id/custom_roles/:id` | `GET`, `PATCH`/`PUT`, `DELETE` | `config/routes.rb:100` | same |
| `/api/v1/accounts/:account_id/campaigns/:campaign_id/analytics/metrics` | `GET` | `config/routes.rb:104` | `dashboard/api/campaigns.js:11` |
| `/api/v1/accounts/:account_id/campaigns/:campaign_id/analytics/contacts` | `GET` | `config/routes.rb:105` | `dashboard/api/campaigns.js:20` |
| the agent create/update endpoints that accept a role | `POST`, `PATCH` | the account `agents` resource | `routes/dashboard/settings/agents/{AddAgent,EditAgent}.vue` |
| the WhatsApp webhook endpoints | `GET`, `POST` | the `webhooks/whatsapp` routes | Meta |

**MAY BE REDESIGNED:** nothing. Do not add, rename or nest a route in these five areas; the frontend is not
part of the rewrite and will not be adjusted for you.

---

## 2. In-process call surfaces — MUST REMAIN COMPATIBLE

This is the section most easily missed, and the most expensive to miss. **Clean code that is not part of your
rewrite calls into your packages.** If you rename these, that clean code stops working.

### 2.1 The audit record's entry point — seven clean callers

Seven pieces of clean Lynomia code write audit records today. None is part of the rewrite. Every one of them
calls `Custom::AuditLog`:

| caller | file:line | phase |
|---|---|---|
| contact merge | `custom/app/actions/custom/contact_merge_action.rb:75` | P10 |
| commerce store connections | `custom/app/services/commerce/audit_trail.rb:27` | Commerce |
| flow lifecycle | `custom/app/services/flows/audit.rb:11` | Flow Builder |
| plan entitlement edits | `custom/app/services/billing/plan_audit.rb:24` | P11 |
| entitlement overrides | `custom/app/services/billing/override_grant.rb:132` | P11 |
| plan-sync revocations | `custom/app/services/billing/feature_sync.rb:54` | P11 |
| audience auditing | `custom/app/models/custom/audit/custom_filter.rb` | pre-P8 (via the `audited` macro, not a direct call) |

Between them they use:

| call | used by |
|---|---|
| `Custom::AuditLog.create!(auditable:, associated:, user:, action:, comment:, audited_changes:)` | all six direct callers; `remote_address:` is also passed by some |
| `Custom::AuditLog.create(...)` (non-bang) | one caller, which must not raise on a failed record |
| `Custom::AuditLog.insert_all!(rows)` | the bulk path, writing explicit columns including `version` and `request_uuid` |
| `Custom::AuditLog.unscoped.auditable_finder(<id>, '<Type>').maximum(:version)` | the bulk path, to continue a record's version sequence |
| `#user` must be **polymorphic** | P11's override grant, whose actor is a `SuperAdmin`, not a plain `User` |

So: **the constant `Custom::AuditLog`, those keyword names, and the polymorphic actor are a contract.** Either
keep them, or update all seven callers in the same change — and if you do the latter, say so, because those
callers have their own tests which are not part of your scope.

`auditable_finder` is the `audited` gem's own scope, so it comes for free if the record remains an
`Audited::Audit` subclass.

### 2.2 The capability list

| call | callers (all clean, none in scope) |
|---|---|
| `account_user.permissions` → an array of strings | `custom/app/policies/commerce/action_policy.rb:20`, `custom/app/policies/support/ticket_policy.rb:25` and `:49`, `custom/app/policies/custom/contact_policy.rb:18`, and OSS `app/views/api/v1/models/_user.json.jbuilder` |
| the capability strings themselves | `'commerce_order_manage'`, `'support_ticket_manage'`, `'contact_manage'` are declared as constants in those three clean policies. **The strings are fixed** |
| `'custom_role'` as a marker in the list | `dashboard/helper/permissionsHelper.js:getUserRole` treats a membership with a role as the role `custom_role` |
| `CustomRole::PERMISSIONS` | `spec/factories/custom_roles.rb` (upstream MIT, clean). Either keep the constant or update the factory |
| `account_user.custom_role_id` | OSS `app/views/api/v1/models/_agent.json.jbuilder`, OSS `app/models/account_user.rb:86` (it invalidates a cached visibility when the attachment changes) |
| `account_user.custom_role` association | OSS `app/views/api/v1/models/_user.json.jbuilder` preloads it with `includes(:custom_role)` |

### 2.3 The campaign recipient record

| call | caller |
|---|---|
| `CampaignRecipient.where(account_id: ..., created_at: ...)` and the scopes built on it | `custom/app/services/analytics/campaigns/metrics.rb` (P8), throughout |
| `status: :skipped` and `status: :queued` **by name** | same file |
| `delivered_at`, `read_at`, `failed_at`, `error_code`, `error_message`, `source_id`, `campaign_id`, `inbox_id` read directly in SQL | same file |

### 2.4 Internal to the five packages — MAY BE REDESIGNED

Nothing outside the five packages calls these, so they are yours:

- how a provider send error reaches the recipient record (today a reader on the channel and one on the provider
  service — both are rewritten files, so the mechanism is open);
- whether the delivery-report application runs inline or through a job, and what that job is called;
- the names, arity and decomposition of every method inside your packages;
- the read scopes on the audit record;
- how address masking is expressed;
- how capture points are registered (model macro, controller hook, service call — §2.1 only fixes the write
  entry point, not the hook style).

---

## 3. Wire format — MUST REMAIN COMPATIBLE

The frontend is clean, shipped and **not part of the rewrite**. These keys are read by name.

### 3.1 Audit trail

| consumer | keys it reads |
|---|---|
| `dashboard/store/modules/auditlogs.js` | `audit_logs`, `total_entries`, `per_page`, `current_page` |
| `dashboard/helper/auditlogHelper.js` | per entry: `auditable_type`, `action`, `auditable_id`, `user_id`, `audited_changes`; and the `<type>:<action>` label vocabulary this file enumerates |
| `routes/dashboard/settings/auditlogs/Index.vue` | `created_at`, `remote_address`, `username` |
| `routes/dashboard/settings/auditlogs/components/AuditLogFilters.vue` | the request parameters `type`, `sort`, `since`, `until`, `range`, `user_id`, `page` |

### 3.2 Roles and memberships

| consumer | keys |
|---|---|
| the role settings pages | a role's `id`, `name`, `description`, `permissions` |
| `permissionsHelper.js` | on each entry of the user's `accounts`: `permissions`, `custom_role_id`, `role` |
| OSS `_user.json.jbuilder` | renders the partial `api/v1/models/_account_user`, which must therefore keep that path and emit the membership's role attachment |
| the agent list | `custom_role_id` per agent |

### 3.3 Campaign results

| consumer | keys |
|---|---|
| `WhatsAppCampaignAnalyticsPage.vue` | `audience`, `sent`, `delivered`, `read`, `failed`, `skipped`, `status_counts.{queued,sent,delivered,read,failed,skipped}`; and on the list response `payload`, `meta.total_count` |
| `CampaignDeliveryBreakdown.vue` | the same counters, used arithmetically — see `specs/D-campaign-recipient-outcomes.md` §2 |
| `CampaignDeliveryTable.vue` | per row: `contact.{id,name,phone_number}`, `status`, `message_content`, `error_code`, `error_title`, `error_message` |
| `DeliveryStatusBadge.vue` | `status` as a short lower-case token; an unknown one is displayed verbatim |

### 3.4 Locale keys

The interface's strings live in `config/locales/en.json` (frontend) and `config/locales/en.yml` (backend) and
are already written for these surfaces, in English and Arabic. A new key needs a translation; a renamed key
silently renders as the key. Where a key's **name** is wrong for the product — package C §9 names one family of
them — renaming it is a deliberate, declared change, not a side effect.

---

## 4. Database contracts — MUST REMAIN COMPATIBLE

Production data exists. See `specs/A` §3, `specs/C` §3 and `specs/D` §3 for the column lists; the summary:

| table / column | why it is fixed |
|---|---|
| `audits` (all columns, six indexes) | the `audited` gem's table; seven clean writers and the read surface use it |
| `audits.city`, `.country`, `.country_code` | must stay **unwritten and unread** |
| `custom_roles` (`account_id`, `name`, `description`, `permissions` text array) | existing rows; the OSS factory |
| `account_users.custom_role_id` | existing attachments; OSS code reads it |
| `campaign_recipients` (every column; status enum values `queued 0 … skipped 5`; the unique `(campaign_id, contact_id)`, the unique partial `source_id`, and `(campaign_id, status)`) | existing rows and P8's SQL |
| `messages.source_id`, `.status`, `.external_error` | OSS; package E's join |
| `sla_policies`, `campaigns`, `accounts`, `account_users` | upstream tables |

**No migration is expected.** If you conclude one is needed, it must be additive, and
`docs/p-final/03-migration-review.md` (in the workspace) states the rules this release deploys under —
including why a non-concurrent index build or a volatile column default is not acceptable here.

---

## 5. Capabilities and feature flags — MUST REMAIN COMPATIBLE

Capabilities are declared in `config/features.yml`, read with `account.feature_enabled?('name')`, and are
already set on production accounts.

| capability | line | governs |
|---|---|---|
| `audit_logs` | `config/features.yml:112` | whether the account has an audit trail at all. Off ⇒ package A returns an empty page, **not** an error |
| `audit_log_ip_address` | `config/features.yml:277` | whether the full originating address is disclosed |
| `custom_roles` | `config/features.yml:148` | whether named permission sets are available |
| `whatsapp_campaign` | `config/features.yml:193` | already enforced by the OSS campaign path |

Two rules:

- **Do not invent a new flag** for any of the five packages. These four already exist and are already set.
- If a capability should additionally depend on the customer's plan, ask `Billing::Entitlements` (P11,
  `custom/app/services/billing/entitlements.rb`). Do not build a second entitlement path.

---

## 6. Features that may simply be removed instead of rewritten

**None.** Every one of the 44 affected production files serves a surface that is live, shipped, documented and
depended on by at least one clean subsystem:

| package | why it cannot simply go |
|---|---|
| A — audit read | a shipped settings page, a documented capability (`custom/db/documentation/{en,ar}/administration/audit-logs.md`), and the only reader of the records seven clean writers produce. Removing it would silently blind P9, P10, P11, Commerce and Flow auditing |
| B — audit capture | without it the read surface shows only what those seven clean writers happen to record; the product would claim an audit trail and not have one for inboxes, teams, roles, channels, sign-ins or deletions |
| C — named permission sets | three clean policies, the agent settings UI and `permissionsHelper.js` all consult the capability list. Production memberships already carry attachments; removing the feature would silently widen or narrow those people's access |
| D — campaign recipient outcomes | the campaign analytics page, two routes, and the whole of P8's campaign analytics family read these records. Production rows exist |
| E — delivery report routing | without it every campaign recipient stays at "sent" and D's numbers are wrong by construction |

The only thing in this area that *could* be dropped without a visible loss is the acceptance of a capability
the interface does not offer (`specs/C-account-role-permissions.md` §9 names it). That is a one-value decision,
not a feature removal.

---

## 7. Dependencies on P8, P9, P10 and P11 — MUST REMAIN COMPATIBLE

These four subsystems are original Lynomia work, shipped, and **not part of the rewrite**. Each depends on
something you are implementing:

| phase | depends on | what breaks if the contract moves |
|---|---|---|
| **P8** analytics | package D's table, enum names, timestamp semantics, `error_code` and `error_message` | every campaign metric, the campaign series, the failure and skip breakdowns. `DELIVERED_SQL` in `custom/app/services/analytics/campaigns/metrics.rb` encodes the read-before-delivered rule — if your writer stops upholding it, P8 undercounts delivery |
| **P8** contact timeline | the audit records, read through `Contacts::ActivityTimelineQuery` | the timeline loses its audit-sourced entries |
| **P9** support cases | `'support_ticket_manage'` in the capability list | every role-holder loses or gains access to cases |
| **P9** operations centre | nothing of yours directly — it has its own signal store | — |
| **P10** contact merge and identity | `Custom::AuditLog` (§2.1) | the merge audit record, which P10 added deliberately so a destructive action is attributable |
| **P11** billing | `Custom::AuditLog` with a **polymorphic actor** (§2.1), and `Billing::Entitlements` as the one entitlement authority | the override-grant, plan-edit and sync-revocation records — the audit trail P11 relies on to explain why an account's capabilities changed |
| **Commerce** | `'commerce_order_manage'` in the capability list, and `Custom::AuditLog` | order actions by role-holders, and the store-connection trail |
| **Flow Builder** | `Custom::AuditLog` | the flow lifecycle trail |

---

## 8. What may be redesigned freely

Stated positively, so you do not over-constrain yourself:

- **Every internal structure.** Class names inside your packages (except `Custom::AuditLog`, §2.1), method
  decomposition, where logic lives, what is a service and what is a model concern.
- **How capture points hook in.** The thirteen OSS `Audit::<Model>` include sites exist
  (`02-safe-interfaces.md` §1) but nothing forces you to use them.
- **How the forward-only recipient rule is expressed** — provided it holds, is idempotent, and is applied under
  a row lock.
- **Whether delivery reports are applied inline or asynchronously.**
- **The query shapes**, provided the per-page query count does not grow with the page's size
  (`specs/A` §8 criterion 8).
- **Error messages and validation copy**, provided the HTTP status codes in the specifications are kept.
- **The file layout** under `custom/`, provided the two view paths the OSS views render by name are kept:
  `api/v1/models/_account_user` and whatever the audit read surface renders.
- **Your own tests**, entirely. There is no prior test suite for these packages in the workspace, by design.

---

## 9. The compatibility test

One scenario is worth more than the rest of this document, and it is in the acceptance plan as **F-3**: restore
a database taken before the rewrite, start the product, and exercise all five areas. Existing audit entries
render; existing role attachments still grant what they granted; existing campaign recipients read the same;
and no migration was needed to get there.

If F-3 passes and sections 1–7 above are untouched, the rewrite is compatible. If F-3 fails, something in this
document was changed without being noticed.
