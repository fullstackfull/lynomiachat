# P8 discovery — Analytics and Contact Activity Timeline

Branch `claude/p8-analytics-contact-timeline`, cut from `origin/lynomia-custom` at the production SHA
`b03ea43df6abf18cb9c4e5d6a9271ba040b689f4`. Read-only discovery; no product code changed.

Verified against this checkout at that SHA:

| Fact | Value |
| --- | --- |
| `enterprise/` directory | absent |
| `ChatwootApp.extensions` | `["custom"]` |
| `ChatwootApp.enterprise?` | `false` (literal, `lib/chatwoot_app.rb:20`) |
| migration files | 196 (180 in `db/migrate`, 16 in `custom/db/migrate`) |
| latest migration | `20261006100000_create_commerce_carts.rb` |

Everything below carries a `path:line` or a `db/schema.rb` citation. Where a claim could not be established from
the repository it says **NOT ESTABLISHED** rather than guessing, because a wrong "this is durable" would make P8
promise a metric the data cannot support.

---

## 1. The existing reporting architecture

### 1.1 It is substantial, and P8 extends it rather than replacing it

| Layer | Files |
| --- | --- |
| Raw event model | `app/models/reporting_event.rb`, `app/models/concerns/reportable.rb` |
| Aggregate model | `app/models/reporting_events_rollup.rb` |
| Write path | `app/listeners/reporting_event_listener.rb`, `app/services/reporting_events/rollup_service.rb`, `app/services/reporting_events/backfill_service.rb` |
| Metric vocabulary | `app/services/reporting_events/event_metric_registry.rb`, `app/services/reporting_events/metric_registry.rb`, `app/services/reports/report_metric_registry.rb` |
| Read path | `app/services/reports/{data_source,raw_data_source}.rb`, `app/builders/v2/report_builder.rb` and 17 builders under `app/builders/v2/reports/` |
| Controllers | `app/controllers/api/v2/accounts/{reports,summary_reports,live_reports}_controller.rb` |
| Policy | `app/policies/report_policy.rb` |
| Helpers | `app/helpers/{report_helper,reporting_event_helper,date_range_helper,timezone_helper}.rb`, `app/helpers/api/v2/accounts/reports_helper.rb` |
| Operator tooling | `lib/tasks/reporting_events_rollup.rake`, `lib/tasks/reporting_events_rollup_timezone_setup.rake` |

### 1.2 The complete metric vocabulary that exists today

Six event names are written to `reporting_events` (`app/listeners/reporting_event_listener.rb`):

| Event name | Written at | In the rollup registry? | Read by a report metric? |
| --- | --- | --- | --- |
| `conversation_resolved` | `:9` | yes | yes |
| `first_response` | `:32` | yes | yes |
| `reply_time` | `:59` | yes | yes |
| `conversation_bot_handoff` | `:86` | yes | yes |
| `conversation_bot_resolved` | `:143` (via `create_bot_resolved_event`) | yes | yes |
| **`conversation_opened`** | `:129` | **no** | **no** |

`ReportingEvents::EventMetricRegistry::EVENTS` (`event_metric_registry.rb:7-24`) covers only the first five.
The nine readable report metrics are `ReportingEvents::MetricRegistry::REPORT_METRICS`
(`metric_registry.rb:27-38`): `conversations_count`, `incoming_messages_count`, `outgoing_messages_count`,
`avg_first_response_time`, `avg_resolution_time`, `reply_time`, `resolutions_count`, `bot_resolutions_count`,
`bot_handoffs_count`.

**`conversation_opened` is written but never read, and it is the only durable record of a reopen.**
`reporting_event_listener.rb:101-124` looks for the most recent prior `conversation_resolved`; if one exists the
event is a *reopen* and `value` is the seconds since that resolution, with `event_start_time` set to the
resolution time. For a first-time open, `value` is 0 and `event_start_time` is `conversation.created_at`.
So "reopened conversations" (an A1 metric) is honestly derivable from existing historical data, by the robust
discriminator `event_start_time != conversation.created_at` rather than `value > 0`, which would miss a reopen
inside the same second. **This is existing data nothing currently surfaces.**

### 1.3 `reporting_events` shape and its one decisive limitation

