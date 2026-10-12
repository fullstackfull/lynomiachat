# P10 — Release gate

The brief's 69 gate questions, in its own eleven groups and counts: CHANNELS 1–8, IDENTITY 9–22,
CUSTOMER 360 23–28, PERMISSIONS 29–34, OPERATIONS 35–40, P8/P9 41–45, DATABASE 46–50, PERFORMANCE 51–55,
SECURITY 56–60, ENTERPRISE 61–63, RELEASE 64–69. Each question is stated in the terms that group's section of
the brief set out, and answered with evidence rather than with an assurance. Where the honest answer is "no" or
"pending", it says so.

---

## CHANNELS (1–8)

**1. Is every channel in this fork inventoried from the code, not from what upstream supports?**
Yes. Twelve `Channel::` models, each read for its model, table, connect flow, auth, send path, receive path,
webhook, identity field, secret storage, health signal and test coverage
(docs/p10/02-channel-capability-matrix.md §1). `spec/services/channels/capability_spec.rb` asserts the
registry's key set equals the `Channel::*` files on disk, so a channel added later fails that spec rather than
going undescribed.

**2. Is there one source of truth for channel capability, consumed by backend and frontend?**
Partly, deliberately. `Channels::Capability` is the one source for the three dimensions nothing else owned —
contact identity kind, connection kind, and where this fork learns the connection is broken — and it is
consumed by `Channels::ConnectionState`, by the inbox serializer through it, and by
`Operations::AccountHealth`. It does **not** absorb icons and labels (`dashboard/helper/inbox.js`), flow node
limits (`Flows::ChannelCapabilities`) or the outbound service map (`SendReplyJob::CHANNEL_SERVICES`), because
those answer different questions and merging them would mean touching 297 `Channel::` literals across 68
frontend files for no gain in correctness. Stated as a boundary, not left implied (§8 of the matrix).

**3. Does every channel report an honest connection state?**
Yes, including when the honest answer is "nobody knows". `Channels::ConnectionState` returns P9's
`Operations::Health::Component`: `healthy`, `warning`, `critical`, or `unknown` with `source_class: 'absent'`
and a reason that distinguishes *no provider* (website, API) from *nothing reports it* (Telegram, LINE, Twilio,
Bandwidth SMS, X). Thirteen examples in `spec/services/channels/connection_state_spec.rb`.

**4. Is `DISCONNECTED` reported?**
No, and not by omission. No column, flag or provider field in this fork says a channel was disconnected —
unlike a Commerce store, which has a real `disconnected` status that P9 reads. Reporting it would mean
inventing a state the repository cannot substantiate, so the vocabulary is `critical` ("go and reconnect it")
and `unknown` ("nobody can say"). Recorded in docs/p10/06-channel-lifecycle-health.md §2.

**5. Were the channels that silently looked healthy while broken fixed?**
Three were. A plain IMAP inbox (the common self-hosted case) reported nothing to anybody, because the
serializer emitted `reauthorization_required` for email only for Google/Microsoft and only to administrators. A
manually configured WhatsApp number reported nothing, because the serializer gated it on embedded signup while
`setup_webhooks!` latches for both providers. And five channels report nothing at all, which now renders
`unknown` rather than green. Eight examples in `spec/requests/channels/p10_connection_state_spec.rb`.

**6. Was any provider behaviour invented?**
No. The WhatsApp risky-status set is the repository's own `Whatsapp::HealthService#risky_health?`, used as one
category rather than split into a severity order the repository does not make. Instagram's ten-day expiry
window is `Instagram::RefreshOauthTokenService:43`. TikTok's refresh-token distinction is
`Tiktok::TokenService`. Nothing calls a provider during serialization.

**7. Is any channel reported as ready when it is not?**
No. Two are **PARTIAL** with the defects named in code, not configuration: Bandwidth SMS (unauthenticated
webhook, delivery receipts that always raise, batched webhooks that drop events, no health state) and X
(connect entry point removed, gating flag deliberately repurposed by a migration, management half-gone). Five
more are **CAPABLE_PENDING_CREDENTIALS** because they cannot be exercised here. Recorded in
docs/p10/02-channel-capability-matrix.md §§1, 5, 6.

