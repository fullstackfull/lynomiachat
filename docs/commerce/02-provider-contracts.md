# Lynomia Commerce: normalized contracts and provider mapping

- Nothing here is implemented yet.
- Normalized objects are **plain Ruby value objects** (`Data.define`, Ruby 3.4), not database models. Only `Commerce::Store` and `Commerce::CustomerLink` are persisted (`01` §5).
- `VERIFY` = confirm on the official page before coding (see `00` §0). Every item's Phase 6 status is in doc 23 §9.

## 1. Normalized objects (serialized to the frontend as JSON)

```text
CommerceStore      id, provider, name, domain, status
CommerceCustomer   store_id, external_id (nullable for guests), name, email, phone_e164,
                   orders_count?, total_spent?, admin_url?
CommerceOrder      store_id, provider, external_order_id, order_number, customer (CommerceCustomer, minimal),
                   status (canonical), status_label (provider text, localized), payment_status (canonical),
                   payment_method_label?, currency, total (decimal string), subtotal?, items [CommerceOrderItem],
                   created_at (UTC ISO8601), updated_at (UTC ISO8601, nullable when provider lacks it),
                   shipments [CommerceShipment], refunds [CommerceRefund],
                   links { admin_order_url, customer_order_url? }
CommerceOrderItem  name, sku?, quantity, unit_price?, total?, image_url?
CommercePayment    (embedded in order in MVP: payment_status + payment_method_label)
CommerceShipment   provider (carrier name), status (canonical), status_label, tracking_number?, tracking_url?,
                   shipped_at?
CommerceRefund     amount, currency, reason?, created_at
```

### Canonical enums

The provider's raw value is always kept in `*_label`; unmapped values become `unknown`.

| Enum | Values |
|---|---|
| `status` | `pending` (awaiting payment or confirmation), `processing`, `on_hold`, `shipped`, `delivered`, `completed`, `cancelled`, `refunded`, `failed`, `unknown` |
| `payment_status` | `paid`, `pending`, `partially_paid`, `partially_refunded`, `refunded`, `failed`, `voided`, `unknown` |
| shipment `status` | `pending`, `in_transit`, `delivered`, `returned`, `cancelled`, `unknown` |

## 2. Connector contract (Ruby, one class per provider)

**Naming follows repo conventions:** a `Base` class with one subclass per provider (like `Crm::BaseProcessorService`), and service objects with `perform` for single operations.

```ruby
# custom/app/services/commerce/providers/base.rb   (Phase 2)
class Commerce::Providers::Base
  def initialize(store) = @store = store

  # connection lifecycle
  def self.authorization_url(state:, redirect_uri:)           # OAuth providers; WooCommerce: wc-auth URL
  def self.complete_authorization(params:)                    # -> { external_store_id:, name:, domain:, credentials:, expires_at: }
  def refresh_credentials!                                     # rotating refresh under Commerce::CredentialRefresher lock
  def health                                                   # cheap identity call; used by Settings → Stores "Test"
  def disconnect!                                              # provider-side revoke/unsubscribe when supported; purge cache

  # read-only data
  def find_customers(phone_e164: nil, email: nil)             # -> [CommerceCustomer] (exact-match only, see 03)
  def list_customer_orders(customer:, limit: 5)                # -> [CommerceOrder] newest first
  def fetch_order(external_order_id)                           # -> CommerceOrder (with items + shipments)

  # webhooks
  def self.verify_webhook(request, store: nil)                 # -> true/false (constant-time)
  def self.resolve_store(request, params)                      # -> Commerce::Store or nil
  def self.parse_webhook(request)                              # -> Commerce::WebhookEvent(kind:, dedup_key:, external_order_id:, occurred_at:)
end
```

- **Mappers:** `Commerce::Providers::<Name>::OrderMapper` maps raw data → `CommerceOrder`, and is covered by fixture-based specs recorded from real sandbox responses.
- **Error taxonomy** (shared):
  - `Commerce::Errors::AuthExpired`: sets `needs_reauth` and triggers the `Reauthorizable` e-mail.
  - `RateLimited(retry_after)`.
  - `NotFound`.
  - `ProviderUnavailable` (timeouts, 5xx).
  - `InvalidResponse`.
