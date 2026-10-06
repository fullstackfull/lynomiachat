# 02 — The local template record: exact schema, identity, and rollback

Written **before** the migration, as PART 24 requires. This is the one migration P3 is authorised to add.
A second migration stops for approval.

---

## 1. Why a local record is necessary (re-confirmed at this HEAD, not assumed)

`app/services/whatsapp/providers/whatsapp_cloud_service.rb:43`:

```ruby
whatsapp_channel.update_columns(message_templates: templates, message_templates_last_updated: Time.current)
```

The sync replaces the **entire** jsonb document. A local draft kept inside it is destroyed by the next sync, which
runs at most three hours later (`templates_sync_scheduler_job.rb:8`, `config/schedule.yml:12-15`). The 360dialog
sibling does the same with `update` (`whatsapp_360_dialog_service.rb:31`).

There is no per-template table anywhere in the schema: `db/schema.rb` has 108 `create_table` statements and the only
`templ` match is `email_templates` (`:1217`), which is transactional email. Verified again at this HEAD.

So a draft that survives a sync, and a per-template lifecycle that Meta does not store for us, need one new table.
Nothing else in P3 needs schema.

---

## 2. The table

`custom/db/migrate/20261005100000_create_whatsapp_message_templates.rb`

```ruby
# Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/02-local-record-design.md): the templates an
# account manages, both local drafts that Meta has never seen and the mirror of the templates Meta holds. Meta stays
# authoritative for remote status; this table is where a draft lives and where lifecycle timestamps are kept.
# Identity follows Meta's: (WABA, name, language), scoped to the account. The channel's message_templates jsonb
# snapshot is unchanged and keeps being written exactly as before.
class CreateWhatsappMessageTemplates < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_message_templates do |t|
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string   :business_account_id, null: false
      t.string   :name,                null: false
      t.string   :language,            null: false
      t.string   :category,            null: false
      t.string   :parameter_format,    null: false, default: 'POSITIONAL'
      t.jsonb    :components,          null: false, default: []
      t.string   :meta_template_id
      t.string   :meta_status
      t.jsonb    :meta_payload,        null: false, default: {}
      t.datetime :meta_synced_at
      t.datetime :submitted_at
      t.string   :submission_error, limit: 1000
      t.timestamps
    end

    add_index :whatsapp_message_templates,
              'account_id, business_account_id, name, lower(language)',
              unique: true, name: 'index_whatsapp_message_templates_on_identity'

    add_index :whatsapp_message_templates, %i[account_id meta_template_id],
              unique: true, where: 'meta_template_id IS NOT NULL',
              name: 'index_whatsapp_message_templates_on_meta_id'
  end
end
```

Model: `Whatsapp::MessageTemplate` at `custom/app/models/whatsapp/message_template.rb`, with
`self.table_name = 'whatsapp_message_templates'`
(the `custom/` convention — `custom/app/models/commerce/store.rb` does the same). The explicit `table_name` is
required: without a `table_name_prefix` on the `Whatsapp` module, Rails would infer `message_templates`.

### Every column, and the P3 consumer that reads it

No column is here on the chance it is useful later. Each one is named with the thing that uses it.

