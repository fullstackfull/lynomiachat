---
agent: 031
scope: Contacts — create/edit, identity uniqueness, custom attributes, labels, CSV import, bulk actions, merge, contact_identities, Customer 360, activity timeline, deletion
confidence: high
---

## 1. What the feature is

A `Contact` is one person inside one account, stored apart from any conversation
(`app/models/contact.rb:44`). Four things make the Lynomia version different from upstream Chatwoot, and three
of the four are invisible in the published documentation.

**Three primary identity columns, all three UNIQUE per account.** `email`, `identifier` and `phone_number` each
carry a model `uniqueness` validation scoped to `account_id` (`app/models/contact.rb:51-56`). Upstream only
backed the first two with a database index; Lynomia added
`uniq_phone_number_per_account_contact` (`custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb:22`).
That migration refuses to run while duplicates exist (`:83-99`), normalizes `phone_number = ''` to NULL in
batches (`:65-74`), and rebuilds an INVALID index left by an interrupted concurrent build (`:49-59`). The
operator surface is read-only: `contacts:phone_uniqueness:audit` and `:dry_run`
(`lib/tasks/contact_phone_uniqueness.rake:18-20`).

**Blank is NULL, not `''`.** `prepare_contact_attributes` nils out blank `phone_number` and `identifier` and
downcases `email`, *before validation* rather than before save, because `Contact.import` runs validation
callbacks and skips save callbacks (`app/models/contact.rb:229-234`). This is what lets any number of contacts
have no number while a second `''` would collide.

**Phone numbers have one rule, in one place.** `Contacts::Phone::STRUCTURAL_FORMAT = /\A\+[1-9]\d{1,14}\z/`
(`app/services/contacts/phone.rb:21`) is what may be *stored*; `Contacts::Phone.e164` is what may be *typed*,
and it deliberately has **no default region** — a local number with no explicitly supplied country returns nil
rather than a guess (`:26-36`). No account locale, timezone, inbox or business number is consulted.

**`contact_identities` — the additional values a contact owns.** One row is one normalized phone number or email
address, UNIQUE on `(account_id, identity_type, value)`
(`custom/db/migrate/20261009120000_create_contact_identities.rb:60-61`), with `source` of `agent_linked` or
`merged` and no fuzzy source at all (`custom/app/models/contact_identity.rb:14-21`). The table holds only the
*additional* values; `contacts.phone_number` / `contacts.email` stay the primary fields, so an empty table means
today's behaviour and no backfill (migration comment `:33-38`). Rows are written through exactly one service,
`Contacts::IdentityLinker`, which normalizes, checks both domains for an owner and reports rather than raises
(`custom/app/services/contacts/identity_linker.rb:33-45`). Reading a link ignores the feature flag on purpose —
"a link an account made while the feature was on must keep routing its messages if the feature is later turned
off" (`:15-18`).

The two tables must agree on who owns a value and no index spans both, so the check runs from both sides:
`IdentityLinker#current_owner` looks at rows *and* primary fields (`:76-87`), and
`Custom::Concerns::Contact#primary_identities_not_linked_elsewhere` stops an agent giving a contact a value
already linked to somebody else (`custom/app/models/custom/concerns/contact.rb:26-45`). It is conditional on
`phone_number_changed? || email_changed?`, which keeps it off the hot inbound path.

Inbound resolution adds two fallbacks after the OSS order (identifier → email → phone candidates → Instagram
source_id): a linked-identity lookup, then a TikTok `social_tiktok_user_id` lookup
(`custom/app/builders/custom/contact_inbox_with_contact_builder.rb:30-32`). Both are exact matches. The TikTok
index's shape was measured, not guessed — the expression must lead and the index cannot be partial
(`custom/db/migrate/20261009130000_add_social_identity_index_to_contacts.rb:13-25`).

