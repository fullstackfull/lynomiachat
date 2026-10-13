---
agent: 037
scope: Flow builder and bots — canvas, node types, draft/publish lifecycle, templates, inbox attachment, human handover, agent/webhook bots, bot authorization, mid-conversation failure
confidence: high
---

## 1. What the feature is

Lynomia has three distinct automation products that the sidebar groups together under **Automation**
(`app/javascript/dashboard/components-next/sidebar/Sidebar.vue:911-941`): automation rules, the **Flow Builder**,
and **Bots** (agent bots). Agent 036 owns rules; this report owns the other two and the boundary between them.

A **flow is a bot**. It is not a new model: a flow is a row in `agent_bots` with `bot_type: flow`
(`app/models/agent_bot.rb:42`), extended by `custom/app/models/custom/agent_bot.rb`. Chatwoot's original bot
(`bot_type: webhook`) receives conversation events as HTTP POSTs to an `outgoing_url` and replies through the API.
A flow bot has no `outgoing_url` — the model forbids one (`custom/app/models/custom/agent_bot.rb:87-90`) — and
receives the same events as in-process `Flows::RunJob` runs instead
(`custom/app/listeners/custom/agent_bot_listener.rb:4-41`). `bot_type` is immutable after create
(`custom/app/models/custom/agent_bot.rb:92-94`), so a webhook bot can never become a flow or vice versa.

A flow's content is a **graph**, versioned in `flow_versions` (`custom/app/models/flow_version.rb`). One row per
version, `status` in `draft | published | archived`, exactly one draft and at most one published version per bot.
A published version's graph is frozen for life (`custom/app/models/flow_version.rb:34-36`). A conversation's
progress through a published version is a row in `flow_sessions`
(`custom/app/models/flow_session.rb`): `active | waiting | handed_off | completed | failed | cancelled`.

A flow only ever **answers** a conversation, and only in Chatwoot's bot phase: the inbox's active bot is this flow
bot, the conversation is `pending`, nobody is assigned, and the AI assignee is nil or this bot
(`custom/app/services/flows/runner.rb:137-140`). It cannot start a conversation and cannot be triggered by a store
event, a schedule, a webhook or a campaign — the only entry is a customer's incoming non-private message
(`custom/app/listeners/custom/agent_bot_listener.rb:10-11`).

**The product distinction from automation rules**, stated from the code rather than the marketing: a rule is
evaluated once against an event and finishes; a flow has a persisted session with a cursor (`current_node_id`),
stored values (`context`), timers (`wake_at`, `step_token`) and safety counters, so it can stop at a node and
resume when the customer replies minutes or hours later
(`custom/app/services/flows/runner.rb:257-268`). A rule works on every channel; a flow runs on WhatsApp Cloud
only (`custom/app/services/flows/channel_capabilities.rb:19-22`). A rule has an on/off switch; a flow has a draft
you publish.

### Node types

The server owns the contract — the builder renders whatever `Flows::NodeTypes::TYPES` says
(`custom/app/services/flows/node_types.rb:99-124`, shipped to the browser as `node_types` in the show payload,
`custom/app/controllers/api/v1/accounts/flows_controller.rb:121-126`). 22 types:

| Type | Outputs (optional in brackets) | Waits | `data` keys |
|---|---|---|---|
| `start` | next | no | keywords, conditions |
| `send_message` | next | no | text |
| `send_template` | next, [failed] | no | name, language, params |
| `question` | reply, [invalid], [timeout] | yes | text, reply_type, keywords, store_as, max_attempts, retry_text, timeout_minutes |
| `buttons` | one per option, [other], [timeout] | yes | text, options, timeout_minutes |
| `list` | one per option, [other], [timeout] | yes | text, button_label, options, timeout_minutes |
| `condition` | true, false | no | conditions |
| `audience_condition` | true, false | no | conditions |
| `commerce_condition` | true, false | no | conditions |
| `set_contact_attribute` | next | no | key, value |
| `set_conversation_attribute` | next | no | key, value |
| `add_label` / `remove_label` | next | no | labels |
| `assign_agent` | next, [failed] | no | agent_id |
| `assign_team` | next, [failed] | no | team_id |
| `commerce_lookup` | found, [not_found], [unavailable] | no | mode, number |
| `webhook` | next | no | url |
| `delay` | next | yes | seconds |
| `handoff` | none (terminal) | no | team_id, agent_id, priority, labels, reason |
| `goto` | none (jumps to `data.target`) | no | target |
| `end` | none (terminal) | no | resolve |

The load-bearing rule of the whole product is in the file's own header comment
(`custom/app/services/flows/node_types.rb:94`): **"An optional output left unconnected hands the conversation to
humans when the runner takes it (safe default)."** The runner implements it at
`custom/app/services/flows/runner.rb:248-255` — no edge for the output the step chose means
`hand_off(session, "unrouted_#{output}")`.

Per-node behaviour worth documenting:

- `question` re-asks with `retry_text` (or the original text) until `max_attempts`, default 3, then takes `invalid`
  (`custom/app/services/flows/nodes/question.rb:100,113-117`). The answer is checked against the custom attribute
  definition when stored on one (`:139-142`).
- `buttons` / `list` send one WhatsApp interactive message whose option values are `lfb:<node id>:<option id>`, so a
  tap on an older menu can never match the current one; a typed option title or its position number ("2") is also
  accepted; anything else takes `other` if connected, otherwise the menu is re-sent at most twice more and then the
  conversation goes to humans with `no_choice` (`custom/app/services/flows/nodes/choice.rb:10,17-24,47-56`).
