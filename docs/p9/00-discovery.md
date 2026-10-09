# P9.0 Discovery — support cases and operator visibility

Read-only discovery across the whole repository, done before any P9 code was written. Branch
`claude/p9-support-operations-center`, cut from the completed P8 head `4e8e3d0b`.

Method: twelve parallel readers, one per subsystem; five adversarial verifiers whose only job was to try to
**refute** the load-bearing claims; one completeness critic that re-checked the result and corrected it. Four of
the five verifiers returned PARTLY-WRONG or REFUTED against the readers' claims, and the critic found six
internal contradictions. Every correction is folded in below. Nothing here is asserted without a file:line.

---

## 1. What Conversation already gives us

`Conversation` (`app/models/conversation.rb:57`) is already a competent support object for the **channel-thread**
shape of support. P9 must not rebuild any of this:

| Capability | Where | Note |
| --- | --- | --- |
| Per-account human reference | `conversation.rb:429-431` | `display_id`, assigned by a Postgres BEFORE INSERT trigger off `conv_dpid_seq_<account_id>`; DB-unique via `index_conversations_on_account_id_and_display_id` (`db/schema.rb:1051`) |
| Public unguessable token | `db/schema.rb:1035` | `uuid`, `gen_random_uuid()` default; already the customer-facing CSAT handle (`conversation.rb:258-260`) |
| Lifecycle | `conversation.rb:86` | `open/resolved/pending/snoozed`, with `snoozed_until` deferral and customer-triggered reopen (`message.rb:404-435`) |
| Priority | `conversation.rb:87` | `low/medium/high/urgent`, indexed, sortable NULLS LAST (`sort_handler.rb:14-20`) |
| Ownership | `conversation.rb:116-124` | one human `assignee`, a polymorphic `ai_assignee`, a `team`; capacity-aware round-robin in `assignment_handler.rb` / `auto_assignment_handler.rb` |
| Labels | `app/models/concerns/labelable.rb` | `acts_as_taggable_on :labels` — the concern is **two methods and one macro**, fully generic, reusable on any model |
| Account-defined fields | `app/models/custom_attribute_definition.rb:45-46` | eight display types; an account can add structured conversation fields today with no P9 code |
| Messaging | `app/models/message.rb` | messages, private notes, attachments, mentions — all conversation-bound |
| CSAT | `app/models/csat_survey_response.rb` | per conversation |
| Durable metrics | `reporting_events` | six event names, the basis of all P8 analytics |
| Filtering, bulk edit, automation, macros | `Conversations::FilterService`, `BulkActionsJob`, `AutomationRules::ActionService`, `app/models/macro.rb` | |

### What Conversation does **not** model

- **No subject or title.** Nothing names the case.
- **No due date, no SLA, no escalation.** In code, nothing at all (see §3).
- **No category or resolution reason.**
- **No status history.** `status_changed_at` (`db/schema.rb:1050`) holds only the *most recent* transition.
- **Only one structured activity type.** `content_attributes.activity = { type: 'conversation_status_changed',
  status: … }` is written at `app/models/concerns/activity_message_handler.rb:50-61`. Assignee, team, label and
  priority changes are written as **localized prose with no structured payload** — unqueryable history. P8 had
  to record this as a permanent limitation; P9 inherits it.
- **No case-scoped internal note.** The `notes` table is contact-scoped, not conversation-scoped.
- **No conversation-to-conversation link, merge or parent.**

### The deciding fact

A Conversation **cannot exist without an inbox, and cannot be created without a contact**:

- `db/schema.rb:1024` — `t.integer "inbox_id", null: false`. Hard NOT NULL.
- `app/models/conversation.rb:77` — `validates :inbox_id, presence: true`; `:115` `belongs_to :inbox` with no
  `optional: true`, under `config.load_defaults 7.0` (`config/application.rb:39`). Enforced three times over.
- `db/schema.rb:1029` — `t.bigint "contact_id"` is **nullable**, but `app/models/conversation.rb:78`
  `validates :contact_id, presence: true` and `before_create :determine_conversation_status` (`:138`)
  dereferences both `inbox` and `contact` (`:308`, `:312`) before the row is written.

