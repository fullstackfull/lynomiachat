---
title: What each platform supports
description: You will know exactly what Lynomia Chat can read and change on WooCommerce, Salla, Zid, Shopify and Store Syria, and which parts are not in production everywhere.
position: 20
tags: [commerce]
seo_description: "Commerce support per platform in Lynomia Chat: reading, shipments, order search, live updates and order actions for WooCommerce, Salla, Zid, Shopify and Store Syria."
---
The five platforms are not equivalent. Each store API offers a different set of facts and allows a different set
of changes, and Lynomia Chat implements only what a platform documents and confirms. This article is the
reference the setup guides link back to. Read it before you promise anything to your team.

## Reading

Every platform gives you the same shape: the store customer a contact was matched to, and that customer's latest
**5** orders, newest first, with status, payment status, items and totals.

| | WooCommerce | Salla | Zid | Shopify | Store Syria |
|---|---|---|---|---|---|
| Orders beside the conversation | yes | yes | yes | yes | yes |
| Matched by the conversation's verified phone | yes | yes | yes | yes | yes |
| Matched by email | yes | yes | yes | yes | yes |
| Guest checkouts (no store account) | yes, by email or phone | no | no | yes, by email only | yes, by email or phone |
| Shipments and tracking numbers | **no** | yes | yes, one per order | yes | yes, one per order, number only |
| Can show *shipped* | **no** | yes | yes | yes | yes |
| Can show *delivered* | **no** | yes | yes | yes | yes |
| Can show *paid*, so counts towards spend | yes | **no** | yes | yes | yes |
| Link to the order in the store admin | yes | yes | **no** | yes | yes |
| Find an order by its number | yes | **no** | yes | yes | yes |
| Live updates when an order changes | yes, with a Read/Write key | yes | yes | yes | yes, pushed by the store |

Three rows deserve a sentence each.

**WooCommerce has no shipments.** WooCommerce core has no shipment or tracking field, so Lynomia Chat shows
none, and a WooCommerce order is never *shipped* or *delivered*. Tracking plugins are not read.

**Salla never reports an order as paid.** A Salla order states only that it is *awaiting payment*, or says
nothing about payment at all. Lynomia Chat will not infer payment from an order being completed, so for a
contact whose only store is Salla the **Spend** figure stays empty. Everything else about a Salla order is
shown.

**Salla cannot be searched by order number.** Salla offers no lookup for the reference number it prints on an
order, and Lynomia Chat does not scan a store's orders. **Find an order** reports a Salla store as not
searchable and still searches the others.

## Changing an order

Order actions are the only writes Lynomia Chat makes to a store. Every one is read-again-then-confirm: the order
is re-read from the store, you see what will happen, and you confirm.

| Action | WooCommerce | Salla | Zid | Shopify | Store Syria |
|---|---|---|---|---|---|
| Change status | processing → completed or on hold; on hold → processing | **none** | shipped, then delivered | **no** | **none** |
| Cancel order | unpaid orders (pending, on hold) | **none** | **no** | unpaid, unfulfilled orders | **none** |
| Refund, full or partial | yes, up to what is still refundable | **none** | **no** | yes, up to what Shopify says is refundable | **none** |
| Resend order details | yes | **none** | **no** | **no** | **none** |
| Resend payment link | yes | **none** | **no** | **no** | **none** |
| Change shipping or address | **no** | **no** | **no** | **no** | **no** |

- **Salla and Store Syria have no order actions at all.** For Store Syria that is the design and not a gap:
  Lynomia Chat reads it and never writes to it.
- **Zid can only change status**, and only two steps of its own flow: an order Zid has ready becomes shipped,
  and an order in delivery becomes delivered. There is no cancel and no refund — a Zid refund is a reverse
  order, which is a different thing Lynomia Chat does not create.
- **Shopify has no order status to set**, so there is nothing to change; and resending an invoice or a payment
  link is not supported.
- A WooCommerce refund goes through the order's payment gateway when that gateway supports refunds. When it does
  not, the store **records** a refund and no money moves. The confirmation text states which of the two happens.

## Not in production on any platform

Two things exist in the product and are switched off everywhere. They are held in code, so no setting turns
them on.

| | Status |
|---|---|
| **Order actions on Salla, Zid and Shopify** | Held until each platform's writes are verified on a live store. Only **WooCommerce** order actions can be used. Store Syria has none by design. |
| **Abandoned carts** | Read on **Store Syria** only, as an administrator's read-only recovery queue. Held on Salla, Zid and Shopify; WooCommerce has no merchant-wide abandoned-cart API at all. |

There is also no abandoned-cart campaign and no recurring campaign — see
[WhatsApp campaigns](whatsapp-campaigns) for the two types that exist.

## Which platforms you can connect at all

Reading is always available for WooCommerce. Salla, Zid and Shopify each need the matching app configured on
your installation, and each is switched on there, not in your account. The platform picker marks the rest as
*Not available yet*.

Shopify has one extra condition: **Protected Customer Data**. Until Shopify approves the Lynomia Chat Commerce
app to read a store's customer emails and phone numbers, customers cannot be matched and the section says so.

## Per-platform limits worth planning around

| Platform | Limit |
|---|---|
| WooCommerce | Order search works because WooCommerce numbers orders by their internal id. A plugin that renumbers orders breaks it. A Read key gives you orders but no live updates and no order actions. |
| Salla | Salla limits requests per store. While it is limiting, the section serves its last answer, marked with its time. |
| Zid | The order number shown is Zid's own order id. Marketplace orders carry no customer, so they never match anyone. Zid allows 60 requests a minute per store. |
| Shopify | Without extended order access, Shopify returns only the **last 60 days** of orders. Shopify also sends no customer name. |
| Store Syria | The integration token names one store, so a store is connected, and its token replaced, one store at a time. Shipment state is folded into the order's own delivery state, and a tracking number arrives without a carrier link. |

## Related

- [What connecting a store gives you](commerce-overview)
- [Connect WooCommerce](connect-woocommerce) · [Salla](connect-salla) · [Zid](connect-zid) ·
  [Shopify](connect-shopify) · [Store Syria](connect-store-syria)
- [Customer 360](customer-360)
