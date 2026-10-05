---
title: Automation or flow builder?
description: One reacts to an event and finishes. The other remembers where it is and waits for the customer. Pick on that difference alone.
position: 30
tags: [automation]
seo_description: When to use an automation rule and when to use a flow in Lynomia Chat, and the limits that decide it for you.
---
Both do things to a conversation without a person involved. Both can label it, route it, change its priority and
call a webhook. The lists overlap enough that reading them will not tell you which to use.

One sentence will:

> **An automation rule reacts and finishes. A flow remembers and waits.**

A rule is a reflex. Something happens, the conditions are checked once, the actions run, it is over. A flow is a
conversation: it sends something, stops, and the customer's reply decides what happens next.

## Side by side

| | Automation rule | Flow |
|---|---|---|
| **What starts it** | one of twelve events | a customer's message, nothing else |
| **Channels** | every channel | WhatsApp Cloud only |
| **Can wait for a reply** | no | yes, that is the point |
| **Remembers what was said** | no | yes, for the whole session |
| **Branches** | no — conditions decide whether it runs at all | yes, on every answer |
| **Can ask a question** | no | yes |
| **Can send a menu or buttons** | no | yes |
| **Can start from a store event** | yes, seven order events | no |
| **Runs with nobody online** | yes | yes |
| **Needs the conversation pending and unassigned** | no | yes |
| **Review before it goes live** | an on/off switch | a draft you publish |
| **Who can build it** | administrators | administrators |

## The question that decides it

**Do you already know everything you need?**

If yes — the message mentioned "refund", the contact is in the VIP audience, an order was just refunded — then
you have all the facts at the moment the event fires. Use a rule.

If no — you need to know *which* department, *which* order number, *what* went wrong — then you have to ask, and
asking means waiting. Use a flow.

## What only a rule can do

- **Start from something other than a message.** Seven order events, a conversation being resolved, a
  conversation being opened. A flow cannot be entered by any of these.
- **Work on channels other than WhatsApp Cloud.** A flow cannot.
- **Act on a conversation that is already being handled.** A flow only ever runs while a conversation is pending
  with nobody assigned; a rule does not care.
- **Email a team, or email a transcript.** There is no flow node for either.

## What only a flow can do

- **Ask, and use the answer.** The reply can be stored on the contact or the conversation and quoted back in
  later messages.
- **Branch.** Buttons and lists create one path per option. A condition node splits the path in two.
- **Look up an order.** The contact's own newest order, or a number they type.
- **Hand over deliberately,** with a team, a priority, labels and a note attached to the handoff.
- **Be tested before anybody sees it.** A flow draft runs against a test contact with nothing sent.

## Neither of them can

- **Behave differently out of hours.** There is no business-hours, working-hours or time-of-day condition
  anywhere, and no flow node for it. Whatever you build runs the same at 2pm and at 2am.
- **Escalate a priority over time.** Both set a priority once. Nothing raises it as a conversation ages.
- **Label a contact.** Both label the *conversation*. See
  [Labels or shared audiences?](labels-or-shared-audiences).
- **Start a conversation.** For that you need a [WhatsApp campaign](whatsapp-campaigns).

## Use both, in order

The usual shape of a working setup is a flow in front and rules behind it.

1. **The flow** greets the customer on WhatsApp, asks what they need, and hands the conversation to the right
   team with the answer already written down.
2. **A rule** on *conversation created* labels anything from a high-spend audience, so the right conversations are
   findable and reportable whatever path they took.
3. **Another rule** on *order refunded* raises the priority of that customer's latest conversation and routes it
   to returns — a store event the flow could never have seen.

Each does the part the other cannot. Neither is a fallback for the other.

## A worked example of choosing wrongly

You want: "if nobody has replied within four hours, tell the manager."

Neither tool does this well, and knowing that early saves a day. A flow cannot: it is not running once a person
has the conversation. A plain rule cannot: it reacts to an event, and "four hours passed" is not an event. There
is an optional **waiting** rule that handles exactly this shape — *no teammate has replied for N* — but it has to
be enabled for your account and is off by default, and it can only test the conversation's status and inbox.

The honest answer is to check whether waiting rules are enabled for your account before designing around them.

## Related

- [Automation rules](automation-rules)
- [Flow builder](flow-builder)
- [Macros or automation?](macros-or-automation)
- [Agent bots](agent-bots)

## If it does not work

**I built a flow and it never ran.** It was probably not a WhatsApp Cloud inbox, or the conversation was not
pending and unassigned. Both are hard requirements.

**I built a rule to ask the customer something.** A rule's "send a message" sends and finishes — the reply goes
to your team, not back to the rule. Rebuild it as a flow.

**I need an order change to start a conversation flow.** That combination does not exist. A store event can only
start a rule, and a rule cannot send a message to a customer on a Commerce trigger.
