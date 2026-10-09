# P9 FINAL COMPLETION REPORT

**Branch** `claude/p9-support-operations-center`, based on the completed P8 head `4e8e3d0b`
**Head** the commit that adds this report. The last **code** commit is `7afc61de`; everything after it is documentation.
**Production** still `lynomia-custom` @ `b03ea43df6abf18cb9c4e5d6a9271ba040b689f4` — **neither P8 nor P9 is deployed**
**Verdict** **PASS WITH KNOWN LIMITATIONS**

---

## A. Executive summary

P9 adds two things the product did not have: a **support case** — a unit of work the business owes somebody,
which can exist with no customer and no channel — and an **Operations Center**, a Super Admin view of what is
broken across the installation. It is 7 commits, 165 files, +13,511 / −43 lines, three new tables and **no change
to any existing column**.

The architecture question the brief asked to settle first was settled by one schema fact rather than by
preference: `conversations.inbox_id` is `NOT NULL` and `contact_id`, though nullable in the column, is validated
present and dereferenced in `before_create`. An internal operational case has neither, so it cannot be a
Conversation without relaxing a `NOT NULL` on the most-read table in the product. So option (B): a thin
`support_tickets` table beside `Conversation`, with **nothing about messaging reimplemented** — no message
table, no attachment path, no channel, no delivery status, no conversation status, no notification type.

The SLA was the same kind of question. Chatwoot's SLA engine lived in `enterprise/`, which is permanently
absent, and what its removal left behind is a *dormant half-feature*: three empty tables, a column a jbuilder
still reads, a premium feature flag with no operator-reachable enable path, and the entire conversation-SLA Vue
frontend in ~60 locales with no Ruby behind it and no router entry. P9 reuses the `sla_policies` table and the
OSS business-hours calculator, writes the clock and the sweep itself, and deliberately **does not claim the API
path the dormant frontend expects**, so that product decision stays open instead of appearing to have been made.

Three defects were found in this phase and fixed in it, none of them visible by reading the code:

1. The index built for the default list **could not serve the default list** — `status` sat between the equality
   column and the sort column. 39.997 ms → 0.057 ms at 500,000 cases.
2. `Support::Ticket.overdue` counted cases already recorded as breached, contradicting the product's own
   definition *and* making its purpose-built partial index unusable. 23.697 ms → 12.826 ms.
3. `Operations::SignalRecorder` bounded the **length** of a failure reason but not its **content**, so an IMAP
   server answering a failed `LOGIN` with the password it was given stored it verbatim, rendered it in the
   console, and copied it into a support case.

The third is why the verdict is not a plain PASS in spirit as well as in letter: a security property was assumed
to hold and did not, and it was caught by a test written specifically to try to break it rather than by review.

The verdict is **PASS WITH KNOWN LIMITATIONS** because **nothing in this phase has been proved against real
data.** Production holds zero support cases and zero operations signals. Every result is automated or simulated;
the whole 41-item UAT is pending the combined deployment.

---

## B. Discovery conclusions

An 18-agent adversarial read of the repository, then independent verification of every decisive claim. Four of
five verifiers came back PARTLY-WRONG or REFUTED against the readers and a critic found six internal
contradictions; all of it was corrected before any code was written, and the five facts the architecture turns
on were re-checked by hand. `docs/p9/00-discovery.md`.

| What the brief asked | What the repository actually said |
| --- | --- |
| Is a ticket engine needed? | Yes, and narrowly. `conversations.inbox_id NOT NULL` (`db/schema.rb:1024`), validated (`app/models/conversation.rb:77`); `contact_id` nullable in the column but validated present (`:78`) and dereferenced in `before_create` (`:308`, `:312`). An internal case has neither. |
| Is there an SLA to reuse? | Half of one. `sla_policies`, `applied_slas`, `sla_events` and `conversations.sla_policy_id` all exist; the whole conversation-SLA frontend survives in ~60 locales; `Notification` enum values 6/7/8 are `sla_missed_*`. There is **no Ruby model, service, route or router entry**, so none of it is reachable. |
| Is `premium: true` enforced in this fork? | Yes, properly. `BillingPlan.assignable_features` rejects premium features and `Billing::FeatureSync` never grants them, and `AccountDashboard::FORM_ATTRIBUTES` is `%i[name locale status]`, so no operator UI toggles a flag. A premium flag has no enable path at all. |
| How is channel health recorded? | Two Redis keys with **no TTL** and nothing in Postgres. "Every broken inbox, newest first" was not expressible, and a Redis flush turned a broken inbox green. |
| What happens to an IMAP inbox with a rotated password? | **One log line per poll.** No row, no counter, no Sentry event, and a *successful* Sidekiq job. Then the latch stops the polling, so the inbox goes quiet. This is the shape of the production incident on record for inbox 74. |
| Is there a polymorphic allow-list convention to copy? | No. Seven polymorphic declarations in the repository and **not one allow-list**. P9 had to establish the pattern rather than follow it. |
| Is there a Pundit layer in Super Admin? | No. `authenticate_super_admin!` is the only guard in the Administrate stack. P9 uses it and does not invent a second. |

---

## C. Final support-ticket architecture

Option **(B)**: a lightweight case layer linked to Conversation.

```
support_tickets          28 columns, 8 indexes   the case itself
support_ticket_events     8 columns, 2 indexes   its history AND its internal notes
sla_policies                       (reused)      targets, a table the OSS schema already shipped
```

**Canonical in `Conversation`** — messages and bodies, attachments, private notes to a customer thread,
conversation status, conversation assignment and team routing, inbox and channel, contact identity and
`contact_inboxes`, delivery and read status, typing and presence, unread counts, every existing notification
type, conversation labels, `first_reply_created_at`, the OSS reporting events.

