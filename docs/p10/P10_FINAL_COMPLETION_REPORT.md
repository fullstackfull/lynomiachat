# P10 FINAL COMPLETION REPORT

Omnichannel completion and unified customer identity. Branch
`claude/p10-omnichannel-unified-identity`, cut from P9 head `15efa6a7`
(`git merge-base --is-ancestor 15efa6a7 HEAD` succeeds). Production untouched, still on
`b03ea43df6abf18cb9c4e5d6a9271ba040b689f4`. Sections A–AI, in the span the brief asked for.

---

## A. Executive summary

A Contact in this product is exactly **one** phone number, one email address and one identifier. That is not a
convention — `contacts` carries three full unique indexes per account, and the model turns blanks into NULL so
the uniqueness is real. A customer who reaches the brand from a second number is therefore a second Contact,
and the merge an agent runs to join them **kept one value of each and destroyed the rest**.

P10 measured that, closed it, and found that the merge was destroying rather more than the number: the database
was silently deleting the mergee's campaign send history, its commerce store link, its CSAT answers and its
labels, and orphaning its support cases and carts — none of it visible in the UI, none of it recorded, and the
endpoint had no authorization check at all.

It also found that a broken channel could look fine in three different ways, that a TikTok conversation created
a brand-new contact every time, and that three credentials the code encrypts at rest were being sent to the
browser in plaintext.

Nine commits, 69 files, +6,253/−63. One new table, two migrations, four new services, fifteen new spec files.
The table was justified against every alternative before it was written; the one new index was measured, found
unused, and corrected.

## B. Verdict

**PASS WITH KNOWN LIMITATIONS.**

Pass, because the two defects P10 exists to close are closed and proven by measurement rather than assertion;
every new path is specced; the five gates are recorded in §AB; nothing was built that duplicates an existing
system; and no boundary — production, WhatsApp, AI, P11, P-FINAL, Enterprise — was crossed.

With known limitations, because: nothing has been exercised against a real provider or a real installation (§AG
and `docs/p10/08-uat-runbook.md` — every step is PENDING REAL UAT); the TikTok fix cannot be verified without a
TikTok credential; eight real findings outside P10's scope are recorded rather than fixed (§AE), two of them
cross-tenant; and the Operations Center's channel column catches up on broken channels only from their next
state change (§R).

## C. Branch and commits

| commit | what |
| --- | --- |
| `58b5b295` | docs(p10): omnichannel and identity discovery |
| `265171bb` | feat(contacts): make contact merge non-destructive and auditable |
| `a53027a5` | feat(contacts): record the phone numbers and addresses a contact cannot hold |
| `fd7508b2` | feat(channels): one honest connection state per channel, and stop three silent greens |
| `47b706e8` | feat(contacts): show everything a customer can be reached at |
| `5d836ef0` | fix(contacts): a discarded duplicate must not take anything else with it |
| `5b06f61d` | fix(channels): stop sending three encrypted credentials to the browser |
| `acc2ab03` | docs(p10): final completion report |
| `e0d24af1` | test: update two assertions P10 deliberately changed (§AB) |

Every commit is pushed. P8 and P9 branches were not touched after branching.

## D. What P10 was asked for, and what it delivered

| asked | delivered |
| --- | --- |
| P10.0 discovery from repository evidence only | `docs/p10/00-discovery.md`, twelve channels on 24 dimensions, questions A–T answered |
| P10.1 channel capability and lifecycle | `Channels::Capability`, `Channels::ConnectionState`, three silent-greens fixed, health plumbed into P9 |
| P10.2 unified identity architecture | `contact_identities`, `Contacts::IdentityLinker`, deterministic inbound fallback, one feature flag |
| P10.3 safe linking and duplicate handling | `Contacts::MergeRelocation`, `Custom::ContactPolicy#merge?`, merge audit, irreversibility disclosure |
| P10.4 omnichannel Customer 360 | the Identities tab |
| P10.5 cross-channel conversation experience | **verified as already present**, not rebuilt (§P) |
| P10.6 channel lifecycle, onboarding, health | `docs/p10/06-channel-lifecycle-health.md`; the connection state and the Operations column |
| P10.7 integration with Tickets, Timeline, Automation, Operations | asserted in `spec/requests/contacts/p10_identity_integration_spec.rb` |
| P10.8 security, performance, hardening | nine query plans, nine isolation assertions, three credentials masked |
| P10.9 tests, documentation, release gate | fifteen spec files, ten documents, 69 gate answers, five gates |

