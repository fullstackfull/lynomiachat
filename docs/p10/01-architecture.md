# P10 — Architecture

What this document is for: the shape of P10 in one place — what was added, what was extended, what was
deliberately not built, and the rule each decision followed. The detail lives in the numbered documents beside
it; this is the map.

---

## 1. The rule P10 was built under

> DO NOT BUILD A SECOND CONTACT SYSTEM.

Taken literally, and applied as a test on every piece of work: before adding anything, say which existing table,
service or vocabulary already owns the question, and either extend it or state in writing why it cannot answer.
The result is one new table, one new index, four new services and no new engine of any kind.

| P10 asked for | what already owned it | what P10 did |
| --- | --- | --- |
| a customer master | `contacts` | extended it with `contact_identities` for the values it has no column for |
| provider identities per customer | `contact_inboxes` | nothing — it already works, one row per inbox |
| cross-channel conversation history | `conversations` + the contact's conversation list | nothing |
| the customer's own timeline | P8's `Contacts::ActivityTimelineQuery` | nothing |
| channel health | P9's `Operations::Signal` + `Operations::Health` | fed the existing store and fixed the column that lied |
| a channel health dashboard | P9's Operations Center | extended it; no second dashboard |
| conversation visibility | `Conversations::PermissionFilterService` | nothing — reused, unchanged |
| the audit trail | `Custom::AuditLog` (Settings → Audit Logs) | wrote one new event to it; no new reader |
| merge | `ContactMergeAction` | prepended, so the OSS transaction and ordering are unchanged |
| the E.164 rule | `Contacts::Phone` | reused; no second parser |

## 2. What was added

**One table.** `contact_identities` — `account_id`, `contact_id`, `identity_type` (phone, email), the normalized
`value`, `source` (agent_linked, merged), `linked_by_id`, timestamps. UNIQUE `(account_id, identity_type, value)`
plus an index on `contact_id`. It holds only the values `contacts` cannot: a Contact is exactly one phone, one
email and one identifier, enforced by three full unique indexes
(docs/p10/03-unified-customer-identity.md §1). It does **not** mirror the primary fields, so an empty table is
today's behaviour and no backfill is needed to deploy it.

**One index.** A partial expression index on `contacts` for `additional_attributes->>'social_tiktok_user_id'`,
which is what makes TikTok's identity lookup a probe rather than a scan
(docs/p10/02-channel-capability-matrix.md §3).

**Four services.**

| service | what it decides |
| --- | --- |
| `Contacts::IdentityLinker` | the only writer of an identity row: normalizes, checks BOTH tables for an owner, reports a conflict instead of guessing |
| `Contacts::MergeRelocation` | what a merge carries across before the mergee is destroyed, and what it deliberately discards |
| `Channels::Capability` | the three per-channel dimensions nothing else owned: identity kind, connection kind, where this fork learns the connection is broken |
| `Channels::ConnectionState` | one honest connection state per inbox, returned as P9's `Operations::Health::Component` |

**Three extension points taken.** `ContactMergeAction`, `ContactPolicy` and
`Api::V1::Accounts::Actions::ContactMergesController` were prepended through the repository's own
`prepend_mod_with` mechanism; `ContactInboxWithContactBuilder` gained that hook (one line) so its matching could
be extended the same way rather than edited. Each prepend was verified live in the console before being relied
on.

## 3. The decisions that shaped it

**Identity is deterministic or it does not exist.** Three confidence classes, and only three: a primary field or
a provider `source_id` is VERIFIED; a row in `contact_identities` is EXPLICITLY LINKED; everything else is
UNRESOLVED and stays two contacts until a human decides. There is no similarity, no score, no fuzzy source, and
`source` has exactly two values because there are exactly two ways an identity gets recorded. A collision is
reported as a conflict and refused — the stance `ContactIdentifyAction` already took.

