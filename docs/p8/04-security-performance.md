# P8 security and performance

Updated at each phase. §1–§3 are the P8.1 baseline; §4–§6 are the P8.8 hardening pass over every
shape P8.2–P8.7 ship.

---

## 1. Performance baseline — measured, not assumed

### Method

`EXPLAIN (ANALYZE, BUFFERS)` against a local PostgreSQL 16.15 carrying a representative fixture: **60,000
`reporting_events`** across two accounts spread over ~430 days, plus **431 `reporting_events_rollups`** rows, with
`ANALYZE` run on both tables so the planner had current statistics. The four shapes are the queries P8.1 actually
issues plus the two widest a P8.2 screen could issue.

The fixture was removed from the test database afterwards; see §3.

### Results

| # | Shape | Plan | Index used | Time |
| --- | --- | --- | --- | --- |
| 1 | raw daily counts in the account timezone, one metric, 7-day range (`RollupCoverage#raw_daily_counts`) | Bitmap Index Scan → HashAggregate, 15 buffer hits | `reporting_events__account_id__name__created_at` | **0.358 ms** |
| 2 | rollup lookup, one metric, 7-day range | Bitmap Index Scan → GroupAggregate, 7 buffer hits | `index_rollup_timeseries` on `(account_id, metric, date)` | **0.237 ms** |
| 3 | the widest allowed daily range, 366 buckets, one metric | Bitmap Index Scan → HashAggregate, 6,706 rows | `index_reporting_events_on_name` | **8.8 ms** |
| 4 | a whole account over a year with **no** metric filter | Seq Scan, 33,852 of 60,000 rows | none | **16.6 ms** |

### What the evidence says

**The account-timezone bucketing costs nothing at the index level.** In shape 1 all three predicates
(`account_id`, `name`, `created_at` range) appear in the Index Cond, and the
`AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kuwait'` expression is applied afterwards in the HashAggregate. Grouping in
the account's timezone therefore does **not** prevent index use — which is the single most important thing to know
before building timeseries endpoints on top of it.

**Shape 3 shows the planner switching index.** At a 366-day range it preferred the single-column
`index_reporting_events_on_name` over the composite. Still indexed, still under 9 ms at this volume, but worth
knowing that the plan is range-width dependent.

**Shape 4's sequential scan is correct, not a missing index.** The query returns 56% of the table; an index scan
would be slower. It would only merit attention at far larger volume, and at that point the useful index would
likely be `(account_id, created_at)` — which is **not** being added, because adding it now would be speculative.
The production row counts needed to decide are gathered by **R7** in `docs/p8/00b-rollup-production-check.md`.

### Index changes in P8.1: none

No index was added. Every shape the foundation issues is served by an index that already exists. The condition for
revisiting is explicit: production `reporting_events` row counts from R7, plus an `EXPLAIN` of a real P8.2 query
shape against them.

### Bounding, rather than indexing

`Analytics::DateRange` caps **buckets**, not days: 366 daily, 104 weekly, 60 monthly. Buckets are what cost — they
are the group-by's output rows, the chart's points and the response's width — so capping them bounds the query, the
payload and the coverage check together. Shape 3 is that ceiling, measured.

### Caching: none at P8.1

With the foundation's shapes under 9 ms on 60k rows, a cache would add staleness and a tenant-key risk for no
measured gain. If one is introduced later the key must include the account id, the resolved range, the `group_by`
and every filter value; `docs/p8/01-architecture.md` §7 holds that rule.

---

## 2. Security posture at P8.1

### Tenant isolation

| Control | Where |
| --- | --- |
| Account derived only from `Current.account` | `Analytics::RequestScoped`; `params[:account_id]` is never read |
| Every filter id resolved against that account before it reaches a query | `Analytics::FilterSet#ownership_checks` |
| Agent ids checked through `account.account_users`, because users are global and membership is not | `FilterSet#owned_agent_id` |
| `channel_type` validated against the account's own inboxes | `FilterSet`, so the allowed set is itself account-scoped |
| Rollup coverage reads only this account's rows on both sides | `RollupCoverage`, with two account-isolation specs |

