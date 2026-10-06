# Starter library opportunity study

Scope: which starter recipes the platform can actually run **today**, at HEAD `6c381e96` on `claude/practical-thompson-9xfqed`.
Every claim carries a `path:line`. Where the verifier corrections contradict an inventory agent, the verifier is used.

---

## 1. The decision

**Build the starter library around the three engines that need no new primitive — Automation rules, Flow Builder, and Macros — and deliberately exclude every commerce-event-driven and every time-driven recipe from v1.**

Three facts drive this:

1. **There is no clock.** No business-hours, time-of-day or scheduled trigger exists anywhere in the rule engine. The only time mechanism is `execution_delay` on an *existing event* (`app/models/automation_rule.rb:25`, range 10 min–30 days), and for conversation-level events it may only be combined with `status` and `inbox_id` conditions (`app/models/automation_rule.rb:28`, enforced at `:119-126`). That kills every out-of-hours recipe and every "every morning" recipe, but it fully supports *follow-up-after-N* recipes, which is where the volume actually is.
2. **Commerce events are read-driven, not webhook-driven.** `Automation::CommerceEvents.dispatch` has exactly one call site (`custom/app/models/commerce/contact_metric.rb:27`), reached only from `Commerce::ContactMetric.record`, which has exactly two callers: `custom/app/services/commerce/conversation_panel.rb:62` and `custom/app/services/commerce/realtime.rb:93`. A provider webhook only invalidates cache; the event fires when something **re-reads** the order. No commerce recipe can promise "the moment X happens".
3. **The default installation has one commerce provider, and it is the weakest one.** `SALLA_ENABLED`, `ZID_ENABLED` and `SHOPIFY_COMMERCE_ENABLED` all ship `value: false` (`config/installation_config.yml:488-490`, `:515-517`, `:535-537`); WooCommerce has no switch so it inherits `enabled? = true` (`custom/app/services/commerce/providers/base.rb:6`). WooCommerce can never report `shipped` or `delivered` (no `STATUSES` entry produces them and `shipments: []` is hardcoded, `custom/app/services/commerce/providers/woocommerce/normalizer.rb:17-20,35`) and has no cart code at all. So on a default install, "order shipped" and "order delivered" recipes are dead on arrival.

Consequence for the roadmap: **the highest-value, lowest-risk unlock in the whole library is a macro starter pack** (returns, cancellation, refund request, escalation). Macros are agent-invoked, so they have no trigger dependency — they sidestep all three facts above — and they are the only recipe surface an agent rather than an administrator can reach (`app/policies/macro_policy.rb` `create?` is `true` for any agent; flow and automation galleries are admin-only, `flows.routes.js:9-12`, `automation.routes.js:23-25`). The recipe architecture cannot express a macro starter today, and that is a small, contained EXTEND.

---

## 2. The capability floor

| Engine | Size | Entry condition | Classification |
|---|---|---|---|
| Automation rules | 12 triggers, 18 OSS + 1 EE + 12 Lynomia conditions, **20 actions** | any of 12 events; `automations` feature (`config/features.yml:71-73`, default on) | REUSE |
| Delayed automation | `execution_delay` 10 min–30 days; 3 UI wait presets | an event must still fire first | REUSE |
| Flow Builder | **21 node types** | incoming customer message, **WhatsApp Cloud inbox only**, conversation `pending`, no assignee | REUSE |
| Macros | **16 server-valid actions** (15 offered in the builder) | agent clicks it | REUSE |
| Commerce reads (`commerce_lookup`, audience conditions) | Customer 360 over linked store customers | `lynomia_commerce` feature (`config/features.yml:282-285`, default off) + an active store | REUSE |
| Commerce writes / recovery | 7 action types, 4 providers | **hard-off in production** | DO NOT CREATE |

Triggers (12): `conversation_created`, `conversation_updated`, `conversation_opened`, `conversation_resolved`, `message_created` (`app/listeners/automation_rule_listener.rb:2,6,10,14,18`) plus the seven `commerce_order_{created,updated,paid,shipped,delivered,cancelled,refunded}` generated over `Commerce::OrderTransitions::EVENTS` (`custom/app/listeners/custom/automation_rule_listener.rb:5-7`, `custom/app/services/commerce/order_transitions.rb:22-29`).

Actions (20): 19 in `app/models/automation_rule.rb:54-59` plus `add_sla` from `enterprise/app/models/enterprise/automation_rule.rb:6-8`. `send_message` and `send_attachment` are **withheld on every commerce trigger**, server-side (`custom/app/models/custom/automation_rule.rb:9,38-39`) and client-side (`lynomiaAutomation.js:24,173-174`). The per-event `actions:` arrays in `constants.js:90,232,378,518,648` are dead data — the dropdown is built from the flat `AUTOMATION_ACTION_TYPES`, so every action is offered on every non-commerce trigger.

Nodes (21): `custom/app/services/flows/node_types.rb:9-34`. `Flows::ChannelCapabilities.for` returns a table only for `Channel::Whatsapp` with `provider == 'whatsapp_cloud'` (`custom/app/services/flows/channel_capabilities.rb:19-22`); anything else is `unsupported_channel` at `custom/app/services/flows/runner.rb:136`.

Macro actions (16): `app/models/macro.rb:33-35`. The builder offers 15 — `change_status` is API-only (`app/javascript/dashboard/routes/dashboard/settings/macros/constants.js:1-77`).

Recipe architecture: 22 recipes in three client-side catalogues, one scalar `type`, one `build(values)` returning **one** payload, dialog emits **one** `create` (`app/javascript/dashboard/recipes/index.js:9-23`). No server-side catalogue of any kind. Inputs vocabulary has no inbox, agent, free-text, boolean or template control (`app/javascript/dashboard/components-next/recipes/RecipeInputs.vue:127-135` falls everything unknown through to a URL field).

