# Lynomia Chat — enterprise zero-dependency implementation

**Status:** the small replacements the audit identified are implemented, with one named blocker left
(section 11). `enterprise/` has **not** been removed. No table was dropped, no migration was added,
no production data was read or written, and no feature flag or licensing file was changed.

**Inputs:** `docs/enterprise-audit/00-enterprise-dependency-audit.md` (the dependency map) and
`docs/enterprise-audit/01-zero-dependency-readiness.md` (the verdict this phase acts on:
*READY AFTER SMALL REPLACEMENTS*).

**Commits in this phase**

| SHA | Workstream |
|:--|:--|
| `92211aba` | WhatsApp campaign recipient tracking → Lynomia |
| `d03acb0b` | Audit class → Lynomia, Chatwoot's 11 declarations mirrored |
| `fbc485a8` | The custom role that grants Commerce order management → Lynomia |
| `4ebab747` | Chatwoot Cloud billing frontend removed |
| `7a7779cb` | 113 enterprise-only route declarations removed |
| `60b43f64` | `ChatwootApp.extensions` derived from what is on disk; two test corrections |
| `46553231` | `custom_role_id` shipped to the dashboard without the enterprise gate |

64 files changed: 462 insertions, 808 deletions. 16 of them are `git mv` relocations out of
`enterprise/` or `spec/enterprise/`; nothing inside `enterprise/` was edited or deleted.

---

## 1. Exact dependencies replaced

| # | Dependency, as the audit stated it | How it is now satisfied | Resolves an `Enterprise::` constant? |
|--:|:--|:--|:--|
| 1 | `CampaignRecipient`, its associations, the recipient-writing send path, the status updater and its job, `last_provider_error`, the analytics controller — all under `enterprise/` | relocated to `custom/`, with three `Custom::` overlays on injection sites OSS already carries | no, except item 7 below |
| 2 | `Enterprise::AuditLog`, named by `config/initializers/audited.rb` and by three guarded Lynomia call sites | `Custom::AuditLog < Audited::Audit` on the same `audits` table; the guards removed | **no** |
| 3 | `CustomRole` + `AccountUser#custom_role`, without which `commerce_order_manage` cannot be granted | relocated to `custom/` with `Custom::AccountUser#permissions` and two association overlays | **no** |
| 4 | The cloud billing frontend, calling `/enterprise/api/v1/accounts/:id/*` | removed | n/a (frontend) |
| 5 | 113 ungated route declarations naming enterprise-only controllers or actions | removed from `config/routes.rb` | n/a |
| 6 | `ChatwootApp.extensions` listing `enterprise` unconditionally | derived from `enterprise?` / `custom?` | **no** |
| 7 | `Enterprise::Whatsapp::IncomingMessageBaseService#process_statuses` — the delivered / read / failed path | **NOT relocated.** Blocked; see section 11 | **yes** |

**The measured bottom line.** Across `app/`, `lib/`, `custom/`, `config/` and `db/` there is now
exactly **one** line of code naming an `Enterprise::` constant:

```
app/views/api/v1/models/_account.json.jbuilder:10
  json.billing_currency resource.billing_currency if resource.respond_to?(:billing_currency) && Enterprise::Billing::Currencies.enabled?
```

It is safe by short-circuit rather than by a guard: `billing_currency` is defined by
`Enterprise::Account`, so once the overlay is gone `respond_to?` is false and `&&` never evaluates
the constant. It is left as-is because it needs no change to be correct, and recorded here because
"safe by evaluation order" is worth knowing about rather than discovering. Six further mentions in
those trees are comments.

---

## 2. Exact files changed

### Relocated out of `enterprise/` (16 `git mv`s, content preserved)

| From | To |
|:--|:--|
| `enterprise/app/models/campaign_recipient.rb` | `custom/app/models/campaign_recipient.rb` |
| `enterprise/app/jobs/campaigns/update_recipient_status_job.rb` | `custom/app/jobs/campaigns/update_recipient_status_job.rb` |
| `enterprise/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb` | `custom/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb` |
| `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb` | `custom/app/services/custom/whatsapp/oneoff_campaign_service.rb` |
| `enterprise/app/models/custom_role.rb` | `custom/app/models/custom_role.rb` |
| `enterprise/app/policies/custom_role_policy.rb` | `custom/app/policies/custom_role_policy.rb` |
| `enterprise/app/controllers/api/v1/accounts/custom_roles_controller.rb` | `custom/app/controllers/api/v1/accounts/custom_roles_controller.rb` |
| `enterprise/app/controllers/enterprise/api/v1/accounts/agents_controller.rb` | `custom/app/controllers/custom/api/v1/accounts/agents_controller.rb` |
| `enterprise/app/views/api/v1/accounts/custom_roles/{create,index,show,update}.json.jbuilder` | `custom/app/views/api/v1/accounts/custom_roles/` |
| `enterprise/app/views/api/v1/models/_custom_role.json.jbuilder` | `custom/app/views/api/v1/models/_custom_role.json.jbuilder` |
| `enterprise/app/views/api/v1/models/_account_user.json.jbuilder` | `custom/app/views/api/v1/models/_account_user.json.jbuilder` |