Tested: an inbox, team, campaign, automation rule or agent belonging to another account is refused with a 422; a
non-numeric id and a SQL fragment are refused rather than coerced; an administrator of another account receives
401 for this account's endpoint and their own timezone for their own.

The two tables discovery flagged are untouched by P8.1 — `audits` (no `account_id`, scoped via
`associated_type`/`associated_id`) and `contact_inboxes` (no `account_id`). The rule for when they are used is in
`docs/p8/01-architecture.md` §4, and it is enforced by review rather than by code until a phase actually reads them.

### Authorization

`ReportPolicy#view?` — administrator only — for account-wide analytics. Record-scoped screens follow the record's
own policy, as the existing per-campaign analytics already does. Agent access is refused and tested.

### Information disclosure

Error bodies are `{"message": "..."}` and nothing else, asserted by a spec. No credential, token, provider payload
or internal identifier appears in any P8.1 response. The `meta` block carries only the timezone, the resolved
range, the chosen source and the resolved filter values.

One real failure mode found and fixed: `format` is a reserved I18n interpolation key, so interpolating it raised
`I18n::ReservedInterpolationKey` **while building the error message**, escaping the rescue and turning a 422 into a
500 whose body was Chatwoot's generic `{status, error}`. Renamed to `expected_format`, and a sweep over
`errors.analytics.*` against `I18n::RESERVED_KEYS` confirms none remain. It was caught only by exercising the HTTP
path; the service-level specs passed throughout.

---

## 3. Test hygiene note

Seeding the 60k-row EXPLAIN fixture into `chatwoot_test` caused **two unrelated specs** in
`spec/builders/v2/reports/timeseries/report_builder_spec.rb` to fail in a full run while passing in isolation: a
report builder averaging over `ReportingEvent` picked up the seeded rows. Deleting the fixture restored the file to
15 examples, 0 failures.

Recorded because it is a trap for anyone benchmarking against the test database: a planner fixture is not
transactional and will leak into every example in the run. Benchmark fixtures belong in a scratch database, or must
be removed before any suite is run.

---

## 4. P8.8 — EXPLAIN over every shipped shape

### Method, and why it leaves nothing behind

The §3 trap is the reason this pass runs inside **one transaction that is rolled back**, with `ANALYZE` on the
seeded tables *inside* that transaction so the planner has real statistics while the plans are taken. After the
rollback the harness re-counts `messages` and `conversations` and prints zero, which is the proof that the
benchmark fixture did not leak into the test database.

Two passes were needed, because the first one's answer turned out to be about the fixture rather than the code.

**Pass 1** — one dominant tenant: 71,000 messages, 7,200 conversations, 24,800 reporting events, 801 contacts,
with the target account holding ~86% of the rows, plus one HEAVY contact (200 conversations, 6,000 messages).

**Pass 2** — the realistic multi-tenant shape: 126,000 messages and 20,200 conversations, with the target
account a **small minority** (202 conversations), plus a HEAVY contact (200 conversations) and a QUIET contact
(2 conversations) inside it.

### Pass 1 results

