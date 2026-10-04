# Lynomia Contacts: what the product already has

Read-only trace of the Contact, Label, Import, bulk-action and bridge code across the three trees — `app/` (Community),
`enterprise/` (Enterprise overlay), `custom/` (Lynomia overlay) — before any Contacts change.

Branch `claude/practical-thompson-9xfqed`, HEAD `23f9cbbd`.

Every claim below carries `file:line`. Nothing in this phase changed product code.

---

## 0. Where the Contacts surfaces actually live

The Contacts route tree is **`app/javascript/dashboard/routes/dashboard/contacts/routes.js`** — note the filename. It is
*not* `contacts.routes.js`, so a glob of the form `**/*.routes.js` does not match it. The UI/UX phase was bitten by
exactly this (`docs/ui-modernization/FINAL-CHECKPOINT.md`, route-count correction), so the tree is enumerated here by
hand rather than discovered.

| Route name | Path | File |
|---|---|---|
| `contacts_dashboard_index` | `accounts/:accountId/contacts` | `contacts/routes.js:17-22` |
| `contacts_dashboard_segments_index` | `…/contacts/segments/:segmentId` | `contacts/routes.js:23-28` |
| `contacts_dashboard_labels_index` | `…/contacts/labels/:label` | `contacts/routes.js:29-34` |
| `contacts_dashboard_active` | `…/contacts/active` | `contacts/routes.js:35-40` |
| `contacts_edit` | `…/contacts/:contactId` | `contacts/routes.js:48-53` |
| `contacts_edit_segment` | `…/contacts/:contactId/segments/:segmentId` | `contacts/routes.js:54-59` |
| `contacts_edit_label` | `…/contacts/:contactId/labels/:label` | `contacts/routes.js:60-65` |

All seven are gated by `featureFlag: FEATURE_FLAGS.CRM` and
`permissions: ['administrator', 'agent', 'contact_manage']` (`contacts/routes.js:6-9`).

Components behind them:

| Surface | Component |
|---|---|
| List / segment / label / active list | `routes/dashboard/contacts/pages/ContactsIndex.vue` |
| Contact detail | `routes/dashboard/contacts/pages/ContactManageView.vue` → `components-next/Contacts/Pages/ContactDetails.vue` |
| List chrome, search, sort, filters, header actions | `components-next/Contacts/ContactsListLayout.vue`, `components-next/Contacts/ContactsHeader/ContactListHeaderWrapper.vue` |
| Rows | `components-next/Contacts/Pages/ContactsList.vue` |
| Bulk bar | `routes/dashboard/contacts/components/ContactsBulkActionBar.vue` |
| Create / import / export / segment dialogs | `components-next/Contacts/ContactsForm/{CreateNewContactDialog,ContactImportDialog,ContactExportDialog,CreateSegmentDialog,DeleteSegmentDialog,ContactMergeForm}.vue` |
| Contact labels widget | `components-next/Contacts/ContactLabels/ContactLabels.vue` |
| Legacy conversation-sidebar contact panel | `routes/dashboard/conversation/contact/{ContactInfo,ContactForm}.vue` |

Sidebar: the Contacts group has **Segments** children (from `customViews`) and a **"Tagged With"** group whose children
are *every label in the account* (`components-next/sidebar/Sidebar.vue:569-591`), each linking to
`contacts_dashboard_labels_index` with `{ label: label.title }`. The list is not filtered to labels that are actually
used on a contact — see §8.

---

## 1. A1 — Contact lifecycle

### 1.1 Model

`app/models/contact.rb:44-70`.

| | |
|---|---|
| Concerns | `Avatarable`, `AvailabilityStatusable`, **`Labelable`**, `LlmFormattable` (`:45-48`) |
| Validations | `account_id` presence (`:50`); `email` blank-allowed, unique per account case-insensitive, `Devise.email_regexp` (`:51-52`); `identifier` blank-allowed, unique per account (`:53`); `phone_number` blank-allowed, unique per account, format `/\A\+[1-9]\d{1,14}\z/` (`:54-56`) |
| Associations | conversations, contact_inboxes, csat_survey_responses, inboxes, messages (as sender), notes — all `dependent: :destroy_async` (`:59-65`) |
| Callbacks | `before_validation :prepare_contact_attributes` (`:66`); `after_create_commit :dispatch_create_event, :ip_lookup` (`:67`); `after_update_commit :dispatch_update_event` (`:68`); `after_destroy_commit :dispatch_destroy_event` (`:69`); `before_save :sync_contact_attributes` (`:70`) |
| Enum | `contact_type: { visitor: 0, lead: 1, customer: 2 }` (`:72`) |
| Resolved scope | `resolved_contacts(use_crm_v2:)` — `contact_type = lead` with `crm_v2`, else email/phone/identifier present (`:183-187`) |

`before_save :sync_contact_attributes` (`:69`, body at `:233-235`) delegates to `Contacts::SyncAttributes`
(`app/services/contacts/sync_attributes.rb`), which copies city/country out of `additional_attributes` into the
columns and promotes `visitor` → `lead`. The three dispatchers are `CONTACT_CREATED` / `CONTACT_UPDATED` (with
`changed_attributes: previous_changes`) / `CONTACT_DELETED` (`:237-253`). Extension point: `include_mod_with` at the
file's last line.

**Uniqueness is not symmetric at the database.** `db/schema.rb:946-948`:

```ruby
t.index ["email", "account_id"],      name: "uniq_email_per_account_contact",      unique: true
t.index ["identifier", "account_id"], name: "uniq_identifier_per_account_contact", unique: true
t.index ["phone_number", "account_id"], name: "index_contacts_on_phone_number_and_account_id"   # NOT unique
```

Email and identifier are protected by unique indexes; **phone number is protected only by the model validation**
(`contact.rb:54-56`). Any write path that skips validations can therefore create duplicate phone numbers — see §1.6.