So the schema is permissive exactly where the model is not. An **internal operational case has no customer and
no channel**, and therefore cannot be a Conversation. This single fact decides the architecture (§10).

A second consequence: P9 must never create conversations through `insert_all` — the database will accept
`contact_id: NULL` and every serializer then raises on nil. `lib/test_data/contact_batch_service.rb` already
uses `Conversation.insert_all!`, so the hazard is real rather than theoretical.

---

## 2. Is there an existing ticket / case / incident model?

**No.** Verified by eleven independent searches across `app/models` (55 files, all read), `custom/app/models`,
`app/policies`, `custom/app/policies`, all 108 tables in `db/schema.rb` enumerated by name, `config/routes.rb`,
`config/routes/`, `spec/factories`, and the filesystem by filename. Confirmed live in a booted application:
`defined?(Ticket)`, `defined?(SupportTicket)` and `defined?(Incident)` are all `nil`.

The nearest neighbours, and why none of them is a case:

- `Commerce::ActionRun` (`custom/app/models/commerce/action_run.rb`) — one provider action attempt, not a case.
- `AutomationRulePendingExecution` — one armed automation episode, 30-day retention.
- `FlowSession` — where a conversation sits in a published flow version.
- The Help Center / portal models — content, not cases.
- `Integrations::App` entries in `config/integration/apps.yml` — Linear is present as an *integration*, not as a
  local ticket store.

---

## 3. Existing SLA architecture

This is the most misleading area in the repository, and the readers got it wrong in both directions before the
verifier corrected them. The accurate picture:

**There is no SLA backend. There is a substantial SLA periphery.**

Absent (verified by `find app lib custom config spec db -iname '*sla*' -type f`, which returns only seven
migrations and three `.liquid` mailer templates — zero `.rb` classes; plus a booted-app check where
`defined?(SlaPolicy)`, `defined?(AppliedSla)` and `defined?(SlaEvent)` are all `nil`):

- no `SlaPolicy`, `AppliedSla` or `SlaEvent` model, service, job, listener, policy or spec;
- no SLA route anywhere in `config/routes.rb`, which is the only routes file that defines them.

Present, and reusable:

| Surviving piece | Where |
| --- | --- |
| Three tables | `sla_policies` (`db/schema.rb:1661`): `name`, `description`, `first_response_time_threshold`, `next_response_time_threshold`, `resolution_time_threshold`, `only_during_business_hours`, `account_id`. `applied_slas` (`:179`): `account_id`, `sla_policy_id`, `conversation_id` **NOT NULL**, `sla_status`, `completed_at`. `sla_events` (`:1644`). No foreign keys on any of them |
| A dangling column | `conversations.sla_policy_id` (`db/schema.rb:1045`), with **no** `belongs_to` in the model, yet read on every conversation render: `app/views/api/v1/conversations/partials/_conversation.json.jbuilder:73-74` gates it on `feature_enabled?('sla')`. Orphaned, not dead — dropping it breaks that view |
| A live feature flag | `config/features.yml:131-135` — `sla`, `enabled: false`, **`premium: true`** |
| The whole client clock | `app/javascript/dashboard/helper/slaHelper.js`, `composables/useSlaStatus.js`, `components-next/Conversation/Sla/SLACardLabel.vue`, `SLAPopoverCard.vue`, `SLAEventItem.vue` — spec-covered |
| Registered Vuex stores | `store/modules/sla.js` and `store/modules/SLAReports.js`, both registered at `store/index.js:112-113` |
| API clients | `api/sla.js` (targets `/sla_policies`), `api/slaReports.js` |
| i18n in ~60 locales | `i18n/locale/*/sla.json`, including `en` and `ar` |
| Breach notifications, end to end | `Notification` enum values 6/7/8 (`app/models/notification.rb:44-46`), push titles (`:97-99`), bodies (`:118-122`), three `sla_missed_*` Liquid templates, and the agent preference toggles |

**Crucially, the SLA UI is unreachable**: there is no SLA settings route in the Vue router. The stores are
registered but nothing navigates to them, and the conversation SLA cards read an `applied_sla` field the backend
never sends. So the periphery is inert, and P9 can reuse the pieces without a dormant screen lighting up wrongly.

### Business hours

