---
agent: 051
scope: corpus audit of the `contacts` section (4 EN + 4 AR articles) against the contacts, merge, identity, import, export and custom-attribute code
confidence: high
sources_normative: 0
sources_observational: 0
---

# 051 — Corpus: `contacts`

Method: all eight Markdown files read in full; every factual claim traced to code, i18n strings or schema. Nothing was
executed (contract §6.1), so a finding that depends on runtime behaviour is marked `†` ("by reading, not executed") and
the evidence needed to close it is named. Citations are `path:line`. `EN Ln` means a line in the English article.
The baseline map (`01-current-system.md`) was verified where it touches this section: 4 EN + 4 AR files, exact parity,
`doc_key` = file basename (`content_seeder.rb:107`) — confirmed.

Headline: the section was written on 2026-10-05/06 (`git log`: `45ff789b`, `ba69c6d5`) and the contact merge, merge
permission and identity system were rebuilt on 2026-10-09 (`265171bb`, `a53027a5`, `5d836ef0`). The articles describe
the merge the product no longer has. The same wrong sentences appear in the Arabic files. The whole identity system and
the contact page's tabs have no article at all.

## 1. Inventory

Words are body words (front matter excluded), counted with a Unicode-aware script; plain `wc -w` under-counts Arabic.

| key (`doc_key`) | EN file | AR file | EN title | AR title | pos | EN words | AR words | in `DOC_ARTICLES` | contextual link wired in UI |
|---|---|---|---|---|---|---|---|---|---|
| `contacts` | `en/contacts/contacts.md` | `ar/contacts/contacts.md` | Contacts | جهات الاتصال | 10 | 1093 | 877 | `contacts` (`documentationLinks.js:26`) | none — `FEATURE_DOC_KEYS.contacts` exists (`featureHelper.js:15`) but no component passes `contacts` |
| `custom-attributes` | `en/contacts/custom-attributes.md` | `ar/contacts/custom-attributes.md` | Custom attributes | السمات المخصصة | 20 | 1250 | 1016 | `customAttributes` (`:27`) | yes, one: Settings header `feature-name="custom_attributes"` (`settings/attributes/Index.vue:173`) |
| `import-contacts` | `en/contacts/import-contacts.md` | `ar/contacts/import-contacts.md` | Import contacts | استيراد جهات الاتصال | 30 | 1401 | 1155 | `contactImport` (`:28`) | none — no `FEATURE_DOC_KEYS` entry and no caller; the import dialog carries no link |
| `bulk-actions` | `en/contacts/bulk-actions.md` | `ar/contacts/bulk-actions.md` | Bulk actions on contacts | الإجراءات الجماعية على جهات الاتصال | 40 | 1303 | 1053 | `bulkActions` (`:29`) | none — mapped as `bulk_actions` (`featureHelper.js:10`), never called |

Only `getHelpUrlForFeature` callers are Settings pages (`BaseSettingsHeader.vue:46`); every `feature-name` in the app
is a Settings page. The contacts surface (`components-next/Contacts/**`, `routes/dashboard/contacts/**`) uses neither
`getHelpUrlForFeature` nor `DocsLink` (grep). Three of the four articles are reachable only by search or by the `/docs`
URL, never from the screen they describe.

All cross-links resolve to existing corpus keys (`labels`, `shared-audiences`, `whatsapp-campaigns`, `automation-rules`,
and the four siblings). Front matter is complete (`title`, `description`, `position`, `tags`, `seo_description`); none
has `seo_title`, `version` or `release_date`; zero images in all eight files.

## 2. Per-article verdict

| article | verdict | reason and evidence |
|---|---|---|
| `contacts` | **REWRITE, then SPLIT** | Seven topics in 128 lines (creation, identity rules, phone format, listing, merge, blocking, permissions), and four of the seven contain claims the code contradicts: merge labels (§3 C12), who may merge (C15), who may import/export (C15), audit (C17); plus a false reason for unlisted contacts (C9) and a half-true blocking section (C13). Carve out: *Merge two contacts*, *Block a contact*, *Linked identities*, *Why a contact is not in the list*. Leave a shorter `contacts` as the overview. |
| `custom-attributes` | **EXPAND** (with four corrections) | Best-aligned article of the four: key rules, types, variables, filters, deletion semantics all check out. Wrong: "nothing in Lynomia Chat sets one for you" (Flow Builder does, A15); "travel in exports" (A5); regex "checked in the form, not on the data" (A14, half true). Missing: how an agent sets, edits and removes a value on a contact, and that the type/key lock is UI-only. |
| `import-contacts` | **EXPAND** (with five corrections) | Structurally right and the preview description matches code. Wrong or misleading: contact_manage agents "can import" (I2), "refuses rather than guesses" (I9), "blank cell never clears" for custom-attribute columns (I12 †), the sample CSV (I7), the "attached" email (I17). Missing: the export round-trip's side effects, and linked-identity conflicts. |
| `bulk-actions` | **KEEP, patch three lines** | Mechanics, limits, permissions and the whole-view model are confirmed against `bulk_actions_controller.rb`, `Contacts::ViewScope` and `ContactsBulkActionBar.vue`. Patch: "scrolled to the bottom" (B5), "skipped quietly" (B13 †), and say the 10,000 cap applies to whole-view selection only (B11). |