## E. P10.0 Discovery

448 lines, written before any code. Twelve `Channel::` models read for model, table, connect flow, auth, send
path, receive path, webhook, contact identity field, contact-inbox behaviour, conversation creation,
attachments, reply restrictions, secret storage, refresh/expiry, disconnect behaviour, health signal, error
persistence, feature flag, current UI, test coverage and production readiness.

Two findings decided the whole phase:

1. **The constraint.** Three full unique indexes on `contacts`, plus `prepare_contact_attributes` normalising
   blanks to NULL. One Contact, one phone, one email, one identifier.
2. **What already works.** `contact_inboxes` is UNIQUE on `(inbox_id, source_id)` with a plain `contact_id`
   index, so one Contact already holds many provider identities. The gap was never provider identities; it was
   multi-valued phone and email.

Breadth was also sought from a fan-out of twelve per-channel readers with adversarial verifiers. Four
verifications completed before the container restarted and all four **agreed on readiness**; the remaining
verifiers were lost. Their channel reports had already been read and folded into
`docs/p10/02-channel-capability-matrix.md`, and every claim in that document that mattered was then checked
first-hand against the code — including the three the verifiers raised (§AE). Recorded as a limitation of
method, not glossed.

## F. Channel inventory and capability matrix

`docs/p10/02-channel-capability-matrix.md`. Twelve channels. Four put a customer-identifying value in
`source_id` (WhatsApp, Email, Twilio, Bandwidth: phone or email); six put a provider-scoped opaque id
(Facebook, Instagram, TikTok, Telegram, LINE, X); two put a session token (web widget, API).

That split is why `source_id` was **not** unified: a provider-scoped id cannot be normalised into a phone
number, and normalising a session token is meaningless. What P10 unified is the layer above.

`Channels::Capability` holds the three dimensions nothing else owned — identity kind, connection kind, and
where this fork learns the connection is broken — and `spec/services/channels/capability_spec.rb` asserts every
row against the thing that would produce it: the `Reauthorizable` include list, the presence of an `expires_at`
column, the presence of `phone_number_health`. A channel added later with no entry fails that spec.

It deliberately does **not** absorb icons and labels, flow node limits or the outbound service map. Those
answer different questions, and merging them would mean touching 297 `Channel::` literals across 68 frontend
files for no gain in correctness. Stated as a boundary.

## G. Channel connection state and lifecycle

`Channels::ConnectionState` returns P9's `Operations::Health::Component` — not a second vocabulary. The brief's
five names map onto P9's four, and `DISCONNECTED` is deliberately absent because nothing in this fork can
substantiate it for a channel, unlike a Commerce store's real `disconnected` column.

Inputs, in the order read: no capability entry → unknown; no provider → unknown; no health source → unknown
with the reason; the reauthorization latch → critical; missing credentials → critical (only WhatsApp can reach
this); an expired token → critical; a token inside Instagram's own ten-day window → warning; a risky provider
health reading, mirroring `Whatsapp::HealthService#risky_health?` exactly → warning; counted errors below the
threshold → warning; otherwise healthy, listing what was checked.

Three things nobody was told before now surface: Instagram's `expires_at` and TikTok's
`refresh_token_expires_at` were used only by their refresh services; WhatsApp's stored `phone_number_health`
was only a `Rails.logger.warn` line.

## H. The identity constraint, measured

Before P10, on a real account with three inboxes and two contacts for one human:

```
after merge: phone="+96550000001" email="dana@example.com"
second phone survives on contacts? false
second email survives on contacts? false
inbound from the merged-away number resolved to contact 9517 (survivor is 9515)
DUPLICATE RECREATED: true
contacts in the account now: 2
```

After, with the feature enabled:

```
inbound from the merged-away number resolved to contact 9520 (survivor is 9520)
DUPLICATE RECREATED: false
contacts in the account now: 1
identities recorded on the survivor:
  phone +96560000002 source=merged
  email dana.alt@example.com source=merged
```

Note what already worked: the mergee's `contact_inbox` rows moved, so a further message on **the same inbox**
resolved correctly. The failure was the omnichannel one — the same person, the same number, a **different**
channel.

## I. `contact_identities`: the one table

Seven columns, two indexes: `account_id`, `contact_id`, `identity_type` (phone, email), the normalized `value`,
`source` (agent_linked, merged), `linked_by_id`, timestamps. UNIQUE `(account_id, identity_type, value)` plus an
index on `contact_id`.

The B3 questions are each answered in `docs/p10/03-unified-customer-identity.md` §3: why the existing model
fails, why a custom attribute is not enough (no uniqueness, so matching becomes a guess; a jsonb scan on the
hot path; no provenance), why `ContactInbox` is not enough (it validates `inbox_id` presence and its `source_id`
is provider-scoped and unique only per inbox), why widening `contacts` is not enough, why a link table is
required, the three query shapes, the uniqueness rule, the merge behaviour, and the rollback.

**It does not mirror the primary fields.** Consequence: an empty table is today's behaviour, and **no backfill
is needed to deploy it** — which matters because a backfill across a large `contacts` table is the riskiest
part of any identity change, and the brief forbids one.

## J. The linking service

`Contacts::IdentityLinker` is the only writer, used by both the API and the merge. It normalizes, asks **both**
tables who owns the value, and **reports rather than raises**: `linked`, `already_linked`, `conflict` (naming
the owning contact), `invalid`, `disabled`. A conflict is refused — nothing merges, nothing is guessed.

The advisory lock an earlier sketch called for was dropped, deliberately and with the reasoning recorded: the
unique index already makes the concurrent case safe, and a lock the `Contact` save does not also take closes
nothing. Keeping it would have been the speculative guard the project's own guidelines forbid. The residual
exposure is stated rather than papered over.

## K. Deterministic matching on the inbound path

`find_contact` is now `super || linked identity || social identity`. The OSS order is untouched and still
answers every message it can; the additions fire only on the branch that was about to create a new contact.

Email is downcased in the lookup. That is not cosmetic: without it a provider reporting a mixed-case address
would miss the link and then try to create a contact holding a value the account has already linked, which the
`Contact` validation refuses — losing the message. There is a spec for exactly that.

**Reading is never gated on the feature flag.** A link made while the feature was on must keep routing its
messages if the feature is later turned off; silently delivering a customer's replies somewhere else is worse
than either state.

## L. Merge safety

Every table with a `contact_id` was enumerated against the schema — eleven — and each accounted for.
`Contacts::MergeRelocation` moves eight relations inside the merge's existing transaction, where the database
was previously deleting `campaign_recipients`, `commerce_customer_links` and `csat_survey_responses`,
nullifying `support_tickets`, `commerce_carts` and `commerce_action_runs`, and destroying labels through the
gem.

Two relations have a uniqueness the move can violate. The survivor's row is kept, the duplicate is **discarded
deliberately and counted**, and — found by the enumeration, fixed in `5d836ef0` — rows that pointed at the
*discarded* row are moved to the survivor first, which is how a cart keeps its store attribution.

`calls` is absent on purpose: it has a `contact_id` but no model, no foreign key and no writer in this fork.

## M. Merge audit and irreversibility

One `Custom::AuditLog` row per merge, `contact.merged`, against the surviving contact with `associated: account`
— which puts it on Settings → Audit Logs with **no new reader**. Payload: `base_contact_id`,
`mergee_contact_id`, `moved`, `discarded_duplicates`, `identities_absorbed`. Ids, counts and booleans only; a
spec asserts the serialized payload contains neither contact's email address nor phone number. Writing the
record can never roll the merge back.

The merge cannot be undone and nothing stores a snapshot, so both merge surfaces now say so in words, in
English and Arabic, and list what carries over. Nothing implies an undo exists.

Authorization: the OSS endpoint had **no `authorize` call at all** — any account member could destroy a
contact, while `ContactPolicy#destroy?` has always been administrator-only. Now administrator or the
`contact_manage` custom-role permission.

