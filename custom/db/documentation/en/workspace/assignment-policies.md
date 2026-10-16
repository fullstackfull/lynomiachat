---
title: Assignment policies
description: "Decide how conversations are handed out: in turn, oldest first, with a cap, and per channel."
position: 50
tags: [workspace, assignment]
seo_description: Assignment policies in Lynomia Chat — round robin, assignment priority, fair distribution and stale conversations.
---
Auto-assignment on a channel hands new conversations out without anyone intervening. An **assignment
policy** is how you control the way it does that, and you attach one policy to one or more channels.

**Settings → Agent assignment → Assignment policy.**

## What a policy decides

| Setting | Choices | What it means |
|---|---|---|
| **Assignment order** | Round robin, Balanced | in turn, or by who has room |
| **Assignment priority** | Earliest created, Longest waiting | which conversation goes out next |
| **Fair distribution** | a number and a time window | the most any one agent can be given in that window |
| **Skip stale conversations** | an age, or off | unassigned conversations older than this are left alone |
| **Added inboxes** | channels | which channels this policy governs |

**One policy per channel.** Adding a channel that already belongs to another policy moves it; the product
asks before it does.

### Round robin and Balanced

**Round robin** goes round the online agents in turn. It is predictable and it is the right default.

**Balanced** assigns by available capacity instead — who has room, not whose turn it is. It depends on
agent capacity policies, and **it is a premium feature**: where your plan does not include it, the option
is visible and marked, not hidden.

### Assignment priority

**Earliest created** empties the queue in the order it arrived. **Longest waiting** looks at who has been
waiting for a reply the longest, which is not the same thing: a conversation created this morning and
answered twice has waited less than one created yesterday and never answered.

### Fair distribution

A cap: at most *n* conversations to one agent in every *x* minutes. It defaults to 100 an hour, which is
effectively off; the number to set is the one that stops a burst landing on whoever happens to be online.

### Skip stale conversations

Unassigned conversations older than this are not handed out. It defaults to seven days. Without it, an old
backlog lands on the next person who comes online, which is how a desk punishes the first agent to log in
on a Monday.

## What a policy cannot do

- **It cannot assign to someone who is offline.** Auto-assignment only considers agents whose availability
  is online. Nobody online means nothing is assigned, and conversations wait, visible, in the channel.
- **It cannot assign to a non-member.** An agent who is not a member of the channel is not a candidate.
- **It does not reassign.** A conversation already assigned stays where it is.

## Who can do this

Administrators.

## Related

- [Assign and prioritise](assign-and-prioritise)
- [Teams and agents](teams-and-agents)
- [Set up an inbox](set-up-an-inbox)
