# Flow / Automation / Bots / Macros reuse map

Scope: the orchestration systems, at HEAD `6c381e96` on `claude/practical-thompson-9xfqed`.
Part 19 reuse matrix, then the exact primitive inventories, then the Part 20 starter-catalogue study.
Every claim carries a `path:line`. Where a verifier corrected an inventory agent, the verifier is used.

---

## 1. The decision

**Four engines exist and all four are REUSE. Nothing in the orchestration layer needs a new primitive. The one thing that does need building is the recipe *contract*, and it needs an EXTEND, not a rewrite.**

Three facts drive every recommendation below.

1. **All four engines already share one action vocabulary.** `ActionService` (`app/services/action_service.rb:9-96`) is the base class of `AutomationRules::ActionService` (`app/services/automation_rules/action_service.rb:1-69`) and `Macros::ExecutionService` (`app/services/macros/execution_service.rb:1-72`), **and** it is instantiated directly by the Flow handoff node (`custom/app/services/flows/nodes/handoff.rb:7,15-19`). Flow conditions are literally automation conditions: `Flows::ConditionRule.build` constructs an unsaved `AutomationRule` with `event_name 'conversation_updated'` and evaluates it with `AutomationRules::ConditionsFilterService` (`custom/app/services/flows/condition_rule.rb:7-14`). There is no second condition engine and no second action engine to build.
2. **There is no Conversation Workflow engine to reuse or replace.** `grep -ci workflow db/schema.rb` returns **0**. The name is a frontend route and a sidebar label over two unrelated toggles (`app/javascript/dashboard/routes/dashboard/settings/conversationWorkflow/index.vue:31-47`). See §6. Any "workflow" ask must be mapped onto Automation / Macro / Flow — which is possible for most of them, and provably impossible for two.
3. **The gap is the catalogue, not the engines.** `type` is a scalar (`app/javascript/dashboard/recipes/index.js:13`), `build` returns **one** payload (`:19-20`), and `RecipeDialog` emits **one** `create` (`app/javascript/dashboard/components-next/recipes/RecipeDialog.vue:101`). That is what blocks multi-object kits, macro starters and template starters — all three are blocked by the same 40 lines of contract, not by any missing engine capability.

Consequence: the build order is **(a) extend the recipe contract, (b) add a macro catalogue, (c) patch the two live defects in §8**. Do not build a workflow engine. Do not build a bot-template table.

---

## 2. Part 19 reuse matrix

Legend for *Needs migration?*: **no** = no schema change; **yes (approval)** = a schema change would be required and is left for approval per the brief.