### The five blockers applied throughout

| Blocker | Proof | Kills |
|---|---|---|
| No time-of-day / business-hours condition | zero hits for `business_hour\|working_hour\|time_of_day\|out_of_office` across `app/models/automation_rule.rb`, `lib/filters/filter_keys.yml`, `custom/app/services/automation/`, `app/services/automation_rules/` (re-verified here) | every out-of-hours recipe |
| No `contact_created` / `contact_updated` / audience-membership trigger | the two automation listeners define only the 12 methods above; `WebhookListener`/`HookListener` have contact handlers, the automation listener does not | every contact-lifecycle recipe |
| No abandoned-cart trigger, no cart persistence | zero `cart` lines in `db/schema.rb`; a cart is a `Data.define` cached in Redis only (`custom/app/services/commerce/abandoned_cart.rb:12-15`, `custom/app/services/commerce/cache.rb:8-9`, FRESH 120s / KEEP 24h); cache is **deleted, not staled**, on every webhook (`custom/app/services/commerce/realtime.rb:54-57`) | every abandoned-cart recipe |
| Commerce triggers are read-driven | `custom/app/models/commerce/contact_metric.rb:27` ← `conversation_panel.rb:62` / `realtime.rb:93` | every "notify the moment X happens" recipe |
| Commerce actions + recovery hard-off | `PRE_UAT = { actions: %w[salla zid shopify], recovery: %w[salla zid shopify] }` (`custom/app/services/commerce/switches.rb:16`); `RECOVERY_KEYS` has no `woocommerce` key so `provider_recovery_enabled?('woocommerce')` is unconditionally false (`:15,29-31`) | every automated refund/cancel and all recovery |

One more thing a product owner must know before shipping any catalogue: **`event_name` is not validated.** `app/models/automation_rule.rb` has no inclusion validation on it (only the DB `NOT NULL`, `db/schema.rb:313`) and the controller merely permits it (`app/controllers/api/v1/accounts/automation_rules_controller.rb:62`). A recipe that ships a typo'd or aspirational event name **saves successfully and silently never fires**. That is the single most dangerous failure mode for a starter library. → **PATCH**.

---

## 3. HIGH confidence — build these first

### H1 — First-response routing by inbox and keyword
- **Target user**: support lead setting up a new account. **Problem**: everything lands in one unassigned pile; nobody owns the first touch.
- **Systems used**: Automation rules. **Classification: REUSE.**
- **Requirements**: `automations` feature (default on). **Provider requirements**: none.
- **Triggers**: `conversation_created`. **Conditions**: `inbox_id`, `content` (contains), `country_code`, `conversation_language` (`app/models/automation_rule.rb:49-52`).
- **Actions**: `assign_team`, `add_label`, `change_priority` (`app/services/action_service.rb:64-74,37-41,33-35`).
- **Account resources required**: ≥1 team, ≥1 label. **Supported providers**: channel-agnostic.
- **Risks**: `content` is matched against `messages.processed_message_content` lower-cased on both sides (`conditions_filter_service.rb:115,123`) — keyword lists must be lower-case and unaccented. Conversations with `additional_attributes['auto_reply']` are skipped (`automation_rule_listener.rb:100-103`).
- **Confidence: HIGH.**

### H2 — VIP audience priority and context note
- **Target user**: support lead with a known VIP list. **Problem**: VIP messages queue behind everyone else.
- **Systems used**: Automation rules + shared contact audiences. **Classification: REUSE** — it already ships as `vip_audience_priority` (`app/javascript/dashboard/recipes/automationRecipes.js:140`).
- **Requirements**: `automations`; `Automation::Extensions.enabled?` (`custom/app/services/automation/extensions.rb:8-9`); ≥1 **shared** contact audience. **Provider requirements**: none.
- **Triggers**: `conversation_created`. **Conditions**: `contact_audience` `equal_to` (`custom/app/services/automation/lynomia_condition.rb:17,22`).
- **Actions**: `change_priority`, `assign_team`, `add_private_note`.
- **Account resources required**: a shared contact custom filter, a team.
- **Risks**: membership is evaluated in Ruby per event — `audience.members.exists?(id: contact_id)` (`lynomia_condition.rb:119`), so a very large audience costs a query per conversation. A personal (unshared) filter fails validation with `audience_not_shared`. The Lynomia kill switch `LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED` is **not** a registered installation config, so it cannot be seen or flipped from Super Admin — if it is off, the save fails with an error the builder does not predict.
- **Confidence: HIGH.**

### H3 — WhatsApp welcome menu → department routing
- **Target user**: SMB owner on WhatsApp. **Problem**: every conversation starts with "how can I help?" typed by a human.
- **Systems used**: Flow Builder. **Classification: REUSE** — ships as `whatsapp_welcome_menu` and `support_department_routing` (`app/javascript/dashboard/recipes/flowTemplates.js:373,220`).
- **Requirements**: `lynomia_flow_builder` feature (`config/features.yml:286-289`, **default off**); `Flows::Switch.available?`; administrator (flow routes are `permissions: ['administrator']`).
- **Provider requirements**: n/a for commerce. **Channel requirement is the real gate**: WhatsApp Cloud only.
- **Triggers**: incoming customer message matching the `start` node's keywords/conditions (`custom/app/services/flows/runner.rb:138-140`). **Conditions**: `start` node keywords; optionally a `condition` node over the standard automation keys.
- **Nodes**: `start` → `send_message` → `buttons` (max 3, title ≤20) or `list` (max 10) → `assign_team` → `handoff`.
- **Account resources required**: a WhatsApp Cloud inbox, teams, a published flow version, an `AgentBotInbox` row.
- **Supported providers**: WhatsApp Cloud (`whatsapp_cloud`). 360dialog/on-prem is accepted by the builder's inbox picker (`FlowBuilder.vue:102-107` filters on `channel_type` only, never `provider`) but then fails at runtime with `unsupported_channel` — a trap the recipe cannot protect against.
- **Risks**: the flow only acts while the conversation is `pending` with no assignee (`runner.rb:89-92`); the listener fires `stop` the moment anyone is assigned. Pressing Test on a published flow creates a new draft row and the UI then falsely shows "Unpublished changes" (`custom/app/controllers/api/v1/accounts/flows_controller.rb:75` → `versions.rb:33-34`).
- **Confidence: HIGH.**

