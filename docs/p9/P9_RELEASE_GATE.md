# P9 release gate

The brief's sixty questions, quoted verbatim and answered in order. Every answer points at the file, the spec or
the measurement that backs it; nothing here is an opinion about the code.

Gate run on: branch `claude/p9-support-operations-center`, based on the completed P8 head `4e8e3d0b`.

---

## Support architecture

**1. Did P9 reuse Conversation rather than duplicate messaging?**
Yes, completely. P9 adds no message table, no attachment path, no inbox concept, no channel, no delivery status,
no private-note mechanism, no conversation status, no assignment engine and no notification type. A case's
conversation link is a nullable `conversation_id`; everything that happens in a conversation continues to happen
in `Conversation` and `Message`. The one place P9 reads the message table is
`Support::Tickets::FirstResponseDetector`, which runs a single indexed `SELECT` for the first outgoing
non-private message — no hook, no column, no duplicate copy.

**2. Why is a Ticket/Case entity necessary, if one was created?**
Because of one schema fact: `conversations.inbox_id` is `NOT NULL` (`db/schema.rb:1024`) and validated
(`app/models/conversation.rb:77`), and `contact_id`, though nullable in the column, is validated present
(`:78`) and dereferenced in `before_create` (`:308`, `:312`). An internal operational case — "the Zid token
needs rotating before Thursday" — has **no customer and no channel**, so it cannot be a Conversation without
inventing a fake inbox and a fake contact for it. The brief's option (A), extending Conversation, would have
required relaxing a `NOT NULL` on the single most-read table in the product; option (C), reusing an existing
model, has no candidate (`AutomationRule`, `Macro` and `Campaign` are configuration, not work items). So
option (B): a thin table beside Conversation. `docs/p9/01-architecture.md` has the full argument including what
was rejected.

**3. What remains canonical in Conversation?**
Messages and their bodies; attachments; private notes to a customer thread; conversation status
(`open/resolved/pending/snoozed`); conversation assignment and team routing; the inbox and the channel;
contact identity and `contact_inboxes`; delivery and read status; typing, presence and unread counts; every
existing notification type; conversation labels; `first_reply_created_at` and the OSS reporting events.

**4. What remains canonical in Ticket?**
The per-account reference number; the case's own title, description and category; the case status and its
transition table; case priority; the case's assignee and team *for the case* (which may differ from the
conversation's); the SLA policy link and all seven SLA timestamps; the durable, typed, queryable case history
including internal notes; the lifecycle stamps `resolved_at` / `closed_at`; and the polymorphic `source` that
records an operational issue having opened it.

**5. Can a ticket link safely to contact/conversation/account?**
Yes, and all three links are optional. `account_id` is `NOT NULL` with a foreign key `on_delete: :cascade`;
`conversation_id`, `contact_id`, `inbox_id`, `assignee_id`, `team_id` and `sla_policy_id` are nullable with
`on_delete: :nullify` so deleting a conversation or a policy cannot take a case's history with it.

**6. Can links cross tenant boundaries?**
No, and this is enforced twice on purpose. At the boundary,
`Api::V1::Accounts::Support::TicketsController#resolved_attributes` turns every incoming id into a record
through `Current.account`, so a foreign id raises `RecordNotFound` and renders **404 before any write**. Under
that, `Support::Ticket#linked_records_belong_to_account` validates every link, and users through `AccountUser`
membership rather than a column comparison, for a console or a future service that does not come through the
controller. Proved by `spec/requests/support/p9_tenant_isolation_spec.rb` against a **mirrored two-account
fixture** — same data shape in both, including the same case reference — so a missing predicate shows up as a
borrowed record rather than as nothing at all.

**7. Is Ticket history durable?**
Yes. `support_ticket_events` is a table, not a log: `account_id`, `support_ticket_id`, `user_id`, a validated
`event_type` from a list of sixteen, an optional `body` for notes, and a jsonb `data`. Written only through
`Support::Tickets::EventRecorder`. This is the one history in the product that is **queryable** — a
conversation's own assignee, team, label and priority changes are localized prose with no structured payload
(`app/models/concerns/activity_message_handler.rb`), which is why P8's contact timeline had to leave them out
and P9's can include cases.