Each is a **top-level constant** (`CampaignRecipient`, `CustomRole`, `CustomRolePolicy`, the two
controllers, the job) or a module whose name changes (`Enterprise::Whatsapp::OneoffCampaignService`
→ `Custom::`). Defining the same top-level constant in two autoload roots is a Zeitwerk conflict, so
relocation — not duplication — was the only correct option for these. That is why they moved while
nothing else in `enterprise/` was touched.

### Added under `custom/` (16 files)

```
custom/app/models/custom/audit_log.rb                  the audit class
custom/app/models/custom/audit/{account,account_user,agent_bot,automation_rule,conversation,
                                inbox,inbox_member,macro,team,team_member,webhook}.rb
custom/app/models/custom/campaign.rb                   has_many :campaign_recipients
custom/app/models/custom/concerns/contact.rb           has_many :campaign_recipients
custom/app/models/custom/channel/whatsapp.rb           keeps the provider across a template send
custom/app/models/custom/account_user.rb               #permissions via the custom role
custom/app/models/custom/concerns/account_user.rb      belongs_to :custom_role
custom/app/models/custom/concerns/account.rb           has_many :custom_roles
```

**No `prepend_mod_with` or `include_mod_with` line was added anywhere.** Every one of these overlays
attaches at an injection site the OSS file already carries, which is worth stating because it is the
single best evidence that this is a relocation rather than a redesign:

| Overlay | Existing injection site |
|:--|:--|
| `Custom::Campaign` | `app/models/campaign.rb:173` |
| `Custom::Concerns::Contact` | `app/models/contact.rb:263` |
| `Custom::Channel::Whatsapp` | `app/models/channel/whatsapp.rb:238` |
| `Custom::Whatsapp::OneoffCampaignService` | `app/services/whatsapp/oneoff_campaign_service.rb:148` |
| `Custom::Whatsapp::Providers::BaseService` | `app/services/whatsapp/providers/base_service.rb:136` |
| `Custom::AccountUser` | `app/models/account_user.rb:102` |
| `Custom::Concerns::AccountUser` | `app/models/account_user.rb:104` |
| `Custom::Concerns::Account` | `app/models/account.rb:242` |
| `Custom::Audit::<Name>` ×11 | `app/models/<name>.rb` → `include_mod_with('Audit::<Name>')` |

### Edited elsewhere (11 files)

```
config/initializers/audited.rb                    audit_class → 'Custom::AuditLog'
config/routes.rb                                  113 route entries removed; analytics ungated
lib/chatwoot_app.rb                               extensions derived from disk
app/views/api/v1/models/_user.json.jbuilder       two enterprise gates dropped
app/views/api/v1/models/_agent.json.jbuilder      custom_role_id gate dropped
custom/app/services/flows/audit.rb                guard dropped, Custom::AuditLog
custom/app/services/commerce/audit_trail.rb       guard dropped, Custom::AuditLog
custom/app/models/custom/audit/custom_filter.rb   guard dropped
custom/app/services/custom/whatsapp/providers/base_service.rb   last_error capture added
custom/app/policies/custom/portal_policy.rb       comment corrected
app/javascript/… (7 files)                        see section 6
```

---

## 3. Campaign recipient ownership

**One table, one model, one engine.** `campaign_recipients` is unchanged — it ships in the OSS
schema (`db/schema.rb:401`) with its eight indexes and four cascading foreign keys, and this phase
added no migration. `CampaignRecipient` is the same class with the same status ladder
(`queued → skipped | sent → delivered → read | failed`), the same `mark_sent!` / `mark_skipped!` /
`mark_failed!` / `update_from_whatsapp_status!` and the same downgrade refusal; it simply lives in
`custom/` now.

**The send path.** `Custom::Whatsapp::OneoffCampaignService` prepends onto the OSS service and
replaces `#perform`, exactly as the Enterprise module did: every contact gets a recipient row before
it is sent, then `mark_sent!` with Meta's message id, or `mark_skipped!` / `mark_failed!` with the
reason. Shared-audience campaigns keep working because recipients come from
`Campaign#audience_contacts`, and `Custom::CampaignAudience` — which resolves the account's shared
contact audiences beside its labels — is unaffected. Measured ancestor chain without
`enterprise/`:

```
Campaign.ancestors            → Custom::CampaignAudience, Campaign, Custom::Campaign
OneoffCampaignService          → Custom::Whatsapp::OneoffCampaignService, Whatsapp::OneoffCampaignService
  defines #create_recipients    → true
Campaign#campaign_recipients   → {dependent: :delete_all}
Contact#campaign_recipients    → {dependent: :destroy_async}
```

**Failure detail.** A failed recipient needs Meta's own wording, which only exists on the provider
response. OSS `Channel::Whatsapp` reaches the provider through
`delegate :send_template, to: :provider_service` (`app/models/channel/whatsapp.rb:147`), which
discards the provider instance along with its error. `Custom::Channel::Whatsapp#send_template` sends
through the provider once and keeps it, so `Custom::Whatsapp::Providers::BaseService#last_error`
reaches the recipient. Both measured present without `enterprise/`.

**Reporting.** The analytics controller is relocated verbatim — same authorization
(`authorize @campaign, :show?` plus a one-off/WhatsApp/`whatsapp_campaign` check), same 25-per-page
pagination, same response shape — and its two routes move out of the `if ChatwootApp.enterprise?`
block. Measured over HTTP without `enterprise/`:
`GET /api/v1/accounts/1/campaigns/1/analytics/metrics` → **401**, i.e. the route exists and demands
authentication, rather than the 404 it answered before this phase.

