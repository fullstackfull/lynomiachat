---
agent: 036
scope: Automation rules — trigger events, condition vocabulary and operators, action vocabulary (incl. send_whatsapp_template), ordering and multiple matches, action failure, recipe library, automation analytics
confidence: high
---

## 1. What the feature is

An automation rule is one row in `automation_rules` (`app/models/automation_rule.rb:1-24`) carrying **one
`event_name`**, a **jsonb `conditions`** array, a **jsonb `actions`** array, an `active` flag and an optional
`execution_delay` in minutes. It is account-scoped and admin-only.

The engine is three pieces:

1. **`AutomationRuleListener`** (`app/listeners/automation_rule_listener.rb`) — one public method per trigger name.
   It loads the account's `active` rules for that event, evaluates each one's conditions, and either runs the
   actions inline or arms a delayed row.
2. **`AutomationRules::ConditionsFilterService`** (`app/services/automation_rules/conditions_filter_service.rb`) —
   compiles the rule's conditions into one SQL `WHERE` against a base relation locked to the single event's
   conversation (`:174-183`), left-joined to `contacts` and `messages`. The rule matches iff that query returns a
   row.
3. **`AutomationRules::ActionService`** (`app/services/automation_rules/action_service.rb`) — iterates
   `@rule.actions` and `send`s each `action_name` as a Ruby method, inheriting most action implementations from
   `ActionService` (`app/services/action_service.rb`).

Three Lynomia overlays extend it, all through `prepend_mod_with`:
`Custom::AutomationRule` (new triggers, new action, extra validations),
`Custom::AutomationRuleListener` (Commerce trigger dispatch),
`Custom::AutomationRules::{ActionService,ConditionValidationService,ConditionsFilterService}`.
There is no `enterprise/` tree in this repository.

A single installation-wide kill switch, `LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED`
(`custom/app/services/automation/extensions.rb:8-10`, default **true**), turns off *only* what Lynomia added:
Commerce triggers stop dispatching, audience/Commerce conditions stop matching and stop saving. Every plain
Chatwoot rule keeps running.

### 1.1 The real trigger list — 13, not 12

`AutomationRule#event_names` (`app/models/automation_rule.rb:55-57`) returns five conversation triggers, and
`Custom::AutomationRule#event_names` (`custom/app/models/custom/automation_rule.rb:34-36`) appends
`Automation::CommerceEvents::EVENTS`, which is `Commerce::OrderTransitions::EVENTS` (7) plus `CART_EVENTS` (1)
(`custom/app/services/automation/commerce_events.rb:14-15`, `custom/app/services/commerce/order_transitions.rb:22-29`).

| # | `event_name` | Dispatched by | Notes |
|---|---|---|---|
| 1 | `conversation_created` | `Conversation` after-create | Also arms **delayed `conversation_updated`** rules (listener `:62-67`) |
| 2 | `conversation_updated` | conversation update | |
| 3 | `conversation_opened` | status → `open` (`app/models/conversation.rb:379`) | a *status* change, not an agent opening the UI |
| 4 | `conversation_resolved` | status → `resolved` (`app/models/conversation.rb:380`) | |
| 5 | `message_created` | `app/models/message.rb:380` | skips activity messages and auto-reply emails (listener `:105-108`) |
| 6 | `commerce_order_created` | `Automation::CommerceEvents.dispatch` | |
| 7 | `commerce_order_updated` | ditto | |
| 8 | `commerce_order_paid` | ditto | |
| 9 | `commerce_order_shipped` | ditto | |
| 10 | `commerce_order_delivered` | ditto | |
| 11 | `commerce_order_cancelled` | ditto | |
| 12 | `commerce_order_refunded` | ditto | |
| 13 | `commerce_cart_abandoned` | `Automation::CommerceEvents.dispatch_cart` (`:39-46`) | the only cart trigger; `commerce_cart_recovered` deliberately absent (`:11-14`) |

`event_name` is validated by inclusion (`app/models/automation_rule.rb:38-39`), so a name nothing dispatches to
cannot be saved. The frontend offers all 13: five from `AUTOMATION_RULE_EVENTS`
(`app/javascript/dashboard/routes/dashboard/settings/automation/constants.js:689-710`) plus the eight from
`COMMERCE_EVENTS` (`.../lynomiaAutomation.js:13-22`) when the account has `lynomia_commerce`.

Commerce triggers are not provider webhooks: they are the diff between two reads of a customer link's normalized
orders (`custom/app/services/commerce/order_transitions.rb:1-29`). They act on **the contact's latest conversation
in the account** (`custom/app/services/automation/commerce_events.rb:61-63`); if the contact has none, nothing runs
and one `no_conversation` log line is written (`custom/app/listeners/custom/automation_rule_listener.rb:17`). Each
rule runs at most once per event id, claimed in Redis for 7 days (`commerce_events.rb:66-68`, listener `:30`).

### 1.2 The real condition attribute list — 18 + custom attributes + 3 Lynomia keys

