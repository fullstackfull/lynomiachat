# Platform Support Desk — data model

> Phase 0. **No migrations are written in this phase.** This is the proposal to approve.

## 1. Option comparison

| | Option A — new `platform_support_*` tables | Option B — reuse `Conversation`/`Message` | Option C — extend `Support::Ticket` |
|---|---|---|---|
| Cross-tenant isolation | Schema-level: one `account_id` meaning "subject", one policy scope that adds the predicate itself | Would need a fabricated inbox + contact per account; isolation becomes inbox membership | Per-call-site: every existing reader needs a new `kind` predicate (`01-architecture.md` §2 C-3) |
| Global reference | A unique index on one column | n/a (`display_id` is per-account) | Impossible: existing unique index is `[account_id, reference_number]` (`db/schema.rb:1796`) |
| Staff as assignee | FK to `platform_support_agents` | `Conversation#assignee` must be an `AccountUser` | Blocked by `support/ticket.rb:145-151` |
| Internal-note secrecy | A separate table the tenant query cannot reach | `private` flag on `messages` — a boolean one query can forget | `support_ticket_events` has no visibility column (`db/schema.rb:1750-1760`) |
| Audit | Explicit writes, no account association | Conversation audit is activity messages, not queryable | `audited associated_with: :account` publishes operator activity to the tenant (§2 C-4) |
| Blast radius of a bug | New tables only | Touches the conversation workspace every agent uses daily | Touches the shipped P9 module |
| Cost | 7 tables, 1 migration | "Cheapest" only until the fake contact appears in Contacts, campaigns and analytics | Looks cheapest, is not |

**Recommendation: Option A.**

## 2. `platform_support_tickets`

| Column | Type | Null | Notes |
|---|---|---|---|
| `id` | bigserial | no | |
| `reference_number` | integer | no | **Global**, see §8 |
| `account_id` | bigint | **yes** | The *subject* account, not the owner. See §3 |
| `account_name_at_creation` | string | no | Snapshot, same reason `Custom::AuditLog#capture_actor_name` snapshots the actor (`custom/app/models/custom/audit_log.rb:45-51`) |
| `reporter_id` | bigint | yes | FK `users`, nullify |
| `reporter_name` | string | no | Snapshot. The **only** personal-data snapshot on the table, and it is the minimum that keeps a thread attributable after the person's record is deleted — the same rule `Custom::AuditLog#capture_actor_name` already applies to every audit row (`custom/app/models/custom/audit_log.rb:45-51`) |
| `category` | string | no | default `'other'`, frozen allow-list, §6 |
| `subject` | string | no | max 255. Deliberately `subject`, not `title`, so the two vocabularies read differently |
| `description` | text | yes | max 10 000, matching `support/ticket.rb:63` |
| `status` | integer | no | default 0, §5 |
| `priority` | integer | no | default 1, `{low: 0, medium: 1, high: 2, urgent: 3}` — the same four in the same order as `Conversation` and `Support::Ticket` (`support/ticket.rb:27`), so an operator learns one scale |
| `assignee_id` | bigint | yes | FK **`platform_support_agents`**, nullify. §4 |
| `sla_policy_id` | bigint | yes | FK `platform_support_sla_policies`, nullify |
| `plan_id_at_creation` | bigint | yes | FK `billing_plans`, nullify |
| `plan_name_at_creation` | string | yes | Snapshot: `billing_plans.name` is free text and mutable (`db/schema.rb:342`) |
| `subscription_status_at_creation` | string | yes | Snapshot |
| `first_response_due_at` | datetime | yes | |
| `resolution_due_at` | datetime | yes | |
| `first_responded_at` | datetime | yes | |
| `first_response_breached_at` | datetime | yes | |
| `resolution_breached_at` | datetime | yes | |
| `sla_paused_at` | datetime | yes | |
| `sla_paused_seconds` | integer | no | default 0. Required for honest analytics, `06-sla-notifications.md` §6 |
| `last_customer_message_at` | datetime | yes | Drives the "customer replied" queue |
| `last_operator_message_at` | datetime | yes | |
| `customer_last_viewed_at` | datetime | yes | Drives the tenant unread badge without a notification row |
| `last_activity_at` | datetime | no | |
| `resolved_at` | datetime | yes | |
| `closed_at` | datetime | yes | |
| `created_at`, `updated_at` | datetime | no | |