Enterprise overlay `enterprise/app/models/enterprise/concerns/contact.rb`: `belongs_to :company`,
`has_many :campaign_recipients`, company association from email, `company_name` sync, company activity recording.

`custom/` adds **no** Contact model code. `grep -rln "label_list\|add_labels\|update_labels\|tagged_with" custom/`
returns nothing — the Lynomia overlay does not touch labels at all today.

### 1.2 Create

`app/controllers/api/v1/accounts/contacts_controller.rb:85-92`:

```ruby
def create
  ActiveRecord::Base.transaction do
    @contact = Current.account.contacts.new(permitted_params.except(:avatar_url))
    @contact.save!
    @contact_inbox = build_contact_inbox
    process_avatar_from_url
  end
end
```

`permitted_params` (`:173-175`):

```ruby
params.permit(:name, :identifier, :email, :phone_number, :avatar, :blocked, :avatar_url,
              additional_attributes: {}, custom_attributes: {})
```

**`labels` is not permitted on create or update.** Enterprise extends this list with `company_id` only
(`enterprise/app/controllers/enterprise/api/v1/accounts/contacts_controller.rb:4-10`). The controller ends with
`prepend_mod_with('Api::V1::Accounts::ContactsController')` (`:218`) — the available extension point.

### 1.2b Every path that creates a Contact

`contacts_controller#create` is one of six families. The others matter because any fix applied only at the dashboard
controller leaves them untouched.

| Path | Entry | Validations / callbacks |
|---|---|---|
| Dashboard / application API | `contacts_controller.rb:85-92` | full |
| Public inbox API | `public/api/v1/inboxes/contacts_controller.rb:7` (`config/routes.rb:629`) | full |
| Widget identify | `ContactIdentifyAction` on an already-built widget contact | full, `discard_invalid_attrs: true` |
| Every inbound channel | `app/builders/contact_inbox_with_contact_builder.rb:16` — SMS, Telegram, Line, TikTok, Facebook, Instagram, Twitter, email mailbox, web widget | full |
| Legacy CSV import | `DataImportJob` → `Contact.import(..., validate: true)` (`data_import_job.rb:77`) | validated, callbacks skipped by bulk import |
| Intercom / Freshdesk import | `DataImports::Importer` — **`Contact.insert_all!` (`:286`) and `contact.update_columns` (`:316`)** | **none** — no validations, no callbacks, no `CONTACT_CREATED` |

The integration importer compensates with its own normalizer: `E164_REGEX` at `:17`, `normalized_phone` at `:850-854`
(prefix `+` when the number matches `PHONE_WITHOUT_PLUS_REGEX`, then **drop to `nil`** unless it matches E.164). So it
is defensive — but it is a **third** independent phone implementation, after `ContactManager#format_phone_number` and
`Commerce::Phone`.

There is **no Platform (super-admin) Contact API**: `config/routes.rb:598-620` exposes users, agent_bots, accounts,
account_users and email_channel_migrations only.

`blocked` is settable directly through `permitted_params` on create and update (`:174`).

### 1.3 Read / list / search / filter

| Action | Line | Notes |
|---|---|---|
| `index` | `:19-22` | `resolved_contacts` → `fetch_contacts`, 15 per page (`RESULTS_PER_PAGE`, `:12`) |
| `search` | `:24-32` | `ILIKE` over name/email/phone/identifier; `fetch_contacts_with_has_more` |
| `active` | `:53-58` | `OnlineStatusTracker` ids |
| `filter` | `:62-72` | `Contacts::FilterService`; rescues the four `CustomExceptions::CustomFilter::*` into 422 |
| `show` | `:60` | |
| `destroy` | `:100-110` | refuses while the contact is online (422, `contacts.online.delete`) |

`resolved_contacts` (`:120-127`) is where the **`labels` request param is consumed**:

```ruby
@resolved_contacts = @resolved_contacts.tagged_with(params[:labels], any: true) if params[:labels].present?
```

That is a **list filter**, not an assignment. See §8.

### 1.4 Update

`:94-98`. `contact_update_params` (`:189-193`) merges `custom_attributes` / `additional_attributes` onto the existing
hashes rather than replacing them.

### 1.5 Identify / merge (the duplicate-resolution path)

`app/actions/contact_identify_action.rb` — used by widget and public API identification, **not** by dashboard create.
In one transaction (`:15-20`) it merges an existing contact found by identifier (`:30-34`), then email (`:36-40`), then
phone number (`:42-47`), then updates. Guards: a different `identifier` blocks the merge and drops that key from the
update list (`:72-85`); an email mismatch blocks a phone-number merge (`:90-98`). `discard_invalid_attrs` is opt-in and
set only by the two widget controllers (`api/v1/widget/conversations_controller.rb:24`,
`api/v1/widget/contacts_controller.rb:41`).

`app/actions/contact_merge_action.rb` — the explicit merge.
`POST /api/v1/accounts/:account_id/actions/contact_merge` (`config/routes.rb:55-57`) →
`Api::V1::Accounts::Actions::ContactMergesController` (both contacts looked up through `Current.account.contacts`, so a
cross-account id is a 404 and reveals nothing). It moves conversations (`:34-36`), messages (`:42-44`), contact inboxes
(`:46-48`), notes (`:38-40`), calls (Enterprise, `enterprise/app/actions/enterprise/contact_merge_action.rb:4-6`), then
destroys the mergee and merges attributes with base preference (`:54-66`).

**`mergable_attribute_keys` is `%w[identifier name email phone_number additional_attributes custom_attributes]`
(`:55`) — labels are not in it, and the mergee is destroyed (`:62`). Merging two contacts therefore loses the mergee's
labels.** Recorded as a finding; not in the brief's scope.

### 1.6 Which paths can bypass which guard

