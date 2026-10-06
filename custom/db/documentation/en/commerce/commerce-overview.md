---
title: What connecting a store gives you
description: You will know what Commerce adds to a conversation, which parts of Lynomia Chat start to see store data, and what it deliberately does not do.
position: 10
tags: [commerce]
seo_description: "Commerce in Lynomia Chat: orders beside the conversation, store conditions in filters and automation, and the limits of what it reads."
---
Commerce connects your online store to Lynomia Chat so that the agent reading a message can see what the person
is writing about. The store stays the system of record. Lynomia Chat keeps no copy of your orders: it asks the
store, shows the answer, and remembers nothing beyond a short cache.

## What it adds

| Where | What appears |
|---|---|
| A conversation | A **Commerce** section: the store customer this contact was matched to, and that customer's latest orders with status, payment, items and totals |
| Across stores | An **Overview** tab adding up every connected store's view of the same person — see [customer 360](customer-360) |
| The conversation | **Find an order**, which looks up an order by the number the customer quotes |
| Contact filters | Commerce conditions — linked store, platform, visible orders, visible spend per currency, last purchase, order, payment and shipment status — usable in a [shared audience](shared-audiences) |
| [Automation rules](automation-rules) | Triggers for an order being created, updated, paid, shipped, delivered, cancelled or refunded |
| [Flow Builder](flow-builder) | A lookup step that answers a customer asking about their own latest order, or an order they quote by number |
| A WooCommerce conversation | A short menu of order actions, once an administrator turns them on — see [connect WooCommerce](connect-woocommerce) |

What appears depends on the platform. The differences are real and large, so they live in one place:
[what each platform supports](commerce-provider-support).

## Everything is read when it is needed

There is no order table in Lynomia Chat and no scheduled import. A store is read when an agent opens the
conversation, when the store sends a webhook saying a customer changed, and when someone presses **Refresh**. An
answer is reused for 120 seconds. If the store cannot be reached, the last answer is shown for up to 24 hours,
labelled with the time it was fetched, rather than passed off as current.

Three consequences are worth knowing before you plan around it.

- **Figures are visible, not lifetime.** Each store returns its latest 5 orders for that customer. Spend is the
  total of the paid orders among those, per currency, never converted. It is not the customer's lifetime value.
- **A webhook carries no data.** It tells Lynomia Chat that one customer's orders changed; the orders are then
  read from the store. The webhook body itself is discarded.
- **A contact nobody has opened yet is unknown, not zero.** Order conditions in filters read what was last read.

## When to use it

- Agents need to answer "where is my order" without a second browser tab.
- You want to message a group defined by what they bought, with a [shared audience](shared-audiences).
- You want an automation rule to react to an order being paid, shipped or refunded.

## When not to use it

- **For reporting.** There is no commerce report. Nothing here totals revenue, orders per day or per agent.
- **For lifetime value.** See the explanation in [customer 360](customer-360).
- **For abandoned-cart recovery.** It is not available on any platform. See
  [what each platform supports](commerce-provider-support).
- **For bulk work on orders.** Actions are one order at a time, from one conversation, confirmed by a person.

## What you need first

- A plan that includes Commerce. Without it the section and the settings page do not appear.
- **Administrator** access to connect a store.
- Your platform offered on your installation. The platform picker shows the ones that are not as *Not available
  yet*; that is set by whoever runs your installation, not in your account.

## Steps

1. **Settings → Commerce → Add store.**
2. Choose your platform. Each connects differently: a key for
   [WooCommerce](connect-woocommerce), an app installation for [Salla](connect-salla),
   [Zid](connect-zid) and [Shopify](connect-shopify).
3. Open a conversation from a customer of that store. The Commerce section matches them and reads their orders.

## Who can do what

| Action | Who |
|---|---|
| Connect, rename, disable, disconnect a store | administrator |
| See the Commerce section, search an order, link or unlink a customer | any agent who can see the conversation |
| Change an order's status, resend a store email | administrator, or an agent whose custom role includes order management |
| Cancel or refund an order | administrator only |

## Limits

- **One store belongs to one Lynomia Chat account.** A store already connected elsewhere is refused.
- Your plan sets how many stores you may connect. A disconnected store stops counting.
- Store credentials are encrypted and never shown again, not even to the administrator who entered them.
- Matching is exact: a normalized email address, or a phone number in international form. **Names are never
  matched or searched.**
- Disconnecting deletes the store's credentials and every customer link it held. Contacts, conversations and the
  store itself are untouched.

## Related

- [What each platform supports](commerce-provider-support)
- [Customer 360](customer-360)
- [Shared audiences](shared-audiences)
- [Automation rules](automation-rules)

## If it does not work

**I do not see Commerce anywhere.** Your plan does not include it, or no store is connected yet.

**The platform I use is marked "Not available yet".** It is switched off on your installation. Ask whoever runs
it; there is no setting for this in your account.

**The section says the store needs re-authorization.** The store refused the credentials. An administrator
reconnects it, or replaces its keys, in Settings → Commerce.
