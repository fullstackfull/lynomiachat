---
title: Analytics overview
description: How much work arrived, how much was closed, how fast your team answered, and what is still open.
position: 20
tags: [analytics]
seo_description: The Analytics overview screen in Lynomia Chat — every tile, what it counts, and what it deliberately does not count.
---
The Overview is the first Analytics screen and the one to look at daily. It answers four questions: how much
arrived, how much closed, how fast you answered, and what is still open.

![The Analytics overview, with the counters and the conversation series for the selected range](media:analytics/analytics-overview-en.png)

## The tiles

| Tile | What it counts |
|---|---|
| **Conversations started** | conversations opened in this period, on any channel |
| **Conversations resolved** | times a conversation was marked resolved in this period |
| **Conversations reopened** | times a resolved conversation was opened again |
| **Average first response** | how long a customer waited for the first human reply |
| **Average resolution time** | how long a conversation stayed open before it was resolved |
| **Messages received** | customer messages — activity notes and private notes are not counted |
| **Messages sent** | replies to customers, including approved template sends — notes are not counted |
| **Open right now** | conversations open or pending at this moment; snoozed ones are not counted |

Three of these repay a careful read.

**Resolved is an event, not a state.** A conversation resolved, reopened and resolved again counts twice.
That is deliberate: it measures work done, and closing something twice was two pieces of work.

**Reopened is the quality signal.** A desk with a high resolve count and a high reopen count is closing
conversations that were not finished. Watch the ratio rather than either number.

**Open right now ignores your date range.** It is a reading taken when you loaded the page. Looking at last
month and seeing today's open count is not a bug.

## Where the volume sits

Under the tiles, a breakdown shows which channels, teams or labels carry the volume, as a share of the
whole. "Not recorded" is its own row rather than being hidden — a large "Not recorded" share usually means
something is not being labelled, which is worth knowing.

## Reading the series

The chart is the same measure over time, grouped by day, week or month. Three readings are worth making a
habit of:

1. **Started against resolved.** If started is consistently above resolved, the backlog is growing, and no
   amount of speed on individual conversations will fix it.
2. **First response against your promise.** If your website widget says "typically replies in a few
   minutes" and this says hours, one of the two has to change.
3. **The shape of the week.** Where the volume lands tells you when to staff, and it is almost never spread
   evenly.

## Limits

- **Averages hide the tail.** An average first response of eleven minutes is consistent with most customers
  waiting two minutes and a few waiting a day.
- **A reply by an automation or a bot is not a human first response.** First response measures the first
  human reply.
- **Counts are scoped to the account**, not to what you personally can see.

## Who can see this

Administrators. Agents do not have the Analytics screens.

## Related

- [Analytics and Reports — which is which](analytics-and-reports)
- [Reports](reports)
- [Work in the inbox](work-in-the-inbox)
