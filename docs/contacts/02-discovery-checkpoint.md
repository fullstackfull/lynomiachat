# Lynomia Contacts: Phase A discovery checkpoint

The twelve answers Phase A had to produce, each resolved from
[00](00-existing-system-discovery.md) and [01](01-reuse-map.md).

Branch `claude/practical-thompson-9xfqed`, HEAD at discovery `23f9cbbd`. **No product code changed.**

---

## 1. The exact Contact lifecycle

`Contact` (`app/models/contact.rb:44-70`) is created through **six** families of entry point, not one:

| Path | Entry | Guards |
|---|---|---|
| Dashboard / application API | `contacts_controller.rb:85-92` | all validations + callbacks |
| Public inbox API | `public/api/v1/inboxes/contacts_controller.rb:7` (`routes.rb:629`) | all |
| Widget identify | `ContactIdentifyAction` (`discard_invalid_attrs: true`) | all, invalid attrs reverted |
| Every inbound channel | `contact_inbox_with_contact_builder.rb:16` | all |
| Legacy CSV import | `DataImportJob` → `Contact.import(validate: true)` (`:77`) | validated, bulk |
| Intercom / Freshdesk import | `DataImports::Importer` → `Contact.insert_all!` (`:286`), `update_columns` (`:316`) | **none** |

Validations: `account_id` presence; `email` format + case-insensitive uniqueness per account; `identifier` uniqueness
per account; `phone_number` E.164 `/\A\+[1-9]\d{1,14}\z/` + uniqueness per account (`:50-56`).
Callbacks: `before_validation :prepare_contact_attributes` (downcase-or-nil email, default both jsonb columns);
`before_save :sync_contact_attributes` → `Contacts::SyncAttributes` (city/country sync, `visitor` → `lead`);
`after_create_commit` dispatch + IP lookup; `after_update_commit` / `after_destroy_commit` dispatch (`:66-70`).

At the database, `(email, account_id)` and `(identifier, account_id)` are unique indexes;
**`(phone_number, account_id)` is not** (`db/schema.rb:946-948`).

Update merges `custom_attributes` and `additional_attributes` rather than replacing them (`:189-193`).
Destroy refuses while the contact is online (`:100-110`). Overlays: Enterprise adds company association
(`enterprise/app/models/enterprise/concerns/contact.rb`) and `company_id` to `permitted_params`;
**`custom/` has no Contact overlay at all**.

**Labels are accepted by no create or update endpoint** (`contacts_controller.rb:173-175`, and the Enterprise
override adds only `company_id`).

## 2. The exact Label lifecycle

Storage is `acts-as-taggable-on` 12.0.0 — one line, `acts_as_taggable_on :labels`
(`app/models/concerns/labelable.rb:4-6`), included by `Contact` (`contact.rb:47`) and `Conversation`. Taggings carry
`taggable_type` and `context: 'labels'`. `tags` / `taggings` are **global** tables (`db/schema.rb:1644,1663`); tenancy
comes from always resolving `taggable_id` through `Current.account.contacts`.

| Stage | Where | Contact-aware? |
|---|---|---|
| Catalogue create / update / delete | `Api::V1::Accounts::LabelsController` | — |
| Title normalization | `label.rb:33-35` (lowercased), uniqueness per account (`:25-28`) | — |
| Assign to one contact | `POST /contacts/:contact_id/labels` → `LabelConcern#create` → `update_labels` (**full replace**) | yes |
| Read one contact's labels | `GET /contacts/:contact_id/labels` → `{ payload: [titles] }` | yes |
| Assign / remove in bulk | `POST /bulk_actions` → `BulkAssignLabelsService` / `BulkRemoveLabelsService` | yes |
| Import | `DataImportJob` bulk-inserts taggings (`:81-116`) | yes |
| Export | `contacts_export_job.rb:43-57` virtual `labels` column | yes |
| **Rename** | `label.rb:30` → `Labels::UpdateJob` → `Labels::UpdateService:13-19` | **yes** |
| **Delete** | `labels_controller.rb:25` → `Labels::RemoveAssociationsJob` → `Labels::DestroyService:26-30` | **yes** |
| Filter | `contacts_controller.rb:125` `tagged_with(any: true)`; `filter_keys.yml:75-81` + `filter_service.rb:128-142` | yes |