**What is not yet relocated** is the delivered / read / failed status path. See section 11.

---

## 4. Audit ownership

`Custom::AuditLog < Audited::Audit`. No new table, no new gem, no new engine, no migration: the
`audited` gem is an OSS dependency (`Gemfile:184`), the `audits` table is created by an OSS migration
(`db/migrate/20230426130150_init_schema.rb`) and `Enterprise::AuditLog` was itself only a subclass on
that table — so **history is preserved exactly**, because the rows never moved.

Carried over: `log_additional_information`, the `after_save` that fills `username` on every row and
points an Account audit at itself. Without it, the Template Manager's existing audit rows would
silently stop recording who acted.

Deliberately not carried over, and recorded as a decision rather than an omission: the IP
geolocation hook, `location`, `masked_remote_address` and the `search_by_user` / `created_after` /
`with_auditable_types` scopes. Those serve Chatwoot's Enterprise audit log viewer, which Lynomia does
not ship; the geolocation path additionally needs the `ip_lookup` feature (`config/features.yml:32`,
`enabled: false`) and an Enterprise job. The `city` / `country` / `country_code` columns stay null,
as they already are.

**Lynomia's three writers lose their guards.** `Flows::Audit`, `Commerce::AuditTrail` and
`Custom::Audit::CustomFilter` were each wrapped in `defined?(Enterprise::AuditLog)`. They now write
unconditionally — which, for the audience audit, *restores* coverage the guard was silently
disabling.

**Chatwoot's own coverage is mirrored, not dropped.** Eleven `Custom::Audit::*` concerns carry the
same declarations for Account, AccountUser, AgentBot, AutomationRule, Conversation, Inbox,
InboxMember, Macro, Team, TeamMember and Webhook. `Enterprise::Audit::User` is the twelfth file and
is deliberately **not** mirrored: its declaration carries `unless: proc { |_u| true }`, so the gem
never writes from it — it exists only to install the machinery for the manual sign-in/sign-out writes
in the Enterprise sessions controller, which Lynomia does not port.

The risk this created is duplicate callbacks while both overlays are loaded, which would double every
audit row. `spec/models/custom/audit_log_spec.rb` measures it directly rather than reasoning about
ActiveSupport's callback de-duplication: for a Macro, a Webhook, an AutomationRule and an AgentBot it
asserts `where(auditable: record, action: 'create').count == 1`, and for inbox members and team
members one row each on create and on destroy. All pass with `enterprise/` installed.

Measured without `enterprise/`:

```
Audited.audit_class            → Custom::AuditLog      (table: audits)
'Enterprise::AuditLog'         → nil
models still declaring audited → Account, AccountUser, AgentBot, AutomationRule, Conversation,
                                 CustomFilter, Inbox, Macro, Team, Webhook,
                                 Whatsapp::MessageTemplate
```

(InboxMember and TeamMember write by hand, so they do not appear in that reflection.)

---

## 5. Commerce permission ownership

The audit found that removal would delete `CustomRole` and `AccountUser#custom_role`, so
`commerce_order_manage` could never be granted again and order status changes and e-mail resends
would quietly become administrator-only. That regression was refused, so the **grant mechanism moved
to Lynomia rather than being replaced**.

No second RBAC system, and no migration. The same `custom_roles` table and the same
`account_users.custom_role_id` column from the OSS schema; the same Pundit policies; the same
`account_user.permissions` list that `Commerce::ActionPolicy` already reads
(`custom/app/policies/commerce/action_policy.rb:8,19-20`). What changed is ownership of the files.

Two consequences had to be handled or the capability would have existed only on paper, and both are
the kind of thing that looks fine in a diff and fails in the product:

* **Granting.** `Enterprise::Api::V1::Accounts::AgentsController` was the only place an agent's
  `custom_role_id` is written. It moved too, as `Custom::Api::V1::Accounts::AgentsController`.
  Without it a role could exist and be given to nobody.
* **Seeing.** `_user.json.jbuilder:41`, `_user.json.jbuilder:3` and `_agent.json.jbuilder:14` shipped
  the role to the browser only `if ChatwootApp.enterprise?`, and the settings route declared
  `installationTypes: [CLOUD, ENTERPRISE]`. All four now follow the account's `custom_roles` feature
  flag, which is the mechanism Chatwoot already used. The `_agent` line is the one the Agents settings
  page reads, and it had no test coverage — it was found by sweeping for `ChatwootApp.enterprise?`,
  not by a failing spec.

Preserved, each asserted: administrator access, authorized custom-role access,
denial for an ungranted agent, refunds and cancellations still administrator-only whatever the role
grants, and **tenant isolation** — a role defined in another account grants nothing here, which the
audit asked for and which no spec covered before.

Measured without `enterprise/`:

```
CustomRole                        → present, PERMISSIONS includes commerce_order_manage
AccountUser#permissions owner     → Custom::AccountUser
AccountUser belongs_to :custom_role / Account has_many :custom_roles → both present
Api::V1::Accounts::CustomRolesController → present
GET /api/v1/accounts/1/custom_roles      → 401  (route exists, demands authentication)
```

