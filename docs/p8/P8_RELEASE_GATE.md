# P8 release gate

Sections A–F ask 39 questions of this implementation. Section G answers, in its own words and order, the 36
questions the phase brief required before P8 could be declared complete. Every answer carries the evidence that
supports it: a question with no evidence is a **NO**, not an assumption.

Scope: branch `claude/p8-analytics-contact-timeline`, cut from `lynomia-custom` at
`b03ea43df6abf18cb9c4e5d6a9271ba040b689f4`.

---

## A. Correctness of definitions

| # | Question | Answer | Evidence |
| --- | --- | --- | --- |
| 1 | Is there exactly one definition of each metric, or two that can disagree? | **One** | The per-campaign endpoint and the campaign analytics family share `Analytics::Campaigns::Metrics::DELIVERED_SQL`. Conversation metrics point at the OSS `reporting_events` definitions unchanged. `Analytics::Breakdown.resolve` is the only breakdown resolver |
| 2 | Is a reopen distinguished from a first open by the writer's own discriminator? | **Yes** | `event_start_time <> conversations.created_at`, which is what `ReportingEventListener` writes (`:101-124`). `value > 0` was rejected because a same-second reopen has value 0. `metrics_spec.rb` covers both |
| 3 | Is "delivered" ever read as status equality with `delivered`? | **No** | Campaigns read `delivered_at IS NOT NULL OR read_at IS NOT NULL`; WhatsApp reads `status IN (delivered, read)` because `messages` has no timestamps. Specs cover read-before-delivered |
| 4 | Is a duration with nothing to average reported as zero? | **No** | `average_duration` returns `nil`; the UI renders `—`. Specs: `avg_resolution_time` nil, `completion_rate` nil, `targeting_rate` nil, every rate nil at zero denominator |
| 5 | Is any current-state reading plotted or compared as if it were a period count? | **No** | Every KPI carries `kind`; `current_state` KPIs (`unresolved_backlog`, `awaiting_now`, `stranded_now`, `live_now`, `open_abandoned_now`, `actions_unresolved_now`) are excluded from series and carry the "reading taken now" hint |
| 6 | Is any number invented where the schema has no record? | **No** | Immediate automations: absent + warned. Flow nodes: absent. Flow "abandoned": absent. Historical backlog: absent. Cart transition history: absent. Contact field changes: absent. Each is listed in its phase doc's "known limitations" |
| 7 | Is any revenue, GMV or profit figure published? | **No** | `visible_total` is never summed. The currency breakdown reports cart counts. A request spec asserts no money key and no unit outside `count`/`percent` |
| 8 | Is completion after outreach presented as recovery? | **No** | `post_target_completions`, named for the time ordering it measures, beside `untargeted_completions`. The UI hint says it is not proof of cause |

## B. Timezone contract

| # | Question | Answer | Evidence |
| --- | --- | --- | --- |
| 9 | Is one timezone used for every P8 aggregation? | **Yes** | `Account#reporting_timezone`, through `Analytics::DateRange`, for every family |
| 10 | Can two viewers of the same account and dates see different totals? | **No** | The client sends calendar dates, never instants. `date_range_spec.rb` and the request specs assert the resolved UTC instants |
| 11 | Is the timezone reported in the response? | **Yes** | `meta.timezone`, plus `starts_at`/`ends_at` and `boundaries: 'start inclusive, end exclusive'` |
| 12 | Is the fallback when no timezone is set the repository's existing behaviour? | **Yes** | `UTC`, matching `TimezoneHelper#timezone_name_from_offset` and the rollup writer's own skip. Documented in `01-architecture.md` |
| 13 | Does the existing v2 report contract change? | **No** | Untouched. The disagreement between the two regimes is recorded in `01-architecture.md` and in the UAT runbook's U20 |

## C. Tenant isolation and permissions

