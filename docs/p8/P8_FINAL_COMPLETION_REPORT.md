# P8 final completion report

Lynomia Analytics and the Contact Activity Timeline.

Branch `claude/p8-analytics-contact-timeline`, cut from `lynomia-custom` at
`b03ea43df6abf18cb9c4e5d6a9271ba040b689f4`.

---

## A. Executive summary

P8.2 through P8.9 are complete. The account now has six analytics screens and every contact has an activity
timeline, and both are built entirely on records the product was already writing.

Nothing was added to the database. No migration, no table, no column, no index, no job, no listener, no
outbound call, no dependency. Every number on every screen is a read of an existing row, which is why there is
no period before the feature existed where the screens are blank, and no second source of truth that can
disagree with the first.

Three things are worth a reviewer's attention more than the feature list:

1. **One timezone, proved rather than asserted.** Every bucket boundary in all six families is cut in
   `Account#reporting_timezone`. The client sends calendar dates, never instants, so a viewer's clock cannot
   reach the grouping. Executed against a live instance: three account timezones moved the window, three
   different viewer timezones moved not a single number.

2. **The limitations are published on the screens, not buried in a document.** Where the product never recorded
   something, the metric is absent and the response says why — immediate automation rules leave no execution
   record, flows have no node history and no abandoned state, carts carry a per-cart currency so no revenue can
   be summed. Nothing was reconstructed from localized prose.

3. **Executing the UAT runbook found a defect the 352 new examples had not.** Private notes were being counted
   as WhatsApp sends — 4 sends and a 75% delivery rate where 3 and 66.7% were correct. It is fixed, with a spec
   labelled for where it came from. That is the single strongest argument in this report for having run the
   runbook rather than only writing it.

Full Ruby suite: **9058 examples, 0 failures.** Full JS suite: **5166 tests, 0 failures.** RuboCop: **0
offenses** over 2771 files. Production was never touched.

Verdict: **PASS WITH KNOWN LIMITATIONS** (§U).

---

## B. Product features delivered

| Feature | What an operator can now do |
| --- | --- |
| Analytics section | A new top-level sidebar group with six screens, behind the existing `reports` feature flag and the existing administrator-only report permission |
| Operational overview | See how much work arrived, how much closed, how much is still open, how fast the team responds, and where the volume sits — in one request |
| WhatsApp delivery | See whether WhatsApp is actually delivering, across every send in the account: campaign, flow, automation or agent |
| Campaign performance | See the period's one-off campaigns as a funnel, from the recipient snapshot that is also their audience record |
| Automation activity | See what the delayed automation rules did, with an explicit warning about what cannot be covered |
| Flow activity | See flow session lifecycle, with no invented states |
| Commerce activity | See cart lifecycle and order actions, provider-neutral, with no money anywhere |
| Contact activity timeline | Open any contact and read one ordered story of everything that happened with them, across eight sources, filterable and paged |
| Date range and grouping | Pick a range and a Day/Week/Month grouping that cannot produce a rejected request |
| Honest footnotes | Every screen states its range, its grouping, its timezone and where its numbers came from |

---

## C. Analytics screens delivered

Six screens, each about fifteen lines of page code because they share one `AnalyticsScreen` component:

| Screen | Route | KPIs | Series | Breakdown dimensions |
| --- | --- | --- | --- | --- |
| Overview | `/analytics` | 8 | 4 | inbox, channel, team, agent |
| WhatsApp delivery | `/analytics/whatsapp` | 9 | 3 | template, inbox, failure |
| Campaigns | `/analytics/campaigns` | 11 | 3 | campaign, audience, failure, skip reason |
| Automations | `/analytics/automations` | 6 | 3 | rule, skip reason, status |
| Flows | `/analytics/flows` | 9 | 3 | bot, status, failure, end reason |
| Commerce | `/analytics/commerce` | 12 | 3 | provider, store, currency, action type, action error |

