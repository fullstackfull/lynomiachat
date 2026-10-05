---
title: Bulk actions on contacts
description: Act on many contacts at once — including every contact matching the view you are looking at, not only the ones on screen.
position: 40
tags: [contacts]
seo_description: Selecting many contacts in Lynomia Chat, labelling or deleting them in one action, and acting on every contact matching a filter.
---
A bulk action is one instruction applied to many contacts. Lynomia Chat offers three: add labels, remove
labels, and delete. They all work the same way, and the interesting part is not the buttons — it is what
"many" is allowed to mean.

## Two kinds of selection

The contacts list shows fifteen rows at a time, so there are two different things you might mean by "all of
them".

| | What it selects | How you get it |
|---|---|---|
| **Rows** | the contacts you ticked | tick them, or **Select all (15)** for the page |
| **The whole view** | every contact the current view matches, however many pages that is | tick everything on the page, then **Select all N in this view** |

The second option only appears once the page itself is exhausted and the view has more rows beyond it, because
until then the two mean the same thing. Once it is on, the bar stops counting rows and reads **All N
selected**. Touching any individual checkbox turns it back off — a hand-made change to the selection is no
longer "everything this view matches".

A row selection survives paging, so you can also build one up across several pages by hand.

## The views you can act on as a whole

Whichever view you are in is the view that gets acted on:

- the contacts list, on its own or narrowed to one label
- a search
- the **Active contacts** list
- a filter you have applied, or a saved [shared audience](shared-audiences)

The resolution happens on the server, from the same description the list was built from, so the contacts acted
on are the contacts the list was showing. This is also why a whole-view action is not available until you have
scrolled to the bottom of the page: only the server can enumerate the rows your browser does not have.

On a search, Lynomia Chat sometimes cannot say how many results there are without a slow count, and in that
case the button reads **Select all results in this view** with no number. It still acts on all of them. A
missing number is honest, not a failure.

## What you can do

| Action | Who | Notes |
|---|---|---|
| **Assign Labels** | any agent | Additive. Existing labels on the contact are kept. The label must already exist in the account. |
| **Remove Labels** | any agent | Subtractive. Labels the contact does not carry are ignored. |
| **Delete** | administrator | Permanent, and takes the contacts' conversations with them. |

The Remove menu lists every label in the account rather than only the ones your selection carries, so you may
see labels that do nothing when removed. That is harmless.

## Steps

1. Open the contacts list and get to the set you want: search, apply a filter, or open a label or audience.
2. Tick the rows, or tick the page and then **Select all N in this view**.
3. Choose an action in the bar that appears.
4. Wait. The action is queued and the list refreshes once it has actually run, so the rows you see afterwards
   are the result and not a stale copy.

## A worked example

You want every customer in Hawalli who has bought from you to carry the label `hawalli`, so you can message
them when a branch opens there.

1. In the contacts list, apply a filter: city is Hawalli.
2. Tick the checkbox at the top of the page. The bar says **15 selected**.
3. **Select all 412 in this view**. The bar now says **All 412 selected**.
4. **Assign Labels → hawalli**.
5. Open **Contacts → Tagged with → hawalli** to confirm, and use it as a campaign's recipients from there.

Note what step 4 did: it put the label on the **contacts**, which is what a campaign reads. Labelling
conversations would not have worked — see [labels](labels).

## Limits

- **10,000 contacts per action.** A view matching more than that is refused outright and nothing is queued. An
  action that silently did a quarter of the job would be worse than one that did nothing. Narrow the view, or
  work through it page by page.
- **Only labels and deletion.** There is no bulk edit of names, phone numbers, [custom
  attributes](custom-attributes) or the blocked flag, and no bulk "add to an audience". To change field values
  in bulk, export the contacts, edit the file and [import](import-contacts) it back.
- **No partial-failure report.** If one contact in a selection cannot be saved, it is skipped quietly. The
  action reports success for the batch.
- **Bulk actions are not recorded in the audit log**, and neither is any other change to a contact.
- **Deletion cannot be undone**, and unlike deleting a single contact it does not stop for a contact who is
  currently online.
- Export is a separate action in the page header, not part of this bar. It exports the view you are looking at,
  is administrator-only, and arrives by email.

## Related

- [Contacts](contacts)
- [Labels](labels)
- [Import contacts](import-contacts)
- [Shared audiences](shared-audiences)
- [WhatsApp campaigns](whatsapp-campaigns)

## If it does not work

**"Select all N in this view" is not offered.** Either every row of the view is already on the page — in which
case the page selection is the whole view — or you have not selected the whole page yet. It appears only once
every visible row is ticked.

**The message says the view has too many contacts.** It matches more than 10,000. Add a condition to the
filter and try again; nothing was changed.

**The labels menu will not accept a label.** Labels have to exist in the account before they can be assigned.
Create it in Settings first.

**Delete is missing from the bar.** You are signed in as an agent. Deleting contacts is an administrator
action.

**I removed a label and the contacts still show it.** Check which label. Contact labels and conversation
labels are stored separately, and this bar only touches contact labels.
