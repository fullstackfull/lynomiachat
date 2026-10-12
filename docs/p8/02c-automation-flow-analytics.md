# P8.4 — Automation and flow analytics

Companion to `docs/p8/02-analytics.md`. Two families whose defining characteristic is what the product does
**not** record. Both are built around saying so rather than around filling the gap.

---

## 1. Automation execution

`GET /api/v1/accounts/:account_id/analytics/automations`

| Parameter | Values |
| --- | --- |
| `since`, `until`, `group_by` | the shared contract |
| `automation_rule_id` | validated against the account |
| `breakdown_by` | `rule` (default) \| `skip_reason` \| `status` |

### What is covered, and what is not

A **delayed** rule (`automation_rules.execution_delay` present) arms a row in
`automation_rule_pending_executions`, and that row carries its own outcome. Those rows are the entire source.

An **immediate** rule (no `execution_delay`) runs inline and writes nothing, anywhere. There is no execution
record to count. Immediate rules are therefore **absent** from these numbers rather than reported as zero, and
the response says so: when the account has any immediate rule, `meta.warnings` carries

```json
{ "scope": "immediate_rules", "reason": "no_execution_record" }
```

and `meta.partial` is `true`. The UI shows it as an amber note above the numbers.

Nothing here reconstructs an execution from a side effect. An automation that sent a message leaves a message,
but attributing messages back to rules would be inference, not a record.

### The retention window

`AutomationRulePendingExecution::RETENTION_WINDOW` is 30 days, and `purge_terminal!` deletes terminal rows past
it. A range reaching further back is incomplete **by construction**, so the response warns:

```json
{ "scope": "retention_window", "reason": "terminal_rows_purged_after_30_days" }
```

rather than presenting a truncated history as a complete one.

### Metrics

| Metric | Definition | Kind |
| --- | --- | --- |
| `episodes_armed` | rows whose `created_at` falls in the range | event |
| `executed` | `status = executed`, by `updated_at` | event |
| `skipped` | `status = skipped`, by `updated_at` | event |
| `execution_rate` | `executed / (executed + skipped)`, `nil` when neither | event |
| `awaiting_now` | the model's `armed` scope: `pending` or `processing` | **current state** |
| `stranded_now` | the model's `abandoned` scope: `executing` past the 15-minute stale timeout | **current state** |

### Why outcomes are bucketed on `updated_at` and arming on `created_at`

They are different questions. `created_at` is when the episode started its clock; `updated_at` on a terminal row
is when it reached its outcome. Bucketing an execution on `created_at` would place a Monday action on the
preceding Friday for a 72-hour delay. `updated_at` is also the column the retention sweep and the
`(status, updated_at)` index use, so the read follows the writer.

### `stranded_now` is a real operational signal, not a curiosity

A row in `executing` whose worker died is never replayed, by design: the actions are customer-facing (messages,
emails, webhooks) and repeating them is worse than dropping them
(`app/models/automation_rule_pending_execution.rb`). Nothing reclaims those rows, so before this screen a crash
that stranded customer-facing actions was invisible. Any number above zero is worth investigating, and the KPI
hint says so.

---

## 2. Flow sessions

`GET /api/v1/accounts/:account_id/analytics/flows`

| Parameter | Values |
| --- | --- |
| `since`, `until`, `group_by` | the shared contract |
| `inbox_id` | validated against the account; applied through `flow_sessions → conversations.inbox_id` |
| `breakdown_by` | `bot` (default) \| `status` \| `failure` \| `end_reason` |

### What does not exist, and is therefore not reported

**No per-node execution history.** `flow_sessions.current_node_id` holds only where a session is or where it
stopped. Nothing records the path a run took. So there are **no node-level metrics**: no per-node entry counts,
no drop-off-by-node, no path analysis. Producing them would mean inferring a path from messages, which is not a
record of what the flow did.

**No "abandoned" state.** A run that stops getting replies stays `waiting` until something ends it — the
conversation resolving, the flow being disabled — at which point it becomes `cancelled` with that reason
(`custom/app/services/flows/session_end.rb`). Calling a long-waiting run "abandoned" would invent both a state
the product does not have and a threshold nobody chose. `waiting` runs are reported as `live_now`, which is what
they are.

### Metrics

| Metric | Definition | Kind |
| --- | --- | --- |
| `sessions_started` | `created_at` in range | event |
| `sessions_completed` | `status = completed`, by `finished_at` | event |
| `sessions_failed` | `status = failed`, by `finished_at` | event |
| `sessions_cancelled` | `status = cancelled`, by `finished_at` | event |
| `handed_off` | `status = handed_off`, by `finished_at` | event |
| `completion_rate` | completed / all runs that ended in range, `nil` when none ended | event |
| `average_duration` | `AVG(finished_at - created_at)` in seconds, over runs that ended in range | event |
| `average_steps` | `AVG(steps_count)` over runs that ended in range | event |
| `live_now` | the model's `live` scope: `active` or `waiting` | **current state** |

`Flows::SessionEnd#close` writes `finished_at` for every terminal status, so filtering on it selects the runs
that **ended** in the period — a different and more useful set than the runs that started in it. Both are
reported, which is why a range can show more started than ended, or the reverse.

### Duration is wall clock, and says so

`finished_at - created_at` includes every stretch the flow spent waiting for the customer, because that is what
these two columns record. There is no per-node timing to subtract the waits from. The KPI hint states it.

### `end_reason`

`Flows::SessionEnd` writes the reason for a cancellation or a handoff into `flow_sessions.context`. `context` is
plain `jsonb` with no `ActiveRecord::Store` declaration, so `context ->> 'end_reason'` reads it directly —
unlike `messages.content_attributes` (see `docs/p8/02b-whatsapp-campaign-analytics.md` §1).

---

## 3. Tenant isolation

Both families start from `account_id` on the row itself. The flow `inbox_id` filter is the one that crosses a
table: it joins `conversations` and matches `conversations.inbox_id`, and the request spec asserts a 422 for an
inbox belonging to another account rather than a silent empty result.

---

## 4. Frontend

Both screens are the shared `AnalyticsScreen` shell with a scope, a fetcher and three series cards. Routes
`analytics_automations` and `analytics_flows`; sidebar entries Analytics → Automations and Analytics → Flows.
Copy under `ANALYTICS.AUTOMATIONS.*` and `ANALYTICS.FLOWS.*`, EN and AR.

The warning strip already built for `AnalyticsMetaNote` renders the two automation warnings without any
screen-specific code, which is what the `degrade` primitive was for.

---

## 5. Tests

| Spec | Count |
| --- | --- |
| `spec/services/analytics/automations/metrics_spec.rb` | 17 |
| `spec/services/analytics/flows/metrics_spec.rb` | 19 |
| `spec/requests/analytics/analytics_automations_spec.rb` | 12 |
| `spec/requests/analytics/analytics_flows_spec.rb` | 11 |

---

## 6. Known limitations carried forward

1. **Immediate automation rules record nothing**, so their executions can never be reported. Absent, warned,
   not approximated.
2. **Delayed automation history ends at 30 days.** Older outcomes are deleted by the retention sweep.
3. **Automation action-level success or failure is not recorded.** A row that reached `executed` says its actions
   ran, not that each one succeeded.
4. **No per-node flow metrics**, because no per-node history exists.
5. **No flow "abandoned" state**, because the product has none.
6. **Flow duration is wall clock**, including customer wait time, because no per-node timing exists to subtract.