| # | Shape | Time | Note |
| --- | --- | --- | --- |
| A1 | conversations created over a range | 1.1 ms | Seq Scan on conversations |
| A2 | the same, bucketed `date_trunc(... AT TIME ZONE)` | 3.3 ms | Seq Scan; the timezone expression did not prevent anything |
| A3 | unresolved backlog (current state) | 1.0 ms | Seq Scan |
| A4 | inbound messages over a range | 8.9 ms | Seq Scan on messages |
| A5 | reopen detection, `reporting_events` ⋈ `conversations` | 1.2 ms | index on reporting_events |
| A6 | breakdown by inbox | 1.5 ms | Seq Scan |
| A7 | breakdown by channel (⋈ inboxes) | 2.2 ms | Seq Scan + hash join |
| B1 | WhatsApp sends with the echo exclusion | **23.3 ms** | see §5 |
| B2 | template breakdown on `additional_attributes` | 8.5 ms | jsonb read, no index |
| C1 | timeline fan-out, HEAVY contact | 3.6 ms | see §6 |
| C2 | the same with a cursor | 1.3 ms | — |
| C3 | timeline fan-out, ordinary contact | 0.2 ms | — |
| C4 | timeline reporting events, HEAVY contact | 17.7 ms | see §6 |
| C5 | the contact's conversations | 0.9 ms | — |
| C6 | timeline fan-out for an inbox-restricted agent | 3.5 ms | — |

**The eight Seq Scans are a property of the fixture, not of the code.** When one account holds 86% of a table,
a sequential scan *is* the cheaper plan and the planner is right to choose it. Pass 2 was run to settle it.

### Pass 2 results — the account index is used when the account predicate is selective

| # | Shape | Plan | Time |
| --- | --- | --- | --- |
| Q2a | conversations over a range, minority tenant | `index_conversations_on_account_id` | 0.064 ms |
| Q2b | backlog, minority tenant | `index_conversations_on_account_id` | 0.084 ms |
| Q2c | inbound messages over a range, minority tenant | `index_messages_on_account_id` | 1.219 ms |

No Seq Scan appears in any of them. The pass-1 plans were correct for pass-1 data, and the account indexes do
their job at the shape production actually has. **No new index is needed for the analytics shapes.**

---

## 5. The one measured cost worth naming: the coexistence-echo exclusion (B1, 23.3 ms)

The predicate is a functional expression over a double-encoded column
(`docs/p8/02b-whatsapp-campaign-analytics.md` §1), so it cannot use an index and is evaluated per candidate row.
The plan shows exactly that:

```
->  Index Scan using index_messages_on_inbox_id on messages (rows=26000)
      Filter: (created_at >= ... AND created_at < ... AND account_id = ... AND message_type = 1
               AND COALESCE(((content_attributes #>> '{}')::jsonb ->> 'external_echo'), 'false') <> 'true')
      Rows Removed by Filter: 40000
```

What bounds it: the predicate only ever runs on rows an index has already narrowed to one account's WhatsApp
inboxes, one message type and one date range. 23 ms for 66,000 candidate rows is ~0.35 µs per row, so the cost
scales with the **WhatsApp outgoing volume inside the requested window**, not with the table.

It is recorded rather than optimised because the lever is a migration — a generated column or a functional index
on the decoded expression — and nothing in production has yet shown it is needed. The trigger to revisit: a
single account sending more than roughly a million outgoing WhatsApp messages inside one requested range, which
would put this query near a second.

---

## 6. The contact-timeline fan-out: measured, and the conclusion is "no change"

This was flagged in discovery as *"the one place a new index may be justified, and it must be decided from a
real EXPLAIN, not assumed"* (`docs/p8/00-discovery.md` §7). `messages` carries no `contact_id`, so the read has
to go through `conversations.contact_id`.

### What the plans show

| # | Contact | Query form | Plan | Time |
| --- | --- | --- | --- | --- |
| Q1a | HEAVY (200 conversations) | subquery — what P8.6 ships | `index_messages_on_account_id` + bitmap on `index_conversations_on_contact_id` | 2.58 ms |
| Q1b | HEAVY | literal id list | `index_messages_on_account_id` | 1.91 ms |
| Q1c | QUIET (2 conversations) | subquery — what P8.6 ships | **`index_messages_on_conversation_account_type_created`**, per conversation | **0.062 ms** |
| Q1d | QUIET | literal id list | the same index | 0.135 ms |

Three conclusions, all of them negative decisions:

1. **No new index.** `index_messages_on_conversation_account_type_created` already leads on `conversation_id`
   and the planner uses it exactly where it matters — a contact with few conversations in a large database,
   which is the common case and which comes back in 62 µs.

