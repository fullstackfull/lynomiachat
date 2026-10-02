# Lynomia Flow Builder: what Chatwoot and Lynomia already have

Discovery before any Flow Builder code, on `claude/laughing-albattani-8yi0kh` at `81ad706d2` (Chatwoot 4.18 + Enterprise
overlay + Lynomia `custom/`: Commerce, Audience, Automation). Paths are the code as found.

```text
EXISTING SYSTEMS TO REUSE:
- Messaging:      Messages::MessageBuilder (sender AgentBot) → Message (Liquidable, after_create_commit) → SendReplyJob →
                  channel send service; ActionCable broadcast on create; delivery status from provider webhooks
- WhatsApp:       Channel::Whatsapp → Whatsapp::SendOnWhatsappService (24 h window, templates) →
                  Whatsapp::Providers::WhatsappCloudService (API and WhatsApp Business coexistence alike);
                  input_select → interactive button (≤ 3 items) or list; inbound via Whatsapp::IncomingMessage*Service
                  with Whatsapp::MessageDedupLock
- AgentBot:       AgentBot (account-scoped identity, bot_type, bot_config jsonb, secret, access token, avatar),
                  AgentBotInbox (one bot per inbox, active/inactive), AgentBotListener (bot events),
                  pending bot phase (Conversation#determine_conversation_status), Conversation#bot_handoff!,
                  CONVERSATION_BOT_HANDOFF → bot reports; Integrations::BotProcessorService (in-process bots)
- Automation:     AutomationRules::ConditionsFilterService (+ Lynomia audience / Commerce keys),
                  AutomationRule validation (Custom::AutomationRule), ActionService actions, WebhookJob
- Conditions:     lib/filters/filter_keys.yml keys and operators, custom attributes, contact_audience,
                  commerce_* (Audience::CommerceCondition, local summaries only)
- Actions:        ActionService (labels, agent, team, priority, status, snooze), as Macros::ExecutionService reuses it
- Assignment:     ActionService#assign_agent / #assign_team (inbox membership / account checks)
- Contact fields: Contact / Conversation custom_attributes + CustomAttributeDefinition (type, list values, regex)
- Realtime:       ActionCable broadcasts of messages and conversations (unchanged by a bot)
- Jobs:           Sidekiq / ActiveJob, scheduled jobs (`set(wait_until:)`), MutexApplicationJob + Redis::LockManager
- Dedup:          Whatsapp::MessageDedupLock (provider message id), Redis SET NX keys (Redis::Alfred)
- Permissions:    AgentBotPolicy (administrators manage bots), conversation permissions for agents
- Audit:          Enterprise Audit::AgentBot (create / update / destroy), Enterprise::AuditLog for named events

NEW COMPONENTS ACTUALLY REQUIRED:
- flow_versions: immutable, versioned graph definitions of a flow bot (a draft and published versions)
- flow_sessions: per-conversation execution state (current node, waiting, timers, step counters)
- the runner that walks a published graph (node executors calling the systems above)
- an interactive-reply id on inbound WhatsApp messages (today only the visible title is kept)
- the visual canvas (@vue-flow/core) and its node settings panel
```

## 1. AgentBot

### Model and tables

`agent_bots`: `name`, `description`, `outgoing_url`, `account_id` (nil = system bot), `bot_type` (enum, only
`webhook: 0`), `bot_config` (jsonb, default `{}`), `secret` (`WebhookSecretable`), plus `AccessTokenable` (an API
token so the bot can call Chatwoot's API as itself) and `Avatarable`.

`agent_bot_inboxes`: `inbox_id`, `agent_bot_id`, `account_id` (set from the inbox), `status` (`active` / `inactive`).
`Inbox has_one :agent_bot_inbox` and `has_one :agent_bot, through:` it: **an inbox has at most one bot**; one bot can be
attached to many inboxes (one `agent_bot_inboxes` row each). `AgentBot.accessible_to(account)` = the account's bots and
system bots.

Audit: `AgentBot.include_mod_with('Audit::AgentBot')` (Enterprise `audited`: create, update, destroy).

### Attachment

`POST /api/v1/accounts/:id/inboxes/:inbox_id/set_agent_bot` (`InboxesController#set_agent_bot`): creates or replaces the
inbox's `AgentBotInbox`, or removes it. `GET …/agent_bot` reads it. Dashboard: Settings → Bots (list / create / edit /
delete, `agentBots/Index.vue`), and the inbox's Bot configuration tab.

### What a bot does to a conversation

- `Conversation#determine_conversation_status` (before create): if `inbox.active_bot?` (an active `AgentBotInbox`, or a
  Dialogflow hook; Enterprise adds an active Captain assistant), a new conversation starts **`pending`** and, with an
  active `AgentBotInbox` and no human assignee, `ai_assignee` = the inbox's bot (`assignee_agent_bot_id`).
- A resolved conversation that the contact writes in again re-opens as `pending` when the inbox has an active bot
  (`Message#reopen_resolved_conversation`).