`db/schema.rb`: `name`, `value`, `account_id`, `inbox_id`, `user_id`, `conversation_id`, `created_at`,
`updated_at`, `value_in_business_hours`, `event_start_time`, `event_end_time`.

Indexes: `(account_id, name, created_at)`, `(account_id, name, inbox_id, created_at)`, `account_id`,
`conversation_id`, `created_at`, `inbox_id`, `name`, `user_id`.

**There is no `contact_id` column.** Every reporting event is reachable from a contact only by joining through
`conversations.contact_id`. That is the single most important structural fact for Part B.

### 1.4 The rollup layer: written broadly, read almost nowhere

`reporting_events_rollups`: `account_id`, `date`, `dimension_type`, `dimension_id`, `metric`, `count`,
`sum_value`, `sum_value_business_hours`. Unique on
`(account_id, date, dimension_type, dimension_id, metric)`, plus `(account_id, dimension_type, date)` and
`(account_id, metric, date)`.

Three findings, all from the code:

1. **The write path is not feature-gated, but it is timezone-gated.** `rollup_service.rb:22-27` states this in
   its own comment: "Rollup data is collected for all accounts with a valid reporting timezone (soft toggle).
   The feature flag only controls the read path." `rollup_enabled?` returns false unless
   `account.reporting_timezone` is present *and* a valid `ActiveSupport::TimeZone`.
   **Consequence: for any account with no `reporting_timezone`, the rollup table is empty.**
2. **The read path is off in production.** `config/features.yml:112-114` has `report_rollup` with
   `enabled: false`, and migration `db/migrate/20260226153427_disable_report_rollup_for_all_accounts.rb`
   explicitly disabled it for every existing account. `lib/tasks/reporting_events_rollup.rake:219` confirms the
   intent — "Enable report_rollup read path now? Only do this after parity verification."
3. **Only three dimensions exist**: `account`, `agent`, `inbox` (`rollup_service.rb:33-39`). There is no `team`,
   `label`, `campaign`, `template`, `automation`, `flow`, `commerce` or `contact` dimension.

The upsert is additive (`count = count + EXCLUDED.count`, `rollup_service.rb:73-79`), so a re-run over the same
day double-counts unless the caller clears first — relevant to any P8 backfill.

> **Operator question, not answerable from the repository.** Whether `reporting_events_rollups` holds any
> production data depends on whether the production account has `reporting_timezone` set. **NOT ESTABLISHED**
> here. P8 must therefore not assume rollups are populated; A1 trend queries are designed against raw
> `reporting_events` with rollups as an optimisation, not a prerequisite.
>
> **Status at P8.1.** Still NOT ESTABLISHED. This session has no path to production — verified in the container:
> no `ssh` binary, no `~/.ssh` keys, no `.env`, no `POSTGRES_*` environment and no production host in any git
> remote. The read-only check is written up as seven operator queries in
> `docs/p8/00b-rollup-production-check.md`, every one of them validated against this schema, with the coverage
> query (R5) additionally proved on a fixture where it correctly reported valid coverage for one account and drift
> for another. Record the output here when you have run it.
>
> **P8.1 does not depend on the answer.** `Analytics::RollupCoverage` refuses the rollup unless all four of its
> conditions hold, and the first — the `report_rollup` feature — is off by default, so the foundation reads raw
> regardless (`docs/p8/01-architecture.md` §2).

### 1.5 Date range and timezone handling — A9 is already solved, with one real inconsistency

The established strategy, which P8 adopts unchanged:

- The client sends `since` and `until` as **Unix epoch seconds**; `DateRangeHelper#parse_date_time`
  (`app/helpers/date_range_helper.rb:13-18`) parses with `DateTime.strptime(datetime, '%s')`, and `#range`
  builds a **half-open** range with `...` (exclusive end) at `:10`.
- Grouping happens **in SQL, in the requested timezone**, via the `groupdate` gem (6.2.1, `Gemfile:65`):
  `report_builder.rb:103-111` calls `group_by_period(params[:group_by] || DEFAULT_GROUP_BY, :created_at,
  default_value: 0, range: range, permit: %w[day week month year hour], time_zone: @timezone)`.
  So buckets are not naive UTC dates.
