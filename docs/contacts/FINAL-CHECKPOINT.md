# Contacts at scale — final checkpoint

Phases A, B and C. What was reused, what was extended, what was deliberately not built, and what each claim is
proved by.

Branch `claude/practical-thompson-9xfqed`. Phase C base `92b11a20`.

---

## What was reused

Nothing in this phase replaced a system the product already had.

| | |
|---|---|
| Import | `DataImport`, `DataImportItem`/`DataImportError` (unused by the CSV path, still unused), `DataImportJob`, `DataImport::ContactManager`, ActiveStorage attachments, the `low` queue, the failed-records CSV, the admin notification mailers, the Settings → Data list and detail pages |
| Contacts | `Contact`, `Contacts::SyncAttributes`, `Contact.import` (activerecord-import), `Contacts::FilterService` and its Lynomia overlay, `resolved_contacts` |
| Labels | acts-as-taggable-on, `Labelable#add_labels`, `Tagging.import`, `Current.account.labels` as the catalogue, `ContactLabelParams` from phase B |
| Bulk | `POST /bulk_actions`, `Contacts::BulkActionJob`, `Contacts::BulkAssignLabelsService`, `Contacts::BulkRemoveLabelsService`, `Contacts::BulkDeleteService`, `ContactsBulkActionBar`, `BulkSelectBar`, `BulkLabelActions` |
| Campaigns | `Campaign#audience_contacts`, `Custom::CampaignAudience`, `buildCampaignAudience`, `CampaignRecipients`, `POST /campaigns/audience_preview`, `CampaignPolicy` |
| Audiences | `CustomFilter`, `Custom::CustomFilter#members`, `Audience::ConversationCondition`, the audience preset gallery and its wizard |
| Phone | the `telephone_number` gem, `Commerce::Phone`'s explicit-region rule, phase B's `shared/helpers/phoneNumber.js` |
| UI | `Dialog`, `Button`, `ComboBox`, `TagMultiSelectComboBox`, the countries constant, the parity harness and its fixture axios |

## What was extended

| | |
|---|---|
| `DataImport::ContactRows` | **new** — one read-only classifier, used by the import and by its preview |
| `DataImport::ContactLabels`, `ContactCsv` | **extracted** from `DataImportJob`, unchanged in behaviour |
| `DataImport::ContactPreview`, `PastedNumbers` | **new** — a dry run, and a pasted list turned into the CSV the importer already reads |
| `Contacts::Phone` | **new** — the server's single explicit-region rule; `Commerce::Phone` delegates to it |
| `ContactImportParams` | **new** concern — the batch's choices validated at the request boundary |
| `POST /contacts/import` | **extended** — pasted numbers, batch labels, batch country, duplicate policy, on the existing `source_metadata` jsonb |
| `POST /contacts/import_preview` | **new** action on the existing controller |
| `Contacts::BulkActionService` | **patched** — add and remove in one payload |
| `BulkActionsController` | **patched** — authorize a label write; validate the labels being added |
| `audienceHelper.js` | **extended** — a label query parameter beside the audience one |
| `ContactMoreActions` / `ContactHeader` / `ContactListHeaderWrapper` | **extended** — a label page's own action |
| `WhatsAppCampaignsPage` / `Dialog` / `Form` | **extended** — `initialLabelIds` into the picker they already had |
| `AUDIENCE_PRESETS` | **extended** — two conversation-history presets, 7 → 9 |

## What was deliberately not built

No new contacts engine, database, label or tagging system, importer, bulk-action engine, campaign engine,
audience engine, contact-automation engine, background label synchronisation, or recipe framework.

Specifically refused, each with its reason written down:

| | |
|---|---|
| `contact_created` / `contact_updated` automation triggers | forbidden by the brief, and the wrong shape: dynamic membership is a shared audience |
| a contact-label automation condition | none exists; `labels` as a condition means the **conversation's** labels |
| a contact-label automation action or flow node | `ActionService#add_label` labels the conversation and has no contact in scope |
| the brief's own "Contacted us" recipe | would label the conversation while appearing to label the contact — answered with an audience preset instead ([07](07-label-vs-audience.md)) |
| "run this rule over every matching contact" / audience → label synchronisation | stored membership for a question that should be asked fresh |
| a campaign starter catalogue | would be a fourth catalogue |
| an arbitrary-contact-id campaign recipient source | the campaign engine has none, and C3.2 says not to invent one |
| a merge option on import | Chatwoot's merge is an interactive two-contact decision, not something an import may do to a thousand rows |
| a unique index on `(phone_number, account_id)` | a migration — written up for approval in [04](04-bulk-import.md), not written |
| filter-targeted bulk actions ("all 900 matching") | documented as a limitation in [05](05-bulk-labels.md) rather than faked client-side |
| a control for `INPUT_TYPES.LABEL` | no catalogue entry asks for one |

No CRM, SLA or AI work was started.

**Migrations: zero.** `git diff --name-only 92b11a20..HEAD` matches nothing under `db/migrate`, `db/schema.rb`
or `db/structure`.

---

## What each phase had to correct in the last one

Every correction below is proved by a test that now exists, not argued.

**Phase B corrected Phase A.** `/contacts` is itself a server-filtered view (`resolved_contacts`), so the
false-row defect was never limited to label pages. And the E.164 rule is structural, so a dial code concatenated
onto a trunk-prefixed number is usually *accepted* — it stored a wrong number silently rather than refusing it.

**Phase C corrected the brief, four times.**

| The brief assumed | The code said |
|---|---|
| labels on import need building | already validated against the account catalogue, already applied additively, already spec-pinned |
| duplicate behaviour is "skip existing" | **update existing, always** — the *lookup* called `contact.save` |
| do not add a fifth phone normalizer | one already existed in that path and was wrong: `0551112233` → `+0551112233`, which `Contact` then refused |
| "conversation created → add label" labels the Contact | `ActionService#add_label` labels the **conversation**, and `ActionService` holds no contact at all |

The last one is the reason the brief's own suggested recipe was rejected rather than built
([07](07-label-vs-audience.md)), and answered with an audience preset instead.

**Phase C confirmed Phase A was right** about `Commerce::Phone.e164` being a country-aware normalizer that
refuses to guess. C1 made it the server's single rule for user input, with `Commerce::Phone` delegating.

## Defects found by writing a test that asserted the intent

Neither was in the brief; both were real.

1. **Two rows sharing only a phone number inserted two contacts.** activerecord-import strips the model's
   `UniquenessValidator`, and `contacts` has unique indexes on email and identifier per account but only a
   **non-unique** one on `(phone_number, account_id)`. Fixed in-file; the remaining cross-process race needs a
   migration, written up for approval in [04](04-bulk-import.md).
2. **Bulk-imported contacts stayed `contact_type: 'visitor'`.** `Contact.import` skips `before_save`, so
   `Contacts::SyncAttributes` never ran — and in an account with `crm_v2` enabled, `resolved_contacts` is
   `where(contact_type: 'lead')`, so contacts somebody had just imported were **absent from the contacts list
   entirely**.