`ReportingEventHelper#business_hours(inbox, from, to)` (`app/helpers/reporting_event_helper.rb`) is a real,
working elapsed-business-time calculator built on the `working_hours` gem (`Gemfile:166`). It reads
`inbox.working_hours_enabled?`, builds a day map from `WorkingHour` rows (`app/models/working_hour.rb`:
`day_of_week`, `open_hour/open_minutes`, `close_hour/close_minutes`, `open_all_day`, `closed_all_day`), and sets
`WorkingHours::Config.time_zone = inbox.timezone`.

Two consequences P9 must respect: it is **inbox-scoped**, not account-scoped — so a case with no inbox has no
working-hours source at all; and there are **no holidays** anywhere in the schema or the code.

### What historical SLA data is unavailable

All of it. No SLA was ever computed or stored, and `applied_slas` has never had a row written by this fork. Any
SLA number P9 reports is prospective, starting from the moment a policy is attached to a case.

---

## 4. Existing Super Admin capabilities

**Administrate (ERB), with a first-class Vue-island escape hatch.** The readers claimed "not Vue"; the verifier
refuted that half.

- `gem 'administrate', '>= 0.20.1'` (`Gemfile:97`), plus `administrate-field-active_storage` and
  `administrate-field-belongs_to_search` (`:98-99`).
- `SuperAdmin::ApplicationController < Administrate::ApplicationController`
  (`app/controllers/super_admin/application_controller.rb:7`), with exactly one guard:
  `before_action :authenticate_super_admin!` (`:16`). Devise scope `devise_for :super_admins`
  (`config/routes.rb:597`).
- **There is no authorization layer inside Super Admin.** No Pundit include, no policies, no `skip_before_action`
  anywhere in either super_admin controller tree. Every signed-in super admin can reach everything that is
  routed. Two surfaces are hard-gated in code instead: `PlatformBannersController` raises unless
  `ChatwootApp.chatwoot_cloud?` (permanently false here), and `AccountDashboard::FORM_ATTRIBUTES` is
  `%i[name locale status]` (`app/dashboards/account_dashboard.rb:57-61`), so **no super admin can toggle an
  account feature flag through the UI**.
- Vue islands exist and the home page uses one: `render_vue_component(name, props)`
  (`application_controller.rb:33-42`, exposed via `helper_method` at `:14`), the runtime loaded on every page by
  `vite_javascript_tag 'superadmin_pages'` in `app/views/super_admin/application/_navigation.html.erb:10-11`,
  with a `ComponentMapping` registry in `app/javascript/entrypoints/superadmin_pages.js:8-11`.
- Styling is administrate's vendored SCSS **plus full Tailwind** — `tailwind.config.js:34` scans
  `./app/views/**/*.erb`, so utilities, the radix palette variables and dark mode work in a new ERB view with
  zero setup.
- Bespoke (non-Administrate) pages already exist and are the pattern to copy: `dashboard_controller.rb`,
  `instance_statuses_controller.rb`, `push_diagnostics_controller.rb`, `settings_controller.rb`,
  `app_configs_controller.rb`.
- `Sidekiq::Web` is already mounted at `/monitoring/sidekiq` behind `authenticated :super_admin`
  (`config/routes.rb`, end of the super_admin block).

### Two Super Admin patterns, one to copy and one to avoid

- **Copy** `SuperAdmin::DashboardController#index` (`app/controllers/super_admin/dashboard_controller.rb:13-23`):
  `Rails.cache.fetch('super_admin:dashboard_stats', expires_in: 30.minutes)` around exactly five flat queries,
  including a deliberate planner estimate — `SELECT reltuples::bigint FROM pg_class WHERE relname =
  'conversations'` (`:28-30`) with a negative-value fallback to `Conversation.count` (`:32`).
- **Avoid** `CountField` (`app/fields/count_field.rb:3-7`): four lines, `data.count`, declared for both `users`
  and `conversations` in `AccountDashboard::COLLECTION_ATTRIBUTES` (`app/dashboards/account_dashboard.rb:30-37`).
  That is **two COUNT queries per row, uncached, during view render** — an N+1 the accounts index already pays.
  A P9 Operations page listing accounts with per-account counts must not copy it.

### Adding a section

