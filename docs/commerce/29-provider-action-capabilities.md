# Lynomia Commerce: provider action capabilities (Phase 9–10)

What each provider lets Lynomia do to an order, and why. A capability is offered only when the provider's API supports it
for certain and Lynomia can verify its result by reading the store afterwards: an endpoint existing is not enough. The
architecture is in [28-commerce-actions-architecture.md](28-commerce-actions-architecture.md).

## 1. Matrix

| Action | WooCommerce | Salla | Zid | Shopify |
|---|---|---|---|---|
| Change status | processing → completed / on-hold; on-hold → processing | — | ready → shipped (`indelivery`); in delivery → delivered | — (Shopify has no order status to set) |
| Cancel | pending / on-hold (unpaid) only; restocks; refunds nothing | — | — (status name VERIFY) | unpaid (`PENDING`/`AUTHORIZED`/`EXPIRED`), unfulfilled, not cancelled; `refund: false`, customer not notified, restocked |
| Refund (partial / full) | paid orders (processing/completed with a payment date); amount ≤ total − refunds; gateway or recorded-only | — | — (Zid refunds are reverse orders) | `refundable` orders with one payment transaction; amount ≤ Shopify's suggested maximum |
| Resend invoice / payment link | WooCommerce's order-details email (`send_order_details`) | — | — | — |
| Update shipping | — | — | — | — |
| Write credentials | Read/Write REST key, proven by webhook registration | — | the authorization's permission, learned from a 403 | `write_orders`, only after an explicit reconnect |
| Idempotency | none in WooCommerce: Lynomia sends once; the key in refund meta | — | none: sends once | native `@idempotent(key:)` on `refundCreate` (VERIFY on a live store) + the key in the refund note |
| Reconciliation (read-only) | refund by `lynomia_action_key` meta; status by the order's status | — | the order's status | refund by note; cancellation by its Job and `cancelledAt` |
| Production | **GO** (opt-in per store) | NO-GO (no write contract) | NO-GO until real UAT | NO-GO until real UAT and Protected Customer Data approval |

`supports_actions?` is true for WooCommerce, Zid and Shopify. Salla reports every action unsupported, so its orders show
no ••• menu.

## 2. WooCommerce (REST API v3)

- **Credentials.** A Read/Write REST key the store's administrator chose. Lynomia never asks WooCommerce for more and
  never replaces a key. `write_access` (store metadata) is `granted` once Lynomia created its webhooks with the key
  (proof it can write) and `read_only_key` when WooCommerce refused a webhook or a write with 401. Stores connected before
  this phase fall back to their realtime state. A Read key shows "Order actions require a Read/Write WooCommerce API key."
- **Status.** `PUT /orders/{id} {status}` from an allow-list only: processing → completed or on-hold, on-hold →
  processing. Never `trash`, never a plugin's status, never back to pending. Success means the answer carries the new
  status.
- **Cancel.** The same endpoint with `cancelled`, for pending and on-hold orders. WooCommerce restores the stock and moves
  no money; a paid order answers "refund it first". The review says "Cancelling does not refund any payment."
