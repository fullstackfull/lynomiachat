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
| A new foreign key that constrains a table old code deletes from | **yes, in one place, now fixed** | the new FKs point *at* `accounts`, `contacts`, `conversations`, `inboxes`, `users`, `teams`, `billing_plans`. Every one is `ON DELETE CASCADE` or `ON DELETE SET NULL` **except** the two on `billing_entitlement_overrides`, which were created with no `on_delete:` at all and so carried PostgreSQL's restricting default |

That last row is the one that would normally bite, and this review's first pass asserted that "not a single FK
in this release uses the restricting default". **That was wrong**, and the post-integration migration audit
caught it. `custom/db/migrate/20261010100000_create_billing_entitlement_overrides.rb:39,45` passed
`foreign_key: true` and `foreign_key: { to_table: :users }` without `on_delete:`, which `db/schema.rb` recorded
faithfully as two bare `add_foreign_key` lines.

The `granted_by_id` one was live: nothing nullifies that column — the model declares
`belongs_to :granted_by, optional: true` and no `dependent:` anywhere points back at it — so once a Super Admin
had granted an override, PostgreSQL refused to delete that user's record, and agent removal destroys users
(`Agents::DestroyJob` → `DeleteObjectJob`). It surfaced as a failed job rather than as a message anybody saw.
The `account_id` one was defensive only, because `Custom::Account` already declares
`has_many :billing_entitlement_overrides, dependent: :destroy`.

`custom/db/migrate/20261011140000_set_on_delete_on_billing_override_foreign_keys.rb` re-creates both with
`on_delete: :cascade` and `on_delete: :nullify`. It is reversible, and it was applied and rolled back once to
prove it. **With it applied, the claim above is true.** An override is a commercial decision about an account
and must outlive the person who made it, which is what nullify means here.

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

Every new table carries `account_id NOT NULL` except two, both Super-Admin-only surfaces, so neither nullable
column is a tenant boundary a customer can cross. The per-surface tenancy evidence is in `05-security-audit.md`.

- `operations_signals.account_id` is nullable **on purpose**: a queue-depth or installation-wide signal belongs
  to no account.
- `billing_webhook_events.account_id` is nullable and, unlike every other new column of that name, has **no
  foreign key at all** (`custom/db/migrate/20261010110000_create_billing_webhook_events.rb:36` declares a plain
  `t.integer`). This is deliberate and this review's first pass failed to name it, which the post-integration
  audit corrected. The receipt is written when the event arrives, before anything has decided which account it
  concerns, and `BillingWebhookEvent#processed!` fills the column afterwards from
  `stripe_subscription.client_reference_id` — a value Stripe supplies and this installation does not control.
  A `NOT NULL` column would make an unattributable event unrecordable, and a foreign key would make a receipt
  for an account that has since been deleted fail to write, which is the opposite of what a durable receipt is
  for. The column is an attribution hint for the operator's event list, never an authorization input: nothing
  reads it to decide access.

---

## 8. Conclusions for the deployment

1. Run the eight migrations in one step; they are additive and need no backfill.
2. Expect migration 4 to take as long as a concurrent index build on production's `contacts` takes, with
   writes continuing throughout. Keep `POSTGRES_STATEMENT_TIMEOUT=0` for the step (the deploy script already
   does) and let the post-migration invalid-index check decide whether it finished.
3. If the release has to be withdrawn: **revert the application, keep the schema.** No data is lost and the
   old code cannot tell the difference.
4. Never replay migrations from empty to rebuild this database; `db:schema:load` is the only path that works.

---

## 7. Final state after the clean-room exchange (P-FINAL.CR)

**The replacement added no migration and no schema change.** Verified, not asserted:
`git diff --name-only cbf2a0da..HEAD` matches nothing under `db/migrate`, `custom/db/migrate` or `db/schema.rb`.

Every table, column, enum value and index the replacement uses was then checked against a live database:

| table | result |
|---|---|
| `campaign_recipients` | all 16 columns present |
| `custom_roles` | all 6 columns present |
| `account_users.custom_role_id` | present |
| `audits` | all 17 columns present, including `city`, `country` and `country_code`, which stay unwritten and unread |
| `messages.source_id`, `.status` | present. `external_error` is **not** a column — it is a `store` accessor on `messages.content_attributes` (`app/models/message.rb:112-114`). The integration contract has been corrected to say so |

The three behaviour-carrying indexes on `campaign_recipients` are present with the right properties:

```
index_campaign_recipients_on_campaign_id_and_contact_id   unique=true
index_campaign_recipients_on_source_id                    unique=true  where=(source_id IS NOT NULL)
index_campaign_recipients_on_campaign_id_and_status        unique=false
```