- `delay` waits up to 24h on a scheduled job; a customer message during the delay is consumed and does **not** move
  the flow (`custom/app/services/flows/nodes/delay.rb:38`, `custom/app/services/flows/nodes/base.rb:13`).
- `commerce_lookup` reads only the contact's own matched store customers' orders, never writes, and is throttled to
  10 lookups per conversation per hour (`custom/app/services/flows/nodes/commerce_lookup.rb:15,78-83`).
- `webhook` posts through Chatwoot's own `WebhookJob` signed with the **flow bot's** `secret` and never waits for or
  reads the response; it follows `next` immediately
  (`custom/app/services/flows/nodes/webhook.rb:11-19`). On a plan without API and webhooks it silently delivers
  nothing (`:16`).
- `handoff` routes with Chatwoot's `ActionService` (team, agent, priority, labels — each optional), leaves the
  merchant's `reason` as a **private note** and ends the session
  (`custom/app/services/flows/nodes/handoff.rb:58-76`).
- `end` with `resolve: true` resolves the conversation (`custom/app/services/flows/nodes/end.rb:14-17`).

### Publishing, drafts, templates and duplication

`Flows::Versions` is the whole lifecycle (`custom/app/services/flows/versions.rb`):

- A new flow has no version. The first edit creates draft v1 from `STARTER` — a Start node wired to an End node
  (`:20-26,85-89`).
- `save!` stores the draft after a **shape-only** check; references, routing and channels are checked at publish
  (`:37-45`, `custom/app/services/flows/graph_validator.rb:44-47`).
- `publish!` runs the full `Flows::GraphValidator`, archives the previous published version, flips the draft to
  published (`:49-60`). After publishing the bot has no draft; the next edit creates a new draft from the published
  graph, which is why "published + draft exists" is exactly the signal the UI uses for *unpublished changes*
  (`app/javascript/dashboard/routes/dashboard/settings/flows/Index.vue:175`).
- `disable!` archives the published version and enqueues `Flows::RunJob(..., 'disabled')` for every live session so
  humans take those conversations (`:63-72`).
- `delete!` refuses with `{ code: 'flow_active' }` while a published version or a live session exists (`:74-81`).

**Templates** are not a separate engine: `app/javascript/dashboard/recipes/flowTemplates.js` builds an ordinary
graph, the client creates a normal flow and saves it as the draft with the normal calls, then opens the builder
(`Index.vue:126-145`). Eight templates: `commerce_order_tracking`, `commerce_after_sales`,
`support_department_routing`, `faq_menu`, `complaint_intake`, `vip_priority_routing`, `bilingual_welcome`,
`whatsapp_welcome_menu` (`flowTemplates.js:81,163,229,290,360,426,476,520`). The created flow's description records
provenance: *"Created from the {name} template (v{version})."*
(`app/javascript/dashboard/i18n/locale/en/recipes.json:107`).

**Duplication** is a client-side compose: read the source's graph, create a new flow, save that graph as its draft
(`Index.vue:86-91,93-119`). The copy starts unpublished and attached to no inbox, deliberately — "an inbox holds one
bot, so connecting the copy would take the inbox away from the original" (`Index.vue:84-85`).

### Attaching a flow to an inbox

There is no flow-specific attachment mechanism. A flow is attached with Chatwoot's own
`POST /api/v1/accounts/:id/inboxes/:inbox_id/set_agent_bot`
(`config/routes.rb:209`, `app/controllers/api/v1/accounts/inboxes_controller.rb:69-78`), which creates or updates the
single `AgentBotInbox` row for that inbox. **One bot per inbox**, flow or webhook. Two surfaces call it:

- the builder header's *Connect a WhatsApp inbox* select
  (`app/javascript/dashboard/routes/dashboard/settings/flows/FlowBuilder.vue:205-216,363-369`), and
- the inbox's own **Bot Configuration** tab
  (`app/javascript/dashboard/routes/dashboard/settings/inbox/components/BotConfiguration.vue:95-99`).

These two surfaces disagree, which is finding F3 below.

### How a flow hands over to a human

Always through Chatwoot's `Conversation#bot_handoff!` (`app/models/conversation.rb:183-192`): the conversation
opens, the bot assignee is cleared, `CONVERSATION_BOT_HANDOFF` is dispatched so bot reports count it, and the normal
assignment rules then apply. `Flows::SessionEnd` is the single exit
(`custom/app/services/flows/session_end.rb`): `complete` (no handoff), `cancel` (no handoff — the conversation has
already left the bot phase), `fail` and `hand_off` (both hand over), and `skip` for "no session ever started".
`hand_over` only calls `bot_handoff!` when the conversation is still `pending` (`:47-51`).

**The bot stops.** It acts only in the bot phase and the handoff ends that phase; there is no resume. A new session
starts only if a human puts the conversation back to pending and unassigned and the customer writes again
(`docs/flow-builder/07-human-handoff.md` §Explicit resume).

## 2. Surfaces and routes

