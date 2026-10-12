# P10.2 — Unified customer identity

What this document is for: the record of why Lynomia added one table, what it does and does not do, and how the
inbound path, the merge and the API agree about who owns a phone number or an email address.

The short version. A Contact can hold exactly one phone number and one email address. That is not a convention,
it is three unique indexes. So a customer who reaches the brand from a second number is a second Contact, and
the merge an agent performs to join them **destroys** the second number — after which the next message carrying
it creates the duplicate again. P10 records the values `contacts` has no column for, in one narrow table, and
consults them on the one path that was about to create a duplicate. Nothing is guessed, nothing is merged
automatically, and no second contact system exists.

---

## 1. The constraint that forces the design

`contacts` (db/schema.rb) carries three FULL unique indexes per account:

| index | columns |
| --- | --- |
| `uniq_email_per_account_contact` | `(email, account_id)` UNIQUE |
| `uniq_phone_number_per_account_contact` | `(phone_number, account_id)` UNIQUE |
| `uniq_identifier_per_account_contact` | `(identifier, account_id)` UNIQUE |

None is partial, and `Contact#prepare_contact_attributes` (`app/models/contact.rb:229`, a `before_validation`)
turns a blank into NULL in each of the three columns and lowercases the email:

```ruby
self.email = email.present? ? email.downcase : nil
self.phone_number = nil if phone_number.blank?
self.identifier = nil if identifier.blank?
```

PostgreSQL treats NULLs as distinct, so any number of contacts may have no phone number while the *second*
contact holding a given number is refused by the database. The uniqueness is therefore real, not defeated by
empty strings — which is exactly what makes a stored primary field a deterministic identity, and also exactly
what makes a second one impossible.

**One Contact = one phone + one email + one identifier.** This is the P10 analogue of P9's
`conversations.inbox_id NOT NULL`: the schema fact the phase has to design around rather than argue with.

## 2. The measured defect

Provider identities already work. `contact_inboxes` is UNIQUE on `(inbox_id, source_id)` with a plain index on
`contact_id`, so one Contact already holds many provider identities, one per inbox — a WhatsApp `source_id`, an
email address, a widget token and a Facebook PSID can all hang off the same customer, and the cross-channel
conversation list already works once the contacts are one. The gap is not provider identities. It is
**multi-valued phone and email**, and the way a merge handles them.

`ContactMergeAction#merge_and_remove_mergee_contact` (`app/actions/contact_merge_action.rb:54`):

```ruby
mergable_attribute_keys = %w[identifier name email phone_number additional_attributes custom_attributes]
base_contact_attributes = base_contact.attributes.slice(*mergable_attribute_keys).compact_blank
mergee_contact_attributes = mergee_contact.attributes.slice(*mergable_attribute_keys).compact_blank
merged_attributes = mergee_contact_attributes.deep_merge(base_contact_attributes)
```

The base's value wins and the mergee's is gone with its row. Run against a real account before P10.2
(`/tmp/.../prove_merge_loses_second_phone.rb`, three inboxes, two contacts for one human):

```
after merge: phone="+96550000001" email="dana@example.com"
second phone survives on contacts? false
second email survives on contacts? false
contact_inboxes now on the survivor: ["+96550000001", "+96560000002"]
inbound from the merged-away number resolved to contact 9517 (survivor is 9515)
DUPLICATE RECREATED: true
contacts in the account now: 2
```

Note what *did* work: the mergee's `contact_inbox` rows moved, so a further message on **the same inbox**
resolves to the survivor. The failure is specific and is the omnichannel one — the same person, the same number,
reaching the brand through a **different channel** after the merge. `ContactInboxWithContactBuilder#find_contact`
looks at `contacts.phone_number`, the number is no longer there, and a new Contact is created. The agent merges
again, forever.

After P10.2, same script, feature enabled:

```
inbound from the merged-away number resolved to contact 9520 (survivor is 9520)
DUPLICATE RECREATED: false
contacts in the account now: 1
identities recorded on the survivor:
  phone +96560000002 source=merged
  email dana.alt@example.com source=merged
audit payload: {"moved"=>{}, "base_contact_id"=>9520, "mergee_contact_id"=>9521,
                "identities_absorbed"=>2, "discarded_duplicates"=>{}}
```

## 3. B3 — why a table, answered in order

