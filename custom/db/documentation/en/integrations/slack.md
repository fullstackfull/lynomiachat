---
title: Slack
description: You will have every incoming conversation appearing as a thread in one Slack channel, you will have decided whether replies typed there reach the customer, and you will know whose name those replies carry.
position: 30
tags: [integrations, slack]
seo_description: "Connect Slack to Lynomia Chat: one channel, one thread per conversation, two-way sync versus alerts only, note: for private notes, and how agent identity is matched."
---
The Slack integration mirrors your conversations into **one Slack channel**. Each conversation becomes a
thread, and every message in it — incoming, outgoing, private notes and activity lines — is posted into that
thread as it happens.

What makes it worth a decision rather than a click is the **thread behaviour** setting. In one mode a reply
typed in the Slack thread is sent to the customer. In the other it never leaves Slack. Choosing wrong is how a
manager's aside reaches a customer.

## When to use it

When the people who need to see customer messages already live in Slack and will not open a second tool —
an operations team, a shift manager, a founder. It is also the cheapest way to give somebody visibility without
giving them an account.

## When not to use it

- **As your team's main inbox.** Assignment, labels, priorities, macros, canned responses, templates and
  reports exist in [the inbox](work-in-the-inbox) and not in Slack. A thread is a copy, not a workspace.
- **To route conversations to different teams.** There is **one** channel for the whole account. You cannot
  send the sales inbox to `#sales` and support to `#support`.
- **For WhatsApp beyond the 24-hour window.** A reply typed in Slack is an ordinary message. If
  [the window](the-whatsapp-24-hour-window) has shut, it will not be delivered, and Slack is not where you will
  notice.

## What you need first

- An **administrator** account.
- Your installation must have Slack credentials configured. If it does not, Slack is simply absent from
  **Settings → Integrations** — see [integrations](integrations).
- Permission to install a Slack app in your workspace.
- **If you want a private channel, add the app to that channel in Slack first.** The connect step joins public
  channels for you; it cannot join a private one it has not been invited to.

## Steps

1. Go to **Settings → Integrations → Slack** and start the connection. Slack asks you to authorise the app for
   your workspace.
2. You come back with the workspace linked and the integration **inactive**. This is expected: a workspace is
   not a destination.
3. Choose **Connect channel** and pick the channel from the list. Public and private channels are both listed;
   archived channels are not.
4. Choose the **Slack thread behaviour**. You can change this later without reconnecting.

A public channel is joined automatically when you pick it. The integration becomes active at that point, not
before.

## The two modes

| | **Two-way sync** | **Alerts only** |
|---|---|---|
| Conversations posted to the channel | yes | yes |
| A reply typed in the thread | **sent to the customer** | stays in Slack, always |
| `note:` prefix needed to stay internal | yes | no — nothing escapes |
| What the thread is for | answering | discussing |

Pick **Alerts only** whenever the people in that channel are not the people who answer customers. It is the
safe default for a visibility channel, and it is the only configuration in which a careless message in the
thread cannot reach a customer.

Pick **Two-way sync** only if those people *are* your agents and understand that the thread is a reply box.

## Replying from Slack

In two-way sync:

- **Reply in the thread**, not in the channel. A new channel message is not attached to any conversation and is
  ignored. Only replies inside a conversation's thread are read.
- **Start the message with `note:` or `private:`** to make it a private note instead of a reply to the
  customer. The prefix is checked at the start of the message, case-insensitively.
- **Files** posted in the thread are picked up; edits, reactions, joins and other Slack message subtypes are
  not.
- **Messages posted by apps and bots are ignored**, which is what stops a Slack workflow from answering your
  customers.

## Whose name the reply carries

This is worth getting right before you switch two-way sync on.

| The Slack author | How the customer sees it |
|---|---|
| Has a Lynomia Chat profile **with the same email address** | as that agent |
| Does not | as the integration's own bot profile, carrying their Slack display name and avatar inside Lynomia Chat |

So a person replying from Slack under a different email is not impersonating anyone, but the customer does not
see a named agent either. If you want attribution, match the email addresses.

## What a thread looks like

The first post for a conversation carries the context you need to act: the **inbox name and type**, a **link to
the conversation** in Lynomia Chat, and — on an email inbox — the subject line. Later posts in the thread are
just the message.

Two formatting details, because they are easy to misread:

- A **private note** appears in the thread prefixed `private:`.
- An **activity line** — an assignment, a status change — appears in italics.

## A worked example

A Kuwait retailer wants its operations team watching WhatsApp without replying by accident. An administrator
connects Slack, picks `#support-watch`, and sets the behaviour to **Alerts only**.

Conversations now arrive in that channel as threads. The shift manager reads them and discusses a difficult one
in the thread; the customer sees none of it. When a decision is made, the manager opens the conversation from
the link in the thread and the agent answers in [the inbox](work-in-the-inbox). Replies and notes made there
keep appearing in the Slack thread, so the channel stays current.

## Who can do this

Administrators only. The custom role permission list has no entry for integrations, so this cannot be
delegated — see [roles and permissions](roles-and-permissions).

## Limits

- **One Slack connection per account, and one channel.** To change channel, update the selection; to change
  workspace, delete the integration and connect again.
- **An agent's reply does not start a thread.** A thread exists once the conversation has been posted; a
  conversation that has never had an incoming message has nothing to attach to.
- **Only thread replies are read.** Channel-level messages are ignored.
- **No reactions, no edits, no deletions.** Editing a Slack message does not edit the customer's copy, and
  deleting it does not unsend anything.
- **No per-inbox routing and no filtering.** Every conversation in the account goes to the channel.
- **Deleting the integration removes the link, not the history.** The threads stay in Slack; they simply stop
  updating.
- **The connection can expire.** When it does, the integration shows that attention is required and the fix is
  to delete it and connect the workspace again — there is no silent re-authorisation.
- **Tweets are excluded** on a connected Twitter profile; everything else is posted.

## Related

- [Integrations](integrations) · [Webhooks](webhooks) · [Dashboard apps](dashboard-apps)
- [Work in the inbox](work-in-the-inbox)
- [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)
- [Roles and permissions](roles-and-permissions)

## If it does not work

**Slack is not listed under Integrations.** Your installation has no Slack credentials configured. Nothing in
your account turns this on.

**The integration says it is inactive.** You linked the workspace but have not picked a channel. Choose
**Connect channel**.

**My private channel is not in the list, or picking it does nothing.** Add the app to that channel in Slack
first, then try again. A private channel cannot be joined for you.

**Conversations arrive but my replies do not reach the customer.** Either the behaviour is set to **Alerts
only**, or you replied in the channel instead of inside the thread, or your message began with `note:`.

**My replies reach the customer as a bot.** Your Slack account's email does not match a Lynomia Chat profile.

**Fetching channels failed.** Try again — a large workspace is paged through in several requests, and a
transient Slack error fails the whole fetch rather than half of it.

**It stopped working after a while.** Look for the expiry notice on the Slack page. Delete the integration and
connect the workspace again.