The SLA column set is deliberately identical in shape to `support_tickets`
(`db/schema.rb:1781-1788`) — same algebra, separate table.

### Indexes

| Index | Purpose |
|---|---|
| `unique (reference_number)` | What makes a global reference true rather than hoped |
| `(account_id, last_activity_at DESC)` | The tenant's list, which is always filtered by account first |
| `(assignee_id, status)` | "My queue" |
| `(status, priority, last_activity_at DESC)` | The staff queue's default ordering |
| partial `(resolution_due_at)` where `resolution_due_at IS NOT NULL AND resolution_breached_at IS NULL AND status < 4` | The SLA sweep. Mirrors `index_support_tickets_on_open_resolution_due` (`db/schema.rb:1793`) |
| partial `(first_response_due_at)` where `… AND first_responded_at IS NULL AND … AND status < 4` | Mirrors `index_support_tickets_on_awaiting_first_response` |
| partial `(status)` where `assignee_id IS NULL AND status < 4` | The unassigned queue |

`status < 4` is why the enum numbering in §5 puts `resolved` and `closed` last. Same convention, same reason.

## 3. `account_id` nullable, and why that is the safer choice

Three options for what happens to a vendor support record when its subject account is deleted:

| | `ON DELETE CASCADE` | `RESTRICT` | **nullify + name snapshot** |
|---|---|---|---|
| Account deletion still works | yes | **no** — breaks the existing `DeleteObjectJob` path | yes |
| Lynomia keeps the complaint history of a churned customer | **no** | yes | yes |
| Tenant can still read it | n/a | n/a | **no** — `where(account_id: <id>)` never matches NULL |

The third column wins on all three rows. A NULL `account_id` means "orphaned, staff-only", and that falls out
of the tenant scope predicate automatically rather than needing a rule. The model keeps `account_id` required
**on create** (`validates :account_id, presence: true, on: :create`) so a live ticket always has a subject,
while the column stays nullable so deletion can orphan rather than erase.

> **D-4 — APPROVED, with a tightening.** Nullable `account_id` plus a **minimal** snapshot. The approval
> added: *do not snapshot unnecessary personal or sensitive data.* Applied as follows.
>
> | Snapshot column | Kept? | Why |
> |---|---|---|
> | `account_name_at_creation` | **kept** | The approved "minimal account-name snapshot". Commercial identity, not personal data |
> | `reporter_name` | **kept** | The minimum that keeps a thread attributable; the existing audit trail already snapshots exactly this and no more |
> | `reporter_email` | **REMOVED** | Was in the original proposal. It is personal data, and it is not necessary: the live address is reachable through `reporter_id` while the user exists, and once the user is deleted there is nobody to reply to. Operators reply in-thread, not by address |
> | `plan_name_at_creation`, `plan_id_at_creation`, `subscription_status_at_creation` | **kept** | Commercial state, no personal data. Required for honest SLA resolution and analytics (`06-sla-notifications.md` §6) |

## 4. `platform_support_agents`

| Column | Type | Null | Notes |
|---|---|---|---|
| `id` | bigserial | no | |
| `user_id` | bigint | no | FK `users`, cascade. Unique index |
| `role` | integer | no | default 0, `{agent: 0, lead: 1}` |
| `active` | boolean | no | default true |
| `display_name` | string | no | Snapshot of `User#available_name` (`app/models/concerns/user_attribute_helpers.rb:4`) at creation, refreshed on edit |
| `created_at`, `updated_at` | datetime | no | |

Validation: `user.is_a?(SuperAdmin)` on create in V1 — because STI constrains reads, not writes
(`01-architecture.md` §7), so without this a plain tenant user id could be seeded as staff. When the brief's
future dedicated support-agent role arrives, this validation is the one place that relaxes.

`lead` is the only capability distinction in V1: a lead may reassign another agent's ticket and edit SLA
policies; an agent may work its own and pick up unassigned. Anything finer is Phase 2.

## 5. Status vocabulary — keeping the brief's six

```
open: 0, in_progress: 1, waiting_on_customer: 2, waiting_on_lynomia: 3, resolved: 4, closed: 5
```

The brief asked for an explanation if a different naming were technically better. It is not — the proposal is
accepted as given, with two notes:

1. **`waiting_on_lynomia` earns its keep as customer-facing copy, not as a queue state.** From the operator's
   side, `open`, `in_progress` and `waiting_on_lynomia` are all "ours", so the staff queue groups them under
   one "Needs us" heading. From the customer's side the distinction is the whole point: it says "we have it,
   you do not need to do anything". Keep it.
2. **The numbering is the only change, and it is internal.** `resolved` and `closed` must be 4 and 5 so the
   partial indexes in §2 can use `status < 4`, the convention the existing table already relies on
   (`db/schema.rb:1793,1796`).

`ACTIVE_STATUSES` / `TERMINAL_STATUSES` / `SLA_PAUSING_STATUSES` constants mirror `support/ticket.rb:35-37`.
`SLA_PAUSING_STATUSES = %w[waiting_on_customer]` — `waiting_on_lynomia` pauses nothing, because waiting on
ourselves is our own delay. That is the existing module's own recorded reasoning (`support/ticket.rb:29-30`)
and it is the right answer here too. Decided explicitly, per the brief: **`waiting_on_customer` pauses both
the resolution clock and the next-response clock; `waiting_on_lynomia` pauses neither.**

## 6. Category taxonomy

A frozen Ruby constant on a plain string column — this repository's own pattern for a constrained type
(`support/ticket.rb:39`, `SOURCE_TYPES` at `:45`, `CustomRole::PERMISSIONS`, `Account::SUSPENSION_CATEGORIES`):

```
technical billing account whatsapp integrations commerce campaigns automation bug feature_request other
```

The brief's eleven, taken as given. The constant is validated with `inclusion:` so an unknown value is a 422 at
the boundary, not a row.

Why not a `platform_support_categories` table: a category needs a label in two languages and nothing else. A
table buys per-category routing, per-category SLA and operator-managed taxonomy — all three of which are
Phase 2 features nobody has asked for, and all three of which can be added later by introducing the table and
backfilling from the constant. Building the table first is building the admin UI for it first, which is the
over-engineered category-management product the brief warned against.

Localisation lives in the locale files, keyed on the constant value
(`platformSupport.json` → `CATEGORY.TECHNICAL`), exactly as the tenant module does for its own categories.

## 7. The thread: two tables, not one with a flag

**`platform_support_messages`** — public, always. Visible to the tenant and to staff.

| Column | Type | Null | Notes |
|---|---|---|---|
| `platform_support_ticket_id` | bigint | no | FK, cascade |
| `author_type` | string | no | frozen allow-list `%w[User PlatformSupport::Agent System]` |
| `author_id` | bigint | yes | NULL for `System` |
| `author_name` | string | no | Snapshot |
| `body` | text | no | max 10 000. **Plain text.** No HTML, no markdown rendering, §9 |
| `created_at`, `updated_at` | datetime | no | |

**`platform_support_internal_notes`** — never public. Same shape minus `author_type` (an internal note is
always written by an agent): `platform_support_ticket_id`, `agent_id` (FK `platform_support_agents`),
`author_name`, `body`, timestamps.

### Why two tables

The brief's requirement was: *"The API and serializer must make accidental disclosure structurally difficult.
Do not rely on frontend hiding alone."*

With one table and a `visibility` column, secrecy is a predicate. The tenant serializer must carry
`where(visibility: :public)`, and so must every count, every "last message" lookup, every search, every export
and every future endpoint. Each is a place where omitting four words discloses an internal note. The repository
has a live example of exactly that failure mode: `Support::TicketPolicy::Scope#resolve` carries no account
predicate and depends on each caller supplying one (`custom/app/policies/support/ticket_policy.rb:37-43`) —
which works today because there are two callers and both remember.

With two tables, there is no predicate to forget. `PlatformSupport::Ticket has_many :messages` and the
tenant-facing code has no association, no model constant and no table name for notes anywhere in its reach. The
omission is not a `where` clause somebody drops; it is a table nobody joined.

**The cost, stated honestly:** the operator view needs one merged chronological list, which means two queries
merged in Ruby (`(messages + notes).sort_by(&:created_at)`) or a UNION. A ticket holds tens of rows, not
thousands, so this is a non-issue for the desk and would be a real issue only for an export over every ticket —
which does not need the merge. The one-table alternative's cost is a disclosure bug; this one's cost is a sort.

A secondary benefit: attachment authorization becomes trivially correct. An attachment on a
`PlatformSupport::InternalNote` is staff-only *because of its parent class*, with no flag to check
(`03-authorization-security.md` §5).

