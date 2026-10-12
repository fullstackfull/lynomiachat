# P8 analytics — the API contract

Companion to `docs/p8/01-architecture.md`. The shared contract every P8 analytics endpoint obeys. Per-family
detail lives in `02a` (conversations), `02b` (WhatsApp and campaigns), `02c` (automations and flows) and `02d`
(commerce).

---

## 1. Request contract

| Parameter | Required | Form | Notes |
| --- | --- | --- | --- |
| `since` | yes | `YYYY-MM-DD` | interpreted in the account's reporting timezone |
| `until` | yes | `YYYY-MM-DD` | **inclusive** as a date |
| `group_by` | no | `day` \| `week` \| `month` | defaults to `day` |
| filters | no | see §3 | each validated against the account |

`hour` and `year` are deliberately **not** accepted yet, although the v2 reports permit them. They are added when
a screen needs them rather than before.

### Bucket ceilings

A ceiling on buckets rather than on days, because buckets are what cost: they are the rows the group-by returns,
the points the chart draws and the width of the response.

| `group_by` | maximum buckets | roughly |
| --- | --- | --- |
| `day` | 366 | a year |
| `week` | 104 | two years |
| `month` | 60 | five years |

Exceeding it is a 422 naming the count and the maximum, so the remedy ("narrow the range or group by a longer
period") is in the message.

## 2. Errors — all 422, all with a `message`

`CustomExceptions::Analytics::*` carry `http_status` 422, so an unusable request is refused at the boundary rather
than reaching a query, a model or Sentry. The body is `{"message": "..."}` and nothing else.

| Class | Raised when |
| --- | --- |
| `MissingDate` | `since` or `until` absent |
| `InvalidDate` | not `YYYY-MM-DD` (an epoch value lands here) |
| `InvertedRange` | `since` later than `until` |
| `InvalidGroupBy` | outside day / week / month |
| `RangeTooLarge` | above the bucket ceiling |
| `UnsupportedFilter` | a filter the family has no meaning for |
| `UnknownFilterValue` | a value this account does not own |
| `UnknownMetricFamily` | unknown family |

> **Note for anyone adding a message.** `format` is a reserved I18n interpolation key. Passing it raises
> `I18n::ReservedInterpolationKey` while *building the message*, which escapes the rescue around the raise site and
> turns a 422 into a 500. `InvalidDate` therefore interpolates `expected_format`. The full reserved list is
> `I18n::RESERVED_KEYS`; this bug was caught only by exercising the HTTP path, not by the service specs.

## 3. Metric families

A family declares the metrics a screen reads, the filters meaningful for it, and whether a rollup could answer it.
`conversations` points at `ReportingEvents::MetricRegistry::REPORT_METRICS` so there is one definition of a
conversation metric, not two.

| Family | Filters | Rollup-capable | Honesty note | Detail |
| --- | --- | --- | --- | --- |
| `conversations` | `inbox_id`, `channel_type`, `team_id`, `agent_id` | 6 of 9 metrics | reuses the OSS metric definitions | `02a` |
| `whatsapp` | `inbox_id`, `template_id` | none | `messages` has no delivery timestamps, so delivered means the ladder reached delivered **or read**; coexistence echoes excluded and reported | `02b` |
| `campaigns` | `inbox_id`, `campaign_id` | none | delivered is `delivered_at IS NOT NULL OR read_at IS NOT NULL`; the audience breakdown counts campaigns, never recipients | `02b` |
| `automations` | `automation_rule_id` | none | delayed rules only, 30-day retention; immediate rules are **absent**, not zero, and the response warns | `02c` |
| `flows` | `inbox_id` | none | session lifecycle only; no node-level metrics and no invented abandoned state | `02c` |
| `commerce` | `provider` | none | no revenue, GMV or profit at all, not even per currency; no recovery attribution | `02d` |

**Most families are rollup-incapable by nature, not by omission.** `ReportingEvents::RollupService` only writes
the `account`, `agent` and `inbox` dimensions (`rollup_service.rb:33-39`), so a campaign, template, automation,
flow or commerce breakdown has no rollup row to read.

### Why delivered is counted from a timestamp

Both delivery ladders are monotonic and store only the furthest state reached —
`CampaignRecipient#status_downgrade?` (`custom/app/models/campaign_recipient.rb:71-75`) and
`Messages::StatusUpdateService#valid_status_transition?` (`app/services/messages/status_update_service.rb:36-45`),
both under a row lock, because Meta redelivers statuses out of order. A recipient delivered then read has
`status = read` with **both** `delivered_at` and `read_at` set, so `status = 'delivered'` would exclude every read
recipient and understate the delivery rate.

The existing per-campaign controller already handles this correctly by summing `delivered + read`
(`campaigns/analytics_controller.rb:48`). P8.3 **extends that controller**; it does not replace it.

Coexistence echo messages are created with `status: :delivered` directly
(`app/services/whatsapp/incoming_message_base_service.rb:181-182`), not by a status webhook, so any delivered
figure that includes them must exclude or explicitly classify them rather than present them as webhook-confirmed.

## 4. Response contract

One envelope for every endpoint, so the frontend learns it once:

```json
{
  "meta": {
    "family": "conversations",
    "since": "2026-10-01", "until": "2026-10-07", "group_by": "day",
    "timezone": "Asia/Kuwait",
    "starts_at": "2026-09-30T21:00:00Z", "ends_at": "2026-10-07T21:00:00Z",
    "boundaries": "start inclusive, end exclusive",
    "empty": false, "partial": false,
    "source": "raw", "source_reason": "feature_disabled",
    "filters": { "inbox_id": 7 },
    "warnings": []
  },
  "kpis":       [{ "key": "resolutions_count", "value": 12, "unit": "count" }],
  "series":     [{ "key": "volume", "unit": "count", "points": [{ "bucket": "2026-10-01", "value": 3 }] }],
  "breakdowns": [{ "key": "by_inbox", "dimension": "inbox", "unit": "count",
                   "rows": [{ "id": 7, "label": "Support", "value": 4 }] }]
}
```

The meta block is the honest part: it names the timezone the buckets were cut in, the exact half-open instants, and
which source answered and why. A chart that cannot say which timezone it used is a chart nobody can reconcile
against another report.

- **`empty`** — everything worked and there is no data. Series still emit a point per bucket including zeros, so a
  chart never has to infer a gap.
- **`partial`** — an optional contributor failed; `warnings` names the scope and reason. Never set for an
  authorization or primary-query failure, which raise.

## 5. Endpoints

### `GET /api/v1/accounts/:account_id/analytics`

The canonical analytics contract for the account. Administrator only. Returns the resolved timezone and its source,
the resolved range, the bucket count against its ceiling, the supported `group_by` values, and every metric family
with its filters and rollup-capable metrics.

It exists at P8.1 because the frontend needs it before it can render a date picker that produces deterministic
requests — and because it exercises the whole foundation end to end rather than leaving it as untested
scaffolding.

### The metric endpoints

All on `Api::V1::Accounts::AnalyticsController`, all administrator only, all taking the request contract above
plus a per-family `breakdown_by`.

| Endpoint | Family | `breakdown_by` | Detail |
| --- | --- | --- | --- |
| `GET …/analytics/overview` | conversations | `inbox` (default), `channel`, `team`, `agent` | `02a` |
| `GET …/analytics/whatsapp` | whatsapp | `template` (default), `inbox`, `failure` | `02b` |
| `GET …/analytics/campaigns` | campaigns | `campaign` (default), `audience`, `failure`, `skip_reason` | `02b` |
| `GET …/analytics/automations` | automations | `rule` (default), `skip_reason`, `status` | `02c` |
| `GET …/analytics/flows` | flows | `bot` (default), `status`, `failure`, `end_reason` | `02c` |
| `GET …/analytics/commerce` | commerce | `provider` (default), `store`, `currency`, `action_type`, `action_error` | `02d` |

`GET …/analytics` (the meta endpoint) reports each family's supported breakdowns and its default, so a screen can
build its dimension switcher from the contract instead of a hardcoded list.

The contact activity timeline is **not** on this controller and does not use this contract: it is one record's
own history, follows the contact's permission, and is cursor-paged. See `03-contact-activity-timeline.md`.

### `UnsupportedBreakdown`

A seventh 422: a `breakdown_by` the requested family has no meaning for, with that family's allowed list in the
message. Resolved in one place, `Analytics::Breakdown.resolve`, so the list and the error cannot drift apart.
