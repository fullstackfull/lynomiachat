---
agent: 055
scope: CORPUS audit of the `automation` section (4 articles x EN/AR) against the automation rules, flow builder and agent-bot code
confidence: high
---

# 055 - Corpus audit: `automation`

Baseline `claude/documentation-v2` @ `f986521c` over `lynomia-custom` `021ea6e3`. Read-only. Every claim below was
re-checked against code in this pass; peer reports 036/037 and `_ARBITRATION.md` were used only to look for conflicts,
never as evidence. Where a peer already holds a finding I say so and cite the code myself.

**Instrument note for every corpus agent.** `wc -w` in this shell runs under the POSIX locale and **undercounts Arabic
by about 4x** (it reports `agent-bots.md` AR as 284 words; a Unicode-aware split gives 901). All word counts below are
Python `str.split()` over the body after the front matter. Anyone quoting EN/AR length ratios from `wc` has bad data.

## 1. Inventory

| key | EN file | AR file | title (EN / AR) | pos | EN words | AR words | type |
|---|---|---|---|---|---|---|---|
| `automation-rules` | `custom/db/documentation/en/automation/automation-rules.md` (119 lines) | `.../ar/automation/automation-rules.md` (112) | Automation rules / قواعد الأتمتة | 10 | 977 | 852 | concept + how-to + limits |
| `flow-builder` | `.../en/automation/flow-builder.md` (132) | `.../ar/automation/flow-builder.md` (127) | Flow builder / منشئ التدفقات | 20 | 1055 | 905 | concept + how-to + limits |
| `automation-or-flow-builder` | `.../en/automation/automation-or-flow-builder.md` (112) | `.../ar/automation/automation-or-flow-builder.md` (108) | Automation or flow builder? / أتمتة أم منشئ تدفقات؟ | 30 | 955 | 780 | decision guide |
| `agent-bots` | `.../en/automation/agent-bots.md` (134) | `.../ar/automation/agent-bots.md` (128) | Agent bots / روبوتات وكلاء الدعم | 40 | 1103 | 901 | developer how-to + comparison |

Section total: 4,090 EN / 3,438 AR words. Manifest: `custom/db/documentation/manifest.yml:67-75` (slug `automation`, position 60, icon
`workflow`, EN "Automation and bots"). Contextual-help keys that point here: `DOC_ARTICLES.automation`, `.flows`,
`.automationOrFlows`, `.agentBots` (`documentationLinks.js:59-62`).

## 2. Per-article verdict

| key | verdict | one-sentence reason |
|---|---|---|
| `automation-rules` | **EXPAND** (after five factual corrections) | The prose is honest about limits, but it miscounts triggers/recipes, omits an action and a trigger, states a stale provider fact, and never lists conditions/operators, so the reader cannot build a second rule unaided. |
| `flow-builder` | **EXPAND** | All 21 nodes are named correctly, yet no node's settings, outputs or limits are documented, the runtime safety limits are absent, Delay is described wrongly, and there is no end-to-end worked example. |
| `automation-or-flow-builder` | **KEEP** (two number fixes + three absolutes softened) | Best article in the section; its one-sentence rule ("reacts and finishes / remembers and waits") survives every code check. It repeats the wrong "twelve"/"seven" and three over-absolute "cannot" claims. |
| `agent-bots` | **EXPAND, then consider SPLIT** | It is the only developer-facing page and it stops before the developer can write a handler: no headers, no payload, no API surface, no handoff call; plus three inaccurate limits. Overview and "developer reference" are different readers. |

Nothing here is RETIRE, MERGE or RELOCATE. The four articles are the right set; the gap is depth, not scope.

## 3. Accuracy against the product

Verdict key: **C** confirmed, **W** wrong, **P** partly (true but incomplete or overstated), **U** unverifiable here.

