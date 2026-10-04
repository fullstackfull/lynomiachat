# Contacts phase C2 — bulk label actions

Almost all of this already existed. What follows is what was there, what was missing, and what was deliberately
left as it is.

---

## What was already there

| | |
|---|---|
| Endpoint | `POST /bulk_actions` (`config/routes.rb:58`), one request for any number of contacts |
| Dispatch | `bulk_actions_controller.rb` routes `type: 'Contact'` to `Contacts::BulkActionJob.perform_later` — **enqueued**, never N requests and never synchronous |
| Payload | `params.permit(:type, :action_name, ids: [], labels: [add: [], remove: []])` — both directions already permitted |
| Add | `Contacts::BulkAssignLabelsService` → `contact.add_labels`, **additive** |
| Remove | `Contacts::BulkRemoveLabelsService` → `label_list - labels`, **subtractive only**, no replacement semantics anywhere |
| Delete | `Contacts::BulkDeleteService`, authorized by `ContactPolicy#destroy?` |
| Scoping | `@account.contacts.where(id: @contact_ids)` in each service, plus the controller's account scope |
| Batching | `find_each` in both label services, so a large id list is read in batches |
| UI | `ContactsBulkActionBar.vue`, already using `BulkSelectBar`, the shared `BulkLabelActions` menu in both directions, and logical RTL utilities (`ms-auto`, `ltr:!pr-3 rtl:!pl-3`) |
| Wiring | `ContactsIndex.vue` already calls the endpoint once per action and clears the selection |

So C2 is not a feature to build. The brief's own instruction applies: *if Add Label already exists, do not
rewrite it.*

---

## What was missing, and is now fixed

**A payload with both directions applied only one of them.** `Contacts::BulkActionService#perform` was a chain of
`return`s, so `{ labels: { add: ['vip'], remove: ['prospect'] } }` added `vip` and silently kept `prospect`. It
now applies both, removing before adding — the order the conversation bulk job already uses, so a payload that
moves a contact from one label to another lands on the added one.

**A bulk label write was the one contact write with no authorization.** `check_authorization_for_contact_action`
checked `ContactPolicy#destroy?` for a deletion and nothing at all otherwise, so a label write never reached the
policy — including the overlay `ContactPolicy.prepend_mod_with` installs, which is where Enterprise adds the
`contact_manage` custom-role permission. It now authorizes `update?`.

**It accepted any string as a label.** `add_labels` creates a tag for whatever it is given, and a tag outside the
account's catalogue is invisible to the contacts sidebar, dropped by the CSV exporter (`contacts_export_job.rb`)
and ignored by campaign audiences (`campaign.rb`). The create path (phase B) and the CSV importer both refuse
one; this did not. Additions are now checked against `Current.account.labels` at the request boundary, reusing
the same `ContactLabelParams` check, returning the same structured 422 with `error_types: { labels: ['not_in_account'] }`.

Removals are deliberately **not** checked. A title the catalogue no longer holds is exactly what somebody needs
to remove — refusing it would trap an off-catalogue tag applied before the rule existed.

---

## All of the current filter's results

Not implemented. Documented, as the brief allows.

Selection is client-side and page-scoped: `ContactsIndex.vue` holds `selectedContactIds`, "Select all (N)" names
the loaded page (`RESULTS_PER_PAGE = 15`), and the selection accumulates as the user pages because
`onPageChange` passes `clearSelection: false`. There is no "select all 900 contacts matching this filter".

The server side for it does exist — `Custom::Contacts::FilterService#relation` resolves a filter to a contacts
relation without counting it, and two shipped operations already take a filter payload instead of an id list
(`POST /contacts/export` → `Account::ContactsExportJob`, and a campaign's audience). So a filter-targeted bulk
action would be an extension of the existing endpoint rather than a new one.

It is not done here because it is a bigger change than C2's remit: the endpoint would have to accept a filter
payload and re-resolve it inside the job, which means deciding what happens when the filter's results change
between the request and the job, how a per-record permission filter applies to records the user never saw, and
what an unbounded label write does to the taggings table. Faking it client-side by paging through results and
sending ids would duplicate `Contacts::FilterService` in the browser, which the brief forbids.

What is verified instead: the existing selection works on the ordinary contacts list, on a label page, in a
search view and in a segment, because selection is independent of how the list was fetched — it holds ids.

---

## Known limitations

| | |
|---|---|
| The list is refetched immediately after an enqueued job returns | `BulkActionsAPI.create` returns `head :ok` once the job is *queued*, and `ContactsIndex` refetches at once, so with Sidekiq the refetch can race the work and show labels as they were. The websocket corrects each row's attributes afterwards (`contact.updated` → `contacts/updateContact`), but not its membership of a filtered list — the mirror of phase B's `EDIT_CONTACT` note. Making this exact needs the client to learn when the job finished, which the endpoint does not tell it. |
| `Limits::BULK_ACTIONS_LIMIT = 100` is not applied here | Deliberate. Both label services use `find_each`, so a large id list is already batched, and the selection legitimately accumulates past 100 as a user pages. Applying the cap would remove capability rather than protect anything; the practical bound is the request body size. |
| The Remove-labels menu offers every account label, not only the ones the selection carries | A narrowing, not a correctness problem. The data for it exists (`contactLabels` store, `GET /contacts/:id/labels`), but computing the union across a selection means a request per contact today. |
| Bulk contact actions are not audited | `Contact` is not in the audited model set at all (`enterprise/app/models/enterprise/audit/*`), so this is a property of contacts generally rather than of bulk actions. |
| No partial-failure report | The job's return value is discarded and the services report `{ success: true, updated_contact_ids: [...] }` to nobody. A contact that fails to save is skipped silently. Reporting it would need somewhere to put the outcome — which is what `DataImportError` does for imports, and would be the model to follow. |

---

## Verification

| Gate | Result |
|---|---|
| `spec/services/contacts` (bulk action, assign, remove, delete, filter, sync) | **included in 86 examples, 0 failures** |
| `spec/controllers/api/v1/accounts/bulk_actions_controller_spec.rb` | **86 examples, 0 failures** with 6 new |
| `ContactsBulkActionBar.spec.js` | **8 tests** — the first frontend coverage this bar has had |

New coverage: both directions from one payload, in the right order; an off-catalogue label refused with nothing
enqueued; another account's label refused; an off-catalogue label still removable; another account's contact
untouched by an id that names it; the bar's selected count and page-scoped select-all; both label menus disabled
with an empty selection; and delete offered only to a user the policy admits.

---

## Out of scope, by instruction

No second contacts bulk API, no second toolbar, no client-side filtering, no N-request implementation, and no
global selection that the server cannot honour.
