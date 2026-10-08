---
title: Quality rating and messaging limits
description: You will know what the green, yellow and red rating is measuring, what a messaging tier allows, and the few things that genuinely move both.
position: 70
tags: [whatsapp, errors, quality]
seo_title: "WhatsApp quality rating and messaging limits in Lynomia Chat"
seo_description: "What a green, yellow or red WhatsApp quality rating means, how messaging limit tiers work, and what actually improves them."
---
**Account Health** reports two numbers Meta keeps about your WhatsApp number: a **quality rating** and a
**messaging limit tier**. They are related but not the same thing, and confusing them wastes effort.

## Quality rating

Green, yellow or red. It is a rolling judgement based on **how recipients react** — blocking the number,
reporting it, or simply never replying. It is not about your templates being approved, your server, or how many
messages you send.

Yellow and red are treated as risky here: Lynomia Chat records the transition in the operator log so a drop is
visible after the fact rather than discovered later.

| Rating | What it means in practice |
|---|---|
| Green | nothing to do |
| **Yellow** | enough negative signal to be noticed. Still sending. This is the moment to act |
| **Red** | sustained negative signal. A messaging limit cut usually follows |

## Messaging limit tier

How many **unique customers you may start a conversation with** in a rolling 24 hours — not how many messages you
may send. Replying inside the [24-hour window](the-whatsapp-24-hour-window) does not count against it.

Tiers go up on their own when you send consistently at quality, and down when the rating is red. Hitting the
ceiling shows up as *Rate limited* on the number's status — see
[what the number's status means](whatsapp-number-status).

## What actually improves both

Only one thing, in the end: **send messages people want.**

- **Send to people who asked.** An [audience](shared-audiences) built from customers who opted in behaves
  completely differently from one built from every contact you have.
- **Send less, and less often.** The commonest cause of a yellow rating is the same list receiving the same kind
  of promotion repeatedly. It is also what produces
  [error 131049](whatsapp-error-131049).
- **Make it obvious who you are** in the first line. A message that reads as unexpected gets blocked.
- **Answer replies.** A number that only broadcasts collects worse signal than one that holds conversations.

What does **not** help: resubmitting templates, reconnecting the number, changing the display name, or sending
the same campaign again to the people it failed for.

## A worked example

A clinic's rating goes yellow a week after it starts sending a weekly offer to its whole contact list. It stops
the weekly send, keeps appointment reminders — which are about one transaction and go to people expecting them —
and sends nothing promotional for a fortnight. The rating returns to green and the tier is untouched, because it
never reached red.

## Who can do this

**Administrators** read Account Health and run campaigns. Agents can see neither.

## Limits

- **Neither number can be changed from here, or by support.** Both are Meta's.
- **There is no history** in Lynomia Chat. Account Health shows Meta's latest answer.
- **No alert fires** when the rating drops or the tier is cut.
- **A tier increase is not something you can request** in the product.
- **The rating is per number**, so a second number does not inherit a good one — and splitting marketing onto a
  separate number to protect the main one is a decision to make deliberately, not a trick that removes the cap.

## Related

- [What the number's status means](whatsapp-number-status)
- [Error 131049](whatsapp-error-131049)
- [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)
- [WhatsApp campaigns](whatsapp-campaigns)