**Merge is wrapped, not replaced.** The OSS action moves conversations, messages, contact_inboxes and notes,
then destroys the mergee before copying attributes onto the base (`app/actions/contact_merge_action.rb:34-66`).
`Custom::ContactMergeAction` hooks `merge_and_remove_mergee_contact` to run `Contacts::MergeRelocation` before
and absorb identities plus write an audit row after (`custom/app/actions/custom/contact_merge_action.rb:30-38`).
`MergeRelocation` exists because the database used to settle eight relations silently and badly —
`campaign_recipients` and `commerce_customer_links` CASCADE-deleted, `support_tickets`, `commerce_carts` and
`commerce_action_runs` SET NULL, `csat_survey_responses` never moved, taggings destroyed, `contact_identities`
CASCADE-deleted (`custom/app/services/contacts/merge_relocation.rb:8-15`). It moves all of them inside the
merge's existing transaction, keeps the base's row where a scoped uniqueness forbids two, repoints dependents
before discarding, and returns moved/discarded counts (`:32-58`, `:89-122`). Labels move through the gem's own
`add_labels` so tag counters stay right (`:126-132`). `calls` is deliberately absent — this fork has no Call
model (`:27-29`).

Identities are absorbed *after* the destroy, because until then the mergee's number is another contact's primary
field and the linker would correctly call it a conflict
(`custom/app/actions/custom/contact_merge_action.rb:15-20`). A value the survivor kept is not an additional
identity and redundant rows are cleared (`:50-62`). The audit row carries ids, counts and booleans only, never a
phone number or address (`:22-24`, `:74-85`), and a failed audit write never rolls back a succeeded merge
(`:86-90`).

**Activity timeline** is a read projection over eleven existing sources, not a new event table
(`custom/app/services/contacts/activity_timeline_query.rb:1-25`). Six categories, two CORE adapters whose
failure fails the request and five optional ones that degrade to `partial: true` plus a warning (`:33-51`,
`:93-101`). Pagination is mandatory and bounded: default 30, max 100 (`:27-28`).

**Customer 360** is two different things with one name. The published article describes the Commerce *Overview*
tab (`custom/db/documentation/en/commerce/customer-360.md:9-22`); the Lynomia identity work added an
**Identities** tab on the contact page (`docs/p10/05-omnichannel-customer-360.md`,
`app/javascript/dashboard/components-next/Contacts/ContactsSidebar/ContactIdentities.vue:10-18`). Nothing
documents the second.

## 2. Surfaces and routes

| Surface | Vue / component | API | Controller + action |
|---|---|---|---|
| Contacts list, label and segment views | `routes/dashboard/contacts/routes.js:12-52`, `pages/ContactsIndex.vue` | `GET/POST /api/v1/accounts/:id/contacts{,/search,/active,/filter}` | `contacts_controller.rb:21,26,59,66` |
| Contact detail + sidebar tabs | `pages/ContactManageView.vue:70-90` | `GET …/contacts/:id` | `contacts_controller.rb:64` |
| Create contact | `components-next/Contacts/ContactsForm/CreateNewContactDialog.vue:93-146` | `POST …/contacts` | `contacts_controller.rb:89-102` |
| Edit contact | `ContactsForm/ContactsForm.vue` via `Pages/ContactDetails.vue` | `PATCH …/contacts/:id` | `contacts_controller.rb:104-110` |
| Delete contact | `ContactsCard/ContactDeleteSection.vue:28`, `ConfirmContactDeleteDialog.vue` | `DELETE …/contacts/:id` | `contacts_controller.rb:112-122` |
| Custom attributes panel | `ContactsSidebar/ContactCustomAttributes.vue` | `POST …/contacts/:id/destroy_custom_attributes` | `contacts_controller.rb:84-87` |
| Labels on a contact | `Contacts/ContactLabels/ContactLabels.vue` | `GET/POST …/contacts/:id/labels` | `contacts/labels_controller.rb:1-12` |
| CSV / paste import + preview | `ContactsForm/ContactImportDialog.vue:1-10` | `POST …/contacts/import`, `…/import_preview` | `contacts_controller.rb:32-46` |
| Export | `ContactsForm/ContactExportDialog.vue` | `POST …/contacts/export` | `contacts_controller.rb:48-56` |
| Bulk actions bar | `contacts/components/ContactsBulkActionBar.vue` | `POST …/bulk_actions` | `bulk_actions_controller.rb:12-24` |
| Merge (contact page) | `ContactsSidebar/ContactMerge.vue:85-102` | `POST …/actions/contact_merges` | `actions/contact_merges_controller.rb:5-12` + `custom/.../contact_merges_controller.rb:7-10` |
| Merge (conversation sidebar) | `routes/dashboard/conversation/contact/ContactInfo.vue:342-354` → `modules/contact/ContactMergeModal.vue` | same | same |
| Linked identities | `ContactsSidebar/ContactIdentities.vue` | `GET/POST/DELETE …/contacts/:id/identities` | `contacts/identities_controller.rb:15-36` |
| Activity timeline | `ContactsSidebar/ContactActivity.vue` | `GET …/contacts/:id/activity` | `contacts/activity_controller.rb:12-22` |
| Import history | Settings → Data | `…/data_imports` | `config/routes.rb:183-194` |