| Surface | Path / file:line |
|---|---|
| Sidebar → Automation → Flow Builder | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:922-928` |
| Sidebar → Automation → Bots | `Sidebar.vue:929-934` |
| Flow list | route `settings_flows_index`, `/accounts/:accountId/settings/flows` — `app/javascript/dashboard/routes/dashboard/settings/flows/flows.routes.js:17-22`, component `flows/Index.vue` |
| Flow builder canvas (full page, outside the settings column) | route `settings_flows_builder`, `/accounts/:accountId/settings/flows/:flowId` — `flows.routes.js:23-28`, component `flows/FlowBuilder.vue` |
| Canvas internals | `flows/components/{FlowNode,NodePalette,NodeConfigPanel,ConditionsEditor,OptionsEditor,TemplateEditor,TestPanel,SessionsPanel}.vue`; graph⇄canvas conversion in `flows/flowGraph.js` |
| Agent bots list (flows filtered out) | route `agent_bots`, `/accounts/:accountId/settings/agent-bots` — `settings/agentBots/agentBot.routes.js:9-25`, `agentBots/Index.vue:31-34` |
| Inbox → Bot Configuration | `settings/inbox/Settings.vue:1418`, `settings/inbox/components/BotConfiguration.vue` |
| Flow analytics | route `analytics_flows`, `routes/dashboard/analytics/analytics.routes.js:52-56`, `AnalyticsFlows.vue`; server `custom/app/services/analytics/flows/{overview,metrics}.rb` |
| Contact activity timeline rows for ended runs | `custom/app/services/contacts/activity_timeline/flows_adapter.rb` |

API (`config/routes/flows.rb`, controller `custom/app/controllers/api/v1/accounts/flows_controller.rb`):

| Verb + path | Action | Line |
|---|---|---|
| `GET /api/v1/accounts/:id/flows` | `index` | `:28-30` |
| `POST .../flows` | `create` (name, description; `bot_type: flow` forced) | `:36-40` |
| `GET .../flows/:id` | `show` — graph (draft else published else STARTER), `errors`, `capabilities`, `node_types`, `variables` | `:32-34,121-126` |
| `PATCH .../flows/:id` | `update` (name, description only) | `:42-45` |
| `DELETE .../flows/:id` | `destroy` → `Flows::Versions#delete!` | `:47-50` |
| `PUT .../flows/:id/draft` | `draft` — save graph | `:52-56` |
| `POST .../flows/:id/publish` | `publish` | `:58-61` |
| `POST .../flows/:id/disable` | `disable` | `:63-66` |
| `GET .../flows/:id/sessions` | `sessions` — latest 50, optional `status` filter, no message content | `:17,68-72` |
| `POST .../flows/:id/simulate` | `simulate` — Test Mode, ≤30 inputs | `:74-76,94-110` |

Agent bots use the stock Chatwoot API: `app/controllers/api/v1/accounts/agent_bots_controller.rb` (index, show,
create, update, destroy, avatar, `reset_access_token`, `reset_secret`).

## 3. User-visible states

**Flow list** (`flows/Index.vue`): loading (skeleton rows plus an `sr-only` "Loading flows…" at `:232-234`); empty
state with a template button and a "New flow" button (`:235-260`); populated table. Each row carries a status label
— *Published · version N* or *Not published* (`:168-171`) — plus an amber *Unpublished changes* chip when the flow
has both a published version and a draft (`:175,300-305,322-328`), plus *"{n} conversations in the flow"* when
`live_sessions > 0` (`:329-334`), plus the inbox list or *Not connected* (`:178-180`). The delete button is disabled
while the flow is published (`:367`). Below `sm`, the status and inbox columns collapse into the name cell
(`:52,290-311`).

**Builder** (`flows/FlowBuilder.vue`): spinner while loading (`:415-417`); then palette + canvas + optional right
panel. The header status line composes three facts: published version, *Unsaved changes* when the canvas differs
from the last saved snapshot, *Unpublished changes* when it is saved but not published
(`:108-122`). A red error panel sits top-left on the canvas listing up to 8 server validation problems, each
clickable to select and centre its node (`:473-495`). Node chips in the header show attached inboxes with an X to
disconnect (`:350-362`). The *Connect a WhatsApp inbox* select is hidden entirely when there is no eligible inbox
(`:364`). The *Disable* button appears only when a published version exists (`:398`).

**Node palette is hidden below the `md` breakpoint** (`flows/components/NodePalette.vue:252` — `hidden md:flex`).
On a phone the canvas and panels render but no node can be added, and there is no message saying so.

**Config panel**: per-type fields, with inline hints for Start, menus, Assign agent, Order lookup, Webhook and
templates (`flows/components/NodeConfigPanel.vue:177-180,332,395,418,431`). The template picker has three
degraded states of its own: *"No approved WhatsApp template can be sent from these inboxes…"*,
*"This template is no longer available on these inboxes."* and the per-parameter inputs
(`app/javascript/dashboard/i18n/locale/en/flowBuilder.json:192-199`). The Commerce palette group is hidden unless
`lynomia_commerce` is on (`FlowBuilder.vue:83-85`, `NodePalette.vue:240-242`).

**Test panel** (`flows/components/TestPanel.vue`): a transcript of customer / bot / private-note bubbles, tappable
option buttons that only work on the latest bot message (`:150`), a *Skip the wait* button when a timer is pending
(`:175`), a collapsible *Steps* trace of `node_id → result` (`:163-170`), and a one-line session state combining the
status label and the end reason (`:37-47`). When no session started it says *"The flow did not start: the
conversation would go to your team."* (`:39`).

