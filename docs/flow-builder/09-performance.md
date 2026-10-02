# Lynomia Flow Builder: performance

Measured with `docs/flow-builder/perf/perf.rb` (results: `perf/results.json`) on the E2E database in production mode,
Ruby 3.4.4 / Node 24 verification image, 4 vCPU, **while the full RSpec suite ran on the same machine** (so the figures
are pessimistic). A throwaway account is created and deleted; jobs are recorded, never sent. Each figure is the median of
5 runs, through the real API (`ActionDispatch::Integration::Session`, token auth) or the real job.

## Builder and API

Graphs built of repeated segments (a question, then a condition, a label, a conversation attribute and a message) ending
in a handoff, every node connected and valid.

| Nodes | Edges | JSON | Load (GET, with validation) | Save draft (PUT) | Validate | Publish (POST) | Test Mode, 6 inputs |
|---|---|---|---|---|---|---|---|
| 50 | 59 | 10 KB | 49 ms | 79 ms | 44 ms | 76 ms | 550 ms |
| 100 | 119 | 21 KB | 69 ms | 97 ms | 82 ms | 80 ms | 552 ms |
| 200 | 239 | 43 KB | 99 ms | 148 ms | 156 ms | 135 ms | 488 ms |

Validation grows with the graph (reach, loop and per-node checks, each node's references queried once). Browser
rendering of a 200-node canvas was not measured in this phase; the builder E2E exercises small flows.

## Runtime (on the 200-node flow and two small flows)

| Step | Median | What it includes |
|---|---|---|
| start | 168 ms | lock, session created, Start, the first question sent (a Chatwoot message) and its timer scheduled |
| resume one segment | 280 ms | the reply consumed and stored, a condition (Automation's filter service), a label, an attribute write, a message, the next question and its timer |
| longest automatic chain | 893 ms | `MAX_AUTO_STEPS` = 25 nodes without waiting (labels and attribute writes, each a conversation update with its events), then End |
| handoff | 409 ms | team, priority and label through `ActionService`, a private note, `bot_handoff!` |

The time is Chatwoot's own work per node (conversation updates and their callbacks, message creation); the flow's
orchestration adds little. Runs are bounded: at most 25 nodes and 5 messages between two waits, 200 nodes per session, 10
messages consumed per job.

## Load characteristics

- One job per incoming message (`high` queue); one Redis lock per conversation, so conversations advance in parallel
  across workers and each conversation sequentially.
- Waiting costs nothing: a waiting session is a row; timers are scheduled jobs, no polling.
- Graph reads are one row (`flow_versions.graph`); sessions are indexed by conversation (one live session per
  conversation, partial unique index) and by account, bot and status (inspector).
- Commerce lookups go through Commerce's cache and per-store timeouts (Customer 360: 15 s, order search: 10 s) and are
  limited to 10 per conversation per hour.
