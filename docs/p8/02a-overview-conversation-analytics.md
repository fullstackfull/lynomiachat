# P8.2 — Overview and conversation analytics

Companion to `docs/p8/02-analytics.md` (the request/response contract) and `docs/p8/01-architecture.md` (why the
account timezone is the canonical one). This document covers the first screen built on that foundation: the
Analytics overview.

---

## 1. What the screen answers

Five operational questions, which is why it has the visualizations it has and no others:

| Question | What answers it |
| --- | --- |
| How much work arrived? | `conversations_created` KPI + series, `inbound_messages` |
| How much work was closed? | `conversations_resolved` KPI + series, `conversations_reopened` |
| How fast do we respond? | `avg_first_response_time`, `avg_resolution_time` |
| How much is still open? | `unresolved_backlog` (current state) |
| Where does the volume sit? | breakdown by inbox / channel / team / agent |

There is no chart that does not answer one of these.

---

## 2. Endpoint

`GET /api/v1/accounts/:account_id/analytics/overview`

Parameters are the shared analytics contract (`since`, `until`, `group_by`, filters) plus:

| Parameter | Required | Values | Notes |
| --- | --- | --- | --- |
| `breakdown_by` | no | `inbox` \| `channel` \| `team` \| `agent` | defaults to `inbox`; an unknown value answers `422` |

Authorization is `authorize :report, :view?` — `ReportPolicy#view?` is administrator-only, which is the
permission account-wide reporting already carries in this product. The frontend route declares the matching
`['administrator', 'report_manage']` permissions, the same pair the existing report routes use.

### Response

The standard `Analytics::Result` envelope: `meta`, `kpis`, `series`, `breakdowns`.

- **8 KPIs** — the seven event metrics plus `unresolved_backlog`.
- **4 series** — `conversations_created`, `conversations_resolved`, `inbound_messages`, `outbound_messages`.
- **1 breakdown** — keyed `by_<dimension>`.

---

## 3. Metric definitions, and the evidence behind each

`custom/app/services/analytics/conversations/metrics.rb`.

| Metric | Source | Why this and not something else |
| --- | --- | --- |
| `conversations_created` | `conversations.created_at` in range | the row's own creation; no event is written for it |
| `conversations_resolved` | `reporting_events` named `conversation_resolved` | the OSS definition, unchanged |
| `conversations_reopened` | `reporting_events` named `conversation_opened` where `event_start_time <> conversations.created_at` | see §4 |
| `avg_first_response_time` | `AVG(value)` of `first_response` events | the OSS definition, unchanged |
| `avg_resolution_time` | `AVG(value)` of `conversation_resolved` events | the OSS definition, unchanged |
| `inbound_messages` | `Message.chat` + `message_type: incoming` | `Message.chat` is the repository's own "real communication" scope |
| `outbound_messages` | `Message.chat` + `message_type: outgoing` | same; an approved WhatsApp template send is an ordinary outgoing message and is counted |
| `unresolved_backlog` | `conversations.status IN (open, pending)` **now** | current state; see §5 |

### Message counting

`Message.chat` is `where.not(message_type: :activity).where(private: false)` (`app/models/message.rb:119`). On top
of that, filtering to `incoming`/`outgoing` excludes `message_type: template`, which in this schema means a
**system** message — greeting, auto-resolve, out-of-office, email-collect, CSAT survey — not a WhatsApp approved
template. Those are product messaging rather than an exchange with the customer, so they are not counted as
either direction. A WhatsApp approved template send is persisted as `outgoing` and *is* counted.

---

## 4. Reopen detection

`conversation_opened` is one event name covering two different things. The listener distinguishes them by what it
writes into `event_start_time` (`app/listeners/reporting_event_listener.rb:101-124`):

- **first open** → the conversation's own `created_at`
- **reopen** → the end of the resolution that preceded it

So comparing `reporting_events.event_start_time` against `conversations.created_at` is the discriminator the
*writer itself* established, and it holds for any number of cycles: resolved → reopened → resolved → reopened
writes one row per reopen, each with a start time taken from its own preceding resolution.

`value > 0` is the obvious shortcut and it is **wrong**: a conversation reopened inside the same second as its
resolution has `value = 0` and would be miscounted as a first open.

`conversation_opened` is read by no metric registry in OSS, which makes it the sole durable record of a reopen
in this schema (`docs/p8/00-discovery.md` §2).

---

## 5. Current state is not a range count

`unresolved_backlog` is deliberately **not** date-filtered. A backlog is a reading taken at an instant, and the
instant is now.

There is no honest way to produce "backlog as it stood last Tuesday" from this schema: a conversation keeps only
its current `status` and a single most recent `status_changed_at`. No per-transition history exists
(`docs/p8/00-discovery.md` §3). Rather than approximate it, the response labels the metric
`kind: "current_state"` and the UI shows the hint *"A reading taken now, not a count over the selected dates."*

`snoozed` is excluded from the backlog: a snoozed conversation is deliberately out of the queue until it wakes,
so counting it would overstate what an agent faces.

### Durations are null, not zero

`average_duration` returns `nil` when there is nothing to average, and the UI renders `—`. "No conversation was
resolved" must not display as "resolved instantly".

---

## 6. Tenant isolation

Every query starts from `@account.<association>` or from an explicit `account_id`, and every filter id was already
proved to belong to the account by `Analytics::FilterSet` before it reached the metric object. `params[:account_id]`
is never read: the account comes from `Current.account`, which the base controller resolved from the authenticated
session and the route.

Two joins deserve naming because they cross a table that is not account-scoped by itself:

- `reporting_events` is filtered by `account_id` explicitly (the table carries one).
- `messages` comes from `@account.messages`, and the team/agent filters narrow it through
  `conversation_id IN (filtered_conversations)` rather than by any looser predicate.

---

## 7. Source reporting: raw vs rollup

The overview reads **raw** throughout, and says so rather than leaving it implied. `meta.source` and
`meta.source_reason` come from `Analytics::RollupCoverage#decide`, so an operator can tell apart:

| `source_reason` | Meaning |
| --- | --- |
| `feature_disabled` | the `report_rollup` feature is off for this account |
| `no_account_reporting_timezone` | no timezone is set, so the rollup writer never wrote a row |
| `no_rollup_dimension` | the requested grouping has no rollup dimension |
| `no_rollup_metric` | the metric has no rollup counterpart |
| `incomplete_coverage` | rollup totals disagreed with the raw events, so raw was used |
| `coverage_verified` | rollup totals matched raw for every day in range |

Rollups are **not** consulted per metric on this screen. It mixes metrics that have no rollup counterpart at all
(message counts, reopens, backlog) with ones that do, and splitting sources within one response is exactly what
`Analytics::RollupCoverage` exists to prevent.

---

## 8. Frontend

| File | Role |
| --- | --- |
| `dashboard/api/analytics.js` | the two endpoints, with `signal` passed through |
| `dashboard/constants/analytics.js` | groupings, bucket ceilings, KPI kinds, breakdown dimensions |
| `dashboard/composables/useAnalyticsQuery.js` | range state + request lifecycle, shared by every P8 screen |
| `dashboard/components-next/analytics/AnalyticsRangeControls.vue` | existing `WootDatePicker` + grouping `TabBar` |
| `dashboard/components-next/analytics/AnalyticsKpiGrid.vue` | KPI cards (reuses the campaign analytics metric card) |
| `dashboard/components-next/analytics/AnalyticsSeriesCard.vue` | one series, via the existing `BarChart` wrapper |
| `dashboard/components-next/analytics/AnalyticsBreakdownCard.vue` | breakdown rows with share bars + dimension switcher |
| `dashboard/components-next/analytics/AnalyticsMetaNote.vue` | range, timezone, source and any warnings |
| `dashboard/routes/dashboard/analytics/AnalyticsOverview.vue` | the page |

No new charting dependency was added. `@chatwoot/viz` (already a dependency) supplies the bars through the
existing `shared/components/charts/BarChart.vue` wrapper, which carries the design-system CSS variables.

### Dates, not instants

The client sends the calendar dates the operator picked, formatted with `date-fns` `format` (which reads the
local calendar parts — exactly what "1 October" means to the person who clicked it). It never sends epoch
seconds derived from the browser clock, because that would make the same requested period produce different
totals for two viewers. Viewer timezone affects nothing but display.

### The grouping control is a control, not a duplicated guard

`availableGroupBy` offers only groupings whose bucket count fits the server's ceiling, so the picker cannot hand
the operator a request the server will reject. Its weekly and monthly estimates add one bucket for the partial
bucket at each end, which makes them an **upper bound** on the server's own `bucket_starts` walk — verified
against that walk over 72,000 start-date/span/grouping combinations with zero under-estimates. Erring high can
hide a grouping the server would have accepted at the margin; it can never offer one the server rejects.

When a range change invalidates the current grouping, the composable moves to the longest grouping the range
supports rather than failing the request.

### Request ordering

Requests go through the repository's shared `useAbortableRequest`, so dragging through a date picker cannot let a
slow earlier response overwrite a newer one.

---

## 9. Navigation and permissions

A top-level **Analytics** group in the sidebar (`components-next/sidebar/Sidebar.vue`), above Reports, with
`Overview` as its first child. It is a separate area from Reports rather than another Reports child because
P8.3–P8.5 add WhatsApp, campaign, automation, flow and commerce screens to it, none of which belong under the
conversation reports.

The route carries `featureFlag: FEATURE_FLAGS.REPORTS` and `permissions: ['administrator', 'report_manage']`.

---

## 10. Tests

| Spec | Count | Covers |
| --- | --- | --- |
| `spec/services/analytics/conversations/metrics_spec.rb` | 24 | every metric, reopen discrimination, null durations, account scoping |
| `spec/requests/analytics/analytics_overview_spec.rb` | 17 | authorization, 422 shapes, breakdowns, envelope |
| `composables/spec/useAnalyticsQuery.spec.js` | 10 | calendar dates, grouping ceilings, request ordering |
| `components-next/analytics/specs/*.spec.js` | 26 | KPI formatting, zero-vs-null, bucket labelling, shares, meta note |

---

## 11. Known limitations carried forward

These are product limitations of the schema, recorded so a later phase does not mistake them for bugs:

1. **No historical backlog.** Conversations keep only their current status; no per-transition history exists.
2. **No conversation-level channel column.** The channel breakdown joins `inboxes`, which is correct but means
   a conversation whose inbox was deleted has no channel.
3. **`first_response` averages exclude conversations that never got a reply**, because no event is written for
   them. This matches the existing OSS reports exactly, and changing it would make the two disagree.
4. **A reopen is only recognised when the preceding resolution left an event.** The listener looks for the most
   recent `conversation_resolved` event for that conversation and falls back to treating the open as a first
   open when it finds none (`app/listeners/reporting_event_listener.rb:105-121`). So a conversation whose
   resolution predates the reporting-event writer, and which is then reopened, is recorded with
   `event_start_time = created_at` and counts as a creation rather than a reopen. This is the writer's own
   behaviour, not something the read path can correct.
