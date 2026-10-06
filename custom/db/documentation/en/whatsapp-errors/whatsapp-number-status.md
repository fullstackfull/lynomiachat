---
title: Flagged, restricted, banned — what the number's status means
description: You will know what each of the six statuses Lynomia Chat treats as risky actually means, which ones stop messages, and which of them you can do anything about.
position: 60
tags: [whatsapp, errors, connection]
seo_title: "WhatsApp phone number status in Lynomia Chat"
seo_description: "Flagged, restricted, banned, rate limited, disconnected or deleted: what each WhatsApp phone number status means and what you can do about it."
---
Open **Settings → Inboxes → the inbox → Account Health**. Near the top is the number's **status**, as Meta reports
it. Six values are treated here as worth your attention, and Lynomia Chat writes a line to the operator log when
a number moves into one of them so the change is not silent.

| Status | What Meta means by it | Can you act? |
|---|---|---|
| **Flagged** | quality dropped far enough that Meta is watching the number. Messages still send | yes — the cause is message quality |
| **Restricted** | the number has hit a limit Meta imposed. Sending is reduced or stopped | partly — it lifts as quality recovers |
| **Rate limited** | too many messages too quickly for this number's tier | yes — slow down, and see [messaging limits](whatsapp-quality-and-limits) |
| **Banned** | Meta has removed the number's ability to message | no, not from here. Appeal in WhatsApp Manager |
| **Disconnected** | the number is no longer attached to a usable WhatsApp Business account | sometimes — see [reconnect a number](whatsapp-reconnect-a-number) |
| **Deleted** | the number has been removed at Meta | no. Connect a different number |

## The honest division

Three of these are about **what you send**: Flagged, Restricted and Rate limited all come from quality and volume,
and they improve when the messaging does. That is the part you control, and
[quality rating and messaging limits](whatsapp-quality-and-limits) is the article about it.

Three are about **the number's standing at Meta**: Banned, Disconnected and Deleted. Nothing in Lynomia Chat
changes any of them. A ban is appealed in WhatsApp Manager, by the business that owns the number, and the outcome
is Meta's.

Saying this plainly matters, because the instinct on seeing *Banned* is to reconnect the inbox or recreate it.
Neither helps, and recreating it can release the number from your Meta app — which makes reconnecting harder once
the ban is lifted.

## What to do first

1. Read the status on **Account Health** rather than guessing from symptoms. *Restricted* and
  [error 131042](whatsapp-error-131042) both stop messages and have nothing to do with each other.
2. If the status is one of the first three, look at your recent [campaigns](whatsapp-campaigns): volume,
   audience size and whether people are blocking or reporting the messages.
3. If it is one of the last three, the work is at Meta. Note the date and what changed before it.

## Who can do this

**Administrators.** Account Health is not available to agents, and the permission list for a custom role has no
entry for inboxes — see [roles and permissions](roles-and-permissions).

## Limits

- **Lynomia Chat cannot change any status.** All six are Meta's.
- **There is no alert when a status changes.** The value is on Account Health; nobody is emailed.
- **The history is not kept** in the product. Account Health shows the latest answer Meta gave.
- **A number can be Flagged and still send normally**, which is why it is easy to miss until it becomes
  Restricted.

## Related

- [Quality rating and messaging limits](whatsapp-quality-and-limits)
- [Reconnect a WhatsApp number](whatsapp-reconnect-a-number)
- [When WhatsApp does not work](whatsapp-troubleshooting)
- [WhatsApp campaigns](whatsapp-campaigns)
