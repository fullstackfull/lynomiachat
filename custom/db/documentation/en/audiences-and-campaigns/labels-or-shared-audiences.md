---
title: Labels or shared audiences?
description: The difference between a sticker you put on a customer and a question the system keeps answering, and how an unsaved filter fits between them.
position: 20
tags: [audiences, contacts, labels]
seo_description: When to use a label and when to use a shared audience in Lynomia Chat, and why an applied contact filter is neither.
---
Both group customers. Both can be the recipients of a WhatsApp campaign. They are still not interchangeable, and
picking the wrong one is the most expensive small mistake in the product.

The rule fits in one line:

> **If you can point at the customers, use a label. If you can describe them, use an audience.**

## Side by side

| | Label | Shared audience |
|---|---|---|
| **What it is** | a sticker stored on the contact | conditions stored under a name |
| **Who puts a customer in it** | a person | nobody — the conditions decide |
| **When membership changes** | when somebody adds or removes it | every time the audience is used |
| **Can go out of date** | yes, silently | no, there is nothing stored to be out of date |
| **Can record a decision** | yes, that is its only job | no |
| **Can express "bought in the last 30 days"** | not durably | yes |
| **Who creates it** | an administrator creates the label; any agent applies it | any agent saves one; an administrator shares it |
| **Visible to the account** | always | only when shared |
| **Campaign recipient source** | yes | yes, when shared |
| **Automation condition** | no | yes, when shared |

## The test

Ask: *can this change without anybody touching the contact?*

A customer becomes a "recent buyer" because time passed. Nobody did anything. That is an audience.

A customer becomes "VIP" because somebody decided so. There is no data that implies it. That is a label.

## Three things, not two

People usually compare labels with audiences and forget the thing in the middle.

| | What it is | How long it lasts | Who else sees it |
|---|---|---|---|
| **A contact filter** | conditions you have applied to the list you are looking at | until you clear them or leave | nobody |
| **A personal audience** | the same conditions, saved and named | until you delete it | nobody |
| **A shared audience** | the same conditions, saved and owned by the account | until an administrator deletes it | everyone |

A filter is a view. It is the right tool for a question you are asking once. Saving it is what turns the view
into something you can come back to, and sharing it is what makes it available to a campaign, to an automation
rule, and to your colleagues. Nothing can reference an unsaved filter, because there is nothing to reference.

So the honest sequence is: filter to explore, save when you will want it again, share when something other than
you needs it.

## What only a label can do

Record a judgement. `vip`, `wholesale`, `complaint-escalated`, `do-not-call`, `event-attendee`. None of these can
be worked out from your data, so no set of conditions will ever reproduce them.

A label is also the only way to pin an arbitrary set of people — the thirty contacts from a trade show, the list
somebody sent you. Lynomia Chat has no static audience. Import or select those contacts and apply a label in
bulk; see [import contacts](import-contacts) and [bulk actions](bulk-actions).

## What only an audience can do

Stay correct. "Spent over 1,000 SAR", "has an open order", "has never written to us", "customers of one store" —
each is re-answered when it is used, so there is no moment at which it is quietly wrong.

An audience is also the only one of the two that an [automation rule](automation-rules) can test. A rule can ask
*is this conversation's contact in audience X*. There is no condition anywhere that asks whether a contact carries
a particular label.

## The trap that costs money

Two things that look alike and are not:

**A conversation label is not a contact label.** They come from the same catalogue and are stored separately.
Tagging a conversation `vip` does not make that person a `vip` contact, and a campaign reads **contact** labels.
Build a campaign to a label that only ever went on conversations and it reaches nobody.

**No automation action labels a contact.** An automation rule's "add label" action always labels the
*conversation*. There is also no trigger for a contact being created or changed. So you cannot build a rule that
maintains a contact label for you — which is exactly why the questions people want such a rule for ("who has
contacted us?") are audience presets instead.

## Which to use, by case

| What you want | Use |
|---|---|
| customers who bought in the last 30 days | shared audience |
| customers with an order still open | shared audience |
| customers who have spent above a threshold | shared audience |
| customers of one connected store | shared audience |
| customers who have never written to us | shared audience |
| customers we decided are VIP | label |
| customers who asked not to be contacted | label |
| the thirty people from last week's event | label, applied in bulk |
| a one-off question you will not ask again | a filter, unsaved |

## A worked example

You want a monthly offer to good customers who are not wholesale accounts.

"Good customers" is describable: *Visible spend (SAR) — more than — 1000*. That is a shared audience.

"Wholesale" is a decision: your team knows which accounts those are. That is the `wholesale` label.

Lynomia Chat has no "exclude these" option on a campaign, so you cannot subtract the label from the audience.
Add a condition to the audience instead — contact labels are a filter field, so *Labels — not equal to —
wholesale* joined with **and** does it, inside the audience, once.

## Both are recipient sources

A campaign takes labels and shared audiences together, and each contact receives it once however many of them
they are in. So choosing correctly costs nothing at the point of sending — the cost is paid earlier, in whether
the group is still right by the time you send.

## Limits

- Nothing maintains a label for you. No rule, job or schedule anywhere adds or removes a contact label.
- Nothing writes an audience's membership onto contacts, either. There is no synchronisation in either direction.
- A personal audience cannot be used by a campaign or a rule. Only shared ones can.
- Label names are stored in lower case, must be at least two characters, and cannot contain spaces.
- Deleting a label removes it from everything carrying it, with no undo. Deleting an audience removes only its
  conditions.

## Related

- [Shared audiences](shared-audiences)
- [Labels](labels)
- [WhatsApp campaigns](whatsapp-campaigns)
- [Automation rules](automation-rules)
- [Contacts](contacts)
- [Bulk actions](bulk-actions)

## If it does not work

**My campaign to a label found no recipients.** The label is on conversations, not contacts. Open it under
**Contacts → Tagged with** — an empty page is the answer. Apply it to the contacts from the contacts list.

**I built the filter but cannot find it tomorrow.** An applied filter is not saved. Use **Save as audience**.

**I cannot see the audience I need in the campaign form.** It is personal. An administrator has to share it.

**I want a rule that fires when a contact gets a label.** That does not exist. Describe the same people as a
shared audience and have the rule test the audience instead.
