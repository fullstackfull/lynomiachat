---
title: SLA policies
description: The first-response and resolution times a case is held to, and what "breached" actually counts.
position: 20
tags: [support, sla]
seo_description: Creating SLA policies for support cases in Lynomia Chat, business-hours counting, and what the breach figures mean.
---
An SLA policy is a promise with a clock: answer within this long, finish within that long. Attach one to a
case and the product measures both, and says when a target was missed.

## Creating one

**Settings → Support SLA policies → New policy.**

| Field | What it does |
|---|---|
| **Name** | what you will pick it by — "Standard support", "Priority customers" |
| **Description** | who it is for and why these targets |
| **First response within** | how long until somebody answers |
| **Resolved within** | how long until it is finished |
| **Count business hours only** | whether the clock stops outside opening hours |

Enter each target in whatever unit reads naturally; it is stored in seconds. **Leave a target at zero to
let the policy govern the other one only** — a policy that cares about resolution and not about first
response is a legitimate policy, not a half-finished one.

### Business hours

With **Count business hours only** on, the clock runs only during the business hours set on the inbox the
case belongs to. A case opened at 6pm on Friday with a four-hour first-response target is due at 11am on
Monday, not at 10pm on Friday.

This depends on business hours actually being set on that channel. If they are not, there are no closed
hours to subtract.

## Attaching one

A policy is chosen when a case is opened, and can be changed afterwards. **A case has no SLA until a policy
is attached**, and every SLA figure for that case starts from that moment — not from when the case was
opened.

That has a consequence worth stating plainly: **a zero breach count does not mean nothing was late.** It
means nothing with a policy attached was late. The analytics screen says so in its own small print, and it
is the first thing to check when the numbers look too good.

## What the states mean

| State | Means |
|---|---|
| **On time so far** | neither target has been missed yet |
| **Target missed** | a target was missed; the case carries that permanently |
| **Overdue** | the resolution time has passed and the case is still active |
| **Clock paused** | the clock is not running — the case is waiting on the customer |
| **Closed on time** | the case finished inside its targets |

**Target missed is permanent.** A case that misses its first response and is then resolved quickly keeps
the miss: the customer waited, and hiding it afterwards would make the measure useless.

## Limits

- **One policy per case.**
- **No automatic attachment.** Nothing attaches a policy for you; a case opened without one is unmeasured.
- **Deleting a policy** does not retrospectively change what was already recorded.
- **Business-hours counting needs business hours** on the relevant channel.

## Who can do this

Administrators create and edit policies. Agents choose one when opening a case.

## Related

- [Support cases](support-cases)
- [Support case analytics](support-case-analytics)
- [Set up an inbox](set-up-an-inbox)