| Guard | Enforced by | Bypassable by |
|---|---|---|
| Email uniqueness per account | model validation + `uniq_email_per_account_contact` unique index | nothing |
| Identifier uniqueness per account | model validation + `uniq_identifier_per_account_contact` unique index | nothing |
| **Phone uniqueness per account** | **model validation only** (`contact.rb:54-56`); the index is not unique | `DataImports::Importer`'s `insert_all!` (`:286`) |
| E.164 format | model validation (`contact.rb:54-56`) | the same `insert_all!` — mitigated there by `normalized_phone` (`:850-854`) dropping a bad number to `nil` |
| Email format | model validation | the same |

### 1.7 Policy

`app/policies/contact_policy.rb`: `index?`, `active?`, `search?`, `filter?`, `update?`, `show?`, `create?`, `avatar?`,
`contactable_inboxes?`, `destroy_custom_attributes?` → everyone with contacts access. `import?`, `export?`, `destroy?`
→ administrator only (`:10-16`, `:50-52`). Enterprise adds the `contact_manage` custom-role permission to `import?` and
`export?` (`enterprise/app/policies/enterprise/contact_policy.rb`).

Neither `Contact` nor `Label` is audited (`grep audited` in both models returns nothing).

---

## 2. A2 — Label system

### 2.1 Storage

`acts-as-taggable-on`, one line: `app/models/concerns/labelable.rb:4-6` — `acts_as_taggable_on :labels`. The concern is
included by `Contact` (`contact.rb:47`) and by `Conversation`. Taggings carry `taggable_type` (`'Contact'` /
`'Conversation'`) and `context` (`'labels'`). **Contact labels are a first-class, supported feature of the schema; there
is no Contact-specific tag table and none is needed.**

`Labelable` gives two writers: `update_labels(labels)` → `update!(label_list: labels)` (`:8-10`) and
`add_labels(new_labels)` → union then `update!` (`:12-18`).

Three properties of the store matter later:

- `tags` and `taggings` are **global** tables (`db/schema.rb:1644,1663`), not account-scoped. Tenancy comes from the
  `taggable_id` always being resolved through `Current.account.contacts` — e.g.
  `Labels::DestroyService#contact_label_taggings` pins `taggable_id: account.contacts.select(:id)` (`:47`).
- Contacts have **no `cached_label_list` column**; `Conversation` does. Every read of a contact's labels is a
  `taggings` join.
- `update_labels` performs **no validation against the account's `Label` catalogue**. `acts-as-taggable-on`
  (12.0.0) creates the `tags` row on demand, so the nested endpoint will accept any string. The catalogue is enforced
  only by the CSV importer (`data_import_job.rb:50`), the CSV exporter
  (`account/contacts_export_job.rb:39-41,50`), campaign audiences (`campaign.rb:72`) and the dashboard UI
  (`ContactLabels.vue:31-34` only offers `labels/getLabels`).

### 2.2 The account's label catalogue

`app/models/label.rb:19-55`. `title` is required, lowercased on validation (`:33-35`), matched against
`UNICODE_CHARACTER_NUMBER_HYPHEN_UNDERSCORE`, unique per account (`:25-28`). Helper associations are
**conversation-only**: `#conversations`, `#messages`, `#reporting_events` (`:37-47`). There is no `Label#contacts`.

CRUD: `Api::V1::Accounts::LabelsController` (`index`, `show`, `create`, `update`, `destroy`), permitted
`:title, :description, :color, :show_on_sidebar` (`:39-41`).

### 2.3 Rename and delete are already Contact-aware

| | |
|---|---|
| Rename | `label.rb:30` `after_update_commit :update_associated_models` → `Labels::UpdateJob` → `Labels::UpdateService`, which rewrites taggings for **conversations (`:5-11`) and contacts (`:13-19`, `tagged_contacts` at `:28-30`)** |
| Delete | `labels_controller.rb:19-31` → `Labels::RemoveAssociationsJob` → `Labels::DestroyService`, which removes conversation taggings (`:12-24`) **and contact taggings (`:26-30`, `contact_label_taggings` at `:46-48`)**, scoped to `taggings.created_at <= label_deleted_at` (`:56-61`) |

So the whole Label lifecycle already accounts for Contact taggings. Nothing to add there.

### 2.4 Per-contact label API

Routes (`config/routes.rb:239-246`, `scope module: :contacts`): `resources :labels, only: [:create, :index]` →

- `GET  /api/v1/accounts/:account_id/contacts/:contact_id/labels`
- `POST /api/v1/accounts/:account_id/contacts/:contact_id/labels`

`Api::V1::Accounts::Contacts::LabelsController` includes `LabelConcern` and permits `labels: []` (`:10-12`).
`LabelConcern#create` is `model.update_labels(permitted_params[:labels])` (`:2-5`) — a **full replace**, not an add.
Views render `json.payload @labels`, an array of titles
(`app/views/api/v1/accounts/contacts/labels/{index,create}.json.jbuilder`).

### 2.5 Frontend

| | |
|---|---|
| API client | `dashboard/api/contacts.js:49` `getContactLabels`, `:59-61` `updateContactLabels(contactId, labels)` → `POST {url}/{contactId}/labels` |
| Store | `dashboard/store/modules/contactLabels.js` — `get` (`:23-41`), `update` (`:42-63`), `setContactLabel` (`:64-66`), records keyed by contact id |
| Widget | `components-next/Contacts/ContactLabels/ContactLabels.vue` — reads `labels/getLabels` + `contactLabels/getContactLabels`, toggles one label at a time and posts the full new list (`:57-87`) |
| Mounted on | **only** `components-next/Contacts/Pages/ContactDetails.vue:180` |

Gaps:

- **The contact serializer does not emit labels.** `app/views/api/v1/models/_contact.json.jbuilder` (21 lines) has no
  `json.labels`. The only way the client learns a contact's labels is the dedicated `/labels` endpoint, one request per
  contact. A list of 15 contacts cannot show their labels without 15 extra requests.