Six files, not four: a route (a new `config/routes/<name>.rb` + a `draw` line, following `config/routes/billing.rb`),
a controller under `custom/app/controllers/super_admin/`, views under `app/views/super_admin/<name>/`, **two**
edits to `_navigation.html.erb` (the skip-list **and** an explicit nav item — missing the skip-list edit is a
hard 500 on every super admin page, because `display_resource_name` constantizes `"<Name>Dashboard"`), a
`<symbol>` in `_icons.html.erb`, and strings under `super_admin:` in `config/locales/en.yml`.

---

## 5. Existing operational health sources

The single most consequential finding in this discovery. The claim "the application durably records that a
channel is broken, in Postgres" was **refuted**: it is true for one channel out of twelve, and categorically
false for email.

### The shared "broken" mechanism is Redis-only

`Reauthorizable` (`app/models/concerns/reauthorizable.rb`) is the only cross-channel mechanism, and every read
and write is Redis:

- `:20` `reauthorization_required?` → `Redis::Alfred.get`
- `:26` `authorization_error_count` → `Redis::Alfred.get`
- `:31` `authorization_error!` → `Redis::Alfred.incr`
- `:42` `prompt_reauthorization!` → `Redis::Alfred.set` with **no TTL**
- `:71-72` `reauthorized!` → `Redis::Alfred.delete`

Keys: `AUTHORIZATION_ERROR_COUNT:%<obj_type>s:%<obj_id>d` and
`REAUTHORIZATION_REQUIRED:%<obj_type>s:%<obj_id>d` (`lib/redis/redis_keys.rb:68-69`). There is **no
corresponding column**: the concern's own comments at `:18` and `:23` call them "model attribute".

So "show me every broken inbox across all accounts, newest first" is **not expressible** against what exists.
Any such page would need one Redis round trip per channel, unsortable, unfilterable, unjoinable, and silently
empty after a Redis flush.

### Email is the worst case and the most common channel

A plain-password IMAP inbox with a rotated password produces **exactly one log line per poll**
(`app/jobs/inboxes/fetch_imap_emails_job.rb:14-16`) — no Postgres row, no Redis counter, no Sentry event, and a
*successful* Sidekiq job. The OAuth variant needs **ten consecutive failures**
(`app/models/channel/email.rb:42`) before even the Redis flag latches.

There is a second trap: once the flag latches, `should_fetch_email?`
(`fetch_imap_emails_job.rb:26`) and `should_fetch_emails?` (`fetch_imap_email_inboxes_job.rb:20`) stop polling.
The inbox then goes **quiet rather than erroring**, and nothing durable says why. If Redis is flushed, polling
silently resumes against still-invalid credentials and the ten-strike count restarts from zero.

This is exactly the production symptom on record (email inbox 74, "Invalid credentials"): invisible to any
Postgres-backed view.

### The signal inventory