**Reading is never gated; writing is.** The `lynomia_unified_identity` account feature controls whether an
identity can be **recorded**. It is deliberately not consulted when one is **read**: a link an account made
while the feature was on must keep routing its messages if the feature is later turned off, because silently
delivering a customer's replies somewhere else is worse than either state.

**Every new matching rule is a fallback, never a replacement.** `find_contact` is now
`super || linked identity || social identity`. The OSS order — identifier, email, phone and its provider-quirk
candidates, then an Instagram `source_id` seen on a Facebook page — is untouched and still answers every message
it can. The additions fire only on the branch that was about to create a new contact, so the cost is one indexed
lookup on the rare path and nothing on the common one.

**Silence is not green.** P9's rule, extended to channels. A channel type with no health source renders
`unknown` with the reason, not `healthy`; an account holding one cannot be summarised as healthy on the strength
of the others. Five of the twelve channels report nothing, and P10 says so rather than inventing a probe.

**A state the repository cannot substantiate is not reported.** `DISCONNECTED` has no source of truth for
channels in this fork, unlike a Commerce store's real `disconnected` column, so it is absent rather than faked.

**Where two readers need the same fact, they may read it differently.** The inbox serializer computes
`Channels::ConnectionState` live, because it handles one inbox. The Operations Center counts durable signals,
because it renders 25 accounts and a per-inbox computation would be a Redis read and a channel load each. The
difference, and the one thing it costs, are written down rather than left to be discovered
(docs/p10/06-channel-lifecycle-health.md §4).

**An irreversible operation says so.** The merge cannot be undone and nothing stores a pre-merge snapshot, so
both merge UIs now say that in words, and every merge writes one audit row carrying ids and counts — never a
phone number, an email address or a name.

## 4. What P10 deliberately did not build

- No second contact table, address book, customer master or identity graph.
- No probabilistic or AI matching, no duplicate suggestions, no scoring. Nothing compares names, avatars,
  usernames, email local-parts or phone suffixes.
- No second inbox engine, conversation engine, social messaging runtime, queue or omnichannel event bus.
- No second channel health dashboard, and no second health vocabulary.
- No second E.164 parser. `Whatsapp::PhoneNormalizers::*` are untouched — they answer a different question
  (provider quirks of an already-international id) and feed the candidate list the fallback consumes.
- No change to WhatsApp's provider semantics, webhook handling, status model or the genuine-new-contact UAT
  gate. No unofficial WhatsApp path was reactivated or introduced.
- No `engagement score`, no new ReportingEvent, no change to P8's existing metrics.
- No backfill, in a migration or out of it.
- No server-side feature gating added to the six channels that have none — a behaviour change for existing
  accounts, recorded for P11.
- No Enterprise restoration: `enterprise/` is absent, `ChatwootApp.extensions == ["custom"]`, `enterprise?` is
  false, and nothing in P10 depends on any of it.
- No AI, no CAPTAIN, no OpenAI.
- No billing, plan, quota or usage work.
- No licence, provenance or commercial-cleanup audit — that is P-FINAL's.

## 5. The documents

| document | what it holds |
| --- | --- |
| `00-discovery.md` | the repository evidence P10 was planned from, and the A–T answer index |
| `01-architecture.md` | this map |
| `02-channel-capability-matrix.md` | twelve channels, read from the code; the TikTok identity defect and the two PARTIAL channels |
| `03-unified-customer-identity.md` | why one table, what it is not, the measured defect it closes, normalization, the inbound path |
| `04-contact-merge-linking.md` | what a merge used to destroy, what it carries now, who may run one, what is recorded |
| `05-omnichannel-customer-360.md` | what an agent sees about a customer across channels, and what it reuses |
| `06-channel-lifecycle-health.md` | the three silent-green cases, the one connection state, the Operations column |
| `07-security-performance.md` | the query plans, the isolation tests, the secret audit |
| `08-uat-runbook.md` | what a human has to do on a real installation, in order |
| `P10_RELEASE_GATE.md` | the 69 questions, answered |