## 3. Accuracy against the product

Verdicts: `confirmed | wrong | unverifiable`. `†` = established by reading code, not executed.

### 3.1 `contacts.md`

| # | Claim (EN line) | Verdict | Evidence |
|---|---|---|---|
| C1 | Inbound message creates a contact from provider data; a placeholder name is generated when none is sent (L16-23) | confirmed | `app/builders/contact_inbox_with_contact_builder.rb:62-65` (`Haikunator`); WhatsApp name/phone from `incoming_message_identifier_helper.rb:97-105`. Gap: a business-scoped (BSUID) WhatsApp message yields `{ name: }` with **no phone** (`:99`). |
| C2 | Phone, email, identifier each unique per account (L27-33) | confirmed | `app/models/contact.rb:51-56`; unique indexes `db/schema.rb:1041,1042,1044`. |
| C3 | Email compared case-insensitively (L32) | confirmed | `contact.rb:51` (`case_sensitive: false`), `:230` (downcased on save). |
| C4 | Empty never collides (L35) | confirmed | `contact.rb:229-234` (blank becomes NULL; NULLs are distinct). |
| C5 | Dialog names the clashing field and offers to open the holder when exactly one clashes (L36-38) | confirmed | `CreateNewContactDialog.vue:89-93,118-125,175-208`; strings `contact.json:888-897,903-910`. It also offers "Add “label” to {name}" (undocumented) and exists on the **create** dialog only; the edit form's behaviour was not checked. |
| C6 | Identifier has no form field; arrives by import or API (L40-41) | confirmed | `ContactsForm.vue:38-47` (no identifier); read-only display `ContactDetails.vue:143-147`; `permitted_params` `contacts_controller.rb:199`. |
| C7 | Stored form `+` country rest, ≤15 digits (L45) | confirmed | `app/services/contacts/phone.rb:21` `\A\+[1-9]\d{1,14}\z`. |
| C8 | `00`→`+`; local number needs an explicit country; never guessed from locale, timezone or the WhatsApp number (L47-51) | confirmed | form: `shared/helpers/phoneNumber.js:17-23,29-44`; import: `phone.rb:26-37`, `contact_manager.rb:77-81`. Nuance: the browser-timezone country is a *visible pre-fill* in the picker (`phoneNumber.js:12-14` comment). The raw API requires `+` (a `00…` body is rejected by `phone.rb:21`). |
| C9 | The list shows only contacts with a phone, email or identifier; a name-only record "cannot be messaged, so there is nothing to do with it" (L55-59) | wrong | The filter is right (`contact.rb:183-187`; `crm_v2` is off, `config/features.yml:207-210`). The reason is wrong: name-only contacts are created by Instagram/Messenger (`app/models/channel/facebook_page.rb:42-46` passes `contact_attributes: { name: }`), by business-scoped WhatsApp (C1), and by any channel that supplies no phone/email/identifier. They hold live conversations and can be replied to, but never appear in the list, in bulk actions, in a label page or in an export. |
| C10 | Merge procedure: open the record to discard, Merge tab, search the keeper, confirm (L66-69) | confirmed | `ContactMerge.vue:92-95` (`childId` = opened, `parentId` = chosen) → `accountActions.js:10-14` (`base_contact_id`=parent, `mergee_contact_id`=child); help labels `contact.json` "To be saved"/"To be deleted". |
| C11 | Conversations, messages, notes, channel links move; primary wins on conflict; the opened record is deleted (L71-72) | confirmed, incomplete | `app/actions/contact_merge_action.rb:34-66` (deep_merge with base preference at `:56-60`). Omits everything else that moves (C12). |
| C12 | "One thing does not move: **labels**. The record being removed takes its labels with it." (L74-75) | **wrong** | `custom/app/services/contacts/merge_relocation.rb:126-132` `move_labels` adds the mergee's labels to the base inside the merge transaction; design record `docs/p10/04-contact-merge-linking.md` §3; the product's own merge panel says so: `contact.json:650` "Conversations, messages, notes, labels, campaign history, support cases and commerce links move to the contact that is kept." The article instructs agents to hand-copy labels before merging — needless, and it hides that campaign history, support cases, CSAT answers, commerce links/carts and linked identities also move (`merge_relocation.rb:32-42`). Duplicate campaign-recipient and commerce-link rows are discarded, not moved (`:46-49,89-97`). |
| C13a | Blocked: inbound **WhatsApp** messages are dropped; no notifications (L79-81) | confirmed | `app/services/whatsapp/incoming_message_base_service.rb:54` (echoes excepted); `app/builders/notification_builder.rb:29` (mentions excepted). |
| C13b | …"any conversation of theirs is set to resolved and muted" (L80-81) | wrong | A conversation is *created* resolved for a blocked contact (`app/models/conversation.rb:307-309`) and "muted" is derived from `contact.blocked?` (`conversation_mute_helpers.rb:19-21`). Blocking from the contact header only PATCHes `blocked` (`ContactManageView.vue:139-164` → `contacts_controller.rb:104-110`); no callback resolves existing open conversations (grep: no `saved_change_to_blocked`). Only the conversation-level mute action does `resolved!` (`conversation_mute_helpers.rb:7-9`, reached from `conversations_controller.rb:63`, `action_service.rb:10`). Other channels still store the message. |
| C14 | Blocking does not filter campaigns; build the audience with "blocked is false" (L83-86) | confirmed | No `blocked` reference in `custom/app/models/custom/campaign_audience.rb:12-20` or `custom/app/services/custom/whatsapp/oneoff_campaign_service.rb`; the filter exists (`lib/filters/filter_keys.yml:214`, `contactFilterItems/index.js:88-93`). Undocumented but relevant: blocked contacts are skipped by flows (`custom/app/services/flows/runner.rb:95`) and by the automation template action (`custom/app/services/custom/automation_rules/template_action.rb:73`). |
| C15a | View/search/create/edit contacts, apply/remove labels: any agent (L92-93) | confirmed | `app/policies/contact_policy.rb:23-53`; `contacts/labels_controller.rb` has no `authorize`. |
| C15b | **Merge two contacts: any agent** (L94) | **wrong** | `custom/app/policies/custom/contact_policy.rb:17-19`: administrator or `contact_manage` only; enforced at `custom/app/controllers/custom/api/v1/accounts/actions/contact_merges_controller.rb:7-10`; the controller spec asserts a plain agent is refused (`spec/controllers/api/v1/accounts/actions/contact_merges_controller_spec.rb:48`). The Merge tab is still shown to everyone (`ContactManageView.vue:85` has no `when:`), and any failure shows the generic "Could not merge contacts, try again!" (`ContactMerge.vue:99-101`). |
| C15c | Delete: administrator (L95) | confirmed | `contact_policy.rb:55-57`. |
| C15d | **Import and export: administrator, or an agent whose custom role includes contact management** (L96, L127-128) | **wrong (server)** | `app/policies/contact_policy.rb:10-21` — `import?`, `import_preview?`, `export?` are `administrator?` only; `Custom::ContactPolicy` adds `merge?` and `manage_identities?` and nothing else. The *UI* shows both to `contact_manage` (`ContactMoreActions.vue:40-42,185-205`), so such an agent sees the actions and is refused (403). Also repeated in `import-contacts.md` L27-28 and `workspace/roles-and-permissions.md`. |
| C16 | Delete is permanent, deletes conversations, refused while the contact is online (L100-101) | confirmed | `contact.rb:59` (`destroy_async`); `contacts_controller.rb:113-118`. Undocumented: support cases survive with the customer nulled (`custom/app/models/custom/concerns/contact.rb:9-11`). |
| C17 | "Changes to a contact are not recorded in the account's audit log" (L102) | wrong for merge | No `Custom::Audit::Contact` exists (`custom/app/models/custom/audit/*.rb`), so create/edit/delete are indeed unaudited. But a merge writes a `contact.merged` row: `custom/app/actions/custom/contact_merge_action.rb:26,74-90`, and the product says "The merge is recorded in the audit log" (`contact.json:649`). Caveat †: `auditlogHelper.js:12-53` has no `contact:update` label, so the row will render unlabelled; not rendered here. The same stale claim is at `administration/audit-logs.md:39` (agent 059). |
| C18 | List pages fifteen rows (L103) | confirmed | `contacts_controller.rb:14`. Search uses "load more" (`ContactsIndex.vue`, `loadMoreSearchResults`), not page numbers. |
| C19 | Uniqueness is per account (L105-106) | confirmed | `contact.rb:51-56` scope `account_id`; index columns `(…, account_id)`. |
| C20 | Quoted dialog errors (L118, L121) | confirmed | `contact.json:888,890`. |