The authoritative allow-list is `AutomationRule#conditions_attributes`
(`app/models/automation_rule.rb:59-62`). It is **not** `lib/filters/filter_keys.yml`: the yml is the operator
table, but keys in it that are absent from `conditions_attributes` (`contact_id`, `display_id`, `campaign_id`,
`created_at`, `last_activity_at`, `message_status`, contact `name`, `identifier`, `blocked`) are rejected by
`json_conditions_format` (`:88-94`) with `Automation conditions <key> not supported.`

| Attribute key | Table | Operators (`lib/filters/filter_keys.yml`) |
|---|---|---|
| `status` | conversations | equal_to, not_equal_to |
| `priority` | conversations | equal_to, not_equal_to |
| `inbox_id` | conversations | equal_to, not_equal_to, is_present, is_not_present |
| `team_id` | conversations | equal_to, not_equal_to, is_present, is_not_present |
| `assignee_id` | conversations | equal_to, not_equal_to, is_present, is_not_present |
| `labels` | conversations | equal_to, not_equal_to, is_present, is_not_present |
| `browser_language` | conversations.additional_attributes | equal_to, not_equal_to |
| `conversation_language` | conversations.additional_attributes | equal_to, not_equal_to |
| `referer` | conversations.additional_attributes | equal_to, not_equal_to, contains, does_not_contain |
| `mail_subject` | conversations.additional_attributes | equal_to, not_equal_to, contains, does_not_contain |
| `email` | contacts | equal_to, not_equal_to, contains, does_not_contain |
| `phone_number` | contacts | equal_to, not_equal_to, contains, does_not_contain, **starts_with** |
| `country_code` | contacts.additional_attributes | equal_to, not_equal_to |
| `city` | contacts.additional_attributes | equal_to, not_equal_to, contains, does_not_contain |
| `company_name` | contacts.additional_attributes | equal_to, not_equal_to, contains, does_not_contain |
| `message_type` | messages | equal_to, not_equal_to |
| `private_note` | messages (`private` column, remapped at `conditions_filter_service.rb:116`) | equal_to, not_equal_to |
| `content` | messages (`processed_message_content`, remapped at `:115`) | equal_to, not_equal_to, contains, does_not_contain |

Plus **any of the account's `custom_attribute_definitions`** (`:91`), with operators taken from the attribute's
display type, and **three Lynomia keys** (`custom/app/services/automation/lynomia_condition.rb`):

| Key | Operators | Semantics |
|---|---|---|
| `contact_audience` | `equal_to` ("Is in") / `not_equal_to` ("Is not in") | membership of one or more **shared** contact audiences, evaluated as a separate indexed query for that one contact and bound into the rule's SQL as a boolean (`:51-58`) |
| `commerce_*` (the `Audience::CommerceCondition` fields, e.g. `commerce_spend_sar`, `commerce_active_order`, `commerce_store`) | from `Audience::CommerceCondition#operators` | the contact's Commerce facts, local data only |
| `commerce_event_store`, `commerce_event_provider` | equal_to / not_equal_to | the store and platform **of the event being handled**; only valid on a Commerce trigger (`custom/app/models/custom/automation_rule.rb:68-73`) |

Two operator facts the UI hides:

- **`attribute_changed`** is accepted for *any* key: `ConditionValidationService#operation_valid?` returns true
  before consulting the operator table (`app/services/automation_rules/condition_validation_service.rb:52-53`),
  and `ConditionsFilterService` evaluates it against `event.data[:changed_attributes]` with a
  `{from: [...], to: [...]}` value shape (`:81-109`). No operator list in `operators.js` offers it, so it is
  **API-only**. It is forbidden on delayed rules (`app/models/automation_rule.rb:122-128`).
- The date operators `is_greater_than`, `is_less_than`, `days_before` exist in `FilterService`
  (`app/services/filter_service.rb:37-40, 86-114`) but **no allowed standard key has a date data type**, so in
  automation they are reachable only through date-typed custom attributes.

`query_operator` must be `AND` or `OR`, case-insensitively, and exactly one condition may omit it
(`app/models/automation_rule.rb:105-110, 112-118`).

### 1.3 The real action list — 19

`AutomationRule#actions_attributes` (`app/models/automation_rule.rb:64-68`, 18 entries) plus
`send_whatsapp_template` from `Custom::AutomationRule#actions_attributes`
(`custom/app/models/custom/automation_rule.rb:27-29`) = **19**. Anything else is refused by `json_actions_format`
(`:96-101`).