- **There is no authorization on the per-contact label endpoint.**
  `Api::V1::Accounts::Contacts::LabelsController` never calls `authorize` or `check_authorization`, its parent
  `Api::V1::Accounts::Contacts::BaseController` only does `ensure_contact` (`:6-8`), and `verify_authorized` appears
  nowhere in `app/controllers`, `enterprise/app/controllers` or `custom/app/controllers`. So any authenticated member
  of the account — or any valid access token on an API-enabled account — can read and overwrite any contact's labels.
  Tenancy still holds (`Current.account.contacts.find`, so another account's id is a 404), but role gating does not.
- **There is no route to remove one label.** `resources :labels, only: [:create, :index]` (`config/routes.rb:242`);
  removal means POSTing the shorter full list, which is what the UI does (`ContactLabels.vue:69-76`).
- `ContactLabels.vue:84-86` — `catch (error) { // error }`. A failed label write is silent.
- The conversation-sidebar contact panel (`routes/dashboard/conversation/contact/`) has **no** contact-label control
  (`grep -rn "contactLabels\|ContactLabel"` over that directory returns nothing). An agent inside a conversation cannot
  label the contact.
- **A contact label change is not broadcast.** `CONTACT_UPDATED` does fire (`contact.rb:68,241`) but neither
  `push_event_data` (`:150-164`) nor `webhook_data` (`:166-180`) carries labels, so websocket and webhook consumers
  never see the change.
- No `Label#contacts` association (`label.rb:37-47`); a reverse lookup is always
  `account.contacts.tagged_with(title)`, as in `Labels::UpdateService:29` and `Campaign#audience_contacts:72`.
- No Platform (super-admin) API for contact labels.

### 2.6 Labels as a filter condition

`lib/filters/filter_keys.yml:75-81` (contacts section): `labels`, `attribute_type: standard`, `data_type: labels`,
operators `equal_to`, `not_equal_to`, `is_present`, `is_not_present`. SQL is built by
`FilterService#tag_filter_query` (`app/services/filter_service.rb:128-142`) as an `EXISTS` subquery over `taggings`
pinned to the entity's `taggable_type`. Frontend attribute entry: `contactFilterItems/index.js:97`.

So "contacts with label X" is already expressible both as a route (`/contacts/labels/:label`) and as a saved
audience condition.

One asymmetry: the `labels` query param is read in `resolved_contacts` (`contacts_controller.rb:120-127`), which
`index`, `search`, `filter` and `export` reach, but **`#active` builds its own scope** (`:53-58`) and is therefore not
label-filterable.

Enterprise reads contact labels in two places: `Captain::AudienceMatcher` uses `@contact.label_list`
(`enterprise/app/services/captain/audience_matcher.rb:60`), and `app/services/llm_formatter/contact_llm_formatter.rb:23`
puts them in LLM context.

---

## 3. A3 — Import system

### 3.1 Two unrelated importers share one table

`DataImport` (`app/models/data_import.rb:34-56`) distinguishes:

- `legacy_contacts_csv_import?` — `data_type == 'contacts'`, blank `source_provider` (`:70-72`)
- `integration_import?` — `data_type == source_provider ∈ %w[freshdesk intercom]` (`:82-84`)

`after_create_commit :process_data_import` (`:68`) enqueues `DataImportJob` **only** for the legacy CSV case, with a
one-minute wait for the blob to land (`:128-133`). Integration imports go through
`DataImportsController#create` → `DataImports::CreationService` → a per-source import job (`:146-151`).

### 3.2 The CSV path end to end

| Step | Location |
|---|---|
| Upload | `POST /api/v1/accounts/:account_id/contacts/import` (`config/routes.rb:231`) → `ContactsController#import` (`:34-43`): 422 `errors.contacts.import.failed` when `import_file` is blank, else create `DataImport(data_type: 'contacts')` + attach, `head :ok` |
| Worker | `app/jobs/data_import_job.rb` |
| Row → contact | `DataImport::ContactManager#build_contact` (`app/services/data_import/contact_manager.rb:6-10`) |
| Insert | `Contact.import(..., on_duplicate_key_ignore: true, track_validation_failures: true, validate: true, batch_size: 1000)` (`data_import_job.rb:77`) |
| Rejected rows | `append_rejected_contact` writes `contact.errors.full_messages.join(', ')` into a per-row `errors` column (`:69-72`), and the whole set is attached as `failed_records` CSV (`:157-163`) |
| Notification | `AdministratorNotifications::AccountNotificationMailer#contact_import_complete` / `#contact_import_failed` (`:183-189`) |

### 3.3 The importer already imports labels

This is the single most important A3 finding.

`data_import_job.rb` constants (`:8-10`): `LABELS_DELIMITER = ','`, `LABELS_CONTEXT = 'labels'`,
`CONTACT_TAGGABLE_TYPE = 'Contact'`.

- `extract_labels` (`:65-67`) splits the row's `labels` cell on commas.
- `build_contact_from_row` (`:47-63`) rejects the row when any label is not already an account label
  (`approved_labels` = `account.labels.pluck(:title)`, `:144-146`; error string `"Unknown labels: …"`, `:148-151`).
- `apply_labels_to_contacts` (`:81-87`) bulk-inserts `ActsAsTaggableOn::Tagging` rows with
  `%i[tag_id taggable_type taggable_id context created_at]`, `on_duplicate_key_ignore: true`, batch 1000.
- `taggings_for_contacts` (`:89-102`) resolves each imported contact's id (`contact_for_label_import`, `:118-136`, by
  identifier → email → phone) and de-duplicates against existing taggings (`reject_existing_taggings`, `:104-116`).
- `tags_by_label_name` (`:138-142`) uses `ActsAsTaggableOn::Tag.find_or_create_all_with_like_by_name`.

The shipped sample file `public/downloads/import-contacts-sample.csv` (linked from
`ContactImportDialog.vue:21,71-81`) already has the column:

```
id,name,email,identifier,phone_number,labels,ip_address,company_name,custom_attribute_1,custom_attribute_2
```

