# P9 architecture

The decisions, the schema, and the boundaries. Everything here follows from `00-discovery.md`; where a decision
turns on a single fact, that fact is cited again rather than referenced.

---

## 1. Two products, one seam

**Support cases** are a tenant product: an account's agents open, work and resolve structured cases that a
conversation alone cannot hold. **The Operations Center** is an operator product: one Super Admin console that
answers "what in Lynomia Chat needs attention?".

The seam between them is a single field on the ticket, `source_type` + `source_id`, pointing at the operational
signal that caused the case. An operator looking at a failing inbox can open the case that already exists for it
or create one; the case carries the affected account, inbox and signal, and nothing else from the operator's view.
That is the whole bridge. Neither product has a copy of the other's data.

---

## 2. Namespace and placement

Lynomia-exclusive, so a top-level namespace under `custom/`, exactly as P8 did with `Analytics::` and
`Contacts::`:

```
custom/app/models/support/ticket.rb            -> Support::Ticket
custom/app/models/support/ticket_event.rb      -> Support::TicketEvent
custom/app/models/support/sla_policy.rb        -> Support::SlaPolicy        (on the existing sla_policies table)
custom/app/models/operations/signal.rb         -> Operations::Signal
custom/app/services/support/...
custom/app/services/operations/...
custom/app/controllers/api/v1/accounts/support/...
custom/app/controllers/super_admin/operations_controller.rb
custom/db/migrate/2026100910XXXX_*.rb
```

`Custom::X` stays reserved for `prepend_mod_with` overrides of OSS classes, which is how P9 hooks the two places
that currently only log a channel failure.

---

## 3. `support_tickets`

One row is one support case. It holds the case, never the conversation: no message bodies, no attachments, no
contact identity beyond the foreign key, no provider payload, no credential.

| Column | Type | Null | Why |
| --- | --- | --- | --- |
| `account_id` | references | no | the tenant boundary; every query starts here |
| `reference_number` | integer | no | per-account sequential, rendered as `TCK-000123` |
| `title` | string | no | the thing Conversation has no column for |
| `description` | text | yes | the case summary; optional because an operator-created case may be fully described by its signal |
| `category` | string | no | controlled allow-list, default `other` |
| `status` | integer | no | enum, default `open` |
| `priority` | integer | no | enum, default `medium` — the same four values Conversation uses |
| `conversation_id` | references | **yes** | the linked thread, when there is one |
| `contact_id` | references | **yes** | the customer, when there is one |
| `inbox_id` | references | **yes** | the channel, when there is one; also the business-hours source |
| `assignee_id` | references(User) | yes | reuses Chatwoot users |
| `team_id` | references | yes | reuses Chatwoot teams |
| `created_by_id` | references(User) | yes | never accepted from the client; nil for an operator/system case |
| `source_type` | string | yes | allow-listed; the operational origin |
| `source_id` | bigint | yes | |
| `sla_policy_id` | references | yes | the existing `sla_policies` table |
| `first_response_due_at` | datetime | yes | |
| `resolution_due_at` | datetime | yes | |
| `first_responded_at` | datetime | yes | |
| `first_response_breached_at` | datetime | yes | written once, by the sweeper |
| `resolution_breached_at` | datetime | yes | written once, by the sweeper |
| `sla_paused_at` | datetime | yes | set on entering a customer-waiting state |
| `sla_paused_seconds` | integer | no | default 0, accumulated |
| `last_activity_at` | datetime | no | the list's default sort |
| `resolved_at` / `closed_at` | datetime | yes | |
| `created_at` / `updated_at` | datetime | no | |

The three nullable links are the entire reason this is a table and not columns on Conversation:
`conversations.inbox_id` is `null: false` (`db/schema.rb:1024`) and `contact_id` is validated present
(`app/models/conversation.rb:78`) and dereferenced in `before_create` (`:308`). An internal operational case has
neither.

### Indexes, and why each one

Eight, not the eleven the brief's filter list would suggest:

| Index | Serves |
| --- | --- |
| `(account_id, reference_number)` UNIQUE | identity, and reference lookup |
| `(account_id, last_activity_at DESC)` | the default list, every status tab, and paging |
| `(account_id, assignee_id, status)` | My Tickets, Unassigned (`assignee_id IS NULL` uses the same index) |
| `(account_id, team_id, status)` | Team Tickets |
| `(conversation_id)` | the conversation panel's reverse lookup |
| `(contact_id)` | Contact 360 |
| `(account_id, resolution_due_at)` partial `WHERE resolution_due_at IS NOT NULL AND resolution_breached_at IS NULL AND status < 4` | the overdue list and the resolution sweeper |
| `(account_id, first_response_due_at)` partial `WHERE first_response_due_at IS NOT NULL AND first_responded_at IS NULL AND first_response_breached_at IS NULL AND status < 4` | the first-response sweeper — one of the two queries that run on a schedule across every account |

The second row is a **correction P9.8 made from measurement**, and it is worth stating plainly because the
original choice looked right and was not. This table first carried `(account_id, status, last_activity_at DESC)`
on the reasoning that the list is always filtered by status and always sorted by activity. But `status` sits
between the equality column and the sort column, so that index cannot produce `ORDER BY last_activity_at DESC`
for a given account at all: the plan fell to a parallel sequential scan and a top-N sort. At 500,000 cases with
the account holding 30% of them the default list took **39.997 ms**; with `(account_id, last_activity_at DESC)`
it takes **0.057 ms**. Status is then a cheap filter over the ordered scan. The replaced index earns nothing
beside the new one — measured on the worst case for the new one, an account with 150,000 cases of which only 200
are still active and those the oldest, the planner picks the activity index either way. Full plans in
`06-security-performance.md` §2.

Deliberately **not** added: `(account_id, priority)` — priority is a low-cardinality filter that the ordered
scan already narrows, and an index per filter combination is how a write-heavy table gets slow. `(account_id,
updated_at)` — `last_activity_at` is the sort the product actually uses, and two near-identical indexes is one
too many. `(account_id, status)` for the tab counts — tried, measured, and rejected: it moved the grouped count
from 28.3 ms to 24.6 ms, which does not buy a 3.4 MB index. Every decision here is taken with
`EXPLAIN (ANALYZE, BUFFERS)` against fixtures built inside a rolled-back transaction, as P8 established.

### Reference numbering

Per-account sequential, assigned inside the creating transaction:

```sql
SELECT pg_advisory_xact_lock(hashtext('support_tickets_reference'), account_id);
SELECT COALESCE(MAX(reference_number), 0) + 1 FROM support_tickets WHERE account_id = $1;
```

Race-safe (the lock is per account and released by the transaction), needs no trigger, no per-account sequence,
no backfill for existing accounts, and no edit to `app/models/account.rb`. The alternative — copying
`display_id`'s HairTrigger plus dynamic-sequence mechanism (`app/models/account.rb:205-207`,
`app/models/conversation.rb:429-431`) — would require a second explicitly named trigger on `accounts`, a
backfill migration creating a sequence for every existing account (the sequences are not in `db/schema.rb`, so a
fresh load gets none and the first insert raises), an addition to `Account#remove_account_sequences` or every
account deletion leaks a sequence, and a post-create re-fetch. For an object created by a human a few times an
hour, the advisory lock is the smaller correct answer.

`TCK-` + six zero-padded digits is a presentation concern, rendered in the serializer and the UI. Lookup accepts
`123` or `TCK-000123`. Numbers are not reused because tickets are closed, not destroyed; P9 exposes no delete.

---

## 4. Status model

```
open(0)  in_progress(1)  waiting_on_customer(2)  waiting_on_internal(3)  resolved(4)  closed(5)
```

Six, deliberately. The brief's list, minus nothing and plus nothing.

| Property | Values |
| --- | --- |
| **Active** | `open`, `in_progress`, `waiting_on_customer`, `waiting_on_internal` |
| **Terminal** | `resolved`, `closed` |
| **Pauses the SLA clock** | `waiting_on_customer` only |

`waiting_on_internal` does **not** pause the clock, and that is the point: waiting on ourselves is our own delay,
and a policy that stopped counting it would let a case sit forever inside its target. Waiting on the customer is
outside our control, so it pauses. This is the single rule in P9 most likely to be argued with, so it is stated
here rather than left to be inferred from behaviour.

