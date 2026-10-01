# Lynomia Commerce: abandoned carts (Phase 9–10)

A conversation's Customer 360 shows the contact's recent abandoned carts, read from the store, so an agent can prepare a
recovery message (doc 31). Carts are never stored in Postgres, never matched loosely, and never shown for providers
whose merchant API has no abandoned carts.

## 1. Provider-neutral cart

`Commerce::AbandonedCart` (a value, not a table):

| Field | |
|---|---|
| `provider`, `store_id`, `external_cart_id` | |
| `created_at`, `updated_at` | ISO 8601 UTC |
| `currency`, `total` | as the store reports them (string decimal) |
| `items` | `[{ name, quantity }]` (names when the store gives them) |
| `customer_reference` | the store's customer id, when the cart has one |
| `email`, `phone` | for matching only (normalized; masked values dropped); never cached, never sent to the browser |
| `recovery_url` | the store's own link, validated before use (doc 31 §3); never cached, never listed |
| `status` | `abandoned` or `recovered` |
| `recovered_at`, `provider_metadata` | small provider facts (Zid phase, Salla age, Shopify checkout name) |

A provider offers carts with `supports_carts?`, `cart_access_problem`, `abandoned_carts(customer_reference:, limit:)`,
`abandoned_cart(id)` and `recovery_hosts` (`Commerce::Providers::Base`).

## 2. Providers

| | Salla | Zid | Shopify | WooCommerce |
|---|---|---|---|---|
| API | `GET /admin/v2/carts/abandoned?per_page=` (Cart resource: id, checkout_url, total, customer, items) — path and scope VERIFY | `GET /v1/managers/store/abandoned-carts?page&page_size&customer_id` and `/{id}` (official SDK) | GraphQL `abandonedCheckouts(query: "status:open" / "id:N", sortKey: CREATED_AT, reverse: true)` | **unsupported** |
| Scope | `carts.read` (checked against the token's scopes) | `abandoned_carts.read` (not readable; a refusal shows the store as unreadable) | `read_orders` (existing) | — |
| Customer filter | none: the latest page (30) is read, then matched | `customer_id` when the contact is linked | none: the latest 20, then matched | — |
| Identity used | customer id, mobile, email | customer id, mobile, email | **customer id only** (no email, phone or address requested: protected customer data) | — |
| Recovered | the cart leaves Salla's list | phase `completed` or an `order_id` | `completedAt` | — |
| Recovery link hosts | the store's host, `salla.sa`, `*.salla.sa` | the store's host, `zid.store`, `*.zid.store` | the shop's `*.myshopify.com` host and its primary domain | — |
| Cart events | `abandoned.cart`, `abandoned.cart.update` (app webhook; Partner Portal subscription) | none documented | none used (no new topic or scope) | — |

**WooCommerce.** WooCommerce core keeps carts in customer sessions and has no merchant-wide abandoned-cart API. Lynomia
does not pretend otherwise and does not require a plugin: WooCommerce stores show no abandoned carts, and the recovery
switch has no WooCommerce entry.

## 3. Matching: only trusted identities

A cart belongs to the conversation's contact by one of these, in this order (`Commerce::AbandonedCarts`):

1. `linked_customer`: the cart's customer is the contact's linked store customer (a trusted link from Phase 2–8)
2. `verified_phone`: the cart's phone equals the phone of the conversation's channel identity (WhatsApp/SMS
   `source_id`, as `CustomerMatcher#trusted_phone`)
3. `verified_email`: the cart's email equals the address an email conversation came from (the contact inbox's
   `source_id`)

Never: by name, by the contact's editable phone or email fields, by a masked value (`t***@…`, `*******2233`). Never a
cart of another store customer than the linked one, nor of the customer an agent unlinked (suppressed link). When the
verified phone or email appears on carts of several store customers, none of them matches (ambiguous). Shopify carts
match by linked customer only.

The panel shows how each cart matched ("Linked store customer", "Matched by this conversation’s verified phone", …).

## 4. Customer 360

- An "Abandoned carts" section appears only when the contact has carts (or a store could not be read). Overview lists
  every store's; the store view that store's.
- Shown: abandoned carts younger than 30 days, newest first, at most 5 per store: total and currency, item count (and
  names on "View cart"), store and provider, age, the match, and the recovery state (prepared / sent / cooldown).
- Never shown: a recovered or expired cart, the recovery link, the customer's email or phone.
- A store that cannot be read says "Couldn’t read {store}’s abandoned carts." (expired token, missing scope, Shopify's
  protected-data refusal, timeout), without blocking the others (read concurrently, 15 s each).

## 5. Cache and realtime

- Read through `Commerce::Cache` (`:carts`, per contact and link): fresh 120 s, kept 24 h for an outage. Only the public
  fields of matched carts are cached (no email, phone or link). The admin queue caches `:cart_queue` per store the same
  way (ids, amounts, status, customer id).
- Every order event and every cart event of a store **drops** the store's cached carts (not just "outdated"), so a cart an
  order completed is never shown again, not even as a stale fallback (`Commerce::Realtime.cart_event` / `order_event`).
- A cart event naming a customer refreshes that customer's linked contacts through the Phase 7 core and broadcasts
  `commerce.customer.updated`; the open section reads the carts again without a reload.

## 6. Retention and data kept

- Carts: Redis cache only, at most 24 h; nothing in Postgres.
- Recovery message runs (`commerce_action_runs`, `recovery_message`): cart id, amount, currency, how it matched, an HMAC
  digest of the link (not the link), the message id once sent. Deleted after **90 days** by `Commerce::ActionSweepJob`.
- Not stored anywhere: addresses, payment data, browsing history, the cart's items beyond the cache, contact details.

## 7. Switches and defaults

| Switch | Default |
|---|---|
| `COMMERCE_RECOVERY_ENABLED` (kill switch for carts and recovery) | `true` |
| `SALLA_RECOVERY_ENABLED`, `ZID_RECOVERY_ENABLED`, `SHOPIFY_COMMERCE_RECOVERY_ENABLED` | `false`, and held back until each provider's real UAT (`COMMERCE_ALLOW_PRE_UAT_PROVIDERS` for staging only) |

So in production no store shows abandoned carts until a provider passes its UAT: WooCommerce has none, the others are
held back.

## 8. Metrics

`commerce.cart.fetch` (a read from the store), `commerce.cart.matched` (count, ambiguous), `commerce.cart.recovered`
(recovered carts seen), `commerce.cart.event` (Salla events), and the recovery metrics of doc 31.
