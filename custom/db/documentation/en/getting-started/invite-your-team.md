---
title: Invite your team
description: You will have added the people who answer messages, given each of them the right role, and know what they see when they accept.
position: 30
tags: [getting-started]
seo_description: Add people to Lynomia Chat, choose between administrator, agent and custom roles, and understand what an invitation does.
---
A person who answers customer messages in Lynomia Chat is called an **agent**. Adding someone creates their login,
puts them in your account, and decides — through their **role** — what they are allowed to do once they are in.

Adding a person and giving them a channel are two separate steps. This article covers the first.

## When to do this

Before you connect a channel, not after. Auto-assignment hands a new conversation to an agent who is online and a
member of that channel; if nobody is there yet, messages pile up unassigned.

## What you need first

An administrator account, and the work email address of each person. You do not need their password, and you should
never set one for them — they set their own.

## The roles

| Role | What it covers |
|---|---|
| **Administrator** | everything: settings, channels, people, billing, reports, and every conversation in every channel |
| **Agent** | conversations in the channels they have been added to, and the contacts behind them |
| **A custom role** | a named set of permissions you define yourself |

A custom role is built from a fixed list of permissions, so it is worth knowing what can and cannot be granted:

- manage all conversations
- manage unassigned conversations, and assign them to themselves
- manage conversations they are assigned to or participating in
- manage contacts
- manage reports
- manage help centre portals
- change store order statuses and resend store emails

That last one is the Commerce permission, and it stops short: **refunds and cancellations stay with
administrators** and cannot be granted to a custom role.

A **team** is a different idea from a role. A role is what a person may do; a team is a group you can hand a
conversation to, such as Sales or Deliveries. A person can be in several teams and still have one role.

## Steps

1. Go to **Settings → Agents** and choose **Add agent**.
2. Enter the person's name, pick their role, and enter their email address.
3. Save. The invitation goes out by email.
4. Add them to the channels they should work in. Until you do, an agent sees no conversations at all.

## What the person receives

If the email address is new to Lynomia Chat, they get a message headed *"You are invited to join &lt;your
business&gt;"*, naming you as the person who invited them. The button takes them to a page where they choose a
password. Once they have set it they are signed in, and your business appears in their account.

If the email address already belongs to someone who has a Lynomia Chat login — someone who works in another account
on the same installation — **no invitation email is sent**. They are added immediately and will find your business
waiting the next time they sign in. This surprises people, so tell them you have added them.

## A worked example

A clinic in Riyadh adds three people. The practice manager becomes an **administrator**, so she can connect
WhatsApp and change settings. Two receptionists become **agents**. Both receptionists are then added to the WhatsApp
channel, and both are put in a team called Reception so that a conversation can be handed to the desk rather than to
a named person.

Later the clinic hires a bookkeeper who should see orders but never read patient conversations. That is a custom
role: contacts and reports, nothing else.

## Who can do this

Administrators. Adding, editing and removing people, and creating custom roles, are all administrator jobs. An
administrator can also send a password-reset email to an agent from that agent's own page, which is the right fix
when someone cannot get in.

## Limits

- Role names are fixed at **administrator** and **agent**. Anything in between is a custom role.
- Custom roles are limited to the permissions listed above. Refunds and cancellations are always
  administrator-only.
- Adding a person grants no channel access. An agent must be made a member of each channel. Administrators see
  every channel without being a member.
- If your plan limits how many people you may add, the save is refused with a message about licences rather than
  quietly succeeding.
- An administrator can reset an agent's password by email, but cannot read or choose it.

## Related

- [Connect your first channel](connect-your-first-channel)
- [Roles and permissions](roles-and-permissions)
- [Teams and agents](teams-and-agents)

## If it does not work

**"This email address is already in use."** That address is already in this account. Look for the person in the
agent list rather than adding them again.

**They never got the email.** Check the address for a typo, then check whether they already had a Lynomia Chat
login — in that case there is no email, and they simply sign in. Otherwise ask an administrator to send a password
reset from the agent's page.

**They are in, but see an empty conversation list.** They are not a member of any channel yet. Open the channel and
add them.
