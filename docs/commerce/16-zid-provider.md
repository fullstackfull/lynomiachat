# Lynomia Commerce: the Zid provider (Phase 4)

`Commerce::Providers::Zid` implements the provider contract of doc 02 on the Zid Merchant API (`https://api.zid.sa/v1`, fixed host). The matcher, cache, conversation API, panel UI, order card, permissions and audit are the Commerce core's, unchanged.
- There is no Zid-specific order card.
- The UI only ever receives the provider-neutral `Commerce::Order` / `Commerce::Customer`.

## 1. Requests

Every request:
- carries `Authorization: Bearer <authorization>` and `X-Manager-Token: <access_token>` from `Commerce::Zid::TokenManager` (doc 14);
- goes through `Commerce::HttpClient` (SSRF filter, no redirects, bounded time and size, one GET retry);
- is **GET only**, except Lynomia's own webhook subscriptions (doc 15).

| Purpose | Request |
|---|---|
| Store identity (connect, health) | `GET /managers/account/profile` → `user.store.{id, title, url, timezone}` |
| Customer candidates | `GET /managers/store/orders?search_term=<national number or email>&per_page=20&payload_type=default` |
| A linked customer's orders | `GET /managers/store/orders?customer_id=<id>&per_page=50&sort_by=desc&payload_type=default` |
| One order | `GET /managers/store/orders/<id>/view` → `order` |

Sources:
- Official Zid SDK `OrdersResource.list`, which documents `payload_type`, `customer_id`, `search_term` ("Search by customer phone, email, order code, or name") and `sort_by`, with the `orders` results key.
- `StoresResource.get_profile`.
- The SDK's recorded fixtures (`tests/fixtures/orders_list_default.json`, `order_detail.json`, `customers_list.json`), which the specs' fixture `spec/fixtures/files/commerce/zid/orders.json` is built from.

**Products** need an explicit payload: the default list payload is `simple`, which has no products. It also has no `is_marketplace_order`, as the SDK fixture `orders_list.json` shows. Lynomia always asks for `payload_type=default`.

## 2. Customer matching

The core `CustomerMatcher` is unchanged: existing link → verified channel phone (auto-link when exactly one) → contact email and phone (suggestions) → manual search.

Zid's side:
1. Lynomia does not call the customers endpoints: their filters are undocumented, and the customers-read scope is avoided.
2. Candidates come from the orders list's documented `search_term`:
   - the phone's national number (`551112233` for `+966551112233`), or the downcased email;
   - `search_term` is broad (it also matches names and order codes), so it is only discovery.
3. A candidate is kept only on an **exact** match:
   - the E.164 phone of `customer.mobile`: Zid writes international digits without "+", `966551112233`; a local `05…` number never matches;
   - or the downcased `customer.email`.
   - **Names never match.**
4. Candidates are deduplicated by Zid customer id.

**Marketplace orders and masked data.** For orders from external marketplaces (`is_marketplace_order: true`), Zid masks the customer's details (docs.zid.sa list-of-orders): name `J*** D***`, email `t***@.`, phone `***00`.
- A marketplace order yields **no** candidate. Lynomia never matches on it and never links from it.
- Any value containing `*` is never taken as an email or phone either, flag or not.
- Result: a contact whose phone matches only a marketplace buyer sees "Customer not found in this store", and the agent can still link a customer manually.
- A *linked* customer's marketplace orders are still shown with the rest of their orders: they are theirs by `customer_id`, and nothing about identity is read from them.

**Re-check of the customer filter.** Every order returned for a linked customer is re-checked: `customer.id` must equal the linked id. A filter Zid ignored could therefore never show another customer's orders.

## 3. Order normalization (`Commerce::Providers::Zid::Normalizer`)

| Order field | Zid | Notes |
|---|---|---|
| `external_order_id`, `order_number` | `id` | The id is what Zid's dashboard and notifications number orders by; `code` (invoice URL token) is not shown |
| `status` / `provider_status` | `order_status.code` (lowercased) | §4 |
| `payment_status` | `payment_status` | §5 |
| `currency`, `total` | `currency_code`, `order_total` | Decimal string (`"100.00000000000000"` → `"100.0"`); the UI formats it with the currency |
| `items`, `item_count` | `products[].{name, quantity, total}` | `item_count` nil when the payload had no products |
| `customer` | `customer.{id, name}` | A marketplace order's name stays masked, as Zid sends it |
| `created_at`, `updated_at` | `created_at`, `updated_at` (`"YYYY-MM-DD HH:MM:SS"`, no zone) | Read in the store's time zone from its profile (`metadata.time_zone`, e.g. `Asia/Riyadh`), else `Asia/Riyadh`; **VERIFY** |
| `shipping` | `shipping.method` | `{ method: courier or delivery option, provider: courier, status }` |
| `shipments` | `shipping.method.{tracking, waybill, courier, order_shipping_status}` | §6 |
| `tracking` | the shipment's number and https link | Never guessed |
| `admin_order_url` | nil | Zid documents no merchant-dashboard order URL, so none is built |
| `customer_order_url` | nil | `order_url` is the customer's invoice page and is not needed by agents |