**Sessions panel** (`flows/components/SessionsPanel.vue`): the latest 50 sessions with a status filter, each showing
the status label, a link to the conversation, *"Node {node} · version {version} · {steps} steps"*, the end reason and
a timestamp. Clicking a row centres that node on the canvas (`:296`).

**The conversation itself shows nothing about the flow.** There is no flow panel, badge or banner in the agent's
conversation view — a grep for `flow_session` / `flowSession` across `app/javascript` returns nothing. The only
agent-visible traces are the bot's messages, the handoff note if the merchant wrote one, the conversation moving
from pending to open, and (after the run ends) a contact-timeline row: *"Flow reached the end" / "Flow stopped on an
error" / "Flow handed to the team"* (`app/javascript/dashboard/i18n/locale/en/contact.json:705-708`).

## 4. Errors and validation messages

All flow-builder strings live in one file, `app/javascript/dashboard/i18n/locale/en/flowBuilder.json` (329 lines),
with an Arabic counterpart `.../ar/flowBuilder.json`. The server sends **codes only** (`{ code, node_id, edge_id,
detail }`, `custom/app/services/flows/graph_validator.rb:13,51-53`); the browser renders them
(`flowGraph.js:209-226`, which also substitutes an option's title for its raw id in `unconnected_output` /
`duplicate_output`).

Toasts (`flowBuilder.json:58-71`): "The draft could not be saved." · "Version {version} is published." · "The flow
could not be published. Fix the problems shown on the canvas." · "The flow is disabled." · "The inbox now answers
with this flow." · "The flow could not be created." · "The flow is deleted." · "The flow could not be deleted." ·
"The flow could not be duplicated." · "The flows could not be loaded." Plus the leave guard "You have unsaved
changes. Leave without saving?" (`:70`) and the error-panel heading "{n} problems to fix before publishing" (`:71`).

Server validation codes, grouped (`flowBuilder.json:252-320` for the strings;
`custom/app/services/flows/graph_validator.rb` and `custom/app/services/flows/node_validator.rb` for the emitters):

- **Shape** — `invalid_graph`, `graph_too_large`, `too_many_nodes` (300), `too_many_edges` (900), `invalid_node`,
  `unknown_node_type`, `invalid_position`, `duplicate_node_id`, `invalid_edge`, `duplicate_edge_id`
  (`graph_validator.rb:15-17,55-106`). These are the only codes a **draft save** can return.
- **Structure** — `start_count` ("A flow needs exactly one Start."), `dangling_edge`, `edge_into_start`,
  `unknown_output`, `duplicate_output`, `unconnected_output` ("Connect the output \"{detail}\"."), `invalid_target`,
  `unreachable`, `loop_without_wait` ("This loop never waits for the customer.")
  (`graph_validator.rb:108-178`).
- **Channel** — `unsupported_channel` → "Not supported on {detail}." where detail is `"<inbox name>: <node types>"`
  (`graph_validator.rb:180-186`).