| Signal | Durability | Evidence |
| --- | --- | --- |
| `GET /health` | **NOT RECORDED** — returns a static literal, checks nothing | `app/controllers/health_controller.rb:5` |
| `GET /api` readiness (Redis PING + `SELECT 1`, 503 on failure) | **NOT RECORDED** — computed per request, no history | `app/controllers/api_controller.rb:6-14, 20-24, 30-34` |
| Sidekiq enqueued / scheduled / retry / dead / processed / failed | **REDIS-ONLY**, plus **LOGS-ONLY** every 5 min | `custom/app/jobs/lynomia/queue_health_job.rb:40-47`; `config/schedule.yml:88-90` |
| Per-queue depth and latency (16 strict-priority queues) | **REDIS-ONLY** + **LOGS-ONLY** | `queue_health_job.rb:52-61`; `config/sidekiq.yml` |
| Worker process count | **REDIS-ONLY** + **LOGS-ONLY** (error level when zero) | `queue_health_job.rb:38-47` |
| Dead-set growth | **REDIS-ONLY** (a marker key with a 1-day TTL) | `queue_health_job.rb:64-72` |
| Channel authorization failure (any channel) | **REDIS-ONLY**, no TTL | `reauthorizable.rb:31, 42`; `redis_keys.rb:68-69` |
| Email/IMAP invalid credentials | **NOT RECORDED** (plain password) / **REDIS-ONLY** after 10 strikes (OAuth) | `fetch_imap_emails_job.rb:14-16`; `channel/email.rb:42` |
| Webhook delivery failure | **LOGS-ONLY** | `custom/app/services/custom/webhooks/trigger.rb` via `Lynomia::OperatorLog` |
| WhatsApp send failure, Meta error code | **DURABLE IN POSTGRES** | `messages.status` + `content_attributes.external_error` — but `content_attributes` is double-encoded (P8, `app/models/message.rb:112`) |
| WhatsApp template rejection | **DURABLE IN POSTGRES** | `whatsapp_message_templates` status columns; `custom/app/services/whatsapp/templates/status_update.rb` |
| Campaign delivery failure | **DURABLE IN POSTGRES** | `campaign_recipients.status`, `failed_at` |
| Delayed automation skipped / stranded | **DURABLE IN POSTGRES**, 30-day retention | `automation_rule_pending_executions.status`, `skip_reason` |
| Flow terminal failure | **DURABLE IN POSTGRES** | `flow_sessions.status`, `failure_code`, `context->>'end_reason'` |
| Commerce store connection / sync | **DURABLE IN POSTGRES** | `commerce_stores`, `commerce_action_runs` error columns |
| Product exceptions | **NOT RECORDED** in the app database | Sentry/Scout are external |
| Query-level DB health | **DURABLE, AND COMPLETELY UNREAD** | `enable_extension "pg_stat_statements"` (`db/schema.rb:15`); zero Ruby consumers |

### What already exists for operator visibility

P7 built a log-line layer, and P9 should build on it rather than beside it:

- `Lynomia::OperatorLog` (`custom/app/services/lynomia/operator_log.rb`) — a bracketed `[LYNOMIA][EVENT]
  key=value` formatter whose `#value` method is where "no secrets, no message bodies, no unnecessary PII" is
  actually enforced (whitespace collapsed, 200-char truncation, non-token values quoted).
- Four call sites: `custom/app/jobs/lynomia/queue_health_job.rb`,
  `custom/app/services/custom/messages/status_update_service.rb`,
  `custom/app/services/custom/webhooks/trigger.rb`,
  `custom/app/services/whatsapp/templates/status_update.rb`.

Everything it emits goes to stdout → journald. **Nothing is queryable.** That is the gap P9 closes.

---

## 6. Existing provider and error sources

Covered in the table above. The three rules that fall out of it:

1. **Never read a provider to find out whether it is healthy.** No existing code performs a health-check call,
   and doing one on dashboard render would mean an outbound request per store per page load.
2. **Never expose a credential.** `commerce_customer_links.external_customer_id` is encrypted;
   `channels.provider_config` and the WhatsApp/OAuth token columns must never be serialized. P8 already
   established and spec-asserted this rule for its own payloads.
3. **Sanitize provider prose.** Meta error codes and provider messages are useful; raw response bodies, webhook
   payloads and URLs with query tokens are not. `Lynomia::OperatorLog#value` is the existing precedent for the
   bound.

---

## 7. Existing permissions

- `AccountUser#role` is `{ agent: 0, administrator: 1 }` (`app/models/account_user.rb:34`).
- `CustomRole` is **Lynomia-owned** (`custom/app/models/custom_role.rb`), with a frozen
  `PERMISSIONS` list at `:40-48`: `conversation_manage`, `conversation_unassigned_manage`,
  `conversation_participating_manage`, `contact_manage`, `report_manage`, `knowledge_base_manage`,
  `commerce_order_manage`; validated by `validates :permissions, inclusion: { in: PERMISSIONS }` (`:51`).
  **A P9 permission must be added here or no custom role can ever be granted ticket access.** Note the
  `custom_roles` feature flag is `premium: true` (§8).
- `pundit_user` returns a **hash**, not a user: `{ user: Current.user, account: Current.account, account_user:
  Current.account_user }` (`app/controllers/application_controller.rb:21-27`). Every policy therefore reads
  `@account_user`, which is why `ReportPolicy#view?` is `@account_user.administrator?`.
