# Lynomia Commerce: the Shopify GraphQL provider (Phase 5)

`Commerce::Providers::Shopify` reads customers, orders and fulfillments through the Shopify **Admin GraphQL API, pinned to `2026-07`**. The connector does not use the REST Admin API, `latest`, `unstable` or `2026-10`. It plugs into the existing matcher, cache, conversation API and panel: nothing Shopify-specific reaches the UI, and there is no Shopify panel.

## 1. API version pin

- **Pin.** `Commerce::Shopify::Config::API_VERSION = '2026-07'`. Every request goes to `https://<shop>.myshopify.com/admin/api/2026-07/graphql.json`.
- **Why 2026-07.** It is Shopify's latest stable version. `@shopify/dev-mcp` 1.16.0 `supported-versions` lists it as `latestVersion`, and 2026-10 as a release candidate. `shopify_api` 16.3.0 supports it.
- **Moving the pin** is a reviewed change:
  1. validate the documents against the new schema;
  2. re-run the specs and the E2E;
  3. update this section.

  The documents are already valid on 2026-10 (RC) and 2026-04 (`docs/commerce/e2e/results/shopify_schema_validation.txt`).
- **Schema evidence.** The five documents the connector sends were validated with graphql-js against the published 2026-07 schema:
  - 5/5 valid;
  - queries only;
  - no deprecated field (`Customer.email` and `Customer.phone` are deprecated, so `defaultEmailAddress` and `defaultPhoneNumber` are used).

## 2. GraphQL client

`Commerce::Shopify::Graphql` is a small layer over `Commerce::HttpClient#post_json` (no new networking framework):
- **Transport.** The client inherits `HttpClient`'s protections: SSRF filter with a pinned IP, no redirects, bounded time and size, errors mapped to Commerce codes.
- **Headers.** `X-Shopify-Access-Token: <token>` and `Content-Type: application/json`. No `Authorization` header.
- **Host.** Always the store's validated myshopify.com domain.
- **Variables for every value.** Documents are constants and are never interpolated. Search strings are built by one helper (§4).
- **HTTP 200 is not success.** Any top-level `errors` raises, whatever `data` holds:

| GraphQL answer | Commerce error |
|---|---|
| `extensions.code = THROTTLED` | `RATE_LIMITED` |
| `ACCESS_DENIED` whose message says the app is not approved to access/use protected customer data | `PROTECTED_DATA_NOT_APPROVED` (new core code; not a stale-fallback code) |
| other `ACCESS_DENIED` | `PERMISSION_DENIED` |
| `INTERNAL_SERVER_ERROR` | `STORE_UNAVAILABLE (shopify_internal_error)` |
| any other error, or `data` missing | `INVALID_RESPONSE` |
| HTTP 401 / 403 / 429 / 5xx | `AUTH_INVALID` / `PERMISSION_DENIED` / `RATE_LIMITED` / `STORE_UNAVAILABLE` (`HttpClient`) |

`userErrors` exist only on mutations, which the connector never sends.

## 3. Throttling (query cost)

- Every answer's `extensions.cost` is read: `requestedQueryCost` and `throttleStatus {currentlyAvailable, restoreRate}`.
- A `THROTTLED` answer stops further calls for the store (`Commerce::Backoff`, key `COMMERCE::SHOPIFY::MERCHANT::<shop id>::BACKOFF`) for the time the budget needs to recover: `ceil((requested − available) / restoreRate)` seconds, at most 60.
- A successful answer that leaves less budget than the query just cost also pauses the store for that recovery time, before Shopify throttles.
- A 429 uses `Retry-After`.
- No fixed sleep anywhere. While paused, the panel serves its cache (`RATE_LIMITED` is a stale-fallback code) and the fields are already minimal.

## 4. Search strings (GraphQL injection)

- `Commerce::Shopify::SearchQuery` is the only place a search string is built:
  - `email:"<value>"` and `phone:"<value>"` are quoted phrases. Quoting also makes the email filter exact, since Shopify tokenizes emails.
  - Inside the phrase, `\` and `"` are escaped. No value can close the phrase, add a filter (`OR email:*`) or an operator.
  - `customer_id:<n>` accepts only a positive integer.
- The string is sent as the `$query` variable, never written into the document.
- Specs cover quotes, backslashes, `\"` sequences, `OR`/`*` injection, parentheses and non-numeric ids (`spec/services/commerce/shopify/search_query_spec.rb`, provider spec).

## 5. Customers and guests

- **Registered customers:**
  - `customers(first: 20, query: email:"…" | phone:"+…")` → `nodes { id defaultEmailAddress { emailAddress } defaultPhoneNumber { phoneNumber } }`.
  - A candidate is kept only when its default email (case-normalized) or E.164 phone equals the searched value exactly.
  - Names are never requested or matched.
  - The candidate id is the numeric part of `gid://shopify/Customer/<n>`.
- **Guests:**
  - A guest checkout has no Shopify customer, and **no Shopify id is invented**: the candidate is `guest:<email>`, the same contract as WooCommerce guests, allowed by `CustomerLink.external_customer_id`.
  - It is found with `orders(first: 20, query: email:"…")` → `nodes { id email customer { id } }`, and kept only when an order has **no customer** and its email matches exactly.
  - The 2026-07 `orders` search has no phone filter, so guests are found by email only.
