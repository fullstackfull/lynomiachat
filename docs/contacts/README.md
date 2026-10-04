# Contacts Reliability & Bulk Workflows — Phase 1

Phase A was discovery. Phase B fixed the proven defect. C1–C5 are not started.

## Read this first

| | |
|---|---|
| [`03-phase-b.md`](03-phase-b.md) | **what changed**: create-with-label is durable, the real validation shows next to its field in both languages, duplicate recovery, phone normalization, and the end of false list membership — with what each is proved by |
| [`02-discovery-checkpoint.md`](02-discovery-checkpoint.md) | the twelve answers Phase A had to produce, including the exact cause of the reported label-page failure and the smallest production-safe plan |

## The trace

| | |
|---|---|
| [`00-existing-system-discovery.md`](00-existing-system-discovery.md) | what the product already has — Contact lifecycle, labels, import, bulk actions, the Audience/Campaign/Automation bridges, recipes, phone and duplicates — with `file:line` for every conclusion, across `app/`, `enterprise/` and `custom/` |
| [`01-reuse-map.md`](01-reuse-map.md) | **EXISTING SYSTEM TO EXTEND**, the 125-row REUSE / EXTEND / PATCH / NOT PRESENT matrix, what is deliberately not created, the zero-migration assessment with two declined candidates, and the sequenced plan |

## The three headlines

1. **The reported single failure is three independent defects.** The active label is never in the create payload —
   `dashboard/api/contacts.js:5-11` is the *list filter*, and `labels` is not in `permitted_params` — so a label page
   creation attaches no label even when it succeeds. Four of five 422 handlers ignore the server message that already
   reaches them and go silent when the invalid attribute is neither `email` nor `phone_number`. And
   `ContactsIndex.vue:428-430` has no handler at all.

2. **More already exists than the brief assumed.** The CSV importer imports a `labels` column and the exporter emits
   one, so export → edit → import already round-trips labels in bulk. The bulk endpoint already batches contact label
   writes in one request. Label rename and delete already rewrite Contact taggings. `Commerce::Phone.e164` already
   does country-aware normalization that refuses to guess. `DataImportError` and its whole serving chain are generic
   and simply unused by the CSV path.

3. **The real scale gap is selection.** Bulk actions take an explicit id list, the list shows 15 rows at a time, and
   `contacts#export` already accepts a filter. That asymmetry — not a missing engine — is what limits bulk workflows.

Two constraints shape what later phases can be, and neither was obvious from outside the code: **no automation event
fires on a Contact**, so "label every contact matching X" is not an automation rule — it is what a Shared Audience
already is. And there is **no account- or channel-level country column**, so a server-side phone normalizer has no
region to fall back on; refusing an ambiguous number is the only correct behaviour, not a policy preference.

## Where the Contacts surfaces are

`app/javascript/dashboard/routes/dashboard/contacts/routes.js` — seven routes. Note the filename: a
`**/*.routes.js` glob does **not** match it, which is how the UI/UX phase first undercounted them. They are
enumerated by hand in [00 §0](00-existing-system-discovery.md).

## How this was verified

The first trace was written by reading the code directly. Eight independent read-only agents then re-traced the
same eight areas; every fact they added was re-verified against the source before being written down, and the
counts above are measured from the matrix, not asserted. Nothing here rests on a single pass.

## Status

Phase A and Phase B are done. **C1–C5 are not started** and must not start until Phase B has been reviewed.

Two things Phase B had to correct in Phase A's own account of the defect, both proved by test:
`/contacts` is itself a server-filtered view, so the false-row defect was never limited to label pages; and
the E.164 rule is structural, so a dial code concatenated onto a trunk-prefixed number is usually *accepted*
rather than rejected — it stored a wrong number silently.
