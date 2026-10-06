---
title: The WhatsApp Business app and Lynomia Chat on one number
description: You will know what connecting your existing WhatsApp Business app number to Lynomia Chat gives you, what it cannot do, and whether the route is available yet.
position: 20
tags: [whatsapp, inboxes]
seo_description: "Coexistence in Lynomia Chat: keep the WhatsApp Business app on the phone and add your team, what is not carried over, and its release status."
---
Most businesses in the Gulf already run WhatsApp from a phone, in the **WhatsApp Business app**, with one person
holding the handset. Meta calls keeping that *and* connecting the same number to a platform **coexistence**. In
Lynomia Chat it is the **WhatsApp Business** card under **Settings → Inboxes → Add inbox → WhatsApp**.

It exists so that you do not have to choose between the phone your staff know and an inbox your team can share.

## Check whether it is available to you first

This route is built, and the whole onboarding has been tested end to end against a simulated Meta in a staging
rehearsal. **It has not been released to production.** Two things still have to happen against the real Meta before
it goes live: a signup run through Lynomia's own Meta app, and a real WhatsApp Business app number connected and
messaging.

So treat this article as a description of the route, not an instruction to use it today. If the **WhatsApp Business**
card is not on your Add inbox screen, that is expected — ask whoever runs your installation before planning a
migration around it.

## What it allows

| | |
|---|---|
| **You keep the number** | no new number, no port, no "message us on our new WhatsApp" |
| **The phone keeps working** | the WhatsApp Business app stays on the handset and stays usable |
| **Both sides land in one conversation** | a reply sent from the phone appears in the Lynomia Chat conversation as an outgoing message, so the history is not split in two |
| **Your team replies from Lynomia Chat** | assignment, labels, canned responses, reports — the same as any other WhatsApp channel |
| **It is an official Meta connection** | the number joins the WhatsApp Business Platform; nothing is scanned, scraped or proxied |

A reply typed on the phone reaches Lynomia Chat because Meta sends an echo of it. Each echo is matched by its
WhatsApp message id, so a message cannot be duplicated, and Lynomia Chat never re-sends it to the customer.

## What it does not do

- **It does not import your past chats.** Nothing from before the connection comes across. Meta only allows that
  synchronisation in the first 24 hours after onboarding, and Lynomia Chat does not implement it at all — so it
  cannot be turned on later for a number that is already connected either. Your history stays on the phone.
- **It does not import your contacts.** Contacts in Lynomia Chat are created by the messages that arrive after the
  connection, or by [importing them yourself](import-contacts).
- **It does not change WhatsApp's rules.** The number is now a WhatsApp Business Platform number, so
  [the 24-hour window](the-whatsapp-24-hour-window) and approved [templates](whatsapp-templates) apply exactly as on
  any other WhatsApp channel — including to the phone.
- **It is not a second channel.** One number, one inbox. The phone and Lynomia Chat are two doors into the same
  conversation, not two conversations.

## What you need first

- **Administrator access** in Lynomia Chat.
- **The WhatsApp Business app, version 2.24.17 or later**, signed in on the phone that holds the number.
- **A Meta login with admin rights** on the business portfolio you want the number to live under.
- **The phone in your hand during setup** — you confirm the connection on it.

## Steps

1. **Settings → Inboxes → Add inbox → WhatsApp → WhatsApp Business.**
2. Read the note on the card, then start the connection. Meta's own window opens.
3. In Meta's window, log in and pick your **existing WhatsApp Business app number**.
4. **Confirm the connection on the phone.** Linked devices such as WhatsApp Web are signed out at this point; link
   them again afterwards if you use them.
5. Back in Lynomia Chat, choose the agents who will work in the new inbox.
6. Send yourself a test message, and send one reply from the phone. Both should appear in the same conversation —
   the customer's message incoming, the phone's reply outgoing.

## Who can do this

**Administrators** only. Agents can work in the inbox once they are added to it, from either side.

## Limits

- **There is no manual fallback for this route.** If the Meta window fails, there is no credentials form to fill in
  instead. The ordinary WhatsApp Cloud card still has its manual setup, but that is for a number already on the
  WhatsApp Business Platform.
- **Deleting the inbox releases the number from the Meta app.** Reconnecting means running the flow again, and
  because history is never imported, the chats from the gap do not come across.
- **Account Health reports coexistence, it does not control it.** The inbox's **Account Health** tab shows a
  *Coexistence* line when Meta says the number is on the Business app as well. That is Meta's own signal.
- **Everything Meta decides stays Meta's.** Display-name review, quality rating and the business messaging limit are
  reported in Account Health and set by Meta.

## Related

- [Connect a WhatsApp number](connect-whatsapp)
- [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)
- [WhatsApp templates](whatsapp-templates)
- [When WhatsApp does not work](whatsapp-troubleshooting)

## If it does not work

**There is no WhatsApp Business card.** Either your installation has no Meta app configured for it, or this route is
not released on your install yet. Both are installation-level, not account settings.

**The Meta window finished but no inbox appeared.** The flow ended without a number that can be connected. Run it
again and pick the WhatsApp Business app number explicitly.

**Replies from the phone are not showing up in Lynomia Chat.** Open the inbox's **Account Health** tab. If it
reports that the webhook is not configured, or shows a URL mismatch, use **Register Webhook** there.

**My old chats are missing.** They were never imported, and there is no setting that will bring them in. Keep the
phone for reference.
