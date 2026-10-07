# Enterprise dependency audit

**Status: ANALYSIS ONLY. Nothing was removed, disabled, moved, rewritten or modified.**
No feature flag was changed, no licensing file was touched, no runtime behaviour was refactored.
The only file this phase adds to the repository is this document.

Audited at `5d471ee9`, branch `claude/practical-thompson-9xfqed`, working tree clean before and after.

**Scope note on licensing.** Section 9 is a *technical file-boundary map*: which files sit under
`enterprise/`, and which files outside it reach in. It is a dependency map and nothing more. This
document draws **no legal conclusion** about entitlement, licence compatibility or what may lawfully
be redistributed, and it neither modifies nor reinterprets `enterprise/LICENSE`. That remains an
open external gate owned by you.

**Two citations in an earlier draft of this document were wrong and are corrected here.** The
`audit_logs` route is `config/routes.rb:127`, not `:120`, and the enterprise-gated route examples are
`:152/:195/:276/:278/:309/:389/:573/:707`, not `:198/:221`. Both stale numbers came from a prior
session's notes (`docs/p7/00b-discovery-informational.md:651`); `config/routes.rb` has shifted since.
Every line number below was re-read in this session before being written.

**Evidence standard.** Every number and path below was derived by direct inspection in this session —
`db/schema.rb` reads, mechanical greps, `Rails.application.routes` enumeration under a booted app, and
reading the `audited` gem's own source. Where a conclusion reverses an intuition, the measurement that
reversed it is shown. A parallel 14-agent sweep was also launched for breadth; it had not returned by
the time this was written, so **nothing here depends on it**. Anything it adds later will be appended
as a revision rather than silently merged.

---

## 1. Executive summary

Lynomia's own code has **exactly one** dependency on `enterprise/`: optional audit logging through
`Enterprise::AuditLog`, and all three call sites already guard it with `defined?`.

A transitive sweep of 26 Lynomia product areas against 309 enterprise-only constants and 108 overlay
injection constants found enterprise coupling in **3** areas. Two are the guarded `Enterprise::AuditLog`
calls. The third is a **code comment**.

| | |
| --- | --- |
| Files under `enterprise/` | **557** (514 `app`, 38 `lib`, 3 `config`, 1 railtie, 1 LICENSE) |
| Classes/modules defined only under `enterprise/` | **309** (excluding `Enterprise::` overlay modules) |
| OSS injection call sites (`prepend_mod_with` etc.) outside `enterprise/` and `custom/` | **122** |
| …answered by an `Enterprise::` module | **107** |
| …also answered by a `Custom::` module (Lynomia is consulted first) | **14** |
| …answered by `Custom::` only | **13** |
| …answered by neither — a no-op today | **2** |
| Routes whose controller exists **only** under `enterprise/` | **154**, across **38** controllers |
| Tables in OSS `db/schema.rb` whose model exists only under `enterprise/` | **14** |
| Jobs under `enterprise/app/jobs` | **50** |
| Spec files under `spec/enterprise` | **291** of 1051 total |
| **Lynomia files that reference `Enterprise::` in live code** | **3 files / 5 lines**, all `Enterprise::AuditLog`, all guarded |

**Rails would still boot with `enterprise/` absent.** Every load path is guarded, and the overlay
injector is designed to no-op when the namespace is missing. Removal is a *feature-loss* event, not a
*boot* event. The costs land almost entirely on upstream Chatwoot Enterprise features Lynomia's stated
product does not include.

---

## 2. Enterprise runtime map

### 2.1 How `enterprise/` enters the process

| Mechanism | Location | Guarded? | If `enterprise/` were absent |
| --- | --- | --- | --- |
| `eager_load_paths << enterprise/lib` | `config/application.rb:43` | no | path simply does not exist; Rails tolerates it |
| `eager_load_paths << enterprise/listeners` | `config/application.rb:44` | no | same |
| `eager_load_paths += Dir["…/enterprise/app/**"]` | `config/application.rb:46` | implicitly | `Dir[]` returns `[]` — nothing added |
| view path unshift | `config/application.rb:49` | no | a non-existent view path is inert in Rails lookup |
| enterprise initializers `require`d | `config/application.rb:63-64` | **yes** — `if enterprise_initializers.exist?` | skipped |
| overlay injection | `config/initializers/01_inject_enterprise_edition_module.rb` | **yes** — see below | every call site no-ops |
| `enterprise/tasks_railtie.rb` | loads enterprise rake tasks | n/a | tasks absent |

### 2.2 The injector is fail-safe by design

`config/initializers/01_inject_enterprise_edition_module.rb:82-87`:

```ruby
def const_get_maybe_false(mod, name)
  # mod is false when the extension namespace is missing (e.g. custom/ without enterprise/)
  return false unless mod
  mod.const_defined?(name, false) && mod.const_get(name, false)
end
```

`each_extension_for` (`:70-80`) yields only when the module resolves. So all 122 call sites degrade to
no-ops. This is the single most important structural fact in the audit: **the overlay was built to be
removable.**

### 2.3 Override ordering, and a correction

`ChatwootApp.extensions` returns `%w[enterprise custom]` whenever `custom/` exists
(`lib/chatwoot_app.rb:40-48`). `prepend` applies in order, so the ancestor chain is
`[Custom::X, Enterprise::X, OSSClass]`.

**I initially recorded the 14 both-answered constants as "Enterprise override dead". That is wrong.**
`Custom::X` is consulted *first*, but if it calls `super` the Enterprise module still runs. I checked
all five of Lynomia's WhatsApp/message overrides and **every one calls `super`**:

| Lynomia module | `super` at |
| --- | --- |
| `custom/app/services/custom/whatsapp/providers/whatsapp_cloud_service.rb` | `:10` |
| `custom/app/services/custom/whatsapp/providers/base_service.rb` | `:8`, `:14` |
| `custom/app/services/custom/whatsapp/incoming_message_base_service.rb` | `:8` |
| `custom/app/jobs/custom/webhooks/whatsapp_events_job.rb` | `:17`, `:21` |
| `custom/app/models/custom/message.rb` | `:20` |

So the Enterprise modules in those chains **do execute today**. What they contribute is section 4.

---

## 3. Enterprise features currently active

Reachability was judged by route + controller + flag, never by UI visibility.

| Feature | Enterprise surface | Flag | Default | Reachable today? |
| --- | --- | --- | --- | --- |
| **Captain assistants / copilot / documents** | 66 routes, `enterprise/app/controllers/api/v1/accounts/captain/*` | `captain_integration`, `captain_integration_v2` | **off** (auto-enabled per account when `INSTALLATION_PRICING_PLAN ∈ {premium,enterprise}`, `enterprise/app/models/enterprise/account.rb:103-105`) | flag-gated |
| **Captain task services** | **OSS** — `lib/captain/*.rb`, `app/controllers/api/v1/accounts/captain/tasks_controller.rb` | `captain_tasks` | **ON** (`config/features.yml:241-243`) | **yes, and not Enterprise** |
| Cloud billing (Stripe/Shopify) | 18 routes, `enterprise/app/controllers/enterprise/api/v1/accounts_controller.rb` | — | cloud-only paths | Lynomia has its own billing |
| Companies | 15 routes, `enterprise/app/models/company.rb`, table `companies` (`db/schema.rb:916`), frontend route wired at `app/javascript/dashboard/routes/dashboard/dashboard.routes.js:6` | `companies` | **off**, `premium: true` (`config/features.yml:230`) | flag-gated |
| Agent capacity policies | 13 routes, 2 tables | — | — | admin-only, unused by Lynomia |
| SLA | 9 routes, 3 tables (`sla_policies`, `applied_slas`, `sla_events`) | — | — | unused by Lynomia |
| Custom roles | 6 routes, `custom_roles` table | `custom_roles` | — | see §9 — Lynomia **overrides** its only relevant grant |
| SAML SSO | OSS routes `config/routes.rb:115` and `:473`, OSS table `account_saml_settings` (`db/schema.rb:31`), enterprise-only model/controller **and** middleware registered by `enterprise/config/initializers/omniauth_saml.rb` | — | — | reachable if configured |
| WhatsApp calling | 6 routes + extensive OSS frontend (`FloatingCallWidget`, `ConversationCallButton`, `useWhatsappCallSession.js`) | `channel_voice` | **off**, `premium: true` | flag-gated |
| Voice (Twilio) / conference | 7 routes | `channel_voice` | off | flag-gated |
| Audit logs | 1 route (`GET /api/v1/accounts/:id/audit_logs`), **unconditionally routed** at `config/routes.rb:127` | — | — | **yes** |
| Advanced reports / reporting events | 1 route, gated `if ChatwootApp.enterprise?` | — | — | yes |
| Campaign analytics | 2 routes | — | — | upstream campaign model |
| Custom domains, Firecrawl, Stripe webhooks | 3 controllers | — | — | cloud/upstream |
| OpenSearch advanced search | `ChatwootApp.advanced_search_allowed?` = `enterprise? && OPENSEARCH_URL` | — | env-gated | not configured here |
| Super Admin enterprise fields | `enterprise/app/fields/{account_limits,account_features,manually_managed_features,captain_model_overrides}_field.rb` | — | — | yes, **correctly guarded** (§6) |

---

## 4. Lynomia dependencies

### 4.1 The only real one — C