**Canonical in `Support::Ticket`** — the per-account reference, the case's title/description/category, case
status and its transition table, case priority, the case's own assignee and team, the SLA policy link and all
seven SLA timestamps, the typed queryable history, `resolved_at`/`closed_at`, and the polymorphic `source`.

Every link is nullable with `on_delete: :nullify`, except `account_id` which is `NOT NULL` and cascades. The
three cases that matter:

| | |
| --- | --- |
| customer problem | contact + conversation + inbox all set |
| internal operational task | **none of them set** — the case a Conversation cannot represent |
| a case from an operational issue | `source_type: 'Operations::Signal'`, account set, no customer |

### Reference numbering

An advisory lock plus `MAX + 1`, inside the creating transaction. The alternative was copying
`Conversation#display_id`'s per-account Postgres sequence and its two triggers, which would have added: a second
named trigger on `accounts`; a backfill creating a sequence for every existing account (the sequences are **not
in `db/schema.rb`**, so a fresh schema load has none and the first insert raises); a line in
`Account#remove_account_sequences` or every account deletion leaks one; and a post-create re-fetch. For an
object a human creates a few times an hour, the lock is the smaller correct answer.

---

## D. Ticket features

Reference, title (≤255), description (≤10,000, excluded from the audit trail), ten categories, six statuses,
four priorities matching `Conversation`'s scale exactly, the account's existing labels through `Labelable`, six
optional links, an allow-listed polymorphic source, a typed history with internal notes, and five SLA
timestamps plus a pause ledger.

Nine endpoints under `/api/v1/accounts/:account_id/support/`, all behind the `lynomia_support_tickets` account
feature, which answers **404 when off** — the module does not exist for that account, and 403 would tell a
caller what it could have if it paid.

**What a client may never write**, ignored rather than rejected and asserted field by field in a spec:
`account_id`, `reference_number`, `created_by_id`, `source_type`, `source_id`, all seven SLA timestamps,
`sla_paused_seconds`, `resolved_at`, `closed_at`, `last_activity_at`. A note's `user_id` and `event_type` are
likewise inert.

Filters: status (plus the pseudo-statuses `active`/`terminal`), priority, category, assignee (plus `me` and
`unassigned`), team, contact, inbox, conversation, SLA state, free text, a created-at window in epoch seconds,
six sorts, and a page size capped at 100. **Nothing is silently dropped**: an unknown enum is a 422 naming the
allowed set, a foreign id is a 422 naming the filter, an oversized page is a 422 naming the maximum. An empty
page would read as an answer.

---

## E. Ticket workflow and status model

| From | To |
| --- | --- |
| any active | any other active, or either terminal |
| `resolved` | `closed`, `open` |
| `closed` | `open` |
| anything | itself (a no-op, so a client retry does not 422) |

Movement between active states is not policed; an agent may close a case without resolving it; a terminal case
reopens only to `open`. A refused edge is a 422 naming the edge and the allowed set — a silent coercion to some
"nearest legal" state would make the history a fiction.

Reopening clears both lifecycle stamps and writes `reopened`; `resolved → closed` keeps `resolved_at`, because
"resolved Monday, closed Friday" must stay readable. Three status outcomes get their own event names so the
trail reads as a story rather than as six identical `status_changed` rows.

All of it in one service, one transaction, with the SLA side effects and the history write — a controller
assigning attributes directly would get none of them.

---

## F. SLA implementation

**Reused**: the `sla_policies` table (never held a row in this fork; reusing it means P9 adds no table for SLA
configuration at all) and the business-hours calculator — `ReportingEventHelper` plus the `working_hours` gem,
with the `WorkingHour` rows an inbox already has. **Written here**: `Support::SlaPolicy`,
`Support::Tickets::SlaClock`, `Support::Tickets::SlaSweeper`, `Support::Tickets::FirstResponseDetector`,
`Support::SlaSweepJob`, and the API. **Not reused**: `applied_slas` and `sla_events`
(`applied_slas.conversation_id` is `NOT NULL`, so they cannot hold a case), and the `/sla_policies` API path.

| | |
| --- | --- |
| starts | when a policy is attached, measured **from that instant** — never backwards from `created_at`, because a due time invented backwards is a commitment nobody made |
| pauses | `waiting_on_customer` only. `waiting_on_internal` does not: waiting on ourselves is our own delay. |
| resumes | both due times move forward by exactly the paused duration, and the total is recorded so the pause is visible rather than inferred |
| first response | the first outgoing non-private message in the linked conversation at or after the case opened — one indexed query, no hook, no new column. `conversations.first_reply_created_at` is deliberately not reused: it records the first reply in the whole thread, possibly weeks earlier. |
| ends | a terminal status, or the sweep recording a breach |
| on reopen | a new resolution target from the reopen instant; `resolution_breached_at` cleared; a first response that happened stays satisfied |
| business hours | **inbox-scoped**, because that is the scope the calculator has. A case with no inbox runs on calendar time and the API says so. |
| holidays | none, anywhere in this codebase. Adding them for cases alone would make case SLAs and conversation reporting disagree about a working day. |

The sweep runs every 5 minutes on `housekeeping`, batched at 500, over two partial indexes. It compares
**message time against due time, never sweep time**, so a late sweep cannot turn a met target into a breach. A
breach is written once and never un-written.

A case with no conversation has no first response to detect. That is a real product limitation — there is no
channel on which a reply could have been sent — not a gap filled with a guess.

---

## G. Ticket UI

`Support` in the sidebar → one workspace whose **URL is its entire state**: six saved views (all, mine,
unassigned, overdue, resolved, closed), every filter, the sort and the page are query parameters, and one
watcher on `route.query` refetches. Nothing holds a second copy, so the list cannot disagree with the address
bar and any view is a link somebody can send. Two guards on every request: the shared abortable-request helper
cancels a superseded request on the wire, and a fetch-id discards a response that had already arrived before
its cancellation landed.

