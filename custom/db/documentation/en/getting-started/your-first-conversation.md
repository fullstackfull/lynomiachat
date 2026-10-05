---
title: Your first conversation
description: You will have replied to a real customer message, assigned it, labelled it and resolved it — the loop an agent repeats all day.
position: 50
tags: [getting-started]
seo_description: Reply, assign, label and resolve a conversation in Lynomia Chat, and learn what the 24-hour WhatsApp window does to a reply.
---
A **conversation** is one continuous thread with one customer on one channel. It is not a ticket you open and close
once: it has a status, it can be handed between people, and it can be reopened months later when the same customer
writes again.

Almost everything an agent does is four moves on that thread — **reply, assign, label, resolve**. Learn those and
the rest of Lynomia Chat is detail.

## What you need first

A connected channel and an account that is a member of it. If **Conversations** is empty and you are an agent, you
have probably not been added to any channel yet — see [Invite your team](invite-your-team).

## The four statuses

A conversation is always in exactly one of these, and the list you are looking at is filtered by them.

| Status | What it means |
|---|---|
| **Open** | live, needs someone |
| **Pending** | waiting on you, deliberately parked |
| **Snoozed** | hidden until a time you chose, or until the customer replies |
| **Resolved** | done — until the customer writes again, which reopens it |

Alongside the status filter you can narrow by assignment: **Mine**, **Unassigned**, or **All**. Most agents live in
Mine, and look at Unassigned when they have capacity.

## A message arrives

When a customer writes, a conversation appears in the channel's inbox. If auto-assignment is on for that channel,
Lynomia Chat gives it to a member who is **online** at that moment. If nobody is online, it stays unassigned and
waits — it is not lost, but nobody owns it.

## Reply

The composer has two modes, and the difference matters.

- **Reply** goes to the customer.
- **Private Note** is visible only to your colleagues. Use it for what you would otherwise say in a side chat:
  context, a warning, a decision.

Two shortcuts that pay for themselves:

- Type `/` at the start of a reply to pick a saved **canned response**. This works in a reply, not in a private
  note.
- Type `@` in a private note to mention a colleague or a team, which notifies them.

`Shift + Enter` gives you a new line instead of sending.

## Assign

Assignment answers "whose job is this". In the conversation's side panel you can set:

- an **agent** — the one person responsible, or yourself with the self-assign button
- a **team** — a group such as Sales or Deliveries, when the right person is not yet known
- a **priority** — low, medium, high or urgent

Assigning does not reply for you. An assigned conversation with no answer is still an unanswered conversation.

## Label

A **label** is a word you put on a conversation so you can find it later and report on it: `complaint`,
`wrong-size`, `vip`. Press `L` or use the add-label control in the side panel.

Agents choose from the labels that already exist. **Only an administrator can create a new one** from here, which
is deliberate — it stops the same idea being spelled five ways by five people.

## Resolve

Resolving says you are finished. Use the **Resolve** button in the conversation header. If the customer writes
again, the conversation reopens with its history intact, so resolving is never destructive.

Two neighbours of Resolve:

- **Snooze** parks it and brings it back — in an hour, tomorrow, next week, next month, at a time you pick, or as
  soon as the customer replies.
- **Reopen** brings a resolved or snoozed conversation back to open.

If your account has been set up to require certain fields before resolving, you will be asked for them at this
point rather than afterwards.

## A worked example

A customer messages a WhatsApp number: *"The sofa arrived with a scratch."* It arrives unassigned; Noura is online,
so it lands with her.

She replies with a canned response apologising and asking for a photo. She adds the label `damage-claim`, sets the
priority to **high**, and leaves a private note: *"Delivered 3 Oct, driver route 7."* The photo arrives. She
assigns the conversation to the Deliveries team, who arrange a replacement and **resolve** it. Three weeks later the
same customer asks about a dining table — the conversation reopens, with the whole scratch story above it.

## Who can do this

Any agent, in the channels they are a member of. Creating labels, and changing what the channel does
automatically, are administrator jobs.

## Limits

- **WhatsApp only lets you reply freely for 24 hours** after the customer's last message. After that, a plain reply
  is not delivered — it is marked as failed, and the error says the window is closed and an approved template is
  required. The composer will still let you type it. See
  [The WhatsApp 24-hour window](the-whatsapp-24-hour-window).
- Auto-assignment considers only members who are online, so a quiet shift produces a queue of unassigned
  conversations rather than assigned ones.
- Agents cannot create labels, only apply them.
- Resolving is not archiving. A new message from the same contact reopens the same conversation.
- A private note is private to your team, not to you. Every agent on the conversation can read it.

## Related

- [Work in the inbox](work-in-the-inbox)
- [Labels](labels)
- [Macros](macros)
- [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)
- [Troubleshooting](troubleshooting)

## If it does not work

**Your reply shows as failed on WhatsApp.** Check the time of the customer's last message. More than 24 hours ago
means you need an approved template, not a reply.

**The composer tells you that you can only reply with a template.** Same cause, stated before you send.

**You cannot find a label you need.** It does not exist yet. Ask an administrator to create it rather than
inventing a near-duplicate.

**Nothing is assigned to anyone.** No member of that channel was online. Set yourself online, or assign by hand
from the Unassigned list.
