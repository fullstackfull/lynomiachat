# Contacts phase C1 — bulk add and import

Large contact ingestion, on the importer that was already there. Phase A's map
([00](00-existing-system-discovery.md), [01](01-reuse-map.md)) and phase B's fixes
([03](03-phase-b.md)) are the input.

Branch `claude/practical-thompson-9xfqed`, base `92b11a20`.

---

## What was already there, and what the brief assumed wrongly

The CSV path is `POST /contacts/import` → `data_imports(data_type: 'contacts')` →
`DataImport#process_data_import` → `DataImportJob`, all in `app/` with no `enterprise/` or `custom/` override and
no `prepend_mod_with` hook. Three of the brief's assumptions did not survive reading it.

| Assumption | What the code does |
|---|---|
| Labels on import need building | Already done. `data_import_job.rb` validated titles against `account.labels` and rejected a row with an unknown one **before** touching the contact, and applied labels through `Tagging.import(on_duplicate_key_ignore: true)` after rejecting the taggings that already existed — additive, including for contacts the account already had. Pinned by spec since before this phase. |
| Duplicate behaviour is "skip existing" | It was **update existing, always**. `on_duplicate_key_ignore: true` only suppresses the duplicate *insert*; the update had already happened, inside the lookup — `ContactManager#find_existing_contact` called `contact.save`. So name, email, phone_number and identifier were overwritten and custom_attributes merged, with no choice offered and no way to preview it. |
| Do not add a fifth phone normalizer | There were already four, and the one in this path was wrong: `format_phone_number` was `phone_number.start_with?('+') ? phone_number : "+#{phone_number}"`. So `0551112233` became `+0551112233` and `00965…` became `+00965…`, both of which `Contact` then refused — with "should be in e164 format", which does not say what to do about it. |

Two further facts shaped the work:

- **`Contact.import` skips the model's uniqueness validation.** activerecord-import strips `UniquenessValidator`
  unless `validate_uniqueness: true` (its README states this; the repo never passes it). The insert's bare
  `ON CONFLICT DO NOTHING` then relies on indexes — and `contacts` has `uniq_email_per_account_contact` and
  `uniq_identifier_per_account_contact` but only a **non-unique** `index_contacts_on_phone_number_and_account_id`.
  So two rows sharing only a phone number inserted two contacts, against the model's own rule.
- **`Contact.import` skips `before_save`.** So `Contacts::SyncAttributes` never ran for a bulk-inserted contact,
  which left it with the default `contact_type: 'visitor'`. In an account with `crm_v2` enabled,
  `Contact.resolved_contacts` is `where(contact_type: 'lead')` — so contacts somebody had just imported were not
  in the contacts list at all.

---

## One classifier, read-only, used by the preview and the import

`DataImport::ContactRows` decides what a row means. It only reads, so a preview is a true dry run, and the
importer takes its results and performs the writes. That is the whole reason it exists: a preview that reasons
about a file separately from the importer eventually promises something the importer does differently.

| Classification | Meaning |
|---|---|
| `new_contact` | the account does not have this contact |
| `update_existing` | it has it, and the row rewrites its details |
| `skip_existing` | it has it, and the row leaves its details alone |
| `duplicate_in_file` | an earlier row already named this contact; both rows' labels land on that one contact |
| `no_identity` | no email, phone or identifier, so nothing can ever reach it |
| `invalid` | refused, with the reason |

Reasons are machine-readable (`unknown_labels`, `phone_country_required`, `phone_invalid`, `missing_identity`,
`duplicate_in_file`, `existing_contact`, `invalid_record`) and localized in the browser, the way phase B localizes
validation failures, so the same payload reads correctly in English and Arabic.

`DataImport::ContactLabels` holds the tagging write, extracted from the job unchanged.

---

## Duplicate policy, and the exact field semantics

Two choices, named for what they do rather than for "skip":

| | `update` (the default, and what the importer has always done) | `keep` |
|---|---|---|
| `name`, `company_name`, `city` | overwritten when the row carries a value | untouched |
| `email`, `phone_number`, `identifier` | overwritten when the row carries one; a blank column never clears a stored value | untouched |
| `custom_attributes` | merged — the row's keys win, keys it does not mention survive | untouched |
| **labels** | **added, never replaced** | **added, never replaced** |

Labels are additive under both, because they are the point of the workflow and because adding a tagging cannot
destroy another agent's. That is stated in the dialog itself rather than left for someone to discover.

No merge option. Chatwoot has a contact merge primitive, but it is an interactive two-contact decision, not
something an import may do to a thousand rows on its own — and the brief forbids inventing merge semantics.

---

## Phone numbers

`Contacts::Phone.e164(raw, region)` is now the server's single rule for turning what a person typed or a file
carried into a stored `phone_number`, and `Commerce::Phone.e164` delegates to it — so for that question the count
of normalizers went **down**. The rule is phase B's, unchanged: a number that names its own country parses alone,
a local number parses only with a region somebody stated, and there is no default region — not the account's
locale, not its timezone, not an inbox, not a business number.