### H4 — Self-service order status by order number
- **Target user**: ecommerce merchant drowning in "where is my order". **Problem**: agents re-type the same lookup 50 times a day.
- **Systems used**: Flow Builder + commerce reads. **Classification: REUSE** — ships as `commerce_order_tracking` (`app/javascript/dashboard/recipes/flowTemplates.js:74`).
- **Requirements**: `lynomia_flow_builder` + `lynomia_commerce` (both default off); a store with status `active`/`needs_reauth`.
- **Provider requirements**: the provider must implement order search. WooCommerce, Zid and Shopify do; **Salla does not** (`searches_orders?` is not overridden, so `custom/app/services/commerce/providers/base.rb:30` keeps it `false`).
- **Triggers**: incoming message. **Conditions**: `start` keywords (e.g. "order", "طلب").
- **Nodes**: `question` (`reply_type: number`) → `commerce_lookup` (`mode: order_number`) → `send_message` with `{{flow.order.number}} {{flow.order.status}} {{flow.order.payment_status}}` → `handoff` on `not_found`/`unavailable`.
- **Account resources required**: WhatsApp Cloud inbox, connected store, published flow.
- **Supported providers**: WooCommerce ✅ status/payment only · Zid ✅ · Shopify ✅ · Salla ❌.
- **Risks**: `commerce_lookup` reads only the contact's own linked store customers, and linking is created on a single verified-phone match inside the panel read path (`custom/app/services/commerce/customer_matcher.rb:63`, reached from `conversation_panel.rb:23`) — a customer the provider cannot resolve by their WhatsApp number falls to `not_found`. 10 lookups/hour/conversation. WooCommerce finds an order only if its *displayed* number equals the quoted number, so a renumbering plugin breaks it. Test Mode always short-circuits to `not_found` (`custom/app/services/flows/nodes/commerce_lookup.rb:19`), so the happy path cannot be demonstrated in the simulator.
- **Confidence: HIGH** (for status; see M2 for tracking).

### H5 — Lead qualification and customer information collection
- **Target user**: sales/ops lead. **Problem**: agents chase the same three details on every new enquiry.
- **Systems used**: Flow Builder + contact custom attributes. **Classification: REUSE.**
- **Requirements**: `lynomia_flow_builder`; contact custom attribute definitions must already exist. **Provider requirements**: none.
- **Triggers**: incoming message / start keywords. **Conditions**: optional `condition` node.
- **Nodes**: `question` ×N with `store_as: {scope: 'contact', key: '<attr>'}` (`custom/app/services/flows/nodes/question.rb:36-47`) → `set_contact_attribute` → `buttons` for a closed choice → `assign_team` → `handoff`.
- **Account resources required**: WhatsApp Cloud inbox, `CustomAttributeDefinition` rows with `attribute_model: contact_attribute`, a team.
- **Supported providers**: WhatsApp Cloud only. **Risks**: a missing attribute definition **fails the session** (`attribute_missing`) rather than skipping — the recipe must create nothing it cannot verify, and the inputs vocabulary has no custom-attribute picker, so the key is hand-typed. Reply parsing is fixed to `any/number/email/phone/keywords` (`custom/app/services/flows/reply.rb:3-31`); no tenant regex.
- **Confidence: HIGH.**

### H6 — Customer-unresponsive follow-up nudge
- **Target user**: support lead. **Problem**: conversations stall silently after the agent's last reply.
- **Systems used**: Delayed automation. **Classification: REUSE.**
- **Requirements**: `automations`. **Provider requirements**: none.
- **Triggers**: `message_created` behind the `customer_unresponsive` wait preset (`constants.js:818-830`, which writes `message_type outgoing` + `private_note false`).
- **Conditions**: `message_type`, `private_note`, `inbox_id`. **Actions**: `send_message`, or `add_private_note` + `assign_agent` for an internal-only nudge.
- **Account resources required**: none beyond an inbox. **Supported providers**: channel-agnostic, but a WhatsApp follow-up past 24h will be refused by the channel — the rule has no way to know.
- **Risks**: `message_created` carries **no** `changed_attributes` (`app/models/message.rb:380` vs the listener read at `app/listeners/automation_rule_listener.rb:24`), so `attribute_changed` must never appear in this recipe. Delay range is 10 min–30 days. Immediate rules have no idempotency key, so a Sidekiq retry re-runs them.
- **Confidence: HIGH.**

