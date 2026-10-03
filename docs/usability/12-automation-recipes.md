# Automation recipes

Seven recipes. Each creates a **normal Chatwoot automation rule**, through the ordinary call, **switched off**.
Architecture in [10](10-recipe-architecture.md); why these seven in [09a](09a-recipe-opportunity-study.md) §4.2.

## 1. What they may contain

Only what the engine has, verified in the repository rather than assumed:

- **Triggers**: Chatwoot's own, plus the seven Lynomia Commerce triggers of
  `Commerce::OrderTransitions::EVENTS` — `commerce_order_created | updated | paid | shipped | delivered |
  cancelled | refunded`.
- **Conditions**: Chatwoot's `conditions_attributes`, plus what `Custom::AutomationRule#conditions_attributes` adds:
  `contact_audience` (**shared** audiences only), the Commerce contact fields, and — on a Commerce trigger only —
  `commerce_event_store` and `commerce_event_provider`.
- **Actions**: the eighteen in `AutomationRule#actions_attributes`.
- **Shapes**: `add_label` takes label **titles**; `assign_team` takes `[team_id]`; `change_priority` takes
  `[priority]`; `send_webhook_event` takes `[url]`.
- **Query operators**: at most one condition may carry a null operator (`query_operator_presence`), so the last one
  is null and the rest are `and`.

## 2. The seven

| id | Name | Trigger → conditions → actions | Needs | Asks for |
|---|---|---|---|---|
| `commerce_new_order_routing` | New order goes to a team | `commerce_order_created`, store → add label?, assign team | Commerce, a store, a team | store, team, labels? |
| `commerce_order_shipped_label` | Label a shipped order | `commerce_order_shipped`, store → add label | Commerce, a store, a label | store, labels |
| `commerce_refund_escalation` | Refund gets escalated | `commerce_order_refunded`, store → priority High, assign team, add label? | Commerce, a store, a team | store, team, labels? |
| `commerce_event_webhook` | Send an order event to another system | the chosen event, store → send webhook | Commerce, a store, API and webhooks | event, store, url |
| `vip_audience_priority` | Audience gets priority | `conversation_created`, `contact_audience` is in X → priority, assign team, add label? | a shared audience, a team | audience, team, priority, labels? |
| `high_value_spend_routing` | High-value customer routing | `conversation_created`, `commerce_spend_<ccy>` > N → add label?, assign team | Commerce, a currency seen, a team | currency, amount, team, labels? |
| `active_order_routing` | Customer with an open order | `conversation_created`, `commerce_active_order` = true → add label?, assign team | Commerce, a team | team, labels? |

A label nobody chose adds **no action at all**, rather than an action with an empty parameter list.

## 3. Why the Commerce recipes ask which store

`commerce_event_store` is a real condition about the event being handled, not about the contact — and it is the
condition that makes a multi-store account able to route each store differently. A single-store account has it
filled in by the wizard and never sees the question as a decision.

It also means every recipe produces **at least one condition**. A rule with none is a path the product's own UI never
produces (`getDefaultConditions` always returns one), so the recipes do not produce it either.

## 4. Two of the brief's examples are absent, on purpose

| Asked for | Why not |
|---|---|
| "Order shipped → message the customer" | `Custom::AutomationRule::CUSTOMER_MESSAGE_ACTIONS` withholds `send_message` and `send_attachment` from every Commerce trigger: a store event is not a customer message, and the conversation may be outside WhatsApp's 24-hour window. The engine refuses it, so the catalogue does not pretend |
| "Commerce order issue routing" | There is no "issue" event. The seven transitions are the whole set, so this became `commerce_refund_escalation` and `active_order_routing`, built on events that exist |

Both are recorded in [09a](09a-recipe-opportunity-study.md) §7 rather than quietly dropped.

## 5. Safe default state, and review

```text
Recipes → Use this → values → Create
  → POST /automation_rules  { …, active: false }
  → the created rule opens in the edit panel
  → the user reads it, changes it, and turns it on with the existing toggle and its existing confirmation
```

The description reads `Created from the <name> recipe (v1).` — ordinary editable text, which nothing at runtime
reads.

## 6. How they are checked

`recipes/specs/automationRecipes.spec.js` (18 assertions) transcribes the controller's permitted condition and action
keys, the model's condition and action vocabulary, the query-operator rule and the Commerce-trigger restrictions,
and runs every recipe against them — including that none sends a customer message on a Commerce trigger, none asks
for a delay, the event-store condition appears only on a Commerce trigger, and the `requires` list matches what the
built rule actually uses.

`routes/dashboard/settings/automation/specs/Index.spec.js` (6 assertions) covers the page: the empty state, the exact
payload sent for a recipe, that it carries `active: false` and the provenance description, that a refused create
reports and stays, and that the audience query is dropped after it is read.