- **Node data** — 40-odd codes in `Flows::NodeValidator`, including `text_required`, `text_too_long`,
  `unknown_variable`, `invalid_attempts` ("Attempts must be 1 to 5."), `invalid_timeout` ("The wait must be 1 to 1440
  minutes."), `invalid_delay` ("…1 to 86400 seconds."), `unknown_label` / `unknown_team` / `unknown_agent` /
  `unknown_attribute`, `commerce_disabled` ("Commerce is not enabled for this account.",
  `node_validator.rb:94,111`), `webhooks_unavailable` ("Webhooks are not available on this plan.",
  `node_validator.rb:120`), and the eight template codes (`template_required`, `template_no_inbox`,
  `template_not_found`, `template_language_unavailable`, `template_not_approved`, `template_not_allowed`,
  `template_param_missing`, `invalid_template_params`, `invalid_media_url`, `copy_code_too_long`).
- **Lifecycle** — `flow_active` → "Disable the flow before deleting it."
  (`custom/app/services/flows/versions.rb:76`); `no_inbox` → "Connect a WhatsApp inbox to test this flow."
  (`custom/app/services/flows/simulator.rb:68`).

Runtime **end reasons** shown in the Sessions and Test panels (`flowBuilder.json:227-251`): "No option was chosen",
"The 24-hour WhatsApp window closed", "An agent replied", "An agent was assigned", "The flow was disabled", "The
conversation was opened, assigned or resolved", "Human handoff", "Flows are switched off", "Interrupted", "Too many
steps", "Too many messages in a row", "A node ran too many times", "A step failed", "The attribute no longer
exists", "The value does not fit the attribute", "Nothing connected to \"{output}\"", five template reasons, and
"WhatsApp rejected a message".

Authorization and missing-parameter errors come from Chatwoot's shared handler: a feature-off or non-admin request
returns **401** `{"error":"You are not authorized to do this action"}`
(`app/controllers/concerns/request_exception_handler.rb:23-25,37-39`); a malformed `simulate` body returns 422 from
`ActionController::ParameterMissing` (`:26-28`, raised at `flows_controller.rb:96,106,107`).

Agent-bot strings are upstream Chatwoot's (`app/javascript/dashboard/i18n/locale/en/agentBots.json`): "Successfully
updated the agent bot.", "Could not update the agent bot. Please try again.", "Bot added successfully.", "Could not
add bot. Please try again later." They are generic and carry no diagnosis.

## 5. Failure paths

**F1 — A publish that fails for a non-validation reason is reported as a validation problem.** `publish()` catches
everything and always raises the same toast, *"The flow could not be published. Fix the problems shown on the
canvas."*, even on a 500, a timeout or a 401; `errors` is only replaced when the response actually carried some
(`FlowBuilder.vue:189-195`). A user sent to look at a canvas that has no problems has nowhere to go.

**F2 — Disable and inbox connect/disconnect have no error handling at all.** `disable`, `connectInbox` and
`disconnectInbox` `await` without `try`/`catch` (`FlowBuilder.vue:198-216`). A failed call shows the success toast's
absence and nothing else — no error toast, no reverted UI. `disable` even closes its confirmation dialog before the
request (`:199`).

**F3 — The two inbox-attachment surfaces disagree, and the inbox one can attach a flow where it cannot run.** The
builder offers only `Channel::Whatsapp` inboxes (`FlowBuilder.vue:102-107`), but the inbox's **Bot Configuration**
select lists *every* agent bot of the account with no type or channel filter at all
(`BotConfiguration.vue:95-99`) — flows included, under the heading "Select an agent bot". So a flow can be attached
from inbox settings to a website, email or Facebook inbox. The flow then matches no channel
(`Flows::ChannelCapabilities.for` returns nil, `channel_capabilities.rb:19-22`) and every arriving conversation is
skipped with `unsupported_channel` and sent to the team
(`custom/app/services/flows/runner.rb:182-189`), with nothing in the inbox UI explaining why. The Agent Bots list
page does filter flows out (`agentBots/Index.vue:31-34`); Bot Configuration does not.

**F4 — Even the builder's own inbox filter is too loose.** It filters on `channel_type === 'Channel::Whatsapp'` but
not on provider, while capabilities require `provider == 'whatsapp_cloud'`
(`channel_capabilities.rb:21`; providers are `default` (360dialog) and `whatsapp_cloud`,
`app/models/channel/whatsapp.rb:36`). Connecting a `default`-provider WhatsApp inbox succeeds, then publishing is
refused with *"Not supported on <inbox>: <every node type>"* and the user is told nothing about why that inbox is
the problem.

**F5 — Delete is blocked by live sessions with a generic message.** `delete!` refuses while a published version *or*
a live session exists (`versions.rb:76`). The list disables the delete button only on `flow.published`
(`Index.vue:367`), so the reachable sequence *Disable → Delete immediately* (before the `disabled` run jobs have
drained the live sessions) returns 422 `flow_active` and the user sees only *"The flow could not be deleted."*
(`Index.vue:157-166`). The precise string *"Disable the flow before deleting it."* exists in i18n
(`flowBuilder.json:310`) but no code path renders it — `Index.vue` never reads `error.response.data.errors`.

**F6 — A flow that breaks mid-conversation says nothing to the customer.** Every failure path ends in
`Flows::SessionEnd#fail` → `hand_over` → `bot_handoff!`
(`custom/app/services/flows/session_end.rb:18-23,47-51`). No message is sent to the customer, and no note is left
for the agent. From the customer's side the bot simply stops mid-conversation; from the agent's side a pending
conversation becomes open with no explanation visible in the conversation. The reason is recorded only in
`flow_sessions.failure_code` / `context['end_reason']`, readable in the builder's Sessions panel, in the contact
activity timeline once the run has ended, in the audit log (`flow.execution.failed` / `flow.execution.handed_off`,
`custom/app/services/flows/audit.rb:39-48`) and in the structured log. The reachable triggers:

| Trigger | Code | Where |
|---|---|---|
| a node raised | `node_error` (also captured to Sentry) | `runner.rb:233-236` |
| 25 nodes without a wait, or 200 nodes in the session | `step_limit` | `runner.rb:68-70,218-223` |
| one node visited 10 times | `visit_limit` | `runner.rb:69,222` |
| 6 messages between two waits | `send_limit` | `runner.rb:71,220` |
| a reply arrived while the session was still `active` (a worker died mid-run) | `interrupted` | `runner.rb:193-194` |
| an optional output the designer left unconnected | `unrouted_<output>` | `runner.rb:248-255` |
| a free-form message due after WhatsApp's 24h window | `window_closed` | `nodes/send_message.rb:5`, `nodes/question.rb:103,114`, `nodes/choice.rb:31` |
| the template can no longer be sent, `failed` unconnected | six `template_*` codes | `nodes/send_template.rb:56-69` |
| WhatsApp rejected a message the flow sent | `message_rejected` | `custom/app/listeners/custom/agent_bot_listener.rb:17-24`, `runner.rb:109-116` |
| the agent replied, or the business replied from the WhatsApp Business app on a coexistence number | `human_reply` | `runner.rb:102-107` |
| the kill switch or the account feature went off, or the contact was blocked | `flow_unavailable` | `runner.rb:142-144,284-286` |
| the flow was disabled | `flow_disabled` | `versions.rb:63-72`, `runner.rb:118-122` |
| the conversation was opened, assigned, resolved or snoozed from outside | `left_bot_phase` (cancelled, no handoff) | `custom/app/listeners/custom/agent_bot_listener.rb:26-40`, `runner.rb:124-126` |
| nothing published / Start did not match / unsupported channel | no session at all; conversation goes to the team | `runner.rb:169-189`, `session_end.rb:34-38` |

**F7 — Unsaved work.** The route guard uses `window.confirm` (`FlowBuilder.vue:293-296`) and a `beforeunload`
handler covers reload and tab close (`:300-304`); `Cmd/Ctrl+S` saves (`:308-316`). A flow whose draft differs from
the canvas is still the saved draft that **Test** runs — `TestPanel` calls `beforeRun` which saves first
(`FlowBuilder.vue:175-177,515`), so a test can silently write the draft.

**F8 — Test Mode is a real run that is rolled back.** `Flows::Simulator` wraps a real `Flows::Runner` run in a
transaction it always rolls back (`simulator.rb:27-37`), suppressing timers, webhook posts, store calls and handoff
broadcasts via `Flows::Simulator.active?`. Inside that transaction it **reassigns the inbox's `agent_bot_inbox` to
this flow and turns off `enable_auto_assignment`** (`simulator.rb:70-71`), and creates a throwaway contact on a
`+999…` number (`:77`). It is sound only because the rollback holds; a crash between those writes and the rollback
is the risk the design accepted. The test inbox is the flow's first connected inbox, else the account's first
WhatsApp Cloud inbox, else 422 `no_inbox` (`:65-73`).

**F9 — Concurrency and ordering.** Every advance runs inside a per-conversation Redis mutex
(`custom/app/jobs/flows/run_job.rb:11-34`, 60s timeout, 15 retries at 1s), and each customer message is consumed at
most once via `flow_sessions.last_message_id` (`runner.rb:162-167`, capped at 10 messages per run). Timers carry a
`step_token` so a stale wake is ignored (`runner.rb:148-151`).

## 6. Permissions

| Surface | Gate | file:line |
|---|---|---|
| Flow Builder routes (list and canvas) | `featureFlag: lynomia_flow_builder` + `permissions: ['administrator']` | `flows.routes.js:9-12` |
| Flow Builder sidebar entry | derived from the resolved route's `meta.featureFlag` and permissions | `components-next/sidebar/provider.js:120-127`, `Sidebar.vue:922-928` |
| Every flow API action | `Current.account.feature_enabled?('lynomia_flow_builder')` else `Pundit::NotAuthorizedError` → 401 | `flows_controller.rb:20,80-82` |
| Every flow API action | `authorize(@flow \|\| AgentBot, :update?)` → `AgentBotPolicy#update?` = account administrator | `flows_controller.rb:22`, `app/policies/agent_bot_policy.rb:6-8` |
| Tenancy | flows scoped to `Current.account.agent_bots.flow`; `FlowVersion` and `FlowSession` both validate same-account | `flows_controller.rb:84-88`, `custom/app/models/flow_version.rb:30-32`, `custom/app/models/flow_session.rb:66-70` |
| Account feature flag default | `lynomia_flow_builder`, `enabled: false` | `config/features.yml:311-314` |
| Installation kill switch | `LYNOMIA_FLOW_BUILDER_ENABLED` (GlobalConfig then ENV, default on) — off means no session starts or advances; live ones hand over | `custom/app/services/flows/switch.rb:84-91` |
| Commerce nodes | `lynomia_commerce` — palette group hidden, `commerce_disabled` at publish, `unavailable` at runtime | `FlowBuilder.vue:83-85`, `node_validator.rb:94,111`, `nodes/commerce_lookup.rb:20` |
| Webhook node | `account.api_and_webhooks_enabled?` — `webhooks_unavailable` at publish, silent skip at runtime | `node_validator.rb:120`, `nodes/webhook.rb:13-17` |
| Agent Bots page | `featureFlag: agent_bots` (default `enabled: true`) + administrator | `agentBot.routes.js:10,19-22`, `config/features.yml:47-50` |
| Agent bot CRUD, token and secret reset | `AgentBotPolicy` — administrator for everything except `index?`/`show?`, which agents also get | `app/policies/agent_bot_policy.rb` |
| Attaching any bot to an inbox | `authorize @inbox, :show?` on fetch, then `set_agent_bot`; the bot must be `AgentBot.accessible_to(Current.account)` (account bots plus global system bots) | `app/controllers/api/v1/accounts/inboxes_controller.rb:86-94`, `app/models/agent_bot.rb:28-31` |

**No custom-role permission covers flows or bots.** `AVAILABLE_CUSTOM_ROLE_PERMISSIONS` is
`conversation_manage`, `conversation_unassigned_manage`, `conversation_participating_manage`, `contact_manage`,
`report_manage`, `commerce_order_manage`, `support_ticket_manage`
(`app/javascript/dashboard/constants/permissions.js:4-12`). A custom role can never be given the Flow Builder or
Bots; only the `administrator` role reaches them.

Flow bots carry Chatwoot's bot credentials (`AccessTokenable`, `WebhookSecretable`,
`app/models/agent_bot.rb:22,25`). A flow never uses the access token, but it does use `secret` to sign the Webhook
node's deliveries (`nodes/webhook.rb:14`) — the same secret a merchant would read from the Bots UI, which does not
list flows, so there is no UI anywhere that shows a flow's webhook signing secret.