### 3.2 `custom-attributes.md`

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| A1 | Model and type are fixed after creation; key read-only (L18, L106) | confirmed (UI) / wrong (API) | UI: `EditAttribute.vue:185,203` (`readonly`, `disabled`). Server: `custom_attribute_definitions_controller.rb:36-47` permits `attribute_key`, `attribute_model`, `attribute_display_type` on update. The lock exists only in the dashboard. |
| A2 | Contact value is set on the contact's Attributes tab (L22) | confirmed | `ContactManageView.vue:71`. |
| A3 | Attributes work as contact-filter and automation conditions (L35-37, L80-85) | confirmed | `lib/filters/filter_keys.yml` (custom attributes accepted on contacts); `automationHelper.js:297`, `useAutomation.js:167`. Operator list per type not checked line by line. |
| A4 | A template variable can be filled from a contact attribute (L37-38) | confirmed | `app/services/whatsapp/liquid_template_processor_service.rb:39` exposes `ContactDrop`; `app/drops/contact_drop.rb:30-33`. |
| A5 | Values "travel in exports" (L51-52) | wrong | The export dialog sends no `column_names` (`ContactExportDialog.vue:29-46`), so the job uses `%w[id name email phone_number labels]` (`app/jobs/account/contacts_export_job.rb:100-102`). Custom attributes are exported only if an API caller names a column. Visibility to every agent: confirmed (`contact_policy.rb:43-45`). |
| A6 | Only an administrator creates, renames or deletes definitions; any agent fills values (L56) | confirmed | `custom_attribute_definition_policy.rb:10-20`; route `attributes.routes.js:20`; value writes `contact_policy.rb:31` (`update?` true). |
| A7 | Key: no spaces; letters of any alphabet, digits, `_`, `.`, `-`; unique per model (L65) | confirmed | `custom_attribute_definition.rb:36-39` (`\A[\p{L}\p{N}_.\-]+\z`, scope `account_id, attribute_model`). |
| A8 | Description is required (L66) | confirmed (UI) / wrong (API) | UI: `AddAttribute.vue:104`. Model has no validation on `attribute_description` (`custom_attribute_definition.rb:33-43`). |
| A9 | Types: Text, Number, Link, Date, List, Checkbox (L68) | confirmed | `settings/attributes/constants.js:6-13`. The model also defines `currency` and `percent` (`custom_attribute_definition.rb:46`), not offered; and a third model `company_attribute` (`:45`), not offered. |
| A10 | Built-in names are refused (L72-73) | confirmed | `custom_attribute_definition.rb:25-30,90-97` (on create only). Imprecise: `status` and `priority` are reserved for *conversation* attributes, not contact ones (`:28`). |
| A11 | `{{` offers the attribute; forms `contact.custom_attribute.<key>` (L86-88) | confirmed | `VariableList.vue:48`; `contact_drop.rb:30-33`; `conversation_drop.rb:26-29`. |
| A12 | Deleting a definition leaves the values; re-creating the key shows them again (L113-114) | confirmed | No cleanup callback (`custom_attribute_definition.rb:49-52`). |
| A13 | Import stores unrecognised columns as custom-attribute values (L110-112) | confirmed, understated | `contact_manager.rb:141` merges the entire row minus `identifier/email/name/phone_number` — so `labels`, `company_name`, `city`, `country_code`, `country` and an exported `id` column are *also* written as custom-attribute values. † |
| A14 | Regex is "checked in the form, not on the data" (L108-109) | wrong (half) | True for the API and import (`contacts_controller.rb:202-212`, `contact_manager.rb:141`). False for flows, which enforce the pattern and the type: `custom/app/services/flows/attribute_value.rb:13-16,44-60`, used by `flows/nodes/set_attribute.rb:10` and `flows/nodes/question.rb:28-33`. |
| A15 | "No automation action writes an attribute… nothing in Lynomia Chat sets one for you" (L115-116) | **wrong** | Flow Builder's **Set Contact/Conversation Attribute** node writes one (`custom/app/services/flows/nodes/set_attribute.rb:5-15`) and the **Question** node stores a reply into a contact attribute (`flows/nodes/question.rb:35-42`). True of automation *rules* only (`app/services/automation_rules/action_service.rb`, no such action). Flow Builder is gated by `lynomia_flow_builder` (`config/features.yml:311-314`, default off). |
| A16 | No bulk editor for values (L117-118) | confirmed | `Contacts::BulkActionService` handles labels and delete only (`bulk_action_service.rb:12-17`). |

