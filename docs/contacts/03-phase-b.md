# Contacts Phase B — contact create / label reliability

What changed, why, and what it is proved by. Phase A's discovery
([00](00-existing-system-discovery.md), [01](01-reuse-map.md), [02](02-discovery-checkpoint.md)) is the input;
this is the fix.

Branch `claude/practical-thompson-9xfqed`, base `968aef48`.

**The objective:** a contact must never appear to belong to a label only because the store put it in the list.
After a successful create it either genuinely owns the label, or it is not in the label-filtered list.

---

## B0 — the success path, answered

Traced end to end before anything was changed.

| Question | Answer |
|---|---|
| 1. Did the backend accept `labels` on create? | **No.** `permitted_params` (`contacts_controller.rb:173-175`) listed `name, identifier, email, phone_number, avatar, blocked, avatar_url, additional_attributes, custom_attributes`; the Enterprise override adds only `company_id`. |
| 2. If yes, where were they persisted? | — |
| 3. If no, where were they dropped? | At the request boundary, by `params.permit`. Nothing downstream read `params[:labels]` in `create`; the only reader was `resolved_contacts` (`:125`), which uses it as a **list filter** — `tagged_with(..., any: true)`. The frontend never sent it either: `buildContactParams`'s `labels` (`api/contacts.js:5-11`) is a query param for `get`/`search`, and `CreateNewContactDialog` had no props and `ContactsForm` no label field. |
| 4. Did the create response contain the persisted labels? | **No.** `create.json.jbuilder` renders `_contact.json.jbuilder`, which has no `labels` key. |
| 5. Why could `SET_CONTACT_ITEM` place a contact on a filtered page without checking membership? | Because that mutation pushes the id into `sortOrder` unconditionally (`mutations.js:55-57`), and `sortOrder` **is** the rendered list (`getters.js:5`). Nothing refetched afterwards, so no server ever confirmed membership. |

Two things the trace corrected in the brief's premise, both proved by test rather than argument:

- **`/contacts` is itself a server-filtered view.** `index` reads `resolved_contacts`, i.e. `email <> '' OR
  phone_number <> '' OR identifier <> ''` (`contact.rb:183-187`). The create form requires only a first name,
  so a name-only contact is pushed into a list the server will never return it in. The defect was therefore
  not limited to label pages, and "the ordinary list relies on the insertion" was false.