### H7 — Auto-close stale pending conversations
- **Target user**: store operations manager. **Problem**: the pending queue is a graveyard and the real backlog is invisible.
- **Systems used**: Delayed automation. **Classification: REUSE.**
- **Requirements**: `automations`. **Provider requirements**: none.
- **Triggers**: `conversation_updated` behind the `conversation_status` wait preset. **Conditions**: `status`, `inbox_id` **only** — `execution_delay_supported_event` rejects anything else for conversation-level events (`app/models/automation_rule.rb:119-126`).
- **Actions**: `resolve_conversation` + `add_label` + `add_private_note`.
- **Account resources required**: a label. **Supported providers**: channel-agnostic.
- **Risks**: `resolve_conversation` from automation has **no** required-attributes gate — only the macro path does (`enterprise/app/services/enterprise/macros/execution_service.rb:3,9`), so on an account using `conversation_required_attributes` this recipe resolves conversations the UI would have blocked. Editing the rule discards already-armed pending executions (`app/models/automation_rule.rb:45`).
- **Confidence: HIGH.**

### H8 — Returns / cancellation / refund-request macro pack ⭐ highest-value unlock
- **Target user**: frontline agent. **Problem**: after-sales handling is six manual steps and every agent does them differently.
- **Systems used**: Macros. **Classification: EXTEND** — the engine is REUSE, but the recipe architecture cannot express a macro starter: `type` is a scalar, `build` returns one payload, the dialog emits one `create` (`app/javascript/dashboard/recipes/index.js:9-23`), and there is no owning page wiring on Settings → Macros. The extension is: one new `type`, one catalogue file, one `RecipeDialog` mount on the macros index.
- **Requirements**: `macros` feature (`config/features.yml:50-52`, default on). **Provider requirements**: none — and that is the point: **no trigger, no clock, no provider.**
- **Triggers**: agent invocation (`POST /macros/:id/execute`, `app/controllers/api/v1/accounts/macros_controller.rb`). **Conditions**: none — macros have no conditions column (`db/schema.rb:1389`).
- **Actions**: from the 16 in `app/models/macro.rb:33-35` — `add_label`, `change_priority`, `assign_team`, `add_private_note`, `send_message`, `send_email_transcript`, `snooze_conversation`, `resolve_conversation`.
- **Account resources required**: labels, teams. **Supported providers**: channel-agnostic (`send_message`/`add_private_note` are skipped on tweet conversations, `action_service.rb:115-119`).
- **Risks**: execution is fire-and-forget — `execute` returns 200 immediately and per-action failures are swallowed into Sentry (`app/services/macros/execution_service.rb:10-21`), so a half-applied macro is invisible to the agent. An agent-created macro is forced to `personal` visibility (`app/models/macro.rb:37-46`), so shipping a *global* pack needs an administrator. `change_status` must not be used: it is server-valid but absent from `MACRO_ACTION_TYPES`.
- **Confidence: HIGH.**

### H9 — Conversation-event webhook bridge
- **Target user**: ops/integration engineer. **Problem**: the ERP/helpdesk never learns that a conversation was resolved or escalated.
- **Systems used**: Automation rules. **Classification: REUSE.**
- **Requirements**: `api_and_webhooks` account feature (checked by the recipe requirement `webhooks`, `app/javascript/dashboard/recipes/useRecipeContext.js:40-57`). **Provider requirements**: none.
- **Triggers**: any of the five conversation/message events. **Conditions**: any OSS key.
- **Actions**: `send_webhook_event` → `WebhookJob.perform_later(url, conversation.webhook_data.merge(event: "automation_event.<event_name>"))` (`app/services/automation_rules/action_service.rb:38-41`).
- **Account resources required**: a reachable HTTPS endpoint. **Supported providers**: n/a.
- **Risks, and this is a decision point**: **automation webhooks are unsigned** — no secret or signature is passed. The Flow Builder's `webhook` node *is* signed (`X-Chatwoot-Signature`, HMAC over `<ts>.<body>`, `lib/webhooks/trigger.rb:54-63`). If the recipe's audience cares about authenticity, ship it as a flow node, not a rule. `conversation.webhook_data` carries contact PII off the install. Rule chaining is impossible by construction (`performed_by_automation?`, `app/listeners/automation_rule_listener.rb:96-98`), so the receiving system cannot write back into another rule.
- **Confidence: HIGH.**

### H10 — Human handoff with context
- **Target user**: agent receiving a bot conversation. **Problem**: the bot hands over with no summary and no priority.
- **Systems used**: Flow Builder (`handoff` node) or Automation. **Classification: REUSE.**
- **Requirements**: `lynomia_flow_builder` for the node form. **Provider requirements**: none.
- **Triggers**: reached as a terminal node, or `conversation_created` for the rule form. **Conditions**: optional.
- **Nodes/Actions**: `handoff` with `team_id`, `agent_id`, `priority`, `labels`, `reason` (`custom/app/services/flows/nodes/handoff.rb:5-24`) — it runs `assign_team`/`assign_agent`/`change_priority`/`add_label` through the shared `ActionService` and posts `reason` as a private note (truncated to 255), then `finish(:handed_off)`.
- **Account resources required**: team and/or agent, labels. **Supported providers**: WhatsApp Cloud for the node form; channel-agnostic for the rule form.
- **Risks**: `assign_agent` silently does nothing if the agent is neither an inbox member nor an account administrator (`app/services/action_service.rb:104-109`); the node then takes its `failed` output only if that output is wired. The `reason` strings in the existing starter copy are English-only (`app/javascript/dashboard/recipes/starterCopy.js`).
- **Confidence: HIGH.**

---

## 4. MEDIUM confidence