Each screen is one request, not one request per number. Routes carry `featureFlag: FEATURE_FLAGS.REPORTS` and
`permissions: ['administrator', 'report_manage']`, so the group is invisible without the flag and unreachable
without the permission.

---

## D. Metrics delivered and definitions

**55 metrics. 49 historical, 6 current state.** Every current-state metric is labelled `kind: "current_state"`
in the response so a screen cannot plot a reading taken now as if it were a history.

### Conversations (7 historical + 1 current)

| Metric | Definition |
| --- | --- |
| `conversations_created` | `conversations.created_at` inside the window |
| `conversations_resolved` | `reporting_events` named `conversation_resolved` |
| `conversations_reopened` | `conversation_opened` rows where `event_start_time <> conversations.created_at`. That is the discriminator the listener itself established: a first open writes the conversation's own `created_at`, a reopen writes the end of the preceding resolution. It holds for any number of cycles. `value > 0` would be the obvious shortcut and is wrong — a conversation reopened in the same second as its resolution has value 0 |
| `avg_first_response_time` | average `reporting_events.value` for `first_response`. The OSS definition, unchanged |
| `avg_resolution_time` | average `reporting_events.value` for `conversation_resolved`. The OSS definition, unchanged |
| `inbound_messages` | `Message.chat` (not an activity row, not private), `message_type: incoming` |
| `outbound_messages` | the same, `outgoing`. A WhatsApp approved-template send is an ordinary outgoing message and is counted; a system template — greeting, out-of-office, CSAT, email collect — carries `message_type: template` and is not |
| `unresolved_backlog` | **current state.** `conversations.status IN (open, pending)`. `snoozed` is excluded: a snoozed conversation is deliberately out of the queue until it wakes, so counting it would overstate what an agent faces |

Both averages return `null`, never `0`, when there is nothing to average. The screen renders `—`.

### WhatsApp (8 + `coexistence_echoes`)

`messages_sent`, `template_messages_sent`, `delivered`, `read`, `failed`, `delivery_rate`, `read_rate`,
`failure_rate`, `coexistence_echoes`. Definitions in §E.

### Campaigns (11)

`campaigns_run`, `recipients_targeted`, `sent`, `delivered`, `read`, `failed`, `skipped`, `pending`,
`delivery_rate`, `read_rate`, `failure_rate`. Definitions in §F.

### Automations (4 + 2 current)

`episodes_armed`, `executed`, `skipped`, `execution_rate`, and the current-state `awaiting_now`,
`stranded_now`. Definitions in §G.

### Flows (8 + 1 current)

`sessions_started`, `sessions_completed`, `sessions_failed`, `sessions_cancelled`, `handed_off`,
`completion_rate`, `average_duration`, `average_steps`, and the current-state `live_now`. Definitions in §G.

### Commerce (10 + 2 current)

`carts_seen`, `carts_abandoned`, `carts_targeted`, `carts_completed`, `post_target_completions`,
`untargeted_completions`, `order_actions_requested`, `order_actions_failed`, `recovery_messages_prepared`,
`targeting_rate`, and the current-state `open_abandoned_now`, `actions_unresolved_now`. Definitions in §H.

---

## E. WhatsApp analytics

Every outgoing WhatsApp message in the account, whatever sent it.

**Delivery is `status IN (delivered, read)`, and the limitation is published.** `messages` carries no per-status
timestamps, only a single `status` column holding the furthest state reached — and
`Messages::StatusUpdateService#valid_status_transition?` permits any transition to or from `failed`, so a
message that was delivered and then failed reads only as failed. Delivery is therefore understated for exactly
that case. The family note and the screen's footnote both say so. Where authoritative timestamps *do* exist —
campaign recipients — they are used instead (§F).

**Coexistence echoes are excluded from every count and every rate, and reported separately.** A message sent
from the WhatsApp Business app arrives back as `message_type: outgoing, status: delivered, sender: nil,
content_attributes: {external_echo: true}`. That `delivered` is written **locally**, to stop `SendReplyJob` — it
is not a Meta receipt. Counting echoes would push the delivery rate toward 100% on exactly the accounts where it
matters most.