One operational note: `custom_roles` is a premium flag (`config/features.yml`, `enabled: false`), and
the relocated controller keeps Chatwoot's `ensure_custom_roles_feature_enabled` check. Granting the
Commerce permission therefore requires the flag enabled on the account — the same precondition as
before this phase, now the only one.

---

## 6. Frontend cleanup

Lynomia bills through its own API, so none of the Chatwoot Cloud billing frontend is needed. What it
called — `checkout`, `subscription`, `billing_summary`, `select_billing_currency`, `topup_checkout`,
`topup_options`, `toggle_deletion` — all lives under `/enterprise/api/v1/accounts/:id/*`, inside an
`if ChatwootApp.enterprise?` block.

| Action | File |
|:--|:--|
| deleted | `routes/dashboard/settings/billing/ShopifyBilling.vue` |
| deleted | `routes/dashboard/settings/account/components/AccountDelete.vue` |
| trimmed to `getLimits` only | `api/enterprise/account.js` |
| `checkout`, `subscription`, `selectBillingCurrency`, `toggleDeletion` and the `isCheckoutInProcess` flag removed | `store/modules/accounts.js` |
| Shopify branches removed; mounts the one provider | `routes/dashboard/settings/billing/ProviderIndex.vue` |
| `<AccountDelete />` mount and its unused getter removed | `routes/dashboard/settings/account/Index.vue` |
| `installationTypes: [CLOUD, ENTERPRISE]` dropped | `routes/dashboard/settings/customRoles/customRole.routes.js` |

`getLimits` is kept on purpose: it is Captain's usage quota, not billing, and it is only ever called
behind `isEnterprise` (`composables/useCaptain.js:61`), so it is inert on a Lynomia install. Removing
it would have meant editing Captain's overview page and two limit banners — a feature this phase is
not touching.

**Boundary.** Lynomia's own billing and subscription settings pages, `api/billingSubscription.js`,
`helper/billingGuard.js` and `constants/billing.js` are untouched.

Neither deleted component was actually reachable before this phase, which is worth saying plainly
rather than implying a fix: `ShopifyBilling` rendered only for an account whose `billing_provider`
came from `Enterprise::AccountBillingIdentity`, and `<AccountDelete />` was already behind
`v-if="isOnChatwootCloud"`. This is dead-code removal, not a repair.

Three frontend specs covered the removed code and were **rewritten rather than deleted**: the API
spec now asserts the billing methods are absent, the store spec drops the `toggleDeletion` group, and
the provider spec asserts the page still waits for the account and then mounts billing. 11 vitest
examples pass, `eslint` reports no errors on every touched file, and `npx vite build --mode
production` exits 0.

Two i18n groups become unreferenced by code and are **left in place** rather than deleted, since
pruning locales is out of scope here: `BILLING_SETTINGS.SHOPIFY` and
`GENERAL_SETTINGS.ACCOUNT_DELETE_SECTION`.

---

## 7. Route cleanup

The audit measured 162 affected route entries. They split into two kinds, which get different
treatment:

| Kind | Count | Action | Why |
|:--|--:|:--|:--|
| Already inside `if ChatwootApp.enterprise?` | 41 | **left alone** | already guarded; they disappear correctly on removal |
| Ungated, naming a controller or action that exists only in `enterprise/` | 113 | **removed** | they advertise endpoints backed by nothing |
| Re-homed to Lynomia earlier in this phase | 8 | **kept, ungated** | 2 campaign analytics + 6 custom roles |

Measured with `enterprise/` still installed: **939 route entries before, 826 after** — 113 removed,
exactly the ungated set — and the count of pre-existing unresolvable entries falls from 52 to 44 as
the phantom `new`/`edit` members on those resources go with them.

Removed: the Captain assistants / stats / scenarios / inboxes / agent sessions / assistant responses
/ FAQ suggestions / message reports / bulk actions / copilot / documents trees; `companies` and its
three nested resources; `sla_policies` and `applied_slas`; `agent_capacity_policies` with its `users`
and `inbox_limits`; `saml_settings` and `api/v1/auth/saml_login`; `audit_logs`; the Cloudflare custom
hostname challenge; and the two actions enterprise adds to OSS controllers,
`ConversationsController#inbox_assistant` and `PortalsController#ssl_status`.

**Kept after checking rather than assuming the namespace was uniform**, which is the part of this
edit that could silently have broken Lynomia:

* `captain/preferences` and `captain/tasks`. Their controllers are in `app/`, not `enterprise/`, and
  the task services are OSS with `captain_tasks` enabled by default. Deleting the whole `captain`
  namespace — the obvious move — would have removed the rewrite, summarize, reply-suggestion,
  label-suggestion and follow-up endpoints.
* `assignment_policies`. Its controller is OSS; its four unresolvable entries were already
  unresolvable before this change and are not in the 113.

No route was replaced by a guard. A removed declaration and a guarded one answer identically once
`enterprise/` is gone, and the guard's condition could never be true again.

---

## 8. Test changes

**Nothing meaningful was deleted.** Nine spec files moved out of `spec/enterprise/` into the suite
proper, which is the point: `spec/enterprise/**` is excluded from the non-enterprise run that is the
removal gate, so coverage that lived there was invisible to the gate.

