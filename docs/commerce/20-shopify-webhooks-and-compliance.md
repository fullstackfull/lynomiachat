# Lynomia Commerce: Shopify webhooks and the privacy topics (Phase 5)

The Lynomia Commerce Shopify app receives a minimal set of webhooks:
- order events, used only to drop cached reads;
- `app/uninstalled`;
- Shopify's three mandatory privacy topics.

There is no local order database, and webhooks never write orders anywhere.

## 1. Registration: app-specific subscriptions

The subscriptions are declared **once in the app's configuration** (`docs/commerce/shopify.app.toml.example`, deployed with `shopify app deploy`) and apply to every shop that installs the app:

| Subscription | Topics | URI |
|---|---|---|
| Orders and lifecycle | `orders/create`, `orders/updated`, `app/uninstalled` | `<FRONTEND_URL>/webhooks/shopify_commerce` |
| Compliance | `customers/data_request`, `customers/redact`, `shop/redact` | the same |

Why this and not `webhookSubscriptionCreate` per shop:
- **No per-install duplication.** Nothing is created or deleted per shop, so nothing can drift or be left behind on disconnect.
- **Strictly read-only.** The connector sends no mutation at all, not even for subscriptions.
- **Required for the App Store.** The compliance topics can only be declared in the app configuration.

The webhook `api_version` is `2026-07`, the same pin as the API.

Topics **not** subscribed:
- `orders/paid`, `orders/fulfilled` and `orders/cancelled` all change the order, and `orders/updated` already fires for them.
- `fulfillments/create` and `fulfillments/update` need `read_fulfillments`, a scope the connector does not otherwise need (doc 18 §7). A tracking-only change that does not update the order is picked up when the 120 s cache entry expires.
- `customers/update`: customer changes do not affect cached orders.

## 2. Receiving: `POST /webhooks/shopify_commerce`

`Webhooks::ShopifyCommerceController`: authenticate, deduplicate, queue. Nothing heavy runs in the request.

1. **HMAC before parsing.** `X-Shopify-Hmac-Sha256` must equal `base64(HMAC-SHA256(raw body, Commerce client secret))`, compared in constant time (`Commerce::Shopify::Webhook.authentic?`). Otherwise the answer is 401 and the body is never parsed. A missing header, a wrong or hex-encoded value, a body changed after signing, or the legacy app's secret all get 401.
2. **Shape.** `X-Shopify-Webhook-Id` must be present and `X-Shopify-Shop-Domain` must be a valid myshopify.com domain. Otherwise the answer is 400.
3. **Dedup.** `Commerce::WebhookQueue` (shared with Zid) sets `COMMERCE::SHOPIFY::WEBHOOK::<sha256(webhook id)>` with NX for 1 day.
   - `X-Shopify-Webhook-Id` is the same across Shopify's retries of one delivery, so a retry is acknowledged (200) without being queued again.
   - No body fingerprint is needed, since Shopify always sends the id.
   - The key expires: nothing is remembered forever.
4. **Queue.** `Commerce::Shopify::WebhookJob` gets the topic, shop domain, `X-Shopify-Triggered-At` and the body **encrypted** (Sidekiq keeps arguments in Redis in plaintext, and payloads carry emails and phones). An unknown topic is acknowledged and dropped. The answer is 200.

The privacy topics and `app/uninstalled` are accepted whatever the provider switch says: they must be honoured even when Shopify Commerce is switched off.

## 3. Handling (`Commerce::Shopify::WebhookJob`)

- **Finding the store.** The store is found by `base_url = https://<shop domain>`.
- **Trusting the payload.** Shopify's headers are not covered by the HMAC, only the body is. So every removal acts only when the **shop id in the signed body** is the store's `external_store_id`.
- **Stale events.** `app/uninstalled` and `shop/redact` are ignored for a store authorized again after the event was triggered (`verified_at > X-Shopify-Triggered-At`), since the merchant reinstalled.