### 3.3 `import-contacts.md`

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| I1 | Export → edit `labels` → import round-trips labels (L17-19) | confirmed †, with a side effect | `contacts_export_job.rb:100-102` includes `labels`; `contact_rows.rb:148-150` reads it. The default export also contains an `id` column, which the importer writes onto each contact as a custom-attribute value `id` (`contact_manager.rb:141`). Needs a test import to confirm. |
| I2 | An agent with contact management can import (L27-28) | **wrong** | See C15d: `contact_policy.rb:10-12`. |
| I3 | Every label must already exist (L29-30) | confirmed | `contact_rows.rb:53-55,156-158`. |
| I4 | `.csv` of ≤10 MB (L31, L162-163) | confirmed | `contact_import_file.rb:14,98-107`; client check `ContactImportDialog.vue:152`. The server also accepts `text/plain`/`vnd.ms-excel` content types (`:12,103-106`). |
| I5 | No column-mapping step; headers matched by name (L35) | confirmed | `contact_manager.rb` reads fixed keys; `contact_csv.rb`. |
| I6 | Column list incl. `country_code` or `country` (L38-47) | confirmed | `contact_rows.rb:10`, `contact_manager.rb:104-143`. |
| I7 | "**Download a sample csv** gives you a file with the right headers" (L36) | wrong † | `public/downloads/import-contacts-sample.csv` header is `id,name,email,identifier,phone_number,labels,ip_address,company_name,custom_attribute_1,custom_attribute_2`; 23 of its 25 rows carry the same phone `+15417543011`. Run through `ContactRows` (`:70-75`) the first claims the number and 22 are "Repeated rows"; `id`, `ip_address`, `custom_attribute_*` become custom-attribute values. Close by previewing the file in a test account. |
| I8 | Three whole-import choices (L52-58) | confirmed | `contact_import_params.rb:44-50`. |
| I9 | Phone table; "Lynomia Chat refuses rather than guesses: a local number with no country…" (L64-74) | wrong (half) | The five rows of the table are right (`contact_manager.rb:77-87`). The refusal is only for numbers that start with `0` (`contact_rows.rb:123`). Anything else that fails to parse without a region is blindly prefixed with `+` (`contact_manager.rb:83-86`) and accepted if it merely has the E.164 *shape* (`phone.rb:21`). Kuwaiti local numbers have no trunk `0`: `51112233` with no country stores `+51112233`. The article's own worked example (L122) is exactly this case and is safe only because step 3 sets Kuwait. † |
| I10 | Existing contacts matched by identifier, then email, then phone (L78-79) | confirmed | `contact_manager.rb:97-102`. |
| I11 | Update/Keep table (L81-86) | confirmed | name/company/city only when present (`:134-137`); identity fields `compact_blank` (`:49`); custom attributes merged (`:141`); Keep leaves the record untouched (`contact_rows.rb:88-90`); labels always additive (`contact_labels.rb`, `reject_existing`). |
| I12 | "A blank cell never clears a stored value, under either choice" (L88) | wrong for custom-attribute columns † | `contact_manager.rb:141` merges blank-cell `nil`s from the row over stored values; true for name/company/city/identity. No spec covers it (`spec/services/data_import/` holds only `contact_rows_spec.rb`). Needs a test import of a file with an empty custom-attribute cell. |
| I13 | Repeated rows collapse to one contact; labels accumulate (L91-93) | confirmed | `contact_rows.rb:70-75`, `data_import_job.rb:76`. Matching is on *any* of identifier/email/phone (`:135-142`), so a second row sharing only an email loses its different phone. |
| I14 | Paste: separators, internal spaces, phone-only, ≤10,000 (L99-104) | confirmed | `pasted_numbers.rb:10,18`; `contact_import_file.rb:13,118-123`. |
| I15 | Preview groups, 250-row bound (L114-116) | confirmed | `contact_preview.rb:17`; labels `contact.json` COUNTS. Undocumented: the row listing is capped at 100 (`:18`). |
| I16 | No undo (L136) | confirmed | no rollback path in `data_import_job.rb`. |
| I17 | Admins are emailed "with the rejected rows attached as a CSV"; page does not report completion (L138-141) | confirmed, corrected | Recipients: all administrators (`base_mailer.rb:24-26`); the mail carries a **link** to the file, not an attachment (`account_notification_mailer.rb:29-33`); nothing is sent when SMTP is unset (`base_mailer.rb:4`). `errors` column: `data_import_job.rb:58,126`. |
| I18 | Per-import breakdown under Settings → Data needs the Data import feature (L141-142) | confirmed | `data.routes.js:15-18`; `config/features.yml:280-283` default off; stats written at `data_import_job.rb:94-114`. |
| I19 | Name-only row is created but not listed (L143-144) | confirmed | `contact_rows.rb:81-84`, `contact.rb:183-187`. |
| I20 | (not in the article) A row naming a number or address that is a *linked identity* of another contact | gap † | `find_existing` ignores `contact_identities` (`contact_manager.rb:97-102`); the row is built as new and rejected by `primary_identities_not_linked_elsewhere` (`custom/app/models/custom/concerns/contact.rb:26,31-37`) → "Skipped: …is already linked to another contact in this account". |