Anything malformed raises `INVALID_RESPONSE` (`malformed_order` / `malformed_customer`). No partial or raw JSON reaches the UI.

## 4. Status mapping

The neutral enum is unchanged ("unknown" is the core's `other`, shown as "Other").

| Zid `order_status.code` | Neutral | Why |
|---|---|---|
| `new` | processing | Received, not yet prepared. Zid keeps payment separate, and neutral `pending` means *pending payment* in the UI. |
| `preparing` | processing | |
| `ready` | processing | Ready for pickup or shipping |
| `indelivery` / `inDelivery` | shipped | The orders API writes `indelivery`, webhook conditions `inDelivery` |
| `delivered` | delivered | |
| `cancelled` / `canceled` | cancelled | Both spellings appear in Zid's docs and SDK |
| `reversed`, `reverse_in_progress`, `partially_reversed`, `initial`, merchant or future statuses | other | Returns are not refunds; nothing is inferred |

## 5. Payment mapping

Only Zid's explicit `payment_status` (SDK: `pending`, `paid`, `refunded`, `voided`):

| Zid | Neutral |
|---|---|
| `paid` | paid |
| `pending` | unpaid |
| `refunded` | refunded |
| `voided`, missing, anything else | unknown ("Payment not confirmed") |

- Payment is **never inferred from the order status**. A delivered order with `pending` payment shows Unpaid, and one without a payment status shows unknown, never Paid.
- Evidence: `spec/services/commerce/providers/zid_spec.rb` (every documented value; delivered + pending).

## 6. Shipping and tracking

Zid keeps an order's shipment on its shipping method (SDK `ShippingMethodDetail`):
- **Tracking number and link:** `tracking.number` / `tracking.url`, else `waybill.tracking_number` / `waybill.tracking_url`. Links are kept only when https.
- **Carrier:** `courier` is a string or `{ name: { ar, en }, code }`; the English name is used, else the Arabic.
- **Shipment status:**
  - from the order's own delivery statuses: `indelivery` → in_transit, `delivered` → delivered, anything else → other;
  - Zid's own shipment status text (`tracking.status`, `waybill.status`, `order_shipping_status`) is kept as `provider_status`, because Zid documents no status vocabulary for shipments.
- An order without a courier, number or link (e.g. "Doesn't Require Shipping") has no shipment.

The neutral card shows the courier, shipment status, **Track shipment** (https link only) and **Send tracking** (fills the reply box; nothing is sent). This is the same UI as WooCommerce and Salla.

## 7. Rate limits and errors

- Zid allows 60 requests/min per app and store (leaky bucket).
  - A 429, or a response reporting no requests left, sets `COMMERCE::ZID::MERCHANT::<id>::BACKOFF` until Zid's `Retry-After` or reset, at most 60 s (`Commerce::Backoff`, shared with Salla). Calls fail fast with `RATE_LIMITED` meanwhile.
  - The panel serves its cache as stale meanwhile (120 s fresh, 24 h stale; `Commerce::Cache`, unchanged).
- A 401, or a redirect to Zid's login page (the SDK treats both as authentication failures), gives one refresh and one retry, then `needs_reauth` (doc 14).
- Stale data is never served for `AUTH_INVALID`, and `needs_reauth` purges the store's cache.

## 8. Multi-store and multi-tenant

- Several Zid stores can be connected to one account, next to Salla and WooCommerce stores (E2E: one conversation lists WooCommerce, Salla and two Zid stores).
- A Zid store belongs to one account at a time (`provider + external_store_id` unique; ownership rules of `StoreConnection`).
- Cache keys, locks and backoff are per store.
- Webhooks are per store with per-store credentials (doc 15).

## 9. Enabled and disabled

A Zid store is read only when:
- the account has the `lynomia_commerce` plan feature;
- Super Admin → Zid is enabled;
- the store is active.

With Zid switched off, stores are kept, explained in settings, and not listed in conversations; nothing can be connected (`PROVIDER_DISABLED`).

## 10. Files and specs

- Code:
  - `custom/app/services/commerce/providers/zid.rb`, `providers/zid/normalizer.rb`;
  - `custom/app/services/commerce/backoff.rb`;
  - `custom/app/services/commerce/providers/base.rb` (`release` hook).
- Specs:
  - `spec/services/commerce/providers/zid_spec.rb` (15);
  - `spec/controllers/api/v1/accounts/conversations/commerce/zid_panel_spec.rb` (5: auto-link, marketplace, webhook refresh, stale on rate limit, no stale on revoked auth).
- Fixtures: `spec/fixtures/files/commerce/zid/{orders,profile,token}.json`.

## 11. VERIFY

Phase 6 classification of every item: doc 23 §9 (Z-items).

1. `search_term` matches a customer's mobile by its national number (Lynomia sends `551112233`, Zid stores `966551112233`).
2. The zone of `created_at` (store time zone assumed).
3. `sort_by=desc` sorts by creation. The newest-first order is also applied locally within the page of 50.
4. Whether `payment_status` has values beyond the SDK's four (they would show as unknown).
5. The merchant-dashboard order URL pattern, if an "Open in Zid" link is wanted later.