### M1 — High-value spend routing
- **Target user**: ecommerce merchant. **Problem**: big spenders get the same queue as everyone else.
- **Systems/Classification**: Automation + commerce audience conditions. **REUSE** — ships as `high_value_spend_routing` (`automationRecipes.js:165`).
- **Requirements**: `lynomia_commerce`, `Automation::Extensions.enabled?`, ≥1 store, ≥1 seen currency. **Provider requirements**: the provider must be able to report `payment_status == 'paid'`, because `Customer360.spend` selects only paid orders (`custom/app/services/commerce/customer360.rb:22-27`). **Salla can never report `paid`** (`custom/app/services/commerce/providers/salla/normalizer.rb:137-139`), so Salla spend is always empty.
- **Triggers**: `conversation_created`. **Conditions**: `commerce_spend_<ccy>` `is_greater_than` (`custom/app/services/audience/commerce_condition.rb:24-25`).
- **Actions**: `change_priority`, `assign_team`, `add_private_note`. **Account resources**: store, team.
- **Supported providers**: WooCommerce (partial — `paid` requires status `processing|completed` **and** `date_paid_gmt`, so COD and bank-transfer orders read `unknown`), Zid ✅, Shopify ✅, Salla ❌.
- **Risks**: spend lives in `commerce_contact_metrics`, written only by `ContactMetric.record` — i.e. only after someone read that customer's orders. A brand-new contact has **no** metrics, so the rule evaluates false on their very first conversation, which is exactly when it matters. Currency is never converted. Numbers render as a plain text input in the automation builder because `AUTOMATION_INPUT_TYPES` has no `number` entry.
- **Confidence: MEDIUM** — correct when warm, wrong when cold.

### M2 — Shipment tracking self-service
- **Systems/Classification**: Flow Builder + `commerce_lookup`. **REUSE.** **Target user**: ecommerce merchant. **Problem**: "where is my parcel" with a courier link.
- **Requirements**: as H4. **Provider requirements**: the provider must expose tracking. WooCommerce hardcodes `tracking: nil, shipments: []` (`woocommerce/normalizer.rb:14-15,35`), so `{{flow.order.tracking_number}}` is **always empty** on the one provider that is on by default.
- **Triggers/Conditions/Nodes**: as H4, plus a `condition` node on whether tracking is present and a `send_message` with `{{flow.order.tracking_url}}`.
- **Supported providers**: Zid ✅ (one shipment/order, status derived from the order code), Shopify ✅ (bounded to 10 fulfillments × 5 tracking numbers), Salla ✅ (real shipment records), **WooCommerce ❌**.
- **Risks**: all three supporting providers are **off by default**. Shopify tracking-only changes may emit no webhook at all, so freshness depends on the 120 s cache or an agent refresh.
- **Confidence: MEDIUM** — correct code, wrong default configuration.

### M3 — Refund-event internal escalation
- **Systems/Classification**: Automation on a commerce trigger. **REUSE** — ships as `commerce_refund_escalation` (`automationRecipes.js:106`).
- **Target user**: after-sales lead. **Problem**: refunds are discovered late.
- **Requirements**: `lynomia_commerce`, extensions switch. **Provider requirements**: `commerce_order_refunded` fires from status `refunded` or a refund total, so WooCommerce ✅ and Shopify ✅ (both partial and full), Zid partial (payment_status only; order status `reversed` maps to `other`), Salla partial (only the `restored` slug; partial refunds are unrepresentable).
- **Triggers**: `commerce_order_refunded`. **Conditions**: `commerce_event_store`, `commerce_event_provider` (valid on commerce triggers only, `custom/app/models/custom/automation_rule.rb:22-31`).
- **Actions**: `change_priority`, `assign_team`, `add_private_note`, `send_webhook_event`. **Never** `send_message`/`send_attachment` — rejected at save.
- **Account resources**: store, team. **Risks**: read-driven. The rule fires when an agent opens the commerce panel or a refresh re-reads the order — **not** when the refund happens. Say this in the recipe description, not in a footnote. Also: `execution_delay` is forbidden on commerce triggers (`custom/app/models/custom/automation_rule.rb:36`).
- **Confidence: MEDIUM.**

### M4 — New paid order internal alert and label
- **Systems/Classification**: Automation on `commerce_order_paid`. **REUSE** (close cousin of `commerce_new_order_routing`, `automationRecipes.js:74`).
- **Requirements/Providers**: `lynomia_commerce`; WooCommerce ⚠ (derived, see M1), Zid ✅ (explicit field), Shopify ✅, **Salla ❌ — `paid` is unreachable**.
- **Triggers**: `commerce_order_paid`. **Conditions**: `commerce_event_store`/`commerce_event_provider`. **Actions**: `add_label`, `change_priority`, `assign_team`, `add_private_note`, `send_webhook_event`.
- **Risks**: read-driven; a link's **first** read is a silent baseline that emits nothing (`custom/app/services/commerce/order_transitions.rb:39`), so the first order of a newly linked customer never produces an event. WooCommerce stores whose API key is read-only get **no webhooks at all** and therefore no refresh (`custom/app/services/commerce/providers/woocommerce.rb:101-106`).
- **Confidence: MEDIUM.**

### M5 — Bilingual welcome and language routing
- **Systems/Classification**: Flow Builder. **REUSE** — ships as `bilingual_welcome` (`flowTemplates.js:329`).
- **Requirements**: `lynomia_flow_builder`, WhatsApp Cloud. **Triggers**: incoming message. **Nodes**: `send_message` → `buttons` (ar/en) → `set_conversation_attribute` → `assign_team`.
- **Account resources**: WhatsApp Cloud inbox, teams, optionally a `conversation_attribute` definition.
- **Risks**: language is *chosen*, never detected — there is no language-detection node and `conversation_language` is only populated upstream. Button titles must fit 20 chars, which is why `starterCopy.title` carries a separate short bilingual string.
- **Confidence: MEDIUM.**