**Path key** (to keep citations short). `runner.rb`, `graph_validator.rb`, `node_types.rb`, `node_validator.rb`, `channel_capabilities.rb`,
`versions.rb`, `simulator.rb`, `reply.rb`, `variables.rb`, `nodes/*` = `custom/app/services/flows/`; `flows_controller.rb` =
`custom/app/controllers/api/v1/accounts/`; `commerce_events.rb` = `custom/app/services/automation/`; `order_transitions.rb`,
`conversation_panel.rb`, `realtime.rb` = `custom/app/services/commerce/`; `contact_metric.rb` = `custom/app/models/commerce/`;
`providers/shopify.rb`, `shopify/normalizer.rb`, `woocommerce/normalizer.rb` = `custom/app/services/commerce/providers/`;
`audience/commerce_condition.rb` = `custom/app/services/audience/`; `automation_rule.rb` = `app/models/` (the `custom/` prefix
marks `custom/app/models/custom/automation_rule.rb`); `automation_rule_listener.rb` and `agent_bot_listener.rb` = `app/listeners/`
unless prefixed `custom/`; `action_service.rb` = `app/services/`, `automation_rules/action_service.rb` = `app/services/`;
`trigger.rb` = `lib/webhooks/`; `webhook_job.rb` = `app/jobs/agent_bots/`; `access_token_auth_helper.rb` = `app/controllers/concerns/`;
`conversations_controller.rb`, `inboxes_controller.rb` = `app/controllers/api/v1/accounts/`, `assignments_controller.rb` under
`.../conversations/`; `message_filter_helpers.rb` = `app/models/concerns/`; `filter_service.rb` = `app/services/`;
`portals/articles_controller.rb` = `app/controllers/public/api/v1/portals/`; `*_policy.rb` = `app/policies/`. Front-end files
(`*.vue`, `*.js`) are under `app/javascript/dashboard/` (`routes/dashboard/settings/automation|flows|agentBots/`, `helper/`,
`recipes/`); `en/*.json` and `ar/*.json` = `app/javascript/dashboard/i18n/locale/`.

### 3.1 `automation-rules.md`

