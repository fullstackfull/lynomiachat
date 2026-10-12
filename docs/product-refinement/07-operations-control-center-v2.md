# Operations Control Center V2

Product Refinement, workstreams F and G. Branch `claude/product-refinement`.

## 1. What V1 was, and what it could not do

P9 built the Operations Center (`docs/p9/04-operations-center.md`): a signal store, four honest health states,
a computed product-area block, an issue feed and a support-case bridge. Its central design rule is the one this
phase keeps and extends:

> `unknown != healthy`. Nothing in this console turns silence into green.

What it could not do was let an operator **work**. It answered "what is wrong" and then stopped:

| missing | consequence |
|---|---|
| no work list | 400 open signals in one flat feed, newest first, with no notion of "somebody is on it" |
| no acknowledgement | two operators pick up the same incident; neither knows |
| no suppression | a known-noisy signal stays at the top forever, so the feed gets ignored |
| no incident history | a recurring problem looks identical to a new one |
| no per-account view | diagnosing one account meant five unrelated Super Admin pages |
| no per-store commerce truth | `status` was the only answer (see `09-commerce-operations.md`) |
| no channel matrix | the five channel types this fork reports nothing about were invisible as a *class* |

## 2. The operator-handling layer

Two migrations, both additive:

- `20261012090000` — `acknowledged_at`, `acknowledged_by_id`, `suppressed_until`, `suppression_reason`,
  `suppressed_by_id` on `operations_signals`, plus two partial indexes
  (`index_operations_signals_on_unacknowledged`, `index_operations_signals_on_suppressed`).
- `20261012091000` — `operations_signal_events`: the stored half of the incident timeline.
- `20261012101000` — `index_operations_signals_on_recovered`, a partial descending index on
  `resolved_at IS NOT NULL`. Every pre-existing index on this table is partial on `resolved_at IS NULL`, so the
  Overview's "what recovered recently" read would otherwise scan the whole table and get slower with every
  incident ever closed.

**The signal's own two states are untouched.** A signal is open until something *observes* the thing working
again. Acknowledging resolves nothing; suppressing hides no fact. The handling layer is strictly a second
layer on top of the fact layer, and `Operations::Signal#handling_state` is **derived, never stored**: a stored
status would have to be swept when a suppression lapses, and a sweep that falls behind is exactly how a
silenced problem stays silent. Suppression is bounded by the clock, so a lapsed suppression returns to the
queue by itself.

### `Operations::SignalLifecycle` — the only writer of an operator decision

Separate from `Operations::SignalRecorder` on purpose. The recorder is built for **machine** observations: it
upserts on the open identity, raises severity monotonically, and swallows every error so a validation bug
cannot stop email arriving. All three are wrong for a human action — one deliberate act on one row, which must
fail loudly if it cannot be recorded and must never be coalesced with another operator's.

Every path through it:

- takes an **explicit actor** and refuses without one. Nothing infers `current_user`: the `audited` gem's
  Sweeper resolves an actor through Devise's `:user` scope while a Super Admin authenticates under
  `:super_admin`, so an inferred actor here would be nil or the wrong person (see `08-security-performance.md`);
- is idempotent — acknowledging twice is one acknowledgement and writes no second event;
- writes the incident timeline **and** an explicit `Custom::AuditLog` row with the real actor;
- bounds and sanitizes the operator's typed reason, reusing
  `Operations::SignalRecorder::CREDENTIAL_PATTERNS`.

Suppression requires **both** a deadline and a reason, and `MAX_SUPPRESSION` is 30 days: a suppression that
outlives the problem is how a real failure stays invisible, so there is no "forever".

### `Operations::AttentionQueue` — the work list

Eight views. The default, `needs_action`, is `needing_attention.unacknowledged.not_suppressed` — an open
problem that matters, that nobody has picked up, and that nobody has deliberately silenced.

The eight tab counts are **one** `select_one` with eight `COUNT(*) FILTER (WHERE …)` clauses, so a label can
never disagree with the list under it. Ordering is `severity DESC, last_seen_at ASC, id ASC`: worst first,
then oldest-untouched, which is the order a human triages in.

Search matches the signal and source names, the error code inside `detail`, the account name, and — for a
numeric term — the account id and subject id.