11 components in `components-next/SupportTickets/`, 3 pages, a settings page and dialog for SLA targets, and
`AnalyticsTickets.vue`. Built from the existing design system — `BaseTable`, `PaginationFooter`,
`AccordionItem`, `TabBar`, `DurationInput`, `Label` — with no new primitives and, per the house rules, no custom
CSS, no scoped CSS and no inline styles.

The status control offers only reachable states, mirroring the server's table. That is a usable control, not a
second guard: the server remains the authority, its 422 is shown with the message it came with, and the view
then reloads the case so the control cannot keep displaying a value the server rejected.

**192 i18n keys, complete in both English and Arabic**, verified key-by-key in both directions. RTL throughout
via logical utilities.

Deliberately out of scope, each because it would have been a worse first version: no inbox dropdown in the
filter bar (seven menus plus a date range was the ceiling; the parameter is still read from the URL so the
panels' deep links work), labels read-only, no `sla_policy_id` control on the detail page (the policies endpoint
is administrator-only, so an agent's select would 403), and no `KeepAlive` (the list's state is in the URL, and
caching the detail page would show stale data when moving between two cases).

---

## H. Conversation and Contact integration

| Surface | What it does |
| --- | --- |
| conversation sidebar | the cases linked to this conversation, plus one button that opens a case **prefilled** with the conversation, contact and inbox — the agent has already answered "which customer" by being on this screen |
| contact → Cases tab | this contact's cases, beside P8's activity timeline. Beside and not inside: the timeline says what happened, this says what is still open and who owns it. |
| contact → Activity timeline | case history as timeline entries, through the **same** policy scope the case list uses |
| Analytics → Support cases | a seventh family in P8's registry |

The timeline adapter is the interesting one. P9.4 changed the shared adapter base to take one `Visibility`
value instead of three keyword arguments, carrying the caller, the permission-filtered conversations and the
visible inbox ids. The tickets adapter can use **neither** of the latter two — a case may have no inbox and no
conversation — so it asks `Support::TicketPolicy::Scope.for`, by construction the same rule as the list, so the
two cannot drift. It **never emits a note body**: an internal note is written for colleagues working the case,
and a timeline is a wider audience.

---

## I. Operations Center

Super Admin → **Operations**. Three pages and one button.

**The one rule: unknown is not healthy.** `SEVERITY_ORDER` ranks `unknown` above `healthy`, so a page with one
unreadable component cannot present itself as fine; a probe that raises reports `unknown` with a reason, never
`critical` and never green; an area with no source in this installation reports `absent` with a reason; an empty
signal store says "nothing has been recorded". A console that invents green is worse than no console, because an
operator starts trusting it.

**Probes**, live and cheap: one `SELECT 1`, one Redis `PING` plus `INFO`, the Sidekiq process set (critical at
zero), pending migrations (a warning — the code and the schema disagree), and release metadata. No shell
command, no provider call, no table scan.

**Computed signals**, one grouped query each, cached 5 minutes with a `computed_at` so the page says how old it
is: WhatsApp delivery failures, rejected templates, campaign failure **rates** (a rate, because ten failures out
of ten is a broken campaign and ten out of ten thousand is a Tuesday), abandoned automation episodes, failed
flow sessions, commerce stores needing reauthorization. Every threshold is a named constant with an environment
override, and each component's detail carries the threshold it used.

**The issue feed** from `operations_signals`, bounded at 50 per page over a partial index of unresolved rows.

A bug worth recording: the migrations probe first used `connection.migration_context`, which does not exist on
Rails 7.2. It raised, the rescue made it `unknown`, and the page looked plausible while reporting nothing — found
by reading the page. It is the reason `unknown` is a visible state with a reason attached rather than a blank.

---

## J. Account health

One page of 25 accounts, five independent component statuses each (the account, open signals, channels,
commerce, cases), and the row's badge is the worst of them.

**No score.** Not "87% healthy": a score is a number nobody can act on, and averaging an unknown into it turns
missing information into a reassuring digit.

**No N+1, by construction**: one page of accounts, then one grouped query per component restricted to that
page's ids — six queries, fixed whatever the page size. Written deliberately against the existing Super Admin
accounts index, which pays two uncached `COUNT`s per row through `CountField` (40 queries for a page of 20).
Measured at 1.104 ms over 20,001 signals.

---

## K. WhatsApp operations

Two durable facts the product was already writing, read installation-wide for the first time: failed outgoing
messages on WhatsApp inboxes over 24 hours (healthy / ≥25 / ≥250), and templates whose `meta_status` is
`REJECTED` with **no window**, because a rejection from last month is still a rejection until somebody edits the
template.

**Nothing calls Meta.** P9 adds no provider call, changes no WhatsApp gate, and does not touch the template
sync, the campaign path or the coexistence handling. The per-account detail stays where P8 put it, on
Analytics → WhatsApp, rather than being re-implemented here.

---

## L. Email and IMAP operations

The worst gap the discovery found, and the one with a production incident behind it.

Before P9, a plain-password IMAP inbox whose password had been rotated produced **one log line per poll** — no
Postgres row, no Redis counter, no Sentry event, and a *successful* Sidekiq job. The OAuth variant needed ten
consecutive failures before even the Redis flag latched, and once it latched `should_fetch_email?` stopped
polling, so the inbox went **quiet** rather than erroring and nothing durable said why.

`Custom::Inboxes::FetchImapEmailsJob` hooks `process_email_for_channel`, which is where the three outcomes are
already distinguishable (true / false / raise):

| Outcome | Recorded |
| --- | --- |
| success | `resolve_all` — a fixed inbox clears itself |
| `OAuth2::Error` | `authentication_failed`, critical |
| `Net::IMAP::NoResponseError` / `BadResponseError` | `authentication_failed`, critical |
| everything else (the connection errors in `ExceptionList::IMAP_EXCEPTIONS`) | `connection_failed`, warning — a different problem with a different fix |