Routes are declared at `config/routes.rb:156-182`; `identities` and `activity` are the two Lynomia additions
(`:176-180`).

## 3. User-visible states

**List.** Empty account, empty view, empty search and empty active list each get their own sentence
(`contact.json:767-774`). The list shows only *resolved* contacts — those
with at least one of the three identities (`app/models/contact.rb:183-187`, `view_scope.rb:52`) — so an imported
name-only row exists and is invisible. Pages are 15 rows (`contacts_controller.rb:14`).

**Search.** `search` returns `has_more` rather than a count, by design: an unindexed ILIKE over four columns with
a COUNT on the hot path is what `has_more` exists to avoid (`contacts_controller.rb:169-185`,
`ContactsBulkActionBar.vue:32-37`). So the bulk bar reads **All results in this view selected** with no number
on a search (`contact.json:813`), and **All {count} selected** elsewhere (`:808`).

**Bulk selection.** Row selection, page selection, and whole-view selection which only appears once the page is
exhausted (`ContactsBulkActionBar.vue` `canSelectAllMatching`). Over-limit shows **This view has too many
contacts to act on at once. Narrow it first.** (`contact.json:814`).

**Import dialog.** Two steps, six preview tiles (`new_contact`, `update_existing`, `skip_existing`,
`duplicate_in_file`, `no_identity`, `invalid`) and a noteworthy-rows list
(`ContactImportDialog.vue:23-34`). A file longer than 250 rows is previewed partially and says so
(`isPartialPreview`, `DataImport::ContactPreview:17`, `:28-39`). Each row shows the number as it *would be*
stored (`contact_preview.rb:69-78`).

**Duplicate recovery on create.** A 422 whose single taken field is identifiable triggers a lookup and offers
**Open {name}** and **Add "{label}" to {name}** (`CreateNewContactDialog.vue:86-146`, `contact.json:903-910`).
Two collided fields offer nothing, because they can belong to two different contacts (`:88-90`).

**Identities tab.** Loading spinner, two labelled sections ("Primary" / "Also reachable at"), an empty state, a
per-row source label ("Linked by an agent" / "From a merge"), and the add form only when `canManage`
(`ContactIdentities.vue:124-220`). The tab is absent entirely for an account without
`lynomia_unified_identity` (`ContactManageView.vue:54-58,81`).

**Activity tab.** Seven category filters, loading, empty, error, **partial** banner naming the degraded sources,
and Load more (`ContactActivity.vue`, `contact.json:667-669`).

**Merge tab.** Search combobox, a "To be deleted / To be saved" diagram, and three standing paragraphs including
**This cannot be undone. The merge is recorded in the audit log.** and the carried-over list
(`ContactMerge.vue:106-120`, `contact.json:280-281`).

