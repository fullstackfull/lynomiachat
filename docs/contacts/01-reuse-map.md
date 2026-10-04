# Lynomia Contacts: reuse map

Decision, from [00](00-existing-system-discovery.md): **the Contacts reliability work extends Chatwoot's existing
Contact, Label, DataImport and bulk-action systems. It creates no parallel contact platform.**

Branch `claude/practical-thompson-9xfqed`, HEAD `23f9cbbd`. No product code changed in this phase.

---

## EXISTING SYSTEM TO EXTEND

The exact files, classes, components, services and routes that later phases reuse. Everything in this table exists at
HEAD and is read in [00](00-existing-system-discovery.md).

### Backend — models and concerns

| | |
|---|---|
| `app/models/contact.rb` | the identity record; E.164 validation at `:54-56`, uniqueness per account for email / phone / identifier; `include_mod_with` at the last line |
| `app/services/contacts/sync_attributes.rb` | `before_save` city/country sync and `visitor` → `lead` promotion |
| `db/schema.rb:946-948` | unique indexes on `(email, account_id)` and `(identifier, account_id)`; `(phone_number, account_id)` is **not** unique |
| `app/models/concerns/labelable.rb` | `acts_as_taggable_on :labels`, `update_labels`, `add_labels` |
| `app/models/label.rb` | the account's label catalogue; lowercasing, uniqueness, rename hook |
| `app/models/data_import.rb` | the import record; `legacy_contacts_csv_import?`, `failed_records` attachment, `process_data_import` |
| `enterprise/app/models/enterprise/concerns/contact.rb` | company association — must keep working |

### Backend — controllers and routes

| | |
|---|---|
| `app/controllers/api/v1/accounts/contacts_controller.rb` | `create` `:85-92`, `update` `:94-98`, `permitted_params` `:173-175`, `import` `:34-43`, `resolved_contacts` `:120-127`; extension point `prepend_mod_with` at `:218` |
| `app/controllers/api/v1/accounts/contacts/labels_controller.rb` + `app/controllers/concerns/label_concern.rb` | `GET`/`POST /contacts/:contact_id/labels` (`config/routes.rb:242`) |
| `app/controllers/api/v1/accounts/bulk_actions_controller.rb` | `POST /bulk_actions` (`config/routes.rb:58`); contract `{ type, action_name, ids: [], labels: { add: [], remove: [] } }` at `:65` |
| `app/controllers/api/v1/accounts/actions/contact_merges_controller.rb` | `POST /actions/contact_merge` (`config/routes.rb:55-57`) |
| `app/controllers/api/v1/accounts/data_imports_controller.rb` | import index / show / error_logs / skip_logs (`config/routes.rb:248-259`) |
| `app/controllers/concerns/request_exception_handler.rb` | `render_record_invalid` `:58-64` — the `{ message, attributes }` 422 shape every client already parses |
| `app/policies/contact_policy.rb` + `enterprise/app/policies/enterprise/contact_policy.rb` | `import?` / `export?` / `destroy?` administrator or `contact_manage` |

### Backend — services, jobs, actions