## 8. Reference allocation: global, by advisory lock

Confirming the stated preference. `LYN-000001`, globally sequential, prefix in `#reference` and not in the
column, so changing the prefix never needs a migration (`support/ticket.rb:47-48,91-93`).

Mechanism: mirror `Support::Tickets::ReferenceAllocator` with a constant lock key instead of `account_id`:

```
pg_advisory_xact_lock(hashtext('platform_support_reference'), 0)  -- then MAX(reference_number) + 1
```

### Concurrency analysis, as requested

- The lock serialises **all** platform-ticket creates installation-wide, where the existing per-account lock
  serialises only same-account creates (`reference_allocator.rb:3-5`). That is a real reduction in concurrency,
  and it is free at this scale: a platform ticket is created by a human, a handful of times a day across all
  customers. Two simultaneous creates wait on a single-row `MAX` over an indexed column — microseconds.
- The lock is transaction-scoped, so a crashed request cannot leave it held (`reference_allocator.rb:5`).
- It does **not** serialise anything else. The tenant desk's per-account lock uses a different namespace
  (`hashtext('support_tickets_reference')`), so the two never contend.
- Numbers are not reused: tickets are closed, never destroyed, and no delete endpoint exists.

### Why not a Postgres sequence

A dedicated sequence has no lock and no serialisation at all, and gaps on rollback would be harmless here
(a reference is an identifier, not a count). It is rejected for the reason this repository already recorded
when it faced the same choice: sequences created outside the schema do not appear in `db/schema.rb`, so a
fresh `db:schema:load` has none and the first insert raises — which is one of the four costs enumerated at
`custom/app/models/support/ticket.rb:113-118`. Adding a mechanism whose failure mode is "a new developer's
database is broken until somebody remembers" to save microseconds is the wrong trade.

### Operational usefulness of global over per-account

This is the deciding argument, not the concurrency one. `LYN-000123` on a phone call, in an email subject, in a
Slack escalation or in a status page resolves to exactly one ticket with no "which account?" follow-up. A
per-account reference needs the account alongside it in every one of those places, and silently collides
across accounts in search. It is also the precondition for reference-based email threading
(`01-architecture.md` §10).

## 9. `platform_support_events` — history, default-deny

| Column | Type | Null | Notes |
|---|---|---|---|
| `platform_support_ticket_id` | bigint | no | FK, cascade |
| `event_type` | string | no | frozen allow-list |
| `actor_type` | string | yes | `%w[User PlatformSupport::Agent System]` |
| `actor_id` | bigint | yes | |
| `actor_name` | string | yes | Snapshot |
| `metadata` | jsonb | no | default `{}`. **Never serialised to the tenant** |
| `created_at` | datetime | no | |

Event types:

```
created  subject_changed  category_changed  priority_changed  status_changed  assigned  unassigned
sla_policy_applied  sla_first_response_met  sla_first_response_breached  sla_resolution_breached
customer_replied  operator_replied  internal_note_added  link_added  link_removed  resolved  reopened  closed
```

**Tenant visibility is a positive allow-list of event types**, not a visibility column:

```
CUSTOMER_VISIBLE_EVENT_TYPES = %w[created status_changed customer_replied operator_replied
                                  resolved reopened closed].freeze
```