## 4. Errors and validation messages

Server, `config/locales/en.yml`:

| Key | String | Raised at |
|---|---|---|
| `errors.contacts.phone_number.invalid` (`:143`) | `should be in e164 format` | `app/models/contact.rb:56` |
| `errors.contacts.email.invalid` (`:141`) | `Invalid email` | `app/models/contact.rb:52` |
| `errors.contacts.identities.linked_elsewhere` (`:147`) | `is already linked to another contact in this account` | `custom/app/models/custom/concerns/contact.rb:35` |
| `errors.contacts.identities.conflict` (`:150`) | `This already belongs to another contact in this account (contact %{contact_id}).` | `identities_controller.rb:49` |
| `errors.contacts.identities.feature_disabled` (`:146`) | `Linked identities are not enabled for this account` | `identities_controller.rb:43,50` → **404** |
| `errors.contacts.identities.unknown_type` (`:148`) | `must be one of: %{types}` | `identities_controller.rb:58` |
| `errors.contacts.identities.unusable` (`:149`) | `is not a phone number or an email address we can use. A local phone number needs its country.` | `identities_controller.rb:61` |
| `errors.contacts.labels.not_found` (`:152`) | `do not exist in this account: %{labels}` | `contact_label_params.rb:34-36` |
| `errors.contacts.bulk_action.too_many` (`:129`) | `matches more than %{count} contacts. Narrow the filter…` | `bulk_actions_controller.rb:73` |
| `errors.contacts.import.phone_country_required` (`:132`) | `A local phone number needs a country. Add a country_code column or choose one for this import.` | `data_import_job.rb:65` |
| `errors.contacts.import.not_a_csv` (`:133`) | `must be a CSV file` | `contact_import_file.rb:99,106` |
| `errors.contacts.import.too_large` (`:134`) | `must be smaller than %{size} MB` | `contact_import_file.rb:101` |
| `errors.contacts.import.not_an_import_file` (`:135`) | `is no longer available. Choose the file again.` | `contact_import_file.rb:70` |
| `errors.contacts.import.too_many_numbers` (`:136`) | `holds more than %{count} numbers. Split the list…` | `contact_import_file.rb:122` |
| `errors.contacts.import.not_a_country` (`:137`) | `%{country} is not a country code` | `contact_import_params.rb:61` |
| `errors.contacts.import.not_a_duplicate_policy` (`:138`) | `must be one of: %{policies}` | `contact_import_params.rb:69-71` |
| `errors.contacts.import.failed` (`:131`) | `File is blank` | `contact_import_params.rb:30` |
| `contacts.online.delete` (`:536`) | `%{contact_name} is Online, please try again later` | `contacts_controller.rb:116` |
| `errors.timeline.*` (`:244-246`) | invalid cursor / unsupported category / invalid limit | `lib/custom_exceptions/timeline.rb:10-26`, all **422** |

Client, `app/javascript/dashboard/i18n/locale/en/contact.json`. `contactErrors.js` maps `(attribute, validator)`
pairs to localized strings and falls back to the server's own wording, which keeps a format rejection from being
rendered as "in use" (`app/javascript/dashboard/helper/contactErrors.js:1-30`): `CONTACT_ERRORS.PHONE_NUMBER.TAKEN`
(`:888`), `.INVALID` (`:889`), `.NEEDS_COUNTRY` (`:890`), `EMAIL.TAKEN` (`:893`), `IDENTIFIER.TAKEN` (`:897`),
`LABELS.NOT_IN_ACCOUNT` (`:900`), `GENERIC` (`:902`). The identities panel shows the server's message and falls
back to `IDENTITIES.LINK_ERROR` / `UNLINK_ERROR` / `LOAD_ERROR` (`:750-752`).

Older duplicate strings survive in four places and say something different — "This email address is in use for
another contact." (`contact.json:106,334,509`) and the phone equivalents (`:115,335,513`).