| | |
|---|---|
| `app/services/contacts/bulk_action_service.rb` | the dispatcher: delete / add labels / remove labels |
| `app/services/contacts/bulk_assign_labels_service.rb`, `bulk_remove_labels_service.rb`, `bulk_delete_service.rb` | the three bulk operations |
| `app/jobs/contacts/bulk_action_job.rb` | queue `medium` |
| `app/jobs/data_import_job.rb` | the CSV importer — **already imports a `labels` column**: `:8-10`, `:47-67`, `:81-116`, `:138-151` |
| `app/services/data_import/contact_manager.rb` | per-row find-or-upsert; `format_phone_number` `:47-49` |
| `app/jobs/account/contacts_export_job.rb` | CSV export — **already emits a virtual `labels` column** (`:4`, `:21`, `:34`, `:43-57`), filtered to the account catalogue |
| `app/models/data_import_error.rb`, `app/models/data_import_item.rb`, `app/finders/data_import_error_finder.rb`, `app/finders/data_import_skip_log_finder.rb` | generic per-row import error storage, finders — **written only by the integration pipeline today** |
| `app/views/api/v1/accounts/data_imports/{show,index,_data_import}.json.jbuilder` | already serialize `import_errors`, `skip_logs` and their counts |
| `app/services/data_imports/importer.rb` | the Intercom / Freshdesk importer; `Contact.insert_all!` `:286`, `E164_REGEX` `:17`, `normalized_phone` `:850-854` — the one path with no validations or callbacks |
| `app/builders/contact_inbox_with_contact_builder.rb`, `app/builders/contact_inbox_builder.rb` | the inbound-channel create path, every channel |

### Backend — the serializer

| | |
|---|---|
| `app/views/api/v1/models/_contact.json.jbuilder` | the contact payload — **emits no labels** today |
| `app/views/api/v1/accounts/contacts/labels/{index,create}.json.jbuilder` | `json.payload @labels`, an array of titles |
| `app/services/contacts/filter_service.rb` + `custom/app/services/custom/contacts/filter_service.rb` | audience evaluation |
| `app/services/labels/update_service.rb`, `app/services/labels/destroy_service.rb` | label rename / delete, **already Contact-aware** |
| `app/actions/contact_merge_action.rb` + `enterprise/app/actions/enterprise/contact_merge_action.rb` | the merge |
| `app/actions/contact_identify_action.rb` | identify-time merge; `discard_invalid_attrs` |
| **`custom/app/services/commerce/phone.rb`** | `Commerce::Phone.e164(raw, country)` — country-aware E.164 that **never guesses**; 12 existing call sites |
| `app/services/action_service.rb` | automation / macro / flow actions; `add_label` `:37-41`, `remove_label` `:57-62`; `include_mod_with` at `:122` |
| `custom/app/services/flows/nodes/{add_label,remove_label,set_contact_attribute}.rb` | the flow nodes to extend |
| `app/models/campaign.rb` `audience_contacts` `:69-72` + `custom/app/models/custom/campaign_audience.rb` | campaign recipients |

### Backend — dependencies already present

| | |
|---|---|
| `telephone_number` | `Gemfile:22`, lock 1.4.20 — used by SMS, Twilio, WhatsApp, LeadSquared and `Commerce::Phone` |
| `activerecord-import` | `Contact.import` / `ActsAsTaggableOn::Tagging.import` in `data_import_job.rb:77,85` |
| `acts-as-taggable-on` | the label store |

### Frontend

