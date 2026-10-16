---
title: Connect Telegram
description: Turn a Telegram bot into a support channel in about two minutes — the shortest setup of any channel.
position: 40
tags: [channels, telegram]
seo_description: Connecting a Telegram bot to Lynomia Chat with BotFather, and what the Telegram channel can and cannot do.
---
Telegram connects through a **bot**. You create the bot in Telegram itself, paste its token into Lynomia
Chat, and anyone who messages that bot appears in Conversations.

It is the quickest channel to connect: one field, no review, no business verification, no provider account.

## What you need

A Telegram bot token, which you get from **BotFather** — Telegram's own bot for making bots.

1. In Telegram, open a chat with `@BotFather`.
2. Send `/newbot`.
3. Give it a display name and a username ending in `bot`.
4. BotFather replies with a token that looks like `123456789:AAH...`. That is what you paste.

The display name and the profile picture your customers see belong to the bot, and you change them in
BotFather — not in Lynomia Chat.

## Steps

1. Go to **Settings → Inboxes**, add an inbox, and choose **Telegram**.
2. Paste the **Bot Token**.
3. Add the agents who will work in this channel, and finish.

Lynomia Chat registers itself with Telegram as the bot's webhook, so messages start arriving immediately.
Send your bot a message from your own Telegram account to watch it land.

## Limits

- **A bot cannot start a conversation.** Telegram only lets a bot message someone who has messaged it
  first. There is no way to open a Telegram conversation from the dashboard, and no Telegram campaigns.
- **One token, one channel.** The same bot cannot be connected twice, and connecting it elsewhere takes the
  webhook away from here — Telegram allows a bot only one webhook at a time.
- **The bot's name and avatar come from BotFather**, so the inbox name you choose is for your dashboard.
- **Groups behave differently from one-to-one chats.** A bot added to a group sees only messages addressed
  to it unless its privacy mode is changed in BotFather.

## Who can do this

Administrators.

## Related

- [Connect your first channel](connect-your-first-channel)
- [Set up an inbox](set-up-an-inbox)

## If it does not work

**Messages do not arrive.** The usual cause is the same bot being connected somewhere else: Telegram keeps
one webhook per bot, so the most recent registration wins. Reconnect the channel here and check nothing else
is using the token.

**The token is refused.** Copy it again from BotFather — the token is the whole string including the number
before the colon, and a copy that drops it is the most common mistake.