## N. The TikTok duplicate-contact defect

`Tiktok::MessageService` passes `content[:conversation_id]` as the builder's `source_id`; the customer's actual
TikTok user id goes only into `additional_attributes['social_tiktok_user_id']`, which nothing read back. Since
`find_contact` matches on identifier, email and phone — TikTok supplies none — **every new TikTok conversation
created a brand-new Contact for a customer the account already had.** Verified first-hand in the source, not
taken from a report.

Fixed by a third deterministic fallback on that stored user id — an exact match on a provider-issued id, so
nothing is guessed — behind an expression index. `source_id` stays the conversation id because
`find_conversation` and the reply path key on it.

Contacts already duplicated stay duplicated; joining them is a merge, which is now safe and audited. **No
backfill is proposed and none was run.** Status: PENDING REAL UAT — there is no TikTok credential here, so the
fix is proven by six specs against the payload shape the repository's own TikTok specs use.

## O. Customer 360

One tab, gated on the account feature with the same `when:` mechanism the Cases tab uses. Two sections from two
sources, deliberately not merged: the contact's **primary** phone and email, and the **linked** identities with
where each came from. Saying which is which is the point, and the panel says it in a sentence — a primary field
is what an outgoing conversation uses, a linked one is what an incoming message is matched against.

Reading follows the contact; linking and unlinking follow the merge. A viewer without the permission sees no
buttons, which a spec asserts. A server refusal is shown as the server wrote it, naming the contact that owns
the value; nothing offers to merge.

## P. Cross-channel agent experience

**P10.5 needed no code, and that is a finding rather than an omission.** Each part was traced to what already
answers it: the contact's conversation list spans channels; P8's activity timeline spans channels and already
applies the conversation permission filter; P9's cases have their own visibility rule; and the new-conversation
composer already asks the server which inboxes a contact is reachable on and offers only those, with the
controller filtering that answer through `InboxPolicy#show?`. There is no "send on any channel" button to
remove, and P10 did not add one.

What P10 did **not** do, stated as a boundary: a linked identity is not an outbound target. Changing
`contactable_inboxes` to one entry per (inbox, identity) pair would alter an endpoint three components consume,
and the failure mode of getting it wrong is a message sent to the wrong number.

## Q. Permissions

`Conversations::PermissionFilterService` stays canonical and unchanged. Contact access still does not imply
conversation access, and P10 added no surface that hangs conversation data off a contact without the filter.

| action | rule |
| --- | --- |
| read a contact's identities | `authorize @contact, :show?` — anyone who may open the contact |
| link / unlink | administrator, or `contact_manage` |
| merge | the same |

The boundary is on the server: a plain agent POSTing directly gets 401 and no row is created.

## R. Operations Center integration

P9's Operations Center is the one place; P10 feeds it. The channels column said HEALTHY the moment an account
had one inbox. It now counts **distinct** inboxes with open signals — two problems on one inbox is one broken
channel — scoped on `subject_type` rather than a source list, and applies P9's own rule to channels: an account
holding a channel nothing reports on is `unknown`, not green. An account with only a web widget is healthy,
because a channel with no provider has nothing to be silent about.

Two grouped queries per page, measured at **2.233 ms for 25 accounts**. The cost of reading signals rather than
probing each inbox is stated rather than hidden: a channel already latched **before P9 shipped** has a Redis
flag but no signal row, so the cross-account console counts it as unreported until its next transition. The
inbox page, which reads Redis live, is right either way.

## S. P8 analytics and timeline integration

P8 was not rewritten and no new metric was added. Asserted rather than assumed:

- `reporting_events` has **no contact column** — it keys on account, inbox, user and conversation — so a merge
  moves the conversation without touching the event. A spec asserts the row is byte-identical across a merge.
- The timeline shows the union **once** after a merge, and a linked identity adds no entry.
- No analytics family gained an identity, engagement or score metric, and no family named `identity` exists.
- `commerce_contact_metrics` keys on the customer link, so metrics follow a moved link and go with a discarded
  one through its cascade.

## T. P9 support cases integration

