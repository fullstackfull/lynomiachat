# P9 security and performance

Everything in this document is **measured**, and every measurement is reproducible from the harnesses described
in §1. Where a number contradicted a design decision made earlier in P9, the decision changed and the change is
named; where it confirmed one, the confirmation is recorded rather than assumed.

Two defects were found by this phase and fixed in it. Neither was visible by reading the code:

| Found | What it was | Where it is fixed |
| --- | --- | --- |
| §2.3 | The default list index could not serve the default list. `(account_id, status, last_activity_at DESC)` puts `status` between the equality column and the sort column, so `account_id = ? ORDER BY last_activity_at DESC LIMIT 25` could not be answered by an ordered scan at all. 39.997 ms at 500,000 cases. | `custom/db/migrate/20261009100000_create_support_tickets.rb` — replaced by `(account_id, last_activity_at DESC)`. 0.057 ms. |
| §2.4 | `Support::Ticket.overdue` counted cases whose breach had already been recorded, contradicting the product's own definition of the two states and making the purpose-built partial index unusable. | `custom/app/models/support/ticket.rb` — `resolution_breached_at: nil` added to the scope. |
| §3.2 | `Operations::SignalRecorder` bounded the length of `reason` but not its content, so a provider error that quotes the credential it was given — an IMAP `LOGIN failed` is the clearest case — was stored verbatim, rendered in the Super Admin console, and copied into a support case by the bridge. | `custom/app/services/operations/signal_recorder.rb` — the subject's own secrets are removed by value, and two inline-credential shapes by pattern. |

---

## 1. Method

### The harnesses

Five passes, each a `rails runner` script that seeds a volume **inside one transaction**, runs `ANALYZE` on the
seeded tables *inside* that transaction so the planner has real statistics, takes `EXPLAIN (ANALYZE, BUFFERS,
COSTS OFF)` on every shape, and then rolls back. Each prints its row counts after the rollback; all five print
zero, which is the proof that no benchmark fixture leaked into the test database. This is the discipline P8
established after a fixture did leak and produced plans about the wrong data.

| Pass | Shape of the fixture | What it answers |
| --- | --- | --- |
| 1 | 100,200 cases / 300,600 events / 20,001 signals over 3 accounts, target holding **5%** | every shipped query shape, at the realistic multi-tenant shape |
| 2 | 200,000 cases in **one** account holding 100% of the table | the degenerate single-tenant shape — answered nothing, see below |
| 3 | 500,000 cases over 4 accounts, target holding **30%** | the two index questions, each with a candidate change measured beside it |
| 4 | 500,000 cases, target 150,000 of which only **200 active and those the oldest** | the worst case for an ordered scan that filters, and the tab-count index candidate |
| 5 | 20,200 then 45,200 signals, 200 then 5,000 of them open | the recorder's identity lookup |

**Pass 2 is recorded as a method failure, deliberately.** Putting 200,000 cases in an account that held 100% of
the table made every plan a parallel sequential scan — correctly, because when a predicate selects the whole
table a sequential scan *is* cheaper. It proved nothing about the index set, which is exactly the lesson P8
wrote down, and pass 3 was run to replace it. It is left in this document because "the fixture was wrong" is a
result worth being able to recognise a second time.

### Where the SQL comes from

Not hand-written. Every shape is taken from the **real service** through `#to_sql`, so a plan cannot drift from
the code it claims to describe:

```ruby
q = ->(params) { Support::Tickets::Query.new(account:, scope:, user:, params:).call }
explain 'S1 list, default sort, admin', sql_for(q.call({}))
```

The policy scope is likewise built by `Support::TicketPolicy::Scope.for`, so the restricted-agent plan is the
real OR-of-three, subquery and all.

---

## 2. Performance

### 2.1 The shipped shapes, at the realistic multi-tenant volume

Pass 1, after the two §2.3/§2.4 fixes. 100,200 cases, 300,600 events, 20,001 signals; the target account holds
5.0%. **Zero sequential scans on `support_tickets`, `support_ticket_events` or `operations_signals` in any of
the 40 shapes.**

