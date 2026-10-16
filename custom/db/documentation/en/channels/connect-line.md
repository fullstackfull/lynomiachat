---
title: Connect LINE
description: Connect a LINE Official Account so its messages arrive in your inbox with the rest.
position: 50
tags: [channels, line]
seo_description: Connecting a LINE Official Account to Lynomia Chat — channel ID, secret, access token and the webhook URL.
---
LINE is the main messenger in Japan, Thailand and Taiwan. If you sell into those markets, a LINE Official
Account is usually where your customers already are.

The channel connects to a LINE **Messaging API channel**, which you create in the LINE Developers Console
and attach to your Official Account.

## What you need

From the LINE Developers Console, on your Messaging API channel:

- the **Channel ID**
- the **Channel Secret**
- a **Channel Access Token** (long-lived)

## Steps

1. Go to **Settings → Inboxes**, add an inbox, and choose **LINE**.
2. Enter a channel name for your own dashboard, then the Channel ID, Channel Secret and Channel Access
   Token.
3. Finish. Open the channel's **Configuration** tab and copy the **Callback URL**.
4. In the LINE Developers Console, set that URL as the channel's **Webhook URL** and switch "Use webhook"
   on.
5. In the same console, switch **off** the auto-reply and greeting messages if you want your agents to be
   the ones replying. LINE answers on the account's behalf by default, and those replies do not come from
   Lynomia Chat.

## Limits

- **A LINE channel cannot start a conversation** with someone who has not added the Official Account.
- **LINE's own auto-replies are configured in LINE**, not here, and they will talk over your agents until
  you turn them off.
- **Rich message types** — stickers, location, LINE-specific templates — arrive as what LINE sends; an agent
  replies with text and attachments.

## Who can do this

Administrators.

## Related

- [Connect your first channel](connect-your-first-channel)
- [Set up an inbox](set-up-an-inbox)

## If it does not work

**Nothing arrives.** Check the webhook in the LINE Developers Console: the URL must be the one on the
Configuration tab, "Use webhook" must be on, and LINE's own "Verify" button must report success.

**Replies fail.** The Channel Access Token has expired or was issued for a different channel. Issue a new
long-lived token and update the channel's settings.