A merged customer's support cases follow the survivor — before P10 the foreign key nullified them — and the
move appears in the merge audit as a count. A flow mid-conversation also survives: `flow_sessions` keys on the
conversation, which the OSS merge moves, so nothing in P10 had to touch it. Both asserted.

## U. Feature flags

One new account feature, `lynomia_unified_identity`, `enabled: false`, `column: feature_flags_ext_1`. Its
meaning is exact and was measured both ways:

```
feature=false identities=0 resolved_to_survivor=false contacts_in_account=2
feature=true  identities=1 resolved_to_survivor=true  contacts_in_account=1
```

Off: no row is ever created, and the merge and inbound path behave exactly as they do in production today. On:
the merge records what it absorbs and the API accepts links. Reading is unconditional (§K).

## V. Normalization

`Contacts::Phone.e164` — the app's one E.164 path — with the contact's own recorded country as the only region
source and **no default region**, so a local number typed without a country is refused rather than guessed. No
second parser; `Whatsapp::PhoneNormalizers::*` untouched and feeding the candidate list the fallback consumes.
Email: strip, downcase, `Devise.email_regexp`. A name is never an identity key, anywhere.

One deliberate subtlety, documented: a number that carries its own country is kept even when `e164` will not
vouch for it, because `contacts.phone_number` only asks whether it is *well formed* and the CSV importer stores
such numbers. A stricter rule would have quietly refused to carry across a number a contact already has —
exactly what a merge asks it to do.

## W. Secrets and credential exposure

Three credentials that the models `encrypts` at rest were serialized in full to any administrator:
`imap_password`, `smtp_password` and Twilio's `auth_token`. The inbox payload was the one place each existed in
plaintext. All three now report configured-or-not.

Masking alone would have been a data-loss bug, because the forms pre-filled from the payload and sent the value
back on every save. Three things changed together: the serializer, a blank-means-keep rule
(`Custom::Channel::Email#with_stored_credentials`, with the controller hook generalized from "if whatsapp" to
"if the channel answers it"), and the forms — which start empty, say *"Leave blank to keep the current
password"*, and no longer demand a password once one is stored.

What stays, and why: `channel_api`'s `hmac_token` and `secret` are this installation's own tokens, which an
administrator must copy into their client and can rotate through an existing endpoint; `account_sid`,
`api_key_sid` and the provider ids are identifiers, not secrets.

Nothing P10 added carries a secret. The merge audit holds ids and counts; the connection state reports a failed
WhatsApp health check **without quoting the provider's message**, and a spec asserts its JSON contains neither
a planted secret nor `graph.facebook.com`.

## X. Tenant isolation

`spec/requests/contacts/p10_identity_isolation_spec.rb` builds two tenants holding **the same phone number and
the same email address** — the fixture that catches a filter keyed on the wrong thing — and asserts nine
behaviours: the same value is allowed in two accounts; the list returns only this account's row; reading
another account's contact is 404; reading your own through another account's id is 401; unlinking another
account's identity is 404 with the row intact; linking a value another account holds is allowed; the inbound
match resolves to this account's contact; a cross-account merge is 404 with the mergee intact.

The account scope is not re-implemented: the controller inherits the existing contacts base controller, so a
foreign id is 404 before any policy runs.

## Y. Query plans, including the one that failed

Fixtures spread across **50 accounts** — 200,000 contacts, 100,000 identities, 20,000 signals — because a single
account holding the whole table makes a sequential scan genuinely cheaper and proves nothing (the method
failure recorded in P9).

| query | plan | time |
| --- | --- | --- |
| inbound identity fallback | Index Scan, `index_contact_identities_on_account_type_value` | **0.091 ms** |
| the linker's cross-check | Index Scan, same | **0.027 ms** |
| the Contact validation | Index Scan, same | **0.018 ms** |
| one contact's panel | Index Scan, `index_contact_identities_on_contact_id` | **0.022 ms** |
| Operations channels column, 25 accounts | Unique over an Index Scan | **2.233 ms** |
| **control:** the cross-check with the index dropped | **Seq Scan** | **8.311 ms** |

