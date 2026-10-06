---
title: Connect Shopify
description: You will have a Shopify store connected through the Lynomia Chat Commerce app, and you will know the two approvals it depends on.
position: 60
tags: [commerce, shopify]
seo_description: "Connect a Shopify store to Lynomia Chat: the myshopify domain, Protected Customer Data approval, the 60-day order window and what cannot be changed."
---
Shopify connects by authorizing the **Lynomia Chat Commerce** app on your store. You enter the store's
myshopify.com domain, approve the app in Shopify, and come back. No token is typed anywhere.

This is a different app from the Shopify integration listed under Integrations. The two never share
credentials, and a store already connected through that integration is refused here, so the same orders never
appear twice.

## What you need first

- **Administrator** access in Lynomia Chat, and a plan that includes Commerce.
- Shopify offered on your installation. If the picker marks it *Not available yet*, the app is not configured
  there.
- The store's **myshopify.com domain**, which is in Shopify admin under **Settings → Domains**. Your custom
  shop domain is not accepted; the myshopify one is the store's identity.
- **Shopify's Protected Customer Data approval** for the Lynomia Chat Commerce app. Shopify treats a customer's
  email and phone number as protected, and those two fields are what matching needs. Until Shopify approves it,
  the store connects but the section reports that customers cannot be matched.
- The store not already connected through this account's Shopify integration.

## Steps

1. **Settings → Commerce → Add store → Shopify.**
2. Enter the store domain, for example `your-store.myshopify.com`.
3. **Connect with Shopify.** Shopify opens in the same browser.
4. Sign in and approve the Lynomia Chat Commerce app. It asks to read customers and orders, and nothing else.
5. You come back with the store listed as **Active**.

Finish in the browser you started in: Lynomia Chat ties the return to that browser.

## A worked example

A customer writes about order 1042.

1. The agent opens the conversation. The contact's email matched a Shopify customer, so the section lists that
   customer's recent orders.
2. Order 1042 is older than the five shown. The agent uses **Find an order** and types `1042` — the number as
   Shopify prints it, without the `#`.
3. The order comes back with its fulfillment status, its payment status and its tracking number, and **View
   order** opens it in Shopify admin.

If order 1042 were from last year, it would not be found. See the order window below.

## Who can do this

Connecting, reconnecting, disabling and disconnecting are **administrator** actions, recorded in the audit log.
Any agent who can see a conversation sees the Shopify orders in it.

## Limits

- **Only the last 60 days of orders.** The app asks for ordinary order access, and Shopify limits that to the
  last 60 days. An older order does not appear in the list and is not found by number.
- **Order actions are not available.** Lynomia Chat implements two Shopify writes — cancelling an unpaid,
  unfulfilled order and creating a refund — but they are held until they are verified on a live store, and no
  setting turns them on. Beyond those two there is nothing: **Shopify has no order status to set**, so there is
  nothing to change, and resending an invoice or a payment link is not supported.
- **No customer name.** The app does not request customer names, so a matched Shopify customer is shown without
  one. The contact's own name is what agents see.
- **Guest checkouts are matched by email only.** Shopify's order search has no phone filter, so a checkout with
  no Shopify customer can only be matched by its email address.
- **Order statuses are Shopify's fulfillment stages**, read as processing, on hold, shipped, cancelled, and
  delivered once every shipment on the order is delivered. There is no *completed*.
- Payment is shown only when Shopify states it: paid, unpaid, partially paid, refunded, partially refunded.
  Shopify's *authorized*, *voided* and *expired* read as *Payment not confirmed*.
- Shopify meters requests by query cost. When the budget runs low, the section shows its last answer, labelled
  with the time, rather than failing.
- **Abandoned checkouts are not available.** The feature is switched off for Shopify and cannot be turned on.
- Only the latest 5 orders per customer are shown, so every figure is *visible*, not lifetime.

## Related

- [What each platform supports](commerce-provider-support)
- [What connecting a store gives you](commerce-overview)
- [Customer 360](customer-360)

## If it does not work

**"Enter the store's myshopify.com domain."** You entered a custom domain, or added `https://` and a path. Use
the plain `your-store.myshopify.com` form from Shopify admin → Settings → Domains.

**"This Shopify store is already connected through this account's Shopify integration."** Disconnect it under
Integrations first, then connect it here.

**The section says Shopify has not approved reading customer data.** That is Protected Customer Data. The
store's orders cannot be matched to contacts until Shopify approves the app. Nothing in your account changes
this.

**Shopify sent me back without connecting.** The authorization was finished in a different browser, or it took
too long. Start again from **Connect with Shopify**.

**An order the customer is asking about is missing.** It is probably older than 60 days.

**Disconnecting.** It removes Lynomia Chat's access and every customer link for that store. Nothing in Shopify
changes: to remove the app from the store, uninstall it in Shopify admin.
