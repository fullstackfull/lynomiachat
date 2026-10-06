---
title: Automation rules
description: Build a rule that watches for one event, checks the conditions you set, and does the work nobody should have to remember.
position: 10
tags: [automation]
seo_description: "Automation rules in Lynomia Chat: the real trigger events, what a condition can test, what an action can do, and the recipes that write a rule for you."
---
An automation rule is three things, in this order: **one event**, **the conditions that must be true**, and **the
actions to run**. Nothing else. If you can say "when X happens, and Y is true, do Z", you can build it.

Rules run on the server, so they work overnight, at the weekend, and while every agent is logged out.

## When to use one

When the trigger is a fact rather than a judgement, and you want the same thing to happen every time. Routing new
conversations to a team. Labelling anything that mentions a word you care about. Raising the priority of a
customer you have already described as an [audience](shared-audiences).

## When not to use one

- **When somebody has to read the conversation first.** That is a [macro](macros).
- **When you need to ask the customer something and branch on the answer.** A rule runs its actions and finishes;
  it cannot wait. That is the [flow builder](flow-builder) — see
  [Automation or flow builder?](automation-or-flow-builder).

## What you need first

An **administrator** account. Rules live under **Settings → Automation**. Commerce triggers also need a store
connected under [Commerce](commerce-overview).

## The real trigger events

A rule picks exactly one. There are twelve.

| Group | Events |
|---|---|
| **Conversations** | conversation created, conversation updated, conversation opened, conversation resolved, message created |
| **Commerce** | order created, order updated, order paid, order shipped, order delivered, order cancelled, order refunded |

A Commerce trigger fires when Lynomia Chat reads a change in a linked customer's orders, and acts on **the
contact's most recent conversation**. If that contact has no conversation, nothing runs.

Which Commerce events ever fire depends on the platform: WooCommerce has no shipped or delivered status, and
Shopify has no cancelled one. The recipe gallery says so next to each affected recipe.

## What conditions and actions are available

Conditions cover the conversation (status, priority, inbox, assignee, team, labels), the message (its text, its
type, whether it is a private note), the contact (email, phone, company, country, language), your custom
attributes, whether the contact is in a **shared audience**, and what Commerce knows about them. On a Commerce
trigger you can also test the order's store and store platform. Conditions join with **and** or **or**, and the
form expects at least one.

Actions cover ownership (assign or unassign an agent or team), classification (add or remove a label, change
priority), status (resolve, reopen, mark pending, snooze, mute), messages (send a message, add a private note,
send an attachment, email a transcript, email a team) and **send a webhook event**.

A Commerce trigger deliberately offers neither **send a message** nor **send an attachment**: a store event is
not a customer message, and the conversation may be outside
[the WhatsApp 24-hour window](the-whatsapp-24-hour-window). Use a private note and a team instead.

## Recipes

A recipe fills in a working rule and asks only for what it cannot know — which team, label, store, audience or
amount. The eleven cover order routing, refund escalation, paid-order priority, cancelled-order follow-up,
audience labelling and priority, spend-based routing, open-order routing, sending an order event to another
system, and greeting every new conversation. The same gallery also offers a setup recipe that creates a shared
audience and a rule that uses it, in one go.

**A rule created from a recipe starts switched off.** You read it, edit the wording, and turn it on yourself. A
rule you build by hand is live the moment you save it. Either way it is then an ordinary rule.

## A worked example

Refund questions must reach the returns team within seconds, at any hour.

1. **Settings → Automation → Create automation**. Name it *Refund to returns*.
2. Event: **message created**.
3. Condition: *content — contains — refund*.
4. Actions: add label `refund`, assign team **returns**, priority **high**.
5. Save, send yourself a WhatsApp message containing the word, and check the conversation.

## Who can do this

Administrators only — creating, editing, cloning, switching on and deleting. Automation is not one of the
permissions a custom role can be granted, so a custom role cannot be given this page. See
[roles and permissions](roles-and-permissions).

## Limits

- **No time-based conditions** of any kind: no business hours, time of day or day of week.
- **No priority escalation.** A rule sets a priority once. Nothing raises it as a conversation ages.
- **A rule's own actions do not trigger other rules.** This prevents loops, and means rules cannot be chained.
- **One event per rule.** Two events means two rules, and both can match the same change.
- **"Add label" labels the conversation, never the contact,** and there is no trigger for a contact changing. See
  [Labels or shared audiences?](labels-or-shared-audiences).
- **A failed action is not reported.** Each action is attempted in turn; the rest still run, silently.
- **Commerce rules never wait,** and each runs at most once per order change.
- **Waiting rules are optional and off by default.** A rule can act only if something is *still* true after 10
  minutes to 30 days, but it must be enabled for your account, and on a conversation event it can test only
  **status** and **inbox**. Editing such a rule discards the waits already armed.

## Related

- [Automation or flow builder?](automation-or-flow-builder)
- [Macros or automation?](macros-or-automation)
- [Flow builder](flow-builder)
- [Shared audiences](shared-audiences)

## If it does not work

**Nothing happened.** Check the switch first — a rule from a recipe is off until you turn it on. Then check that
the conditions can be true at the moment the event fires. A condition on a label the rule itself adds later
never matches.

**It ran twice.** Two rules on two events can both match one change.

**A Commerce rule never fires.** Either your platform does not report that status, or the contact has no
conversation to act on.