`resolved` means the work is done and the case can still be reopened; `closed` means finished, and is what an
auto-close would set. Transitions are validated by an explicit table in `Support::Tickets::StatusTransition`
rather than by free assignment: every active state can reach every other active state and both terminal states;
`resolved` can reach `closed` or reopen to `open`; `closed` can only reopen to `open`. Any other transition is a
422 naming the attempted edge. Reopening clears `resolved_at`/`closed_at` and starts a **new** resolution target
from the reopen instant, leaving a satisfied first-response target satisfied.

---

## 5. Priority, category, labels

**Priority** is `low/medium/high/urgent` — the same vocabulary and the same order as `Conversation`
(`app/models/conversation.rb:87`), so an agent learns one scale. No separate severity field: SEV1–4 would be a
second name for one concept, and the brief's own rule is not to carry two fields the product does not need. An
operational incident is `category: operational` at `priority: urgent`.

**Category** is one controlled string, validated by `inclusion:` against a frozen list — the house pattern
(`custom/app/models/commerce/action_run.rb:66`), because there is no polymorphic-type allow-list anywhere in this
repository to copy and `conversations.ai_assignee_type` is unconstrained at both layers:

`technical, billing, account, integration, whatsapp, commerce, campaign, automation, operational, other`

**Labels** are not reinvented. `Labelable` (`app/models/concerns/labelable.rb`) is one macro and two methods,
fully generic, so `Support::Ticket` includes it and gets the account's existing labels for free. Category is the
one axis the product routes and reports on; labels are the open-ended axis the account owns.

---

## 6. Relationships

- A **conversation has many tickets**; a **ticket links to at most one conversation**. One thread can raise two
  issues, which is the realistic case; one case spanning several threads is not, and a join table for it would
  be speculative. `conversation_id` is nullable and `on_delete: :nullify`, so deleting a conversation leaves the
  case intact with its history.
- **Contact 360**: `contact_id` nullable, `on_delete: :nullify`. The contact page lists the contact's cases, and
  P8's activity timeline gains a ticket adapter (§9).
- **Cross-tenant linking is impossible by construction**: every link is resolved through
  `Current.account.<association>.find(...)`, so a foreign id is a 404 before it can be written, and a model
  validation re-checks that `conversation`, `contact`, `inbox`, `assignee`, `team` and `sla_policy` all belong to
  the ticket's account. Both layers, because the controller is the enforcement point and the validation is the
  net under it.
- **`source_type` / `source_id`** is the operational origin, with a frozen allow-list of exactly one type in P9
  (`Operations::Signal`) and a validation that refuses anything else. A string column plus `inclusion:` rather
  than a Rails polymorphic association, so an arbitrary class name cannot be injected and then constantized.

---

## 7. History and internal notes: one table

`support_ticket_events` serves **both**, because an internal note *is* an entry in the case's history, and two
tables would mean two orderings to merge in the UI.

| Column | Type | Null | Why |
| --- | --- | --- | --- |
| `account_id` | references | no | scoping, independently of the ticket |
| `support_ticket_id` | references | no | |
| `user_id` | references(User) | yes | nil for a system or sweeper event |
| `event_type` | string | no | allow-listed |
| `body` | text | yes | populated only for `note` |
| `data` | jsonb | no | default `{}`; the structured before/after, ids and codes only |
| `created_at` / `updated_at` | | no | |

`event_type` allow-list: `created`, `note`, `status_changed`, `priority_changed`, `assigned`, `team_changed`,
`category_changed`, `conversation_linked`, `conversation_unlinked`, `sla_applied`, `sla_first_response_met`,
`sla_first_response_breached`, `sla_resolution_breached`, `resolved`, `reopened`, `closed`.

Index: `(support_ticket_id, created_at)` for the trail, and `(account_id, created_at)` for the account-wide feed.
`data` is jsonb with **no** ActiveRecord `store`, so it is directly queryable — the trap P8 documented on
`messages.content_attributes` (`app/models/message.rb:112`) is avoided by not repeating it.

This table is also what makes the case history *queryable*, which Conversation's history is not: only
`conversation_status_changed` carries a structured payload
(`app/models/concerns/activity_message_handler.rb:50-61`) and every other change is localized prose.

**@mentions are deferred.** The `mentions` table is `(user_id, conversation_id)` and cannot address a ticket, and
the notification that would carry a mention is Conversation-only (§11).

---

