# Workflow and SLA

Two things that look like one feature and are not: the **status workflow**, which is a table of allowed moves,
and the **SLA clock**, which is arithmetic over business hours. Each is small on its own. What makes them worth
a document is the set of decisions that stop them lying.

---

## 1. The status workflow

Six statuses, four of them active (`open`, `in_progress`, `waiting_on_customer`, `waiting_on_internal`) and two
terminal (`resolved`, `closed`).

The allowed moves are a **table**, not an inference from the enum's order:

| From | To |
| --- | --- |
| any active | any other active, or either terminal |
| `resolved` | `closed`, or `open` |
| `closed` | `open` |
| anything | itself |

The product rules that encodes:

- **Movement between active states is not policed.** An agent picking work up, putting it down, or waiting on
  somebody is not a workflow to approve.
- **An agent may close a case outright** without resolving it first. A case raised by mistake does not need to
  be pretended-resolved on the way to being closed.
- **A terminal case reopens to `open`, never to something else.** Reopening to `in_progress` would claim
  somebody is already working it.
- **A no-op is allowed and is a no-op**, so an idempotent client retry does not 422.

Anything else is refused with **the attempted edge named and the allowed set listed**. The alternative — a
silent coercion to some "nearest legal" state — would make the case history a fiction, which is worse than an
error message.

The client mirrors the table so the status control offers only reachable states. That is a *usable control*,
not a second guard: the server remains the authority, its 422 is shown with the message it came with, and the
view then reloads the case so the control cannot keep displaying a value the server rejected.

### Lifecycle timestamps

`resolved_at` and `closed_at` are stamped on entering their state and **both cleared on reopen**. Moving
`resolved → closed` does *not* clear `resolved_at`: the case really was resolved at that time, and the pair is
how "resolved on Monday, closed on Friday" stays readable.

### One service, one transaction

`Support::Tickets::Update` does three things that must happen together: check the transition, move the SLA
clock, and write one history row per change. A controller assigning attributes directly would get none of them,
which is why there is a service and the controller does not touch `assign_attributes`.

---

## 2. Where the SLA came from

There is **no SLA engine in this fork to reuse**. Chatwoot's lived in `enterprise/`, which is permanently
absent (`ChatwootApp.extensions == ['custom']`), and `01-architecture.md` records what survived its removal:
the `sla_policies`, `applied_slas` and `sla_events` tables, a `conversations.sla_policy_id` column a jbuilder
still reads, the `sla` feature flag, and the entire Vue frontend for conversation SLAs in ~60 locales — with no
Ruby model, no service, no route and no router entry anywhere. A dormant half-feature.

Three decisions follow, and all three are about **not pretending**:

1. **Reuse the `sla_policies` table.** Its columns are exactly what a case policy needs — name, description,
   first-response threshold, resolution threshold, business-hours switch — so P9 adds no table for SLA
   configuration at all. Nothing else will ever claim those rows. None of the code here is derived from the
   engine that used to read them.
2. **Do not claim `/api/v1/accounts/:id/sla_policies`.** That is the path the surviving conversation-SLA
   frontend expects. Serving case-shaped data there would make a dormant UI appear to work. The endpoints live
   under `/support/` so the namespace says what the rows are for.
3. **Leave `next_response_time_threshold` unused.** A case has no "next response" concept, and inventing one to
   fill a column is the wrong way round. One unused nullable column, recorded here rather than hidden.

`applied_slas` and `sla_events` are **not** reused: `applied_slas.conversation_id` is `NOT NULL`, so they
cannot hold a case, and `support_tickets` carries its own five SLA timestamps instead of a join.

A policy with neither threshold set is **invalid**. Attaching one would make a case look governed when nothing
can ever be computed for it.

---

## 3. The clock

Five timestamps on the case itself: `first_response_due_at`, `resolution_due_at`, `first_responded_at`,
`first_response_breached_at`, `resolution_breached_at`, plus `sla_paused_at` and `sla_paused_seconds`.

### Targets are measured from now, never backwards

`SlaClock#apply` runs when a policy is attached — at create if one was given, otherwise the moment it is set —
and measures from **that instant**, not from the case's `created_at`. A due time invented backwards is a
commitment nobody made, and would mark a case breached the moment a policy was first attached to it.

This is also the honest reason there is no attainment percentage in Analytics (`02-support-tickets.md` §7): the
population of governed cases begins when policies start being attached, so any rate over a longer range divides
two different populations.