| Moved from `spec/enterprise/` | To | Change |
|:--|:--|:--|
| `models/campaign_recipient_spec.rb` | `spec/models/` | none |
| `jobs/campaigns/update_recipient_status_job_spec.rb` | `spec/jobs/campaigns/` | none |
| `controllers/api/v1/accounts/campaigns/analytics_controller_spec.rb` | `spec/controllers/api/v1/accounts/campaigns/` | none |
| `services/enterprise/whatsapp/incoming_message_base_service_spec.rb` | `spec/services/custom/whatsapp/` | `describe` constant |
| `services/enterprise/whatsapp/oneoff_campaign_service_spec.rb` | `spec/services/custom/whatsapp/` | `describe` constant |
| `models/custom_role_spec.rb` | `spec/models/` | none |
| `controllers/api/v1/accounts/custom_roles_controller_spec.rb` | `spec/controllers/api/v1/accounts/` | none |
| `controllers/enterprise/api/v1/accounts/agents_controller_spec.rb` | `spec/controllers/custom/api/v1/accounts/` | `describe` string |
| `policies/commerce/action_policy_spec.rb` | `spec/policies/commerce/action_policy_custom_role_spec.rb` | one example added |

**Added**

* `spec/models/custom/audit_log_spec.rb` — 9 examples: the active class and table, a Flow Builder
  event with `username` recorded, a Commerce event, an audited audience and an unaudited conversation
  folder, and one row per record for each mirrored Chatwoot-side declaration.
* one example in `spec/policies/commerce/action_policy_custom_role_spec.rb` — a custom role defined
  in another account grants nothing here. The audit asked for this case and nothing covered it.
* one example in `spec/requests/custom/tenant_help_center_removal_spec.rb` — see below.

**Corrected, and only where the assumption genuinely disappeared**

* `spec/models/campaign_audience_spec.rb` — **no change needed.** It asserted
  `campaign.campaign_recipients`, which was the audit's one `D`; re-homing the association makes it
  pass without touching it. This was the measurement that said the relocation was complete.
* `spec/requests/custom/tenant_help_center_removal_spec.rb` — the `CustomRole` fixture at line 21 was
  the audit's other removal-caused failure (24 examples on one line). Because the role is now
  Lynomia's, **that fixture keeps working and the `power_user` arm is unchanged.** The only real
  change came from the route cleanup: the spec asserted 401 on `portals/:id/ssl_status`, which is now
  404 because the route is gone. Rather than drop the case, it is split — one new example asserts
  that no `ssl_status` route is offered at all AND that `Custom::PortalPolicy#ssl_status?` still
  refuses, so a restored route would still be denied. The invariant is strengthened:

  > TENANTS MAY CONSUME LYNOMIA DOCUMENTATION. TENANTS MAY NOT AUTHOR TENANT HELP CENTER CONTENT.

  25 examples pass — the original 24 across administrator, agent and a maximally-privileged custom
  role, plus the new one.

**A consequence to be explicit about.** Removing 113 route declarations means the `spec/enterprise/`
specs for those capabilities now exercise routes that no longer exist, so the *enterprise* suite no
longer passes. That is the intended direction — those capabilities are being dropped — but it is a
real change in a suite this phase did not run, and it should not come as a surprise later.

---

## 9. No-enterprise runtime evidence

### 9.1 The proof mechanism, and why not `DISABLE_ENTERPRISE`

Every measurement below was taken in a **throwaway git worktree of the current HEAD with
`enterprise/` renamed aside**, leaving the primary checkout untouched:

```bash
git worktree add --detach <scratchpad>/noee HEAD
mv <scratchpad>/noee/enterprise <scratchpad>/noee/.enterprise-removed
```

`DISABLE_ENTERPRISE` was **not** used, and must not be, because it does not produce the state being
tested. `ChatwootApp.enterprise?` reads

```ruby
return if ENV.fetch('DISABLE_ENTERPRISE', false)
@enterprise ||= root.join('enterprise').exist?
```

Two things are wrong with it as a proof. The guard returns `nil` before the memoised check, so the
answer depends on whether anything asked earlier in the boot and cached a different value. And more
fundamentally the files are still on disk: `config/application.rb:46` still adds
`Dir["…/enterprise/app/**"]` to the eager-load paths, so every `Enterprise::` constant still loads and
resolves — only the `enterprise?` predicate lies. That is the half-disabled state the audit recorded
as SHO-12. Moving the directory is the only mechanism that reproduces deletion.

(This phase also makes `ChatwootApp.extensions` honest, so `DISABLE_ENTERPRISE` now at least drops
`enterprise` from the injection list. It still does not unload the constants, so it is still not a
proof mechanism.)

### 9.2 Boot, eager load, routes

```
RAILS_ENV=production  bundle exec rails runner 'Rails.application.eager_load!; …'

eager_load            OK
enterprise?           false
custom?               true
extensions            ["custom"]          <- enterprise no longer listed
Enterprise namespace  absent
routes_total          785
```

Production eager loading is the strongest available boot test: it loads every class in `app/`, `lib/`
and `custom/` and resolves every constant referenced at class-definition time. No error, no warning
beyond the two pre-existing ones (a RubyLLM deprecation and the GeoIP setup notice).

