---
title: Live chat campaigns
description: You will have a message that opens itself in the live chat widget after someone has been on a page for a while, and you will know every condition that has to be true before it appears.
position: 40
tags: [campaigns, livechat]
seo_description: "Live chat campaigns in Lynomia Chat: a proactive widget message triggered by URL and time on page, business-hours gating, and why a returning visitor never sees one."
---
A live chat campaign is a message the **live chat widget** shows a visitor by itself. You pick a page, say how
long someone has to be on it, and write what appears. Nobody sends it; the widget decides, in the visitor's
browser.

It is the only campaign type in Lynomia Chat that is *reactive* — it waits for behaviour rather than going out
to a list. [WhatsApp campaigns](whatsapp-campaigns) and SMS campaigns are the opposite: you choose the
recipients and the time.

Find it at **Campaigns → Live chat**.

## When to use it

When a page has a predictable question. Someone on the checkout page for ninety seconds has hit a problem;
someone on the shipping-policy page for two minutes did not find their answer. A proactive line at that moment
is worth ten replies afterwards.

## When not to use it

- **To reach a list of customers.** It cannot. A live chat campaign has no audience and no recipients — it
  reaches whoever happens to be on the page. For a chosen group, use [WhatsApp campaigns](whatsapp-campaigns)
  and [shared audiences](shared-audiences).
- **To reach existing customers in conversation.** A visitor who already has a conversation in that inbox will
  never be shown one. See the conditions below.
- **On WhatsApp.** It only works on a **website** inbox, because the widget is the thing that shows it.
- **To follow up after something happened.** That is an [automation rule](automation-rules) or a
  [flow](flow-builder) — see [campaigns or automation?](campaigns-or-automation).

## What you need first

- An **administrator** account. Every page under Campaigns is administrator-only.
- A **website inbox** with the widget installed on the pages you want to target — see
  [set up an inbox](set-up-an-inbox).
- Campaigns enabled for your account. Without it the Campaigns section is absent.
- If you want business-hours gating, **business hours configured on that inbox**. With no business hours set,
  the gate has nothing to consult.

## Steps

1. Go to **Campaigns → Live chat** and choose **Create campaign**.
2. **Title** — for you, in the campaign list. The visitor never sees it.
3. **Message** — what the visitor sees. This is the whole campaign.
4. **Select Inbox** — a website inbox.
5. **Sent by** — an agent from that inbox, or **Bot**. This is the name and avatar on the message.
6. **URL** — the page or pages it applies to. It must be a full `http://` or `https://` address.
7. **Time on page (Seconds)** — how long the visitor must have been there. The default is 10.
8. **Other preferences** — **Enable campaign**, and optionally **Trigger only during business hours**.
9. **Create.**

A campaign is live the moment it is enabled. There is no scheduling, no start date and no end date: it is on
until you disable or delete it.

## Every condition that has to be true

A live chat campaign is the most conditional thing in the product, and almost every "it did not fire" is one of
these:

| Condition | Why |
|---|---|
| The campaign is **enabled** | a disabled campaign is not sent to the widget at all |
| Campaigns are enabled for the account | the widget is told there are none otherwise |
| The **current page matches the URL** | pattern-matched, see below |
| It is **within business hours**, if that box is ticked | checked in the visitor's browser against the inbox's hours |
| The visitor has been on the page for the **full time on page** | the timer restarts whenever the page changes |
| The **widget is closed** | a campaign never interrupts an open widget |
| The visitor has **no messages yet** in this widget session | somebody mid-conversation is left alone |
| The visitor has not **dismissed** a campaign in the last hour | dismissing writes a one-hour cookie that silences every campaign for that browser |
| The contact has **no existing conversation** in that inbox | checked on the server, at the moment the conversation would be created |

That last one is the one that surprises people most: **a returning customer who has ever talked to you through
that widget will not be shown a live chat campaign.** It is a tool for strangers.

## How the URL is matched

