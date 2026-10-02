# Lynomia Automation: contract for a future Flow Builder

No Flow Builder, visual editor or bot builder was built in this phase. This is what one may rely on, so that it is a
new editor over the same rules engine rather than a second engine.

## 1. A flow compiles to Chatwoot automation rules

A visual flow is an editor for `automation_rules` rows (or, for multi-step flows, an ordered set of them), never its own
runtime:

| Flow node | Stored as |
|---|---|
| Trigger | `event_name`: the 5 Chatwoot events, the 7 `commerce_order_*` events ([04](04-commerce-triggers.md)) |
| Condition / branch | `conditions`: Chatwoot keys, `contact_audience`, `commerce_*`, `commerce_event_*` ([03](03-audience-and-commerce-conditions.md)); AND / OR chain |
| Action | `actions`: Chatwoot's action names and params; no Lynomia action names |
| Wait | `execution_delay` (Chatwoot delayed runs, conversation-status episodes only; not on Commerce triggers) |
| Webhook / n8n | `send_webhook_event` with a URL |

A branch "if A then X else Y" is two rules on the same trigger with complementary conditions (`contact_audience
equal_to` / `not_equal_to`). The editor shows them as one diagram; the engine sees rules.

## 2. Stable today

- **Rule JSON**: `{ name, description, event_name, conditions: [{ attribute_key, filter_operator, values,
  query_operator, custom_attribute_type }], actions: [{ action_name, action_params }], active, execution_delay }`
  through `/api/v1/accounts/:id/automation_rules` (administrators).
- **Condition keys and operators** in the tables of [03](03-audience-and-commerce-conditions.md); audience values are
  shared audience ids, store values store ids, platform values the Commerce provider keys.
- **Event names** and their meaning in [04](04-commerce-triggers.md), including what is not emitted.
- **Webhook payload**: Chatwoot's conversation payload plus `commerce: { event, store_id, provider, order: { number,
  status, payment_status, shipment_statuses } }` on Commerce triggers.
- **Validation messages** (`automation.lynomia.*`) as 422 errors on `conditions`, `actions`, `event_name`,
  `execution_delay`.
- **Execution log line** fields ([05](05-runtime-security-and-tenancy.md)) for a run history view.

## 3. What a Flow Builder would need that does not exist yet

| Need | Today | Direction |
|---|---|---|
| Run history per rule in the UI | log lines only | read the structured log, or persist a capped `automation_rule_runs` (rule, event id, outcome, duration) when a history screen is built |
| Multi-step flows with state ("wait for reply, then…") | delayed runs are conversation-status episodes only | extend `AutomationRulePendingExecution` (episode, due time, re-check) rather than a new scheduler |
| Contact-level triggers (audience entered / left, contact created) | none | membership snapshots for watched audiences only ([Audience 06 §4](../audience/06-automation-integration-contract.md)), dispatched through the same dispatcher |
| Acting without a conversation | rules act on one conversation | contact-level actions (labels on the contact, custom attributes) as Chatwoot actions, or an explicit "conversation selector" on Commerce rules |
| Customer messages from Commerce events | refused | only templates on WhatsApp (outside 24 h), with template parameters the rule supplies; per-channel eligibility and opt-out first |
| Abandoned cart, store health triggers | not emitted | a normalized cart change event in Commerce first, then a trigger |
| Versioning / drafts of flows | rules are live rows | a draft copy that becomes the rule on publish, audited like rules |

## 4. Not allowed by this contract

- a second rules table, condition language or action registry;
- copying an audience's conditions into a rule (rules hold audience ids, so an audience edit applies everywhere);
- calling a store from a condition (conditions read Lynomia's tables only);
- an action that changes a store order (refund, cancel, status) from automation: Commerce order actions stay
  agent-confirmed ([Commerce 28–34](../commerce/));
- bypassing the WhatsApp 24-hour window or opt-out.

## 5. Out of scope here

Visual Bot Builder, CRM, SLA and AI features are separate phases and were not started.