## 7. Contextual-help opportunities

The registry already has the four keys this area needs — `flows: 'flow-builder'`,
`automation: 'automation-rules'`, `automationOrFlows: 'automation-or-flow-builder'`, `agentBots: 'agent-bots'`
(`app/javascript/dashboard/helper/documentationLinks.js:58-62`) — and `FEATURE_DOC_KEYS` maps `flows → flows` and
`agent_bots → agentBots` (`app/javascript/dashboard/helper/featureHelper.js:7,18`). **Not one Flow Builder surface
consumes any of them.** `DocsLink.vue` is used only by Commerce and Platform Support, and the flow list's
`BaseSettingsHeader` passes no `feature-name` and no `link-text` (`flows/Index.vue:206-209`), unlike the Agent Bots
page which does (`agentBots/Index.vue:112,114`).

| UI location | The question a user has there | Registry key | Key exists? |
|---|---|---|---|
| `flows/Index.vue:206-209` (list header) | "What is a flow, and is it what I want instead of a rule?" | `flows` | yes — **not wired** |
| `flows/Index.vue:235-260` (empty state) | "Where do I start — template or blank?" | `flows` | yes — not wired |
| `flows/Index.vue:412-419` (delete dialog) | "Why must I disable it first?" | `flows` | yes — not wired |
| `FlowBuilder.vue:473-495` (error panel) | "What does *this* validation code mean?" | needs a per-code anchor under `flows` | no |
| `FlowBuilder.vue:363-369` (inbox select) | "Why is my WhatsApp inbox not in this list?" | needs `whatsapp`/`flows` | `whatsapp` exists |
| `FlowBuilder.vue:528-535` (disable dialog) | "What happens to the conversations in it now?" | `flows` | yes — not wired |
| `flows/components/TestPanel.vue:110-112` (test hint) | "Is this really safe? Does the customer see it?" | `flows` | yes — not wired |
| `flows/components/SessionsPanel.vue:323-325` (end reason) | "The run says `window_closed` / `step_limit` — now what?" | a flow-troubleshooting key | **no** |
| `NodeConfigPanel.vue:422-431` (webhook hint) | "What is posted, and how do I verify the signature?" | `webhooks` | yes — not wired |
| `NodeConfigPanel.vue:399-418` (order lookup) | "Why does it say the store is unavailable?" | `commerce`/`customer360` | yes — not wired |
| `flowBuilder.json:192` (`TEMPLATE_NONE`) | "How do I get approved templates onto this inbox?" | `whatsappTemplates` | yes — not wired |
| `BotConfiguration.vue:90-99` (inbox bot select) | "Which of these is a flow, and may I put one on this channel?" | `flows` + `agentBots` | yes — not wired |
| `agentBots/Index.vue` list | "Flow or webhook bot?" | `automationOrFlows` / `agentBots` | `agentBots` wired, the comparison not |
| `AnalyticsFlows.vue` | "What counts as a completed run?" | a flow-analytics key | **no** |