| line | claim | v | evidence |
|---|---|---|---|
| :33-38 | "There are twelve" trigger events | **W** | 13. `event_names` returns 5 conversation events (`app/models/automation_rule.rb:55-57`) plus `Automation::CommerceEvents::EVENTS` (`custom/app/models/custom/automation_rule.rb:34-36`) = 7 order events + `commerce_cart_abandoned` (`custom/app/services/automation/commerce_events.rb:14-15`). The UI offers all 13 (`lynomiaAutomation.js:13-22`; label `AUTOMATION.EVENTS.COMMERCE_CART_ABANDONED`, `en/automation.json`). |
| :35-37 | the five conversation + seven order events listed | C | `order_transitions.rb:22-29` (created, updated, paid, shipped, delivered, cancelled, refunded). The eighth, cart abandoned, is the omission. |
| :40-41 | Commerce trigger acts on the contact's most recent conversation; none = nothing runs | C | `commerce_events.rb:61-63`; `custom/app/listeners/custom/automation_rule_listener.rb:16-17` (logs `no_conversation`). |
| :40 | fires "when Lynomia Chat reads a change" | P | True, but "reads" is the whole story and is never explained: events are emitted only from `Commerce::ContactMetric.record`, which runs from an agent opening the Commerce panel (`conversation_panel.rb:62`) or the webhook-driven refresh (`realtime.rb:93`), never from a poll (`contact_metric.rb:5-8`); the first read of a link is a baseline that emits nothing (`order_transitions.rb:6-7`). The troubleshooting entry (:118-119) gives only two causes and misses both. |
| :43-44 | WooCommerce has no shipped/delivered status | C | `woocommerce/normalizer.rb:17-20` STATUSES has neither. |
| :43-44 | **Shopify has no cancelled status** | **W** | The Shopify query requests `cancelledAt` (`providers/shopify.rb:39`) and the normalizer returns `'cancelled'` when it is present (`shopify/normalizer.rb:66`). The product copy repeats the error (`en/recipes.json` `AUTOMATION.COMMERCE_ORDER_CANCELLED_FOLLOWUP.PROVIDER_NOTE`: "Shopify does not"). `docs/product-enablement/16-commerce-aware-starters.md:30` is the origin (it read `normalizer.rb:15-22` and missed :66); `docs/product-enablement/03-commerce-recipe-capability-matrix.md:299` has it right. |
| :48-52 | conditions cover conversation, message, contact, custom attributes, shared audience, Commerce; "the form expects at least one" | P | Categories correct; "at least one" confirmed (`validations.js:103`, `ATLEAST_ONE_CONDITION_REQUIRED`). Not stated: which fields exist per trigger (they differ: `conversation_resolved` has no labels, `conversation_created` has no assignee/team, `constants.js:157-228`, `:573-647`), the 10 operators (`operators.js`), website/email-only fields (browser language, referrer link, email subject), or that Commerce triggers borrow the `conversation_updated` set (`lynomiaAutomation.js:153-163`). |
| :54-56 | actions list | P | All 18 base actions the UI offers are described (the server's 19th, `change_status`, is not offered by the UI; `app/models/automation_rule.rb:64-69`); **`send_whatsapp_template` is missing** (`custom/app/models/custom/automation_rule.rb:27-29`; UI label "Send an approved WhatsApp template", `en/automation.json` `ACTIONS`). Shown only when the account has a WhatsApp inbox (`lynomiaAutomation.js:183-189`). |
| :58-60 | a Commerce trigger offers neither send message nor attachment; "use a private note and a team instead" | P | Correct as far as it goes (`custom/automation_rule.rb:15,80-81`; `lynomiaAutomation.js:28,184`), but the one customer-facing action Commerce triggers *are* allowed, the approved template, is the whole reason the abandoned-cart recipe exists (`automationRecipes.js:108-117`). The server error text (`config/locales/en.yml` `automation.lynomia.no_customer_message`) repeats the same omission. |
| :62-68 | "The eleven" recipes | **W** | 12 rule recipes (`automationRecipes.js` ids at :109,119,135,152,169,186,211,231,250,264,289,322) + 1 setup recipe (`setupRecipes.js:52`). The prose list names ten and omits the shipped-label and abandoned-cart recipes. |
| :70-71 | recipe rules start off; hand-built rules are live on save | C | `automationRecipes.js:62` (`active: false`); schema default `active ... default: true` (`app/models/automation_rule.rb:7`). |
| :77-81 | worked example "Refund to returns" | P | It will run, but: **Description is also required** (`validations.js:80`; `ADD.FORM.DESC.ERROR`), and with no `message_type = incoming` condition the rule also fires on agent replies and private notes containing "refund" (the listener skips only automation, activity and auto-reply messages, `app/listeners/automation_rule_listener.rb:105-108`), re-assigning and re-prioritising on every agent message. The example teaches a trap. |
| :85-87 | administrators only; not a custom-role permission | C | `automation_rule_policy.rb:2-24`; `CustomRole::PERMISSIONS` (`custom/app/models/custom_role.rb:19-28`) has no automation entry. |
| :91 | "No time-based conditions of any kind" | P | The three named examples (business hours, time of day, day of week) hold. "Of any kind" does not: a date-typed custom attribute takes greater/less-than (`automationHelper.js:68`), and Commerce "last purchase" takes `days_before` (`audience/commerce_condition.rb:18`; `filter_service.rb:101-112`). Peer 036 reached the same point. |
| :92 | "No priority escalation. ... Nothing raises it as a conversation ages." | **W** when waiting rules are on | A wait rule (e.g. "No teammate has replied for 4 hours") may carry `change_priority`; actions are not restricted by a delay (`automation_rule.rb:41-43,122-136` restrict only conditions and event). Repeated in `automation-or-flow-builder.md:67-68`. |
| :93 | own actions do not trigger rules | C | `automation_rule_listener.rb:96-98,107`; `automation_rules/action_service.rb:6`. |
| :95 | "Add label" labels the conversation, never the contact | C | `action_service.rb:37-41`. |
| :97 | a failed action is not reported; the rest still run | C | `automation_rules/action_service.rb:13-17` (rescued, sent to the exception tracker only). |
| :98 | Commerce rules never wait; once per order change | C | `custom/automation_rule.rb:79`; `commerce_events.rb:66-68` (Redis claim, 7 days). |
| :99-101 | waiting rules: optional, off by default, 10 min to 30 days, status+inbox only on conversation events, editing discards armed waits | C | `config/features.yml:297-300` (`delayed_automations` `enabled: false`); `automation_rule.rb:25,131-136,47,140-149`. Not stated: who turns the flag on (an operator, not the admin), that the whole "run after a wait" control is hidden when it is off (`AutomationRuleForm.vue:89-91`), the three wait triggers' UI names ("Conversation stays in a status / Customer hasn't replied / No teammate has replied", `en/automation.json` `WAIT.OPTIONS`), and that a wait whose due time is more than 3 days past when the sweep reaches it (downtime) is dropped, not run (`automation_rule_pending_execution.rb:28`; `process_pending_execution_job.rb:24`). |
| :112-114 | label added by the rule itself never matches | C | by construction: conditions run before actions (`automation_rule_listener.rb:31-33`). |

### 3.2 `flow-builder.md`

| line | claim | v | evidence |
|---|---|---|---|
| :30-32 | non-WhatsApp-Cloud attach is "refused with 'Not supported on <inbox>'"; stray conversations go to the team | P | Runtime rule confirmed (`channel_capabilities.rb:19-22`; `runner.rb:136` hands over). The refusal happens **only at publish, only for inboxes already attached** (`graph_validator.rb:180-186`); attaching is unchecked (`app/models/agent_bot_inbox.rb:15-16`, `inboxes_controller.rb:69-77`) and the inbox "Bot configuration" picker lists every bot (`BotConfiguration.vue:98`). The real message also lists node types (`graph_validator.rb:184`). Peer 037 holds this as PD-27. The article's own step order (Publish, then attach) means a reader never sees the refusal. |
| :36-40 | entry: active bot, conversation pending, nobody assigned; Start keywords/conditions; else straight to team | C | `runner.rb:89-92,121-141`; `custom/app/listeners/custom/agent_bot_listener.rb:10-11`. Also required, unstated: contact not blocked and the flow switch on (`runner.rb:94-96`; `flows/switch.rb:13`), AI assignee empty or this bot (`runner.rb:91`). Keywords are a case-insensitive **substring** match (`nodes/start.rb:7-10`). |
| :44 | "the flow builder enabled for your account" | C | `config/features.yml:311-314` default off; `flows_controller.rb:80-82`. Who enables it is not said. |
| :47-58 | node table | C | All 21 types and 7 groups match `flows/node_types.rb:9-34` and `en/flowBuilder.json` `NODES`/`GROUPS`. |
| :60 | "Four of these wait for the customer: Question, Buttons, List and Delay" | **W** for Delay | Delay waits for **time**; customer messages during it are consumed and do nothing (`nodes/delay.rb:1-2,4`). Delay is a "waits" node only for the loop check (`node_types.rb:30`). |
| :62-65 | Question stores the answer (run/contact/conversation) and re-asks; Order lookup is own-customer, read-only | C | `nodes/question.rb:35-41`; `nodes/commerce_lookup.rb:1-12`. Retries default 3, max 5; reply types any/number/email/phone/keywords (`reply.rb:8`; `node_validator.rb` `invalid_attempts`). |
| :69-73 | steps; Test is non-destructive | C | `simulator.rb:1-9,29-37`. Test needs any WhatsApp Cloud inbox in the account (`simulator.rb:66-68`), which the article's prerequisites already imply. |
| :77-79 | eight templates | C | `flowTemplates.js` ids at :81,163,229,290,360,426,476,520. |
| :83-94 | what publishing refuses | C | `graph_validator.rb:108-186`. The optional-output list is partial (see 3.5). |
| :98-99 | administrators only | C | `flows_controller.rb:22`; `agent_bot_policy.rb:6-8`. |
| :106-108 | 3 buttons/20 chars, 10 list rows, 4,096 chars, 300 nodes/900 connections | P | Numbers confirmed (`channel_capabilities.rb:10-12`; `graph_validator.rb:15-16`). "4,096" is plain text only; button/list body is **1,024**, list row title 24, description 72 (`channel_capabilities.rb:11-12`). The 512 KB graph cap is unstated (`graph_validator.rb:17`). |
| :109-115 | handoff ends the flow; human reply ends it; one published version; disable before delete; 10 lookups/hour; 24 h window | C | `runner.rb:54-59`; `agent_bot_listener.rb:12-13`; `versions.rb:49-81`; `commerce_lookup.rb:41,104-109`; `send_message.rb:5`. |
| (absent) | runtime safety limits | **gap** | A session fails and hands over after 25 nodes between waits, 10 visits to one node, 200 nodes per session, or 5 messages between waits (`runner.rb:20-24`); user-facing reasons "Too many steps / Too many messages in a row / A node ran too many times" (`en/flowBuilder.json` `REASONS`). A looping FAQ menu or a 6-message welcome hits these; the article lists 300/900 but not these. |
| (absent) | Webhook node | **gap** | Plan-gated: publish is refused with "Webhooks are not available on this plan." (`node_validator.rb:119-120`); one-way and fire-and-forget, the response is never read (`nodes/webhook.rb:4-5,18`). |

### 3.3 `automation-or-flow-builder.md`

| line | claim | v | evidence |
|---|---|---|---|
| :22,:29,:47 | "one of twelve events", "seven order events" | **W** | 13 and 8, see 3.1. EN and AR. |
| :8-9 | both can "change its priority" | P | A flow has no priority node; priority exists only inside Human handoff (`nodes/handoff.rb:17`), which ends the flow. |
| :52 | only a rule can email a team or a transcript | C | `node_types.rb:9-34` has no email node. |
| :67-68 | neither can escalate priority over time | **W** with waiting rules | see 3.1 :92. |
| :87-94 | four-hour example; waiting rule "no teammate has replied for N" | C | UI name "No teammate has replied" (`en/automation.json` `WAIT.OPTIONS.AGENT_UNRESPONSIVE`); flag default off. |
| :111-112 | "A store event can only start a rule, and a rule cannot send a message to a customer on a Commerce trigger." | **W** as an absolute | An approved WhatsApp template can be sent from a Commerce-triggered rule (`custom/automation_rule.rb:10-17`, `custom/app/services/custom/automation_rules/action_service.rb:24-28`). |

### 3.4 `agent-bots.md`

| line | claim | v | evidence |
|---|---|---|---|
| :11-12 | "It can do anything your code can do, and nothing it cannot" | **W** | A bot token may call only an allow-list: conversations `show/toggle_status/toggle_typing_status/toggle_priority/create/update/custom_attributes`, messages `create`, assignments `create`, labels `index/create` (`access_token_auth_helper.rb:2-7`); everything else answers "not authorized for bots" (`:29-33`). |
| :35-40 | steps; token and secret shown once and re-readable | C | `en/agentBots.json` `SECRET.CREATED_DESC`; `app/views/api/v1/models/_agent_bot.json.jbuilder` (token/secret only to admins). |
| :44-53 | six events + widget; no conversation-created | C | `app/listeners/agent_bot_listener.rb:2-61`. |
| :46 | "message created: a message is added to a conversation the bot can see" | P | Incomplete in a way that bites: the gate is `webhook_sendable?` = incoming, outgoing **or template** with no private exclusion (`message_filter_helpers.rb:8-10`), so the bot receives **its own replies, agents' replies and private notes**. A handler that does not filter on `message_type` answers itself. (Peer article `integrations/webhooks.md` says private notes are "not sent"; the code says otherwise, see Handoffs.) |
| :60-63 | signature: HMAC-SHA256 over timestamp and raw body | P | Algorithm right (`webhooks/trigger.rb:54-61`). The header names (`X-Chatwoot-Signature`, `X-Chatwoot-Timestamp`, `X-Chatwoot-Delivery`), the `sha256=` prefix and the `<timestamp>.<body>` joiner are **not in this article**; they are in `en/integrations/webhooks.md:76-92`, which this article never links to. |
| :65-72 | worked example step 4: "it assigns a team, and your people pick the conversation up" | P | Team assignment only sets `team_id` (`assignments_controller.rb:36-43`); the conversation stays **pending**. Handoff is `toggle_status` to `open` on a pending conversation (`conversations_controller.rb:84-85,95-99` -> `bot_handoff!`). The step the reader needs is missing. |
| :82 | flow "Reaching your own systems: a webhook node, and order lookups" | P | The webhook node cannot read an answer back (`nodes/webhook.rb:4-5`). |
| :95-99 | Agent: "See the bots list: yes" | **W** in the UI | `AgentBotPolicy#index?` allows agents (`agent_bot_policy.rb:2-4`) but the Bots page route is `permissions: ['administrator']` (`agentBot.routes.js:11,22`); an agent cannot open it. |
| :106-107 | one bot per inbox; type fixed at creation | C | `inbox.rb:76-77`; `custom/app/models/custom/agent_bot.rb:21-23`. |
| :108 | 5-second timeout | C | `webhooks/trigger.rb:118-123` (installation-wide `WEBHOOK_TIMEOUT`, not per account). |
| :109-110 | 429/500 "retried up to three times" | **W** (off by one) | `retry_on ... attempts: 3` (`agent_bots/webhook_job.rb:3`) and ActiveJob counts the original run: "The number of attempts includes the original job execution" (`activejob-7.2.3.1/lib/active_job/exceptions.rb:33`). Three deliveries, two retries. Statuses `[429, 500]` only (`trigger.rb:3,125-127`), so 502/503/timeouts are never retried. |
| :111-113 | "If a message delivery keeps failing, the conversation moves from pending to open"; "unless your account is configured to keep it pending" | P | It moves on the **first** non-retryable failure (a single 5 s timeout, any 4xx, 502/503), not after repeated failure (`trigger.rb:26-37,65-84`), and only for `message_created`/`message_updated`. The setting exists (`account.rb:60`) but no UI control for it was found in `app/javascript`; an administrator cannot act on the sentence. |
| :114 | no queue, no delivery log | C | failure goes to `Rails.logger` only (`trigger.rb:36`). |
| :90-91,134 | flows are not on the Bots page | C | `agentBots/Index.vue:30-33`. They **do** appear in the inbox bot picker (`BotConfiguration.vue:98`), unmentioned. |

### 3.5 Does the section enumerate honestly?

| surface | real size | what the article does | verdict |
|---|---|---|---|
| rule triggers | 13 | names 12 in a two-row table, states the count | enumerated, **miscounted** |
| rule conditions | 18 standard keys (`automation_rule.rb:59-62`), contact + conversation custom attributes, audience, 8 Commerce fields + per-currency spend, 2 event fields, 10 operators | five sentences by category; zero operators; no per-trigger availability | **gestured at** |
| rule actions | server accepts 19 base + template; UI offers 18 base + template, plus `add_sla` when the `sla` feature is on, which the server rejects (peer PD-20) | grouped prose covering all 18 base UI actions; template missing; names differ from the UI labels | **gestured at, one missing** |
| rule recipes | 12 + 1 setup | "eleven"; ten named | miscounted |
| flow nodes | 21 | all 21 named in 8 groups matching the UI | **honest list, name only**: no settings, outputs or limits per node |
| node outputs | required vs optional per type (`node_types.rb:10-33`) | lists 4 optional kinds | partial: omits menu `timeout`, template `failed`, assign `failed`, lookup `unavailable` |
| flow variables | `{{ contact.* }}`, `{{ conversation.* }}`, `{{ inbox.name }}`, `{{ account.name }}`, `{{ flow.reply }}`, `{{ flow.<stored key> }}`, `{{ flow.order.* }}`; no Liquid tags (`flows/variables.rb:1-24`) | "for use later in message text" with no syntax | **absent** |
| flow templates | 8 | all 8 described | honest |
| bot events | 6 + widget | all listed | honest |
| bot API surface | 4 controllers / 12 actions | "anything" | **false by omission** |
| flow end reasons | ~23 (`en/flowBuilder.json` `REASONS`) | "each session shows where it ended and why" | not listed |

## 4. Missing articles

Questions a stuck user has, each of which the section cannot answer today.

| proposed article | user question | evidence it is needed |
|---|---|---|
| Automation rule reference (triggers, conditions per trigger, operators, actions) | "What can I put in a rule, and why is that field not in my dropdown?" | per-trigger field sets differ (`constants.js:8-690`); 10 operators; 20 actions; none listed |
| Waiting (delayed) rules | "Can a rule act after four hours, and how do I switch that on?" | feature spread over 3 paragraphs in 2 articles; flag is operator-controlled; a priority-escalation use case the section currently denies |
| Commerce triggers: why my order rule did not fire | "I changed an order in my store and nothing happened." | baseline read, read-driven dispatch, linked customer, latest conversation, per-platform statuses (incl. the Shopify correction), 13th trigger, template action |
| Send an approved WhatsApp template from a rule | "Message a customer about an order or abandoned cart outside 24 hours" | `send_whatsapp_template`; recipe `commerce_abandoned_cart_template`; held by Zid cart ingestion being pre-UAT |
| Flow builder node reference | "What does each node need, and which outputs must I wire?" | 21 nodes, limits in `node_validator.rb:10-12,127,161` (timeouts 1-1440 min, delay 1-86400 s, 10 conditions, 10 labels, 255-char handoff note) |
| Flow variables and stored answers | "How do I put the customer's answer or order number in a message?" | `flows/variables.rb`; no syntax in the corpus |
| Why did my flow hand over or fail? | "Sessions says 'A node ran too many times'." | `runner.rb:20-24`; ~23 reasons; also "Flows are switched off", blocked contact |
| Build a first flow, end to end | "Show me a department menu from scratch" | `flow-builder.md` is the only one of the four without a worked example |
| Agent bot developer reference | "What does my endpoint receive, what may it call, how do I hand off, how do I stop it answering itself?" | payload, 4-controller allow-list, `toggle_status` handoff, echo filtering, private URLs refused (SafeFetch) |
| How do I know my rule or flow ran? | "Did it fire?" | Analytics -> Automations / Flows pages exist (`Sidebar.vue:661-668`) and are mentioned nowhere in the corpus; instant rules leave **no** execution record (`custom/app/controllers/api/v1/accounts/analytics_controller.rb:44`); the only trace is the conversation's activity line attributed to "Automation System" (`en.yml` `automation.system_name`) |

### First rule, first flow, first bot: what the reader cannot find

*First rule.* That Description is mandatory, and at least one condition and one action; that `message created` fires on agent replies and notes; that "Add a Label" needs an existing label; that message text accepts Liquid personalisation (`Message` includes `Liquidable`, `app/models/message.rb:45`; not documented here; the variable set itself is **unverified** for rules); that instant rules leave no history; where the recipe gallery is (the "Start from a recipe" button, `en/recipes.json`).

*First flow.* The `{{ }}` syntax; Start keywords are substring matches; the Delay node is time not reply; every output's required/optional status; the runtime ceilings; that the Webhook node is plan-gated and one-way; that connecting an inbox happens **inside the builder** ("Connect a WhatsApp inbox", `FlowBuilder.vue:207`, `en/flowBuilder.json` `INBOXES.CONNECT`) while the article says "as you would any bot"; who enables the feature.

*First bot.* Everything between "save" and "reply": headers, payload shape, the endpoint, the `api_access_token` header (`access_token_auth_helper.rb:10`), what is callable, how to hand off, the echo problem, and that a staging URL on a private network will never be called.

### Contextual-help coverage for this section

| surface | link today |
|---|---|
| Settings -> Automation header | "Learn more" -> `automation-rules` (`Index.vue:429-431`; `featureHelper.js:10`) |
| Settings -> Bots header | "Learn more" -> `agent-bots` (`agentBots/Index.vue:112-114`) |
| Settings -> Flow Builder (list and canvas) | **none**: no `feature-name` is passed (`flows/Index.vue`, `FlowBuilder.vue`), although `FEATURE_DOC_KEYS.flows` exists (`featureHelper.js:18`) |
| `DOC_ARTICLES.automationOrFlows` | **no surface references it** |
| rule editor: wait selector, Commerce trigger note, recipe gallery | none |
| Bot webhook-secret dialog | none |

## 5. Quality

- **Structure.** All four share one skeleton (when to use, when not, what you need, steps, worked example, who can do this, limits, related, if it does not work). Predictable and task-oriented. Strongest asset: the **Limits** sections say what the product cannot do, which is rare and valuable. Weakest: they are prose paragraphs where a reference table is needed.
- **Worked examples.** Three of four have one. `flow-builder.md` has steps but no example flow. The rule example is flawed (3.1 :77-81).
- **Screenshots.** Zero images in all eight files. The section describes a canvas, a side panel and a recipe gallery in words only.
- **Length.** 955-1,103 EN words; dense but not padded. The reference material (conditions, nodes, payload) is what is missing, not narrative.
- **Front matter.** `title`, `description`, `position` (10/20/30/40), `tags`, `seo_description` present everywhere; `seo_title` absent everywhere (falls back to `title`, `content_seeder.rb:107-108`). Titles 10-27 chars; descriptions 89-144; `seo_description` 90-151: all inside the audit band. Tags are thin: `automation` only (plus `whatsapp` on flow-builder); no `commerce`, `webhooks`, `api`, `bots`.
- **Links.** 36 internal links per language (13 distinct targets), all 13 targets exist in EN and AR, and the sets are identical. All are bare slugs (`](flow-builder)`); see section 6 for the Arabic consequence. `agent-bots.md` does not link to `webhooks` (signature spec) or `connect-whatsapp`; `integrations/webhooks.md`'s "Other things that POST" table has no agent-bot row.
- **Maintenance debt.** The "no business hours / no priority escalation / twelve events" statements are repeated across three articles and four files per language; each correction must be made in 6 places.
- **Hygiene.** No internal `docs/...` paths leak into article bodies.

## 6. EN/AR parity

**Structure and facts: very high parity.** Same heading counts per file (11/13/9/12 for rules/flow/choice/bots), same tables, same 36 links, same numbers. This is good: it means **every error in section 3 is duplicated exactly in Arabic**, including "twelve", "seven", "three retries" and the Delay description. Meaning differences found are small: AR `automation-rules` limit 1 adds a sentence ("after-hours handling cannot be built as a rule", `ar/automation-rules.md:48-49`); AR `agent-bots` `seo_description` adds a clause about service failure that the EN does not; nothing contradicts.

**The real parity problem is Arabic UI vocabulary, not the Arabic articles.** The articles tell Arabic readers to click labels the Arabic product does not show:

| article says (AR) | Arabic product shows | evidence |
|---|---|---|
| «إنشاء أتمتة» (create automation) | `Create Automation`, untranslated | `ar/automation.json:7` |
| «إضافة روبوت» (add bot) | `Add Bot`, untranslated | `ar/agentBots.json:28` |
| event names «إنشاء رسالة», «حلّ محادثة», «فتح محادثة» | `Message Created`, `Conversation Resolved`, `Conversation Opened`, English | `ar/automation.json:183-185` |
| action names (assign, label, email, message, note, attachment, webhook) | mostly English (`Assign to Agent`, `Send a Message`, ...) | `ar/automation.json:195-212` |
| Commerce cart abandoned trigger | no Arabic key at all | `ar/automation.json` `EVENTS` lacks `COMMERCE_CART_ABANDONED` |
| flow nodes «إسناد إلى **وكيل دعم**», «تحويل إلى **وكيل دعم**» | «إسناد إلى **موظف**», «تحويل إلى **موظف**» | `ar/flowBuilder.json` `NODES.ASSIGN_AGENT`, `HANDOFF`; the corpus uses «وكيل دعم»/«وكلاء الدعم» ~115 times vs «موظف» ~12, so the choice is corpus-wide (agent 061) |

**Product defect surfaced:** the Arabic label for the **Resolve conversation** action is «إعادة فتح المحادثة» ("reopen conversation"), and the real Open action is «فتح المحادثة» (`ar/automation.json:205,212`). An Arabic administrator building a rule picks "reopen" and gets resolve. This is a translation file maintained through Crowdin (CLAUDE.md), so it is an owner decision, not a corpus fix, and no article text can compensate.

**Probable cross-corpus defect (agents 061/076, not verified in a browser):** Arabic articles link with bare slugs, e.g. `](flow-builder)`. An Arabic page lives at `/hc/lynomia-docs/articles/flow-builder-ar` (slug rule `content_seeder.rb:85-87`; route `config/routes.rb:519`), so a relative `flow-builder` resolves to `/hc/lynomia-docs/articles/flow-builder`, the **English** article, and the article lookup is by slug alone (`portals/articles_controller.rb:36`). No link rewriting exists in the renderers (`lib/*markdown_renderer*.rb`). If that holds, every one of the 36 in-text links in the four Arabic articles lands on English.

## Handoffs (for the orchestrator)

- **DC (corpus writer):** all "W"/"P" rows in section 3. `_ARBITRATION.md` DC-09 and DC-10 are confirmed; add: Shopify cancelled, Delay, "no priority escalation", retries off by one, Agent list-visibility, handoff step, 4-controller allow-list, template action on Commerce rules.
- **Product copy:** `en/recipes.json` `AUTOMATION.COMMERCE_ORDER_CANCELLED_FOLLOWUP.PROVIDER_NOTE` ("Shopify does not") is wrong against `shopify/normalizer.rb:66`. Owner: Commerce.
- **IR:** `docs/product-enablement/16-commerce-aware-starters.md:30` ("never fires for Shopify") contradicts `03-commerce-recipe-capability-matrix.md:299` and the code.
- **Cross-agent (058/092):** `en/integrations/webhooks.md` troubleshooting says private notes "are not sent as messages"; `MessageFilterHelpers#webhook_sendable?` (`message_filter_helpers.rb:8-10`) has no private exclusion and the payload carries `private` (`message.rb:193`). Needs one arbiter.
- **Not checked:** the Arabic flow-builder canvas strings beyond node names; the full variable set available to rule messages; Zid cart ingestion gate (peer 056/047); whether `Automation::Extensions` off-switch text reaches users; browser rendering of any page.
