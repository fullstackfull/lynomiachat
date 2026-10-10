# P-FINAL.14–.16 — Migration review, rollback tolerance and data integrity

The deployment that follows P-FINAL crosses four phases of schema work in one step. This document is the
per-migration review the brief asks for, plus the one thing a combined release most needs written down: what an
application rollback may and may not assume about the database.

Everything here was measured on this tree against PostgreSQL 16.15, on a database loaded from `db/schema.rb`
and then migrated — the same starting point production is in.

---

## 1. What the release actually changes

Eight migrations, all added since production `b03ea43d`, all under `custom/db/migrate`, none modifying or
deleting an existing migration. Six new tables, two new columns, one new index on an existing table.

| # | Migration | Phase | Object | Kind |
|---|---|---|---|---|
| 1 | `20261009100000_create_support_tickets` | P9 | `support_tickets`, `support_ticket_events` | new tables (2) |
| 2 | `20261009100100_create_operations_signals` | P9 | `operations_signals` | new table |
| 3 | `20261009120000_create_contact_identities` | P10 | `contact_identities` | new table |
| 4 | `20261009130000_add_social_identity_index_to_contacts` | P10 | `contacts` | **index on an existing table** |
| 5 | `20261010100000_create_billing_entitlement_overrides` | P11 | `billing_entitlement_overrides` | new table |
| 6 | `20261010100100_add_channel_entitlements_to_billing_plans` | P11 | `billing_plans.channel_entitlements` | new column, default `[]` |
| 7 | `20261010110000_create_billing_webhook_events` | P11 | `billing_webhook_events` | new table |
| 8 | `20261010110100_add_last_event_at_to_billing_subscriptions` | P11 | `billing_subscriptions.last_event_at` | new column, nullable |

P8 added no schema at all, which is consistent with its design as a read projection over existing tables.

---

## 2. Per-migration review

Columns: the lock it takes, whether it needs a table scan, whether a backfill is required, reversibility, and
the production impact that follows from the first three.

| # | Lock | Scan / rewrite | Backfill | Reversible | Production impact |
|---|---|---|---|---|---|
| 1 | `ACCESS EXCLUSIVE` on two **new** tables; brief `SHARE ROW EXCLUSIVE` on `accounts`, `conversations`, `contacts`, `inboxes`, `users`, `teams` while the six FK triggers are added | none — the tables are empty, so each FK is created already-valid | none | `drop_table` ×2 | **negligible.** The only locks on existing tables are the momentary ones needed to attach a foreign-key trigger. Measured: 1.44 s total on a schema-loaded database. |
| 2 | same shape, one new table, FKs to `accounts` and `support_tickets` | none | none | `drop_table` | negligible (0.44 s) |
| 3 | same shape, one new table, FKs to `accounts`, `contacts`, `users` | none | none | `drop_table` | negligible (0.29 s) |
| 4 | **`SHARE` on `contacts` only** — `CREATE INDEX CONCURRENTLY`, see §3 | builds over every row in `contacts`, concurrently | none | `DROP INDEX CONCURRENTLY` | **the one migration whose duration scales with production data.** Writes are not blocked. |
| 5 | one new table, FKs to `accounts`, `users` | none | none | `drop_table` | negligible (0.43 s) |
| 6 | `ACCESS EXCLUSIVE` on `billing_plans`, momentary | **no rewrite**: PostgreSQL 11+ stores a non-volatile column default as catalogue metadata, and `'[]'::jsonb` is constant. `billing_plans` is an operator-managed catalogue of a handful of rows in any case | none | `remove_column` | negligible (0.003 s) |
| 7 | one new table, no FK | none | none | `drop_table` | negligible (0.39 s) |
| 8 | `ACCESS EXCLUSIVE` on `billing_subscriptions`, momentary | no — nullable, no default | **deliberately none**: a nil means "no ordering information yet", so the out-of-order guard becomes effective from the first event after deployment rather than needing a value invented for every existing row | `remove_column` | negligible (0.003 s) |

**No destructive migration, and no required backfill anywhere in the release.** Nothing drops a column, drops
a table, renames anything, changes a type, or adds a `NOT NULL` to an existing column. There is no data
migration to run before, during or after the deploy.

---

## 3. The one lock risk, and what P-FINAL did about it

Migration 4 is the only one that touches a table production already holds rows in. As P11 left it, it was a
plain `CREATE INDEX` inside the migration's DDL transaction, which takes `ACCESS EXCLUSIVE` on `contacts` for
the whole build — so every inbound message that creates or updates a contact would wait behind it, on the
busiest table in the product, during a deploy.

**Changed in P-FINAL** to `CREATE INDEX CONCURRENTLY`, with the three precautions this repository's own
concurrent-index migrations already take:

| Precaution | Why, with the evidence |
|---|---|
| `disable_ddl_transaction!` | `CONCURRENTLY` cannot run inside a transaction |
| `SET statement_timeout = '0'` | `config/database.yml:13` sets `14s` on every connection including production's, and being killed by it is exactly what leaves an index `INVALID`. `deployment/deploy.sh` also exports `POSTGRES_STATEMENT_TIMEOUT=0` for the migration step; the migration does not rely on that, because a manual `rails db:migrate` would not have it |
| explicit `INVALID`-leftover check | `IF NOT EXISTS` would skip the rebuild and report success while the index answered nothing — and `deployment/deploy.sh:176-183` aborts a deploy on any invalid index, so a skipped rebuild would be a loop the operator could not leave by re-running |

Precedent in this tree, so this is the house pattern rather than a new idea: 21 upstream migrations use
`algorithm: :concurrently`, two of them on `contacts`
(`db/migrate/20230727065605_add_partial_index_contact_account_id.rb`,
`db/migrate/20250722152516_add_index_on_contact_type_and_account_id_to_contacts.rb`), and
`custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb` takes all three precautions
above for the same measured reasons.

`db/schema.rb` is unchanged by the switch — the index definition is identical, only the way it is built differs
— which §5 proves rather than asserts.

---

## 4. Migration up / down validation (P-FINAL.35)

Run on a dedicated database (`lyn_pfinal_mig`) loaded from `db/schema.rb`, so the starting point is the schema
production is on plus the eight new migrations.

**Down, in reverse order — all eight reverted:**

```
DOWN 20261010110100: reverted (0.0083s)      DOWN 20261009130000: reverted (0.0038s)
DOWN 20261010110000: reverted (0.0272s)      DOWN 20261009120000: reverted (0.0138s)
DOWN 20261010100100: reverted (0.0085s)      DOWN 20261009100100: reverted (0.0215s)
DOWN 20261010100000: reverted (0.0170s)      DOWN 20261009100000: reverted (0.0366s)
```

**And the rollback left nothing behind.** Queried directly, not inferred:

```
tables  support_tickets, support_ticket_events, operations_signals, contact_identities,
        billing_entitlement_overrides, billing_webhook_events            -> none present
columns billing_plans.channel_entitlements, billing_subscriptions.last_event_at -> none present
index   index_contacts_on_social_tiktok_user_id                          -> 0 rows in pg_class
```

**Up again — all eight re-applied**, with the timings quoted in §2.

### One pre-existing defect found while doing this, which the operator must know

`bundle exec rails db:migrate` **from an empty database fails**, and has nothing to do with this release:

```
== 20231211010807 AddCachedLabelsList: migrating
StandardError: An error has occurred, this and all later migrations canceled:
NameError: uninitialized constant ActsAsTaggableOn::Taggable::Cache
```

That is an upstream Chatwoot migration from December 2023 referring to a constant the current
`acts-as-taggable-on` no longer defines. It is **not a release blocker** — production's database already exists
and this migration ran on it years ago, and the test database is built with `db:schema:load`, which is also
what a new installation must use. It is recorded here because "rebuild the database by replaying migrations"
is not a recovery path available in this repository, and a runbook must not suggest it.

---

## 5. Schema round trip

```
SCHEMA=<tmp>/schema.roundtrip.rb bundle exec rails db:schema:dump   # against the migrated database
diff db/schema.rb <tmp>/schema.roundtrip.rb                         # -> no differences
```

**Byte-identical.** The committed `db/schema.rb` is exactly what the migrations produce, including after the
`CONCURRENTLY` change, and the tracked file was not modified by the exercise (`git status --porcelain
db/schema.rb` → empty).

---

## 6. Rollback policy: application rollback versus database rollback (P-FINAL.15)

These are two different operations and the combined release makes the difference matter. The policy, stated so
an operator at 3am does not have to derive it:

> **Roll the application back. Leave the schema in place.**

### Why that is safe here

Every one of the eight migrations is additive. Production's current code (`b03ea43d`) does not read or write
any of the six new tables, the two new columns or the new index, because none of them existed when it was
built. A database carrying them is, to that code, indistinguishable from one that does not — with one
exception, which is not an exception at all: the new `contacts` index makes a query it never issues faster.

So an application rollback needs **no** database change, loses **no** data, and can be done in the time it
takes to check out the previous revision and restart.

### What a database rollback would cost, if anyone reached for it

| Dropping | Would destroy |
|---|---|
| `support_tickets`, `support_ticket_events` | every support case and its whole history, including internal notes |
| `operations_signals` | the record of every operational problem seen, and the dedup key the support bridge uses |
| `contact_identities` | the additional phone numbers and email addresses agents linked to customers |
| `billing_entitlement_overrides` | every commercial exception an operator granted, with its reason and audit trail |
| `billing_webhook_events` | the idempotency and ordering record for billing; a replayed Stripe event would then be processed twice |