### 3.4 `bulk-actions.md`

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| B1 | Three actions: add labels, remove labels, delete (L8) | confirmed | `bulk_action_service.rb:12-17`. |
| B2 | Rows vs whole view; labels "Select all (15)", "All N selected" (L14-27) | confirmed | `contact.json:808-813`; `ContactsBulkActionBar.vue:60-99`. |
| B3 | Touching any checkbox cancels whole-view mode (L23-25) | confirmed | `ContactsIndex.vue:167-190`. Row selection surviving paging (L27) was not checked. |
| B4 | Whole-view button appears once the page is exhausted and more rows exist (L22-23) | confirmed | `ContactsBulkActionBar.vue:93-99`. |
| B5 | "…not available until you have scrolled to the bottom of the page" (L39-40) | wrong (minor) | The gate is "every visible row is ticked" (`:93-99`); no scroll condition. |
| B6 | Acts on list, label, search, Active, filter, saved audience; resolved server-side (L29-40) | confirmed | `app/services/contacts/view_scope.rb:29-34`; `bulk_actions_controller.rb:55-68`. |
| B7 | Uncounted search label (L42-44) | confirmed | `contact.json:812`. |
| B8 | Assign/remove: any agent; delete: administrator; label must exist (L69-73) | confirmed | `bulk_actions_controller.rb:81-95`. |
| B9 | Queued; list refreshes when the work has run (L83-84) | confirmed | `app/jobs/contacts/bulk_action_job.rb:13-33` (completion broadcast). |
| B10 | Remove menu lists every account label (L75-76) | unverifiable | `BulkLabelActions.vue` not read; low risk. |
| B11 | 10,000 per action, refused outright (L102) | confirmed, narrower | `bulk_actions_controller.rb:10,55-75`: applies to whole-view selection. An explicit `ids` list is not capped. |
| B12 | Only labels and deletion (L105-107) | confirmed | as B1. |
| B13 | "If one contact in a selection cannot be saved, it is skipped quietly. The action reports success" (L108-109) | wrong † | `add_labels` and `update_labels` use `update!` (`labelable.rb:9,17`), removal uses `update!` (`bulk_remove_labels_service.rb:14`), deletion `destroy!` (`bulk_delete_service.rb:10`). A contact that fails validation raises inside `find_each`, aborting the rest of the batch, and the completion event (`bulk_action_job.rb:30`) is never sent. Needs a run with one deliberately invalid contact. |
| B14 | Not audit-logged (L110) | confirmed | no Contact audit class. |
| B15 | Delete cannot be undone and ignores "online" (L111-112) | confirmed | `bulk_delete_service.rb:10` vs `contacts_controller.rb:113-118`. |
| B16 | Export is separate, view-scoped, administrator-only, emailed (L113-114) | confirmed | `contacts_controller.rb:48-56`; `contact_policy.rb:19-21`; mail to the requester `contacts_export_job.rb:93`. |

