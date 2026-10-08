---
title: Error 131042 — the WhatsApp Business account cannot be billed
description: You will know that this one is yours to fix rather than Meta's to lift, where to fix it, and why Retry stays available for it.
position: 20
tags: [whatsapp, errors, billing]
seo_title: "WhatsApp error 131042 in Lynomia Chat"
seo_description: "WhatsApp error 131042: the WhatsApp Business account has no usable payment method or currency. Fix it in Meta Business Manager, then retry."
---
The message failed and WhatsApp's words begin with `131042`. The **WhatsApp Business account's payment setup is
not usable** — most often no payment method, a card that was declined, or a currency that does not match the
account.

This is the one in this section that is genuinely yours to fix. It is about the account, not about the person you
were writing to, so it stops every paid message on that number rather than one.

## Why Retry stays available

Unlike [131049](whatsapp-error-131049), the Retry button is kept. The reason is simple: an administrator can fix
the billing in Meta Business Manager, and the **same message will then send**. Withdrawing Retry here would be
telling you to give up on something you are about to be able to do.

Lynomia Chat does not re-send it for you. Nothing here retries a WhatsApp message on its own; after you have
fixed the billing you press Retry on the message yourself.

## What to do

1. Open **business.facebook.com** and go to the WhatsApp Business account for this number.
2. Check **Billing** — a payment method must be present and valid, and the account's currency must be set.
3. Fix whatever is missing. A declined card and an unset currency look identical from here.
4. Come back to the conversation and press **Retry** on the message.

Nothing in Lynomia Chat changes this. There is no billing screen here for your WhatsApp account, because the money
relationship is between you and Meta.

## A worked example

Messages stop sending on the first of the month, all with `131042`. The administrator opens Business Manager and
finds the card on the WhatsApp Business account expired. They add a new one, return to the three conversations
where an agent was mid-reply, and press Retry on each. All three go out. No template needed re-approving and no
number needed reconnecting, because nothing was wrong with either.

## Who can do this

An **administrator** of the Meta Business Manager account — which may not be the same person as a Lynomia Chat
administrator. An agent can see the refusal and press Retry, but cannot fix the cause.

## Limits

- **There is no warning before it happens.** Lynomia Chat learns the billing is unusable when Meta refuses a
  message.
- **Account Health does not report billing.** The number can look entirely healthy and still refuse every paid
  message — see [when WhatsApp does not work](whatsapp-troubleshooting).
- **Messages that failed while billing was broken are not sent automatically** once you fix it. Each one is
  retried by hand.
- **A campaign that ran during the outage does not resume.** Check what failed and send again.

## Related

- [Error 131049](whatsapp-error-131049)
- [When WhatsApp does not work](whatsapp-troubleshooting)
- [WhatsApp campaigns](whatsapp-campaigns)
- [Roles and permissions](roles-and-permissions)
