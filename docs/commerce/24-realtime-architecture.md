# Lynomia Commerce: realtime architecture (Phase 7–8)

How a change in a connected store reaches an agent's open conversation without a reload. Security of the same path is
in [26-realtime-security.md](26-realtime-security.md); Customer 360 in [25-customer-360.md](25-customer-360.md); the
E2E in [27-phase7-8-e2e.md](27-phase7-8-e2e.md).

## 1. Principles

- **A webhook is a signal, not data.** The store's API stays the source of truth. No event body is stored as an order,
  and nothing in Postgres holds orders. An event only says "this customer's orders changed".
- **No event state machine.** Events can arrive late, twice or out of order. Every refresh reads the current state from
  the store, so ordering never matters.
- **One shared path for every provider.** Providers only parse their own events. Authentication, deduplication,
  invalidation, coalescing, refresh and broadcast are provider-neutral (`Commerce::Realtime`). The UI has no provider
  branching.
- **Existing infrastructure only.** Sidekiq jobs, the Redis cache, and Chatwoot's ActionCable account stream. There is
  no new WebSocket server and no new tables or migrations.

## 2. Flow

```
store ──webhook──▶ /webhooks/<provider>[/<store>]       authenticate (before parsing), 401 otherwise
                     │                                  deduplicate (Redis SET NX, bounded TTL), 200 for a duplicate
                     ▼                                  queue the body encrypted (Commerce::WebhookQueue / Salla::Webhook)
                   <Provider>::WebhookJob               identify the store (path, merchant id or shop domain)
                     │
                     ▼
                   Commerce::Realtime.order_event       provider.event_customer_ids(payload)
                     │  ├─ ids named   → mark those customers' cached orders outdated
                     │  └─ none named  → mark every customer's cached orders of the store outdated (store level)
                     ▼
                   schedule_refresh(link)               only for links (not suppressed) of a named customer;
                     │                                  lock per link + "pending" flag: at most 2 reads per burst
                     ▼  (at once; a coalesced re-run after COALESCE_WINDOW = 2 s)
                   Commerce::RefreshJob → Realtime.refresh
                     │  read the orders from the store (cache write; stale fallback on outage)
                     │  broadcast commerce.customer.updated to "account_<id>"
                     │  pending flag set meanwhile? → exactly one more refresh
                     ▼
                   ActionCable (existing RoomChannel)   agents of that account only
                     ▼
                   dashboard: actionCable.js → bus event → CommercePanel
                     │  same contact (and, in the store view, same store)? debounce 500 ms
                     ▼
                   GET the open view again (Commerce API, authorized as usual), silently
```

## 3. Provider capability interface

`Commerce::Providers::Base` declares what a provider can do. The core and the UI read these declarations and never
check a provider's name.

| Method | Meaning | WooCommerce | Salla | Zid | Shopify |
|---|---|---|---|---|---|
| `self.supports_realtime?` | Its order events reach the realtime core | yes | yes (KEEP VERIFY) | yes | yes |
| `self.registers_webhooks?` / `register_webhooks` | Lynomia creates the store's webhooks with the store's own credentials | yes (needs a Read/Write key) | no (app events, Salla Partner Portal) | no (registered by its OAuth flow, doc 15) | no (`shopify.app.toml`) |
| `release` | Removes what Lynomia set up in the store before a disconnect | deletes its webhooks | — | unregisters (existing) | — |
| `event_customer_ids(payload)` | Store customer ids the event is about, as links keep them; `[]` when it names none | `customer_id`, or every guest identity of the order (`guest:<email/phone>`) | `data.customer.id` | `customer.id` | `customer.id`, or `guest:<email>` |
| `event_order_id(payload)` | For logs and metrics only | `id` | `data.id` | `id` | `id` |
| `self.searches_orders?` / `find_orders(number)` | Exact lookup by order number, never a scan (doc 25 §7) | yes | no | yes | yes |

A malformed id (not a positive integer, wrong type) makes `event_customer_ids` return `[]`. That is the store-level
fallback; nothing is refreshed.

## 4. Event sources per provider