| ms | Shape |
| --- | --- |
| 6.456 | SLA sweep, awaiting first response, installation-wide (see §2.5) |
| 3.110 | analytics day series, `group_by_period` over the range |
| 2.380 | analytics `tickets_reopened` (events ⋈ cases subquery) |
| 2.256 | analytics breakdown by category |
| 2.137 | analytics `tickets_created` |
| 1.696 | analytics `tickets_resolved` |
| 1.631 | analytics breakdown by assignee |
| 1.477 | list sorted by priority |
| 1.417 | analytics `open_now` |
| 1.387 | analytics average resolution seconds |
| 1.330 | tab counts, grouped by status |
| 1.268 | list sorted by resolution due time |
| 1.235 | analytics ungoverned-active count (the warning condition) |
| 1.173 | analytics `resolution_breaches` |
| 1.104 | operations open counts by account |
| 1.101 | operations identity lookup (see §2.6) |
| 0.943 | operations totals by severity |
| 0.822 | SLA sweep, awaiting resolution, installation-wide |
| 0.773 | tab count, unassigned / analytics `unassigned_now` |
| 0.680 | contact-timeline tickets adapter |
| 0.554 | list, assignee=me + active |
| 0.362 | tab count, mine |
| 0.326 | list, page 50 |
| 0.246 | list, sla=breached |
| 0.111 | list, restricted agent scope |
| 0.099 | list, unassigned + active |
| 0.095 | list filtered by contact (the contact Cases panel) |
| 0.091 | list filtered by conversation (the conversation panel) |
| 0.081 | operations open feed |
| 0.052 | **list, default sort** |
| 0.048 | list, status=active |
| 0.047 | list, `q` as a title ILIKE |
| 0.037 | analytics `overdue_now` |
| 0.036 | one case's history, page 1 |
| 0.035 | first-response detector |
| 0.031 | list, `q` as a reference |
| 0.030 | list, created-at window |
| 0.028 | tab count, overdue |
| 0.025 | list, sla=overdue |

### 2.2 What the two fixes bought, on the same fixture

Pass 1 was run twice: once against the index set and scope as originally written, once after. Same seed shape,
same machine.

| Shape | Before | After | Why |
| --- | --- | --- | --- |
| list, default sort | 1.450 ms | **0.052 ms** | ordered index scan instead of a bitmap scan over the account plus a top-N sort |
| list, `q` title ILIKE | 4.226 ms | **0.047 ms** | the ordered scan stops after 25 matches; before, it filtered all 5,000 of the account's rows and then sorted |
| list, created-at window | 1.675 ms | **0.030 ms** | same |
| list, restricted agent scope | 1.470 ms | **0.111 ms** | same, with the OR-of-three as a filter |
| list, page 50 | 1.321 ms | **0.326 ms** | same |
| list, sla=overdue | 0.781 ms | **0.025 ms** | the partial index is now usable |
| tab count, overdue | 0.940 ms | **0.028 ms** | the partial index is now usable |
| analytics `overdue_now` | 1.068 ms | **0.037 ms** | the partial index is now usable |

### 2.3 The default-list index: why the first choice was wrong

The table originally carried `(account_id, status, last_activity_at DESC)`, on the reasoning that the list is
always account-scoped, usually status-filtered, and always sorted by activity. That reasoning is wrong about how
a btree is read: with `status` between the equality column and the sort column, the index's order within an
account is *by status first*, so it cannot produce `ORDER BY last_activity_at DESC` for an account at all.

Pass 3, 500,000 cases with the target holding 30%:

```
=== P3-1 default list === 39.997 ms
  Gather Merge -> Sort (top-N heapsort) -> Parallel Seq Scan on support_tickets
      Filter: (account_id = 394)
```

With `(account_id, last_activity_at DESC)` added:

```
=== P3-1b default list === 0.057 ms
  Limit -> Index Scan using index_support_tickets_on_account_and_activity on support_tickets
      Index Cond: (account_id = 394)
```

| Shape, 500k cases, target 30% | status-leading index | `(account_id, last_activity_at DESC)` |
| --- | --- | --- |
| default list | 39.997 ms | **0.057 ms** |
| list, status=active | 25.355 ms | **0.074 ms** |
| list, page 200 | 40.763 ms | **1.976 ms** |

