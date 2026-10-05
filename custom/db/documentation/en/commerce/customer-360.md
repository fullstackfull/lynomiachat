---
title: Customer 360
description: You will know what the Overview tab adds up across your stores, how a contact is matched to a store customer, and why visible spend is not lifetime value.
position: 70
tags: [commerce, contacts]
seo_description: "Customer 360 in Lynomia Chat: every store's view of one contact beside the conversation, how matching works, and visible spend versus lifetime value."
---
Customer 360 is the **Overview** tab of the Commerce section in a conversation. It asks every connected store
what it knows about this one person, at the moment you look, and adds the answers up. It appears once you have
more than one store; with a single store the section shows that store directly.

## What it shows

| Line | What it is |
|---|---|
| **Stores** | how many are connected, and in how many this contact is linked to a store customer |
| **Orders** | how many orders are visible right now, with the hint *not a lifetime total* |
| **Last purchase** | the newest order that is not a draft, a failure or a cancellation |
| **Spend** | the total of the **paid** orders among those shown, one figure per currency |
| **Activity** | how many of the visible orders are active, and how many are shipped |
| **Recent orders** | up to ten, newest first, each labelled with the store it came from |
| **Stores** | one row per store: linked, not linked, needs re-authorization, or could not be refreshed |

Stores are read at the same time, and the tab answers after about fifteen seconds whatever is still running. A
store that failed or was too slow says so in its own row. One bad store never blanks the tab.

## Customer 360 or a contact?

They answer different questions, and only one of them is yours to edit.

| | Contact | Customer 360 |
|---|---|---|
| What it is | the person's record in Lynomia Chat | a live view of what your stores say about that person |
| Where it lives | your database | the stores; nothing is copied onto the contact |
| What it holds | phone, email, identifier, [labels](labels), [custom attributes](custom-attributes), notes, conversations | store customer links, and orders read a moment ago |
| Who edits it | you and your agents | your stores |
| If you disconnect the store | unchanged | the orders disappear with it |

So: the contact is the identity, Customer 360 is the evidence. Nothing you see in Customer 360 can be edited
there, and nothing written on a contact changes what a store reports. See [contacts](contacts).

## How a contact gets linked

A store customer is matched to a contact in this order:

1. **An existing link.** Once linked, it stays until someone changes it.
2. **The conversation's own phone number** — the WhatsApp or SMS number the message arrived on. Exactly one
   matching store customer is linked automatically. Several are offered for an agent to choose from.
3. **The contact's email, then its phone field.** These are agent-editable, so matches here are only
   *suggestions*: the panel shows them and an agent confirms.

Matching is exact, on a normalized email address or a phone number in international form. **Names are never
matched and never searched.** If nothing matches, an agent can search the store by email or phone and link the
right customer by hand. **Unlink** is remembered: the phone will not link that contact again on its own.

## Visible spend is not lifetime value

This is the most important sentence in the article: **the figures describe the orders Lynomia Chat can see, not
the customer's history.** Four reasons, all of them structural.

- **Each store returns its latest 5 orders** for that customer. Everything — the order count, the spend, the
  activity counts — is computed over those. A customer with forty orders shows five.
- **Only orders the store reports as paid count towards spend.** An order the store leaves unconfirmed does not,
  and a refunded or partially refunded order drops out. For a **Salla** store nothing is ever reported as paid,
  so a Salla-only contact has no spend figure at all — see
  [what each platform supports](commerce-provider-support).
- **Currencies are never converted.** Spend is a figure per currency, side by side. There is no total.
- **Platform windows apply.** A **Shopify** store returns only the last 60 days.

There is also no commerce report anywhere in Lynomia Chat. If you need lifetime value, your store or your
finance system is where it lives. What Customer 360 is good at is the question an agent actually has: what did
this person buy, and where is it now.

## Keeping it current

The tab reads the stores when you open it, reuses that answer for two minutes, and reads again when a store says
this customer changed. **Refresh** reads immediately, then waits 30 seconds, shared by everyone looking at the
same contact. If a store cannot answer, the last answer is shown for up to 24 hours, labelled *Showing data
from …* rather than presented as current.

## Finding an order the customer quotes

**Find an order**, in a store's view, looks up an exact order number across your stores, for when the order is
not among the five shown. Digits only, up to ten searches a minute per agent, each recorded in the audit log. An
order found this way **may belong to any customer of the store**, so it is shown without its customer and its
tracking details cannot be sent into the conversation. Salla stores are reported as not searchable.

## Limits

- Only **active** stores whose platform is offered are read. A disabled store, or one waiting for
  re-authorization, is listed without data.
- Nothing here is stored on the contact, and nothing is written back to a store.
- A linked contact nobody has opened yet is **unknown**, not zero, to the Commerce conditions in contact filters
  and [shared audiences](shared-audiences).

## Related

- [What each platform supports](commerce-provider-support)
- [What connecting a store gives you](commerce-overview)
- [Contacts](contacts)
- [Shared audiences](shared-audiences)

## If it does not work

**"Customer not linked" for someone I know bought from us.** Their email and phone in the store do not match
what Lynomia Chat holds, or they checked out as a guest on a platform where guests cannot be matched. Search the
store by email or phone and link by hand.

**The wrong customer is linked.** Use **Change** to link the right one, or **Unlink**. Both are recorded.

**Spend is empty but there are orders.** None of the visible orders is reported as paid. On Salla that is
permanent.

**A store row says it could not be refreshed.** It did not answer in time. Press **Refresh** after the cooldown;
if it persists, an administrator re-authorizes the store in Settings → Commerce.
