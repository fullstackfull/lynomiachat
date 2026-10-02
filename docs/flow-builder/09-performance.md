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

Validation grows with the graph (reach, loop and per-node checks, each node's references queried once).

## The canvas in a real browser

`perf/canvas.sh` → `perf/canvas.js` (results: `perf/canvas_results.json`, screenshots `screenshots/perf-canvas-*`): the
production build on the production server, Chromium (Playwright) at 1440 × 900, the same valid graphs (`e2e/ctl.rb
perf_graph`). Every interaction is done as a person does it (wheel, mouse drags from the connectors, typing in the
panel) and timed until the canvas shows its result; "frames" are the animation frames drawn meanwhile, "slow" those over
50 ms. Gesture times include the scripted pointer movement (20 steps per drag), so they are not latencies; the frame
columns are.

| | 50 nodes | 100 nodes | 200 nodes |
|---|---|---|---|
| Initial render (navigation → every node and edge drawn; first / median of the next 2) | 1489 / 1428 ms | 1425 / 1692 ms | 1298 / 1442 ms |
| Fitted zoom | 0.2 | 0.2 | 0.2 (the minimum: not every node fits a 1440 px screen) |
| Zoom with the wheel to 1× (4–5 notches) | 675 ms, worst frame 17 ms | 644 ms, 33 ms | 689 ms, 17 ms |
| Pan (two 160 px drags) | 788 ms, worst frame 17 ms | 819 ms, 17 ms | 836 ms, 33 ms |
| Select a node | 55 ms | 48 ms | 48 ms |
| Open its settings panel (after the click) | 59 ms | 51 ms | 50 ms |
| Edit it (7 characters typed; the node on the canvas updated) | 436 ms, worst frame 33 ms | 500 ms, 33 ms | 789 ms, worst frame 100 ms, 5 slow |
| Drag a node 80 px | 410 ms, worst frame 17 ms | 359 ms, 17 ms | 499 ms, 33 ms |
| Add an edge (drag from an output to a node) | 262 ms | 284 ms | 392 ms, one 100 ms frame |
| Save (graph sent, validated, "saved" shown) | 287 ms, 200 | 180 ms, 200 | 239 ms, 200 |
| JS heap after load → after 10 zoom + pan rounds (after GC) | 88.4 → 89.5 MB | 92.9 → 93.4 MB | 100.6 → 101.2 MB |
| DOM changes on the canvas during 3 s at rest | 0 | 0 | 0 |
| Nodes drawn / unique | 50 / 50 | 100 / 100 | 200 / 200 |
| Long tasks (whole run) / worst | 4 / 135 ms | 4 / 289 ms | 12 / 338 ms |
| Worst input event (Event Timing, whole run) | 112 ms | 192 ms | 304 ms |

At 200 nodes: no crash, memory flat after interactions (no growth), no render loop (nothing changes at rest), no duplicate
nodes, no console error from the builder. Input stays usable: typing in a node of a 200-node flow draws frames of up to
100 ms (each keystroke updates the node on the canvas and the "unsaved" check compares the graph), and the worst input
event of the whole run was 304 ms. Vue Flow draws every node (no virtualisation), which is what the initial render pays.

The 200-node flow in each language and width:

| | Initial render | Pan | Select → settings | Page overflow | Palette | Settings panel |
|---|---|---|---|---|---|---|
| Desktop, English (LTR) | 1884 ms | 608 ms, worst frame 33 ms | 74 ms | 0 px | shown | 384 px beside the canvas |
| Desktop, Arabic (RTL) | 1525 ms | 522 ms, 33 ms | 100 ms | 0 px | shown | 384 px beside the canvas |
| 390 px, English | 1712 ms | 349 ms, 17 ms | 48 ms | 0 px | hidden | over the canvas, full width |
| 390 px, Arabic | 1559 ms | 311 ms, 17 ms | 49 ms | 0 px | hidden | over the canvas, full width |

The page follows the language (right to left in Arabic); the canvas itself stays left to right in both (`dir="ltr"`), so
a graph reads the same for every user.

**Mobile is limited editing, by design of the implementation**: below `md` the node palette is hidden, so no new node
type can be added on a phone; selecting a node opens its settings over the canvas, where everything can be edited,
duplicated or deleted; the canvas pans, zooms and selects; Save, Publish, Test Mode, Sessions and the inbox connection
are in the header. Building a flow from scratch is a desktop task.

Found and fixed by this measurement (the builder E2E's small flows had not shown them): the fitted view could be
skipped on load (the fit ran when Vue Flow's pane was ready, sometimes before the nodes were measured; it now runs once
the nodes are measured, once per load), and a first visit to the builder logged uncaught IndexedDB errors (the builder
refreshed labels, inboxes, teams and custom attributes at the same time as the dashboard sidebar; it now fetches only
agents). The only console errors left in the run are the 404s of Chatwoot's enterprise
`GET /enterprise/api/v1/accounts/:id/limits` (upstream since 4.14, not served by this installation), which every
dashboard page logs; none comes from the Flow Builder.

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
