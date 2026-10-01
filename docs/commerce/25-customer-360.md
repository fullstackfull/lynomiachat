# Lynomia Commerce: Customer 360 (Phase 7–8)

The conversation's Commerce section moves from "Conversation → Store → latest orders" to "Conversation → Customer 360":
the contact's stores, orders, spend, last purchase, payment, shipping, tracking and freshness across every connected
store. The per-store view stays as it was, one tab away.

## 1. Identity model: no new CRM

- **The Chatwoot contact is the customer.** There is no `commerce_customers` table and no merged "customer" record.
- **`commerce_customer_links`** (unchanged schema) maps one contact to one store customer per store
  (`external_customer_id`, encrypted; `guest:<email|phone>` for guest checkouts). Customer 360 is the set of a
  contact's links, read live.
- **No order tables.** Orders are never stored in Postgres. They are read from the stores through the existing Redis
  cache (`Commerce::Cache`: fresh 120 s, stale fallback up to 24 h).
- **Migrations: none.** `match_source` is an integer enum. The one new value, `suppressed: 4`, needs no migration.

Identities are never combined across stores by guesswork. Each store's link comes from that store's own exact match
(the conversation's verified channel phone, doc 03) or an agent's explicit choice. Customer 360 only places the
per-store results side by side.

## 2. Persisted data added in Phase 7–8

| Where | What | Lifetime |
|---|---|---|
| `commerce_customer_links.match_source` | new value `suppressed` (an agent removed the link) | until someone links by hand, or the store is disconnected |
| `commerce_stores.credentials` (encrypted, existing) | WooCommerce `webhook_secret` | replaced on each registration; deleted with the credentials |
| `commerce_stores.metadata` (existing) | `realtime: { status: active \| read_only_key, webhook_ids, registered_at }` | per registration |
| Redis cache entries (existing) | `"outdated": true` on invalidated entries | entry TTL (24 h) |
| Redis | refresh lock and pending flag per link | ≤ 60 s |
| Redis | Refresh cooldown per contact and view | 30 s |
| Redis | order-search counter per agent | 60 s |

## 3. API

`GET /api/v1/accounts/:account_id/conversations/:conversation_id/commerce/overview` (`Commerce::Customer360`).

```json
{
  "contact": { "id": 3 },
  "stores_count": 4,
  "linked_stores_count": 4,
  "orders_count_visible": 16,
  "total_spend_visible": [{ "currency": "SAR", "amount": "843.56" }],
  "currencies": ["SAR"],
  "last_order_at": "2026-09-29T07:15:00Z",
  "active_orders_count": 9,
  "shipped_orders_count": 3,
  "latest_orders": [{ "order_number": "41000102", "status": "shipped", "...": "…", "store": { "id": 7, "name": "Zid Store", "provider": "zid" } }],
  "stores": [
    { "store": { "id": 5, "name": "Woo Store", "provider": "woocommerce" }, "state": "linked",
      "link": { "match_source": "verified_phone", "customer_type": "guest", "linked_at": 0, "confirmed_by": null },
      "fetched_at": "…", "stale": false, "error": null, "orders_count": 3 }
  ],
  "partial": false
}
```

`POST .../commerce/refresh[?store_id=]` returns the same shape (or one store's panel) read from the stores now (doc 24
§8). `GET .../commerce/orders?number=` is the order search (§7).

## 4. Aggregation

- Stores: the account's `active` and `needs_reauth` stores, oldest first. Each contributes exactly what its store view
  shows (`Commerce::ConversationPanel#show`): link (auto-linking as before), latest `ORDER_LIMIT` (5) orders, freshness.
- **Bounded parallel reads.** `Commerce::Parallel` runs at most `MAX_CONCURRENCY` (4) stores at once. It answers after
  `STORE_TIMEOUT` (15 s) whatever is still running; that store is reported `unavailable`/`TIMEOUT`. Threads hold no
  database connection while waiting on a store.
- **Partial, never failing.** A store that errors, times out, needs re-authorization or whose provider is switched off is
  its own entry. `partial: true` when any store has an error. The overview itself always answers 200 (except
  authorization).
- **Per-store freshness.** `fetched_at` and `stale` per store. A store served from its stale cache during an outage
  shows "Showing data from …", the others "Updated …".
- Cost per open: one cached read per store (≤ 1 provider call per store when cold, 0 when warm). No 100-order
  fetches: the latest 10 across stores come from each store's latest 5.

## 5. Figures and their definitions

All figures cover only the orders the stores returned ("visible"), never a lifetime total, and are labelled so.

| Figure | Definition |
|---|---|
| Stores | `stores_count` connected; `linked_stores_count` where the contact is linked |
| Orders | `orders_count_visible`: sum of the stores' returned orders |
| Active orders | normalized status in `pending`, `processing`, `on_hold`, `shipped` |
| Shipped orders | normalized status `shipped` (handed to the carrier, not yet delivered) |
| Spend | totals of orders whose normalized `payment_status` is `paid`, summed per currency as exact decimals, **never converted**: `[{SAR: 743.56}, {USD: 100.00}]`. Salla reports no explicit "paid", so its orders count toward no spend (doc 13) |
| Currencies | distinct currencies of the visible orders |
| Last purchase | newest `created_at` among orders that are not `draft`, `failed` or `cancelled`; "No orders found" when there is none |
| Latest orders | up to 10 across stores, `created_at` descending, each tagged with its store `{id, name, provider}` |

Not shown, by design: lifetime value, average order value, customer lifetime, predicted value.

## 6. States and empty states

| Store `state` | Meaning | UI |
|---|---|---|
| `linked` | the contact is linked in this store | "Linked" + "Guest/Registered · Matched by …" |
| `not_found`, `suggested`, `multiple` | not linked (candidates are not part of the overview) | "Customer not linked"; "Open store" to link |
| `unavailable` (+ `error`) | the store could not be read (`STORE_UNAVAILABLE`, `TIMEOUT`, …) | "Couldn't refresh" |
| `needs_reauth` | credentials were rejected; nothing cached is shown | "Store needs re-authorization" |
| `provider_unavailable` | the installation switched the provider off; not contacted, nothing cached shown | "Provider currently unavailable" |

Panel-level empty states:

- "No store is connected yet." (no store);
- "Customer not linked" (no linked store);
- "No orders found";
- "Some stores couldn't be refreshed" (partial).

Rejected credentials outrank the cache: such a store never shows cached orders.

## 7. Order search

Agents can find an order by the number a customer quotes, in the open store or in every store
(`GET .../commerce/orders?number=1001[&store_id=]`, `Commerce::OrderSearch`).

- Input: digits only, an optional leading `#`, at most 20 digits; anything else gets 422 `INVALID_QUERY` before any
  store is asked.
- Each store is asked for that number directly through its provider's `find_orders`, never scanned:
  - WooCommerce: the order with that id, kept only if its number matches. A store whose orders are renumbered by a
    plugin is not found by number.
  - Zid: the order with that id, which is the number the panel shows (doc 16; Z15 still VERIFY).
  - Shopify: `orders(query: name:"<n>")`, a quoted phrase sent as a GraphQL variable, re-checked exactly.
  - Salla: not searchable. The store is reported "order search isn't available for this store" (no confirmed
    contract, KEEP VERIFY).
- Stores are searched in parallel (`Commerce::Parallel`, 4 at a time, 10 s budget). Several results are allowed, newest
  first, each naming its store.
- A found order can belong to any customer of the store. It is returned without its customer, not cached, not linked,
  and the panel offers no "Send tracking" for it.
- Limited to 10 searches per agent per minute (429 + `Retry-After`). Each search is audited
  (`commerce.orders_searched`: number, stores searched, results).

## 8. Linked identities and unlink suppression

Each store entry shows how the contact is linked: guest or registered, and the match source (verified phone, verified
email, manual by agent). Store customer ids are never shown.

Removing a link used to be undone by the next read, because the conversation's verified phone linked the same customer
again. Now:

- **Unlink** keeps the row as `match_source: suppressed` (no new table), with the agent as `confirmed_by`. It is audited
  `commerce.customer_link_removed` with `{match_source: [previous, "suppressed"]}`, ids only.
- A suppressed contact counts as not linked everywhere: store list, Customer 360, realtime refreshes
  (`not_suppressed`), `RefreshJob`.
- The matcher no longer links it automatically. The verified match is offered as a candidate instead.
- **Link by hand** updates the same row to `manual` (audited `customer_link_changed`, `[suppressed, manual]`).
- Disconnect and Shopify redaction delete suppressed rows like any other link.

## 9. PII minimization

- The overview carries no candidates, no store customer ids, no emails or phones. Orders in `latest_orders` have their
  `customer` (name) removed and gain only the store's id, name and provider.
- The realtime event carries ids and a time only (doc 24 §7).
- Order search results carry no customer.
- Customer 360 reads exactly what the per-store view already read. It adds no provider call for customer data.

## 10. Permissions (unchanged)

- Overview, refresh, order search and the store view are available to whoever can see the conversation (inbox or team
  membership, or administrator), in `lynomia_commerce` accounts only.
- Connecting, disconnecting, credentials and enable/disable stay administrator-only (Settings → Commerce).
- Every Commerce endpoint is scoped to the conversation's account. Another account's store id is 404, and another
  account's conversation is 401.

## 11. UI

- **Tabs.** "Overview" and "Store" appear when the account has more than one store. The store selector is unchanged in
  the Store tab.
- **Default view.** Overview opens first when the contact is linked in more than one store, otherwise the Store tab.
  An agent's own choice is remembered in the browser (`lynomia.commerce.view`).
- **Overview layout.**
  - Metrics grid: stores, orders (visible, active · shipped), last purchase, spend per currency.
  - Collapsible "Recent orders": cards with store and provider.
  - Collapsible "Stores": state, identity, freshness, "Open store".
  - "Find an order" (order search).
- **Refresh.** A button for the open view, with the cooldown notice.
- **Layout and language.** Arabic (RTL) and English, desktop and mobile. Tailwind only, logical spacing (`ms-*`,
  `text-start`).