- **Matching rules (core):**
  - The verified WhatsApp/SMS phone auto-links one exact match.
  - Contact email and phone are suggestions only.
  - Several matches (for example the same email as a registered customer and as a guest) are offered for manual selection. An agent's search accepts an exact email or an international phone.
- **Protected data:**
  - A customer whose email or phone Shopify withholds (null) never matches.
  - A denial is reported (`PROTECTED_DATA_NOT_APPROVED`), never guessed around.

## 6. Orders

- **Registered:** `orders(first: 5, query: customer_id:<n>, sortKey: CREATED_AT, reverse: true)`, each re-checked: `customer.id == gid://shopify/Customer/<n>`.
- **Guest:** `orders(first: 20, query: email:"…", …)`, kept only when `customer` is null and the email matches; the newest five.
- **Window:** without `read_all_orders`, Shopify returns the last 60 days.
- **Fields** (nothing else: no addresses, no marketing data, no names):
  - `id legacyResourceId name createdAt updatedAt cancelledAt email displayFinancialStatus displayFulfillmentStatus subtotalLineItemsQuantity`
  - `currentTotalPriceSet { presentmentMoney { amount currencyCode } }` (the currency the customer paid in)
  - `customer { id }`
  - `lineItems(first: 10) { nodes { name quantity discountedTotalSet { presentmentMoney { amount } } } }`
  - `fulfillments(first: 10) { status displayStatus trackingInfo(first: 5) { company number url } }`
- **Bounds:**
  - 10 line items; `item_count` is `subtotalLineItemsQuantity`, the whole order's quantity, so a truncated list never understates the count;
  - 10 fulfillments;
  - 5 tracking numbers per fulfillment.
- **`order_number`** is `name` without its leading `#`, since the UI adds it.
- **Admin link:** `https://<myshopify domain>/admin/orders/<legacyResourceId>`, built locally from the validated domain and a numeric id. No URL from the response is used for it, and `statusPageUrl` is not requested.

## 7. Mappings

**Payment status: `displayFinancialStatus` only, never inferred from fulfillment or order status.**

| Shopify | Neutral |
|---|---|
| PAID | `paid` |
| PENDING | `unpaid` |
| PARTIALLY_PAID | `partially_paid` (new neutral value; en "Partially paid", ar "مدفوع جزئيًا") |
| PARTIALLY_REFUNDED | `partially_refunded` |
| REFUNDED | `refunded` |
| AUTHORIZED, VOIDED, EXPIRED, null | `unknown` ("Payment not confirmed") |

**Order status: cancellation and fulfillment only.**

| Shopify | Neutral |
|---|---|
| `cancelledAt` set | `cancelled` |
| FULFILLED, and every active fulfillment delivered | `delivered` |
| FULFILLED | `shipped` |
| UNFULFILLED, PARTIALLY_FULFILLED, IN_PROGRESS, PENDING_FULFILLMENT, OPEN, SCHEDULED | `processing` |
| ON_HOLD | `on_hold` |
| RESTOCKED, REQUEST_DECLINED, anything new | `other` |

`closed` (archived) is the merchant's filing, not a stage, so it is not read. No lifecycle is forced; `provider_status` keeps `displayFulfillmentStatus`.

**Shipments: one per tracking number of each fulfillment, or one per fulfillment without tracking.**

| `Fulfillment.displayStatus` (or `status` CANCELLED) | Neutral |
|---|---|
| LABEL_PRINTED, LABEL_PURCHASED, CONFIRMED, SUBMITTED, READY_FOR_PICKUP | `pending` |
| CARRIER_PICKED_UP, IN_TRANSIT, DELAYED, ATTEMPTED_DELIVERY | `in_transit` |
| OUT_FOR_DELIVERY | `out_for_delivery` |
| DELIVERED, PICKED_UP | `delivered` |
| FAILURE, NOT_DELIVERED | `failed` |
| CANCELED, or fulfillment `status` CANCELLED | `cancelled` |
| FULFILLED, MARKED_AS_FULFILLED, LABEL_VOIDED, null | `other` |

- **Carrier** is `trackingInfo.company`.
- **Tracking links** are kept only when https without credentials.
- **Main shipment.** The order card's tracking and shipping line come from the first active shipment with a tracking number or link, else the first active one. A cancelled fulfillment is never offered for tracking.
- **UI.** Track shipment and Send tracking appear exactly as for the other providers. The card's architecture is unchanged; only a `partially_paid` badge colour and label were added.

## 8. Files and evidence

- **Code:**
  - `custom/app/services/commerce/providers/shopify.rb`, `…/providers/shopify/normalizer.rb`
  - `custom/app/services/commerce/shopify/{graphql,search_query}.rb`
- **Specs:**
  - `spec/services/commerce/providers/shopify_spec.rb`: matching, guests, re-checks, every mapping, bounds, admin link, protected data, throttling, 401 refresh.
  - `spec/services/commerce/shopify/{graphql,search_query}_spec.rb`
  - `spec/controllers/api/v1/accounts/conversations/commerce/shopify_panel_spec.rb`: auto-link, guest suggestion, PCD message without stale data, throttled stale fallback, revoked token → needs_reauth, multi-provider listing.
- **Fixtures** in 2026-07 shapes: `spec/fixtures/files/commerce/shopify/{customers,orders,guest_orders,shop,token}.json`.
- **Schema validation:** `docs/commerce/e2e/results/shopify_schema_validation.txt`.