| Capability | Existing implementation | Files / classes | Current UX | Can reuse? | Needs extension? | Needs backend? | Needs migration? | Provider limitations | Permission model | Risk | Recommendation |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Event-triggered rules** | 12 live triggers, condition filter + action chain | `app/models/automation_rule.rb:21-153`; listener `app/listeners/automation_rule_listener.rb:2-35`; `custom/app/listeners/custom/automation_rule_listener.rb:5-7` | Settings → Automation, two tabs, search, clone, per-row toggle | **Yes, fully** | No | No | No | 7 of 12 triggers are commerce and **read-driven**, not webhook-driven (`custom/app/models/commerce/contact_metric.rb:27` is the sole `dispatch` call site; its only callers are `custom/app/services/commerce/realtime.rb:93` and `custom/app/services/commerce/conversation_panel.rb:62`) | `AutomationRulePolicy` administrator-only for all six actions (`app/policies/automation_rule_policy.rb:1-25`); route gated on `automations` (`automation.routes.js:23`) | `event_name` has **no inclusion validation** (`app/models/automation_rule.rb:33-41`; only DB NOT NULL at `db/schema.rb:313`) — a typo saves and silently never fires | **REUSE** |
| **Delayed rules (wait-then-act)** | `execution_delay` 10 min – 30 days + a durable pending-execution row | `app/models/automation_rule.rb:25,28`; `app/models/automation_rule_pending_execution.rb:26-209`; sweep `app/jobs/automation_rules/trigger_pending_executions_job.rb:1-27` every 5 min (`config/schedule.yml:12-15`) | "Runs after a wait" tab + 3 wait presets | **Yes** | No | No | No | An event must still fire first — there is no clock trigger. Conversation-level delayed rules may only add `status` and `inbox_id` conditions (`app/models/automation_rule.rb:28`, enforced `:112-126`) | Same policy; additionally gated on `delayed_automations`, **off by default** (`config/features.yml:272`) | Off means delayed rules neither arm nor fall back to instant; a banner warns (`automation/Index.vue`) | **REUSE** |
| **Visual branching bot (Flow Builder)** | Versioned graph engine, 21 node types, persisted per-conversation session | `custom/app/services/flows/node_types.rb:9-34`; `custom/app/services/flows/runner.rb:19-243`; `custom/app/models/flow_version.rb:9-37`; `custom/app/models/flow_session.rb:11-33` | Settings → Flow Builder: canvas, palette, config panel, Test Mode, session inspector | **Yes, fully** | No | No | No | **WhatsApp Cloud only.** `Flows::ChannelCapabilities.for` returns a table only for `Channel::Whatsapp` with `provider == 'whatsapp_cloud'` (`custom/app/services/flows/channel_capabilities.rb:19-22`); anything else → `unsupported_channel` (`runner.rb:136`) | `AgentBotPolicy#update?` = administrator (`app/policies/agent_bot_policy.rb:6-8`), hard-gated on `lynomia_flow_builder` (`custom/app/controllers/api/v1/accounts/flows_controller.rb:80-82`), route meta `['administrator']` (`flows.routes.js:11`) | Bot-phase only: `bot_phase?` requires `pending` + no assignee (`runner.rb:88-91`). Once assigned or opened, no flow can act | **REUSE** |
| **Agent-invoked action sequence (Macros)** | 16 server-valid actions, flat ordered loop | `app/models/macro.rb:33-35`; `app/services/macros/execution_service.rb:10-21`; `app/jobs/macros_execution_job.rb:1-41` | Settings → Macros editor; run from sidebar, composer and command bar | **Yes** | **Yes — one UI gap**: `change_status` is server-valid but absent from `macros/constants.js` (15 entries) | No | No | No conditions, no waiting, no branching — `perform` is a flat `send` loop (`execution_service.rb:14`) | `MacroPolicy#create?` is `true` for **any** member (`app/policies/macro_policy.rb:6-8`); `Macro#set_visibility` forces `:personal` for agents (`app/models/macro.rb:37-40`); job re-checks `ConversationPolicy#show?` per conversation (`macros_execution_job.rb:11-23`) | Fire-and-forget: controller returns `head :ok` on enqueue (`macros_controller.rb:50-54`) and every per-action error is swallowed into Sentry (`execution_service.rb:15-17`), so the success toast lies | **REUSE** (+ **PATCH** the 15-vs-16 UI gap) |
| **Shared action vocabulary** | One base class for all three engines | `app/services/action_service.rb:9-96` (14 public actions); `enterprise/app/services/enterprise/action_service.rb:2-14` adds `add_sla`; `custom/app/services/custom/automation_rules/action_service.rb:7-14` overrides `send_webhook_event` | Invisible — surfaced as each engine's action list | **Yes** | No | No | No | `assign_agent` requires inbox membership or account admin (`action_service.rb:104-109`); `assign_team` requires account ownership (`:111-113`); both silently skip otherwise | Enforced inside the service, independent of caller | Action ids are **not** validated at save time, so a rule can store a foreign team/agent id and the action silently no-ops at run time | **REUSE** |
| **Shared condition vocabulary** | 18 OSS + 12 Lynomia keys + account custom attributes, 11 operators | `app/models/automation_rule.rb:49-52`; `custom/app/services/automation/lynomia_condition.rb:16-126`; `custom/app/services/audience/commerce_condition.rb:14-33`; `lib/filters/filter_keys.yml` | Automation rule builder; reused verbatim by the Flow `ConditionsEditor` with a `scope` prop | **Yes** | No | No | No | `attribute_changed` is satisfiable on `conversation_updated` **only** (`app/models/conversation.rb:263` is the only `previous_changes` dispatch; `:328` passes nil, `:385` passes `status_change`); Flow Builder rejects it outright (`custom/app/services/flows/node_validator.rb:230`) | Audiences restricted to **shared** contact filters of the account (`lynomia_condition.rb:116`); stores to `account.commerce_stores` (`:103-106`) | `sla_policy_id` is a **dead key** (§3.3) — accepted by the EE model, no `filter_keys.yml` entry, no SQL branch, no UI; a rule using it never matches and auto-disables after 2 evaluations (`app/models/concerns/reauthorizable.rb:16`) | **REUSE** (+ **PATCH**/remove `sla_policy_id`) |
| **Bot attachment to a channel** | One `AgentBotInbox` per inbox | `app/models/agent_bot_inbox.rb:14,22`; `app/models/inbox.rb:76-77` (`has_one`); `app/controllers/api/v1/accounts/inboxes_controller.rb:69-78` | Inbox → Bot Configuration select | **Yes** | **Yes — two UX gaps**: the picker filters neither `bot_type` nor channel (`BotConfiguration.vue:98`); the builder's own connector filters only `channel_type`, never `provider` (`FlowBuilder.vue:102-107`) | No | No | Attaching a flow bot to a non-WhatsApp-Cloud inbox publishes fine, then hands every conversation to humans with `unsupported_channel`. `GraphValidator#check_channels` catches it only for inboxes connected *at publish time* (`graph_validator.rb:180-186`) | Inbox update permissions | The `inactive` enum value is **never written anywhere** in `app/`, `enterprise/` or `custom/` — detach destroys the row. There is no "pause this bot" | **REUSE** (+ **PATCH** the two pickers) |
| **Webhook agent bots** | Signed HTTP delivery of 7 events | `app/listeners/agent_bot_listener.rb:1-91`; `app/jobs/agent_bots/webhook_job.rb:1`; HMAC at `lib/webhooks/trigger.rb:54-63` | Settings → Agent Bots (flow bots filtered out, `agentBots/Index.vue:30-33`) | **Yes** | No | No | No | Delivery is skipped entirely when `outgoing_url` is blank (`agent_bot_listener.rb:85`) — which is exactly how flow bots bypass this path | `AgentBotPolicy`: index/show admin-or-agent, every mutation admin-only | `bot_config` jsonb is permitted (`agent_bots_controller.rb:48`) and serialized (`_agent_bot.json.jbuilder:7`) but **read by no production code** — do not design a starter around it | **REUSE** |
| **Flow versioning / publish** | draft → published → archived, graph frozen once published | `custom/app/services/flows/versions.rb:33-81`; `custom/app/models/flow_version.rb:34-36`; partial unique indexes one-draft/one-published (`db/schema.rb:1254-1268`) | Save (Cmd+S), Publish, Disable, unpublished-changes badge | **Yes** | No | No | No | `publish!` runs full reference + routing validation; `save!` runs shape checks only (`versions.rb:38-46`) | Same as Flow Builder | `POST /flows/:id/simulate` calls `versions.draft` unconditionally (`flows_controller.rb:75`), which **lazily creates** a draft (`versions.rb:33-34,85-89`) — pressing Test on a clean published flow makes it read as having unpublished changes | **REUSE** (+ **PATCH** the Test-Mode side effect) |
| **Flow Test Mode** | Draft replayed on the real runtime inside a rolled-back transaction | `custom/app/services/flows/simulator.rb:12-98` | Test panel: transcript, tappable buttons, fire-timer, node path | **Yes** | No | No | No | No timer scheduled, no webhook posted, no store call, no handoff broadcast, no audit; `commerce_lookup` short-circuits to `not_found` (`custom/app/services/flows/nodes/commerce_lookup.rb:19`) | Same as Flow Builder | Stateless — each call replays the whole input list, `MAX_INPUTS 30` | **REUSE** |
| **Flow observability** | Structured log events + last-50 session inspector | `custom/app/services/flows/log.rb:7-23`; `GET /flows/:id/sessions` capped at 50 (`flows_controller.rb:68-72`) | Sessions panel with status filter | **Yes, for debugging** | **Yes, for reporting** | Yes, for reporting | **yes (approval)** for durable aggregates | `Flows::Log` writes to `Rails.logger` only — no metrics sink, no reports entry | Admin | Nothing answers "what is my completion rate" or "where do people drop off" | **REUSE** as-is; **DO NOT CREATE** a flow analytics surface in this phase |
| **Automation run history** | Delayed runs only | `automation_rule_pending_executions` (`db/schema.rb:290`), purged after 30 days (`app/models/automation_rule_pending_execution.rb:32`); Lynomia rules log one line via `Automation::ExecutionLog` (`custom/app/services/automation/execution_log.rb:7-18`) | None | Partially | Yes | Yes | **yes (approval)** — no `automation_runs` table exists | A plain OSS rule on an OSS trigger leaves **no record at all** | Admin | Merchants cannot see whether a rule fired. This is the single biggest trust gap in the automation product | **EXTEND** — requirement stated, migration left for approval |
| **Proactive / outbound flow start** | — | — | — | **No** | — | Yes | Possibly | `Flows::Runner`'s only session-creating path is private `#start`, reached solely from `#consume` on an **incoming customer message** (`runner.rb:105-132`); `RunJob` accepts only `messages\|human\|rejected\|wake\|stop\|disabled` (`custom/app/jobs/flows/run_job.rb:20-33`); the routes expose no start endpoint (`config/routes/flows.rb:4-19`) | — | Any "start a flow from a campaign / schedule / API" promise is unimplementable today | **NEW PRIMITIVE REQUIRED** |
| **Time-of-day / business-hours condition** | — | — | — | **No** | — | Yes | Possibly | Zero time keys in `conditions_attributes` (`app/models/automation_rule.rb:49-52`); `filter_keys.yml` conversations section has only absolute `created_at` / `last_activity_at`. Out-of-hours exists solely as a per-inbox auto-reply (`app/models/concerns/out_of_offisable.rb:22-28`) | — | Kills every out-of-hours routing recipe | **NEW PRIMITIVE REQUIRED** |
| **Escalation levels (L1/L2/L3)** | — | — | — | **No** | — | Yes | **yes (approval)** | `enterprise/lib/captain/tools/handoff_tool.rb:120-131` is an explicit TODO block naming exactly this. No `escalation_level` column in `db/schema.rb`; the only tier mechanic is `Conversation#priority` (4 values, `app/models/conversation.rb:87`) | — | "Escalation" in any starter must mean priority + team, nothing more | **DO NOT CREATE** (reframe as priority + routing) |
| **Contact-level triggers / actions** | — | — | — | **No** | — | Yes | No | Neither automation listener defines `contact_created`/`contact_updated`/audience-membership handlers. Every `ActionService` method acts on `@conversation`; `add_label` writes `@conversation.label_list`, not contact labels | — | "When a contact joins an audience, do X" is not expressible | **NEW PRIMITIVE REQUIRED** |
| **Rule chaining** | Deliberately zero-depth | `Current.executed_by = @rule` (`app/services/automation_rules/action_service.rb:6`) → `performed_by:` on every dispatch (`app/models/conversation.rb:389`) → dropped by `performed_by_automation?` (`app/listeners/automation_rule_listener.rb:96-98`) | — | — | — | — | — | Zero chain depth by construction, no opt-in and no depth counter | — | A starter must never assume rule B sees rule A's work | **DO NOT CREATE** |
| **AI / Captain node inside a flow** | — | — | — | **No** | — | Yes | Possibly | The 21-key registry contains nothing AI-related (`node_types.rb:9-34`). `enterprise/app/builders/captain/assistant_resolution_flow_builder.rb` is unrelated to `FlowVersion`/`FlowSession`. Captain attaches via `CaptainInbox`, a separate runtime (`enterprise/app/models/captain/assistant.rb:19`) | — | Captain and Flow are two different bot runtimes competing for the same `ai_assignee` column | **NEW PRIMITIVE REQUIRED** |
| **Macro conditions / branching / waiting** | — | — | — | **No** | — | Yes | **yes (approval)** | `macros` has no conditions column (`db/schema.rb:1389`: `actions` jsonb, `name`, `visibility` only) | — | If a starter needs a branch, it is a Flow, not a Macro | **DO NOT CREATE** — route to Flow |
| **Macro over many conversations** | API already plural | `macros_controller.rb:51` takes `conversation_ids[]`; `MacrosExecutionJob` iterates | Every caller sends **one** id (`useMacroExecution.js:48`); the conversation bulk-action bar has no macro option | **Yes** | **Yes — UI only** | No | No | — | Per-conversation `ConversationPolicy#show?` re-check already in place | Low — the backend contract is already bulk | **EXTEND** (frontend only) |
| **Recipe catalogue contract** | 3 client-side catalogues, 22 recipes, one dialog | `app/javascript/dashboard/recipes/index.js:25-77`; `useRecipeContext.js:15-139`; `RecipeDialog.vue:1-211` | Three separate entry points, no shared gallery, no route | **Yes** | **Yes — this is the work** | No | No | Single scalar `type`; `build` returns one payload; dialog emits one `create`; 11 input types with no inbox / agent / text / boolean / template control | No role vocabulary at all in the contract — gating is the owning route's `meta` | The audience-preset entry point has **no feature flag and no permission check** (`ContactMoreActions.vue:158-171` appends it unconditionally) | **EXTEND** |
| **Server-side recipe catalogue** | — | — | — | **No** | — | — | — | `grep -i recipe` over `custom/app`, `enterprise/app`, `app/models`, `app/services`, `app/controllers`, `app/jobs`, `lib` returns nothing. Deliberate, recorded at `docs/usability/09-starter-kits-discovery.md §3` | — | Adding one buys nothing in this phase and costs an API surface | **DO NOT CREATE** |
| **Recipe provenance / upgrade path** | Human-editable prose only | `flows/Index.vue:130-133` and `automation/Index.vue:209-212` interpolate `RECIPES.*.PROVENANCE` into `description`; audiences get none | Invisible | No | — | Yes | **yes (approval)** | Nothing reads those strings back; `version` (`index.js:14`) therefore has no upgrade path | — | Objects created from a v1 recipe can never be found, counted or migrated | **EXTEND** — requirement stated, migration left for approval |

