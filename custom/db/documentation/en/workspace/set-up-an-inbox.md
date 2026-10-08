---
title: Set up an inbox
description: You will understand what an inbox holds, which settings belong to it rather than to your account, and how its business hours and greeting behave.
position: 10
tags: [workspace, inboxes]
seo_description: What an inbox is in Lynomia Chat, the settings each one carries, and how business hours and the greeting message actually work.
---
An **inbox** is one channel plus everything that governs it: who works in it, when you are open, what a first-time
customer is told, and whether satisfaction is asked for. The channel is the connection to the outside world; the
inbox is the set of decisions you make about it.

This matters because most of the settings people look for in account settings are not there. They are per inbox. Two
WhatsApp numbers can keep different hours, different greetings and different staff.

## The channels you can connect

Nine are always offered: **Website** (a live-chat widget), **WhatsApp**, **Email**, **SMS** (through Twilio or
Bandwidth), **Facebook**, **Instagram**, **Telegram**, **Line** and **API** for your own application. **TikTok**
appears only where it has been configured on the installation, and **Voice** and **WhatsApp calling** depend on being
switched on for your account. Connecting the channel itself is covered in
[Connect your first channel](connect-your-first-channel).

## What you need first

An administrator account, and a connected channel. An inbox cannot exist without one.

## The settings each inbox carries

Open **Settings → Inboxes**, pick the inbox, and work through its tabs.

| Tab | What it decides |
|---|---|
| **Settings** | name, logo, greeting message, and channel-specific options |
| **Collaborators** | which agents work here, and whether auto-assignment is on |
| **Business Hours** | your timezone, your weekly schedule, and the reply sent when you are closed |
| **CSAT** | whether a satisfaction survey is sent when a conversation is resolved |

Other tabs appear only where they apply: **Pre Chat Form** for a website widget, **Configuration** for channels that
hold credentials, **Bot Configuration** where agent bots are enabled, **Account Health** for WhatsApp and Twilio, and
**Voice** or **Calls** where calling is switched on.

## Business hours

Business hours are **off** by default, and a new inbox is created on **UTC** time. The default schedule is Monday to
Friday, 09:00 to 17:00, with Saturday and Sunday closed — which is wrong for most of the Gulf, where the working week
usually runs Sunday to Thursday. Set the timezone and the days before you switch the feature on.

When business hours are on and you are currently closed, an incoming message gets your unavailable message. It is
sent at most **once a day** in any one conversation, and it is not sent if an agent sent a public reply in the last
five minutes, so a conversation that is still live at closing time is not interrupted.

Business hours drive that one automatic reply and the hours shown on a website widget. They are **not** available
anywhere else. There is no business-hours or time-of-day condition in [automation rules](automation-rules), so
out-of-hours routing cannot be built.

## The greeting

The greeting is also **off** by default. When it is on, it is sent once — on the contact's first message in a
conversation — and never on a conversation created by a [campaign](whatsapp-campaigns). Out of hours you get the
unavailable message instead of the greeting, not both.

## A worked example

A clinic in Kuwait runs one WhatsApp inbox. It sets the timezone to Asia/Kuwait, opens Sunday to Thursday 08:00 to
20:00, and closes Friday and Saturday. The unavailable message says the clinic is closed and will answer the next
working morning. The greeting is left off: the unavailable message already covers the case that matters, and a
greeting on every first message would only add noise during opening hours.

## Who can do this

Administrators only. Agents cannot open inbox settings. The permission list behind a custom role has no entry for
inboxes or channels, so this cannot be delegated — see [Roles and permissions](roles-and-permissions).

## Limits

- A new inbox is on **UTC** until you change it, and business hours are evaluated in the inbox's timezone.
- **Closing time must be later than opening time on the same day.** Hours that run past midnight cannot be
  expressed.
- "All day" means 00:00 to 23:59, not a true 24 hours.
- The unavailable message goes out on **every channel**, not only the website widget, even though its help text
  mentions live chat.
- Greeting and unavailable messages are capped at 10,000 characters each.
- CSAT on WhatsApp needs a template approved by Meta before it can be sent.
- Auto-assignment is on for a new inbox and only considers agents who are **online**.

## Related

- [Connect your first channel](connect-your-first-channel)
- [Connect WhatsApp](connect-whatsapp)
- [Teams and agents](teams-and-agents)
- [Assign and prioritise](assign-and-prioritise)

## If it does not work

**The unavailable message is sent at the wrong time.** The inbox timezone is still UTC, or the schedule follows a
Monday-to-Friday week it should not.

**Nobody is getting the unavailable message.** Check that business hours are switched on, that today is marked
closed, and that the message field is not empty. All three are required.

**The greeting never arrives.** It is sent only on the contact's first message in a conversation. On an existing
conversation, or out of hours, it does not send.

**An agent cannot see the inbox's conversations.** They are not a collaborator. Add them on the Collaborators tab.