- **Refund.** `POST /orders/{id}/refunds` with `amount` (string, the store's precision), `reason` ("Lynomia: …"),
  `api_restock: false`, `meta_data: [{key: lynomia_action_key, value: <idempotency key>}]`, and `api_refund`:
  - **gateway** when `GET /payment_gateways/{payment_method}` is enabled and lists `refunds` in `method_supports`: money
    goes back through the gateway (the review names it);
  - **manual** otherwise (cash on delivery, bank transfer, a gateway without refunds or unknown): the refund is only
    recorded; the review says "No money is sent to the customer: refund the payment yourself."
  - Max = order total − every refund the store reports. Amount-only: no line items, nothing restocked.
  - "Paid" means WooCommerce recorded a payment date. A cash-on-delivery order in processing has none (the cash is
    collected on delivery), so no refund is offered until WooCommerce records the payment.
  - A gateway refusal arrives as HTTP 500 `woocommerce_rest_cannot_create_order_refund` after WooCommerce deleted the
    refund: `REFUND_DECLINED`. Any other 5xx is unknown (a proxy may answer while WordPress still runs).
- **Resend.** `POST /orders/{id}/actions/send_order_details` (WooCommerce 9.8+): the "Order details" (customer invoice)
  email to the billing email; offered for processing/completed/on-hold orders (invoice) and pending/failed orders that
  need payment (payment link). The store adds an order note. Not reconcilable (an email leaves no state): a lost answer
  stays unknown and the agent checks the order notes.
- **Version.** SHA-256 of status, currency, total, payment date, payment method and refunds. Notes or metadata changing
  do not count.
- **Abandoned carts.** Unsupported: WooCommerce core has no merchant-wide abandoned-cart API; no plugin is required or
  assumed (doc 30).

## 3. Shopify (Admin GraphQL 2026-07 only)

- **Scope.** A first connection asks only `read_customers,read_orders` (Phase 5). `write_orders` is requested only when an
  administrator clicks **Reconnect for order actions**: the scopes are carried in the signed OAuth state, and the callback
  accepts the grant only when Shopify granted exactly what was asked (write implies read). A merchant who approves less
  keeps the existing read-only connection unchanged. A re-authorization clears a recorded `missing_scope`. An
  `ACCESS_DENIED` on a mutation marks the store `missing_scope`.
- **Order read for actions.** One query (`LynomiaOrderActions`): the order fields of Phase 5 plus `refundable`,
  `presentmentCurrencyCode`, `totalRefundedSet`, `suggestedRefund(suggestFullRefund: true)` (maximum and suggested
  transactions) and `refunds(first: 20) { id legacyResourceId note createdAt }`. No address, email or phone.
- **Cancel.** `orderCancel(orderId, reason, restock, refund: false, notifyCustomer: false, staffNote: "Lynomia <key>")`.
  Offered only for unpaid, unfulfilled, uncancelled orders (a paid order is refunded first). Shopify answers a Job: the
  run stays running and is settled by reading the order (`cancelledAt`) and the Job (`done`).
- **Refund.** `refundCreate(input) @idempotent(key: $idempotencyKey)` with the run's key, `notify: false`, the note
  `Lynomia <key>`, and one transaction: Shopify's suggested refund transaction (gateway and parent transaction id) for the
  amount. Orders with several payment transactions are not offered (`multiple_payments`). Max = min(suggested maximum,
  the transaction's maximum).
- **Answers.** HTTP 200 is not success: `userErrors` → `PROVIDER_REJECTED`; `THROTTLED` → `RATE_LIMITED`;
  `ACCESS_DENIED` → `WRITE_ACCESS_DENIED`; `INTERNAL_SERVER_ERROR`, a missing payload or a 5xx → unknown; 401 →
  `AUTH_INVALID`.
- **Protected customer data.** Unchanged from Phase 5: without approval the customer's email and phone are refused and
  customers cannot be matched; actions need a linked customer, so they need the approval too. In production Shopify also
  stays NO-GO until that approval (doc 23).
- **VERIFY.** The `@idempotent` directive is in Shopify's documentation for 2026-04+ but not in the introspection Lynomia
  was built against; the note-based reconciliation does not depend on it.

## 4. Zid

- **Status.** `POST /v1/managers/store/orders/{id}/change-order-status {order_status}` (the official SDK), answered with
  the updated order. Two steps of Zid's own flow: ready → `indelivery` (shown "Shipped") and `indelivery` → `delivered`.
  Moving into "ready" needs a pickup location, which Lynomia does not choose.
- **Permission.** Zid exposes no granted scopes Lynomia can read; a 403 on a status change marks the store
  `missing_scope` ("Additional Zid permissions are required. Reconnect Zid to enable order actions."), cleared by the next
  authorization.
- **Not offered.** Cancel (the status code differs between Zid's docs: `cancelled`/`canceled`, VERIFY), refunds (Zid
  refunds through reverse orders/returns, not an order refund), resend, shipping.
- **Reconciliation.** By the order's status; `NOT_APPLIED` once the order still shows the previous status 5 minutes after
  sending.

## 5. Salla

No order actions. Salla's Merchant API has order status endpoints, but their status ids are per store, there is no
documented refund or cancel contract Lynomia could verify, and no idempotency; nothing was confirmed on a live store.
Per the brief ("Do not enable write capability merely because an API endpoint exists") Salla stays read-only.

## 6. What the UI receives

`GET …/orders/:order/actions` answers, per action, `{ available: true, … }` or `{ available: false, reason }` with
reasons `unsupported` (not listed), `permission_denied`, `action_in_progress`, `paid_refund_first`, `already_cancelled`,
`not_paid`, `nothing_refundable`, `order_state`, `no_email`, `multiple_payments`. Available refunds carry `max_amount`,
`currency`, `mode` (`gateway`/`manual`) and `gateway` (a display name); status changes carry `targets`; cancellations
`restocks` and `refunds: false`. The dialog renders these without knowing the provider.