## 8. Current documentation coverage

Four EN articles in the `automation` section, each with an AR counterpart
(`custom/db/documentation/{en,ar}/automation/`):

| File | Lines EN / AR | Covers |
|---|---|---|
| `flow-builder.md` | 132 / 127 | what a flow is, when not to use one, the WhatsApp-Cloud limit, how it is entered, the node table, build steps, templates, what publishing refuses, who can do it, limits, troubleshooting |
| `automation-or-flow-builder.md` | 112 / 108 | the rule-versus-flow decision, a side-by-side table, what only each can do, what neither can do, a worked wrong choice |
| `agent-bots.md` | 134 / 128 | webhook bots: when to use, setup steps, the event list, signing, and a flow-versus-bot section |
| `automation-rules.md` | 119 / 112 | rules (agent 036's scope) |

Coverage of this area is unusually good for this corpus, and `flow-builder.md` is largely accurate. Claims I
verified true: WhatsApp Cloud only (`channel_capabilities.rb:21`); entered only by a customer message
(`agent_bot_listener.rb:10-11`); pending and unassigned required (`runner.rb:137-140`); the four waiting nodes
(`node_types.rb` `wait: true` on question, buttons, list, delay); eight templates (`flowTemplates.js`); the publish
checklist, item for item (`graph_validator.rb:28-39`); 300 nodes / 900 connections (`graph_validator.rb:15-16`);
3 buttons / 20-char titles / one list of 10 rows / 4096 chars (`channel_capabilities.rb:9-15`); order lookups capped
at ten per conversation per hour (`nodes/commerce_lookup.rb:15,78-83`); one published version at a time and sessions
staying on their version (`versions.rb:49-60`, `flow_version.rb:34-36`); disable before delete (`versions.rb:74-81`);
administrators only, and not grantable to a custom role (`flows.routes.js:11`, `permissions.js:4-12`); a coexistence
reply ending the session (`runner.rb:102-107`).

## 9. Missing or stale documentation

1. **No article answers "the flow stopped halfway — what does this reason mean?"** `flow-builder.md:132` says only
   "Open **Sessions** on the flow. Each session shows where it ended and why." There are **28 distinct end reasons
   and failure codes** (`flowBuilder.json:227-251`) and the corpus explains four of them. A merchant reading
   *"Too many steps"*, *"A node ran too many times"*, *"Interrupted"* or *"Nothing connected to \"timeout\""* has
   nowhere to go. This is the single largest gap in my scope and wants an article of its own.
2. **The customer-facing silence of a failure is never stated.** No article says that when a flow breaks the
   customer gets no message and the agent gets no note — only a pending conversation turning open. Merchants will
   design around the opposite assumption.
3. **Nothing documents the safety limits** that produce those reasons: 25 nodes between waits, 200 nodes per
   session, 10 visits per node, 6 messages between waits (`runner.rb:68-72`). They are a design constraint a flow
   author needs before building a long flow, not after.
4. **The kill switch is undocumented.** `LYNOMIA_FLOW_BUILDER_ENABLED` (`switch.rb:86-88`) hands every live
   conversation to humans when flipped, and its session reason is the opaque *"Flows are switched off"*. No article,
   including the administration section, mentions it.
5. **No article explains attaching a flow from the inbox side, or the F3/F4 traps.** `flow-builder.md:73` says
   "Attach the published flow to a WhatsApp Cloud inbox, as you would any bot" — which is exactly the path that lets
   a user attach a flow to an unsupported channel, with no warning in the product and none in the docs.
6. **Agent bots are documented from the hosting developer's point of view only.** `agent-bots.md` has no coverage of
   the Bot Configuration tab's shared select, the one-bot-per-inbox rule as it collides with flows, or what happens
   to a conversation when the merchant's endpoint is down (nothing: no handoff, no timeout, the conversation simply
   sits unanswered — `app/listeners/agent_bot_listener.rb:84-89` fires and forgets).

