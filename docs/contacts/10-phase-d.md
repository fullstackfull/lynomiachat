# Phase D — contacts final hardening

Four items, each one a defect the earlier phases left behind rather than a new feature. This file records what
was actually wrong, the evidence, and what changed.

---

## D1 — the recipe gallery had no Arabic strings

### What was wrong

Phase C shipped `app/javascript/dashboard/recipes/` with twenty-two catalogue entries and
`i18n/locale/en/recipes.json`, and nothing else. `ar/index.js` had no `recipes` import, so for an Arabic agent
every name, description, input label and requirement reason in the gallery rendered as its raw key —
`RECIPES.AUDIENCE.PRESETS.HIGH_VALUE.NAME` and so on down the list.

This is the one place where CLAUDE.md's "only update `en.yml` and `en.json`" does not apply: that rule is about
not hand-editing what Crowdin owns. Arabic is a first-class product language here, and a key with no Arabic
value is not a missing translation, it is a broken screen.

### What changed

- `i18n/locale/ar/recipes.json`, 99 strings, the same tree as `en`.
- `ar/index.js` imports and spreads it between `flowBuilder` and `chatlist`, where `en/index.js` has it.
- `recipes/specs/catalogue.spec.js` now runs its three requirement tests over **both** locales
  (`it.each(LOCALES)`), so a catalogue entry added in English only fails here instead of in the UI. Two more
  tests hold the file honest: the two locales must stay structurally identical, and every `{placeholder}` in an
  English string must survive into the Arabic one.

---

## D2 — the page refetched before the job had run

### What was wrong

Three separate defects on the same path. All three are live in the product today.

**1. The refetch raced the job.** `BulkActionsController#create` answers `head :ok` the moment
`Contacts::BulkActionJob` is *enqueued*. `ContactsIndex.vue` then refetched immediately. In development the
inline adapter runs the job before the response, so the list came back correct and the bug was invisible; with
Sidekiq the refetch reads the list before any label is written, and the rows come back exactly as they were. The
user sees their own action apparently do nothing until they reload.

The per-contact `contact.updated` pushes cannot stand in for a completion signal. They correct a row's
attributes, but they say nothing about whether that row still belongs in a filtered or label-scoped list — which
is precisely what changes when you add or remove a label.

**2. The selection was cleared before the server had acted.** `ContactsIndex.vue:347`, `:369` and `:391` each
called `clearSelection()` on the line after the request resolved — i.e. while the work was still queued. If the
job then failed, the user had an error toast and no selection to retry with.

**3. The job did not say who performed the write.** Every contact written by the bulk services dispatches
`contact.updated`, and `ActionCableListener#broadcast` reads `Current.user` to name the performer.
`Contacts::BulkActionJob` never set it — unlike `BulkActionsJob`, the conversation equivalent, which does — so a
bulk label write arrived at every other agent's tab attributed to nobody.

### Two more bugs found while proving it

Both in `store/modules/contacts/mutations.js`, both reachable from any websocket push, neither specific to bulk
actions.

`EDIT_CONTACT` **replaced** the stored record (preserving only `attachments`). Its payload is
`Contact#push_event_data`, which carries no `labels`, no `last_activity_at`, no `availability_status` and no
`created_at`. So any push about a contact deleted all four from a row the list had already loaded — and
`last_activity_at` is the column the default sort and the list's own timestamp column read. It now merges.

`DELETE_CONTACT` did `sortOrder.splice(findIndex(id), 1)`. `findIndex` answers `-1` for a contact the current
page never rendered, and `splice(-1, 1)` removes the **last** element — so a `contact.deleted` push for any
contact in the account dropped an unrelated row from whatever page you were looking at. It now checks the index.

### What changed

Nothing new was built. The completion signal uses the broadcast path `Account::BrandingEnrichmentJob` already
uses for exactly this purpose — `ActionCableBroadcastJob` straight to the initiating user's own `pubsub_token`,
no dispatcher event, no listener, no new channel:

- `Contacts::BulkActionJob` sets `Current.user`, runs the service, then enqueues
  `ActionCableBroadcastJob.perform_later([user.pubsub_token], 'contact.bulk_action_completed', { account_id: })`,
  with `Current.reset` in an `ensure`. A failed bulk action announces nothing, so the page falls through to its
  timeout rather than refetching on a lie.