Finding them required solving a real problem: **`messages.content_attributes` is not readable with the ordinary
JSON operators.** It is a `json` column, but the model declares `store :content_attributes`, so
ActiveRecord::Store serialises the hash to a JSON *string* which the column then encodes again. The stored value
is `"{\"external_echo\":true}"`, and `content_attributes ->> 'external_echo'` returns NULL for every row in the
table. The family decodes it with `(messages.content_attributes #>> ARRAY[]::text[])::jsonb`, which works for
both the double-encoded and the plain shape. This was established by querying the real column, not assumed.

**Private notes are excluded.** A private note is an internal message, never handed to Meta, and its `status` is
whatever was written locally — so it has no delivery state to report. This was the one defect executing the UAT
runbook found; the fix cites `Message.chat` for making the same exclusion for the same reason.

The template breakdown reads `additional_attributes -> 'template_params' ->> 'name'`, which *is* plain jsonb and
directly queryable. The failure breakdown reads Meta's own `external_error` wording rather than inventing
categories.

---

## F. Campaign and audience analytics

**`campaign_recipients` is both the snapshot and the funnel.** There is no separate execution engine to read and
none was built.

**Delivered and read come from the timestamps being present, never from status equality:**
`delivered_at IS NOT NULL OR read_at IS NOT NULL`. This matters because the recipient ladder is forward-only
under a row lock: a late `delivered` webhook backfills `delivered_at` without downgrading a row that already
reached `read`, and `failed` is refused after delivered or read. Counting `status == 'delivered'` would silently
drop every recipient who went on to read the message.

**The existing per-campaign analytics was extended, not replaced.** Its controller stays where it is and its
response keys are unchanged; its `delivery_metrics` now computes delivered through the same
`Analytics::Campaigns::Metrics::DELIVERED_SQL` constant, so the per-campaign screen and the Campaigns family
share one definition and cannot drift. Verified live in the UAT: both reported
`{sent: 1, delivered: 1, read: 1, failed: 0, skipped: 1}` against an audience of 2.

**Audiences stayed dynamic.** Nothing was materialised or snapshotted. The audience breakdown counts
**campaigns per targeted audience or label, never recipients**, because a campaign keeps only a reference to
each audience and resolves membership at send time — so no recipient can honestly be attributed to a source.
That is a published property of the breakdown, not an omission.

---

## G. Automation and flow analytics

### Automations — delayed rules only, and the screen says so

The family reads `automation_rule_pending_executions` and `automation_rules`. No second engine.

Outcomes are bucketed on `updated_at`, which is when the episode reached its outcome and is also the column the
retention sweep and the `(status, updated_at)` index use. `episodes_armed` is bucketed on `created_at`, because
when an episode was armed is a different question.

Two degradations are reported in `meta` rather than left for the reader to discover:

- `immediate_rules: no_execution_record` — an immediate rule runs inline and writes nothing, so its history does
  not exist. It is absent rather than reported as zero, and the response says how many such rules the account
  has.
- `retention_window: terminal_rows_purged_after_30_days` — when the requested range reaches past the 30-day
  retention window.

`awaiting_now` (episodes still bound to fire) and `stranded_now` (a row whose worker died mid-execution) are
current state, whatever the range.

### Flows — lifecycle only

The family reads `flow_sessions`. No second bot runtime, no node instrumentation.

**No node-level metrics**, because no per-node execution history is stored. **No abandoned state**, because the
product has none: a session with no further replies stays waiting until something ends it. Inventing either
would mean inventing data.

`average_duration` is stated for what it is — wall-clock `finished_at - created_at` — and returns `null`, not
zero, when nothing finished. The end-reason breakdown reads `context ->> 'end_reason'`, the value the runtime
itself writes.

---

## H. Commerce analytics

Provider-neutral throughout: every metric reads `commerce_carts` and `commerce_action_runs`, and `provider` is a
filter and a breakdown, never a branch in the code.