The URL is a **pattern**, not a literal string, so one campaign can cover a section of your site. A pattern
ending in a slash is treated as "this page and anything below it", including query strings and fragments.

Two practical consequences:

- `https://example.com/checkout/` covers `/checkout/payment` and `/checkout?step=2`.
- `https://example.com/checkout` covers that one page.

Query strings and fragments are part of the address the pattern is tested against, so a campaign scoped to a
clean path still fires for a visitor who arrived with tracking parameters, provided the pattern allows for
them.

## What happens when it fires

The message appears in the widget as an unread message from the sender you chose. Nothing exists on your side
yet — no contact, no conversation, no record.

**If the visitor engages**, the conversation is created at that moment: the campaign's message becomes its
first message, from your chosen sender, and the conversation records which campaign started it.

**If the visitor ignores or dismisses it**, nothing is created and nothing is counted. A dismissal silences
every campaign in that browser for an hour, via a cookie — so clearing cookies resets it, and so does testing
in a fresh private window.

## Timing, and the hour that confuses people

The widget fetches the campaign list once and **caches it in the visitor's browser for an hour**. An edit you
make now reaches a visitor who loaded your page five minutes ago only after that cache expires.

So when you change a message and it does not change in your own browser, you are usually looking at your own
cache, not a bug. Test in a fresh private window.

## A worked example

A Kuwait retailer finds that visitors abandon the delivery-options page. An administrator creates a live chat
campaign on the website inbox: URL `https://shop.example.com/delivery/`, time on page **45** seconds, sent by
**Bot**, message *"Delivery questions? We answer in a minute — just ask."*, business hours **on**.

During opening hours, a visitor who lingers 45 seconds on any delivery page sees the line. Most ignore it. The
ones who reply become conversations in the website inbox, each carrying the campaign that started it. Outside
opening hours nothing appears, because nobody is there to answer.

## Who can do this

Administrators only. The custom role permission list has no entry for campaigns, so this cannot be delegated —
see [roles and permissions](roles-and-permissions).

## Limits

- **Website inboxes only.** The inbox picker offers no other type.
- **No audience, no segmentation, no personalisation.** One message, the same for everybody who matches.
- **No schedule.** Enabled or disabled; that is the whole lifecycle.
- **One message.** A campaign is not a sequence, and there is no follow-up.
- **Never shown to a visitor who already has a conversation** in that inbox.
- **No per-visitor frequency control** beyond the one-hour dismissal cookie, which the visitor controls, not
  you.
- **Business-hours gating depends on the inbox having business hours.** Without them the condition has nothing
  to check.
- **No delivery report.** There is no count of how many visitors were shown a campaign — only the
  conversations that resulted, each carrying its campaign.
- **A failure is silent.** If the conversation cannot be created, the visitor sees nothing more and nothing is
  reported to you.
- **The list is cached in the visitor's browser for an hour** after it is fetched.

## Related

- [WhatsApp campaigns](whatsapp-campaigns) · [Campaigns or automation?](campaigns-or-automation)
- [Shared audiences](shared-audiences) · [Labels or shared audiences?](labels-or-shared-audiences)
- [Set up an inbox](set-up-an-inbox)
- [Automation rules](automation-rules) · [Flow builder](flow-builder)

## If it does not work

**Nothing appears on the page.** Walk the condition table above in order. The three most common are: the
campaign is not enabled, the widget is open in your test window, or you already have a conversation in that
inbox from an earlier test. Use a fresh private window with no prior conversation.

**It fired yesterday and not today.** Business-hours gating is on and you are testing outside hours.

**My edit has not taken effect.** The visitor's browser is holding the old list for up to an hour. Test in a
fresh private window.

**The URL does not match what I expected.** It is a pattern. A trailing slash widens it to everything below;
no trailing slash limits it to that one page.

**It appeared but no conversation was created.** The visitor did not engage, or dismissed it. Nothing is
recorded in either case.

**Campaigns is not in the sidebar.** Campaigns are not enabled for your account, or you are not an
administrator.
