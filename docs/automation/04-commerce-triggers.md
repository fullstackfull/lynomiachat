# Lynomia Automation: Commerce triggers

Chatwoot automation rules run on events (`conversation_created`, `message_created`, …). Lynomia adds seven event names,
`commerce_order_*`, that run through the same dispatcher, listener, conditions and actions. They are never raw provider
webhooks: a provider webhook only says "this customer changed"; the event comes from what Commerce reads and normalizes
afterwards.

## Pipeline

```text
store                    Commerce (existing)                                   Automation (existing + hooks)
─────                    ───────────────────                                   ─────────────────────────────
provider webhook ──► endpoint: signature, tenant, dedup ──► Commerce::Realtime.order_event
                                                              │ cache outdated, RefreshJob (coalesced per link)
agent opens the Commerce section ─┐                           ▼
agent presses Refresh ────────────┼──► provider.list_customer_orders (latest 5, normalized Commerce::Order)
after an order action ────────────┘                           │
                                                              ▼
                             Commerce::ContactMetric.record(link, result)   ← the one write of every new read
                               row lock; ignore reads not newer than the stored one
                               Commerce::OrderTransitions.between(previous order_states, this read)
                               update summary + order_states
                                                              │ after the lock (committed)
                                                              ▼
                             Automation::CommerceEvents.dispatch ──► Rails.configuration.dispatcher
                               only if extensions on, Lynomia Commerce on,      │ EventDispatcherJob (critical)
                               an active rule for one of the events             ▼
                                                              AutomationRuleListener#commerce_order_paid …
                                                                rules of the account for that event
                                                                contact's latest conversation
                                                                run once per rule and event (Redis claim)
                                                                ConditionsFilterService → ActionService
```

The only new state is one jsonb column on the existing summary row, `commerce_contact_metrics.order_states`
(`20261003100100_add_order_states_to_commerce_contact_metrics`): per visible order, a 24-character hash of
`store id:order id` and its normalized status, payment status, shipment statuses and creation time. No order data,
customer data or amounts.

## Events

| Rule event | Emitted when a new read shows, compared with the previous read of the same link |
|---|---|
| `commerce_order_created` | an order not in the previous read and newer than every order of it (not an older order entering the visible window) |
| `commerce_order_updated` | an order of both reads whose status, payment status or shipment statuses changed |
| `commerce_order_paid` | payment status became `paid` |
| `commerce_order_shipped` | status became `shipped` |
| `commerce_order_delivered` | status became `delivered` |
| `commerce_order_cancelled` | status became `cancelled` |
| `commerce_order_refunded` | status became `refunded`, or payment status `refunded` / `partially_refunded` |

A new order emits `created` plus the facts already true of it (a card order: created and paid). An order that moves
several steps between two reads emits each fact that became true (pending → completed between reads: updated and
paid), never the steps it skipped through.

Which platforms produce which facts, from the normalizers:

| | created / updated | paid | shipped | delivered | cancelled | refunded |
|---|---|---|---|---|---|---|
| WooCommerce | yes | processing / completed with a payment date | **no** (core has no shipping state) | **no** | yes | yes |
| Salla | yes | yes | shipped / delivering | delivered | canceled | restored / refunds |
| Zid | yes | yes | indelivery | delivered | yes | yes |
| Shopify | yes | yes | FULFILLED | all fulfillments delivered | yes | yes |

Salla, Zid and Shopify are switched off in production (Commerce production gate): their stores are not read, so they
emit nothing there.

### Not offered

- **Abandoned cart**: carts live in Redis per conversation, have no normalized change event, and are read on demand.
- **Store needs reauthorization / disconnected**: a store state, not a customer order event, with no reliable
  normalized signal across platforms.
- **Customer created / updated**: Commerce does not track store customers as records.
- **Audience entered / left**: deferred, see below.

## When an event is emitted (and when not)

- **It needs a read.** Events come from new reads: realtime webhooks (the WooCommerce webhooks Lynomia registers when
  a store is connected, which needs a key allowed to create them; Salla / Zid / Shopify adapters), an agent opening the
  conversation's Commerce section, the Refresh button (30 s cooldown), and the read after an order action. A change
  nobody reads produces no event until the next read; a store connected with a read-only key gets no deliveries, so its
  events come from agents' reads only.
- **Baseline.** A link's first read after deploy (or ever) has no previous state: it records the baseline and emits
  nothing. So does a link whose summary was dropped (unlinked, relinked).
- **Visible window.** Only the latest 5 orders per store are read, as in the Commerce panel. A change to an older order
  is never seen; an older order appearing because a newer one disappeared is not `created`.
- **Cached and stale reads** carry the time of the read they came from and change nothing: no event.
- **Only when someone listens.** Nothing is dispatched unless the account has an active rule for one of the events, the
  extensions are on and the account has Lynomia Commerce; otherwise the transition is computed and stored only.

