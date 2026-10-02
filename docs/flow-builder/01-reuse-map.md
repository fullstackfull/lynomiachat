# Lynomia Flow Builder: reuse map

Decision, from [00](00-existing-system-discovery.md): **a Lynomia flow is a Chatwoot AgentBot** of a new type, `flow`,
attached to inboxes through the existing `AgentBotInbox`, living in the existing bot phase of a conversation (pending,
bot assignee) and leaving it through the existing `bot_handoff!`. What a flow *says and does* goes through Chatwoot's
message builder, channels and `ActionService`, and its conditions are Lynomia Automation's. The only new runtime is the
part nothing in the repository models: a versioned graph, and where a conversation is in it.

## Matrix

| Capability | Existing | Class | Flow Builder |
|---|---|---|---|
| Bot identity | `AgentBot` (name, description, avatar, account, `bot_type`, `bot_config`, `secret`) | **EXTEND** | `bot_type: flow`; the flow *is* the bot. No `LynomiaBot` / `WhatsAppBot` / `CommerceBot`, no `flows` table |
| Bot attachment to inbox | `AgentBotInbox` (one bot per inbox, active / inactive), `set_agent_bot` | **REUSE** | attaching the flow bot to an inbox is what routes its conversations to the flow |
| Flow conflicts | an inbox has at most one bot | **REUSE** | one flow per inbox by construction: no competing flows |
| Bot phase / human phase | `pending` + `ai_assignee` = bot; `open` after handoff | **REUSE** | no second human-mode flag |
| Message receiving | incoming message → `MESSAGE_CREATED` → `AgentBotListener#message_created` (synchronous; inbox bot, bot assignee) | **EXTEND** | for `flow` bots the listener only enqueues the flow runner job (instead of a webhook); webhook bots unchanged |
| Message sending | `conversation.messages.create!` with the AgentBot as sender (the Dialogflow / Captain pattern; `Messages::MessageBuilder` takes `input_select` items only from request params) → `Message` → `SendReplyJob` → channel | **REUSE** | every node message is a normal Chatwoot message (persistence, provider ids, delivery status, realtime) |
| Variables | `Liquidable` + `app/drops` (contact, conversation, inbox, account, custom attributes) | **REUSE** | message text uses Chatwoot's Liquid drops; flow values (Commerce lookup, stored answers) through an allow-listed `{{flow.*}}` pre-substitution, escaped |
| WhatsApp buttons | `input_select` → interactive `button` (≤ 3, no description) | **REUSE** | Buttons node = an `input_select` message, item `value` = the option id |
| WhatsApp lists | `input_select` → interactive `list` (> 3 items or descriptions), one section | **REUSE** + **PATCH** | List node = `input_select` with descriptions; the flow enforces WhatsApp's counts / lengths before sending (a channel capability contract), since the provider enforces none |
| Interactive reply parsing | inbound keeps `button_reply` / `list_reply` **title only** | **PATCH** | keep the reply id on the incoming message (`content_attributes.interactive_reply`); branches follow ids, never translated labels |
| Templates | `additional_attributes.template_params` → `TemplateProcessorService` | **NOT USED (Phase 1)** | a flow starts from a customer message, so its window is open; a session that would send after the window closed hands the conversation to humans instead ([06](06-whatsapp-channel-capabilities.md#templates)) |
| 24 h window | `Conversation#can_reply?` (`Conversations::MessageWindowService`) | **REUSE** | a session message outside the window is not sent: the session ends handed to humans (`window_closed`) |
| Condition evaluation | `AutomationRules::ConditionsFilterService` + `AutomationRule` validation | **REUSE** + **PATCH** | a Condition node holds Automation conditions; validated and evaluated as an unsaved rule; the service skips the reauthorization counter for unsaved rules |
| Audience membership | `contact_audience` condition, shared audiences only | **REUSE** | same key and validation; personal audiences refused |
| Commerce conditions | `commerce_*` keys on local summaries | **REUSE** | same keys, no HTTP |
| Commerce lookup | `Commerce::Customer360`, `ConversationPanel`, `OrderSearch` | **REUSE** + **EXTEND** | the lookup node reads the contact's latest orders through Customer 360 (cache, per-store errors), and searches a quoted number with `OrderSearch`, given an `owners` filter so only the matched customer's orders come back |
| Commerce actions | `Commerce::ActionExecutor` (refund, cancel, status) | **NOT USED** | agent-confirmed only; no bot node |
| Labels | `ActionService#add_label` / `#remove_label` | **REUSE** | idempotent already |
| Custom attributes | `custom_attributes` + `CustomAttributeDefinition` | **REUSE** + **EXTEND** | only defined attributes of the account; the value checked against the definition's type, list values and regex (bounded) |
| Assign agent / team | `ActionService#assign_agent` / `#assign_team` | **REUSE** | inbox membership / account checks as for macros; a missing agent or team follows the node's `failed` output |
| Webhook | `WebhookJob` → `Webhooks::Trigger` → `SafeFetch`; optional HMAC with a secret | **REUSE** | fire-and-continue; signed with the flow bot's own `secret` (`X-Chatwoot-Signature`), unlike unsigned automation webhooks, which stay as they are |
| Conversation status | `ActionService` status actions, `Conversation#bot_handoff!` | **REUSE** | End may resolve; handoff opens |
| Human handoff | `bot_handoff!` (+ `CONVERSATION_BOT_HANDOFF`, bot reports) | **REUSE** | Handoff node = optional team / agent / priority / label, then `bot_handoff!` |
| Human takeover | `Message#human_response?` (agent, or coexistence app echo) | **REUSE** | a human reply in the bot phase ends the session as handed off |
| Jobs | Sidekiq / ActiveJob | **REUSE** | one runner job class |
| Delays, timeouts | `set(wait_until:)` scheduled jobs | **REUSE** | Delay node and reply timeouts are scheduled runner jobs with a step token; no polling, no sleeping |
| Locking | `MutexApplicationJob#with_lock` (Redis) | **REUSE** | one lock per conversation around every advance |
| Dedup | `Whatsapp::MessageDedupLock`; Redis `SET NX` | **REUSE** | one Chatwoot message per provider message already; the session records the last message it consumed |
| Wait for reply | nothing models it | **NEW REQUIRED** | session status `waiting` + node; resumed by the next incoming message |
| Flow definition | `agent_bots.bot_config` (mutable jsonb) | **NEW REQUIRED** | `flow_versions`: published versions must be immutable rows that running sessions point to; a jsonb field rewritten on every save cannot be |
| Flow versions | — | **NEW REQUIRED** | same table: one draft, published history |
| Flow execution / session | `AutomationRulePendingExecution` (delayed rule runs, rule id required), `Captain::AgentSession` (LLM runs, Enterprise) | **NEW REQUIRED** | `flow_sessions`: conversation, version, current node, status, timers, counters, small context |
| Canvas UI | none | **NEW REQUIRED** (dependency) | `@vue-flow/core` |
| Node settings UI | `components-next` inputs, Automation condition rows | **REUSE** | settings panel built from existing components; condition nodes use Automation's `ConditionRow`, field list (`useAutomation`) and payload conversion; the field mapping is shared with the rule builder (`useConditionFilterTypes`) |
| Realtime | ActionCable on messages / conversations | **REUSE** | nothing flow-specific |
| Audit | Enterprise `Audit::AgentBot`; `Enterprise::AuditLog` | **REUSE** + **EXTEND** | bot create / update / delete audited as today; `flow.published`, `flow.disabled`, handoff and failure as named audit entries |
| Permissions | `AgentBotPolicy` | **REUSE** | managing flows, Test Mode and the session inspector take `AgentBotPolicy#update?` (administrators) |
| Feature flag | `config/features.yml` | **EXTEND** | `lynomia_flow_builder` (independent of Commerce) |
| Kill switch | Lynomia installation-config / ENV pattern | **EXTEND** | `LYNOMIA_FLOW_BUILDER_ENABLED`: stops flow execution only |

## Deliberately not created

- a flow model separate from `AgentBot`, a bot model per channel or per purpose;
- an automation, condition or action engine (conditions are Automation's, actions `ActionService`'s);
- a messaging path or a WhatsApp client (no node calls Meta);
- a transcript table: messages stay Chatwoot messages;
- a variable store: persistent answers go to existing custom attributes, temporary ones to the session's context;
- contact, conversation, Commerce or audience copies;
- a lock service, a scheduler, a polling loop;
- AI, CRM, SLA, campaign or broadcast features.

## How AgentBot is used

| Question | Answer (code) |
|---|---|
| Can an AgentBot already attach to an inbox? | Yes: `AgentBotInbox`, `InboxesController#set_agent_bot`, inbox Bot configuration tab |
| Does it receive incoming message events? | Yes: `AgentBotListener#message_created` for the inbox's active bot and the conversation's bot assignee |
| Can it send through the normal message path? | Yes: a message created on the conversation with the AgentBot as sender (as Dialogflow and Captain do) follows `SendReplyJob` and the channel like any other |
| Can it hand conversations to humans? | Yes: `Conversation#bot_handoff!` (pending → open, bot assignee cleared, `CONVERSATION_BOT_HANDOFF`, bot reports) |
| Can multiple inboxes use one AgentBot? | Yes: one `agent_bot_inboxes` row per inbox. An inbox has at most one bot |
| Is bot configuration account-scoped? | Yes: `agent_bots.account_id`, `Current.account.agent_bots` in the API (system bots, account nil, are not flow bots) |
| What state does AgentBot maintain? | None about conversations: identity, `bot_config`, `outgoing_url`, `secret`, token. The bot phase lives on the conversation (`pending`, `assignee_agent_bot_id`) |
| Is it safe to extend? | Yes, through a new `bot_type` value and a prepended listener branch for that type only: webhook bots, their events and payloads are untouched, and every place that already understands "a bot owns this pending conversation" (status, reports, Captain yielding, assignment reset) applies to flow bots as is |
| What must not go inside AgentBot? | Versioned graphs (published versions must be immutable rows sessions reference), per-conversation execution state, timers, and anything per contact. `bot_config` keeps only small bot-level settings |

Hence: Flow = `AgentBot(bot_type: flow)`; inbox scope = its `agent_bot_inboxes`; versions = `flow_versions`; execution =
`flow_sessions`.
