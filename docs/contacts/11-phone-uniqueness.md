# Phase E — contact phone uniqueness

A contact's phone number was unique by validation only. This is what that meant, what the data looked like,
and what now enforces it.

---

## E2 — the uniqueness semantics, read off the model and the schema

Three columns on `contacts` identify a person. They were not treated alike.

| | model | database (before phase E) |
|---|---|---|
| `email` | `uniqueness: { scope: [:account_id], case_sensitive: false }`, `allow_blank: true` | `uniq_email_per_account_contact (email, account_id) UNIQUE` |
| `identifier` | `uniqueness: { scope: [:account_id] }`, `allow_blank: true` | `uniq_identifier_per_account_contact (identifier, account_id) UNIQUE` |
| `phone_number` | `uniqueness: { scope: [:account_id] }`, `allow_blank: true`, plus `Contacts::Phone::STRUCTURAL_FORMAT` | `index_contacts_on_phone_number_and_account_id (phone_number, account_id)` — **not unique** |

Four consequences followed from that table, and all four are real.

**1. A validation cannot see a row that does not exist yet.** `validates :uniqueness` issues a `SELECT`. Two
requests that both run that `SELECT` before either `INSERT`s both pass. For email and identifier the database
then refuses the loser; for phone numbers nothing did. This is not theoretical: phase C found the single-file
case in the CSV importer (two rows sharing only a phone number inserted two contacts) and closed it by
deduplicating in the file, while recording that the cross-request race needed an index
([04-bulk-import.md](04-bulk-import.md)).

**2. `''` is a value; NULL is not.** PostgreSQL's unique indexes treat NULLs as distinct from one another
(`NULLS DISTINCT`, the default), so any number of contacts may have no email. That only works because
`Contact#prepare_email_attribute` turns a blank email into NULL, with the comment *"So that the db unique
constraint won't throw error when email is ''"*. **Nothing did that for `identifier` or `phone_number`.**
`permitted_params` on the contacts controller permits both directly, so `PATCH /contacts/:id` with
`identifier: ""` writes an empty string — and the *second* contact in an account to receive one hits
`uniq_identifier_per_account_contact` and answers **500**, because the model's `allow_blank: true` skips the
validation that would have made it a 422. That bug predates this work and is live.

**3. The email index is case-sensitive; the validation is not.** `uniq_email_per_account_contact` is on the raw
column, while the validation is `case_sensitive: false`. They agree only because `prepare_email_attribute`
downcases first. (`index_contacts_on_lower_email_account_id` exists separately, and is not unique.)

**4. The phone format rule is structural, not semantic.** `STRUCTURAL_FORMAT = /\A\+[1-9]\d{1,14}\z/` checks
the shape of an E.164 number, not that the number exists. Uniqueness is therefore uniqueness of a string, and
two spellings of one number — `+966551112233` and `00966551112233` — are two different contacts to the
database. Normalizing them is `Contacts::Phone`'s job at the write boundary, and out of scope here.

### What the index therefore has to be

- **Plain, not partial.** Phase C sketched a partial unique index (`WHERE phone_number <> ''`) to tolerate the
  blank strings. That is the wrong instrument: PostgreSQL will only use a partial index when it can prove the
  predicate holds, which it cannot do under a generic plan from a prepared statement — so the constraint would
  hold but the lookups that index serves today would stop using it. The right order is to make the data fit a
  plain index: blank becomes NULL, as email already does.
- **Built `CONCURRENTLY`**, in a migration with `disable_ddl_transaction!`, with `statement_timeout` cleared
  for the migration's own session — `config/database.yml:13` sets it to 14s on every connection, production
  included, and a concurrent build on a large `contacts` will exceed that. Being killed by that timeout is
  exactly what leaves an index behind marked `INVALID`.
- **Preceded by a refusal, not a failure.** A failed `CREATE UNIQUE INDEX CONCURRENTLY` leaves the INVALID
  index behind, so duplicates have to be found before the build rather than by it.

---

## E1 / E3 — the audit, and what it found

`lib/tasks/contact_phone_uniqueness.rake` has two read-only tasks, neither of which takes a lock, and each of
which clears the 14s `statement_timeout` for its own session only:

- `contacts:phone_uniqueness:audit` — what is there.
- `contacts:phone_uniqueness:dry_run` — the three steps the migration will take, and whether it can.

Both accept `ACCOUNT_ID` to narrow to one account.

The development database could not be used: this container has no development-group gems, so
`RAILS_ENV=development` cannot boot (`cannot load such file -- rack-mini-profiler`). The audit was therefore
exercised against the test database, seeded with exactly the conditions it exists to find — duplicates created
the way a race creates them (past the validation), blank strings written the way `PATCH /contacts/:id` writes
them, and the same number in a second account to confirm it is not a conflict:

```
Contacts examined: 10
  phone_number IS NULL: 0  (any number of these is fine — NULLs are distinct)
  phone_number = '':    4  (two of these in one account collide)
  identifier = '':      1  (the identifier index is already UNIQUE)

Accounts with more than one blank-string phone number: 1
  account 1: 4 rows

Duplicate (account_id, phone_number) groups: 2
Contacts involved: 5
  account 1 +966551110002: 3 rows {3,4,5}
  account 1 +966551110001: 2 rows {1,2}
```

The dry run then refused, naming the row to keep in each group:

```
Step 1 — UPDATE contacts SET phone_number = NULL WHERE phone_number = '': 4 row(s)
Step 2 — CREATE UNIQUE INDEX CONCURRENTLY uniq_phone_number_per_account_contact ON contacts (phone_number, account_id)
Step 3 — DROP INDEX index_contacts_on_phone_number_and_account_id (the new one subsumes it)
Would FAIL. 2 duplicate group(s), 5 contacts.
  account 1 +966551110002: keep 3, conflicts {3,4,5}
  account 1 +966551110001: keep 1, conflicts {1,2}
```

Note that the same number in the second account was correctly absent from both reports.

### The identifier bug, reproduced rather than predicted

Seeding the fixtures proved §E2's third point on the spot. Three rows inserted with `identifier: ''` produced
one row, because `Model.insert` is `ON CONFLICT DO NOTHING` and the other two collided on
`uniq_identifier_per_account_contact`. Saving a second one through the model gives the exception a request would
turn into a 500:

```
identifier: a second blank was REFUSED by the database -> ActiveRecord::RecordNotUnique
```

That is a live defect on `main`, independent of phone numbers, and the normalization below closes it.

---

## E4 — what was changed

