---
title: Reports
description: How the team is doing — volume, response times, resolutions — by agent, channel, label and team, with the raw records behind every bar.
position: 70
tags: [reports]
seo_description: The Reports screens in Lynomia Chat — Overview, Conversations, CSAT, Agents, Inboxes, Labels and Teams — and how to read each one.
---
Reports answer questions about the **team**: who handled how much, how quickly, and how it compares.

![The Reports overview, with the live counters and a week of conversation traffic](media:analytics/reports-overview-en.png)

## The screens

| Screen | What it is for |
|---|---|
| **Overview** | a live snapshot plus traffic and resolution heatmaps |
| **Conversations** | the core metrics over time, with a drill-down to the records |
| **CSAT** | every customer rating, as a table you can filter |
| **Agents** | the same metrics per agent, with a page per person |
| **Inboxes** | the same metrics per channel |
| **Labels** | the same metrics per label |
| **Teams** | the same metrics per team |

Every one of them takes a date range — last 7, 14 or 30 days, this or last month, the last 3, 6 or 12
months, or a custom range — and most take a grouping: day, week, month or year.

## Overview

Two different kinds of number share this screen, and it is worth knowing which is which.

**The Live row is now.** Open, Unattended, Unassigned, Pending. These are counts at this moment and they
ignore the date range completely. **Unattended** is the one to watch: a conversation nobody has answered
yet, or one where the customer is still waiting.

**The heatmaps are history.** Conversation Traffic and Resolutions, by day of the week and hour of the day,
over the range you chose. They are where staffing decisions come from: the busiest hours are rarely the
ones people assume, and the gap between the traffic map and the resolution map is where the queue builds.

## Conversations

The headline metrics over time:

- **Conversations**, **Messages received**, **Messages sent** — totals
- **First Response Time**, **Resolution Time**, **Customer waiting time** — averages
- **Resolution Count** — a total

Each average tells you how many conversations it was computed from. An average first response time
calculated from four conversations is not a measurement of your service, and the screen says so rather than
letting you quote it.

**Click a bar to see the records behind it.** The drill-down lists the actual conversations or messages in
that bucket — which turns "Tuesday looks wrong" into "these are the eleven conversations on Tuesday".
Drill-down is for administrators only.

### Business hours

There is a **Business Hours** switch on this screen. With it on, response and resolution times count only
the hours your channels are open. A conversation that arrived at 7pm and was answered at 9am is a fourteen
hour wait on the clock and a few minutes of your working day. Which number is fair depends on what you are
asking; keep the setting consistent when you compare two periods.

## Agents, Inboxes, Labels, Teams

The same metrics sliced four ways, each with an overview table and a page per row. Each can be downloaded
as a CSV.

The useful comparison is rarely the ranking. It is the **shape**: an agent with a high conversation count
and a high resolution time is probably picking up everything and finishing nothing; a channel with a slow
first response is usually one nobody has made a habit of watching.

## CSAT

Every rating a customer left, with the agent, the channel, the conversation and the comment. Filter by
agent, inbox, team or rating, and download it.

CSAT only exists where you switched the survey on, per channel, and only for conversations that were
resolved. See [Ask customers how you did](csat).

## Bot reports

Where you run an agent bot, this screen shows how many conversations it handled, how many it resolved
itself, and how often it handed over. The handoff rate is the honest measure of a bot: a bot that resolves
nothing but routes correctly is useful, and a bot with a high resolution rate and angry follow-up
conversations is not.

## Limits

- **Reports are account-wide.** They are not filtered to what you personally can see.
- **Averages do not show the tail.** Use the drill-down to find the conversations that dragged a figure.
- **"Not enough data" is a real answer.** A chart that refuses to draw is refusing to imply a trend from
  three points.

## Who can see this

Administrators. The drill-down into individual records is administrators only as well.

## Related

- [Analytics and Reports — which is which](analytics-and-reports)
- [Analytics overview](analytics-overview)
- [Ask customers how you did](csat)
- [Assign and prioritise](assign-and-prioritise)