**WHY THE EXISTING MODEL FAILS.** §1 and §2. A second phone number cannot be stored, and the merge that joins
two records throws one of them away rather than recording it.

**WHY A CUSTOM ATTRIBUTE IS NOT ENOUGH.** `additional_attributes` and `custom_attributes` are written by
`PATCH /contacts/:id`, by `Contacts::SyncAttributes` and by the CSV importer, so an identity claim stored there
is client-supplied data. Nothing can make it unique, so two contacts could both claim one number and the inbound
match becomes a guess — the one thing P10 must never do (B1). Resolving "who owns +965…" would also mean a jsonb
containment scan on the hot inbound path instead of an index probe. And there is nowhere to record *who* linked
it and *how*, which B1's confidence classes require.

**WHY CONTACTINBOX IS NOT ENOUGH.** `ContactInbox` validates `inbox_id` presence (`app/models/contact_inbox.rb:26`)
and its `source_id` is a provider-scoped string, unique only per inbox. "This person also owns this number" is an
account-level fact about a human, not a membership of a channel. Recording it as one would mean inventing an
inbox to hang it on, would inherit the pubsub-token and conversation-routing side effects of
`ContactInboxBuilder`, and — decisively — could not stop two contacts in the account claiming the same number,
because the only uniqueness available is per inbox.

**WHY WIDENING `contacts` IS NOT ENOUGH.** `phone_number_2`, `email_2` bounds the product at two, needs a
further unique index per column, and still records no provenance. The third number arrives anyway.

**WHY A LINK TABLE IS REQUIRED.** The account-scoped UNIQUE is the point: one normalized identity value belongs
to at most one contact in an account. That is the same guarantee `contacts` gives for its primary fields,
extended to the values `contacts` has no column for, and it is what makes the inbound match deterministic
rather than probabilistic.

**QUERY SHAPES.** Three, and only three:

| caller | query |
| --- | --- |
| inbound fallback (`Custom::ContactInboxWithContactBuilder`) | `account_id = ? AND identity_type = ? AND value IN (?)` |
| the linker's cross-check | `account_id = ? AND identity_type = ? AND value = ?` |
| the contact's panel / a merge's move | `contact_id = ?` |

The first two are answered by `index_contact_identities_on_account_type_value` as a leading-column equality
match; the third by `index_contact_identities_on_contact_id`. No other shape exists, so no other index does.

**UNIQUENESS RULE.** `UNIQUE (account_id, identity_type, value)`. Per account, because identity is per account
everywhere else in the product and because the inbound path knows the account but not the contact — that is the
whole reason `account_id` is on the table rather than reached through `contact_id`.

**MERGE BEHAVIOR.** §5.

**ROLLBACK.** `drop_table`, and nothing else. The table is additive: nothing in `contacts`, `contact_inboxes`,
`conversations` or `messages` references it, and every path that reads it falls back to today's behaviour when
it holds no rows. Verified by a full `db:rollback` / `db:migrate` round trip producing a byte-identical
`db/schema.rb`.

## 4. The table, and what it deliberately is not

`custom/db/migrate/20261009120000_create_contact_identities.rb`:

| column | note |
| --- | --- |
| `account_id` | NOT NULL, FK cascade. Part of the uniqueness and of every lookup. |
| `contact_id` | NOT NULL, FK cascade. An identity has no meaning without its contact. |
| `identity_type` | `{ phone: 0, email: 1 }` |
| `value` | normalized; phone to E.164, email lower case |
| `source` | `{ agent_linked: 0, merged: 1 }` |
| `linked_by_id` | the user who linked it, FK nullify |
| `created_at` / `updated_at` | |

**It does not mirror `contacts`.** `contacts.phone_number` and `contacts.email` remain the primary fields and
keep their own unique indexes; this table holds only the *additional* values. Three consequences, all
deliberate:

1. **No backfill.** An empty table means the product behaves exactly as it does today. Nothing has to be
   migrated at deploy time, which matters because the brief forbids a production backfill and because a
   backfill across a large `contacts` table is the riskiest part of any identity change.
2. **One place to read, two places to check.** The inbound match reads `contacts` first (unchanged) and this
   table only as a fallback. The *uniqueness* question has to be asked of both tables, which §4.1 covers.
