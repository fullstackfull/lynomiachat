---
title: The WhatsApp 24-hour window
description: You will understand the one WhatsApp rule that explains why some messages send and others do not, and what to do on each side of it.
position: 30
tags: [whatsapp, conversations]
seo_description: "WhatsApp's 24-hour window explained: when you can write freely, when only an approved template sends, and what opens the window again."
---
Almost everything that looks strange about WhatsApp at work comes from one rule, and it is not a Lynomia Chat rule.
It is WhatsApp's.

**When a customer messages you, you can write back freely for 24 hours. After that, the only thing that will send
is an approved template.**

That is the whole rule. Templates, campaigns, automation and most of this section exist because of it.

## Why WhatsApp has it

WhatsApp is the app people keep for family. Meta protects that by making the customer's own message the permission
slip: a business may talk freely to someone who has just spoken to it, and otherwise may only send message shapes
it has reviewed in advance. Breaking it is not possible — the message simply does not go out.

## How the clock actually runs

- The clock starts at **the customer's most recent message** in that conversation.
- It runs for **24 hours** and is **per conversation**. One customer being inside the window tells you nothing
  about another.
- **Nothing you send restarts it.** Not a reply, not a template, not a campaign. Only a new message from the
  customer does.
- A customer who messages you at 09:00 and again at 20:00 has pushed the deadline to 20:00 the next day.

## What changes when it closes

| | Window open | Window closed |
|---|---|---|
| Typing a reply in the conversation | yes, anything | the composer is switched off |
| Images, files, voice notes | yes | no |
| An approved WhatsApp template | yes | **yes — the only thing that sends** |
| A WhatsApp campaign | yes | yes, it sends a template |
| An automation rule that sends a message | yes | the message is created and then fails |
| A satisfaction survey | yes | not sent |
| A private note | yes | yes — notes are never sent to the customer |

When the window is closed, the reply box tells you so: *you can only reply using a template message due to 24-hour
message window restriction.* Use the WhatsApp templates button beside the composer and pick an approved template.

If something sends a plain message anyway — an automation rule, a flow, your own integration — that message does
not quietly vanish. It appears in the conversation marked **Failed to send**, with WhatsApp's own explanation
underneath: the 24-hour customer service window is closed and no template was used.

## A worked example

A customer asks about a delivery at 11:00 on Sunday. Your agent replies, they talk, the conversation is resolved at
11:20.

- **Sunday 18:00** — you remember something. The window is open until Monday 11:00, so you type it and send it.
- **Monday 15:00** — the courier updates you. The window closed four hours ago. Typing is no longer possible.
  You send your approved *order_delivered* template instead, and the customer's reply to it opens a fresh 24 hours.
- **Tuesday** — you want to tell 400 customers about a sale. Most are long outside the window, which is why a
  [WhatsApp campaign](whatsapp-campaigns) sends a template rather than a message you type.

## What this means for how you work

- **Answer inside the window.** It is free-form, it is immediate, and it costs you nothing in review cycles.
- **Prepare templates before you need them.** The moment you need one is the moment you cannot write one — approval
  is WhatsApp's and takes as long as it takes. See [WhatsApp templates](whatsapp-templates).
- **Do not build your process around reopening the window.** There is no way to reopen it from your side.

## Limits

- **The window cannot be extended, shortened or switched off.** It is not a setting anywhere in Lynomia Chat.
- **A template is not unlimited either.** Meta caps how many unique customers you may message outside the window in
  a rolling 24 hours — your *business messaging limit*. It is shown on the inbox's **Account Health** tab, Meta
  decides it, and it is shared by every WhatsApp number in the business portfolio.
- **Lynomia Chat does not warn you that the window is about to close.** There is no countdown and no reminder.
- **Other channels have their own windows**, and they are not the same number. A WhatsApp number running through
  Twilio has the same 24 hours; Facebook, Instagram and TikTok differ.
- **Resolving or reopening a conversation changes nothing.** The window only ever follows the customer's last
  message.

## Related

- [WhatsApp templates](whatsapp-templates)
- [WhatsApp campaigns](whatsapp-campaigns)
- [Connect a WhatsApp number](connect-whatsapp)
- [Work in the inbox](work-in-the-inbox)
- [When WhatsApp does not work](whatsapp-troubleshooting)

## If it does not work

**The composer is greyed out on a conversation I am sure is recent.** Check the last *incoming* message, not the
last message. Your own replies do not count.

**The template button shows nothing.** The inbox has no approved templates synced yet. See
[WhatsApp templates](whatsapp-templates).

**My automation replies keep failing.** The rule fires on something that happens long after the customer wrote —
hours later, or on a resolve. Have it send a template, or have it fire on the incoming message instead.
