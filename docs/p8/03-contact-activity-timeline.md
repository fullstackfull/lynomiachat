# P8.6 / P8.7 — Contact activity timeline

`GET /api/v1/accounts/:account_id/contacts/:contact_id/activity`

One contact's activity, in order, from every source that already records it.

---

## 1. Why a read projection and not a timeline table

Every event this screen shows already has a canonical home: a message, an activity message, a reporting event,
a CSAT response, a campaign recipient, an automation execution, a flow session, a cart, an order action, a
customer link.

Writing them a second time into a `contact_timeline_events` table would:

- create a second source of truth that can disagree with the first,
- be **empty for everything that happened before it existed**, which is most of what a timeline is for,
- and need a backfill from exactly the sources this query already reads.

So the timeline is a composition of per-source adapters over the existing tables. `docs/p8/00-discovery.md` §4
is the register of what each source can honestly say; this document is what was built from it.

---

## 2. Shape

```
Contacts::ActivityTimelineQuery
  ├── MessagesAdapter             messages (incoming, outgoing, system template, private note)
  ├── ConversationEventsAdapter   conversations.created_at + activity messages
  ├── ReportingEventsAdapter      first_response, resolved, bot handoff/resolved, reopen
  ├── CsatAdapter                 csat_survey_responses
  ├── CampaignsAdapter            campaign_recipients
  ├── AutomationsAdapter          automation_rule_pending_executions
  ├── FlowsAdapter                flow_sessions
  └── CommerceAdapter             commerce_carts, commerce_action_runs, commerce_customer_links
```

### The normalised row

Every adapter returns the same `Contacts::ActivityTimeline::Entry`:

| Field | Meaning |
| --- | --- |
| `id` | `"<source>:<record_id>"` — stable, so a UI can key a list on it |
| `source` | which table it came from; also the cursor's tiebreak |
| `category` | the UI filter it belongs to |
| `kind` | what happened, e.g. `message_incoming`, `campaign_read`, `cart_abandoned` |
| `occurred_at` | microsecond ISO 8601, UTC |
| `conversation_id` | when the event belongs to one |
| `summary` | short human text, truncated to 240 characters |
| `meta` | ids, codes, counts and statuses only |

`meta` never carries a provider payload, a token, an encrypted value, or a customer identifier the caller did
not already have. `commerce_customer_links.external_customer_id` is encrypted and is never emitted; the entry
carries `match_source` instead, which is what a reader needs to judge the match.

### Categories

A category is a reading of the activity, not a table. `conversations` spans activity messages, reporting
events, CSAT and flow outcomes, because to an operator those are all "what happened in the conversations".

| Category | Adapters |
| --- | --- |
| `messages` | Messages |
| `conversations` | ConversationEvents, ReportingEvents, Csat, Flows |
| `campaigns` | Campaigns |
| `automations` | Automations |
| `commerce` | Commerce |

An unknown category answers `422` with the allowed list.

---

## 3. Pagination is mandatory and bounded

There is no unpaginated mode and no "all" limit. `limit` defaults to 30 and is capped at 100; anything outside
`1..100` answers `422`.

### The cursor encodes the whole sort key

The order is `occurred_at DESC, source ASC, record_id DESC` — **total**, not just by time. Two sources can
record something in the same instant, and with only a timestamp cursor one of those rows would be skipped or
repeated at every page boundary. So the cursor carries all three components, base64-encoded, and a malformed
cursor answers `422` rather than silently producing a wrong page.

Each adapter applies the cursor as SQL over its own column. Because `source` is constant within one adapter,
the equal-instant case collapses to one of three predicates:

| `cursor.source <=> adapter.source` | at exactly the cursor instant |
| --- | --- |
| cursor sorts first | include every row |
| same source | include rows with a smaller id |
| cursor sorts later | include none |

### How "more remains" is known

Each adapter is asked for `limit + 1`. After merging and sorting, more remains exactly when the merged list is
longer than one page. That is an exact answer, not an estimate: a merged list longer than `limit` can only
happen if at least one row was left over.

A spec walks a whole timeline in pages of two and asserts the concatenation equals the single-page read, with no
duplicate and no gap.

---

## 4. Permissions

Authorization follows the **contact**, not the report permission. Analytics is account-wide reporting and is
administrator-only (`ReportPolicy#view?`); this is one record's own history, so it follows that record's policy
— `authorize @contact, :show?` — exactly as the contact's attachment and conversation lists do. An agent who
may open a contact may see what happened with that contact.

Within that, what the caller sees is narrowed twice:

1. **Conversation-derived adapters** read `Conversations::PermissionFilterService`, the same filter the
   contact's attachment list already uses. An agent restricted to some inboxes must not learn through a
   timeline what happened in a conversation they cannot open. A spec asserts a message in an unassigned inbox
   is absent for a restricted agent and present for an administrator.