3. **`source` has no fuzzy value.** An identity exists because an agent said so or because a merge absorbed a
   value that was already a verified primary field. There is no `probable_match`, no score, no confidence
   percentage, because there is no fuzzy matching to record. B1's three classes map onto the product as:
   VERIFIED/DETERMINISTIC = a primary field or a provider `source_id`; EXPLICITLY LINKED = a row in this table;
   UNRESOLVED = everything else, which stays two contacts until a human decides.

### 4.1 The cross-table uniqueness, from both sides

No index can span `contacts` and `contact_identities`. So the rule — *one value, one contact* — is enforced at
both writers:

- **`Contacts::IdentityLinker`** (`custom/app/services/contacts/identity_linker.rb`) is the only way a row is
  created. Before it writes, it asks both tables who owns the value: an existing row, and
  `contacts.phone_number` / `contacts.email`. A value owned by another contact is reported as a `:conflict` and
  the agent decides; a value the contact already owns, as a row *or* as its own primary field, is
  `:already_linked` and nothing happens.
- **`Contact`** gains `primary_identities_not_linked_elsewhere`
  (`custom/app/models/custom/concerns/contact.rb`), conditional on `phone_number_changed? || email_changed?`.
  An agent cannot give a contact a value another contact has linked. The condition is what keeps it off the hot
  path: a conversation, a message or a `last_activity_at` touch runs no extra query, and a spec asserts that.

Because both sides check both tables, the state "value V is contact X's primary field *and* contact Y's linked
identity" cannot be produced through any of the product's own entry points. One consequence worth stating
plainly: the conflict branch inside the merge's absorption step is therefore unreachable through the product,
and it exists only because the linker reports a status instead of raising — there is no extra guard code for it,
and no spec asserts a state the product cannot reach.

**On the advisory lock.** An earlier sketch of this phase had the linker take a transaction-scoped advisory
lock. It was dropped, deliberately. Two agents linking the same value concurrently both pass the pre-check and
one `INSERT` loses to the unique index, which the linker re-reads and reports as the conflict it is — the lock
changes nothing. The cross-domain race (an agent sets X's primary number while another links the same number to
Y) is not closed by a lock the `Contact` save does not also take, and taking one inside a validation trades a
near-impossible interleaving for a deadlock surface. Residual exposure if it ever happened: one redundant row,
with resolution still deterministic because `find_contact` checks primary fields first. Recorded here rather
than papered over.

## 5. The merge

`Custom::ContactMergeAction` wraps `merge_and_remove_mergee_contact`, the last step before the destroy:

1. **Before `super`** — `Contacts::MergeRelocation` moves everything pointing at the mergee that the OSS action
   does not, now eight relations including `contact_identities` (docs/p10/04-contact-merge-linking.md). The
   mergee's own linked identities move with it; they cannot collide, because the account-scoped unique index
   already rules out two contacts in one account holding the same value.
2. **Also before `super`** — the four primary values (`base.phone_number`, `mergee.phone_number`, `base.email`,
   `mergee.email`) are read while both contacts still exist.
3. **`super`** — the OSS action destroys the mergee and copies the merged attributes onto the base.
4. **After `super`** — for each type, the value the survivor *kept* is its primary field; the others are
   recorded through `Contacts::IdentityLinker` with `source: :merged`. Any row that now duplicates the
   survivor's own primary field is deleted, so the invariant "this table holds only additional values" survives
   the merge.

Recording has to happen *after* the destroy: until then the mergee's number is another contact's primary field
and the linker would rightly call it a conflict.

The audit row (Settings → Audit Logs, via `Custom::AuditLog`) gains `identities_absorbed` — a count. Ids, counts
and booleans only; no phone number and no email address is ever written to it, and a spec asserts the payload
does not contain either contact's values.

## 6. The API and its boundary

`config/routes.rb`, inside the existing `contacts` resource:

```
GET    /api/v1/accounts/:account_id/contacts/:contact_id/identities
POST   /api/v1/accounts/:account_id/contacts/:contact_id/identities
DELETE /api/v1/accounts/:account_id/contacts/:contact_id/identities/:id
```

`Api::V1::Accounts::Contacts::IdentitiesController` inherits the existing
`Api::V1::Accounts::Contacts::BaseController`, so the contact is always found through
`Current.account.contacts` and a foreign contact is 404 before any policy runs.

**Reading follows the contact.** `authorize @contact, :show?` — the same rule as the contact's notes,
attachments and P8 activity timeline. An agent who may open a contact may see how that customer can be reached.