What the lifecycle does **not** do: emit labels in the contact serializer (`_contact.json.jbuilder`); validate
`update_labels` against the account catalogue (`acts-as-taggable-on` creates the tag on demand); authorize the
per-contact endpoint (no `authorize` call in that controller chain, no `verify_authorized` anywhere); expose a
single-label DELETE; carry labels in `push_event_data` / `webhook_data`; preserve the mergee's labels on
`ContactMergeAction`; or offer a `Label#contacts` association.

## 3. The exact cause of the known failed workflow at current HEAD

One reported symptom, **three independent defects**. Full trace in [00 §8](00-existing-system-discovery.md).

**(a) The active label is never in the create payload.** The cited fragment
`...(label ? { labels: [label] } : {})` is real but lives in `buildContactParams`
(`dashboard/api/contacts.js:5-11`), which only `get()` and `search()` use — the **list filter**. `create(data)` is
`axios.post(this.url, data)` (`ApiClient.js:50-52`) and injects nothing. Server-side, `labels` is consumed by
`ContactsController#resolved_contacts` as `tagged_with(..., any: true)` (`:125`) and is **absent from
`permitted_params`** (`:173-175`). `ContactsIndex.vue` holds `activeLabel` (`:62`) and passes it only to
`getCommonFetchParams` (`:194-198`) for fetch and export; the only `route.params.label` reference in
`components-next/Contacts/ContactsForm/` is `ContactExportDialog.vue:40`.

> This **materially contradicts** the brief's premise that the frontend includes the label in the create payload. It
> does not, at this HEAD. Creating a contact from a label page attaches no label **even when creation succeeds** — a
> missing capability, not a broken wire. It also explains the production console result: zero `Contact`/`labels`
> taggings while `Contact#update_labels(["test-lynomia"])` worked, because the UI never exercised the write path.

**(b) The 422 shown is the wrong message, and sometimes there is none.** The server's real text does reach the client:
`handleContactOperationErrors` attaches `error.response.data.message` to the exception
(`store/modules/contacts/actions.js:39-51`) and `DuplicateContactException#contactErrorDetail` exposes it
(`shared/helpers/CustomErrors.js:11-16`). Of five handlers, **one** uses it — `ContactInfo.vue:167-186`. The other four
branch on `error.data` instead:

| Handler | Line | Real message? | When `attributes` is neither key |
|---|---|---|---|
| `ContactListHeaderWrapper.vue` (the main Add-contact button) | `:110-120` | no | **no alert at all** |
| `ContactsList.vue` | `:41-51` | no | **no alert at all** |
| `ContactForm.vue` | `:265-275` | no | **no alert at all** |
| `message/bubbles/Contact.vue` | `:85-93` | no | **no alert at all** |

So a 422 of `{ message: "Phone number should be in e164 format", attributes: ["phone_number"] }` renders
`CONTACT_CREATION.PHONE_NUMBER_DUPLICATE` — *"This phone number is in use for another contact."*
(`i18n/locale/en/contact.json:333`). The format error is never shown anywhere in the product, and an invalid
attribute outside those two keys produces silence with the dialog still open.

**(c) One create path has no handler.** `ContactsIndex.vue:428-430` is a bare
`await store.dispatch('contacts/create', contact)` — no `try`/`catch`, no `useAlert`, and `onSuccess()` never called.
It is bound to `ContactEmptyState`'s `@create` (`:543-549`), so the account's first contact fails as an unhandled
rejection. The same file handles its bulk actions correctly (`:333-399`).

**Why it then looks silent.** The sidebar's "Tagged With" group lists **every** account label, not labels with contact
taggings (`Sidebar.vue:575-591`). The label page filters correctly and finds nothing, rendering its ordinary empty
state — indistinguishable from "my contact vanished".

