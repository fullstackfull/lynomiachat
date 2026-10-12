# P8 architecture

Branch `claude/p8-analytics-contact-timeline`, cut from `lynomia-custom` at `b03ea43d`.
Discovery and its evidence: `docs/p8/00-discovery.md`.

---

## 1. Timezone semantics — the P8 decision

**`Account#reporting_timezone` is the canonical timezone for all P8 analytics aggregation and bucketing.**

| Concern | Rule |
| --- | --- |
| Database timestamps | stay UTC. Nothing is rewritten |
| Date range interpretation | account timezone |
| Day / week / month bucket boundaries | account timezone |
| Period boundaries | account timezone |
| Viewer / browser timezone | display formatting only. It must never change grouping or totals |

### Why the request contract is calendar dates, not instants

The existing `/api/v2/.../reports` endpoints take `since` and `until` as **Unix epoch seconds**
(`app/helpers/date_range_helper.rb:13-18`). An instant-based contract cannot deliver the determinism this phase
requires: a browser computing "the last 7 days" from its own clock sends a *different instant per viewer*, so two
administrators asking for the same named period would get different windows and different totals.

So P8 endpoints take `since` and `until` as **`YYYY-MM-DD`**, interpreted in the account's reporting timezone.
Determinism is then structural rather than something the frontend has to be careful about.
`Analytics::DateRange` refuses an epoch value with a 422 rather than silently accepting it
(`spec/services/analytics/date_range_spec.rb`, "rejects an epoch timestamp").

The existing v2 reports keep their own contract. P8 does not change them.

### Boundary semantics

`until` is **inclusive as a date** and resolves to an **exclusive instant** at the start of the following day in the
account timezone. So 1–7 October covers the whole of the 7th, and the UTC window is half-open:

```
[ since 00:00 account-local ,  (until + 1 day) 00:00 account-local )
```

Half-open is what keeps adjacent ranges from double counting a row on the boundary or losing one between them —
asserted directly in the spec ("is half-open, so adjacent ranges neither double count nor skip an instant").

Measured example, account on `Asia/Kuwait` (UTC+3), 1–7 October 2026:
`starts_at = 2026-09-30T21:00:00Z`, `ends_at = 2026-10-07T21:00:00Z`.

### The fallback when `reporting_timezone` is absent: UTC

This is the repository's existing behaviour, not a new invention:

- `TimezoneHelper#timezone_name_from_offset` returns `'UTC'` for a blank offset
  (`app/helpers/timezone_helper.rb:16`).
- `ReportingEvents::RollupService#rollup_enabled?` writes no rollup row at all for an account without one
  (`app/services/reporting_events/rollup_service.rb:25-27`).

`Analytics::DateRange` additionally falls back to UTC if a *stored* value is not a real zone. `Account` validates
this on write (`app/models/account.rb:217-220`), so reaching that branch means the row predates the validation.
The response's `timezone.source` field says `account.reporting_timezone` or `fallback`, so a viewer can always see
which applied.

### The inconsistency this decision resolves

Two timezone regimes already coexist in the codebase and disagree whenever a viewer's offset differs from the
account's reporting timezone:

| Path | Timezone source | Evidence |
| --- | --- | --- |
| v2 live reports | the **viewer's** `params[:timezone_offset]` | `report_builder.rb:15`, `base_timeseries_builder.rb:59`, `drilldown_builder.rb:196`, `data_source.rb:58` |
| rollup write and backfill | the **account's** `reporting_timezone` | `rollup_service.rb:26,30`, `backfill_service.rb:44` |

P8 adopts the account-timezone side, which is also the side the rollup data is already bucketed by — so the raw
and rollup paths agree on what a day is, which is what makes the coverage check in §2 meaningful.

Measured consequence of getting this wrong: for an account on `Asia/Kuwait`, events at 22:00 and 23:30 UTC on
1 October belong to **2 October** locally. Naive UTC bucketing misfiles 2 of 3 events in that fixture.

### DST

Offsets are resolved per boundary, not once. For `America/New_York` across the 1 November 2026 transition,
25 October resolves at UTC-4 and 6 November at UTC-5, and a 12-day request still yields exactly 12 daily buckets
(`date_range_spec.rb`, "daylight saving").

---

## 2. Raw versus rollup

**RAW is the source of truth. ROLLUP is an optimisation and never the only place an answer comes from.**

`Analytics::RollupCoverage#decide` returns `{ source:, reason: }`. The decision is **all or nothing for the whole
requested range**, which is the core correctness property: serving part of a range from rollups and the rest from
raw would publish a number that is partly double-counted and partly missing, with nothing in the response to say
so. The rollup upsert is additive (`rollup_service.rb:73-79`, `count = count + EXCLUDED.count`), so a day rolled
up twice reads high and a day before the rollup began reads zero. Choosing one source for the entire range turns a
wrong rollup into a *refused* rollup instead of a wrong total.

