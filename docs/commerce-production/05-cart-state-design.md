# 05 — Durable cart state: proposed design

**STATUS: PROPOSAL. NOT IMPLEMENTED. NO MIGRATION HAS BEEN WRITTEN.**

This is the one additive migration B2 authorises, put up for approval before anything is created. Zid only — `04`
§4 rejects the other three with reasons.

---

## 1. Why existing structures cannot carry this

| Candidate | Why it cannot |
|---|---|
| `Commerce::AbandonedCart` | a `Data.define` value object in Redis, 120 s fresh / 24 h stale. Its own header says "never in Postgres". A cart that the provider stops listing ceases to exist with no terminal state recorded |
| `commerce_contact_metrics` | order rollups per contact: `orders_count`, `spend`, `order_statuses`. No per-cart row exists or could, and a cart is not a contact-level aggregate |
| `commerce_action_runs` | already holds the single durable cart trace — a `recovery_message` run keyed by the provider cart id. But it records *an attempt Lynomia made*, not *a state the cart is in*, it is swept at 90 days, and overloading it would make "did we message" and "is it abandoned" the same row |
| Redis alone | the specific thing that breaks it: `abandoned_cart.completed` can arrive after the 24-hour cache horizon, and with the cart gone from Redis there is no previous state to transition *from*. Completion would be unattributable |

The precedent for doing this properly already exists in the codebase: `Commerce::OrderTransitions` diffs previous
against current order state and **persists** the result. Carts need the same treatment, and nothing more.

## 2. Proposed table — `commerce_carts`

Every candidate field from the brief was tested against the **proven** Zid contract. Columns that nothing in that
contract supports are listed in §9 as rejected, not carried "just in case".

| Column | Type | Null | From | Why |
|---|---|---|---|---|
| `account_id` | bigint FK | no | — | tenant scope, mirroring `commerce_customer_links` |
| `commerce_store_id` | bigint FK | no | — | the store that owns the cart |
| `provider` | string | no | — | denormalised for querying and for the uniqueness story in §3; `commerce_stores` does the same |
| `provider_cart_id` | string | no | Zid `id` | the identity. See §3 on the `id` / `cart_id` ambiguity |
| `contact_id` | bigint FK, nullify | **yes** | resolved | nullable on purpose: a cart may arrive before its customer can be matched, and must still be recorded |
| `commerce_customer_link_id` | bigint FK, nullify | yes | resolved | the link that resolved it, so a suppressed link can be traced |
| `external_customer_id` | string, **encrypted deterministic** | yes | `customer_id` | matches `commerce_customer_links`' existing treatment exactly |
| `state` | integer enum | no | derived | §4 — three values only |
| `provider_phase` | string | yes | `phase` | Zid's own funnel position, kept verbatim and never interpreted as state |
| `currency` | string | yes | `currency_code` | the field exists in the contract |
| `visible_total` | decimal(15,2) | yes | `cart_total` | "visible" because it is what the provider showed the shopper, not an authoritative price |
| `item_count` | integer | yes | `products_count` | the contract supplies the count directly, so the line items need not be stored at all |
| `first_seen_at` | datetime | no | — | when Lynomia first recorded it |
| `last_provider_event_at` | datetime | no | — | the provider's own timestamp from the last event. §5 depends on this being distinct from Lynomia's clock |
| `abandoned_at` | datetime | yes | `created_at` | Zid's abandonment time, not ours |
| `completed_at` | datetime | yes | `updated_at` on completion | when the provider said completed |
| `provider_order_id` | string | yes | `order_id` | §7 |
| `targeted_at` | datetime | yes | — | when an Automation actually sent for this cart. This is the single field that separates *recovered* from merely *completed* |
| `created_at` / `updated_at` | datetime | no | — | Rails |

Seventeen columns plus timestamps. No `checkout_url` — see §9.

## 3. Identity and uniqueness

**Proposed:** `UNIQUE (commerce_store_id, provider_cart_id)`, plus `index (account_id, state)` for the batch
sweep and `index (contact_id)` for the panel.

`commerce_store_id` alone is sufficient for isolation and is strictly stronger than `(account_id, provider,
provider_cart_id)`, because a store belongs to exactly one account and one provider — `commerce_stores` carries a
global unique index on `(provider, external_store_id)`. This is the same shape `commerce_customer_links` already
uses, which keeps one convention rather than two.

