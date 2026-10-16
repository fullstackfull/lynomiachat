---
title: Analytics and Reports — which is which
description: Two sets of numbers live in Lynomia Chat. This explains what each one answers, so you stop checking the wrong screen.
position: 10
tags: [analytics, reports]
seo_description: The difference between Analytics and Reports in Lynomia Chat, and which screen answers which question.
---
There are two numerical areas in the dashboard, and they are not duplicates.

| | **Analytics** | **Reports** |
|---|---|---|
| In the sidebar | Analytics | Reports |
| Answers | "what happened across the whole product?" | "how is the support team doing?" |
| Covers | conversations, WhatsApp delivery, campaigns, automation, flows, commerce, support cases | conversations, CSAT, agents, channels, labels, teams |
| Groups by | day, week or month, over a date range you choose | a date range you choose |
| Honest about gaps | yes — it says when a number is incomplete and why | no, it shows what it has |

**Use Reports for the team.** Who answered how much, how fast, which channel is busiest, how customers rated
the service.

**Use Analytics for the product.** Whether WhatsApp messages are actually arriving, whether a campaign
reached anyone, whether your flows finish or stall, whether abandoned-cart outreach is going out.

If a question is about **people**, it is a Reports question. If it is about **machinery**, it is an
Analytics question.

## What both share

**A date range.** Every screen has one, and every number on the screen is for that range and nothing else.

**One timezone.** Days, weeks and months are cut in the account's reporting timezone, so two people in two
countries looking at the same account see the same totals for the same dates. That is why a day can look
"wrong" against your own clock: it is the account's day, not yours.

## What Analytics does that Reports does not

### It groups

Day, week or month. The same range grouped by month is four bars instead of a hundred, which is the
difference between a trend and a thicket.

### It tells you when a number cannot be trusted

Under most Analytics screens there is a line of small print. It is not decoration — it is the part of the
screen that keeps the rest honest:

- **"Immediate automation rules: they run inline and record nothing, so they are absent here rather than
  counted as zero."** Automation analytics covers *delayed* rules. Immediate ones leave no trace to count.
- **"Part of this date range: finished episodes are kept for 30 days, so earlier days are incomplete."**
  Ask for a longer range than the data is kept for, and it says so rather than showing you a dip that is
  really a deletion.
- **"SLA breach counts: some open cases have no SLA policy attached, so a zero breach count does not mean
  nothing was late."**

### It says where the number came from

"Computed from source records" or "Served from daily rollups". A rollup is a pre-computed daily total, which
is why a long range loads quickly. When the rollups do not match the source records, the screen falls back
to the source records and tells you it did.

### It separates "over the period" from "right now"

Most tiles count things that happened inside your date range. A few — **Open right now**, **Running now**,
**Overdue right now** — are a reading taken at the moment you looked, and they ignore the date range
entirely. They carry the note "A reading taken now, not a count over the selected dates."

## Related

- [Analytics overview](analytics-overview)
- [WhatsApp delivery](whatsapp-delivery)
- [Campaign performance](campaign-performance)
- [Automation and flow analytics](automation-and-flow-analytics)
- [Commerce analytics](commerce-analytics)
- [Reports](reports)
