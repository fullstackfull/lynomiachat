---
title: WhatsApp templates
description: You will be able to write a WhatsApp template that follows WhatsApp's rules, with variables and sample values, and submit it for review.
position: 40
tags: [whatsapp, templates]
seo_description: "Write WhatsApp templates in Lynomia Chat: UTILITY and MARKETING categories, variables and sample values, buttons, and the starters on offer."
---
A **template** is a message WhatsApp has reviewed in advance. It is the only thing you can send to a customer
outside [the 24-hour window](the-whatsapp-24-hour-window), which makes it the most important thing you will set up
after connecting your number.

Templates live under **Settings → Templates**. They belong to the **WhatsApp Business Account**, not to one inbox:
if two of your numbers are on the same business account, both can send the same template.

Use one for any message you need to *start* rather than answer: an order update, an appointment reminder, a payment
reminder, a follow-up on a conversation that went quiet. Inside the window you do not need one — type the message.

## Two categories, and WhatsApp picks the final one

| Category | For | Note |
|---|---|---|
| **UTILITY** | something that follows from an action the customer took — an order, a booking, an invoice | approved most readily |
| **MARKETING** | offers, announcements, anything promotional | reviewed more strictly, and the usual reason for a rejection |

You choose one; **WhatsApp decides the final category and may change it.** What Lynomia Chat stores afterwards is
WhatsApp's answer, not your request. An AUTHENTICATION template — one-time passcodes — cannot be written here at
all: WhatsApp writes that kind of body itself and needs an Android package name and signature hash, so a template
authored here would be one the product could never send.

## What a template is made of

| Part | Rules |
|---|---|
| **Header** | optional; text, image, video or document. A text header is up to 60 characters and may hold one variable |
| **Message** | required, up to 1024 characters |
| **Footer** | optional, up to 60 characters, and **no variables** |
| **Buttons** | up to ten in total: up to ten quick replies, two website buttons, one call button, one copy-code button. Keep the quick replies next to each other — WhatsApp refuses them scattered among the others |

A website button may hold one variable, and it has to come at the end of the address.

## Variables, and the sample values that are not real

Write a variable as `{{1}}`, `{{2}}` if you chose numbered variables, or `{{order_number}}` if you chose named
ones. Three rules catch most rejections before they happen:

- a variable cannot be the first or last thing in the text;
- two variables cannot sit next to each other — put words between them;
- numbered variables have to run 1, 2, 3 in the order they appear, and named ones have to be unique lowercase
  words.

Each variable then grows its own **sample value** box. These are required, and they are what WhatsApp reads when it
reviews the template. **They are never sent to a customer.** The real value is filled in at send time — by the
agent in the composer, by you when you build a campaign, or by a flow.

For an image, video or document header, WhatsApp wants a sample file rather than text. Upload it in WhatsApp
Manager once and paste the handle it gives you into **Sample media handle**.

## What gets approved

Lynomia Chat checks the structural rules WhatsApp publishes — lengths, component types, variable placement, button
counts and samples — before letting you submit, and shows each problem against the field that caused it. That saves
review cycles, and it is all it does. **Passing those checks is not approval.**
WhatsApp reviews tone, accuracy and whether the content fits the category, and none of that is a rule anyone can
check in advance. In practice, utility messages about a real order get approved quickly; vague promotional copy and
anything that promises what you cannot deliver are where rejections concentrate.

## The starters

The builder offers eight starting points at the top. Each one fills the form with a draft in English or Arabic that
you then edit. **They are not templates, and none of them is approved** — WhatsApp reviews whatever you submit,
exactly as if you had written it from scratch.

| Starter | Category | Carries |
|---|---|---|
| Order shipped | UTILITY | a tracking link button |
| Order delivered | UTILITY | two quick replies |
| Delivery delayed | UTILITY | — |
| Appointment reminder | UTILITY | confirm and reschedule quick replies |
| Payment due | UTILITY | a link to the invoice |
| Back in stock | MARKETING | an unsubscribe footer |
| Support follow-up | UTILITY | — |
| Welcome message | UTILITY | — |

## Steps

1. **Settings → Templates → New template.**
2. Pick the **WhatsApp inbox**. This decides which business account the template is created in.
3. Give it a **name** — lowercase letters, numbers and underscores. It can never be changed.
4. Type the **language code** of the template's own text: `en_US`, `ar`, and so on. Not the language of your
   dashboard, and it can never be changed either.
5. Choose the **category** and whether variables are numbered or named.
6. Write the message, and add a header, footer or buttons if you need them. The preview beside the form redraws as
   you type, using the same renderer that draws real messages.
7. Fill in a **sample value** for every variable.
8. **Save draft.** Nothing has gone to WhatsApp yet. Submit it when you are ready — see
   [the template lifecycle](whatsapp-template-lifecycle).

## A worked example

A clinic wants to confirm bookings. An administrator opens **New template**, chooses the *Appointment reminder*
starter, and edits it to `appointment_reminder_ar` in language `ar`, category UTILITY. The body becomes a sentence
holding the patient's name, the date and the doctor; the samples are a real-looking name, "Sunday 12 October" and
"Dr Al-Harbi". Two quick replies go underneath. Saved, submitted, approved in minutes.

## Who can do this

**Administrators** only, for every part of the templates page. Agents send approved templates from the composer but
cannot see or change the template manager.

## Limits

- **The name and the language can never change** after a template is created. Nothing can rename a template, in
  Lynomia Chat or at WhatsApp.
- **Catalogue, carousel, product-list and limited-time-offer components cannot be written or sent here.** Neither
  can a location header or a call-permission button. Templates using them appear in the list but are managed in
  WhatsApp Manager.
- **A copy-code sample is capped at 15 characters**, stricter than WhatsApp's own limit, because a longer coupon
  would fail at send time.
- **There is no template library from Meta to pick from.** The starters are Lynomia Chat's own.
- **Satisfaction survey templates are read-only here.** They are managed in the relevant inbox's survey settings.
- **On a Twilio inbox, templates are not managed in Lynomia Chat.** The page links out to Twilio.
- **A template's quality rating appears on its detail panel only when WhatsApp reports one.** There is no quality
  dashboard and no health score page.
- Templates refresh from WhatsApp automatically every few hours, and **Sync templates** refreshes them now.

## Related

- [The template lifecycle](whatsapp-template-lifecycle)
- [The WhatsApp 24-hour window](the-whatsapp-24-hour-window)
- [WhatsApp campaigns](whatsapp-campaigns)
- [When WhatsApp does not work](whatsapp-troubleshooting)

## If it does not work

**The page says to connect a WhatsApp inbox.** No WhatsApp channel exists yet. See
[Connect a WhatsApp number](connect-whatsapp).

**It will not let me save.** Read the problems above the fields. The most common are a missing sample value, a
variable at the very start or end of the message, and two variables with nothing between them.

**It says a template with that name already exists.** A name has to be unique per language within one business
account — including a name WhatsApp is still holding from a template you deleted in the last 30 days.

**A part of my template cannot be edited.** It uses a component Lynomia Chat does not author. Manage that one in
WhatsApp Manager.
