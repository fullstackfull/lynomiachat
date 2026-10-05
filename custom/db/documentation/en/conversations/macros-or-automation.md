---
title: Macros or automation?
description: The difference is who starts it. A person presses a macro; an event starts an automation rule.
position: 60
tags: [conversations, automation]
seo_description: When to use a macro and when to use an automation rule in Lynomia Chat, and what each one can do that the other cannot.
---
Macros and automation rules do almost the same things to a conversation. They assign it, label it, change its
status and priority, send a message, leave a note, call a webhook. If you read only the list of actions, you
would not be able to tell them apart.

The difference is one thing, and it is the only thing that matters:

> **A macro waits for a person. An automation rule waits for an event.**

Everything else follows from that.

## Side by side

| | Macro | Automation rule |
|---|---|---|
| **Who starts it** | an agent presses it | an event fires it |
| **How many conversations** | the one in front of them | every conversation the event happens on |
| **Conditions** | none — every action always runs | yes, and nothing runs unless they match |
| **Preview before it runs** | yes, the action list | no, it has already happened |
| **Who can create it** | any agent (private), administrators (public) | administrators only |
| **Can be switched off** | delete it, or stop pressing it | an on/off switch, kept for later |
| **Runs while nobody is working** | no | yes |
| **Judgement involved** | the agent's | none |

## Choose a macro when

- **Somebody has to read the conversation first.** "Is this an escalation?" is not a question a condition can
  answer. "Does this customer sound like they are about to leave?" even less so.
- **You want the agent to stay in control.** They see the actions before pressing, and they can choose not to.
- **An agent needs it and nobody will build it for them.** Any agent can create a private macro in two minutes.
  An automation rule needs an administrator.
- **You want it to assign to whoever is dealing with it.** A macro's "assign an agent" offers **Self**, meaning
  the person pressing. Automation has no equivalent, because there is nobody pressing.

## Choose an automation rule when

- **The trigger is a fact, not a judgement.** A conversation arriving on a channel. A message containing a word.
  A conversation being resolved. An order being shipped.
- **It must happen even at 3am.** Rules run whether or not anybody is logged in. Macros do not run themselves,
  ever.
- **It must happen every time without exception.** Relying on each agent remembering to press something is how
  a process quietly stops being followed.
- **It needs to look at things a macro cannot see.** A rule can condition on the message's text, the contact's
  country, the language, the channel, a label, a custom attribute, a shared audience the contact is in, or what
  your store knows about them. A macro has no conditions at all.

## What each one can trigger on

A macro has no trigger. An agent presses it.

An automation rule picks exactly one event:

| Event | Fires when |
|---|---|
| Conversation created | a new conversation arrives |
| Conversation updated | something about it changes |
| Conversation opened | it moves into open |
| Conversation resolved | it moves into resolved |
| Message created | a message is added |
| Commerce order created / updated / paid / shipped / delivered / cancelled / refunded | your connected store reports that change |

The Commerce events need [Commerce](commerce-overview) connected, and they act on the contact's most recent
conversation. They deliberately offer no customer-facing message action: a store event is not a customer message,
and the conversation may be outside its 24-hour window.

## The few actions only one of them has

The action lists overlap almost entirely. The exceptions:

- **Automation only:** email a team, reopen a conversation, mark a conversation pending.
- **Macro only:** assign to **Self**.

Everything else — labels, priority, agent, team, resolve, snooze, mute, send a message, private note, attachment,
email transcript, webhook — is available in both.

## A worked example of using both

Every WhatsApp conversation that mentions "refund" should be labelled and routed, and then a human decides
whether it becomes a formal complaint.

1. **An automation rule**, on *message created*, condition *content contains "refund"*: add the label `refund`
   and assign the **returns** team. This happens every time, including overnight.
2. **A macro** called *Escalate to management*, which an agent presses only when the customer is genuinely
   unhappy: priority high, assign management, label `complaint-escalated`, private note.

The rule does the part with no judgement in it. The macro does the part that needs a person, and makes that
person's decision fast and consistent.

## Who can do this

Creating and editing **automation rules** is **administrator**-only, with no exceptions. Creating a **private
macro** is open to any **agent**; public macros are administrator-only. See
[roles and permissions](roles-and-permissions).

## Limits

- **An automation rule's actions do not trigger other rules.** A rule that resolves a conversation will not set
  off your "conversation resolved" rule. This stops loops, and it also means you cannot chain rules.
- **A macro cannot wait.** Neither can an instant automation rule. A rule *can* be set to run after a delay —
  "if the conversation is still in this status N minutes later" — but delayed automation is a capability that has
  to be enabled for your account, and it is off by default.
- **A delayed rule can only wait on status, and on the channel.** It cannot wait on a label, an assignee or a
  changed attribute.
- Neither can ask the customer a question and branch on the answer. That is the [flow builder](flow-builder) —
  see [Automation or flow builder?](automation-or-flow-builder).
- Neither reports a failed action to you. Check the result the first few times you use a new macro or rule.

## Related

- [Macros](macros)
- [Automation rules](automation-rules)
- [Automation or flow builder?](automation-or-flow-builder)
- [Canned responses](canned-responses)
- [Assign and prioritise](assign-and-prioritise)

## If it does not work

**My macro did not run on its own.** It never will. A macro only runs when somebody presses it. If you want it
automatic, rebuild it as an automation rule.

**My automation rule did nothing.** Check it is switched on, that the event is the one that actually happens,
and that the conditions match. A condition on something the event cannot see — a label on a conversation that
has not been labelled yet — never matches.

**The rule ran twice.** Two rules on different events can both match the same change. Check the list rather than
assuming one rule misbehaved.