- **HTTP:** every call has timeouts (connect 3 s, read 8 s) and goes through `SafeFetch` or an equivalent guard for merchant-supplied hosts (WooCommerce), so private and loopback addresses are refused.

## 3. Salla

**Auth**
- Facts:
  - OAuth2 at `accounts.salla.sa/oauth2/{auth,token}` (https://docs.salla.dev/421118m0).
  - **Easy Mode**: tokens are delivered by the `app.store.authorize` webhook `{event, merchant, created_at, data:{access_token, expires, refresh_token, scope}}` (https://docs.salla.dev/421413m0).
  - Access token lives **14 days**.
  - The **refresh token is single-use and rotating**. Reuse or a parallel refresh returns `invalid_grant` and revokes access, and the merchant must reinstall (https://docs.salla.dev/421123m0). Its lifetime is 1 month per the docs **VERIFY**.
  - Refresh tokens need the `offline_access` scope.
  - Store identity: `GET accounts.salla.sa/oauth2/user/info` → `merchant.id` (https://docs.salla.dev/9466620e0).
  - Salla's kit says Custom Mode is for development only.
- Decisions:
  - Use Easy Mode; our app-level webhook endpoint receives the authorize event.
  - Refresh proactively at T−48h, under a per-store lock, and persist the rotated pair atomically.

**Scopes:** `orders.read`, `customers.read`, `shipping.read`, `offline_access` (optional: `carts.read`, `webhooks.read_write`).

**APIs** (`https://api.salla.dev/admin/v2`)

| Call | Endpoint | Notes |
|---|---|---|
| Customers | `GET /customers?keyword=<966…>` | Matches mobile, email or name. The API search is broad, so an exact match is re-checked locally (`03`). |
| Orders | `GET /orders?customer_id=` | |
| Order detail | `GET /orders/{id}` | **Light format since 2026-09-01**: no items or shipments. |
| Items | List Order Items | Path **VERIFY** |
| Shipments | `GET /shipments?order_id=` | `courier_name`, `tracking_number`, `tracking_link`, `status`, `trackable` |

**Webhooks**
- App events arrive at the Partner Portal URL. Store events need a subscription (Portal, or `POST /webhooks/subscribe`).
- Security strategy **Signature**: `X-Salla-Signature` = HMAC-SHA256(raw body, webhook secret), plus `X-Salla-Security-Strategy`.
- Retries: 3 × ~5 min.
- No event id, so dedup on `merchant:event:sha256(body)` (https://docs.salla.dev/421119m0).

**Rate limits**
- Per-plan leaky bucket, with `X-RateLimit-*` headers and 429 + `Retry-After`.
- Customers endpoints have a separate cap of 500 requests / 10 min (https://docs.salla.dev/421125m0).

**Phone:** customer `mobile` is local and `mobile_code` is `+966`, so E.164 = `mobile_code + mobile` (https://docs.salla.dev/5394122e0).

| Normalized | Salla |
|---|---|
| external_order_id | `id` |
| order_number | `reference_id` |
| customer | `customer.{id, first_name, last_name, mobile_code+mobile, email}` (present in light format? **VERIFY**) |
| status / label | `status.slug` / `status.customized.name` or `status.name` |
| payment_status | derived from `is_pending_payment`, `status.slug == payment_pending` and the transactions API (**VERIFY**) |
| currency / total | `amounts.total.currency` / `amounts.total.amount` |
| items | List Order Items `{name, sku, quantity, amounts.total}` |
| created_at / updated_at | `date.date` + `date.timezone` / **VERIFY** (fallback: status history or webhook time) |
| shipment | `/shipments?order_id=` → `courier_name`, `status`, `tracking_number`, `tracking_link` (only when `trackable`) |
| links | `urls.admin` / `urls.customer` |

**Status mapping:**

| Salla | Canonical |
|---|---|
| `payment_pending` | pending |
| `under_review` | on_hold |
| `in_progress` | processing |
| `shipped`, `delivering` | shipped |
| `delivered` | delivered |
| `completed` | completed |
| `canceled` | cancelled |
| `restoring` | processing |
| `restored` | refunded (**VERIFY**) |

## 4. Zid

**Auth**
- Facts:
  - OAuth2 authorization code (https://docs.zid.sa/authorization). The host is `oauth.zid.sa` or `api.zid.sa` (**VERIFY**).
  - **Two tokens**:
    - `authorization`, sent as `Authorization: Bearer`: identifies the partner app.
    - `access_token`, sent as `X-Manager-Token`: store-scoped.
  - Both last **1 year**.
  - ~~The refresh token is single-use~~ (help-partner article). **Superseded in Phase 4:** Zid's official agent skill and SDK do not document single-use refresh tokens, so Lynomia does not assume it either way (doc 14 §5).
  - Store identity: `GET /v1/managers/account/profile` (https://docs.zid.sa/get-manager-profile). The store is `user.store.{id, title, url, timezone}` (official SDK model, Phase 4).
- Headers: `Authorization`, `X-Manager-Token`, `Accept-Language`. Whether `Store-Id` and `Role` are needed on manager endpoints is **VERIFY**.

**Scopes:** `orders.read`, `customers.read` (or `third_customers_read`), `webhooks.read_write` (to subscribe), `abandoned_carts.read` (later). Scopes are chosen in the Partner Dashboard (**VERIFY**).

**APIs** (`https://api.zid.sa/v1`)

| Call | Endpoint | Notes |
|---|---|---|
| Orders | `GET /managers/store/orders` | Filters include `customer_id`, `customer_phone`, `payload_type`, dates, status. Exact-match semantics of the phone filter **VERIFY**. |
| Order | `GET /managers/store/orders/{id}/view` | |
| Customers | `GET /managers/store/customers` | Cursor pagination; the filter for mobile or email is **VERIFY** |
| Refunds | `GET /managers/store/orders/{id}/credit-notes` | |
| Marketplace orders | | Customer PII is **masked** |

**Webhooks**
- Per-store subscription: `POST /v1/managers/webhooks` with `{event, target_url, original_id, subscriber, conditions}`.
- Events:
  - `order.create`, `order.status.update`;
  - `order.payment_status.update` (**VERIFY**);
  - customer events (**VERIFY**);
  - abandoned cart phases;
  - app lifecycle `app.market.application.{install, uninstall, authorized}` (Partner Dashboard).
- **Authentication (closed in Phase 4):** HTTP Basic Authentication, mandatory for all Zid webhooks from 2026-09-30 (Zid Partner changelog 57336). Lynomia registers a per-store random username/password and refuses deliveries without it (doc 15). The earlier "Signature: none documented (VERIFY)" note is closed.
- Retries: 3 attempts with exponential backoff. **Circuit breaker**: 10 failures in 60 min marks the endpoint degraded, and recovery requires a *new* `target_url` (https://docs.zid.sa/webhook-health-tracking-2197281m0).

**Rate limits:** 60 requests/min per app per store (leaky bucket), enforced on product endpoints today (https://docs.zid.sa/rate-limiting-644369m0).

| Normalized | Zid |
|---|---|
| external_order_id | `id` |
| order_number | `id` (**VERIFY** vs `invoice_number` or `code`) |
| customer | `customer.{id, name, email, mobile}` (masked for marketplace orders) |
| status / label | `order_status.code` / `order_status.name` |
| payment_status | `payment_status` (full value set **VERIFY**) |
| currency / total | `currency_code` / `order_total` |
| items | `products[]` (needs a non-`simple` `payload_type`) |
| created_at / updated_at | `created_at` / `updated_at` (timezone **VERIFY**) |
| shipment | `shipping.method.name`; `shipping.method.tracking.{number, status, url}` (path **VERIFY**) |
| links | admin URL built from a dashboard pattern (**VERIFY**) / `order_url` (customer invoice) |

**Status mapping:**

| Zid | Canonical |
|---|---|
| `new` | pending |
| `preparing`, `ready` | processing |
| `indelivery` | shipped |
| `delivered` | delivered |
| `cancelled` | cancelled |
| `reversed` | refunded |
| custom statuses | unknown, with label |

## 5. WooCommerce (REST API v3)

**Auth**
- Consumer key/secret: HTTPS Basic auth, falling back to query-string auth.
- **wc-auth approval flow** `/wc-auth/v1/authorize?app_name&scope=read&user_id&return_url&callback_url`:
  - WooCommerce POSTs `{key_id, user_id, consumer_key, consumer_secret, key_permissions}` to our **HTTPS** callback.
  - The callback must answer exactly 200, or the key is deleted.
  - Sources: `woocommerce-rest-api-docs/source/includes/wp-api-v3/_authentication.md`; `woocommerce/plugins/woocommerce/includes/class-wc-auth.php`.
- Keys **never expire** (revocable), so there is no refresh.

**APIs** (`{home}/wp-json/wc/v3`)

| Call | Endpoint | Notes |
|---|---|---|
| Orders | `GET /orders?customer=&search=&status=&per_page≤100` | `search` covers billing email and phone (legacy storage; HPOS ≥ ~9.4 **VERIFY**) |
| Customers | `GET /customers?email=&role=all` | **Phone is not searchable. Guests are not customers**, so guests are found through order `search`. |
| Refunds | `GET /orders/{id}/refunds` | |

**Tracking: not in core.**
- Official Shipment Tracking extension: `GET /wp-json/wc-shipment-tracking/v3/orders/{id}/shipment-trackings`, fields `tracking_provider, tracking_number, tracking_link, date_shipped`.
- Core "Order Fulfillments" (beta, feature flag): `GET /wc/v3/orders/{id}/fulfillments`, with meta `_tracking_number, _tracking_url, _shipment_provider`.
- Other plugins use arbitrary `meta_data` keys.
- **Decision:** a per-store `settings.tracking_source`, one of `shipment_tracking` | `fulfillments` | `meta_keys:{number,url,provider}` | `none`, auto-detected on connect.

**Webhooks**
- `POST /wc/v3/webhooks {topic, delivery_url, secret}`; this needs a **write** key (**VERIFY**), so with a read-only key the merchant would create webhooks manually.
- Headers `X-WC-Webhook-{Source, Topic, Resource, Event, ID, Delivery-ID}`; `X-WC-Webhook-Signature` = base64(HMAC-SHA256(raw body, secret)).
- An unsigned `webhook_id=` ping is sent on creation.
- **No retries**; the webhook is disabled after 5 consecutive failures.

**Other:** no built-in rate limit (host or WAF dependent). Pagination via `X-WP-Total`, `X-WP-TotalPages`. Pretty permalinks are required.

| Normalized | WooCommerce |
|---|---|
| external_order_id / order_number | `id` / `number` |
| customer | `customer_id` (0 = guest), `billing.{first_name, last_name, email, phone}` |
| status | `status` |
| payment_status | **derived**:<br>• `refunded` → refunded<br>• `refunds[]` present → partially_refunded<br>• `date_paid_gmt` set or status processing/completed → paid<br>• `failed` → failed<br>• `pending`/`on-hold` → pending<br>• `cancelled` → voided |
| currency / total | `currency` / `total` |
| items | `line_items[].{name, sku, quantity, total, image.src}` |
| created_at / updated_at | `date_created_gmt`+Z / `date_modified_gmt`+Z |
| shipment | from `tracking_source`; otherwise `shipping_lines[0].method_title`, which is the method, not the carrier |
| links | `{home}/wp-admin/admin.php?page=wc-orders&action=edit&id={id}` (works with and without HPOS) / `{home}/my-account/view-order/{id}/` (logged-in customers only; slug configurable **VERIFY**) |

**Status mapping:**

| WooCommerce | Canonical |
|---|---|
| `pending` | pending |
| `processing` | processing |
| `on-hold` | on_hold |
| `completed` | completed |
| `cancelled` | cancelled |
| `refunded` | refunded |
| `failed` | failed |
| custom statuses | unknown, with label |

## 6. Shopify (GraphQL Admin API)

> **Implemented in Phase 5** (docs 18–22). Where the implementation differs from the Phase 1 research below:
> - The connector uses `Commerce::HttpClient`, not the `shopify_api` gem, whose version is unchanged.
> - Customers are found with `customers(query:)` (quoted exact email or phone, re-checked locally), not `customerByIdentifier`.
> - Names are not requested; the protected customer data needed is Level 1 + Email and Phone only.
> - Status and payment follow doc 19 §7:
>   - `closed` is not read;
>   - PENDING → unpaid;
>   - AUTHORIZED, VOIDED and EXPIRED → unknown, never "failed".
> - Amounts use `currentTotalPriceSet.presentmentMoney`.
> - The admin link is `https://<shop>.myshopify.com/admin/orders/<legacyResourceId>`; `statusPageUrl` is not requested.

**Auth**
- Non-embedded apps use the authorization-code grant.
- **Expiring offline tokens**:
  - Opt-in from 2025-12-10 with `expiring=1`.
  - Required for new public apps from 2026-04-01.
  - **Required for all public apps from 2027-01-01**: non-expiring tokens then get 403 on both GraphQL and REST.
  - Lifetimes: access token 3600 s; refresh token 90 days, rotating (the old refresh token can be retried until the new one is first used, from 2026-08-27).
  - Migrating an existing token: token exchange `migrate_to_expiring_token`, one-time per shop.
  - Sources: https://shopify.dev/docs/apps/build/authentication-authorization/access-tokens/offline-access-tokens, https://shopify.dev/changelog/expiring-offline-access-tokens-required-for-all-public-apps-as-of-january-1-2027
- Ruby support: `shopify_api` **16.x** (`Auth::RefreshToken`, `TokenExchange.migrate_to_expiring_token`). The repo has **14.8.0**.

**Scopes and approvals**
- Scopes: `read_customers`, `read_orders`.
- `read_all_orders` (older than 60 days) needs Shopify approval.
- **Protected customer data Level 2** is needed for name, email and phone. Non-development stores return no data until it is approved (https://shopify.dev/docs/apps/launch/protected-customer-data).

**API**
- **REST is legacy**, and new public apps must be GraphQL-only (since 2025-04-01).
- GraphQL:
  - find the customer with `customerByIdentifier(identifier:{phoneNumber|emailAddress})`;
  - then `customer.orders(first:5, sortKey:CREATED_AT, reverse:true)`.
- Versions are quarterly; the current stable is 2026-07 (2026-10 on Oct 1). Rate limits use query cost.

**Webhooks**
- Mandatory compliance topics are set in `shopify.app.toml`.
- `X-Shopify-Hmac-Sha256` (base64 HMAC-SHA256, client secret). `X-Shopify-Webhook-Id` is used for dedup. Next-gen `Shopify-*` headers without the `X-` prefix exist.
- Delivery: respond within 5 s. Retries 8× over 4 h, and an API-created subscription is deleted after 8 consecutive failures.

| Normalized | GraphQL |
|---|---|
| external_order_id / order_number | `id` (`legacyResourceId`) / `name` |
| customer | `customer{id displayName defaultEmailAddress{emailAddress} defaultPhoneNumber{phoneNumber}}` |
| status | `cancelledAt` → cancelled; `closedAt` → completed; otherwise mapped from `displayFulfillmentStatus` |
| payment_status | `displayFinancialStatus`:<br>• PAID → paid<br>• PENDING / AUTHORIZED → pending<br>• PARTIALLY_PAID → partially_paid<br>• PARTIALLY_REFUNDED → partially_refunded<br>• REFUNDED → refunded<br>• VOIDED → voided<br>• EXPIRED → failed |
| currency / total | `currencyCode` / `totalPriceSet.shopMoney.amount` |
| items | `lineItems(first:10){nodes{title quantity sku discountedTotalSet}}` |
| created_at / updated_at | `createdAt` / `updatedAt` |
| shipment | `fulfillments{displayStatus trackingInfo{company number url}}` |
| links | `https://admin.shopify.com/store/{handle}/orders/{legacyResourceId}` (**VERIFY**) / `statusPageUrl` (needs protected-data approval) |