| | |
|---|---|
| `dashboard/routes/dashboard/contacts/routes.js` | the seven Contacts routes — enumerated by hand, **not** discoverable by a `**/*.routes.js` glob |
| `dashboard/routes/dashboard/contacts/pages/ContactsIndex.vue` | list page; bulk handlers `:333-399`; `createContact` `:428-430` |
| `dashboard/routes/dashboard/contacts/components/ContactsBulkActionBar.vue` | the bulk bar; admin-gated delete `:119-133` |
| `dashboard/components-next/Contacts/ContactsHeader/ContactListHeaderWrapper.vue` | header actions; `onCreate` `:101-121`, `onImport` `:124-139`, `onExport` `:142-153` |
| `dashboard/components-next/Contacts/ContactsForm/*` | create / import / export / segment / merge dialogs |
| `dashboard/components-next/Contacts/Pages/{ContactsList,ContactDetails}.vue` | rows `:35-53`; detail page, mounts `ContactLabels` at `:180` |
| `dashboard/components-next/Contacts/ContactLabels/ContactLabels.vue` | the per-contact label widget |
| `dashboard/components/widgets/conversation/conversationBulkActions/BulkLabelActions.vue` | the shared bulk-label picker, already reused for contacts |
| `dashboard/api/contacts.js`, `dashboard/api/bulkActions.js`, `dashboard/api/ApiClient.js` | API clients |
| `dashboard/store/modules/contacts/actions.js` | `create` `:157-177`, `handleContactOperationErrors` `:39-51` |
| `dashboard/store/modules/contactLabels.js` | per-contact label store |
| `shared/helpers/CustomErrors.js` | `DuplicateContactException` + **`contactErrorDetail`** `:11-16` |
| `dashboard/routes/dashboard/conversation/contact/ContactInfo.vue` `:167-186` | **the one correct 422 handler — the pattern to copy** |
| `dashboard/components-next/phonenumberinput/PhoneNumberInput.vue` | the phone control; `emitPhoneNumber` `:115-118` |
| `shared/components/PhoneInput/helper.js` | timezone-derived default dial code |
| `dashboard/recipes/{index,audiencePresets,automationRecipes,flowTemplates}.js` | the recipe contract and the three catalogues |
| `dashboard/helper/audienceHelper.js` | `AUDIENCE_QUERY_PARAM`, `audienceConditionFor` — the cross-module prefill mechanism |
| `dashboard/components-next/sidebar/Sidebar.vue` `:569-591` | the "Tagged With" group |
| `libphonenumber-js` | `package.json:86`; already imported by four components |

### i18n files to extend

`app/javascript/dashboard/i18n/locale/en/contact.json` (`CONTACT_CREATION` `:327-336`, `CONTACTS_BULK_ACTIONS`
`:618-640`) and its `ar/` counterpart (`:308-317`); `config/locales/en.yml` (`errors.contacts` `:122-131`, the subtree starting at `:122`) and
`config/locales/ar.yml` — which has **no** `errors.contacts` subtree today.

---

## Reuse matrix

**REUSE** = use as it is. **EXTEND** = add through an existing extension point without changing behaviour.
**PATCH** = a defect in existing code. **NOT PRESENT** = the capability does not exist.

### A1 — Contact lifecycle

| Capability | Exists? | Location | Class |
|---|---|---|---|
| Contact as identity record | yes | `app/models/contact.rb` | **REUSE** |
| Create / update / destroy API | yes | `contacts_controller.rb:85-110` | **REUSE** |
| `permitted_params` accepting `labels` | no | `contacts_controller.rb:173-175` | **NOT PRESENT** → extend via `prepend_mod_with` |
| 422 shape `{ message, attributes }` | yes | `request_exception_handler.rb:58-64` | **REUSE** |
| Server message reaching the client | yes | `contacts/actions.js:39-51`, `CustomErrors.js:11-16` | **REUSE** |
| Honest 422 display on create | partly | `ContactInfo.vue:167-186` correct; `ContactListHeaderWrapper.vue:110-120`, `ContactsList.vue:41-51`, `ContactForm.vue:265-275`, `message/bubbles/Contact.vue:85-93` wrong | **PATCH** |
| Error handling on the empty-state create | no | `ContactsIndex.vue:428-430` | **PATCH** |
| Explicit merge | yes | `contact_merge_action.rb`, `ContactMergeForm.vue` | **REUSE** |
| Merge preserving the mergee's labels | no | `contact_merge_action.rb:55,62` | **NOT PRESENT** (finding; outside the brief) |
| Identify-time merge | yes | `contact_identify_action.rb` | **REUSE** — do not touch |
| Permissions | yes | `ContactPolicy`, `Enterprise::ContactPolicy` | **REUSE** |
| Account scoping | yes | `Current.account.contacts` everywhere | **REUSE** |
| Unique DB index on email / identifier | yes | `db/schema.rb:946-947` | **REUSE** |
| Unique DB index on phone | no | `db/schema.rb:948` is non-unique | **NOT PRESENT** — recorded as a known limitation, not proposed (a migration) |
| Validations on every create path | no | `DataImports::Importer:286` uses `insert_all!` | **REUSE** as is — it pre-normalizes at `:850-854` |
| Platform (super-admin) Contact API | no | `config/routes.rb:598-620` | **NOT PRESENT** — not needed |