**And one index was wrong.** The TikTok index as first written was measured and found **never to be used**. Two
mistakes: the expression has to lead, because `account_id` is not selective inside the account doing the asking;
and the index cannot be partial, because PostgreSQL uses a partial index only when it can prove the query
implies the predicate, and `(additional_attributes ->> 'k') = 'v'` does not prove `additional_attributes ? 'k'`
— measured with and without the containment test added to the query. On one account with 200,000 contacts:
**21–26 ms unused** in both partial shapes, **0.045 ms** once the expression leads and the index is complete,
for 4,712 kB against a 61 MB table. Re-measured against the fragment the product ships: **0.056 ms**.

Finding that is the entire reason the brief asks for the plan, and it is recorded as a correction rather than
quietly fixed (`docs/p10/07-security-performance.md` §3.3).

## Z. Frontend, i18n and RTL

Composition API with `<script setup>`; Tailwind utilities and design tokens only, no custom CSS, no scoped CSS,
no inline styles; existing `Button`, `Input` and `Spinner`; no new frontend dependency; `usePolicy` for the
permission check; loading, empty and error states, with the error showing the server's own words.

Fifteen keys in both English and Arabic, static i18n keys so the linter can check them, `bdi dir="auto"` on each
value so an Arabic interface renders a `+965…` number the right way round. Writing the spec found a real i18n
bug: a bare `@` is vue-i18n's linked-message syntax, so `name@example.com` failed to compile as a message.

Removed: `getInboxWarningIconClass`, which hard-coded Facebook and Email and had no caller outside its own test.

## AA. Tests added

Fifteen new spec files and six modified. Four existing assertions were **deliberately changed**, each with the
reasoning written into the example: the upstream expectation that a manually configured WhatsApp number reports
no reauthorization latch; the frontend expectation that the IMAP form round-trips the password; the expectation
that the inbox payload returns Twilio's `auth_token`; and the exhaustive feature-flag map. The last two were
found by the full gate rather than during development (§AB).

| file | what it holds |
| --- | --- |
| `spec/models/contact_identity_spec.rb` | uniqueness per account, DB-level enforcement, format, cascade |
| `spec/models/contact_linked_identity_spec.rb` | the `Contact` validation, both directions, and that it costs no query when neither column changes |
| `spec/services/contacts/identity_linker_spec.rb` | every status, normalization, the race, the flag |
| `spec/services/contacts/merge_relocation_spec.rb` | all eight relations, the discards, the re-pointed dependents |
| `spec/actions/custom/contact_merge_action_spec.rb` | absorption, the audit, the transaction, the flag |
| `spec/builders/contact_inbox_with_contact_builder_identity_spec.rb` | the two new fallbacks, precedence, cross-account |
| `spec/services/channels/capability_spec.rb` | the table against the filesystem and against `Reauthorizable` |
| `spec/services/channels/connection_state_spec.rb` | every rung, and that a provider message is not quoted |
| `spec/services/operations/account_health_spec.rb` | the channels column, including "silence is not green" |
| `spec/controllers/.../identities_controller_spec.rb` | the API, the permission split, the 422s, idempotency |
| `spec/requests/channels/p10_connection_state_spec.rb` | the serializer, and the two silent-green regressions |
| `spec/requests/channels/p10_credential_exposure_spec.rb` | the three secrets, both save directions |
| `spec/requests/contacts/p10_identity_integration_spec.rb` | P8 and P9, asserted not assumed |
| `spec/requests/contacts/p10_identity_isolation_spec.rb` | two tenants, same values |
| `ContactIdentities.spec.js` | the panel, including the permission split |

## AB. Quality gate results

Run on a clean, untouched tree at `5b06f61d` — `git status` showed nothing but this untracked report.
No code was edited while a suite ran; the only file touched during the RSpec run was this document, which
nothing loads.

| gate | result |
| --- | --- |
| `bundle exec rubocop` | **2,870 files inspected, no offenses detected** |
| `pnpm eslint` | **478 problems: 0 errors, 478 warnings** — see the delta below |
| `npx vite build` | **built in 1m 30s, exit 0** |
| `pnpm test` | **491 test files, 5,294 examples, all passed, exit 0** (222.71s) |
| `bundle exec rspec` | **9,464 examples, 0 failures, 70 pending, exit 0** (33m 13s) |