## 4. Existing phone normalization behaviour

| Path | Behaviour | Country-aware |
|---|---|---|
| Model | none — validates only, `/\A\+[1-9]\d{1,14}\z/` (`contact.rb:54-56`) | — |
| Dashboard create / update | none; the raw string is passed through (`contacts_controller.rb:85-98`) | no |
| `Contact#discard_invalid_attrs` | reverts an invalid number to `phone_number_was` (`:206-209`); **opt-in**, reached only by the two widget controllers via `ContactIdentifyAction(discard_invalid_attrs: true)` | no |
| Legacy CSV import | `"+#{phone}"` when `+` is missing (`contact_manager.rb:47-49`); a leading `0` survives and the row is rejected | no |
| Intercom / Freshdesk import | prefix `+`, then drop to `nil` unless it matches `E164_REGEX` (`data_imports/importer.rb:17,850-854`) | no |
| **`Commerce::Phone.e164(raw, country)`** | `00` → `+`; international parses alone; **a local number only with an explicit country**; returns nothing otherwise — *"No country and no '+' means no match, never a guess"* (`custom/app/services/commerce/phone.rb:1-11`) | **yes** |
| Frontend | `` `${activeDialCode}${value}` `` raw concatenation (`PhoneNumberInput.vue:115-118`); validation is `minLength(2)` + `numeric` (`:45-56`); `libphonenumber-js` is imported but used only to parse an incoming value (`:147-159`); the default dial code is guessed from the **browser timezone** (`shared/components/PhoneInput/helper.js`) | no |

Three independent server-side implementations exist; only `Commerce::Phone` is country-aware and only it refuses to
guess. Dependencies already in the repo: `telephone_number` (`Gemfile:22`) and `libphonenumber-js`
(`package.json:86`).

## 5. Existing duplicate behaviour

| Path | On an existing email / phone / identifier |
|---|---|
| Dashboard / API create and update | `save!` → `RecordInvalid` → 422 `{ message, attributes }` (`request_exception_handler.rb:58-64`) |
| Legacy CSV import | **upserts** the existing contact (`contact_manager.rb:20-27,51-57`) |
| Widget / public identify | **merges** — identifier → email → phone, with identifier-conflict and email-priority guards (`contact_identify_action.rb:12-20,72-98`) |
| Explicit merge | `POST /actions/contact_merge`, agent-initiated, both ids resolved inside `Current.account.contacts` |
| Intercom / Freshdesk import | `find_existing_contact` then `insert_all!` — the one path with no validation |

Nothing auto-merges on a dashboard create. Enforcement is the model for all three keys, and the database for two of
them (§1). On a 422 the user is told the key is taken but is offered **no route to the existing contact**, although
`ContactMergeForm.vue` and the merge endpoint both exist.

## 6. Existing importer capabilities

`POST /contacts/import` (`routes.rb:231`, `contacts_controller.rb:34-43`) → `DataImport(data_type: 'contacts')` →
`DataImportJob` one minute later (`data_import.rb:128-133`).

Present: UTF-8/BOM-tolerant CSV reading (`:199-207`); per-row find-or-upsert by identifier → email → phone
(`contact_manager.rb:20-27`); `name`, `company_name`, `city` into `additional_attributes` and every other column into
`custom_attributes` (`:61-67`); batched insert with `on_duplicate_key_ignore` and `track_validation_failures`
(`:77`); per-row rejection reasons from `contact.errors.full_messages` (`:69-72`); a `failed_records` CSV
(`:157-163`); admin completion / failure mail (`:183-189`); `processed_records` / `total_records` (`:153-155`).

**And a full `labels` column**: comma-split (`:65-67`), validated against `account.labels.pluck(:title)` with the row
rejected on an unknown label (`:50-55`, `:144-151`), resolved to contact ids (`:118-136`), de-duplicated against
existing taggings (`:104-116`), and bulk-inserted as `ActsAsTaggableOn::Tagging` rows in batches of 1000 (`:85-86`).
The shipped sample file already carries the header
(`public/downloads/import-contacts-sample.csv`), with every value blank.

