---
title: Connect Facebook and Instagram
description: Bring Messenger and Instagram direct messages into the same inbox, and understand what Meta allows you to send back.
position: 60
tags: [channels, facebook, instagram, meta]
seo_description: Connecting a Facebook Page and an Instagram account to Lynomia Chat, the permissions Meta asks for, and the 24-hour messaging window.
---
Facebook Messenger and Instagram direct messages are two channels with one owner. Both connect by signing
in to Meta and authorising the Page or the account, and both are governed by the same messaging rules.

## Before you start

**These two channels depend on the installation, not on your account.** They need a Meta app configured by
whoever runs your installation. If Facebook or Instagram is greyed out when you add an inbox, that is what
is missing, and no setting in your account will change it. Ask your provider.

You also need to be an administrator of the Facebook Page, and — for Instagram — a **professional** account
(business or creator) that is set up to receive messages.

## Steps

1. Go to **Settings → Inboxes**, add an inbox, and choose **Facebook** or **Instagram**.
2. Sign in to Meta in the window that opens and grant the permissions it asks for. They cover reading and
   sending the Page's or account's messages, and nothing else.
3. Choose the Page or account from the list, name the inbox, and finish.
4. Add the agents who will work in it.

Meta occasionally restricts this flow at their end. When that happens the screen says so and links to Meta's
own status page; it is not something to retry your way out of.

## The 24-hour rule

Meta allows a reply to a conversation for **24 hours** after the customer's last message. After that a plain
message will not go out.

This is the same rule as WhatsApp's, and it is why a conversation left overnight can become unanswerable.
Where WhatsApp has approved templates to reopen it, Messenger has a narrower set of Meta-approved reasons,
and Instagram has none at all. In practice: answer Meta conversations the same day, or they close.

The product shows this where it matters. A conversation past the window carries a banner saying a reply
cannot be sent, and the composer offers a private note instead, so an agent finds out before they write
rather than after.

## Limits

- **You cannot start a conversation.** Both channels are reply-only; the customer messages first.
- **One Page, one channel.** Connecting the same Page to a second installation takes the subscription away.
- **The token expires.** When Meta invalidates the authorisation — a password change, a permission
  withdrawn, a Page role removed — the channel stops and shows a reconnection prompt. Reconnect from the
  channel's settings; nothing is lost while it is disconnected except the messages Meta would not hand over.
- **Story replies and mentions** arrive as Instagram sends them, which is as a message with a reference,
  not as the story itself.

## Who can do this

Administrators of the account, who are also administrators of the Facebook Page.

## Related

- [Connect your first channel](connect-your-first-channel)
- [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)
- [Set up an inbox](set-up-an-inbox)

## If it does not work

**The channel is greyed out.** The installation has no Meta app configured. This is not something your
account can change.

**The Page is not in the list.** You are not an administrator of it, or you signed in to Meta as a different
person than you meant to. Sign out of Facebook in that browser and run the setup again.

**Messages stopped arriving and the channel shows a reconnection prompt.** The authorisation was
invalidated. Open the channel's settings and reauthorise; the conversations that already exist are not
affected.

**"You cannot reply due to 24 hour message window restriction."** The customer's last message is more than
a day old. The conversation can still be read, labelled, assigned and noted — it cannot be replied to on
that channel.
