---
title: Error 131060 — an incoming message WhatsApp will not hand over
description: You will know why a conversation shows an empty incoming message, what WhatsApp did, and why the placeholder is deliberately kept.
position: 40
tags: [whatsapp, errors, inbox]
seo_title: "WhatsApp error 131060 in Lynomia Chat"
seo_description: "WhatsApp error 131060: an unsupported incoming WhatsApp message. Why Lynomia Chat shows a placeholder instead of nothing at all."
---
A customer sent you something and the conversation shows an **incoming message with no content**. WhatsApp
delivered the event but refused to hand over the message itself, marking it unsupported — the code behind that is
`131060`.

It happens with message types WhatsApp will not forward to a business API: some interactive and system message
types, and media WhatsApp itself could not process.

## Why there is a placeholder at all

Lynomia Chat records the empty message on purpose rather than dropping the event.

A dropped event would leave your agent reading a conversation where the customer appears to have gone quiet, and
the customer insisting they wrote. The placeholder says, truthfully, that something arrived at that moment and
could not be shown. It also keeps the conversation's timing honest: the
[24-hour window](the-whatsapp-24-hour-window) opens from the customer's message, and that is still what
happened.

## What to do

**Ask.** The customer can see what they sent; you cannot. A single line — "something came through that we could
not open, could you send it as a photo or describe it?" — resolves almost all of these, and you are inside the
24-hour window because they just wrote to you.

Do not treat it as a fault in your inbox. Other messages in the same conversation arrive normally.

## A worked example

A customer forwards a product from a shopping catalogue. The agent sees an empty incoming message and asks what it
was. The customer types the product name. The agent answers, and the conversation continues. Nothing was
misconfigured and nothing needed fixing.

## Who can do this

Any agent working the conversation. There is nothing for an administrator to change.

## Limits

- **The content cannot be recovered**, by you or by support. WhatsApp did not send it.
- **There is no notification.** The placeholder sits in the conversation like any other incoming message.
- **It is not reported as a failure** anywhere, because nothing of yours failed.
- **Some unsupported types carry no useful hint at all** about what was sent.

## Related

- [Work in the inbox](work-in-the-inbox)
- [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)
- [When WhatsApp does not work](whatsapp-troubleshooting)