**Export matches it**: a virtual `labels` column in the default set, preloaded in one query and filtered to the
account catalogue (`account/contacts_export_job.rb:4,21,34,43-57`). So **export → edit → import already round-trips
contact labels in bulk**; the product simply never says so.

Duplicate handling is two mechanisms: a **matched** contact is updated and `save`d row by row during parsing
(`contact_manager.rb:51-57`, scalars only when `.present?`, and `save` not `save!`), while **new** contacts go in
under `on_duplicate_key_ignore: true` (`:77`) — `ON CONFLICT DO NOTHING`, never an upsert. Because that relies on the
unique indexes, a file listing the same **phone** twice inserts two contacts (no unique index), while the same email
twice inserts one. `Contact.import` also skips callbacks, so a newly imported contact gets no `Contacts::SyncAttributes`
and no `CONTACT_CREATED`, while a matched one does.

Missing: rejected rows anywhere in the product (`failed_records` is read only by
`account_notification_mailer.rb:29-30`); completion feedback (the UI alert fires on `head :ok`, i.e. on upload —
`ContactListHeaderWrapper.vue:124-139`); country-aware phone normalization; a column whitelist (every unknown header
becomes a custom attribute); dry run, preview or column mapping; upload content-type / size / header validation;
feature gating; streaming (the whole file is read into memory).

**But the per-row error machinery already exists and is generic** — `DataImportError`, `DataImportErrorFinder`,
`DataImportSkipLogFinder`, `show.json.jbuilder:3-26`, the index counts and
`GET /data_imports/:id/{error_logs,skip_logs}`. Only `DataImports::Importer:1136` writes to it; the CSV path has
only to populate it.

## 7. Existing bulk-action capabilities

`POST /api/v1/accounts/:account_id/bulk_actions` (`routes.rb:58`), shared with Conversations.
Contract: `params.permit(:type, :action_name, ids: [], labels: [add: [], remove: []])`
(`bulk_actions_controller.rb:65`). `type: 'Contact'` → `Contacts::BulkActionJob` (queue `medium`) →
`Contacts::BulkActionService`, dispatching to `BulkDeleteService`, `BulkAssignLabelsService` or
`BulkRemoveLabelsService`, all scoped to `@account.contacts.where(id: ids)`.

The UI already uses it: `ContactsIndex.vue:333-399` sends **one request for N contacts** for assign, remove and
delete, each with success and failure alerts (`:345,349,367,371,389,394`);
`ContactsBulkActionBar.vue:105-117` reuses the conversation `BulkLabelActions` picker, with the delete button behind
`Policy :permissions="['administrator']"` (`:119-133`).

So the brief's C2 constraint — *do not send one HTTP request per Contact if a server batch path exists* — is already
satisfied.

What the path lacks, measured against the Conversation side of the same endpoint
([00 §4.4](00-existing-system-discovery.md)): **selection by filter** (`ids: []` only, while `#export` *is*
filter-based — the one gap that actually limits bulk workflows at scale, given a 15-row page); any payload cap or
batching; per-record permission filtering (conversations get `Conversations::PermissionFilterService`); a recorded
acting user (`@user` is assigned and never read; `Current.user` unset); a transaction; partial-failure reporting
(`head :ok` precedes the work); `add` + `remove` in one payload (the conversation job supports both); the
online-presence guard that single delete enforces; authorization on label add / remove; and **any extension point at
all** — no `prepend_mod_with` or `include_mod_with` on the controller, either job, or the four services. There is
also no bulk "add to an audience / campaign / segment", which is C3's target.

## 8. Existing Audience → Campaign bridge

An Audience is a shared contact `CustomFilter` (`filter_type: contact`, `shared: true`) — no new table, no new API
(`docs/audience/00-existing-system-discovery.md` §3). Lynomia conditions arrive through
`prepend_mod_with` → `Custom::Contacts::FilterService`.

