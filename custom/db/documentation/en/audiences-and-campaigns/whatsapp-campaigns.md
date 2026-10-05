---
title: WhatsApp campaigns
description: Send one approved WhatsApp template, at a time you choose, to everyone in a set of labels and shared audiences.
position: 30
tags: [campaigns, whatsapp, audiences]
seo_description: "WhatsApp campaigns in Lynomia Chat: choosing recipients, why only an APPROVED template can be sent, and when to use automation instead."
---
A WhatsApp campaign sends **one** template message, **once**, at a scheduled time, to every contact selected by
the labels and shared audiences you choose. That is the whole shape of it. It is not a sequence, not a drip, and
not a conversation — it is one outbound message to a group.

It exists because WhatsApp will not let you write freely to someone who has not messaged you recently. Outside
that window only an approved template may be sent, which is why a campaign asks you to pick a template rather
than type a message. See [the WhatsApp 24-hour window](the-whatsapp-24-hour-window).

## When to use it

An announcement, offer or reminder that goes to a described group at a moment you choose, and where you want to
see how many people it will reach before you send.

## When not to use it

- A reply to one customer. Reply in the conversation.
- Anything that should happen *because* something happened. That is automation, covered below.
- Anything you will want to edit later. A WhatsApp campaign cannot be edited once created, only deleted.

## What you need first

| | |
|---|---|
| A WhatsApp inbox on WhatsApp Cloud | campaigns refuse to run on any other WhatsApp provider |
| WhatsApp campaigns switched on for your account | off until enabled |
| An **APPROVED** template | see [WhatsApp templates](whatsapp-templates) |
| At least one label or shared audience | the form will not submit without one |
| Administrator access | every campaign action is administrator-only |

## Choosing who receives it

The **Recipients** section takes two kinds of source, and you can mix them:

- **Labels** — contacts carrying any of the labels you pick. Contact labels, not conversation labels.
- **Shared audiences** — contacts matching any of the audiences you pick. Personal audiences are not offered;
  only shared ones, because a campaign belongs to the account.

As you choose, Lynomia Chat counts the matching contacts on the server and shows the number. Each contact is
counted and sent to **once**, however many of your labels and audiences they fall into.

Two things about that number matter. **It is the count now, not at send time** — recipients are worked out again
when the campaign is dispatched, and for a date-based or order-based audience that will be a different set of
people. And **it is a count, not a list**: no screen shows exactly who will receive a campaign, so open the
audience or the label in **Contacts** to inspect the people.

If your account has no shared audiences yet, the Recipients section explains what one is and offers to take you
to build one. Your draft campaign is kept while you do.

## Only an APPROVED template can be sent

Meta approves each template before it can be used, and Lynomia Chat enforces that in two independent places.

The template picker offers a template only when **all** of these hold:

- Meta's status for it is APPROVED;
- it is not an AUTHENTICATION template;
- it is not a customer-satisfaction survey template;
- it has no list, product, catalogue or call-permission component, and no location header.

Then, at the moment of sending, the template is looked up again in that channel's synced list by name and
language and must still be APPROVED. A template that was approved when you built the campaign and has since been
paused, rejected or removed is not sent — nothing is sent to that contact at all.

Meta decides a template's category when it approves it. A UTILITY template and a MARKETING template are both
sendable here, and the category of an already-approved template cannot be changed; to move a template between
categories you create a new one.

## Steps

1. **Campaigns → WhatsApp campaigns → Create campaign.**
2. **Title** — for you and your colleagues, never shown to the customer.
3. **Select Inbox** — the WhatsApp channel it is sent from.
4. **WhatsApp Template** — pick one, then fill in its variables. The preview shows the message as the customer
   will see it.
5. **Recipients** — labels, shared audiences, or both. Check the count.
6. **Scheduled time** — required. There is no "send now".
7. **Create.** The campaign appears in the list as *Scheduled*.

Lynomia Chat checks for due campaigns every five minutes, so a campaign goes out at the first check at or after
its scheduled time. While it is sending the card reads *Processing*; afterwards, *Completed*.

## A worked example

A clearance offer to customers who bought in the last 90 days, excluding wholesale accounts.

1. In **Contacts**, filter *Last visible purchase — more than N days ago — 90* **and** *Labels — not equal to —
   wholesale*. Save it as a shared audience called *Retail buyers, last 90 days*.