---

## 3. The primitives, exactly

### 3.1 All 21 flow node types

`custom/app/services/flows/node_types.rb:9-34` is the complete registry — 21 keys, each with a runtime executor under `custom/app/services/flows/nodes/` and a `check_<type>` branch in `custom/app/services/flows/node_validator.rb:5-240`. The registry is sent verbatim to the canvas as `node_types` (`flows_controller.rb:125`), so the builder draws exactly the outputs the server accepts.

| # | Type | Outputs (optional in brackets) | Waits | `data` keys | Executor | Palette |
|---|---|---|---|---|---|---|
| 1 | `start` | `next` | — | `keywords`, `conditions` | `nodes/start.rb:3-16` | **Not creatable** — seeded by `Flows::Versions::STARTER` (`versions.rb:20-26`); `GraphValidator` requires exactly one (`graph_validator.rb:108-112`) |
| 2 | `send_message` | `next` | — | `text` | `nodes/send_message.rb:3-10` | MESSAGES |
| 3 | `send_template` | `next`, [`failed`] | — | `name`, `language`, `params` | `nodes/send_template.rb:11-62` | MESSAGES |
| 4 | `question` | `reply`, [`invalid`], [`timeout`] | **yes** | `text`, `reply_type`, `keywords`, `store_as`, `max_attempts`, `retry_text`, `timeout_minutes` | `nodes/question.rb:5-53` | MESSAGES |
| 5 | `buttons` | one per option id, [`other`], [`timeout`] | **yes** | `text`, `options`, `timeout_minutes` | `nodes/buttons.rb:2` (subclass of `Choice`) | MESSAGES — max 3 options, title ≤ 20 |
| 6 | `list` | one per option id, [`other`], [`timeout`] | **yes** | `text`, `button_label`, `options`, `timeout_minutes` | `nodes/list.rb:2-6` (subclass of `Choice`) | MESSAGES — max 10 rows |
| 7 | `condition` | `true`, `false` | — | `conditions` | `nodes/condition.rb:3-5` | LOGIC |
| 8 | `audience_condition` | `true`, `false` | — | `conditions` | `nodes/audience_condition.rb:2` | CUSTOMER — keys restricted to `contact_audience` (`node_validator.rb:91`) |
| 9 | `commerce_condition` | `true`, `false` | — | `conditions` | `nodes/commerce_condition.rb:2` | COMMERCE — commerce-gated (`node_validator.rb:93-97`, `NodePalette.vue:14-16`) |
| 10 | `set_contact_attribute` | `next` | — | `key`, `value` | `nodes/set_contact_attribute.rb:1-7` | CUSTOMER |
| 11 | `set_conversation_attribute` | `next` | — | `key`, `value` | `nodes/set_conversation_attribute.rb:1-7` | CUSTOMER |
| 12 | `add_label` | `next` | — | `labels` | `nodes/add_label.rb:4-13` → `ActionService#add_label` | CUSTOMER |
| 13 | `remove_label` | `next` | — | `labels` | `nodes/remove_label.rb:2-7` | CUSTOMER |
| 14 | `assign_agent` | `next`, [`failed`] | — | `agent_id` | `nodes/assign_agent.rb:5-10` → `ActionService#assign_agent` | TEAM |
| 15 | `assign_team` | `next`, [`failed`] | — | `team_id` | `nodes/assign_team.rb:4-9` → `ActionService#assign_team` | TEAM |
| 16 | `commerce_lookup` | `found`, [`not_found`], [`unavailable`] | — | `mode`, `number` | `nodes/commerce_lookup.rb:13-83` | COMMERCE — 10 lookups/hour per conversation |
| 17 | `webhook` | `next` **only** | — | `url` | `nodes/webhook.rb:9-30` | INTEGRATION — fire-and-forget; the response is never read |
| 18 | `delay` | `next` | **yes** | `seconds` (1..86 400) | `nodes/delay.rb:3-7` | FLOW |
| 19 | `handoff` | — (terminal) | — | `team_id`, `agent_id`, `priority`, `labels`, `reason` | `nodes/handoff.rb:5-24` → `ActionService` ×4 | TEAM |
| 20 | `goto` | — (terminal in the registry) | — | `target` | `nodes/goto.rb:3-5` | FLOW — returns `Step.next('target')`; `Runner#follow` finds no edge and falls back to `data['target']` (`runner.rb:200-207`) |
| 21 | `end` | — (terminal) | — | `resolve` | `nodes/end.rb:3-8` | FLOW |

Four waiting nodes (`question`, `buttons`, `list`, `delay`), three terminal (`handoff`, `goto`, `end`). Palette groups: 7 (`flowGraph.js:5-25`), listing the 20 non-`start` types; `NodeIcons` covers all 21. `NodeConfigPanel.vue` has an editor for every one of the 21.

**Node gaps worth naming once:** no attachment/media/location/product node (`Flows::Run#say` only ever builds `:text` or `:input_select`, `custom/app/services/flows/run.rb:38-45`), no CSAT node (`Flows::Template` skips CSAT templates by name, `template.rb:32`), no subflow/call-another-flow (`goto` targets the same graph only, `graph_validator.rb:139-142`), no AI node.

### 3.2 All 12 triggers

Verified complete by the adversarial check: *"TRIGGERS and CONDITIONS: the report is correct and complete."*