## 8. SLA

### What is reused

- The **`sla_policies` table**, unchanged: `name`, `description`, `first_response_time_threshold`,
  `resolution_time_threshold`, `only_during_business_hours`, `account_id` (`db/schema.rb:1661`). Zero migration.
  `next_response_time_threshold` has no meaning for a case and stays nil — one unused nullable column, recorded
  rather than hidden.
- **`ReportingEventHelper`** (`app/helpers/reporting_event_helper.rb`) and the `working_hours` gem
  (`Gemfile:166`) for business-hours arithmetic, including its private `configure_working_hours`, reachable by
  including the helper.
- **`WorkingHour`** rows and `inbox.working_hours_enabled?` / `inbox.timezone`.
- **`Account#reporting_timezone`** for every display and every analytics bucket, exactly as P8 fixed it.
- The surviving **`sla.json`** i18n in `en` and `ar`, for the shared vocabulary.

### What is new

`applied_slas` cannot hold a ticket's SLA state: its `conversation_id` is `null: false` (`db/schema.rb:181`). So
the per-case clock lives on the ticket itself, in the eight columns listed in §3.

### The clock, stated precisely

| Event | Rule |
| --- | --- |
| **Starts** | when a policy is attached — at create if `sla_policy_id` is given, otherwise at the moment it is set. `first_response_due_at` and `resolution_due_at` are computed from that instant. Never retroactively from `created_at` of an older ticket, because that would invent history |
| **Business hours** | applied only when the policy says `only_during_business_hours` **and** the ticket has an inbox **and** that inbox has working hours enabled. Otherwise calendar time. A case with no inbox always uses calendar time, and the API says so in its `meta` |
| **First response satisfied** | the first outgoing, non-private message in the linked conversation after the ticket was created, or an explicit mark by the assignee for a ticket with no conversation. `first_responded_at` is written once |
| **Pauses** | on entering `waiting_on_customer`: `sla_paused_at = now` |
| **Resumes** | on leaving it: `sla_paused_seconds += (now - sla_paused_at)`, both due timestamps move forward by the same amount, `sla_paused_at = nil` |
| **Breaches** | the sweeper writes `first_response_breached_at` / `resolution_breached_at` once, when the due time has passed, the target is unmet, and the clock is not paused. A breach is never un-written |
| **Resolution satisfied** | entering `resolved` or `closed` before `resolution_due_at` |
| **Reopen** | a new `resolution_due_at` from the reopen instant; `resolution_breached_at` is cleared because the new target has its own outcome; a satisfied `first_responded_at` stays |
| **Priority change** | does **not** move the due times. Due times are a commitment made when the policy was attached; silently re-dating them on a priority edit would make the SLA unfalsifiable |
| **Team reassignment** | no effect |
| **Timezone** | the account's, for everything a human reads. The inbox's, only inside the business-hours calculation, because that is the scope the gem configuration has |

The sweeper is one scheduled job over the partial index in §3, bounded, with no per-account loop.

### What cannot be reported

Nothing historical. No SLA was ever computed or stored in this fork and `applied_slas` has never held a row, so
every SLA figure P9 shows begins at the moment a policy is attached to a case. Stated in the API `meta` and on
the screen, not only in this document.

---

## 9. Reuse of P8, without touching it

P8 is a frozen library. P9 adds files and exactly two registry lines.

- **A `tickets` metric family**: a new `Analytics::Tickets::Metrics` + `Overview` pair mirroring
  `Analytics::Commerce::*`, one entry appended to `Analytics::MetricFamily::FAMILIES`, one action on the
  analytics controller, one route, one breakdown entry. No change to `DateRange`, `FilterSet`, `Breakdown`,
  `Result`, `RollupCoverage` or `RequestScoped`.
- **A ticket adapter on the contact timeline**: a new `Contacts::ActivityTimeline::TicketsAdapter` under the
  existing `BaseAdapter` contract, and one entry in `ActivityTimelineQuery::CATEGORIES`. It is **optional**, not
  core, so a ticket table problem degrades to a warning and cannot hide a contact's conversation history.
- The ticket metrics that P8's rules permit: created, resolved, open now, overdue now, by priority, by team, by
  category, average resolution where there is something to average. `average_` returns nil, never zero. No
  historical SLA attainment, because §8 says there is none.