**The raised error is re-raised unchanged**, so the OSS job's own rescues, logging and exception tracking behave
exactly as before. Nothing here reads or writes a credential.

`Custom::Reauthorizable` does the same for every channel that includes the concern, recording **only the two
state changes** rather than every error — the OSS concern already computes `state_changed`, so a channel failing
once a minute produces one row that gets incremented. The Redis flag is left exactly as it was; the row sits
beside it, so `reauthorization_required?` and the existing UI keep working unchanged. `AutomationRule` and
`Integrations::Hook` also include the concern and have no inbox; they are skipped rather than recorded against a
subject the console has no page for.

---

## M. Commerce and integration operations

Commerce needed **no new writer**: `commerce_stores.status` was already durable, so the console reads it. Stores
in `needs_reauth` or `disconnected` are critical — a store whose authorization is gone has stopped working
entirely.

**The Salla, Zid and Shopify provider gates are unchanged**, no provider is called, and no credential is read.
That matters for the deployment: nothing in P9 can change how a provider behaves.

Outbound webhooks gained a writer. `Custom::Webhooks::Trigger` records `delivery_failed` beside the existing
operator-log line, with the `Webhook` record as the subject where one can be identified
(`index_webhooks_on_account_id_and_url` is unique, so it is a single indexed lookup) so two broken endpoints in
one account stay two rows. Neither the URL nor the payload is stored: `detail` carries the host alone, the HTTP
status and the exception class.

---

## N. Queue and application health

`Lynomia::QueueHealthJob` already ran every 5 minutes and already logged. It now also records: **no workers**
(critical — nothing is running), a backlog above its threshold, and a dead set that grew since the last check.
A recovered backlog resolves itself.

Read-only throughout: no retry, no kill, no clearing the dead set, no enqueue. `Sidekiq::Web` is already mounted
at `/monitoring/sidekiq` behind the same super-admin guard and does all of that properly.

---

## O. Operational issue → support case bridge

`Operations::CaseBridge`, one button on the Issues page.

| | |
| --- | --- |
| priority | critical → `urgent`, warning → `high`, info → `medium` |
| category | `operational` |
| links | `support_tickets.source_type/source_id` and `operations_signals.support_ticket_id`, both ways |
| `created_by` | **nil** — a super admin is not an account user, and borrowing an account's administrator would put a name in the audit trail that did nothing |
| idempotent | while the linked case is active, the button surfaces *that* case; once it is closed, a recurrence opens a new one |
| installation-wide issue | **refused, with a reason.** `support_tickets.account_id` is `NOT NULL`, and a synthetic "operations account" would be a worse lie than an honest refusal — it would appear in every account list, count and report. |
| operator trail | `Lynomia::OperatorLog` line with the acting super admin's email, the signal and the case |

The case inherits the signal's sanitization for free, because it is built from the stored row rather than from a
raw error.

---

## P. Security and authorization

| Surface | Boundary |
| --- | --- |
| `support/tickets`, `support/.../events` | feature gate (404 when off) → Pundit `Support::TicketPolicy` → `Scope`: administrator or `support_ticket_manage` ⇒ the account; otherwise assignee, team, or creator |
| `support/sla_policies` | feature gate → `check_admin_authorization?` — an account-wide commitment follows the administrator boundary, not the per-case one |
| `analytics/tickets` | the existing `reports` gate and analytics authorization, unchanged |
| the timeline's `tickets` category | `Support::TicketPolicy::Scope.for` — the same rule as the list, by construction |
| `super_admin/operations` | `authenticate_super_admin!`, the only guard the Administrate stack has, proved against an unauthenticated caller, a tenant administrator and a tenant agent, on all three pages and the one mutation |

**Cross-tenant**: every incoming id is resolved through `Current.account` at the controller — a foreign id is a
**404 before any write** — with the model's own validation as the net under it, and user links checked through
`AccountUser` membership rather than a column comparison. A **filter** id from another account is a 422 naming
the filter, never an empty page. A case the caller may not see is a **404, not 403**, because 403 confirms it
exists. Proved by 24 examples against a **mirrored** two-account fixture, same data shape in both — including
the same case reference — so a missing predicate shows up as a borrowed record rather than as nothing.

**Secrets**: the case serializer carries ids, enum values, timestamps, counts and the contact's display name,
with the exact key list pinned in a spec. The signal table is constrained at its single writer: `reason` has the
subject's own secrets removed **by exact value** plus URL userinfo and credential-named `key=value` pairs
removed by pattern, whitespace collapsed, bounded at 500 characters; `detail` accepts only 24 allow-listed keys
holding scalar, whitespace-free values. Nothing is matched on entropy or length — an entropy rule would redact
the order ids and `wamid`s an operator needs while still missing a short password.

**Polymorphism**: `source_type` is allow-listed to `%w[Operations::Signal]`, is not in the permitted params at
all, and the spec proves `'User'` is refused. The repository has seven polymorphic declarations and had no
allow-list anywhere, so this is a pattern P9 established rather than followed.

**Audit**: `Support::Ticket` is `audited associated_with: :account, except: [:description]`. The one Super Admin
mutation leaves an operator-log line with the acting super admin's email; the `audits` row for the case it
creates has no `user`, because a super admin is not an `AccountUser` and `Audited` has nobody to attribute it to.
That is a stated limitation, not a silent one.

**Rate limits**: `support/*` at 300/min and `analytics/*` at 120/min, both keyed per **user within the account**
the way the existing reports throttle is — keying per account alone would let one agent's refresh loop throttle
their colleagues. The analytics one closes a pre-existing gap: no analytics path was throttled before, including
the six families P8 shipped.

---

## Q. Database and schema changes

Two migrations, both in `custom/db/migrate/`, both reversible, and the schema verified identical after a full
rollback and re-migrate round trip.

```
20261009100000_create_support_tickets      support_tickets (28 cols, 8 indexes)
                                           support_ticket_events (8 cols, 2 indexes)
20261009100100_create_operations_signals   operations_signals (15 cols, 4 indexes)
```

