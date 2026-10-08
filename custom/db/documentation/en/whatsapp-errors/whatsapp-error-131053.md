---
title: Error 131053 — WhatsApp could not fetch the file
description: You will know why this one is about hosting rather than about your file, and why you will rarely see it here at all.
position: 30
tags: [whatsapp, errors, attachments]
seo_title: "WhatsApp error 131053 in Lynomia Chat"
seo_description: "WhatsApp error 131053: WhatsApp could not download the attachment. Why Lynomia Chat uploads media to WhatsApp instead, and what to do if you still see it."
---
`131053` means WhatsApp tried to **download a file from your installation and could not**. It is a transport
problem between Meta and whoever hosts your server, not a problem with the attachment.

You should rarely see it, because Lynomia Chat avoids the situation that causes it.

## Why you rarely see it

There are two ways to send a file on WhatsApp: give Meta a URL and let it fetch the file, or upload the file to
WhatsApp first and send it by its media id.

Lynomia Chat **uploads first and sends by id**. The reason is exactly this error: Meta's download path is rate
limited per destination network, so on shared hosting your installation can be throttled because of traffic that
has nothing to do with you. The refusals that follow are intermittent, which makes them look like a fault in your
own file when they are not.

Uploading removes Meta's download from the path entirely.

## If you do see it

It means the upload itself did not happen or did not finish, and the send fell back to something Meta had to
fetch. Check, in this order:

| Check | Where |
|---|---|
| Is the file very large or very slow to read? | the attachment in the conversation. An upload has a long but finite timeout |
| Did the number stop being connected mid-send? | **Settings → Inboxes → the inbox → Account Health** |
| Is this one message or every message with a file? | the conversation list, filtered to failed messages |

Press **Retry** on the message. Because the cause is intermittent, a retry genuinely can succeed here — which is
the opposite of [131049](whatsapp-error-131049), and why Retry is offered.

## Who can do this

An agent can retry the message. Reading Account Health and changing anything about the inbox is an administrator's
job.

## Limits

- **Lynomia Chat cannot raise Meta's rate limit.** It is per destination network and not something an account
  setting reaches.
- **The file is not re-uploaded in the background.** A retry repeats the whole send.
- **Repeated failures on every file** point at the host rather than at WhatsApp. That is a conversation with
  whoever runs your server, and the operator's diagnostic is where the evidence is — see
  [when WhatsApp does not work](whatsapp-troubleshooting).

## Related

- [Error 131049](whatsapp-error-131049)
- [When WhatsApp does not work](whatsapp-troubleshooting)
- [Work in the inbox](work-in-the-inbox)
