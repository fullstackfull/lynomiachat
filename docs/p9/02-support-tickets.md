# Support cases

A support case is a unit of work the business owes somebody, which is not the same thing as a conversation. The
architecture decision that follows from that — a thin `support_tickets` table beside `conversations` rather than
columns added to it, and nothing about conversations reimplemented — is argued in `01-architecture.md`. This
document is what the thing actually does.

Vocabulary: the table and the models are `support_tickets` / `Support::Ticket`, because "ticket" is what the
schema and the API say. Everything a user reads says **case**, because "ticket" in a product that also has
conversations invites the question "so is a conversation a ticket?". The answer is no, and the word change is
the cheapest way to stop the question being asked.

---

## 1. What a case is

| | |
| --- | --- |
| **Reference** | `TCK-000001`, per account. The column is a bare integer; the prefix and the padding are presentation, so changing either never needs a migration. |
| **Title** | required, ≤ 255 |
| **Description** | optional, ≤ 10,000. Excluded from the audit trail — a customer may have dictated something into it that should not exist in a second copy. |
| **Category** | one of ten: `technical billing account integration whatsapp commerce campaign automation operational other` |
| **Status** | `open in_progress waiting_on_customer waiting_on_internal resolved closed` |
| **Priority** | `low medium high urgent` — the same four values in the same order as `Conversation`, so an agent learns one scale |
| **Labels** | the account's existing labels, through `Labelable`. No new label system. |
| **Links** | conversation, contact, inbox, assignee, team, SLA policy — every one of them optional |
| **Source** | polymorphic, allow-listed to `Operations::Signal`. One thing in this product opens a case on its own. |

**Every link is optional, and that is the point.** A case with no contact, no inbox and no conversation is an
internal operational case — "the Zid token needs rotating before Thursday" — and it is the case
`conversations.inbox_id NOT NULL` makes impossible to represent as a conversation. A case with all three is a
customer problem being worked alongside the thread it came from.

### Reference numbering

```sql
SELECT pg_advisory_xact_lock(hashtext('support_tickets_reference'), account_id);
SELECT COALESCE(MAX(reference_number), 0) + 1 FROM support_tickets WHERE account_id = $1;
```

Taken inside the creating transaction, so two simultaneous creates in one account serialise and creates in
different accounts do not block each other at all. The alternative — copying `Conversation#display_id`'s
per-account Postgres sequence and its two triggers — was rejected in `01-architecture.md` §4 with the five
pieces of work it would have added, the first of which is that those sequences are not in `db/schema.rb`, so a
fresh schema load has none and the first insert raises.

---

## 2. Who can see a case

Not inbox membership. A case can exist with no inbox at all, and its title may describe a customer the reader
has no business seeing, so visibility is **ownership**:

| | |
| --- | --- |
| administrators | every case in the account |
| agents with `support_ticket_manage` | every case in the account |
| everyone else | the cases assigned to them, assigned to one of their teams, or that they opened |

`support_ticket_manage` is a new entry in `CustomRole::PERMISSIONS`, so it cannot be granted by a typo. It is
the account's way of saying "this agent is a support lead".

`Support::TicketPolicy::Scope` is the single definition, and `Scope.for(user:, account:)` exists so the contact
activity timeline asks the *same* rule rather than growing a second one that can drift. A case the caller may
not see answers **404, not 403**: a 403 confirms the record exists.

---

## 3. The API

`/api/v1/accounts/:account_id/support/…`, nine endpoints. Every one of them is behind the account feature
`lynomia_support_tickets`; an account without it gets **404**, because the module does not exist for it — not
403, which would tell a caller what it could have if it paid.

| | |
| --- | --- |
| `GET tickets` | the list: filters, sort, page, and the tab counts in `meta.counts` |
| `GET tickets/:id` | one case, by id **or by pasted reference** (`TCK-000123`) |
| `POST tickets` | opens a case |
| `PATCH tickets/:id` | changes one |
| `GET tickets/:id/events` | history, oldest first, 50 per page |
| `POST tickets/:id/events` | an internal note — the only event type a client may create |
| `GET/POST/PATCH/DELETE sla_policies` | targets, administrator only |

### What the server owns

`account_id`, `reference_number`, `created_by_id`, `source_type`, `source_id`, every SLA timestamp,
`sla_paused_seconds`, `resolved_at`, `closed_at` and `last_activity_at` are **never read from a request**. A
request that sends them is not rejected, it is ignored — and `spec/requests/operations/p9_hardening_spec.rb`
sends all of them in one call and asserts each one. `created_by` comes from the session. A note's `user_id` and
`event_type` are likewise inert: `Support::Tickets::EventRecorder` takes the actor from the session and the type
from the controller, so a client cannot fabricate a status change that never happened.

### Cross-tenant links are resolved, not validated

```ruby
LINKS = { 'conversation_id' => [:conversation, :conversations], 'contact_id' => [:contact, :contacts], … }
attributes[association] = value.presence && Current.account.public_send(collection).find(value)
```

One enforcement point. An id from another account raises `RecordNotFound` and renders 404 before any write,
rather than becoming a validation error after one. The model's own `linked_records_belong_to_account` is the net
under that, for a console or a future service that does not come through this controller.

### Filters, and why nothing is silently dropped