- `Api::V1::Accounts::BaseController` is **15 lines** (`app/controllers/api/v1/accounts/base_controller.rb`):
  `include SwitchLocale`, `include EnsureCurrentAccountHelper`, `before_action :current_account`,
  `before_action :validate_token_api_access, if: :authenticate_by_access_token?`,
  `around_action :switch_locale_using_account_locale`, and one private method. It does **not** authorize
  anything, set `Current.user`, rescue anything, or paginate — those come from `ApplicationController`.
- Agent inbox narrowing: `Conversations::PermissionFilterService` — administrators see all, others see
  `conversations.where(inbox: user.inboxes.where(account_id:))`. P8's contact timeline already reuses it.
- `Rack::Attack` is **on in production only** (`Rails.env.production? ? … : false`), so no spec can exercise a
  throttle. The only blanket rule is `req/ip` at 3000/min; there is no wildcard over
  `/api/v1/accounts/:account_id/*`. The template for a new per-endpoint throttle is the contacts/search one.

---

## 8. Existing feature flags

`config/features.yml`: **72 entries, 26 default-true, 19 `premium: true`, 10 on `feature_flags_ext_1`.**

The file header is binding: *"DO NOT change the order of features EVER"*, *"The `feature_flags` column is FULL
(63/63 slots used). Do NOT add to it"*, *"New flags MUST set `column: feature_flags_ext_1` and be appended at
the end"*, *"never reorder or remove existing entries, and never change an existing feature's `column` after
release"*. The last ext_1 entry is `lynomia_flow_builder` (`:287-290`).

**`premium: true` is enforced in this fork** — the readers twice claimed it was inert metadata and the critic
refuted them. `BillingPlan.assignable_features` (`custom/app/models/billing_plan.rb:36-41`) rejects any feature
carrying `premium`, and `Billing::FeatureSync` (`custom/app/services/billing/feature_sync.rb:21-25`) only ever
propagates assignable features onto subscribed accounts. Combined with `AccountDashboard::FORM_ATTRIBUTES`
exposing no feature field, a `premium: true` flag in this fork has **no operator-reachable enable path at all**.

Four features P9 might otherwise have leaned on are premium and therefore un-grantable: `sla`, `audit_logs`,
`audit_log_ip_address`, `custom_roles`.

`Featurable` is included only by `Account` (`app/models/account.rb:30`), so flags are per-account — but a
per-**plan** layer sits above it in `BillingPlan` + `Billing::FeatureSync`, and that is the only operator-driven
enable path that exists.

---

## 9. Missing durable operational information

The things P9 cannot report truthfully from what exists today:

1. **Channel health, for eleven of twelve channel types.** Redis-only, no TTL, no history, not joinable.
2. **Email/IMAP authentication failure.** Not recorded anywhere for a plain-password inbox.
3. **Webhook delivery outcomes.** No table, no row, no counter — log lines only.
4. **Queue history.** Sidekiq's numbers are live-only; a five-minutely log line is the sole trail.
5. **Any "it was broken, then it recovered" transition.** Nothing records a recovery.
6. **Product exceptions.** External only.
7. **Conversation status history**, assignee/team/label/priority change history — prose only (inherited from P8).
8. **All historical SLA.** Never computed, never stored.

For each of these, the Operations Center must either show a live probe clearly labelled as such, or show
**unknown**. "Green because nothing was reported" is the one thing it must never do.

Where P9 adds durable recording, it is additive instrumentation at the point where the failure is already
detected, and it starts from the deploy — not a reconstruction.

---

## 10. Recommended architecture

### A new `support_tickets` entity, not a Conversation extension

**Option (B)** from the brief. The decisive evidence is §1: `conversations.inbox_id` is NOT NULL at the database
and validated in the model, and `contact_id` is validated present and dereferenced in `before_create`. An
internal operational case has neither. No amount of metadata on Conversation fixes that, and inventing a
synthetic "internal" inbox to satisfy a NOT NULL would be a worse lie than a new table.

The division of canonical responsibility:

| Stays canonical in Conversation | Belongs to the ticket |
| --- | --- |
| messages, private notes, attachments, mentions, CSAT | subject, description, category |
| channel identity (inbox), customer identity (contact, contact_inbox) | due dates and SLA state |
| the conversation's own status, priority, assignee, team, labels | the case's own lifecycle, including resolve-vs-close |
| realtime, webhooks, push payloads | a durable event trail and internal notes |
| conversation filters, bulk actions, automation, macros | the operational source that caused the case |

