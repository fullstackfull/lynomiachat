---
title: Finding the conversations where a message failed
description: You will know where a failed message shows up, how to list every conversation containing one, and what that list does not tell you.
position: 140
tags: [whatsapp, errors, inbox]
seo_title: "Find failed WhatsApp messages in Lynomia Chat"
seo_description: "Where a failed WhatsApp message appears, how to filter conversations by message delivery status, and what that list does not tell you."
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

## Listing them

**Conversations → Filter → Message delivery → Equal to → Failed to send.** The condition asks whether the
conversation *contains* a message with that delivery status, so it finds the conversation however long ago the
failure happened and wherever it sits in the thread.

It combines with the other conditions, which is where it earns its keep:

| Add this | To get |
|---|---|
| Status is Open | failures still waiting on somebody |
| Inbox is your WhatsApp number | failures on that number only |
| Assignee is you | your own |
| Last activity is 7 days before | the ones that have gone quiet since |

**Save it as a folder.** Once the filter is right, save it, and the queue is one click away from then on rather
than something to rebuild. See [work in the inbox](work-in-the-inbox).

One honest note: a conversation whose failure was retried successfully still contains the original failed
message, so it still matches. The filter answers "something failed here", not "something is still broken here" —
open the conversation to tell the two apart.

Two habits make the rest less costly:

- **Watch the composer, not just the message.** Where the [24-hour window](the-whatsapp-24-hour-window) has
  closed, the composer is disabled before you type — that is the failure prevented rather than recorded.
- **Read a campaign's report after it finishes**, rather than treating *completed* as *delivered*.

## Who can do this

Any agent sees failures in the conversations they can open. A campaign's report is an administrator's. The
server-side diagnostic is the operator's.

## Limits

- **No notification is raised** when a message fails. The agent who sent it sees it; nobody else is told, so the
  filter is something somebody has to look at.
- **The filter does not distinguish a failure that was later retried** from one that was not.
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