## 5. Failure paths

**Lost uniqueness race.** Two simultaneous writes both pass the `uniqueness` SELECT and the database refuses the
loser. `reject_duplicate_contact` revalidates so the loser gets the same 422 it would have got a moment later,
and re-raises if revalidation finds nothing — rather than inventing a message
(`contacts_controller.rb:131-144`). Applies to all three identity columns now that phone is indexed.

**`identifier: ""` → 500.** `permitted_params` permits `identifier` directly (`contacts_controller.rb:199`) and
`allow_blank: true` skips the validation, so before the Lynomia normalization the second `''` in an account hit
`uniq_identifier_per_account_contact` and answered 500. `prepare_contact_attributes` now nils it
(`app/models/contact.rb:231-232`); the history is in `docs/contacts/11-phone-uniqueness.md` §E2.2.

**Merge refused by policy.** The Merge tab (`ContactManageView.vue:85`) and the conversation-sidebar merge
button (`ContactInfo.vue:342-354`) carry **no permission gate**, while the server now requires administrator or
`contact_manage` (`custom/app/policies/custom/contact_policy.rb:17-19`). A plain agent reaches the confirm
button and gets the generic **Could not merge contacts, try again!** (`contact.json:293`) — which does not say
why and invites a retry that cannot succeed.

**Import/Export offered and then refused.** `ContactMoreActions.vue:40-42` gates both on
`['administrator','contact_manage']`, and the route itself admits `contact_manage`
(`routes/dashboard/contacts/routes.js:7-10`), but `ContactPolicy#import?`/`#export?` are
`@account_user.administrator?` with no Lynomia override (`app/policies/contact_policy.rb:10-21`;
`custom/app/policies/custom/contact_policy.rb` adds only `merge?` and `manage_identities?`). An agent with
`contact_manage` sees both menu items and is refused by Pundit.

**A third contact owns the value.** A merge that would absorb a value belonging to a third contact skips that
row, does not merge into it, and never rolls back the merge
(`custom/app/actions/custom/contact_merge_action.rb:64-72`). The count is visible only in the audit row's
`identities_absorbed`; nothing tells the agent a value was dropped.

**Bulk delete ignores the online check.** Single delete refuses for a contact currently online
(`contacts_controller.rb:113-118`); `Contacts::BulkDeleteService#perform` calls `destroy!` on each with no such
check (`app/services/contacts/bulk_delete_service.rb:7-11`).

**Bulk partial failure is silent.** `BulkAssignLabelsService` returns `{ success: true, … }` regardless
(`app/services/contacts/bulk_assign_labels_service.rb:9-18`); `BulkActionService` logs an unknown payload and
returns `{ success: false, error: 'unknown_operation' }` to a job nobody reads
(`app/services/contacts/bulk_action_service.rb:12-13`). The user is told the batch completed via
`contact.bulk_action_completed` (`app/jobs/contacts/bulk_action_job.rb:13,30`).

**Import is not transactional across the file.** Updates to existing contacts are written once the whole file is
read, so a mid-file failure has not already changed half the account
(`app/jobs/data_import_job.rb:83-89`). Inserts use `on_duplicate_key_ignore: true` (`:78`). Rejected rows go
into an attached `failed_records` CSV with an `errors` column (`:116-135`) and the account's administrators get
an email (`:142-144`) — the page that started the import never reports completion.

**Timeline degradation.** A commerce or ticket table being unavailable produces a warning and `partial: true`
rather than hiding the conversation history; a Messages or ConversationEvents failure raises
(`activity_timeline_query.rb:93-101`). An authorization error is never downgraded (`:92` comment).

**Blocked contacts still receive campaigns.** Documented in the corpus
(`custom/db/documentation/en/contacts/contacts.md:83-88`) and not contradicted by anything I read; not
independently verified here.

## 6. Permissions