A conversation may have **many** tickets (one thread can raise two issues); a ticket links to **at most one**
conversation. Multi-conversation linkage is a deliberate non-goal: no evidence of need, and the inverse
`has_many` already covers the realistic case.

### Reference numbering without a trigger

The `display_id` mechanism is a pair of HairTrigger Postgres triggers plus one dynamically created sequence per
account (`app/models/account.rb:205-207`, `app/models/conversation.rb:429-431`, `db/schema.rb:1870-1897`).
Copying it would require: a second explicitly named trigger on `accounts` (an unnamed one collides), a
**backfill migration creating the sequence for every existing account** (the sequences are not in `db/schema.rb`,
so a fresh schema load or an existing production account gets none and the first insert raises), an addition to
`Account#remove_account_sequences` (`:233-236`) or every account deletion leaks a sequence, and a post-create
re-fetch because the value is written server-side.

P9 takes the smaller, equally race-safe route: a per-account **advisory lock** plus `MAX(reference_number) + 1`
inside the creating transaction. No trigger, no OSS model edit, no sequence, no backfill. The integer is stored;
the `TCK-000123` form is rendered in the presentation layer, and lookup accepts either form.

### One table for history and notes

Conversation has only one structured activity type, so a case's history cannot be derived. P9 adds
`support_ticket_events`, serving **both** the durable activity trail and internal notes: a type-validated
`event_type`, a `body` for notes, a `data` jsonb for structured before/after payloads, and a nullable `user_id`
for system events. One table rather than two, because an internal note *is* an event in the case's history.

@mentions on ticket notes are deferred: the `mentions` table is `(user_id, conversation_id)` and cannot address
a ticket.

### SLA: new engine, maximum reuse

Reuse the **existing `sla_policies` table** — right columns, zero migration, and the table has never held a row
in this fork. Reuse `ReportingEventHelper#business_hours` and the `working_hours` gem for business-hours
arithmetic, `Account#reporting_timezone` for display and bucketing, and the surviving `sla.json` i18n. Put the
per-case clock on the ticket itself (two due timestamps, a first-response timestamp, two breach timestamps, and
an accumulated pause) rather than in `applied_slas`, whose `conversation_id` is NOT NULL and so cannot hold a
ticket's state.

Conversation SLA stays absent. Reviving it is a separate product decision with its own surviving API contract,
and bundling it into P9 would make the phase three products instead of two.

Business hours require an inbox, because the gem configuration is inbox-scoped. A ticket with no inbox uses
calendar time even under a business-hours policy, and the response says so.

### Operations Center: computed + recorded + probed, and `unknown` where nothing exists

ERB inside the Administrate shell, with Tailwind, following `push_diagnostics`. Three classes of signal, each
labelled with its own source and freshness:

- **Computed** from durable Postgres the product already writes: WhatsApp failures and Meta codes, template
  rejections, campaign failure rates, stranded automations, failed flow sessions, commerce store state.
- **Recorded** in P9's one new operational table, written at the points where a failure is already detected and
  currently only logged — IMAP authentication, channel reauthorization, webhook delivery, queue health. Rows
  collapse by `(account, source, subject, signal)` while open, so a failing inbox is one row with an occurrence
  count rather than a flood, and the same key is the dedup key for the support-case bridge.
- **Probed** live, and labelled as a reading taken now: Postgres, Redis, Sidekiq process set and queue depths,
  version, SHA, pending migrations — reusing `instance_statuses_controller.rb` rather than duplicating it.

Everything else reads **unknown**. Health is never inferred from silence.

### Incidents

No `Incident` table. An internal operational case is a `support_tickets` row with `category: operational` and a
link to the operational signal that caused it. Severity is the existing four-value priority vocabulary; SEV1–4
is deliberately not added, because it would be a second field for one concept.

### Deliberate non-goals, each with its reason