**No existing table is altered.** The only line removed from `db/schema.rb` across the whole phase is the
version stamp. No column is dropped, renamed or retyped; no data is backfilled; no destructive statement exists
in either migration. `operations_signals.account_id` is nullable on purpose — some problems belong to the
installation rather than to a tenant.

Foreign keys: `account_id` cascades, every optional link nullifies, so deleting a conversation, a contact or an
SLA policy cannot take a case's history with it.

One constraint is correctness rather than performance:

```sql
CREATE UNIQUE INDEX index_operations_signals_on_open_identity
  ON operations_signals (COALESCE(account_id, 0), source, COALESCE(subject_type, ''),
                         COALESCE(subject_id, 0), signal)
  WHERE resolved_at IS NULL;
```

`COALESCE` because NULLs are distinct in a unique index, so without it an installation-wide signal would insert
a fresh row on every observation. `WHERE resolved_at IS NULL` so the same problem recurring after it was fixed is
a **new** row with its own `first_seen_at`. It is also the concurrency answer: two workers racing on the insert,
the loser gets `RecordNotUnique`, the recorder retries as an increment. A P9.8 benchmark fixture tripped this
index by accident, which was an unplanned proof that it works.

Also: one new feature flag `lynomia_support_tickets` (`enabled: false`, `column: feature_flags_ext_1`, appended
— the `feature_flags` column is full at 63/63 and the order of entries is never changed), and one new entry in
`CustomRole::PERMISSIONS`.

---

## R. Indexes and EXPLAIN evidence

Full plans in `docs/p9/06-security-performance.md`. Five passes, each seeding inside **one transaction that is
rolled back**, with `ANALYZE` inside it so the planner has real statistics, and the row counts printed as zero
afterwards — the proof that no benchmark fixture leaked into the test database. SQL taken from the **real
services** via `#to_sql`, so a plan cannot drift from the code it describes.

```
support_tickets    (account_id, reference_number) UNIQUE        identity + paste-a-reference lookup
                   (account_id, last_activity_at DESC)          the default list ordering
                   (account_id, assignee_id, status)            My / Unassigned
                   (account_id, team_id, status)                Team
                   (conversation_id)                            the conversation panel
                   (contact_id)                                 Contact 360
                   (account_id, resolution_due_at)   partial    the resolution sweep + the Overdue view
                   (account_id, first_response_due_at) partial  the first-response sweep
```

**Headline: 40 shapes, zero sequential scans** on any P9 table at 100,200 cases / 300,600 events / 20,001
signals with the target account holding 5%. Slowest shape 6.456 ms, and that one is a fixture artefact whose
realistic value is 0.842 ms.

The evidence **overturned a design decision**, which is the point of taking it. The table first carried
`(account_id, status, last_activity_at DESC)`, on the reasoning that the list is always status-filtered and
always sorted by activity. That is wrong about how a btree is read: with `status` between the equality column
and the sort column the index cannot produce that order at all.

| 500,000 cases, target 30% | status-leading | `(account_id, last_activity_at DESC)` |
| --- | --- | --- |
| default list | 39.997 ms, parallel seq scan + top-N sort | **0.057 ms**, ordered index scan |
| status=active | 25.355 ms | **0.074 ms** |
| page 200 | 40.763 ms | **1.976 ms** |

It was **replaced**, not supplemented: measured against the worst case for the new index — an account with
150,000 cases of which only 200 are active and those the oldest — the planner picks the activity index whether
or not the old one is present, so the old one would have bought a plan the planner does not choose. The honest
cost is 20.3 ms instead of 17.8 ms for `status=active` on that pathological shape.

Two candidates were built, measured and **rejected**: `(account_id, status)` for the tab counts (28.306 → 24.623
ms for 3.4 MB — not worth an index), and rewriting the signal recorder's lookup to match the COALESCE expression
index (0.058 → 0.055 ms at a realistic open-signal count).

---

## S. Performance

| | |
| --- | --- |
| list page, 100,200 cases | 0.052 ms |
| list page, 500,000 cases, account holding 30% | 0.057 ms |
| page 200 of 500,000 | 1.976 ms |
| title search | 0.047 ms |
| tab counts (one grouped query + two counts) | 1.330 ms at 100k; **36.965 ms** at 500k with one account holding 150,000 |
| a case's history, page 1 | 0.036 ms |
| contact timeline tickets adapter | 0.680 ms |
| analytics, slowest shape (day series) | 3.110 ms |
| SLA sweep batch of 500, installation-wide | 0.842 ms with realistic SLA linkage |
| operations issue feed, 50 rows over 20,001 signals | 0.081 ms |
| operations account health, 25 accounts | 1.104 ms |

Bounded everywhere: list 25/100, history 50, issue feed 50, accounts 25/100, sweep batch 500. An oversized page
request is a 422 naming the maximum rather than a silent clamp.

The tab-count figure at half a million cases is the **largest remaining cost and is recorded rather than
pre-solved**: production holds zero support cases today, the index candidate that would address it was measured
and did not earn its space, and caching is named in `06-security-performance.md` §2.6 as the first thing to
revisit if it ever matters.

Caching added: exactly one key, `operations:computed_signals`, 5 minutes, carrying a `computed_at` so the page
states its own staleness. No tenant-facing response is cached.

---

## T. Tests, with exact results

Every gate below was run **sequentially, on a clean untouched tree** (`git status --porcelain` empty before and
after), on the release head. Sequentially because P8 established why: `config/environments/test.rb` sets
`cache_classes = false`, so editing a watched file during a run triggers a reload that makes `described_class`
and frozen class references stale — P8 lost an afternoon to 76 phantom failures that way. A concurrent
`vite build` is the same hazard from the other side: it rewrites `public/vite-test/.vite/manifest.json`, and a
super-admin page spec that reads it mid-write renders a 500.