| Provider | Events | Authentication | Dedup key | Registration |
|---|---|---|---|---|
| WooCommerce | `order.created`, `order.updated`, `order.deleted` | `X-WC-Webhook-Signature` = base64 HMAC-SHA256 with a per-store secret | `X-WC-Webhook-Delivery-ID`, else the body | Lynomia creates 3 webhooks named "Lynomia Commerce" after connect, key rotation and re-enable (`Commerce::WebhookRegistrationJob`); deleted on disconnect |
| Salla | `order.*`, `shipment.*` store events on the existing app webhook URL | `X-Salla-Signature` hex HMAC with the app's webhook secret (Signature strategy only) | body hash (3 days) | App settings in the Salla Partner Portal. **KEEP VERIFY**: the store-event payload shape on a live store (doc 23) |
| Zid | `order.create`, `order.status.update`, `order.payment_status.update` | HTTP Basic Auth with the per-store random pair Lynomia gave Zid | body hash per store | Existing per-store subscription (doc 15). No shipment event is assumed: none is documented |
| Shopify | `orders/create`, `orders/updated` (plus app/uninstalled and compliance, unchanged) | `X-Shopify-Hmac-Sha256` base64 HMAC with the app's client secret | `X-Shopify-Webhook-Id` | `shopify.app.toml`. No new topic and no new scope: fulfillment and payment changes update the order, so `orders/updated` covers them |

**WooCommerce key permission (decision).** WooCommerce creates webhooks only for a key with write permission. A Read
key gets 401 on `POST /webhooks` (verified against the WooCommerce 10.9.4 source and in the real E2E). Lynomia
therefore:

- never asks for more than it needs: a Read key keeps working as before (cache plus Refresh), and the store's settings
  row says "Live order updates off: this key is read-only";
- with a Read/Write key, creates its webhooks and never writes anything else. Every other write in the provider is
  still impossible: the surface spec allows `POST`/`DELETE` on `/webhooks` only.

The secret is generated per store (`SecureRandom.hex(32)`), saved encrypted with the store's credentials before
WooCommerce can use it, sent only to WooCommerce, and never rendered, logged or cached. WooCommerce sends an unsigned
"ping" when a webhook is created. It is refused (401) like any unsigned delivery, which WooCommerce tolerates. A store
whose webhooks are deleted by its merchant simply stops getting live updates (WooCommerce does not retry, and disables
a webhook after 5 consecutive failures). The Refresh button and the 120 s cache still apply.

## 5. Cache invalidation

Keys stay `COMMERCE::V1::ACCOUNT::<a>::STORE::<s>::<KIND>::<HMAC(id)>` (doc 07), so invalidation is naturally scoped to
account, store and external customer.

- **Customer level** (`Commerce::Cache.invalidate`): the event names the customer. Only that customer's `ORDERS` entry
  in that store is touched.
- **Store level** (`invalidate_all(store, :orders)`): the event names no customer (WooCommerce `order.deleted`, a Salla
  `shipment.*` without a customer, a malformed id). Every customer's orders of that store, and nothing else.
- **Outdated, not deleted.** An invalidated entry gets `"outdated": true` (same TTL, `KEEPTTL`). Its next read goes to
  the store. If the store is down, the entry is still served as stale, with the time it was fetched. Deleting it would
  have shown an outage as "no orders" (found while building the outage E2E).
- **Deleted** only where data must go: disconnect, rejected credentials (`credentials_rejected`), Shopify
  `customers/redact` and `shop/redact`.

## 6. Refresh and coalescing

- `schedule_refresh(link)` takes `COMMERCE::REFRESH::ACCOUNT::<a>::STORE::<s>::LINK::<id>` (`SET NX EX 60`) and
  enqueues `Commerce::RefreshJob` at once. If the lock is held, it sets `::PENDING` instead and counts
  `commerce.refresh.coalesced`.
- `refresh(link)` clears `::PENDING`, reads the orders, broadcasts, then either releases the lock or, if an event
  arrived meanwhile, marks the entry outdated and runs exactly once more, `COALESCE_WINDOW` (2 s) later. A burst of N
  events makes 1–2 store reads.
- The first refresh is not delayed on purpose. A delayed job goes through Sidekiq's scheduled set, which is polled
  about every 5 s. The first E2E runs, which delayed every refresh by 2 s, measured 5.5–7 s from delivery to the
  agent's screen.