— every row leaves it empty, so the capability is shipped but never demonstrated.

**Conclusion: bulk contact labelling by CSV already exists, server-side, batched, idempotent, and label-validated.**

### 3.3b Export already round-trips labels

`app/jobs/account/contacts_export_job.rb`: `LABELS_COLUMN = 'labels'` (`:4`), a **virtual column** in the default set,
preloaded by one query — `ActsAsTaggableOn::Tagging.joins(:tag).where(context: 'labels', taggable_type: 'Contact',
taggable_id: …).where(tags: { name: approved_labels })` (`:43-53`) — and written comma-joined (`:34`). It filters to
the account's label titles (`:39-41`), exactly as the importer validates against them.

So **export → edit the `labels` cell → import** is already a complete, supported bulk-labelling workflow. It is simply
not described anywhere in the product.

### 3.4 Where the CSV importer is weak

| | |
|---|---|
| Feedback | The dashboard alert fires on `head :ok` (`ContactListHeaderWrapper.vue:124-139`), i.e. on upload, not on completion. Rejected rows reach the user **only** by email: `failed_records` is read solely by `account_notification_mailer.rb:29-30` and is exposed by no API, jbuilder or page (`grep -rn failed_records` → 6 hits, all backend) |
| Phone normalization | `ContactManager#format_phone_number` (`:47-49`) is `phone_number.start_with?('+') ? phone_number : "+#{phone_number}"` — a bare `+` prefix. `"96512345678"` → `"+96512345678"` works; `"012345678"` → `"+012345678"` fails the model's `[1-9]` rule and the row is rejected |
| Duplicate policy | `find_existing_contact` (`:20-27`) looks up identifier → email → phone and, when found and valid, **updates** it (`update_contact_with_merged_attributes`, `:51-57`). So the CSV path upserts while the API path 422s |
| Per-row errors | Written but not surfaced (above) |
| Progress | `processed_records` / `total_records` set once at the end (`:153-155`) |

---

## 4. A4 — Bulk-action infrastructure

### 4.1 The shared endpoint

`config/routes.rb:58` — `resource :bulk_actions, only: [:create]` →
`POST /api/v1/accounts/:account_id/bulk_actions`.

`Api::V1::Accounts::BulkActionsController`:

```ruby
case normalized_type           # :18-20, params[:type].camelize
when 'Conversation' then enqueue_conversation_job ; head :ok
when 'Contact'      then check_authorization_for_contact_action ; enqueue_contact_job ; head :ok
else render json: { success: false }, status: :unprocessable_entity
end
```

Common permitted shape (`:62-67`): `params.permit(:type, :action_name, ids: [], labels: [add: [], remove: []])`.
Authorization: `authorize(Contact, :destroy?)` when `action_name == 'delete'` (`:38-44`).

### 4.2 The Contact chain

`Contacts::BulkActionJob` (`app/jobs/contacts/bulk_action_job.rb`, queue `medium`) → `Contacts::BulkActionService`,
which dispatches on payload (`app/services/contacts/bulk_action_service.rb:8-15`):

| Payload | Service |
|---|---|
| `action_name: 'delete'` | `Contacts::BulkDeleteService` — `contacts.find_each(&:destroy!)` |
| `labels: { add: [...] }` | `Contacts::BulkAssignLabelsService` — `contact.add_labels(@labels)` per contact (`:13-15`) |
| `labels: { remove: [...] }` | `Contacts::BulkRemoveLabelsService` — `update!(label_list: contact.label_list - @labels)` (`:13-15`) |
| anything else | logs a warning, returns `{ success: false, error: 'unknown_operation' }` (`:13-14`) |

The dispatch is a sequence of early returns (`:9-11`), so the order is `delete` → `add` → `remove`: a payload carrying
both `labels: { add: [...] }` and `labels: { remove: [...] }` applies **only the add**, silently. The HTTP layer has
already answered `head :ok` by then (`bulk_actions_controller.rb:7-10`), and the job's return value is discarded, so a
caller cannot learn that half its request was dropped. Worth knowing before composing a new payload; no current caller
sends both (`ContactsIndex.vue:333-375` sends one key at a time).

Authorization note: only `delete` is policy-checked (`bulk_actions_controller.rb:38-44`). Bulk label add and remove
are reachable by any member of the account.

All three scope to `@account.contacts.where(id: @contact_ids)`.

### 4.3 The frontend already uses it

`ContactsIndex.vue`:

| Handler | Line | Call |
|---|---|---|
| `assignLabels` | `:333-353` | `BulkActionsAPI.create({ type: 'Contact', ids, labels: { add } })`, success + failure `useAlert`, clears selection, refetches |
| `removeLabels` | `:355-375` | same with `labels: { remove }` |
| `deleteContacts` | `:377-399` | same with `action_name: 'delete'`, closes the confirm dialog |

Bar: `ContactsBulkActionBar.vue` — two `BulkLabelActions` instances (`type="contact"`, one with `action="remove"`,
`:105-117`), reusing the conversation bulk-label component
`dashboard/components/widgets/conversation/conversationBulkActions/BulkLabelActions.vue`, plus a
`Policy :permissions="['administrator']"`-gated delete (`:119-120`). Strings:
`CONTACTS_BULK_ACTIONS.*` (`i18n/locale/en/contact.json:618-640`).

**Conclusion: a server batch path for bulk contact labels exists and is already wired to the UI — one request for N
contacts. Nothing here needs to be built.**

Note the asymmetry worth knowing before touching it: label *assignment* goes contact-by-contact inside the job
(`BulkAssignLabelsService:13-15` calls `add_labels` → `update!` per contact), whereas the CSV importer bulk-inserts
taggings in batches of 1000 (`data_import_job.rb:85-86`). For large selections the importer's shape is the faster one.

---

## 5. A5 — Audience, Campaign and Automation bridges

Already built and documented; repeated here only as the reuse surface.

