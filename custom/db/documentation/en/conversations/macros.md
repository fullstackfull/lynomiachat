---
title: Macros
description: Turn the five things you always do to a conversation into one button an agent presses.
position: 50
tags: [conversations]
seo_description: Macros in Lynomia Chat: a saved sequence of actions an agent runs on one conversation, and what they can and cannot do.
---
A macro is a named list of actions, run in order, on **one conversation**, because a person pressed it.

Think of the sequence your team repeats without thinking. Escalating: raise the priority, hand it to the right
team, tag it, leave a note explaining why. Four separate clicks in four separate places, done slightly
differently by each agent, several times a day. A macro makes it one.

## When to use one

When the same group of actions always goes together, and a person decides when. That decision is the whole point
of a macro — it waits for judgement, and then does the mechanical part perfectly.

## When not to use one

- **When nobody needs to decide.** If the trigger is an event rather than a judgement, you want an
  [automation rule](automation-rules). [Macros or automation?](macros-or-automation) is the full comparison.
- **When it is only a message.** One reply and nothing else is a [canned response](canned-responses).
- **When it needs to wait for the customer's answer.** A macro runs its actions and stops. A conversation that
  branches on what the customer says is a job for the [flow builder](flow-builder).

## What a macro can do

Fifteen actions, in any order, repeated as often as you like:

| Group | Actions |
|---|---|
| **Ownership** | assign an agent, assign a team, remove the assigned agent, remove the assigned team |
| **Classification** | add a label, remove a label, change priority |
| **Status** | resolve, snooze, mute |
| **Messages** | send a message, add a private note, send an attachment, send an email transcript |
| **Elsewhere** | send a webhook event |

Two of these are worth calling out.

**"Assign an agent" offers Self.** It means whoever presses the macro, not a named person — so one macro works
for the whole team.

**"Snooze" in a macro sets no time.** It snoozes until the customer's next reply. If you want a timed snooze, do
it by hand.

## Steps

1. Go to **Settings → Macros → Add macro**. You can start from a ready-made macro in the starter gallery, or
   build one action at a time.
2. Name it for what it achieves, not for what it does: "Escalate to management" reads better in a list than
   "Priority + assign + label".
3. Add actions. They run top to bottom, and you can drag them into order.
4. Choose **Private** (only you) or **Public** (everyone in the account).
5. Save.

To run it: open a conversation and press the macro in the panel beside it, or type `#` in the composer and pick
it. Either way you see the list of actions before it runs.

## A worked example

A customer's question needs the manager, and your team has been handling this inconsistently.

1. Create a macro called **Escalate to management**:
   - change priority to **high**
   - assign team **management**
   - add label `complaint-escalated`
   - add private note: *"Escalated. Please review and reply."*
2. Make it **Public** so the whole team has it.
3. An agent reading a complaint presses it once. The conversation is now high priority, owned by management,
   findable later by its label, and carries a note saying what happened.

The agent still decided this was an escalation. The macro just removed the four chances to forget a step.

## Who can do this

| | Private macro | Public macro |
|---|---|---|
| **Agent** | create, edit, delete, run | run only |
| **Administrator** | their own | create, edit, delete, run |

An agent choosing "Public" when they create a macro gets a private one instead — this is enforced on the server,
not just hidden in the interface. Public macros are an account-wide standard, so changing them is an
administrator's call.

The order macros appear in beside a conversation is **yours**: drag them, and your own arrangement is
remembered. It does not change what anyone else sees.

## Limits

- **A macro has no conditions and no branches.** Every action runs every time. If an action should only happen
  sometimes, make two macros.
- **A macro cannot read or change a store order.** There is no commerce action. What it can do is route an order
  question to the people who can open the store — see [Commerce](commerce-overview).
- **A failed action is not reported.** Actions are attempted one at a time, and if one cannot complete the rest
  still run. You will not get an error. Check the conversation afterwards the first few times you run a new
  macro.
- **"Send a message" obeys WhatsApp's rules.** A macro that sends ordinary text on a WhatsApp conversation
  outside the 24-hour window does not deliver that message, although the rest of the macro still runs. See
  [the WhatsApp 24-hour window](the-whatsapp-24-hour-window).
- **Mute does more than mute.** The mute action resolves the conversation *and* blocks the contact. Do not put
  it in a macro your team runs casually.
- If a macro resolves the conversation and your account requires certain conversation attributes before
  resolving, you are asked for them. Dismissing that prompt still runs the macro, but leaves the conversation
  unresolved.
- Messages and notes in a macro are fixed text, with one exception: variables in double braces, such as
  `{{contact.first_name}}`, are filled in when the message is sent, exactly as in a canned response.

## Related

- [Macros or automation?](macros-or-automation)
- [Canned responses](canned-responses)
- [Automation rules](automation-rules)
- [Assign and prioritise](assign-and-prioritise)
- [Labels](labels)

## If it does not work

**The macro is not in the panel.** It is somebody else's private macro, or it has not been created yet.

**Nothing visible happened.** Macros run in the background. Reload the conversation. If it still looks untouched,
one of the actions could not complete — most often assigning an agent who is not a member of that channel, or
adding a label that does not exist in Settings.

**I cannot edit a public macro.** Only administrators can. Ask one, or copy the actions into a private macro of
your own.