- Refreshes run only for confirmed links (`not_suppressed`) of an active store of an enabled provider. There are no
  full-store scans: one `list_customer_orders` call (the provider's bounded page) per refresh.
- `RefreshJob` has `retry: false`. Store errors are handled inside: `AUTH_INVALID` flags the store for
  re-authorization and purges its cache, and the next event or open reads again. The lock always ends, released or
  expired.
- Provider backoff (`Commerce::Backoff`: Salla, Zid, Shopify) applies to refreshes like any other read. A refresh
  never bypasses it, and gets the stale fallback.

## 7. Broadcast and frontend

- `ActionCableBroadcastJob.perform_later(["account_<id>"], "commerce.customer.updated", { account_id, contact_id,
  store_id, updated_at })`. No order data, contact detail or token. This is the existing account stream: only agents of
  that account subscribe to it (`RoomChannel` resolves the account through the user's own accounts). The client also
  drops events whose `account_id` is not the current account (`isAValidEvent`).
- `actionCable.js` relays the event on the dashboard bus (`BUS_EVENTS.COMMERCE_CUSTOMER_UPDATED`). `CommercePanel`
  listens while mounted:
  - it ignores other contacts, and in the store view other stores;
  - it debounces 500 ms, so the events of several stores make one request;
  - it then refetches its open view silently (no spinner; an agent's search is kept).
- Events are not replayed after a disconnect, so the panel reads its open view again on `WEBSOCKET_RECONNECT`.
- The refetch is an ordinary Commerce API call. Visibility rules are unchanged, so an agent who cannot see the
  conversation gets 401 even if the event reached their browser.

## 8. Manual Refresh

`POST .../conversations/:id/commerce/refresh[?store_id=]` reads the open view (Customer 360, or one store) from the
stores even when the cache is fresh (`force: true`). It is rate-limited per contact and view: one refresh per 30 s,
shared by everyone viewing it (`SET NX EX`). Within that window the endpoint returns 429 with `Retry-After`, and the
panel says "Just refreshed. Try again in N s.". Provider backoff still applies, and a refused store answers with its
last data marked stale.

## 9. Switches

| Switch | Effect |
|---|---|
| `COMMERCE_REALTIME_ENABLED=false` (installation config, else ENV; default on) | No refreshes and no broadcasts. Webhooks are still authenticated, deduplicated and applied to the cache (outdated), so the next open or Refresh shows the change. An internal kill switch, not an entitlement |
| Provider switch off (`SALLA_ENABLED`, …) | The provider is not contacted. Its stores show "Provider currently unavailable" with no cached data |
| Store disabled or needing re-authorization | No refresh. Overview shows the state, no data |
| `lynomia_commerce` feature off for the account | Every Commerce endpoint (overview, refresh, orders, stores) answers 401. No new billing feature was added |

## 10. Telemetry

`Commerce::Metrics.event` emits one `ActiveSupport::Notifications` event (for an APM subscriber) and one structured log
line `[Commerce] metric=<name> k=v…`. Fields are ids, counts, codes and durations only.

| Metric | Where | Fields |
|---|---|---|
| `commerce.cache.hit` / `commerce.cache.miss` | `Commerce::Cache.fetch` | store_id, kind, forced |
| `commerce.provider.request` | `Commerce::HttpClient` (every provider call) | client, method, path, status, ms |
| `commerce.provider.error` | refresh failures | provider, store_id, code |
| `commerce.webhook.accepted` / `.duplicate` / `.rejected` | webhook endpoints and queues, all four providers | provider (store_id when known) |
| `commerce.webhook.applied` | `Realtime.order_event` | provider, store_id, customers |
| `commerce.refresh.coalesced` | `schedule_refresh` | store_id, link_id |
| `commerce.customer360.load` | `Customer360#call` | account_id, stores, failed, ms |

## 11. Failure modes

| Situation | Behavior |
|---|---|
| Unsigned, forged, cross-store delivery | 401 before parsing; `webhook.rejected`; nothing queued |
| Same delivery again | 200, not queued (`webhook.duplicate`) |
| Burst for one customer | One refresh, at most one more |
| Event older than the store's state | Irrelevant: the refresh reads the store |
| Store down at refresh time | Previous orders shown stale with their time; banner "Couldn't refresh store data right now." |
| Credentials revoked | Store flagged "needs re-authorization", cache purged, overview lists the state with no orders (auth outranks cache) |
| Worker down | Webhooks still accepted and deduplicated; cache unchanged until jobs run; panel refreshes on open (120 s TTL) or Refresh |
| WebSocket down | No live update; the panel reads again on reconnect |
| Realtime switched off | Cache outdated only; Refresh shows the change |