Campaign recipients: stock `Campaign#audience_contacts` resolves **labels only**
(`app/models/campaign.rb:69-72`). Lynomia's `Custom::CampaignAudience`
(`custom/app/models/custom/campaign_audience.rb`) additionally accepts `{ type: 'Audience', id: <custom filter id> }`,
resolves it through each audience's `members` and unions with the labels (`:12-19`), validated to shared contact
filters of the same account on one-off campaigns only (`:24-27`). Consumers:
`sms`/`twilio` one-off services (`:18`), `whatsapp/oneoff_campaign_service.rb:63`,
`enterprise/.../oneoff_campaign_service.rb:39`, and the count preview
(`custom/.../campaigns/audience_previews_controller.rb:12`).

Cross-module prefill (Audience → Campaign, Audience → Automation) is a route query, not a record:
`AUDIENCE_QUERY_PARAM`, `audienceIdFromQuery`, `findSharedAudience`, `audienceConditionFor`
(`dashboard/helper/audienceHelper.js`).

## 9. Existing Automation label capabilities

**Conversation-only.** `ActionService#add_label` (`app/services/action_service.rb:37-41`) and `#remove_label`
(`:57-62`) both act on `@conversation`, and the service is constructed `ActionService.new(conversation)` (`:4-7`).
The Lynomia flow nodes delegate straight to it: `Flows::Nodes::AddLabel#enter` is
`ActionService.new(conversation).add_label(labels)` (`custom/app/services/flows/nodes/add_label.rb:5-8`), with
`RemoveLabel` subclassing it (`remove_label.rb:2-7`); both resolve titles against `account.labels` (`add_label.rb:12`).

There is a `custom/app/services/flows/nodes/set_contact_attribute.rb` for contact *attributes*, but **no
contact-label action in Automation or in the Flow Builder.** The extension point is
`ActionService.include_mod_with('ActionService')` (`:122`), already used by
`Enterprise::ActionService` (`add_sla`) and `Custom::AutomationRules::ActionService`.

## 10. What is actually missing

1. Honest 422 display on contact create and update — the message, the getter and one correct implementation all
   exist; four sites ignore them and one has no handler.
2. A label on contact create — `labels` is not permitted and no UI puts the active label in the payload.
3. Country-aware phone normalization at the write boundary — `Commerce::Phone.e164` exists; the create path, the CSV
   importer and the frontend input each do something weaker.
4. Duplicate recovery — no route from a 422 to the existing contact.
5. Import feedback in the product — per-row reasons exist but are emailed only.
6. Contact labels in Automation and the Flow Builder.
7. Contact labels in the conversation sidebar (`ContactLabels.vue` is mounted on one page).
8. Labels on merge.
9. Labels in the contact serializer.
10. Role gating on the per-contact label endpoint; a policy check on bulk label add / remove.
11. Catalogue validation on `update_labels`.
12. A unique index on `(phone_number, account_id)` — **recorded, not proposed**: see [01](01-reuse-map.md) §declined
    migrations.
13. **Bulk action over "every contact matching this filter".** The bulk endpoint takes an explicit id list and the
    list shows 15 rows at a time, while `#export` already accepts a filter (`contacts_controller.rb:45-50`). This is
    the one gap that genuinely limits the brief's bulk workflows at scale, and the shape to copy already exists.
14. An extension point on the bulk-action path, and the five robustness gaps listed in §7.

None of these needs a new engine, a new table, a second importer, a second bulk framework, a new audience system or a
new phone-validation framework.

## 11. REUSE / EXTEND / PATCH / NOT PRESENT matrix

The full matrix, by sub-area, is [01 §Reuse matrix](01-reuse-map.md): **103 classified capabilities** across A1, A2,
A3, A4, A5, A6 and A8.