- Timezone resolution handles DST correctly: `TimezoneHelper#timezone_name_from_offset`
  (`app/helpers/timezone_helper.rb:15-27`) compares `zone.now.utc_offset` rather than using
  `ActiveSupport::TimeZone[offset]`, and the comment cites the three Rails issues that make the naive form wrong.

**The inconsistency P8 must decide about.** Two timezone regimes coexist and can disagree:

| Path | Timezone source | Evidence |
| --- | --- | --- |
| Live/on-the-fly reports | the **viewer's** `params[:timezone_offset]` | `report_builder.rb:15`, `base_timeseries_builder.rb:59`, `drilldown_builder.rb:196`, `data_source.rb:58` |
| Rollup write + backfill | the **account's** `reporting_timezone` | `rollup_service.rb:26,30`, `backfill_service.rb:44`, both rake tasks |

`Account#reporting_timezone` exists as a validated `store_accessor` on `settings`
(`app/models/account.rb:52,59,217-220`) and **nothing outside the rollup pipeline reads it** — confirmed by a
full-tree grep. `TimezoneHelper#timezone_name_from_params(timezone, offset)` exists and prefers an explicit IANA
name over an offset, but has **no callers**.

### 1.6 CSAT is fully present — use it, do not rebuild it

`csat_survey_responses` (`db/schema.rb`): `account_id`, `conversation_id`, `message_id`, `rating`,
`feedback_message`, **`contact_id`**, `assigned_agent_id`, `csat_review_notes`, `review_notes_updated_at`,
`review_notes_updated_by_id`. Indexed on `account_id`, `contact_id`, `conversation_id`, `assigned_agent_id`,
and uniquely on `message_id`.

A complete CSAT reporting UI already exists: `app/javascript/dashboard/routes/dashboard/settings/reports/
CsatResponses.vue`, `components/CsatMetrics.vue`, `components/CsatTable.vue`, plus
`CsatRatingDistribution`/`CsatMetricCard` stories. Backend: `app/services/csat_survey_service.rb`,
`app/policies/csat_survey_response_policy.rb`, jbuilder views under
`app/views/api/v1/accounts/csat_survey_responses/`.

**Because `csat_survey_responses.contact_id` exists and is indexed, a CSAT response is a first-class, durable,
contact-linked timeline event** — an addition the P8 brief did not list but which costs nothing.

### 1.7 Audit infrastructure: writes unconditionally, reads are flagged off, and Contact is not audited

- `audit_logs` is `enabled: false, premium: true` (`config/features.yml:112-115`), and P7 established it is
  disabled for every production account. As with `report_rollup`, the flag gates the **read** surface; the
  `audited` declarations in the models are not gated, so rows accumulate regardless.
- `audits` columns: `auditable_id/type`, `associated_id/type`, `user_id/type`, `username`, `action`,
  `audited_changes` (jsonb), `version`, `comment`, `remote_address`, `request_uuid`, `created_at`, `city`,
  `country`, `country_code`. **No `account_id` and no `contact_id`.** Account scoping is via
  `associated_type='Account'` + `associated_id`, supported by `index_audits_on_associated_and_created_at`.
- Audited models (`custom/app/models/custom/audit/*.rb` plus two P7 writers): `Macro`, `CustomFilter`
  (contact filters only), `TeamMember`, `Account` (update only), `Conversation` (**destroy only**), `AgentBot`,
  `AutomationRule`, `AccountUser`, `Team`, `Inbox`, `InboxMember`, `Webhook`,
  `Whatsapp::MessageTemplate`, channel credential updates (`custom/app/models/custom/channelable.rb`), and
  message/conversation deletion.

Two consequences that bound Part B:

1. **`Contact` is not audited.** There is no durable record of contact profile or custom-attribute changes.
   B1's "important profile changes" and "custom attribute changes" are **not currently durable**.
2. **`AutomationRule` is audited, but that records rule *configuration* changes, not *executions*.** These must
   not be conflated in A5.

---

## 2. Frontend foundation — reuse, do not add libraries

Already present in `package.json`, so P8 introduces no new frontend dependency:

| Need | Existing library |
| --- | --- |
| charts | `@chatwoot/viz` ^0.1.5 |
| dates / timezone | `date-fns` 2.21.1, `date-fns-tz` ^1.3.3 |
| date range picker | `vue-datepicker-next` ^1.0.3 |
| state | `vuex` ~4.1.0 and `pinia` ^3.0.4 (migration in progress) |
| i18n | `vue-i18n` 9.14.5 |