**`custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb`** (Lynomia migrations live in
`custom/db/migrate`, which `config/application.rb:56` appends to the migration path, and which is where the
fork's other changes to OSS tables went). With `disable_ddl_transaction!`, in this order:

1. Clear `statement_timeout` for the migration's session.
2. Drop the unique index if it exists and is `INVALID`.
3. **Refuse** if duplicates remain, naming up to twenty of them and pointing at the audit task.
4. Normalize `phone_number = ''` to NULL, in batches of 1000.
5. `CREATE UNIQUE INDEX CONCURRENTLY uniq_phone_number_per_account_contact ON contacts (phone_number, account_id)`.
6. Drop `index_contacts_on_phone_number_and_account_id` — the same columns in the same order, so the unique one
   subsumes it.

The refusal comes *before* the normalization, and that ordering was a correction made during verification. The
first run of the migration normalized four rows and *then* refused, which with `disable_ddl_transaction!` meant
an aborted migration had already changed the table. Two things had to move together: refuse first, and exclude
`''` from the duplicate query — because a blank string is not NULL, four blanks in one account read as a
duplicate group, and the migration would otherwise have refused over the very thing its next step fixes, while
disagreeing with a dry run that had always excluded them.

`down` recreates the plain index **before** dropping the unique one, so `phone_number` is never left unindexed —
`ContactInboxWithContactBuilder` looks a contact up by number on every inbound message. It does not undo the
blank-to-NULL normalization: `''` and NULL both mean "no number", and NULL is what every other identity column
on the table already uses for it.

**`Contact#prepare_contact_attributes`** now nulls a blank `phone_number` and `identifier` alongside what it
already did for email. It is `before_validation`, not `before_save`, and that is load-bearing: activerecord-import's
`valid_model?` wraps each record in `run_callbacks(:validation)` but never runs the save callbacks, so the CSV
importer only sees what happens before validation. Putting it in `Contacts::SyncAttributes` — the `before_save`
service — was the first attempt, and would have left `Contact.import` writing empty strings.

**`ContactsController#create` / `#update`** translate `ActiveRecord::RecordNotUnique` into the 422 the loser of
a race would have got a moment later, by revalidating now that the winner is visible. If revalidation finds
nothing wrong, the original error is re-raised rather than a message being invented for it. This path was
already reachable for email and identifier, whose indexes have been unique since the first schema.

**Nothing was needed for the inbound path.** `ContactInboxWithContactBuilder#perform` already rescues
`ActiveRecord::RecordNotUnique` and retries find-or-create, with the comment *"in case of race conditions where
contact is created by another thread"*. The index turns a race that used to produce two duplicate contacts into
a retry that finds the winner — so for inbound messages this is a fix delivered by existing machinery, not a new
failure mode. The CSV importer is likewise covered: `Contact.import(..., on_duplicate_key_ignore: true)` emits
`ON CONFLICT DO NOTHING` with no arbiter, which covers every unique constraint on the table.

---

## E5 / E6 — verification

### The constraint, and the race

| | |
|---|---|
| `spec/models/contact_phone_uniqueness_spec.rb` | a duplicate the validation did not see is refused; the same number in another account is not; any number of contacts may have no number at all; a blank number and a blank identifier are both stored as NULL, so two of each coexist; and a number cleared by an update becomes NULL rather than `''` |
| `spec/models/contact_phone_race_spec.rb` | two real connections, each with its own, racing on a latch, outside a transaction — exactly one wins, the other is told either by its own validation or by the index, and exactly one row exists |
| `spec/controllers/api/v1/accounts/contacts_controller_spec.rb` | the loser of a create race is answered 422 with `error_types: { phone_number: ['taken'] }`, not 500 |

The race spec needs `self.use_transactional_tests = false`, because each thread needs its own connection and a
transactional example would hide one thread's row from the other. Its first cleanup was wrong in a way worth
recording: `account.contacts.delete_all` *nullifies* the foreign key on a `has_many` rather than deleting rows,
which `contacts.account_id NOT NULL` refuses. Nothing there is transactional, so the cleanup has to be exact.

### Rollback, and the INVALID index

Verified against the test database, with the index state read from `pg_index` at each step.

| step | result |
|---|---|
| after `db:migrate` | `uniq_phone_number_per_account_contact valid=true unique=true`, and the plain index gone |
| a duplicate past the validation | `ActiveRecord::RecordNotUnique` |
| `db:rollback STEP=1` | `index_contacts_on_phone_number_and_account_id valid=true unique=false`, the unique one gone |
| the same duplicate again | accepted — two rows share the number, which is what the index was refusing |
| re-migrate | back to `valid=true unique=true` |

The `INVALID` branch was not verified by inspection but by manufacturing one the way production does: reintroduce
a duplicate, then run `CREATE UNIQUE INDEX CONCURRENTLY` by hand. PostgreSQL answers
`could not create unique index ... Key (phone_number, account_id)=(+966551110001, 1) is duplicated` and leaves
the index in place:

```
uniq_phone_number_per_account_contact valid=false unique=true
```

Running the migration against that state exercises both branches in order:

```
-- uniq_phone_number_per_account_contact exists but is INVALID, left by an interrupted build; dropping it and rebuilding
StandardError: contacts holds duplicate (account_id, phone_number) rows, so the unique index cannot be created.
              Run `bundle exec rake contacts:phone_uniqueness:audit` ... First 1: account 1 +966551110001 (2 rows)
```

— the invalid index dropped rather than skipped past, and then a refusal rather than a second failed build.
`if_not_exists: true` is the wrong instrument here precisely because it would have skipped the build and
reported success while the column stayed unconstrained.

### A note on `db/schema.rb`

`db:migrate` and `db:rollback` both re-dump the schema, and this container's dumper disagrees with whatever
produced the committed file: it writes `ActiveRecord::Schema[7.2]` where the file says `[7.1]`, sorts two index
lists differently, and adds a layer of parentheses to two partial-index predicates. None of that is this
change's to make, so the commit carries only the two lines the migration actually changed — the version, and
the contacts index.