- `actionCable.js` registers the event and puts it on the mitt bus as
  `BUS_EVENTS.CONTACT_BULK_ACTION_COMPLETED`. It dispatches nothing to the store: the only thing that cares is
  the page that is waiting.
- `helper/bulkActionCompletion.js` is the wait — one promise that races the bus event against a 15s timeout and
  unsubscribes on whichever path settles it. It resolves on timeout rather than rejecting: a late refetch is
  still a correct refetch, and the alternative is a bar that spins forever when the websocket is down.
- `ContactsIndex.vue`'s three near-identical handlers collapse onto one `runBulkAction`, which subscribes
  **before** sending the request (a small selection can finish before the response lands), then awaits
  completion, alerts, clears the selection and refetches, in that order.

### Scope held

- No new job, queue, channel, event bus or store module. One new event name on an existing channel.
- No polling. The page waits on a push, with a timeout as the failure path, not as the mechanism.
- The broadcast goes to one `pubsub_token`, so it reaches the agent who pressed the button and no other tab.
- No migration.

### Tests

| | |
|---|---|
| `spec/jobs/contacts/bulk_action_job_spec.rb` | the service is still called with account and user; `Current.user` is the initiator *during* the write and nil after; the completion broadcast carries the initiator's own `pubsub_token`; a failed bulk action announces nothing |
| `helper/specs/bulkActionCompletion.spec.js` | resolves on the announcement; resolves on its own after the timeout; unsubscribes on both paths; leaves no timer behind |
| `helper/specs/actionCable.spec.js` | the event is registered, and reaches the bus rather than the store |
| `store/modules/specs/contacts/mutations.spec.js` | `EDIT_CONTACT` keeps the four fields the push omits, and stores a contact the list has not loaded; `DELETE_CONTACT` removes the right row, and leaves the order alone for a contact the page never showed |

### A note on the test database

The contacts and bulk-action specs failed en masse mid-phase with
`ActiveRecord::RecordInvalid: Validation failed: User has already been taken`, from
`create(:inbox_member, ...)` in `bulk_actions_controller_spec.rb`'s `before` block. The cause is not in the
tree: that block iterates `Conversation.all`, which is not account-scoped, and the test database held three
orphaned conversations sharing one inbox from an earlier interrupted run. `rails db:test:prepare` and all 91
examples pass. Worth knowing before calling such a failure a regression.

---

## D3 — the same file was uploaded two, three, four times

### What was wrong

The preview and the import take the same payload, deliberately: whatever the preview classified is what the
import then performs. The cost was that the *bytes* were part of that payload both times. The dialog's own flow
is: choose a file, look at what it would do, go back, change the duplicate policy or the country, look again,
then import. Each of those steps was a fresh multipart upload of the whole CSV. At the 10MB ceiling that is
40MB on the wire to import 10MB, over a connection the user is waiting on.

The preview also read the upload directly and the import attached it directly, so the two never looked at the
same copy of the file — only at two copies that were expected to be identical.

### What changed

The first request carrying a file stores it, and hands back the id of what it stored. Nothing here is new
machinery: `ActiveStorage::Blob.create_and_upload!` is what `Api::V1::Accounts::UploadController` already does
with every attachment in the product, and a client sending a signed blob id back is what
`PortalsController#process_attached_logo` and `AttachmentConcern` already accept.

