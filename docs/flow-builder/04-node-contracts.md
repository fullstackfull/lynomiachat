# Lynomia Flow Builder: node contracts

A graph is `{ nodes: [{ id, type, position: { x, y }, data }], edges: [{ id, source, sourceHandle, target }] }`.
`sourceHandle` names one **output** of the source node; each output has at most one edge. The contracts live in
`Flows::NodeTypes` (outputs, optional outputs, waiting, data keys) and are sent to the builder by the API, so the canvas
draws exactly the outputs the server accepts. `Flows::NodeValidator` checks each node's data; `Flows::GraphValidator` the
whole graph.

**Unconnected optional output** (marked *optional* below): taking it hands the conversation to humans
(`unrouted_<output>`). **Failure policy**: a node that cannot do its job either follows a dedicated output (`failed`,
`not_found`, `unavailable`, `invalid`, `timeout`) or, where none exists, fails the session, which hands the conversation
to humans. Nothing is retried silently.

| Type | Group | Outputs | Waits | Data |
|---|---|---|---|---|
| `start` | — | `next` | | `keywords`, `conditions` (both optional) |
| `send_message` | Messages | `next` | | `text` |
| `send_template` | Messages | `next`, `failed`* | | `name`, `language`, `params` (Chatwoot's `processed_params`) |
| `question` | Messages | `reply`, `invalid`*, `timeout`* | yes | `text`, `reply_type`, `keywords`, `store_as`, `max_attempts`, `retry_text`, `timeout_minutes` |
| `buttons` | Messages | one per option, `other`*, `timeout`* | yes | `text`, `options` (≤ 3), `timeout_minutes` |
| `list` | Messages | one per option, `other`*, `timeout`* | yes | `text`, `button_label`, `options` (≤ 10), `timeout_minutes` |
| `condition` | Logic | `true`, `false` | | `conditions` |
| `audience_condition` | Customer | `true`, `false` | | `conditions` (`contact_audience` only) |
| `commerce_condition` | Commerce | `true`, `false` | | `conditions` (`commerce_*` only) |
| `set_contact_attribute`, `set_conversation_attribute` | Customer | `next` | | `key`, `value` |
| `add_label`, `remove_label` | Customer | `next` | | `labels` |
| `assign_team`, `assign_agent` | Team | `next`, `failed`* | | `team_id` / `agent_id` |
| `commerce_lookup` | Commerce | `found`, `not_found`*, `unavailable`* | | `mode`, `number` |
| `webhook` | Integration | `next` | | `url` |
| `delay` | Flow | `next` | yes | `seconds` |
| `handoff` | Team | — | | `team_id`, `agent_id`, `priority`, `labels`, `reason` (all optional) |
| `goto` | Flow | — (continues at `target`) | | `target` |
| `end` | Flow | — | | `resolve` |

\* optional

## Start

Every session begins here. Whether a conversation enters the flow at all is decided before a session exists: the first
customer message must contain one of `keywords` (any message, when none) and the conversation must match `conditions`
(Automation conditions, optional). Otherwise the conversation goes to humans at once.

## Send message

One text message from the flow bot through Chatwoot's message path. Outside WhatsApp's 24-hour window nothing is sent:
the session ends handed off (`window_closed`).

## Send WhatsApp template

One approved WhatsApp template of the conversation's inbox, sent by Chatwoot's own template path: the flow bot's message
carries `additional_attributes.template_params` exactly as the dashboard composer sends them (`name`, `category`,
`language`, `namespace`, `content_mode: raw_template`, `processed_params`), and `Whatsapp::SendOnWhatsappService` sends
it with `TemplateProcessorService` — also after the 24-hour window, unlike Send Message.

- `name` + `language`: a template of the inbox (`message_templates`), approved, one the composer would send.
- `params`: `body` and text `header` values by variable, a media header's `media_url` (and `media_name` for a document),
  `buttons` by position (`url` value, `copy_code`). Values may use the allow-listed variables; copy codes only `flow.*`;
  media links none.
- Publish: looked up in this account's inboxes only (every connected inbox, or one of the account's WhatsApp inboxes
  before any is connected); every value required.
- Run: a template the inbox can no longer send, or a value empty once filled in, follows `failed`, or fails the session
  (`template_*` codes) when `failed` is not connected. A message Meta rejects later hands the conversation to humans
  (`message_rejected`). Details in [06](06-whatsapp-channel-capabilities.md).

## Question

Asks `text`, waits for the next customer message, checks it (`reply_type`: `any`, `number` — Arabic-Indic and Persian
digits accepted —, `email`, `phone`, `keywords`), stores it (`store_as`: `context` → `flow.<key>`, or a contact /
conversation custom attribute of the account, checked against its definition) and follows `reply`. A reply that does not
fit is asked again (`retry_text`) until `max_attempts` (1–5, default 3), then follows `invalid`. `timeout_minutes`
(1–1440) schedules a timer that follows `timeout`.

## Choices

Buttons and List send one `input_select` message; each option's value is `lfb:<node id>:<option id>`, which WhatsApp
returns with the reply ([06](06-whatsapp-channel-capabilities.md)). The branch is chosen **by that id**, so renaming or
translating a title never changes routing, and a reply to an older menu cannot match a newer one. A typed reply equal to an
option's title, or its number (`2`, `٢`), is accepted too. Anything else follows `other` when connected; otherwise the
menu is sent again (at most twice), then the conversation goes to humans (`no_choice`). Options have stable ids
(`[A-Za-z0-9_-]{1,64}`, unique in the node); titles and descriptions must fit the channel (buttons: 3 × 20 characters;
list: 10 rows, title 24, description 72, button label 20; body 1024).

