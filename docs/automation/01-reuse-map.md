# Lynomia Automation: reuse map

Decision, from [00](00-existing-system-discovery.md): **Lynomia Automation is Chatwoot's Automation Rules**, extended
through the overlay hooks Chatwoot already uses (`prepend_mod_with`). Rules stay rows of `automation_rules`, run by
`AutomationRuleListener`, matched by `AutomationRules::ConditionsFilterService` and acted on by
`AutomationRules::ActionService`. Lynomia adds condition keys, trigger event names, one dispatch point for normalized
Commerce events, and a `shared` flag on saved contact filters.

## Matrix

| Capability | Existing | Classification | What Lynomia does |
|---|---|---|---|
| Rule persistence | `automation_rules` (conditions / actions jsonb) | **REUSE** | rules store new keys and audience ids in the same jsonb; no new table |
| Triggers | 5 conversation / message events, `AutomationRuleListener` | **EXTEND** | `commerce_order_*` event names, handled by a prepended listener module |
| Condition engine | `ConditionsFilterService` (SQL on the event's conversation + contact) | **EXTEND** | audience and Commerce keys appended to the same SQL chain, through a prepended module |
| Condition validation | `ConditionValidationService`, `AutomationRule#json_conditions_format` | **EXTEND** | accepts the new keys with their operators; rejects foreign and personal audiences, foreign stores |
| Operators | `equal_to`, `not_equal_to`, `is_present`, `is_greater_than`, `is_less_than`, `days_before`, … | **REUSE** | the same operator names; "is in / is not in" audience = `equal_to` / `not_equal_to` |
| Commerce condition SQL | `Audience::CommerceCondition` (Audience Phase 1) | **REUSE** | the same class and semantics (unknown ≠ zero, counted links, per currency) |
| Audience evaluation | `CustomFilter` + `Contacts::FilterService` | **REUSE** | evaluated for the event's contact only (`contacts.id = :id`) |
| Shared audiences | `CustomFilter` per user only | **EXTEND** | `shared` flag on the same table; shared filters belong to the account, survive their creator |
| Actions | `ActionService` / `AutomationRules::ActionService` | **REUSE** | no new action; Commerce triggers offer the existing non-messaging actions |
| Event bus | `Dispatcher` → `EventDispatcherJob` → Wisper listeners | **REUSE** | Commerce events dispatched through it |
| Normalized Commerce events | none (webhooks are "customer changed" signals) | **NOT PRESENT** → derived | transitions computed where a new normalized read is recorded (`Commerce::ContactMetric.record`); one extra column of per-order state fingerprints on the same table |
| Jobs | `EventDispatcherJob`, `Commerce::RefreshJob`, `WebhookJob`, delayed-run jobs | **REUSE** | no new job class |
| Outgoing webhooks / n8n | `send_webhook_event` → `WebhookJob` → `SafeFetch` | **REUSE** + **EXTEND** | same action; for Commerce triggers the payload also carries the normalized Commerce event (ids, statuses, order number) |
| Messages | `send_message`, `send_attachment`, channel services, WhatsApp 24 h window | **REUSE** | unchanged on conversation triggers; not offered on Commerce triggers (a store event is not a customer message) |
| Labels, teams, agents, priorities, status | `ActionService` | **REUSE** | — |
| `send_email_to_team` | `Team.where(id:)` unscoped | **PATCH** | team lookup scoped to the account |
| Custom attribute actions | none | **NOT PRESENT** | not created |
| Task / follow-up model | none | **NOT PRESENT** | not created |
| Permissions | `AutomationRulePolicy` (administrators), `CustomFilterPolicy` | **REUSE** / **EXTEND** | shared audiences managed by administrators; no new permission flag |
| Audit | Enterprise audit on rules; Lynomia audit on contact filters | **REUSE** | `shared` changes appear in the existing audience audit |
| Retries | per-action rescue, no retry; webhook no retry; Sidekiq job retry | **REUSE** + **PATCH** | per-event, per-rule run key for Commerce triggers so a job retry never repeats a rule |
| Loop protection | `performed_by: AutomationRule` events ignored | **REUSE** | Commerce events are never caused by an action; chain depth stays bounded |
| Deduplication | delayed runs only | **PATCH** | Commerce transitions emitted once per recorded read; rule run key per event |
| Execution observability | log lines, delayed-run rows | **PATCH** | one structured log line per Lynomia evaluation (rule, trigger, matched / skipped, duration, correlation id; no PII) |
| Kill switch | none | **NOT PRESENT** → added | `LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED` turns off only the Lynomia triggers and conditions |
| Realtime UI updates | ActionCable | **REUSE** | — |
| Rule builder UI | `AutomationRuleForm`, `ConditionRow`, constants | **EXTEND** | grouped triggers, Audience and Commerce condition groups, Commerce-safe action list |
| Campaigns | labels only | not changed | future: audience as recipients (06 of Audience) |

## Deliberately not created

- no automation engine, runtime, table, DSL, action framework, event bus, job system or standalone UI;
- no Audience model, table or membership table; no copy of audience conditions into rules;
- no orders table: the new column keeps, per visible order, a hashed id and its normalized statuses only;
- no Commerce destructive action (refund, cancel, status change, coupon, customer change) and no `lyn_*` copy of an
  existing action;
- no `N8nAction`: n8n is a URL for the existing webhook action;
- no abandoned-cart or store-reauthorization trigger: Commerce has no reliable normalized event for them;
- no Visual Flow Builder (contract only, [07](07-future-flow-builder-contract.md)).
