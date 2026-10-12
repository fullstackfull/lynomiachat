---
title: Your store keys cannot do that
description: The difference between “connected” and “allowed”, why order actions can be unavailable on a working store, and what to change — per platform.
position: 63
tags: [troubleshooting, commerce]
seo_description: "A Lynomia Chat commerce store that reads orders but cannot change them: Read vs Read/Write keys, missing Shopify scopes, and Shopify protected customer data."
---
A store can be connected, reachable and working — and still refuse something. Reading orders and changing them
are different permissions on every platform, and Lynomia **never quietly upgrades the access you granted**: an
administrator grants it deliberately or it stays as it is.

| What you see | The code behind it |
|---|---|
| “Your store refused that” | `PERMISSION_DENIED` |
| “These keys cannot change orders” | `WRITE_ACCESS_DENIED` |
| “This store is not approved for customer data” | `PROTECTED_DATA_NOT_APPROVED` |
| Order actions greyed out, with a reason | `read_only_key` or `missing_scope` |

## Reading and writing are different grants

- **WooCommerce** — an API key is created as **Read** or **Read/Write**. A Read key is exactly right if you
  only want order history in conversations. Order actions need Read/Write, and the product will not pretend
  otherwise: it records `read_only_key` the first time a write is refused, and shows that as the reason the
  action is unavailable. To change it, create a **new Read/Write key** in WordPress → WooCommerce → Settings →
  Advanced → REST API and replace the keys in Settings → Commerce. An existing key's permissions cannot be
  raised in place.
- **Shopify** — order actions need the `write_orders` scope. Without it the product records `missing_scope` and
  reports the action as unavailable rather than attempting it. Reconnecting the store re-requests the scopes.
- **Zid** — the same shape: a store whose authorization does not include order management records
  `missing_scope`.
- **Salla** — the Lynomia app is read-only by design. Order actions are not offered for Salla at all, which is
  a capability of the integration rather than a problem with your store.

## Shopify protected customer data

Shopify requires an app to be **approved** before it may read customer names, emails and phone numbers. Until
that approval is in place, a Shopify store connects and works for everything except customer details, and the
product reports it as not approved rather than as a failure — because it is not one, and it is not something
you can fix from your store.

## Order actions also have their own switch

Separately from the keys, order actions are **off by default** per store. Settings → Commerce → the store →
turn on order actions. Turning them on requires credentials that can already write, which is why the switch
refuses with the same reason above if the keys are Read-only: an opt-in that silently does nothing would be
worse than an honest refusal.

## What this is not

If the store reads nothing at all, this is not your problem — see **Your store needs to be reconnected**
(the access is gone) or **Lynomia cannot reach your store** (the store did not answer).