The three collisions it must prevent, and why it does:

| Collision | Prevented because |
|---|---|
| Account A and Account B, same `provider_cart_id` | different `commerce_store_id` → two rows, and neither can see the other through `account_id` scoping |
| Store A and Store B in one account, same id | different `commerce_store_id` |
| Zid and Shopify, same id string | different store, and `provider` is on the row for querying |

**One thing to verify before writing this.** Zid's schema carries `id`, **`cart_id`** and **`session_id`**, and
the documentation does not say which is stable across a cart's life. `provider_cart_id` is proposed to hold `id`
because `id` is what the detail endpoint is addressed by — but if `cart_id` turns out to be the durable identity
and `id` a per-row surrogate, the unique index would be on the wrong column and completion events would create
duplicate rows instead of transitioning existing ones. **This is a real-UAT question and a blocker on writing the
migration**, not a detail to settle by assumption.

## 4. The state machine — three states, not six

The previous brief listed six example transitions. Only what Zid's events can establish is proposed:

```
   abandoned_cart.created            abandoned_cart.completed
            │                                   │
            ▼                                   ▼
      ┌───────────┐                       ┌───────────┐
      │ ABANDONED │ ────────────────────► │ COMPLETED │
      └───────────┘                       └───────────┘
            │
            │  no event for MAX_AGE
            ▼
      ┌───────────┐
      │  EXPIRED  │   (local bookkeeping only, never reported as a provider fact)
      └───────────┘
```

**There is no ACTIVE state**, and that is the key simplification. Zid does not tell Lynomia about a live cart — the
first thing it ever says is "this one is abandoned". Modelling ACTIVE would mean inventing a state no event can
establish.

### What `abandoned_cart.completed` actually means — and what it does not

The published contract supports exactly this: **the cart reached `phase: completed`, and may carry an
`order_id`.** It proves *checkout completion*. It does **not**, on its own, prove recovery.

So the state is named `COMPLETED`, not `RECOVERED`, and recovery is a **derived** reading of two facts:

| Reading | Condition | Honest label |
|---|---|---|
| Completed | `state == completed` | "the shopper finished this cart" |
| **Recovered** | `completed_at.present? && targeted_at.present? && completed_at > targeted_at` | "we messaged, then they finished" |
| Converted | `completed_at.present? && targeted_at.nil?` | "they finished on their own" |

`targeted_at` is the whole reason the migration is needed rather than reading Zid on demand: Zid knows the cart
completed, but only Lynomia knows whether Lynomia caused it. And even "recovered" here is correlation in time, not
proven causation — §8 keeps that distinction in the metric names.

Two further cautions, both from the contract:

- Zid's schema has **`reminders_count`** and a **`whatsapp_message`** field, and its `history` includes "Reminder
  Sent". **Zid appears to send its own reminders.** If so, a "recovered" cart may have been recovered by Zid's
  reminder, not Lynomia's. This must be checked on a real store before any recovery figure is shown to a user, and
  `reminders_count` is worth reading at UAT for exactly this reason.
- `EXPIRED` is Lynomia's own bookkeeping for a cart that stopped being mentioned. It must never be presented as
  something the provider said.

## 5. Provider outage must never read as abandonment

This is satisfied **by construction**, which is the strongest reason to prefer Zid's events over polling:

- Abandonment arrives **only** as `abandoned_cart.created`. Lynomia runs no inactivity timer for Zid, so there is
  no clock that can fire while the provider is silent. B5's rule is honoured by having nothing to disable.
- If Zid is down or its webhook is `broken`, Lynomia receives nothing and **no state changes**. Silence is not a
  signal.
- `EXPIRED` is the one time-based transition, and it must be gated on provider liveness: a cart may only expire
  if the store has had *some* provider contact since the cart's `last_provider_event_at`. Otherwise a broken
  webhook would quietly expire every open cart — the same mistake in a different direction.

That last gate is a design requirement, recorded here so it is implemented deliberately rather than discovered.

## 6. Idempotency, duplicates and out-of-order events

Zid documents **no delivery id**, so none may be assumed. The upsert is keyed on
`(commerce_store_id, provider_cart_id)` and each case is decided by the row that is already there:

| Case | Behaviour |
|---|---|
| Duplicate delivery of the same event | the existing `WebhookQueue` dedup (store id + SHA-256 of body, 24 h) absorbs most. Beyond that, the upsert is naturally idempotent: same fields, same state, no transition emitted |
| The same cart updated twice | `last_provider_event_at` advances; no transition unless `state` changes |
| **`completed` arrives before a delayed `created`** | the upsert creates the row **directly in `COMPLETED`**, with `abandoned_at` from the payload's `created_at`. A late `created` must then **not** move it back — the guard is a monotonic one: a transition is applied only if it advances the lifecycle |
| Out-of-order updates | compare the payload's own timestamp against `last_provider_event_at` and ignore anything older. Provider time, never Lynomia's |
| Replay of an old body after the Redis horizon | the monotonic guard rejects it; this is precisely what Redis alone cannot do, and why the row is needed |

So the ordering rule is one sentence: **the lifecycle only ever moves forward, and only on a provider timestamp
newer than the one already recorded.**

## 7. Cart → order attribution

**Zid's `order_id` on the cart is authoritative** — the provider performs the correlation, Lynomia does not infer
it. Today that field is read by the normalizer and discarded; the proposal is simply to keep it in
`provider_order_id`.

What that does and does not buy:

| Claim | Supportable? |
|---|---|
| "this cart became an order" | **Yes** — the provider says so |
| "this order's value" | **Only by reading the order**, through the existing order path, at display time. The cart's `visible_total` is what the shopper saw, not what they paid: shipping, discounts and partial changes all move between the two |
| "recovered revenue" | **Not from the cart alone.** It requires the order read above, and even then it is revenue from a *completed* cart, attributable to Lynomia only when `targeted_at` precedes `completed_at` |

So `visible_total` must never be summed and labelled revenue. §8 holds the line.

## 8. What future Analytics could honestly answer

| Metric | Provable? | From |
|---|---|---|
| Abandoned carts detected | **Yes** | count of rows ever in `ABANDONED` |
| Abandoned carts targeted | **Yes** | `targeted_at IS NOT NULL` |
| Completed carts | **Yes** | `state == COMPLETED` |
| Completion rate | **Yes** | completed ÷ detected |
| **Recovery rate** | **Yes, with the caveat named** — targeted-then-completed ÷ targeted. It is time-ordered correlation, and Zid's own reminders may be a confound (§4) | `targeted_at`, `completed_at` |
| **Recovered order value** | **Only** by joining `provider_order_id` to a live order read, and only for carts where `targeted_at < completed_at` | §7 |
| "Recovered revenue" as a headline number | **No.** Not shown until the confound in §4 is settled on a real store | — |

## 9. Deliberately not persisted

| Rejected | Why |
|---|---|
| `checkout_url` / `url` | Zid supplies a durable checkout URL, so B12's variable **is** available — but the existing recovery path already proves the safer pattern: `recovery_messages.rb` stores only an **HMAC digest** of the URL and fetches the real one on demand. A stored checkout URL is a bearer token for someone's cart; persisting it for every cart indefinitely is a standing risk for no gain |
| Line items (`products[]`) | `products_count` gives the only thing the lifecycle and the message need. Storing names, SKUs, prices and image URLs would duplicate the product catalogue |
| Addresses, `city_id`, `country_id` | not needed by any proposed transition, message or metric |
| Payment data | never |
| The full provider payload | B4. A payload column becomes a permanent, un-minimised copy of customer data |
| `session_id` | identity ambiguity is resolved in §3 by choosing one field, not by storing all three |
| `whatsapp_message` | Zid's own message text. Reading it at UAT is useful to understand the confound; persisting it is not |
| `ACTIVE` state | no event can establish it (§4) |
| A second abandonment timer | B5, and §5 |

## 10. Coexistence with the Redis viewer — no split-brain

Two roles, one definition:

| | Role |
|---|---|
| `Commerce::AbandonedCart` + `Commerce::Cache` | **provider read-through display.** What the store says right now: the agent's cart list, the queue, the totals and items shown in the panel |
| `commerce_carts` | **lifecycle and event state.** What happened over time: abandoned, targeted, completed, and the order it became |

