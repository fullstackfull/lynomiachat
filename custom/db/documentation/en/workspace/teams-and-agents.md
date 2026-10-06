---
title: Teams and agents
description: You will know the difference between an agent, a team and an inbox member, and exactly what happens to a conversation when you hand it to a team.
position: 20
tags: [workspace, teams]
seo_description: How teams work in Lynomia Chat, how team membership differs from inbox membership, and what assigning a team does to a conversation.
---
An **agent** is a person who answers messages. A **team** is a named group of agents you can hand a conversation to —
Sales, Reception, Deliveries. Teams exist so a question can have an owner before it has a named person.

Three kinds of membership are easy to confuse, and they do different jobs:

| | What it decides |
|---|---|
| **Role** | what a person may do anywhere in the account |
| **Inbox membership** | which conversations they can see at all |
| **Team membership** | which group's queue they appear in, and who can be handed work |

Only inbox membership grants access. A team gives nobody anything they did not already have.

## When to use a team

When the right answer depends on a function rather than a person: a delivery complaint belongs to whoever is handling
deliveries today, not to the agent who happened to read it. A team also keeps a conversation owned while nobody is at
their desk, and keeps the queue visible.

## When not to use a team

Do not use a team as a label for the kind of question. A conversation carries only **one** team, so one that is both
a delivery problem and a refund request has to pick. Use [labels](labels) for that, and the team for who acts. And do
not use a team to control access — use inbox membership and [roles](roles-and-permissions).

## What you need first

An administrator account, and the agents already added. See [Invite your team](invite-your-team).

## Steps

1. Go to **Settings → Teams** and create a team. Give it a name and a short description.
2. Decide whether to tick **Allow auto assign for this team**. This matters most; see below.
3. Add members.
4. Add those same people as collaborators on the inboxes they work in. Team membership does not do this for you.

## What assigning a team actually does

This is the part that surprises people. When you set a team on a conversation:

1. If the current assignee is **not a member of that team**, the assignee is cleared. The conversation has changed
   hands, so the old owner stops being the owner.
2. If the team allows auto-assignment, one member is then picked — but only from people who are **both** members of
   that team **and** collaborators on that inbox, **and** currently online.
3. If the team does not allow auto-assignment, or nobody qualifies, the conversation sits unassigned inside the team
   until someone takes it.

Removing a team from a conversation does not clear the assignee.

A team member who was never added to the inbox is invisible to all of this. They cannot be picked automatically or
chosen by hand: the assignee list is the inbox's collaborators plus the account's administrators.

## Where teams show up elsewhere

- In the sidebar, under Conversations, you see **only the teams you are a member of**, each with its unread count.
- [Automation rules](automation-rules) can read the team as a condition, and can assign a team, remove the assigned
  team, or email a team about a new conversation. A [macro](macros) can assign a team.
- Reports include a per-team view.

## A worked example

A furniture retailer in Jeddah creates two teams: **sales** and **deliveries**. Sales allows auto-assignment — its
three staff are interchangeable and all three are collaborators on the WhatsApp inbox. Deliveries does not, because
one coordinator owns each case and picks work up deliberately.

An agent reads a message about a damaged table and assigns **deliveries**. Her own assignment is cleared, and because
the team does not auto-assign, the conversation waits in the deliveries queue until the coordinator takes it.

## Who can do this

Administrators create, edit and delete teams and manage their membership; the Teams settings page is
administrator-only. Any agent can assign a team to a conversation they can already see.

## Limits

- **A conversation can have one team.** There is no secondary or watching team.
- Team names are stored in **lower case** and must be unique in the account. "Sales" is saved as "sales".
- **Team membership grants no access.** An agent still sees nothing from an inbox they are not a collaborator on.
- Auto-assignment within a team still requires a member to be **online**. A team of offline people behaves like a
  team with auto-assignment switched off.
- Deleting a team does not delete its conversations. They are left with no team and keep their assignee.
- There is no team-level business-hours or escalation behaviour. A conversation left in a team queue stays there
  until someone moves it.

## Related

- [Invite your team](invite-your-team)
- [Roles and permissions](roles-and-permissions)
- [Assign and prioritise](assign-and-prioritise)
- [Set up an inbox](set-up-an-inbox)
- [Automation rules](automation-rules)

## If it does not work

**I assigned a team and the conversation vanished from my own list.** Expected. You are not in that team, so your
assignment was cleared. Assign yourself again after the team if you want to keep it.

**The team allows auto-assignment but nobody is being picked.** Check that at least one member is a collaborator on
that inbox, and that at least one of those is online.

**I cannot find a colleague in the assignee list.** They are not a collaborator on that inbox. Being in the team is
not enough.

**A colleague cannot see the team in their sidebar.** The sidebar lists only your own teams. Add them to it.