Reports frontend lives at `app/javascript/dashboard/routes/dashboard/settings/reports/` with `components/`,
`components/ChartElements/`, `components/Csat/`, `components/Filters/` and `Filters/v3/`, `components/heatmaps/`,
`components/overview/`, `composables/`, `helpers/`, `specs/`; stores under
`app/javascript/dashboard/store/modules/` (`reports`, `slaReports`).

---

## 3. The decisive Part B finding: conversation events are already durable, as activity messages

`messages.message_type` is `{ incoming: 0, outgoing: 1, activity: 2, template: 3 }` (`app/models/message.rb:88`).
`ActivityMessageHandler` (`app/models/concerns/activity_message_handler.rb`) writes an **activity message** for
conversation lifecycle changes, via `Conversations::ActivityMessageJob`. It composes four concerns (`:4-7`):
`AssigneeActivityMessageHandler`, `PriorityActivityMessageHandler`, `LabelActivityMessageHandler`,
`TeamActivityMessageHandler`.

So conversation status, assignment, team, label and priority changes **are** recorded durably, dated, and
account/inbox/conversation-scoped, in a table that is already indexed for this read:
`index_messages_on_conversation_account_type_created` on
`(conversation_id, account_id, message_type, created_at)`. They reach the Contact through
`conversations.contact_id`.

**But only one of them is machine-readable, and this distinction decides what P8 may honestly promise.**

| Activity | Written by | Payload |
| --- | --- | --- |
| conversation status changed | `activity_message_handler.rb:41-61` | **structured**: `content_attributes.activity = { type: 'conversation_status_changed', status: <status> }` |
| assignee changed | `assignee_activity_message_handler.rb:6-20` | localized prose only, `conversations.activity.assignee.{assigned,removed,self_assigned}` |
| team changed | `team_activity_message_handler.rb:6-16` | localized prose only, `conversations.activity.team.*` |
| label added / removed | `label_activity_message_handler.rb:6-19` | localized prose only, `conversations.activity.labels.{added,removed}`, label names flattened with `labels.join(', ')` |
| priority changed | `priority_activity_message_handler.rb:6-14` | localized prose only |

`activity_message_params(content, content_attributes: nil)` (`activity_message_handler.rb:94-98`) attaches
`content_attributes` **only when a caller passes it**, and a repository-wide grep finds
`conversation_status_changed` to be the only caller that does.

Consequences P8 must respect:

1. **Status changes** (open / pending / snoozed / resolved, and the reopen that follows a resolve) are fully
   usable — classifiable and parameterised, for history as well as for new activity.
2. **Assignee, team, label and priority changes** are present and correctly dated but **not reliably
   classifiable**. The text depends on the account locale *at write time*, and `labels.join(', ')` is lossy for a
   label name containing a comma. They can honestly be surfaced in the timeline as the recorded activity text —
   which is exactly what the conversation view already shows — but P8 **must not** build an analytics breakdown
   such as "label X added N times" or a structured actor/target from them.
3. `Current.executed_by` already distinguishes automation-driven from human-driven status changes
   (`activity_message_handler.rb:42-46`), and `activity_message_owner`
   (`assignee_activity_message_handler.rb:22-34`) names an `AssignmentPolicy`, an `Inbox` auto-assignment, or
   `automation.system_name` as the actor. Useful, but again only as prose.

This is why the timeline is designed as a **read projection**, not a new event table: the events already exist.

---

## 4. Event source register

`durable` = written today for new activity. `historical` = present for activity that already happened.
`analytics` / `timeline` = honestly usable for that purpose.

### 4.1 Conversation and message events

