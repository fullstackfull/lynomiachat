# 06 — The Zid cart transition design, as built

Zid only. `04` §4 rejects the other three providers with reasons.

---

## 1. The four layers, and why they are separate

```
Zid delivery  →  POST /webhooks/zid/:store_id        existing endpoint, Basic Auth, no new route
              →  Commerce::WebhookQueue              existing dedup + body encryption
              →  Commerce::Zid::WebhookJob           existing job, now routes by event name
              →  Commerce::Providers::Zid::CartEvents   raw Zid  →  canonical
              →  Commerce::CartEvent                  provider-neutral
              →  Commerce::CartLifecycle              the durable row and the transition
              →  Automation::CommerceEvents           existing registry, one event
```

The split exists for one reason: **the Zid webhook payload shape is not proven.** Zid publishes the abandoned-cart
object but not the envelope its events deliver. So everything uncertain is confined to the normalizer, and
`Commerce::CartLifecycle` never sees a Zid field name. When a real store settles the open questions, one file
changes.

## 2. What the normalizer owns, and the two things it declares unverified

**`UNVERIFIED(zid-cart-identity)`.** Zid's schema carries `id`, `cart_id` **and** `session_id`, and the
documentation does not say which is stable across a cart's life. `IDENTITY_KEY = 'id'` is the single declared
choice, and a payload without it is **refused**, not fallen back on:

> falling back to another key would let two deliveries about one cart choose two identities and create two rows,
> which is worse than refusing one delivery loudly.

Identifiers are never concatenated. When UAT settles this, that one constant changes — never the schema.

**`UNVERIFIED(zid-cart-envelope)`.** The resource is read from the top level, or from one of
`abandoned_cart` / `cart` / `data` if a delivery wraps it. Anything else is refused and reported.

## 3. The kind comes from the cart's state, not from the event name

```ruby
completed = resource['phase'] == 'completed' || order_reference.present? || event_name == COMPLETED_EVENT
```

The event name is the *last* of three signals, deliberately. `phase` and `order_id` are the same fields the
existing read-through adapter already trusts, and they survive an envelope whose name is absent or wrong — whereas
trusting the name alone would record an abandonment for a cart the provider is telling us is finished. A regression
pins that a delivery named `created` carrying `phase: completed` records a completion.

## 4. Routing: both kinds arrive at one endpoint

Zid registers every event to the same `target_url`, so the job routes on the event name. A delivery with **no**
event name is treated as an order event, which is what this job has always done. A cart-shaped body without one is
**not** guessed at:

```
[COMMERCE CART] event=unusable_zid_cart_delivery store_id=… zid_event=… keys=…
```

Filing a cart as an order, or an order as a cart, is worse than refusing one delivery visibly.

## 5. The state machine — two states

```
   abandoned_cart.created              abandoned_cart.completed
            │                                     │
            ▼                                     ▼
      ┌───────────┐                         ┌───────────┐
      │ ABANDONED │ ──────────────────────► │ COMPLETED │
      └───────────┘                         └───────────┘
```

No `ACTIVE`: Zid never announces a live cart — the first thing it says is that one was abandoned.
No `RECOVERED`: see §8.
**No `EXPIRED`**: it was in the `05` proposal and has been **dropped**. On inspection it existed only so retention
could find old rows, and retention can select on state and age without a lifecycle state that no provider event
establishes. A state nothing can prove is a state that will eventually be reported as fact.

### The three rules

| # | Rule | Where |
|---|---|---|
| 1 | **Forward only.** `completed` never returns to `abandoned`. A late `created` is recorded as `state_regression` and not applied | `CartLifecycle#regression?` |
| 2 | **Provider time only.** An event older than the row's `last_provider_event_at` is `stale_event`. Lynomia's clock never orders events, so a redelivery days later cannot overtake what it carries. Equal timestamps are *not* stale — a provider that stamps both identically must still move the cart forward, and rule 1 stops it moving back | `#stale?` |
| 3 | **No clock creates state.** Abandonment arrives only as a provider event | §7 |

## 6. Duplicates, and out-of-order arrival