**8. Does Ticket reuse users/teams?**
Yes. `assignee` and `created_by` are `User`, `team` is `Team`; no new membership model, no new role. Visibility
reuses `AccountUser` for membership and `user.teams` for team scope, and the new permission
`support_ticket_manage` is an entry in the existing `CustomRole::PERMISSIONS`.

**9. Does it reuse labels where appropriate?**
Yes — `include Labelable`, which is `acts_as_taggable_on :labels`, the same account-wide labels conversations
and contacts already use. No new label table, no new label UI, and the existing labels work on a case with no
new code.

---

## Workflow

**10. What are the final statuses?**
`open`, `in_progress`, `waiting_on_customer`, `waiting_on_internal`, `resolved`, `closed`.

**11. Which are active?**
`open`, `in_progress`, `waiting_on_customer`, `waiting_on_internal` (`ACTIVE_STATUSES`).

**12. Which are terminal?**
`resolved`, `closed` (`TERMINAL_STATUSES`). Both are integer enum values ≥ 4, which is what the partial indexes'
`status < 4` predicate means.

**13. How does reopen work?**
`resolved → open` or `closed → open`, never to another state (reopening to `in_progress` would claim somebody is
already working it). Reopening clears **both** `resolved_at` and `closed_at`, writes a `reopened` history event,
and — if a policy is attached — gets a **new resolution target from the reopen instant** and clears
`resolution_breached_at`, because the new target has its own outcome. A first response that already happened
stays satisfied. Moving `resolved → closed` deliberately does *not* clear `resolved_at`.

**14. Are transitions validated?**
Yes, against an explicit table in `Support::Tickets::StatusTransition::ALLOWED`, in a service that also owns
the SLA side effects and the history write — so a controller cannot bypass it by assigning attributes. A refused
edge is a **422 naming the attempted edge and the allowed set**; a no-op transition is allowed and is a no-op,
so an idempotent client retry does not 422.

**15. How are priority/category represented?**
`priority` is an integer enum with the **same four values in the same order as `Conversation`** (`low`,
`medium`, `high`, `urgent`), so an agent learns one scale. `category` is a validated string from a list of ten
(`technical billing account integration whatsapp commerce campaign automation operational other`) — a string
rather than an enum because the list is product vocabulary that will grow, and a string column plus
`validates … inclusion:` is the house pattern (`custom/app/models/commerce/action_run.rb`). There is no separate
`severity` field: two overlapping scales invite the question "which one do I set?".

---

## SLA

**16. Is SLA reused from existing architecture or newly implemented?**
Both, deliberately, and the split matters. **Reused**: the `sla_policies` table that already ships in the OSS
schema and has never held a row in this fork; the business-hours calculator (`ReportingEventHelper` plus the
`working_hours` gem) with the `WorkingHour` rows an inbox already has. **Newly implemented**: the clock
(`Support::Tickets::SlaClock`), the sweep (`Support::Tickets::SlaSweeper` + `Support::SlaSweepJob`), the model
(`Support::SlaPolicy`) and the API. Chatwoot's own SLA engine lived in `enterprise/`, which is permanently
absent; **none of the code here is derived from it**. `applied_slas` and `sla_events` are *not* reused —
`applied_slas.conversation_id` is `NOT NULL` so they cannot hold a case. The endpoints deliberately do not claim
`/api/v1/accounts/:id/sla_policies`, which is the path the surviving (and currently unreachable)
conversation-SLA frontend expects: serving case-shaped data there would make a dormant UI appear to work.

**17. What starts SLA?**
Attaching a policy — at create if one is given, otherwise the moment `sla_policy_id` is set. Targets are
measured **from that instant**, never retroactively from `created_at`, because a due time invented backwards is
a commitment nobody made and would mark a case breached the moment a policy was first attached.