**8. Was the WhatsApp boundary held?**
Yes. No unofficial path was reactivated or introduced, no QR or Evolution path, no WhatsApp Web shortcut, no
change to Meta status or webhook semantics, and the `order_delivered` / `en_US` / APPROVED / genuinely-new-contact
UAT gate is carried forward unchanged and unrun. P10's only WhatsApp-facing change is that a manually
configured number now reports a latch it already had. One WhatsApp routing fragility was **found and
deliberately not changed** (§3a of the matrix): inbound resolves on `display_phone_number`, with
`phone_number_id` only a post-hoc filter.

## IDENTITY (9–22)

**9. Was a second contact system built?**
No. One narrow table beside `contacts`, which stays the customer record. No customer master, address book,
identity graph, inbox engine, conversation engine, messaging runtime, queue or event bus
(docs/p10/01-architecture.md §4).

**10. Why was a table needed at all, and is that argued from the schema?**
Yes, in order: `contacts` carries three FULL unique indexes per account and
`Contact#prepare_contact_attributes` turns blanks into NULL, so one Contact is exactly one phone, one email and
one identifier (docs/p10/03-unified-customer-identity.md §1). The B3 questions — why the existing model fails,
why a custom attribute is not enough, why `ContactInbox` is not enough, why widening `contacts` is not enough,
why a link table is required, the query shapes, the uniqueness rule, the merge behaviour and the rollback — are
each answered in §3 of that document.

**11. Is the defect it closes measured, not asserted?**
Yes. Before: after a merge the second number existed nowhere and the next inbound message through an untouched
inbox created a new contact (2 contacts). After, with the feature on: the same script resolves to the survivor
(1 contact). Both runs are quoted in §2.

**12. Is matching deterministic, with no probabilistic merging?**
Yes. Three confidence classes and nothing else: a primary field or provider `source_id` is VERIFIED, a row in
`contact_identities` is EXPLICITLY LINKED, everything else is UNRESOLVED and stays two contacts until a human
decides. Nothing compares names, avatars, usernames, email local-parts or phone suffixes. `source` has exactly
two values because there are exactly two ways an identity is recorded.

**13. Is there one entry point for creating an identity?**
Yes. `Contacts::IdentityLinker`. Both writers go through it: the API and the merge. Twenty examples in
`spec/services/contacts/identity_linker_spec.rb`.

**14. Does it check both domains before writing?**
Yes — an existing row **and** `contacts.phone_number` / `contacts.email`. And the same check exists from the
other side: `Contact` gains `primary_identities_not_linked_elsewhere`, conditional on those two columns
changing so the hot path runs no extra query (a spec asserts no query when neither changes).

**15. What happens on a collision?**
It is reported as a conflict naming the owning contact, and refused. Nothing merges, nothing is guessed,
nothing is retried. That is the stance `ContactIdentifyAction` already took (`mergable_phone_contact?`).

**16. Is phone normalization reused rather than reimplemented?**
Yes. `Contacts::Phone.e164`, the app's one E.164 path, with the contact's own recorded country as the only
region source and no default region. No second parser. `Whatsapp::PhoneNormalizers::*` are untouched and feed
the candidate list the fallback consumes. One deliberate subtlety is documented: a number that carries its own
country is kept even when `e164` will not vouch for it, because `contacts.phone_number` only asks whether it is
well formed and the CSV importer stores such numbers — a stricter rule would refuse to carry across a number a
contact already has (§7).

**17. Is a name ever an identity key?**
No, nowhere.

**18. Is the merge non-destructive?**
Now yes. Eight relations are moved inside the merge's existing transaction, where before the database silently
deleted campaign recipients, commerce links, CSAT responses and labels, and orphaned support cases and carts
(docs/p10/04-contact-merge-linking.md §§2–3). Every table with a `contact_id` was enumerated against the schema
to confirm all eleven are accounted for.

**19. What happens when a row cannot be moved?**
It is discarded deliberately and counted. `campaign_recipients` is UNIQUE (campaign_id, contact_id) and
`commerce_customer_links` is UNIQUE (commerce_store_id, contact_id), so when both contacts hold a row for the
same campaign or store, keeping both is impossible — the survivor's is kept, the duplicate is discarded, and
the count is in the audit. Rows that pointed at the *discarded* row are moved to the survivor first, which is
how `commerce_carts` keeps its store attribution.