## 3. The incident detail and its timeline

`/super_admin/operations/signal?id=…` answers four questions in the order an operator asks them: what is it,
who does it affect, what has happened to it, what may I safely do.

`Operations::IncidentTimeline` merges two sources into one ordered story:

- **operator decisions** — stored rows (`acknowledged`, `suppressed`, `resumed`, `action_taken`,
  `case_created`), written only by `SignalLifecycle`;
- **machine observations** — `detected`, `recurred` and `resolved`, **derived** from the signal's own columns
  (`first_seen_at`, `occurrences` with `last_seen_at`, `resolved_at`).

Deriving the machine half is the important decision. Storing a `recurred` row per observation would write
1,440 rows a day for a channel failing every minute, to say exactly what the `occurrences` column already
says. So there is one `recurred` entry carrying the count, the table stays bounded, and the timeline is still
complete.

Every entry is marked `machine?`, and the UI renders the two with different markers, because that distinction
is the whole point: "it came back at 03:10" and "somebody suppressed it at 03:12" lead to very different next
questions.

**This does not duplicate tenant Audit Logs.** `Custom::AuditLog` answers "who changed this account's product
data" and is served to that account's own administrators; an operator act writes a row in both, on purpose.
The timeline is one incident's operational story, which the audit log cannot express — and the audit rows
written here carry **no `associated`**, which files them installation-wide so operator activity is never
published to the customer.

## 4. Account 360

`/super_admin/operations/account?id=…` — `Operations::AccountSnapshot`.

Separate from `Operations::AccountHealth` because they answer different questions with different budgets.
`AccountHealth` is page-shaped: "which of these 25 accounts is in trouble", and its whole design is about not
paying per row. This is "what is going on with THIS account" — one account can afford reads a list cannot, and
pretending otherwise is how a detail page ends up as thin as the list it was opened from.

Nine areas: identity and suspension reason, commercial state, usage against the plan's own limits,
channels, commerce stores, open issues, support cases, recent operator activity, and when it was generated.

Two deliberate reads:

- **channels** use `Channels::ConnectionState` *live* — the product's own per-inbox answer, whose own
  documentation says not to call it per inbox across accounts. Here there is one account, at most 50 inboxes,
  and the state comes from Redis and the channel's own columns, so **no provider request** is made while the
  page renders; `includes(:channel)` loads the polymorphic channels one query per type. The recorded signal is
  shown *beside* the live state, not instead of it: the live reading says what is true now, the signal says
  what was observed and when.
- **stores** pair `status` with `Commerce::StoreHealth` (`09-commerce-operations.md`), `includes(:health)`.

Usage pairs `Billing::ResourceLimit.current_count` with `Billing::Entitlements.limit` for every
`BillingPlan::LIMIT_KEYS` entry, because a bare count means nothing until you know the limit, and a `nil`
limit renders as *unlimited* rather than as a blank or a zero.

`#support` is the documented **seam** for the frozen Platform Support Desk: a Platform Support ticket count
becomes one more key there and one more line in the view's support block. Not implemented here.

## 5. Information architecture

Six tabs, ordered the way an operator works: what is wrong, what I am doing about it, then the three places the
answer lives, then the raw feed.

| tab | answers |
|---|---|
| Overview | the six questions in `10-operations-ui.md` §1 |
| Queue | the work list, worst first |
| Accounts | which accounts are in trouble; 360 per account |
| Channels | what we can and cannot say about each channel type |
| Commerce | every connected store and whether its provider answers |
| Issues | the raw signal feed, open / resolved / all |

## 6. What this phase deliberately did not build

- **No new notification path.** The bell is deferred and the existing notification path is not reused until
  the `Notifications::ConversationVisibility` authorization issue is fixed separately (workstream E).
- **No Platform Support tickets.** That architecture is frozen at discovery
  (`docs/platform-support/11-approved-decisions.md`).
- **No corrective actions yet.** `SignalLifecycle::ACTIONS` declares the two safe ones
  (`health_reprobe`, `commerce_resync`) and `record_action` records an outcome, but no UI runs them: running a
  provider action from a console needs its own authorization and idempotency review.
- **No second Grafana and no second Sidekiq.** See `10-operations-ui.md` §4.