### A2 — Labels

| Capability | Exists? | Location | Class |
|---|---|---|---|
| Contact labels in the schema | yes | `labelable.rb:4-6`, `taggings.taggable_type = 'Contact'` | **REUSE** |
| Writers `update_labels` / `add_labels` | yes | `labelable.rb:8-18` | **REUSE** |
| Per-contact label endpoint | yes | `contacts/labels_controller.rb`, `routes.rb:242` | **REUSE** |
| Label catalogue CRUD | yes | `labels_controller.rb` | **REUSE** |
| Rename propagating to contacts | yes | `labels/update_service.rb:13-19` | **REUSE** |
| Delete propagating to contacts | yes | `labels/destroy_service.rb:26-30` | **REUSE** |
| Labels as a filter condition | yes | `filter_keys.yml:75-81`, `filter_service.rb:128-142` | **REUSE** |
| Label route for contacts | yes | `contacts/routes.js:29-34`, `contacts_controller.rb:125` | **REUSE** |
| Per-contact label widget | yes | `ContactLabels.vue` | **REUSE** |
| Silent failure on a label write | — | `ContactLabels.vue:84-86` | **PATCH** (finding) |
| Label widget in the conversation sidebar | no | `routes/dashboard/conversation/contact/` | **NOT PRESENT** (finding) |
| Sidebar listing only labels in use | no | `Sidebar.vue:575-591` lists all | **NOT PRESENT** (finding) |
| Labels in the contact serializer | no | `_contact.json.jbuilder` | **NOT PRESENT** — one request per contact today |
| `cached_label_list` on Contact | no | `Conversation` has one, `Contact` does not | **NOT PRESENT** — not needed (would be a migration) |
| Role gating on the per-contact label endpoint | no | no `authorize` in `contacts/labels_controller.rb` or `contacts/base_controller.rb`; no `verify_authorized` anywhere | **PATCH** (authorization finding) |
| Catalogue validation on `update_labels` | no | `labelable.rb:8-10`; enforced only by import, export, campaigns, UI | **NOT PRESENT** (hygiene finding) |
| Single-label DELETE route | no | `routes.rb:242` is `[:create, :index]` | **NOT PRESENT** — full-list POST is sufficient |
| Label change in websocket / webhook payloads | no | `contact.rb:150-180` | **NOT PRESENT** (integration finding) |
| Label filter on `#active` | no | `contacts_controller.rb:53-58` builds its own scope | **NOT PRESENT** (consistency finding) |
| A second tag engine / tag table | — | — | **DO NOT CREATE** |

### A3 — Import