### Pausing

`waiting_on_customer` is the one status that stops the clock — the only state where the delay is not ours.
`waiting_on_internal` does **not** pause it, because waiting on ourselves is our own delay.

Resuming moves *both* due times forward by exactly as long as the clock was stopped and adds that to
`sla_paused_seconds`, so the pause is visible in the record rather than inferred from a gap in the history.

### Reopening

A reopen gets a **new resolution target from the reopen instant** and clears `resolution_breached_at`, because
the new target has its own outcome. A first response that already happened stays satisfied — it did happen.

### Business hours

Business hours are **inbox-scoped**, because that is the scope the calculator has: `ReportingEventHelper` sets
`WorkingHours::Config` from `inbox.working_hours` and `inbox.timezone` (the `working_hours` gem, already in the
Gemfile, already used by the OSS reporting helpers). P9 does not write a second day-map or a second
"closed all day" rule; it includes the helper and uses it.

So a case with **no inbox** uses calendar time even under a business-hours policy, and
`business_hours_applicable?` returns false for it. The `sla_applied` history event records that flag, and the
API exposes it, so the UI can say which kind of clock a case is on instead of quietly pretending.

**No holidays.** There is no holiday concept anywhere in this codebase — not in the gem configuration, not in
`WorkingHour`, not in the OSS reporting helpers. Adding one for cases alone would make case SLAs and
conversation reporting disagree about what a working day is.

---

## 4. The sweep

`Support::SlaSweepJob`, every 5 minutes on the `housekeeping` queue (`config/schedule.yml`). Two bounded scopes,
each with its own partial index so this stays a read over the working set rather than a scan of every case ever
opened:

| Scope | Predicate |
| --- | --- |
| awaiting first response | active, governed, no first response recorded, no first-response breach recorded |
| awaiting resolution | active, governed, no resolution breach recorded, resolution due time passed |

Batched at 500.

### Comparison is message time against due time, never sweep time

A sweep that runs late must not turn a met target into a breach. So the sweeper compares the *detected response
instant* with the *due instant*, and only writes a first-response breach when no response exists at all and the
due time has passed.

### A breach is written once and never un-written

The case really did pass its target; clearing that later would make the history a fiction. Reopening is the one
thing that clears a resolution breach, and only because the reopened case has a new target with its own outcome.

### Detecting the first response needs no new instrumentation

```ruby
Message.where(conversation_id:, message_type: :outgoing, private: false)
       .where(created_at: ticket.created_at..).order(:created_at).limit(1).pick(:created_at)
```

The first outgoing, non-private message in the linked conversation at or after the case was opened. No hook on
the message path, no new column, no new event.

`conversations.first_reply_created_at` is deliberately **not** reused: it records the first reply in the whole
thread, which may be weeks before the case was raised.

A case with **no conversation has no first response to detect**. That is a real product limitation rather than a
gap to fill with a guess — there is no channel on which a reply could have been sent — and the first-response
target on such a case simply never resolves either way.

### A paused case is not swept

`sla_paused?` short-circuits both sweeps. The clock being stopped is the whole point of stopping it.

---

## 5. Overdue is not breached

Two states, drawn differently, and the distinction is load-bearing:

| | |
| --- | --- |
| **overdue** | a resolution target in the past, on a case still active, that the sweep has not turned into a breach yet |
| **breached** | a miss the sweep has already recorded |

P9.8 found the server scope counting a breached case under *both* labels while the UI showed it under one
(`06-security-performance.md` §2.4). The scope now excludes recorded breaches, which also made the partial index
built for it usable for the first time — a partial index cannot be used by a query that does not ask for its
predicate.

---

## 6. What was deferred, with the reason

| Deferred | Why |
| --- | --- |
| In-app notifications for SLA breaches | `Notification` is structurally conversation-only: it dereferences `conversation` at six points, and its `primary_actor` has no case shape. Making it polymorphic over cases is a change to a core OSS model used by every existing notification type, which is not a sub-phase of P9. The breach is in the case history, the Analytics counts and the Operations console. |
| A `support_case_*` automation event | 14 files in the OSS automation registry, plus a condition and action vocabulary that only makes sense once cases have been used in anger. |
| Reviving conversation SLAs | A separate product decision about a different object, with a dormant UI already written for it. P9 deliberately does not claim its API path so that decision stays open. |
| `next_response` targets | No product concept to measure. |
| Holidays | See §3. |