| | |
| --- | --- |
| **Enterprise file** | `enterprise/app/models/enterprise/audit_log.rb` (`Enterprise::AuditLog < Audited::Audit`) |
| **Lynomia callers** | `custom/app/services/flows/audit.rb:11,13` · `custom/app/services/commerce/audit_trail.rb:27,29` · `custom/app/models/custom/audit/custom_filter.rb:8` |
| **Runtime chain** | Flow publish / commerce order action / shared-audience change → Lynomia audit service → `defined?(Enterprise::AuditLog)` → `Enterprise::AuditLog.create!` |
| **Feature affected** | audit trail for Flow Builder, Commerce actions, shared audiences |
| **API/UI affected** | `GET /api/v1/accounts/:id/audit_logs` (enterprise-only controller) |
| **DB dependency** | `audits` — **an OSS table**, created by the OSS `audited` gem (`Gemfile:184`, `audited (5.4.1)`) |
| **Replacement difficulty** | **easy** |
| **Strategy** | define `Lynomia::AuditLog < Audited::Audit` (or use `Audited::Audit` directly) and point the three guards at it. The table, gem and write path are all already OSS. |
| **Reuse core?** | **yes, fully** — `Audited::Audit` is the gem's own class |
| **Lynomia partial replacement already?** | yes in effect: all three sites are already written to run with the constant absent |
| **Removal impact** | `NO_IMPACT` on correctness; `BACKEND_FEATURE_FAILURE` only in that those three actions stop being audited |

**Why this is not worse than it looks.** `config/initializers/audited.rb:4` — a file **outside**
`enterprise/` — sets `config.audit_class = 'Enterprise::AuditLog'`. That reads like a hard core
dependency. It is not, and the reason is in the gem:

```ruby
# vendor/bundle/ruby/3.4.0/gems/audited-5.4.1/lib/audited.rb:15-20
def audit_class
  @audit_class = @audit_class.safe_constantize if @audit_class.is_a?(String)
  @audit_class ||= Audited::Audit
end
```

`safe_constantize`, not `constantize`. Measured: `'Enterprise::AuditLog'.safe_constantize` → `nil`;
`constantize` → `NameError`. So the gem falls back to `Audited::Audit` and **every audited write keeps
working**, including Lynomia's own unguarded `audited associated_with: :account` at
`custom/app/models/whatsapp/message_template.rb:46`. I had this queued as the audit's top risk until I
read the gem.

### 4.2 Indirect — what Enterprise contributes to Lynomia's `super` chains

All five Enterprise modules in Lynomia's WhatsApp/message chains turn out to implement features
outside Lynomia's product:

| Enterprise module | What it adds | Lynomia impact if absent |
| --- | --- | --- |
| `enterprise/app/services/enterprise/whatsapp/providers/whatsapp_cloud_service.rb` (122 lines) | **WhatsApp calling only** — `pre_accept_call`, `accept_call`, `reject_call`, `terminate_call`, `initiate_call`, `send_call_permission_request`, `update_calling_status`. Does **not** define `sync_templates` or touch the send path | none — Lynomia's `Custom#sync_templates` `super` lands on the OSS method either way |
| `enterprise/app/jobs/enterprise/webhooks/whatsapp_events_job.rb` (60 lines) | `call_event?`, `handle_call_events`, `call_permission_reply?` — **calling** | none for text/template messaging |
| `enterprise/app/models/enterprise/message.rb` (84 lines) | `captain_response_triggering?`, `captain_pending_conversation?`, `create_captain_auto_open_activity_message` — **Captain** | none with Captain off |
| `enterprise/app/services/enterprise/whatsapp/providers/base_service.rb` (25 lines) | sets `@last_error` from Meta's error payload | **none** — the only consumer is `enterprise/app/models/enterprise/channel/whatsapp.rb:9`. Nothing in `app/` or `custom/` reads `last_error` |
| `enterprise/app/services/enterprise/whatsapp/incoming_message_base_service.rb` (17 lines) | updates `CampaignRecipient` from WhatsApp status webhooks; enqueues `Campaigns::UpdateRecipientStatusJob` behind `feature_enabled?(:whatsapp_campaign)` | **none** — `CampaignRecipient` is referenced **only inside `enterprise/`** (zero hits in `app/`, `custom/`, `lib/`), and `whatsapp_campaign` is `enabled: false` (`config/features.yml:193-195`). Lynomia uses its own `custom/app/models/custom/campaign_audience.rb` |

**Lynomia's delivery-failure UX does not depend on Enterprise.** `custom/app/models/custom/message.rb:16`
reads `Whatsapp::DeliveryFailure.for(self)`, which parses `content_attributes.external_error` — written
by the OSS path. It never reads the Enterprise `@last_error`.

