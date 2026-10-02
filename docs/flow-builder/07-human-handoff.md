# Lynomia Flow Builder: human handoff

Handing a conversation to humans is always Chatwoot's own `Conversation#bot_handoff!`: the conversation opens, the bot
assignee is cleared, `CONVERSATION_BOT_HANDOFF` is dispatched (bot reports count it), and Chatwoot's assignment rules
apply as for any bot handoff. The session ends `handed_off` (or `failed`, which hands off too) with its reason, audited as
`flow.execution.handed_off` / `flow.execution.failed`. **The bot stops**: it acts only in the bot phase, which the
handoff ends. There is no automatic resume; a new session starts only in a new bot phase (for example a later
conversation in the inbox).

## When it happens

| Reason (`end_reason` / `failure_code`) | Cause |
|---|---|
| `handoff_node` | a Human handoff node (team, agent, priority, labels, private note first) |
| `human_reply` | an agent replied, or the business replied from the WhatsApp Business app on a coexistence number (`Message#human_response?`) |
| `human_assigned` | an agent was assigned (Assign Agent node, or an agent in the dashboard) and the flow reached a wait or its end |
| `left_bot_phase` (cancelled) | the conversation was opened, resolved, snoozed or assigned from outside |
| `no_choice` | no option chosen after the menu was sent three times |
| `window_closed` | a message was due after WhatsApp's 24-hour window |
| `unrouted_<output>` | an optional output that is not connected (`invalid`, `timeout`, `other`, `failed`, `not_found`, `unavailable`) |
| `flow_disabled`, `flow_unavailable` | the flow was disabled; the feature or the kill switch is off; the contact is blocked |
| `step_limit`, `visit_limit`, `send_limit`, `node_error`, `interrupted`, `attribute_missing`, `invalid_attribute_value` | failures |
| `no_published_version`, `start_not_matched`, `unsupported_channel` | no session started; the conversation goes to humans at once |

## Deterministic

Every handoff runs inside the conversation's lock, once: the session closes, then `bot_handoff!` runs only if the
conversation is still pending. A human reply, an assignment or a status change that arrives while a job is running is
handled after it, by the `human` / `stop` jobs the listener enqueues, which find the session already closed or close it.

## Explicit resume

Not built in Phase 1. Agents who want the bot again can mark the conversation pending again, unassigned, in Chatwoot; the
next customer message then starts a **new** session from Start (logged as `flow.execution.started`), never a silent
continuation of the old one.