| Capability | Exists? | Location | Class |
|---|---|---|---|
| CSV upload endpoint | yes | `contacts_controller.rb:34-43`, `routes.rb:231` | **REUSE** |
| Import record, status, counts | yes | `data_import.rb` | **REUSE** |
| Batched contact insert | yes | `data_import_job.rb:77` | **REUSE** |
| Per-row validation + reasons | yes | `data_import_job.rb:69-72` | **REUSE** |
| **`labels` CSV column → contact taggings** | **yes** | `data_import_job.rb:8-10,47-67,81-116,138-151`; sample header in `public/downloads/import-contacts-sample.csv` | **REUSE** |
| Label validation against the account catalogue | yes | `data_import_job.rb:144-151` | **REUSE** |
| Tagging de-duplication | yes | `data_import_job.rb:104-116` | **REUSE** |
| Find-or-upsert per row | yes | `contact_manager.rb:20-27,51-57` | **REUSE** |
| Country-aware phone normalization in import | no | `contact_manager.rb:47-49` prefixes `+` only | **PATCH** |
| Rejected rows visible in the product | no | `failed_records` read only by `account_notification_mailer.rb:29-30` | **NOT PRESENT** |
| **Per-row error storage + finder + serializer + CSV download** | **yes** | `DataImportError`, `DataImportErrorFinder`, `show.json.jbuilder:3-26`, `GET /data_imports/:id/{error_logs,skip_logs}` | **REUSE** — generic, but written only by `DataImports::Importer:1136`; the CSV path has only to populate it |
| Within-file duplicate phone detection | no | `on_duplicate_key_ignore` needs a unique index; phone has none | **NOT PRESENT** — a file with the same phone twice inserts two contacts |
| Callbacks on bulk-imported contacts | no | `Contact.import` validates but skips callbacks (`:77`) | **NOT PRESENT** — matched contacts (`contact.save`) do run them; the halves differ |
| Column whitelist | no | `ContactManager:14,52-54,62-66` names six, sweeps the rest into `custom_attributes` | **NOT PRESENT** |
| Dry run / preview / column mapping | no | — | **NOT PRESENT** |
| Upload content-type / size / header validation | no | `contacts_controller.rb:35` checks blankness only | **NOT PRESENT** |
| Feature gating on CSV import | no | the `data_import` flag guards `DataImportsController` only | **NOT PRESENT** |
| Streaming / chunked parsing | no | whole file in memory (`:199-207`, `:34-45`) | **NOT PRESENT** |
| Completion feedback in the UI | no | alert fires on upload (`ContactListHeaderWrapper.vue:124-139`) | **NOT PRESENT** |
| **`labels` column on CSV export** | **yes** | `account/contacts_export_job.rb:4,21,34,43-57` | **REUSE** — export → edit → import already round-trips labels |
| A second CSV import engine | — | — | **DO NOT CREATE** |

### A4 — Bulk actions

| Capability | Exists? | Location | Class |
|---|---|---|---|
| Shared bulk endpoint | yes | `bulk_actions_controller.rb`, `routes.rb:58` | **REUSE** |
| Contact bulk payload contract | yes | `bulk_actions_controller.rb:65` | **REUSE** |
| **Server batch path for bulk contact labels** | **yes** | `BulkActionService` → `BulkAssignLabelsService` / `BulkRemoveLabelsService` | **REUSE** |
| Bulk delete with authorization | yes | `bulk_actions_controller.rb:38-44`, `BulkDeleteService` | **REUSE** |
| Bulk bar UI, one request for N contacts | yes | `ContactsBulkActionBar.vue:105-117`, `ContactsIndex.vue:333-375` | **REUSE** |
| Success / failure alerts on bulk actions | yes | `ContactsIndex.vue:345,349,367,371,389,394` | **REUSE** |
| Batched tagging writes in the bulk job | no | `BulkAssignLabelsService:13-15` is per contact | **NOT PRESENT** (performance finding) |
| `add` and `remove` in one payload | no | `bulk_action_service.rb:9-11` early-returns on `add`; the conversation job does support both (`bulk_actions_job.rb:20-23`) | **NOT PRESENT** — send one key per request |
| **Bulk action over "all contacts matching this filter"** | no | `bulk_actions_controller.rb:65` permits `ids: []` only; `#export` **is** filter-based (`contacts_controller.rb:45-50`) | **NOT PRESENT** — the one gap that limits bulk workflows at scale; copy the export path's shape |
| Per-record permission filtering | no | conversations have `Conversations::PermissionFilterService` (`bulk_actions_job.rb:66`) | **NOT PRESENT** (authorization finding) |
| Acting user recorded | no | `BulkActionService:3-6` assigns `@user` and never reads it; `Current.user` unset | **NOT PRESENT** (observability finding) |
| Transaction / payload cap / partial-failure reporting | no | none in the controller, services or job; `head :ok` precedes the work | **NOT PRESENT** (robustness finding) |
| Online-presence guard on bulk delete | no | single delete has one (`contacts_controller.rb:101-105`); `BulkDeleteService:10` does not | **NOT PRESENT** (consistency finding) |
| Extension point on the bulk path | no | no `prepend_mod_with` / `include_mod_with` on the controller, jobs or four services | **NOT PRESENT** — adding one is itself the cheapest change if the path must be extended |
| Bulk "add to audience / campaign / segment" | no | — | **NOT PRESENT** — C3's target |
| Policy check on bulk label add / remove | no | only `delete` is checked (`bulk_actions_controller.rb:38-44`) | **PATCH** (authorization finding) |
| A second bulk-action framework | — | — | **DO NOT CREATE** |