| Action | Implementation | Param shape |
|---|---|---|
| `assign_agent` | `app/services/action_service.rb:43-55` | `[agent_id]`, `['nil']`, or `['last_responding_agent']`; agent must be an inbox member or an administrator |
| `assign_team` | `:64-74` | `[team_id]`; `nil`/`0`/blank unassigns; team must belong to the account |
| `remove_assigned_agent` | `:76-78` | none |
| `remove_assigned_team` | `:80-82` | none |
| `add_label` | `:37-41` | label name array |
| `remove_label` | `:57-62` | label name array |
| `change_priority` | `:33-35` | `[priority]`, `['nil']` clears |
| `change_status` | `:29-31` | `[status]` — **not offered anywhere in the UI**, API-only |
| `resolve_conversation` / `open_conversation` / `pending_conversation` / `snooze_conversation` / `mute_conversation` | `:9-27` | none |
| `send_message` | `automation_rules/action_service.rb:43-48` | `[text]`; skipped on tweets |
| `add_private_note` | `:50-55` | `[text]` |
| `send_attachment` | `:25-36` | `[blob_id]`; signed blob id resolved in `AttachmentConcern` |
| `send_email_to_team` | `:57-66` | `[{team_ids:, message:}]`; account-scoped teams, account email rate limit |
| `send_email_transcript` | `action_service.rb:84-96` | `[comma-separated emails]`; requires `email_transcript_enabled?` |
| `send_webhook_event` | `:38-41` → `WebhookJob` | `[url]`; payload is `conversation.webhook_data` + `event: "automation_event.<event_name>"`, plus a `commerce:` block on a Commerce trigger (`custom/app/services/custom/automation_rules/action_service.rb:12-19`) |
| `send_whatsapp_template` | `custom/.../action_service.rb:24-28` → `Custom::AutomationRules::TemplateAction` | `[{inbox_id:, name:, language:, params:}]` |

**`send_whatsapp_template`** is the one Lynomia-added action. It exists because a Commerce trigger must be able to
reach a shopper whose 24-hour service window has closed, and an approved template is the only thing WhatsApp
permits there (`custom/app/services/custom/automation_rules/template_action.rb:1-21`). It reuses the existing
`Flows::Template` gate, `Messages::MessageBuilder` with `template_params`, `Commerce::RecoveryUrl` and
`Commerce::ActionRun`; it adds no sender and makes no Meta call of its own. It supports a small closed token set
in its variable mapping — `{{contact.name}}`, `{{cart.recovery_url}}`, `{{cart.total}}`, `{{cart.currency}}`,
`{{cart.item_count}}` (`:112-127`) — and **refuses rather than sending a half-filled template** if any token or
required slot cannot be resolved (`:78-110`). It never falls back to free-form text (`:20-21`).

It is deliberately **not** in `CUSTOMER_MESSAGE_ACTIONS` (`custom/app/models/custom/automation_rule.rb:15`), which
stays `%w[send_message send_attachment]` — the free-form deny-list for Commerce triggers.

### 1.4 Ordering, multiple matches, and chaining

- **Actions within a rule** run strictly in array order, each after `@conversation.reload`
  (`app/services/automation_rules/action_service.rb:10-18`).
- **Multiple rules on the same event**: all of them run.
  `AutomationRuleListener#current_account_rules` (`:88-94`) issues `AutomationRule.where(event_name:, account_id:,
  active: true)` with **no `ORDER BY`**, and `rules.each` runs them in whatever order Postgres returns. Rule
  execution order is therefore **unspecified** — two rules that both set priority or status on one event have a
  non-deterministic winner. Not configurable, not surfaced.
- **Rules do not chain.** `ActionService#initialize` sets `Current.executed_by = rule` (`:6`); every conversation
  and message event carries `performed_by: Current.executed_by` (`app/models/conversation.rb:390`,
  `app/models/message.rb:380`), and the listener drops any event whose `performed_by` is an `AutomationRule`
  (`:96-98, 107`). `Current.reset` runs in an `ensure` (`:19-20`).
- **One change can match two different triggers.** A resolve dispatches both `conversation_updated` and
  `conversation_resolved` (`app/models/conversation.rb:377-387`), so a rule on each both fire.
- **Conversation creation also arms delayed `conversation_updated` rules** (`listener:62-67`), deduped by the
  unique episode index.

### 1.5 Delayed ("wait") rules

`execution_delay` is 10 minutes to 30 days (`app/models/automation_rule.rb:25`), gated on the account feature
`delayed_automations` (default off, `config/features.yml:297-300`). A matching event writes an
`AutomationRulePendingExecution` instead of acting (`listener:72-80`); `AutomationRules::TriggerPendingExecutionsJob`
sweeps every 5 minutes (`config/schedule.yml:12-15` → `app/jobs/trigger_scheduled_items_job.rb:33`), and
`ProcessPendingExecutionJob` re-checks and runs.

Constraints that shape the UI:

- A conversation-level delayed rule may only filter on `status` and `inbox_id`
  (`app/models/automation_rule.rb:28, 131-136`), because the episode key is the status clock.
- `attribute_changed` is forbidden with a delay (`:122-128`).
- Commerce triggers may not be delayed at all (`custom/app/models/custom/automation_rule.rb:79`).
- Editing a rule's `active`, `execution_delay`, `event_name`, `conditions` or `actions` **deletes its armed rows**
  (`:47, 139-150`) — waits already in flight are silently discarded.
- The UI expresses this as three named waits, not raw event+condition
  (`.../constants.js:823-837`): *Conversation stays in a status*, *Customer hasn't replied*,
  *No teammate has replied*.

## 2. Surfaces and routes