### 3.5 Not checked

Operator list per attribute type (A3); `BulkLabelActions.vue` contents (B10); edit-form duplicate recovery (C5); whether
selection survives paging (B3); contacts API and web-widget `identifier_hash` behaviour (belongs to 058); how the
Audit Logs page renders `contact.merged` (C17, needs the page); RTL rendering of inline `+965…` and
`{{contact.custom_attribute.…}}` code spans in the Arabic articles (AR contacts L42; AR import L64-69; AR custom-attributes
L202) — a bidi hazard to render, not assessed.

## 4. Missing articles

The section documents the 2023-era contact (a record with three unique fields) and none of what Lynomia added. Ordered by
the cost of not having it.

| # | Article | The user question it answers | Evidence it is real behaviour |
|---|---|---|---|
| M1 | **Merge two contacts** (replaces the merge section) | Which one do I keep? What moves? Why can't I merge? Why did the duplicate come back? | Relocated set of eight relations plus labels: `merge_relocation.rb:32-42,68-73,126-132`; permission `custom_policy.rb:17-19`; audit `contact_merge_action.rb:74-90`; irreversible (`contact.json:649`); the survivor keeps its *primary* phone/email, and the other number/address is preserved only as a linked identity **when `lynomia_unified_identity` is on** (`contact_merge_action.rb:30-37,50-73`; `identity_linker.rb:34`), which is off by default — otherwise the mergee's second number is lost and the next message from it creates the duplicate again (documented failure, `docs/p10/03-unified-customer-identity.md` §2). Not moved: `blocked`, `contact_type`, `last_name`, `company_id` (`app/actions/contact_merge_action.rb:55`). A merge is refused for plain agents with only a generic toast. |
| M2 | **Automatic merges** (a section of M1) | I never merged these. Why did two contacts become one? | The web widget's `setUser`, pre-chat form and conversation start run `ContactIdentifyAction`, which merges the visitor into an existing contact matched by identifier, then email, then phone, with no agent and no `merge?` check (`app/actions/contact_identify_action.rb:12-22,49-52,118-126`; callers `widget/contacts_controller.rb:38`, `widget/messages_controller.rb:19`, `widget/conversations_controller.rb:20`, `public/inboxes/contacts_controller.rb:17`). It refuses when identifiers differ (`:72-85`). |
| M3 | **Linked identities (the Identities tab)** | A customer wrote from a second number. How do I stop a duplicate? Why is my number "already linked to another contact"? Can I message the linked number? | Feature `lynomia_unified_identity`, default off (`config/features.yml:319-322`); tab only when on (`ContactManageView.vue:56-58,81`); primary vs linked, "Linked by an agent" / "From a merge" (`ContactIdentities.vue`, `contact.json:740-762`); link/unlink = administrator or `contact_manage` (`identities_controller.rb:22,32`), reading = anyone who can open the contact (`:16`); endpoint 404s when off (`:40-43`); phone and email only, normalized, conflict reported not merged (`identity_linker.rb:14-104`); inbound-only — outgoing uses the primary field (`ContactIdentities.vue` description, `contact.json:741`; `custom/app/builders/custom/contact_inbox_with_contact_builder.rb:28-60`); a primary field cannot be set to a value linked elsewhere (`custom/app/models/custom/concerns/contact.rb:26-37`); no fuzzy matching (`docs/p10/03` §4). Not in any billing plan list (grep: only `features.yml`, `featureFlags.js`, `contacts.js`, `identity_linker.rb`) — how an account gets it is unverified. |
| M4 | **The contact page: everything about one customer** | Where do I see everything this customer did, across channels? What are Activity, Cases, History, Media? | Eight tabs: Attributes, Activity, Cases (flag `lynomia_support_tickets`), Identities (flag above), History, Notes, Media, Merge (`ContactManageView.vue:70-86`); P8 timeline (`docs/p8/03-contact-activity-timeline.md`), P10 "omnichannel Customer 360" (`docs/p10/05-omnichannel-customer-360.md` §1-2). Naming collision: the corpus already uses "Customer 360" for the *commerce* Overview tab (`commerce/customer-360.md:7-15`); the P10 record uses the same words for the contact page. Pick one meaning before either is edited. |
| M5 | **Block and unblock a contact** (accurate version) | If I block someone, what actually stops? Does my open conversation close? Will a campaign still reach them? | C13/C14 above: only WhatsApp drops inbound; other channels store the message and open the conversation resolved; existing conversations are untouched; flows and automation template actions skip blocked contacts; campaigns do not. |
| M6 | **Why a contact is not in the list** (troubleshooting) | I can see the conversation but not the contact. Where did my imported contacts go? | `resolved_contacts` (`contact.rb:183-187`); name-only contacts from Instagram/Messenger/business-scoped WhatsApp (C9); `crm_v2` variant (`:183-184`); cross-link `whatsapp-errors/whatsapp-business-scoped-contacts.md`. |
| M7 | **Find, filter and sort contacts** | How do I search for a contact? What can I filter by? | Search covers name, email, phone, identifier (`view_scope.rb:17`); filters on standard, additional and custom attributes, labels, blocked (`lib/filters/filter_keys.yml:138-223`); plus conversation and commerce conditions (`custom/app/services/custom/contacts/filter_service.rb:1-12`, commerce gated by `lynomia_commerce`); Active list; sort fields (`contacts_controller.rb:5-12`); saving as an audience. Overlaps agent 052's audiences section; agree the owner. |
| M8 | **Export contacts** | Where is my export? Why are my attributes missing? Can I re-import it? | Administrator-only, emailed to the requester, scoped to the current view, default columns `id, name, email, phone_number, labels` (`contacts_export_job.rb:93,100-102`); the round-trip side effect (I1). Currently mentioned in three articles, explained in none. |
| M9 | **Add a contact and start a conversation** | What can I fill in? Why can't I set an identifier? Which inbox can I message from? | `ContactsForm.vue:38-47`; duplicate recovery C5; `contactable_inboxes` filtered by inbox membership (`contacts_controller.rb:78-81`); `docs/p10/05` §1. |
| M10 | **Delete a contact** | What disappears, what survives, why am I refused? | C16 plus: conversations destroyed asynchronously (`contact.rb:59`); campaign recipients `destroy_async` (`custom/app/models/custom/concerns/contact.rb:8`); support cases survive; commerce links cascade (`db/schema.rb`, `commerce_customer_links on_delete: :cascade`). |
| M11 | **Troubleshooting entries** for the permission mismatch | I can see Import/Export/Merge but I'm refused. | C15b/C15d; the UI offers actions the server will refuse — an engineering defect (§ Blockers in the digest), but a stuck user still needs the sentence. |

