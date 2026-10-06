---
title: Nothing is arriving from WhatsApp
description: You will know how to tell "nothing is being delivered to us" from "nothing is being sent to us", where to look, and what cannot be recovered.
position: 90
tags: [whatsapp, errors, inbox]
seo_title: "WhatsApp messages not arriving in Lynomia Chat"
seo_description: "No incoming WhatsApp messages: how to check the webhook, what Account Health reports, and why messages sent during an outage cannot be recovered."
---
Customers say they wrote and nothing is in **Conversations**. There are only a few causes, and
**Settings → Inboxes → the inbox → Account Health** distinguishes them.

## The one to check first

**Webhook not configured**, or a URL that does not match. WhatsApp delivers incoming messages by calling your
installation; if Meta does not know where to call, or is calling somewhere else, nothing arrives and nothing
fails visibly. Press **Register Webhook** on that tab.

This is the commonest cause by a wide margin, and it is the one that produces exactly the symptom of total
silence rather than partial trouble.

## The rest, in order

| What you see | What it is |
|---|---|
| **WhatsApp connection needs to be refreshed**, or **access token needs attention** | the credential stopped being accepted. See [error 190](whatsapp-error-190) and [reconnect a number](whatsapp-reconnect-a-number) |
| Status *Banned*, *Disconnected* or *Deleted* | the number's standing at Meta. See [what the status means](whatsapp-number-status) |
| An incoming message that is there but empty | it arrived and WhatsApp would not hand it over. See [error 131060](whatsapp-error-131060) |
| Health data is not available | Meta did not answer this request. Try again before concluding anything |
| Everything looks healthy | the messages may be arriving in an inbox this agent is not a collaborator on — see [set up an inbox](set-up-an-inbox) |

That last row is worth taking seriously before escalating. An agent sees only the inboxes they are a member of, so
"nothing is arriving" and "nothing is arriving *for me*" look identical from an agent's screen.

## What an operator can check that you cannot

A deployed installation has a read-only diagnostic an operator runs on the server. It reports whether Meta's calls
are reaching the route, whether the background workers are processing them, what the queue depth is, and what the
recent outbound failures actually said. If Account Health looks healthy and messages still are not appearing,
that is the next step and it is the operator's, not yours.

## A worked example

Messages stop on a Sunday. Account Health says *Webhook not configured*. The administrator presses **Register
Webhook**, the warning clears, and a test message from their own phone appears in Conversations within seconds.
The messages customers sent while the webhook was missing never arrive — WhatsApp had nowhere to deliver them —
so the team answers what did arrive and reopens the rest with a template.

## Who can do this

**Administrators**, for everything above. An agent can confirm the symptom and should escalate rather than wait.

## Limits

- **Messages sent while the webhook was missing are gone.** There is no backfill and no replay. This is the single
  most important limit on this page.
- **There is no alert** when incoming messages stop. Silence looks like a quiet day.
- **Registering the webhook does not fetch anything retrospectively.**
- **Account Health reports Meta's answer at that moment**, not a history.

## Related

- [Error 190](whatsapp-error-190)
- [Reconnect a WhatsApp number](whatsapp-reconnect-a-number)
- [What the number's status means](whatsapp-number-status)
- [When WhatsApp does not work](whatsapp-troubleshooting)
- [Set up an inbox](set-up-an-inbox)
