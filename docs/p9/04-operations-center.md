# The Operations Center

Super Admin → **Operations**. Three pages and one button, for the person who runs the installation rather than
the people who use it.

The problem it solves is not "there is no monitoring page" — `Instance Health` and `Sidekiq Dashboard` already
exist. It is that **operational problems in this product were a log line or a Redis key with no TTL**, so there
was nothing for a page to read. `00-discovery.md` has the table; the worst case is an IMAP mailbox whose
password was rotated: it wrote nothing durable at all and then *stopped polling itself*, so the only symptom was
an inbox that went quiet.

So P9 adds the durable record first (`05-integration-health.md`) and the console reads it.

---

## 1. The one rule

**Unknown is not healthy.** A component with no source reports `absent`; a probe that cannot run reports
`unknown`; a signal store with nothing in it says "nothing has been recorded" rather than showing a green badge.

`SEVERITY_ORDER` deliberately ranks `unknown` *above* `healthy`, so a page with one unreadable component cannot
present itself as fine. A console that invents green is worse than no console, because an operator starts
trusting it.

There is also **no health score**. Not "87% healthy": a score is a number nobody can act on, and averaging an
unknown into it turns missing information into a reassuring digit. Each component stands or falls on its own and
a row's badge is the worst of its components.

---

## 2. Page one: the installation

### Probes — read live, this request

| Probe | How |
| --- | --- |
| database | one `SELECT 1` |
| redis | one `PING`, plus `used_memory` and client count from `INFO` |
| workers | the Sidekiq process set; **critical at zero processes**, because no worker means nothing is running |
| migrations | `ActiveRecord::MigrationContext#needs_migration?` — pending is a **warning**, because the running code and the schema disagree |
| release | version, git SHA, edition, `ChatwootApp.extensions` — facts with no health of their own |

Deliberately cheap: no shell command, no provider call, no table scan. An operator opening a page must not cost
the installation anything it would notice.

This overlaps the existing Instance Status page by one query and one PING. That page is linked to rather than
rewritten: it keeps its fuller Redis dump, and refactoring an OSS controller to share two lines would be a
bigger change than the duplication it removes.

> A bug worth recording: the migrations probe first used `connection.migration_context`, which does not exist on
> Rails 7.2. It raised, the probe's rescue turned it into `unknown`, and the page looked plausible while
> reporting nothing. Found by reading the page, not by a failing test — which is why "unknown" is a visible
> state with a reason attached rather than a blank.

### Computed signals — what the product's own tables say

Six areas, **one grouped query each**, no per-account loop, cached for 5 minutes under
`operations:computed_signals` with a `computed_at` so the page says how old the reading is.

| Area | Source | Healthy / warning / critical |
| --- | --- | --- |
| WhatsApp delivery | failed outgoing messages in 24h | 0 / ≥ 25 / ≥ 250 |
| WhatsApp templates | `meta_status = REJECTED`, **no window** — a rejection from last month is still a rejection | 0 / any |
| Campaigns | per-campaign failure **rate** over 7 days | < 10% / ≥ 10% / ≥ 50% |
| Automations | `AutomationRulePendingExecution.abandoned` | 0 / any |
| Flows | failed `flow_sessions` in 24h | 0 / ≥ 10 |
| Commerce | stores `needs_reauth` or `disconnected` | 0 / — / any |

Every threshold is a named constant with an environment override, and every component's `detail` carries the
threshold it used. "One failed recipient is critical" would train an operator to ignore the badge, so the
numbers are explicit and arguable rather than implicit.

Two choices worth defending:

- **Campaigns are a rate, not a count.** Ten failures out of ten is a broken campaign; ten out of ten thousand
  is a Tuesday. A minimum of 5 recipients stops a two-person test campaign reading as a 50% failure.
- **An area with no source is `absent`, not green.** No WhatsApp inbox, no synced template, no commerce store,
  no recent campaign — each says so, with the reason.

### The signal feed

The most recent open signals from `operations_signals`, bounded at 50 per page, read from a partial index
holding only unresolved rows.

---

## 3. Page two: accounts

One page of 25 accounts, each with five component statuses: the account itself (status and feature state),
open signals, channels, commerce, and support cases.

**No N+1, by construction.** The existing Super Admin accounts index pays two uncached `COUNT`s per row through
`CountField`, which is 40 queries for a page of 20. This takes one page of accounts and then **one grouped query
per component restricted to that page's ids** — six queries, fixed whatever the page size. Measured at 1.104 ms
over 20,001 signals.

---

## 4. Page three: issues

The signal feed with an open / resolved / all filter, 50 per page. Each row shows the source, the signal, its
severity, how many times it has recurred, when it was first and last seen, which account and which subject it
belongs to, and the sanitized reason.

---

## 5. The one button: open a support case

`Operations::CaseBridge` turns an issue into a support case, which is what closes the loop between "something
is broken" and "somebody owns fixing it".

| | |
| --- | --- |
| Priority | critical → `urgent`, warning → `high`, info → `medium` |
| Category | `operational` |
| Link | `source_type: 'Operations::Signal'`, and `operations_signals.support_ticket_id` back |
| `created_by` | **nil** — a super admin is not an account user, and borrowing an account's administrator would put a name in the audit trail that did nothing |
| Idempotent | while the linked case is still active, the button surfaces *that* case instead of opening a second |
| Reopened | once the linked case is closed, a recurrence opens a new one |

**An installation-wide signal cannot become a case**, and the button says so with a reason.
`support_tickets.account_id` is `NOT NULL`, and a synthetic "operations account" to hold such cases would be a
worse lie than an honest refusal: it would appear in every account list, every count and every report.

Every open is written to `Lynomia::OperatorLog` with the acting super admin's email, the signal and the case.

---

## 6. What it cannot tell you

Stated here because a monitoring page that implies completeness is the dangerous kind:

- **It is not live.** Computed signals are up to 5 minutes old and the page says so. Probes are live.
- **It cannot see a provider that has not failed yet.** Nothing here calls Meta, Salla, Zid or Shopify. Every
  area reads a durable record of something that already happened.
- **It has no history.** `operations_signals` holds one row per distinct open problem with a recurrence count,
  not a time series. "Was this worse last week?" is not a question this page answers.
- **It does not mutate Sidekiq.** No retry, no kill, no clearing the dead set. `Sidekiq::Web` is already mounted
  at `/monitoring/sidekiq` behind the same super-admin guard and does all of that properly.
- **It cannot enable or disable anything.** The console is read-only apart from the one case button. Feature
  flags, provider gates and credentials are not touched from here.