### 9.3 Sidekiq and the Lynomia cron registration

```
RAILS_ENV=production  bundle exec sidekiq -C config/sidekiq.yml      (ran 100s, then SIGTERM)

Booted Rails 7.2.3.1 application in production environment
Cron Jobs - added job with name … ×12, including:
  commerce_action_sweep_job      <- Lynomia
  lynomia_queue_health_job       <- Lynomia
Performed: ActionCableBroadcastJob, AutoAssignment::AssignmentJob,
           Conversations::ActivityMessageJob, EventDispatcherJob,
           Inboxes::FetchImapEmailInboxesJob, UserSessionIpLookupJob
NameError / uninitialized constant occurrences: 0
```

It did more than boot: six job classes ran to completion. The log also carries four
`ActiveJob::DeserializationError: Couldn't find Account with 'id'=…` lines — stale jobs left in Redis
by earlier spec runs referencing records that no longer exist. Environment noise, not a removal
consequence, and recorded rather than filtered.

### 9.4 HTTP surfaces

A Puma server booted in the worktree in production mode. **Zero 500s in the log.**

| Request | Status | Reading |
|:--|--:|:--|
| `GET /` | 200 | dashboard shell |
| `GET /app/login` | 200 | |
| `GET /super_admin/sign_in` | 200 | Super Admin, all 8 Administrate dashboards loaded |
| `GET /api/v1/accounts/1/contacts` | 401 | OSS path healthy — auth required |
| `GET /api/v1/accounts/1/custom_roles` | **401** | **re-homed: the route exists and demands auth** |
| `GET /api/v1/accounts/1/campaigns/1/analytics/metrics` | **401** | **re-homed: same** |
| `GET /api/v1/accounts/1/sla_policies` | 404 | removed capability |
| `GET /api/v1/accounts/1/audit_logs` | 404 | removed capability |
| `GET /api/v1/accounts/1/captain/assistants` | 404 | removed capability |
| `GET /api/v1/accounts/1/companies` | 404 | removed capability |
| `GET /api/v1/accounts/1/portals/1/ssl_status` | 404 | removed action |
| `GET /api/v1/accounts/1/conversations/1/inbox_assistant` | 404 | removed action |
| `POST /api/v1/auth/saml_login` | 404 | removed capability |
| `GET /docs`, `GET /changelog` | 404 | the controller ran (2 AR queries) and found no portal — this database has none seeded, so this is data, not routing |

The two **401s** are the load-bearing results. Before this phase both answered 404; they are the
HTTP-level proof that the campaign analytics and custom roles surfaces are Lynomia's now.

### 9.5 Per-capability constant and association resolution

Measured in the same worktree. Every line is a thing that would have been `nil`, `false` or a
`NameError` before this phase.

| Capability | Measured |
|:--|:--|
| audit class | `Audited.audit_class` → `Custom::AuditLog`, table `audits`; `'Enterprise::AuditLog'.safe_constantize` → `nil` |
| audit coverage | 11 models still declaring `audited` (list in section 4) |
| Lynomia audit writers | `Flows::Audit` and `Commerce::AuditTrail` carry no `defined?(Enterprise…)` guard |
| campaign recipients | `CampaignRecipient` present; `Campaign` and `Contact` associations present with their original `dependent:` options |
| campaign send path | `Custom::Whatsapp::OneoffCampaignService` prepended; `#create_recipients` present |
| shared audiences | `Campaign.ancestors` → `Custom::CampaignAudience, Campaign, Custom::Campaign` |
| failure detail | `Channel::Whatsapp#last_provider_error` → true; `Whatsapp::Providers::BaseService#last_error` → true |
| campaign reporting | `Campaigns::UpdateRecipientStatusJob` and `Api::V1::Accounts::Campaigns::AnalyticsController` both resolve |
| Commerce permission | `CustomRole::PERMISSIONS` includes `commerce_order_manage`; `AccountUser#permissions` owner is `Custom::AccountUser`; both associations present; controller resolves |

### 9.6 The full test suite, with the three categories separated

Both runs are of **the same commit**, differing only in whether `enterprise/` is present, each against
its own PostgreSQL database and its own Redis logical database. The first attempt at this comparison
had both runs sharing one Redis namespace and was discarded as contaminated — the numbers below are
from the isolated re-run.

```
with    enterprise/ :  8648 examples, 0 failures, 70 pending   in 40m29s
without enterprise/ :  8638 examples, 19 failures, 73 pending   in 39m33s
```

**With `enterprise/` installed the suite is completely clean: 0 failures.** That is the first thing
worth stating, because it means none of the seven commits in this phase breaks anything in the
composition the application boots with today.

The 19 failures without it are **not** the removal delta. Every failing file was re-run in a fresh
worktree at the final commit, with `installation_configs` truncated first:

```
85 examples, 1 failure
```

| Category | Count | What they are |
|:--|--:|:--|
| baseline failure | **0** | nothing fails in both runs |
| environment / test database | **17** | leftover `installation_configs` rows in `chatwoot_test` |
| test correction, found by this gate | **1** | the onboarding example; fixed in `ffd15dc5` |
| **removal delta** | **1** | the known blocker |

