---
title: Import contacts
description: Bring a list of customers in from a CSV file or a pasted list of numbers, see exactly what will happen before it happens, and understand how duplicates are treated.
position: 30
tags: [contacts]
seo_description: "Importing contacts into Lynomia Chat: CSV columns, pasted phone numbers, the preview, duplicate handling and the phone-number rules."
---
An import is how a list that lives somewhere else becomes contacts you can message. It has two entrances — a
CSV file, or phone numbers pasted into a box — and from the moment you press **Continue** they behave
identically, because pasted numbers are turned into a one-column file and run through the same importer.

The part worth knowing before you use it is the preview: it tells you what the import will do, row by row,
without doing any of it.

## When to use it, and when not

Use it when you are moving from another tool, when somebody has handed you a list of numbers for a campaign, or
when you want to relabel many contacts at once — export them, edit the `labels` column, import the file back.
The export includes that column and the importer reads it, so the round trip works.

Do not import to keep a field up to date. An import is a one-off write and will not notice later changes at the
source. Membership that goes stale belongs in a [shared audience](shared-audiences), which is recalculated each
time it is used.

## What you need first

- You must be an **administrator**. On plans with custom roles, an agent granted contact management can import
  too.
- **Any label you want to apply must already exist.** The import refuses a row naming a label this account does
  not have, rather than inventing it.
- A `.csv` file of 10 MB or less, if you are importing a file.

## The CSV columns

There is **no column mapping step**. Headers are matched by name, so they must be spelled exactly as below.
**Download a sample csv** in the dialog gives you a file with the right headers.

| Column | What it does |
|---|---|
| `name` | the contact's name |
| `phone_number` | the number, in any of the forms described below |
| `email` | the email address |
| `identifier` | your own key for this person |
| `labels` | one or more existing labels, separated by commas |
| `company_name` | stored on the contact |
| `city` | stored on the contact |
| `country_code` or `country` | the country for this row's phone number, overriding the import's choice |

Every other column is kept on the contact as a [custom attribute](custom-attributes) value, keyed by the column
header — but it is only visible in the Attributes panel if a custom attribute with exactly that key exists.

## The three choices for the whole import

| Choice | Effect |
|---|---|
| **Labels for every contact in this import** | Added to every row, on top of anything in the row's own `labels` column |
| **Country for local numbers** | Used only for rows that give no country of their own, and only for numbers written without a country code |
| **Contacts this account already has** | **Update their details**, or **Keep their details** |

## Phone numbers

A number is stored in international form, but what you may write in the file is wider than that.

| In the file | Stored as |
|---|---|
| `+966551112233` | `+966551112233` |
| `00966551112233` | `+966551112233` |
| `966551112233` | `+966551112233` |
| `0551112233`, with the country set to Saudi Arabia | `+966551112233` |
| `0551112233`, with no country | **skipped** — "a local number needs a country" |

Lynomia Chat refuses rather than guesses: a local number with no country could belong to any of a dozen
countries, and a wrong guess stores a number that looks plausible and reaches nobody. The country that was used
is remembered on the contact, so editing it later starts from the same country.

## Duplicates

**Against your account**, a row is matched by identifier first, then email, then phone number. What happens next
is the choice you made:

| | Update their details | Keep their details |
|---|---|---|
| Name, company, city | overwritten when the row has a value | untouched |
| Email, phone, identifier | overwritten when the row has a value | untouched |
| Custom attributes | merged; the row's keys win, the rest survive | untouched |
| **Labels** | **added** | **added** |

A blank cell never clears a stored value, under either choice. Labels are additive either way, because an import
should not be able to delete a decision another agent made.

**Within the file**, a second row naming a contact an earlier row already named is counted as a repeated row.
One contact is created, and both rows' labels land on it. Since a phone number can belong to only one contact in
an account, a file listing the same number twice produces one contact, not two.

There is no merge option on import — see [contacts](contacts) for merging two existing records.

## Pasting numbers

Choose **Paste numbers** instead of a file. One number per line, or separated by commas, semicolons or tabs, so
a hand-typed list and a column copied from a spreadsheet both work. Spaces inside a number are fine:
`+965 5111 2233` is one number.

This path sets phone numbers only — names, emails and identifiers need a CSV — and takes at most 10,000 numbers
per paste.

## Steps

1. In the contacts list, open the add menu and choose **Import contacts**.
2. Pick **CSV file** or **Paste numbers**, and provide one.
3. Set the labels, the country for local numbers, and what to do about contacts you already have.
4. **Continue**. Read the preview.
5. **Import**.

The preview groups rows into **New contacts**, **To update**, **Left as they are**, **Repeated rows**, **No way
to reach** and **Will be skipped**, lists the rows you need to act on with the reason for each, and shows each
number as it would be stored. It examines the first 250 rows and says whether that was the whole file.

Nothing happens until step 5. You can go **Back**, change a choice, and look again.

## A worked example

A trade show gave you 600 numbers in a spreadsheet, written as local Kuwaiti numbers.

1. Create a label `expo-2026` in Settings first.
2. Paste the column in, or save it as a CSV with one `phone_number` header.
3. Set **Labels** to `expo-2026`, **Country for local numbers** to Kuwait, and leave the duplicate choice on
   **Update their details**.
4. **Continue**. The preview says 548 new contacts, 11 to update, 38 repeated rows and 3 skipped, and names the
   three.
5. **Import**, then fix the three by hand.

Those 11 "to update" are people you already had. They keep their names and gain the label.

## Limits

- **No undo.** An import cannot be rolled back. The preview exists so that you do not need one.
- The preview checks the first 250 rows; longer files are imported the same way, just not shown in full.
- The import runs in the background and the page does not report when it finishes. The account's
  **administrators** receive an email, with the rejected rows attached as a CSV — your original row plus an
  `errors` column saying why.
- The per-import breakdown of counts lives on that import's own page under **Settings → Data**, which needs the
  Data import feature enabled for your account.
- A row with a name and nothing else is created but never appears in the contacts list. The preview counts it
  under **No way to reach**.

## Related

- [Contacts](contacts)
- [Custom attributes](custom-attributes)
- [Bulk actions on contacts](bulk-actions)
- [Labels](labels)
- [Shared audiences](shared-audiences)

## If it does not work

**Every row was skipped for unknown labels.** The `labels` column names labels that do not exist in this
account. Create them, or clear the column.

**Everything was skipped with "a local number needs a country".** The file has local numbers and no country was
chosen. Set **Country for local numbers**, or add a `country_code` column.

**The file will not upload.** It must have a `.csv` extension and be 10 MB or smaller. Export again as CSV
rather than renaming an `.xlsx`.

**The import changed names I wanted left alone.** The duplicate choice was **Update their details**. Re-run with
**Keep their details** to add labels without touching anything else.

**Arabic names came out as symbols.** Save the CSV as UTF-8. Exports from Lynomia Chat already are, and
re-import cleanly.