---

## 5. Unused Enterprise features

Classified **A_UNUSED** or **B_UPSTREAM_ONLY** for Lynomia's stated product. "Unused" here always means
*no runtime caller was found*, never *the UI is hidden*.

| Capability | Class | Evidence |
| --- | --- | --- |
| Captain assistants, copilot, documents, scenarios, FAQ suggestions, agent sessions, message reports | B | 66 routes, all flag-gated; `captain_integration*` default off |
| SLA (policies, applied SLAs, events) | B | 9 routes; 3 enterprise-only tables; no `app/` or `custom/` reference |
| Agent capacity policies + inbox capacity limits | B | 13 routes; 2 enterprise-only tables |
| Companies + company notes/contacts/conversations | B | `companies` flag `enabled: false, premium: true`; **Lynomia's Customer 360 is its own** (`custom/app/services/commerce/customer360.rb`) and contains zero `Company` references |
| SAML SSO | B | enterprise model + controller + middleware; no Lynomia caller. Lynomia auth is `custom/app/controllers/api/v1/mobile/auth_controller.rb` |
| Cloud billing (Stripe, Shopify subscriptions, topups, Cloudflare verification, custom domains) | B | Lynomia has its own billing under `custom/app/controllers/{api/v1/accounts/billing_controller.rb, platform/api/v1/billing/*, billing/*}` |
| WhatsApp calling / voice / conference / Twilio voice | B | `channel_voice` `enabled: false, premium: true` |
| `whatsapp/access_requests` | **A** | doubly closed: the route is gated (`config/routes.rb:389` — `resource :access_request, only: [:create] if ChatwootApp.enterprise?`) **and** the action raises — `enterprise/.../whatsapp/access_requests_controller.rb:7`, `raise Pundit::NotAuthorizedError unless ChatwootApp.chatwoot_cloud?`. Unreachable on a self-hosted install |
| `Enterprise::Whatsapp::Providers::BaseService#parsed_error` | **A** for Lynomia | sets an ivar whose only reader is another enterprise file |
| Campaign recipient status tracking | B | `CampaignRecipient` referenced only within `enterprise/`; `whatsapp_campaign` off |
| OpenSearch advanced search / article embeddings | B | needs `OPENSEARCH_URL`; not configured |
| Onboarding Help Center article generation | B | Lynomia **removed** tenant Help Center authoring; `custom/app/controllers/custom/api/v1/accounts/onboardings_controller.rb` already no-ops `create_help_center` |
| Enterprise audit-log IP geolocation jobs (3) | B | enterprise-internal enqueuers only |
| 41 of 50 enterprise jobs | B | "enterprise-internal only" — no `app/`, `custom/`, `lib/` or cron enqueuer |

---

## 6. Boot / runtime dependencies (D)

**No `D_CORE_BOOT_RUNTIME` item was found.** Each candidate was checked and each is guarded.

| Candidate | Why it is **not** a boot dependency |
| --- | --- |
| `config/initializers/audited.rb:4` sets `audit_class = 'Enterprise::AuditLog'` | gem uses `safe_constantize` → falls back to `Audited::Audit` (§4.1, measured) |
| `app/dashboards/account_dashboard.rb:13,17,20,21` reference 4 enterprise-only field classes | wrapped in `if ChatwootApp.enterprise?` at `:11` with `else {}` at `:24-26` |
| 122 `prepend_mod_with` / `include_mod_with` call sites | `const_get_maybe_false` returns `false`; each call no-ops |
| `config/schedule.yml` cron entries | names **only OSS** job classes (`TriggerScheduledItemsJob`, `Internal::TriggerDailyScheduledItemsJob`, …). Enterprise merely prepends onto them |
| `config/application.rb:43-49` load paths | non-existent paths are inert; `Dir[]` returns `[]` |
| `enterprise/config/initializers/omniauth_saml.rb` | `require`d only `if …exist?` |

**One real landmine, not a boot failure.** 154 routes resolve to controllers that exist only under
`enterprise/`. Routes are resolved lazily, so the app boots; the first request to any of them raises
`NameError` → **500**. Two are in the OSS route table with no `ChatwootApp.enterprise?` guard at all:

- `config/routes.rb:127` → `resource :audit_logs, only: [:show]` — sits unguarded between `assignable_agents` and `callbacks`
- `config/routes.rb:115` → `resource :saml_settings` (show/create/update/destroy)
- `config/routes.rb:473` → `POST auth/saml_login`

### 6.1 Pre-existing configuration hazard — do not use `DISABLE_ENTERPRISE`

