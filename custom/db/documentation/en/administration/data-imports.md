---
title: The record of your imports
description: You will know where to see every import this account has run, who started it, how far it got, and exactly which records were skipped and why.
position: 20
tags: [administration, contacts, data]
seo_description: "Settings → Data in Lynomia Chat: the list of imports, who started each one, the stages it passes through, and the skip and error logs you can download."
---
Every import this account has run is listed under **Settings → Data**, newest first. Each row opens a page that
says who started it, how long it took, how many records went in, and — the part worth the trip — which records
did **not**, with a reason for each.

This article is about that record. How to *run* a contact import from a file is
[import contacts](import-contacts); this is what you read afterwards, and what you read when somebody asks
what happened to the twelve rows that never appeared.

## When to use it

- **After an import**, to see what was skipped rather than assuming nothing was.
- **During a long import**, to see which stage it is on.
- **When somebody asks** who brought a list of contacts into the account, and when.
- **When an import appears stuck**, to retry or abandon it.

## When not to use it

- **To get data out.** There is an **Export** tab and it says *Coming soon*. Nothing is exported from this page
  today.
- **As a general audit trail.** Imports are the only thing on this page. For settings changes and sign-ins, see
  [audit logs](audit-logs).
- **To undo an import.** Nothing on this page reverses one. An import is a write, and the records it created
  are ordinary contacts and conversations from then on.

## What you need first

An **administrator** account, and the data-import capability enabled for your account. On an account without
it, **Data** is simply absent from Settings and the pages behind it refuse access.

There is no custom role permission for this, so it cannot be delegated — see
[roles and permissions](roles-and-permissions).

## The list

| Column | What it tells you |
|---|---|
| **Name** | what the import was called when it was started, or *Untitled import* |
| **Type** | contacts, conversations, or both |
| **Status** | where it is, or how it ended |
| **Imported** | how many records have gone in so far |
| **Created** | when it was started |

While an import is running the list **updates itself every five seconds**, and there is a **Refresh** button if
you would rather not wait. A row opens the import's own page.

## The stages

The status is not a simple pass or fail. It walks through the work:

| Status | Meaning |
|---|---|
| **Queued** | accepted, not started yet |
| **Importing contacts** | working through the contacts |
| **Importing conversations** | working through the conversations |
| **Finalizing import** | tidying up at the end |
| **Completed** | finished, nothing skipped |
| **Completed with errors** | finished, and some records did not go in |
| **Failed** | could not finish |
| **Abandoned** | you stopped it, or it was stopped |

**Completed with errors is the status people misread.** It means the import finished *and* records were lost.
Open it and read the logs; do not treat it as a success.

## The import's own page

| | |
|---|---|
| **Source** | where the records came from |
| **Import types** | contacts, conversations, or both |
| **Created** / **Duration** | when it started and how long it took |
| **Started by** | the person who ran it. This is the "who did it" |
| **Import progress** | *N of M imported*, or just *N imported* when the total is not known in advance |
| **Errors** | a record that could not be created, with a code, the object it came from and a message |
| **Skip logs** | a record that was deliberately not created, with its kind, source object and message |

**Errors and skip logs are different things and the page keeps them apart.** An error is a failure; a skip is a
decision — a duplicate, or a record that did not qualify. Both lists download as CSV, which is how you hand
them to whoever owns the source data.

If both are empty the page says so plainly: *No errors recorded* and *No skipped or failed records recorded*.

## Where imports come from

The **New import** panel offers a file, and the support tools your installation has enabled. Whichever you
choose, you pick the **data to import** — contacts, conversations, or both.

**Only one import runs at a time.** Starting a second while one is active is refused with *Wait for the active
import to finish before starting another one*. This is a queue of one, not a queue.

Credentials you paste for a connected source are stored encrypted where your installation has encryption
configured, and are never shown back to you.

## Retry and Abandon

Two actions appear on an import that is still active, and they are narrower than they look.

**Retry** resumes an import that has **stalled** — made no progress for fifteen minutes. It is not a "run it
again" button: on an import that is simply slow, it answers *This import is no longer stalled* and does
nothing. It is also refused when another import of the same kind is already in progress, or when the
credential the import was started with is no longer available.

**Abandon** stops an active import. What was already imported stays; nothing is rolled back. The row keeps its
history and reads **Abandoned** from then on.

Neither action exists on a finished import. A completed, failed or abandoned import is a record, not a job.

## A worked example

An administrator at a Kuwait retailer imports 3,400 contacts and tells the team it is done. A week later
somebody notices a customer is missing.

They open **Settings → Data**, find the import, and see **Completed with errors**. The import's page shows
3,388 imported and twelve in the error list — all twelve with the same message about an unusable phone number.
They download the CSV, send it to the person who produced the file, and re-import the corrected twelve rows.
Nothing was mysterious; it was written down the whole time.

## Who can do this

Administrators only, for all of it — the list, each import's page, the logs, retry and abandon. An agent cannot
see this page at all, and the list is empty rather than partial for anyone else.

## Limits

- **Export does nothing yet.** The tab exists and says so.
- **One import at a time.**
- **Retry only works on a stalled import**, which means fifteen minutes without progress.
- **Nothing undoes an import.** Abandon stops it; it does not reverse what was already written.
- **A skipped record is not retried for you.** Download the CSV and fix it at the source.
- **The page shows imports only.** It is not a general record of changes — that is
  [audit logs](audit-logs).
- **Starting an import is not itself in the audit log**, so this page is the only record that it happened.
- **There is no notification when an import finishes.** You come back and look.

## Related

- [Import contacts](import-contacts) · [Bulk actions](bulk-actions)
- [Contacts](contacts) · [Custom attributes](custom-attributes)
- [Audit logs](audit-logs)
- [Roles and permissions](roles-and-permissions)

## If it does not work

**Data is not in Settings.** The capability is not enabled for your account, or you are not an administrator.
Nothing in your account turns it on.

**The status says Completed with errors and I do not know what is missing.** Open the import and read the
**Errors** and **Skip logs** tables. Download both as CSV.

**Retry says the import is no longer stalled.** It is still working. Stalled means fifteen minutes with no
progress; wait and look again.

**Retry says a credential is unavailable.** The key the import was started with is gone. Start a new import
rather than retrying this one.

**I cannot start an import.** One is already running. Finish it or abandon it first.

**The counts stop moving.** Give it fifteen minutes, then retry. The list refreshes itself every five seconds,
so a frozen count is a real observation and not a stale page.
