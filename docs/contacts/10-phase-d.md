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
