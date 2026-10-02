# Lynomia Flow Builder: architecture

A flow is a **Chatwoot AgentBot of type `flow`** ([01](01-reuse-map.md)). It is connected to WhatsApp inboxes the way
any bot is (`AgentBotInbox`), owns their new conversations while they are in Chatwoot's bot phase, and gives them to
humans with Chatwoot's own `bot_handoff!`. Everything a flow says goes through Chatwoot's message model and the WhatsApp
provider; everything it does goes through `ActionService`, Lynomia Automation's conditions and Commerce's services. The
new code is only what nothing in the repository modelled: versioned graphs, and where a conversation is in one.

```
WhatsApp Cloud webhook ─▶ Chatwoot incoming service ─▶ Message (incoming)
                                                          │ MESSAGE_CREATED (sync dispatcher)
                                                          ▼
                              AgentBotListener (+ Custom::AgentBotListener for flow bots)
                                                          │ Flows::RunJob.perform_later(conversation, 'messages')
                                                          ▼
                     Flows::RunJob  ── Redis lock per conversation (MutexApplicationJob)
                                                          │
                                                          ▼
     Flows::Runner ── FlowSession (version, node, status, context, timers)
         │  node executors (Flows::Nodes::*)
         ├─ say ─────────────▶ conversation.messages.create!(sender: AgentBot) ─▶ SendReplyJob ─▶ WhatsApp provider
         ├─ template ────────▶ the same message with the composer's template_params ─▶ SendOnWhatsappService
         │                     ─▶ TemplateProcessorService ─▶ send_template (WhatsApp API and coexistence alike)
         ├─ conditions ──────▶ AutomationRules::ConditionsFilterService (unsaved AutomationRule)
         ├─ labels / team / agent / priority ─▶ ActionService
         ├─ attributes ──────▶ contact / conversation custom_attributes (account definitions)
         ├─ order lookup ────▶ Commerce::Customer360, Commerce::OrderSearch (owners)
         ├─ webhook ─────────▶ WebhookJob ─▶ Webhooks::Trigger ─▶ SafeFetch (signed with the bot secret)
         ├─ delay / timeout ─▶ Flows::RunJob.set(wait_until:) with a step token
         └─ handoff / failure ▶ Conversation#bot_handoff! (open, ai_assignee cleared)

A flow message turning failed (Meta rejected it) ─▶ MESSAGE_UPDATED ─▶ Custom::AgentBotListener
                              ─▶ Flows::RunJob 'rejected' ─▶ humans (message_rejected)
```

## Components

| Part | Code | Role |
|---|---|---|
| Flow | `AgentBot` (`bot_type: flow`), `Custom::AgentBot` | identity, inbox connection, the bot phase, the secret that signs webhooks |
| Versions | `FlowVersion`, `Flows::Versions` | one draft, one published, archived history ([03](03-data-model-and-versioning.md)) |
| Contracts | `Flows::NodeTypes`, `Flows::NodeValidator`, `Flows::GraphValidator`, `Flows::ChannelCapabilities`, `Flows::Variables` | what each node is, the publish gate, channel limits, the variable allow-list ([04](04-node-contracts.md)) |
| Runtime | `Flows::RunJob`, `Flows::Runner`, `Flows::Run`, `Flows::Nodes::*`, `Flows::SessionEnd`, `FlowSession` | one advance per job under the conversation's lock ([05](05-runtime-and-session.md)) |
| Listener | `Custom::AgentBotListener` (prepended) | enqueues the runner for flow bots; webhook bots unchanged |
| WhatsApp patches | `Custom::Whatsapp::IncomingMessageBaseService`, `Custom::Whatsapp::Providers::BaseService` | keep the reply id of a button or list row; send a List node as a list with its own button label ([06](06-whatsapp-channel-capabilities.md)) |
| API | `Api::V1::Accounts::FlowsController`, `config/routes/flows.rb` | flows, drafts, publish, disable, delete, sessions, Test Mode |
| Test Mode | `Flows::Simulator` | the real runtime on the draft, in a rolled-back transaction |
| Builder | `settings/flows/*` (Vue, `@vue-flow/core`) | canvas, palette, configuration, validation, publish, Test Mode, inspector |
| Switches | `lynomia_flow_builder` (account feature), `LYNOMIA_FLOW_BUILDER_ENABLED` (installation kill switch), `Flows::Switch` | [08](08-security-and-tenancy.md) |
| Observability | `Flows::Log` (`[Lynomia::Flow]` lines), `Flows::Audit` (Enterprise audit log) | ids and timings only |

## Activation, and why flows never compete

An inbox has at most one bot (`AgentBotInbox`), so an inbox runs at most one flow: connecting a flow to an inbox
replaces whatever bot it had. A new conversation in that inbox starts in Chatwoot's bot phase (pending, the flow bot as
`ai_assignee`) and its first customer message starts a session on the **published** version: deterministic, one flow,
one version, no priority rules to resolve. If the Start node's keywords or conditions do not match, or nothing is
published, or the inbox's channel is not supported, the conversation goes to humans at once.

## The bot phase is the only switch

The runner acts only while the conversation is pending, unassigned and owned by this flow bot. Anything that ends the bot
phase in Chatwoot ends the flow: an agent replying (Chatwoot's own `human_response?`, which includes WhatsApp Business app
echoes on coexistence numbers), an assignment, opening or resolving the conversation. There is no second "bot mode" flag.

## Out of scope

AI, CRM, SLA, campaigns and broadcasts, and channels other than WhatsApp Cloud (the capability layer is channel-ready,
[11](11-future-channel-and-ai-contract.md)). No Commerce write action (refund, cancel, status) is reachable from a flow.