### A5 — Audience / Campaign / Automation

| Capability | Exists? | Location | Class |
|---|---|---|---|
| Audience = shared contact `CustomFilter` | yes | `docs/audience/00-existing-system-discovery.md` §3 | **REUSE** |
| Lynomia audience conditions | yes | `custom/app/services/custom/contacts/filter_service.rb` | **REUSE** |
| Campaign recipients from labels | yes | `campaign.rb:69-72` | **REUSE** |
| Campaign recipients from shared audiences | yes | `custom/app/models/custom/campaign_audience.rb` | **REUSE** |
| Audience → Campaign / Automation prefill | yes | `dashboard/helper/audienceHelper.js` | **REUSE** |
| Automation / flow **conversation** label actions | yes | `action_service.rb:37-41,57-62`; `flows/nodes/add_label.rb`, `remove_label.rb` | **REUSE** |
| Automation / flow **contact** label actions | no | `ActionService.new(conversation)` only | **NOT PRESENT** → extend via `include_mod_with` |
| A new audience engine / recipient system / automation engine | — | — | **DO NOT CREATE** |

### A6 — Recipes and presets

| Capability | Exists? | Location | Class |
|---|---|---|---|
| Recipe contract | yes | `recipes/index.js:9-23` | **REUSE** |
| `REQUIREMENTS.LABEL`, `CONTACT_FILTER` | yes | `recipes/index.js:40,43` | **REUSE** |
| `INPUT_TYPES.LABEL` / `LABELS` / `AUDIENCE` | yes | `recipes/index.js:49-52` | **REUSE** |
| Three catalogues (7 / 7 / 6 entries) | yes | `audiencePresets.js`, `automationRecipes.js`, `flowTemplates.js` | **EXTEND** (data only) |
| A recipes table or endpoint | — | — | **DO NOT CREATE** |

### A8 — Phone numbers and duplicates

| Capability | Exists? | Location | Class |
|---|---|---|---|
| E.164 validation on `Contact` | yes | `contact.rb:54-56` | **REUSE** — must not be weakened |
| E.164 error string | yes | `en.yml:130-131` "should be in e164 format" | **REUSE** |
| Arabic translation of that string | no | `config/locales/ar.yml` has no `errors.contacts` | **NOT PRESENT** |
| **Country-aware normalization that never guesses** | **yes** | `custom/app/services/commerce/phone.rb:5-11` | **REUSE** |
| National-significant-number helper | yes | `commerce/phone.rb:15-20` | **REUSE** |
| `telephone_number` gem | yes | `Gemfile:22` | **REUSE** |
| `libphonenumber-js` | yes | `package.json:86` | **REUSE** |
| Normalization on contact create / update | no | `contacts_controller.rb:85-98` passes the raw string | **NOT PRESENT** |
| Normalization in CSV import | partly | `contact_manager.rb:47-49` adds `+` only | **PATCH** |
| Client-side validation against the chosen country | no | `PhoneNumberInput.vue:45-56,115-118` concatenates; `libphonenumber-js` imported but used only to parse incoming values `:147-159` | **PATCH** |
| Uniqueness per account on email / phone / identifier | yes | `contact.rb:51-56` | **REUSE** — must not be weakened |
| Duplicate → 422 with the real message | yes | `request_exception_handler.rb:58-64` | **REUSE** |
| Route from a duplicate 422 to the existing contact | no | — | **NOT PRESENT** |
| Silent auto-merge on dashboard create | no (by design) | — | **DO NOT CREATE** |
| Normalization in the integration importer | yes, its own | `data_imports/importer.rb:17,850-854` | **REUSE** as is — third implementation, but it refuses bad numbers |
| A new phone-validation framework | — | — | **DO NOT CREATE** |