`lib/chatwoot_app.rb:15` is `return if ENV.fetch('DISABLE_ENTERPRISE', false)`. Every non-nil ENV
string is truthy in Ruby, so even `DISABLE_ENTERPRISE=false` makes `enterprise?` falsey — **while
`extensions` (`:40-48`) checks `custom?` first and still returns `%w[enterprise custom]`**. The result
is a half-disabled edition: the overlay is still prepended, but every `enterprise?` gate reports false.
Recorded previously as `SHO-12` in `docs/p7/00-discovery-findings.md:415`. **The clean path is directory
removal, never this flag.**

---

## 7. Database dependencies

14 tables live in the OSS `db/schema.rb` but their models exist only under `enterprise/`. The schema is
shared; the code is not.

| Table | Enterprise model | Lynomia use |
| --- | --- | --- |
| `agent_capacity_policies`, `inbox_capacity_limits` | `agent_capacity_policy.rb`, `inbox_capacity_limit.rb` | none |
| `sla_policies`, `applied_slas`, `sla_events` | `sla_policy.rb`, `applied_sla.rb`, `sla_event.rb` | none |
| `custom_roles` | `custom_role.rb` | **overridden** — see §9 |
| `companies` | `company.rb` | none (Customer 360 is Lynomia's own) |
| `campaign_recipients` | `campaign_recipient.rb` | none |
| `calls` | `call.rb` | none |
| `copilot_threads`, `copilot_messages`, `agent_sessions`, `conversation_outcomes`, `article_embeddings` | Captain models | none |

Removing `enterprise/` leaves these tables **present and orphaned** — no migration is required, no data
is lost, and nothing reads them. `audits` is **not** in this list: it is an OSS table owned by the
`audited` gem.

---

## 8. Frontend dependencies

**Removing the backend `enterprise/` directory has no effect on the frontend build.** No JavaScript or
Vue file imports from a path under `enterprise/`. The `app/javascript/dashboard/api/enterprise/`
directory is a *naming* convention for cloud-billing API clients, not a link into the backend tree.

| Frontend surface | Backend it calls | Status |
| --- | --- | --- |
| `dashboard/api/enterprise/account.js` (`checkout`, `subscription`, `billing_summary`, `limits`, `topup_*`) imported by `store/modules/accounts.js:6` and `settings/billing/ShopifyBilling.vue:7` | `enterprise/app/controllers/enterprise/api/v1/accounts_controller.rb` | **FRONTEND_FEATURE_FAILURE** on removal — Chatwoot Cloud billing UI. Lynomia ships its own billing |
| `routes/dashboard/companies/**` wired at `dashboard.routes.js:6` | enterprise Companies controllers | flag-gated on `companies` (off) |
| `useWhatsappCallSession.js`, `FloatingCallWidget.vue`, `ConversationCallButton.vue`, `VoiceCallButton.vue`, `VoiceCall.vue`, `stores/calls.js`, `helper/voice.js` | `whatsapp_calls`, `calls`, `conference` controllers | flag-gated on `channel_voice` (off) |
| Captain assistant/copilot UI | Captain controllers | flag-gated |

---

## 9. Permissions dependencies

`CustomRole` (`enterprise/app/models/custom_role.rb`, table `custom_roles`) is consulted by Enterprise
policy overrides. The only one that intersects Lynomia is the Help Center trio, and **Lynomia already
overrides it**:

| OSS policy | Enterprise override | Lynomia override | Net effect |
| --- | --- | --- | --- |
| `PortalPolicy` (`app/policies/portal_policy.rb:39`) | grants on `knowledge_base_manage` | `custom/app/policies/custom/portal_policy.rb` returns `false` for every verb | Lynomia wins; the Enterprise grant never takes effect |
| `ArticlePolicy` (`:31`) | same | `custom/app/policies/custom/article_policy.rb` | same |
| `CategoryPolicy` (`:31`) | same | `custom/app/policies/custom/category_policy.rb` | same |

Because `Custom::` modules define these methods **without `super`**, the Enterprise grant genuinely
cannot run for those three policies. Removing `enterprise/` would not change tenant authorization for
Lynomia's product. Specs already assert this (`spec/policies/*_policy_spec.rb`,
`spec/enterprise/policies/*_policy_spec.rb`, `spec/requests/custom/tenant_help_center_removal_spec.rb`).

### LICENSE BOUNDARY MAP (technical file boundaries only — no legal conclusion)

1. **Files under `enterprise/`** — 557 files; 309 constants defined only there.
2. **Files outside `enterprise/` that call into it** — 122 injection call sites in `app/`, `lib/`,
   `config/` (107 answered); plus `config/initializers/audited.rb:4`;
   plus `app/dashboards/account_dashboard.rb:13,17,20,21` (guarded);
   plus 3 unguarded OSS route declarations (`config/routes.rb:115`, `:127`, `:473`).
