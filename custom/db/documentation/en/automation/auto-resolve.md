---
title: Auto-resolve conversations
description: You will have a rule that closes conversations nobody has touched for a while, you will know exactly what "a while" is measured from, and you will know which conversations it will never close.
position: 50
tags: [automation, conversations]
seo_description: "Auto-resolve in Lynomia Chat: the inactivity clock, the optional closing message and label, and why pending and snoozed conversations are never closed."
---
Auto-resolve is one account-wide rule: **a conversation nobody has touched for a set period is marked resolved
by the system.** It exists because open conversations accumulate. Someone asks a question, is answered, and
never writes again — and the conversation sits open forever, inflating every count your team works from.

It is in **Settings → Automation → Conversation Workflow**, as a block with its own switch. It appears there
only when auto-resolve is enabled for your account; on an account without it, the page shows the other
conversation-workflow settings and no auto-resolve block at all.

## When to use it

When your open count is no longer a to-do list. If a third of the conversations marked open are finished
exchanges nobody will return to, your team cannot tell real work from residue, and no amount of discipline
fixes that by hand.

## When not to use it

- **To chase a reply.** Auto-resolve closes a conversation; it does not nudge anybody. If you want a customer
  prompted after silence, that is a [flow](flow-builder) or an
  [automation rule](automation-rules), not this.
- **As a per-inbox rule.** There is exactly one setting for the whole account. You cannot auto-resolve the
  sales inbox after two days and the support inbox after two weeks.
- **To hide a backlog.** A resolved conversation is still in the account, still searchable, and still counted in
  [reports](work-in-the-inbox). Closing it changes what your team sees, not what happened.

## What you need first

An **administrator** account. Conversation Workflow is administrator-only, and the custom role permission list
has no entry for it, so it cannot be delegated — see [roles and permissions](roles-and-permissions).

**Auto-resolve enabled for your account.** It is a capability your installation switches on, not something you
turn on yourself. If the block is absent, that is the reason.

If you want the optional label, **create the label first**. The picker offers only labels that already exist —
see [labels](labels).

## Steps

1. Go to **Settings → Automation → Conversation Workflow** and find **Auto-resolve conversations**.
2. Turn the switch on.
3. Set **Inactivity duration**. The unit selector offers minutes, hours and days, and the value is stored in
   minutes either way. The accepted range is **10 minutes to 999 days**; the form refuses anything shorter than
   10 minutes.
4. Optionally write a **custom auto-resolution message**. This is sent to the customer when the conversation is
   closed. Leave it empty and nothing is sent.
5. Optionally turn on **Skip conversations waiting for agent's reply**, and optionally pick a label to apply.
6. **Save Changes.**

Turning the switch off clears the duration, the message, the skip preference and the label. It is an off switch,
not a pause.

## What "inactivity" is measured from

This is the part that surprises people. The clock is the conversation's **last activity**, and *every* message
written into the conversation resets it — including the ones your customer never sees:

| Written into the conversation | Resets the clock |
|---|---|
| An incoming customer message | yes |
| An outgoing reply | yes |
| A **private note** | yes |
| An activity line, such as an assignment or a status change | yes |

So a conversation an agent keeps adding notes to is never idle, however long the customer has been silent. If
you want a clock that measures only the customer, auto-resolve is not it.

## Which conversations it will never close

| Conversation | Closed? |
|---|---|
| **Open**, idle longer than the duration | yes |
| **Pending** — waiting on a bot | no |
| **Snoozed** | no |
| Already **resolved** | no |
| **Open** and idle, but the customer is waiting for a reply | only if **Skip conversations waiting for agent's reply** is off |
| A conversation whose contact has been deleted | no |

"The customer is waiting" has a precise meaning here: it is set when a customer message arrives and nothing has
answered yet, and it is cleared by the first non-private reply — a bot reply clears it too. With the skip
preference on, those conversations are left open no matter how old they are, which is usually what you want:
auto-resolving an unanswered question is worse than leaving it open.

## The closing message, and when it is not sent

If you wrote one, it is sent as the conversation closes, and it appears in the conversation as a template
message rather than as an agent's reply.