`Whatsapp::PhoneNormalizers::*` are deliberately not part of this. They reconcile provider-specific quirks of an
already-international WhatsApp id — Argentina's 9, Brazil's ninth digit, Mexico's 1 — for contact lookup, which
is a different question, and they are untouched.

The importer applies it and then falls back to the shape it has always produced:

```ruby
Contacts::Phone.e164(raw, region) || prefixed(raw)
```

That fallback matters. `Contact`'s rule is structural (`/\A\+[1-9]\d{1,14}\z/`), so numbers that are well-formed
without being real numbers — `+123456` is in this repo's own fixtures — have always been accepted here.
Tightening that belongs to the model, not to one of its writers, so the importer refuses exactly what the model
refuses and no more. What changes:

| Row | Before | Now |
|---|---|---|
| `+966551112233` | stored | stored |
| `918080808080` | `+918080808080` | `+918080808080` |
| `00966551112233` | `+00966551112233`, refused | `+966551112233`, stored |
| `0551112233`, country `SA` | `+0551112233`, refused | `+966551112233`, stored |
| `0551112233`, no country | `+0551112233`, refused as "should be in e164 format" | refused as **"a local number needs a country"** |

A row's own `country_code` or `country` column wins; the batch's choice only fills a row that names neither. The
region used is written to `additional_attributes['country_code']`, the key the contact form reads, so editing an
imported contact later starts from the same country the import used.

---

## Preview

`POST /contacts/import_preview` takes exactly the payload `POST /contacts/import` takes — a file or pasted
numbers, plus the batch's choices — and creates nothing. It is authorized by `ContactPolicy#import_preview?`,
which is `import?`.

It returns every classification including the zeros, so a caller never has to guess whether a missing key means
none or means not looked at, and it reports each row as written beside the number it would be stored as, so a
batch country's effect is visible before it is applied.

The examined rows are bounded at `DataImport::ContactPreview::ROW_LIMIT` (250) and the response says what it
did: `total_rows` is the whole file, `previewed_rows` is what was examined, and the dialog says "checked the
first 250 of 900 rows" rather than reporting the rest as nothing. Row-level reasons are capped at 100.

The bound is a measurement rather than a guess. The batch's existing contacts are looked up in three queries
(`ContactManager#preload`) rather than three per row, but the remaining cost is the model's own uniqueness
validations, which the preview runs on purpose so that whatever `Contact` would refuse is reported as refused.
On this machine, half the batch naming contacts that already exist:

| rows | elapsed | queries |
|---|---|---|
| 100 | 0.62s | 217 |
| 250 | 1.43s | 502 |
| 500 | 2.89s | 752 |

250 is where a synchronous click still feels like an answer. It covers a pasted list exactly, and for a file of
thousands both 250 and 500 are a sample, so the extra latency bought very little.

The file is uploaded twice for a CSV — once to preview, once to import. That is the cost of a preview that
persists nothing; the alternative is creating the import first and starting it later, which would mean
suppressing `DataImport`'s own `after_create_commit`.

---

## Pasting numbers

An entry path, not a second importer. `DataImport::PastedNumbers.csv` turns the text into the one-column CSV the
importer already reads, which is attached to an ordinary `DataImport` exactly as an uploaded file is. So pasted
numbers get the same normalization, the same duplicate handling, the same labels, the same per-row reasons and
the same failed-records CSV, and `DataImportJob` never learns the difference.

Split on newlines, commas, semicolons and tabs — a hand-typed list and a copied spreadsheet column both work —
and **never on a space**, because `+965 5111 2233` is one number. Repeats are kept rather than quietly dropped,
so the preview can say how many of the pasted numbers were repeats. Bounded at 10,000 numbers per paste, with a
422 pointing at the CSV upload for anything larger.

---

## Where the batch's choices live

On `data_imports.source_metadata`, an existing unvalidated jsonb column:

```ruby
{ 'labels' => ['vip'], 'default_country' => 'SA', 'duplicate_policy' => 'update' }
```

**Zero migrations.** Nothing in C1 needed a schema change.

They are validated at the request boundary, in `ContactImportParams`, reusing the label validation phase B built
for the create path — so an unknown label, a country that is not a country, a policy that is not one of the two,
a file that is not a CSV, or a paste that is too long all return 422 with the same
`{ message, attributes, errors, error_types }` body every other contact validation failure returns, instead of
failing silently inside a queue an hour later. The errors are on `:base`: activemodel reads the attribute off the
record to build an error's message, with no `respond_to?` guard, so any invented attribute name raises while the
422 is being rendered.

---

## Counts, and what the job records

`processed_records` still counts the rows the importer **accepted**, not the rows it inserted — that is what it
has always meant, and a spec pins it. The in-file deduplication therefore changes what is inserted, not what is
counted: two rows naming one contact carry the same contact object, so `contacts.uniq` inserts it once while both
rows still count as processed.

What the old counters could not express now goes into `stats`, which the import's own detail page already
renders:

```ruby
{ 'total' =>, 'imported' =>, 'updated' =>, 'kept' =>,
  'duplicate_in_file' =>, 'without_identity' =>, 'skipped' => }
```

A contact the account already had is saved once the whole file has been read rather than row by row, so a file
that fails half way through has not already changed half the account — and before the insert, because
`synchronize:` re-reads every already-persisted instance and would throw away an update still only in memory.

---

## Queue and bounds

Unchanged: `DataImportJob` on the `low` queue, `retry_on ActiveStorage::FileNotFoundError` three times, the file
streamed from ActiveStorage through a tempfile, `batch_size: 1000` for both the contact insert and the tagging
insert. No second queue, no browser-side parsing, no new background system.

The job still builds every accepted row in memory before inserting. That is pre-existing and unchanged; the
preview's bound is what keeps the synchronous path small.

---

## Verification

| Gate | Result |
|---|---|
| `spec/services/data_import/contact_rows_spec.rb` | **20 examples, 0 failures** |
| `spec/jobs/data_import_job_spec.rb` | **22 examples, 0 failures** (15 pre-existing, all still passing) |
| `spec/controllers/api/v1/accounts/contacts_controller_spec.rb` | **87 examples, 0 failures** |
| Contacts, labels, model, export, imports, policies | **209 examples, 0 failures** |
| Commerce, after `Commerce::Phone` was made a delegate | **508 examples, 0 failures** |
| `ContactImportDialog.spec.js` | **11 tests** incl. the Arabic preview |
| `api/specs/contacts.spec.js` | **20 tests**, 6 new for the import body |
| Contacts frontend | **7 files, 109 tests, 0 failures** |
| ESLint, changed files | 0 errors, 4 warnings (`no-dynamic-keys`, the repo's existing pattern) |
| RuboCop, changed files | no offenses |

Covering the brief's C1.8 list: a valid CSV import, a pasted-number import, explicit-country normalization,
`00` → `+`, an ambiguous local number refused rather than guessed, a duplicate in the same file, an existing
same-account contact, cross-account privacy (a contact in another account previews as new, never as existing),
labels on a new contact, labels added additively to an existing one, an invalid label flagged, invalid rows
reported with their reasons, the queued path unchanged, and the pre-existing import specs still green.

---

## Known limitations

| | |
|---|---|
| Two concurrent imports can still create two contacts sharing a phone number | In-file deduplication closes the single-file case, which is the reported one. The remaining race needs a **unique index on `(phone_number, account_id)`** — a migration, which the brief says to stop before writing. Reported in [§A migration this would need](#a-migration-this-would-need) rather than written. |
| A row with only a name is still created, and still does not appear in the contacts list | Unchanged behaviour, now *stated*: the preview classifies it `no_identity` and says it will be created but will not be listed. Changing it would change what the importer imports. |
| The CSV is uploaded twice when a preview is used | The cost of a preview that persists nothing. See [§Preview](#preview). |
| The preview examines at most 250 rows | Bounded by measurement (see [§Preview](#preview)). Lifting it further means not running the model's validations on every row, which would make the preview less truthful, or running the preview in a job, which would make it not a preview. |
| `POST /contacts/import` is not in the OpenAPI definitions | It never was — only `create` is, which is why phase B updated swagger and this phase does not. The whole import family is undocumented there. |
| No link from the dialog to the import's status page | The import returns `head :ok` with no id. The existing Settings → Data page does list and detail legacy CSV imports, so the page is there; only the link is missing. |
| Arabic strings were added here, not left to Crowdin | CLAUDE.md leaves non-English to Crowdin. Phase B set the precedent for Contacts because the brief requires the flow to work in Arabic, and an RTL capture of untranslated copy proves nothing. |

### A migration this would need

Not written. Recorded for approval, as the brief requires.

1. **What is insufficient.** `contacts` has unique indexes on email and identifier per account but only a
   non-unique one on `(phone_number, account_id)`. `Contact` validates phone uniqueness, and
   activerecord-import strips that validator, so the bulk path has no enforcement at all.
2. **Exact schema.**
   `add_index :contacts, [:phone_number, :account_id], unique: true, where: "phone_number <> ''", algorithm: :concurrently`
   — partial, because blank phone numbers are legitimate and numerous.
3. **Why nothing else can do it.** In-memory deduplication cannot see another process's rows. Passing
   `validate_uniqueness: true` to `Contact.import` would run one `SELECT` per row and still lose a race.
   `on_duplicate_key_ignore` needs an index to arbitrate on.
4. **Tenant implications.** The index is account-scoped, so it enforces per account, as the model intends. Any
   existing account that already holds duplicate phone numbers would block the index — so this needs a survey
   first, and a decision about what to do with those rows.
5. **Rollback.** `remove_index`. No data is changed by adding it.

---

## Out of scope, by instruction

No new importer, no `BulkContactImporter` / `ContactImportV2` / `PhoneListImporter`, no second queue, no second
persistence service for pasted numbers, no browser-side parsing, and no change to what the existing CSV import
does by default.