3. **Lynomia custom files that depend on Enterprise code** — **3**:
   `custom/app/services/flows/audit.rb`, `custom/app/services/commerce/audit_trail.rb`,
   `custom/app/models/custom/audit/custom_filter.rb` — all `Enterprise::AuditLog`, all `defined?`-guarded.
4. **Upstream files modified by Lynomia that indirectly rely on Enterprise behaviour** — the 14
   both-answered constants in §2.3. Five call `super` into Enterprise, and all five Enterprise
   contributions are WhatsApp calling or Captain (§4.2).

---

## 10. Background-job dependencies

50 jobs under `enterprise/app/jobs`. **41 have no enqueuer outside `enterprise/`.** The 9 that appear
to have one are all cases where OSS owns the job class and Enterprise prepends a module onto it —
verified against `config/schedule.yml`, which names only OSS classes:

`Internal::TriggerDailyScheduledItemsJob`, `TriggerScheduledItemsJob`,
`Internal::TriggerHourlyScheduledItemsJob`, `Account::ConversationsResolutionSchedulerJob`,
`DeleteObjectJob`, `Internal::CheckNewVersionsJob`, `Webhooks::WhatsappEventsJob`, and the two
`Captain::*ResponseBuilderJob` names referenced as **strings** in
`lib/captain_response_dequeued_logger.rb:3`.

Removal impact: `BACKGROUND_JOB_FAILURE` confined to Enterprise features. No Lynomia job
(`custom/app/jobs/**`, `Commerce::ActionSweepJob`, `Lynomia::QueueHealthJob`) touches `enterprise/`.

---

## 11. Feature-by-feature Lynomia matrix

Transitive sweep: each area's implementation paths grepped for `Enterprise::` and for all 309
enterprise-only constants.

| Lynomia area | Verdict | Evidence |
| --- | --- | --- |
| WhatsApp Cloud API | **no coupling** | `custom/app/services/whatsapp`, `custom/app/jobs/custom/webhooks`, `app/services/whatsapp` — zero hits |
| Meta Coexistence | no coupling | zero hits |
| WhatsApp Template Manager | no coupling | zero hits |
| Inbox / Conversations | no coupling | zero hits |
| Contacts | no coupling | zero hits |
| Customer 360 | no coupling | `custom/app/services/commerce/customer360.rb` — zero `Company` references |
| **Commerce** | **C — guarded** | `custom/app/services/commerce/audit_trail.rb:27,29` `Enterprise::AuditLog` |
| WooCommerce / Salla / Zid / Shopify | no coupling | zero hits each |
| Abandoned Cart | no coupling | zero hits |
| Audience Builder | no coupling | zero hits |
| Shared Audiences | no coupling | zero hits (the `custom_filter` audit guard is in the model, §4.1) |
| Automations | no coupling | zero hits |
| **Flow Builder** | **C — guarded** | `custom/app/services/flows/audit.rb:11,13` `Enterprise::AuditLog` |
| Campaigns | no coupling | `CampaignRecipient` is enterprise-internal; Lynomia uses `custom/app/models/custom/campaign_audience.rb` |
| Documentation / Changelog / Help & Support | no coupling | zero hits |
| Branding / API documentation / Observability | no coupling | zero hits |
| Authentication / Mobile Auth | no coupling | zero hits |
| Super Admin | no coupling | Lynomia's controllers inherit `SuperAdmin::ApplicationController`, not the enterprise base |
| **Roles / Permissions** | **comment only** | `custom/app/policies/custom/portal_policy.rb:16` names `Enterprise::PortalPolicy` in prose |
| Billing | no coupling | Lynomia billing is its own |
| Webhooks | no coupling | zero hits |
| Analytics / reporting | not swept as Lynomia-owned | upstream reporting; `reporting_events` route is enterprise-gated |
| integrations | no coupling | zero hits |

---

## 12. Removal impact simulation

*Static simulation. The directory was **not** removed.*

| Impact class | What falls into it |
| --- | --- |
| **BOOT FAILURE** | **none.** All load paths guarded; injector no-ops; `account_dashboard.rb` guarded; gem falls back |
| **BACKEND FEATURE FAILURE** | 154 routes → `NameError` 500 on first request, across 38 controllers: Captain (66), cloud billing (18), Companies (15), agent capacity (13), SLA (9), custom roles (6), WhatsApp calling (6), SAML (5), Twilio voice (4), conference (3), campaign analytics (2), reporting events, custom domains, audit logs. Plus loss of the 107 Enterprise overlay behaviours |
| **FRONTEND FEATURE FAILURE** | cloud-billing UI (`ShopifyBilling.vue`, accounts store), Companies pages, Captain UI, call widgets. **The build itself is unaffected** — no JS imports the backend tree |
| **BACKGROUND JOB FAILURE** | Enterprise-only jobs (SLA, Captain, Companies, billing reconciliation, audit IP lookup, voice transcription). No Lynomia job affected |
| **PERMISSION FAILURE** | **none for Lynomia.** `CustomRole` grants disappear; the Help Center trio is already overridden by `Custom::` without `super` |
| **DATA MODEL FAILURE** | **none.** 14 tables orphaned but intact; no migration needed; `audits` is OSS |
| **NO IMPACT** | Lynomia's 26 swept areas, except that three actions stop writing audit rows |

