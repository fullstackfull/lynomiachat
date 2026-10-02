# Lynomia Flow Builder: data model and versioning

Two new tables, both under `custom/db/migrate` (`20261004100000`, `20261004100100`), and one new `agent_bots.bot_type`
value. Nothing else in Chatwoot's schema changes. Every foreign key cascades, so deleting an account, a bot, a version or a
conversation leaves nothing behind.

## `agent_bots` (existing)

`bot_type` gains `flow: 1` next to `webhook: 0`. A flow bot (`Custom::AgentBot`):

- belongs to an account (system bots, account `nil`, are never flows) and has no `outgoing_url`;
- never changes type (`bot_type` is immutable on update);
- `has_many :flow_versions, :flow_sessions`; `published_flow_version`.

Its name, description, avatar, `secret` and access token are Chatwoot's.

## `flow_versions`

| Column | |
|---|---|
| `account_id`, `agent_bot_id` | the flow (same account, checked) |
| `version` | 1, 2, 3 … per bot (unique per bot) |
| `status` | `draft` 0, `published` 1, `archived` 2 |
| `graph` | jsonb `{ nodes: [...], edges: [...] }` ([04](04-node-contracts.md)) |
| `created_by_id`, `published_by_id`, `published_at` | who and when |

Partial unique indexes allow **at most one draft and one published version per bot**.

```
draft ──save!(graph)──▶ draft ──publish! (valid)──▶ published ──next publish!──▶ archived
                                                     │
                         disable! ───────────────────┘──▶ archived (nothing published)
```

- **Draft**: created on the first edit, from the published graph (or a Start → End starter). `save!` checks the shape only
  (so a half-built flow can be saved); references and routing are checked at publish.
- **Publish** (`Flows::Versions#publish!`, under the bot's row lock): the draft must pass `Flows::GraphValidator`
  against the bot's inboxes; the previous published version becomes archived; the draft becomes published. The next edit
  starts a new draft from it.
- **Immutability**: `FlowVersion#graph_frozen` refuses any graph change once a version has left `draft`. A session points
  to its version row, so a published version that sessions run on never changes under them; new sessions start on the
  newly published one.
- **Disable**: archives the published version (no new session starts) and hands live sessions to humans, each under its
  conversation's lock.
- **Delete**: only a flow that is not published and has no live session (`flow_active` otherwise): disable first.

## `flow_sessions`

| Column | |
|---|---|
| `account_id`, `agent_bot_id`, `flow_version_id`, `conversation_id` | all in one account (validated) |
| `status` | `active` 0, `waiting` 1, `handed_off` 2, `completed` 3, `failed` 4, `cancelled` 5 |
| `current_node_id` | the node running or waited at |
| `context` | jsonb: the last reply, values a Question stored (`values`), the order a lookup found (`order`), visit and attempt counters, `end_reason` |
| `last_message_id` | the last incoming message the flow consumed (exactly-once consumption) |
| `wake_at`, `step_token` | the pending timer and the token it must present |
| `steps_count`, `failure_code`, `finished_at` | limits and how it ended |

A partial unique index allows **one live (active or waiting) session per conversation**. Sessions hold orchestration
state only: the transcript stays Chatwoot messages, durable answers go to custom attributes, and nothing about a contact
or an order is copied beyond the few values a later node reads.

## Sizes

A graph is bounded at 300 nodes, 900 edges and 512 KB of JSON (`Flows::GraphValidator`); ids are 1–64 characters of
`[A-Za-z0-9_-]`; context values are cut at 1024 characters.

## Migrations and rollback

Both migrations are additive. Rolling back drops the two tables; flow bots then remain as AgentBots of an unknown type and
should be deleted first (`AgentBot.flow.destroy_all`). Webhook bots, conversations and messages are untouched either way.