**RSpec took two runs, and the first one is part of the record.** The first full run reported **9,464
examples, 2 failures** — both of them stale assertions encoding contracts P10 changed on purpose, neither
caught by the per-file runs during development:

- `spec/controllers/api/v1/accounts/inboxes_controller_spec.rb:352` asserted that the inbox payload returns
  Twilio's `auth_token` in full. P10 stopped sending it (§W). Updated to assert the new contract — no
  `auth_token` key, `auth_token_configured` true, `account_sid` still present — and the agent example now also
  asserts the boolean is not disclosed to a non-administrator. The positive coverage already existed in
  `spec/requests/channels/p10_credential_exposure_spec.rb`; this file held the inverse.
- `spec/models/account_spec.rb:146` asserts the whole `feature_flags_ext_1` map, which gained
  `feature_lynomia_unified_identity` at `1 << 10`. Extended, following the convention P9's flag set at
  `1 << 9`.

Fixed in `e0d24af1`, after which the suite was re-run **in full on a clean tree** to produce the figure in the
table. The 70 pending examples are all pre-existing (MFA, Devise sessions, the encrypted-credential shared
examples, `data_import`, `user_spec`); P10 added none and skipped none.

**The ESLint delta is zero.** The baseline at P9 head `15efa6a7` was measured in a throwaway `git worktree`
with the same `node_modules`: **478 problems (0 errors, 478 warnings)** — the same figure as this head. So P10's
new and changed frontend files added no warning. (The `pnpm eslint` script globs `app/**/*.{js,vue}`; the
baseline run globbed `app/javascript/**/*.{js,vue}`, which is where every JS and Vue file in `app/` lives, and
both returned 478.)

RuboCop inspects 2,870 files with zero offences, which includes every new and changed Ruby file.

## AC. Database changes and reversibility

Two migrations, both additive, both verified by a full `db:rollback` / `db:migrate` round trip producing a
byte-identical `db/schema.rb`:

- `20261009120000_create_contact_identities` — one table, two indexes. Rollback is `drop_table`; nothing in
  `contacts`, `contact_inboxes`, `conversations` or `messages` references it, and every reader falls back to
  today's behaviour when it is empty.
- `20261009130000_add_social_identity_index_to_contacts` — one expression index, whose shape was measured (§Y).

No column was added to an existing table. No data was migrated. No backfill exists.

## AD. What P10 deliberately did not build

No second contact table, address book, customer master or identity graph. No probabilistic or AI matching, no
duplicate suggestions, no scoring — nothing compares names, avatars, usernames, email local-parts or phone
suffixes. No second inbox engine, conversation engine, messaging runtime, queue or event bus. No second channel
health dashboard and no second health vocabulary. No second E.164 parser. No engagement score, no new
ReportingEvent. No backfill. No server-side feature gating added to the six channels that have none (a
behaviour change for existing accounts; recorded for P11). No Enterprise restoration — `enterprise/` is absent,
`ChatwootApp.extensions == ["custom"]`, `enterprise?` is false, all three verified in the console on this
branch. No AI, CAPTAIN or OpenAI. No billing, plan, quota or usage work. No licence, provenance, security or
commercial-cleanup audit.

## AE. Findings recorded but not fixed

Each verified first-hand, each with the evidence and the reason it is not P10's to change
(`docs/p10/07-security-performance.md` §5, `docs/p10/02-channel-capability-matrix.md` §§3a, 3b, 5, 6).

| finding | why not here |
| --- | --- |
| **Bandwidth SMS webhook is unauthenticated** and picks the tenant from a body field | a cross-tenant injection path; a security repair on a channel with no credential here. **P-FINAL.** |
| Bandwidth delivery receipts always raise (wrong kwarg, wrong payload level) | same channel |
| Bandwidth batched webhooks drop all but the first event | same channel |
| **Voice calling posts to four endpoints that have no routes and no controller actions** | implementing them is a new feature; the two connect flows degrade with an alert, the three settings pages do not |
| **WhatsApp inbound routes on `display_phone_number`, not Meta's `phone_number_id`** | the inbound path production runs; cannot be exercised without a real Meta webhook |
| TikTok OAuth `state` has no `exp` claim | needs a TikTok app |
| TikTok webhook replay guard is one-sided (a future timestamp passes) | same |
| TikTok webhook is never registered — the client methods have no callers | same |
| X is effectively retired: connect entry point removed, gating flag repurposed by a migration | a product and licence decision |