Out of scope here but owed to a neighbour: contacts API and `identifier_hash` (058); Companies (premium flag `companies`,
`config/features.yml:241-244`, off — not a user-visible gap today).

## 5. Quality

Strengths worth preserving: every article follows one shape (what it is → when to use / not → prerequisites → steps →
worked example → limits → related → "If it does not work"); decision guidance ("when not to use") is unusually good and
is the reason `bulk-actions` is the strongest of the four; UI labels are quoted exactly in EN; limits are stated
plainly (no undo, 10,000, 250-row preview).

Weaknesses:

- **Staleness with no marker.** No `version`, `release_date` or "verified against" field, so nothing records that the
  merge text predates the 2026-10-09 rebuild. Every claim in §3 marked wrong is a claim that was true, or intended, on
  2026-10-05.
- **No visuals.** Zero images in all eight files, on pages whose subject is a screen (the preview table, the bulk bar, the
  Merge tab). The preview's six groups and the two selection modes are exactly what a screenshot is for.
- **No `seo_title`** in any file; the `contacts` page's `<title>` is the 8-character "Contacts". `import-contacts` EN
  `description` is 164 characters (over the 160 the audit warns on); its `seo_description` (132) is the field the audit
  prefers, so the audit is unlikely to fire. Descriptions otherwise sit in 50–160.