**No revenue, GMV or profit, and no second order database.** `visible_total` is never summed anywhere. Carts
carry a per-cart currency and nothing in the product converts between currencies, so a sum would be a number
with no unit. The currency breakdown therefore reports **cart counts** per currency. Orders are read where they
already live; no order table, mirror or cache was created.

**No recovery attribution.** `post_target_completions` is defined as
`targeted_at IS NOT NULL AND completed_at > targeted_at` — a completion that followed outreach. That is a time
ordering, not a proof of cause, and it is named for the ordering it measures. `untargeted_completions` sits
beside it so a reader can see the base rate instead of reading the first number as a recovery figure. The UI
hint says this in as many words.

`order_actions_requested`, `order_actions_failed` and `recovery_messages_prepared` come from
`commerce_action_runs`. `open_abandoned_now` and `actions_unresolved_now` are current state.

The browser UAT asserts there is no money wording anywhere on the screen, and it passed.

---

## I. Contact activity timeline

A new **Activity** tab on every contact, beside the existing History tab.

**It is a read projection, not an event table.** Eight adapters read ten existing tables in place: messages,
conversations and their activity messages, `reporting_events`, `csat_survey_responses`, `campaign_recipients`,
`automation_rule_pending_executions`, `flow_sessions`, `commerce_carts`, `commerce_action_runs` and
`commerce_customer_links`. Writing those events a second time into a timeline table would create a source of
truth that could disagree with the first, and would be empty for everything that happened before it existed.

**Each adapter is account-scoped and contact-scoped on its own.** No adapter relies on another having filtered
for it, so adding one cannot widen what an earlier one returned.

**Permissions follow the contact, not the report.** The controller authorizes `@contact, :show?` — an agent may
read a contact's timeline, which is the point of the feature. Inside it, conversation-derived adapters read
through `Conversations::PermissionFilterService`, the same filter the contact's attachment list already uses, so
an agent restricted to some inboxes cannot learn through a timeline what happened in a conversation they cannot
open. Sources that carry an inbox but no conversation use the caller's own visible inbox set, deliberately
rather than deriving it from this contact's conversations — the latter would hide a campaign that addressed the
contact in an inbox they have never written in.

**Core versus optional is a correctness rule, not a convenience.** Messages and conversation events are what a
contact timeline *is*: if either cannot be read the request fails, because a timeline missing the communication
is wrong rather than partial. Every other adapter degrades to a `{scope:, reason: 'unavailable'}` warning plus
`partial: true` — a commerce table being unreachable must not hide the conversation history. The rescue is
narrowed to `ActiveRecord::ActiveRecordError`, `NoMethodError` and `KeyError` so an authorization error can
never be downgraded to a warning.

**Paging is mandatory and bounded**: cursor-based, default 30, hard maximum 100, no unpaginated mode and no
"all" limit. The cursor is the last entry's own sort key, so order is stable across pages.

**Localized activity messages are passed through as prose.** Only `conversation_status_changed` carries
structured `content_attributes.activity`, and only that one is read structurally. Assignee, team, label and
priority changes are shown as the human-readable text they are, never parsed into fake structure.

Five filter categories — messages, conversations, campaigns, automations, commerce — where `conversations` spans
activity messages, reporting events, CSAT and flow outcomes, because to an operator those are all "what happened
in the conversations".

---

## J. Architecture

Chatwoot OSS core plus the Lynomia `custom/` overlay, unchanged. Lynomia-exclusive code takes a top-level
namespace (`Analytics::`, `Contacts::`); `Custom::X` stays reserved for `prepend_mod_with` overrides.

Every family is two objects with one job each:

- **`Metrics`** — the SQL. One method per metric, plus `series` and `breakdown`.
- **`Overview`** — the assembler. Which KPIs, which series, which breakdown, and the `meta`.

Shared across all six:

| Object | Role |
| --- | --- |
| `Analytics::DateRange` | calendar dates in the account timezone → UTC instants, bucket counts, ceilings |
| `Analytics::FilterSet` | validates every filter id against the account before it can reach a query |
| `Analytics::MetricFamily` | what each screen may ask for, and whether a rollup row could answer it |
| `Analytics::Breakdown` | one resolver, so a family's allowed list and its error cannot drift apart |
| `Analytics::Result` | KPI / series / breakdown / meta response primitives, with `degrade` for published limitations |
| `Analytics::RollupCoverage` | the all-or-nothing raw-versus-rollup decision, with its reason |
| `Analytics::RequestScoped` | `Current.account` only; `params[:account_id]` is never trusted |

Reuse rather than replacement, concretely: `avg_first_response_time` and `avg_resolution_time` are the OSS
`reporting_events` definitions; the conversation metric vocabulary points at
`ReportingEvents::MetricRegistry::REPORT_METRICS` so there is one definition of a conversation metric and not
two; bucketing uses `groupdate`'s `group_by_period(..., time_zone:)`, the same mechanism the existing v2 report
builders use; charts go through the existing `@chatwoot/viz` `BarChart` wrapper; the timeline reuses
`Conversations::PermissionFilterService`; the analytics screens reuse `ReportPolicy#view?`.

`enterprise/` does not exist, `ChatwootApp.extensions` is `['custom']`, and no P8 source file mentions
Enterprise.

---

## K. Database, schema and index changes

**None.**

`git diff` against the base touches no file under `db/`, and no `Gemfile`, `Gemfile.lock`, `package.json` or
`pnpm-lock.yaml`. No migration, no table, no column, no index, no job, no listener, no callback, no outbound
call. Every P8 service is a read.

No new charting or analytics dependency: `@chatwoot/viz` through the existing wrapper, `groupdate` as the
existing builders already use it.

---

## L. Performance evidence

Twenty-two query shapes were run under `EXPLAIN (ANALYZE, BUFFERS)` across two passes in a database carrying
126,000 messages — fifteen shapes in the first pass, seven in the second. Recorded in
`04-security-performance.md` §4–§6.

| Finding | Evidence |
| --- | --- |
| No index was needed | The contact→conversation→messages fan-out is already served by `index_messages_on_conversation_account_type_created`, at 0.062 ms–2.58 ms across four plans on a heavy and a quiet contact |
| Materialising conversation ids would be slower | The literal-list variant measured 0.135 ms against 0.062 ms, so it was not adopted |
| The first pass's eight Seq Scans were a fixture artifact | One account held 86% of the rows. Pass two against a minority tenant shows the account indexes used throughout, 0.06–1.2 ms |
| One shape is slow, and is named with its trigger | The coexistence-echo exclusion, 23 ms over 66,000 candidate rows, bounded by WhatsApp volume in the window. The lever and the threshold that would change the decision are both written down |
| Nothing is unbounded | Analytics ranges are capped by bucket ceilings (366 daily, 104 weekly, 60 monthly); the timeline is cursor-paged with a hard 100 limit |
| The benchmark did not pollute the test database | Both passes ran inside a rolled-back transaction and re-counted to zero afterwards. An earlier incident in P8.1 is why that was checked |

---

## M. Tenant and security evidence

| Property | Evidence |
| --- | --- |
| Account scoping is per query, not once at the door | Every service starts from `@account.<association>` or an explicit `account_id` |
| A missing predicate would be caught | `p8_tenant_isolation_spec.rb` runs against a **mirrored** two-tenant fixture — identical data in both accounts — so a missing scope shows up as a doubled count. A spec that seeds one account cannot catch this |
| `params[:account_id]` is never trusted | `Current.account` only, through `Analytics::RequestScoped` |
| A filter id from another account is refused, not ignored | `Analytics::FilterSet` validates every id and raises `422`. Exercised live in the UAT |
| The two tables with no `account_id` are never read | A spec scans every P8 source file for `audits` and `contact_inboxes`, with comment lines stripped first |
| Analytics follows the existing report permission | `authorize :report, :view?` (administrator-only). An agent gets `401` on all six endpoints — asserted, and exercised live |
| The timeline follows the contact's permission | `authorize @contact, :show?`. An agent is allowed; a foreign administrator gets `401`; a foreign contact gets `404` |
| An inbox-restricted agent is narrowed inside the timeline | `Conversations::PermissionFilterService` plus the caller's visible inbox set. Live: the restricted agent saw 19 of 22 entries and **zero** rows from the inbox they cannot access |
| No secret can reach a response | Responses carry ids, codes, counts, statuses and timestamps only. `commerce_customer_links.external_customer_id` is encrypted and never emitted; a spec asserts its absence |