## Once per event

- The transition is computed and the row written under the summary row's lock; two reads racing (webhook refresh and
  an agent opening the panel) see each other's result, and an older read never overwrites a newer one. Events are
  dispatched after the lock, so a rule never sees an uncommitted summary.
- Each event has an id, `link id:order key:event:read time`. The listener claims `rule id + event id` in Redis
  (`SET NX`, 7 days) before running a rule: a retried `EventDispatcherJob`, or the same event delivered twice, never runs
  a rule twice. The log records the second delivery as `duplicate`.

## Which conversation

A Commerce event is about a contact, and Chatwoot rules act on a conversation. The rules run on **the contact's latest
conversation in the account** (by last activity), which is also the one an agent is most likely to see. A contact with
no conversation: nothing runs, logged `no_conversation`. Conversation conditions in a Commerce rule (status, inbox,
labels, team, …) are about that conversation.

## Rules on Commerce triggers

- **Actions**: Chatwoot's own, except `send_message` and `send_attachment`. A store event is not a customer message,
  and on WhatsApp the latest conversation may be outside the 24-hour window, where Chatwoot would mark a free-form
  message failed. The builder does not offer them and the API refuses them (`no_customer_message`). Private notes,
  labels, assignment, priority, status, team e-mail, transcript and webhook remain.
- **No delay**: `execution_delay` is refused (`no_delay`); Chatwoot's delayed runs are conversation-status episodes.
- **Conditions**: everything a conversation rule has, plus the Audience and Commerce groups, plus *Order store* and
  *Order store platform* about the event ([03](03-audience-and-commerce-conditions.md)).
- **Lynomia Commerce required**, and the kill switch on ([05](05-runtime-security-and-tenancy.md)).

## Webhook / n8n

The existing *Send Webhook Event* action. On a Commerce trigger the payload is Chatwoot's (the conversation's
`webhook_data`, `event: automation_event.commerce_order_paid`) plus a `commerce` object:

```json
{
  "event": "automation_event.commerce_order_paid",
  "id": 1,
  "...": "the conversation, as every Chatwoot automation webhook",
  "commerce": {
    "event": "commerce_order_paid",
    "store_id": 227,
    "provider": "woocommerce",
    "order": { "number": "23", "status": "processing", "payment_status": "paid", "shipment_statuses": [] }
  }
}
```

No store credential, token, amount or address. n8n (or any receiver) is a URL in the action; delivery goes through
Chatwoot's `WebhookJob` and `SafeFetch` ([05](05-runtime-security-and-tenancy.md)).

## Audience entered / left: deferred

"Contact entered / left audience X" is not implemented in this phase, because it cannot be done cleanly inside the
existing system:

- **There is no membership to compare.** Audiences are evaluated, never stored ([Audience
  02](../audience/02-audience-architecture.md)). An entered / left event needs a stored snapshot per audience and
  contact: the design in [Audience 06 §4](../audience/06-automation-integration-contract.md) is a new
  `audience_memberships` table, a new listener re-evaluating one contact on every change any audience can read
  (contact fields, labels, conversations, Commerce summaries, links, the audience's own conditions), and a batch job
  for time-based conditions ("last purchase before 30 days" crosses midnight without any event). That is a new table,
  listener and job family: what Phase 1 rules out.
- **False events would be worse than none.** Without the batch sweep, time-based audiences would never emit "left";
  with partial hooks, a contact changed through a path that is not watched (imports, console, provider switch-off)
  would silently drift.
- **The supported form today** is the condition: any trigger + *Contact audience is in X* evaluates membership at the
  moment of the event, always current.

Revisit with the Flow Builder ([07](07-future-flow-builder-contract.md)), which needs a contact-level trigger model
anyway.

## Campaigns

Not changed (documentation only). Chatwoot campaigns target labels; using a shared audience as campaign recipients is
specified in [Audience 06 §5](../audience/06-automation-integration-contract.md) (resolve the audience at send time, keep
each channel's eligibility and opt-out, record through `campaign_recipients`). Campaigns resolve contact labels, while
automation actions label conversations, so a rule does not feed a campaign today.

## Files

`custom/app/services/commerce/order_transitions.rb`, `custom/app/models/commerce/contact_metric.rb` (`record`,
`apply`), `custom/app/services/automation/commerce_events.rb`, `custom/app/listeners/custom/automation_rule_listener.rb`
(hook in `app/listeners/automation_rule_listener.rb`), `custom/app/services/custom/automation_rules/action_service.rb`
(webhook context), `custom/app/models/custom/automation_rule.rb` (validation),
`custom/db/migrate/20261003100100_add_order_states_to_commerce_contact_metrics.rb`. Tests:
`spec/services/commerce/order_transitions_spec.rb`, `spec/listeners/automation_rule_listener_commerce_spec.rb`, E2E
[08](08-e2e.md).
