---
title: Finding the conversations where a message failed
description: You will know where a failed message shows up, how to find it again later, and what the inbox does not do for you.
position: 140
tags: [whatsapp, errors, inbox]
seo_title: "Find failed WhatsApp messages in Lynomia Chat"
seo_description: "Where a failed WhatsApp message appears, how to find the conversation again, and what the conversation list does and does not show."
---
A failure is shown **on the message**, inside the conversation: *Failed to send*, the explanation where Lynomia
Chat recognises the code, WhatsApp's own words, and a Retry button where retrying could possibly work.

That is precise and it is easy to walk past. A conversation containing a failed message looks like any other
conversation in the list.

## Finding one again

**If you know the customer.** Search for the contact and open the conversation. The failed message is in place,
in the timeline, where it was.

**If you do not.** Two places are worth looking:

| Where | What it tells you |
|---|---|
| The campaign's own report, under **Campaigns** | which sends failed, for a campaign. See [WhatsApp campaigns](whatsapp-campaigns) |
| The operator's diagnostic, on the server | the recent failed outgoing messages on a WhatsApp inbox and what each refusal said |

The second is the operator's, not yours, but it is the honest answer to "which messages failed on this number
this week" and it is worth knowing it exists before you spend time reconstructing it by hand.

## What the conversation list does not do

**It does not filter by "has a failed message".** Scanning the inbox for failures is not something the list can
do for you today, so a failure that nobody was looking at when it happened is found by the customer asking again
rather than by you noticing.

Two habits make that less costly:

- **Watch the composer, not just the message.** Where the [24-hour window](the-whatsapp-24-hour-window) has
  closed, the composer is disabled before you type — that is the failure prevented rather than recorded.
- **Read a campaign's report after it finishes**, rather than treating *completed* as *delivered*.

## Who can do this

Any agent sees failures in the conversations they can open. A campaign's report is an administrator's. The
server-side diagnostic is the operator's.

## Limits

- **There is no "failed messages" view** and no filter for one.
- **No notification is raised** when a message fails. The agent who sent it sees it; nobody else is told.
- **A failed message is not retried automatically**, ever, by design — see
  [error 131042](whatsapp-error-131042) for why that matters.
- **Retry is withdrawn** where a retry would simply repeat the refusal — see
  [error 131049](whatsapp-error-131049).
- **A failure older than a day cannot be retried** from the conversation. Send again instead.

## Related

- [Error 131049](whatsapp-error-131049)
- [Error 131042](whatsapp-error-131042)
- [When WhatsApp does not work](whatsapp-troubleshooting)
- [WhatsApp campaigns](whatsapp-campaigns)
- [Work in the inbox](work-in-the-inbox)