| Surface | Path |
|---|---|
| Rule list, recipes button, delete/clone/toggle | `app/javascript/dashboard/routes/dashboard/settings/automation/Index.vue:1-564` |
| Route | `.../automation/automation.routes.js` |
| Create panel | `.../AddAutomationRule.vue:63-75` (accepts `?audience=` prefill) |
| Edit panel | `.../EditAutomationRule.vue` |
| Shared form | `.../AutomationRuleForm.vue:296-389` |
| Instant trigger section | `.../components/AutomationInstantTrigger.vue` |
| Wait section | `.../components/AutomationWaitCondition.vue:377-476` |
| Run-type switch | `.../components/AutomationRunTypeSelector.vue` |
| Action rows | `.../components/AutomationActions.vue:52-93` → `app/javascript/dashboard/components/widgets/AutomationActionInput.vue` |
| WhatsApp template action control | `app/javascript/dashboard/components/widgets/AutomationActionWhatsappTemplateInput.vue:135-212` |
| Recipe gallery | `app/javascript/dashboard/components-next/recipes/RecipeDialog.vue`, catalogues in `app/javascript/dashboard/recipes/automationRecipes.js` and `setupRecipes.js` |
| Analytics screen | `app/javascript/dashboard/routes/dashboard/analytics/AnalyticsAutomations.vue:18-25`, route `analytics/automations` (`analytics.routes.js:45-50`) |
| Contact timeline entries | `custom/app/services/contacts/activity_timeline/automations_adapter.rb` |

API: `resources :automation_rules, only: [index, create, show, update, destroy]` plus a nested `clone`
(`config/routes.rb:94`), served by `app/controllers/api/v1/accounts/automation_rules_controller.rb:8-57`.
Analytics: `GET /api/v1/accounts/:id/analytics/automations` (`config/routes/analytics.rb:17` →
`custom/app/controllers/api/v1/accounts/analytics_controller.rb:45`).

## 3. User-visible states

| State | Produced by |
|---|---|
| Empty list with recipe + scratch buttons | `Index.vue:475-500` |
| Loading skeleton + `sr-only` "Loading" | `Index.vue:466-468, 507` |
| Two tabs, *Runs instantly* / *Runs after a wait*, with counts | `Index.vue:82-93`; tabs hidden entirely when the feature is off and no legacy delayed rule exists (`:74-78`) |
| Amber banner: delayed execution turned off, those rules paused | `Index.vue:145-149, 469-474` |
| `Runs after 4 hours` badge on a row | `AutomationRuleRow.vue:53-62` |
| Search with no results | `Index.vue:107` → `AUTOMATION.NO_RESULTS` |
| Activate/deactivate confirmation modal | `Index.vue:344-378` |
| Delete modal requiring the rule name typed | `Index.vue:542-551` |
| Recipe tile reading *Needs a connected store first* | `useRecipeContext.js:90-104`, `RecipeDialog.vue:151` |
| Recipe provider note ("WooCommerce has no shipped status…") | `recipes/index.js:18-22`, copy in `recipes.json` |
| `Created. Review it before you turn it on.` | `Index.vue:280` |
| Partial setup-recipe failure naming what exists | `Index.vue:224-233` |
| Commerce-trigger note inside the trigger section | `AutomationRuleForm.vue:347-353` → `AUTOMATION.LYNOMIA.COMMERCE_TRIGGER_NOTE` |
| Template control: inbox select → template select → one input per slot | `AutomationActionWhatsappTemplateInput.vue:137-205` |
| `This inbox has no approved template that can be sent.` | same file `:154-159` |
| `Fill every variable this template needs, or it cannot be sent.` | same file `:207-209` |
| **Rule auto-deactivated and an email sent** | `Reauthorizable#handle_automation_rule_reauthorization` (`app/models/concerns/reauthorizable.rb:62-64, 95`) after 2 condition-validation failures (`conditions_filter_service.rb:46-52`) |
| Analytics: six KPIs, three series, three breakdowns | `Analytics::Automations::Overview#call` |
| Analytics warnings: *Immediate automation rules: they run inline and record nothing…* and *Part of this date range: finished episodes are kept for 30 days…* | `Overview#add_warnings:36-39`, copy in `analytics.json` `ANALYTICS.META.WARNING_REASON` |

**There is no per-rule run history, last-run time, match count or error surface in the rule list or the rule
editor.** Nothing in the product tells an administrator whether an instant rule has ever matched.

## 4. Errors and validation messages

Server, `config/locales/en.yml:730-743` (`automation.lynomia.*`), all rendered as a 422 body by
`render_could_not_create_error`:

| Key | String | Raised at |
|---|---|---|
| `extensions_disabled` | `%{installation_name} automation extensions are turned off on this installation.` | `custom/app/models/custom/automation_rule.rb:85-88, 97` |
| `too_many_conditions` | `A rule can have at most %{count} audience and Commerce conditions.` | `:100` |
| `invalid_operator` | `This operator is not available for %{key}.` | `lynomia_condition.rb:42` |
| `invalid_values` | `The values of %{key} are not valid.` | `:43, 80, 99` |
| `audience_not_shared` | `Automation rules can only use the shared audiences of this account.` | `:88` |
| `commerce_disabled` | `Commerce conditions and triggers need Lynomia Commerce on this account.` | `:77, 94`; also `custom_automation_rule.rb:77` |
| `invalid_store` | `The store is not one of this account's stores.` | `:78, 95` |
| `no_delay` | `Commerce triggers run at once; they cannot wait.` | `custom/app/models/custom/automation_rule.rb:79` |
| `no_customer_message` | `Commerce triggers cannot send messages to the customer (%{actions}). Use a label, an assignment, a private note or a webhook.` | `:81` |
| `template_action_incomplete` | `The approved WhatsApp template action needs %{keys}. Choose a WhatsApp inbox and an approved template.` | `:60` — **checked only while `active?`** (`:53`) |
| `event_condition_without_trigger` | `The order store and order platform conditions need a Commerce trigger.` | `:72` |
| `errors.automation_rule.event_name.unsupported` | `is not a trigger this installation can run` | `app/models/automation_rule.rb:38-39` |

Un-i18n'd server strings (English literals in the model/controller):

- `Automation conditions <keys> not supported.` — `app/models/automation_rule.rb:93`
- `Automation actions <names> not supported.` — `:100`
- `Automation conditions should have query operator.` — `:108`
- `Query operator must be either "AND" or "OR"` — `:117`
- `cannot be used with attribute_changed conditions.` — `:127`
- `only supports status and inbox conditions for conversation-level events.` — `:135`
- `Delayed automations are not enabled for this account.` — `app/controllers/api/v1/accounts/automation_rules_controller.rb:80`
- `errors.attachments.invalid` — `app/controllers/concerns/attachment_concern.rb:12`

Client, `app/javascript/dashboard/i18n/locale/en/automation.json` → `AUTOMATION.ERRORS.*`, raised by
`app/javascript/dashboard/helper/validations.js:81-190`:
`Attribute key is required`, `Filter operator is required`, `Value is required`,
`Value must be between 1 and 998`, `Action parameters are required`,
`At least one condition is required`, `At least one action is required`, plus
`AUTOMATION.ADD.FORM.WAIT.ERROR` — `The wait must be between 10 minutes and 30 days`
(`AutomationWaitCondition.vue:472-474`).

Provider-relayed errors: **none reach the UI.** Every refusal of `send_whatsapp_template` is a log line only
(`template_action.rb:183-188`): `inbox_not_in_account`, `channel_not_whatsapp`,
`conversation_inbox_mismatch`, `contact_unavailable`, `template_not_found`,
`template_language_unavailable`, `template_not_approved`, `template_not_allowed`
(`custom/app/services/flows/template.rb:23-29, 76-78`), `template_param_missing`.

## 5. Failure paths

1. **An action raises → swallowed.** `ActionService#perform` rescues `StandardError` per action, sends it to
   `ChatwootExceptionTracker`, and continues with the next action
   (`app/services/automation_rules/action_service.rb:13-17`). The user is never told. A rule whose first action
   fails still runs the rest, and the list shows a healthy, enabled rule.
2. **A condition fails validation at run time → the rule is silently disabled.**
   `ConditionsFilterService#rule_valid?` calls `@rule.authorization_error!` (`:49`); two failures cross
   `Reauthorizable::AUTHORIZATION_ERROR_THRESHOLD` and the rule is set `active: false` with an email to
   administrators (`app/models/concerns/reauthorizable.rb:62-64`). Typical trigger: a shared audience is deleted
   or un-shared, or a custom attribute is removed. The rule list shows only an off toggle, with no reason.
3. **Condition compilation raises → the rule does not match.** `perform` rescues everything, logs, returns false
   (`conditions_filter_service.rb:40-44`). An `attribute_changed` condition on an attribute that did not change
   NoMethodErrors here (`:95`) and lands in this path.
4. **`send_whatsapp_template` refused → nothing is sent, nothing is shown.** See §4. The refusal is only in the
   logs; there is no activity message, no failed message bubble and no rule-level indicator.
5. **Free-form `send_message` outside the WhatsApp 24-hour window** → the message is created and marked failed by
   `Whatsapp::SendOnWhatsappService`; visible in the conversation but not attributed to the rule in any list.
6. **Webhook refused by SSRF filter or timing out** → logged, not retried
   (`docs/automation/05-runtime-security-and-tenancy.md:50-66`). Invisible in the product.
7. **Email actions hit the account rate limit** → the loop `break`s mid-way
   (`action_service.rb:61`, `app/services/action_service.rb:90`); some teams/addresses are mailed and some are not,
   with no record of where it stopped.
8. **Delayed row stranded.** A worker that dies while actions are running leaves the row `executing`, and
   **nothing ever reclaims it**, by design (`app/models/automation_rule_pending_execution.rb:50-52`). Only
   Analytics' `Stranded` KPI exposes this.
9. **Delayed row expires.** A row more than `DUE_WINDOW` (3 days) overdue is skipped with
   `skip_reason: 'expired'` (`app/jobs/automation_rules/process_pending_execution_job.rb:24`). Other skip reasons:
   `rule_inactive`, `conversation_gone`, `episode_moved`, `conditions_changed` (`:29-42`).