- **Handoff**: `Conversation#bot_handoff!` sets `waiting_since`, clears `ai_assignee`, sets `open`, dispatches
  `CONVERSATION_BOT_HANDOFF`. `ReportingEventListener#conversation_bot_handoff` records `conversation_bot_handoff` once
  per conversation; bot resolutions are `conversation_bot_resolved`. Bot reports (`V2::Reports::BotMetricsBuilder`) read
  them. A bot calling `POST …/toggle_status` with `status: open` on a pending conversation is a handoff
  (`ConversationsController#bot_handoff?`).
- Assigning a human (`assignee_id`) clears the bot assignee (`reset_agent_bot_when_assignee_present`).
- Captain (Enterprise) does not answer when an external bot is active (`captain_conversation_message?` requires
  `!inbox.external_bot_active?`).

So the "bot phase" of a conversation is already modelled: **pending + ai_assignee = bot**, and the human phase is
**open**. There is no other human-mode flag.

### Events

`AgentBotListener` (async, `EventDispatcherJob`) handles `message_created`, `message_updated`, `conversation_opened`,
`conversation_resolved`, `conversation_status_changed`, `conversation_updated`, `webwidget_triggered` for
`agent_bots_for(inbox, conversation)` = the inbox's active bot plus the conversation's bot assignee. Each becomes an
`AgentBots::WebhookJob` POST to `outgoing_url` (signed with the bot's `secret`); a bot without `outgoing_url` gets
nothing. `message_created` only for `message.webhook_sendable?` messages.

### State

An AgentBot keeps no conversational state: webhook bots keep theirs on their own server and act through the API with
their token. `bot_config` holds configuration only.

### In-process bots that already exist

- `Integrations::BotProcessorService` (Dialogflow): runs on `message.created` / `message.updated` of **pending**
  conversations, reads `submitted_values` of an answered `input_select`, sends replies as messages, and hands off with
  `bot_handoff!` (actions `handoff`, `resolve`).
- Captain (Enterprise): triggered from `MessageTemplates::HookExecutionService` on each incoming message of a pending
  conversation, answers in a job (`Captain::Conversation::ResponseBuilderJob`), hands off with `bot_handoff!`; its
  `Captain::AgentSession` rows are LLM run records (assistant, documents, credits), not a conversation state machine.

## 2. Messaging path

`Messages::MessageBuilder.new(user, conversation, params).perform`:

- `message_type` outgoing; `sender` = `params[:sender_type] == 'AgentBot'` bot of the account, else the `user` passed (a
  bot calling the API is `Current.user`); `content_type` (`text`, `input_select`, `cards`, `form`, …) and
  `content_attributes` (`items`, `in_reply_to`, …), validated by `ContentAttributeValidator` (select items: `title`,
  `value`, `description`).
- `Message` callbacks: `Liquidable` renders `{{contact.*}}`, `{{conversation.*}}`, `{{inbox.*}}`, `{{account.*}}`,
  `{{agent.*}}` through allow-listed `Liquid::Drop`s (`app/drops`, including `contact.custom_attribute.<key>`), never
  code; `after_create_commit` → events (`MESSAGE_CREATED`, `performed_by: Current.executed_by`), `waiting_since`, and
  `SendReplyJob` → the channel's send service. Bot messages count as `bot_response?` (sender `AgentBot`).
- `Message#human_response?`: outgoing, not automation / campaign, sent by a `User` **or an `external_echo`** (a reply
  typed in the WhatsApp Business app on a coexistence number).

## 3. WhatsApp

- **API and WhatsApp Business (coexistence)** are the same `Channel::Whatsapp` with the `whatsapp_cloud` provider;
  coexistence adds echoes of the app's own replies (`external_echo`, outgoing, `status: delivered`, not re-sent).
- **Outgoing**: `Whatsapp::SendOnWhatsappService#perform_reply`: template when `additional_attributes.template_params`
  (Whatsapp::TemplateProcessorService, existing template sending from the dashboard); otherwise a session message only
  when `conversation.can_reply?` (`Conversations::MessageWindowService`: 24 h after the last incoming message); outside
  it the message is marked `failed` ("outside messaging window") and nothing is sent.
- **Interactive**: `WhatsappCloudService#send_message` sends `input_select` messages as `interactive`:
  `BaseService#create_payload_based_on_items` → **buttons** when ≤ 3 items without descriptions (`reply.id` = item
  `value`, `reply.title` = item `title`), else a **list** with one section (`list_button_label`), rows `id` / `title` /
  `description`. No length or count limits are enforced before sending (WhatsApp rejects invalid payloads).
- **Inbound interactive replies**: `Whatsapp::IncomingMessageServiceHelpers#message_content` keeps
  `interactive.button_reply.title` / `list_reply.title` as the message text ("TODO: map interactive messages back to
  button messages"). **The reply id is dropped.** The reply's `context.id` becomes `content_attributes.in_reply_to`
  (the original message), when found.
- **Dedup**: `Whatsapp::MessageDedupLock` (`SET NX`, one day) on the provider message id: one Chatwoot message per
  WhatsApp message, however often Meta retries.
- WhatsApp Flows (`nfm_reply`) responses are stored as `whatsapp_flow_response` content attributes: Meta's own forms,
  unrelated to a conversational flow engine.

## 4. Automation (Lynomia-extended)

- `AutomationRules::ConditionsFilterService.new(rule, conversation, options).perform`: the rule's `conditions` as one SQL
  statement over the conversation, its contact and messages; Lynomia's `contact_audience` (shared audiences only),
  `commerce_*` (local summaries, unknown ≠ zero) and `commerce_event_*` keys. Uses the rule for `conditions`, `account`,
  its id in logs, `authorization_error!` when a condition no longer validates, and (Lynomia) `event_name`.
- `AutomationRule` validation (`Custom::AutomationRule`): condition keys, operators, shared audiences, the account's
  stores, limits (`automation.lynomia.*` messages).
- `ActionService` (base class of `AutomationRules::ActionService` and `Macros::ExecutionService`): `add_label`,
  `remove_label`, `assign_agent` (agent must belong to the inbox), `assign_team` (team of the account),
  `change_priority`, `change_status`, snooze / mute / resolve / open / pending, transcript.
- `send_webhook_event` → `WebhookJob` (queue `medium`) → `Webhooks::Trigger` → `SafeFetch` (SSRF filter, timeout
  `WEBHOOK_TIMEOUT` 5 s, no retry). `Webhooks::Trigger` already signs a request when given a `secret`
  (`X-Chatwoot-Timestamp`, `X-Chatwoot-Signature: sha256=HMAC(ts.body)`, `X-Chatwoot-Delivery`); automation webhooks
  pass none.

## 5. Contacts, conversations, labels, teams, agents

- Custom attributes: `contacts.custom_attributes` / `conversations.custom_attributes` (jsonb), defined per account by
  `CustomAttributeDefinition` (`attribute_model` contact / conversation, `attribute_display_type` text, number,
  currency, percent, link, date, list, checkbox; `attribute_values` for lists; `regex_pattern`). The value is not
  validated server-side today (the dashboard validates); the definitions are the contract.
- Labels: `Labelable#add_labels` / `label_list` (acts_as_taggable): adding an existing label is a no-op.
- Teams and agents: `ActionService#assign_team` ignores another account's team; `#assign_agent` only assigns members of
  the inbox (or administrators).
- Opt-out: `contacts.blocked` (block contact). A blocked contact's new conversations are created `resolved`.

## 6. Commerce (Lynomia)

- Local, no HTTP: `commerce_contact_metrics` summaries through `Audience::CommerceCondition` (automation conditions).
- Live reads (provider + Redis cache, existing rate-limit backoff): `Commerce::Customer360.new(conversation:, user:)`
  (all stores, latest orders, active / shipped counts), `Commerce::ConversationPanel` (one store, link + latest orders,
  tracking), `Commerce::OrderSearch.new(stores:, number:)` (order number lookup in providers that support it,
  concurrent, per-store errors). `user` is used only for link / unlink audit; reads accept none.
- Order actions (refund, cancel, status) are `Commerce::ActionExecutor`, agent-confirmed: not for a bot.

## 7. Jobs, locks, realtime

- Sidekiq queues `critical`, `high`, `medium`, `low`, …; `ActiveJob` `set(wait:)` / `set(wait_until:)` for timers.
- `MutexApplicationJob#with_lock(key, timeout)` + `retry_on_lock_conflict` (Redis `SET NX EX`, `Redis::LockManager`):
  the existing per-key serialization for jobs.
- ActionCable: messages and conversation updates broadcast by the models; nothing bot-specific.

## 8. Frontend

- Vue 3.5, Tailwind 3, `@vueuse/core` 12, `components-next` design system (Button, Dialog, Input, DropdownMenu,
  FilterSelect, MultiSelect), `SidePanel`. Settings pages under `routes/dashboard/settings/*` (`agentBots`, `automation`,
  `macros`, …).
- **No graph / canvas library** in `package.json` or `node_modules` (no Vue Flow, React Flow, jsPlumb, Drawflow, Rete,
  Konva, Cytoscape, dagre, d3). Macros and automation use vertical lists.
- Candidate: **`@vue-flow/core` 1.48.2** (MIT, Vue 3 native, peer `vue ^3.3`, depends on `d3-drag`, `d3-zoom`,
  `d3-selection`, `d3-interpolate` and `@vueuse/core` 10): pan / zoom, drag, handles and edges, selection, custom node
  components as Vue SFCs. Available from the registry through this environment's proxy.

## 9. Permissions and features

- `AgentBotPolicy`: administrators create / update / delete bots, reset tokens and secrets; agents may list and view.
- Features: `config/features.yml` (`lynomia_commerce` on `feature_flags_ext_1`), checked with
  `account.feature_enabled?`; Lynomia kill switches as installation config with an ENV fallback
  (`LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED`).

## 10. Searched, not present

No conversational state machine, flow / workflow table, node graph, wait-for-reply mechanism, per-conversation bot
session, or visual builder exists in Chatwoot, the Enterprise overlay or Lynomia. `AutomationRulePendingExecution` is a
delayed *rule run* (rule id required, one episode per status change); `Captain::AgentSession` is an LLM run record. Neither
can hold "this conversation is at node X of version Y, waiting for a reply until T".