Staleness found: `agent-bots.md:34` says "**Settings → Bots → Add Bot**", which still matches the shipped label
"Bots" (`app/javascript/dashboard/i18n/locale/en/settings.json:352`). I found no stale navigation claims in
`flow-builder.md`.

## 10. Doc claims not proven by code

| Claim | Where | Verdict |
|---|---|---|
| "Publishing is refused with *'Not supported on <inbox>'*" | `en/automation/flow-builder.md:31` | **Confirmed but incomplete.** The code appends the inbox name *and* the offending node types: `detail: "#{inbox.name}: #{unsupported.join(', ')}"` (`graph_validator.rb:184`), rendered as "Not supported on {detail}." (`flowBuilder.json:272`). On a non-WhatsApp inbox `unsupported` is *every* node type (`channel_capabilities.rb:27`), so the real message is long and unlike the article's quotation. |
| "A flow runs on WhatsApp Cloud inboxes, and nothing else" | `flow-builder.md:30` | **Confirmed in the runtime, contradicted in the UI.** True of `ChannelCapabilities` (`:21`), but both attachment surfaces let a user attach a flow to an inbox that is not one (F3, F4). The article states the rule; the product does not enforce it at the point of attachment. |
| "Nothing you save affects a customer" (Save draft) | `flow-builder.md:70` | **Confirmed.** Only `flow_versions.published` is read by `Flows::Runner#start` (`runner.rb:170`). |
| "Press **Test** … Nothing is sent or stored." | `flow-builder.md:71` | **Confirmed for the customer, with a caveat the article omits:** the whole run is rolled back (`simulator.rb:29-37`), but Test first saves the draft if it is dirty (`FlowBuilder.vue:175-177,515`), so pressing Test does store the graph. |
| "Once a person takes the conversation it stops and does not resume." | `flow-builder.md:109-110` | **Confirmed**, and the design doc records the only re-entry: a human setting the conversation back to pending and unassigned starts a brand-new session from Start, never a continuation (`docs/flow-builder/07-human-handoff.md` §Explicit resume). The corpus does not mention that re-entry exists. |
| "no loop that never waits for the customer" | `flow-builder.md:88` | **Confirmed** — `check_loops` / `cycle_from?` treat any waiting node as breaking the cycle (`graph_validator.rb:164-178`). |
| "**Runs with nobody online** — yes" for flows | `automation-or-flow-builder.md:30` | **Unverified as written.** Nothing in the flow runtime consults agent availability or business hours, so the answer is right; but the comparison table's neighbouring claim "**Behave differently out of hours** — neither" (`:65-66`) is the real, verifiable fact and the two rows invite confusion. No business-hours condition exists in `Flows::ConditionRule` or the node set. |
| "an optional **waiting** rule … has to be enabled for your account and is off by default" | `automation-or-flow-builder.md:91-92` | **Not checked** — it is an automation-rules claim, agent 036's scope. Flagged so it is not double-counted. |
| "One bot per inbox." | `en/automation/agent-bots.md:38` | **Confirmed** — a single `AgentBotInbox` row per inbox, replaced in place (`app/controllers/api/v1/accounts/inboxes_controller.rb:69-78`). The article does not say this means a flow and a webhook bot compete for the same slot. |
| "There is no 'conversation created' event for bots." | `agent-bots.md:56-57` | **Confirmed** — `AgentBotListener` defines `conversation_resolved`, `conversation_opened`, `conversation_status_changed`, `conversation_updated`, `message_created`, `message_updated`, `webwidget_triggered`, and nothing else (`app/listeners/agent_bot_listener.rb:2-61`). |

One cross-tree note for the orchestrator: there is **no `enterprise/` overlay for any of this**. Every flow file is
in `custom/app/**` (models, controller, job, listener, 40 services) with `custom/db/migrate/20261004100000_create_flow_versions.rb`
and `..._create_flow_sessions.rb`, hooked into OSS through `prepend_mod_with` on `AgentBot` and `AgentBotListener`
(`app/models/agent_bot.rb:73`, `app/listeners/agent_bot_listener.rb:91`). The 13 design records in
`docs/flow-builder/` (1,426 lines) are the authoritative internal description and are the right source for a
documentation writer to work from — in particular `04-node-contracts.md` for node behaviour, `05-runtime-and-session.md`
for the session model and `07-human-handoff.md` for the complete end-reason table.
