---
title: Support cases
description: Work that needs tracking beyond a single conversation — a title, an owner, a due time, and a history you can read back.
position: 10
tags: [support, cases]
seo_description: Support cases in Lynomia Chat — when to open one, the statuses, the history, and how a case relates to a conversation.
---
**Support cases are a module your installation switches on per account.** Where it is off, there is no
Support cases item in the sidebar and no Support cases tab in Analytics. If you cannot see it and want it,
that is a conversation with your provider, not a setting in your account.

A conversation ends when the customer stops writing. Some work does not: a refund waiting on finance, a bug
waiting on a developer, a delivery waiting on a courier. A **case** is that work — with a subject, an owner,
a due time and a history you can read back weeks later.

![The support case list, filtered to open cases](media:support/support-cases-en.png)

## When to open one

Open a case when the work:

- **outlives the conversation** — the customer will stop writing before it is finished
- **belongs to somebody specific**, who is not necessarily the agent replying
- **needs a due time** of its own
- **needs a record** that someone will read later

Do not open a case for something you will finish in the conversation. A case you close two minutes after
opening is paperwork, and a desk that does it for everything stops reading its own case list.

## Opening one

From **Support cases → Open a case**, or from the **Support cases** panel inside a conversation, which
links the two together.

| Field | What it is for |
|---|---|
| **Subject** | what needs doing |
| **Description** | what has happened so far, and what finished looks like |
| **Category** | technical, billing, account, integration, WhatsApp, commerce, campaign, automation, operational, other |
| **Priority** | low, medium, high, urgent |
| **Assignee** and **Team** | who owns it; both may be left empty |
| **SLA policy** | the targets it is held to — see [SLA policies](sla-policies) |

**A new case always opens**, whoever it is assigned to. You change the status afterwards.

## The six statuses

| Status | Means |
|---|---|
| **Open** | nobody has started |
| **In progress** | somebody is working on it |
| **Waiting on customer** | we are blocked by them |
| **Waiting on us** | we are blocked by someone inside the business |
| **Resolved** | the work is done |
| **Closed** | the case is finished and filed |

The two waiting statuses are the ones that earn their keep. "Waiting on customer" is not your backlog;
"waiting on us" is, and separating them is how a case list stops being a list of things that feel stuck.

## The history

Every change is recorded: status, priority, assignee, team, SLA, and every internal note. It shows who
changed what and when, and changes the product itself made are attributed to Lynomia rather than to a
person.

This is the part that pays off months later, when somebody asks why a refund took three weeks.

## Finding cases

The list has ready-made views — **All**, **My cases**, **Unassigned**, **Overdue**, **Resolved**,
**Closed** — and filters for status, priority, category, assignee, team, SLA state and the dates a case was
opened between. Sort by newest activity, oldest activity, newest, oldest, due soonest, or highest priority.

**Overdue** and **Past its resolution time** are the two to check daily. They are the cases where you have
already missed, or are about to miss, something you promised.

## Cases and conversations

A case can be linked to a conversation, and the conversation shows its cases in a panel. They stay separate
objects on purpose: resolving the conversation does not resolve the case, and closing the case does not
close the conversation.

## Limits

- **A case is not a conversation.** The customer does not see it, is not notified about it, and cannot
  reply to it. Anything they should know has to be said in the conversation.
- **A case has one assignee**, not several.
- **SLA figures only exist from the moment a policy is attached.** A case opened without one and given a
  policy later is measured from then, not from when it opened.

## Who can do this

Agents open, own and work cases. What an agent can see follows the same access rules as the rest of the
product.

## Related

- [SLA policies](sla-policies)
- [Support case analytics](support-case-analytics)
- [Assign and prioritise](assign-and-prioritise)