It is subject to the channel's own sending rules. On WhatsApp, a free-form message cannot be sent once
[the 24-hour window](the-whatsapp-24-hour-window) has shut — which, for a conversation idle for days, is
precisely the normal case. When that happens the message is **not** sent, nothing fails, and the conversation
gets an activity line reading *Auto-resolve message not sent due to outgoing message restrictions*. The
conversation is still resolved.

So on a WhatsApp-only account, expect the closing message to be the exception rather than the rule. If
customers must hear from you at closing time, that is an approved [template](whatsapp-templates), sent
deliberately — not this field.

## What the customer and your team see

The conversation gets an activity line naming the reason and the duration, in the form *Conversation was marked
resolved by system due to 15 days of inactivity*. The unit in that line follows the duration you set: days when
it divides into whole days, otherwise hours, otherwise minutes.

Your chosen label, if any, is added to the conversation at the same time.

## It is not final

**A new incoming message reopens the conversation.** A customer who writes back lands in the same conversation,
not a new one: it goes back to open, or to pending if that inbox has an active bot. Auto-resolve tidies the
list; it does not end the relationship.

## How often it runs

A scheduled job looks for resolvable conversations **every five minutes**, across every account that has the
setting on. Two consequences worth knowing:

- A conversation is not closed the instant it crosses the threshold. Expect up to a few minutes of lag.
- Each run closes at most **100 conversations per account**. The first run after you switch this on will not
  clear a backlog of thousands; it will work through it over successive runs.

## A worked example

A Kuwait retailer has 4,000 open conversations and about 300 real ones. On **Settings → Automation →
Conversation Workflow** the administrator sets the duration to **14 days**, turns **Skip conversations waiting for agent's reply** on, leaves the message empty, and picks the
label `auto-closed`.

Over the next hours the open count falls in steps of 100 per five minutes. Nothing is sent to any customer.
Unanswered questions stay open, because of the skip preference, which is how the team finds the ones they
actually dropped. A customer writing back next week reopens their own conversation, and the `auto-closed` label
on it says plainly why it had been closed.

## Who can do this

Administrators only.

## Limits

- **One rule per account.** Not per inbox, not per team, not per label.
- **The minimum is 10 minutes** and the maximum is 999 days.
- **Private notes and activity lines count as activity**, so an internally busy conversation never ages.
- **Pending and snoozed conversations are never auto-resolved**, so a conversation parked with a bot or snoozed
  to next month is not touched.
- **At most 100 conversations per account per run.**
- **The closing message is not retried.** If the channel refuses it, it is dropped and an activity line records
  that.
- **There is no preview and no dry run.** You cannot ask how many conversations the current duration would
  close before saving it.
- **There is no record of the old value.** Changing the duration is a settings change, and
  [audit logs](audit-logs) record that the account settings were updated, not what the number used to be.

## Related

- [Work in the inbox](work-in-the-inbox) · [Assign and prioritise](assign-and-prioritise)
- [Labels](labels)
- [Automation rules](automation-rules) · [Flow builder](flow-builder)
- [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)
- [Audit logs](audit-logs)

## If it does not work

**Nothing is being resolved.** Check the switch is on and saved, then check the conversations you expect to
close are actually **open** — pending and snoozed are excluded. Then check whether **Skip conversations waiting
for agent's reply** is on and those conversations are unanswered, which is the most common reason.

**It resolved something an agent was working on.** The agent had not written in it for longer than the
duration. Private notes count as activity, so the usual cause is a longer gap than anyone realised. Lengthen
the duration.

**The closing message never arrives.** On WhatsApp it almost never can: the 24-hour window has closed by the
time a conversation is idle enough to qualify. Look for the activity line saying so.

**The count is falling too slowly.** That is the 100-per-run cap, not a fault. It clears at roughly 100 every
five minutes.

**Auto-resolve conversations is not on the page.** Either auto-resolve is not enabled for your account — the
most likely reason, and nothing in your account changes it — or you are not an administrator. Conversation
Workflow is administrator-only.