2. **No materialising the conversation ids.** Replacing the subquery with a literal `IN` list changes nothing
   worth having: 1.91 ms against 2.58 ms for the heavy contact, and *slower* (0.135 ms against 0.062 ms) for the
   quiet one, because the planner loses the row estimate the subquery gives it. The subquery P8.6 ships is the
   better form, so no change was made.

3. **The residual risk, stated precisely.** For a contact with *many* conversations the planner switches to
   walking the account's messages newest-first and probing `conversations` per row — 4,006 rows scanned to
   return 31 in Q1a. That is bounded by `account messages ÷ this contact's share of them`. It is fast here and
   would degrade for a contact holding a small fraction of a very large account's messages. The lever if it ever
   bites is not an index (the index exists) but asking per conversation and merging, which costs one query per
   conversation and is worse in every case measured. Revisit only with a production plan that shows it.

C4 (timeline reporting events, 17.7 ms) has the same shape and the same conclusion: it walks
`index_reporting_events_on_created_at` backwards and memoizes the conversation probe (12,022 cache hits against
6,012 misses), which is the planner handling the fan-out well.

---

## 7. P8.8 — tenant isolation, proved against a mirrored fixture

`spec/requests/analytics/p8_tenant_isolation_spec.rb` builds **two accounts with the same shape of activity** —
one conversation, one message, one reporting event, one campaign recipient, one automation execution, one flow
session, one cart each — and then asserts that every P8 read surface returns **one** of each, not two.

That mirroring is the point. A spec that creates data in only one account cannot catch a missing account
predicate, because the absent rows would not exist to leak. Here a missing predicate shows up as a doubled
count, and the spec also asserts the count is not zero, so a query that returns nothing cannot pass by
accident.

| Surface | Scoped | Foreign administrator | Foreign record |
| --- | --- | --- | --- |
| `/analytics/overview` | ✅ | 401 | — |
| `/analytics/whatsapp` | ✅ | 401 | — |
| `/analytics/campaigns` | ✅ | 401 | — |
| `/analytics/automations` | ✅ | 401 | — |
| `/analytics/flows` | ✅ | 401 | — |
| `/analytics/commerce` | ✅ | 401 | — |
| `/contacts/:id/activity` | ✅ | 401 | 404 for a contact from the other account |

Per-filter isolation is asserted separately in each family's own spec: a `template_id`, `campaign_id`,
`automation_rule_id` or `inbox_id` from another account answers **422 with the reason**, not an empty result, so
a probe cannot distinguish "not yours" from "nothing there" by the row count.

### The two tables with no account column of their own

`audits` has no `account_id` at all (it scopes through `associated_type`/`associated_id`) and `contact_inboxes`
has none either, so any join through them would need an explicit account predicate on the *other* side — easy
to write once and easy to forget on the next change.

**P8 reads neither.** The spec enforces it by scanning every P8 source file, with comment lines stripped first
so that the documents explaining *why* the tables are avoided do not read as using them. If a later change
introduces a read of either table, that spec fails and the author has to add the predicate deliberately.

### Inbox-level narrowing

The contact timeline narrows twice, and both are asserted:

- conversation-derived adapters go through `Conversations::PermissionFilterService`, so a message in an inbox
  the agent is not a member of is absent for that agent and present for an administrator;
- campaign recipients, which carry an inbox but no conversation, are narrowed by the caller's own visible inbox
  set computed from their role rather than from the contact's conversations.

### What is deliberately not restricted

Private notes are included in the timeline, because the conversation view includes them for anyone who can open
the conversation and the timeline is gated on the same conversation visibility. Commerce rows are gated on the
contact alone, because carts and customer links carry neither an inbox nor a conversation and there is nothing
narrower to gate on without inventing a rule. Both are recorded in
`docs/p8/03-contact-activity-timeline.md` §4.