| Surface | Gate | Citation |
|---|---|---|
| index / active / search / filter / show / create / update / avatar / contactable_inboxes / destroy_custom_attributes | any account member | `app/policies/contact_policy.rb:3-53` |
| destroy | administrator | `app/policies/contact_policy.rb:55-57` |
| import / import_preview / export | **administrator only** | `app/policies/contact_policy.rb:10-21` |
| bulk delete | `Contact#destroy?` | `bulk_actions_controller.rb:82` |
| bulk labels | `Contact#update?` + label catalogue check | `bulk_actions_controller.rb:86-95` |
| merge | administrator **or** `contact_manage` | `custom/app/policies/custom/contact_policy.rb:15-19` |
| link / unlink identity | `manage_identities?` = `merge?` | `custom/app/policies/custom/contact_policy.rb:25-27`, `identities_controller.rb:22,32` |
| read identities | `@contact.show?` | `identities_controller.rb:16` |
| activity timeline | `@contact.show?`, then narrowed per-conversation by `Conversations::PermissionFilterService` | `activity_controller.rb:13`, `activity_timeline_query.rb:116-131` |
| identities endpoints | feature `lynomia_unified_identity`, else **404** | `identities_controller.rb:40-43`, `identity_linker.rb:18`, `config/features.yml:319` |
| contacts section itself | `FEATURE_FLAGS.CRM`, roles `administrator, agent, contact_manage` | `routes/dashboard/contacts/routes.js:7-10` |

`contact_manage` resolves through the one permission list every Lynomia policy reads
(`custom/app/models/custom/account_user.rb:1-18`), and that list can never reach administrator — administrator
is the `role` column.

Before the Lynomia overlay the merge endpoint performed **no** `authorize` call at all, so any member including
an inbox-restricted agent could destroy any contact in the account by merging it
(`custom/app/policies/custom/contact_policy.rb:3-7`). The web widget's automatic identify-and-merge
(`ContactIdentifyAction`) is deliberately not gated — it has no acting agent
(`custom/app/policies/custom/contact_policy.rb:11-13`, `app/actions/contact_identify_action.rb:12-22`).

## 7. Contextual-help opportunities

| UI location | The question there | Registry key | Exists in `DOC_ARTICLES`? |
|---|---|---|---|
| `ContactIdentities.vue:189-220` (add form) | "What is a linked identity, and what does linking change?" | `contactIdentities` | **no** |
| `ContactIdentities.vue:129-148` (Primary vs linked) | "Why are these two lists separate?" | `contactIdentities` | **no** |
| `ContactManageView.vue:74` (Activity tab) | "What is on this timeline and why is some of it missing?" | `contactActivity` | **no** |
| `ContactActivity.vue` partial banner (`contact.json:669`) | "Which sources failed and is what I see complete?" | `contactActivity` | **no** |
| `ContactMerge.vue:106-120` | "What moves, what is lost, who may do this?" | `contactMerge` | **no** (`contacts` covers it badly) |
| `ContactMergeModal.vue` from the conversation sidebar | same, for an agent who may not be allowed | `contactMerge` | **no** |
| `ContactImportDialog.vue:360-375` (duplicate policy) | "Update or keep — which?" | `contactImport` | yes → `import-contacts` (`documentationLinks.js:28`) |
| `ContactImportDialog.vue` country selector | "Why does a local number need a country?" | `contactImport` | yes, same article |
| `ContactsBulkActionBar.vue` whole-view selection | "What does 'all in this view' mean, and what is the cap?" | `bulkActions` | yes (`documentationLinks.js:29`) |
| `CreateNewContactDialog.vue:903-910` duplicate panel | "Is this the same person? Should I merge?" | `contacts` | yes (`documentationLinks.js:26`) |
| `ContactCustomAttributes.vue` empty state (`contact.json:608`) | "How do I create one?" | `customAttributes` | yes (`documentationLinks.js:27`) |
| `ContactDeleteSection.vue:28` | "What else is deleted with this contact?" | `contacts` | yes, but the article understates it |