| Bridge | Mechanism |
|---|---|
| Audience = saved contact filter | `CustomFilter` with `filter_type: contact`; `shared: true` makes it an account-wide audience. See `docs/audience/00-existing-system-discovery.md` §3 |
| Audience conditions | `Contacts::FilterService` + `prepend_mod_with` → `Custom::Contacts::FilterService` (`custom/app/services/custom/contacts/filter_service.rb`): conversation and Commerce conditions in the same condition format, `MAX_CONDITIONS = 10`, `MAX_VALUES = 50` (`:11-12`) |
| Campaign recipients, stock | `Campaign#audience_contacts` (`app/models/campaign.rb:69-72`) → `account.contacts.tagged_with(labels, any: true)` — **labels only** |
| Campaign recipients, Lynomia | `Custom::CampaignAudience` (`custom/app/models/custom/campaign_audience.rb`) — an `audience` entry may be `{ type: 'Audience', id: <custom filter id> }`; resolved with the labels via each audience's `members` (`:12-19`), validated to shared contact filters of the same account on one-off campaigns (`:24-27`) |
| Who consumes it | `app/services/{sms,twilio}/oneoff_sms_campaign_service.rb:18`, `app/services/whatsapp/oneoff_campaign_service.rb:63`, `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb:39`, `custom/app/controllers/api/v1/accounts/campaigns/audience_previews_controller.rb:12` (count preview) |
| Audience → Campaign / Automation (UI) | `dashboard/helper/audienceHelper.js` — `AUDIENCE_QUERY_PARAM = 'audience'`, `audienceIdFromQuery`, `sharedAudiences`, `findSharedAudience`, `audienceConditionFor` (the `contact_audience` automation condition) |
| Automation conditions | `AutomationRules::ConditionsFilterService` + `Custom::AutomationRules::ConditionsFilterService` |

**Automation / flow label actions are conversation-only.** `ActionService#add_label` (`app/services/action_service.rb:37-41`)
and `#remove_label` (`:57-62`) both operate on `@conversation`; the service is constructed as `ActionService.new(conversation)`
(`:4-7`). The Lynomia flow nodes delegate straight to it: `Flows::Nodes::AddLabel#enter` is
`ActionService.new(conversation).add_label(labels)` (`custom/app/services/flows/nodes/add_label.rb:5-8`), and
`Flows::Nodes::RemoveLabel` subclasses it (`remove_label.rb:2-7`). There is a
`custom/app/services/flows/nodes/set_contact_attribute.rb` for contact *attributes*, but **no contact-label action in
Automation or in the Flow Builder.**

---

## 6. A6 — Recipes and presets

`app/javascript/dashboard/recipes/` (`docs/usability/10-recipe-architecture.md`). A recipe is source code, not a
record: no table, no endpoint, created through each object's own API and validation (`index.js:1-23`).

| Catalogue | Count | Ids |
|---|---|---|
| `audiencePresets.js` | 7 | `high_value_buyers`, `repeat_buyers`, `recent_buyers`, `customers_with_active_order`, `customers_with_shipped_order`, `store_customers`, `linked_commerce_customers` |
| `automationRecipes.js` | 7 | `commerce_new_order_routing`, `commerce_order_shipped_label`, `commerce_refund_escalation`, `commerce_event_webhook`, `vip_audience_priority`, `high_value_spend_routing`, `active_order_routing` |
| `flowTemplates.js` | 6 | `commerce_order_tracking`, `commerce_after_sales`, `support_department_routing`, `vip_priority_routing`, `bilingual_welcome`, `whatsapp_welcome_menu` |

The contract already has the vocabulary a Contacts recipe needs: `REQUIREMENTS.LABEL` and
`REQUIREMENTS.CONTACT_FILTER` (`index.js:40,43`), `INPUT_TYPES.LABEL` / `LABELS` / `AUDIENCE` (`index.js:49-52`),
`CATEGORIES.OPERATIONS` (`index.js:29`), and `joinConditions` (`index.js:73-77`). Adding entries is data, not
architecture.

---

## 7. A8 — Phone numbers and duplicates

### 7.1 What enforces E.164

One place: `contact.rb:54-56` — `format: { with: /\A\+[1-9]\d{1,14}\z/, message: I18n.t('errors.contacts.phone_number.invalid') }`.
The message is `config/locales/en.yml:130-131` → `"should be in e164 format"`, so a full message reads
**"Phone number should be in e164 format"**. There is no `ar.yml` translation for it (`config/locales/ar.yml` has
`errors.validations.presence` but no `errors.contacts` subtree).

`Contact#discard_invalid_attrs` (`:187-190`) → private `phone_number_format` (`:206-209`) reverts an invalid number to
`phone_number_was` instead of failing. It is **opt-in**, reached only via
`ContactIdentifyAction(discard_invalid_attrs: true)` (`:10`, `:106`), which only the two widget controllers pass. The
dashboard create/update path never calls it.

### 7.2 Normalization that exists today

| Where | Behaviour |
|---|---|
| CSV import | `DataImport::ContactManager#format_phone_number` (`:47-49`) — prefix `+` when missing. No country awareness. A leading `0` survives and the row is then rejected |
| Lynomia Commerce | **`Commerce::Phone.e164(raw, country = nil)`** (`custom/app/services/commerce/phone.rb:5-11`) — strips a leading `00` to `+`, parses with `TelephoneNumber` (international on its own, local **only** with an explicit country), returns `e164_number` only when `parsed.valid?`. Its own comment states the rule: *"No country and no '+' means no match, never a guess."* Plus `Commerce::Phone.search_term(e164)` (`:15-20`) for the national significant number |
| Who uses it | 12 call sites across `custom/app/services/commerce/` — Woo, Shopify, Salla, Zid normalizers and providers, `conversation_panel.rb:97`, `customer_matcher.rb:41,54` |
| Intercom / Freshdesk import | its own pair of regexes: `E164_REGEX` (`app/services/data_imports/importer.rb:17`) and `normalized_phone` (`:850-854`) — prefix `+` when it matches `PHONE_WITHOUT_PLUS_REGEX`, else **drop the number to `nil`**. No country awareness |
| Elsewhere in Chatwoot | `TelephoneNumber.parse(...).international_number` in `app/services/sms/incoming_message_service.rb:36`, `twilio/incoming_message_service.rb:78,212`, `whatsapp/incoming_message_base_service.rb:213`, `whatsapp/contact_info_response_service.rb:93`, `whatsapp/user_id_rotation_service.rb:122`, `crm/leadsquared/mappers/contact_mapper.rb:34` |

