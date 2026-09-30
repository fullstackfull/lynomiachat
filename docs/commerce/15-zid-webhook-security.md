# Lynomia Commerce: Zid webhook security (Phase 4)

Zid order webhooks only tell Lynomia that a customer's orders changed, so the conversation panel reads them again right away instead of after the 120 s cache freshness. Lynomia keeps no order database and never acts on an order.

**This is HTTP Basic Authentication, not a signature (not HMAC).**
- The body is not signed. The credentials prove the delivery comes from whoever holds the store's pair: Zid, and Lynomia.
- TLS protects them in transit.

## 1. What Zid provides

- **Subscription API.** Per store, with the store's tokens:
  - `GET` / `POST /v1/managers/webhooks` (`event`, `target_url`, `original_id`, optional `conditions`);
  - `DELETE /v1/managers/webhooks?original_id=` removes every subscription of the app with that original id in the store.
  - Sources: official Zid SDK `WebhooksResource`; docs.zid.sa create-a-webhook, list-of-webhooks, delete-a-webhook-by-original-id.
- **Mandatory authentication.** Basic Authentication is mandatory for all webhooks from **2026-09-30** (Zid Partner changelog 57336, "Action Required: Webhook Security Changes by September 30, 2026"), with the credentials given when the webhook is created. The old Phase 1 note "Signature: none documented (VERIFY)" (doc 02 §4) is **closed**.
- **Delivery health.** 10+ failed deliveries in 60 min marks a subscription degraded, 30+ broken; a broken one is recovered with a *new* `target_url` (docs.zid.sa webhook-health-tracking).

**VERIFY (field shape).** The exact request field that carries the username and password could not be read from Zid's documentation here.
- It is set in one place only: `Commerce::Zid::Webhooks#subscription`, currently `authentication: { type: 'basic', username:, password: }`.
- Whatever Zid does with it, a delivery without the store's pair is refused (§3). A wrong field shape can only make deliveries fail (401), never let an unauthenticated one in.
- Deliveries are optional: cached orders refresh after 120 s anyway.
- STOP condition 4 does not apply: secure authentication is configurable, and its exact wire field is the first real-UAT check (doc 17 §6).

## 2. Registration (`Commerce::Zid::Webhooks#register`)

Triggered by `Commerce::Zid::WebhookRegistrationJob` after every connect and re-authorization:

1. Under `Commerce::StoreLock('zid_webhooks', <store id>)` and with the store's tokens (refresh/retry rules of doc 14):
2. `DELETE /managers/webhooks?original_id=<ZID_CLIENT_ID>` removes all of Lynomia's previous subscriptions in this store (404 counts as done).
3. A new pair is generated:
   - username `SecureRandom.hex(16)` (128 bits);
   - password `SecureRandom.urlsafe_base64(48)` (384 bits, 64 characters).
4. The pair is saved in the store's encrypted credentials **before** Zid can use it.
5. `POST /managers/webhooks` once per event (`order.create`, `order.status.update`, `order.payment_status.update`), each with:
   - `target_url = <FRONTEND_URL>/webhooks/zid/<zid store id>`;
   - `original_id = ZID_CLIENT_ID`;
   - the pair.
6. Subscription ids are kept in `metadata.zid_webhooks.ids` with `registered_at`; they are not secrets.

- **Idempotent.** Reconnect or re-authorization never duplicates subscriptions: the delete-then-create always leaves exactly three.
- **Rotated.** Every registration gets a new pair, and the old pair is refused immediately (E2E doc 17 §5).
- Job: Zid/Redis briefly unavailable is retried by Sidekiq; anything else is reported once (`ChatwootExceptionTracker`).
- POST and DELETE are never retried by the HTTP client (`Commerce::HttpClient#post_json`, `#delete`).

## 3. Receipt (`POST /webhooks/zid/:store_id`, `Webhooks::ZidController`)