**Therefore: a `db:rollback` is not a first response and is not in the runbook.** It is only ever correct when
a specific migration is itself the fault, and then only for that one migration, after a backup has been
verified. `deployment/ROLLBACK.md` carries the executable procedure; `docs/p-final/09-rollback-and-rollout.md`
carries the decision tree.

### Is there any migration old production code cannot tolerate?

No. Checked against each of the three ways additive schema can still break old code:

| Risk | Present? | Evidence |
|---|---|---|
| A new `NOT NULL` column without a default on a table old code inserts into | **no** | the only new columns are `billing_plans.channel_entitlements` (default `[]`) and `billing_subscriptions.last_event_at` (nullable); both tables are written only by code that ships with this release |
| A new unique constraint or index that old code's writes would now violate | **no** | every new unique index is on a new table. The one index on an existing table (`contacts`) is non-unique |
| A new foreign key that constrains a table old code deletes from | **effectively no** | the new FKs point *at* `accounts`, `contacts`, `conversations`, `inboxes`, `users`, `teams`, `billing_plans`, and every one is `ON DELETE CASCADE` or `ON DELETE SET NULL` — so an old-code delete of a parent row still succeeds, and the child row is cascaded or nullified rather than refusing the delete |

That last row is the one that would normally bite, and it was designed around: not a single FK in this release
uses the restricting default.

---

## 7. Data integrity review (P-FINAL.16)

The high-risk paths, and what holds them. Each row names the constraint or code that enforces it, so the claim
is checkable.

| Path | Risk | What holds it |
|---|---|---|
| Contact merge | silent loss of related rows | P10 rewrote `ContactMergeAction` to move rather than destroy campaign, commerce, ticket and CSAT rows, authorized it, and audits it (`265171bb`, `5d836ef0`) |
| Contact identities | two contacts claiming one phone number, making inbound matching a guess | `index_contact_identities_on_account_type_value` UNIQUE on `(account_id, identity_type, value)`, with values normalized before storage (E.164 via `Contacts::Phone.e164`, email downcased) |
| TikTok identity lookup | a new Contact per conversation | the expression index from migration 4, plus the lookup that uses it |
| Support tickets | a reference number colliding inside an account | `index_support_tickets_on_account_and_reference` UNIQUE on `(account_id, reference_number)` |
| Support ticket links | orphaned tickets when a conversation, contact, inbox, assignee or team is deleted | every one of those FKs is `ON DELETE SET NULL`, and the columns are nullable by design — an internal case has no customer and no channel |
| Operations signals | one row per occurrence instead of per problem; duplicate support cases | partial UNIQUE on `COALESCE(account_id,0), source, COALESCE(subject_type,''), COALESCE(subject_id,0), signal WHERE resolved_at IS NULL` — the `COALESCE` is what makes installation-wide rows dedup, since PostgreSQL treats NULLs as distinct |
| Polymorphic references | a client choosing a class name | `support_tickets.source_type` and `operations_signals.subject_type` are plain strings with allow-list validation, chosen over Rails polymorphic associations precisely because nothing in this repository constrains a polymorphic type column |
| Billing subscription state | a delayed `past_due` overwriting a recovered `active` | `billing_subscriptions.last_event_at` plus the refusal in `Billing::SubscriptionSync` |
| Billing webhooks | processing one Stripe event twice | `uniq_billing_webhook_event_per_provider` UNIQUE on `(provider, provider_event_id)` — the database decides, so it is concurrency-safe without a lock |
| Entitlement overrides | two rows for one capability | `uniq_billing_override_per_account_capability` UNIQUE on `(account_id, kind, name)` |
| Seat and inbox limits | two concurrent requests both passing the last seat | `account.lock!` inside the save transaction (`Billing::ResourceLimit`), proven at SQL level in `docs/p11/07-security-performance.md` |
| Plan entitlement edits | a customer losing mid-period what they pay for | **new in P-FINAL**: `BillingPlan#refuse_narrowing_while_billed` |

### Cross-account relations

Every new table carries `account_id NOT NULL` except `operations_signals`, where it is nullable **on purpose** —
a queue-depth or installation-wide signal belongs to no account — and the Operations Center is Super-Admin-only,
so that nullable column is never a tenant boundary a customer can cross. The per-surface tenancy evidence is in
`05-security-audit.md`.

---

## 8. Conclusions for the deployment

1. Run the eight migrations in one step; they are additive and need no backfill.
2. Expect migration 4 to take as long as a concurrent index build on production's `contacts` takes, with
   writes continuing throughout. Keep `POSTGRES_STATEMENT_TIMEOUT=0` for the step (the deploy script already
   does) and let the post-migration invalid-index check decide whether it finished.
3. If the release has to be withdrawn: **revert the application, keep the schema.** No data is lost and the
   old code cannot tell the difference.
4. Never replay migrations from empty to rebuild this database; `db:schema:load` is the only path that works.