Default-deny is the property that matters: an event type added in a later phase is invisible to the customer
until somebody deliberately adds it to the list. A `visibility` column would default to *something*, and
whatever it defaults to is what a future contributor gets by forgetting. Note what is excluded and why:
`assigned` (the operator's identity is internal), `internal_note_added` (its existence is internal),
`priority_changed` (internal triage), and every `sla_*` event (Lynomia's internal commitments).

`metadata` holds the structured before/after values for the operator view. It is excluded from the tenant
serializer by construction — the tenant event partial does not reference it.

## 10. `platform_support_sla_policies`

| Column | Type | Null | Notes |
|---|---|---|---|
| `name` | string | no | |
| `description` | string | yes | |
| `billing_plan_id` | bigint | **yes** | FK `billing_plans`, nullify. NULL = the installation default |
| `first_response_time_threshold` | integer | yes | seconds |
| `next_response_time_threshold` | integer | yes | seconds |
| `resolution_time_threshold` | integer | yes | seconds |
| `active` | boolean | no | default true |
| `created_at`, `updated_at` | datetime | no | |

Unique partial index on `(billing_plan_id)` where `billing_plan_id IS NOT NULL`, plus a unique partial index
enforcing a single default row where `billing_plan_id IS NULL`. At least one threshold is required — the same
validation and the same reason as `Support::SlaPolicy#at_least_one_threshold`
(`custom/app/models/support/sla_policy.rb:29-33`): a policy with no target makes a ticket look governed when
it is not.

**No plan names anywhere.** The mapping key is `billing_plans.id`. `billing_plans` has `name` (free text,
mutable), `position`, `features` and `channel_entitlements`, and **no tier or code column** (`db/schema.rb:341-359`),
so an id is the only stable key available. Thresholds are stored as integer seconds rather than the tenant
table's `float` (`db/schema.rb:1739-1746`) because sub-second SLA precision is meaningless and a float
threshold already forced a `.round` in the existing clock (`sla_clock.rb:89`).

Resolution order: the subject account's current plan id → the matching policy; else the default row; else no
SLA, and the UI says so rather than implying one.

> **D-8 — APPROVED.** V1 keys policies on plan only, not on `(plan, priority)`, through configurable policy
> **records**. Priority orders the queue; it does not change the target. The desk tightens later by adding rows,
> with no migration.
>
> **D-7 — APPROVED, reframed.** No threshold numbers are fixed anywhere — not in code, not in a constant, and
> not in this document. Every threshold is a column on a `platform_support_sla_policies` row, supplied as
> operator-entered data when implementation resumes. The architecture is complete without the numbers; that is
> the point of keeping them data-driven.

## 11. `platform_support_links` — Phase 2

| Column | Type | Null |
|---|---|---|
| `platform_support_ticket_id` | bigint | no |
| `linkable_type` | string | no |
| `linkable_id` | bigint | no |
| `created_by_agent_id` | bigint | yes |
| `created_at` | datetime | no |

Unique index on `(platform_support_ticket_id, linkable_type, linkable_id)`.

**One polymorphic table with a frozen type allow-list**, not one nullable FK column per resource. The brief
asked for both options analysed:

| | Nullable columns on the tickets table | **Polymorphic link table** |
|---|---|---|
| Adding a seventh linkable type | A migration on the hot table | A string in a constant |
| "Everything linked to this ticket" | Six OR'd predicates over six indexes | One indexed read |
| "Every ticket touching this store" | One index per type, six times | One index |
| Type safety | Real FKs | A frozen allow-list, validated with `inclusion:` — this repo's own pattern (`support/ticket.rb:40-45`, which explicitly rejects copying `conversations.ai_assignee_type` because that column "is unconstrained at both layers") |
| More than one link of a type | Impossible | Natural |
| Referential integrity | Enforced by the database | Enforced by the model |

The last row is the polymorphic option's one real cost, and it is the cost `operations_signals.subject_type`
already accepted (`db/schema.rb:1601-1602`). Allow-list for V2:
`%w[Inbox Commerce::StoreConnection Campaign Automation BillingSubscription Operations::Signal]`.

Links are **never serialised to the tenant**. The brief: *"do not automatically expose Operations internals to
the tenant"*. The tenant ticket serializer has no `links` key at all.

## 12. Foreign keys, summarised

| FK | On delete | Why |
|---|---|---|
| `tickets.account_id → accounts` | **nullify** | §3 |
| `tickets.reporter_id → users` | nullify | The ticket outlives the employee; `reporter_name` is the snapshot that keeps it attributable |
| `tickets.assignee_id → platform_support_agents` | nullify | A departed agent's tickets return to the unassigned queue |
| `tickets.sla_policy_id → platform_support_sla_policies` | nullify | Same as `Support::Ticket`'s `dependent: :nullify` (`sla_policy.rb:19`) |
| `tickets.plan_id_at_creation → billing_plans` | nullify | `billing_plans` is `restrict_with_error` against subscriptions (`billing_plan.rb:15-18`); a support ticket must never be the reason a plan cannot be retired, hence nullify plus the name snapshot |
| `messages.ticket_id`, `internal_notes.ticket_id`, `events.ticket_id`, `links.ticket_id` | **cascade** | A ticket is never destroyed in product; cascade exists so account teardown and test cleanup leave no orphans |
| `agents.user_id → users` | cascade | Deleting the person removes the staff row; their tickets survive via nullify |