```
1. authenticate   store = active/disabled/needs_reauth Zid store with that Zid store id (path only: the body is not parsed)
                  HTTP Basic (Rails ActionController::HttpAuthentication::Basic) →
                  secure_compare(username) & secure_compare(password) against the store's pair (both always compared)
                  → 401 on: no Authorization header, not Basic, wrong username, wrong password, another store's pair,
                    unknown store, disconnected store, store without a pair
2. deduplicate    SET NX COMMERCE::ZID::WEBHOOK::<store id>::<sha256(raw body)>  EX 1 day   → duplicate: 200, not queued
3. enqueue        Commerce::Zid::WebhookJob(store id, MessageEncryptor(raw body))  (purpose-bound key from secret_key_base)
4. 200
```

- **Constant time.** `ActiveSupport::SecurityUtils.secure_compare` on both values, combined with a non-short-circuit `&`.
- **Never logged.** Rails does not log the `Authorization` header. The request log shows only the path. Specs and the E2E scan logs for the password and its Base64 form.
- **Before authentication** nothing is parsed: the store id comes from `request.path_parameters`, since touching `params` would parse the JSON body.

## 4. Deduplication

- **Key.** Zid documents no delivery id, so the fingerprint is SHA-256 of the raw body, per store.
  - A redelivery (Zid retries up to 3 times with backoff) has the same body and is acknowledged without being queued again.
  - A real change (new status, payment, `updated_at`) has a different body and is queued.
- **TTL: one day.** It is bounded, never forever: it covers Zid's retry window many times over. A duplicate after a day is harmless, since the job only drops a cache entry.

## 5. The job (`Commerce::Zid::WebhookJob`)

- Unseals the body. A tampered sealed body raises and is never applied.
- Ignores an event whose `store_id` names another store.
- Drops the `ORDERS` cache entry of the event's `customer.id` for that store (`Commerce::Cache.invalidate`). Nothing else: no order is stored, nothing is written to Zid, no customer is linked.
- Why encrypted: an order body carries the customer's name, email and phone, and Sidekiq keeps job arguments in Redis in plaintext.

## 6. Disconnect

`StoreConnection#disconnect` first calls the provider's `release`: for Zid, `DELETE /managers/webhooks?original_id=` with the store's tokens. This is best effort: an unreachable Zid or rejected tokens do not block the disconnect. Then, as for every provider:
- credentials (tokens **and** the webhook pair) are set to nil;
- customer links are deleted;
- cached data is purged;
- status becomes `disconnected`.

Contacts and conversations are kept. Deliveries to a disconnected store get 401.

## 7. Evidence

| Test | Where |
|---|---|
| correct pair → 200 + one encrypted job; missing / wrong username / wrong password / Bearer / another store's pair / unknown / disconnected / no pair → 401; redelivery → one job; password not in logs | `spec/controllers/webhooks/zid_controller_spec.rb` |
| three subscriptions after delete-by-original-id; ≥128-bit username, 384-bit password, encrypted at rest; re-registration rotates and never duplicates; disconnect removes subscriptions, tokens, pair, links and cache and keeps contacts and conversations; unreachable Zid still disconnects | `spec/services/commerce/zid/webhooks_spec.rb` |
| job drops only that customer's orders; other store's event ignored; unsealed body refused | `spec/jobs/commerce/zid/webhook_job_spec.rb` |
| webhook → job → the next panel read shows Zid's new status | `spec/controllers/api/v1/accounts/conversations/commerce/zid_panel_spec.rb` |
| over HTTP against the production build, including rotation after Reconnect | doc 17 §5 |

## 8. VERIFY

1. The create-webhook field for the Basic Auth pair (§1), and whether Zid echoes it in `GET /managers/webhooks`.
2. Whether `order.payment_status.update` is a subscribable event name (Phase 1 marked it VERIFY; the SDK lists `order.create` and `order.status.update`). A subscription Zid refuses fails the registration job, which is reported; the other two still work after a fix.
3. Whether deliveries carry a delivery id header usable for deduplication instead of the body hash.
4. The delivery body shape: order JSON at top level, as assumed by the job, which reads `store_id` and `customer.id` and ignores anything else.
