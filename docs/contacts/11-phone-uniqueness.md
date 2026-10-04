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