| Gate | Result |
| --- | --- |
| **RuboCop** | `2842 files inspected, no offenses detected` |
| **ESLint** (`eslint app/**/*.{js,vue}`) | **0 errors**, 478 warnings |
| **Production build** (`vite build`) | **✓ built in 1m 20s** |
| **Full JS suite** (`vitest run`) | **490 files, 5287 tests, 0 failures** (248.76 s) |
| **Full Ruby suite** (`rspec`) | **9307 examples, 0 failures, 70 pending** (37 min 07 s) |

### The ESLint warnings, measured rather than asserted

The pre-P9 baseline was measured first-hand by checking `4e8e3d0b` out into a throwaway worktree and running the
same command there:

| | baseline `4e8e3d0b` | release head | delta |
| --- | --- | --- | --- |
| errors | 0 | 0 | — |
| `@intlify/vue-i18n/no-dynamic-keys` | 392 | 406 | **+14** |
| `@intlify/vue-i18n/no-raw-text` | 68 | 68 | — |
| `vue/no-root-v-if` | 4 | 4 | — |
| total warnings | 464 | 478 | +14 |

All 14 are `no-dynamic-keys`: 13 in the nine new `SupportTickets` components and 1 in the rewritten
analytics-warning line. They are the pattern the dashboard already uses 392 times to render an enum label —
`t(\`SUPPORT_TICKETS.ENUMS.STATUS.${value.toUpperCase()}\`)` — and the alternative is a hand-written switch per
enum. Neither of the other two rules gained a single warning, and no P9 file produces one.

### What P9 added to the suites

| | |
| --- | --- |
| New Ruby spec files | 22 — the model, the five services, the policy, the reference allocator, the SLA clock and sweeper, the status transition table, the operations signal and recorder, computed signals, the console, the two writers, the analytics metrics, the timeline adapter, and the two P9.8 files (24 mirrored isolation examples, 12 hardening examples) |
| New JS spec files | 10 — seven components, the composable, the helper, and the SLA dialog |
| Existing specs updated | 6, every one an exact-list assertion that a P9 registration lengthened: the account feature-flag map, the timeline category list, the analytics family list, the permissions list, the timeline filter list, and the meta-note warning copy. **No P8 behavioural assertion was changed or removed.** |

### Evidence that is not a test

- **EXPLAIN**, five passes, 40+ shapes, every fixture inside a rolled-back transaction with the post-rollback
  row counts printed as zero. `docs/p9/06-security-performance.md`.
- **Migration reversibility**: both migrations rolled back and re-applied, and `db/schema.rb` verified identical
  afterwards.
- **i18n parity**: 192 keys in `supportTickets.json`, compared key-by-key in both directions between `en` and
  `ar`, zero gaps; the additions to four shared locale files likewise present in both.

---

## U. Frontend coverage

| | |
| --- | --- |
| New | `api/supportTickets.js`, `constants/supportTickets.js`, `helper/supportTicketHelper.js`, `composables/useSupportTickets.js`, 11 components in `components-next/SupportTickets/`, `ContactCases.vue`, 3 workspace pages, 2 SLA settings files, `AnalyticsTickets.vue` |
| Wired | sidebar (3 entries, each flag-gated), 3 route files, `featureFlags.js`, `constants/permissions.js`, `constants/analytics.js`, `constants/contactActivity.js` (+16 case icons), `api/analytics.js`, `useUISettings.js`, `ContactPanel.vue`, `ContactManageView.vue` |
| i18n | `en/supportTickets.json` + `ar/supportTickets.json`, **192 keys each**, registered in both index files; plus additions to `analytics.json` (26 + the new warning-copy maps), `contact.json` (21), `settings.json` (4), `customRole.json` (1) — all in both locales |
| Specs | 10 new spec files; 3 existing specs extended where a P9 constant lengthened a list they assert exactly |

**Everything is flag-gated**, which is a change made during integration rather than as first written. The
frontend initially followed the house pattern for Lynomia features — an unconditional sidebar entry plus a
route-level flag — but `lynomia_commerce` and `lynomia_flow_builder` are also `enabled: false`, so that pattern
leaves a nav item that leads to a redirect. The Support leaf, the Analytics Tickets child and the Settings
Support group are now each wrapped in the flag, and the contact's Cases tab is filtered out of the tab list
rather than rendering an error the moment it is opened. The two pre-existing ungated entries are left as they
are and recorded here rather than changed under cover of P9.

One integration change worth naming because it removed work rather than adding it. The list was built to resolve
contact names client-side, one `GET /contacts/:id` per contact id per page — up to 25 requests for one page of
cases. The server now serializes `contact_name` and `Support::Tickets::Query` preloads
`:conversation, :contact, :taggings`, so a page of 25 costs **three extra queries server-side and zero extra
requests client-side**, and the composable that did the fan-out is gone. The contact's name tells a caller
nothing it did not already have: contacts are readable account-wide and the id was already in the payload.

The analytics partial-response banner also changed: it rendered the server's snake_case `scope` and `reason`
tokens straight into the sentence, so the new conditional SLA warning would have read "sla could not be
included: active_cases_without_a_policy." It now looks both up, in both locales, and falls back to the raw token
so a reason this build has no wording for is never a blank line. This improves P8's own two warnings as well.

---

## V. Documentation

`docs/p9/`, 2,900 lines across eight documents:

| | |
| --- | --- |
| `00-discovery.md` | the repository-wide inventory, the SLA periphery, the operational-signal durability table, the recommended architecture |
| `01-architecture.md` | the column table, the index justification, reference numbering, the status model, the SLA clock rules, `operations_signals`, and a deliberate non-goals table |
| `02-support-tickets.md` | what a case is, visibility, the API and what the server owns, the list, history, every surface, and the three absent analytics metrics |
| `03-sla-workflow.md` | the transition table, where the SLA came from, the clock, the sweep, overdue vs breached, and what was deferred with reasons |
| `04-operations-center.md` | the one rule, the three pages, the thresholds, the bridge, and what the console cannot tell you |
| `05-integration-health.md` | what was durable before P9, the signal table, the four writers, the credential rules, and what is still not durable |
| `06-security-performance.md` | every plan, the two rejected candidates, the three defects, and what this phase did not do |
| `07-uat-runbook.md` | 31 P9 checks, 10 P8 regression checks, a 41-row classified matrix, and the nine carried-forward P8 items |
| `P9_RELEASE_GATE.md` | the brief's 60 questions, verbatim, each answered with its evidence |

---

## W. Commits

Seven, on `claude/p9-support-operations-center`, based on `4e8e3d0b` (the completed P8 head, verified as an
ancestor). **P8's branch was not touched after the P9 branch was created.**

| | | |
| --- | --- | --- |
| `55e04ad8` | docs(p9): discovery and architecture | 2 files, +894 |
| `5ff52677` | feat(support): P9.1 + P9.2 support case foundation, workflow and SLA | 52 files, +2,843 |
| `f3f7921f` | feat(support): P9.4 cases in Customer 360 and in P8 analytics | 15 files, +667 −15 |
| `b443cff0` | feat(operations): P9.5–P9.7 Operations Center, provider health and support bridge | 35 files, +2,126 |
| `7c7a0c9a` | feat(support): P9.3 support case workspace, panels and SLA settings | 63 files, +5,998 −15 |
| `7afc61de` | fix(support): P9.8 index, scope and redaction defects found by measurement | 15 files, +1,005 −31 |
| `065188d7` | docs(p9): support cases, SLA, operations, integration health, UAT and the release gate | 6 files, +1,717 |

165 files, **+13,511 / −43**. All 43 deletions are lines replaced in place: 9 in the analytics meta-note
component (the warning line rewritten), 8 in the shared timeline adapter base (three keyword arguments replaced
by one `Visibility` value), and the rest single lines in locale files, exact-list assertions and registries that
P9 extended. **Nothing was removed from any existing feature.**

OSS files touched, and how: `app/models/concerns/reauthorizable.rb` and
`app/jobs/inboxes/fetch_imap_emails_job.rb` gain **one `prepend_mod_with` line each**, which is the extension
point the Chatwoot architecture already expects; `app/views/super_admin/application/_navigation.html.erb` gains
a nav item and a skip-list entry; `config/features.yml`, `config/routes.rb`, `config/routes/analytics.rb`,
`config/schedule.yml`, `config/locales/en.yml` and `config/initializers/rack_attack.rb` gain registrations;
`lib/custom_exceptions/tickets.rb` and the seven `app/views/super_admin/operations/*.erb` are new files in
locations the OSS stack requires them to be in. **No OSS logic was edited.**

---

## X. Known limitations

Each of these was decided during the phase, with the change-set it would have required, and is recorded here
rather than discovered later.

| Limitation | Why it stands |
| --- | --- |
| **No in-app notification for a case event** — no breach notification, no assignment notification | `Notification` is structurally conversation-only: it dereferences `conversation` at six points and its `primary_actor` has no case shape. Making it polymorphic over cases is a change to a core OSS model used by every existing notification type, which is not a sub-phase of P9. A breach is visible in the case history, in Analytics, and in the Operations console. |
| **No `support_case_*` automation event** | 14 files in the OSS automation registry, plus a condition and action vocabulary that only makes sense once cases have been used in anger. |
| **No attachments on a case** | Attachments are `Message`-shaped in this product. A case linked to a conversation already has them there; an internal case would need a new attachable, which is a schema change for a use the product has not yet had. |
| **One conversation per case** | `conversation_id` is a single column, not a join table. Two conversations about one problem is a real shape; it is also a join table, a UI for managing it, and a visibility question, and no evidence yet says it is common. |
| **No separate incident table** | `operations_signals` holds one row per distinct open problem with a recurrence count, not a time series. "Was this worse last week?" needs another table and a retention policy. |
| **No @mentions on an internal note** | Mentions are tied to the conversation mention pipeline and to notifications, which is the first row of this table. |
| **No holidays in the SLA calendar** | There is no holiday concept anywhere in this codebase. Adding one for cases alone would make case SLAs and conversation reporting disagree about what a working day is. |
| **Tab counts cost 36.965 ms at 500,000 cases** in one account | Measured, named, and left. The index candidate was built and did not earn its space; caching is the answer if it ever matters. Production holds zero cases today. |
| **The Operations console is up to 5 minutes stale and has no history** | Deliberate: the alternative is an expensive page an operator refreshes. The page states its own staleness. |
| **An `audits` row for a Super Admin case-open has no user** | A super admin is not an `AccountUser`, so `Audited` has nobody to attribute it to. The acting email is in the operator log instead. |
| **Nothing is proved against real data** | The reason for the verdict. See §Z. |

---

## Y. P8 regression status

P9 touched four things P8 owns: the contact activity timeline (a new category *and* a changed adapter
signature), the analytics family registry (a new family), the shared partial-response banner (its copy), and the
analytics API client.

| | |
| --- | --- |
| P8 behavioural assertions changed or removed | **none** |
| P8 metric definitions, bucket rules, filters, rollup decisions or timezone rules changed | **none** |
| P8 specs updated, and why | 3 Ruby: the account feature-flag map, the timeline category list, the analytics family list — each an exact-list assertion that a P9 registration lengthened. 3 JS: the permissions list, the timeline filter list, and the meta-note warning copy. |
| P8 feature gating | unchanged. Every analytics route still carries `featureFlag: REPORTS`; the new screen carries the same gate plus the support flag on its sidebar entry. |
| Contact Activity tenant safety | preserved and tightened — the adapter base now carries one `Visibility` value, and the new adapter asks the case policy rather than inventing a second rule. Note bodies are never emitted. |
| The one cosmetic cross-over | P8's own two warnings now read in words instead of snake_case tokens. |