`status` (or the pseudo-statuses `active` / `terminal`), `priority`, `category`, `assignee_id` (or `me` /
`unassigned`), `team_id`, `contact_id`, `inbox_id`, `conversation_id`, `sla`, `q`, `since`, `until`, `sort`,
`page`, `per_page`.

An unknown enum value is a **422 naming the allowed set**. An id that does not belong to the account is a **422
naming the filter**, never an empty page — an empty page reads as "this customer has no cases", which is a
different and wrong answer. `per_page` above 100 is a 422 rather than a silent clamp.

`q` is reference-first: `TCK-000123` or `123` looks up that one case, and only a term that is not
reference-shaped falls through to a title `ILIKE` with `%` and `_` escaped. Falling through on a reference miss
would hide the fact that the reference does not exist.

`me` and `unassigned` are resolved server-side so a client needs neither its own user id nor a way to express a
`NULL`.

### Epoch seconds, not calendar dates

`since` and `until` are epoch seconds, bounded at `253_402_300_799`. This differs from Analytics on purpose:
Analytics takes calendar dates because the server cuts buckets in the account's own timezone, while a case's
clock is an instant. Same contract as the audit-log reader.

---

## 4. The list, and its counts

Default sort `last_activity_at DESC`, 25 per page, ceiling 100. Six sorts: activity (both directions), creation
(both directions), resolution due time, and priority (desc, then activity).

The tab counts are **four numbers from one grouped query plus two cheap counts**, not six list requests, and
they run through the caller's own policy scope. A tab reading "12" over a list of 3 would be a disclosure, not a
cosmetic bug.

The measured cost of the whole list request, at 100,200 cases with the account holding 5%: **0.052 ms** for the
page and **1.330 ms** for the counts. Plans in `06-security-performance.md`.

---

## 5. History

One table, `support_ticket_events`, holding both the history and the internal notes — because an internal note
*is* an entry in the history, and two tables would mean merging two orderings in the UI for no gain.

Sixteen event types: `created note status_changed priority_changed assigned team_changed category_changed
conversation_linked conversation_unlinked sla_applied sla_first_response_met sla_first_response_breached
sla_resolution_breached resolved reopened closed`.

Three of them exist so the trail reads as a story rather than as six identical `status_changed` rows: entering a
terminal state records `resolved` or `closed`, and leaving one records `reopened`.

`data` is jsonb holding ids, enum values and timestamps. `user_id` is nil for an event the system wrote — the
SLA sweeper, or a case an operator opened from the Super Admin console, where there is no acting account user
and inventing one would be a lie in the audit trail.

**This is the one history in the product that is queryable.** A conversation's own assignee, team, label and
priority changes are localized prose with no structured payload (`ActivityMessageHandler`), which is why P8's
contact timeline had to leave them out and why P9's can include cases.

---

## 6. Where a case appears

| Surface | What it shows |
| --- | --- |
| **Support** in the sidebar | the workspace: six saved views, filter bar, sortable list, pagination |
| a case's own page | status and priority controls offering only reachable states, assignment, the SLA reading, history, note box |
| the **conversation** sidebar | the cases linked to this conversation, and one button that opens a case prefilled from it |
| the **contact**'s Cases tab | this contact's cases, beside P8's activity timeline |
| the contact **activity timeline** | case history as timeline entries, never note bodies |
| **Analytics → Support cases** | the metrics P8's rules permit |
| **Settings → Support → SLA policies** | targets, administrator only |

Every one of these is gated on `lynomia_support_tickets`: the routes carry the flag, and the sidebar entries,
the conversation panel and the contact tab are each gated on it too, so an account without the module is never
shown a door that leads to a 404.

### The workspace's URL is its state

The six views (all, mine, unassigned, overdue, resolved, closed), every filter, the sort and the page are all
query parameters, and one watcher on `route.query` refetches. Nothing holds a second copy, so the list cannot
disagree with the address bar and any view is a link somebody can send. Requests go through the shared
abortable-request helper *and* a fetch-id guard: the signal cancels a superseded request on the wire, and the id
discards a response that had already arrived before its cancellation landed.

---

## 7. Analytics

Five counts, one duration, three current-state readings: `tickets_created`, `tickets_resolved`,
`tickets_reopened`, `first_response_breaches`, `resolution_breaches`, `average_resolution_time`, `open_now`,
`overdue_now`, `unassigned_now`. Breakdowns by priority, category, status, team and assignee.

**What is deliberately absent, and why**, because an absent number that should be there is worse than a present
one that is wrong:

- **No SLA attainment percentage.** Every SLA figure in this product begins when a policy is first attached to
  a case, so a percentage over a range that predates the policy divides two different populations. The breach
  *counts* are honest; the rate is not.
- **No first-response average.** `first_responded_at` is filled by a sweep over cases that have a policy, so
  averaging it would describe the governed subset while looking like it described all cases.
- **No reopen rate**, for the same reason the breach rate is absent: the denominator moves.

`tickets_reopened` is counted from the durable event trail rather than inferred from current status, so a case
reopened and resolved again is still counted.

When the account has active cases with no policy attached, the response carries one warning —
`sla / active_cases_without_a_policy` — because a zero breach count does not then mean nothing was late. It is
**conditional**, not permanent: a banner operators see every time is a banner they learn to ignore.
