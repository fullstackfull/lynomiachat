---
title: Shared audiences
description: Build a customer group from conditions instead of a list, share it with your account, and use it in campaigns and automation.
position: 10
tags: [audiences, contacts, campaigns]
seo_description: "Shared audiences in Lynomia Chat: saved conditions that are answered again every time the audience is used, plus the presets you can start from."
---
An audience is a question about your customers that Lynomia Chat keeps answering. You write the conditions
once — "last purchase in the past 30 days", "has never written to us", "spent over 1,000 SAR" — and give them a
name. From then on, every time something opens, counts or sends to that audience, the conditions are run again
against your data as it is at that moment.

No membership is stored anywhere. There is no list of members to refresh, no sync button, and no way for an
audience to go stale. A customer who places an order this morning is in "recent buyers" this afternoon because
the question was asked again, not because anything was updated.

## A saved question, not a saved list

An audience is built in the contacts filter: apply some conditions, see who matches, then save the conditions
under a name. What you saved is the conditions — never the contacts that matched at the time. Delete the audience
later and the conditions go; every contact stays exactly as it was.

Because the answer is recalculated, an audience can only express things derivable from your data. "Customers who
complained and we escalated it" is not derivable, so that belongs in a [label](labels).

## When to use one

- The group changes on its own, as time passes or as orders arrive.
- You want the same group used in more than one place — a campaign this week, an automation rule next month.
- You want everyone in the account working from the same definition rather than each person's own filter.

## When not to use one

- The group is a decision your team made and nothing in the data implies. Use a label.
- You need a fixed list of exactly these people, frozen at a point in time. Lynomia Chat has no static list;
  the nearest thing is a label applied in bulk.

## What you need first

Nothing, for a personal audience built from contact and conversation conditions. For the **Commerce** conditions
you need a connected store — see [Commerce](commerce-overview). To share an audience with the account you need to
be an administrator.

## What you can ask about a contact

The condition picker groups the fields:

| Group | What it asks about |
|---|---|
| Standard and additional filters | name, email, phone number, identifier, labels, country, city, company, created at, last activity, blocked |
| Custom attributes | every contact attribute you have defined — see [custom attributes](custom-attributes) |
| Conversations | conversation status, priority, inbox, assigned agent, assigned team, conversation labels |
| Commerce | linked store, store platform, visible orders, visible spend per currency, last visible purchase, has an active order, order status, payment status, shipment status |

Conversation conditions are about *existence*: **Equal to** means the contact has at least one conversation like
that, **Not equal to** means none. Several values in one condition mean "or" — status *open or pending* is one
condition.

Commerce conditions read what Lynomia Chat has already stored locally, so evaluating an audience never calls your
store. That has two consequences worth knowing. Figures are **visible** orders and spend, not lifetime totals.
And a linked customer whose orders have not been read yet is *unknown*, never zero: it will not match "more than
3 orders", and it will not match "fewer than 3 orders" either. The filter panel tells you how many linked
contacts are in that state.

Spend is held per currency and never converted, so there is a separate field per currency and no way to add two
currencies together.

## Conditions join in a flat chain

Each condition joins the next with **and** or **or**, and "and" binds tighter than "or", so
`A and B or C` means `(A and B) or C`. There are no brackets and no nested groups. To express "Salla or Shopify,
and spend above 1,000", put both platforms as two values in one *Store platform* condition and add the spend
condition with **and**.

## Steps

1. Go to **Contacts** and open the filter panel.
2. Add your conditions and **Apply filters**. The list shows the first page and the total, as
   *Showing 1 - 15 of N contacts*.
3. **Save as audience**, give it a name, and — if you are an administrator — tick **Share with the whole
   account**.
4. It appears under **Audiences**, marked *Shared* or *Only you*.

## Start from a preset

**More actions → New audience from a preset** opens a short gallery. A preset fills in the conditions; you then
confirm the name and whether the account shares it, in the same dialog as always. What it creates is an ordinary
audience with editable conditions.

| Preset | Asks you for |
|---|---|
| Has contacted us | — |
| Has never contacted us | — |
| High-value buyers | currency and amount |
| Repeat buyers | number of orders |
| Recent buyers | number of days |
| Customers with an open order | — |
| Customers with a shipped order | — |
| Customers of one store | which store |
| All linked customers | — |

The first two work in any account. The other seven need Commerce, and are shown with what is missing rather than
hidden.

Note that "High-value buyers" asks you for the threshold. Lynomia Chat will not decide what a high-value customer
is for your business, and deliberately does not ship a preset called "VIP".

## Personal or shared

| | Personal | Shared |
|---|---|---|
| Who can open it | you | everyone in the account |
| Who can change or delete it | you | administrators |
| Usable in a campaign or an automation rule | no | yes |
| If its creator leaves | deleted with them | stays |

Sharing is always an explicit tick. Nothing converts a personal audience on its own. An agent can open a shared
audience and adjust the conditions to look at something, but cannot save, rename or delete it.

## A worked example

You want to message customers who bought in the last 60 days and have an open order.

1. **Contacts → filter**: *Last visible purchase — more than N days ago — 60*, joined with **and** to
   *Has an active order — Yes*.
2. **Apply filters**. The footer tells you how many match right now.
3. **Save as audience**, name it *Recent buyers with an open order*, tick **Share with the whole account**.
4. From the audience's **More actions**, choose **Use in a new WhatsApp campaign**.

Next month the same audience contains different people, with nothing to maintain.

## Who can do this

Any **agent** can build a filter and save a personal audience. Only an **administrator** can share one, change a
shared one, or delete a shared one. Changes to audiences are recorded in the audit log. See
[roles and permissions](roles-and-permissions).

## Limits

- **A filter may use at most 10 conversation or Commerce conditions**, and at most 50 values in one condition.
  Contact and custom-attribute conditions are not counted against that.
- Up to 1,000 saved filters per person.
- An audience with no conditions matches every contact. The Audiences page says so on the card.
- Editing a shared audience changes what every campaign and rule using it matches, immediately. The filter panel
  warns you with the count.
- You cannot delete a shared audience, or make it personal, while an automation rule or an unsent campaign
  references it. Remove it from those first.
- The contacts list shows a page at a time and a count, so there is no screen that shows the whole membership at
  once. There is no export button on an audience itself; export from the contacts list, which sends the filters
  you have applied.
- When *you* open an audience, conversation conditions only see conversations you are allowed to see. When a
  campaign or an automation rule reads the same audience it is evaluated for the whole account, so the two counts
  can differ.
- Nothing writes an audience's membership back onto contacts. There is no audience-to-label sync.

## Related

- [Labels or shared audiences?](labels-or-shared-audiences)
- [Labels](labels)
- [WhatsApp campaigns](whatsapp-campaigns)
- [Automation rules](automation-rules)
- [Contacts](contacts)
- [Commerce](commerce-overview)

## If it does not work

**I saved an audience and nobody else can see it.** It is personal. Only an administrator can share one, and only
by ticking **Share with the whole account**.

**My audience does not appear in the campaign's recipient picker.** Campaigns list shared audiences only.

**A customer I know bought something is not in my Commerce audience.** Their orders have probably not been read
yet. Lynomia Chat reads a linked customer's orders when an agent opens their conversation or the store sends an
update; until then the contact is unknown, not zero.

**I cannot delete the audience.** A rule or an unsent campaign is using it. The error says how many of each.

**My condition was rejected.** A value of the wrong kind, more than 50 values in one condition, or more than 10
conversation and Commerce conditions in one filter.
