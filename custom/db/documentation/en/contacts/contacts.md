---
title: Contacts
description: What a contact is, how one comes to exist, the three fields that decide whether two records are the same person, and how to merge duplicates.
position: 10
tags: [contacts]
seo_description: "Contacts in Lynomia Chat: how they are created, the phone, email and identifier uniqueness rules, merging duplicates, and blocking."
---
A contact is one person, stored apart from anything they ever said to you. Conversations open and close; the
contact record is what outlives them and carries the history, the [labels](labels), the notes and the
[custom attributes](custom-attributes).

## How a contact comes to exist

| Route | What it does |
|---|---|
| Someone messages you | The channel creates the contact from whatever the provider sent |
| **Add contact** in the contacts list | You type the details yourself |
| [Import contacts](import-contacts) | A CSV file, or a pasted list of phone numbers |

The first route is the one that fills most accounts, and it is worth knowing what it stores. A WhatsApp message
from a number Lynomia Chat has not seen before creates a contact whose phone number is that number and whose
name is the WhatsApp display name. If the provider sent no name, Lynomia Chat generates a placeholder one, so a
list of oddly-named contacts is a sign that names are not arriving, not a sign that something failed.

## The three identities

Three fields decide whether two records are the same person. Each is unique inside your account.

| Field | Uniqueness | Usually set by |
|---|---|---|
| **Phone number** | one contact per number | the channel, the contact form, an import |
| **Email** | one contact per address, upper and lower case treated as the same | the contact form, an import, an email channel |
| **Identifier** | one contact per identifier | your own system, through an import or the API |

Leaving a field empty is always allowed, and empty never collides: any number of contacts may have no email at
all. But a value that is already in use is refused, and you are told which field clashed. When exactly one field
clashed, the dialog finds the contact that already holds it and offers to open it, which is almost always what
you wanted.

The **identifier** is your own key for this person — a membership number, a CRM id. It is the only one of the
three with no field in the contact form, so it arrives through an import or the API.

## Phone numbers are stored in international form

A stored number is a `+`, the country code, then the rest: `+96522201234`. Fifteen digits is the ceiling.

A number that names its own country is understood on its own, and `00` at the front is read as `+`. A **local**
number such as `0551112233` can only be stored if you also say which country it belongs to, using the country
field on the contact. Lynomia Chat will not guess. It does not infer the country from your account language,
your timezone, or the WhatsApp number the message arrived on, because a wrong guess produces a number that looks
right and reaches nobody.

The check is structural: it confirms the shape of an international number, not that the number is in service.

## A contact nobody can reach is not listed

The contacts list shows contacts that have at least one of the three identities. A record with only a name is
stored, but it does not appear — there is no way to message it, so there is nothing to do with it. Imports
report these rows before you commit to them.

## Merging two contacts

Merging is for the case you cannot prevent: the same person reached you twice, once by WhatsApp and once by
email, and you now have two records.

1. Open the record you want to **get rid of**.
2. Go to the **Merge** tab.
3. Search for the record you want to **keep**. That one is the primary contact.
4. Confirm.

Conversations, messages, notes and channel links all move to the primary contact. Where both records hold a
value for the same field, the primary contact's value wins. The record you opened is then deleted.

One thing does not move: **labels**. The record being removed takes its labels with it. If it carries a label
that matters, apply that label to the primary contact before you merge.

## Blocking

**Block contact**, in the header of a contact, is for someone you want to stop hearing from. Once blocked,
inbound WhatsApp messages from that person are dropped rather than queued, any conversation of theirs is set to
resolved and muted, and no notifications are raised.

Blocking governs what comes in. It does not govern what goes out. Nothing filters blocked contacts out of a
campaign, so a blocked person still receives a campaign whose label they carry. Keep them out of the labels you
send to — or build the audience you send to with **blocked is false** as one of its conditions, which is a
filter you can add.

## Who can do this

| Action | Role |
|---|---|
| View, search, create and edit contacts | any agent |
| Apply and remove labels | any agent |
| Merge two contacts | any agent |
| Delete a contact | administrator |
| Import and export | administrator, or an agent whose custom role includes contact management |

## Limits

- Deleting a contact is permanent, deletes its conversations with it, and is refused while that contact is
  online.
- Changes to a contact are not recorded in the account's audit log.
- The contacts list pages fifteen rows at a time, which matters when you are selecting many of them — see
  [bulk actions](bulk-actions).
- Uniqueness is per account. Two accounts on the same installation may both hold the same number, and neither
  can see the other's.

## Related

- [Custom attributes](custom-attributes)
- [Import contacts](import-contacts)
- [Bulk actions on contacts](bulk-actions)
- [Labels](labels)
- [Shared audiences](shared-audiences)

## If it does not work

**"This phone number already belongs to another contact in this account."** The number is in use. The dialog
offers to open the contact that holds it; merge if they really are two records for one person.

**The number will not save and the error mentions a country.** You entered a local number with no country.
Either write it in full international form, or choose the country on the contact.

**I imported contacts and cannot find them in the list.** The rows had no email, phone number or identifier.
They exist, but the list only shows contacts that can be reached.

**A colleague cannot see Import or Export.** Both are administrator actions. On plans with custom roles, an
agent granted contact management also gets them.
