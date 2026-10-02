# Lynomia Flow Builder: runtime and session

## Entry points

Everything runs in `Flows::RunJob` (queue `high`), which takes the conversation's Redis lock
(`LYNOMIA::FLOW::CONVERSATION::<id>`, `MutexApplicationJob#with_lock`, 60 s) and calls `Flows::Runner`. A job that finds
the lock taken is retried (`retry_on_lock_conflict`, up to 15 times, 1 s apart), so **one conversation is advanced by one
worker at a time**.

| Event | Enqueued by | Runner |
|---|---|---|
| `messages` | `Custom::AgentBotListener#message_created`: an incoming message in an inbox whose active bot is a flow bot | consume new customer messages |
| `wake` | the runner itself, `set(wait_until:)`, with the session id and a step token | a node's timer (delay, reply timeout) |
| `human` | the listener: a human reply (`Message#human_response?`) while a session is live | hand off (`human_reply`) |
| `stop` | the listener: the conversation left pending, or got an assignee | cancel (`left_bot_phase`) |
| `disabled` | `Flows::Versions#disable!` | hand off (`flow_disabled`) |
| `rejected` | `Custom::AgentBotListener#message_updated`: a message the flow bot sent turned `failed` (Meta rejected it) | hand off (`message_rejected`); a finished session's conversation still with the flow goes to humans |

## Bot phase

The runner acts only when the inbox's active bot is this flow bot and the conversation is **pending, unassigned, with no
other AI assignee** — Chatwoot's bot phase. It also needs the account feature, the installation switch, and a contact that
is not blocked; otherwise the conversation is handed to humans. Leaving the bot phase in any Chatwoot way (agent reply,
assignment, open, resolve, snooze) ends the session.

## Consuming messages exactly once, in order

The session records `last_message_id`. A `messages` run reads the conversation's incoming, public messages with a higher
id, **oldest first**, at most 10 per run, and consumes each: the first starts a session (Start's keywords and conditions,
on the published version), later ones answer the node the session waits at. Jobs for messages that arrived together can
run in any order: whichever runs first consumes them all in order, the others find nothing new. WhatsApp's own
deduplication (`MessageDedupLock`) already makes one Chatwoot message per provider message.

## Session states

```
            ┌──────────── reply / timer ───────────┐
            ▼                                       │
start ─▶ active ──node waits──▶ waiting ────────────┘
            │                       │
            ├── End ─────────────▶ completed
            ├── Handoff / unrouted output / window closed / human assigned ─▶ handed_off ─▶ bot_handoff!
            ├── error, safety limit, attribute missing ─▶ failed ─▶ bot_handoff!
            └── left the bot phase / ─▶ cancelled
```

A session found `active` when a message arrives was interrupted (a worker stopped mid-run): it cannot resume safely and
fails (`interrupted`), handing the conversation to humans.

## Waits and timers

A node that waits stores `current_node_id`, `wake_at` and a fresh random `step_token`, and (when it has a timer) schedules
`RunJob.set(wait_until: wake_at)` with that token. A timer job is honoured only if the session is still waiting with the
same token, so a reply that already moved the session, a newer wait, or a cancelled session makes the old timer a no-op.
No polling, no sleeping workers. Messages arriving during a Delay are consumed and the timer keeps its time.

## Safety limits (`Flows::Runner`)

| Limit | Value | When crossed |
|---|---|---|
| `MAX_AUTO_STEPS` | 25 nodes between two waits | `step_limit`: fail, hand off |
| `MAX_NODE_VISITS` | 10 visits of one node in a session | `visit_limit` |
| `MAX_SESSION_STEPS` | 200 nodes in a session | `step_limit` |
| `MAX_AUTO_SENDS` | 5 messages between two waits | `send_limit` |
| `MAX_MESSAGES_PER_RUN` | 10 messages consumed per job | the rest in the next job |

Graphs whose cycles never wait are refused at publish ([04](04-node-contracts.md#validation)); the runtime limits still
stop a looping graph that never went through validation (proved in `spec/services/flows/runner_spec.rb`). Measured costs
are in [09](09-performance.md).

## Errors

An exception in a node is reported to the exception tracker and fails the session (`node_error`); the conversation goes
to humans. Errors never leave a conversation silently pending.

## Test mode

`POST /flows/:id/simulate` (`Flows::Simulator`) runs the **saved draft** on the real runtime: Chatwoot's message model,
the node executors, conditions and actions, for a test contact (a reserved `+999…` number) in one of the account's
WhatsApp inboxes, inside a transaction that is always rolled back. Chatwoot sends to channels, dispatches events and
indexes only after commit, so nothing leaves; while simulating, the runtime additionally schedules no timer (the tester
fires it), posts no webhook (shown in the steps), calls no store (a test contact has no store customer: `not_found`) and
broadcasts no handoff. The builder replays the tester's whole input list on each step (at most 30 inputs), so no test state
is kept anywhere. The response is the transcript, the session's state and the steps (node, result).

## Observability

`Flows::Log` writes one `[Lynomia::Flow] {json}` line per event, ids and timings only — never a phone number, a message,
an answer or a token:

- `flow.execution.started / completed / handoff / failed / cancelled`
- `flow.node.executed` (`node_type`, `result`, `duration_ms`), `flow.wait.started / resumed`, `flow.start.skipped`
  (`reason`), `flow.webhook.skipped / simulated`

Named audit entries (`Flows::Audit`, Enterprise audit log): `flow.created / updated / published / disabled / deleted`,
`flow.execution.handed_off / failed`. The session inspector (`GET /flows/:id/sessions`) shows the latest 50 sessions with
their state, node, version, steps and end reason, and never the context's values.