**20. Is the merge auditable, and does it record a secret?**
Yes and no respectively. One `Custom::AuditLog` row per merge, `contact.merged`, visible in Settings → Audit
Logs with no new reader, carrying ids, counts and booleans only. A spec asserts the serialized payload contains
neither contact's email address nor phone number.

**21. Does the UI say the merge is irreversible?**
Yes. Both merge surfaces render *"This cannot be undone. The merge is recorded in the audit log."* and a list
of what carries over, in English and Arabic. Nothing implies an undo exists, because none does.

**22. Can a merge be run by anyone?**
No longer. The OSS endpoint had **no `authorize` call at all**, so any account member could destroy a contact.
`Custom::ContactPolicy#merge?` is administrator or the `contact_manage` custom-role permission — the rule the
product already uses for `ContactPolicy#destroy?`, widened by the permission that exists for this.

## CUSTOMER 360 (23–28)

**23. Can an agent see everything one customer can be reached at?**
Yes, in one tab: the primary phone and email, and the linked identities with where each came from
(docs/p10/05-omnichannel-customer-360.md §2).

**24. Is the cross-channel history duplicated anywhere?**
No. The conversation list, the P8 activity timeline, the P9 cases and the commerce panel were each traced to
what already answers them, and left alone (§1). P10 added the one thing that was missing.

**25. Is the channel chooser honest?**
Yes, and it already was. `ComposeNewConversationForm` asks the server which inboxes the contact is contactable
on and offers only those; the controller filters that answer through `policy(inbox).show?`. An inbox with no way
to initiate is not offered at all. P10 verified this rather than rebuilding it.

**26. Is a linked identity usable as an outbound target?**
No, and the panel says so. Changing `contactable_inboxes` to one entry per (inbox, identity) pair would alter
the shape of an endpoint three components consume, and the failure mode of getting it wrong is a message sent
to the wrong number. Inbound matching is the half that removes duplicates and it is solved; this is recorded as
a boundary, not a gap nobody noticed (§4).

**27. Does the panel work in Arabic and right-to-left?**
Yes. Fifteen keys in both locales, `bdi dir="auto"` on every value so a `+965…` number renders correctly in an
Arabic interface, and logical Tailwind utilities. Writing the spec found and fixed a real i18n bug: a bare `@`
in the email placeholder is vue-i18n's linked-message syntax and failed to compile.

**28. Does it have loading, empty and error states?**
Yes, and the error state shows the server's own refusal rather than a generic message. Eight examples in
`ContactIdentities.spec.js`.

## PERMISSIONS (29–34)

**29. Does contact access imply conversation access?**
No, and that was checked rather than assumed. `Conversations::PermissionFilterService` stays the canonical
filter and is unchanged; P8's timeline still uses it; P10 added no surface that hangs conversation data off a
contact without it.

**30. Who may read a contact's identities?**
Anyone who may open the contact — `authorize @contact, :show?`, the same rule as its notes, attachments and
activity timeline.

**31. Who may link or unlink one?**
Administrator, or an agent whose custom role grants `contact_manage` — the merge boundary, because linking
decides where the next message carrying that value is delivered. Fourteen examples in the controller spec cover
both the allow and the refuse.

**32. Is the boundary on the server or in the UI?**
On the server. A plain agent POSTing directly gets 401 and no row is created; the UI's `canManage` only hides
controls.

**33. Is tenant isolation tested with a fixture that would catch a missing `account_id`?**
Yes. `spec/requests/contacts/p10_identity_isolation_spec.rb` builds two tenants holding **the same phone number
and the same email address**, then asserts nine behaviours including the inbound match and a cross-account
merge attempt.

**34. Was an existence leak found?**
One was claimed in this project's own discovery document and turned out **not to exist** — the correction is
recorded in docs/p10/00-discovery.md §10 and docs/p10/07-security-performance.md §6.
`Contacts::ContactableInboxesService` is unfiltered, but its only caller filters through `InboxPolicy#show?`.
`SearchService#filter_contacts` remains unfiltered by inbox, which is deliberate and consistent with
`ContactPolicy#index?`.

## OPERATIONS (35–40)

**35. Was a second channel health dashboard built?**
No. P9's Operations Center is the one place, and P10 feeds it.

**36. Was a second health vocabulary introduced?**
No. `Operations::Health::Component` is returned unchanged, including its `source_class`.