### M6 — FAQ menu
- **Systems/Classification**: Flow Builder. **REUSE.** **Target user**: SMB with five recurring questions.
- **Nodes**: `start` → `send_message` → `list` (≤10 rows) → `send_message` per branch → `goto` back to the menu → `handoff` on `other`.
- **Risks that cap confidence**: every answer is **literal copy baked into the published graph** — there is no knowledge-base, Captain or AI node anywhere in the 21-type registry, and no canned-response node. Editing an FAQ answer means editing and republishing the flow. Unmatched replies re-show the menu at most twice (`Flows::Nodes::Choice::MAX_REPEATS = 2`) then hand off. A flow created from a template is created **unpublished and connected to no inbox**, so the merchant must still publish and connect it.
- **Confidence: MEDIUM.**

### M7 — One-off WhatsApp campaign to a shared audience
- **Systems/Classification**: Campaigns + shared audiences. **REUSE.** **Target user**: marketing/ops. **Problem**: no way to reach a segment proactively.
- **Requirements**: a WhatsApp inbox — campaigns accept only `Website`, `Twilio SMS`, `Sms`, `Whatsapp` (`app/models/campaign.rb:125`), and a WhatsApp campaign is forced to `one_off` with a `scheduled_at` (`:129-139`).
- **Triggers**: the schedule. **Conditions**: audience entries `{type: 'Audience'|'Label', id:}`, shared contact filters of the same account only (`custom/app/models/custom/campaign_audience.rb:12-30`).
- **Account resources**: WhatsApp inbox, a shared contact audience or labels.
- **Risks**: **membership is not static.** `audience` is a jsonb list of *references*; recipients are re-resolved at send time from each audience's saved filter. There is no `audiences`/`audience_members` table (108 tables in `db/schema.rb`, none of them), and `campaign_recipients` is a send **log** written during the send, not a membership list. So a merchant who builds a list, then edits the filter, sends to a different set than they reviewed. "Contact id in (a set)" is not expressible as a contact filter. Separately, "Select all N in this view" is unreachable on a search view because `@contacts_count = results.size` caps `totalItems` at the page size (`app/controllers/api/v1/accounts/contacts_controller.rb:183`) — so building the list by bulk-labelling a search result is currently broken.
- **Confidence: MEDIUM.**

### M8 — Contact classification by custom attribute
- **Systems/Classification**: Flow Builder. **REUSE.** **Target user**: ops lead wanting segmentable contact data.
- **Nodes**: `question` with `store_as.scope: 'contact'`, or `set_contact_attribute` (`custom/app/services/flows/nodes/set_contact_attribute.rb`).
- **Risks**: this is the **only** automated write to contact-level data in the platform. Labels are not an option: `add_label` in both Automation and Flow runs `ActionService#add_label` → `@conversation.reload.add_labels` (`app/services/action_service.rb:37-41`, `custom/app/services/flows/nodes/add_label.rb:6`) — **conversation** labels, never contact labels. WhatsApp Cloud only, bot phase only.
- **Confidence: MEDIUM.**

---

## 5. LOW confidence

| # | Candidate | Systems / Class | Why only LOW |
|---|---|---|---|
| L1 | After-sales follow-up flow (ships as `commerce_after_sales`, `flowTemplates.js:155`) | Flow Builder + `commerce_lookup` · **REUSE** | Stacks every H4/M2 limitation: needs `lynomia_commerce` + `lynomia_flow_builder` (both default off), a linked customer, and tracking data that WooCommerce never provides. Target user: ecommerce merchant; providers: Zid/Shopify/Salla, not WooCommerce. |
| L2 | Active-order routing (ships as `active_order_routing`, `automationRecipes.js:198`) | Automation + `commerce_active_order` · **REUSE** | The condition reads `commerce_contact_metrics`, so it is false for any contact nobody has read yet (same cold-start as M1), and `commerce_orders_count` `equal_to`/`is_less_than` use `complete()` — an unread link makes the contact **not match** (`custom/app/services/audience/commerce_condition.rb:100-107`). |
| L3 | Commerce-event webhook to an external system (ships as `commerce_event_webhook`, `automationRecipes.js:123`) | Automation · **REUSE** | Read-driven timing plus an unsigned delivery. The one genuine upside: the custom overlay enriches the payload with `commerce: {event, store_id, provider, order}` when `Automation::CommerceEvents.current` is set (`custom/app/services/custom/automation_rules/action_service.rb:7-14`) — so the receiver gets real order context. Still not a reliable event feed. |
| L4 | SLA escalation on first response | Automation `add_sla` (EE) · **REUSE** | Requires the `sla` account feature at execution time and in the UI (`AutomationRuleForm.vue:221-223`); no-ops if the conversation already has an SLA. There is no applicability-rule engine — `add_sla` and a direct PATCH are the only two writers of `sla_policy_id`, and there are **no escalation levels** anywhere (`enterprise/lib/captain/tools/handoff_tool.rb:120-131` lists L1→L2→L3 as a future enhancement). |

---

## 6. REJECTED — do not put these in the catalogue