So there are **three independent phone implementations for contact writes** — the CSV importer's `+` prefix, the
integration importer's regex pair, and `Commerce::Phone` — and the dashboard create path has none at all. Only the
third is country-aware, and only the third refuses to guess.

Dependencies already in the repo: **`telephone_number` gem** (`Gemfile:22`, `Gemfile.lock:968` → 1.4.20) and
**`libphonenumber-js`** (`package.json:86` → ^1.11.9).

### 7.3 The frontend phone control

`components-next/phonenumberinput/PhoneNumberInput.vue`:

- Default country/dial code come from the **browser timezone**: `getActiveCountryCode()` / `getActiveDialCode()`
  (`:41-42`) from `shared/components/PhoneInput/helper.js`, which uses `timezone-phone-codes` and
  `countries-and-timezones` over `Intl.DateTimeFormat().resolvedOptions().timeZone`.
- The emitted value is a **raw concatenation**: `emitPhoneNumber` → `` `${activeDialCode.value}${value}` `` (`:115-118`).
  Choosing 🇰🇼 +965 and typing `01234567` produces `+96501234567`.
- Validation is `minLength(2)` + `numeric` on the national part and "is a known dial code" on the prefix (`:45-56`).
  `libphonenumber-js` **is** imported (`:3`) but used only to *parse an incoming* value in the `modelValue` watcher
  (`:147-159`) — never to validate what the user typed against the chosen country.

The legacy forms use the same library the same way: `components/widgets/forms/PhoneInput.vue:3`,
`routes/dashboard/conversation/contact/ContactForm.vue:11`, `components-next/taginput/helper/tagInputHelper.js:1`.

### 7.4 Duplicate behaviour today

| Path | On an existing email / phone / identifier |
|---|---|
| Dashboard / API create (`contacts_controller.rb:85-92`) | `save!` raises `ActiveRecord::RecordInvalid` → 422 `{ message: "Phone number has already been taken", attributes: ["phone_number"] }` (`request_exception_handler.rb:58-64`) |
| Dashboard / API update (`:94-98`) | same |
| CSV import | silently **upserts** the existing contact (§3.4) |
| Widget / public identify | **merges** via `ContactIdentifyAction` (§1.5) |
| Explicit merge | `POST /actions/contact_merge`, agent-initiated |

So nothing auto-merges on a dashboard create, and uniqueness is enforced at the model for all three keys — but at
the **database** only for email and identifier (§1.1). A phone duplicate is therefore reachable through
`DataImports::Importer`'s `insert_all!` (`:286`), which skips the validation; in practice its `normalized_phone`
(`:850-854`) is what prevents it, not a constraint.

---

## 8. A7 — The known failed workflow, traced at HEAD

