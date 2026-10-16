---
title: Connect SMS
description: Send and receive text messages through Twilio or Bandwidth, on a number you already own.
position: 30
tags: [channels, sms]
seo_description: Connecting an SMS channel in Lynomia Chat through Twilio or Bandwidth, the callback URL, and what SMS costs you per message.
---
SMS reaches a phone with no app, no internet connection and no account. That makes it the right channel for
a delivery notice, a one-time code or a confirmation — and the wrong one for a conversation that could have
happened on WhatsApp, because every message costs money and arrives without context.

Lynomia Chat does not sell you the number. You bring an account with **Twilio** or **Bandwidth**, and the
channel connects to it.

## What you need

**For Twilio:** an Account SID and Auth Token (or an API Key SID and Secret), and either a phone number you
own in Twilio or a Messaging Service SID.

**For Bandwidth:** an Account ID, an API Key, an API Secret, an Application ID, a phone number, and the
callback username and password set on that Bandwidth application.

Both are in your provider's own console. Lynomia Chat verifies them while the channel is created, so wrong
credentials fail there rather than silently later.

## Steps

1. Go to **Settings → Inboxes**, add an inbox, and choose **SMS**.
2. Pick the provider: **Twilio** or **Bandwidth**.
3. Fill in the credentials, the inbox name, and the number messages will be sent from. The number must be
   in international form — a `+`, then digits, with no spaces.
4. Finish, then open the channel's **Configuration** tab and copy the **Callback URL**.
5. Paste that URL into your provider's console as the message callback for that number or application. This
   is the step people skip, and it is the one that makes incoming messages work: without it you can send
   and never receive.

## Limits

- **Every message costs**, in both directions on most plans, and a long message is split into several. Your
  provider bills it, not Lynomia Chat.
- **There is no delivery guarantee and no read receipt** beyond what your provider reports.
- **Attachments depend on the provider and the country.** Where MMS is not available, an attachment cannot
  be sent at all.
- **A number can only be connected once.** Pointing a second installation at the same number takes the
  callback away from this one.

## Who can do this

Administrators.

## Related

- [Connect your first channel](connect-your-first-channel)
- [Campaigns or automation](campaigns-or-automation)
- [Set up an inbox](set-up-an-inbox)

## If it does not work

**You can send but nothing arrives.** The callback URL is not set, or it is set on a different number.
Copy it again from the channel's Configuration tab and check it against the number in your provider's
console.

**The credentials are refused at setup.** They are being checked against the provider live. Confirm you
pasted the SID and the token from the same project, and that the token has not been rotated.

**Messages fail with a provider error.** Open the message in the conversation to see what the provider said.
The common ones are a number not enabled for the destination country, an unverified sender on a trial
account, and a number that is not SMS-capable at all.