## AF. Corrections to my own earlier statements

Recorded because a report that hides its own corrections is worth less than one that shows them.

1. **The claimed inbox-existence leak does not exist.** This project's own discovery document said
   `Contacts::ContactableInboxesService` leaked inbox existence to a restricted agent. It does not: the service
   is unfiltered, but its only caller filters through `InboxPolicy#show?`. Corrected in
   `docs/p10/00-discovery.md` §10. What remains is a trap, not a defect — the filter lives in the controller, so
   a second caller would not inherit it.
2. **The merge direction.** An earlier reading had the widget's automatic merge destroying the existing
   customer's history. The parameter is *named* `mergee_contact` but passed as `base_contact`, so the existing
   customer survives. The consequence is real but smaller, and was restated accordingly.
3. **The TikTok index was wrong twice** (§Y), found by measuring.
4. **An advisory lock was planned and then dropped**, with the reasoning recorded rather than silently omitted.
5. **The per-file spec runs were not sufficient.** Two stale assertions survived development and were caught
   only by the full suite (§AB). Running the affected file after each change would have found both; running
   only the files I had written would not. Recorded because the gate earned its place.

## AG. Known P8 and P9 production items, carried forward

Unchanged and un-reinterpreted. P10 adds to this list; it does not clear any of it.

- **P8:** all nine pending production items stand exactly as P8 recorded them.
- **P9:** all real UAT remains pending. P10 changed nothing about the support module, the SLA clock or the
  Operations console other than making the channels column honest.
- **P3 / WhatsApp:** the real-number UAT gate is carried forward verbatim — template `order_delivered`,
  language `en_US`, status APPROVED, sent to a **genuinely new Contact**, and **not during development**. P10
  sent nothing and changed nothing about that gate.
- **P10's own:** every step of `docs/p10/08-uat-runbook.md` is PENDING REAL UAT, and TikTok cannot be verified
  at all without a credential.

## AH. Production safety and boundaries held

No deploy, no SSH, no production database mutation, no feature activation, no real customer messaging, no
provider reconnect, no credential rotation, no campaign send, no WhatsApp template send, no backfill, no OS
change. Production remains on `b03ea43df6abf18cb9c4e5d6a9271ba040b689f4`. P8 and P9 are preserved as
checkpoints; `15efa6a7` is an ancestor of this head and the P9 branch was not touched. The WhatsApp boundary
was held in full: no unofficial path, no QR or Evolution route, no WhatsApp Web shortcut, no change to Meta
status or webhook semantics.

## AI. Recommended next step for P11

**Deploy nothing yet; the sequencing in the brief is right.** Three things are worth doing in this order.

1. **Run P10's UAT on one pilot account** (`docs/p10/08-uat-runbook.md`), because the two defects P10 closes are
   closed in code and in specs but not yet in the world. The flag is off by default and per account, so this
   costs one account's risk. Steps 3, 6 and 8 are the ones that matter: a second number resolving on a new
   channel, a merge losing nothing, and a broken IMAP inbox finally showing a warning.
2. **Start P11 on the plan model, not on quotas.** P10 found that "disable a channel for an account" is not a
   capability this product has — six of twelve channels have no flag, and of those that do, most are enforced
   only in the frontend (`docs/p10/02-channel-capability-matrix.md` §7). Any plan that sells channels needs
   that gate to exist server-side first, and adding it is a behaviour change for existing accounts that should
   be made deliberately with the plan design rather than retrofitted under quota pressure. That is the one
   P10 → P11 dependency worth naming.
3. **Hand §AE to P-FINAL as a list, not as prose.** Two of those findings are cross-tenant and one is a
   non-functional surface the dashboard still calls. They are each one commit of work for someone with the
   right credential, and they are the kind of thing a commercial security audit will find anyway — better to
   arrive with them already written down.
