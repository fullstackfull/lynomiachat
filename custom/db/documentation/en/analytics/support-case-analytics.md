---
title: Support case analytics
description: How much support work arrived, how much closed, how much came back, and how often a target was missed.
position: 90
tags: [analytics, support]
seo_description: Support case analytics in Lynomia Chat — opened, resolved, reopened, targets missed, and the right-now readings.
---
The **Support cases** tab appears in Analytics only where the support-case module is switched on for your
account. This screen is about cases, not conversations. If you do not use [support cases](support-cases), it will be
empty, and that is correct.

![Support case analytics: the counters, and the note that a zero breach count is not the same as nothing being late](media:analytics/analytics-tickets-en.png)

## The tiles

| Tile | What it counts |
|---|---|
| **Cases opened** | cases opened in this period, however they started |
| **Cases resolved** | cases whose resolution was recorded in this period |
| **Cases reopened** | reopenings recorded in this period |
| **First-response targets missed** | first-response targets recorded as missed |
| **Resolution targets missed** | resolution targets recorded as missed |
| **Average time to resolve** | opening to resolution, over the cases resolved in this period |
| **Open right now** | cases in one of the four active statuses at this moment |
| **Overdue right now** | active cases whose resolution time has already passed |
| **Unassigned right now** | active cases with nobody assigned |

## Three things these numbers do that most do not

**Resolved counts every resolution, not every case.** A case resolved, reopened and resolved again counts
twice. That is work done twice, and it should show.

**Reopened is read from the case history**, not inferred from the current status. A case reopened and
resolved again still counts as a reopening, which is exactly the case a status-based count would lose — and
it is the one you most want to see.

**Average time to resolve is absent when nothing was resolved.** Absent, not zero. A zero would read as
"instant" when it means "no data".

## The SLA caveat

**Only cases with an SLA policy attached can appear in the two "targets missed" figures.** The screen says
so itself when any open case has no policy. A desk where half the cases are unmeasured will show a low
breach count that means nothing.

If you want the breach numbers to be meaningful, attach a policy when the case is opened — see
[SLA policies](sla-policies).

## The right-now row

**Open right now**, **Overdue right now** and **Unassigned right now** ignore the date range. They are
readings taken as you loaded the page, and they are the three to act on today:

- **Overdue right now** — already late.
- **Unassigned right now** — nobody has picked it up.
- **Open right now** against **Cases opened** over a month — whether the pile is growing.

## Related

- [Support cases](support-cases)
- [SLA policies](sla-policies)
- [Analytics and Reports — which is which](analytics-and-reports)