---

## Deliberately not created

Restated from the brief, each with the thing that already does the job.

| Not created | Because |
|---|---|
| A new Contacts engine or table | `Contact` + `contacts` |
| A new Label / Tag engine or table | `acts-as-taggable-on`, `Labelable`, `Label` |
| A second CSV import engine (`BulkContactImporter v2`) | `DataImport` + `DataImportJob` + `DataImport::ContactManager` |
| A second bulk-action framework | `BulkActionsController` + `Contacts::BulkActionService` |
| A new Audience engine | shared contact `CustomFilter` + `Contacts::FilterService` |
| A new Campaign recipient system | `Campaign#audience_contacts` + `Custom::CampaignAudience` |
| A new Automation system | `AutomationRule` + `ActionService` + the flow nodes |
| A new phone-validation framework | `telephone_number` + `Commerce::Phone` + `libphonenumber-js` |
| A background label-maintenance engine | labels stay manual and persistent; dynamic membership is a Shared Audience |
| Weaker uniqueness or weaker E.164 | both are load-bearing (`contact.rb:51-56`) |
| Silent auto-merge | merge stays explicit (`/actions/contact_merge`) |

Product rule carried forward: **LABEL = persistent, manual, operational. SHARED AUDIENCE = dynamic criteria.** The code
already matches it — a label is a stored tagging, an audience is a filter evaluated on read.

---

## Migration assessment — TARGET ZERO

Every gap in §9 of [00](00-existing-system-discovery.md) is reachable without a schema change.

| Candidate need | Existing storage that covers it |
|---|---|
| Contact labels | `taggings` with `taggable_type = 'Contact'`, `context = 'labels'` — already written by `DataImportJob` |
| Label on create | the same `taggings` rows, through `update_labels` |
| Per-row import errors | `DataImport#failed_records` (ActiveStorage) already holds them; `DataImportError` / `DataImportItem` tables already exist |
| Import progress | `data_imports.processed_records` / `total_records` columns exist |
| Normalized phone | `contacts.phone_number` holds E.164 already |
| Country for normalization | `contacts.additional_attributes->>'country_code'` is already written by `ContactsForm.vue:42,303-304` |
| Recipe entries | source code, no table by design |
| Contact label automation action | `automation_rules.actions` jsonb |

**Conclusion: zero migrations are required for the work described in Phase B and Phase C.** If a later phase believes
one is needed, it stops and documents the need here before writing it.

Two candidates were considered and **declined**, each recorded here rather than written:

| Declined migration | Why |
|---|---|
| A unique index on `(phone_number, account_id)` | It would close the one identity key the database does not protect (`db/schema.rb:948`). But existing production data may already hold duplicate phone numbers inside an account — the index would fail to build, and deciding which row wins is a data-migration question, not a schema one. The model validation already covers every validated path; the one unvalidated path (`DataImports::Importer:286`) pre-normalizes and drops bad numbers at `:850-854`. Out of scope for a zero-migration phase; carried as a known limitation |
| A `cached_label_list` column on `contacts`, mirroring `Conversation` | It would let the contact serializer emit labels without a join. But the same result is reachable by preloading taggings for the page's 15 rows, exactly as `contacts_export_job.rb:43-53` already does for an export — no column, no backfill, no new write path to keep in sync |

---

## Smallest production-safe implementation plan

Sequenced so each step is independently shippable and verifiable. **Not started — Phase A is documentation only.**