**Replaced rather than added.** The case the status-leading index was meant to cover is a *skewed* account — a
long history of closed cases and only a few still active, so an ordered scan has to walk past the closed ones.
Pass 4 built exactly that: 150,000 cases of which 200 are active, and those the oldest by activity, which is the
worst possible arrangement for the new index.

| Pass 4, skewed account | `status=active` | default list |
| --- | --- | --- |
| status-leading index only (as originally written) | 17.762 ms | 36.322 ms |
| both indexes present | 23.814 ms | 0.041 ms |
| status-leading index replaced | 20.283 ms | 0.038 ms |

With both present the planner chooses the activity index for `status=active` anyway, so the status-leading index
does not earn the 7 MB it costs: keeping it would buy a plan the planner does not pick. The index count stays at
eight. The honest cost of the replacement is that worst case: **20.3 ms instead of 17.8 ms** for `status=active`
on a 150,000-case account whose active cases are all ancient, against 36.3 ms → 0.04 ms on the default list.

### 2.4 `overdue` excluded breached cases — a correctness fix that was also an index fix

```ruby
# before
scope :overdue, -> { active.where.not(resolution_due_at: nil).where(resolution_due_at: ...Time.current) }
```

The product defines the two states as distinct and draws them differently: `dashboard/constants/supportTickets.js`
resolves `breached` before `overdue`, so a case with a recorded breach renders as BREACHED in the UI while the
server counted it under both labels. The Overdue tab and `overdue_now` therefore included cases the UI would
never show as overdue.

Adding `resolution_breached_at: nil` makes the scope mean what the product says it means, and — because
`index_support_tickets_on_open_resolution_due` is partial on exactly that predicate — makes the index usable for
the first time. A query that does not ask for an index's predicate cannot use a partial index at all, which is
why the index looked unused while existing.

| Pass 3, 500k cases | as shipped | with `resolution_breached_at IS NULL` |
| --- | --- | --- |
| overdue count | 23.697 ms (bitmap over the whole account) | **12.826 ms** (`index_support_tickets_on_open_resolution_due`) |

### 2.5 The SLA sweep's 6.456 ms is a fixture artefact, and the real number is 0.842 ms

The installation-wide first-response sweep is the slowest shape in pass 1:

```
Bitmap Heap Scan on support_tickets (rows=800)
  Filter: ((sla_policy_id IS NOT NULL) AND (status = ANY ('{0,1,2,3}')))
  Rows Removed by Filter: 15232
  -> Bitmap Index Scan on index_support_tickets_on_awaiting_first_response (rows=16064)
```

15,232 of 16,064 index rows are discarded, because pass 1's fixture wrote a first-response due time on cases
with **no SLA policy**, which the product never does: `Support::Tickets::SlaClock` writes a due time only when a
policy is attached. Pass 2 used realistic linkage — and for a query with no account predicate at all, pass 2's
single-account fixture is not the problem it was for the list — and there the same sweep takes **0.842 ms** for
its 500-row batch, through the primary key with the predicate as a filter.

The index predicate is deliberately *not* extended with `sla_policy_id IS NOT NULL`: deleting a policy nullifies
the link on its cases (`has_many … dependent: :nullify`) while their already-computed due times stay, by design,
and those cases should fall out of the sweep without falling out of the index's own definition of "still waiting".

### 2.6 What was measured and deliberately left alone

| Candidate | Measurement | Decision |
| --- | --- | --- |
| `(account_id, status)` for the tab counts | 28.306 ms → 24.623 ms at 500,000 cases, for 3.4 MB | **Rejected.** It does not buy an index. |
| Rewriting `SignalRecorder#open_signal` to match the COALESCE expression index | 0.058 ms → 0.055 ms at a realistic 200 open signals; 0.063 ms → 0.036 ms at a pathological 5,000 | **Rejected.** The one 1.101 ms reading in pass 1 came from a fixture with 2,001 open signals on one account, which would mean 2,001 distinct unresolved problems. The rewrite is four lines of `COALESCE(...) = ?` and is the fix if that table ever grows; it is not worth the legibility today. |
| Caching the tab counts | not implemented | The grouped count is the biggest remaining cost (**1.330 ms** at 100k, **36.965 ms** at 500k with one account holding 150,000 cases). Production holds zero support cases today. Named here as the first thing to revisit, not pre-solved. |