---

## N. Tests and exact results

| Gate | Result |
| --- | --- |
| `bundle exec rspec` (full suite) | **9058 examples, 0 failures**, 70 pending — 35m 06s |
| P8's own Ruby specs (22 files) | **352 examples, 0 failures** |
| `pnpm test` (full suite) | **480 files, 5166 tests, 0 failures** |
| P8's own JS specs (8 files) | **65 tests, 0 failures** |
| `bundle exec rubocop` | 2771 files, **0 offenses** |
| `pnpm eslint` | **0 errors**, 464 warnings. 392 of the 464 are the repository's established `@intlify/vue-i18n/no-dynamic-keys` pattern, and **15 of those 392 are in P8 files** — KPI, breakdown and timeline-kind labels that resolve a key from the metric name. That is the only rule P8 adds a warning for; it adds none of any other kind |
| `npx vite build` | clean |
| UAT runbook | executed; §7 and §8 of `05-uat-runbook.md` |

**The 22 Ruby spec files:** four for the foundation (`date_range`, `filter_set`, `rollup_coverage`, `result`),
six family `metrics` specs, two timeline specs, seven analytics request specs, the tenant isolation spec, the
contact activity request spec, and the pre-existing campaign analytics controller spec, modified.

### One suite-level caveat, recorded because it misleads if it is not

An earlier run of the full suite reported 76 failures. Those were **not** product failures, and chasing them
down is worth a paragraph because the same trap will catch the next person.

This repository's test environment sets `config.cache_classes = false`, so Zeitwerk reloading is live during a
test run. Files were edited while that 36-minute run was in progress. The reload that followed replaced every
autoloaded class object — but `RSpec.describe SomeClass` resolves its constant when the **spec file loads**, so
`described_class` and anything captured in a frozen constant kept pointing at the pre-reload objects while the
example body resolved fresh ones. The signature is unmistakable once seen: `spec/models/account_spec.rb` failed
with "facebook_pages should resolve to `::Channel::FacebookPage` for class_name", a shoulda-matchers comparison
of two class objects that are equal in every way except identity, in a file P8 does not touch.

The fix was not a code change. The suite was re-run on an untouched tree with no edits during the run:
**9058 examples, 0 failures.** The reported result is that run. Two of the 76 were in a P8 spec and pass both in
isolation and in the clean suite; the other 74 were in files P8 never touched.

---

## O. Frontend coverage

| Layer | Files |
| --- | --- |
| API clients | `analytics.js` (7 endpoints), `contactActivity.js` — every call accepts an abort signal |
| Constants | `analytics.js` (grouping, bucket ceilings, date format, KPI kinds, units, the five breakdown dimension lists), `contactActivity.js` (categories, page size, icon map) |
| Composables | `useAnalyticsQuery.js` (calendar-date range state, available groupings, auto-downgrade of an invalid grouping, requests through the shared cancellation utility), `useContactActivity.js` (cursor paging that appends, category switching that drops the cursor) |
| Components | `AnalyticsScreen`, `AnalyticsRangeControls`, `AnalyticsKpiGrid`, `AnalyticsSeriesCard`, `AnalyticsBreakdownCard`, `AnalyticsMetaNote`; `ContactActivity`, `ContactActivityEntry` |
| Pages and routes | six analytics pages, `analytics.routes.js`, the Analytics sidebar group, the contact Activity tab |
| i18n | `analytics.json`, additions to `contact.json` and `settings.json` — **English and Arabic, matched key for key** |

