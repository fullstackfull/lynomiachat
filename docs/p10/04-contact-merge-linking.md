# P10.3 — Contact merge and linking

What this document is for: what a contact merge used to destroy, what it does now, who may run one, and what is
recorded. The identity side of the same work — the table, the linker and the inbound match — is
docs/p10/03-unified-customer-identity.md.

---

## 1. What the OSS merge does

`ContactMergeAction#perform` (`app/actions/contact_merge_action.rb`) is one transaction that:

1. validates both contacts belong to the account,
2. moves `conversations`, `messages` (as sender), `contact_inboxes` and `notes` to the base,
3. calls `merge_calls`, a hook whose comment points at `enterprise/app/actions/enterprise/contact_merge_action.rb`
   — a directory that does not exist in this fork, so it is a permanent no-op,
4. destroys the mergee and *then* copies the merged attributes onto the base, which is the right order: the base
   can take over a phone number or an email only once the row holding it is gone, or `contacts`' unique indexes
   would refuse.

All of that is sound and none of it changed.

## 2. What the database did with everything else

`destroy!` on the mergee settled the rest, silently, and the settlement is not what anyone would choose:

| relation | what the schema says | consequence |
| --- | --- | --- |
| `campaign_recipients` | `ON DELETE CASCADE` | the mergee's entire campaign send history is deleted |
| `commerce_customer_links` | `ON DELETE CASCADE` | the store-customer link is deleted |
| `contact_identities` | `ON DELETE CASCADE` | the linked numbers and addresses are deleted |
| `support_tickets` | `ON DELETE SET NULL` | a support case loses its customer |
| `commerce_carts` | `ON DELETE SET NULL` | cart attribution lost |
| `commerce_action_runs` | `ON DELETE SET NULL` | action attribution lost |
| `csat_survey_responses` | `dependent: :destroy_async` on `Contact`, never moved | the customer's CSAT answers are deleted |
| `taggings` | destroyed by `acts_as_taggable_on` | labels lost |

P8's campaign analytics read `campaign_recipients`, so deleting those rows rewrites history that has already
been reported. P9's support cases were left pointing at no customer. None of this was visible in the UI, and
none of it was recorded anywhere.

## 3. What happens now

`Contacts::MergeRelocation` (`custom/app/services/contacts/merge_relocation.rb`) moves all eight, inside the
merge's existing transaction, before the destroy. Two of them cannot simply be moved:

- `campaign_recipients` is UNIQUE `(campaign_id, contact_id)`
- `commerce_customer_links` is UNIQUE `(commerce_store_id, contact_id)`

When both contacts already have a row for the same campaign or the same store, moving the mergee's would violate
the index, and there is no way to keep both — after the merge they describe one human. So the base's row is kept,
the mergee's duplicate is **discarded deliberately**, and the count is returned and recorded. A discarded row is
a fact somebody may need later; a hidden one is not.

Labels move through the gem's own `add_labels` rather than the `taggings` table, so the tag counters stay right.

`contact_identities` is in the simple set: the account-scoped unique index already rules out two contacts in one
account holding the same value, so a move cannot collide. What a move *can* produce is a row duplicating the
survivor's own primary field once the base has taken the mergee's attributes; `Custom::ContactMergeAction`
clears those afterwards.

`calls` is deliberately absent — this fork has no `Call` model, no foreign key on that table and nothing that
writes it.

## 4. The identities a merge absorbs

The merge is the moment the second number and the second address are destroyed, and the measured consequence is
that the next inbound message carrying one of them recreates the duplicate
(docs/p10/03-unified-customer-identity.md §2). So `Custom::ContactMergeAction` now records them, after the
destroy, through `Contacts::IdentityLinker` with `source: :merged`. Gated on the `lynomia_unified_identity`
account feature: with the feature off, a merge behaves exactly as it does in production today.

## 5. Who may merge

The OSS endpoint `POST /api/v1/accounts/:account_id/actions/contact_merge` performed **no `authorize` call at
all**, and `ContactPolicy` had no `merge?`. Any account member — including an inbox-restricted agent — could
merge any two contacts in the account, destroying one of them, while `ContactPolicy#destroy?` has always been
administrator-only.

`Custom::ContactPolicy#merge?` is now `administrator || permissions.include?('contact_manage')`: the rule the
product already uses for the destructive end of contact management, widened by the custom-role permission that
exists for exactly this. `Custom::Api::V1::Accounts::Actions::ContactMergesController` prepends the `authorize`
call; the OSS controller gained one line, its `prepend_mod_with` hook.

This does **not** gate the web widget's automatic identify-and-merge. `ContactIdentifyAction` has no acting
agent to authorize, and it is a different question with its own safety rules (§7).

## 6. The record

Every merge writes one `Custom::AuditLog` row — Lynomia's existing audit class, the same writer
`Commerce::AuditTrail` and `Flows::Audit` use — with `comment: 'contact.merged'`, `auditable:` the surviving
contact and `associated:` the account. That is what puts it on **Settings → Audit Logs** with no new reader
(`custom/app/controllers/api/v1/accounts/audit_logs_controller.rb`, gated by the `audit_logs` account feature
and the administrator permission).

The payload is ids, counts and booleans only:

```json
{ "base_contact_id": 9520, "mergee_contact_id": 9521,
  "moved": { "support_tickets": 1 }, "discarded_duplicates": { "campaign_recipients": 1 },
  "identities_absorbed": 2 }
```

No email address, no phone number, no contact name — a spec asserts the serialized payload contains neither
contact's values. A relation with nothing to move says nothing rather than saying zero, because the payload is
read by a human asking what happened and eight zeroes is noise.

Writing the record can never roll the merge back: `record_merge_audit` rescues and logs, because the merge is
the thing the customer's data depends on.

## 7. Irreversibility, and what the UI now says

The merge **cannot be undone**. The mergee row is destroyed, and nothing stores a pre-merge snapshot. B7 is
satisfby by saying so rather than by pretending an undo exists:

- `MergeContactSummary.vue` (the modal) and `ContactMerge.vue` (the sidebar) both render two new strings:
  *"This cannot be undone. The merge is recorded in the audit log."* and *"Conversations, messages, notes,
  labels, campaign history, support cases and commerce links move to the contact that is kept."*
- Both exist in `en` and `ar` under `MERGE_CONTACTS.SUMMARY` and `CONTACTS_LAYOUT.SIDEBAR.MERGE`, with key
  parity asserted.

**Direction.** The two merge UIs use the word "primary" to mean opposite things, which is worth knowing when
reading them. Both were traced to the payload (`merge(parentId, childId)` → `base_contact_id: parentId,
mergee_contact_id: childId`) and **both are internally correct** — there is no direction bug. The automatic
widget path is also correct in a way its parameter name hides: `ContactIdentifyAction#process_contact_merge`
passes the *found* contact as `base_contact`, so the existing customer survives and the widget's current contact
is the mergee.

## 8. What the widget's automatic merge already refuses

`ContactIdentifyAction` is the one path that merges without an agent, and it is already conservative in a way
P10 keeps rather than replaces:

- `merge_contacts?` refuses to merge two contacts that have *different* identifiers.
- `mergable_phone_contact?` refuses to let a phone match overwrite an email match.

That is the in-repo precedent P10's linker follows: on a collision, refuse and let a human decide — never guess,
never pick a winner by similarity.
