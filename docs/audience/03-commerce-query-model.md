# Lynomia Audience: Commerce query model

How Commerce conditions are evaluated in SQL, without a store call, without copying orders, and without passing off
unknown as zero. Code: `Audience::CommerceCondition` (`custom/app/services/audience/commerce_condition.rb`) and
`Commerce::ContactMetric` (`custom/app/models/commerce/contact_metric.rb`).

## 1. Why one small table was needed

From [00 §8](00-existing-system-discovery.md): stores and customer links are in Postgres, so "has a linked store",
"store" and "platform" were already evaluable. Orders are **not**: they live in Redis (`Commerce::Cache`, keyed by an
HMAC of the store customer id, 24 h) and Customer 360's figures are computed in memory per request. Without a local
projection, "visible spend > 1000" over 10,000 contacts would mean thousands of store API calls per preview. That is the
case the brief rules out, so it is the one thing added.

## 2. `commerce_contact_metrics`: one summary per customer link

| Column | Meaning |
|---|---|
| `account_id` | FK → accounts, `on_delete: cascade` (copied from the link, never from the request) |
| `commerce_customer_link_id` | FK → commerce_customer_links, `on_delete: cascade`, **unique** |
| `orders_count` | visible orders read (0 = known none) |
| `active_orders_count` | of those, status pending / processing / on_hold / shipped |
| `last_purchase_at` | newest visible order that is not draft / failed / cancelled (NULL = none) |
| `spend` | jsonb `{ "SAR": "1250.00", "USD": "25.00" }`: totals of visible **paid** orders per currency, exact decimal strings |
| `order_statuses`, `payment_statuses`, `shipment_statuses` | the normalized statuses seen (`Commerce::Order` values), sorted, unique |
| `fetched_at` | when the store answered the read these figures come from |

Not stored: orders, order numbers, items, products, addresses, payment records, shipment objects, customer names,
emails or phones, raw webhooks. A row is a handful of numbers about one link. The contact is reached through the link
(`commerce_customer_links.contact_id`), so a contact linked in two stores has two rows, and the account is pinned on
both tables.

## 3. "Visible" figures

The figures follow Customer 360 (`Commerce::Customer360.spend / last_purchase_at / active_orders_count`) over exactly
the orders the Commerce section shows: the store's latest `ConversationPanel::ORDER_LIMIT` (5) orders for that
customer. They are **visible** orders and spend, never lifetime totals, and the UI says so ("Visible orders",
"Visible spend (SAR)", "Last visible purchase", and the builder note). No field is called lifetime, total or LTV.

## 4. Freshness: written only by the reads that already exist

`Commerce::ContactMetric.record(link, cache_result)` is called right after the two existing order reads:

| Existing path | When it runs |
|---|---|
| `Commerce::ConversationPanel#linked` | an agent opens a conversation's Commerce section (and its manual refresh) |
| `Commerce::Realtime.read_orders` | `Commerce::RefreshJob`: a store webhook named the customer (WooCommerce, Salla, Zid, Shopify adapters), or an order action finished (`ActionExecutor#refresh_customer` invalidates and schedules the refresh) |

There is no new job, schedule, sync pipeline or provider call. Write rules:

- **Idempotent and ordered**: the row changes only when the read is newer than the stored `fetched_at`. A cache hit or a
  stale fallback carries the time of the read it came from, so it rewrites nothing; an older read never replaces a newer
  one. Concurrent first writes resolve through the unique index (`RecordNotUnique` → retry → update).
- **Failed read**: `Commerce::Error` happens before `record`, so nothing is written; the last known row stays, or the link
  stays unknown. Never a zero.
- **Known zero**: a read that returns no orders writes `orders_count 0`, `spend {}`. That contact is known to have none.
- **Account and contact scoped** by construction: `account_id` and the link come from the link being read.
- **Derived only from normalized state**: the `Commerce::Order` hashes the provider adapters already normalized.

So membership follows the data: a new paid order arrives by webhook → the refresh reads it → the row changes → the next
time the audience is opened or counted, the contact is in it.

## 5. Which links count

A link counts when **all** hold (`CommerceCondition.counted_links`, the `links` FROM clause):

1. `audience_links.account_id = <current account>`;
2. not suppressed (`match_source <> suppressed`);
3. its store is `active` (not `disabled`, `needs_reauth` or `disconnected`);
4. its store's provider is in `Commerce::Providers.enabled` (the installation's hard switch).

These are the same stores Customer 360 reads. A link that does not count contributes **nothing** to any condition: not
to spend, orders, statuses, store or platform. Its row may still exist (for example while a store is disconnected) and is
simply ignored; nothing calls the store to refresh it.