| Event | Canonical source | occurred_at | Contact link | durable | historical | analytics | timeline |
| --- | --- | --- | --- | --- | --- | --- | --- |
| message sent / received | `messages` (`message_type` 0/1) | `created_at` | `conversations.contact_id` | yes | yes | yes | yes |
| private note | `messages` where `private = true` | `created_at` | via conversation | yes | yes | yes | yes, permission-gated |
| WhatsApp template message | `messages` where `message_type = 3` | `created_at` | via conversation | yes | yes | yes | yes |
| conversation created | `conversations.created_at` | `created_at` | `contact_id` | yes | yes | yes | yes |
| conversation status changed | activity message, `content_attributes.activity.type = 'conversation_status_changed'` | `created_at` | via conversation | yes | yes | yes | yes |
| conversation reopened | `reporting_events` `name='conversation_opened'` with `event_start_time != conversation.created_at` | `created_at` | via conversation | yes | yes | yes | yes |
| first response | `reporting_events` `name='first_response'` (`value`, `value_in_business_hours`) | `created_at` | via conversation | yes | yes | yes | yes |
| resolution time | `reporting_events` `name='conversation_resolved'` | `created_at` | via conversation | yes | yes | yes | yes |
| reply time | `reporting_events` `name='reply_time'` | `created_at` | via conversation | yes | yes | yes | no (too granular) |
| bot handoff / bot resolved | `reporting_events` `name='conversation_bot_handoff' / 'conversation_bot_resolved'` | `created_at` | via conversation | yes | yes | yes | yes |
| assignee / team / label / priority changed | activity message, **prose only** | `created_at` | via conversation | yes | yes | **no** | yes, as recorded text |
| CSAT response | `csat_survey_responses` (`rating`, `feedback_message`) | `created_at` | **`contact_id`, indexed** | yes | yes | yes, UI already exists | yes |
| conversation deleted | `audits` (`Conversation`, destroy only) | `created_at` | none | yes | yes | no | no |

`conversations.status_changed_at` holds only the **most recent** transition and `conversations.assignee_id` only
the **current** assignee, so neither is a history source. The activity messages are.

### 4.2 WhatsApp and campaign delivery — authoritative, never inferred

| Event | Canonical source | Authority |
| --- | --- | --- |
| campaign recipient queued / skipped / sent | `campaign_recipients.status`, `sent_at` | ours. `mark_sent!` sets `sent_at: Time.current` (`custom/app/models/campaign_recipient.rb:24-33`) |
| campaign recipient delivered / read | `campaign_recipients.delivered_at` / `read_at` | **Meta's**. `update_from_whatsapp_status!` (`:49-67`) is the only writer and stamps Meta's own `status[:timestamp]` via `event_time` (`:87-91`) |
| campaign recipient failed, with reason | `status`, `failed_at`, `error_code`, `error_title`, `error_message` | **Meta's**, extracted by `whatsapp_error` (`:77-85`) with precedence `error_user_msg` → `error_data.details` → `message` |
| outbound message delivered / read / failed | `messages.status` (`sent:0, delivered:1, read:2, failed:3`, `message.rb:104`) | **Meta's**, through `Whatsapp::IncomingMessageBaseService#process_statuses` (`:62-78`) → `Messages::StatusUpdateService` |

Two correctness rules follow, and both are easy to get wrong:

- **Both ladders are monotonic and store only the furthest state reached.** `CampaignRecipient#status_downgrade?`
  (`:71-75`) and `Messages::StatusUpdateService#valid_status_transition?`
  (`app/services/messages/status_update_service.rb:36-45`) refuse to move backwards, under a row lock, because
  Meta redelivers statuses out of order. A recipient that was delivered and then read therefore has
  `status = read` with **both** `delivered_at` and `read_at` set. So a delivered count must be computed as
  `delivered_at IS NOT NULL` (or `status >= delivered`), **never** `status = 'delivered'`, which would exclude
  read recipients and understate the delivery rate. The same applies to `messages.status`.
  `update_from_whatsapp_status!` even back-fills a late `delivered_at` without downgrading a `read` row (`:54-57`).
- **Coexistence echo messages are created with `status: :delivered` directly**
  (`app/services/whatsapp/incoming_message_base_service.rb:181-182`), not by a status webhook. Any "delivered"
  figure that includes echoes is therefore partly non-webhook, and A2 must either exclude echoes or say so.

`Whatsapp::DeliveryFailure` already classifies a failure (`code`, `classification`, `retry_policy`,
`recipient_scoped?`) and is used by `custom/app/services/custom/messages/status_update_service.rb:28-51` — so a
failure-reason breakdown reuses an existing classifier rather than inventing buckets.