| Candidate | Domain | Blocking fact | Class |
|---|---|---|---|
| Out-of-hours auto-reply recipe | out-of-hours | **No time-of-day or business-hours condition exists.** The capability lives only as a per-inbox setting: `out_of_office?` (`app/models/concerns/out_of_offisable.rb:22-24`) → `MessageTemplates::Template::OutOfOffice` (`app/services/message_templates/hook_execution_service.rb:17,32`). Point merchants at the inbox setting. | DO NOT CREATE |
| Out-of-hours routing to an on-call team | out-of-hours, routing | Same. `SlaPolicy#only_during_business_hours` affects SLA clock accounting, not routing. | DO NOT CREATE |
| "Welcome a newly created contact" | customer information collection | **No `contact_created` trigger.** The automation listeners define only the 12 events; contact handlers exist on `WebhookListener`/`HookListener` only. | NEW PRIMITIVE REQUIRED |
| "React when a contact enters/leaves an audience" | contact classification, VIP | No `entered_audience`/`left_audience`/membership listener anywhere; `docs/audience/06-automation-integration-contract.md` §4 proposes it and it is unimplemented. | NEW PRIMITIVE REQUIRED |
| Abandoned-cart recovery automation | abandoned cart | **No cart table** (zero `cart` lines in `db/schema.rb`), cart is a Redis-cached `Data.define`, cache **deleted** not staled on webhooks, no cart transition engine, no trigger, no cart condition, no cart node. Independently re-verified. | DO NOT CREATE (today) |
| Abandoned-cart recovery message send | abandoned cart | Even with a trigger: recovery is **agent-prepared only** by design, and `PRE_UAT` recovery holds salla/zid/shopify while WooCommerce has no `RECOVERY_KEYS` entry (`custom/app/services/commerce/switches.rb:15-16,29-31`). | DO NOT CREATE |
| "Message the customer the moment their order ships" | shipping, order status | Two independent blockers: `send_message`/`send_attachment` are rejected at save on every commerce trigger (`custom/app/models/custom/automation_rule.rb:9,38-39`), and the event is read-driven. | DO NOT CREATE |
| Any "the moment X happens" commerce notification | order status, after-sales | Read-driven dispatch: one `dispatch` call site, two `ContactMetric.record` callers. | DO NOT CREATE |
| WooCommerce "order shipped"/"order delivered" recipe | shipping | WooCommerce's `STATUSES` map produces neither value and `shipments: []` is hardcoded (`woocommerce/normalizer.rb:17-20,35`). On a default install this is the only enabled provider. | DO NOT CREATE |
| Salla "order paid" recipe | order status | `payment_status` can only be `unpaid` or `unknown` for Salla (`salla/normalizer.rb:137-139`); the literal `paid` is unreachable. | DO NOT CREATE |
| Salla order-number lookup | order status | `searches_orders?` is not overridden → `false` (`providers/base.rb:30`); the store is reported `unsupported`. | DO NOT CREATE |
| Automated refund / cancellation / status-change execution | refunds, cancellation | No commerce action exists in `actions_attributes` (`app/models/automation_rule.rb:54-59`) or in the 21-node registry; and writes are hard-off for salla/zid/shopify via `PRE_UAT`. `cancel_order`/`refund_*` are administrator-only and explicitly never grantable to an agent (`custom/app/policies/commerce/action_policy.rb:9-29`). | DO NOT CREATE |
| Automated contact tagging | contact classification | No contact-label action anywhere; `add_label` is conversation-scoped in all three engines. | NEW PRIMITIVE REQUIRED |
| Scheduled / recurring recipe ("every morning", "7 days after resolution" as a standalone job) | store operations | No cron trigger. `config/schedule.yml` has only `trigger_scheduled_items_job` sweeping already-armed delayed executions. A rule cannot exist without an `event_name` mapped to a listener method. | NEW PRIMITIVE REQUIRED |
| CSAT request inside a flow | customer support | `Flows::Template#sendable?` skips CSAT templates by name (`custom/app/services/flows/template.rb:32`) and there is no CSAT node. | DO NOT CREATE |
| Flow that branches on an external API response | webhook/integration | The `webhook` node declares outputs `['next']` only and never reads the response (`custom/app/services/flows/node_types.rb:29`, `nodes/webhook.rb:14,18`). | NEW PRIMITIVE REQUIRED |
| Campaign- or API-triggered flow (proactive outbound flow) | campaigns | `Flows::Runner`'s only session-creating path is an incoming customer message (`runner.rb:105-132`); `RunJob` accepts only `messages/human/rejected/wake/stop/disabled`; the routes expose no start endpoint (`config/routes/flows.rb:9-15`). | NEW PRIMITIVE REQUIRED |
| Any flow recipe on web widget, email, Instagram, SMS or Facebook | customer support | `Flows::ChannelCapabilities` has exactly one table and `for(inbox)` returns it only for `Channel::Whatsapp` + `whatsapp_cloud` (`custom/app/services/flows/channel_capabilities.rb:9-22`). | NEW PRIMITIVE REQUIRED |
| Multi-step branching **after** human handoff | human handoff, after-sales | `bot_phase?` requires `pending` + no assignee + bot `ai_assignee` (`runner.rb:89-92`) and the listener fires `stop` on any assignee being set. Use delayed automation instead — accepting its single-delay, no-branch shape. | NEW PRIMITIVE REQUIRED |
| Any recipe using `sla_policy_id` as a condition | VIP, routing | Accepted by the EE model (`enterprise/app/models/enterprise/automation_rule.rb:2-4`) but has no `filter_keys.yml` entry, no SQL branch and no UI: the rule silently never matches and is **auto-disabled after two evaluations** with an email to admins. | PATCH (remove or implement) |
| A multi-object "ecommerce pack" installing audience + rules + flow together | all | Architecture refuses it: scalar `type`, single-payload `build`, single `create` event (`app/javascript/dashboard/recipes/index.js:9-23`). | NEW PRIMITIVE REQUIRED |
| A WhatsApp-template starter | campaigns, after-sales | No generic template create/edit/delete exists — the only Meta template writes in the repo are CSAT-only. The inputs vocabulary has no template picker. Also: deleting an approved template blocks re-creating that name for 30 days, which the CSAT delete-then-recreate path can trip (`csat_template_management_service.rb:23-35` → `:181-197`) — a live defect, not a recipe opportunity. | DO NOT CREATE |
| A non-flow bot starter | customer support | The only `bot_type` values are `webhook` and `flow` (`app/models/agent_bot.rb:42`); `bot_config` is read by no production code; there is no bot-template table or seeder. | DO NOT CREATE |