| # | Question | Answer | Evidence |
| --- | --- | --- | --- |
| 14 | Is every query account-scoped independently? | **Yes** | Every service starts from `@account.<assoc>` or an explicit `account_id`. `p8_tenant_isolation_spec.rb` proves it against a **mirrored** two-tenant fixture, so a missing predicate shows as a doubled count |
| 15 | Is `params[:account_id]` ever trusted? | **No** | `Current.account` only. Documented in `Analytics::RequestScoped` |
| 16 | Is a filter value from another account refused or silently ignored? | **Refused, 422** | `Analytics::FilterSet` validates every id against the account. Specs for `template_id`, `campaign_id`, `automation_rule_id`, `inbox_id`, `provider` |
| 17 | Are the two tables with no `account_id` read anywhere in P8? | **No** | A spec scans every P8 source file for `audits` and `contact_inboxes`, comments stripped |
| 18 | Do the analytics screens follow the existing report permission? | **Yes** | `authorize :report, :view?` (administrator-only) and `permissions: ['administrator', 'report_manage']` on the routes. Agent → 401 asserted on all six |
| 19 | Does the contact timeline follow the contact's permission rather than the report one? | **Yes** | `authorize @contact, :show?`. An agent is allowed; a foreign administrator is 401; a foreign contact is 404 |
| 20 | Is an inbox-restricted agent narrowed inside the timeline? | **Yes** | `Conversations::PermissionFilterService` for conversation-derived adapters; the caller's own visible inbox set for campaign recipients. Both asserted |
| 21 | Can a token, provider payload or encrypted value reach a response? | **No** | `meta` carries ids, codes, counts and statuses only. `commerce_customer_links.external_customer_id` is encrypted and never emitted; a spec asserts its absence |

## D. Performance

| # | Question | Answer | Evidence |
| --- | --- | --- | --- |
| 22 | Was every shipped query shape EXPLAINed, not estimated? | **Yes** | 15 shapes in pass 1, 7 in pass 2, `EXPLAIN (ANALYZE, BUFFERS)` (`04-security-performance.md` §4) |
| 23 | Is the contact→conversation→messages fan-out measured? | **Yes** | Four plans across a heavy and a quiet contact in a 126,000-message database. 0.062 ms–2.58 ms |
| 24 | Was a new index added? | **No, and the decision is measured** | `index_messages_on_conversation_account_type_created` already covers it and the planner uses it where it matters. §6 records the residual risk with its bound and trigger |
| 25 | Were the Seq Scans in the first pass investigated? | **Yes** | They were a fixture artifact (one account held 86% of rows). Pass 2 with a minority tenant shows the account indexes used throughout, 0.06–1.2 ms |
| 26 | Is any query unbounded? | **No** | Analytics ranges are capped by bucket ceilings (366/104/60); the timeline is cursor-paged with a hard 100 limit and no unpaginated mode |
| 27 | Did the benchmark fixture leak into the test database? | **No** | Both passes run inside a rolled-back transaction and re-count to zero afterwards. The P8.1 §3 incident is why |
| 28 | Is the one slow shape named with its trigger? | **Yes** | The coexistence-echo exclusion, 23 ms over 66,000 candidate rows, bounded by WhatsApp volume in the window, lever and threshold stated |

## E. Boundaries this phase was told not to cross

| # | Question | Answer | Evidence |
| --- | --- | --- | --- |
| 29 | Any migration, new table or schema change? | **No** | `git diff --stat` touches no `db/` file |
| 30 | Any new write path, job, callback or outbound call? | **No** | Every P8 service is a read. No job, no listener, no provider client |
| 31 | Any Enterprise code reintroduced? | **No** | `enterprise/` does not exist and nothing references it |
| 32 | Any new charting or analytics dependency? | **No** | `package.json` and `Gemfile` unchanged. `@chatwoot/viz` through the existing `BarChart` wrapper; `groupdate` as the v2 builders already use it |
| 33 | Was production touched — deployed, mutated, backfilled, or sent to? | **No** | No deploy, no SSH, no write, no send, no provider enabled, no credential changed. The only production contact in this phase's lineage was the read-only rollup check in P8.1 (`00b-rollup-production-check.md`) |
| 34 | Was the final license and provenance audit started? | **No** | That is P-FINAL. Not begun |

## F. Verification

