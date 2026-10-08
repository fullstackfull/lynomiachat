---
title: Error 131049 — WhatsApp refused the message for this one person
description: You will know why this failure names one recipient and not your number, why Retry is withdrawn for it, and what actually makes it stop.
position: 10
tags: [whatsapp, errors, delivery]
seo_title: "WhatsApp error 131049 in Lynomia Chat"
seo_description: "WhatsApp error 131049: Meta capped how many marketing messages one person receives. Why retrying cannot help, and what to do instead."
---
The message says **Failed to send**, and under it WhatsApp's own words begin with `131049`. Meta withheld this
message from **one person** because of how many messages of this kind they have already been sent.

The important part is what it is not. It is not your number being blocked, not your template being wrong, and not
a fault in the connection. Messages to other people keep going out normally in the same minutes — that is exactly
what was observed when this was first investigated here, with delivered and read messages interleaved with the
refusals on the same number.

## Why Retry is not offered

For this code the Retry button is deliberately withdrawn and replaced with the reason.

The restriction follows the **person**, not your configuration. Nothing you change about the message, the
template or the number makes Meta accept the same message to the same recipient, so pressing Retry would simply
collect the refusal again — and every attempt is one more signal against your number's quality rating. See
[quality rating and messaging limits](whatsapp-quality-and-limits).

Other failures keep their Retry. Only refusals that follow the recipient lose it.

## What to do

**Nothing, for that message.** The cap is Meta's and it lifts by itself. There is no setting here or in WhatsApp
Manager that raises it, and no support request that clears it for one contact.

What you can do is reduce how often you hit it:

- **Send fewer marketing messages to the same people.** The cap counts what a person receives, so a narrower
  [audience](shared-audiences) and a longer gap between [campaigns](whatsapp-campaigns) both help.
- **Use the right template category.** A message genuinely about one transaction belongs in UTILITY, which this
  cap does not apply to the same way. Do not relabel marketing as utility to get around it — Meta reads the
  content, and [a template](whatsapp-template-lifecycle) submitted in the wrong category is rejected or
  reclassified.
- **Reply inside the conversation instead.** Within the [24-hour window](the-whatsapp-24-hour-window) you are
  answering a customer rather than marketing to them.

## A worked example

A shop sends a promotion to 4,000 contacts. The campaign completes; 37 messages failed, all with `131049`, and the
same contacts received the shop's order-confirmation messages that afternoon without trouble. There is nothing to
fix. The shop stops sending promotions to contacts who received one in the previous fortnight, and the count on
the next campaign is much lower.

## Who can do this

Any agent can see the explanation on the message. Changing audiences, templates and campaign scheduling is an
administrator's job — see [roles and permissions](roles-and-permissions).

## Limits

- **Lynomia Chat cannot tell you how close a contact is to the cap.** Meta does not report that, so the first
  sign is the refusal.
- **The refusal is per message.** The same contact may receive the next one.
- **There is no list of restricted contacts** anywhere in the product.
- **A campaign reports the failure per message**, so a mostly successful campaign can still contain these.

## Related

- [When WhatsApp does not work](whatsapp-troubleshooting)
- [Quality rating and messaging limits](whatsapp-quality-and-limits)
- [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)
- [WhatsApp campaigns](whatsapp-campaigns)
- [The template lifecycle](whatsapp-template-lifecycle)
