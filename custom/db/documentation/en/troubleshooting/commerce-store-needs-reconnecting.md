---
title: Your store needs to be reconnected
description: What “needs reauthorization” means, why it happened, and the one action that fixes it — for WooCommerce, Salla, Zid and Shopify.
position: 60
tags: [troubleshooting, commerce]
seo_description: "A Lynomia Chat commerce store showing AUTH_INVALID or “needs reauthorization”: what revoked the access, and how an administrator reconnects it."
---
A store in this state has stopped working completely: order history does not load in a conversation, abandoned
carts stop arriving, and order actions are unavailable. The product is not retrying in the background, because
retrying with access the store has refused would not help.

**Only an administrator can fix it, and it takes one action:** Settings → Commerce → the store → **Reconnect**.

## What the product is telling you

| What you see | The code behind it |
|---|---|
| “This store needs to be reconnected” in Settings → Commerce | the store's status is `needs_reauth` |
| “We could not reach your store” in a conversation panel | `AUTH_INVALID` |

The status is durable: it was written the moment the store refused the access, and it stays until somebody
reconnects. It is not a guess from a single failed request.

## Why it happens

The reason differs per platform, and it is worth knowing because two of them can happen without anybody doing
anything wrong.

- **WooCommerce** — the API key was deleted, or its permissions were changed, in WordPress → WooCommerce →
  Settings → Advanced → REST API. This is the one that is usually deliberate: somebody tidied up keys.
- **Salla** — the app was uninstalled or its authorization lapsed in the Salla dashboard. Reinstalling the app
  reconnects the store on its own; you do not need to create a new connection code unless the store is also
  gone from the list.
- **Zid** — the authorization expired, or the app was removed. Zid also sometimes answers a rejected
  authorization with a redirect to its login page rather than a refusal, and the product treats that as a
  rejected authorization, which is the correct reading.
- **Shopify** — the app was uninstalled from the store's admin, or the access it was granted was revoked.

## What is kept and what is removed

Reconnecting does not start you from scratch, and disconnecting does not delete your history:

- the store's **access is removed** when it moves to this state, and so is its **cached data**, which is why
  panels go blank rather than showing something stale;
- **conversations, contacts and your order-action history stay**. They are Lynomia's own records, not the
  store's;
- a store you **disconnect** keeps its row, so reconnecting the same store later reuses it rather than counting
  against your plan's store limit twice.

## If reconnecting does not hold

If the store moves back into this state within minutes of reconnecting, the access you granted is not the
access the product needs — it connected and then was refused on its first real request. That is a permissions
problem rather than an authorization one: see **Your store keys cannot do that**.