| # | Question | Answer | Evidence |
| --- | --- | --- | --- |
| 35 | Do the gates pass on a clean tree? | **Yes** | `bundle exec rspec`: **9058 examples, 0 failures**, 70 pending. `bundle exec rubocop`: 2771 files, **0 offenses**. `pnpm test`: 480 files, **5166 tests, 0 failures**. `npx vite build`: clean. Run on an untouched tree — see the completion report §N for why that matters |
| 36 | Is there a runbook a non-author can execute? | **Yes** | `05-uat-runbook.md`: 24 numbered checks, their pass criteria, the five that are release blockers, and what the runbook deliberately does not test |
| 37 | Was the runbook actually executed, or only written? | **Executed** | Against a locally seeded instance through the real HTTP stack and a real browser. All eight API-level checks passed and 28 of 29 browser assertions passed. Of the five release blockers, U2, U17 and U21 passed at API level and U9 passed in the browser; U24's automated half passed, with the human read still outstanding. Recorded in `05-uat-runbook.md` §7 with the environment, the results and the one failure's classification |
| 38 | Did executing it find anything the specs had not? | **Yes, one defect, fixed** | Private notes were counted as WhatsApp sends: 4 sends and 75% where 3 and 66.7% were correct. 351 Ruby and 65 JS examples had not caught it. Fixed in `Analytics::Whatsapp::Metrics` with a spec labelled as found by the runbook |
| 39 | Is the one browser failure a P8 defect? | **No** | A single `404` on a resource with an empty `href` (the favicon this deployment leaves blank). The companion "no failed P8 requests" assertion passed and no analytics or timeline path appears among the non-2xx responses. Evidence in `05-uat-runbook.md` §7 |

---

## G. The 36 questions the phase brief asked

Answered in the brief's own order and wording, so none can be quietly skipped.

**1. Which metrics use historical durable data?**
49 of the 55. Conversations: `conversations_created`, `conversations_resolved`, `conversations_reopened`,
`avg_first_response_time`, `avg_resolution_time`, `inbound_messages`, `outbound_messages`. WhatsApp: all nine.
Campaigns: all eleven. Automations: `episodes_armed`, `executed`, `skipped`, `execution_rate` — durable, but only
inside the 30-day retention window. Flows: all eight. Commerce: all ten event metrics.

**2. Which metrics are current-state only?**
Six, and the response labels every one of them `kind: "current_state"` so a screen cannot plot a reading as a
history: `unresolved_backlog`, `awaiting_now`, `stranded_now`, `live_now`, `open_abandoned_now`,
`actions_unresolved_now`.

**3. Which metrics only work prospectively?**
**None.** P8 added no instrumentation, no write path and no new column, so no metric starts empty and fills up
from the deploy forward. Every number it reports is computed from records the product was already writing. The
delayed-automation metrics are the one bounded case, and they are bounded by a *rolling* 30-day retention window
that already existed, not by the deploy date.

**4. Which requested metrics were intentionally omitted?**
Revenue, GMV and profit; recovered revenue; order-state transition history; immediate-automation executions;
per-action success/failure detail; flow node-level metrics; a flow "abandoned" state; backlog-over-time;
historical audience membership; contact field and custom-attribute change history; and analytics over
assignee, team, label and priority changes.

**5. Why?**
Each because the record does not exist, not because it was hard. Revenue: `commerce_carts` carries a per-cart
currency and nothing converts between currencies, so a sum would be a number with no unit — the currency
breakdown reports cart counts instead. Recovered revenue: the same, plus attribution the data cannot support.
Order-state history: the commerce cache holds the current state only. Immediate automations: they run inline and
write no execution row, so they are absent rather than reported as zero, and the response warns when the account
has any. Flow nodes: no per-node execution history is stored. Flow "abandoned": the product has no such state —
a session with no further replies stays waiting until something ends it. Backlog-over-time: reconstructing it
would need status-transition history that is not durably recorded. Audience membership: a campaign keeps a
reference to an audience and resolves membership at send time, so no past membership is recoverable, and no
recipient can be attributed to a source. Contact field changes: not audited. Assignee, team, label and priority
changes: recorded as **localized prose** in activity messages, which cannot be parsed back into structure
without inventing it.