Tailwind utilities only, no custom CSS, no scoped CSS, no inline styles. Composition API with `<script setup>`
throughout. Typography utilities rather than hand-rolled font styles. Direction-aware logical utilities, so the
screens work in Arabic. No bare strings in templates.

The grouping control is worth one line: it never offers a grouping whose bucket count would exceed the server's
ceiling, and if the current grouping becomes invalid it moves to the longest the range supports — so the UI
cannot produce a request the API would reject. `useAnalyticsQuery.spec.js` checks that over 72,000 range and
grouping combinations.

---

## P. Documentation

Thirteen documents under `docs/p8/`:

| Document | Contents |
| --- | --- |
| `00-discovery.md` | the repository-wide source mapping P8 was built from |
| `00b-rollup-production-check.md` | the read-only operator check, still pending |
| `01-architecture.md` | the timezone contract, the raw/rollup rule, the two disagreeing timezone regimes |
| `02-analytics.md` | the analytics contract |
| `02a`–`02d` | one document per family: definitions, sources, and what each cannot report |
| `03-contact-activity-timeline.md` | the ten sources, the permission model, the core/optional rule |
| `04-security-performance.md` | tenant isolation and all 22 EXPLAIN plans |
| `05-uat-runbook.md` | 24 numbered checks, the record of executing them (§7), and the UAT matrix (§8) |
| `P8_RELEASE_GATE.md` | 39 questions of this implementation, plus the brief's own 36, each with evidence |
| `P8_FINAL_COMPLETION_REPORT.md` | this document |

---

## Q. Commits

Twelve commits delivered the work on `claude/p8-analytics-contact-timeline`, and a thirteenth carries this
report and the two documents it completes. All pushed. Through `f3c2fa1d`: **113 files changed, 12,351
insertions, 6 deletions** — the six deletions are replaced lines in the campaign analytics controller and its
spec.

| Commit | Scope |
| --- | --- |
| `9d24283f` | P8.0 discovery — analytics and contact timeline source mapping |
| `afc9b295` | P8.1 analytics foundation |
| `79e07227` | P8.2 overview and conversation analytics |
| `5af94605` | P8.3 WhatsApp delivery and campaign performance |
| `f8cc65e6` | P8.4 automation execution and flow sessions |
| `7944ed62` | P8.5 commerce cart lifecycle and order actions |
| `16b6c4ac` | P8.6 contact activity timeline, as a read projection |
| `ca6acc83` | P8.7 contact Activity tab |
| `2d375e6f` | P8.8 EXPLAIN every shipped shape, prove tenant isolation |
| `faac8678` | P8.9 UAT runbook, release gate and the refreshed analytics contract |
| `35bd4a06` | the UAT's finding: exclude private notes from WhatsApp delivery metrics |
| `f3c2fa1d` | the executed UAT, its prerequisites and what it found |

---

## R. Known limitations

The twelve carried into this phase, all preserved as product limitations rather than worked around:

| # | Limitation | How it appears |
| --- | --- | --- |
| 1 | Immediate automation rules record no execution | Metric absent; `meta` warns, with the count of such rules |
| 2 | Automation action success/failure detail is incomplete | Not reported |
| 3 | Delayed automation retention is 30 days | `meta` warns when the range reaches past it |
| 4 | Contact field and custom-attribute changes are not audited | No such timeline entries and no metric |
| 5 | Assignee, team, label and priority activity is localized prose | Shown as prose; never parsed into structure |
| 6 | Flow node execution history does not exist | No node metrics |
| 7 | Flow "abandoned" has no canonical state | No abandoned metric |
| 8 | The commerce cache holds no order-state history | Cart lifecycle only |
| 9 | Revenue, GMV and profit are not safely derivable | No money on the Commerce screen at all |
| 10 | Currencies cannot be combined without conversion | `visible_total` never summed; currency breakdown counts carts |
| 11 | Historical audience membership is unavailable | Audience breakdown counts campaigns, not recipients |
| 12 | Production rollup coverage is unverified | Every screen reads source records and says so; correctness does not depend on rollups |