---

## 13. Replacement complexity matrix

| Work item | Difficulty | Reuse core? | Partial already? |
| --- | --- | --- | --- |
| 1. Lynomia-owned audit log replacing `Enterprise::AuditLog` | **easy** | yes — `Audited::Audit`, OSS gem + OSS table | yes, three `defined?` guards |
| 2. Decide the fate of `GET /audit_logs` (replace controller, or drop the route) | **easy** | yes — a plain Administrate/API controller | no |
| 3. Remove or guard the 3 unguarded OSS route declarations (`routes.rb:115`, `:127`, `:473`) | **easy** | n/a | no |
| 4. Decide the fate of cloud-billing frontend (`ShopifyBilling.vue`, accounts store import) | **easy–medium** | Lynomia billing already exists | yes |
| 5. Companies — keep, replace or drop | **medium** | model + 15 routes + frontend; or drop (flag already off) | no |
| 6. SAML SSO — replace or drop | **medium** | `omniauth-saml` is a gem; the model is thin; the table is OSS | no |
| 7. WhatsApp calling — replace or drop | **hard** | 122-line provider + 6 routes + large OSS frontend | no |
| 8. Captain assistants/copilot/documents — replace or drop | **hard** | 66 routes, 5 tables, large UI. **OSS task services in `lib/captain/` are unaffected** | no |
| 9. SLA — replace or drop | **medium–hard** | 3 tables, 9 routes, scheduler jobs | no |
| 10. Agent capacity — replace or drop | **medium** | 2 tables, 13 routes | no |
| 11. Custom roles — replace or drop | **medium** | affects upstream policies, not Lynomia's | no |

**Only items 1–4 are required for Lynomia's stated product. Items 5–11 are decisions about upstream
Chatwoot Enterprise features, not Lynomia gaps.**

---

## 14. Safe migration / removal strategy

Staged, each stage independently verifiable, nothing destructive before its predecessor is proven.

1. **Do not set `DISABLE_ENTERPRISE`** (§6.1). It produces a half-disabled state, not a clean one.
2. **Decouple audit logging.** Introduce a Lynomia audit class on the OSS `audited` gem and repoint the
   three guards. Verify with the existing Flow and Commerce audit specs.
3. **Close the three unguarded routes.** Either guard them with `if ChatwootApp.enterprise?` — the
   pattern already used at `routes.rb:152`, `:195`, `:276`, `:278`, `:309`, `:389`, `:573`, `:707` — or
   move the audit-log controller into Lynomia ownership.
4. **Decide the cloud-billing frontend.** It is the only frontend code that would 500 against a missing
   enterprise backend on a page a tenant can reach.
5. **Take an inventory decision per upstream feature** (items 5–11). Each is independent.
6. **Only then** consider the directory. Removal is a product decision plus an external legal question
   that this document does not answer.
7. **Re-run the full gate** after each stage: `bundle exec rspec`, excluding `spec/enterprise` once the
   corresponding feature is intentionally gone (§16).

---

## 15. What can be removed safely (technically) today

- Nothing needs to be removed for Lynomia's product to work; the overlay is already inert for it.
- If the goal is to *stop executing* Enterprise code with minimum change: steps 2–4 above leave Lynomia
  fully functional, and every remaining Enterprise route is either flag-gated off or serves an upstream
  feature Lynomia does not ship.

## 16. What must be replaced first

1. `Enterprise::AuditLog` → a Lynomia class (work item 1). The only true Lynomia dependency.
2. The `audit_logs` route/controller pair, if the audit UI is wanted (item 2).
3. The three unguarded OSS route declarations — `config/routes.rb:115`, `:127`, `:473` (item 3).

## 17. What must NOT be touched yet

- `enterprise/LICENSE` — untouched here and in every commit on this branch
  (`git hash-object` matches the upstream base). External legal gate, still open.
- `config/initializers/01_inject_enterprise_edition_module.rb` — the mechanism that makes removal safe.
- `config/initializers/audited.rb` — harmless as written; changing it before item 1 would remove the
  graceful fallback.
