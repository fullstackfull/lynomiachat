---
title: Work in the inbox
description: How the conversation list is organised, what each status means, and how to leave notes your customer never sees.
position: 10
tags: [conversations]
seo_description: The conversation list, the four statuses, folders, private notes and mentions in Lynomia Chat.
---
Every message your business receives lands in one list. The list is not a feed you scroll until you find
something — it is a queue you narrow until only your work is left.

## The four states a conversation can be in

A conversation always has exactly one status. Changing it is how your team signals what happens next.

| Status | What it means | What reopens it |
|---|---|---|
| **Open** | Somebody still has to deal with this | — |
| **Pending** | A bot is handling it, or it is parked for one | A human reply, or the bot handing it over |
| **Snoozed** | Deliberately out of the way until a moment you chose | The time you set, or the customer writing again |
| **Resolved** | Finished | The customer writing again |

Two things about this are worth knowing before you rely on them.

**Resolved is not closed.** When a customer replies to a resolved conversation, it comes back as open and
rejoins the queue. On a channel with a bot attached, it comes back as pending instead, so the bot gets first
look.

**Snooze has two shapes.** "Until tomorrow", "until next week" and a date you pick all set a time, and the
conversation returns to open on its own at that time. "Until next reply" sets no time at all — nothing but a new
message from the customer will bring it back. If you snooze a conversation until next reply and the customer
never writes, it stays snoozed indefinitely.

## Narrowing the list

Three controls stack on top of each other, and they are independent:

- **Mine / Unassigned / All** — who the conversation is assigned to.
- **Status** — open, pending, snoozed, resolved, or all of them.
- **Sort** — last activity, created date, priority, longest waiting, or unread count.

The sidebar adds views that are not filters you build:

| View | What is in it |
|---|---|
| **Mentions** | conversations where somebody wrote your name in a private note |
| **Participating** | conversations you have taken part in, even if you are not the assignee |
| **Unattended** | conversations nobody has ever replied to, plus conversations with a customer message still unanswered |
| **Teams**, **channels**, **labels** | everything belonging to one team, one of your channels, or one label |

A private note does **not** count as answering. A conversation you have only made notes on stays in Unattended.

## Folders: a filter you saved

When a set of filters is one you will use again — "open, urgent, on the WhatsApp channel, unassigned" — save it
as a folder. It appears in the sidebar under **Folders** with its own unread count.

A conversation folder is **yours alone**. There is no way to share one with the team, and nobody else will see
it. If a whole team needs to work the same queue, give them a team or a label instead, because those are
account-wide. (Contact audiences *can* be shared; conversation folders cannot. See
[shared audiences](shared-audiences).)

## Private notes

Switch the composer to **Private Note** and what you write is stored on the conversation and shown only to your
colleagues. It is never delivered to the customer, on any channel.

Use it for the handover sentence the next person needs: what you already tried, what the customer actually wants,
what you promised. Do not use it for anything you would not want a colleague to read — every agent who can open
the conversation can read every note on it.

Two things are switched off inside a private note: [canned responses](canned-responses) and message variables.
Both exist to compose a message to a customer, and a note is not one.

## Mentioning a colleague

Type `@` inside a private note and pick a person or a team. The people you mention get a notification, the
conversation appears in their **Mentions** view, and they are added as participants so they keep getting updates.
Mentioning a team notifies every member of it.

**A mention only works inside a private note.** Typing `@name` in a normal reply sends the text to the customer
and notifies nobody.

You can only mention someone who is a member of that channel, or an administrator. A name outside that list is
ignored, silently — so if a colleague never answered, check they are on the channel first.

## A worked example

A customer asks about a delayed order on Thursday afternoon. You cannot answer until the warehouse replies on
Sunday.

1. Add a private note: "Chased warehouse re order 10482, waiting on them."
2. Mention the person who owns warehouse questions, so it reaches them.
3. Snooze the conversation until next week.

On Monday morning it is back in the open queue, with the note explaining itself. If the customer writes again
before then, it reopens immediately and you see it on Friday.

## Who can do this

Any **agent** can read, reply, note, mention and change the status of any conversation on a channel they are
a member of, or assigned to a team they belong to. An administrator sees everything. A custom role can narrow
this to unassigned conversations only, or to conversations the person is participating in — see
[roles and permissions](roles-and-permissions).

## Limits

- **Selecting conversations in bulk covers only the page in front of you.** Scroll and the earlier selection is
  not extended. Bulk actions reach status, snooze, agent, team and labels — not priority.
- A folder's conditions are limited to conversation facts: status, assignee, priority, channel, team, contact,
  campaign, labels, browser language, referrer, dates and your own custom attributes. You cannot filter a
  conversation folder by what the contact bought.
- **Mute does more than mute.** Muting a conversation resolves it *and* blocks the contact, so nothing further
  from that person opens a conversation. Use it for abuse, not for a noisy thread.

## Related

- [Assign and prioritise](assign-and-prioritise)
- [Labels](labels)
- [Canned responses](canned-responses)
- [Macros](macros)
- [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)

## If it does not work

**The conversation is not in my list.** Check the three filters first — the status filter is the usual culprit,
because a resolved conversation disappears from an open-only list. Then check you are a member of that channel.

**I cannot type a reply, only send a template.** That is the WhatsApp 24-hour window, not a permission problem.
[The WhatsApp 24-hour window](the-whatsapp-24-hour-window) explains it.

**A snoozed conversation never came back.** It was snoozed until next reply, and the customer has not replied.
Open it from the snoozed list and change the status by hand.