| Event | Effect on audiences |
|---|---|
| Agent unlinks (link → `suppressed`) | excluded at once; its summary is deleted (`after_update :drop_contact_metric`) |
| Link re-pointed to another store customer (`external_customer_id` changes) | summary deleted; unknown until the new customer is read |
| Link deleted, store deleted, contact deleted, account deleted | rows go by FK cascade |
| Store disabled, needing re-authorization or disconnected | excluded while not active; counts again when active |
| Provider switched off for the installation (Salla, Zid, Shopify are NO-GO in production) | excluded; their stores are not offered in the builder; no call is ever made |
| Explicit re-link after an unlink | counts again once its orders are read |

## 6. Unknown is never zero

A counted link without a summary has not been read yet: its figures are **unknown**. Each condition is evaluated with
explicit SQL NULL semantics, so unknown never matches as zero and never passes a negation:

| Condition kind | Fields / operators | Rule |
|---|---|---|
| Can only become true with more data | orders > N, spend > N, last purchase after D, has an active order = Yes, has an order with status S | **known**: computed over the summaries that exist; true when they already prove it |
| Could become false with more data | orders < N, orders = N, spend < N, last purchase before D, more than N days ago, active order = No, has no order with status S | **complete**: NULL (no match) unless **every** counted link of the contact has a summary |
| Facts about links | linked store present / absent / equal / not equal, platform | known from links; summaries not needed |

Examples: in the E2E, Layla is linked but never read, so she is not in "visible orders < 100" while she is in "linked
store is present". In the specs, a contact with one read store (SAR 200) who gets a second, unread link stays in "visible
orders > 0" (proved) and leaves "visible spend (SAR) < 1000" (the unread store could add more); "visible orders = 0",
"has an active order = No" and "has no order with status processing" never match an unread contact.

The builder shows how many linked contacts are unread, with what reads them ("… when an agent opens the contact's
conversation or the store sends an update"), instead of hiding them.

## 7. Currency

- One field per currency: `commerce_spend_sar`, `commerce_spend_usd`, … The builder offers the currencies seen in the
  account's counted summaries ("Visible spend (SAR)").
- Amounts are compared within that currency only. The same currency is summed across a contact's stores; different
  currencies are never added together and never converted.
- A known customer with no paid order in SAR has a known SAR spend of 0 (`COALESCE(spend ->> 'SAR', 0)`): they match
  "spend (SAR) < 100" when all their stores are known. An unread customer does not.
- Amount values must be finite, non-negative decimals (422 otherwise).

## 8. Abandoned carts: not exposed

Carts exist only in Redis, per conversation identity (`Commerce::AbandonedCarts`), from Salla, Zid and Shopify;
WooCommerce core has no cart API (`unsupported`). There is no per-link record to query, and all three cart providers are
NO-GO in production. "Has abandoned cart" and its age/value/currency/provider are therefore **not offered**. When needed,
the same pattern applies: a per-link cart summary written by the existing cart reads and `Realtime.cart_event`.

## 9. SQL

Every Commerce condition is a subquery about `contacts.id`; values, the account, the provider list and the enums are
bind parameters (`:audience_account`, `:audience_providers`, `:audience_suppressed`, `:audience_active`, `:audience_<n>`).

```sql
-- the counted links of the contact, with their summary when there is one
FROM commerce_customer_links audience_links
INNER JOIN commerce_stores audience_stores ON audience_stores.id = audience_links.commerce_store_id
LEFT JOIN commerce_contact_metrics audience_metrics ON audience_metrics.commerce_customer_link_id = audience_links.id
WHERE audience_links.contact_id = contacts.id AND audience_links.account_id = :audience_account
  AND audience_links.match_source <> :audience_suppressed AND audience_stores.status = :audience_active
  AND audience_stores.provider IN (:audience_providers)

-- Visible spend (SAR) > 1000: over the known summaries
(SELECT SUM(COALESCE((audience_metrics.spend ->> :audience_0_currency)::numeric, 0)) <links> AND audience_metrics.id IS NOT NULL) > :audience_0

-- Visible orders < 2: only when every counted link is known
(SELECT CASE WHEN COUNT(*) > 0 AND COUNT(audience_metrics.id) = COUNT(*) THEN SUM(audience_metrics.orders_count) END <links>) < :audience_1

-- Linked store = 4, Order status = processing
EXISTS (SELECT 1 <links> AND audience_stores.id IN (:audience_2))
EXISTS (SELECT 1 <links> AND audience_metrics.order_statuses && ARRAY[:audience_3]::varchar[])
```

The result is one more parenthesised expression in Chatwoot's chain, joined by the condition's `query_operator`.
Plans and timings are in [05](05-performance.md).