**37. Did the Operations channels column stop lying?**
Yes. It said HEALTHY the moment an account had one inbox, whatever state that inbox was in. It now counts
distinct inboxes with open signals and applies P9's own rule to channels. Eleven examples in
`spec/services/operations/account_health_spec.rb`.

**38. Does silence render as green anywhere?**
No. An account holding a channel nothing reports on renders `unknown` with the count, even when its other
channels are fine. An account whose only inbox is a web widget is `healthy`, because a channel with no provider
has nothing to be silent about.

**39. Is the per-account page an N+1?**
No. Two grouped queries per page counting `COUNT(DISTINCT subject_id)`, scoped on `subject_type` rather than a
source list so a future writer is counted too. Measured at **2.233 ms for 25 accounts**
(docs/p10/07-security-performance.md §3.2, Q6).

**40. Is there a cost to reading signals instead of probing each inbox, and is it stated?**
Yes, and it is stated rather than hidden: a channel already latched **before P9 shipped** has a Redis flag but
no signal row, so the cross-account console counts it as unreported until its next transition. The inbox page
itself, which reads Redis live, is right either way.

## P8 / P9 (41–45)

**41. Can a merge change a figure P8 has already reported?**
No. `reporting_events` has no contact column at all — it keys on account, inbox, user and conversation — so a
merge moves the conversation without touching the event. Asserted in
`spec/requests/contacts/p10_identity_integration_spec.rb`.

**42. Does unified identity double-count anything?**
No. The timeline shows the union once after a merge, and a linked identity adds no entry. Both asserted.

**43. Was a new omnichannel metric or engagement score added?**
No. A spec asserts no analytics family gained an identity, engagement or score metric, and that no family named
`identity` exists.

**44. Do P9's support cases survive a merge?**
Yes, pointing at the survivor, and the move appears in the merge audit as a count. Before P10 the foreign key
nullified them.

**45. Does a flow mid-conversation survive?**
Yes. `flow_sessions` keys on the conversation, which the OSS merge moves, so nothing in P10 had to touch it.
Asserted by column inspection rather than by assumption.

## DATABASE (46–50)

**46. How many tables were added?**
One: `contact_identities`. Seven columns, two indexes.

**47. Is it narrow?**
Yes, and narrower than the brief's own sketch allowed: `account_id`, `contact_id`, `identity_type` (two values),
the normalized `value`, `source` (two values), `linked_by_id`, timestamps.

**48. Is a backfill required?**
No. The table does not mirror the primary fields, so an empty table is today's behaviour and nothing has to be
migrated at deploy time. No backfill is proposed and none was run.

**49. Are both migrations reversible?**
Yes, verified by a full `db:rollback` / `db:migrate` round trip producing a byte-identical `db/schema.rb`, for
each one.

**50. What is the uniqueness rule, and is it enforced by the database?**
`UNIQUE (account_id, identity_type, value)`. Enforced by the index, not only by the model — a spec saves with
`validate: false` and asserts `ActiveRecord::RecordNotUnique`.

## PERFORMANCE (51–55)

**51. Was every new index justified by a query the product issues?**
Yes — three query shapes, listed in docs/p10/03-unified-customer-identity.md §3, and no others exist.

**52. Were the plans measured with realistic fixtures?**
Yes: 50 accounts, 200,000 contacts, 100,000 identities, 20,000 signals, spread across accounts rather than
concentrated in one — the method failure recorded in P9 §2 pass 2 is explicitly avoided
(docs/p10/07-security-performance.md §3.1).

**53. Is the hot path an index probe?**
Yes. The inbound identity fallback is **0.091 ms**; the linker's cross-check 0.027 ms; the Contact validation
0.018 ms; the panel 0.022 ms.

**54. Is the before/after recorded for each index?**
Yes, and one of them failed. The identity index control: the same query without it is a **Seq Scan, 8.311 ms**
against 0.027 ms — 300×. The TikTok index as first written was measured and found **never to be used**: it took
two corrections (the expression must lead; it cannot be partial, because PostgreSQL cannot prove
`->> = ?` implies `? 'key'`) to go from 21–26 ms to **0.045 ms**. Both the failure and the fix are in §3.3.

**55. Was any speculative index added?**
No. Two indexes on the new table, both answering a listed query shape, and one expression index whose necessity
and shape were both measured.

