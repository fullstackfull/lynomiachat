---
title: Connect your first channel
description: You will understand what a channel is, which ones Lynomia Chat supports, and why most businesses start with WhatsApp.
position: 40
tags: [getting-started]
seo_description: What a channel is in Lynomia Chat, the full list of channels you can connect, and how to connect WhatsApp first.
---
A **channel** is one way customers reach you — one WhatsApp number, one website widget, one mailbox. In the
dashboard a channel appears as an **inbox**: the two words describe the same thing from different sides. The channel
is the connection to the outside world; the inbox is where its conversations land.

Everything else depends on having at least one. Contacts are created by the messages that arrive through a channel,
automation reacts to them, and campaigns go out through them. Until a channel exists, the dashboard has nothing to
show you.

## Which channels you can connect

| Channel | What it connects |
|---|---|
| WhatsApp | a WhatsApp Business number |
| Website | a live-chat widget on your own site |
| Email | a mailbox, so replies arrive as conversations |
| SMS | text messages through Twilio or Bandwidth |
| Telegram | a Telegram bot |
| Line | a Line account |
| Facebook | a Facebook page's Messenger inbox |
| Instagram | an Instagram account's direct messages |
| API | your own application, through Lynomia Chat's API |

Some of these depend on how your installation is configured, and you will see them greyed out rather than hidden.
Facebook and Instagram need a Meta app set up on the installation itself. TikTok appears only where it has been
configured. Voice and WhatsApp calling are marked beta and depend on being switched on for your account. If a
channel you want is not selectable, that is an installation-level setting, not something you can change from your
account.

## Why WhatsApp first

In the Gulf, WhatsApp is usually not one channel among several — it is where the customers already are. It is also
the channel with the most rules, which is the real reason to connect it early: the sooner you have a number
connected, the sooner you find out what Meta will and will not let you send.

The one rule that shapes everything else: once a customer messages you, you can reply freely for **24 hours**.
After that, a plain message will not go out. You may only send an **approved template**. See
[The WhatsApp 24-hour window](the-whatsapp-24-hour-window).

## What you need first

An administrator account. For WhatsApp you also need a phone number that is not already in use on personal
WhatsApp, and access to the Meta Business account that owns it — or, if you are connecting through Twilio, your
Twilio credentials.

## Steps

1. Go to **Settings → Inboxes** and choose to add an inbox.
2. Pick the channel. For WhatsApp, pick your provider next:

   | Provider | Use it when |
   |---|---|
   | WhatsApp Cloud — quick setup through Meta | you are connecting a number through Meta and want the connection configured for you |
   | WhatsApp Cloud — manual setup | the number is already on the WhatsApp Cloud API and you hold its credentials |
   | WhatsApp Business | the number is live in the WhatsApp Business app on a phone and you want to keep using it there |
   | Twilio | WhatsApp is already running through your Twilio account |

3. Complete the provider's own step. Quick setup sends you to Meta to sign in and choose the number. Manual setup
   asks for the phone number, its phone number ID, the business account ID, an API key and a webhook verify token.
4. Choose which agents work in this channel. An agent who is not a member sees nothing from it. Administrators see
   every channel without being added.
5. Finish. For WhatsApp you are shown a QR code — scan it with your own phone to send the channel a test message
   and watch it arrive.

## A worked example

A perfume shop in Dubai connects its WhatsApp number using quick setup through Meta, adds its two sales staff as
members, and finishes. It scans the QR code, sends "hello" from a personal phone, and the conversation appears in
Conversations within seconds, unassigned. One of the two staff is online, so auto-assignment hands it to her.

Only then does the shop set the channel's business hours, because a new channel is created on **UTC** time, and
Dubai is four hours ahead.

## Who can do this

Administrators. Agents cannot see the Inboxes settings at all, let alone connect a channel.

## Limits

- A new channel's timezone is **UTC** until you change it. Business hours and out-of-office replies will be wrong
  by your local offset until you do.
- Auto-assignment is on for a new channel and only considers members who are **online**. If nobody is online,
  conversations wait, unassigned.
- WhatsApp templates belong to the WhatsApp number, not to Lynomia Chat. Only Meta can approve one, and it can
  reject one.
- Quick setup through Meta is not available on every account, and Meta occasionally restricts it at their end. When
  that happens, the manual Cloud API route is still open for a number already on the Cloud API.

## Related

- [Connect WhatsApp](connect-whatsapp)
- [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)
- [WhatsApp Business coexistence](whatsapp-business-coexistence)
- [Set up an inbox](set-up-an-inbox)
- [Your first conversation](your-first-conversation)

## If it does not work

**The channel you want is greyed out.** It needs configuration on the installation, not in your account. Ask your
provider.

**Meta's setup window closed without a number.** Run quick setup again and add a phone number to the WhatsApp
Business account during the Meta steps. A setup that finishes without one cannot produce a channel.

**Your test message never arrived.** Confirm you messaged the connected number from a different phone, and that
setup reached the final step rather than stopping at the agent step.

**Nothing you send goes out.** Check whether the last incoming message is more than 24 hours old. On WhatsApp that
is the window, not a fault.