The brief describes: on `/contacts/labels/:title`, create a contact; the frontend includes the selected label in the
create payload; the server answers 422 (*"Phone number has already been taken"* / *"Phone number should be in e164
format"*); no contact, no label, and the UI does not surface the real failure.

Production evidence was to be treated as established *unless repository inspection materially contradicts it*. It does,
in one respect, so the single reported symptom resolves into **three independent defects**.

### 8.1 The label is not in the create payload — it is a list filter

The cited frontend fragment exists, at `dashboard/api/contacts.js:5-11`:

```js
export const buildContactParams = (page, sortAttr, label, search) => ({
  include_contact_inboxes: false,
  page,
  sort: sortAttr,
  ...(search ? { q: search } : {}),
  ...(label ? { labels: [label] } : {}),
});
```

`buildContactParams` is consumed by `get()` and `search()` — the **list and search** calls. `create(data)` is
`ApiClient#create`, `axios.post(this.url, data)` (`dashboard/api/ApiClient.js:50-52`); it injects nothing. The server
side agrees: `labels` is read by `ContactsController#resolved_contacts` as `tagged_with(..., any: true)` (`:125`) and is
absent from `permitted_params` (`:173-175`).

Nothing in the create path carries the active label. `ContactsIndex.vue` holds
`const activeLabel = computed(() => route.params.label)` (`:62`) and uses it only in `getCommonFetchParams`
(`:194-198`) for fetch and export. Across every file in
`components-next/Contacts/ContactsForm/`, the only reference to `route.params.label` is
`ContactExportDialog.vue:40` — export. The create dialog and form never see it.

**So even a fully successful create from the label page attaches no label.** This is a missing capability, not a broken
one, and it is why `ActsAsTaggableOn::Tagging.group(:taggable_type, :context).count` showed zero `Contact`/`labels`
rows while `Contact#update_labels(["test-lynomia"])` worked from the console: the write path was never exercised by
the UI.

### 8.2 The 422 message shown is the wrong one

The server's real message does reach the client. `handleContactOperationErrors`
(`dashboard/store/modules/contacts/actions.js:39-51`):

```js
if (error.response?.status === 422) {
  const exception = new DuplicateContactException(error.response.data.attributes);
  exception.message = error.response.data.message || exception.message;
  throw exception;
}
```

and `DuplicateContactException` exposes it: `get contactErrorDetail()` returns `this.message` whenever it is not the
`'DUPLICATE_CONTACT'` default (`shared/helpers/CustomErrors.js:11-16`).

Five call sites catch it. **One** uses `contactErrorDetail`:

| Site | Line | Shows the server message? | If `attributes` is neither `email` nor `phone_number` |
|---|---|---|---|
| `routes/dashboard/conversation/contact/ContactInfo.vue` | `:167-186` | **yes** (`:168-170`) | falls back to `CONTACT_FORM.ERROR_MESSAGE` |
| `components-next/Contacts/ContactsHeader/ContactListHeaderWrapper.vue` | `:110-120` | no | **nothing is shown** |
| `components-next/Contacts/Pages/ContactsList.vue` | `:41-51` | no | **nothing is shown** |
| `routes/dashboard/conversation/contact/ContactForm.vue` | `:265-275` | no | **nothing is shown** |
| `components-next/message/bubbles/Contact.vue` | `:85-93` | no | **nothing is shown** (checks `phone_number` only) |

The primary "Add contact" button goes through `ContactListHeaderWrapper#onCreate` (`:101-121`), which on a 422 with
`attributes: ["phone_number"]` shows `CONTACT_CREATION.PHONE_NUMBER_DUPLICATE` =
*"This phone number is in use for another contact."* (`i18n/locale/en/contact.json:333`; Arabic at
`locale/ar/contact.json:314`). When the server actually said **"Phone number should be in e164 format"**, the user is
told the number is taken. The format error is never shown anywhere in the product.

And when the invalid attribute is something else — say `name` — both branches are false and **no alert is raised at
all**, while `onSuccess()` is not called either, so the dialog stays open with no explanation.

### 8.3 One create path has no error handling at all

`ContactsIndex.vue:428-430`:

```js
const createContact = async contact => {
  await store.dispatch('contacts/create', contact);
};
```

No `try`/`catch`, no `useAlert`, and `CreateNewContactDialog.onSuccess()` is never reached. It is bound to
`ContactEmptyState`'s `@create` (`ContactsIndex.vue:543-549`), so creating the account's first contact from the empty
state throws an unhandled rejection on any failure. The same file handles its bulk actions correctly
(`:333-399`), which makes this a local omission rather than a missing convention.

### 8.4 Why the label page then looks like a silent failure

The sidebar's "Tagged With" group lists **every** label in the account, not the labels that have contact taggings
(`Sidebar.vue:575-591`). Clicking one navigates to `/contacts/labels/:title`, which filters correctly through
`tagged_with` (`contacts_controller.rb:125`) and finds nothing, because §8.1 means nothing ever tagged a contact from
the UI. The page renders its ordinary empty state — indistinguishable, to the user, from "my contact disappeared".

---

## 9. What is actually missing

Ordered by how little has to change.

1. **Honest 422 display on contact create/update.** The server message, `DuplicateContactException.contactErrorDetail`
   and one correct implementation (`ContactInfo.vue:167-186`) all already exist. Four sites ignore them, and one
   (`ContactsIndex.vue:428-430`) has no handler.
2. **A label on contact create.** `labels` is not permitted (`contacts_controller.rb:173-175`) and no UI puts the
   active label into the payload. The writer (`update_labels`) and the per-contact endpoint already exist.
3. **Country-aware phone normalization at the write boundary.** `Commerce::Phone.e164` already implements exactly the
   required semantics, including "never guess"; the contact create path, the CSV importer
   (`contact_manager.rb:47-49`) and the frontend input (`PhoneNumberInput.vue:115-118`) each do something weaker.
4. **Duplicate recovery.** On a 422 the user is told the key is taken but is offered no route to the existing contact,
   although `POST /actions/contact_merge` and `ContactMergeForm.vue` exist.
5. **Import feedback in the product.** `failed_records` carries a per-row reason and is emailed only.
6. **Contact labels in Automation and the Flow Builder.** `ActionService` label actions are conversation-only.
7. **Contact labels in the conversation sidebar.** `ContactLabels.vue` is mounted on one page.
8. **Labels on merge.** `ContactMergeAction` drops the mergee's labels.
9. **Labels in the contact serializer.** `_contact.json.jbuilder` emits none, so a contact list cannot show labels
   without one request per row.
10. **Role gating on the per-contact label endpoint.** No `authorize` call anywhere in that controller chain.
11. **Catalogue validation on `update_labels`.** The nested endpoint accepts any string and creates the tag.
12. **A unique index on `(phone_number, account_id)`** — the only one of the three identity keys without one. Noted,
    **not** proposed: adding it is a migration, and existing data may already contain duplicates, so it is out of
    scope for a zero-migration phase and is recorded here as a known limitation instead.

Nothing above requires a new engine, a new table, a second importer, a second bulk framework, a new audience system or
a new phone-validation framework.

## 10. Findings recorded but outside the brief

| | |
|---|---|
| `ContactMergeAction` loses the mergee's labels (`:55`, `:62`) | correctness |
| `ContactLabels.vue:84-86` swallows a failed label write | correctness |
| No `errors.contacts.*` subtree in `config/locales/ar.yml` — backend validation messages reach Arabic users in English | i18n |
| `CONTACT_CREATION.ERROR_MESSAGE` is untranslated in `locale/ar/contact.json:316` | i18n |
| Neither `Contact` nor `Label` is audited | observability |
| `BulkAssignLabelsService` updates one contact at a time while the importer batch-inserts taggings | performance |
| `Contacts::BulkActionService:9-11` applies only `add` when a payload carries both `add` and `remove`, and the caller cannot detect it | correctness |
| Bulk label add / remove are not policy-checked; only bulk delete is (`bulk_actions_controller.rb:38-44`) | authorization |
| The per-contact label endpoint has no `authorize` call at all | authorization |
| Label changes are absent from `push_event_data` and `webhook_data`, so websocket and webhook consumers never see them | integration |
| `#active` is not label-filterable while `index`, `search`, `filter` and `export` are | consistency |
| `ContactInboxBuilder#generate_source_id:27` raises a bare `RuntimeError` → HTTP 500 for an unrecognised channel | robustness |
| Three independent phone-normalization implementations on contact write paths | duplication |