## SECURITY (56–60)

**56. Is any credential exposed that was not before?**
No. Three that **were** exposed are now masked: `imap_password`, `smtp_password` and Twilio's `auth_token`, each
`encrypts`ed at rest and each previously serialized in full to any administrator
(docs/p10/07-security-performance.md §1.1).

**57. Did masking them break anything?**
No, and that was the hard part. The settings forms pre-filled from the payload and sent the value back on every
save, so masking alone would have wiped the stored password. Blank now means keep, via
`Custom::Channel::Email#with_stored_credentials` and a generalized controller hook; the forms start empty, say
so, and no longer demand a password once one is stored. Seven examples cover both directions.

**58. Does anything P10 added write a secret to a log or an audit row?**
No. The merge audit carries ids and counts; the connection state reports a failed WhatsApp health check without
quoting the provider's message (a spec asserts the component's JSON contains neither a planted secret nor
`graph.facebook.com`); `contact_identities` values are never logged.

**59. Are provider payloads and URLs sanitized where they are surfaced?**
Yes, and P9's `Operations::SignalRecorder` redaction is unchanged and still asserted by
`spec/requests/operations/p9_hardening_spec.rb`.

**60. Were security findings outside P10's scope recorded rather than fixed blind?**
Yes — eight, each with the file and the reason it is not P10's to change, in
docs/p10/07-security-performance.md §5. Two are cross-tenant (Bandwidth's unauthenticated webhook picking the
tenant from a body field) and belong in the P-FINAL audit with that evidence.

## ENTERPRISE (61–63)

**61. Is the `enterprise/` directory absent?**
Yes.

**62. Is `ChatwootApp.extensions == ["custom"]` and `enterprise?` false?**
Yes, verified in the console on this branch.

**63. Does anything in P10 depend on Enterprise code, or restore it?**
No. No Enterprise channel, SLA or report functionality was restored. `ContactMergeAction#merge_calls` remains
the permanent no-op it is in this fork, and `calls` has no model, no foreign key and no writer — so a merge has
nothing to move there.

## RELEASE (64–69)

**64. Was production touched?**
No. No deploy, no SSH, no production DB mutation, no feature activation, no customer messaging, no provider
reconnect, no credential rotation, no campaign send, no WhatsApp template send, no backfill, no OS change.
Production remains on `b03ea43df6abf18cb9c4e5d6a9271ba040b689f4`.

**65. Is P9 preserved as a checkpoint?**
Yes. This branch was cut from `15efa6a7` and `git merge-base --is-ancestor 15efa6a7 HEAD` succeeds; the P9
branch was not touched after branching.

**66. Are the AI, P11 and P-FINAL boundaries held?**
Yes. No AI matching, duplicate detection, reply assistance, routing, summaries or agents; no CAPTAIN or OpenAI
activation. No billing, plan, subscription, trial, quota, usage or overage work. No licence, provenance,
security or commercial-cleanup audit begun.

**67. Are the known P8 and P9 production items carried forward unchanged?**
Yes — P8's nine pending items and all of P9's pending UAT, unchanged and un-reinterpreted, restated in the final
report.

**68. Is there a runbook a human can follow?**
Yes: `docs/p10/08-uat-runbook.md`, thirteen sections in order, each saying what it proves, and every one marked
PENDING REAL UAT because nothing in it has been run.

**69. Did the five quality gates run on a clean untouched tree, with exact results?**
Yes, all five, recorded in `docs/p10/P10_FINAL_COMPLETION_REPORT.md` §AB:

| gate | result |
| --- | --- |
| `bundle exec rubocop` | 2,870 files inspected, no offenses detected |
| `pnpm eslint` | 478 problems (0 errors, 478 warnings) — identical to the P9 baseline, so the delta is zero |
| `npx vite build` | built in 1m 30s, exit 0 |
| `pnpm test` | 491 files, 5,294 examples, 0 failures, exit 0 |
| `bundle exec rspec` | 9,464 examples, 0 failures, 70 pending (all pre-existing), exit 0 |

The RSpec gate took two runs: the first found two stale assertions encoding contracts P10 changed on purpose,
both fixed in `e0d24af1`, after which the suite was re-run in full. Both runs are recorded in §AB rather than
only the green one.
