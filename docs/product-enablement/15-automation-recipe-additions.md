# Automation recipe additions

Phase P2, Part D. Four recipes, taking the catalogue from seven to eleven.

---

## 1. The vocabulary these are built from

Twelve triggers: five OSS conversation events plus the seven `commerce_order_*` transitions
(`app/models/automation_rule.rb` `event_names`, extended by `custom/app/models/custom/automation_rule.rb`).
Twenty actions, of which `send_message` and `send_attachment` are **withheld on every commerce trigger**, server-side
and client-side — a store event is not a customer message, and the conversation may be outside WhatsApp's 24-hour
window.

Every recipe's `build` returns `{ event_name, conditions, actions, active: false }`. The rule is created **disabled**:
nothing runs until somebody reads it and turns it on.

## 2. The four

| id | Trigger | What it does | Why it was missing |
|---|---|---|---|
| `greet_new_conversation` | `conversation_created` | replies at once, in the chosen language | the catalogue had **no recipe an account could use on its first day** — every one needed a store, a team, an audience or a label |
| `audience_conversation_label` | `conversation_created` + `contact_audience` | labels the conversation of anyone in a shared audience | the bridge from a described group to a durable, countable one |
| `commerce_order_paid_priority` | `commerce_order_paid` | labels and raises priority | `paid` was the one widely-reported commerce event no recipe used |
| `commerce_order_cancelled_followup` | `commerce_order_cancelled` | labels, assigns a team, leaves a private note asking why | a cancellation is the highest-value follow-up in retail, and the note keeps it a *private* note |

`greet_new_conversation` is the one with no requirements at all, which changes what the gallery looks like for a new
account: it used to be entirely "requires setup".

## 3. Two details that are easy to get wrong

**A new conversation is not always `open`.** On an inbox a bot answers first it starts `pending`. So the
"when a conversation starts" condition is `status equal_to ['open', 'pending']`, which is what makes the greeting
behave the same on every inbox. A rule with no conditions at all would save (`json_conditions_format` returns early
when `conditions.blank?`) but its runtime behaviour is not something a catalogue should rely on.

**A commerce trigger may not message the customer.** `commerce_order_cancelled_followup` therefore uses
`add_private_note`, never `send_message`. The note's wording lives in the recipe source in both languages, because
`build` is pure and has no translator, and the text is stored on the rule as a literal string the author then edits.

## 4. What was not added

- **No per-event label recipe for `shipped`, `delivered`, `updated`.** `commerce_order_shipped_label` already covers
  "label on an event", and `commerce_event_webhook` covers "any event to a webhook". A fourth near-duplicate is
  catalogue noise. `delivered` is also reported by only two of the four platforms
  (`16-commerce-aware-starters.md`).
- **Nothing delayed.** `execution_delay` is permitted only with the `delayed_automations` feature, only on three
  trigger shapes, and never on a commerce trigger. A recipe that needs it would read as ready on accounts where it
  is not.
- **No label-triggered routing.** A `labels` condition on `conversation_created` can never match: a brand-new
  conversation has no labels yet.

## 5. Classification

EXTEND. Same catalogue, same `build` contract, same ordinary `automation_rules` create call, same server-side
validation — including Lynomia's own checks that an audience is a shared one of this account and a store is this
account's.