| Case | Behaviour |
|---|---|
| Identical body redelivered | absorbed by the existing `WebhookQueue` dedup — store id + SHA-256 of the body, 24 h |
| Duplicate `created` beyond that horizon | the upsert finds the row, nothing changes, `no_change`, **no Automation dispatch** |
| Duplicate `completed` | same |
| **`completed` before a delayed `created`** | the row is created **directly in `completed`**, with the provider's own `created_at` as `abandoned_at`. The cart was abandoned; Lynomia simply never saw that delivery |
| A late `created` after that | rule 1 — `state_regression` |
| An older update | rule 2 — `stale_event` |
| Two workers at once | the whole upsert runs inside the existing `Commerce::StoreLock`, keyed by store and cart. The unique index on `(commerce_store_id, provider_cart_id)` is the backstop, and `RecordNotUnique` is caught and reported as `already_recorded` |

Note what is *not* relied on: the 24-hour Redis dedup is for provider redeliveries, and the lifecycle does not
depend on it. Every ordering decision is made against the row.

## 7. Provider outage safety, by construction

There is **no inactivity timer for Zid**, so there is no clock that could misfire while the provider is silent:

- abandonment exists only as `abandoned_cart.created`;
- if Zid is down, or its webhook is in the `broken` state its circuit breaker defines (`02` §1.6), Lynomia
  receives nothing and **no state changes**;
- silence is not a signal.

Two regressions pin this structurally rather than by searching for words: `CartLifecycle` exposes exactly one
public method and it requires an event, and `Commerce::CartLifecycle.new(` appears in exactly one file — the
webhook job. Nothing schedules it.

## 8. Completion is not recovery

`abandoned_cart.completed` proves **checkout completion**. It does not prove that Lynomia caused it, and the
provider's own schema carries `reminders_count` and a `whatsapp_message`, so Zid may be reminding the shopper
itself. So:

| Reading | Condition | What it is called |
|---|---|---|
| Completed | `state == completed` | the shopper finished this cart |
| **Post-target completion** | `targeted_at` present and `completed_at > targeted_at` | we messaged, then they finished — a **time ordering**, not a cause |
| Untargeted completion | `completed_at` present, `targeted_at` nil | they finished with no outreach from us |
| Order-attributed | `provider_order_id` present | Zid itself correlated the cart to an order |

`Commerce::Cart` has no `recovered` state and no `recovered?` method, and a regression asserts both absences.

## 9. Cart → order attribution

Zid's `order_id` on the cart is **authoritative** — the provider does the correlation. Lynomia previously read it
and discarded it; it is now kept in `provider_order_id`, and nothing more:

- completion **with** `order_id` → `COMPLETED` + order attributed;
- completion **without** → `COMPLETED`, not order attributed.

Order *value* is never copied into the cart row. `visible_total` is what the shopper saw, not what they paid, so it
must never be summed and called revenue. Reading the order goes through the existing Commerce order path, at
display time.

## 10. Customer resolution

The contact comes from the store's existing `commerce_customer_links` — never from a name match and never from a
fresh provider read. A cart whose customer is not linked is **still recorded**, with `contact_id` nil: the row is
the lifecycle, and targeting needs a contact, so an unlinked cart simply cannot be targeted.

## 11. Gating

Ingestion sits behind the same gate the read-through viewer uses — `Commerce::AbandonedCarts.offered?`, which
requires an active store, `Commerce::Switches.provider_recovery_enabled?`, and the provider's own
`supports_carts?`. So:

| Provider | Cart ingestion |
|---|---|
| WooCommerce | **never** — `supports_carts?` is false and there is no recovery switch key at all |
| Salla | PRE_UAT |
| **Zid** | **PRE_UAT** — nothing is recorded in production until a real UAT clears it |
| Shopify | PRE_UAT |

Two regressions prove the gate is shut: PRE_UAT ingests nothing, and a WooCommerce store ingests nothing.

## 12. The read-through viewer, and the ownership split

| Question | Authoritative source | When the provider is unavailable |
|---|---|---|
| What is in this cart now — items, totals, the checkout link | `Commerce::AbandonedCart` + `Commerce::Cache` (120 s fresh / 24 h stale) | a stale entry is served, flagged `stale`, and the UI says so |
| What has happened to this cart — abandoned, targeted, completed, the order | `commerce_carts` | unaffected: the row is local and does not expire |

Three rules keep them from diverging:

1. **The lifecycle never reads Redis.** Transitions come only from provider events.
2. **The display never writes the row.** Browsing a cart queue cannot manufacture lifecycle.
3. One of them owns each question, and the panel may show both, labelled.

Unifying them behind a single abstraction was considered and rejected: it would force the display path to persist,
which is how browsing becomes a write.
