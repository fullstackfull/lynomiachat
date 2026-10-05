---
title: Assign and prioritise
description: Give a conversation an owner — a person or a team — let Lynomia Chat do it for you, and mark what matters most.
position: 20
tags: [conversations]
seo_description: Assigning conversations to an agent or a team, how auto-assignment picks, and what priority actually does.
---
An unassigned conversation belongs to everybody, which in practice means nobody. Assignment is how a
conversation gets exactly one owner.

## Two kinds of owner

A conversation can carry an **agent**, a **team**, or both. They answer different questions.

| | What it says | Where it shows |
|---|---|---|
| **Agent** | "this specific person is replying" | the Mine tab, their notifications |
| **Team** | "this group owns the question" | the team view in the sidebar |

They interact in one way that surprises people. **Assigning a team removes an assignee who is not in that
team.** The conversation has moved to a different group, so the previous owner stops being the owner. If the team
has auto-assignment switched on, Lynomia Chat then picks one of its members; if not, the conversation sits
unassigned inside the team until someone takes it.

You can only assign an agent who is a member of that channel, or an administrator. Someone outside the channel
cannot be given the conversation at all, and nothing is assigned.

## Letting Lynomia Chat assign

Each channel has an **auto-assignment** switch, set by an administrator in the channel's settings. With it on,
new conversations are handed out without anyone intervening.

The default behaviour is deliberately plain:

- Only agents whose availability is **online** are considered. An agent set to busy or offline gets nothing.
- Conversations go out **oldest first**.
- Agents are picked **in turn** — round robin.
- An agent receives at most **five** new conversations from one channel in any five minutes. This stops one
  person absorbing a burst.
- Conversations with no activity for more than **seven days** are left alone, so an old backlog does not land on
  whoever happens to be online today.
- If the conversation already has a team, only that team's members are considered — and only if that team allows
  auto-assignment.

An administrator can replace these defaults with an **assignment policy** on a channel: oldest-first or
longest-waiting, round robin or balanced across current load, and different fair-distribution numbers. Assignment
policies are a paid capability and the screen is hidden unless advanced assignment is enabled for your account.
Without it you get the defaults above, which are enough for most teams.

## What priority is, and is not

Priority has five values: none, low, medium, high and urgent.

Priority is a **marker**, not a mechanism. Setting a conversation to urgent does not move it up the
auto-assignment queue, does not notify anyone extra, and does not start any clock. What it does:

- you can sort the conversation list by priority, highest or lowest first;
- you can filter and save a folder on it;
- [automation rules](automation-rules) can read it as a condition and set it as an action;
- a [macro](macros) can set it.

That makes it genuinely useful — as long as somebody is actually looking at the urgent queue. A priority nobody
sorts by is decoration.

## Steps

1. Open the conversation.
2. In the panel beside it, pick an **agent**, a **team**, or both.
3. Set a **priority** if this one is not ordinary.

To do several at once, tick the conversations in the list and use the bar that appears: assign an agent, assign a
team, change status, snooze, add or remove labels.

## A worked example

A customer messages about a damaged delivery. It is not a question you can answer, and it needs a decision today.

1. Set priority to **high**.
2. Assign the **returns** team. Your own assignment is cleared, because you are not in that team.
3. Add a private note saying what the customer sent you.

The returns team's view now shows it, sorted above their ordinary work if they sort by priority.

## Who can do this

Any **agent** can assign a conversation they can see — including to themselves — and change its priority. Only an
**administrator** can switch auto-assignment on for a channel, create teams, or create an assignment policy. See
[roles and permissions](roles-and-permissions) and [teams and agents](teams-and-agents).

## Limits

- **Auto-assignment needs somebody online.** If no agent on the channel is online when a conversation arrives, it
  stays unassigned.
- Without an assignment policy, assignment runs when something happens on the channel — a conversation is
  created, opened, resolved or snoozed. There is no separate sweep. A conversation that found nobody online waits
  for the next such event in that channel.
- **Balanced distribution is only honoured when advanced assignment is enabled.** A policy set to balanced falls
  back to round robin without it.
- **Priority cannot be changed in bulk.** The bulk bar covers status, snooze, agent, team and labels only.
- Assigning a bot to a conversation sets it to **pending** and clears the human assignee. That is a handover, not
  a shared ownership.

## Related

- [Work in the inbox](work-in-the-inbox)
- [Teams and agents](teams-and-agents)
- [Macros](macros)
- [Automation rules](automation-rules)
- [Macros or automation?](macros-or-automation)

## If it does not work

**I assigned a team and lost the conversation from my Mine tab.** Expected: the team is not one you are in, so
your assignment was cleared. Assign yourself again after the team if you want to keep it.

**Auto-assignment is on but nothing is being assigned.** Check, in order: is at least one agent on that channel
set to online; are the waiting conversations older than seven days; has one agent already taken five in the last
five minutes; if the conversations have a team, does that team allow auto-assignment.

**I cannot find a colleague in the assignee list.** They are not a member of that channel. An administrator adds
them in the channel's settings.