- **`contacts` is the wrong size.** It carries seven topics (128 lines) and is where the four wrong claims concentrate.
- **Permissions are restated in four places** (`contacts` L88-96, `import-contacts` L27, `bulk-actions` L69-73,
  `custom-attributes` L56) and have already diverged from the code once; one canonical permissions table would stop that.
- **Contextual help is absent where it matters** (§1): the Merge tab, Identities tab, import dialog, bulk bar and block
  button link nowhere.
- **Tags** are sound; `custom-attributes` carries `workspace` correctly.

## 6. EN/AR parity

Structural parity is exact: same headings, table count (3/2/4/3), numbered-step count, bullet count, code spans and
figures in all four pairs. AR bodies run 80-82% of EN length, normal for Arabic. Because AR is a faithful translation,
**every wrong claim in §3 is wrong identically in Arabic** (AR contacts L65-69 and L88; AR custom-attributes L225-226;
AR import L26-27) — fixing EN without AR would create the only real mismatch.

Meaning differences:

| # | Where | EN | AR | Assessment |
|---|---|---|---|---|
| P1 | import, phones | "could belong to any of **a dozen** countries" (L72) | "عشرات البلدان" — dozens (AR L71) | Quantifier drift; either is rhetorical, neither is a measured number. Align. |
| P2 | import, paste | "takes at most 10,000 numbers per paste" (L103) | adds "وما زاد يُرفع كملف" — anything more is uploaded as a file (AR L102-103) | AR carries the remedy from `errors.contacts.import.too_many_numbers` (`en.yml:136`); EN lacks it. Add to EN. |
| P3 | all four | UI labels quoted from the English UI, which exists | AR names buttons the **Arabic UI does not carry** | Below. |

P3 detail — the Arabic UI is partly untranslated, and the Arabic articles quote translated labels the user will not see:

| AR article says | AR UI actually shows | Source |
|---|---|---|
| تبويب **الدمج** (contacts L61) | `Merge` | `ar/contact.json` `SIDEBAR.TABS.MERGE` |
| **حجب جهة الاتصال** (contacts L73) | `Block contact` | `ar/contact.json` `HEADER.BLOCK_CONTACT` |
| **إضافة جهة اتصال** (contacts L16) | `Add contact` | `…CONTACT_CREATION.ADD_CONTACT` |
| **تحديد الكل (15)** (bulk L183) | `Select all (15)` | `ar/contact.json` `CONTACTS_BULK_ACTIONS.SELECT_ALL` |
| **إزالة الوسوم** (bulk L232) | `Remove Labels` | `…REMOVE_LABELS` |
| **تعيين الوسوم** (bulk L231) | تعيين **التسميات** | `…ASSIGN_LABELS` (and `الوسوم` is the AR sidebar word, `ar/settings.json` `SIDEBAR.LABELS`, so the AR UI is itself inconsistent) |
| **الموسومة بـ** (bulk L254) | مشار إليه بواسطة | `ar/settings.json:378` `SIDEBAR.TAGGED_WITH` |
| **جهات الاتصال النشطة** (bulk L198) | `Active contacts` | `ar/contact.json` `ACTIVE_TITLE` |

Only `import-contacts` AR L107 handles this correctly (English label with an Arabic gloss). The decision — quote the
Arabic UI literally (including its English fragments) or fix the Arabic locale first — belongs to 061; the corpus should
not name a button the screen does not show. Dates, digits and `←` navigation arrows (RTL-correct) are consistent.
RTL rendering of the inline LTR spans was not checked (§3.5).
