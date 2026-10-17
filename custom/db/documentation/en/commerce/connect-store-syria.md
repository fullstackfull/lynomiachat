---
title: Connect Store Syria
description: You will have a Store Syria store connected with an integration token issued in the Store Syria admin, and you will know what Lynomia Chat reads and why it never writes.
position: 65
tags: [commerce, store-syria]
seo_description: "Connect a Store Syria store to Lynomia Chat with a store-bound integration token: what it reads, live updates, the abandoned-cart queue and why there are no order actions."
---
Store Syria connects with an **integration token** that you issue in the Store Syria admin for one store. You
paste it into Lynomia Chat with the store's address, and the connection is tested before it is saved.

The token names the store. That is the whole of the tenancy rule: Lynomia Chat never sends a store id, so there
is nothing in a request for anyone to change, and a token issued for one store cannot be used to read another.

## What you need first

- **Administrator** access in Lynomia Chat, and a plan that includes Commerce.
- Store Syria offered on your installation. If the picker marks it *Not available yet*, it is switched off
  there, and that is an installation setting rather than an account one.
- Access to the Lynomia Chat integration page in your Store Syria admin.

## Steps

1. In **Store Syria**, open the Lynomia Chat integration for the store and **issue a commerce credential**. It
   is shown once. Issuing a new one stops any token issued before it from working.
2. In Lynomia Chat: **Settings → Commerce → Add store → Store Syria.**
3. Enter the store's address and a name for it, and paste the token.
4. **Test and connect.** Lynomia Chat calls the store, confirms which store answered, and saves the connection
   as **Active**.

The token is encrypted and never shown again. If you lose it, issue a new one in Store Syria and use
**Replace the integration token** on the store.

## A worked example

A customer writes "has my order shipped yet?".

1. The agent opens the conversation. The contact's verified phone number matched a Store Syria customer, so the
   Commerce section already lists that customer's latest orders.
2. The order is there with its status, what was paid, the items and the total.
3. It carries a tracking number, so the agent can copy it into the reply. There is no tracking link — Store
   Syria sends the number, not a carrier URL.
4. **View order** opens that order in the Store Syria admin for anything the panel does not show.

## Who can do this

Connecting, replacing the token, disabling and disconnecting are **administrator** actions, recorded in the
audit log. Any agent who can see a conversation sees the Store Syria orders in it.

## Limits

- **Order actions are not available, and none are planned.** Lynomia Chat reads Store Syria and never writes to
  it. Nothing in the order panel changes an order.
- **Shipment state comes from the order, not from a shipment record.** Store Syria folds fulfilment into the
  order's own delivery state, so Lynomia Chat reports one shipment per order and only for the states where one
  demonstrably exists: awaiting collection, in transit, delivered, returned.
- **A tracking number, never a tracking link.** Store Syria sends the number; a carrier URL is never guessed
  from it.
- **Guest checkouts are matched**, by email or phone, the same as registered customers.
- Matching is exact: a normalized email address, or a phone number in international form. Names are never used.
- Only the latest **5** orders per customer are shown, so every figure is *visible*, not lifetime.
- Order dates are read in the time zone the store reports them in.

## Live updates

Store Syria pushes its own commerce events to Lynomia Chat from its transactional outbox, so the Commerce
section updates on its own when an order moves. Nothing is registered in the store during the connection,
because there is nothing to register: the store already knows where to deliver from its own configuration.

An event says which customer changed. The orders are then read from the store, so an event can never put stale
or forged order data on an agent's screen.

## Abandoned carts

Store Syria is the one platform whose carts Lynomia Chat reads. Administrators get a read-only **recovery
queue** of recent abandoned carts, with the linked contact first. Reading a cart is not the same as messaging
about one: whether anyone may be messaged is decided by the consent rules, not by the cart being there.

## Related

- [What each platform supports](commerce-provider-support)
- [What connecting a store gives you](commerce-overview)
- [Customer 360](customer-360)

## If it does not work

**"This store is already connected."** One store belongs to one Lynomia Chat account. Disconnect it in the
other account first.

**The connection test fails straight away.** The token was replaced in Store Syria, the address is not the
store's own, or the integration is switched off there. Issue a fresh credential and try again with the address
exactly as Store Syria shows it.

**"This token belongs to a different store."** A connection keeps the store it was first made for. A token
issued for another store cannot take its place — that is what stops a rotation quietly serving one merchant's
orders under another's connection. Connect the other store as its own store.

**A customer I know buys from us is not matched.** Match is exact, on email or an international phone number,
and names are never used. An agent can search by email or phone in the section and link the right customer by
hand.

**Disconnecting.** It removes Lynomia Chat's access and every customer link for that store. Nothing in Store
Syria changes, and you can connect it again later.