| # | `event_name` | Dispatched at | Handler | Frontend | Notes |
|---|---|---|---|---|---|
| 1 | `conversation_created` | `app/models/conversation.rb:328` | `automation_rule_listener.rb:6` | `constants.js:691` | Passes **nil** changed_attributes; skipped for `auto_reply` conversations (`listener:100-103`) |
| 2 | `conversation_updated` | `conversation.rb:262-264,337-341` | `listener:2` | `constants.js:695` | **The only trigger carrying `previous_changes`** — so the only one on which `attribute_changed` works. Gated by `allowed_keys?` (`:348-351`) over `list_of_keys` (`:343-346`) |
| 3 | `conversation_opened` | `conversation.rb:379,385` | `listener:10` | `constants.js:707` | Passes `status_change` (ActiveModel::Dirty's pre-save accessor), not `previous_changes` |
| 4 | `conversation_resolved` | `conversation.rb:380,385` | `listener:14` | `constants.js:699` | Same; **not** in the auto-reply skip list (`listener:42`) |
| 5 | `message_created` | `app/models/message.rb:380` | `listener:18` | `constants.js:703` | Dispatches only `message:` and `performed_by:` — **no changed_attributes**, yet the listener reads `event.data[:changed_attributes]` at `listener:20`, which is therefore always nil here |
| 6–12 | `commerce_order_{created,updated,paid,shipped,delivered,cancelled,refunded}` | `custom/app/services/automation/commerce_events.rb:16-24` | generated at `custom/app/listeners/custom/automation_rule_listener.rb:5-7` | `lynomiaAutomation.js:13-21` | **Read-driven.** Facts/events at `custom/app/services/commerce/order_transitions.rb:22-29`. Dedup per rule per event via Redis `SET NX`, 7-day TTL (`commerce_events.rb:38-40`) |

Three further facts a starter author must know:

- **`event_name` is not validated.** `app/models/automation_rule.rb:33-41` declares six `validate` calls and two `validates`; none touches `event_name`. The controller merely permits it (`automation_rules_controller.rb:62`). An arbitrary name saves through the API and the rule simply never fires.
- **`DELAYED_TRIGGERS` are not triggers.** `constants.js:818-830` presents `conversation_status`, `customer_unresponsive` and `agent_unresponsive` as choices, but each maps to a real event plus preset conditions: `conversation_updated` + `status`, `message_created` + `message_type outgoing` + `private_note false`, `message_created` + `message_type incoming`.
- **No `conversation_status_changed`, `assignee_changed` or `team_changed` trigger.** Those event types exist (`app/models/concerns/events/types.rb:30,33,34`) and other listeners consume them (`csat_survey_listener.rb:2`, `agent_bot_listener.rb:18`) — the automation listener has no method for any of them.

### 3.3 All conditions

**18 OSS keys** — `app/models/automation_rule.rb:49-52`, verified by direct read:
`content`, `email`, `country_code`, `status`, `message_type`, `browser_language`, `assignee_id`, `team_id`, `referer`, `city`, `company_name`, `inbox_id`, `mail_subject`, `phone_number`, `priority`, `conversation_language`, `labels`, `private_note`.

`city` is **backend-only**: accepted by the model and evaluable (`conditions_filter_service.rb:131-143`) but has no `constants.js` entry for any event, so the builder never offers it. `message_type`, `private_note` and `content` are offered on `message_created` only.

**1 EE key, dead** — `sla_policy_id` (`enterprise/app/models/enterprise/automation_rule.rb:2-4`). Accepted by the model; **no** `filter_keys.yml` entry, **no** `ConditionsFilterService#apply_filter` branch, **no** UI. Validation falls through `condition_validation_service.rb:45` → `:58-64` and returns false, which trips `Reauthorizable`'s threshold of 2 and auto-disables the rule. Treat as a bug, not a capability.

**12 Lynomia keys**: `contact_audience`, `commerce_event_store`, `commerce_event_provider` (`custom/app/services/automation/lynomia_condition.rb:17,19,22`) plus `commerce_store`, `commerce_provider`, `commerce_orders_count`, `commerce_last_purchase_at`, `commerce_active_order`, `commerce_order_status`, `commerce_payment_status`, `commerce_shipment_status` and the dynamic `commerce_spend_<ccy>` (`custom/app/services/audience/commerce_condition.rb:14-25`). The two `commerce_event_*` keys are valid on commerce triggers **only** — on anything else the model rejects with `event_condition_without_trigger` (`custom/app/models/custom/automation_rule.rb:26-31`).

**Plus** any `custom_attribute_definitions` key of the account (`automation_rule.rb:82` → `condition_validation_service.rb:58-64`), manifested in the UI for four of the five OSS events — `conversation_resolved` is omitted (`useAutomation.js:170-175`).

**11 operators**: `equal_to`, `not_equal_to`, `contains`, `does_not_contain`, `is_present`, `is_not_present`, `is_greater_than`, `is_less_than`, `days_before`, `starts_with` (10 SQL — `app/services/filter_service.rb:25-45`, with `starts_with` added by the automation override at `conditions_filter_service.rb:54-61`) plus `attribute_changed`, which bypasses the operator list entirely and is evaluated in Ruby (`:81-109`). `attribute_changed` has **zero occurrences under `app/javascript`** — no UI can produce or edit it — is forbidden on delayed rules (`automation_rule.rb:112-117`), is rejected by Flow Builder (`node_validator.rb:230`), and is only satisfiable on `conversation_updated`. `query_operator` is restricted to `AND`/`OR` (`automation_rule.rb:104-108,141-149`).

`filter_keys.yml` also defines `contact_id`, `display_id`, `campaign_id`, `created_at`, `last_activity_at`, `name`, `identifier`, `blocked` — **none** of these are in `conditions_attributes`, so `json_conditions_format` (`automation_rule.rb:77-84`) rejects them at save. They exist for the conversation and contact filter services only.

### 3.4 All 20 actions

**19 OSS** at `app/models/automation_rule.rb:54-59` (read directly) **+ 1 EE** = 20. The frontend flat list `AUTOMATION_ACTION_TYPES` (`constants.js:712-808`) has 19 — `change_status` is the only backend-only action.

| # | Action | Implementation | Frontend | Notes |
|---|---|---|---|---|
| 1 | `send_message` | `automation_rules/action_service.rb:43-48` | `constants.js:789-792` | Public outgoing, `content_attributes.automation_rule_id`. **Withheld on all 7 commerce triggers**, server-side (`custom/app/models/custom/automation_rule.rb:9,38-39`) and client-side (`lynomiaAutomation.js:173-174`) |
| 2 | `add_label` | `action_service.rb:37-41` | `:733-737` | Takes label **titles** |
| 3 | `remove_label` | `action_service.rb:57-62` | `:738-742` | Uses `update`, not `update!` — failures are silent |
| 4 | `send_email_to_team` | `automation_rules/action_service.rb:57-66` | `:743-747` | Scoped to `@account.teams`; honours `within_email_rate_limit?`; `deliver_now` |
| 5 | `assign_team` | `action_service.rb:64-74` | `:718-722` | `nil`/`0`/blank unassigns; team must belong to the account |
| 6 | `assign_agent` | `action_service.rb:43-55` | `:713-717` | `'nil'` unassigns; `'last_responding_agent'` resolves dynamically; agent must be an inbox member or account admin |
| 7 | `remove_assigned_agent` | `action_service.rb:76-78` | `:723-727` | — |
| 8 | `remove_assigned_team` | `action_service.rb:80-82` | `:728-732` | — |
| 9 | `send_webhook_event` | `automation_rules/action_service.rb:38-41` | `:779-782` | **Unsigned.** Overridden by `custom/app/services/custom/automation_rules/action_service.rb:7-14` to add `commerce: {event, store_id, provider, order}` whenever `Automation::CommerceEvents.current` is set |
| 10 | `mute_conversation` | `action_service.rb:9-11` | `:753-757` | — |
| 11 | `send_attachment` | `automation_rules/action_service.rb:25-36` | `:784-787` | ActiveStorage blob ids from the rule's own attachments. **Withheld on commerce triggers** |
| 12 | `change_status` | `action_service.rb:29-31` | **absent** | Backend-only **and** it breaks the editor: `useEditableAutomation.js:85-87` calls `.find(...).inputType` on a key that is not in the list, and `AutomationActions.vue:71` → `automationHelper.js:400` throws regardless of params |
| 13 | `resolve_conversation` | `action_service.rb:17-19` | `:763-767` | No EE required-attribute gate here — only `Macros::ExecutionService` has one |
| 14 | `open_conversation` | `action_service.rb:21-23` | `:768-772` | — |
| 15 | `pending_conversation` | `action_service.rb:25-27` | `:773-777` | — |
| 16 | `snooze_conversation` | `action_service.rb:13-15` | `:758-762` | Sets no `snoozed_until` |
| 17 | `change_priority` | `action_service.rb:33-35` | `:799-802` | `'nil'` clears |
| 18 | `send_email_transcript` | `action_service.rb:84-96` | `:748-752` | Comma list; `{{contact.email}}` resolved via `EmailHelper#parse_email_variables` |
| 19 | `add_private_note` | `automation_rules/action_service.rb:50-55` | `:793-797` | **Not** withheld on commerce triggers |
| 20 | `add_sla` **(EE)** | `enterprise/app/services/enterprise/action_service.rb:2-14` | `:804-807` | Requires the `sla` feature at execution **and** `isCloudFeatureEnabled('sla')` to be offered (`AutomationRuleForm.vue:221-223`). No-ops if an SLA already exists or the conversation is not `sla_applicable?` |

**Dead frontend data, flagged by the verifier and confirmed:** the per-event `actions:` arrays at `constants.js:90,232,378,518,648` are never read. `AutomationRuleForm.vue:219-226` builds the dropdown from the flat `AUTOMATION_ACTION_TYPES` filtered only by the SLA flag and `lynomia.actionAllowed` (`lynomiaAutomation.js:173-174`), and `useAutomation.js` touches only `automationTypes[event].conditions`. **Every action is offered on every trigger except the two commerce exclusions.** A starter catalogue must not rely on those per-event lists as a capability map.

### 3.5 All 16 macro actions

`Macro::ACTIONS_ATTRS`, `app/models/macro.rb:33-35`, read directly. **Not** extended by `enterprise/` or `custom/` — contrast `enterprise/app/models/enterprise/automation_rule.rb:7`, which does extend the rule list. `grep -c "key: '"` over `macros/constants.js` returns **15**.

| # | Action | Runtime | Builder offers it | Divergence from the automation behaviour |
|---|---|---|---|---|
| 1 | `send_message` | `macros/execution_service.rb:40-48` | yes | Sender is the **executing user**, not nil |
| 2 | `add_label` | `action_service.rb:37-41` | yes | — |
| 3 | `assign_team` | `action_service.rb:64-74` | yes | — |
| 4 | `assign_agent` | `macros/execution_service.rb:25-28` | yes | Macro override maps the literal `'self'` to the executing user |
| 5 | `mute_conversation` | `action_service.rb:9-11` | yes | — |
| 6 | `change_status` | `action_service.rb:29-31` | **no** | The 15-vs-16 gap. EE no-ops it when required attributes are blank (`enterprise/app/services/enterprise/macros/execution_service.rb:8-12`) |
| 7 | `remove_label` | `action_service.rb:57-62` | yes | — |
| 8 | `remove_assigned_agent` | `action_service.rb:76-78` | yes | — |
| 9 | `remove_assigned_team` | `action_service.rb:80-82` | yes | — |
| 10 | `resolve_conversation` | `action_service.rb:17-19` | yes | EE gate as above — **the only server-side enforcement of required attributes anywhere** |
| 11 | `snooze_conversation` | `action_service.rb:13-15` | yes | — |
| 12 | `change_priority` | `action_service.rb:33-35` | yes | — |
| 13 | `send_email_transcript` | `action_service.rb:84-96` | yes | — |
| 14 | `send_attachment` | `macros/execution_service.rb:50-64` | yes | Only blobs already attached to the macro |
| 15 | `add_private_note` | `macros/execution_service.rb:30-38` | yes | Executing user as sender |
| 16 | `send_webhook_event` | `macros/execution_service.rb:66-69` | yes | `event: 'macro.executed'`. **Unsigned** — no secret is passed, unlike agent-bot deliveries (`agent_bot_listener.rb:87-88`). The commerce enrichment is automation-only |

**Not available to macros and provably so:** `send_email_to_team`, `open_conversation`, `pending_conversation` (all three defined in `ActionService` but absent from `ACTIONS_ATTRS`, so `json_actions_format` rejects them) and `add_sla` (EE extends only the rule list). No macro action touches custom attributes — despite `MACROS.DESCRIPTION` in `en/macros.json` advertising "updating a custom attribute". **That copy is wrong and should be corrected.** Flows have `set_contact_attribute` / `set_conversation_attribute`; macros do not.

Macros do interpolate variables, but not in the macro runtime: `send_message` / `add_private_note` create `Message` rows, and `Liquidable`'s `before_create` renders Liquid with the contact/agent/conversation/inbox/account drops (`app/models/concerns/liquidable.rb:5-44`). So `{{contact.name}}` works for free.

### 3.6 The AgentBot architecture

**Two bot types, no more:** `enum bot_type: { webhook: 0, flow: 1 }` (`app/models/agent_bot.rb:42`). A historical third (`csml`) was backfilled away by `db/migrate/20250410061725_convert_csml_bots_to_webhook_bots.rb`, and `flow` reuses integer 1.

```
AgentBot (account_id nullable — nil ⇒ system bot, agent_bot.rb:67)
├── bot_type: webhook ──► outgoing_url + secret ──► AgentBotListener ──► AgentBots::WebhookJob
│                                                    (skipped when outgoing_url blank, :85)
└── bot_type: flow ─────► Custom::AgentBot (prepended at agent_bot.rb:73)
                          ├── has_many :flow_versions   (draft | published | archived)
                          ├── has_many :flow_sessions   (one live per conversation)
                          ├── flow_bot_shape: account required, outgoing_url MUST be blank
                          └── bot_type_unchanged: immutable on update
                          └► Custom::AgentBotListener ──► Flows::RunJob ──► Flows::Runner

AgentBotInbox (has_one per inbox, inbox.rb:76-77) — the only attachment mechanism,
               created/destroyed by POST /inboxes/:id/set_agent_bot (inboxes_controller.rb:69-78)
```

Four creation paths, and only two can make a flow bot:

| Path | Accepts `bot_type`? | Can create a flow bot? | Citation |
|---|---|---|---|
| Account API `POST /agent_bots` | yes | **yes** (then custom validations forbid `outgoing_url`) | `agent_bots_controller.rb:48` |
| Flows API `POST /flows` | hardcodes `:flow` | **yes** — the intended path | `flows_controller.rb:37` |
| Platform API | no | no | `platform/api/v1/agent_bots_controller.rb:40` |
| Super Admin (administrate) | no | no | `app/dashboards/agent_bot_dashboard.rb:55-61` |

The Settings → Agent Bots UI deliberately excludes flow bots (`agentBots/Index.vue:30-33` filters `bot.bot_type !== 'flow'`) and `AgentBotModal.vue:162` always posts `bot_type: 'webhook'` with a required URL. So from the UI, flow bots exist **only** inside Flow Builder.

Three things that are *not* reusable infrastructure, despite looking like it:
- **`bot_config`** (jsonb, `agent_bot.rb:6`) is permitted and serialized but **read by no production code**. Do not design a bot starter around it.
- **`AgentBotInbox#inactive`** is declared (`agent_bot_inbox.rb:22`) and never assigned anywhere in `app/`, `enterprise/` or `custom/`. There is no pause.
- **`Captain::Assistant`** is a *second* AI-assignee runtime attaching through `CaptainInbox`, not `AgentBotInbox` (`enterprise/app/models/captain/assistant.rb:19`). It also satisfies `Inbox#active_bot?` (`enterprise/app/models/enterprise/inbox.rb:11-17`), so Captain and Flow compete for the same `ai_assignee` column on the same inbox.

---

## 4. Brief 0.3 — what must a ready-made bot starter actually create?

**Answer: `AgentBot(bot_type: :flow)` + one `FlowVersion` draft. That is all today's template path creates, and it is not enough to answer anyone. Before a customer gets a reply, four more conditions must hold: a published `FlowVersion`, an active `AgentBotInbox` on a WhatsApp Cloud inbox, the `lynomia_flow_builder` feature on, and a Start node whose keywords/conditions match the inbound message.**

### 4.1 What the template path creates — proof

`createFromTemplate` (`app/javascript/dashboard/routes/dashboard/settings/flows/Index.vue:124-144`) makes exactly two calls:

```js
const { data } = await FlowsAPI.create({ name, description });   // Index.vue:128-135
await FlowsAPI.saveDraft(data.id, flowTemplate.build(values));   // Index.vue:136
```

- `POST /flows` → `Current.account.agent_bots.create!(flow_params.merge(bot_type: :flow))` (`flows_controller.rb:37`). `flow_params` permits **only** `:name, :description` (`:92`). **No FlowVersion is created here** — `create` calls nothing on `Flows::Versions`.
- `PUT /flows/:id/draft` → `versions.save!(graph)` (`flows_controller.rb:54-57`) → `#save!` calls `draft` (`versions.rb:41`), and `#draft` lazily creates the row: `@bot.flow_versions.draft.first || @bot.with_lock { ... create_draft }` (`versions.rb:33-34`), seeding from `published_flow_version&.graph || STARTER` (`:85-89`).

The source comment states the intent exactly: *"It is unpublished and connected to no inbox, so nothing reaches a customer until the user publishes it themselves"* (`Index.vue:121-123`). That is correct and it is the right default — but it means **a "ready-made bot" starter delivers a draft, not a working bot.**

### 4.2 The full object set required before it answers anyone

| Object / condition | Why it is required | Proof |
|---|---|---|
| `AgentBot` with `bot_type: :flow`, `account_id` present, `outgoing_url` blank | Model validation `flow_bot_shape` | `custom/app/models/custom/agent_bot.rb:17-20` |
| `FlowVersion` with `status: :draft` holding the graph | Where the graph lives; one draft max per bot | `versions.rb:33-34,85-89`; partial unique index `db/schema.rb:1254-1268` |
| `FlowVersion` with `status: :published` | `#start` reads `bot.published_flow_version`; nil ⇒ `start_problem` returns `'no_published_version'` and the conversation is handed to humans | `runner.rb:122,135` |
| …and the published graph must pass full validation | `publish!` runs `GraphValidator` over references, routing, reachability, loops and per-inbox channel support, and raises `Invalid` otherwise | `versions.rb:49-60`; `graph_validator.rb:14-186` |
| `AgentBotInbox` with `status: :active` on the inbox | `Runner#bot` resolves the bot **only** from `inbox.agent_bot_inbox` when `link&.active? && link.agent_bot&.flow?`; nil bot ⇒ `messages` returns immediately | `runner.rb:81-86,33` |
| …and that inbox must be `Channel::Whatsapp` with `provider == 'whatsapp_cloud'` | `ChannelCapabilities.for` returns nil otherwise ⇒ `start_problem` returns `'unsupported_channel'` | `channel_capabilities.rb:19-22`; `runner.rb:136` |
| …and the `AgentBotInbox` must exist **before the conversation is created** | `determine_conversation_status` is a `before_create` hook; it sets `status = :pending` and `ai_assignee` only if `inbox.active_bot?`, which is `agent_bot_inbox&.active?` | `conversation.rb:138,307-325`; `app/models/concerns/inbox_bot_status.rb:4-10` |
| Account feature `lynomia_flow_builder` on | Gates the listener on **every** event (`flow_account?`) and `runnable?` via `Flows::Switch.available?`. Default is **off** | `custom/app/listeners/custom/agent_bot_listener.rb:44`; `custom/app/services/flows/switch.rb:13`; `config/features.yml:286-289` |
| Installation switch `LYNOMIA_FLOW_BUILDER_ENABLED` not false | `Flows::Switch.enabled?`, default true | `switch.rb:8-11` |
| Conversation in the bot phase: `pending`, no `assignee_id`, `ai_assignee ∈ [nil, bot]` | `bot_phase?`; checked on every entry point | `runner.rb:88-91,33,45` |
| A contact, not blocked | `runnable?` | `runner.rb:93-95` |
| A `start` node whose keywords **and** conditions match the first message | `start_problem` returns `'start_not_matched'` otherwise | `runner.rb:125-133`; `nodes/start.rb:3-16` |
| `FlowSession` | Created by the runtime, never by a starter | `runner.rb:127-129` |

**Therefore the honest object set for a "one-click working bot" is: `AgentBot` + `FlowVersion(draft)` + `FlowVersion(published)` + `AgentBotInbox(active)`, plus a feature flag the starter cannot flip and an inbox the starter does not currently ask for.** Of those, `AgentBotInbox` is the one a starter could plausibly create and today does not — and **`inbox` is not an input type at all** (`INPUT_TYPES`, `recipes/index.js:48-60`), by the reasoning recorded in `docs/usability/09a-recipe-opportunity-study.md §8`.

**Recommendation.** Keep publishing out of the starter: the current draft-only default is the correct safety posture, and a starter that auto-published would push unreviewed Arabic/English copy to live customers. Add **inbox selection and `AgentBotInbox` creation as an opt-in final step** — that is an **EXTEND** of the recipe contract (one new `INPUT_TYPE`, one extra call in the owning page) and needs **no migration**. Classification: **EXTEND**. Do not build a bot-template table: **DO NOT CREATE**.

---

## 5. Brief 0.5 — there is no Conversation Workflow engine

### 5.1 The negative, proved

- `grep -ci workflow db/schema.rb` → **0**. Schema version `2026_10_04_110000`.
- No `Workflow` class, module, table, service or state machine in `app/`, `enterprise/`, `custom/` or `lib/`.
- The name occurs in exactly four cosmetic places: the frontend route `conversation_workflow_index` (`conversationWorkflow.routes.js:8-18`), the folder `components-next/ConversationWorkflow/`, the sidebar label (`Sidebar.vue:868-873`), and a Swagger tag description that calls automation rules "Workflow automation rules" (`swagger/index.yml:85`).
- The settings page renders **two children**: `<AutoResolve>` (imported from the *account settings* folder) and `<ConversationRequiredAttributes>`, each behind its own independent feature flag (`conversationWorkflow/index.vue:31-47`). With both flags off, the page body is empty. There is no controller, model, route or table behind the page name.
- All five files in `components-next/ConversationWorkflow/` concern required-custom-attributes-on-resolve only; `constants.js` there holds just `ATTRIBUTE_TYPES`.

**Classification: DO NOT CREATE.** The page name is a misnomer and the only correct product response is to stop treating it as an engine. Renaming it is a copy change, not a build.

### 5.2 The real distinctions — trigger model, state, scope

| | Automation rule | Delayed automation | Macro | Flow |
|---|---|---|---|---|
| **Trigger model** | One of 12 events, fire-and-forget, async via `EventDispatcherJob` | Same event **arms** a row; a 5-minute sweep fires it | An agent clicks it (sidebar, composer or command bar) | An **incoming customer message** while the conversation is in the bot phase |
| **State** | **Stateless.** One pass, no memory between runs | **Durable row** — `automation_rule_pending_executions`, with an `episode_key` and 5 skip reasons | **Stateless.** Flat `send` loop | **Persisted session** — `flow_sessions` with `current_node_id`, `context`, `wake_at`, `step_token`, `last_message_id` |
| **Scope** | Whole conversation lifecycle, any status | Same, re-checked at fire time | One conversation, on demand, whatever its status | **Bot phase only**: `pending` + no assignee + `ai_assignee ∈ [nil, bot]` (`runner.rb:88-91`). Once assigned or opened, the session is cancelled (`custom/app/listeners/custom/agent_bot_listener.rb:26-41`) |
| **Conditions** | 18 + 1 + 12 keys, 11 operators | Same, but conversation-level rules may add only `status` and `inbox_id` | **None** | The *same* condition engine via `Flows::ConditionRule` (`condition_rule.rb:7-14`) |
| **Branching** | No | No | No | **Yes** — the whole point |
| **Waiting** | No | One delay, 10 min–30 days | No | `delay` node ≤ 24h (`node_validator.rb:11,127`) and the three waiting message nodes |
| **Versioning** | None — `active` boolean only | None | None | **draft / published / archived**, graph frozen once published (`flow_version.rb:34-36`) |
| **Attribution** | `Current.executed_by = rule` ⇒ messages have a **nil** sender | Same | `Current.user = user` ⇒ messages are **from the agent** | Messages are from the **bot** (`Flows::Run#say`) |
| **Run record** | **None** for instant rules | A row, purged after 30 days | A log line **only when skipped** (`macros_execution_job.rb:30-40`) | `flow_sessions` + a 50-row inspector endpoint |
| **Who can author** | Administrator only | Administrator only | **Any member** (personal); global is admin-only | Administrator only |
| **Channels** | All | All | All | **WhatsApp Cloud only** |

### 5.3 Where they overlap: the same `ActionService`

This is the single most important architectural fact for the starter library.

```
                          ActionService (app/services/action_service.rb:9-96)
                          14 public actions, + Enterprise::ActionService#add_sla
                                       ▲          ▲          ▲
                     subclass ─────────┘          │          └───────── direct instantiation
                                                  │
 AutomationRules::ActionService          Macros::ExecutionService      Flows::Nodes::Handoff
 (+ Custom:: override of                 (+ Enterprise:: gate on       (handoff.rb:7,15-19 calls
  send_webhook_event)                     required attributes)          assign_team / assign_agent /
                                                                        change_priority / add_label)
```

`AutomationRules::ActionService` and `Macros::ExecutionService` are the repo's only two dynamic `send(action[:action_name], ...)` dispatchers (`automation_rules/action_service.rb:14`, `macros/execution_service.rb:14`). Flow's `add_label`, `remove_label`, `assign_agent` and `assign_team` nodes each call the same base methods. **So "add a label", "assign a team", "change priority" and "resolve" behave identically in all four systems, down to the tenancy guards** (`action_service.rb:104-113`). A starter library can promise consistent action semantics without touching any engine.

### 5.4 Mapping the desired workflow use cases

| Desired use case | Correct engine | Why | Classification |
|---|---|---|---|
| Route new conversations by audience / commerce profile | **Automation** on `conversation_created` + `contact_audience` or `commerce_*` condition + `assign_team` | Already shipped as two recipes (`vip_audience_priority`, `active_order_routing`) | **REUSE** |
| Greet, menu, and route a WhatsApp customer | **Flow** | Branching + waiting; four flow templates already do it | **REUSE** |
| Ask for an order number and look the order up | **Flow** (`question` → `commerce_lookup`) | Only Flow has waiting and lookup | **REUSE** |
| One-click "process a return / cancellation" for an agent | **Macro** | Agent-invoked, no trigger dependency, and the only surface an **agent** can author | **REUSE** engine; **EXTEND** the catalogue (§7) |
| Chase an unanswered conversation after N hours | **Delayed automation**, `customer_unresponsive` or `agent_unresponsive` preset | The only wait longer than 24h | **REUSE** |
| Label / priority on a commerce event | **Automation** on `commerce_order_*` | But the event is **read-driven** — it fires when something re-reads the order, not when the store changes. Never promise "the moment it ships" | **REUSE**, with the caveat in the copy |
| Require fields before resolving | `conversation_required_attributes` | **Client-side only**, except inside `Enterprise::Macros::ExecutionService`. A direct `POST /conversations/:id/toggle_status` bypasses it, and so does Automation's `resolve_conversation` | **PATCH** — the server-side gate belongs at the conversation boundary |
| Auto-resolve idle conversations | `Conversations::ResolutionJob` + account settings | Already shipped, flag on by default | **REUSE** |
| **Out-of-hours routing** | **none** | No time-of-day or business-hours condition anywhere in the rule engine. Out-of-hours is a per-inbox auto-reply only (`out_of_offisable.rb:22-28`) | **NEW PRIMITIVE REQUIRED** |
| **Escalate L1 → L2 → L3** | **none** | No escalation concept; explicit TODO at `enterprise/lib/captain/tools/handoff_tool.rb:120-131`. Only `priority` (4 values) exists | **DO NOT CREATE** — reframe as priority + team |
| Follow up after a human has taken over | **Delayed automation**, never Flow | `Custom::AgentBotListener` fires `'stop'` on any non-pending status change and on any assignee being set | **REUSE** (automation) |
| Multi-step branching on an **assigned** conversation | **none** | Flow is bot-phase-only; Macro has no conditions and no waiting; Automation is single-shot with one delay | **NEW PRIMITIVE REQUIRED** |

---

## 6. The existing 22 recipes

Three client-side catalogues; `9 + 7 + 6 = 22`, confirmed by direct count. No server-side representation of any kind.

**9 audience presets** (`app/javascript/dashboard/recipes/audiencePresets.js:47-157`) — each builds a contact-filter `query`:
`contacted_us`, `never_contacted_us` (these two need **no Commerce** — `requires: []` over the factory's `CONTACT_FILTER`), `high_value_buyers`, `repeat_buyers`, `recent_buyers`, `customers_with_active_order`, `customers_with_shipped_order`, `store_customers`, `linked_commerce_customers`.

**7 automation recipes** (`automationRecipes.js:73-210`) — each builds `{event_name, conditions, actions, active: false}`:
`commerce_new_order_routing`, `commerce_order_shipped_label`, `commerce_refund_escalation`, `commerce_event_webhook` (the only one whose `event_name` the user chooses), `vip_audience_priority`, `high_value_spend_routing`, `active_order_routing`. **All created inactive** (`automationRecipes.js:56`) and opened in the edit panel for review (`automation/Index.vue:214-216`).

**6 flow templates** (`flowTemplates.js:73-403`) — each builds `{nodes, edges}`:
`commerce_order_tracking` (12/19), `commerce_after_sales` (10/12), `support_department_routing` (8/8), `vip_priority_routing` (6/5), `bilingual_welcome` (6/6), `whatsapp_welcome_menu` (4/4).

Three observations that matter for the next catalogue:

1. **No template uses `send_template`.** The node exists with a full validator (`node_types.rb:12`; `custom/app/services/flows/template.rb:10-97`) and no template touches it — because there is no template input control. See §7.
2. **Flow copy is not i18n.** It is hand-written literal Arabic/English in `starterCopy.js:34-171`, with a separate short `both` form for WhatsApp's 20/24-char option titles (`:28-32`). A third locale needs a new `COPY` branch, not a new JSON file.
3. **`category`, `nodeCount`, `edgeCount` and `context.whatsAppInboxes` are all collected and read by no UI.** `RecipeDialog.vue:128-143` renders only name, description and the missing-requirements line. There is no filter, no search, no grouping, and no shared gallery route — the three entry points sit behind three different gates, one of which has no gate at all.

---

## 7. What the recipe contract cannot express

Each blocker, its proof, and its classification.

| # | Cannot express | Why — the three structural blockers | Needs backend? | Needs migration? | Classification |
|---|---|---|---|---|---|
| 1 | **Multi-object kit** (e.g. a Flow + an Automation + a Macro created together) | (a) `type` is a single scalar documented as `'audience' \| 'automation' \| 'flow'` (`recipes/index.js:13`) and `catalogue.spec.js:179-183` asserts every recipe's type equals its catalogue's name. (b) `build` returns one payload for "that type's own create call" (`index.js:19-20`); all 22 return a single object. (c) `RecipeDialog.vue:101` emits one `create(recipe, values)` and each owning page hardcodes one API call (`flows/Index.vue:128-136`, `automation/Index.vue:205-213`, `ContactListHeaderWrapper.vue:227-232`). There is no `type`→creator dispatcher, no step ordering, no cross-step id threading (`build` receives `values` only, so a Flow could not reference an audience the same kit just created) and no partial-failure handling | No | No | **EXTEND** — needs a compound type, a `build` returning an ordered list of typed payloads, a dispatcher, id threading and all-or-nothing failure handling. All client-side |
| 2 | **Macro starter** | No recipe has `type: 'macro'`; `REQUIREMENTS` (`index.js:34-45`) has no `macros` key although `FEATURE_FLAGS.MACROS` exists (`featureFlags.js:21`); `useRecipeContext`'s `satisfied` map (`:40-57`) has no entry for it; `macros/Index.vue` imports no recipe module | No | No | **EXTEND** — one `'macro'` type, one `POST /macros` call site, and input types covering the macro action vocabulary. The engine is 100% ready: 16 actions, all wired. **This is the highest-value, lowest-risk extension in the program** — macros are the only starter surface an agent can author (`app/policies/macro_policy.rb:6-8`) and they have no trigger dependency, so they sidestep the read-driven commerce events and the missing clock entirely |
| 3 | **WhatsApp-template starter** | Three independent blockers. (a) No input control: `INPUT_TYPES` (`index.js:48-60`) has no template picker, and `RecipeInputs.vue`'s `optionsFor` (`:30-61`) has no branch — an unrecognised type falls through to a `type="url"` text field (`:127-135`). (b) A template's parameter slots are **dynamic** per template (`Flows::Template#slots` returns `[section, key, kind]` with kind `:text\|:media_url\|:media_name\|:copy_code`, `template.rb:10-97`), and the wizard has no sub-form mechanism. (c) A template exists only **on an inbox**, and `inbox` is not an input type at all. Templates are also not creatable in the product (`api/inboxes.js:37` exposes only `GET .../message_templates`) | No | No | **EXTEND** for the input plumbing (a TEMPLATE type, an INBOX type, a dynamic slot sub-form); **NEW PRIMITIVE REQUIRED** for the sub-form itself, since no existing input renders a variable number of dependent fields |
| 4 | **Non-flow bot starter** | The only bot a recipe can create is `AgentBot(bot_type: :flow)` via `POST /flows`. `agentBots/Index.vue` imports no recipe module and filters flow bots out of its own list (`:30-33`). There is no `AGENT_BOTS` requirement key and no input type for a bot endpoint beyond the generic URL field. And `bot_config`, the only place bot-level settings could live, is read by nothing | No | No | **DO NOT CREATE** — a webhook-bot starter would have to ship a URL the merchant does not have |
| 5 | **Attaching the created bot to an inbox** (the §4 gap) | `inbox` is not in `INPUT_TYPES`; `useRecipeContext` *does* collect `whatsAppInboxes` (`:21,35`) but no requirement, input type or UI reads it | No | No | **EXTEND** — the data is already in the context object; it needs an input type and one `InboxesAPI.setAgentBot` call |
| 6 | **Missing input types in general** | Declared-but-unusable: `INPUT_TYPES.LABEL` (singular, `index.js:49`) is used by no recipe and has no branch in `RecipeInputs.vue`, so a recipe declaring it silently renders a URL field. Entirely absent: inbox, agent, free text, boolean, template, date, multi-select-other-than-labels. The catch-all `v-else` at `RecipeInputs.vue:127-135` swallows every future type added without touching that file | No | No | **EXTEND** — and add a dev-time guard so an unknown type fails loudly instead of rendering a URL box |
| 7 | **Validation beyond required / number-range / http(s) URL** | `RecipeDialog.vue:67-97` implements exactly three checks; there is no validator hook or regex field on the input manifest. The full descriptor vocabulary actually read anywhere is `{key, type, required, default?, min?, max?}` | No | No | **EXTEND** |
| 8 | **The `context` argument `build` is documented to receive** | `index.js:19-20` documents `build (values, context)`, but all three invocations pass one argument (`flows/Index.vue:135`, `automation/Index.vue:207`, `ContactListHeaderWrapper.vue:227`) and no `build` declares a second parameter. The doc comment is wrong; `docs/usability/10-recipe-architecture.md §2` is right | No | No | **PATCH** the comment, or **EXTEND** by actually passing context — needed anyway for #1 |
| 9 | **Stored provenance / a recipe upgrade path** | The only provenance is interpolated, human-editable prose in `description` (`flows/Index.vue:130-133`, `automation/Index.vue:209-212`); audiences get none. Nothing reads it back. So `version` (`index.js:14`) is catalogue metadata with no upgrade path, and objects created from a v1 recipe can never be found, counted or migrated | Yes | **yes (approval)** | **EXTEND** — requirement stated: a stable `{recipe_id, version}` on the created object. Migration left for approval |
| 10 | **Per-account or user-saved recipes** | The catalogues are module-level `export const` arrays in version-controlled source; nothing writes to them, and there is no storage, endpoint or table. Ruled out at `docs/usability/09-starter-kits-discovery.md §3` | Yes | **yes (approval)** | **DO NOT CREATE** in this phase |
| 11 | **An EE or `custom/` overlay for recipes** | `grep -rn 'recipe\|Recipe\|RECIPE'` over `enterprise/` and `custom/` returns **nothing**. No `prepend_mod_with`, no JS override — the catalogues are plain arrays imported directly by three pages | No | No | **EXTEND** if an EE-only recipe is ever wanted; nothing needed today |
| 12 | **Role conditions inside a recipe** | `REQUIREMENTS` holds only account-capability keys; `satisfied` consults `isCloudFeatureEnabled` plus store collection lengths — no `checkPermissions`, no policy, no role. Gating is entirely the owning route's `meta` | No | No | **EXTEND** — needed because the audience-preset entry point is currently ungated (`ContactMoreActions.vue:158-171`) |
| 13 | **A shared gallery, category filter or search** | No route exists (`grep -rni recipe` over `routes/**/*.js` matches only specs); `RecipeDialog` takes one catalogue per instance (`:19`) and is instantiated three times. `category` is written on all 22 and read by no runtime code; `CATEGORIES.OPERATIONS` and `CATEGORIES.INTEGRATIONS` each have exactly one member no user can see as a category | No | No | **EXTEND** — cheap, and it is the only way a merchant ever sees more than one third of the library |

**Locale caveat for anything added:** of 57 locale directories, only `en` and `ar` ship a `recipes.json`, and `catalogue.spec.js:75-86` enforces that the two stay structurally identical with identical interpolation placeholders. A third locale falls back silently.

---

## 8. Defects in scope for this area

Two are live and both are in the matrix above; recording them plainly so they are not lost.

1. **`sla_policy_id` is a dead condition key that disables the rule that uses it.** Accepted by `enterprise/app/models/enterprise/automation_rule.rb:2-4`; no `filter_keys.yml` entry, no `ConditionsFilterService` branch, no UI. Validation returns false, which trips `Reauthorizable`'s `AUTHORIZATION_ERROR_THRESHOLD = 2` (`app/models/concerns/reauthorizable.rb:16`) and sets `active: false` plus a merchant-facing "automation rule disabled" email. **PATCH**: remove the key, or implement the filter. Either is a small change; shipping it as-is is a trap for any API consumer.
2. **Test Mode mutates version history.** `POST /flows/:id/simulate` calls `versions.draft` unconditionally (`flows_controller.rb:75`), which lazily creates `FlowVersion #n+1` when a published flow has no draft (`versions.rb:33-34,85-89`). After pressing Test on a clean published flow, `Index.vue:174` and `FlowBuilder.vue:119-121` both report "Unpublished changes" for a graph identical to the live one. `docs/flow-builder/05-runtime-and-session.md:78` says simulate "runs the saved draft" and does not mention the side effect. **PATCH**.

Three more, lower severity, each already cited above: the `change_status` action crashes the automation edit panel if a rule carries it (`useEditableAutomation.js:85-87`, `automationHelper.js:400`); macro `send_webhook_event` is unsigned while agent-bot deliveries are signed; and the macros description copy advertises a custom-attribute action that does not exist.

Two UX gaps that will bite any bot starter and are both one-line filters: the inbox Bot Configuration picker filters neither `bot_type` nor channel (`BotConfiguration.vue:98`), and the builder's own inbox connector filters `channel_type` but never `provider` (`FlowBuilder.vue:102-107`) even though `TemplateEditor.vue:29-37` does. Either mistake produces a published flow that hands every conversation to humans with `unsupported_channel`. **PATCH** both.

---

## 9. Requirements that would need a migration — left for approval

Stated, not proposed, per the brief.

| Requirement | Why | What it would need |
|---|---|---|
| Recipe provenance on created objects | Nothing can find, count or migrate objects created from a recipe today, so `version` has no upgrade path | A stable `{recipe_id, version}` on `agent_bots`, `automation_rules` and `custom_filters` |
| Automation run history for instant rules | A merchant cannot see whether a rule fired. Delayed runs leave a row; instant rules leave nothing | An execution-record table, or extending `automation_rule_pending_executions` to cover instant runs |
| Flow analytics (completion, handoff, drop-off per node) | `Flows::Log` writes to `Rails.logger` only; the session inspector is capped at 50 rows | A durable aggregate, or a metrics sink |
| `event_name` integrity | A typo'd event saves and silently never fires | Either an inclusion validation (no migration) or a DB constraint (migration). **The validation is the right fix and needs no migration** |

---

## 10. Summary of classifications

| REUSE (11) | EXTEND (9) | PATCH (6) | NEW PRIMITIVE REQUIRED (5) | DO NOT CREATE (6) |
|---|---|---|---|---|
| Event-triggered rules; delayed rules; Flow Builder; Macros; shared `ActionService`; shared condition vocabulary; bot attachment; webhook bots; flow versioning/publish; Test Mode; flow logs for debugging | Recipe contract (compound type, dispatcher, id threading); **macro starter catalogue**; template-starter input plumbing; inbox input type + `AgentBotInbox` step; missing input types; input validation; `build(values, context)`; provenance; shared gallery + category filter; macro-over-many-conversations (UI); automation run history | `sla_policy_id`; Test-Mode draft side effect; macro builder's missing `change_status`; bot-picker `bot_type`/channel filter; builder inbox `provider` filter; required-attributes server-side gate | Proactive/outbound flow start; time-of-day condition; contact-level triggers and actions; AI/Captain flow node; dynamic template slot sub-form | Conversation Workflow engine; server-side recipe catalogue; bot-template table; rule chaining; escalation levels; macro conditions/branching (route to Flow) |