2. **Campaign recipients** carry an inbox but no conversation, so they are narrowed by the caller's own visible
   **inbox** set, computed from their role by the same rule. Deriving it from this contact's conversations
   instead would hide a campaign that addressed them in an inbox they have never written in.

**Commerce** rows carry neither an inbox nor a conversation (carts and links do not), so they are gated on the
contact alone, which the caller was already authorized against. There is nothing narrower to gate on without
inventing a rule.

**Private notes are included**, with their own `kind`. That is what the conversation view does — anyone who can
open a conversation sees its private notes — and the timeline is gated on the same conversation visibility. It
introduces no new disclosure, and omitting them would make the timeline disagree with the thread it summarises.

### Tenant isolation

Each adapter is account-scoped and contact-scoped **on its own**. No adapter relies on another having filtered
for it, so adding one cannot widen what an earlier one returned. `params[:account_id]` is never read: the
account comes from `Current.account` and the contact from `Current.account.contacts.find(...)`, so a contact id
from another account answers `404`.

---

## 5. Degradation: what fails loudly and what degrades

| Adapter | Failure behaviour |
| --- | --- |
| Messages | **raises** |
| ConversationEvents | **raises** |
| everything else | warning + `partial: true` |

Messages and conversation events are what a contact timeline *is*. If either cannot be read, returning the rest
would present a timeline with the communication missing as if that were the whole story — so the request fails.
Every other adapter is optional: a commerce table being unavailable must not hide the conversation history.

The rescue is narrow (`ActiveRecord::ActiveRecordError`, `NoMethodError`, `KeyError`) and deliberately does not
catch everything, so an authorization error can never be downgraded to a warning.

---

## 6. What each source can and cannot say

| Source | Entry kinds | Honest limits |
| --- | --- | --- |
| messages | `message_incoming`, `message_outgoing`, `message_system_template`, `private_note` | `messages` has no `contact_id`, so the path is through `conversations.contact_id` |
| conversations | `conversation_created` | — |
| activity messages | `conversation_status_changed`, `conversation_activity` | only `conversation_status_changed` carries structured data; everything else is localized prose written at the time, surfaced **as** that text with `structured: false`, and nothing parses it to guess what it described |
| reporting events | `first_response`, `conversation_resolved`, `bot_handoff`, `bot_resolved`, `conversation_reopened` | `reply_time` is excluded: one row per agent reply would bury everything else and add nothing a message row does not. A first `conversation_opened` is dropped because the conversation entry already covers it |
| csat | `csat_response` | — |
| campaigns | `campaign_<status>` | one row per recipient, not per state change: the ladder keeps only the furthest state reached, and the per-state timestamps are on that one row, so `meta` carries them |
| automations | `automation_executed`, `automation_skipped` | delayed rules only, 30-day retention; an immediate rule records nothing and nothing infers one from a message it may have sent. Pending episodes are excluded: they have not happened |
| flows | `flow_completed`, `flow_failed`, `flow_cancelled`, `flow_handed_off` | ended runs only; there is no per-node history, so a run is one row and not a trace |
| commerce | `cart_abandoned`, `cart_completed`, `commerce_action_<status>`, `commerce_customer_linked` | no money: `visible_total` is paired with a per-cart currency and nothing converts, so `meta` carries the currency and item count and not the amount. `commerce_contact_metrics` is **not** read: it is a cache refreshed in place, so reading it would put today's number on an old date |

### Not present, and why

| Would-be event | Why it is absent |
| --- | --- |
| contact profile changed | `Contact` is not an audited model; nothing records a change (`docs/p8/00-discovery.md` §4.6) |
| contact field / custom attribute changed | same |
| immediate automation ran | no execution record exists anywhere |
| flow node entered | no per-node history exists |
| cart state transition history | a cart row holds its current state; there is no per-transition log |
| conversation deleted | the `audits` row has no contact link |

---

## 7. Tests

| Spec | Count | Covers |
| --- | --- | --- |
| `spec/services/contacts/activity_timeline_query_spec.rb` | 24 | composition, ordering, truncation, tenant and record isolation, inbox-restricted agents, cursor walk with no gap or repeat, limit and cursor rejection, categories, core-vs-optional degradation |
| `spec/services/contacts/activity_timeline_spec.rb` | 11 | one example per source, plus the money and encrypted-field exclusions |
| `spec/requests/contacts/contact_activity_spec.rb` | 12 | authorization (agent allowed, foreign administrator refused, foreign contact 404), payload shape, category narrowing, inbox narrowing, cursor following, the three 422s |
