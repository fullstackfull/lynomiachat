---
title: When WhatsApp does not work
description: You will be able to work out why a template was rejected, why a message did not send, or why a number has stopped receiving, and what to do about each.
position: 60
tags: [whatsapp, troubleshooting]
seo_description: "Fix WhatsApp problems in Lynomia Chat: rejected templates, failed messages, the 24-hour window, webhooks and disconnected numbers."
---
Nearly every WhatsApp problem is one of three things: WhatsApp refused a template, WhatsApp refused a message, or
WhatsApp has stopped talking to your number. Each has its own place to look.

The common thread is worth saying first: **Meta owns these outcomes.** Lynomia Chat reports what WhatsApp says and
sends what WhatsApp allows. Where that is the answer, this article says so rather than suggesting a setting that
does not exist.

## A template was rejected

Open **Settings → Templates** and click the template. The detail panel shows **Why WhatsApp rejected it**: the
reason WhatsApp returned, and — when WhatsApp sent us an explanation in words — that too.

| Reason you are likely to see | What it usually means |
|---|---|
| The content is promotional in a UTILITY template | you chose UTILITY, WhatsApp read marketing. Make it MARKETING, or make the message genuinely about one transaction |
| The variables look wrong | a sample value is implausible, or a variable sits where WhatsApp will not allow one |
| The content is incorrect or misleading | the text promises something it cannot guarantee, or does not match what your business does |
| A duplicate exists | the same name and language already exist in that business account |

What to do: a rejected template stays editable. Fix the text, save, and submit again — you do not need to recreate
it, and recreating it under a new name costs you the old one for 30 days if you delete it. See
[the template lifecycle](whatsapp-template-lifecycle).

**Two honest caveats.** The words WhatsApp writes about a rejection only arrive with the live status update; if that
did not reach us, you will see the reason code alone. And Lynomia Chat cannot appeal a rejection — appeals happen in
WhatsApp Manager, and a template under appeal shows as *Under appeal* here.

## A message did not send

Find the message in the conversation. A message that failed is marked **Failed to send**, with WhatsApp's own
explanation underneath it.

| What you see | Why | What to do |
|---|---|---|
| *The 24-hour customer service window is closed and no template was used* | the customer last wrote more than 24 hours ago | send an approved template instead. See [the 24-hour window](the-whatsapp-24-hour-window) |
| The composer is greyed out before you even type | same cause | use the templates button beside the composer |
| *Template not found or invalid template name* | the template is not in this inbox's synced list under that name and language, or is no longer approved | check it in **Settings → Templates**, then **Sync templates** |
| A campaign completed but someone received nothing | the template stopped being approved, a variable rendered empty, or the contact has no usable phone number | see [WhatsApp campaigns](whatsapp-campaigns) |
| Nothing at all happened, no message appears | the inbox is disconnected — see below | |

A failed message can be retried from the conversation once you have fixed the cause.

Three causes account for most of the rest:

- **A variable that renders empty.** In a campaign, a contact whose value is blank is skipped entirely.
- **An automation rule firing too late.** A rule that sends a message when a conversation is resolved will often
  fire outside the window. Have it send a template, or trigger it on the incoming message.
- **A number WhatsApp has restricted.** Check the quality rating and phone number status on **Account Health**.

## A number is not connected

Open **Settings → Inboxes → the inbox → Account Health**. It reports what Meta says about the number, and almost
every connection problem is visible there.

| What Account Health says | Meaning |
|---|---|
| **Webhook not configured**, or a URL mismatch | WhatsApp does not know where to deliver messages, so nothing arrives. Use **Register Webhook** on that tab |
| **WhatsApp connection needs to be refreshed** | Meta could not validate the connection. Reconnect it from the inbox's **Configuration** tab |
| **WhatsApp access token needs attention** | for a manually connected number: the token has expired or lost a permission. Replace it in **Configuration** |
| Phone number status *Flagged*, *Restricted* or *Banned* | Meta has acted on the number. This is resolved with Meta, not here |
| Display name *Not approved* | the name is refused; messages still send, but the number may show instead of the name |
| **Health data is not available** | Meta did not answer. Try later |

If an inbox has failed to authorise repeatedly, Lynomia Chat marks it disconnected, tells you at the top of the
dashboard that you will not receive new messages until it is reauthorised, and emails the account's
administrators.

## A worked example

Messages stop arriving on Sunday morning. An administrator opens the inbox's **Account Health** tab and sees
*Webhook not configured*. They press **Register Webhook**, the banner clears, and they send a test message from
their own phone. It arrives in **Conversations** within seconds. The messages customers sent while the webhook was
missing are not recovered — WhatsApp had nowhere to deliver them — so the team works through the conversations that
do arrive and follows up with a template where they need to reopen one.

## Who can do this

**Administrators** only, for everything in this article: Account Health, Configuration, registering a webhook,
syncing templates and the template manager. An agent who cannot send sees the symptom but not the cause, so this is
the conversation to escalate.

## Limits

- **Messages sent while the webhook was missing are gone.** There is no backfill and no replay.
- **Lynomia Chat cannot change a quality rating, a messaging limit, a display-name decision or a template
  verdict.** All four are Meta's.
- **There is no alert when a template is paused or rejected.** The state appears in the template manager; nobody is
  emailed.
- **Deleting and recreating an inbox is rarely the fix** and can release the number from your Meta app. Reconnect
  from **Configuration** first.
- **A number can only be connected once across the whole installation.** If adding it is refused because the phone
  number is taken, it is already connected somewhere — possibly in another account.

## When you have a code

Where WhatsApp's refusal begins with a number, there is a page about that number. Those are the ones this
installation has actually seen; a code with no page here is one nobody here has met, and inventing an explanation
for it would be worse than leaving it to WhatsApp's own words.

- [131049 — refused for this one person](whatsapp-error-131049)
- [131042 — the account cannot be billed](whatsapp-error-131042)
- [131053 — WhatsApp could not fetch the file](whatsapp-error-131053)
- [131060 — an incoming message WhatsApp will not hand over](whatsapp-error-131060)
- [190 — the access token is no longer valid](whatsapp-error-190)

And for the symptoms that carry no code:
[the number's status](whatsapp-number-status) ·
[quality and limits](whatsapp-quality-and-limits) ·
[the display name](whatsapp-display-name) ·
[nothing is arriving](whatsapp-nothing-arrives) ·
[reconnecting a number](whatsapp-reconnect-a-number) ·
[the number is already connected](whatsapp-number-already-connected) ·
[contact information requests](whatsapp-contact-info-requests) ·
[business-scoped contacts](whatsapp-business-scoped-contacts) ·
[finding a failed message](whatsapp-find-a-failed-message)

## Related

- [Connect a WhatsApp number](connect-whatsapp)
- [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)
- [WhatsApp templates](whatsapp-templates)
- [The template lifecycle](whatsapp-template-lifecycle)
- [WhatsApp campaigns](whatsapp-campaigns)