10. **Sweep capped.** 1000 rows per 5-minute sweep by default
    (`app/jobs/automation_rules/trigger_pending_executions_job.rb:4, 20`); a backlog beyond that is only visible in
    the `capped: true` log line (`:13`).
11. **Editing a rule discards armed waits** (`app/models/automation_rule.rb:47, 139-150`). Nothing warns the
    administrator before saving.
12. **Reachable crash: the rule editor throws on an action it does not offer.**
    `showActionInput` does `automationActionTypes.find(i => i.key === action).inputType`
    (`app/javascript/dashboard/helper/automationHelper.js:397-402`) with no guard. `automationActionTypes` is
    filtered by `lynomia.actionAllowed`, which hides `send_whatsapp_template` on an account with **no WhatsApp
    inbox** (`.../lynomiaAutomation.js:183-189`). The *Abandoned cart* recipe requires only
    `[AUTOMATIONS, COMMERCE, COMMERCE_STORE]` (`automationRecipes.js:108-117`) — it does **not** require a
    WhatsApp inbox, and `whatsAppInboxes` is collected in `useRecipeContext` (`:21, 35`) but used by no
    requirement. So: Commerce + a store + no WhatsApp inbox → the recipe is offered, creates a rule carrying
    `send_whatsapp_template`, and `Index.vue:281` immediately opens it for review → `find()` returns `undefined`
    → TypeError. Same path for a rule holding `change_status`, which the backend supports but
    `AUTOMATION_ACTION_TYPES` never lists (API-created rules only).
13. **`add_sla` is offered and cannot be saved.** `AUTOMATION_ACTION_TYPES` includes `add_sla`
    (`constants.js:808-812`), shown whenever the account's `sla` feature is on
    (`AutomationRuleForm.vue:221-226`). The `sla` feature exists (`config/features.yml:131-135`) but this
    repository has **no `SlaPolicy` model, no SLA controller and no `add_sla` action anywhere in Ruby**, and
    `add_sla` is absent from `actions_attributes`. Saving yields
    `Automation actions add_sla not supported.`

## 6. Permissions

| Surface | Gate | `file:line` |
|---|---|---|
| Every rule action (index/show/create/update/clone/destroy) | `@account_user.administrator?` | `app/policies/automation_rule_policy.rb:1-25` |
| Rules are account-scoped | `Current.account.automation_rules` | `automation_rules_controller.rb:9, 18, 50, 88` |
| Automation page/feature | account feature `automations` | `app/javascript/dashboard/featureFlags.js`, required by every recipe (`recipes/index.js:44`) |
| Commerce triggers + Commerce conditions | account feature `lynomia_commerce` **and** `Automation::Extensions.enabled?` | `custom/app/models/custom/automation_rule.rb:76-77`; `custom/app/listeners/custom/automation_rule_listener.rb:23`; `custom/app/services/automation/lynomia_condition.rb:35-37` |
| Audience conditions | installation switch only (no plan flag); audiences must be `shared: true` of the account | `lynomia_condition.rb:116`, `custom/app/models/custom/automation_rule.rb:97` |
| Delayed rules (create, update, clone, sweep) | account feature `delayed_automations` | `automation_rules_controller.rb:63, 72-85`; `listener:74`; `process_pending_execution_job.rb:8`; `AutomationRulePendingExecution.for_enabled_accounts` |
| `add_sla` in the action dropdown | `isCloudFeatureEnabled('sla')` | `AutomationRuleForm.vue:223` |
| `send_whatsapp_template` in the dropdown | account has ≥1 WhatsApp inbox | `lynomiaAutomation.js:186` |
| Analytics automations screen | `administrator` or `report_manage`, feature `reports` | `analytics.routes.js:16-19` |
| Audit trail | `name, description, event_name, active, execution_delay` only — `conditions`/`actions` deliberately excluded | `custom/app/models/custom/audit/automation_rule.rb:10-14` |

Automation is **not** a custom-role permission: there is no `automation_manage`, so a custom role cannot be
granted this page. This matches the existing article's claim.

A rule saved through the API may name another account's team or agent id — Chatwoot does not validate action ids at
save time — and the run-time checks in `ActionService` simply skip the action
(`app/services/action_service.rb:104-113`, documented at `docs/automation/05-runtime-security-and-tenancy.md:27-31`).

## 7. Contextual-help opportunities