Four of the twelve have no key at all, and all four are Lynomia-specific features.

## 8. Current documentation coverage

Four articles, EN + AR, under section `contacts` (`custom/db/documentation/manifest.yml:27-35`):

| Key | EN | AR | EN lines / words | AR lines / words |
|---|---|---|---|---|
| `contacts` | `en/contacts/contacts.md` | `ar/contacts/contacts.md` | 128 / 1144 | 118 / 191 |
| `custom-attributes` | `en/contacts/custom-attributes.md` | yes | 139 / 1298 | 129 / 259 |
| `import-contacts` | `en/contacts/import-contacts.md` | yes | 169 / 1450 | 166 / 342 |
| `bulk-actions` | `en/contacts/bulk-actions.md` | yes | 140 / 1350 | 128 / 252 |

Structurally parallel (line counts track), so the AR word counts are a scripting artefact of Arabic
tokenization rather than evidence of truncation — but I did not compare the two bodies sentence by sentence;
that is 051's and 061's work. Flagging it so nobody reads the table as a parity verdict.

What the four do well: the phone-number rule including the refusal to guess a region
(`contacts.md:43-55`), the resolved-contacts rule (`contacts.md:57-59`), the import preview and the two duplicate policies
(`import-contacts.md:51-57`, `:110-118`), the 10,000 bulk cap and the label-vs-audience distinction
(`bulk-actions.md:102-105`, `:54-61`).

`custom-attributes.md` is the one article I found no contradiction in.

Adjacent: `en/commerce/customer-360.md` documents the Commerce Overview tab and explicitly says "the contact is
the identity, Customer 360 is the evidence" (`:39`) — correct for commerce, and now ambiguous because the
product has a second thing called identity.

## 9. Missing or stale documentation

**Nothing documents linked identities.** No article mentions `contact_identities`, the Identities tab, what
linking does to inbound routing, the `lynomia_unified_identity` flag, who may link, what a conflict means, or
that unlinking is possible. A corpus-wide search for `linked identit`, `identities tab` or `contact_identities` returns nothing; `contacts.md` uses the word "identities" only for the three primary fields (`:25`, `:57`).
This is the single largest gap in scope: it is a routing decision an agent makes by hand, and the only
explanation of it is a sentence of UI copy (`contact.json:740-741`).

**Nothing documents the activity timeline.** Seven filters, a partial-degradation banner naming sources an agent
has never heard of ("reporting_events", "commerce"), and 40+ event kind labels (`contact.json:671-735`) with no
article behind any of them.

**Nothing documents what a merge now carries.** `MergeRelocation` moves eight relations and discards duplicates
on two of them; the audit row records both counts. The article still describes the pre-Lynomia four.

**Nothing documents the merge permission boundary**, which is new and is the reason an agent's merge fails.

**Nothing documents the contact audit event.** `contact.merged` reaches Settings → Audit Logs
(`custom/app/actions/custom/contact_merge_action.rb:22-24,74-85`) and both articles say contacts are never
audited.

**Nothing documents TikTok contact dedup** — a customer who used to get a new contact per conversation now does
not (`custom/db/migrate/20261009130000…:4-9`). That is a visible behaviour change with no release note in the
corpus.

**Thin:** the 250-row preview bound is stated (`import-contacts.md:116`, `:137`) but the 10 MB / 10,000-number caps are
stated only for files and pastes separately (`:30`, `:103-104`) and the signed-blob TTL of one hour
(`contact_import_file.rb:15-16`) is not stated anywhere — a user who leaves the dialog open gets **is no longer
available. Choose the file again.** with no explanation.

## 10. Doc claims not proven by code