| Non-goal | Why |
| --- | --- |
| A new automation event (`ticket_created` etc.) | 14 required files across backend, listener, event types, frontend constants and i18n, and it would be a second vocabulary to keep in sync. Documented change-set recorded in `01-architecture.md` so the deferral is a decision, not an omission |
| In-app notifications for ticket assignment | `Notification` is structurally Conversation-only: `primary_actor.push_event_data.slice('conversation_id','id')` (`notification.rb:84`), `primary_actor.inbox.name` (`:106`), `primary_actor.display_id` (`:111`), `def conversation; primary_actor; end` (`:130`), and the API view (`notifications/index.json.jbuilder:17`). A ticket may have no conversation, so reusing it would either lie about the actor or silently skip conversation-less cases |
| Reviving conversation SLA | A separate product with its own surviving API contract |
| Sidekiq retry / delete actions | Read-only visibility only; `Sidekiq::Web` already exists for actions, behind the same guard |
| Ticket attachments | Messages already carry attachments; a case with a conversation has them, and a case without one has no proven need |
| Multi-conversation linkage | No evidence of need; the inverse `has_many` covers the realistic case |

### Conventions P9 will follow, with the file to copy

| Concern | Follow |
| --- | --- |
| Migration | `custom/db/migrate/`, `ActiveRecord::Migration[7.2]`, `t.references … foreign_key: { on_delete: … }`, integer enums `null: false, default: 0`, jsonb `null: false, default: {}`, named composite and partial indexes. Template: `custom/db/migrate/20261006100000_create_commerce_carts.rb`. For any long DDL: `custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb` |
| Migration safety | `docs/global-documentation/01-global-ownership-design.md:187-190`: `add_column` with a default does not rewrite the table on PG11+; what scans is *adding* a NOT NULL constraint to an existing column |
| Type allow-lists | Plain string column + `validates … inclusion:`. House precedent: `custom/app/models/commerce/action_run.rb:66`. There is **no** polymorphic type allow-list anywhere in the repo to copy, and `conversations.ai_assignee_type` is unconstrained at both layers — do not copy it |
| Pagination | Kaminari 1.2.2 with **no initializer**, so `.per` must be explicit. Template: `custom/app/controllers/api/v1/accounts/audit_logs_controller.rb` (`RESULTS_PER_PAGE = 25`, flat jbuilder with `current_page`/`total_entries`/`per_page`) |
| Tenant controller + policy | `custom/app/controllers/api/v1/accounts/analytics_controller.rb`, `custom/app/controllers/api/v1/accounts/contacts/activity_controller.rb`; 422s via `lib/custom_exceptions/` |
| Audit | `audited associated_with: :account` on the model, with `except:` for anything credential-bearing. Precedent: `custom/app/models/whatsapp/message_template.rb:46`; sanitization precedent `custom/app/models/custom/audit/webhook.rb:7` |
| Operator log | `Lynomia::OperatorLog` for the log line, alongside the durable row |
| List page | `app/javascript/dashboard/routes/dashboard/settings/auditlogs/Index.vue` and its four-file set. `BaseTable` is **presentation-only** — no fetcher, no filters, no pagination; `sortBy`/`sortOrder` are inputs it renders an arrow from. Every list page in this repo hand-rolls its own query orchestration |
| Super Admin page | `app/views/super_admin/push_diagnostics/show.html.erb` for the shell, `dashboard_controller.rb:13-32` for cached flat aggregates |
| Feature flag | A new non-premium entry appended to `config/features.yml` with `column: feature_flags_ext_1` |
| Permission | A new string appended to `CustomRole::PERMISSIONS` |

### Things in the repository nobody is using, noted for honesty

- `pg_stat_statements` is enabled (`db/schema.rb:15`) with zero Ruby consumers — a durable, queryable per-statement
  store an Operations Center could read with a plain SELECT. P9 does not read it either; recorded as an option.
- `vector` is enabled with the `neighbor` and `pgvector` gems loaded (`Gemfile:193-195`) and zero consumers,
  serving the code-less `article_embeddings` table.
- `accounts.internal_attributes` (`db/schema.rb:74`) is a jsonb `NOT NULL default {}` column with **no tenant
  write path** — absent from `account_params` and `permitted_settings_attributes` — already used for suspension
  history and Shopify billing identity. It is the right home for operator-owned per-account state that needs no
  table.
