# Lynomia Commerce: realtime security (Phase 7–8)

What protects the realtime path (doc 24), Customer 360 and order search (doc 25). Earlier provider security docs
(08, 12, 15, 20) still apply. This doc covers what Phase 7–8 adds or relies on.

## 1. Boundaries

- **Inbound.** Store webhooks, from the internet, unauthenticated until proven otherwise.
- **Internal.** Sidekiq job arguments in Redis (plaintext), Redis cache and locks, logs.
- **Outbound to browsers.** ActionCable frames and the Commerce API.

A webhook can never put data into Lynomia: it can only cause Lynomia to read the store again with its own credentials.
The worst outcome of an accepted but misattributed event is one extra read.

## 2. Webhook authenticity: checked before the body is parsed

| Provider | Proof | Store resolved by | On failure |
|---|---|---|---|
| WooCommerce | `X-WC-Webhook-Signature` = base64 HMAC-SHA256(raw body, **this store's** secret), constant-time | path `/webhooks/woocommerce/<lynomia store id>` and that store's own secret | 401 + `commerce.webhook.rejected` |
| Salla | `X-Salla-Security-Strategy: Signature` and hex HMAC-SHA256 with the app's webhook secret; the Token strategy is refused | `merchant` inside the signed body | 401 + `rejected` |
| Zid | HTTP Basic Auth, username and password compared in constant time with **this store's** random pair | path `/webhooks/zid/<zid store id>` and that store's pair | 401 + `rejected` |
| Shopify | `X-Shopify-Hmac-Sha256` base64 HMAC with the app's client secret; `X-Shopify-Webhook-Id` and a valid shop domain required | `X-Shopify-Shop-Domain` | 401 + `rejected`; 400 without a webhook id or a valid shop domain |

- **Unsigned deliveries are refused.** That includes WooCommerce's own creation ping, which is unsigned by design.
  WooCommerce ignores the ping's answer.
- **Cross-store.** A WooCommerce body signed with store A's secret and posted to store B's URL fails, because B's secret
  is used. Zid credentials of store A posted to store B's path fail the same way. This holds across accounts. RSpec and
  the E2E check both directions.
- **Disconnected stores.** Disconnected stores and stores without a secret refuse everything.

## 3. Secrets

- **WooCommerce webhook secret.**
  - Generated per store and per registration (`SecureRandom.hex(32)`).
  - Saved in the store's encrypted credentials (Active Record encryption) before WooCommerce receives it.
  - Sent only in the `POST /wp-json/wc/v3/webhooks` body to that store.
  - Never in the store JSON (only `realtime_status`), never in logs (HttpClient logs method, path, status and time),
    never cached.
  - Removed from the credentials when the key turns out to be read-only.
- **Zid Basic pair, Salla webhook secret, Shopify client secret.** Unchanged (docs 12, 15, 18).
- **E2E check.** Every credential and secret of the run (store keys, tokens, webhook secrets, app secrets) is searched in
  the server, worker and control logs, every API response body and every socket frame: none found (doc 27).

## 4. Replay and duplicates

- **Bounded dedup.** A key per delivery: WooCommerce delivery id (else body), Zid body hash per store, Shopify webhook
  id, Salla body hash. Kept 1 day (3 days for Salla), never forever.
- **Duplicates.** A duplicate is acknowledged (200) and not queued (`commerce.webhook.duplicate`).
- **Replay after the TTL.** Applied again, which is harmless: the refresh reads the store's current state. No event is
  trusted for content.

## 5. Malformed or hostile event content

- **Malformed customer identity.** Not a positive integer, wrong type, injection text: the provider returns `[]`. That
  marks the store's cached orders outdated (store level) and refreshes nobody, so a crafted id can never select another
  customer's link.
- **No content trusted.** Event content is never stored, rendered or used beyond the customer id, which only selects
  which cache entry is outdated. It is not trusted for status, totals or ownership.
- **Encrypted queue arguments.** Webhook bodies are queued encrypted (`Commerce::WebhookQueue`,
  `Commerce::Salla::Webhook`), because Sidekiq keeps arguments in Redis in plaintext.
- **Shopify headers.** `X-Shopify-Shop-Domain` is a header, not covered by the HMAC. A captured authentic body
  re-posted with another shop's domain (and a new webhook id) can at most mark that shop's entry outdated for a
  customer id and cause one extra read. No data crosses shops, because the read uses the target shop's own token and
  re-checks every order's customer (doc 19).

## 6. Realtime events: minimal and per account

- **Payload.** Exactly `{ account_id, contact_id, store_id, updated_at }`. No order data, totals, names, emails, phones,
  addresses or tokens (RSpec and E2E check the keys).
- **Stream.** `account_<id>`, Chatwoot's existing account stream. `RoomChannel` subscribes a user to it only for an
  account the user belongs to (`current_user.accounts.find(account_id)` raises otherwise). A widget visitor never gets
  it (spec `room_channel_commerce_spec.rb`).
- **Client.** The dashboard also drops events whose `account_id` is not the current account.
- **Refetch.** The browser refetches through the Commerce API, which authorizes the conversation. The event grants
  nothing.
- **Accepted exposure.** Within one account, an agent who cannot see the conversation still receives the ids, because
  the event goes to the whole account stream. They learn that contact #n had a commerce update in store #s, and nothing
  else; the refetch is refused (401). This is less than Chatwoot's own account-wide `contact.updated` events, which
  carry the contact's name, email and phone. Agents of another account receive nothing (E2E: zero frames).

## 7. Stale data after an authorization failure

- **Rejected credentials.** A refresh, panel read or search that gets `AUTH_INVALID` flags the store `needs_reauth` and
  purges its cache (`credentials_rejected`).
- **Display.** Customer 360 lists such a store with state `needs_reauth`, `orders_count: nil` and none of its orders.
  The store view hides the store. The outage fallback (stale cache) never applies to auth errors.
- **Provider switched off.** The store is not contacted and nothing cached is shown ("hard off").

## 8. Manual Refresh

- **Rate limit.** One forced read per contact and view per 30 s, shared by every agent; then 429 + `Retry-After`.
  This bounds how often agents can make Lynomia call a store.
- **Provider backoff.** Never bypassed (`Commerce::Backoff`). A store in backoff answers from its stale cache.
- **Scope.** `store_id` must be an active store of an enabled provider in the conversation's account, else 404.

## 9. Order search

- **Input.** Accepted only as `#?\d{1,20}`; anything else is 422 before any store is called. There is nothing to inject
  into a REST path or a search string.
- **Shopify.** The number travels inside the same escaping helper as emails and phones (`name:"<n>"`, backslash and
  quote escaped) and as a GraphQL variable, never interpolated into the query document.
- **No scans.** Exact per-provider lookups only, bounded concurrency, 10 s budget.
- **Results.** Without the customer, not cached, not linked; no "Send tracking" on them (the order may be another
  customer's).
- **Limits.** 10 searches per agent per minute; every search audited (`commerce.orders_searched`: number, stores,
  result count; no PII).

## 10. Identity safety

- **No combined identities.** Customer 360 places per-store links side by side and never merges stores by name or
  heuristics. A store link only ever comes from that store's exact match or an agent's explicit choice.
- **Unlink holds.** The suppressed row stops auto-linking and refreshing for that contact and store.
- **Audit without PII.** Link, change, unlink and suppression are audited with match sources and ids only.

## 11. Tests

| Concern | Where |
|---|---|
| Forged deliveries, all four providers: nothing outdated, refreshed or broadcast; rejected metric | `spec/controllers/webhooks/commerce_realtime_security_spec.rb` |
| Replay: acted on once per provider, accepted + duplicate metrics | same |
| Cross-store and cross-account deliveries (WooCommerce, Zid) | same |
| Another account linking the same store customer id gets no refresh or event | same |
| Malformed identity → store level, nobody refreshed | same |
| Stale data after auth failure | same, `overviews_controller_spec.rb`, `realtime_spec.rb` |
| WebSocket isolation (other account, widget visitor) | `spec/channels/room_channel_commerce_spec.rb` |
| Event payload keys only | `realtime_spec.rb`, security spec, E2E |
| Order search injection, escaping, scope, rate limit, audit | `orders_controller_spec.rb`, `shopify/search_query_spec.rb` |
| Refresh cooldown, backoff, scope | `refreshes_controller_spec.rb` |
| Per-provider signature details (existing) | `woocommerce_controller_spec.rb`, `salla_controller_spec.rb`, `zid_controller_spec.rb`, `shopify_commerce_controller_spec.rb` |
| Live: forged pings, replay, out-of-order, revoked access, tenants, secret scan | E2E (doc 27) |
