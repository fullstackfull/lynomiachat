---
title: Connect Zid
description: You will have a Zid store connected by authorizing the Lynomia Chat app, and you will know which Zid orders can be matched and what cannot be changed.
position: 50
tags: [commerce, zid]
seo_description: "Connect a Zid store to Lynomia Chat by authorizing the app: what Zid reports, why marketplace orders never match, and which order actions are held."
---
Zid connects by authorizing the Lynomia Chat app on your store. You sign in to Zid, approve the app, and come
back. No token is typed anywhere and none passes through your browser.

While you authorize, Lynomia Chat also subscribes to three Zid events — an order created, its status changed,
its payment status changed — so the Commerce section updates on its own when something moves. Those events carry
no order data: they say which customer changed, and the orders are then read from Zid.

## What you need first

- **Administrator** access in Lynomia Chat, and a plan that includes Commerce.
- Zid offered on your installation. If the picker marks it *Not available yet*, the app is not configured there.
- A Zid account that can approve an app for the store.

## Steps

1. **Settings → Commerce → Add store → Zid.**
2. **Connect with Zid.** Zid opens in the same browser.
3. Sign in and approve the Lynomia Chat app for the store.
4. You come back to Settings → Commerce with the store listed as **Active**.

Finish the authorization in the browser you started it in. Lynomia Chat ties the return to that browser, so a
link opened elsewhere will not complete it.

## A worked example

A customer writes "where is order 48213?".

1. The agent opens the conversation. The contact's WhatsApp number matched a Zid customer, so the Commerce
   section already lists that customer's recent orders.
2. Order 48213 is not among the five shown, so the agent uses **Find an order** and types the number.
3. The order comes back with its status, its payment status and its shipment, and the agent can open the
   tracking link or press **Send tracking** to put the tracking details in the reply box for review.

Note what the number is: in Lynomia Chat, a Zid order's number **is** Zid's order id. That is what the panel
shows and what the search expects.

## Who can do this

Connecting, reconnecting, disabling and disconnecting are **administrator** actions, recorded in the audit log.
Any agent who can see a conversation sees the Zid orders in it.

## Limits

- **Order actions are not available.** Lynomia Chat implements two Zid status steps — an order Zid has ready
  becomes shipped, and an order in delivery becomes delivered — but they are held until Zid's writes are
  verified on a live store, and no setting turns them on. There is no cancel and no refund for Zid at all: a Zid
  refund is a reverse order, which Lynomia Chat does not create.
- **Marketplace orders never match a contact.** A Zid marketplace order carries no customer, so there is nobody
  to link it to.
- **Masked values never match.** Where Zid hides a name, email or phone behind asterisks, that value is not
  treated as an identifier, so it cannot match or be linked.
- **Guest checkouts are not matched.** Zid customers are matched; an order with no Zid customer cannot be
  linked.
- **No link to the order in the Zid admin.** Zid documents no admin URL for an order, so there is no *View
  order* link. The order number and a copy button are there instead.
- **One shipment per order**, taken from the order's shipping method, with its tracking number and link when Zid
  provides them.
- Payment is shown only when Zid states it: paid, unpaid or refunded. Anything else, Zid's *voided* included,
  reads as *Payment not confirmed*.
- Zid allows 60 requests a minute per store. While it is limiting, the section shows its last answer, labelled
  with the time.
- Order dates are read in the time zone on your Zid store profile.
- **Abandoned carts are not available.** The feature is switched off for Zid and cannot be turned on.
- Only the latest 5 orders per customer are shown, so every figure is *visible*, not lifetime.

## Related

- [What each platform supports](commerce-provider-support)
- [What connecting a store gives you](commerce-overview)
- [Customer 360](customer-360)

## If it does not work

**Zid sent me back without connecting.** The authorization was started in one browser and finished in another,
or it took too long. Start again from **Connect with Zid** in the same browser.

**"This store is already connected."** One store belongs to one Lynomia Chat account. Disconnect it in the other
account first.

**The store says it needs re-authorization.** Zid stopped accepting the stored access. Use **Reconnect** on the
store and approve the app again.

**A customer I know buys from us is not matched.** Match is exact, on a normalized email address or a phone
number in international form, and names are never used. Marketplace and masked orders cannot match at all. An
agent can search by email or phone in the section and link the right customer by hand.

**Disconnecting.** It removes Lynomia Chat's access, the three event subscriptions and every customer link for
that store. Nothing in Zid changes, and you can connect it again later.
