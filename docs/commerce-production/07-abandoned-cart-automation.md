# 07 — Automation, targeting, and the recipe that is not shipped

---

## 1. One Automation event, in the existing registry

`commerce_cart_abandoned`, added to `Automation::CommerceEvents::CART_EVENTS` and therefore to `EVENTS`, which is
what `Custom::AutomationRule#event_names` offers and what `Custom::AutomationRuleListener` defines a method for.
No second engine, no new dispatcher, no new trigger registry — conditions, actions, execution logging and the
once-per-rule claim all stay where they already are.

It dispatches on **a genuine transition into `abandoned`, once per cart lifecycle**:

| Case | Dispatch? |
|---|---|
| First `abandoned_cart.created` for a cart | **yes** |
| The same delivery again, or any later duplicate | **no** — the lifecycle returns `no_change` and `dispatch` is never called |
| `abandoned_cart.completed` | **no** |
| A cart whose customer is not linked to a contact | **no** — there is nobody to act on, and the row still records the lifecycle |

The payload carries the contact, the store, the provider and a small cart context: `id`, `provider_cart_id`,
`phase`, `currency`, `total`, `item_count`, `abandoned_at`. **No checkout URL and no customer contact details** —
the conversation payload already carries the contact. A regression pins that key list exactly.

### `commerce_cart_recovered` was not added

Deliberately, and this is the condition-2 line. `abandoned_cart.completed` proves checkout completion, not that
Lynomia caused it — and Zid's own schema carries `reminders_count` and a `whatsapp_message`, so the store may be
reminding the shopper itself. A trigger called "recovered" would invite a rule that reports a recovery nobody can
stand behind. It becomes addable the moment a real store settles that confound.

## 2. `targeted_at`: the one moment it is set

It means exactly one thing: **a real Lynomia abandoned-cart outreach was successfully accepted for sending.**

The existing pipeline already has that moment, and it is not a new one. `Commerce::RecoveryMessages` prepares a
recovery message into the agent's reply box and records a pending `Commerce::ActionRun`;
`Commerce::RecoveryListener` marks it `succeeded` when a **confirmed outgoing, non-private message carrying the
prepared link** appears in the conversation within 24 hours. That confirmation is where `targeted_at` is written.

| Not set by | Why |
|---|---|
| a rule matching | nothing was sent |
| a job being enqueued | nothing was sent |
| a template being chosen | nothing was sent |
| a send that failed or was refused | nothing was sent |
| a private note containing the link | not an outreach to the customer |
| an outgoing message without the prepared link | not this outreach |

### Concurrency

One atomic conditional UPDATE, guarded on `targeted_at IS NULL`:

```ruby
Commerce::Cart.where(commerce_store_id: …, provider_cart_id: …, targeted_at: nil)
              .update_all(targeted_at: sent_at, updated_at: Time.current)
```

Two workers confirming near-simultaneous sends set it **once**, and the first send wins. This is deliberately not
`if targeted_at.blank? … end`, which two workers can interleave, and it is not a new lock system — a single
statement needs none. A regression drives two confirmations and asserts the first timestamp survives, and another
pins that the claim is one conditional statement rather than a read-then-write.

## 3. The WhatsApp recipe is NOT shipped — and why

Condition 5 permitted a disabled Zid recipe **only if the existing Automation/WhatsApp action path can safely send
an approved template.** It cannot, for two independent reasons found in the existing code:

**(a) There is no template-send action.** `AutomationRules::ActionService` implements exactly five customer-facing
or notification actions: `send_message`, `send_attachment`, `send_webhook_event`, `add_private_note`,
`send_email_to_team`. `send_message` is free-form text. Nothing sends an approved WhatsApp template.

**(b) Commerce triggers forbid customer messages, by design.**

```ruby
CUSTOMER_MESSAGE_ACTIONS = %w[send_message send_attachment].freeze
…
errors.add(:actions, I18n.t('automation.lynomia.no_customer_message', …)) if messages.any?
```

and the reason is recorded in the same file: *"a store event is not a customer message, and a WhatsApp
conversation may be outside its 24-hour window."* That rule is correct and P5's architecture depends on it.

So shipping a recipe would mean either a free-form `send_message` — forbidden by P5 and by this phase's own
constraints — or a fake action. The brief's instruction for exactly this case is *"do not fake it… or defer that
recipe"*, and it is deferred.

### What the smallest honest future addition looks like

Recorded as a proposal for a later phase, not built here:

1. a `send_whatsapp_template` action in the **existing** `AutomationRules::ActionService`, delegating to the
   existing WhatsApp sender and the existing Template Manager sendability check;
2. that action exempted from `CUSTOMER_MESSAGE_ACTIONS` **because** a template is precisely what is permitted
   outside the 24-hour window — the ban exists to stop free-form sends, not approved templates;
3. only then a Zid recipe, shipped disabled, with the prerequisites in §4.

Until then, `commerce_cart_abandoned` is still useful with the actions that do exist: label the conversation,
assign it, notify the team, or call a webhook.

### The consequence for `targeted_at`, stated plainly

Because the automated path does not exist, the **only** writer of `targeted_at` in this phase is the
agent-confirmed recovery message of §2. That is a real outreach and a truthful signal, but it is agent-initiated.
There is no automated targeting in P6, so "targeted" currently means "an agent sent the prepared recovery
message".

## 4. The targeting path, and the prerequisites a recipe would have to show

```
abandoned_cart.created (Zid)
  → existing endpoint, Basic Auth                  02
  → normalize + durable upsert                     06
  → transition into ABANDONED
  → commerce_cart_abandoned                        07 §1
  → existing AutomationRule
  → [NOT BUILT: approved-template action]          07 §3
  → existing WhatsApp sender
  → targeted_at                                    07 §2
```

Prerequisites that would be shown to a user before such a recipe could be enabled, none of which this phase
invents:

| Prerequisite | Existing check |
|---|---|
| Zid connected and active | `Commerce::Store#active?` |
| Cart events supported and cleared for use | `Commerce::AbandonedCarts.offered?` — still PRE_UAT |
| An approved WhatsApp template exists | the existing Template Manager |
| A valid WhatsApp inbox and WABA | the existing sender; the template must belong to that inbox's WABA |
| The customer has a usable WhatsApp identity | the cart's resolved `contact_id`; an unlinked cart cannot be targeted |

No free-form fallback exists anywhere in this path, and none was added.

## 5. Template variables the state could resolve safely

Customer name, store name, cart value, item count — all from the row or the contact.

**The checkout link is not among them from storage.** Zid does supply a durable checkout `url`, but the row does
not keep it: see `08` §2 for the security decision and the existing digest pattern that replaces it.