They are not two definitions of a cart; they are the current snapshot and the history, joined on
`provider_cart_id`. The rules that keep them from diverging:

1. **The lifecycle never reads Redis.** Transitions come only from provider events.
2. **The display never writes the row.** A read-through fetch records nothing, so browsing a cart queue cannot
   manufacture lifecycle.
3. **One of them owns each question.** "What is in this cart" is always the viewer; "what has happened to this
   cart" is always the row. The panel may show both, labelled.
4. `Commerce::AbandonedCart`'s misleading four-status comment is corrected as part of the same work, so the value
   object stops implying a lifecycle it does not have.

The alternative — unifying them behind one abstraction — was considered and rejected: it would force the display
path to persist, which is how browsing becomes a write.

## 11. Automation integration — one event

Proposed addition to the **existing** `Automation::CommerceEvents` registry, through the existing authoritative
trigger registry. No second engine, no new dispatcher.

| Event | Proposed? | Why |
|---|---|---|
| `commerce_cart_abandoned` | **Yes** | established by a provider event. Fires on the transition into `ABANDONED`, once per cart lifecycle |
| `commerce_cart_recovered` | **No, not yet** | B9 and B12's rule. "Recovered" is derived (§4) and confounded by Zid's own reminders. Adding the trigger would invite a recipe that reports recovery we cannot yet stand behind. It becomes addable the moment a real store settles the confound |
| `commerce_cart_completed` | **deferred** | truthful, but no recipe needs it yet, and an unused trigger is clutter in a registry users browse |

## 12. WhatsApp targeting path

No implementation proposed here; this is the path a recipe would take, and the constraints it must respect.

```
abandoned_cart.created (Zid)
  → existing Zid webhook endpoint, Basic Auth           (02)
  → normalize + durable upsert                          (05 §6)
  → transition into ABANDONED
  → commerce_cart_abandoned                             (05 §11)
  → existing AutomationRule
  → existing WhatsApp sender, approved template only
  → set targeted_at                                     (05 §4)
```

P5's architecture is untouched, and its rules bind this path:

| Rule | How it is met |
|---|---|
| No free-form business-initiated send outside the 24-hour window | An abandoned-cart reminder is business-initiated by definition, so it must be an **approved template**. `SendOnWhatsappService` already refuses plain text on a closed window locally, before Meta is called |
| Approved and sendable template | the existing Template Manager's sendability check, not a new one |
| Correct WABA | the template must belong to the inbox's own WABA — already enforced by the existing sender |
| Correct contact identity | the cart's `contact_id`, resolved through `CustomerMatcher`'s existing rules. A cart whose customer cannot be matched has no contact and **must not be targeted** — which is why `contact_id` is nullable (§2) rather than the row being dropped |
| Duplicate targeting | `targeted_at` on the row, not a Redis lock. One lifecycle, one send |

Template variables that the proposed state can resolve safely: customer name, store name, cart value, item count.
The checkout link is resolvable **on demand** via the existing digest pattern, not from a stored URL (§9).

## 13. Retention and rollback

**Retention:** reuse `Commerce::ActionSweepJob`'s existing schedule rather than adding a job. Rows in a terminal
state (`COMPLETED`, `EXPIRED`) older than 90 days are deletable — the same horizon the `recovery_message` runs
already use, so one retention story rather than two. Analytics needs aggregates, not rows, and aggregation beyond
90 days is a later phase's problem to state before this horizon is widened.

**Rollback:** the migration is purely additive — one new table, no change to any existing table or column. Rolling
back is `drop_table :commerce_carts`. Nothing outside the new code path reads it, so a rollback degrades the
product exactly to today's behaviour: the read-through viewer, gated off.

## 14. What must be answered before this is written

1. **`id` vs `cart_id` vs `session_id`** — which is the stable cart identity (§3). Wrong choice means duplicate
   rows instead of transitions.
2. **The webhook payload shape** — the published schema is the REST object; nothing retrievable states the event
   delivers the same fields. If the event carries only an id, ingestion must re-read the cart, which is a design
   change, not a tweak.
3. **Does Zid send its own reminders** (§4) — it changes what "recovered" may be called.
4. **Approval of this migration**, which B2 requires and which has not been given.

Items 1–3 are real-UAT questions. Item 4 is yours.
