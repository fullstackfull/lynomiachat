# The operator UI: overview, channels, jobs, billing, timeline

Product Refinement, workstream G (§9.1, §9.6, §9.8, §9.9, §9.10). Branch `claude/product-refinement`.

## 1. Overview (§9.1): six answers, no decorative cards

The page answers six questions and nothing else:

1. **What is critical right now?** Open signals at critical severity (suppressed ones excluded — a human
   deliberately silenced those, and this is the list allowed to interrupt) *together with* any live or computed
   component reading critical. An operator does not care which mechanism found it.
2. **What needs a human?** `Operations::Signal.attention_queue.count`, using the queue's own definition so the
   number here and that page cannot disagree. Acknowledged and suppressed counts sit beside it, because
   "0 need action" means something different when 30 are parked.
3. **Which accounts are affected?** One grouped query over the attention queue, worst severity first then most
   occurrences — triage order. Installation-wide signals (`account_id NULL`) are counted separately rather than
   dropped or attributed to an account: "the dead set is growing" belongs to nobody's account.
4. **Which providers or channels are degraded?** The channel types something is recorded against (§2 below),
   and the commerce summary from `09-commerce-operations.md`.
5. **What recovered recently?** Signals *resolved* in the last 24 hours. Resolved, not quiet: a signal leaves
   the open set only when something observed the thing working again, so this is evidence of recovery rather
   than the absence of evidence of failure.
6. **What is unknown because nothing reports it?** Collected from the components already gathered, costing no
   extra query, plus the channel types with no health source and the commerce stores with no observation.

**What was removed.** The page used to open with five counts — accounts, inboxes, cases, active conversations,
a `reltuples` conversation estimate. Nobody decides anything from "11,402 conversations", the Super Admin
dashboard already shows them, and they pushed the only actionable block below the fold. They are gone;
`Operations::Overview#totals` and `#conversation_estimate` went with them, and the page links to the dashboard
for scale.

**Question six is what makes the other five trustworthy**, so the caveat is stated once and always, not only
in an empty state: *recording started when this console was deployed and reconstructs nothing from before it,
so a quiet area means nothing has been reported — not that everything has been checked.*

**Caching.** The derived blocks (computed product areas, channel matrix, commerce summary) are cached together
for five minutes with the moment they were produced, so a stale block cannot claim to be fresh. The probes are
*not* cached — a `SELECT 1`, a PING and a process-set read, where a stale "the database is up" is worse than no
answer. Nothing read from `operations_signals` is cached either: those are bounded reads over partial indexes,
and an operator refreshing after a fix must see the queue clear.

## 2. Channel matrix (§9.6): no recent error is not health

`/super_admin/operations/channels` — `Operations::ChannelMatrix`.

The rule this page exists to enforce: **five of the twelve channel types in this fork report nothing about
their connection.** Nothing in the repository tells us whether a Telegram, LINE, Twilio, Bandwidth SMS or X
connection still works (`Channels::Capability#health_sources` is empty for them, and `website` and `api` have
no provider at all). For those, silence is silence, and the row reads `unknown` with the reason spelled out
however long it has been quiet.

Only a channel type with real evidence can read healthy, and each row **names the evidence it has**:

| evidence | what it is |
|---|---|
| `reauth_latch` | the channel calls `prompt_reauthorization!` (`Custom::Reauthorizable` makes the two state changes durable) |
| `token_expiry` | the channel row stores a real expiry timestamp |
| `provider_health` | the provider's own health reading is fetched and stored |

Per-channel-type state comes from the durable `operations_signals` rows — one grouped query joined to
`inboxes.channel_type`, however many inboxes exist. The per-inbox *live* answer
(`Channels::ConnectionState`) is deliberately not called here; its own documentation says not to across
accounts, and it is called on the Account 360 page instead, where it costs one account rather than all of
them. The two ask their `unknown` reasons in the same order (no provider first, then no health source) so a
reader never gets two different explanations for the same channel.

Underneath, the inboxes with a recorded problem — the bounded set an operator is going to click.

## 3. Incident timeline (§9.10)

