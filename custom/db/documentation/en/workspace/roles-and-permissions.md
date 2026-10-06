---
title: Roles and permissions
description: You will know what an administrator can do that an agent cannot, the exact seven permissions a custom role is built from, and what cannot be delegated at all.
position: 30
tags: [workspace, roles]
seo_description: Administrator versus agent in Lynomia Chat, the exact custom role permission list, and the settings that stay administrator-only.
---
Every person in your account has exactly one role. There are two built-in roles — **administrator** and **agent** —
and, on paid plans, **custom roles** you define yourself. You choose one of the three when you add the person; they
do not stack.

## Administrator and agent

| | Administrator | Agent |
|---|---|---|
| Settings and billing | all of them | none |
| Conversations | every conversation in every inbox, without being a collaborator | only inboxes they are a collaborator on |
| Contacts, canned responses, macros | yes | yes |
| Reports | yes | no |
| Help centre articles | can write them | cannot write them, but can search them from the reply box |

The important line is the second one. An administrator sees everything without being added anywhere. An agent sees
only what inbox membership gives them, which is why [Set up an inbox](set-up-an-inbox) matters as much as the role
does.

## Custom roles

A custom role is an **agent** with a chosen subset of permissions. The list is fixed — you pick from it, you cannot
extend it. These are the seven options, named as the product names them:

| Permission | What it grants |
|---|---|
| Manage all conversations | every conversation in the inboxes they are a collaborator on |
| Manage unassigned conversations and those assigned to them | the unassigned queue, plus their own |
| Manage participating conversations and those assigned to them | their own, plus ones they are a participant in |
| Manage contacts | contacts |
| Manage reports | reports, including satisfaction responses |
| Manage knowledge base | help centre articles, categories and settings |
| Manage store orders (status changes, resend store emails) | the order actions short of cancelling and refunding |

The three conversation permissions are a **hierarchy, not a set**. The widest one you grant wins, so granting all
three is the same as granting the first. A custom role with **no** conversation permission sees no conversations at
all — a legitimate choice for a bookkeeper, but easy to do by accident.

Two permissions stop short of where people expect:

- **Manage knowledge base** covers writing articles and changing a help centre's settings. It does not cover
  **creating** a new help centre, **deleting** one, or setting its analytics ids. Those stay with administrators.
- **Manage store orders** covers status changes and resending the store's own emails. **Cancelling and refunding are
  administrator-only and cannot be granted to any custom role.**

## What is not on the list

This is the most useful thing to know before you plan a role. The permission list has **no entry** for:

inboxes and channels · campaigns · WhatsApp templates · flows · automation rules · audiences · labels · custom
attributes · agents and roles themselves · billing · audit logs

Those are administrator-only, with no middle ground. If someone needs to connect a channel, build an automation rule,
submit a WhatsApp template or send a campaign, they have to be an administrator.

## What you need first

An administrator account. Custom roles are a paid capability — on a plan without them the Custom Roles page is not
shown.

## Steps

1. Go to **Settings → Custom Roles** and add a role. Give it a name and a description.
2. Tick the permissions it should carry, picking **one** conversation permission. Save.
3. Go to **Settings → Agents**, open the person, and choose the custom role in place of administrator or agent.
4. Add them as a collaborator on the inboxes they should work in. The role decides what they may do; inbox
   membership decides what they can see.

## A worked example

A retailer in Riyadh wants a part-time staff member who handles the order side of WhatsApp conversations and nothing
else. The role gets **Manage unassigned conversations and those assigned to them** so she can pick work up from the
queue, plus **Manage contacts** and **Manage store orders**. She is added as a collaborator on the WhatsApp inbox
only.

The result: she can take an unassigned conversation, read the customer's record, change an order's status and resend
the store's confirmation email. She cannot refund, cannot see the other inboxes, and cannot see settings.

## Who can do this

Administrators. Creating custom roles, changing anyone's role and managing agents are all administrator jobs.

## Limits

- **One role per person per account.** A custom role replaces the agent role; it is not added on top of
  administrator.
- The permission list is fixed at the seven entries above and cannot be extended.
- **Refunds and cancellations are never delegable.**
- Permissions are account-wide, not per inbox. You cannot grant "manage all conversations, but only in the Sales
  inbox" — restrict that with inbox membership instead.
- There is no read-only role. The narrowest useful role is one of the conversation permissions.

## Related

- [Invite your team](invite-your-team)
- [Teams and agents](teams-and-agents)
- [Set up an inbox](set-up-an-inbox)
- [Your own help centre](your-own-help-centre)

## If it does not work

**A custom role sees no conversations.** It has no conversation permission, or the person is not a collaborator on
any inbox. Both are required.

**The Custom Roles page is not in settings.** Custom roles are not included on your plan, or you are signed in as an
agent.

**Someone with Manage store orders cannot refund, and someone with Manage knowledge base cannot create a help
centre.** Both are the rule, not a fault. Those actions need an administrator.