**6. What is the canonical source of every implemented metric?**
Conversations: `reporting_events` (resolutions, first response, reopen), `conversations`, `messages`.
WhatsApp: `messages` (`status`, `created_at`, `additional_attributes.template_params`,
`content_attributes.external_error`), scoped to WhatsApp inboxes. Campaigns: `campaign_recipients` timestamps
and `campaigns`. Automations: `automation_rule_pending_executions` and `automation_rules`.
Flows: `flow_sessions`. Commerce: `commerce_carts`, `commerce_action_runs`, `commerce_stores`.
Timeline: the ten tables listed in `03-contact-activity-timeline.md`, each read in place.

**7. Are all analytics account-scoped?**
Yes, and independently per query rather than once at the entry point. Every service starts from
`@account.<association>` or an explicit `account_id`. `p8_tenant_isolation_spec.rb` proves it against a
**mirrored** two-tenant fixture, where a missing predicate shows up as a doubled count.

**8. Can any cross-account ID influence results?**
No. `Analytics::FilterSet` resolves every id against the account before it reaches a query and raises
`422` otherwise; the timeline resolves the contact through `Current.account`. Exercised live: §7 U23.

**9. Is `account.reporting_timezone` used consistently?**
Yes, for every family and every bucket boundary, through the single `Analytics::DateRange`. The client sends
calendar dates, never instants, so a viewer's clock cannot reach the grouping. Proved live in §7 U2: three
account timezones moved the window, three viewer timezones moved nothing.

**10. Are raw results authoritative?**
Yes. Raw source records are the correctness path for every metric, and are what every screen reads today.

**11. Can incomplete rollups corrupt totals?**
No. `Analytics::RollupCoverage` decides all-or-nothing for the whole requested range, and falls to raw when the
feature is off, no timezone is set, a metric has no rollup dimension, coverage is short, or coverage disagrees
with the raw events. The response names which source answered and why, so the choice is auditable rather than
assumed. In practice `report_rollup` is disabled for every account, so the answer is always raw today.

**12. Are WhatsApp delivery/read metrics based on authoritative states/timestamps?**
Campaigns: **yes, timestamps** — `delivered_at IS NOT NULL OR read_at IS NOT NULL`, never status equality, so a
row that reached `read` still counts as delivered. WhatsApp per-message: **state only, and the limitation is
published.** `messages` carries no per-status timestamps, only a single `status`, and
`Messages::StatusUpdateService` permits any transition to or from `failed`, so a message that was delivered and
then failed reads only as failed. Delivery is therefore `status IN (delivered, read)` and is understated for
that case. The family note and the UI footnote both say so.

**13. How are coexistence echoes treated?**
Excluded from every count and every rate, and reported separately as `coexistence_echoes`. They must be: the
`delivered` status on an echo is written **locally** to stop `SendReplyJob`, not by a Meta receipt, so counting
them would inflate delivery toward 100%. Identifying them required decoding `content_attributes`, which is
double-encoded and not readable with the ordinary JSON operators.

**14. Was existing Campaign analytics extended rather than replaced?**
Extended. The per-campaign analytics controller stays where it is, with its response keys unchanged; its
`delivery_metrics` now computes "delivered" through `Analytics::Campaigns::Metrics::DELIVERED_SQL`, so the
per-campaign screen and the Campaigns family share one definition and cannot drift. §7 U21 confirms they agree.

**15. Was Audience kept dynamic?**
Yes. No membership was materialised or snapshotted. The audience breakdown counts **campaigns per targeted
audience**, never recipients, precisely because membership is resolved at send time.

**16. Was Automation reused?**
Yes. The family reads `automation_rule_pending_executions` and `automation_rules`. No second automation engine,
no new execution record, no listener.

**17. Were unavailable automation histories honestly omitted?**
Yes, and announced rather than silently dropped. The response degrades with `immediate_rules:
no_execution_record` when the account has immediate rules, and with `retention_window:
terminal_rows_purged_after_30_days` when the requested range reaches past retention.

**18. Was Flow runtime reused?**
Yes. The family reads `flow_sessions` only. No second bot runtime and no node instrumentation.

**19. Were unavailable flow metrics omitted?**
Yes: no node-level metrics and no "abandoned" state. Duration is stated for what it is — wall-clock
`finished_at - created_at`.

