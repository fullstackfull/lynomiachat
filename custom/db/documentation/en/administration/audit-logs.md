---
title: Audit logs
description: You will know exactly which actions are recorded, which are not, who can read the record, and how long it is kept.
position: 10
tags: [administration, audit]
seo_description: "What the Lynomia Chat audit log records and does not record, who can read it, how IP addresses are shown, and that there is no retention limit."
---
The audit log is a read-only record of **configuration changes and sign-ins**, under
**Settings → Audit Logs**. Each entry says who did what, and when.

It is not a record of work. Replying to a customer, resolving a conversation, labelling it or running a macro
leave no entry. If you want to know what your team did with a conversation, the conversation itself is the record
— see [work in the inbox](work-in-the-inbox).

## What is recorded

The page groups events in four families, and the filter offers exactly these fourteen:

| Group | Events |
|---|---|
| Access | sign-in and sign-out |
| Agents and teams | agents (invited, role changed, availability changed), teams, team members, inbox collaborators |
| Configuration | account settings, inboxes, webhooks, automation rules, macros, audiences, WhatsApp templates |
| Conversations | conversation deletions, message deletions |

Each entry carries the acting user's name and email, the action, the object's id, the time, and — for the
objects that are version-tracked — the attributes that changed.

Two entries surprise people. **An agent switching between online, offline and busy is recorded**, which makes
Agents the noisiest family by far. And a **template submission to Meta is recorded as a template update**,
because that is what it is here — see [the template lifecycle](whatsapp-template-lifecycle).

## What is not recorded

This is the more useful list. Nothing below leaves an entry:

- Reading anything. There is no record of who opened a conversation, a contact or a report.
- Messages sent, conversations assigned, resolved, snoozed or labelled, macros run.
- Contacts created, edited, merged or deleted; [imports](import-contacts) and
  [bulk actions](bulk-actions).
- Campaigns — created, edited or sent. See [WhatsApp campaigns](whatsapp-campaigns).
- Canned responses, custom attributes, help centre articles, custom roles.
- Commerce store connections and order actions, and flow changes, are written to the same table, but the page has
  no label or filter for them, so they appear in the list **without a description**.

## IP address and location

By default the last part of each IP address is masked, and a **Location** column shows a city and country where
your installation looks those up. On installations with the extra IP-address feature enabled, the column shows
the full address instead. There is no setting for this inside your account.

## Who can read it

**Administrators only**, and only where the feature is enabled. Audit logs are a paid capability and are off by
default, so on many accounts the page is simply absent. The permission list for custom roles has no entry for
audit logs, so this cannot be delegated — see [roles and permissions](roles-and-permissions).

Entries are still **written** while the feature is off. Switching it on later reveals the history that
accumulated in the meantime.

## How long it is kept

Indefinitely. There is no retention setting, no age limit, and no scheduled job that deletes entries. Nobody —
including an administrator — can edit or delete one from the product.

## A worked example

A WhatsApp number stops receiving on a Thursday. An administrator opens **Settings → Audit Logs**, filters to
**Inboxes**, and sets the date range to the last two days. One entry shows a colleague updated that inbox on
Wednesday evening. The entry lists the attributes that changed, which is enough to know what to put back. The
conversations lost while the inbox was misconfigured are not in the audit log and are not recoverable — see
[when WhatsApp does not work](whatsapp-troubleshooting).

## Steps

1. Go to **Settings → Audit Logs**.
2. Narrow by event type, by date range, or by searching for a person's name or email. Search needs at least
   three characters.
3. Sort newest or oldest first. The list is paginated at 25 entries a page.

## Limits

- **No export.** No CSV, no download, no export button. What you can do is read, filter and page through entries
  in the browser.
- **One event type at a time** in the filter.
- **You cannot search by object.** Search matches the acting user's name, username or email, not an inbox name or
  a conversation id.
- **Deleted messages show no content.** The deletion is recorded; the text is deliberately withheld from the
  list.
- **A conversation deletion records only that it happened**, not the conversation's contents.
- **A deleted user's entries remain**, shown by the email recorded at the time, so an entry can name somebody who
  no longer has an account.
- **The log answers "what changed", not "why".** There are no comments or annotations.

## Related

- [Roles and permissions](roles-and-permissions)
- [Teams and agents](teams-and-agents)
- [Set up an inbox](set-up-an-inbox)
- [When something is not working](troubleshooting)

## If it does not work

**Audit Logs is not in Settings.** Either you are not an administrator, or the feature is not enabled for your
account or your installation.

**The page is empty.** No recorded event has happened yet in the range you are looking at. Clear the filters
first — a date range and an event type both narrow the list.

**Some entries have no description.** Those are the Commerce and flow events mentioned above. The entry is real;
the page has no sentence for it.

**The action I need to prove is not there.** Check the "what is not recorded" list before concluding something
was hidden. Most day-to-day work is deliberately not audited.
