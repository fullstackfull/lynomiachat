---
title: WhatsApp delivery
description: Whether your WhatsApp messages are reaching people, which templates carry the volume, and what Meta is refusing.
position: 30
tags: [analytics, whatsapp]
seo_description: The WhatsApp delivery analytics screen in Lynomia Chat — sent, delivered, read, failed, and what the rates are measured against.
---
This screen answers one question: **are the messages arriving?**

Every figure on it comes from what Meta told us about a message after we handed it over. None of it is
inferred.

## The tiles

| Tile | What it counts |
|---|---|
| **Messages sent** | outgoing WhatsApp messages handed to Meta in this period |
| **Template sends** | of those, the ones sent as an approved template |
| **Delivered** | messages Meta confirmed as delivered or read |
| **Read** | messages Meta confirmed the recipient opened |
| **Failed** | messages Meta refused to deliver |
| **Delivery rate** | delivered as a share of what was sent |
| **Read rate** | read as a share of what was sent |
| **Failure rate** | refused as a share of what was sent |
| **Synced from the app** | messages sent from the WhatsApp Business app and synced in |

Two of these have a rule inside them.

**A message delivered and later marked failed counts only as failed.** Meta sometimes reports a delivery
and then retracts it. The later word wins, so the delivered figure never overstates.

**Messages synced from the WhatsApp Business app are excluded from every count and rate above.** Their
delivered status was recorded on a phone rather than confirmed by Meta, and mixing the two would make a
delivery rate that means nothing. They are shown separately so the volume is visible without polluting the
measurement.

## What a bad number means

**Failure rate climbing.** Open a failed message in its conversation and read the error. The usual causes
are the 24-hour window, a number that is not on WhatsApp, a template that was rejected or paused, and a
quality-rating restriction on your own number.

**Read rate far below delivery rate.** The messages arrive and nobody opens them. That is a content and
timing problem, not a delivery problem — and on a template campaign it is the number that matters.

**Template sends near zero while sends are high.** Everything is going out inside the 24-hour window, which
is healthy. The reverse — almost everything a template — usually means you are reaching out more than you
are replying.

## Limits

- **This measures delivery, not conversation.** A high delivery rate with no replies is still a failure of
  the message.
- **Rates are shares of what was sent in the period**, so a small period with a handful of sends produces
  rates that jump around.
- **Meta's own delay** means the last hours of a range can look worse than they will once the statuses
  settle.

## Related

- [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)
- [WhatsApp templates](whatsapp-templates)
- [Find a failed WhatsApp message](whatsapp-find-a-failed-message)
- [Campaign performance](campaign-performance)