| Column | Why it exists |
|---|---|
| `account_id` | Tenancy. Every query is account-scoped (PART 1.3: one tenant must never see another's template). FK cascades on account deletion. |
| `business_account_id` | The WABA. Meta's identity scope, and an account can have several (`§4.2` of `00-current-system.md`). Denormalised from `provider_config['business_account_id']`, which is a jsonb key and not a column. |
| `name` | Meta's template name. Part of remote identity; required by create. |
| `language` | Meta's language code. Part of remote identity; names are **not** unique across languages. |
| `category` | `UTILITY` / `MARKETING` / `AUTHENTICATION`. Required by create and edit; the manager filters on it. |
| `parameter_format` | `POSITIONAL` / `NAMED`. Required by create; `Whatsapp::TemplateProcessorService:83` reads it to decide parameter ordering, and the builder needs it to render placeholders. Not derivable without guessing. |
| `components` | The Meta-shaped components payload, stored as Meta sends/accepts it (jsonb, per PART 1.2). The builder edits it, the preview renders it, the submit posts it. |
| `meta_template_id` | Meta's template id. Null until Meta has it. Required for edit (`POST {template_id}`) and for delete-by-id. |
| `meta_status` | The remote status **verbatim** from Meta (`APPROVED`, `PENDING`, `REJECTED`, `PAUSED`, `DISABLED`, `IN_APPEAL`, `LIMIT_EXCEEDED`, `PENDING_DELETION`, `ARCHIVED`, `DELETED`). A string, not an enum, because Meta owns this vocabulary and adds to it. Null for a local draft — which is also why a draft is never shown as "Pending". **Its presence is what makes a row remote**, rather than the id: Meta always reports a status, while a synced template can arrive with no `id` at all (this repo's own factory has such entries, and `WhatsAppCampaignForm.vue:86` already breaks on them), and a row with an id but no status would read as a draft. |
| `meta_payload` | The rest of the remote object as last seen: `rejected_reason`, `quality_score`, `previous_category`, `correct_category`, `sub_category`, `message_send_ttl_seconds`, `library_template_name`, `cta_url_link_tracking_opted_out`. jsonb, so Meta can add fields without a migration, and so the detail view can show what Meta actually said. **Never a column each.** |
| `meta_synced_at` | When this row was last seen in a sync. Two honest uses: freshness in the UI, and absence detection — a mirror pass stamps every template it saw with one timestamp, so a row older than the newest row of its own WABA is one that pass did not see. That is how remote deletion is modelled truthfully without inventing a status (PART 3). It is compared against the WABA's rows, **not** against the channel's `message_templates_last_updated`, because that column is advanced before the fetch (`whatsapp_cloud_service.rb:37`) and so moves even when a fetch comes back empty — comparing against it would report every template as gone after one failed fetch. |
| `submitted_at` | Two honest uses: the "submitted on" fact the UI shows, and the **idempotency claim** for PART 7 — it is set under `with_lock` before the HTTP call, so a double-clicked Submit finds it present and refuses instead of creating a second Meta template. Cleared if the call fails, because the draft must survive (PART 7). |
| `submission_error` | Why the last submit failed, truncated to 1000 chars. On the production path: Meta refuses a create, the user reloads, and a draft with `submitted_at` set and no explanation would be a broken state. Holds the safe structured message only (PART 19: never a credential, never a raw token). |
| `created_at` / `updated_at` | Standard. "Drafted on" in the UI. |

### Deliberately NOT columns

| Not added | Instead |
|---|---|
| `status` (a local lifecycle enum) | **Derived**, so it cannot disagree with itself: `meta_template_id.present?` → remote (and `meta_status` says which); else `submitted_at.present?` → submitting/failed; else draft. A column would be a second truth about the same two facts. |
| `rejected_reason`, `quality_score`, `message_send_ttl_seconds`, `sub_category`, `previous_category`, `correct_category` | Read from `meta_payload`. Meta-shaped data belongs in the jsonb (PART 1.2). P3 does not offer a TTL control, so TTL is recorded, not edited (see `01-meta-api-contract.md`). |
| `created_by_id` / `updated_by_id` | The `audited` gem already records the actor. `custom/app/models/custom/audit/custom_filter.rb` is the Lynomia precedent: `audited associated_with: :account if defined?(Enterprise::AuditLog)`, with `Audited.config.audit_class = 'Enterprise::AuditLog'` (`config/initializers/audited.rb`). The new model gets the same one-line concern, so create/update/destroy and their actor are audited with **no new audit system** (PART 18). |
| `channel_id` / `inbox_id` | The record is WABA-scoped, as Meta's is. Several inboxes can share one WABA (`00-current-system.md §4.2`), so an inbox FK would store the same remote template more than once — exactly what PART 16 forbids. A channel is resolved when one is needed, with the pattern already in the repo: `Channel::Whatsapp.where(account_id:).where("provider_config->>'business_account_id' = ?", waba_id)` (`app/services/whatsapp/webhook_setup_service.rb:100`). |
| `access_token`, any credential | **Never.** PART 1.2. Tokens stay in `provider_config` / `business_management_token`, selected by `Channel::Whatsapp#template_access_token`. |
| A starter-library table | Starters are source-controlled (PART 11), like `app/javascript/dashboard/recipes/`. Using a starter creates an ordinary draft row. Updating a starter therefore cannot mutate anyone's draft. |

---

## 3. Identity, and the two indexes that enforce it

Meta's identity is **(WABA, name, language)**, or the Meta template id. Names are not unique across languages
(`01-meta-api-contract.md`). PART 1.3 is enforced structurally:

**`index_whatsapp_message_templates_on_identity`** — unique on
`(account_id, business_account_id, name, lower(language))`.

- **One tenant cannot see or collide with another's template**: `account_id` leads the key, and every query is
  account-scoped.
- **One WABA cannot overwrite another WABA's same-named template**: `business_account_id` is in the key, so
  `order_update/en_US` on WABA A and on WABA B are two rows that never touch.
- **Name alone never deduplicates**: `language` is in the key.
- `lower(language)` because case-insensitive language comparison is already load-bearing everywhere in this codebase
  (`template_processor_service.rb:24`, `custom/app/services/flows/template.rb:18`,
  `contact_info_request_eligibility_service.rb:111`). The stored value stays **verbatim** as Meta gives it
  (`en_US`, not `en_us`), because that is what a submit must send; only the uniqueness check is case-folded.
  `name` is not folded: Meta restricts names to lowercase alphanumerics and underscores.
- It also serves the list query (`account_id, business_account_id` is its prefix), so no extra index is needed.

**`index_whatsapp_message_templates_on_meta_id`** — unique on `(account_id, meta_template_id)`
`WHERE meta_template_id IS NOT NULL`.

- Two rows can never mirror one remote template inside a tenant.
- Partial, so the many drafts with a null id do not collide with each other.
- Scoped by account rather than global, because the same WABA may legitimately be connected by two Lynomia accounts and
  each manages its own view of it.

No index on `meta_status`, on `(name)` alone, or on `components`. An account holds tens to low hundreds of templates;
a speculative index would be a guess.

---

## 4. The migration is additive, and that is checkable

| PART 1.4 requirement | How this migration satisfies it |
|---|---|
| Must not delete or rewrite `channel_whatsapp.message_templates` | The migration contains one `create_table` and two `add_index`. It does not name `channel_whatsapp` at all. |
| No network calls | No `HTTParty`, no service call, no job enqueue. The file is 25 lines of DDL. |
| No backfill of thousands of remote records | **The table starts empty.** Nothing is copied in the migration. Remote rows arrive from the stored jsonb snapshot, with no network, the first time the mirror runs (see `03-sync-and-lifecycle.md`): the already-scheduled sync writes both stores, and a read reconciles from the snapshot when `message_templates_last_updated` is newer than the newest `meta_synced_at`. |
| Safe indexes | Two indexes on a table created empty in the same migration, so there is nothing to lock and `CONCURRENTLY` is neither needed nor usable inside the transaction. |
| Works with existing production data | It touches none. Every existing channel keeps its jsonb and its timestamp; every existing read path keeps reading the jsonb (`00-current-system.md §5`). |
| Rollback | See below. |

### Rollback

```
bin/rails db:rollback   # or: db:migrate:down VERSION=20261005100000
```

`create_table` + `add_index` are fully reversible by Rails, so `change` needs no `up`/`down`. The down migration
issues `DROP TABLE whatsapp_message_templates` and nothing else.

**What a rollback costs:** every local draft is lost, because a draft exists nowhere else — that is the point of the
table. Nothing about the templates Meta holds is lost: they are still at Meta, and still in each channel's jsonb
snapshot, which this phase keeps writing byte-for-byte as before. A rollback therefore returns the product to exactly
today's behaviour: a read-only template list fed by the jsonb.

Application code and schema roll back together, as usual — the new read paths require the table.

---

## 5. Who reads and who writes each store (PART 2, no split-brain)

| Store | Writers | Readers | Status in P3 |
|---|---|---|---|
| `channel_whatsapp.message_templates` jsonb | **only** `WhatsappCloudService#sync_templates:43` and `Whatsapp360DialogService#sync_templates:31`, unchanged | every consumer listed in `00-current-system.md §5` — composer pickers, campaign form, flow editor, `TemplateProcessorService`, `AuthenticationTemplateGuard`, `ContactInfoRequestEligibilityService`, `Flows::Template`, the inbox jbuilder, the `message_templates` endpoint | **kept, unchanged, not deleted this phase.** It stays the snapshot of what Meta holds. |
| `whatsapp_message_templates` rows | `Whatsapp::Templates::Mirror` (from the snapshot — no network) and the manager's own create/edit/submit/delete actions | `Whatsapp::Templates::Query`, which the manager UI, the campaign selector and the flow selector read through | **new.** Authoritative for drafts and for lifecycle timestamps; a mirror, never an authority, for remote status. |

The rule that keeps the two coherent:

- **Remote truth flows one way only** — Meta → snapshot → mirror → rows. The mirror never writes to the snapshot and
  never invents a remote fact.
- **Local truth has exactly one home** — a draft, `submitted_at`, `submission_error` exist only in the table and are
  never written into the snapshot.
- **The mirror never touches a draft.** Its write set is `meta_template_id IS NOT NULL` plus the row whose
  `(waba, name, lower(language))` matches a template in the snapshot. A draft Meta has never seen is outside that set
  structurally, not by a conditional — which is PART 3's "a sync must never delete a local draft".
- **One read abstraction.** Every new surface reads `Whatsapp::Templates::Query`; no new surface reads the jsonb
  directly, and no old surface is switched to the table in the same step that introduces it. The query reconciles from
  the snapshots before every read, so no caller can see stale rows, and it answers "what can this inbox send" from the
  snapshot under the existing product rule (`Flows::Template.sendable?` plus Meta's approved status, which is exactly
  what `@chatwoot/utils` `isSendableTemplate` applies on the client) — a send must never depend on a projection having
  run.

---

## 6. Derived state, in one place

```ruby
# custom/app/models/whatsapp/message_template.rb
def local_state
  return :remote      if meta_status.present?
  return :submitting  if submitted_at.present?
  :draft
end

def sendable?   # the live gate for an actual send stays the channel snapshot, read through Flows::Template
  meta_status.to_s.casecmp?('APPROVED')
end

# The caller passes the newest meta_synced_at among that WABA's rows.
def missing_at_meta?(waba_mirrored_at)
  remote? && meta_synced_at.present? && waba_mirrored_at.present? && meta_synced_at < waba_mirrored_at
end
```

A `draft`, `submitting` or `rejected` record can never be sendable, because `sendable?` requires Meta's own
`APPROVED`, and `meta_status` is never a permitted parameter on any endpoint — it is written only by a sync or from
Meta's own response, so no client can fake an approval. That is the structural half of PART 2.2; the
other half is the `TemplateProcessorService` fix in `00-current-system.md §6.1`.

**State vocabulary for the UI** (PART 5, and reusing the key that already exists with no producer,
`WHATSAPP_TEMPLATE_MGMT.STATUSES.UNSUBMITTED` at `i18n/locale/en/whatsappTemplateMgmt.json:22`):

| Record | Shown as | Never shown as |
|---|---|---|
| no `meta_template_id`, no `submitted_at` | **Draft — not submitted for WhatsApp approval** | "Pending" |
| `submitted_at`, no `meta_template_id`, no error | **Submitting…** | "Pending" |
| `submitted_at`, no `meta_template_id`, `submission_error` | **Submission failed** + the safe message | "Rejected" (Meta never saw it) |
| `meta_status = PENDING` | **In review at WhatsApp** | — |
| `meta_status = APPROVED` | **Approved** | — |
| `meta_status = REJECTED` | **Rejected by WhatsApp** + `meta_payload['rejected_reason']` | — |
| `meta_status` present, `missing_at_meta?` | **No longer at WhatsApp** (last seen <date>) | silently deleting the row |
