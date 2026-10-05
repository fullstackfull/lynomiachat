---
title: Connect a WhatsApp number
description: You will have a WhatsApp number receiving and sending messages in Lynomia Chat, and you will know which of the three ways to connect fits your number.
position: 10
tags: [whatsapp, getting-started, inboxes]
seo_description: "Connect WhatsApp to Lynomia Chat: what a WhatsApp Business Account is, the three connection routes, and what Meta needs from you first."
---
A WhatsApp number in Lynomia Chat is a **channel**, listed under **Settings → Inboxes** with its own inbox. The
connection itself is made with **Meta**, not with Lynomia Chat: your number lives on Meta's WhatsApp Business
Platform, and Lynomia Chat holds the credentials that let it read and write on that number's behalf.

## What a WhatsApp Business Account is

Meta groups your WhatsApp assets into a **WhatsApp Business Account**, often shortened to WABA. It is not a phone
number and not a Facebook page. It is the container that owns your numbers, your message templates and your
messaging limits, and it has an id — the *WhatsApp Business Account ID* — that you will be asked for at least once.

Two consequences matter more than the terminology:

- **Templates belong to the business account, not to the inbox.** If two inboxes in Lynomia Chat are two numbers on
  the same business account, they see and send the same templates. If they are on different business accounts, a
  template with the same name in each is two separate templates.
- **One account in Lynomia Chat can hold several numbers and several business accounts.** Nothing assumes one of
  either.

## The three ways to connect

| Route | Use it when | What you supply |
|---|---|---|
| **WhatsApp Cloud — quick setup through Meta** | you are connecting a number through Meta and want the connection configured for you | a Meta login with admin rights; you pick the number inside Meta's own window |
| **WhatsApp Cloud — manual setup** | the number is already on the WhatsApp Business Platform, or you manage your own Meta app | Phone Number ID, WhatsApp Business Account ID, a permanent access token |
| **WhatsApp Business** | the number is in use in the WhatsApp Business app on a phone and you want to keep using it there | a Meta login; you confirm on the phone |
| **Twilio** | WhatsApp already runs through your Twilio account | your Twilio credentials |

The **WhatsApp Business** card is shown only when your installation has a Meta app configured for it. If you see
only WhatsApp Cloud and Twilio, that is an installation-level setting, not something you can change in your
account. See [using the WhatsApp Business app and Lynomia Chat on one number](whatsapp-business-coexistence).

## What you need first

- **Administrator access** in Lynomia Chat. Every step below is administrator-only.
- **A Meta business portfolio you have admin rights on**, and a phone number that is not currently signed in to
  personal WhatsApp and not already connected to another WhatsApp Business Platform account.
- **For manual setup only:** a Meta app with the WhatsApp use case, the number added and verified inside it, and a
  permanent access token from a Meta system user carrying both `whatsapp_business_management` and
  `whatsapp_business_messaging`. Meta shows that token once — copy it before closing the dialog.

## Steps

1. **Settings → Inboxes → Add inbox → WhatsApp.**
2. Choose a route from the table above.
3. **Quick setup:** choose *Connect with WhatsApp Business*. Meta's own window opens; log in, choose or add the
   number, and finish. Lynomia Chat exchanges the result on the server, registers the webhook with Meta and
   subscribes it. The access token is never handled in your browser.
4. **Manual setup:** the screen walks you through Meta in four stages — create or select the Meta app, add and
   verify the number and copy its two identifiers, generate the permanent token, then enter the three values.
   *Verify details* checks number access, template access, the webhook callback and the webhook subscription before
   the inbox is created, and shows you the webhook URL it registered.
5. **Choose the agents** who will work in this inbox. An agent who is not a member sees nothing of it;
   administrators see every inbox without being added.
6. Finish. The last screen offers a code to scan with a phone, which opens a chat to the new number — send a test
   message and watch it arrive in **Conversations**.

After the inbox exists, **Settings → Inboxes → the inbox → Account Health** reports what Meta says about the
number: display phone number, display name and its review status, phone number status, quality rating, business
messaging limit, throughput, and the business account's name and id.

## A worked example

A clinic in Kuwait has a landline-free mobile number that has never been on WhatsApp. An administrator opens
**Add inbox → WhatsApp → WhatsApp Cloud**, uses the quick setup, logs in to the clinic's Meta portfolio, adds the
number inside Meta's window and verifies it by SMS. Back in Lynomia Chat the inbox appears, two receptionists are
added as agents, and the QR code is scanned to send a test "hello" — which lands in Conversations, unassigned,
within seconds.

## Who can do this

**Administrators** only — adding an inbox, viewing Configuration, viewing Account Health and syncing templates.
Agents can work in an inbox they are a member of, and cannot change its connection.

## Limits

- **A phone number can be connected once in the whole installation.** The same number cannot be added to two
  accounts or two inboxes.
- **Meta owns the outcomes, not Lynomia Chat.** Number registration, display-name review, quality rating, business
  messaging limit and template approval are all Meta's decisions. Account Health reports them; nothing in Lynomia
  Chat changes them.
- **Quick setup can be unavailable** when Meta has an issue on its side. The page says so and offers manual setup
  for eligible numbers.
- **On Twilio, templates are not managed in Lynomia Chat** — the templates page links out to Twilio instead. WhatsApp
  campaigns also refuse to run on a Twilio inbox: a campaign requires a WhatsApp Cloud number.
- **Deleting the inbox behaves differently per route.** A number connected through quick setup is released from the
  Meta app on delete, so it can be connected elsewhere. A manually connected number is deliberately left
  registered, because deregistering it would disable the number on your own Meta app. Move a manual number in Meta,
  not by deleting the inbox.

## Related

- [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)
- [Using the WhatsApp Business app and Lynomia Chat on one number](whatsapp-business-coexistence)
- [WhatsApp templates](whatsapp-templates)
- [When WhatsApp does not work](whatsapp-troubleshooting)

## If it does not work

**I only see two provider cards.** Your installation has no Meta app configured for the WhatsApp Business app
route. Use WhatsApp Cloud, or ask whoever runs your installation.

**Meta's window finished but no inbox was created.** If the message says the setup finished without a WhatsApp
phone number that can be connected, the Meta flow ended on a business portfolio with no usable number. Run it
again and add a phone number inside Meta's window.

**"This access token is invalid or expired."** The token is not a permanent system-user token, has expired, or is
missing one of the two required permissions. Generate a new one and paste it again.

**The inbox exists but no messages arrive.** The webhook is not registered. Open **Account Health** — if it shows
*Webhook not configured* or a URL mismatch, use **Register Webhook** there.