---

## 10. Operations Center

Super Admin only, ERB inside the Administrate shell with Tailwind, following
`app/views/super_admin/push_diagnostics/show.html.erb` for the page shell and
`app/controllers/super_admin/dashboard_controller.rb:13-32` for cached flat aggregates.

### Health semantics

Four states, each defined so that none of them can be produced by silence:

| State | Definition |
| --- | --- |
| `healthy` | a positive observation exists and is inside its freshness window |
| `warning` | a durable problem that degrades but does not stop a capability, or a named threshold crossed |
| `critical` | a durable problem that stops a capability — no worker process, a channel that cannot authenticate, a store whose authorization is gone |
| `unknown` | no observation exists, or the only source is Redis and Redis holds nothing |

Every health item carries its **status, source class, last-observed time, one-line reason, affected
account/inbox/integration where applicable, and a link to investigate**. An item with no source renders
`unknown` with the reason "not recorded", never green.

### Three source classes, each labelled

- **Computed** from durable Postgres: WhatsApp failures and Meta codes, template rejections, campaign failure
  rates against an explicit threshold, stranded and skipped automations (30-day window), failed flow sessions,
  commerce store state. Grouped aggregate queries, never a per-account loop.
- **Recorded** in `operations_signals` (§11), written where a failure is already detected and currently only
  logged.
- **Probed** live and labelled as a reading taken now: Postgres, Redis, the Sidekiq process set and queue
  depths, version, Git SHA, pending migrations — by reusing what `instance_statuses_controller.rb` already does
  rather than writing it again.

### Account health

Component statuses, never a score. No "87% healthy". The account row shows: enabled/suspended, the feature flags
that matter, inbox count by channel, the worst channel status, commerce connection state, open and overdue cases,
and recent signals — each with its own state and source. A missing component is `unknown`.

The accounts list uses one grouped query per component, not `CountField`
(`app/fields/count_field.rb:3-7`), which is two uncached COUNTs per row during view render and is the N+1 the
existing accounts index already pays.

### Queues and application health

Read-only. `Sidekiq::Stats`, `Sidekiq::Queue`, `Sidekiq::ProcessSet` — the same API Sidekiq's own dashboard uses.
No retry, no delete, no kill: `Sidekiq::Web` is already mounted at `/monitoring/sidekiq` behind
`authenticated :super_admin`, and the Operations Center links to it rather than reimplementing it.

---

## 11. `operations_signals` — the one new operational store

This installation has no durable operational record of anything (`00-discovery.md` §5 and §9). One table closes
that, and its shape is driven by two requirements: an operator must be able to sort and filter across accounts,
and a repeated failure must not become a flood.

| Column | Type | Null | Why |
| --- | --- | --- | --- |
| `account_id` | references | **yes** | nullable because queue and installation signals belong to no account |
| `source` | string | no | allow-listed: `email_channel`, `whatsapp_channel`, `channel`, `commerce_store`, `webhook`, `queue` |
| `signal` | string | no | allow-listed: `authentication_failed`, `connection_failed`, `reauthorization_required`, `delivery_failed`, `sync_failed`, `backlog`, `dead_set_grew`, `no_workers` |
| `severity` | integer | no | `info/warning/critical` |
| `subject_type` | string | yes | allow-listed: `Inbox`, `Channel::Email`, `Channel::Whatsapp`, `Commerce::Store`, `Webhook` |
| `subject_id` | bigint | yes | |
| `reason` | string | yes | one sanitized line, bounded |
| `detail` | jsonb | no | default `{}`; allow-listed keys, ids/codes/counts only |
| `first_seen_at`, `last_seen_at` | datetime | no | |
| `occurrences` | integer | no | default 1 |
| `resolved_at` | datetime | yes | written when the thing works again |
| `support_ticket_id` | references | yes | the bridge, `on_delete: :nullify` |

The identity index is what makes it safe:

```
UNIQUE (account_id, source, subject_type, subject_id, signal) WHERE resolved_at IS NULL
```

One open row per distinct problem. A failing inbox polled every minute is one row with a rising `occurrences`,
not 1,440 rows a day. The same key is the dedup key for the support-case bridge, so "is there already a case for
this?" is a column read rather than a heuristic.