### 4.3 Automation

| Event | Canonical source | durable | historical | analytics |
| --- | --- | --- | --- | --- |
| rule configuration changed | `audits` (`AutomationRule` is audited, `custom/app/models/custom/audit/automation_rule.rb:7`) | yes | yes | yes — but this is **configuration**, not execution |
| delayed execution pending / executed / skipped | `automation_rule_pending_executions` (`status`, `skip_reason`, `due_at`, `episode_key`, `message_id`) | yes, **for delayed rules only** | partial | partial |
| immediate execution | nothing | **no** | **no** | **no** |
| action succeeded / failed | nothing durable; a status change leaves an activity message naming `automation.system_name` | **no** | **no** | **no** |

`automation_rule_pending_executions` is indexed on `(status, due_at)` and `(status, updated_at)` and unique on
`(automation_rule_id, conversation_id, episode_key)`. Rows are **not** deleted on processing — they are advanced
to a terminal status, so the table *is* an execution history for delayed rules:

- enum `{ pending: 0, processing: 1, executed: 2, skipped: 3, executing: 4 }`
  (`app/models/automation_rule_pending_execution.rb:42`)
- the success path is `pending → processing → executing → executed`
  (`app/jobs/automation_rules/process_pending_execution_job.rb:54-62`)
- a skip records a **structured reason** from a fixed vocabulary — `expired`, `rule_inactive`,
  `conversation_gone`, `episode_moved`, `conditions_changed` (`process_pending_execution_job.rb:23-42`)
- a row whose worker died mid-action stays `executing` and is deliberately never replayed, because the actions
  are customer-facing (`automation_rule_pending_execution.rb:39-41`) — so stuck executions are detectable

Three limits bound what A5 may claim, all from the code:

1. **30-day retention.** `RETENTION_WINDOW = 30.days` and `purge_terminal!` deletes `executed` and `skipped` rows
   older than that in batches (`automation_rule_pending_execution.rb:32,161-164`), driven by
   `AutomationRules::TriggerPendingExecutionsJob:8`. **An execution trend can only ever be a rolling 30-day
   window.**
2. **Off by default.** `delayed_automations` is `enabled: false` on `feature_flags_ext_1`
   (`config/features.yml:273-276`), and the sweep only touches `for_enabled_accounts`.
3. **Deleting a rule erases its history.** `automation_rule.rb:31` declares
   `has_many :pending_executions, dependent: :delete_all`.

**So A5 splits in two.** For *delayed* rules on accounts with the flag on, executed/skipped counts, skip-reason
distribution and stuck-execution counts are honest within 30 days. For *immediate* rules — any rule without
`execution_delay` — nothing is recorded anywhere, so there is no history and none can be reconstructed. The
minimum honest instrumentation for those is a listener-level execution record for **future** executions only; it
must not change automation behaviour, and the UI must state the date the data starts.

### 4.4 Flow Builder

`flow_sessions`: `account_id`, `agent_bot_id`, `flow_version_id`, `conversation_id`, `status`,
`current_node_id`, `context` (jsonb), `last_message_id`, `wake_at`, `step_token`, `steps_count`, `failure_code`,
`finished_at`, `created_at`. Status enum `{ active: 0, waiting: 1, handed_off: 2, completed: 3, failed: 4,
cancelled: 5 }` (`custom/app/models/flow_session.rb:19`). Indexes `(account_id, agent_bot_id, status)`,
`(conversation_id, created_at)`, a partial unique "one live session per conversation" on `status IN (0,1)`.

| A6 metric | Honest? | Why |
| --- | --- | --- |
| sessions started | yes | count by `created_at` |
| sessions completed / failed / cancelled / handed off | yes | terminal `status` + `finished_at` |
| active / waiting sessions | yes | `status IN (0,1)` |
| average duration | yes | `finished_at - created_at`, both columns exist |
| failure reasons | yes | `failure_code`, plus `current_node_id` as the node it stopped on |
| sessions **abandoned** | **no, not as its own state** | there is no `abandoned` status. A timeout definition would be P8 inventing a metric; `waiting` with a past `wake_at` is the nearest honest proxy and must be labelled as such |
| node execution distribution | **impossible historically** | only `current_node_id` (overwritten) and `steps_count` (a counter) are stored. There is no per-node transition history |

