---
title: Connect WooCommerce
description: You will have a WooCommerce store connected with a REST API key, and you will know what the Read and Read/Write choice decides.
position: 30
tags: [commerce, woocommerce]
seo_description: "Connect a WooCommerce store to Lynomia Chat with a REST API key, and the difference a Read/Write key makes to live updates and order actions."
---
WooCommerce connects with a **REST API key** you create in your own WordPress admin. There is no app to install
and nothing to approve. The key decides what Lynomia Chat may do for the whole life of the connection, so the
first screen asks you to choose before it asks for anything else.

## Read or Read/Write

| | Read | Read/Write |
|---|---|---|
| Agents see each customer's orders | yes | yes |
| Live updates when an order changes | no | yes |
| Order actions, once you turn them on | no | yes |

Live updates work because Lynomia Chat creates three webhooks in your store, and WooCommerce only accepts
webhook changes from a key with write permission. With a Read key nothing is created and the store still works:
orders are read when an agent opens the conversation or presses **Refresh**.

Read/Write is the recommended choice. It does not hand agents the power to change orders: order actions are off
for the store until an administrator turns them on, and refunds and cancellations stay with administrators even
then.

## What you need first

- **Administrator** access in Lynomia Chat, and a plan that includes Commerce.
- **WooCommerce REST API v3** reachable at your store address. This is WooCommerce's own built-in API; no plugin
  is required.
- The store on **https**, on its domain name, on the standard port. An IP address, a custom port or an address
  on a private network is refused. If your address redirects somewhere else, enter the address it ends at.
- A **WordPress administrator** to own the key.

## Steps

1. **Settings → Commerce → Add store → WooCommerce.**
2. Choose **Read** or **Read/Write**. The steps below change to match.
3. In WordPress, open **WooCommerce → Settings → Advanced → REST API** and click **Add key**.
4. Choose an administrator as the user, and set **Permissions** to the one Lynomia Chat named in step 2.
5. **Generate** the key. WordPress shows the consumer key and consumer secret once.
6. Paste both into Lynomia Chat, give the store a display name if you want one, and choose **Test and connect**.

Lynomia Chat calls the store before saving anything. It confirms the API answers as WooCommerce v3, that it can
list orders and that it can list customers. Keys that fail are not stored, so a store never exists in a state
where its credentials do not work.

## A worked example

You run one store and want agents to see orders and live updates.

1. Choose **Read/Write** and create a Read/Write key owned by your WordPress administrator account.
2. Connect. The store appears as **Active**, with *Live order updates on* beneath it.
3. Leave order actions off for a week while agents get used to the section.
4. When you are ready: **Turn on order actions** on the store, and give the agents who should change statuses a
   custom role that includes order management. Refunds and cancellations remain yours.

## Who can do this

Connecting, replacing keys, disabling, turning order actions on and disconnecting are **administrator** actions,
all recorded in the audit log. Any agent who can see a conversation sees the Commerce section.

## Limits

- **No shipments.** WooCommerce core stores no shipment or tracking data, so Lynomia Chat shows none, and a
  WooCommerce order never reads as *shipped* or *delivered*. Tracking plugins are not read.
- **Order search works by order id.** WooCommerce numbers orders by their internal id, which is what the lookup
  uses. If a plugin renumbers your orders, those orders are not found by number.
- **Order actions are a short list**: processing → completed or on hold, on hold → processing, cancel an unpaid
  order, refund in full or in part, resend the order details email, resend the payment link. There is no way to
  change shipping or an address, and no status beyond that allow-list — never *trash*, never a plugin's own
  status.
- **A refund may or may not move money.** If the order's gateway supports refunds, the money goes back to the
  customer. If it does not, the store records the refund and nothing is sent. The confirmation step says which.
- Keys are encrypted and never shown again. To change them use **Replace keys**, which tests the new pair first.
- The three webhooks Lynomia Chat creates are named *Lynomia Commerce*, and disconnecting removes them. A Read
  key cannot, so WooCommerce disables them itself after five refused deliveries.
- Abandoned carts are not available: WooCommerce has no merchant-wide abandoned-cart API.

## Related

- [What each platform supports](commerce-provider-support)
- [What connecting a store gives you](commerce-overview)
- [Customer 360](customer-360)

## If it does not work

**"The store is not reachable right now."** The address is wrong, the site is down, or something in front of
WordPress is blocking the request. Open the address in a browser: it should load over https without redirecting.

**The connection fails and mentions the WooCommerce API.** The REST API did not answer as WooCommerce v3. A
security plugin blocking `/wp-json`, or WooCommerce being inactive, are the usual causes.

**"The store rejected the credentials."** The key was revoked or mistyped. Create a new key and use **Replace
keys**.

**It says live order updates are off and the key is read-only.** You created a Read key. Create a Read/Write key
and replace it; the webhooks are created on the next successful save. The same key is what **Turn on order
actions** needs.

**An agent cannot see Cancel or Refund.** Those are administrator-only, and no custom role grants them.