**20. Was Commerce kept provider-neutral?**
Yes. Every metric is computed from `commerce_carts` and `commerce_action_runs`, which are provider-neutral, and
`provider` is a filter and a breakdown rather than a branch in the code.

**21. Were currencies kept separate?**
Yes. `visible_total` is never summed anywhere, and the currency breakdown reports **cart counts** per currency.

**22. Was a new order database avoided?**
Yes. No order table, no order mirror, no order cache of its own. Orders are read where they already live.

**23. Is Contact Activity a read projection?**
Yes. Eight adapters read ten existing tables in place. No timeline table, no event copy, no migration — so
nothing can disagree with its source and nothing is empty for the period before the feature existed.

**24. Were localized activity messages kept human-readable rather than parsed into fake structure?**
Yes. Only `conversation_status_changed` carries structured `content_attributes.activity`, and only that one is
read structurally. Every other activity message is passed through as the prose it is.

**25. Is timeline pagination bounded/stable?**
Yes. Cursor-paged with a default of 30, a hard maximum of 100 and no unpaginated mode. The cursor is the last
entry's own sort key, so the order is stable across pages. Walked live in §7 U16: 22 entries as 8 pages of 3, in
identical order, 0 duplicates, nothing lost at a boundary.

**26. Can optional adapters degrade safely?**
Yes. An optional adapter's database or adapter error becomes a `{scope:, reason: 'unavailable'}` warning plus
`partial: true`, and the rest of the timeline is returned — a commerce table being unreachable must not hide the
conversation history.

**27. Can core/security failures ever be incorrectly hidden as partial?**
No, by two separate rules. Messages and conversation events are **core**: their failure re-raises, because a
timeline missing the communication is wrong rather than partial. And the rescue is narrowed to
`ActiveRecord::ActiveRecordError`, `NoMethodError` and `KeyError`, so an authorization error cannot be
downgraded to a warning.

**28. Were secrets removed from API/timeline responses?**
Yes. Responses carry ids, codes, counts, statuses and timestamps only. `commerce_customer_links`
`external_customer_id` is encrypted and never emitted, and a spec asserts its absence from the payload. No
token, provider payload, webhook secret or encrypted value appears in any P8 response.

**29. Were schema changes made?**
No. `git diff` against the base touches no file under `db/`.

**30. Were indexes added?**
No.

**31. What EXPLAIN evidence justified them?**
It justified **not** adding one. Twenty-two query shapes were run under `EXPLAIN (ANALYZE, BUFFERS)` across two
passes in a 126,000-message database. The contact fan-out is already served by
`index_messages_on_conversation_account_type_created` at 0.062 ms–2.58 ms, and materialising the conversation
ids into a literal list made it **slower** (0.135 ms against 0.062 ms), so neither change was made. The first
pass's Seq Scans were chased down to a fixture artifact — one account held 86% of the rows — and pass two
against a minority tenant shows the account indexes used throughout. The one slow shape, the coexistence-echo
exclusion at 23 ms over 66,000 candidate rows, is recorded with its bound and the threshold that would change
the decision. All of it is in `04-security-performance.md` §4–§6.

**32. Is Enterprise still absent?**
Yes. `enterprise/` does not exist, `ChatwootApp.extensions` is `['custom']` because `custom/` is the only
overlay present, and no P8 file references Enterprise outside the two documents that record its absence.

**33. What automated tests passed?**
See the completion report §N for the exact counts and the one suite-level caveat.

**34. What real UAT remains?**
The `PENDING REAL UAT` rows of the matrix in `05-uat-runbook.md` §8: coexistence echoes and Meta failure codes
on a real WhatsApp account, agreement with the existing Reports screens on an account with real history, a human
read of one response per family, and the separate genuine WhatsApp template gate.

**35. What production operator checks remain?**
Three, all read-only. The rollup coverage check in `00b-rollup-production-check.md`; confirming the `reports`
feature flag is enabled on each account that should see Analytics (without it the sidebar group is not rendered
at all — see `05-uat-runbook.md` §0); and a post-deploy load of the six screens and one contact timeline.

**36. Is P8 ready for controlled deployment?**
See the verdict below and in the completion report §U.

---

## Verdict

Recorded in the P8 final completion report, section U.