**The `campaign_recipients.status` enum: the one true blocker of this release, found after integration and
closed.** This review's first pass stated the mapping as `queued 0, sent 1, delivered 2, read 3, failed 4,
skipped 5` and added "unchanged from before the exchange". Both halves were wrong, and the post-integration
migration audit proved it from the repository's own history.

The mapping the production rows carry — written by the code that wrote them, identical at the production
baseline `b03ea43d` and at `487276f2^`, the last commit before the removal — is:

```
queued 0, skipped 1, sent 2, delivered 3, read 4, failed 5
```

The clean-room specification's data contract (`clean-room/specs/D-campaign-recipient-outcomes.md` §3) gave the
*funnel* order instead, and hedged it with "confirm the remaining mappings against the production database
before the first deploy" — a confirmation that never happened. The replacement model was written to that table,
faithfully, and no migration remaps the column, so had this shipped every existing row would have been read as
the next state along: a skipped recipient as sent, a sent one as delivered, a read one as failed. Nothing would
have errored; the analytics would simply have been wrong, in a direction that flatters the product.

It is now corrected in the model, in the specification, and — since a comment is not a check — pinned as an
assertion on the integers themselves in `spec/requests/p_final/integration_corrections_spec.rb`. **No data
migration is required**, because the stored integers were never changed; only the code's reading of them was,
and it is back to the store's. Nothing else in the package depends on the declaration order: `LADDER` is keyed
by name, `metrics.rb` queries by name, and `RecipientMetrics::STATES` takes the names.

The lesson for the register: a clean-room specification may restate a stored encoding, and if it does, the
encoding has to be read off the code that wrote the rows — not reconstructed from the shape of the funnel.

| | |
|---|---|
| pending migrations | none |
| schema version | `20261010110100` |
| migration files | 24 under `custom/db/migrate`, 180 under `db/migrate` |

### 7.1 Rollback tolerance of the exchange specifically

Rolling the **code** back across the exchange is safe in both directions, because the exchange is code-only:

- no column was added, so old code reads the same schema;
- the replacement writes the same columns the removed implementation wrote, with the same meanings — the
  `status` ladder, the four timestamps, the three error fields, `source_id`, `message_content`;
- one difference is worth naming because it is deliberate: the replacement **never** stamps `failed_at` on a
  recipient that already reached `delivered` or `read`, where the previous writer could leave a row carrying
  both a delivery and a failure timestamp. A row written by the replacement is therefore a *subset* of the
  shapes old code could produce, so old code reads it correctly. A row written by the OLD code that carries
  both timestamps is still read correctly by the new analytics, which count delivery and failure independently
  — it would be counted in both, as it always was.

Nothing else in the exchange touches persisted state. `custom_roles`, `audits` and the membership attachment
are written exactly as before.

---

## 8. Deploy-time state this release leaves behind

Three things exist in a running installation at the moment of the restart that are not rows in a table, and
each needs a decision rather than an assumption.

### 8.1 Sidekiq holds jobs for a class this release deleted

`Campaigns::UpdateRecipientStatusJob` is gone — removed with the Enterprise-derived set and deliberately not
re-created, because `Whatsapp::DeliveryReport` now resolves a report against the recipient row directly. At the
production baseline it was enqueued **with a delay**, and with retries:

```
Campaigns::UpdateRecipientStatusJob.set(wait: 2.seconds).perform_later(inbox.id, status.to_h)
retry_on RecipientNotFoundError, wait: ->(executions) { executions * 2.seconds }, attempts: 5
```

so instances sit in Sidekiq's **scheduled and retry sets**, not only in the ready queue, for up to about half a
minute after the last report that produced one. After the restart, each of those raises `NameError` when
Sidekiq tries to constantize the class, retries on the generic backoff, and ends in the dead set.

**Decision: let them die, and quiet the queues first.** Nothing is lost. The job existed only for a report that
matched neither a recipient row nor a message — the case where the recipient had not yet been written — and the
replacement writes the recipient row before the send rather than after it, so the case it covered no longer
arises. A compatibility shim would be dead code from the day it shipped.

What the deploy must do, and what `deployment/deploy.sh` and `08-production-uat-runbook.md` now say: quiet the
Sidekiq workers and let the in-flight set drain before the restart, rather than restarting under load. That is
the right order for any deploy of this size; this class is simply the one that makes it mandatory rather than
merely tidy.

### 8.2 Redis holds filtered unread counts under the old visibility

The counts are versioned per member, and a version bump is what invalidates them. This release adds one bump
the exchange had dropped — editing a permission set's capability list now invalidates every holder — but the
counts cached *before* the deploy were computed under whatever the member's capabilities were then. They are
not wrong, they are simply stale until the member's next visibility change or the version's TTL.

**Decision: no action.** The window is one TTL, the values are counts rather than access, and no capability
check anywhere reads the cache. Clearing the whole store at deploy time would cost every account a full rebuild
to save a stale badge number.

### 8.3 The skip-reason wording changed, so a cross-deploy breakdown has two spellings

P8 groups its campaign skip breakdown on `campaign_recipients.error_message` directly, and the replacement's
reason strings are its own wording, not the removed implementation's (`'Campaign has no template parameters'`
where the old code wrote `'Template parameters are missing'`, and so on; two of the six reasons have no
predecessor at all).

**Decision: keep the new wording.** A campaign's rows all come from one run, so within a campaign — which is
the only place the page shows this breakdown — the wording is consistent. An account-wide breakdown spanning
the deploy would list both spellings as separate buckets, which is accurate rather than misleading: they are
different runs under different code. Rewriting historical rows to match new copy would be a data migration
whose only product is a tidier chart.