Four conditions, all required:

| # | Condition | `reason` when it fails |
| --- | --- | --- |
| 1 | `report_rollup` enabled for the account | `feature_disabled` |
| 2 | account has a valid `reporting_timezone` | `no_account_reporting_timezone` |
| 3 | the dimension is one the writer populates (`account`, `agent`, `inbox`) | `no_rollup_dimension` |
| 4 | every bucket present and agreeing with raw, **in both directions** | `incomplete_coverage` |

Condition 1 is off by default: `config/features.yml:112-114` has `enabled: false`, and
`db/migrate/20260226153427_disable_report_rollup_for_all_accounts.rb` disabled it for every existing account. So
on a default installation the answer is always raw, and condition 4's cost is never paid.

**Condition 4 compares the union of days on both sides.** An earlier draft iterated only the raw side, and
`{}.all?` is `true` — so an account with no events and a stale rollup row would have read the rollup and reported
activity that never happened. Found by a test written against the first implementation; three cases now guard it
(`rollup_coverage_spec.rb`: "refuses a rollup row for a day the account has no raw events on", "reads raw when
both sides are empty", "does not accept a rollup that was bucketed by naive UTC days").

---

## 3. Layout and the autoload trap

Lynomia-exclusive code takes a top-level namespace, matching `Audience::`, `Commerce::`, `Flows::`;
`Custom::X` stays reserved for `prepend_mod_with` overrides of OSS classes.

| Path | Constant |
| --- | --- |
| `custom/app/services/analytics/*.rb` | `Analytics::*` |
| `custom/app/controllers/analytics/request_scoped.rb` | `Analytics::RequestScoped` |
| `custom/app/controllers/api/v1/accounts/analytics_controller.rb` | `Api::V1::Accounts::AnalyticsController` |
| `lib/custom_exceptions/analytics.rb` | `CustomExceptions::Analytics::*` |

**The autoload trap, recorded because the next contributor will hit it.** `config/application.rb:46` adds eager
load paths with `Dir["#{Rails.root}/custom/app/**"]`, and **that glob is single level** — it expands to the eleven
immediate children of `custom/app` and nothing deeper. So under the `custom/app/controllers` root, a file in a
`concerns/` subdirectory resolves as `Concerns::Analytics::RequestScoped`: `concerns` is an ordinary path segment
here, not the special autoload root Rails makes of `app/controllers/concerns`. Verified by booting — the constant
was missing under `concerns/` and resolved with the `Concerns::` prefix. Hence the concern lives in
`controllers/analytics/`.

---

## 4. Tenant isolation

`Current.account`, resolved by `Api::V1::Accounts::BaseController` from the authenticated session and the route, is
the only account source. `params[:account_id]` is never read by analytics code.

Every filter id is resolved **against that account** before it reaches a query (`Analytics::FilterSet`), so a
crafted id cannot select another tenant's rows. `exists?` rather than `find`, because the question is ownership and
a 422 naming the filter is a better answer than a 404 for a row the caller was never allowed to see.

The two tables discovery flagged:

| Table | Why it needs care | Rule |
| --- | --- | --- |
| `audits` | no `account_id` at all; scoped by `associated_type='Account'` + `associated_id` | any analytics read must carry that predicate explicitly. P8.1 reads no audits |
| `contact_inboxes` | no `account_id` | only reachable through an inbox or contact this account owns; never joined without one |

An agent id is checked through `account.account_users`, because users are global while membership is not.

## 5. Authorization

Account-wide analytics follows the reporting permission the product already has: `ReportPolicy#view?` is
`@account_user.administrator?`. Where a P8 screen is scoped to a single record it follows **that record's** policy
instead — the precedent is the existing per-campaign analytics, which authorizes `@campaign, :show?`
(`custom/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb:37-39`). The contact timeline will
follow the contact's policy for the same reason: an agent who may open a contact should see its activity.

No new RBAC layer.

## 6. Degradation

`Analytics::Result#degrade(scope, reason)` records a warning and sets `meta.partial`. It is for an **optional**
contributor only. Authorization failures and primary-query failures raise and answer normally — a security or
database failure must never be presented as a slightly incomplete chart. `meta.empty` distinguishes "no data" from
"something broke", so the two can never blur.

## 7. Caching

**None introduced at P8.1.** The EXPLAIN evidence (`docs/p8/04-security-performance.md`) shows the foundation's
query shapes served from existing indexes in under 9 ms at 60k rows, so a cache would add staleness and a
tenant-key risk for no measured gain. If one is added later, the key must include the account id, the resolved
range, the group_by and every filter value.