- `lib/chatwoot_app.rb` — `DISABLE_ENTERPRISE` has the `SHO-12` defect; do not build on it.
- `spec/enterprise/**` (291 files) — do not delete. They are the specification of what each Enterprise
  feature does, and the reference for anything replaced.
- The `captain_tasks` flag and `lib/captain/**` — **OSS**, default **on**, and the live `ruby_llm`
  reachability path. Out of scope here; tracked separately.

---

## 18. Open questions

1. **Which Enterprise features does any live account actually have enabled?** Flag defaults are read
   here; per-account bits are host state. The §4 query in
   `docs/p7/14-readiness-matrix.md`'s companion collector answers it read-only.
2. **Is `INSTALLATION_PRICING_PLAN` ∈ {premium, enterprise} on the host?** If so,
   `enterprise/app/models/enterprise/account.rb:103-105` has been auto-enabling `captain_integration`
   and `captain_integration_v2` for every new account.
3. **Is SAML configured for any account?** `account_saml_settings` row count decides whether item 6 is
   a removal or a replacement.
4. **Does any account rely on `GET /audit_logs` operationally?**
5. **Is the cloud-billing UI reachable in Lynomia's navigation,** or is it orphaned by routing?
6. **UNKNOWN — Analytics/reporting.** I classified `reporting_events` from its route guard but did not
   trace Lynomia's reporting surface end to end. Test: exercise every Reports page against a build with
   `enterprise/` moved aside in a scratch checkout.
7. **UNKNOWN — the 107 Enterprise overlay behaviours individually.** I verified the five on Lynomia's
   WhatsApp/message path in full. The other ~102 were classified structurally, not read line by line.
   Test: for each, diff behaviour with and without the module in a scratch checkout.
8. The 14-agent parallel sweep had not returned. Its breadth would mainly reduce question 7.

### Test evidence

- `spec/enterprise/**` — **291** spec files. These would fail if `enterprise/` were removed, and they
  are the only tests that cover Enterprise behaviour. They cover features Lynomia does not use, but
  they must not be deleted: they document the behaviour of anything replaced.
- Tests that protect Lynomia's dependencies: `spec/policies/{portal,article,category}_policy_spec.rb`
  and their `spec/enterprise/policies` siblings (the override ordering),
  `spec/requests/custom/tenant_help_center_removal_spec.rb` (three principals × every verb).
- **Coverage gap:** no spec asserts that Lynomia's three `defined?(Enterprise::AuditLog)` guards behave
  correctly when the constant is **absent**. That is precisely the removal scenario. A spec stubbing the
  constant away would make item 1 verifiable before it is attempted.
- **Coverage gap:** no spec exercises any of the 154 enterprise-only routes with `enterprise/` absent,
  so the 500-on-first-request behaviour is reasoned from Rails' lazy controller resolution, not measured.

---

## 19. Final conclusion

**Can Lynomia operate on Chatwoot core + Lynomia custom code only?**
**Technically yes**, and it is closer than the file count suggests. Lynomia's own code has one
dependency — optional audit logging — and it is already written to run without it. 26 of 26 swept
product areas work with `enterprise/` absent. The application boots.

**What exactly prevents it today?**
Nothing prevents Lynomia *functioning*. Three things prevent a *clean* removal:

1. `Enterprise::AuditLog` — Lynomia's only real dependency (3 guarded call sites).
2. Three OSS route declarations with no enterprise guard (`config/routes.rb:115`, `:127`, `:473`) that
   would 500 on request.
3. The cloud-billing frontend, which imports an API client whose backend would be gone.

**How many replacement work items?** **11 identified; 4 required** for Lynomia's stated product.

**Trivial / medium / major:** 4 easy (items 1–4, of which 3 are required), 4 medium (5, 6, 10, 11),
3 hard (7 WhatsApp calling, 8 Captain, 9 SLA) — and all seven of the medium/hard items are decisions
about **upstream Chatwoot Enterprise features Lynomia does not ship**, not gaps in Lynomia.

**Is complete removal realistic without losing Lynomia functionality?**
**Yes — with one honest caveat.** No Lynomia feature is lost. What is lost is upstream Enterprise
functionality: Captain assistants, SLA, agent capacity, Companies, SAML, cloud billing, WhatsApp
calling and voice. All are either flag-gated off today or unused by Lynomia. The caveat is open
question 7: ~102 of the 107 overlay behaviours were classified structurally rather than read
individually, so I would not call removal *proven* safe until each is either read or exercised in a
scratch checkout with the directory moved aside. That is a bounded, mechanical piece of work — and it
is the right gate before anyone touches the directory.

**Recommendation: do not remove anything yet.** Do items 1–3 first, since they are small, independently
valuable, and reduce the dependency to zero. Then close question 7 before any removal decision. The
licence question remains yours and is untouched by this document.