| UI location (`file:line`) | The question a user has there | Registry key that should link there | Key exists in `DOC_ARTICLES`? |
|---|---|---|---|
| `Index.vue:426-431` ("Learn more", `feature-name="automation"`) | What is an automation rule? | `automation` | **yes** — wired via `featureHelper.js:10` |
| `Index.vue:447-454` (*Start from a recipe*) / `RecipeDialog.vue` | What does a recipe create, and why is it switched off? | new `automationRecipes` | no |
| `Index.vue:469-474` (delay-disabled banner) | Why are my waiting rules paused and how do I re-enable them? | new `automationWaits` | no |
| `AutomationWaitCondition.vue:424-434` (wait explanation aside) | What exactly starts and cancels the clock? | new `automationWaits` | no |
| `AutomationWaitCondition.vue:461-470` (*Add condition* on a status wait, which offers nothing) | Why can a waiting rule only test status and inbox? | new `automationWaits` | no |
| `AutomationRuleForm.vue:347-353` (Commerce trigger note) | Which store events does my platform report, and why can't I message the customer? | `commerceProviders` + a new `automationCommerceTriggers` | `commerceProviders` yes; trigger key no |
| `AutomationActionWhatsappTemplateInput.vue:154-159` (*no approved template*) | How do I get a template approved? | `whatsappTemplateLifecycle` | **yes**, not linked here |
| `AutomationActionWhatsappTemplateInput.vue:207-209` (*Fill every variable*) | Why must every variable be filled? | `whatsappTemplates` | **yes**, not linked here |
| `AutomationActions.vue:52-93` (action list) | What does each action do, and which combinations conflict? | `automation` | yes, not linked here |
| `Index.vue:344-378` (activation modal) | Will this act on conversations that already exist? | `automation` | yes, not linked here |
| `AnalyticsAutomations.vue:18-25` + the two warnings | Why are my instant rules missing from this screen? | new `automationAnalytics` | no |
| `Reauthorizable`-driven auto-deactivation email (`app/mailers/administrator_notifications/account_notification_mailer.rb`) | Why was my rule turned off? | new `automationDisabled` | no |

`DOC_ARTICLES` has exactly three automation-area keys today — `automation`, `flows`, `automationOrFlows` — plus
`macrosOrAutomation` and `agentBots` (`app/javascript/dashboard/helper/documentationLinks.js:24, 58-62`).

## 8. Current documentation coverage

| File | Words | Covers |
|---|---|---|
| `custom/db/documentation/en/automation/automation-rules.md` | 1029 | the whole feature: triggers, conditions, actions, recipes, a worked example, permissions, 9 limits, troubleshooting |
| `custom/db/documentation/ar/automation/automation-rules.md` | 211 | the same article, ~a fifth of the length |
| `custom/db/documentation/en/automation/automation-or-flow-builder.md` | 1005 | rule vs flow, including "a rule cannot send a message to a customer on a Commerce trigger" |
| `custom/db/documentation/en/conversations/macros-or-automation.md` | 1094 | manual vs automatic |
| `custom/db/documentation/{en,ar}/automation/flow-builder.md`, `agent-bots.md` | — | adjacent, out of scope here |

The EN automation-rules article is genuinely good: task-oriented, honest about limits, and most of its claims
check out against the code (conditions join with and/or and at least one is required; administrators only;
Commerce rules act on the contact's latest conversation; a failed action is not reported; rules do not chain;
recipes arrive switched off; waiting rules are 10 minutes–30 days, optional, and can only test status and inbox
on a conversation event; editing discards armed waits). Section `automation` sits at manifest position 60
(`custom/db/documentation/manifest.yml:67-76`).

## 9. Missing or stale documentation

**Stale in the published corpus** (`custom/db/documentation/en/automation/automation-rules.md`):

- `:33` — "There are twelve." There are **thirteen**: `commerce_cart_abandoned` is missing from the table at
  `:35-38` (`custom/app/services/automation/commerce_events.rb:14-15`).
- `:54-56` — the action list omits **`send_whatsapp_template`** entirely, the one customer-facing action a
  Commerce trigger *can* use (`custom/app/models/custom/automation_rule.rb:10-13, 27-29`).
- `:58-60` — "A Commerce trigger deliberately offers neither send a message nor send an attachment… Use a private
  note and a team instead." True but now incomplete: the approved-template action exists precisely for this case.
- `:65` — "The eleven [recipes]". There are **twelve** (`automationRecipes.js:98-335`), plus one setup recipe
  (`setupRecipes.js:50-59`) which the article does mention at `:67-68`.
- `:85-87` — says administrators do "creating, editing, cloning, switching on and deleting"; correct, but
  `show?`/`index?` are also administrator-only, so an agent cannot even read a rule.

**Missing from the corpus entirely:**

1. **The `send_whatsapp_template` action.** No article explains the inbox+template+language identity, the five
   supported `{{tokens}}`, that the template must be approved *and* sendable (not authentication category, no
   CSAT, no unsupported component), that an unresolvable variable refuses the send, or that the refusal appears
   nowhere in the product.
2. **The abandoned-cart recipe's two-step completion** — the recipe deliberately leaves the inbox and template
   blank, the rule cannot be switched on until they are filled, and on an account with no WhatsApp inbox the
   editor cannot even render the control (§5.12).
3. **Rule execution order between rules is unspecified** (§1.4). The article says two rules can both match but
   not that their order is non-deterministic.
4. **Rules auto-deactivate after two condition-validation failures**, with an email (§5.2). Nothing documents
   this, and it is the single most likely reason a working rule stops working.