| Topic | What happens | What is kept |
|---|---|---|
| `orders/create`, `orders/updated` | The customer's cached orders are dropped (`customer.id`, or `guest:<email>` for a guest checkout), so the panel reads Shopify again. Disconnected stores are ignored. | Everything |
| `app/uninstalled` | `StoreConnection#disconnect`: status `disconnected`, token pair removed, customer links deleted, cache purged. Audit `commerce.shopify.uninstalled`. | Store row (can be reconnected), contacts, conversations |
| `customers/redact` | That customer's links in this store (registered id and `guest:<email>`) are deleted and the store cache is purged. Audit `commerce.shopify.customer_redacted` with the **count** only. | Contacts, conversations, other customers' links |
| `customers/data_request` | Nothing is removed. Audit `commerce.shopify.customer_data_requested` with the ids of the customer's links and Shopify's `data_request.id`, for the operator's export (§4). | Everything |
| `shop/redact` | The store row is deleted: token, links and cache go with it. Audit `commerce.shopify.shop_redacted` on the **account**, with the store id and the link count. | Contacts, conversations, the account audit entry |

Chatwoot contacts and conversations are never deleted by these topics.

## 4. What Lynomia holds about a Shopify customer (data requests)

For a Shopify customer, Lynomia Commerce stores:
- **`commerce_customer_links`**: which Chatwoot contact is linked to which store customer:
  - `external_customer_id` is the Shopify customer number or `guest:<email>`, encrypted, deterministic;
  - plus how it was matched, who confirmed it, and when.
- **The Redis cache**: provider-neutral order summaries and candidates, 120 s fresh and 24 h at most, then gone.
- **`commerce_stores`**: the shop, not the customer: the encrypted token pair, the shop name and domain.

Shopify's contract for `customers/data_request` ([Shopify: privacy law compliance](https://shopify.dev/docs/apps/build/compliance/privacy-law-compliance)):
1. The topic is declared in the app configuration.
2. The app answers 200 to a genuine delivery and 401 to one with an invalid HMAC. Shopify's automated app review sends a bad HMAC to the compliance endpoints and expects the 401.
3. The app provides the data to the store owner directly within 30 days.

Shopify prescribes no API or automated response for step 3, so an operator-assisted fulfilment meets the contract, for the App Store and for custom distribution alike (decision recorded in doc 23 §5). Lynomia does 1 and 2 automatically. For 3:
1. The job records `commerce.shopify.customer_data_requested` on the store with Shopify's `data_request_id` and the **ids of the customer's links** in that store, registered and guest. No email, phone or customer number is recorded. The ids are what makes the export possible after the payload is gone.
2. The operator exports those links, within 30 days, as JSON for the merchant (the account's administrators):
   ```
   bundle exec rails runner docs/commerce/ops/shopify_data_request_export.rb <data_request_id>
   ```
   An empty list means Lynomia holds no link for that customer. Cached order summaries expire within 24 h and are not retained.
3. The operator sends the export to the merchant and records the date.

The audit lives in the Enterprise audit log, and Lynomia runs the Enterprise overlay. In the Community edition only a log line is written, without the ids.

## 5. Evidence

- **Specs:**
  - `spec/controllers/webhooks/shopify_commerce_controller_spec.rb`: valid; missing, wrong, other-secret and hex signatures; modified body; not-JSON; dedup by webhook id with a bounded TTL; 400 on shape; privacy topics accepted with the provider off; the legacy endpoint refusing the Commerce signature and vice versa.
  - `spec/jobs/commerce/shopify/webhook_job_spec.rb`: order invalidation for customers and guests; uninstall; body shop-id binding; reinstall ordering; customer redaction with counts-only audit; data request; shop redaction; legacy hooks untouched; tampered sealed body.
- **E2E:** doc 22 §2 G and I, with real HTTP deliveries signed like Shopify's.