**Writing follows the merge.** `authorize ::Contact, :manage_identities?`, which is `Custom::ContactPolicy#merge?`:
administrator, or an agent whose custom role grants `contact_manage`. Linking a number decides where the next
message carrying it is delivered and it is how two customer records become one, so it carries the destructive
end's boundary, not the read one's. PART F's rule holds unchanged — this is contact access, and it grants no
conversation access: the conversation list stays behind `Conversations::PermissionFilterService`.

Responses: `422` with `{ error: ... }` for a conflict (naming the contact that owns the value), for an unknown
`identity_type`, and for a value that cannot be normalized. `404` when the account does not have the feature,
the same stance the support module takes — the account has no linked-identity feature, so the endpoint does not
exist for it.

## 7. Normalization (PART M)

| type | rule | where |
| --- | --- | --- |
| phone | `Contacts::Phone.e164`, the app's one E.164 path (telephone_number gem). No default region: a local number with no explicit country returns nil. The contact's own `additional_attributes['country_code']` is the region when it has one — the same explicit source the CSV importer uses. | `app/services/contacts/phone.rb` |
| email | `strip.downcase`, then `Devise.email_regexp`. Lower case because the stored value must match what `Contact#prepare_contact_attributes` produces. | the linker |
| name | never an identity key, anywhere | — |

No second E.164 parser was written. `Whatsapp::PhoneNormalizers::*` stay untouched: they reconcile
provider-specific quirks of an already-international WhatsApp id and feed `phone_number_candidates`, which the
inbound fallback consumes so a linked number matches through those quirks exactly as a primary one does.

**One subtlety, stated because it is a real decision.** `Contacts::Phone.e164` asks whether a number is *real*;
`contacts.phone_number` only asks whether it is *well formed* (`STRUCTURAL_FORMAT = /\A\+[1-9]\d{1,14}\z/`), and
the CSV importer stores numbers that pass the second test and fail the first. So the linker keeps a number that
carries its own country even when `e164` will not vouch for it. A stricter rule would have quietly refused to
carry across a number a contact already has — which is precisely what a merge asks it to do. One rule for what
may be stored (structural, as everywhere else), the stricter one for what may be typed.

## 8. The inbound path

`Custom::ContactInboxWithContactBuilder` prepends one fallback:

```ruby
def find_contact
  super || find_contact_by_linked_identity
end
```

The OSS order — identifier, email, phone and its candidates, then an Instagram `source_id` already seen on a
Facebook page — is untouched and still answers every message it can. The fallback runs **only** where that order
returned nothing, which is the branch that was about to create a new contact. So the cost is one indexed
equality lookup on the rare path and nothing at all on the common one.

Email is tried before phone, matching the OSS precedence, and the email is downcased for the same reason
`Contact.from_email` downcases. That last point is not cosmetic: without it a provider reporting a mixed-case
address would miss the link and then try to create a contact holding a value the account has already linked,
which the `Contact` validation refuses — losing the message. There is a spec for it.

Reading is **not** gated on the account feature, on purpose. A link an account made while the feature was on
must keep routing its messages if the feature is later turned off; silently delivering a customer's replies
somewhere else is worse than either state. Writing is gated, in the linker, which covers both writers.

## 9. The feature flag (PART O)

One new account feature, `lynomia_unified_identity` (`config/features.yml`, `enabled: false`,
`column: feature_flags_ext_1`). Its meaning is exact and was measured both ways:

```
feature=false identities=0 resolved_to_survivor=false contacts_in_account=2
feature=true  identities=1 resolved_to_survivor=true  contacts_in_account=1
```

Off: no `contact_identities` row is ever created, and the merge and the inbound path behave exactly as they do
in production today. On: the merge records what it absorbs and the API accepts links.

## 10. What P10.2 did not build

- No second contact table, address book, customer master or identity graph. One narrow link table beside
  `contacts`, which stays the customer record.
- No probabilistic matching. Nothing compares names, avatars, usernames, email local-parts or phone suffixes,
  and nothing merges automatically. The widget's existing `ContactIdentifyAction` merge is unchanged.
- No AI anywhere near identity.
- No new inbox engine, conversation engine, messaging runtime, queue or event bus.
- No change to WhatsApp's provider semantics, webhook handling or status model.
- No second channel health dashboard; P10.1 extends P9's Operations Center instead.