### Phase B — the proven defect

1. **B1 — show the real 422.** Copy the one correct handler (`ContactInfo.vue:167-186`): prefer
   `error.contactErrorDetail`, fall back to the canned duplicate strings, and always end in a generic message so no
   branch can be silent. Apply to `ContactListHeaderWrapper.vue:110-120`, `ContactsList.vue:41-51`,
   `ContactForm.vue:265-275`, `message/bubbles/Contact.vue:85-93`. Give `ContactsIndex.vue:428-430` the same handler and
   the missing `onSuccess()` call. No backend change; the message is already on the wire.
   Add the missing `errors.contacts` subtree to `config/locales/ar.yml` and translate
   `CONTACT_CREATION.ERROR_MESSAGE` in `locale/ar/contact.json`.
2. **B2 — duplicate recovery.** When a 422 names a unique key, offer the existing contact: the UI already has
   `ContactMergeForm.vue` and `POST /actions/contact_merge`. Resolution stays explicit; nothing auto-merges; the
   lookup stays inside `Current.account.contacts` so no other account's contact can be named.
3. **B3 — country-aware normalization.** Reuse `Commerce::Phone.e164(raw, country)` — it already strips `00`, parses
   international numbers alone, parses a local number **only** with an explicit country, and returns nothing when the
   region is ambiguous. Apply it at the two write boundaries that lack it: the contact controller's request boundary
   (returning 422 through the existing errors, never a guess) and `ContactManager#format_phone_number:47-49`. On the
   client, validate what the user typed against the selected country with the already-imported `libphonenumber-js`
   instead of concatenating in `PhoneNumberInput.vue:115-118`. The model's E.164 rule and all uniqueness constraints
   stay exactly as they are.
4. **B4 — tests** for the above.

### Phase C — the actual gaps

1. **C1 — bulk add / import.** Extend `DataImportJob`, which already imports labels. To surface per-row reasons in
   the product, have it write `DataImportError` rows — the model, both finders, the `show` serializer
   (`show.json.jbuilder:3-26`), the index counts and the two CSV download endpoints are all generic and already
   wired, and only `DataImports::Importer:1136` populates them today. No new importer, no new table, no new
   endpoint.
2. **C2 — bulk labels.** The batch path and its UI are already complete end to end
   (`bulk_actions_controller.rb:65` → `BulkAssignLabelsService`, driven by `ContactsBulkActionBar.vue`), and one
   request covers N contacts, so the brief's "do not send one HTTP request per Contact" is already satisfied.
   The **one** thing worth adding is selection by filter: the bulk endpoint takes `ids: []` only, while `#export`
   already accepts `{ payload:, label: }` (`contacts_controller.rb:45-50`), so the shape, the validation and the
   error vocabulary all exist on a sibling action. With that, `BulkAssignLabelsService:13-15` should move to the
   importer's batched tagging insert (`data_import_job.rb:85-86`) and the service should gain a payload cap, since a
   filter can select far more than 15 rows. If a contact list should *show* labels, preload taggings for the page the
   way `contacts_export_job.rb:43-53` does rather than adding a column or a request per row.
3. **C3 — Contact / Label → Campaign.** The smallest cross-module action on top of
   `Campaign#audience_contacts` and the `audienceHelper.js` prefill pattern.
4. **C4 — automatic classification.** A **contact** label action for Automation and the Flow Builder, added through
   `ActionService.include_mod_with` and a new flow node beside `flows/nodes/add_label.rb`. No background
   label-maintenance engine: labels stay manual and persistent, dynamic membership stays a Shared Audience.
5. **C5 — recipes.** Entries in the three existing catalogues. Data only.

Order matters: B1 is a prerequisite for everything else, because until the real error is visible every later failure
still looks like a silent one.

---

## STOP

Phase A is discovery and the reuse map only. Phase B is **not** started and must not be until this checkpoint has been
reviewed.