**18. What pauses it?**
`waiting_on_customer`, and only that status. `waiting_on_internal` does **not** pause it, because waiting on
ourselves is our own delay. Resuming moves both due times forward by exactly the paused duration and adds it to
`sla_paused_seconds`, so the pause is visible in the record rather than inferred from a gap.

**19. What ends it?**
First response: the first outgoing non-private message in the linked conversation at or after the case opened,
detected by the sweep, which records either `sla_first_response_met` or `sla_first_response_breached`.
Resolution: entering a terminal status; or the sweep writing `resolution_breached_at` once the due time has
passed on a still-active, unpaused case. A breach is written once and **never un-written** — the case really did
pass its target.

**20. What happens on reopen?**
See 13: a new resolution target from the reopen instant, `resolution_breached_at` cleared, the first response
left satisfied.

**21. Is account timezone used?**
For SLA, **no — and that is the correct answer, stated rather than hidden.** Business hours are *inbox*-scoped,
because that is the scope the calculator has: `WorkingHours::Config` is set from `inbox.working_hours` and
`inbox.timezone`. A case with no inbox therefore runs on calendar time even under a business-hours policy;
`business_hours_applicable?` returns false, the `sla_applied` history event records that flag, and the API
exposes it so the UI can say which clock a case is on. The **account** timezone does govern everywhere a
calendar day is involved: all of Analytics, including the new Support cases family, cuts its buckets in it,
unchanged from P8.

**22. What historical SLA data is unavailable?**
Everything before a policy was attached. No case has a due time, a first response or a breach for the period it
was ungoverned, and none is backfilled — a retroactive target is a fiction. Three consequences, all of them
visible rather than quietly papered over: there is **no SLA attainment percentage**, **no first-response time
average** and **no reopen rate** in Analytics, because each would divide two different populations; and when the
account has active cases with no policy, the response carries one conditional warning saying a zero breach
count does not mean nothing was late. Also unavailable: anything the removed Enterprise conversation-SLA engine
would have recorded — `applied_slas` and `sla_events` are empty and stay empty.

**23. Are overdue queries performant?**
Yes, now — and P9.8 is the reason the answer is not "no". The `overdue` scope originally omitted
`resolution_breached_at IS NULL`, which both contradicted the product's own definition of overdue versus
breached *and* made the purpose-built partial index unusable, because a query that does not ask for a partial
index's predicate cannot use it. Fixed:

| | before | after |
| --- | --- | --- |
| overdue count, 500,000 cases | 23.697 ms, bitmap over the whole account | **12.826 ms**, `index_support_tickets_on_open_resolution_due` |
| overdue count, 100,200 cases | 0.940 ms | **0.028 ms** |
| `overdue_now` analytics metric | 1.068 ms | **0.037 ms** |
| the Overdue list view | 0.781 ms | **0.025 ms** |

---

## Operations

**24. What health sources are canonical?**
Three kinds, named as such on the page. **Probed live**: database (`SELECT 1`), Redis (`PING` + `INFO`),
Sidekiq processes, pending migrations, release metadata. **Computed from the product's own durable tables, one
grouped query each, cached 5 minutes**: failed outgoing WhatsApp messages, rejected templates, campaign failure
rates, abandoned automation episodes, failed flow sessions, commerce stores needing reauthorization.
**Recorded**: `operations_signals`, the new table, written by four writers — channel reauthorization, the IMAP
fetch job, outbound webhooks, and the queue health job.