- **The E.164 rule is structural, not a real-number check.** `+9650551112233` — a dial code concatenated onto
  a trunk-prefixed local number — is 13 digits and **passes** `/\A\+[1-9]\d{1,14}\z/`. So the old phone input
  did not reliably produce the 422 the brief describes; for an ordinary-length number it stored a wrong phone
  number silently. It only 422s once the concatenation exceeds fifteen digits. Both cases are now asserted
  (`contacts_controller_spec.rb`, "accepts a dial code concatenated onto a trunk prefix" and "rejects it once
  the concatenation exceeds fifteen digits").

---

## B1 — create with a label is durable

**Server.** `requested_label_titles(contact)` lives in a new concern,
`app/controllers/concerns/contact_label_params.rb`, included by the contacts controller. It normalizes the
requested titles, resolves them against `Current.account.labels`, and rejects an unknown one with a 422 built
from the record's own errors — the same `{ message, attributes, errors, error_types }` body every other
validation failure uses. `create` then assigns them as part of building the contact:

```ruby
@contact = Current.account.contacts.new(permitted_params.except(:avatar_url))
@contact.label_list = requested_label_titles(@contact)
@contact.save!
```

`label_list=` is the same acts-as-taggable-on writer `Labelable#update_labels` uses, and the gem persists the
taggings from its own `after_save`. So one save covers both, the contact is never briefly label-less, and
exactly one `contact.created` event is dispatched and no `contact.updated` — asserted, not assumed.

Labels are deliberately **not** in `permitted_params`: they are taggings, not a column.

**Why an unknown label is a 422 rather than silently dropped.** `update_labels` will create a tag for any
string, and a tag outside the account's catalogue is invisible to the contacts sidebar, dropped by the CSV
exporter (`contacts_export_job.rb:39-41`) and ignored by campaign audiences (`campaign.rb:72`). The CSV
importer already rejects unknown labels (`data_import_job.rb:47-55`), so this matches the one existing
server-side writer. `POST /contacts/:contact_id/labels` stays permissive — a deliberate asymmetry, recorded
in [§Known limitations](#known-limitations) rather than changed, because existing specs rely on off-catalogue
contact tags.

**Response.** `create.json.jbuilder` now emits `json.labels @contact.label_list` inside the contact object —
there only, not in the shared `_contact` partial, which renders for every row of index, search and filter and
would cost a taggings query per row.

**Client.** `CreateNewContactDialog` reads the active label from the route and sends it:

```js
labels: activeLabel.value ? [activeLabel.value] : undefined
```

API contract updated: `labels` on the create request
(`swagger/definitions/request/contact/create_payload.yml`) and on the create response
(`swagger/definitions/resource/extension/contact/show.yml`), with `swagger.json` regenerated.

---

## B2 — the real validation, next to its field, in both languages

The server already sent the reason; five call sites threw it away. The chain now is:

1. **`render_record_invalid`** (`request_exception_handler.rb:58-72`) adds two keys to the 422 body it already
   sent. `errors` keys the full messages by attribute, because `message` joins them with a comma and a client
   cannot split that back onto attributes — one attribute can carry several errors, and a message can itself
   contain a comma. `error_types` keys the **validator** by attribute, which is what lets a client tell
   "already taken" from "wrong format" when both land on `phone_number`. Both are additive; `message` and
   `attributes` are unchanged. The concern is app-wide, so every `RecordInvalid` 422 in the product gains
   them.
2. **`handleContactOperationErrors`** (`contacts/actions.js`) attaches them to the thrown exception, and
   `DuplicateContactException` declares `fieldErrors` / `fieldErrorTypes` as part of its contract.
3. **`dashboard/helper/contactErrors.js`** turns a caught error into the per-field messages and one message
   that is never empty. Where we have our own wording for an `(attribute, validator)` pair it uses that, so
   the text is localized; otherwise it falls back to the server's own sentence, so a validation we have not
   seen before still shows real text instead of disappearing.
4. **`ContactsForm`** takes a `serverErrors` prop and maps server attribute names to its own field keys
   (`SERVER_ATTRIBUTE_FIELDS`: `phone_number` → PHONE_NUMBER, `email` → EMAIL_ADDRESS, `name` → FIRST_NAME,
   since `name` has no field of its own). It passes `:message` to `Input` — which it never did before, so
   even local validation errors used to be a red outline with no text — and `:error-message` to
   `PhoneNumberInput`. An attribute with no field (`identifier`, `labels`) is shown by the dialog's alert, so
   none is dropped.
5. **`PhoneNumberInput`** joins an external message into `hasError` so the field outlines red, and the message
   now wraps instead of truncating — "Phone number should be in e164 format" does not fit one clipped line in
   a half-width grid cell.

The dialog keeps its values on a 422 and does not report success, both asserted.

**Why Arabic works now.** Not by translating the server's string. `app/models/contact.rb:52,56` build their
messages with `I18n.t` **in the class body**, so each is frozen at class-load time in whatever locale was
active then — one string for the whole process, for every account. Keying off `error_types` sidesteps that
entirely: the client picks its own `CONTACT_ERRORS.*` string, which exists in `en` and `ar`. The frozen
message survives only as the fallback for validators we have no wording for. The underlying defect is
recorded in [§Known limitations](#known-limitations).

Backend strings: `errors.contacts.labels.not_found` added to `en.yml` and to the `errors.contacts` block in
`ar.yml` — the **existing** one. A first attempt added a second `errors.contacts:` mapping under the same
parent, which Psych resolves by keeping the later block, silently dropping the new key; caught by loading the
YAML rather than grepping it.

---

## B3 — duplicate recovery, no new endpoint

When a create is rejected because an identity key is already taken, the dialog offers **Open the existing
contact** and, on a label page, **Add this label to the existing contact**.

| Decision | Why |
|---|---|
| The trigger is the **validator**, not the attribute name | `phone_number` carries both a uniqueness and a format rule. `takenIdentityFields` only fires on `taken`, so a malformed number — which can belong to nobody — never offers recovery. |
| And the lookup has the last word | Recovery renders only if a contact is actually found, so the flow cannot dead-end. |
| The lookup calls `ContactAPI.filter` **directly**, not `contacts/filter` | The store action never clears its own `isFetching` when `resetState: false` (the clear sits inside the `if`), which on the contacts page would leave a spinner where the list should be and make every later fetch a no-op. |
| One collided key only | Two taken keys can belong to two different contacts, so nothing is offered rather than guessing which. |
| Adding the label uses `BulkActionsAPI` | `POST /bulk_actions` with `labels: { add: [...] }` reaches `Contacts::BulkAssignLabelsService` → `add_labels`, which is **additive** server-side. The alternative, `contactLabels/update`, is a full replace that would need a read first and could drop another agent's label in between. |
| Opening uses `contactDetailRoute` | Extracted from `ContactsList.vue` into `dashboard/helper/contactRoutes.js` and now used by both: pushing plain `contacts_edit` from a label page drops the param the detail view's context needs. |

**No new endpoint, and nothing disclosed.** `POST /contacts/filter` runs `Contacts::FilterService` scoped to
`Current.account`, so a contact in another account is simply not found — the response cannot distinguish
"exists elsewhere" from "does not exist". Asserted from the other side too: creating a contact whose phone
number belongs to another account's contact **succeeds**, and the response names nothing of the other
account's.

Uniqueness is untouched. Nothing auto-merges.

A pre-existing bug was fixed on the way: `message/bubbles/Contact.vue` passed the `ComputedRef` instead of
its value to its lookup, so that lookup had never once succeeded.

---

## B4 — phone normalization, client side only

Phase A established there is **no server-side region source**: no country column on `accounts`, none on any
channel, and nothing derives a region from an inbox's own number. The only region signal on a contact write is
the client's `additional_attributes.country_code`. So the server is unchanged — its E.164 rule stays
authoritative — and no fifth Ruby normalizer was added.

`app/javascript/shared/helpers/phoneNumber.js` is the repo's **first** JavaScript phone helper (every other
`parsePhoneNumber` call is single-argument, so a local number never parses). It is in `shared/` so the widget's
own phone input can use it later. It keeps `Commerce::Phone`'s rule verbatim: an international number carries
its own region, a local number is read only against an **explicit** region, and `null` otherwise.

In `PhoneNumberInput`:

- `explicitRegion` is the country the user **picked**, or the form's Country field, or nothing. The country
  this component pre-fills from the **browser timezone** is deliberately not explicit — it is a visible
  default, not a statement about the contact, and reading a trunk-prefixed number against it is exactly the
  guess the brief forbids.
- The `numeric` vuelidate rule was replaced. It rejected spaces, hyphens and parentheses outright, so a pasted
  "(055) 512-3456" never reached the model at all — the contact was created with no phone number and no error
  anywhere. Formatting is now accepted and stripped.
- `00` becomes `+` and the dial code is ignored, mirroring `Commerce::Phone`.
- When no explicit region can read a trunk-prefixed number, the field says so
  (`CONTACT_ERRORS.PHONE_NUMBER.NEEDS_COUNTRY`) rather than inventing a country.
- A `lastEmitted` guard stops the `modelValue` watcher writing a normalized number back into the field while
  someone is still typing, which would move the caret.

What is **not** normalized: the legacy `components/widgets/forms/PhoneInput.vue` used by the conversation
sidebar's contact form. Scoped to the `components-next` surface per CLAUDE.md's deprecation note, and recorded
below.

---

## B5 — false list membership, fixed at the shared point

`contacts/create` now commits `SET_CONTACT_RECORD` instead of `SET_CONTACT_ITEM`: the same write to `records`
without joining `sortOrder`. That satisfies the invariant for **every** view at once — label page, segment,
search, active, and `/contacts` itself — with no per-view predicate and no client-side re-implementation of
`Contacts::FilterService`.

It is the right layer because the server decides two things the client cannot: whether a contact belongs in
this view (`/contacts` needs an email, phone or identifier; a label page needs the label; a segment needs its
query, which `Custom::Contacts::FilterService` extends with conversation and Commerce conditions) and where it
sorts (a new contact has no `last_activity_at`, and the order is NULLS LAST, so it belongs on the last page —
never appended to the current one).

So that a contact which *does* belong still appears, `ContactsIndex` re-reads the list after a create, through
the existing context-aware fetch, with `clearSelection: false` so a bulk selection survives. Two contexts are
skipped deliberately: a **search** view, whose infinite-scroll pages would all be discarded by a refetch, and
a **segment whose definition has not loaded**, where the existing fetch would fall through to the unfiltered
list. In both the contact is correctly absent and the success toast is the feedback.

The other six `SET_CONTACT_ITEM` callers are untouched — they are a different trigger, not a created contact.
Recorded below.

Regression cover: `mutations.spec.js` asserts `SET_CONTACT_RECORD` leaves `sortOrder` alone, and
`actions.spec.js` asserts `create` commits that mutation and not the other.

---

## Verification

| Gate | Result |
|---|---|
| Backend, contacts + labels + model | **105 examples, 0 failures** |
| Frontend, full suite | **478 files, 4941 tests, 0 failures** |
| ESLint, changed files | 0 errors, 4 warnings (`no-dynamic-keys`, the repo's existing pattern) |
| RuboCop, changed files | 0 offenses |
| Production build | see the closeout |

The Rails environment was built for this phase — Ruby 3.4.4, 356 gems, Postgres 16 with `pgvector`, Redis — so
the backend numbers are real integration runs, not fixtures.

New backend coverage, in `spec/controllers/api/v1/accounts/contacts_controller_spec.rb`: label persisted and
findable by `tagged_with`; a `Contact` tagging in the `labels` context, not a `Conversation` one; the catalogue
label accepted in any case, reusing the one tag; an unknown label rejected with `error_types: ['not_in_account']`
and nothing created; another account's label rejected without revealing it exists; no label applied when the
contact itself is invalid; one `contact.created` and no `contact.updated`; the e164 structural cases above; the
duplicate-phone contract with its `taken` type; the existing contact not named in the response; and a
same-number contact in another account created successfully.

New frontend coverage: `shared/helpers/specs/phoneNumber.spec.js` (17), `helper/specs/contactErrors.spec.js`
(15), `Contacts/ContactsForm/specs/CreateNewContactDialog.spec.js` (14, including the Arabic message, the
dialog staying open, both recovery actions, and all three cases where recovery is withheld), plus the two
store specs.

---

## Known limitations

Recorded, not fixed, with the reason.

| | |
|---|---|
| `Contact`'s email and phone validator messages are built with `I18n.t` in the class body, so each is frozen at class-load time for the whole process | The pattern is repo-wide (8 models). B2 routes around it by localizing from `error_types`, so no user-facing text depends on it. Fixing it properly is its own change. |
| `POST /contacts/:contact_id/labels` still accepts a title outside the account catalogue | Tightening `Labelable` would change behaviour existing specs rely on (`contacts_controller_spec.rb:150-163` filters on contact tags with no `Label` rows). Create is strict, that endpoint is not — a deliberate asymmetry. |
| The legacy `components/widgets/forms/PhoneInput.vue` (conversation sidebar) still concatenates a dial code | Scoped to `components-next`. That form does gate submit on its own phone validity, and B2 gives it the real error message. |
| The other six `SET_CONTACT_ITEM` callers can still push an arbitrary contact into a filtered list — notably the `conversation.contact_changed` websocket event (`conversations/actions.js:574`) | A different trigger from a created contact, so outside B5's invariant. Same defect class. |
| A contact created with only a name does not appear in the list at all, and on the empty state the empty state stays | Truthful, and the required behaviour: `/contacts` returns only contacts with an email, phone or identifier (`resolved_contacts`), so the server really does not list it. Previously it appeared and then vanished on the next fetch. Whether the form should require an identity field, or `resolved_contacts` should change, is a product decision beyond this phase. The success toast is the confirmation. |
| `EDIT_CONTACT` never removes a row that no longer matches the current filter | The mirror image of B5, on the inline edit path. |
| On a browser whose timezone yields no dial code (UTC), `PhoneNumberInput`'s `required` rule fails permanently and nothing is emitted | Pre-existing, unchanged by this phase. |
| Duplicate recovery can miss the existing contact when the account has `crm_v2` enabled and that contact is not a `lead` | `Contacts::FilterService` is scoped to `resolved_contacts`, which under `crm_v2` means `contact_type: 'lead'`. A contact with a phone number is promoted to `lead` by `Contacts::SyncAttributes`, so this needs a `customer` row; recovery then simply is not offered. |
| The canned duplicate strings the five handlers used to show are now unreferenced by code (`CONTACT_CREATION.{EMAIL_ADDRESS,PHONE_NUMBER}_DUPLICATE`, `CONTACT_FORM.FORM.*.DUPLICATE`, `CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.FORM.*.DUPLICATE`) | Left in place rather than deleted. They are i18n data, not code, and CLAUDE.md leaves the non-English copies to Crowdin, so removing the English keys would orphan the translated ones across every locale file. |
| Regenerating `swagger.json` also synced four `swagger/tag_groups/*.json` that were committed stale against it | Pre-existing drift: `build_tag_groups` derives from `swagger.json`, which already carried newer audit-log text the tag groups did not. Corrected as a side effect. |

## Out of scope, by instruction

No `contact_created` / `contact_updated` automation trigger, no contact-label automation condition, no
"run this automation over every matching contact", and no background label-synchronization engine. Phase A
established these are not part of the current automation execution model. C1–C5 are not started.

**Zero migrations.** Nothing in this phase needed a schema change.