- `ContactImportFile` (split out of `ContactImportParams`, which now reads only the batch's choices) resolves
  where a request's bytes come from: a stored blob's signed id, an upload, or pasted text, in that order.
- The preview answers with `import_file_blob_id`. The dialog keeps it and sends it in place of the file from
  then on, including on the import. So the file crosses the wire once per file chosen, not once per look.
- The preview now reads the bytes back out of the blob rather than out of the upload. Storing a file is what
  moves its read position, so reading the stored copy is both the fix for that and the only arrangement in which
  the preview and the import cannot be describing different bytes.
- The import attaches the blob it was given. Not a second copy of it — the same row, which the preview read.

### Scope held, and what is deliberately not here

- **No migration.** The account stamp lives in `metadata`, a column ActiveStorage already has.
- **No unconfirmed `DataImport` rows.** The first design for this was a two-phase create/confirm on
  `DataImport`: the preview creates the record, the import confirms it. That requires suppressing
  `after_create_commit :process_data_import` until confirmation, keeping unconfirmed rows out of the imports
  list, a run-once guard on `DataImportJob` so a double confirm cannot import twice, and reaping the rows a
  user leaves behind by previewing repeatedly. A bare blob needs none of it: an import record is still created
  exactly once, by the import, exactly as before.
- **No new endpoint.** The existing upload endpoint would also have worked, but it is not admin-only and it
  stamps nothing, so a CSV would have been accepted from an agent and redeemable in any account.

### Why a signed id is safe enough here, and what makes it so

A signed id is a bearer token for one blob, and the upload endpoint mints them for every attachment in the
product. On its own, then, "this id names a blob" says nothing about whether it names a CSV that this account's
import dialog stored. Two things make it say that:

- Every blob stored by this path carries `metadata['contact_import_account_id']`, and redeeming one requires
  that stamp to equal the current account. A signed id for any other blob in the product — an avatar, a message
  attachment, another account's import — is refused with `not_an_import_file`, and so is an expired or forged
  one. The specs cover all four.
- The id expires an hour after it is issued, so one copied out of a response is not a key to that file for ever.

What this does not do is bind the id to a *user*. A member of two accounts could redeem, in one of them, an id
issued to them in the other. The file is their own either way, and binding to a user would need somewhere to
record which one — i.e. a column. Stated rather than guarded.

### Two things fixed in passing, both at the request boundary

- `import_file` sent as a text field reached `#read` on a `String` and answered **500**. It now answers 422
  with `not_a_csv`, like any other malformed parameter.
- The 10MB cap was only applied when the preview read the file, so `import` would accept a CSV of any size, and
  `DataImportJob` reads the whole file into memory. The cap now applies to whatever is about to be stored, which
  is both endpoints. Nothing is stored before the check.
- `DataImport#initiated_by` was never set by a contacts CSV import, although the imports list renders it
  (`_data_import.json.jbuilder:18`) and the integration importers set it. It is set now.

### What is still left behind

A blob whose preview is abandoned, or superseded by choosing a different file, is unattached and stays that way:
the client forgets the id, so the server never hears about it. Re-previewing the *same* file creates nothing new,
which is the case the flow actually produces, so this is one orphan per file chosen and never imported.
`ActiveStorage::Blob.unattached` is the sweep if that ever matters; nothing in the repo runs one today, and this
is not the first path to leave one.

### Tests

| | |
|---|---|
| `spec/controllers/api/v1/accounts/contacts_controller_spec.rb` | the preview answers with the id of what it stored, and the stored copy is byte-for-byte the upload; a second preview of the same file stores nothing new; the import attaches the very blob the preview read; `initiated_by` is recorded; and four refusals — a blob never stored for an import, another account's stored file, an id that is not signed at all, and an expired one — plus the size cap storing nothing and `import_file` sent as text |
| `api/specs/contacts.spec.js` | the id is sent in place of the file, and the file again once the id is gone |
| `ContactsForm/specs/ContactImportDialog.spec.js` | the import is asked for with the id; a second look sends it; it is forgotten when a different file is chosen, and when the server refuses the preview |

`ButtonStub` in that dialog spec re-emitted a click Vue had already passed through to its root element as a
native listener, so every `clickLabel` ran its handler twice. Harmless for the assertions that were there, but
it makes the order of a component's calls unreadable, which the new tests need. Removed.

---

## D4 — "select all" meant "select all fifteen"

### What was wrong

A bulk action could only ever reach the rows the browser was holding. "Select all" selected the current page —
fifteen contacts — and said so: `SELECT_ALL` is "Select all ({count})" with the *page's* count in it. An account
with four thousand contacts carrying a label had no way to act on them other than paging through two hundred and
sixty-seven pages, fifteen at a time.

The reason is real and does not go away by being ignored: the ids are what the endpoint takes, and the browser
does not have the ids. Only the server can enumerate a view.

### What changed

The bulk endpoint now accepts a description of the view instead of a list of ids, resolves it, and sends on what
it resolved.

- `Contacts::ViewScope` answers "which contacts is this view showing" from `{ q, active, payload, label }` —
  the same four parameters the list endpoints already take. Every branch is one of those endpoints' own scopes:
  `Contacts::FilterService` for a filter or a saved segment, `OnlineStatusTracker` for the online list, the
  search endpoint's own predicate for a search, `resolved_contacts` and `tagged_with` for the list itself.
- `ContactsController`'s `index`, `search` and `active` go through it too, so there is one definition rather
  than a copy that can drift. A bulk action over "all the results" that resolved to a different set than the
  list showed would be worse than no feature at all.
- `BulkActionsController` resolves `all_matching` to ids and passes them to the existing
  `Contacts::BulkActionJob`. The job, `Contacts::BulkActionService`, the three label/delete services and the
  policy are untouched: what the user was told would happen is exactly what the queue is given.
- `ContactsIndex.vue` builds the description branch for branch the same way `fetchContactsBasedOnContext`
  decides which list to fetch — the same conditions in the same order, reading the same state. The bar offers
  "Select all N in this view" only once every row on the page is already selected and the view has more, and it
  then reads "All N selected" rather than "15 selected".

### The rules this had to respect

- **An empty payload is never "everything".** The opt-in is `all_matching` being *present*, not `ids` being
  absent. A request that forgot its ids reaches no contacts at all, which a spec holds in place.
  `all_matching: {}` is the unfiltered list, because somebody asked for that in so many words — and it resolves
  to `resolved_contacts`, so a row with no identity is no more reachable than it is on the page.
- **An explicit bound.** `CONTACT_VIEW_LIMIT = 10_000`, the same number the pasted-numbers importer uses. Over
  it the request is refused with `too_many_contacts` and nothing is enqueued. It refuses rather than truncating:
  an action that silently did 10,000 of 40,000 contacts would be worse than one that did nothing, and the
  dialog shows the server's own reason.
- **No `Contacts::FilterService` in the browser.** The client sends the filter query it already sends to
  `/contacts/filter`; it resolves nothing.
- **No cross-account reach.** Every branch starts from `@current_account.contacts`, and a spec checks a search
  that matches a contact of the same name in another account.
- **Authorization unchanged.** `authorize(Contact, :update?)` / `:destroy?` and the label-catalogue check run
  before anything is resolved, so a whole-view delete from a non-admin is refused exactly as a fifteen-row one
  is.
- **No migration, no new endpoint, no new job, no new queue.**

### The adjacent bug this exposed, and fixed

`Account::ContactsExportJob` asked the same question and answered it itself:

```ruby
if @params[:payload].present? then filter
elsif @params[:label].present? then label
else the whole account
```

A search view and the online list carry neither a payload nor a label. So "Export" from a search for one person
exported **every contact in the account**, by email, silently. The export dialog was sending only `payload` and
`label`, and the controller was forwarding only those two.

The job now resolves its view with `Contacts::ViewScope`, the controller forwards `q` and `active` as well, and
the dialog sends the view it is actually showing. Two specs cover the two cases that were wrong.

The export is also handed plain hashes now rather than `ActionController::Parameters`, which is what a job
argument should be.

### Tests

| | |
|---|---|
| `spec/services/contacts/view_scope_spec.rb` | each of the four views; the account boundary; precedence when a description names more than one; and that `{ q: '', active: false, payload: [], label: '' }` — what a quiet view sends — names no view at all |
| `spec/controllers/api/v1/accounts/bulk_actions_controller_spec.rb` | a label view, a search view and a filter view each resolve to the right contacts; another account is never reached; an empty description is the unfiltered list; **a missing description reaches nothing**; over the bound it refuses and enqueues nothing; and an unknown label and a non-admin delete are still refused |
| `spec/jobs/account/contacts_export_job_spec.rb` | a search exports what it matched, and the online list exports who is online — neither exports the account |
| `ContactsBulkActionBar.spec.js` | offered only when the page is exhausted and the view has more; not offered when the page *is* the view; emits the request; and counts the view rather than the ids once taken |