### 2.7 The Operations Center has no N+1 across accounts

`Operations::AccountHealth` pages 25 accounts and then issues **one grouped query per component**, each
restricted to that page's ids, rather than one query per account. The feed is bounded at
`OperationsController::ISSUE_PAGE_SIZE = 50` and reads `index_operations_signals_on_open_feed`, a partial index
holding only unresolved rows (0.081 ms over 2,001 open signals). `Operations::Overview`'s computed signals are
cached for 5 minutes under `operations:computed_signals` and carry a `computed_at` so the page says how old the
reading is instead of implying it is live. Account totals use `reltuples`, which is the estimate the existing
Super Admin dashboard already uses, not a `COUNT(*)` over every table.

---

## 3. Security

### 3.1 Tenant isolation, proved against a mirrored fixture

`spec/requests/support/p9_tenant_isolation_spec.rb` builds **two accounts with the same shape of data** — same
case title pattern, same contact, same team, same SLA policy name, and (because reference numbers are
per-account) *the same case reference* in both. A missing account predicate then shows up as a doubled count or
a borrowed record rather than as nothing at all, which is the failure a single-tenant fixture cannot see.

24 examples covering: the list and its tab counts; one case by id and by reference; history; note writing; SLA
policy index, show, update and destroy; case analytics; the contact activity timeline; and the ownership rule for
an agent without `support_ticket_manage`.

Three behaviours worth naming:

- **A filter id from the other account is a 422 naming the filter, never an empty page.** `contact_id`,
  `team_id` and `assignee_id` are each resolved through the account before they reach a query
  (`Support::Tickets::Query#resolved_id`). An empty page would read as "this customer has no cases".
- **A case the caller may not see is a 404, not a 403.** A 403 confirms the record exists. The same holds for a
  case inside the caller's own account that the ownership rule excludes.
- **The same reference in two accounts resolves to the caller's own.** `TCK-000001` exists in both tenants; the
  lookup goes through the policy scope, so it returns the reader's.

### 3.2 No surface P9 adds renders a credential

The defect this found is in the table above. What makes the test worth having is the fixture: it plants values
that are **really stored** on records the console really reads, and asserts they are stored before asserting
they do not appear.

```ruby
expect(whatsapp_inbox.channel.reload.provider_config['api_key']).to eq(secrets[:whatsapp_api_key])
expect(email_inbox.channel.reload.imap_password).to eq(secrets[:imap_password])
expect(store.reload.credentials['access_token']).to eq(secrets[:salla_access])
```

A WhatsApp Cloud channel's `api_key`, an IMAP mailbox's `imap_password` and `smtp_password`, and a Salla store's
OAuth access and refresh tokens. The pre-existing leakage check in the controller spec guarded a
`create(:inbox)`, which is a web-widget channel with no `provider_config` at all — its setup was a silent no-op,
so it passed while proving nothing.

Each is then recorded through `Operations::SignalRecorder` with the provider's own prose as the `reason`, the
way the product records it, and four things are asserted:

1. the signal rows hold none of the planted values, and every `detail` key is on `DETAIL_KEYS`;
2. none of the three console pages renders any of them, nor the strings `imap_password`, `smtp_password`,
   `provider_config`, `access_token` or `refresh_token`;
3. a support case opened from an issue through `Operations::CaseBridge` carries none of them in its title,
   description or history;
4. a case's audit row carries no `description` (`audited … except: [:description]`) — a customer may have
   dictated a card number into it, and an audit row is not the place for a second copy.

**How the reason is sanitized.** Two mechanisms, neither of them a guess about what a secret looks like:

- **By value.** The recorder is constructed with the record the observation is *about*, so it can read that
  record's own secrets and remove them by exact value. This is the only place in the product that knows both
  "what failed" and "what its credentials are", which is what makes an exact match possible here and nowhere
  else. It reads `provider_config` and `credentials` (hash columns) and `imap_password` / `smtp_password` (plain
  columns), each defensively, so a subject class that does not answer still gets its signal recorded.