**25. Can unknown be distinguished from healthy?**
Yes, and this is the console's single most important property. `Operations::Health` has four statuses —
`healthy`, `warning`, `critical`, `unknown` — plus an `absent` constructor, and `SEVERITY_ORDER` ranks
`unknown` **above** `healthy`, so a page with one unreadable component cannot present itself as fine. A probe
that raises reports `unknown` with the reason, never `critical` and never `healthy`. An area with no source in
this installation reports `absent` with the reason ("No WhatsApp inbox exists", "No commerce store is
connected"). An empty signal store says "nothing has been recorded" rather than showing green. A real bug caught
by this rule during P9.5: the migrations probe used `connection.migration_context`, which does not exist on
Rails 7.2, so it raised and silently became `unknown` — visible as `unknown` with a reason rather than as a
plausible green badge, and fixed.

**26. Is Operations Super Admin-only?**
Yes. `SuperAdmin::OperationsController < SuperAdmin::ApplicationController`, whose only guard is
`authenticate_super_admin!` — there is no Pundit layer in the Administrate stack and P9 does not invent one.
`spec/controllers/super_admin/operations_controller_spec.rb` proves refusal for an unauthenticated caller, a
tenant **administrator** and a tenant **agent**, on all three pages and on the one mutation.

**27. Does account health avoid fake scores?**
Yes, explicitly. There is no score and no percentage. Each account row carries five independent component
statuses (the account, open signals, channels, commerce, cases) and the row's badge is the **worst** of them.
A score would be a number nobody can act on, and averaging an `unknown` into it would turn missing information
into a reassuring digit.

**28. Can WhatsApp issues be investigated safely?**
Yes. The console reads `messages.status = failed` for WhatsApp inboxes over 24 hours and
`whatsapp_message_templates.meta_status = REJECTED` with no window, both of which are durable rows the product
already wrote. **Nothing calls Meta.** The row links through to the account, and the deeper per-account detail
is P8's Analytics → WhatsApp screen rather than a second copy here.

**29. Can email/IMAP failures be surfaced?**
Yes, and this was the worst gap the discovery found. Before P9 a plain-password IMAP inbox whose password was
rotated produced **one log line per poll**, no Postgres row, no Redis counter, no Sentry event and a
*successful* Sidekiq job — and once the OAuth variant's ten-failure Redis latch did trip, `should_fetch_email?`
stopped polling, so the inbox went **quiet** rather than erroring. `Custom::Inboxes::FetchImapEmailsJob` now
records `authentication_failed` (critical) for a `Net::IMAP::NoResponseError` / `BadResponseError` or an
`OAuth2::Error`, and `connection_failed` (warning) for the connection-level errors in
`ExceptionList::IMAP_EXCEPTIONS`, which are a different problem with a different fix. A successful fetch
resolves them. **The raised error is re-raised unchanged**, so the OSS job's own rescues, logging and exception
tracking behave exactly as before.

**30. Can commerce issues be surfaced?**
Yes, from `commerce_stores.status` — a column the product already maintained, so this needed no new writer.
Stores in `needs_reauth` or `disconnected` are **critical**: a store whose authorization is gone has stopped
working entirely. P9 adds no provider call and changes no Salla, Zid or Shopify gate.

**31. Are queue stats read-only?**
Yes. The console reads the Sidekiq process set and the queue sizes and never writes: no retry, no kill, no
clearing the dead set, no enqueue. `Sidekiq::Web` is already mounted at `/monitoring/sidekiq` behind the same
super-admin guard and does all of that properly; duplicating it badly would be worse than linking to it.

**32. Are DB/Redis checks safe and lightweight?**
Yes: one `SELECT 1` and one `PING` plus `INFO` per page load. No shell command, no provider call, no table scan,
no lock. The expensive part of the page — the computed signals — is cached for 5 minutes and carries a
`computed_at` so the page says how old the reading is instead of implying it is live. Account totals use
`reltuples`, the same estimate the existing Super Admin dashboard uses, not `COUNT(*)`.

**33. Are webhook errors sanitized?**
Yes, in the one writer. Neither the URL nor the payload is stored: `detail` carries `endpoint_host` (the host
alone), the HTTP status and the exception class, and `reason` is the exception's own message put through the
recorder's sanitizer — the subject's own secrets removed by exact value, URL userinfo and credential-named
`key=value` pairs removed by pattern, whitespace collapsed, bounded at 500 characters. `detail` separately
accepts only 24 allow-listed keys holding scalar, whitespace-free values, so provider prose cannot arrive that
way either.

---

## Bridge

**34. Can an operational issue link/create a support case?**
Yes — `Operations::CaseBridge`, from one button on the Issues page. Priority maps from severity
(critical → `urgent`, warning → `high`, info → `medium`), category is `operational`, and the two records link
both ways (`support_tickets.source_type/source_id` and `operations_signals.support_ticket_id`). `created_by` is
**nil**: a super admin is not an account user, and borrowing an account's administrator would put a name in the
audit trail that did nothing. An **installation-wide** signal cannot become a case and the button says so with
a reason — `support_tickets.account_id` is `NOT NULL`, and a synthetic "operations account" would be a worse lie
than an honest refusal, appearing in every account list, count and report.

**35. Can duplicate case spam occur?**
No, on both sides. The signal side is deduplicated by a **partial unique index** on the open identity, so a
failure recurring every minute increments one row rather than inserting rows. The case side is idempotent while
the linked case is still active: pressing the button again surfaces *that* case instead of opening a second.
Once the linked case is closed, a recurrence can open a new one, which is the correct behaviour rather than a
leak.

**36. Is diagnostic context sanitized?**
Yes, and the case inherits that for free because it is built from the already-sanitized signal row rather than
from the raw error. `spec/requests/operations/p9_hardening_spec.rb` asserts it directly: it plants a real IMAP
password, a real WhatsApp `api_key` and real Salla tokens, records signals whose `reason` quotes them, opens a
case through the bridge, and asserts the case's title, description and history contain none of them.

---

## Security

**37. Can any secret appear in API response?**
No, and P9.8 found and fixed the one place where it could. The case serializer carries ids, enum values,
timestamps, counts and the contact's display name — nothing else; `spec/requests/support/tickets_spec.rb` pins
the exact key list and asserts the body matches no `token|secret|password|provider_config`. The signal table is
constrained at its one writer (§33). The defect: `reason` was bounded in length but not in content, so an IMAP
server answering a failed `LOGIN` with the password it was given stored it verbatim, rendered it in the console
and copied it into a case. Now the recorder removes the subject's own secrets **by exact value** — it is the one
place that knows both what failed and what its credentials are — plus two inline shapes by pattern. Nothing is
matched on entropy or length, because an entropy rule would redact the order ids and `wamid`s an operator needs
while still missing a short password.

**38. Can foreign account IDs be linked?**
No. See 6: resolved through `Current.account` at the boundary (404), validated on the model (the net), and
proved against a mirrored two-tenant fixture. A **filter** id from another account is a **422 naming the
filter**, never an empty page — an empty page reads as "this customer has no cases", which is a different and
wrong answer.

**39. Can arbitrary polymorphic types be injected?**
No. `support_tickets.source_type` is a plain string column with
`validates :source_type, inclusion: { in: SOURCE_TYPES }, allow_nil: true`, where `SOURCE_TYPES` is
`%w[Operations::Signal]`. This is not optional hygiene: an unvalidated polymorphic type is an arbitrary-class
read, and the repository-wide audit in `00-discovery.md` found **seven polymorphic declarations and no
allow-list anywhere**, so P9 could not copy a pattern and had to establish one. `source_type` and `source_id`
are also not in the controller's permitted params at all. The spec proves `'User'` is refused and
`Operations::Signal` accepted.

P9 introduces **two** polymorphic columns and allow-lists both: `operations_signals.subject_type` is likewise
validated against `%w[Inbox Commerce::Store Webhook]`, and that table's `source` and `signal` are allow-listed
too, so a typo in a writer is a validation failure rather than a row nobody will ever find again.

**40. Can non-Super Admin access Operations?**
No. See 26.

**41. Are admin mutations audited?**
The console has exactly one mutation, Open case, and it leaves two records. `Lynomia::OperatorLog` gets a line
naming the acting **super admin's email**, the signal and the case. The case itself is `audited associated_with:
:account`, so its creation is an `audits` row scoped to the account. Honest limitation: that audit row has no
`user`, because a super admin is not an `AccountUser` and `Audited` has nobody to attribute it to — the super
admin's identity is in the operator log, not in `audits`. Every tenant-side case change is audited the usual
way, with the acting agent attributed.

**42. Are audit payloads secret-safe?**
Yes. `Support::Ticket` is audited `except: [:description]` — a customer may have dictated something into a
description that should not exist in a second copy — and every other audited column is an id, an enum value, a
count or a timestamp. `spec/requests/operations/p9_hardening_spec.rb` asserts the audit row's
`audited_changes` has no `description` key and does not contain the planted text. `Operations::Signal` is not
audited at all: it is itself the record of what happened.

---

## Performance

**43. What indexes were added?**
Eight on `support_tickets`, two on `support_ticket_events`, four on `operations_signals`:

```
support_tickets        (account_id, reference_number) UNIQUE
                       (account_id, last_activity_at DESC)
                       (account_id, assignee_id, status)
                       (account_id, team_id, status)
                       (conversation_id)
                       (contact_id)
                       (account_id, resolution_due_at)      partial, open + governed + unbreached
                       (account_id, first_response_due_at)  partial, open + governed + unanswered
support_ticket_events  (support_ticket_id, created_at)
                       (account_id, created_at)
operations_signals     COALESCE(account_id,0), source, COALESCE(subject_type,''), COALESCE(subject_id,0), signal
                         UNIQUE, partial WHERE resolved_at IS NULL
                       (last_seen_at DESC)         partial, open
                       (account_id, last_seen_at DESC) partial, open
                       (support_ticket_id)         partial, present
```

**44. Why?**
Each is a query shape the product issues, not a column someone might filter on. The reference index is identity
*and* the paste-a-reference lookup. The activity index is the default list ordering. The assignee and team
indexes are the My / Unassigned / Team views. The conversation and contact indexes are the two panels' reverse
lookups. The two partial indexes exist because the SLA sweep runs **on a schedule across every account**, so it
needs an index holding only rows it can ever match rather than relying on per-account indexes; the first also
serves the Overdue view. The signal identity index is not an optimisation at all — it is the **dedup
correctness constraint**, with `COALESCE` because NULLs are distinct in a unique index and an installation-wide
signal would otherwise insert a fresh row on every observation. Deliberately **not** added: `(account_id,
priority)`, `(account_id, updated_at)`, and `(account_id, status)` for the tab counts — the last of those was
built and measured and rejected.

**45. What EXPLAIN evidence supports them?**
`docs/p9/06-security-performance.md`, five passes, every one seeding inside a transaction that is rolled back,
with `ANALYZE` inside it and the row counts printed as zero afterwards. SQL taken from the **real services**
via `#to_sql`, so a plan cannot drift from the code. Headline results: **40 shapes, zero sequential scans** on
any P9 table at 100,200 cases / 300,600 events / 20,001 signals with the account holding 5%; slowest shape
6.456 ms, and that one is a fixture artefact whose realistic value is 0.842 ms. The evidence also **overturned
a design decision**: the original `(account_id, status, last_activity_at DESC)` cannot serve
`account_id = ? ORDER BY last_activity_at DESC LIMIT 25` because `status` sits between the equality column and
the sort column, measured at **39.997 ms → 0.057 ms** at 500,000 cases; the index was replaced, and the
replacement was itself measured against the worst case for it (an account with 150,000 cases of which 200 are
active and those the oldest) before the old one was dropped.

**46. Is ticket pagination bounded?**
Yes. Kaminari, default 25, **hard ceiling 100**, and a request above it is a **422 naming the maximum** rather
than a silent clamp — a silent clamp returns a page the caller will read as the answer to the question they
asked. History is 50 per page. Page 50 of a 100,200-case fixture is 0.326 ms; page 200 of a 500,000-case
fixture is 1.976 ms.

**47. Is operations issue feed bounded?**
Yes. `OperationsController::ISSUE_PAGE_SIZE = 50`, Kaminari, reading a partial index that holds only unresolved
rows: 0.081 ms over 20,001 signals of which 2,001 were open. The accounts page is `PER_PAGE = 25`, clamped to
100.

**48. Are there N+1 account-health queries?**
No, by construction. One page of accounts, then **one grouped query per component restricted to that page's
ids** — six queries, fixed whatever the page size. This was written deliberately against the existing Super
Admin accounts index, which pays two uncached `COUNT`s per row through `CountField` (40 queries for a page of
20). Measured at 1.104 ms. The issue feed and the computed signals are likewise one query each, and the
computed block is cached for 5 minutes.

---

## P8 regression

**49. Do all P8 tests remain green?**
Yes — **9307 examples, 0 failures, 70 pending** on the release build, against P8's clean baseline of 9058 / 0 /
70; and **490 JS files, 5287 tests, 0 failures**. P9 changed three
P8 specs, each because a P9 registration extended a list the spec asserts exactly: the account feature-flag map
(`spec/models/account_spec.rb`), the timeline category list
(`spec/services/contacts/activity_timeline_query_spec.rb`) and the analytics family list
(`spec/requests/analytics/analytics_meta_spec.rb`). On the frontend the same thing happened twice:
`constants/specs/permissions.spec.js` and `ContactActivity.spec.js`. Plus
`components-next/analytics/specs/AnalyticsMetaNote.spec.js`, whose warning-copy expectation changed when P9.8
localized that line. **No P8 behavioural assertion was changed or removed.**

**50. Did any P9 change P8 metric semantics?**
No. No P8 metric definition, bucket rule, filter, rollup decision, timezone rule or warning condition was
touched. P9 **added** to P8's registry: a seventh family (`tickets`) with its own metrics, and three entries in
`CURRENT_STATE_METRICS` — which is collected *from* the families rather than written out, so adding a family
cannot leave it stale. One cosmetic change crosses into P8: the shared partial-response banner now renders its
scope and reason as localized words instead of raw snake_case tokens, which changes how P8's own two warnings
*read* and not whether they appear or what they mean.

**51. Is P8 Analytics still feature-gated?**
Yes, unchanged: every analytics route carries `featureFlag: FEATURE_FLAGS.REPORTS` and the server-side
authorization is untouched. The new Support cases screen carries the same `reports` gate as its six siblings,
and its sidebar entry additionally requires `lynomia_support_tickets` so an account without the support module
is not offered a case-analytics screen.

**52. Is Contact Activity still tenant-safe?**
Yes, and P9.4's change to it was made in the direction that keeps it so. The adapter base now takes one
`Visibility` value instead of three keyword arguments, carrying the caller, the permission-filtered
conversations and the visible inbox ids — the same filter the contact's attachment list already uses. The new
`tickets` adapter cannot use either of those, because a case may have no inbox and no conversation, so it asks
`Support::TicketPolicy::Scope.for` — *the same rule the case list uses*, by construction, so the two cannot
drift. It never emits a note body: an internal note is written for colleagues working the case, and a timeline
is a wider audience. Both are asserted in the isolation spec.

---

## Enterprise

**53. Is enterprise/ still absent?**
Yes. `ls enterprise` → *No such file or directory*. P9 created no file under it and no file that would be
overridden by one.

**54. Are extensions still ["custom"]?**
Yes. `ChatwootApp.extensions` → `["custom"]`.

**55. Is enterprise? still false?**
Yes. `ChatwootApp.enterprise?` → `false`, `ChatwootApp.custom?` → `true`. The three mentions of "enterprise" in
P9 code are **comments** explaining why a table is free to reuse and where the removed SLA engine used to live
(`custom/app/models/support/sla_policy.rb`, `custom/app/services/support/tickets/sla_clock.rb`, plus a
pre-existing comment in `custom/app/models/custom/account.rb`). No Enterprise SLA, audit or report code was
reintroduced; the SLA clock, sweep and policy model are written from the OSS business-hours helper and the
existing Lynomia architecture. **The final provenance audit is P-FINAL's work and was not started in P9.**

---

## Release

**56. What automated tests passed?**
All five gates, run sequentially on a clean untouched tree (`git status --porcelain` empty before and after):

| Gate | Result |
| --- | --- |
| RuboCop | 2842 files inspected, **no offenses** |
| ESLint (`eslint app/**/*.{js,vue}`) | **0 errors**, 478 warnings (baseline at `4e8e3d0b` measured first-hand: 0 errors, 464 — so **+14, all `no-dynamic-keys`**) |
| Production build (`vite build`) | **✓ built in 1m 20s** |
| Full JS suite | **490 files, 5287 tests, 0 failures** |
| Full Ruby suite | **9307 examples, 0 failures, 70 pending** (37 min 07 s) |

P8's own clean baseline was 9058 examples / 0 failures / 70 pending, so P9 adds **249 Ruby examples** and the
pending count is unchanged. P9 added 22 Ruby spec files and 10 JS spec files and modified 6 existing specs
(3 Ruby, 3 JS), every one of them an exact-list assertion that a P9 registration lengthened.

**57. What simulated UAT passed?**
`docs/p9/07-uat-runbook.md` §9, 41 items with every one classified. Simulated-only items: the workspace's
URL-as-state behaviour, the conversation panel's prefill, the Arabic/RTL sweep (192/192 key parity in both
locales), the Operations figures cross-check, and the measured plans behind the accounts page.

