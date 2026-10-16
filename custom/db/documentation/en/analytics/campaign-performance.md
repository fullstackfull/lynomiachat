---
title: Campaign performance
description: Who a campaign addressed, who received it, and why anyone missed out.
position: 40
tags: [analytics, campaigns]
seo_description: Campaign analytics in Lynomia Chat — addressed, sent, delivered, read, failed, skipped and queued, and what each one means.
---
A campaign has two numbers people usually ask for — how many got it, and how many read it — and four more
that explain the gap between them.

## The tiles

| Tile | What it counts |
|---|---|
| **Campaigns run** | campaigns that addressed at least one contact in this period |
| **Recipients addressed** | contacts the period's campaigns selected, counted once per campaign |
| **Sent** | recipients Meta accepted a message for |
| **Delivered** | recipients Meta confirmed as delivered or read |
| **Read** | recipients Meta confirmed opened the message |
| **Failed** | recipients Meta refused to deliver to |
| **Skipped** | recipients never attempted — for example a contact with no phone number |
| **Still queued** | recipients addressed with no outcome yet |
| **Delivery rate** | delivered as a share of the recipients **addressed** |
| **Read rate** | read as a share of the recipients **addressed** |
| **Failure rate** | refused as a share of the recipients **addressed** |

**The rates are measured against addressed, not against sent.** This is the important difference between
this screen and WhatsApp delivery, and it is deliberate. A campaign that addressed a thousand contacts,
skipped six hundred for want of a phone number and delivered to all four hundred of the rest has a delivery
rate of 40%, not 100%. The first figure is the truth about the campaign; the second is the truth about the
four hundred messages that existed.

**Skipped is the number to read first on a disappointing campaign.** It is almost always an audience
problem — contacts with no phone number, no consent, or a number in a format the provider refuses — and it
is fixable before the next send in a way that a low read rate is not.

**Still queued is only meaningful while a campaign is running.** Hours later it should be zero; if it is
not, something stopped.

## Limits

- **A contact addressed by two campaigns counts in both.** These are campaign recipients, not people.
- **Read requires the recipient's read receipts to be on.** Where they are off, a read message is reported
  only as delivered, so read rate is a floor rather than a measurement.
- **Nothing here says whether the campaign worked.** Delivery is not a reply, and a reply is not a sale.
  What a campaign produced lives in the conversations it started.

## Related

- [WhatsApp campaigns](whatsapp-campaigns)
- [Live chat campaigns](live-chat-campaigns)
- [Shared audiences](shared-audiences)
- [WhatsApp delivery](whatsapp-delivery)