| Claim | Where | Code | Verdict |
|---|---|---|---|
| "Merge two contacts \| any agent" | `en/contacts/contacts.md:94` | administrator or `contact_manage` (`custom/app/policies/custom/contact_policy.rb:17-19`) | **wrong** |
| "One thing does not move: **labels**. The record being removed takes its labels with it. If it carries a label that matters, apply that label to the primary contact before you merge." | `en/contacts/contacts.md:74-76` | `MergeRelocation#move_labels` calls `@base.add_labels(names)` (`:126-132`); the UI says labels move (`contact.json:281`) | **wrong**, and it tells the user to do unnecessary work |
| "Conversations, messages, notes and channel links all move to the primary contact." | `en/contacts/contacts.md:71` | plus support cases, campaign recipients, commerce links and carts, action runs, CSAT, labels, linked identities (`merge_relocation.rb:32-58`) | **incomplete** |
| "Changes to a contact are not recorded in the account's audit log." | `en/contacts/contacts.md:102` | `contact.merged` audit row (`custom/app/actions/custom/contact_merge_action.rb:26,74-85`) | **wrong for merges** |
| "**Bulk actions are not recorded in the audit log**, and neither is any other change to a contact." | `en/contacts/bulk-actions.md:110` | same | **wrong for merges** |
| "Import and export \| administrator, or an agent whose custom role includes contact management" | `en/contacts/contacts.md:96` | `import?`/`export?` = `administrator?` only (`app/policies/contact_policy.rb:10-21`) | **wrong** (the *menu* follows the doc, the server does not) |
| "You must be an **administrator**. On plans with custom roles, an agent granted contact management can import too." | `en/contacts/import-contacts.md:27-28` | same | **wrong** |
| "Export … is administrator-only" | `en/contacts/bulk-actions.md:112-114` | correct per policy, and contradicts `contacts.md:96` in the same corpus | **internally inconsistent** |
| "unlike deleting a single contact it does not stop for a contact who is currently online" | `en/contacts/bulk-actions.md:111` | `bulk_delete_service.rb:7-11` vs `contacts_controller.rb:113-118` | **confirmed** |
| "Every other column is kept on the contact as a custom attribute value" | `en/contacts/import-contacts.md:49-50` | `contact_manager.rb:141` merges `params.except(:identifier, :email, :name, :phone_number)` — so `labels`, `company_name`, `city`, `country_code`/`country` are *also* written into `custom_attributes` | **wrong in detail**: the four handled columns are duplicated into custom attributes, not excluded |
| "the dialog finds the contact that already holds it and offers to open it" / "When exactly one field clashed" | `en/contacts/contacts.md:36-38` | `offerRecovery` requires `takenFields.length === 1` and the lookup can return null (`CreateNewContactDialog.vue:86-91`, `:65-84`) | **confirmed** |
| "takes at most 10,000 numbers per paste" | `en/contacts/import-contacts.md:103-104` | `MAX_PASTED_NUMBERS = 10_000` (`contact_import_file.rb:13`) | **confirmed** |
| "10,000 contacts per action … refused outright" | `en/contacts/bulk-actions.md:102-104` | `CONTACT_VIEW_LIMIT = 10_000`, `too_many_contacts!` (`bulk_actions_controller.rb:10,65-75`) | **confirmed** |
| "The preview checks the first 250 rows" | `en/contacts/import-contacts.md:137` | `ROW_LIMIT = 250` (`contact_preview.rb:17`) | **confirmed** |
| "Deleting a contact … deletes its conversations with it" | `en/contacts/contacts.md:100-101` | `has_many :conversations, dependent: :destroy_async` (`app/models/contact.rb:59`); support cases survive with `contact_id` nullified (`custom/app/models/custom/concerns/contact.rb:9-11`), linked identities CASCADE away | **confirmed but incomplete** |
| "Uniqueness is per account." | `en/contacts/contacts.md:105-106` | all four unique indexes are scoped to `account_id` | **confirmed** |

One claim I could not check: that a blocked contact's inbound WhatsApp messages are "dropped rather than queued"
(`en/contacts/contacts.md:79-81`). That belongs to 040's scope and I did not read the WhatsApp inbound path.
Marked **not checked** rather than fine.