**58. What real UAT remains?**
All 41 items are **PENDING REAL UAT**, because this build has not been deployed. Four of them can *only* be
judged against the real installation and are marked as such: the Operations console's figures versus the real
sources (U24), the read-by-eye credential review of the three real console pages (U27), and the WhatsApp
delivery comparison (R4). **No item in this phase is a REAL DATA PASS, and none may be converted into one** —
every result so far came from factory records or a synthetic fixture.

**59. What production checks remain?**
P9's: enable `lynomia_support_tickets` on the pilot account; walk §1–§7 of the runbook; read the three console
pages for leakage by eye; confirm the SLA sweep is running on the `housekeeping` queue; confirm the two new
Rack::Attack throttles are active with `ENABLE_RACK_ATTACK` on. P8's nine, unchanged and still pending for the
same reason they were pending at the end of P8 — it was not deployed: the rollup read-only check, confirming
`reports` for the pilot account, the six-screen Analytics smoke, the Contact Activity Timeline smoke, the
coexistence-echo validation, the Meta failure-code validation, the comparison against real Reports history, the
read-by-eye leakage review, and the genuine-new-contact WhatsApp UAT (`order_delivered` / `en_US` / APPROVED),
**which must not be sent before the deployment**.

**60. Is combined P8 + P9 ready for controlled deployment?**
Yes, with the limitations in §X of the completion report recorded and accepted. The reasoning: P9 is additive —
three new tables, no change to any existing column, no destructive migration, and both migrations reversible and
schema-identical after a round trip (verified); every new surface is behind a feature flag that is **off by
default** and has no operator-reachable enable path other than a console call; the account-facing API is 404
until that flag is on; nothing in the phase calls a provider, changes a provider gate, touches Captain or
mutates Sidekiq; and the one new scheduled job is a bounded read over two partial indexes. The deployment
procedure is §AB of the completion report.

---

## Verdict

**PASS WITH KNOWN LIMITATIONS.**

Not a plain PASS, for one honest reason: **nothing in this phase has been proved against real data.** Every
result is automated or simulated, the full UAT is pending the deployment, and the limitations in §X of the
completion report — in-app notifications for case events, no automation event for cases, no case attachments,
one conversation per case, the tab-count cost at very large case volumes, and the Operations console's 5-minute
staleness and lack of history — are real and recorded rather than discovered later.

Not a NO-GO: no defect found in this phase is open. The three P9.8 found are fixed, tested and pushed.
