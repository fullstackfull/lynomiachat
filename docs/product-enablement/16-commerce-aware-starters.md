# Commerce-aware starters, and the platform capability gates

Phase P2, Part E. What a starter may claim about a merchant's store platform, and the two capabilities recorded as
COMING LATER.

---

## 1. The finding this part exists for

The four store platforms do not normalize the same order statuses. Read from each provider's own normalizer:

| normalized status | WooCommerce | Salla | Zid | Shopify |
|---|---|---|---|---|
| `shipped` | **never** | yes (`shipped`, `delivering`) | yes (`indelivery`) | yes (`FULFILLED`) |
| `delivered` | **never** | yes | yes | **never** (`DELIVERED` is a *shipment* status only) |
| `cancelled` | yes | yes (`canceled`) | yes | **never** |
| `refunded` | yes | yes (`restored`) | yes (payment) | yes (payment) |
| `paid` | yes | yes | yes | yes |

Sources: `custom/app/services/commerce/providers/woocommerce/normalizer.rb:17-20`,
`salla/normalizer.rb:12-15`, `zid/normalizer.rb:16-19`, `shopify/normalizer.rb:15-22`.

The commerce triggers read the *order status*: `commerce_order_shipped` is `state['s'] == 'shipped'`
(`custom/app/services/commerce/order_transitions.rb:22-28`). So:

- **`commerce_order_shipped` can never fire for a WooCommerce store** — and WooCommerce is the only platform
  enabled by default (`custom/app/services/commerce/providers/base.rb:6`; `SALLA_ENABLED`, `ZID_ENABLED` and
  `SHOPIFY_COMMERCE_ENABLED` all ship false).
- **`commerce_order_delivered` fires only for Salla and Zid.**
- **`commerce_order_cancelled` never fires for Shopify.**

Order lookup differs too: Salla has no `searches_orders?` override, so `Commerce::OrderSearch` reports
`unsupported` for a Salla store (`providers/base.rb:30`, `order_search.rb:30`). WooCommerce, Zid and Shopify can all
find an order by its number.

The catalogue had been reading as though all four platforms were alike.

## 2. What shipped

The recipe contract gains an optional `providerNote` — an i18n key, carried by a starter whose usefulness depends on
what the platform reports. `RecipeDialog` renders it twice: in the gallery row, where the choice is made, and again
on the wizard step, where it is confirmed.

Carried by four starters:

| starter | note |
|---|---|
| `commerce_order_shipped_label` | Salla, Zid and Shopify report shipped; WooCommerce has no shipped status, so the rule will not run for a WooCommerce store |
| `commerce_order_cancelled_followup` | WooCommerce, Salla and Zid report cancelled; Shopify does not |
| `commerce_order_tracking` (flow) | WooCommerce, Zid and Shopify can find an order by its number; Salla cannot, so the flow hands over to the team. Tracking detail also differs by platform |
| `commerce_after_sales` (flow) | same lookup limitation |

It is **shown, never enforced**. An account can connect a second platform tomorrow and the created object keeps
working, so gating the starter out would be wrong. `recipes/specs/catalogue.spec.js` asserts the note resolves in
both languages and that the two statuses only some platforms report carry one.

## 3. Why the graphs were already honest

`commerce_lookup` has three outputs — `found`, `not_found`, `unavailable` — and both commerce flow templates wire
`unavailable` to a human handoff. A Salla store takes that branch. So the behaviour was already correct; what was
missing was telling somebody *before* they build on it.

## 4. What no starter does

**No starter performs a provider action.** Order actions need all of: the `lynomia_commerce` account feature
(default off), the installation provider switch (default off for three of four), the per-capability switch, a
per-store administrator opt-in (`settings['order_actions']`, absent means off), and proven write access
(WooCommerce defaults to `write_access_unverified`). Above all of that, `Commerce::Switches::PRE_UAT` holds actions
off for Salla, Zid and Shopify entirely, with the only bypass an ENV-only flag that is deliberately not settable
from Super Admin. A starter that offered an order action would be advertising something no default install can run.

**No starter depends on cart state.** See §5.

**No starter claims a trigger it cannot explain.** The commerce triggers are read-driven: they fire inside
`Commerce::ContactMetric.record`, reached only when an agent opens the conversation panel or a coalesced
`Commerce::RefreshJob` runs after a webhook. A link's first read is a silent baseline, only the latest five orders
are diffed, and a contact with no conversation runs no rules. That is reliable enough to build on, and it is why no
starter promises "the moment X happens".

## 5. COMING LATER

### Abandoned cart — REQUIRES CART-STATE PRIMITIVE

Not implemented, and shown nowhere as ready. Two independent blockers:

1. **There is no persisted cart.** `grep -c cart db/schema.rb` is 0. Carts exist only as Redis cache entries
   (`custom/app/services/commerce/abandoned_carts.rb:1-2`, `cache.rb:8-9`) which any order or cart webhook
   **deletes outright** (`realtime.rb:54-57`), so not even a stale snapshot survives. Nothing records a cart
   appearing: `Commerce::Realtime.cart_event` drops caches and queues an order refresh, and dispatches no automation
   event. `Commerce::ActionRun` recovery rows are not a substitute — they carry no cart contents, totals or
   abandonment time, and exist only after an agent prepares a message.
2. **Recovery is held pre-UAT for every platform.** `PRE_UAT[:recovery]` lists Salla, Zid and Shopify, and
   WooCommerce has no recovery switch at all, so no platform can send a recovery message today. WooCommerce also has
   no cart capability of any kind, so "provider-neutral" would mean three of four platforms at best.

A `commerce_cart_abandoned` trigger needs new persisted state. That is a migration and a new primitive, both out of
scope for this phase, and the reason this is a note rather than a recipe.

### Order actions from a starter — REQUIRES UAT CLEARANCE

The mechanism exists and is gated correctly; what is missing is UAT clearance for the three held platforms and a
`supports_actions?` override for Salla (whose `SALLA_ACTIONS_ENABLED` switch is dead until one lands). When PRE_UAT
clears, an action starter becomes a small addition — the gate reporting is already per-store and already server-side
(`Commerce::OrderActions.store_status`).

## 6. Classification

EXTEND on the recipe contract (one optional field), REUSE on every gate. No new Commerce engine, no new endpoint, no
duplicate of the provider capability logic in JavaScript: the notes are product copy citing the normalizers, and the
behaviour they describe is the behaviour the server already has.