### 4.5 Commerce

No order table exists. Orders stay with the provider; what is persisted is:

| Table | What it is | Timeline / analytics value |
| --- | --- | --- |
| `commerce_carts` | durable cart lifecycle: `state`, `provider_phase`, `currency`, `visible_total`, `item_count`, `first_seen_at`, `last_provider_event_at`, `abandoned_at`, `completed_at`, `targeted_at`, `provider_order_id`, `contact_id`. Indexed `(account_id, state, abandoned_at)`, `(commerce_store_id, state)`, `contact_id` | **both.** Abandoned-cart activity, completed-after-abandonment (`abandoned_at` and `completed_at` both set), outreach (`targeted_at`), provider distribution |
| `commerce_action_runs` | one row per provider action: `action_type`, `status`, `started_at`, `completed_at`, `error_code`, `requested_by_id`, `contact_id`, `conversation_id`. Indexed on `contact_id`, `conversation_id`, `(status, updated_at)` | **both.** A durable, contact-linked action history |
| `commerce_customer_links` | contact ↔ provider customer, `match_source`, `confirmed_by_id`. Unique `(commerce_store_id, contact_id)` | timeline: "order context discovered" |
| `commerce_contact_metrics` | a **cache**, unique per `commerce_customer_link_id`, refreshed in place with `fetched_at`: `orders_count`, `active_orders_count`, `last_purchase_at`, `spend` jsonb, `order_statuses` / `payment_statuses` / `shipment_statuses` arrays, `order_states` jsonb | current snapshot only. **No historical order trend is possible**, because the row is overwritten |

**Currency is explicit and conversion is already refused.** `Commerce::Customer360.spend` is documented as
"totals of orders the store reports as paid, per currency, never converted" (`customer360.rb:13`) and
`Commerce::ContactMetric` stores it as a `{currency => amount}` hash (`contact_metric.rb:46`). So a
**per-currency** spend figure is honest; a single combined revenue or GMV number is **not** and must not be built.
`commerce_carts.visible_total` is likewise paired with a per-row `currency`.

### 4.6 Contact changes

| Event | Source | Verdict |
| --- | --- | --- |
| contact created | `contacts.created_at` | durable, historical, usable |
| contact profile changed | **nothing** | `Contact` is **not** in the audited model list. **Not currently durable** |
| custom attribute changed | **nothing** | same |

B1's "important profile changes" and "custom attribute changes" therefore have no honest historical source. Either
P8 omits them, or it adds minimal forward-only instrumentation and labels the start date.

---

## 5. Gap classification

**Available today**
Message volume and direction; conversation created / status changes / reopens; first response, resolution and
reply time; bot handoff and bot resolution; CSAT; campaign recipient funnel including Meta-confirmed delivered,
read and failed with reasons; outbound message delivery state; flow session lifecycle, duration and failure codes;
cart lifecycle including abandonment, completion and outreach; commerce action runs; contact creation.

**Available but needs an adapter or query layer**
Reopen counting (`conversation_opened` is written but no registry reads it); per-inbox and per-agent aggregates
when `reporting_events_rollups` is unpopulated; assignee / team / label / priority activity, which can be shown
but not aggregated; commerce order-status distribution, which is a snapshot and must be labelled "as of
`fetched_at`"; per-currency spend.

**Not currently durable**
Automation executions for rules **without** `execution_delay`; automation action success and failure beyond the
terminal status of a delayed row; contact profile and custom-attribute changes; label add/remove as structured
data. (Delayed-rule executions *are* durable, but only for 30 days and only where `delayed_automations` is on.)

**Impossible to reconstruct historically**
Flow node-by-node execution and failure-node distribution; order history and any revenue time series; automation
execution history before instrumentation exists; any structured form of the assignee / team / label / priority
activity already written as prose.

---

## 6. Proposed architecture

Extend, do not duplicate. Three additions, each sitting on an existing seam.

**6.1 A metric family registry, extending the existing one.** `ReportingEvents::MetricRegistry::REPORT_METRICS`
(`metric_registry.rb:27-38`) already describes a metric as `{ raw_event_name, rollup_metric, aggregate,
raw_count_strategy }`, and the file's own TODO at `:2` asks for it to be split. P8 adds Lynomia metric families
through a `custom/` module that contributes entries, so the WhatsApp, campaign, flow and commerce metrics are
declared the same way the conversation metrics are, and the existing builders keep working unchanged.