| Class | Rows | Examples |
|---|---|---|
| **REUSE** | 53 | the Contact model and every create path, `Labelable`, the per-contact label endpoint, label rename and delete propagation to Contact taggings, the bulk endpoint and its three services, the CSV importer's `labels` column, the CSV exporter's `labels` column, `Commerce::Phone`, `telephone_number`, `libphonenumber-js`, the 422 `{ message, attributes }` shape, `contactErrorDetail`, the recipe contract, `CustomFilter` audiences, `Campaign#audience_contacts`, `Custom::CampaignAudience`, `audienceHelper.js`, every policy, account scoping everywhere |
| **NOT PRESENT** | 34 | label on create; contact-label action in Automation and the Flow Builder; **bulk action over "all contacts matching this filter"**; labels in the contact serializer; in-product import feedback; a duplicate-recovery route; labels on merge; the label widget in the conversation sidebar; the `#active` label filter; label changes in websocket and webhook payloads; a single-label DELETE; catalogue validation on `update_labels`; `add`+`remove` in one bulk payload; per-record permission filtering; a recorded acting user; a transaction, payload cap or partial-failure report on bulk actions; the online-presence guard on bulk delete; any extension point on the bulk path; within-file duplicate phone detection; callbacks on bulk-imported contacts; a column whitelist; dry run / preview / column mapping; upload content-type and size validation; feature gating on CSV import; streaming parse; a unique phone index; `cached_label_list`; a Platform Contact API |
| **PATCH** | 8 | the four wrong 422 handlers (counted as one row) and `ContactsIndex.vue:428-430`; `ContactManager#format_phone_number`; `PhoneNumberInput.vue` client validation; `ContactLabels.vue:84-86`; the two authorization gaps |
| **DO NOT CREATE** | 7 | a second tag engine, a second CSV importer, a second bulk framework, a new audience engine / recipient system / automation engine, a new phone-validation framework, a recipes table, silent auto-merge |
| **EXTEND** | 1 | the three recipe catalogues (data only) |

Two gaps classified **NOT PRESENT** are closed by *extending* rather than adding: `permitted_params` accepting
`labels` through `prepend_mod_with` (`contacts_controller.rb:218`), and a contact label action through
`ActionService.include_mod_with` (`action_service.rb:122`). Both extension points already exist and are already used
by Enterprise and by `custom/`.

The separate [§Deliberately not created](01-reuse-map.md) table lists **11** things this phase refuses to build, each
paired with the thing that already does the job.

## 12. The smallest production-safe implementation plan

Sequenced in [01 §Smallest production-safe implementation plan](01-reuse-map.md). In one line each:

**B1** copy `ContactInfo.vue:167-186` to the four wrong handlers, give `ContactsIndex.vue:428-430` the same handler
plus the missing `onSuccess()`, and add the absent `errors.contacts` subtree to `ar.yml` — no backend change, the
message is already on the wire. **B2** offer the existing contact from a unique-key 422 through the merge endpoint
and form that already exist; resolution stays explicit. **B3** reuse `Commerce::Phone.e164(raw, country)` at the
controller request boundary and in `ContactManager#format_phone_number:47-49`, and validate client-side with the
already-imported `libphonenumber-js` instead of concatenating; the model's E.164 rule and every uniqueness constraint
stay exactly as they are. **B4** tests.

**C1** extend `DataImportJob` (which already imports labels) and surface `failed_records` in the product.
**C2** the batch path and its UI exist, so the only thing worth adding is selection by filter, copying `#export`'s
`{ payload:, label: }` shape (`contacts_controller.rb:45-50`) — with a payload cap and the importer's batched tagging
insert, since a filter selects more than a page; preload taggings for a page if labels should be shown.
**C3** the smallest cross-module action on `Campaign#audience_contacts` plus the `audienceHelper.js` prefill pattern.
**C4** a **contact** label action via `ActionService.include_mod_with` and one new flow node — no background
label-maintenance engine; labels stay manual and persistent, dynamic membership stays a Shared Audience.
**C5** entries in the three existing catalogues.

**Zero migrations.** Two candidates were considered and declined with reasons recorded in
[01](01-reuse-map.md).

B1 comes first because until the real error is visible, every later failure still looks like a silent one.

---

## STOP

Phase A is discovery and the reuse map. **Phase B is not started** and must not start until this checkpoint has been
reviewed.