---

## 7. Classification register

| Capability | Class | Note |
|---|---|---|
| Automation rules engine (12 / 20 / 31 condition keys) | REUSE | ship recipes on it as-is |
| Delayed automation (`execution_delay` + 3 wait presets) | REUSE | the only clock you have |
| Flow Builder (21 nodes, Test Mode, publish/draft) | REUSE | WhatsApp Cloud only |
| Macros (16 actions) | REUSE | no trigger dependency — best v1 bet |
| Shared contact audiences as conditions | REUSE | shared filters only; evaluated in Ruby |
| Commerce reads (`commerce_lookup`, Customer 360, audience commerce keys) | REUSE | pull, not push |
| Campaigns (one-off WhatsApp + audience references) | REUSE | membership is dynamic, not static |
| Recipe architecture: add a `macro` type + macros-page mount | **EXTEND** | small, unlocks H8 and the first agent-reachable gallery |
| Recipe architecture: multi-object kits | NEW PRIMITIVE REQUIRED | not needed for v1 |
| `event_name` inclusion validation | **PATCH** | a typo'd recipe event saves and never fires — fix before shipping a catalogue |
| `change_status` missing from `AUTOMATION_ACTION_TYPES` | **PATCH** | an API-created rule using it throws a TypeError in the edit panel (`useEditableAutomation.js:85-87`, `automationHelper.js:400`) |
| Dead per-event `actions:` arrays in `constants.js:90,232,378,518,648` | **PATCH** | they imply restrictions the runtime does not apply; remove them or honour them |
| `sla_policy_id` condition key | **PATCH** | remove it or implement it; today it auto-disables the rule |
| `LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED` has no installation-config row | **PATCH** | the kill switch cannot be seen or flipped from Super Admin, and the builder keeps offering conditions it will reject |
| Test Mode creating a spurious draft version | **PATCH** | makes "Unpublished changes" lie right after a merchant tests a template |
| Flow inbox pickers not filtering on `provider` | **PATCH** | `BotConfiguration.vue:98` and `FlowBuilder.vue:102-107` let a merchant connect a flow to an inbox that can never run it |
| Business-hours / time-of-day condition | NEW PRIMITIVE REQUIRED | unlocks the whole out-of-hours domain |
| `contact_created` / `contact_updated` / audience-membership triggers | NEW PRIMITIVE REQUIRED | unlocks the contact-lifecycle domain |
| Persisted cart state + `commerce_cart_abandoned` event | NEW PRIMITIVE REQUIRED | needs a migration — see §8 |
| Contact-label and contact-attribute automation actions | NEW PRIMITIVE REQUIRED | today only a flow can write a contact attribute |
| Webhook-response branching | NEW PRIMITIVE REQUIRED | |
| Proactive / outbound flow start | NEW PRIMITIVE REQUIRED | |
| Flow channels beyond WhatsApp Cloud | NEW PRIMITIVE REQUIRED | second `ChannelCapabilities` table + per-channel node support |
| Commerce write actions from a rule or flow | DO NOT CREATE | agent-confirmed by design; admin-only policy; hard-off |
| Customer-facing message on a commerce trigger | DO NOT CREATE | deliberate product rule, not an oversight |
| Out-of-hours recipe | DO NOT CREATE | reuse the per-inbox setting |
| Signed automation webhooks | NEW PRIMITIVE REQUIRED | the flow node already signs; the rule action does not |

---

## 8. What needs approval before the rejected set can move

Stated as requirements only. **No migrations are proposed here.**

1. **A business-hours condition.** Requirement: a condition key evaluable at rule-fire time against the inbox's `working_hours` (the table and `closed_now?` logic already exist, `app/models/concerns/out_of_offisable.rb`). It needs a `lib/filters/filter_keys.yml` entry, a `ConditionsFilterService` branch and a `constants.js` entry. No schema change identified. This single addition unlocks the out-of-hours domain and materially improves routing recipes.
2. **Contact-lifecycle triggers.** Requirement: `contact_created`/`contact_updated` handler methods on the automation listener, plus matching `lib/events/types.rb` names; the events are already dispatched for other listeners. Contact-scoped conditions and at least one contact-scoped action (`add_contact_label`, `set_contact_attribute`) would be needed for the triggers to be useful — the current action vocabulary acts only on `@conversation`.
3. **Abandoned cart.** Requirement: a persisted prior cart state and a `Commerce::CartTransitions` that emits a provider-neutral `commerce_cart_abandoned` into the **existing** `Automation::CommerceEvents.dispatch`, with the name added to the single constant the model, listener and frontend all derive from. The account-wide read it needs already exists (`custom/app/controllers/api/v1/accounts/commerce/carts_controller.rb:37-43`, `abandoned_carts(limit: 50)` behind the `:cart_queue` cache), so no new provider call is required. **This requires a new table — flagged for approval, not designed here.** Reliability ceiling: Zid only; Shopify for linked customers but never guests; Salla not reliably; WooCommerce impossible.
4. **A production-gate decision.** Salla, Zid and Shopify reads are off by default and their actions/recovery are additionally held by `PRE_UAT`. Until those gates move, any commerce recipe beyond WooCommerce status lookup ships into a configuration where it cannot run. Decide whether the starter library targets the default install (then: WooCommerce status only) or a configured install (then: document the switches as a recipe prerequisite).
5. **A validation decision on `event_name`.** Either validate it, or accept that a mistyped recipe is an invisible no-op. Given the catalogue is the product, validate it.
