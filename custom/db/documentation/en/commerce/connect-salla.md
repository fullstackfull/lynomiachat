---
title: Connect Salla
description: You will have a Salla store connected through the Lynomia Chat app and a one-time code, and you will know what Salla does and does not tell Lynomia Chat.
position: 40
tags: [commerce, salla]
seo_description: "Connect a Salla store to Lynomia Chat with the app and a one-time connection code, and the real limits: read-only, no order actions, no paid status."
---
Salla connects through an app you install from the Salla App Store. You never copy a token: Salla hands the
access to Lynomia Chat's backend directly. What you do copy, once, is a short **connection code** that tells
Salla which Lynomia Chat account the store belongs to.

The connection is **read-only, permanently**. Lynomia Chat reads customers, orders and shipments from Salla and
changes nothing. No order action exists for Salla, and none is planned.

## What you need first

- **Administrator** access in Lynomia Chat, and a plan that includes Commerce.
- Salla offered on your installation. If the picker marks it *Not available yet*, the app is not configured
  there; that is not something you can change in your account.
- Access to your **Salla dashboard** with permission to install apps.

## Steps

1. **Settings → Commerce → Add store → Salla.**
2. **Create connection code.** A 16-character code appears in groups of four. It is shown once, works once, and
   expires after an hour. Creating a new code cancels the previous one.
3. **Install the app in Salla** — the dialog links straight to it.
4. In your Salla dashboard, open the Lynomia Chat app's **settings**, paste the code and save.
5. Watch the dialog. It moves through *Waiting for the code from Salla* → *Code received* → *Your Salla store is
   connected*. Case, spaces and dashes in the code do not matter.

Nothing is stored until Salla confirms the installation with a signed event, so a Salla store never exists in
Lynomia Chat with access that does not work.

## A worked example

You have two Salla stores and want both.

1. Create a code, install the app on the first store, paste the code. The store appears as **Active**.
2. Create a **second** code for the second store. The first code is already spent, and in any case each code
   works once.
3. Install the app on the second store and paste the new code.

Both stores now appear in the Commerce section of a conversation, and a customer who bought from both is shown
once, with each store's orders under its own tab. See [customer 360](customer-360).

## Who can do this

Creating a code, disabling and disconnecting are **administrator** actions, recorded in the audit log. Any agent
who can see a conversation sees the Salla orders in it.

## Limits

These are the ones that change how you work, not edge cases.

- **A Salla order never reads as paid.** Salla states only that an order is awaiting payment, or says nothing
  about payment. Lynomia Chat will not guess from an order being completed. So for a contact whose only store is
  Salla, **Spend** stays empty, and the *Payment* line reads *Payment not confirmed*. Status, items, totals and
  shipments are all shown normally.
- **No order actions at all.** No status change, no cancel, no refund, no resending an invoice or a payment
  link. The order actions menu does not appear for a Salla order.
- **Find an order does not work on Salla.** Salla offers no lookup for the reference number printed on an order,
  and Lynomia Chat will not scan a store's orders. A Salla store is reported as not searchable and the other
  stores are still searched.
- **Guest checkouts are not matched.** Lynomia Chat matches Salla customers, so an order placed without a Salla
  customer account cannot be linked to a contact.
- **Shipments are shown**, with the courier, the status and a tracking link when Salla marks the shipment
  trackable.
- **Abandoned carts are not available.** The feature is switched off for Salla and cannot be turned on.
- Salla limits how often its API may be called per store. While it is limiting, the section shows the last
  answer it got, labelled with the time, instead of an error.
- Only the latest 5 orders per customer are shown, so every figure is *visible*, not lifetime.

## Related

- [What each platform supports](commerce-provider-support)
- [What connecting a store gives you](commerce-overview)
- [Customer 360](customer-360)

## If it does not work

**The dialog stays on "Waiting for the code from Salla".** The code has not reached Lynomia Chat. Confirm you
pasted it into the Lynomia Chat app's own settings in your Salla dashboard and **saved** that screen.

**"This code expired."** Codes last an hour. Create a new one and paste it again.

**"This Salla store is connected to another account."** One store belongs to one Lynomia Chat account.
Disconnect it in the other account first.

**"Your plan's store limit is reached."** The installation went through but the store was not connected.
Disconnect a store or change plan, then create a new code.

**The store says it needs re-authorization.** Salla needs to authorize the app again. Update or reinstall the
Lynomia Chat app from your Salla dashboard; the store reconnects by itself, with no new code.

**It says Salla is turned off on this installation.** The store is kept but not read until Salla is switched
back on there.