## Conditions

Condition nodes hold **Lynomia Automation conditions** (`attribute_key`, `filter_operator`, `values`, `query_operator`),
validated by `AutomationRule`'s own validation on an unsaved rule and evaluated by
`AutomationRules::ConditionsFilterService` on the flow's conversation (event `conversation_updated`). Shared audiences
(`contact_audience`, shared ones only) and local Commerce summaries (`commerce_*`) are the same conditions Automation
offers; no store is called. `attribute_changed` is refused (a flow has no "previous" state). At most 10 conditions.

## Attributes

Writes one custom attribute the account defined, through the model as an agent's edit does, after filling `flow.*`
variables (only `flow.*` here: Chatwoot's message variables are not rendered outside messages). The value must fit the
definition (number, checkbox, list value, date, link, and the definition's regex, compiled with a 0.1 s time limit). An
attribute deleted after publishing (`attribute_missing`) or a value that does not fit (`invalid_attribute_value`) fails
the session.

## Labels

`ActionService#add_label` / `#remove_label`, as Automation and Macros run them: idempotent; labels deleted after
publishing are skipped. At most 10, all of the account.

## Assignment

`ActionService#assign_team` / `#assign_agent`. A team keeps the conversation with the flow (queued for that team when
humans take it). An agent must be a confirmed member of the inbox or an administrator of the account; the human then owns
the conversation, so the flow may still send what follows `next`, and wherever it would wait or end it hands over
(`human_assigned`). A team or agent that cannot take the conversation follows `failed`.

## Commerce lookup

Read only; the contact's own orders only.

- `latest_order`: the newest order of the contact's matched store customers (`Commerce::Customer360`, cached, the view
  agents see).
- `order_number`: the number the customer quotes (`number`, default `{{flow.reply}}`; `#`, Arabic digits accepted): first
  among those latest orders, then by number with `Commerce::OrderSearch` in the stores where the contact is matched, keeping
  only orders of the matched customer. A guessed number of someone else's order is simply not found.

`found` sets `flow.order.number / status / payment_status / tracking_number / tracking_url`. `unavailable`: Commerce off
for the account, no store answered, or more than 10 lookups in an hour for the conversation.

## Webhook

Posts `{ event: 'flow_webhook', flow: { id, name, version, node_id, session_id }, conversation (Chatwoot's webhook data),
reply, values, order }` through Chatwoot's `WebhookJob` → `Webhooks::Trigger` → `SafeFetch` (private addresses refused
unless the installation allows them), signed with the flow bot's secret (`X-Chatwoot-Timestamp`, `X-Chatwoot-Signature:
sha256=HMAC(secret, "<timestamp>.<body>")`). Delivered in the background; the flow follows `next` at once and **nothing the
endpoint answers enters the flow**. Accounts without API and webhooks on their plan cannot publish it.

## Delay

Waits `seconds` (1–86400) on a scheduled job, then follows `next`. Customer messages meanwhile are consumed without
moving the flow; the timer keeps its time.

## Handoff

Optional team, agent (inbox member), priority and labels through `ActionService`; `reason` becomes a private note for the
agents (never sent to WhatsApp); then Chatwoot's `bot_handoff!`. The flow does not answer that conversation again in this
session; there is no automatic resume.

## Go to

Continues at `target` (any node but Start and itself). A loop through it must pass a node that waits.

## End

Completes the session. The conversation keeps its status unless `resolve` is set.

## Variables

`{{ name }}` from an allow-list, no Liquid tags or filters (`Flows::Variables`):

- Chatwoot's: `contact.name / first_name / last_name / email / phone_number / custom_attribute.<key>`,
  `conversation.display_id / custom_attribute.<key>`, `inbox.name`, `account.name` — rendered by Chatwoot's own Liquid
  drops when the message is created;
- the flow's: `flow.reply`, `flow.<key>` (a Question's `context` value), `flow.order.<field>` — filled in by the flow first,
  with `{{`, `}}`, `{%`, `%}` removed from the values, so nothing a customer typed or a store returned becomes a template.

## Validation

`Flows::GraphValidator` is the publish gate; the builder only shows its errors (`{ code, node_id, edge_id, detail }`).

| Check | Errors |
|---|---|
| shape | `invalid_graph`, `graph_too_large`, `too_many_nodes`, `too_many_edges`, `invalid_node`, `unknown_node_type`, `invalid_position`, `duplicate_node_id`, `invalid_edge`, `duplicate_edge_id` |
| start | `start_count` (exactly one), `edge_into_start` |
| edges | `dangling_edge`, `unknown_output`, `duplicate_output` |
| routing | `unconnected_output` (every required output, every option), `invalid_target` |
| reach | `unreachable` (every node reachable from Start, Go To targets included) |
| loops | `loop_without_wait`: a cycle with no question, choice or delay would run without the customer |
| nodes | the per-node checks above: `unknown_field`, `text_required`, `text_too_long`, `unknown_variable`, `invalid_options`, `option_title`, `unknown_label`, `unknown_team`, `unknown_agent`, `unknown_attribute`, `invalid_conditions`, `condition_not_allowed`, `commerce_disabled`, `invalid_url`, `webhooks_unavailable`, `invalid_delay`, `invalid_timeout`, … |
| channels | `unsupported_channel`: every connected inbox can run every node |

Every id a node names (label, team, agent, attribute, shared audience) must be **this account's**.