**The 17 environment failures.** `spec/lib/config_loader_spec.rb` asserts
`InstallationConfig.count == 0` and found 4; `spec/lib/global_config_service_spec.rb` found a
persisted `ENABLE_ACCOUNT_SIGNUP = "false"` row, which is also why five
`POST /api/v1/accounts` and five `POST /api/v2/accounts` examples saw 404 instead of success, and why
three `omniauth_callbacks` examples redirected to `no-account-found`; the two `vapid_service`
examples expect an `InstallationConfig.find_by` the leftover rows short-circuit. They are an artefact
of the comparison, not of the code: the with-enterprise run used a freshly created database and the
without-enterprise run reused `chatwoot_test`, which had re-accumulated those four rows across the
per-workstream runs of this phase. Truncating the table and re-running the same six files without
`enterprise/` gives 0 failures. Reported rather than filtered, because a 19 silently presented as a
1 is not checkable.

**The one test correction this gate found**, which no earlier sweep could have:
`spec/requests/custom/tenant_help_center_removal_spec.rb` stubbed
`Onboarding::HelpCenterCreationService` — an Enterprise constant — so without the overlay there was
nothing to stub and the example raised `NameError`. It now asserts the invariant at its cause
(`Custom::Api::V1::Accounts::OnboardingsController#create_help_center` returning nil in the
controller's ancestor chain) rather than at Chatwoot's service, so it holds either way. Fixed in
`ffd15dc5`; 25 examples pass.

**The removal delta is exactly one example**, and it is the blocker in section 11:

```
Custom::Whatsapp::IncomingMessageBaseService
  defers a campaign status when neither a recipient nor a message is persisted yet
    expected to enqueue exactly 1 jobs … but enqueued 0
```

Enqueued **0** without `enterprise/`, because the status path still lives there. Note the symmetry
with the reason it cannot simply be moved: with both copies present the same example enqueues **2**.
That one example is the whole remaining gap, and it is the capability this phase was told not to
regress.

For the record, the per-workstream runs quoted above cover the capabilities the gate protects, and
all passed: 26 examples across the campaign model, job, analytics controller, send path and shared
audiences; 9 for audit ownership; 66 across the Commerce policy, the custom role, both controllers
and the order-actions service; 25 for tenant Help Center authorization; 11 vitest examples for the
billing frontend.

---

## 10. Remaining production-only checks

Three read-only checks must be run **on the production host** before `enterprise/` is deleted. None
of them can be answered from this container: its database was loaded from `db/schema.rb` and has no
production rows, and this is not the production host. Do not run any of these from a development
environment and expect a meaningful answer.

### 10.1 Campaign recipient data gate

```sql
-- read-only
SELECT count(*) AS campaign_recipients FROM campaign_recipients;
```

| Result | Meaning | Action |
|:--|:--|:--|
| `0` | no campaign has recorded recipients yet | nothing to migrate; the relocation is code-only |
| `> 0` | live campaign reporting data exists | **no migration is required** — see below |

**Why a non-zero count still needs no migration.** The relocation did not move data. It is the same
`campaign_recipients` table, the same columns, the same eight indexes and the same four
`on_delete: cascade` foreign keys from the OSS schema; only the file defining `CampaignRecipient`
moved from `enterprise/app/models/` to `custom/app/models/`. A non-zero count therefore changes the
*risk* of getting the relocation wrong, not the work: existing rows keep being read and written by the
relocated model with no transformation. What a non-zero count does require is that the deployment
of the relocation and the deletion of `enterprise/` happen in one release rather than two, so there
is never a window with no `CampaignRecipient` class while rows exist.

Run it anyway, and record the number, because it tells the operator whether a mistake here would be
visible to customers.

### 10.2 The advanced_assignment release check

**Why this exists.** `Internal::ReconcilePlanConfigService` — the service that disables premium
features for a community plan — lives in `enterprise/app/services/internal/`, and its only caller is
`Enterprise::Internal::CheckNewVersionsJob`. Once `enterprise/` is deleted, **nothing disables premium
feature flags any more.** A flag that is set today stays set forever, and the implementation behind it
is gone. `advanced_assignment` is the one that matters, because it is the flag the dashboard reads to
show the Agent Assignment settings surface (`components-next/sidebar/Sidebar.vue:765`), and its
implementation is `Enterprise::AutoAssignment::{AssignmentService,BalancedSelector,CapacityService}`.

```sql
-- read-only. feature_flags is a bitmask; the bit index comes from the ordering of
-- config/features.yml within the account column group, so ask the application rather than the
-- database for the mask.
SELECT id, name, feature_flags FROM accounts ORDER BY id;
```

Then, on the production host, in a Rails console:

```ruby
# read-only
Account.all.each do |account|
  flags = %w[advanced_assignment assignment_v2 custom_roles sla captain_integration companies
             audit_logs ip_lookup channel_voice help_center_embedding_search]
            .select { |flag| account.feature_enabled?(flag) }
  puts "#{account.id}\t#{account.name}\t#{flags.join(' ')}" if flags.any?
end
```

| Finding | Safe action |
|:--|:--|
| no account has `advanced_assignment` | nothing to do |
| an account has `advanced_assignment` | **disable it before the removal release**, in Super Admin → Accounts → Features. Leaving it on gives that account a settings surface whose backend is gone: `Sidebar.vue` shows "Agent Assignment", the page loads, and `fetchAssignmentPolicy` / `fetchAvailablePolicies` call `/assignment_policies` endpoints that answer 404. Both fetchers swallow the failure (`CollaboratorsPage.vue:168-171,181-182`), so the page renders empty rather than erroring — a confusing surface, not a crash. |
| an account has any other premium flag from that list | same treatment: disable before the release. None of the others has a visible surface that survives, but a flag with no implementation is a trap for the next person. |

`assignment_v2` is the exception and must be **left alone**: it is `enabled: true` and not premium, it
is OSS auto-assignment, and turning it off would change working behaviour.

### 10.3 Audit history continuity

```sql
-- read-only. Confirms the audit class rename inherits the existing history, which it does because
-- Enterprise::AuditLog and Custom::AuditLog are both subclasses on this one table.
SELECT count(*) AS audits, min(created_at) AS oldest, max(created_at) AS newest FROM audits;
```

No action depends on the result. It is recorded so that after the release the operator can confirm
the same count is still there and still growing, rather than taking it on trust.

---

## 11. Removal readiness verdict

# NOT READY FOR ENTERPRISE REMOVAL

Six of the seven dependencies the audit named are closed and measured. **One is not**, and because it
is part of the capability this phase was told not to regress, the verdict cannot be anything else.

### The single blocker

`Enterprise::Whatsapp::IncomingMessageBaseService#process_statuses`
(`enterprise/app/services/enterprise/whatsapp/incoming_message_base_service.rb`, 17 lines) is the
delivered / read / failed path for campaign recipients. It updates the recipient from Meta's status
callback, and defers a status that arrives before the recipient's `source_id` is persisted to
`Campaigns::UpdateRecipientStatusJob`.

If `enterprise/` were deleted today, campaign recipients would still be created and marked `sent`,
and the analytics page would still load — but no recipient would ever progress to `delivered`, `read`
or `failed`. Partial reporting that looks like working reporting is worse than none, so this is a
blocker rather than a caveat.

It is also, measurably, **the only** thing left: the full suite without `enterprise/` fails exactly
one example, and this is it (section 9.6).

**Why it is not done.** The fix is four lines of `Custom::` overlay, written and verified, then
reverted. Adding it while the Enterprise copy is present puts both in the ancestor chain: Custom runs,
calls `super`, Enterprise runs, and the deferral job is enqueued **twice**. That is not a theoretical
concern — the relocated spec catches it:

```
Custom::Whatsapp::IncomingMessageBaseService
  defers a campaign status when neither a recipient nor a message is persisted yet
    expected to enqueue exactly 1 jobs … but enqueued 2
```

Unlike every other overlay in this phase, the two copies are not disjoint and not idempotent, so they
cannot coexist. The relocation therefore requires the Enterprise copy to go, and that is a deletion
inside `enterprise/` — which this environment's permission policy refused
(*"Irreversible Local Destruction"*). I did not route around it, and I did not weaken the spec to
accommodate the duplication.

**What is needed to clear it: permission to delete two files inside `enterprise/`.**

```
enterprise/app/services/enterprise/whatsapp/incoming_message_base_service.rb
enterprise/app/services/enterprise/whatsapp/providers/base_service.rb
```

Both contain *only* campaign-recipient behaviour that this phase has relocated — the first is the
status path, the second is the `last_error` capture whose Custom:: replacement is already in place and
harmlessly duplicated. With those two gone, `process_statuses` moves into
`custom/app/services/custom/whatsapp/incoming_message_base_service.rb` beside the Lynomia behaviour
already there, the spec passes at exactly one enqueue, and item 7 closes.

For reference, 16 files have already moved out of `enterprise/` in this phase by `git mv`, which the
same policy allowed; it is specifically deletion that was refused.

### After that blocker is cleared

The verdict becomes **READY FOR ENTERPRISE REMOVAL WITH PRODUCTION DATA GATE** — the gate being the
three read-only checks in section 10, of which only §10.2 (`advanced_assignment`) can require an
action before the release.

### What removal will still change, by design

These are consequences, not defects, and each was a decision recorded above:

| Capability | After removal |
|:--|:--|
| SLA, Captain assistants / copilot / documents, companies CRM, agent capacity, balanced assignment, SAML SSO, voice and calling, Cloudflare custom domains, the audit log viewer, Chatwoot Cloud billing, Clearbit, OpenSearch advanced search, audio transcription | gone. 26 controllers and 113 route declarations already removed; the remaining 41 gated routes disappear with the directory |
| Sign-in / sign-out and record-deletion audit rows | no longer written. The 11 model-level declarations are preserved; these two were manual writes in the Enterprise sessions controller and delete job, and were judged not worth porting. Listed so the loss is a decision |
| `advanced_assignment` and other premium flags | nothing disables them any more. §10.2 |
| 25 enterprise-owned tables | left in place, unreferenced. No table is dropped; nothing has an inbound foreign key |
| The `spec/enterprise/` suite | no longer passes, because 113 of the routes it exercises are gone. Section 8 |

### What was explicitly not done

`enterprise/` was not removed. No file inside it was edited or deleted — only relocated, 16 times, by
`git mv`. No table dropped, no migration added, no production data read or written, no feature flag or
licensing file changed, no second audit store, no second RBAC system, no replacement billing.
