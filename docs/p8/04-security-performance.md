# P8 security and performance

Updated at each phase. This revision covers P8.1 (the analytics foundation).

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