Covered in `07-operations-control-center-v2.md` §3. In summary: the lifecycle is
`detected → recurred → acknowledged → suppressed → resumed → action_taken → case_created → resolved`; the
machine half is derived from the signal's own columns so a problem seen a thousand times is one `recurred`
entry carrying the count; every entry is marked machine or human and rendered differently; and it does not
duplicate tenant Audit Logs, which answer a different question and are served to a different audience.

Opening a support case now writes a `case_created` entry with the operator who clicked
(`SignalLifecycle#record_case`, called from the controller). Before this, a case appeared in an incident's
history out of nowhere.

## 4. Background work (§9.8): reuse Sidekiq, do not recreate it

`Operations::BackgroundJobs`, rendered on the Overview.

Sidekiq's own web UI is mounted on this installation and is better at every job-level question: which job
failed, with what backtrace, retry it, kill it. This page reproduces none of that and links to it — Sidekiq,
retries, dead jobs — built from the mount point's own route helper so moving the mount moves the links.

What it adds is the one thing Sidekiq's dashboard cannot know: **which product capability a backed-up queue
stops.** `critical: 4,312 enqueued` means nothing to someone deciding whether to wake a developer; *"inbound
messages, replies and webhook deliveries — 4,312 waiting, 6 minutes behind"* is a decision. Each of the
eleven queues this product names carries that sentence; a queue without one is shown as itself rather than
given an invented meaning.

Only non-empty queues are listed, worst latency first — twenty empty queues are noise and the totals already
say the system is idle. "Behind" uses `Lynomia::QueueHealthJob::LATENCY_THRESHOLD`, read from the job that
*records* a backlog rather than chosen again here, so the live page and the durable signal cannot disagree
about what behind means. The durable side is not duplicated: `QueueHealthJob` already writes `backlog`,
`dead_set_grew` and `no_workers` signals, which appear in the queue and the issue feed.

If the queues cannot be read, the block says so — we failed to look, which is not the same as them being
empty.

## 5. Billing (§9.9): a declined card is not a platform incident

`Operations::BillingState`, rendered on the Overview, in two clearly separated halves.

**Commercial** — counts per subscription status, counts per source, trials ending within seven days, and the
past-due count. No health state is attached to any of them. A customer whose payment failed is a commercial
fact Stripe already told them about, and the account has a grace period for exactly that reason; counting it
as red would make the console cry wolf every month. `Billing::OperationsSignal` is already deliberate about
this distinction and this page reads it rather than re-deriving anything.

**Platform incidents** — the open `source: billing` signals: an entitlement write that did not apply, a
verified Stripe event that matched no account here, a subscription that could not be synchronized. Those are
the installation failing at its own job.

**Locked out** — the accounts the product has actually stopped working for, which is the one commercial number
that is also operational: somebody is locked out and will be in touch. Presented as a **recent list and
labelled as one, never a total**: `BillingSubscription#accessible?` is a time-and-config judgement (grace
periods, trial ends, whether billing is enforced at all) that lives in the model, and reimplementing it as a
`WHERE` clause is how the console and the product start disagreeing about who is locked out. The read is
bounded to the statuses that can be locked and to the 200 most recently changed, and the page says how far it
looked. Nothing here calls Stripe.

## 6. Verification

- `spec/services/operations/channel_matrix_spec.rb` — 8 examples: a quiet channel with no health source reads
  `unknown`; a channel with no provider says so; an unused type says so; a WhatsApp inbox may read healthy and
  names `reauth_latch,provider_health`; a recorded problem makes it critical; the unreported list is the seven
  expected keys; `degraded` returns only recorded types; constant query count as inboxes grow.
- `spec/services/operations/incident_timeline_spec.rb` — 6 examples: derived detection and recurrence with the
  count; no recurrence claimed for a single observation; recovery added on resolve; operator decisions merged
  in order and marked human; an observation ordered before a human reaction sharing its timestamp; a support
  case recorded with its operator.
- `spec/services/operations/billing_state_spec.rb` — 5 examples including the central one: a past-due
  subscription is counted commercially and is **not** an incident.
- `spec/controllers/super_admin/operations_controller_spec.rb` — the overview states the recording caveat and
  names what is unknown.
- `spec/controllers/super_admin/operations_control_center_spec.rb` — the channels and commerce pages are in
  the full authorization boundary.