`detail` is written through a single recorder that allow-lists its keys; no provider body, no URL with a query
token, no header, no credential ever reaches it. The `reason` string goes through the same bound
`Lynomia::OperatorLog#value` already enforces.

### Where signals come from

Two OSS files gain the one-line `prepend_mod_with` the repository already uses in 108 places, and the behaviour
lands in `custom/`:

| Hook | Writes | Clears |
| --- | --- | --- |
| `Inboxes::FetchImapEmailsJob` rescue (`app/jobs/inboxes/fetch_imap_emails_job.rb:14-16`) | `email_channel` / `authentication_failed` or `connection_failed`, `critical` | on the next successful fetch |
| `Reauthorizable#prompt_reauthorization!` (`app/models/concerns/reauthorizable.rb:42`) | `channel` / `reauthorization_required`, `critical` | `reauthorized!` (`:71`) |
| `Lynomia::QueueHealthJob` (already exists) | `queue` / `backlog`, `dead_set_grew`, `no_workers` | on the next clean run |
| `Custom::Webhooks::Trigger` (already exists) | `webhook` / `delivery_failed`, `warning` | on the next success |

Each of these already emits a `Lynomia::OperatorLog` line or a `Rails.logger` line; P9 adds the durable row
beside it and leaves the log line alone, so nothing that an operator greps for today stops working.

This is prospective instrumentation. It records from the deploy forward and reconstructs nothing, and the
Operations Center says so for every signal class.

---

## 12. Boundaries

### Deferred, with the reason and the cost

- **A new automation event.** Adding `ticket_created` honestly costs fourteen files: `Custom::AutomationRule`
  extending `event_names`, a handler in `Custom::AutomationRuleListener`, a constant in `lib/events/types.rb`,
  the dispatch site, the condition and action vocabularies, the frontend constant lists, the i18n for both
  locales, and specs for each. It would also create a second event vocabulary to keep in step with the first.
  Out of scope, as a decision rather than an omission.
- **In-app notifications for ticket assignment.** `Notification` is structurally Conversation-only:
  `primary_actor.push_event_data.slice('conversation_id','id')` (`app/models/notification.rb:84`),
  `primary_actor.inbox.name` (`:106`), `primary_actor.display_id` (`:111`), `def conversation; primary_actor; end`
  (`:130`), `primary_actor&.push_event_data` (`:203`) and the API view
  (`app/views/api/v1/accounts/notifications/index.json.jbuilder:17`). A ticket may have no conversation, so
  reusing it would either misname the actor or silently skip conversation-less cases. P9 ships the views an
  agent actually looks at instead — My Tickets, Unassigned, Overdue — plus the durable event trail.
- **Reviving conversation SLA.** A separate product with its own surviving API contract
  (`api/sla.js`, `api/slaReports.js`, `store/modules/sla.js`, `store/modules/SLAReports.js`), currently
  unreachable because no route points at it.
- **Sidekiq mutations**, **ticket attachments**, **multi-conversation linkage**, **an Incident table**,
  **@mentions on notes**, **holidays**: each with its reason in `00-discovery.md` §10.

### Hard rules

- `Current.account` only; `params[:account_id]` is never trusted, and `account_id`, `created_by_id`,
  `reference_number` and every SLA timestamp are never accepted from the client.
- No secret in any response, audit payload, signal `detail`, or log line. The existing
  `Lynomia::OperatorLog#value` bound is the precedent and the test.
- Audit through the existing `audited` gem with `associated_with: :account` — the `audits` table has no
  `account_id` (`db/schema.rb:264-287`), so the association *is* the scope — with `except:` for anything
  credential-bearing. The `audit_logs` feature flag stays off; P9 does not enable it.
- A new non-premium feature flag appended to `config/features.yml` with `column: feature_flags_ext_1`, because
  the `feature_flags` column is full (63/63) and `premium: true` features have no operator-reachable enable path
  in this fork (`custom/app/models/billing_plan.rb:36-41`).
- A new `support_ticket_manage` string appended to `CustomRole::PERMISSIONS`
  (`custom/app/models/custom_role.rb:40-48`), or no custom role could ever be granted access.
- `enterprise/` stays absent. Nothing here is copied from Enterprise; the SLA engine, the audit writers and the
  operations console are all written against OSS and Lynomia code only.