5. **Automation analytics** — six KPIs, three breakdowns, and the crucial caveat that **instant rules are absent,
   not zero**, and that history older than 30 days is incomplete
   (`custom/app/services/analytics/automations/metrics.rb:43-57`). No article mentions the screen.
6. **The `Stranded` KPI** and what to do about a non-zero value.
7. **Delayed-rule skip reasons** (`expired`, `rule_inactive`, `conversation_gone`, `episode_moved`,
   `conditions_changed`) which the analytics *Reason declined* breakdown surfaces verbatim
   (`metrics.rb:175-179`) with no glossary anywhere.
8. **Which condition keys actually exist** — the article describes them in prose ("status, priority, inbox,
   assignee, team, labels… email, phone, company, country, language") and omits `city`, `referer`,
   `mail_subject`, `browser_language`, `private_note`, and the fact that `labels` means conversation labels while
   contact labels are not testable.
9. **Operators** are not listed at all. `starts_with` exists only for `phone_number`; `is_present`/`is_not_present`
   only for `assignee_id`, `inbox_id`, `team_id`, `labels`; date operators only via custom attributes.
10. **`attribute_changed`** — a real, API-only condition form with its own `{from, to}` shape, undocumented.
11. **The webhook payload shape**, including the `commerce:` block added on Commerce triggers
    (`custom/app/services/custom/automation_rules/action_service.rb:12-19`) and the facts that automation webhooks
    are **unsigned** and **not retried**.
12. **The installation switch `LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED`** and what an administrator sees when it is
    off (`%{installation_name} automation extensions are turned off on this installation.`).
13. **EN/AR parity**: the Arabic automation-rules article is 211 words against 1029. It cannot contain the trigger
    table, the limits list or the worked example. (Classification belongs to the corpus agents; flagged here as
    evidence.)

## 10. Doc claims not proven by code

| Claim | Where | Verdict |
|---|---|---|
| "There are twelve [trigger events]" | `en/automation/automation-rules.md:33` | **wrong** — 13 (`commerce_events.rb:14-15`) |
| "The eleven [recipes]" | same `:65` | **wrong** — 12 (`automationRecipes.js:98-335`) |
| Action list for Commerce triggers | same `:54-60` | **incomplete** — omits `send_whatsapp_template` (`custom/app/models/custom/automation_rule.rb:27-29`) |
| "A rule's own actions do not trigger other rules. … means rules cannot be chained." | same `:93` | **confirmed** (`action_service.rb:6`; `listener:96-98, 107`) |
| "A failed action is not reported. Each action is attempted in turn; the rest still run, silently." | same `:97` | **confirmed** (`action_service.rb:13-17`) |
| "No time-based conditions of any kind" | same `:91` | **confirmed** for standard keys; a date-typed **custom attribute** does accept `is_greater_than`/`is_less_than`/`days_before` (`filter_service.rb:86-114`) — so the claim is slightly too strong |
| "'Add label' labels the conversation, never the contact" | same `:95` | **confirmed** (`conversation_query_string:153` resolves `labels` against conversations; `conditions_attributes` has no contact-label key) |
| "Commerce rules never wait, and each runs at most once per order change" | same `:98` | **confirmed** (`custom_automation_rule.rb:79`; `commerce_events.rb:66-68`) |
| "Editing such a rule discards the waits already armed" | same `:101` | **confirmed** (`automation_rule.rb:47, 139-150`) |
| "Automation has no template parameters, so it can never send a template or bypass the window." | **internal** doc `docs/automation/05-runtime-security-and-tenancy.md:72-74` | **now wrong** — `Custom::AutomationRules::TemplateAction` sends `template_params` through `Messages::MessageBuilder` (`template_action.rb:156-164`). The internal design record was not updated when the action landed. |
| "`send_email_to_team` … **patched**: `@account.teams.where(id:)`" | `docs/automation/05:19` | **confirmed** (`automation_rules/action_service.rb:58`) |
| Automation webhooks "are not signed" and "Failure: logged …, not retried" | `docs/automation/05:62-66` | **plausible but not re-verified here** — I did not read `Webhooks::Trigger`/`SafeFetch`. Marked unverified. |
| `AUTOMATION.LYNOMIA.COMMERCE_TRIGGER_NOTE` says a Commerce rule runs "(a store update, or an agent opening the conversation)" | `automation.json` | **confirmed in spirit** — the dispatch is driven by `Commerce::ContactMetric.record`, i.e. by *when Lynomia reads the orders*, not by the store pushing. Worth saying plainly in the article, because it explains perceived delay. |

Not checked: `Webhooks::Trigger`/`SafeFetch` internals; the Arabic article bodies beyond word counts; the
`conversation_updated` dispatch conditions in full; `Audience::CommerceCondition`'s own operator/field list (agent
on audiences owns that); whether `params[:conditions]`/`params[:actions]` being assigned raw rather than from
`automation_rules_permit` (`automation_rules_controller.rb:20, 34-35` vs `:61-70`) persists keys outside the permit
list — the permit list is demonstrably bypassed for those two attributes, but the resulting jsonb content was not
verified at runtime.