2. In the template manager, make sure your offer template is APPROVED.
3. **Campaigns → WhatsApp campaigns → Create campaign.** Choose the inbox and the template, fill in the
   variables, and pick that audience under **Shared audiences**.
4. Read the count. Schedule it for 10:00 tomorrow and create it.

The exclusion lives in the audience, because a campaign has no "exclude these people" field.

## Campaigns or automation?

They answer different questions, and the difference is not about size.

| | Campaign | [Automation rule](automation-rules) |
|---|---|---|
| **Starts because** | a time you set | an event happened |
| **Acts on** | a group you described | the one conversation the event occurred on |
| **Sends** | one template | a message, or a label, assignment, status change, webhook |
| **Runs** | once | every time the event happens |
| **Conditions** | none — the recipients *are* the condition | yes, and nothing runs unless they match |
| **Needs the 24-hour window open** | no, it sends a template | for a text reply, yes |

Choose a **campaign** when you are the one deciding that now is the moment and the recipients are a group. Choose
**automation** when the customer or your store decides the moment — an order shipped, a message arrived, a
conversation was resolved — and the thing to do concerns that one conversation.

A rule cannot message a group; it has no audience. A campaign cannot react to anything; it has no trigger. The
one place they meet is that a rule can test whether a conversation's contact is in a shared audience, so the same
audience can define who gets the campaign and who gets the follow-up. See
[macros or automation?](macros-or-automation) for the neighbouring distinction.

## Who can do this

**Administrators** only — listing, creating, viewing and deleting campaigns, and the recipient count. Agents
have no access to the campaigns section. See [roles and permissions](roles-and-permissions).

## Limits

- **A campaign cannot be edited after it is created.** Delete it and create another. Deleting is also the only
  way to cancel a scheduled campaign.
- **There is no send-now, no draft and no pause.** A campaign is scheduled or it does not exist.
- **A scheduled time more than three days in the past is never sent.** If your account was down over that
  window, recreate the campaign.
- **Blocked contacts are not excluded, and there is no opt-out list.** Whatever you want excluded has to be a
  condition in the audience or a label you filter against.
- **A recipient without a usable destination is skipped.** A contact needs a phone number, or exactly one
  WhatsApp identity on that inbox. A contact with two identities on the same inbox is skipped rather than
  guessed at.
- **A template variable that renders empty skips that contact.** If you use `{{ contact.name }}` and a contact
  has no name, they do not receive the message. Check your data, or choose a template without that variable.
- **The campaign message does not appear in your inbox.** A campaign sends through WhatsApp directly and creates
  no conversation and no outgoing message. When somebody replies, that reply opens a conversation as usual.
- **Per-recipient delivery results are not available on every installation.** Where they are, a **View
  analytics** button appears on a WhatsApp campaign once it has started sending, and shows each recipient as
  queued, skipped, sent, delivered, read or failed, from WhatsApp's own status updates. A campaign still
  scheduled has nothing to show yet.
- A shared audience cannot be deleted or made personal while a campaign that has not yet been sent references it.
- SMS campaigns use the same Recipients section, but WhatsApp's template and window rules do not apply to them.

## Related

- [Shared audiences](shared-audiences)
- [Labels or shared audiences?](labels-or-shared-audiences)
- [WhatsApp templates](whatsapp-templates)
- [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)
- [Automation rules](automation-rules)
- [Labels](labels)

## If it does not work

**My template is not in the dropdown.** It is not APPROVED, it is an authentication template, it is a survey
template, or it uses a component campaigns cannot send — a list, a product or catalogue block, a call-permission
button, or a location header. Check its status in the template manager first.

**The dropdown is empty altogether.** No inbox is selected, or the selected inbox has no approved templates
synced yet.

**The campaign says Completed but people tell me they got nothing.** If your installation has campaign
analytics, open **View analytics**: each recipient carries its own outcome and a reason when it was skipped or
failed — usually a missing phone number, a variable that rendered empty, or an error WhatsApp returned. The three
most common causes are a template that stopped being APPROVED, a variable rendering empty, and recipients with no
phone number.

**My recipient count is zero.** Your labels are on conversations rather than contacts, or the audience genuinely
matches nobody right now. Open each one in **Contacts** to see which.

**I cannot find the campaigns section.** You are not an administrator, or WhatsApp campaigns are not switched on
for your account.

**The count will not load.** The number is unknown, not zero. Reopen the form and reselect the recipients.
