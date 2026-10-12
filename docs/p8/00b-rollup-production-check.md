# P8 — read-only production rollup check

**This session cannot reach production.** Verified in the container: no `ssh` binary, no `~/.ssh` keys, no `.env`,
no `POSTGRES_*` environment, no production host in any git remote. So the check below is for you to run on the
application host. Everything here is **read-only**: `SELECT` only, no mutation, no backfill, no enqueue, no
configuration change. It returns counts, dates and account ids only — no customer data, no message content.

Access uses the same credential-free peer-auth path the deploy runbook established and that `ROLLBACK.md` already
uses: `sudo -u postgres psql -d chatwoot_production`. One command at a time; read each result before the next.

---

### R1 — is the rollup table populated at all, and over what span

```
sudo -u postgres psql -d chatwoot_production -Atc "select count(*) as rows, count(distinct account_id) as accounts, min(date) as first_date, max(date) as last_date from reporting_events_rollups"
```

**Reading it:** `rows = 0` means the optimisation is unavailable and P8 runs entirely on raw events — which is the
designed default, not a problem. A `last_date` far in the past means the rollup is stale.

### R2 — which accounts have a reporting timezone, which is what gates the rollup write

```
sudo -u postgres psql -d chatwoot_production -Atc "select count(*) as accounts_total, count(*) filter (where settings->>'reporting_timezone' is not null and settings->>'reporting_timezone' <> '') as with_reporting_timezone from accounts"
```

```
sudo -u postgres psql -d chatwoot_production -Atc "select id, settings->>'reporting_timezone' as reporting_timezone from accounts order by id"
```

**Why this is the decisive one:** `ReportingEvents::RollupService#rollup_enabled?` returns false unless
`account.reporting_timezone` is present *and* a valid `ActiveSupport::TimeZone`. An account without it has **no
rollup rows at all**, however much raw history it has.

### R3 — per-account rollup presence and span

```
sudo -u postgres psql -d chatwoot_production -Atc "select account_id, count(*) as rows, min(date) as first_date, max(date) as last_date, count(distinct metric) as metrics, count(distinct dimension_type) as dimension_types from reporting_events_rollups group by account_id order by account_id"
```

### R4 — raw event baseline, for the coverage comparison

```
sudo -u postgres psql -d chatwoot_production -Atc "select account_id, count(*) as raw_events, min(created_at)::date as first_event, max(created_at)::date as last_event from reporting_events group by account_id order by account_id"
```

```
sudo -u postgres psql -d chatwoot_production -Atc "select name, count(*) from reporting_events group by name order by 2 desc"
```

**Expect** the names to be a subset of `conversation_resolved`, `first_response`, `reply_time`,
`conversation_bot_handoff`, `conversation_bot_resolved`, `conversation_opened`. Anything else is a surprise worth
reporting.

### R5 — approximate coverage: do the rollups agree with the raw events they aggregate

Compares the rollup's `resolutions_count` against the raw `conversation_resolved` rows, per account, bucketed in
that account's own reporting timezone (the same timezone the rollup writer used):

```
sudo -u postgres psql -d chatwoot_production -Atc "with tz as (select id, coalesce(nullif(settings->>'reporting_timezone',''), 'UTC') as zone from accounts), raw as (select r.account_id, (r.created_at at time zone 'UTC' at time zone t.zone)::date as d, count(*) as n from reporting_events r join tz t on t.id = r.account_id where r.name = 'conversation_resolved' group by 1,2), roll as (select account_id, date as d, sum(count) as n from reporting_events_rollups where metric = 'resolutions_count' and dimension_type = 'account' group by 1,2) select coalesce(raw.account_id, roll.account_id) as account_id, count(*) as days_compared, count(*) filter (where coalesce(raw.n,0) = coalesce(roll.n,0)) as days_matching, count(*) filter (where coalesce(raw.n,0) <> coalesce(roll.n,0)) as days_differing, sum(coalesce(raw.n,0)) as raw_total, sum(coalesce(roll.n,0)) as rollup_total from raw full outer join roll on raw.account_id = roll.account_id and raw.d = roll.d group by 1 order by 1"
```

**Reading it:** `days_differing = 0` with equal totals means coverage is valid for that account.
`rollup_total > raw_total` is the additive-upsert double count (`rollup_service.rb:73-79` adds rather than
replaces, so a re-run inflates). `rollup_total < raw_total` means the rollup starts later than the raw history.
Either way P8 does not use the rollup for that account.

### R6 — are recent periods present

```
sudo -u postgres psql -d chatwoot_production -Atc "select account_id, count(*) filter (where date >= current_date - 7) as last_7d, count(*) filter (where date >= current_date - 30) as last_30d, count(*) filter (where date >= current_date - 90) as last_90d from reporting_events_rollups group by account_id order by account_id"
```

### R7 — table sizes, for the performance baseline

```
sudo -u postgres psql -d chatwoot_production -Atc "select relname, n_live_tup, pg_size_pretty(pg_total_relation_size(relid)) as total from pg_stat_user_tables where relname in ('reporting_events','reporting_events_rollups','messages','conversations','contacts','campaign_recipients','csat_survey_responses','flow_sessions','commerce_carts','commerce_action_runs','automation_rule_pending_executions','audits') order by n_live_tup desc nulls last"
```

**Why P8 wants this:** row counts decide whether an index is warranted. `n_live_tup` is the planner's estimate,
which is the number the planner itself uses, so it is the right input — and it costs nothing to read.

---

## What the answers change, and what they do not

| Outcome | Effect on P8 |
| --- | --- |
| rollups empty or no `reporting_timezone` | **none.** Raw is the source of truth; the rollup path simply never activates |
| rollups present and R5 shows exact agreement | the rollup path may be enabled per account as an optimisation, behind coverage validation |
| rollups present but R5 differs | rollup is **not** used for that account; P8 logs the mismatch and reads raw |
| rollups stale (old `last_date`) | the coverage check fails for recent dates, so raw is used for them |

**Rollup availability is not a P8.1 blocker and P8.1 does not depend on the answer.** Record the output in
`docs/p8/00-discovery.md` §1.4 when you have it, replacing the `NOT ESTABLISHED` note there.
