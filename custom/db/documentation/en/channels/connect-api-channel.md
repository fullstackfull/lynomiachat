---
title: Connect your own application
description: The API channel, for a messaging surface Lynomia Chat does not have a connector for — your own app, a kiosk, a chatbot on a platform nobody else supports.
position: 70
tags: [channels, api, developers]
seo_description: The API channel in Lynomia Chat — the inbox identifier, the webhook URL, and when to use it instead of a built-in channel.
---
The API channel is an empty channel with a door on both sides. Your application posts messages into it over
HTTP, and Lynomia Chat posts your agents' replies back to a webhook URL you give it.

Everything else works as usual: the conversation appears in Conversations, it can be assigned, labelled,
automated, reported on and answered from the same screen as every other channel.

## When to use it

- A messaging surface with no connector here — an in-app chat you wrote yourself, a kiosk, a platform nobody
  supports.
- A bridge to a system you already run, where you want the conversation to live in Lynomia Chat.

Do **not** use it for a channel that has its own connector. The built-in channels carry things the API
channel cannot know about: delivery states, templates, the provider's own rules, and a reconnection flow
when authorisation lapses.

## Steps

1. Go to **Settings → Inboxes**, add an inbox, and choose **API**.
2. Give it a name, and a **Webhook URL** — where Lynomia Chat will POST events, including every reply an
   agent sends. You can leave it blank and add it later on the channel's settings.
3. Finish and add agents.
4. Open the channel's **Configuration** tab. It shows the **Inbox Identifier**, which is the token your
   application authenticates with.

From there, your application creates a contact, creates a conversation for it, and posts messages into that
conversation. The API reference for your installation is the authority on the exact calls and their shapes;
this article is about the channel, not the endpoints.

## Limits

- **The inbox identifier is a credential.** Anyone holding it can create contacts and conversations in this
  channel. Keep it on your server, not in a browser or a mobile app.
- **There are no delivery receipts** unless your application reports them.
- **Attachments obey the installation's size limit.**
- **Nothing retries for you.** If your webhook endpoint is down when an agent replies, that delivery fails;
  handling that is your application's job.

## Who can do this

Administrators create the channel. Your developers do the rest.

## Related

- [Connect your first channel](connect-your-first-channel)
- [Webhooks](webhooks)
- [Set up an inbox](set-up-an-inbox)

## If it does not work

**Your application's calls are rejected.** Check you are sending the inbox identifier from this channel's
Configuration tab, and that you are calling the installation this channel belongs to.

**Agents reply and your application never hears.** The webhook URL is wrong, unreachable, or answering
slowly enough to time out. It is on the channel's settings page; a URL that is correct but behind a firewall
looks exactly the same from here.
