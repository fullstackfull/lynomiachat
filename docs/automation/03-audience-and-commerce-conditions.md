# Lynomia Automation: audience and Commerce conditions

Chatwoot automation conditions are rows of `{ attribute_key, filter_operator, values, query_operator }`, turned into
one SQL statement over the event's conversation (LEFT JOIN its contact and messages) by
`AutomationRules::ConditionsFilterService`. Lynomia adds condition keys to that same chain, through
`Custom::AutomationRules::ConditionsFilterService#apply_filter` (prepended). There is no second condition language:
the new keys use Chatwoot's operator names, AND / OR and the order of the rows exactly like the existing keys.

## Keys

| Group in the builder | Key | Operators | Values | Meaning, for the event's contact |
|---|---|---|---|---|
| Audience | `contact_audience` | `equal_to` "Is in", `not_equal_to` "Is not in" | shared audience ids of the account | the contact matches (does not match) any of the audiences |
| Commerce | `commerce_store` | equal / not equal / present / not present | store ids of the account | the contact has (no) counted link to these stores |
| Commerce | `commerce_provider` | equal / not equal | platform keys | the contact has (no) counted link on these platforms |
| Commerce | `commerce_orders_count` | equal / greater / less | integer | visible orders |
| Commerce | `commerce_spend_<currency>` (`commerce_spend_sar`, …) | greater / less | amount | visible paid spend in that currency, never converted |
| Commerce | `commerce_last_purchase_at` | greater / less / days before | date / days | last visible purchase |
| Commerce | `commerce_active_order` | equal | true / false | an order not yet completed, cancelled or refunded |
| Commerce | `commerce_order_status`, `commerce_payment_status`, `commerce_shipment_status` | equal / not equal | normalized statuses | a visible order with (none with) this status |
| Commerce (Commerce triggers only) | `commerce_event_store` | equal / not equal | store ids of the account | the store of the order event being handled |
| Commerce (Commerce triggers only) | `commerce_event_provider` | equal / not equal | platform keys | the platform of the order event being handled |

The Commerce keys are the Audience fields ([Audience 03](../audience/03-commerce-query-model.md)) through the same class,
`Audience::CommerceCondition`, so a rule and an audience never disagree about a contact.

## How each is evaluated

`Automation::LynomiaCondition#to_sql` returns one SQL expression and its binds; the filter service wraps it in
parentheses and joins it with the row's `query_operator`, like any other row:

- **Commerce fields**: the Audience SQL over `commerce_customer_links` and `commerce_contact_metrics`, correlated to
  the rule's `contacts.id`. One indexed lookup per field for the event's one contact.
- **Audience membership**: the shared audience's saved filter is run as its own query restricted to the contact
  (`Contacts::FilterService#relation.exists?(id: contact_id)`, a primary-key lookup), as the account (conversation
  conditions of the audience see every conversation of the account, like the account's rules do). The answer enters the
  rule's SQL as a bound `true` / `false`: the audience's SQL is never pasted into the rule's, so a rule never inherits
  its joins and the two stay separately explainable ([06](06-performance.md)). Several audience ids in one row: "is in"
  any of them.
- **Event store / platform**: a bound `true` / `false` from the Commerce event being handled
  ([04](04-commerce-triggers.md)): "WHEN order shipped IF platform = Salla" is about that order, not about any link the
  contact happens to have. On any other trigger there is no event: `FALSE`.

Only the current contact is ever evaluated: no audience is materialised, listed or counted when a rule runs. No
condition calls a store: everything reads Lynomia's own tables (0 HTTP, measured in [06](06-performance.md)).

## Unknown is not zero

The Audience semantics hold unchanged: a link whose orders Lynomia has never read has no summary and is **unknown**.

- Conditions that can only grow with more data ("spend greater than", "has an order with status shipped", "last
  purchase after") match when the known summaries prove them.
- Conditions that more data could falsify ("fewer than 2 orders", "spend less than 100", "no order with status
  cancelled") match only when every counted link of the contact is known. An unread contact never satisfies "has no
  orders".
- Counts and spend are of the **visible** orders (the latest 5 per store that Commerce reads), never lifetime totals,
  and spend is per currency.
- A store that is inactive, or of a platform the installation does not offer (Salla / Zid / Shopify while they are
  switched off in production), counts for nothing.

## Validation (save time)

`Custom::AutomationRule` (prepended to `AutomationRule`) adds the Lynomia keys to `conditions_attributes` and checks
each Lynomia row; the errors are Chatwoot's usual 422 with the rule's messages (`automation.lynomia.*`, en / ar):

| Refused | Message key |
|---|---|
| a key's operator not in its list | `invalid_operator` |
| malformed values, more than 50 values, a non-numeric id, an unknown platform, a value the Commerce SQL refuses | `invalid_values` |
| an audience id that is personal, deleted or of another account | `audience_not_shared` |
| a store id of another account (`commerce_store`, `commerce_event_store`) | `invalid_store` |
| a Commerce key without Lynomia Commerce on the account | `commerce_disabled` |
| more than 10 Lynomia conditions in one rule | `too_many_conditions` |
| `commerce_event_*` on a conversation or message trigger | `event_condition_without_trigger` |
| any Lynomia condition while the kill switch is off | `extensions_disabled` |

At run time `Custom::AutomationRules::ConditionValidationService` accepts the keys with their operators (so Chatwoot's
`Reauthorizable` counter is not triggered by them), and `to_sql` decides whether they may run now: switch off, or
Commerce disabled for the account → `FALSE` (the rule does not match). An audience deleted behind a rule's back →
the evaluation raises, Chatwoot's filter service logs it and returns false: fail closed.

## Rule builder

Settings → Automation → Add rule (Chatwoot's side panel) lists, for every trigger, the existing condition fields, then
an **Audience** group (*Contact audience*, "Is in" / "Is not in", only shared audiences offered), then, with Lynomia
Commerce, a **Commerce** group (the Audience Commerce fields with their names and options; on Commerce triggers also
*Order store* and *Order store platform*). Groups are Chatwoot's disabled header rows, as for custom attributes.
Values are the same multi-select / input components as every other condition.

Code: `app/javascript/dashboard/routes/dashboard/settings/automation/lynomiaAutomation.js` (`manifest`,
`conditionOptions`), hooked into `useAutomation.js` (`manifestLynomiaConditions`, `loadLynomiaOptions`),
`useAutomationValues.js`, `AddAutomationRule.vue`, `EditAutomationRule.vue`, `AutomationRuleForm.vue`.

## Examples

```json
[
  { "attribute_key": "contact_audience", "filter_operator": "equal_to", "values": [12], "query_operator": "and" },
  { "attribute_key": "commerce_spend_sar", "filter_operator": "is_greater_than", "values": ["1000"], "query_operator": "and" },
  { "attribute_key": "status", "filter_operator": "equal_to", "values": ["open"], "query_operator": null }
]
```

"Contact is in *VIP buyers* AND visible spend (SAR) > 1000 AND the conversation is open": three expressions in one
statement over the event's conversation.

## Tests

`spec/services/automation_rules/conditions_filter_service_audience_spec.rb` (in / not in, AND / OR with existing rows,
edits apply at once, conversation conditions over the account, only the event's contact and no outside call, personal /
foreign / unknown audiences refused, an unshared audience never matches, label through the listener, kill switch),
`conditions_filter_service_commerce_spec.rb` (links, per-currency spend and unknown ≠ zero, dates and statuses, combined
chain without store calls, foreign stores and bad values refused, Commerce switched off),
`spec/listeners/automation_rule_listener_commerce_spec.rb` (event conditions, validation), E2E [08](08-e2e.md).