**6.2 `Custom::Analytics::*` query services, one per domain, all taking an account and a filter object.**
They reuse `DateRangeHelper#range`, `TimezoneHelper`, and `group_by_period` so bucketing stays identical to the
existing reports. No new aggregation engine.

**6.3 A contact timeline read projection, with adapters.** No new mega-table. One query service composes
per-source adapters, each returning the same normalised row:

    Custom::Contacts::ActivityTimelineQuery
      ├── MessagesAdapter          messages (incoming/outgoing/template/private note)
      ├── ConversationEventsAdapter messages where message_type = activity
      ├── ReportingEventsAdapter    first_response, conversation_resolved, bot_*, conversation_opened
      ├── CsatAdapter              csat_survey_responses (direct contact_id)
      ├── CampaignAdapter          campaign_recipients (direct contact_id)
      ├── CommerceAdapter          commerce_carts, commerce_action_runs, commerce_customer_links
      └── FlowAdapter              flow_sessions via conversation

Each adapter is account-scoped independently, so a failing adapter degrades to a warning plus a `partial: true`
flag on the response rather than an empty timeline. The DTO derives from the existing message serializer
conventions rather than a new invented shape.

**No new durable event table is proposed in this phase.** Every event the timeline shows already has a canonical
home. The only candidates for new storage are automation executions and contact attribute changes, and both are
forward-only instrumentation decisions that belong to their own phases, not to the timeline.

---

## 7. Risks

**Tenancy.** `Current.account` is the only account source in the existing reports (`reports_controller.rb` passes
`Current.account` into every builder); `params[:account_id]` is never trusted. Every P8 adapter must scope
independently — `audits` has no `account_id` at all (it scopes via `associated_type='Account'`), and
`contact_inboxes` has no `account_id` either, so any join through them needs an explicit account predicate on the
other side.

**Permissions.** `ReportPolicy#view?` is `@account_user.administrator?` — reports are administrator-only today,
and `reports_controller.rb:55` repeats the check inline for drilldown. P8 analytics must follow that, and the
contact timeline must follow the *contact* permission rather than the report one, since an agent who may open a
contact should see its activity. Private notes inside the timeline need the same gate the conversation view uses.

**Performance.** The timeline's hardest read is "this contact's messages across all of its conversations ordered
by time". `messages` has no `(contact_id, created_at)` path — there is no `contact_id` on `messages` at all — so
it must go through `conversations.contact_id`. `index_conversations_on_contact_id` exists, and
`index_messages_on_conversation_account_type_created` covers the per-conversation read, but a contact with many
conversations fans out. This is the one place a new index may be justified, and it must be decided from a real
`EXPLAIN`, not assumed.

**Rollup emptiness.** If the production account has no `reporting_timezone`, `reporting_events_rollups` is empty
(§1.4). A1 must therefore work from raw `reporting_events` and treat rollups as an optimisation.

**Timezone split.** §1.5: live reports bucket by the viewer's offset, rollups by the account's timezone. P8 must
pick one and say so; mixing them in a single view produces buckets that disagree.

---

## 8. Recommended NOT to implement

| Feature from the brief | Why not |
| --- | --- |
| Flow node execution distribution and failure-node charts (A6) | no per-node history is stored; only the current node and a step counter |
| Automation execution analytics for **immediate** rules (A5) | rules without `execution_delay` leave no record at all; nothing can be reconstructed |
| Automation execution trend longer than 30 days (A5) | `purge_terminal!` deletes terminal rows past `RETENTION_WINDOW = 30.days` |
| "Sessions abandoned" as a flow state (A6) | no such status exists; any threshold would be invented |
| Revenue / GMV / profit (A7) | no order store, and `spend` is deliberately per-currency and unconverted |
| Order-status trend over time (A7) | `commerce_contact_metrics` is an overwritten cache, not history |
| Structured label / assignment / team analytics (A1, B1) | the activity rows are localized prose, lossy and locale-dependent |
| Contact profile change history (B1) | `Contact` is not audited; nothing records it |