Two more, discovered during this phase and published on the screens:

| # | Limitation | How it appears |
| --- | --- | --- |
| 13 | `messages.status` keeps only the furthest state and a later `failed` overwrites it | WhatsApp delivery is understated for a message that was delivered and then failed. Stated in the family note and the footnote |
| 14 | Historical backlog-over-time cannot be reconstructed | `unresolved_backlog` is labelled current state, and the UI hint says so |

---

## S. Pending production operator checks

Three, all read-only. None blocks deployment.

1. **Rollup coverage** — the prepared read-only check in `00b-rollup-production-check.md`. It cannot change any
   number today, because `report_rollup` is disabled for every account and every screen reads source records; it
   is the evidence needed before that would ever change.
2. **The `reports` feature flag** — confirm it is enabled on each account that should see Analytics. Without it
   the sidebar group is not rendered at all, which looks like a missing feature rather than an empty screen.
   This cost real time to discover during the UAT and is now the first row of the runbook's §0.
3. **Post-deploy smoke** — load the six screens and one contact timeline, and read one footnote to confirm the
   timezone is the account's.

---

## T. Pending real UAT

From the matrix in `05-uat-runbook.md` §8. Nothing here is blocked; each needs real data a seeded instance
cannot produce.

| Item | Needs |
| --- | --- |
| Coexistence echoes (U6) | an account whose WhatsApp Business app traffic actually produces echoes |
| Meta failure-code breakdown (U7) | real Meta error codes |
| Agreement with the existing Reports screens (U20) | an account with enough real history for the two timezone regimes to be compared meaningfully |
| A human read of one response per family (U24) | a reviewer's eyes, in addition to the automated leakage assertion |
| Genuine WhatsApp template UAT (`order_delivered`, `en_US`, APPROVED) | its own operator gate. **P8 did not touch it and cannot be used to mark it complete** |

The analytics and timeline work was exercised against seeded data through the real HTTP stack and a real
browser. That is reported as **SIMULATED PASS** throughout and is never called real UAT.

---

## U. Release gate verdict

### PASS WITH KNOWN LIMITATIONS

All 39 implementation questions and all 36 of the brief's questions are answered with evidence in
`P8_RELEASE_GATE.md`. Every gate is green on a clean tree. The boundaries held: no schema change, no write path,
no new dependency, no Enterprise code, no production contact, and the P-FINAL licence audit not started.

It is not a plain **PASS** for one honest reason: P8 ships fourteen documented limitations and five pending
real-UAT items. None of them is a defect and none is a reason to hold the release — they are places where the
product never recorded something, published on the screens rather than papered over. But a plain PASS would
imply there is nothing an operator still needs to know, and there is.

It is nowhere near **NO-GO**: nothing is unsafe, nothing is unverified that could be verified here, and the one
defect found during verification is fixed and covered.

---

## V. Recommended next step

**Deploy P8 to production under the existing controlled deploy runbook, then enable `reports` on one pilot
account and run §6 of the UAT runbook against it.**

In that order, and for a specific reason: every pending item in §S and §T needs real production data, so they
cannot be closed before the deploy — but all of them can be closed in one sitting on a single pilot account
afterwards. The deploy itself is unusually low-risk for a feature of this size: no migration to run, no backfill
to wait for, no job to drain, no dependency to install, and the whole feature is invisible until a flag is
turned on. Rollback is turning the flag off.

Concretely, after the deploy:

1. Enable `reports` on one pilot account.
2. Run the read-only rollup check (§S.1) and record the result in `00b-rollup-production-check.md`.
3. Walk the runbook's U6, U7, U20 and U24 on that account and fill in §6.
4. Only then widen the flag.

The genuine WhatsApp template UAT and the P-FINAL licence and provenance audit remain separate gates. P8 did not
touch either and must not be read as evidence for them.
