# Lynomia Automation: what Chatwoot already has

Discovery of the existing Automation Rules system before any change. Every path below is the code as found on
`claude/laughing-albattani-8yi0kh` at the start of the phase (Chatwoot 4.18 plus Lynomia's `custom/` overlay).

```text
EXISTING AUTOMATION ENGINE TO EXTEND:
  model        AutomationRule (automation_rules), AutomationRulePendingExecution (delays)
  trigger      Events::Types → Dispatcher (Sync + Async) → EventDispatcherJob → AutomationRuleListener
  conditions   AutomationRules::ConditionsFilterService < FilterService, AutomationRules::ConditionValidationService,
               lib/filters/filter_keys.yml
  actions      AutomationRules::ActionService < ActionService (+ Enterprise::ActionService)
  API          Api::V1::Accounts::AutomationRulesController, AutomationRulePolicy, jbuilder views
  UI           settings/automation: Index.vue, AutomationRuleForm.vue, AutomationInstantTrigger.vue,
               AutomationWaitCondition.vue, AutomationActions.vue, constants.js, operators.js,
               composables useAutomation / useAutomationValues / useEditableAutomation, helper/automationHelper.js,
               components-next/filter/ConditionRow.vue (the same row the contact filter uses)
```

## 1. Model and tables

`automation_rules`: `account_id`, `name`, `description`, `event_name` (string), `conditions` (jsonb), `actions`
(jsonb), `active`, `execution_delay` (minutes, nullable), timestamps. One index (`account_id`). `has_many_attached
:files` (attachments for `send_attachment`).

- `conditions`: the shared condition shape `{ attribute_key, filter_operator, values, query_operator,
  custom_attribute_type }`, flat chain, `query_operator` AND / OR.
- `actions`: `[{ action_name, action_params: [] }]`.
- Validation (`AutomationRule`): every condition key must be in `conditions_attributes` (content, email, country_code,
  status, message_type, browser_language, assignee_id, team_id, referer, city, company_name, inbox_id, mail_subject,
  phone_number, priority, conversation_language, labels, private_note; Enterprise adds `sla_policy_id`) or an account
  custom attribute; every action in `actions_attributes` (below); at most one condition without `query_operator`;
  operators only AND / OR; `execution_delay` 10–43,200 minutes, never with `attribute_changed`, and for conversation
  events only with status / inbox conditions.
- There is **no validation of `event_name`**: the listener simply has no method for an unknown name.
- `Reauthorizable`: a rule whose conditions fail validation at run time gets `authorization_error!` (Redis counter);
  after 2 it is flagged `reauthorization_required` (shown in the UI); changing its conditions clears it.
- `automation_rule_pending_executions` (feature `delayed_automations`): one row per armed delayed run (rule,
  conversation, optional message, `episode_key`, `due_at`, status pending / processing / executing / executed /
  skipped), unique on `(automation_rule_id, conversation_id, episode_key)`. Swept by
  `AutomationRules::TriggerPendingExecutionsJob` (from `TriggerScheduledItemsJob`), run by
  `AutomationRules::ProcessPendingExecutionJob`, which re-checks the rule, the episode and the conditions at due time.
- Enterprise: `Enterprise::AutomationRule` (adds `sla_policy_id`, `add_sla`), `Enterprise::Audit::AutomationRule`
  (`audited associated_with: :account`: create / update / destroy in the audit log).

## 2. Triggers (event pipeline)

| Rule event | Chatwoot event | Dispatched from |
|---|---|---|
| `conversation_created` | `conversation.created` | `Conversation` after create |
| `conversation_updated` | `conversation.updated` | `Conversation` after update (with `changed_attributes`) |
| `conversation_opened` | `conversation.opened` | status → open |
| `conversation_resolved` | `conversation.resolved` | status → resolved |
| `message_created` | `message.created` | `Message` after create |

`Rails.configuration.dispatcher.dispatch(name, time, data)` → `SyncDispatcher` (ActionCable, agent bots, in process)
and `AsyncDispatcher` → `EventDispatcherJob` (queue `critical`) → Wisper publishes to `AutomationRuleListener`,
`CampaignListener`, `CsatSurveyListener`, `HookListener`, `InstallationWebhookListener`, `NotificationListener`,
`ParticipationListener`, unread counts, `ReportingEventListener`, `WebhookListener`. A listener receives only the
events it defines a method for (`conversation.updated` → `conversation_updated`).

`AutomationRuleListener`:
- loads the account's active rules for that `event_name`;
- for each: `ConditionsFilterService.new(rule, conversation, { changed_attributes:, message: }).perform`;
- match → `execute_rule`: immediate `AutomationRules::ActionService`, or, with `execution_delay` and the account's
  `delayed_automations`, `AutomationRulePendingExecution.schedule`;
- `conversation_created` also arms delayed `conversation_updated` rules.

There are no contact, Commerce, campaign or schedule triggers. Every rule runs **on one conversation**.

## 3. Condition engine

`AutomationRules::ConditionsFilterService < FilterService` (the same base class as the contact and conversation
filters):

- `rule_valid?` → `ConditionValidationService`: each key must be in `filter_keys.yml` (`conversations:`,
  `contacts:`, `messages:`) with an allowed operator, or an account custom attribute; else the rule is not run and
  `authorization_error!` is counted.
- Each condition becomes SQL appended to `@query_string`, values as named binds (`@filter_values`):
  conversation columns / additional attributes, `contacts.<column>` / `contacts.additional_attributes`, `messages.*`,
  labels through `tag_filter_query`, custom attributes through `custom_attribute_query`.
- `base_relation` is **one conversation**: `Conversation.where(id: conversation.id)` LEFT JOIN its contact and its
  messages (restricted to the event's message for `message_created`). `records.any?` is the answer.
- `attribute_changed` conditions are checked in Ruby against `changed_attributes`.
- Any exception → logged, `false` (fails closed).

Operators: `equal_to`, `not_equal_to`, `contains`, `does_not_contain`, `is_present`, `is_not_present`,
`is_greater_than`, `is_less_than`, `days_before`, `starts_with`, `attribute_changed` (UI sets `operators.js`
`OPERATOR_TYPES_1..6`).

## 4. Action engine

`AutomationRules::ActionService < ActionService`; `Current.executed_by = rule` while it runs. For each action:
`@conversation.reload`, `send(action_name, params)`, any `StandardError` is captured (`ChatwootExceptionTracker`) and
the next action still runs; no action is retried.

| Action | Implementation | Scope check |
|---|---|---|
| `assign_agent` | conversation `assignee_id` (or none / last responding agent) | agent must be an inbox member or administrator of the account |
| `assign_team`, `remove_assigned_team` | conversation `team_id` | team must be the account's |
| `remove_assigned_agent` | `assignee_id = nil` | — |
| `add_label`, `remove_label` | conversation `label_list` | label names |
| `change_priority` | conversation priority | enum |
| `mute_conversation`, `snooze_conversation`, `open_conversation`, `pending_conversation`, `resolve_conversation`, `change_status` | conversation status | — |
| `send_message`, `add_private_note`, `send_attachment` | `Messages::MessageBuilder` (outgoing / private), channel delivery jobs | channel rules (below) |
| `send_email_to_team` | `TeamNotifications::AutomationNotificationMailer`, account email rate limit | **`Team.where(id:)` is not scoped to the account** |
| `send_email_transcript` | `ConversationReplyMailer`, account email rate limit, `email_transcript_enabled?` | — |
| `send_webhook_event` | `WebhookJob.perform_later(url, conversation.webhook_data + event: "automation_event.<event>")` | — |
| `add_sla` (Enterprise) | `sla_policy_id`, only with the `sla` feature | account's SLA policies |

There is no "set custom attribute" or "send email to address" automation action. Macros use the same `ActionService`.

**Outgoing webhook** (`send_webhook_event` → `WebhookJob` → `Webhooks::Trigger`): `SafeFetch` (`ssrf_filter`:
private / loopback / link-local addresses refused, redirects re-checked; `SAFE_FETCH_ALLOW_PRIVATE_NETWORK` opens it),
POST JSON, timeout `WEBHOOK_TIMEOUT` (default 5 s), no signing secret for automation webhooks, failures logged and
not retried (only agent-bot 429/500 retry).

**Messages and channels**: automation messages go through the normal channel services. WhatsApp
(`Whatsapp::SendOnWhatsappService`): a message without template parameters is sent only inside the 24-hour window
(`conversation.can_reply?`); outside it the message is marked failed with "outside messaging window" and nothing is
sent. Automation has no template parameters, so it can never bypass the window.

## 5. Loop protection, deduplication, retries

- Every change an action makes is dispatched with `performed_by: Current.executed_by` (the rule). The listener
  ignores conversation and message events performed by an `AutomationRule` (`performed_by_automation?`), and
  `message_created` from activity and auto-reply messages. **A rule's actions never trigger rules**: chain depth is
  zero today.
- Auto-reply conversations (`additional_attributes.auto_reply`) do not fire `conversation_created` / `_opened` rules.
- Delayed runs: unique episode key, atomic `claim!`, `executing` rows never replayed, so a delayed action runs once.
- Immediate runs: no per-event deduplication. `EventDispatcherJob` publishes to every listener in one job; Sidekiq
  retries a failed job, and all its listeners run again.

## 6. API, permissions, audit, observability

- `GET/POST /api/v1/accounts/:id/automation_rules`, `GET/PATCH/DELETE …/:id`, `POST …/:id/clone`; all through
  `Current.account.automation_rules` (404 across accounts). `execution_delay` only with `delayed_automations`.
- `AutomationRulePolicy`: **administrators only**, for every action. Feature `automations` (account feature, on by
  default) shows the settings page.
- Audit: Enterprise audit log records rule create / update / destroy (no per-execution audit).
- Observability: `Rails.logger` lines on validation failures and errors; delayed runs keep their row status and
  `skip_reason`; the sweep logs a JSON summary. There is no per-execution log of immediate rules.

## 7. Frontend builder

`settings/automation`: list (`Index.vue`, enable / disable toggle, clone, delete), side panel
`AutomationRuleForm.vue` with a run-type selector (instant / delayed), `AutomationInstantTrigger.vue` (native
`<select>` of `AUTOMATION_RULE_EVENTS`, condition rows with `ConditionRow.vue`), `AutomationWaitCondition.vue`
(delayed triggers), `AutomationActions.vue` (`AUTOMATION_ACTION_TYPES`, one list for every event). Conditions per event
come from `constants.js` `AUTOMATIONS[event].conditions`; `useAutomation.manifestCustomAttributes` appends custom
attributes with disabled group headers; `useEditableAutomation.formatAutomation` turns saved values back into options;
`filterQueryGenerator` turns rows into the saved payload. Strings: `i18n/locale/*/automation.json`.

## 8. Saved filters (Audience), for shared audiences

`CustomFilter` (`custom_filters`: `account_id`, `user_id` NOT NULL, `name`, `filter_type`, `query`): every query is
`Current.account.custom_filters.where(user: Current.user)`; `User has_many :custom_filters, dependent:
:destroy_async`; `CustomFilterPolicy` allows administrators and agents. Lynomia already audits contact filters
(`Custom::Audit::CustomFilter`) and evaluates them with `Contacts::FilterService` + `Custom::Contacts::FilterService`
(Audience Phase 1).

## 9. Commerce events available to Automation

- Provider webhooks are authenticated and deduplicated by each provider's endpoint, then
  `Commerce::Realtime.order_event / cart_event` mark cached orders outdated and schedule `Commerce::RefreshJob`
  (coalesced per link). A webhook only says *this customer changed*; it is never parsed for order state.
- The refresh reads the customer's orders through the provider (`list_customer_orders`, latest 5) into normalized
  `Commerce::Order` hashes and calls `Commerce::ContactMetric.record(link, result)`, which writes the link's summary
  only when the read is newer than the stored one. The same happens when an agent opens the Commerce section, and
  after an order action (`ActionExecutor#refresh_customer`).
- ActionCable `commerce.customer.updated` (ids and a time) tells open panels to refetch.
- **No discrete normalized order event exists** ("order shipped", "order paid"): the only provider-neutral signal is the
  normalized order state of each new read. Carts live in Redis per conversation identity and have no event either.

## 10. Lynomia overrides present before this phase

`custom/` has no automation override. The extension hooks are `AutomationRule.prepend_mod_with('AutomationRule')`
(Custom::AutomationRule would load), `ActionService.include_mod_with('ActionService')`; the listener, the conditions
filter service and the validation service have no hook yet.