- **By shape.** A URL's userinfo (`//user:pass@host`) and a `key=value` pair whose **key** names a credential
  (`password`, `token`, `api_key`, `secret`, `authorization`, `bearer`, …).

Nothing is matched on entropy or length. That is a deliberate refusal: an entropy rule redacts the order ids,
`wamid`s and message ids an operator needs in order to act, while still missing a short password. The spec pins
both directions — `Meta returned 131049 for wamid.HBgMOTY1NTAwMTEyMjMzFQIAERgSN0Y` passes through unchanged.

### 3.3 The fields a client may not write

`spec/requests/operations/p9_hardening_spec.rb` sends every server-owned field in one request and asserts each
is ignored: `account_id`, `reference_number`, `created_by_id`, `source_type`, `source_id`, all seven SLA
timestamps, `sla_paused_seconds`, `resolved_at`, `closed_at` and `last_activity_at`. Also that a note cannot be
attributed to another user or given another event type — `Support::Tickets::EventRecorder` takes the actor from
the session and the type from the controller, so `user_id` and `event_type` in a request body are inert.

### 3.4 The polymorphic source is allow-listed

`support_tickets.source_type` is a plain string column with `validates … inclusion: { in: SOURCE_TYPES }`, which
is the house pattern (`custom/app/models/commerce/action_run.rb`) and is not optional here: an unvalidated
polymorphic type is an arbitrary-class read. `SOURCE_TYPES` is `%w[Operations::Signal]` — one entry, because one
thing opens a case on its own. The spec proves `'User'` is refused and `Operations::Signal` is accepted.

### 3.5 Authorization

| Surface | Boundary |
| --- | --- |
| `support/tickets`, `support/.../events` | account feature gate → Pundit `Support::TicketPolicy` → `Scope` (administrator or `support_ticket_manage` ⇒ the account; otherwise assignee, team, or creator) |
| `support/sla_policies` | account feature gate → `check_admin_authorization?` — an account-wide commitment follows the administrator boundary, not the per-case one |
| `analytics/tickets` | the existing `reports` feature gate and analytics authorization, unchanged |
| the contact timeline's `tickets` category | `Support::TicketPolicy::Scope.for`, the *same* rule as the list, so the two cannot drift |
| `super_admin/operations` | `authenticate_super_admin!`, which is the only guard the Administrate stack has; proved for an unauthenticated caller, a tenant administrator and a tenant agent, on all three pages and the one mutation |

A disabled feature answers **404, not 403**: the account has no support module, so the endpoint does not exist
for it, and a 403 would tell a caller what it could have if it paid.

### 3.6 Rate limiting

Two throttles added to `config/initializers/rack_attack.rb`, both keyed per **user within the account** the way
the existing reports throttle is — keying per account alone would let one agent's refresh loop throttle their
colleagues:

| Throttle | Limit | Override |
| --- | --- | --- |
| `GET /api/v1/accounts/:id/support/*` | 300/min | `RATE_LIMIT_SUPPORT_TICKETS` |
| `GET /api/v1/accounts/:id/analytics/*` | 120/min | `RATE_LIMIT_ANALYTICS` |

Both are set where a human cannot reach them and a loop can: the workspace refetches once per navigation and
debounces its search at 500 ms, and an Analytics screen fires one request per metric family. The analytics
throttle also closes a pre-existing gap — no `/api/v1/.../analytics/` path was throttled before, including the
six families P8 shipped.

The Super Admin console is **not** throttled, and that is a decision rather than an omission: it sits behind
`authenticate_super_admin!`, its expensive part is cached for 5 minutes, and the population that can reach it is
the people who run the installation.

---

## 4. What this phase did not do

- **No load test.** Plans and timings on a seeded fixture are not concurrency. There is no claim here about
  behaviour under parallel traffic.
- **No measurement against production data.** Production holds zero support cases and zero operations signals;
  P9 has never been deployed. Every number here is from a synthetic fixture whose shape is argued for in §1, not
  from the real table.
- **No `pg_stat_statements` reading.** The extension is enabled and still unread, as P8 recorded.