The regression smoke to run on the deployed build is `07-uat-runbook.md` §8: all seven analytics screens, the
account-timezone check, the partial-response banner, WhatsApp, campaigns, automations, flows, commerce, the
contact timeline with every filter and a page-boundary walk, timeline permissions for a restricted agent, and
the agent-refusal check.

---

## Z. Pending combined production UAT

**41 items, every one PENDING REAL UAT.** `07-uat-runbook.md` §9 has the matrix with each item classified
AUTOMATED PASS / SIMULATED PASS / PENDING REAL UAT.

**No item in this phase is a REAL DATA PASS and none may be converted into one.** Every automated and simulated
result came from factory records or a synthetic fixture. Four items can only be judged against the real
installation: the Operations console's figures versus the real sources (U24), the read-by-eye credential review
of the three real console pages (U27), and the WhatsApp delivery comparison (R4).

### P8's nine, carried forward unchanged

Still pending for the reason they were pending at the end of P8 — it was not deployed:

1. production rollup read-only check;
2. confirm `reports` is enabled for the pilot account;
3. production smoke on the six Analytics screens;
4. Contact Activity Timeline smoke;
5. coexistence-echo validation against real echoes;
6. Meta failure-code validation against real failures;
7. comparison against the real Reports history;
8. the read-by-eye leakage review;
9. the genuine-new-contact WhatsApp UAT — template `order_delivered`, `en_US`, APPROVED. **Not sent during
   development, and not to be sent until the deployment.**

---

## AA. Release verdict

**PASS WITH KNOWN LIMITATIONS.**

Not **NO-GO**: no defect found in this phase is open. The three P9.8 found are fixed, tested and pushed. The
migrations are additive and reversible, no existing column changed, every new surface is behind a flag that is
off by default with no operator-reachable enable path, the account-facing API is 404 until that flag is on, and
nothing in the phase calls a provider, changes a provider gate, touches Captain or mutates Sidekiq.

Not a plain **PASS**, for two reasons stated plainly:

1. **Nothing is proved against real data.** Production holds zero support cases and zero operations signals, so
   there is no real-data evidence about this phase to have, and the whole UAT is pending.
2. **A security property was assumed and did not hold.** The failure-reason redaction gap was real, it was in
   code written in this phase, and it was caught by a test designed to break it rather than by review. It is
   fixed; the right conclusion is that the next phase's adversarial tests should come earlier, not that this one
   is clean.

---

## AB. Recommended combined deployment procedure

One deployment, both phases, on the existing tooling. `deployment/deploy.sh` already takes a backup before
touching the database, records the outgoing revision for a rollback to aim at, runs the migration with
`POSTGRES_STATEMENT_TIMEOUT=0`, runs `pnpm install --frozen-lockfile` and `pnpm build:sdk`, verifies the services
came back, and **stops without restarting on any failure** so the previous version keeps serving.

### Before the window

1. Merge this branch into `lynomia-custom`. It contains P8 (`4e8e3d0b` is an ancestor) and P9; deploying it
   deploys both.
2. Confirm the outgoing revision on the server is still `b03ea43d` and record it.
3. Confirm a `pg_dump` has somewhere to go and the disk has room for it.
4. Re-read `deployment/ROLLBACK.md`. The rollback for this release is ordinary: revert the application to
   `b03ea43d`. **Do not roll the schema back** — the three new tables are unreferenced by the old code and
   dropping them would destroy the only record of anything the new code wrote.

### The window

5. `bash deployment/deploy.sh`. The migration is two `CREATE TABLE`s and 14 index creations on empty tables, so
   it is fast and takes no lock on anything in use.
6. After the restart, with **every feature flag still off**, check that the installation is unchanged: open a
   conversation, send nothing, open Analytics on an account that already has `reports`, and confirm the six
   existing screens behave as before. P9's code is loaded but unreachable at this point, which is the property
   worth verifying first.
7. Open Super Admin → **Operations**. This needs no flag. Run U23–U27 of the runbook, and in particular read all
   three pages for a credential leak with your own eyes — that item cannot be automated away.

### Enabling, in this order

8. Enable `reports` on the pilot account if it is not already on, and run the P8 regression smoke
   (`07-uat-runbook.md` §8) plus P8's own nine pending items 1–8.
9. Only once §8 is green, enable `lynomia_support_tickets` on the **pilot account only** and run §1–§7 and §9 of
   the P9 runbook.
10. Grant `support_ticket_manage` to one role and verify the two agent boundaries (U16, U17).
11. Leave the flag off for every other account until the pilot has used it for long enough to have an opinion.

### Last, and separately

12. P8's ninth item, the genuine-new-contact WhatsApp UAT (`order_delivered` / `en_US` / APPROVED), is the only
    step that sends a real message. Run it on its own, deliberately, after everything above is green — not as
    part of a sweep.

### Watch for, in the first day

- `Support::SlaSweepJob` appearing every 5 minutes on the `housekeeping` queue and completing.
- `operations_signals` growing slowly and sensibly. A row count climbing fast means dedup is being defeated by
  a writer producing varying subjects, which is a bug worth looking at immediately.
- The two new Rack::Attack throttles not biting real use: `RATE_LIMIT_SUPPORT_TICKETS` (300/min) and
  `RATE_LIMIT_ANALYTICS` (120/min), both per user per account.
- The six `OPERATIONS_*` threshold variables, if the console's badges read as noise on real volumes.

### Rollback

Application revert to `b03ea43d`, schema left in place. The feature flags are the faster lever: turning
`lynomia_support_tickets` off makes every P9 tenant surface disappear and the API answer 404 again, without a
deployment. The Operations console is the one P9 surface a flag does not cover; it is Super Admin only and
read-only apart from one button.
