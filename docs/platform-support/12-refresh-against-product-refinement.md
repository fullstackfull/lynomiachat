# Platform Support Desk — refresh against Product Refinement, and the frozen implementation contract

> **STATUS: CONTRACTS FROZEN.** Implementation may begin. This document supersedes `00`–`11` wherever the two
> disagree; everywhere else `00`–`11` remain the detail and the reasoning, and this file is the delta plus the
> parts that must be unambiguous for three agents working in parallel.

**Baseline.** Code `3cff6eb0af101b8a606b363028eda95f89b3d274` (`lynomia-custom`, Product Refinement and the
pre-deploy cleanup merged, deployed and smoke-tested healthy by the owner). Branch `claude/platform-support`,
cut from that commit; `85300333` carried `00`–`11` across unchanged, so `git diff 3cff6eb0 HEAD` is docs only.

**How this refresh was done.** Six read-only investigations against this baseline: the prior architecture
extracted and every anchor it cites re-verified; the notification seam; tenant navigation, design system,
i18n/RTL and contextual help; the Super Admin shell and the Operations V2 seams; the cross-cutting backend
conventions; and the existing tenant `Support::` domain plus the documentation seam. Nothing here is a redesign
of an approved decision: D-1 … D-9 stand except where a line of this repository contradicts them, and each such
case is named below.

---

## A. What Product Refinement already solved

| # | The prior architecture said | What this baseline says |
|---|---|---|
| **A-1** | `Sidebar.vue:744`'s `].filter(child => child.href)` silently drops a `to`-based child, and fixing it is *"the one production change this module cannot ship without"* (`01` §9, `04` §2, `08`, `09` §1, `11` §5) | **Already solved.** `Sidebar.vue:734` wraps the Help & Support children in `navigableEntries([...])` from `components-next/sidebar/navigationContract.js`, which states the three routing forms once and accepts `to` and `href` alike; `SidebarGroup.vue:119-120` composes it with the permission half. `docs/product-refinement/11-notifications-and-navigation.md:174-181` is literally titled "Why this mattered to Platform Support". **Phase D loses that edit**; the module's "five files outside itself" becomes four, and adding the two children is purely additive |
| **A-2** | D-6: the notification path is *"an absolute block"* until `conversation_visibility.rb` denies unknown primary-actor types by default | **The precondition is met.** `custom/app/services/notifications/conversation_visibility.rb:79` is a positive allow-list (`VISIBLE_ACTOR_TYPES = ['Conversation']`), applied first and unconditionally at `:110` and `:124`; its own header names *"a platform support case"* as what the old pass-through would have published to tenants. **D-6 is discharged as a block.** A new constraint replaces it — see §5 |
| **A-3** | The Operations Center is the precedent for a non-Administrate Super Admin surface, with a measured N+1 warning | **Superseded, better.** Control Center V2: 11 endpoints, 14 views, 15 services, its own route drawer. The precedent is stronger and the cited line numbers are stale. The `Billing::Settings` N+1 that document warned about **is fixed and has a regression spec** (`spec/services/operations/overview_query_budget_spec.rb`) |
| **A-4** | Account 360 integration needs designing | **Already built, and the code says so.** `custom/app/services/operations/account_snapshot.rb:161-172` carries a comment naming this phase and stating that a Platform Support ticket count *"becomes one more key in this hash and one more line in the view's support block; no other file changes"*. A two-line integration |
| **A-5** | "When this module ships, its tenant portal and its error states should route through whatever contextual-help registry that phase establishes, instead of adding a parallel one" (`11` §5) | **The registry exists.** Platform Support links through it; it does not add another |
| **A-6** | The audit-write pattern had to be described in prose | **A real file to copy.** `Operations::SignalLifecycle` is an explicit-write, Super-Admin-actor, `associated`-deliberately-absent audit writer with a credential-scrubbed operator reason — exactly this module's shape (`custom/app/services/operations/signal_lifecycle.rb:107-146`) |
| **A-7** | D-4's "nullable FK + minimal snapshot" had no in-repo precedent | **It has one now**, written after `524bd8db`: `operations_signal_events` keeps a bare nullable `actor_id` beside an `actor_name` snapshot |

## B. What is superseded, simplified, or newly constrained

| # | Item | Verdict |
|---|---|---|
| **B-1** | Every `db/schema.rb` anchor the docs cite **except `billing_plans`** has shifted 11–34 lines (`support_tickets` 1763→1797, `support_sla_policies` 1742→1776, `notifications` 1574→1589, `users` 1871→1905, the FK block 2006→2042). The content claims all still hold at the new numbers | **Superseded citations, valid content.** Implementers verify by name, never by line |
| **B-2** | `06` §4 reason 3 — "a new `NOTIFICATION_TYPES` entry auto-appears in the tenant preferences UI" | **Superseded.** That UI reads a hard-coded list (`settings/profile/constants.js:1-37`); only the server-side flag vocabulary is derived (`notification_setting.rb:30-31`) |
| **B-3** | Adding a notification actor type is a one-constant edit | **New constraint.** `narrow` applies the conversation subselect to the **whole** allowed set (`conversation_visibility.rb:113`), so a ticket id would be compared against conversation ids — a silent wrong answer by id collision. A non-conversation type needs its **own branch** in both `narrow` and `permits?` |
| **B-4** | — | **New constraint.** Two cross-type collisions exist today, both keyed on `primary_actor_id` while ignoring `primary_actor_type`: `Notification::RemoveDuplicateNotificationJob:11` (also unscoped by account, enqueued for every created row at `notification.rb:164`) and the front-end store (`store/modules/notifications/mutations.js:29-31`, comment "primary_actor_id is unique" — the index it names is **not** unique, `db/schema.rb:1605`) |
| **B-5** | — | **New constraint.** The Inbox feed would break on a non-conversation actor: `InboxList.vue:169` destructures `primaryActor: { inboxId, id: conversationId }` and routes to `inbox_view_conversation`; `InboxCard.vue:55` destructures `inbox.value` unconditionally. Badge and list are **one relation** (`notification_finder.rb:13-31`), so the count cannot be added without the row |
| **B-6** | The "Next response" SLA clock has a policy threshold and a pause rule | **Cut from V1.** There is no `next_response_due_at` and no breach column anywhere in the proposed schema, so the contract cannot express the target it promises. Half a clock is worse than none |
| **B-7** | A 75%-of-window SLA warning with an operator email | **Cut from V1.** It has no event type in the 19-type allow-list, so it cannot be recorded |
| **B-8** | `platform_support_links` (M7) | **Deferred, not migrated.** Phase 2, no V1 consumer, and its allow-list named `Commerce::StoreConnection`, which is a service object and not a model. Also decisive: `Operations::Overview`'s `unlinked` metric reads `support_ticket_id IS NULL` and means "with no support case" — a second link column would silently change what that number means |
| **B-9** | `01` §3 opens by naming the exception namespace `CustomExceptions::PlatformSupport` before contradicting itself | **Resolved: `CustomExceptions::PlatformTickets`**, because `lib/custom_exceptions/tickets.rb:4-6` already owns the other name shape |
| **B-10** | — | **New constraint.** There is **no authorized ActiveStorage blob download anywhere in this repository**: every blob is served by ActiveStorage's own signed-id redirect with no policy check, and blob URLs do not expire here. Platform Support builds the first one, and no serializer may emit a blob URL |
| **B-11** | — | **New constraint.** `app/views/super_admin/application/_navigation.html.erb:40` must gain `"platform_support"` in the exclusion array in the *same commit* as the nav item: Administrate enumerates every controller under `super_admin/` from the route table, and the loop raises for a controller with no index route and no dashboard — omitting it breaks the sidebar on **every** Super Admin page. The nav icon id must exist in `_icons.html.erb` or it renders a blank square |
| **B-12** | — | **Still true and load-bearing:** `PlatformSupport::` collides with nothing. A grep over `app custom lib config db` is empty |

---

## 1. Final schema contract

Six tables in V1. **Zero changes to any existing table.** `platform_support_links` is not created (§B-8).
Integer-backed enums, declared positionally (`enum :status, {...}`) — the keyword form is deprecated in this
Rails version and the repository is full of the warning.

### M1 `platform_support_agents`
`id` bigserial. `user_id` bigint **NOT NULL**, FK `users` ON DELETE CASCADE, **unique index**. `role` integer
NOT NULL default 0 `{agent: 0, lead: 1}`. `active` boolean NOT NULL default true. `display_name` string NOT NULL
(snapshot of `User#available_name`). `created_at`/`updated_at` NOT NULL.
Model: validates on create that the user **is a `SuperAdmin`** — STI constrains reads only, so without it a
tenant user id could be seeded as staff. `lead` is the only capability distinction in V1: a lead may reassign
another agent's ticket and edit SLA policies. **No rows are seeded or invented** (approved constraint).

### M2 `platform_support_sla_policies`
`id`. `name` string NOT NULL. `description` string NULL. `billing_plan_id` bigint NULL, FK `billing_plans` ON
DELETE NULLIFY — NULL means the installation default. `first_response_time_threshold` integer NULL **(seconds)**.
`resolution_time_threshold` integer NULL **(seconds)**. `active` boolean NOT NULL default true. timestamps.
Indexes: unique partial on `(billing_plan_id)` where not null; unique partial enforcing a single default row
where null. Validation: at least one threshold present.
**`next_response_time_threshold` is NOT created** (§B-6). Integer seconds, not the tenant table's float, because
a float already forced a `.round` in the tenant SLA clock. The mapping key is `billing_plans.id` and **never** a
plan name: `billing_plans` has no `tier` and no `code`, and `name` is free text.
**No threshold values are chosen here.** Production targets are owner data, not code (D-7).

### M3 `platform_support_tickets`
`id`. `reference_number` integer NOT NULL — **globally unique**. `account_id` bigint **NULL**, the *subject*
account, FK `accounts` ON DELETE NULLIFY, with `validates :account_id, presence: true, on: :create` so a live
ticket always has a subject while deletion orphans rather than erases. `account_name_at_creation` string NOT
NULL. `reporter_id` bigint NULL, FK `users` NULLIFY. `reporter_name` string NOT NULL — the **only**
personal-data snapshot; **`reporter_email` must never be added** (D-4). `category` string NOT NULL default
`'other'`. `subject` string NOT NULL, max 255. `description` text NULL, max 10 000. `status` integer NOT NULL
default 0. `priority` integer NOT NULL default 1 `{low: 0, medium: 1, high: 2, urgent: 3}`. `assignee_id` bigint
NULL, FK **`platform_support_agents`** NULLIFY. `sla_policy_id` bigint NULL, FK M2 NULLIFY. `plan_id_at_creation`
bigint NULL, FK `billing_plans` NULLIFY. `plan_name_at_creation` string NULL. `subscription_status_at_creation`
string NULL. `first_response_due_at`, `resolution_due_at`, `first_responded_at`, `first_response_breached_at`,
`resolution_breached_at`, `sla_paused_at` datetime NULL. `sla_paused_seconds` integer NOT NULL default 0.
`last_customer_message_at`, `last_operator_message_at`, `customer_last_viewed_at` datetime NULL.
`last_activity_at` datetime NOT NULL. `resolved_at`, `closed_at` datetime NULL. timestamps NOT NULL.
Indexes: unique `(reference_number)`; `(account_id, last_activity_at DESC)`; `(assignee_id, status)`;
`(status, priority, last_activity_at DESC)`; partial `(resolution_due_at)` where `resolution_due_at IS NOT NULL
AND resolution_breached_at IS NULL AND status < 4`; partial `(first_response_due_at)` where `first_response_due_at
IS NOT NULL AND first_responded_at IS NULL AND first_response_breached_at IS NULL AND status < 4`; partial
`(status)` where `assignee_id IS NULL AND status < 4`. `status < 4` is why `resolved` and `closed` are numbered
last.

### M4 `platform_support_messages` — public, always
`id`. `platform_support_ticket_id` bigint NOT NULL, FK CASCADE. `author_type` string NOT NULL, frozen allow-list
`%w[User PlatformSupport::Agent System]`. `author_id` bigint NULL (NULL for `System`). `author_name` string NOT
NULL (snapshot). `body` text NOT NULL, max 10 000, **plain text** — no HTML, no markdown, no rich editor.
timestamps. `has_many_attached :platform_support_message_files`.

### M5 `platform_support_internal_notes` — never public
`id`. `platform_support_ticket_id` bigint NOT NULL, FK CASCADE. `agent_id` bigint NOT NULL, FK M1.
`author_name` string NOT NULL. `body` text NOT NULL, max 10 000, plain text. timestamps.
`has_many_attached :platform_support_note_files`. No `author_type`: a note is always written by an agent.
**A separate table, never a visibility flag on M4** — secrecy must not be a predicate anybody can forget.

### M6 `platform_support_events`
`id`. `platform_support_ticket_id` bigint NOT NULL, FK CASCADE. `event_type` string NOT NULL, frozen allow-list.
`actor_type` string NULL `%w[User PlatformSupport::Agent System]`. `actor_id` bigint NULL. `actor_name` string
NULL (snapshot). `metadata` jsonb NOT NULL default `{}` — **never serialized to the tenant**. `created_at` NOT
NULL.
`EVENT_TYPES` (18 — `link_added`/`link_removed` drop with M7, the SLA warning type is not introduced):
`created, subject_changed, category_changed, priority_changed, status_changed, assigned, unassigned,
sla_policy_applied, sla_first_response_met, sla_first_response_breached, sla_resolution_breached,
customer_replied, operator_replied, internal_note_added, resolved, reopened, closed, account_deleted`.
`CUSTOMER_VISIBLE_EVENT_TYPES` = `%w[created status_changed customer_replied operator_replied resolved reopened
closed]` — a **positive 7-of-18 allow-list**, so a type added later is invisible until deliberately listed.
Deliberately excluded: `assigned` (operator identity is internal), `internal_note_added` (its *existence* is
internal), `priority_changed` (internal triage), every `sla_*` (Lynomia's internal commitments).

### Reference allocation
`pg_advisory_xact_lock(hashtext('platform_support_reference'), 0)` then `MAX(reference_number) + 1`, inside the
creating transaction. The `LYN-` prefix and the six-digit padding live in `#reference`, never in the column.
A **different lock namespace** from the tenant allocator so the two never contend. **No Postgres sequence**: a
sequence is absent from `db/schema.rb`, so a fresh schema load would break — the tenant desk already proved this.
Concurrency is a required proof, not a claim (§10).

### Foreign keys
`tickets.account_id` → `accounts` NULLIFY; `tickets.reporter_id` → `users` NULLIFY; `tickets.assignee_id` →
`platform_support_agents` NULLIFY; `tickets.sla_policy_id` → M2 NULLIFY; `tickets.plan_id_at_creation` →
`billing_plans` NULLIFY; `messages`/`internal_notes`/`events`.`platform_support_ticket_id` CASCADE;
`agents.user_id` → `users` CASCADE.

---

## 2. Final API contract

### Tenant — `/api/v1/accounts/:account_id/platform_support/`
JSON. Devise `:user` or `api_access_token`, Pundit. Drawn from `config/routes/platform_support.rb` by one
`draw :platform_support` line in `config/routes.rb`.

| Verb | Path | Params | Success | Notes |
|---|---|---|---|---|
| GET | `/tickets` | `status[]`, `category[]`, `priority[]`, `q`, `page`, `per_page` — all optional | 200 `{meta:{current_page,total_entries,per_page,counts:{open,closed,unread}}, payload:[ticket]}` | **No** `assignee_id`, **no** SLA filter. An unknown filter *value* is 422 `UnknownFilterValue` |
| GET | `/tickets/:id` | numeric id **or** a `LYN-` reference | 200 ticket | Resolved **inside** the already-account-scoped policy scope. 404 otherwise |
| POST | `/tickets` | `{ticket:{category,subject,description,priority,attachment_ids:[]}}` | 201 ticket | Server-owned and never accepted: `reference_number`, `account_id`, every snapshot, `assignee_id`, `sla_policy_id`, every SLA timestamp, `status`. A new ticket always opens |
| PATCH | `/tickets/:id` | `priority`; `status:'closed'` only when the ticket is `resolved` | 200 ticket | Rejects category, subject, description and every server-owned field |
| GET | `/tickets/:id/messages` | `page` | 200 `{payload:[message]}` | Public messages only |
| POST | `/tickets/:id/messages` | `{message:{body,attachment_ids:[]}}` | 201 message | 422 when closed. On a `resolved` ticket it succeeds **and reopens**: writes `reopened` and restarts the resolution clock |
| GET | `/tickets/:id/events` | — | 200 `{payload:[event]}` | `CUSTOMER_VISIBLE_EVENT_TYPES` only; no `actor_name` for operator-side events; `metadata` never emitted |
| POST | `/tickets/:id/mark_viewed` | — | 200 | Stamps `customer_last_viewed_at`; clears the unread dot |
| GET | `/attachments/:id` | — | 200 stream | Authorizes the blob's **parent record** through the policy scope, then streams. An internal-note attachment 404s as a consequence of that lookup |

**There is no tenant route for internal notes** — not a filtered one, not a 403 one, none. **There is no
`destroy`** anywhere: a ticket is closed, never deleted.

Message payload: `{id, author_role: 'customer'|'lynomia', author_name, body, attachments:[{id, filename,
byte_size, content_type}], created_at}`. `author_name` is the literal **"Lynomia Support"** for every operator
message; the individual's name is never serialized. **Attachment objects carry no `url`** (§B-10).

Ticket payload keys: `id, reference, reference_number, subject, description, category, status, priority,
reporter_name, unread, message_count, attachment_count, last_activity_at, last_operator_message_at, resolved_at,
closed_at, created_at, updated_at`. Timestamps are unix-second integers.
**Absent by construction**: `assignee_id`, `assignee_name`, the whole `sla` object, every `*_due_at`, every
`*_breached_at`, `sla_paused_*`, `plan_*_at_creation`, `subscription_status_at_creation`, `internal_notes`.

`unread` is derived, not stored: `last_operator_message_at.present? && (customer_last_viewed_at.nil? ||
last_operator_message_at > customer_last_viewed_at)`.

Base controller `Api::V1::Accounts::PlatformSupport::BaseController < Api::V1::Accounts::BaseController`:
`rescue_from CustomExceptions::PlatformTickets::Base` → `exception.to_hash` with its 422 status; `ticket_scope =
policy_scope(::PlatformSupport::Ticket.all)` — the **unscoped** relation, because the Pundit Scope supplies the
account predicate itself; **no feature gate**; billing-exempt (§3).

Error contract: not yours or nonexistent → **404** `{"error":"Resource not found"}`; invalid category/status/
priority/filter → 422; reply to a closed ticket → 422 *"This ticket is closed. Open a new one."*; attachment too
large or of a rejected type → 422 naming the limit and the accepted types; rate limited → 429; administratively
suspended account → 401 from the existing guard, untouched.

### Staff — `/super_admin/platform_support/`
Server-rendered ERB inside the existing Super Admin shell, **not** Administrate, following the Operations V2
precedent exactly. Reads are GET; **every mutation is POST or PATCH, never GET**. Routes live in the same
`config/routes/platform_support.rb` drawer, in a `namespace :super_admin` block.

| Verb | Path | Purpose |
|---|---|---|
| GET | `/super_admin/platform_support` | The queue: filters (status, priority, category, assignee, account, `q`), Kaminari pagination, default order `(status, priority, last_activity_at DESC)` |
| GET | `/super_admin/platform_support/tickets/:id` | One ticket: public thread, internal notes, events, account + billing context, SLA state, attachments |
| POST | `/super_admin/platform_support/tickets/:id/reply` | A public reply (becomes an M4 row authored by the acting agent) |
| POST | `/super_admin/platform_support/tickets/:id/note` | An internal note (M5) |
| PATCH | `/super_admin/platform_support/tickets/:id/status` | A status transition |
| PATCH | `/super_admin/platform_support/tickets/:id/triage` | Priority and/or category |
| POST | `/super_admin/platform_support/tickets/:id/assign` | Assign or unassign |
| GET | `/super_admin/platform_support/attachments/:id` | Staff attachment access, authorized per §3 |
| GET/POST/PATCH | `/super_admin/platform_support/agents`, `/sla_policies` | Operator administration of staff rows and SLA policy records |

---

## 3. Authorization contract

### Tenant side
| Rule | Behaviour |
|---|---|
| **D-1 visibility** | An account **administrator** sees every Platform Support ticket whose `account_id` is their account. An **agent** sees only tickets where `reporter_id` is their own user id. A **custom-role holder is treated exactly as an agent** — V1 adds **no** `CustomRole::PERMISSIONS` entry, and the policy file says why in a header comment |
| **Scoping lives in the policy** | `PlatformSupport::TicketPolicy::Scope#resolve` applies `where(account_id: account.id)` **itself**, then the role narrowing. Callers pass the unscoped relation. This is deliberately unlike `Support::TicketPolicy::Scope#resolve`, which carries no account predicate and depends on two callers remembering |
| **Fail closed** | A nil `account`, a nil `account_user`, or a role the policy does not recognise resolves to `none`, never to `all` |
| **404, never 403** | Every member record is fetched **through the policy scope**, so an invisible ticket raises `RecordNotFound` and the existence of another account's ticket never leaks. (Note `Pundit::NotAuthorizedError` renders 401 here, not 403 — one more reason the scope, not a `raise`, is the mechanism) |
| **Cross-account ids** | Every incoming foreign id (`attachment_ids`, a ticket id in a nested route) is resolved through the account-scoped relation before it is written or read |
| **Billing** | A **billing-locked** account reaches Platform Support: the desk is exempt from `Billing::AccessGuard`, declared once on the module's base controller. A customer whose plan excludes paid modules must still be able to complain about it, and the desk is never feature-gated or sold |
| **Administrative suspension** | **No exemption, ever.** The existing suspension guard is **not edited by this module** — that edit was removed from the plan, not deferred. A spam/security suspension never gains an automatic bypass |
| **Account deletion** | `account_id` goes NULL; `account_name_at_creation` preserves attribution; the tenant can no longer read an orphaned ticket (the policy scope requires a non-nil match), while staff and audit history survive |

### Staff side
| Rule | Behaviour |
|---|---|
| Authentication | `authenticate_super_admin!`, inherited from `SuperAdmin::ApplicationController`. No second authentication call, no Pundit |
| **The one extra layer Operations does not have** | A `before_action` resolves the acting `PlatformSupport::Agent` for `current_super_admin` and **refuses when there is none or it is inactive**. Being a Super Admin is not being support staff |
| Assignment | **Only** a `PlatformSupport::Agent` row may be an assignee. A `User` id can never be written to `assignee_id` (FK to `platform_support_agents`), and **no `AccountUser` membership is ever created for Lynomia staff** |
| Lead capability | A `lead` may reassign another agent's ticket and edit SLA policies; an `agent` may not |
| Record lookup | `find_by(id:)` and a redirect with an alert when nil — never `find!` — matching the Operations mutation pattern |
| Internal notes | Reachable only on this surface. No tenant route, no tenant serializer key, no association traversable from a tenant-visible object |

### Attachments (the first authorized download in this repository)
1. Every blob is reached **only** through `GET …/platform_support/attachments/:id` (tenant) or the staff
   equivalent — never a `rails_blob_path`, never a signed id in a payload. Blob URLs do not expire here, so a
   leaked signed id is a permanent leak.
2. The controller authorizes the **parent record** (message or note) through the policy scope, then streams.
3. An internal-note attachment therefore 404s for every tenant request as a *consequence of the parent lookup*,
   not as a special case anybody has to remember.
4. Required proofs (§10): same-account permitted user downloads; another account cannot; an agent who did not
   create the ticket cannot; staff with an agent row can; guessing a blob id or signed id does not bypass;
   internal-note attachments never become tenant-visible.

### Audit
Explicit writes only. **The `audited` macro is never declared on a `platform_support_*` model** — the gem's
Sweeper resolves the actor through Devise's `:user` scope while a Super Admin authenticates under
`:super_admin`, so attribution would be nil or wrong. Copy `Operations::SignalLifecycle`:
`Custom::AuditLog.create!(auditable:, user: @actor, action:, comment:, audited_changes:)` with **`associated`
deliberately absent**, so operator activity is filed installation-wide and never published to the customer's
audit page. `comment` is a dotted event name `platform_support.<event>`. `audited_changes` carries ids, enum
values, counts, timestamps and the reference string **only** — never a body, never a provider payload, never a
credential. The actor is a required keyword and the service refuses without one; the actor's display name is
snapshotted with the same three-way `try` chain the audit model itself uses. These writes are **not**
best-effort: no `rescue`.

---

## 4. Shared statuses, categories and priorities

**Statuses** — the approved six, integer-backed, in this order because the partial indexes depend on `status < 4`:

```ruby
enum :status, { open: 0, in_progress: 1, waiting_on_customer: 2, waiting_on_lynomia: 3, resolved: 4, closed: 5 }
OPEN_STATUSES   = %w[open in_progress waiting_on_customer waiting_on_lynomia].freeze
CLOSED_STATUSES = %w[resolved closed].freeze
```

Transitions: a new ticket is always `open`. Staff may move a ticket to any status. A customer may only
`resolved → closed`, and a customer reply on a `resolved` ticket **reopens** it (`open`) and restarts the
resolution clock. A reply to a `closed` ticket is refused with 422 — the customer opens a new one. Nothing
auto-closes in V1.

**Priorities** — `{low: 0, medium: 1, high: 2, urgent: 3}`: the same four, in the same order, as `Conversation`
and `Support::Ticket`, so an operator learns one scale. A customer may set and change priority; it is a request,
not a promise, and staff may re-triage it.

**Categories** — the approved eleven, a frozen string allow-list with `'other'` as the default:

```ruby
CATEGORIES = %w[billing account_access channel_connection whatsapp commerce campaigns automation
                performance data_export bug other].freeze
```

A value outside the list is 422 at the request boundary, never coerced.

---

## 5. Notification integration contract

**D-6's security precondition is met, so the bell ships in V1 — through one explicitly authorized actor path,
and nothing wider.** The derived per-ticket `unread` flag (§2) and the sidebar leaf badge stay as well: they are
free, they are account-scoped by construction, and they do not depend on the feed.

### What is added, exactly
1. `app/models/notification.rb` — `NOTIFICATION_TYPES` gains `platform_support_reply: 9`; `PRIMARY_ACTORS` gains
   `'PlatformSupport::Ticket'`. **Both are unavoidable OSS core edits**: the class carries no `prepend_mod_with`
   and a prepended module cannot replace a constant the class defines and two other files reference by name.
   `NOTIFICATION_TYPES` is not cosmetic — `NotificationSetting` derives its `email_*?`/`push_*?` predicates from it.
2. `custom/app/services/notifications/conversation_visibility.rb` — `VISIBLE_ACTOR_TYPES` gains the same string
   **and** the type gets its **own branch** in `narrow` and in `permits?`. A longer list alone is a defect: the
   conversation subselect is applied to the whole allowed set, so a ticket id would be matched against
   conversation ids.
3. `permits?`'s ticket branch answers in this order, mirroring the conversation branch: actor type on the
   allow-list → `notification.account_id == @account.id` → the ticket exists, its `account_id` equals the
   account **and is not nil** → `PlatformSupport::TicketPolicy#show?`. Any failure is `false`.
4. `narrow` dispatches by type: conversation rows keep the existing subselect; ticket rows are narrowed by
   `platform_support_tickets` the policy scope resolves. Rows of an unknown type stay **excluded**.
5. The two cross-type collisions are fixed as part of this work, because a second actor type makes them
   destructive: `Notification::RemoveDuplicateNotificationJob` must key on `(primary_actor_type,
   primary_actor_id)` **and** account; the front-end store must do the same instead of assuming
   `primary_actor_id` is unique.
6. The Inbox feed must render a Platform Support row without destructuring a conversation: either a card variant
   that routes to the ticket, or exclusion of the type from the feed list while the count still includes it. The
   fail-safe is absolute — **no crash, no wrong route, no row shown to the wrong account**.

### What is deliberately **not** added
`notification_title_map` and `push_message_body` are left without an entry: both return `''` for an unmapped
type, which is the fail-safe, and the thread title belongs on the Platform Support surface rather than in a
conversation-shaped renderer. No tenant preferences toggle (the type is in-app only). **Never** routed through
`AgentNotifications::ConversationNotificationsMailer` — Platform Support email goes through its own mailer.

### Triggers
Exactly one row type in V1: `platform_support_reply`, written **once per operator public reply, per eligible
recipient**. Nothing else gets a row: not ticket creation, not assignment, not a priority or category change,
not any SLA event, not `waiting_on_lynomia`, and **never an internal note**.

### Required proofs (§10)
The intended actor is explicitly allowed; an account mismatch is denied; an unknown actor type is still denied;
a tenant cannot see another account's Platform Support notification; an internal note never produces a
tenant-visible notification; and one operator reply produces no duplicate storm. Plus: the existing notification
suites still pass unchanged.

---

## 6. Operations integration seams

**Four touch-points, and a hard boundary.**

| Seam | What happens | File |
|---|---|---|
| Account 360 → Platform Support | `Operations::AccountSnapshot#support` gains one key: an open-ticket count and a link to the staff queue filtered by that account. The method's own comment pre-authorises exactly this and states *"no other file changes"*. It must be a **grouped count**, one or two statements, flat in the account's size | `custom/app/services/operations/account_snapshot.rb` (Agent 1), `app/views/super_admin/operations/account.html.erb` (Agent 2) |
| Platform Support → Account 360 | The staff ticket detail links to `/super_admin/operations/account?id=…` and shows the operational context it already renders. Read-only | Agent 2 |
| Billing context | The staff ticket detail reads the account's plan and subscription state through the existing billing readers. No new billing UI | Agent 2 |
| Staff desk nav | One `nav_item` partial in the lower operator block **plus** the `_navigation.html.erb:40` exclusion-array entry, in the same commit (§B-11) | Agent 2 |

**The boundary.** A Platform Support ticket is a customer/support workflow; an `Operations::Signal` is an
operational fact. They are not the same object and V1 creates no link between them:

- **No support ticket becomes an `Operations::Signal`.** `SignalRecorder` upserts on an open identity, raises
  severity monotonically and swallows every error — all three wrong for a human-raised ticket. `Signal`
  validates `source`, `signal` and `subject_type` against three frozen allow-lists, and Platform Support is in
  none of them. It stays out of them.
- **No second operational console**, no Platform Support tab on the Operations tab bar (a hard-coded six-entry
  array), no Platform Support rows in the attention queue, the Issues feed or the incident timeline.
- **No typed signal ↔ ticket link in V1** (§B-8). `Operations::Overview`'s `unlinked` metric reads
  `support_ticket_id IS NULL` and means "with no support case"; a second link column would silently change what
  that number means.
- **`Operations::CaseBridge` is not touched.** It opens a tenant `Support::Ticket` for an operational signal and
  continues to do exactly that.

---

## 7. Documentation integration seams

**One documentation system. Platform Support links into it and adds to it; it does not build another.**

| Element | Contract |
|---|---|
| The registry | `app/javascript/dashboard/helper/documentationLinks.js` exports the frozen `DOC_ARTICLES` map of product moment → **stable article slug**. A Vue file never carries a URL. Platform Support adds its keys there and renders them through `components-next/docs-link/DocsLink.vue` (`articleKey`, `label`) |
| Branded installations | The destination is the installation's own `DOCUMENTATION_URL`; one that has configured none yields an empty string and the caller renders **no link at all**. Platform Support surfaces must behave the same way — no link, never a broken one |
| New articles | `custom/db/documentation/{en,ar}/<section>/<slug>.md`, front matter `title`, `description`, `position`, `tags`, `seo_description`. **No manifest edit is needed** when the section already exists: `manifest.yml` declares sections, and `Documentation::ContentSeeder` globs each section directory |
| V1 adds exactly one article | `troubleshooting/contact-lynomia-support.md`, **EN and AR in the same commit** — what Platform Support is, how to raise a ticket, what each status means, what Lynomia will and will not answer there, and that billing-locked accounts can still reach it. The `troubleshooting` section is where a stuck reader already is |
| Validators that must stay green | `rake lynomia:docs:seo_audit` → **exit 0, 0 errors**. That means: a `description` or `seo_description` of **50–160 characters**, an AR sibling so the hreflang set is reciprocal and has an x-default, a unique slug, and a buildable breadcrumb. A `title` over 60 characters is a warning, not an error — avoid it anyway |
| Existing articles to link, not duplicate | The tenant surface links to the relevant existing slugs rather than restating them (`troubleshooting`, and the topic articles for the category the customer picked) |
| What must not happen | No second knowledge base, no tenant-authored help centre, no article added outside this pipeline, no hard-coded documentation URL anywhere in the module |

---

## 8. File ownership for the three implementation agents

Exactly one agent may **write** each path. A path that appears nowhere below is owned by nobody and must not be
touched. Each agent works in its own git worktree, on its own branch, against its own database; the orchestrator
performs every merge.

### Agent 1 — core backend · branch `claude/ps-a1-backend` · worktree `/tmp/ps-a1` · db `ps_a1`
```
db/migrate/*_platform_support_*.rb            db/schema.rb
custom/app/models/platform_support/**
custom/app/services/platform_support/*.rb     (TOP LEVEL ONLY — sla/ and notifications/ belong to Agent 3)
custom/app/policies/platform_support/**
custom/app/controllers/api/v1/accounts/platform_support/**   EXCEPT attachments_controller.rb
app/views/api/v1/accounts/platform_support/**                (jbuilder)
config/routes/platform_support.rb             (BOTH the tenant and the super_admin blocks, per §2)
config/routes.rb                              (the single `draw :platform_support` line)
lib/custom_exceptions/platform_tickets.rb
config/locales/en.yml                          (backend strings only; English only)
custom/app/services/operations/account_snapshot.rb           (the one additive key, §6)
spec/models/platform_support/**  spec/services/platform_support/*_spec.rb  spec/policies/platform_support/**
spec/requests/platform_support/tenant_api_*_spec.rb
```

### Agent 2 — customer and staff surfaces · branch `claude/ps-a2-surfaces` · worktree `/tmp/ps-a2` · db `ps_a2`
```
app/javascript/dashboard/routes/dashboard/help/**             (new: help.routes.js + pages + components)
app/javascript/dashboard/routes/dashboard/dashboard.routes.js (one import + one spread)
app/javascript/dashboard/components-next/sidebar/Sidebar.vue  (two entries inside the existing navigableEntries array)
app/javascript/dashboard/i18n/locale/en/platformSupport.json  + ar/platformSupport.json + the two index files
app/javascript/dashboard/helper/documentationLinks.js         (the new keys)
custom/db/documentation/{en,ar}/troubleshooting/contact-lynomia-support.md
custom/app/controllers/super_admin/platform_support_controller.rb  (+ any sibling staff controller)
app/views/super_admin/platform_support/**
app/views/super_admin/application/_navigation.html.erb        (the nav item AND the :40 exclusion entry)
app/views/super_admin/operations/account.html.erb             (render the count Agent 1 adds)
spec/controllers/super_admin/platform_support*_spec.rb
app/javascript/dashboard/routes/dashboard/help/**/specs/**    (vitest)
```
**Must not touch**: anything under `notifications` (model, service, store, feed), any migration, any policy, any
file owned by Agent 1 or 3.

### Agent 3 — SLA, notifications, security and hardening · branch `claude/ps-a3-hardening` · worktree `/tmp/ps-a3` · db `ps_a3`
```
custom/app/services/platform_support/sla/**
custom/app/services/platform_support/notifications/**
custom/app/jobs/platform_support/**
custom/app/mailers/platform_support/**   app/views/platform_support_mailer/**
custom/app/controllers/api/v1/accounts/platform_support/attachments_controller.rb   (THE ONE FILE)
app/models/notification.rb                                    (NOTIFICATION_TYPES + PRIMARY_ACTORS)
custom/app/services/notifications/conversation_visibility.rb  (the type-dispatched branches)
app/jobs/notification/remove_duplicate_notification_job.rb
app/javascript/dashboard/store/modules/notifications/**
app/javascript/dashboard/components-next/inbox/**             (ONLY what §5.6 requires)
config/initializers/rack_attack.rb
spec/services/platform_support/sla/**  spec/requests/platform_support/security/**
spec/requests/platform_support/notifications_spec.rb  spec/jobs/platform_support/**
docs/platform-support/13-uat-and-rollout.md
```
**Must not touch**: migrations, the models, the tenant ticket/message controllers, the UI surfaces.

### Orchestrator
`docs/platform-support/12-refresh-against-product-refinement.md`, every merge, the integration fixes, and any
file two agents would otherwise contend for.

### Parallel-development rules
1. The contracts in §1–§7 are frozen. **No agent may invent an API, a column, a status value, a route name or a
   serializer key** because another agent has not finished. If a contract is wrong, it comes back to the
   orchestrator and is changed here first.
2. Mocks and stubs are allowed **only** against this contract, must be named `*_stub`/`*_mock` or declared in the
   spec that uses them, and must be listed in the agent's final report so integration can reconcile them.
3. Every agent runs its own suites in its own database before reporting. No agent merges anything.
4. Nothing existing is modified except the files named above, and each such edit is additive.

---

## 9. Collision avoidance — the exact names, frozen

`PlatformSupport` / `platform_support` is free: a grep over `app custom lib config spec` returns nothing. The
hazard is not the namespace, it is the *tenant* Support desk sitting beside it. Every row below is **must not
take → take instead**.

| Kind | Taken by the tenant desk | Platform Support takes |
|---|---|---|
| Tables | `support_tickets`, `support_ticket_events`, `sla_policies` | `platform_support_tickets`, `platform_support_messages`, `platform_support_internal_notes`, `platform_support_events`, `platform_support_agents`, `platform_support_sla_policies` |
| Ruby namespace | `Support::`, `CustomExceptions::Tickets` | `PlatformSupport::`, **`CustomExceptions::PlatformTickets`** |
| Policy | `Support::TicketPolicy` | `PlatformSupport::TicketPolicy` + a separate staff-side authorizer |
| Route drawer / API path | `config/routes/support.rb`, `/api/v1/accounts/:id/support/**` | `config/routes/platform_support.rb`, `/api/v1/accounts/:id/platform_support/**`, and `namespace :super_admin` modelled on `config/routes/operations.rb` |
| Serializers | `custom/app/views/api/v1/accounts/support/**` | `app/views/api/v1/accounts/platform_support/**` |
| Frontend routes | path `accounts/:accountId/support/cases`, names `support_tickets_index` / `support_tickets_show` | path `accounts/:accountId/help/tickets[/new|/:ticketId]`, names **`platform_support_tickets_index`**, **`platform_support_tickets_new`**, **`platform_support_tickets_show`** |
| Sidebar entry names | `Support`, `Settings Support`, `Analytics Tickets`, group `HelpAndSupport` with `Documentation` and `ContactSupport` | new children **`PlatformSupportMyTickets`** and **`PlatformSupportNewTicket`** inside the existing `HelpAndSupport` group |
| Frontend i18n | `SUPPORT_TICKETS`, `SLA`, `HELP_CENTER`, `SIDEBAR.HELP_AND_SUPPORT` | a new `platformSupport.json` with the single root key **`PLATFORM_SUPPORT`**, imported in both `en/index.js` and `ar/index.js` |
| Backend i18n | `errors.tickets.*`, `super_admin.operations.*` | `errors.platform_support.*`, `super_admin.platform_support.*` |
| Reference series | prefix `TCK`, 6 digits, **per-account** uniqueness, advisory-lock namespace `hashtext('support_ticket…')` | prefix **`LYN`**, 6 digits, **global** uniqueness, advisory-lock namespace `hashtext('platform_support_reference')` |
| Feature gate | `lynomia_support_tickets` gates the tenant desk | **none.** Platform Support is never gated and never sold: a customer who did not buy the tenant ticketing module must still be able to raise a ticket with Lynomia |
| Permission string | `support_ticket_manage` | **none.** No new `CustomRole::PERMISSIONS` member; staff authority is `platform_support_agents.role` (`agent` \| `lead`) |
| Throttles | the path regex, throttle name and ENV at `config/initializers/rack_attack.rb:381-386` | its own distinct throttle name and path regex |
| Labels | `Labelable` writes into the globally-unique `tags` table | Platform Support does **not** use `Labelable` and adds no tags |
| ActiveStorage attachment names | — | `platform_support_message_files`, `platform_support_note_files` |

**`CustomExceptions::PlatformTickets`, not `CustomExceptions::PlatformSupport`**, and the reason is recorded in
this repository: `lib/custom_exceptions/tickets.rb:4-6` explains that naming an exception module after a
top-level domain namespace shadows it, so a `PlatformSupport::Ticket` reference *inside* `CustomExceptions`
would resolve to the wrong constant. The two refresh investigations disagreed here; this is the resolution.

### Why `Support::Ticket` still cannot be used — re-verified at this baseline
1. `custom/app/models/support/ticket.rb:146-151` — an assignee must satisfy `AccountUser.exists?(account_id:,
   user_id:)`. A Lynomia staff member could only be assigned by **becoming a member of the customer's account**,
   which is the one thing this product must never do.
2. `custom/app/policies/support/ticket_policy.rb:21,24-26` — any tenant `administrator?` gets `manage_all?`, and
   `update? == show?`. The customer could edit Lynomia's own rows.
3. `db/schema.rb:1798,2042` — `support_tickets.account_id` is NOT NULL with `on_delete: :cascade`. Every row is
   owned by, and dies with, one tenant account.
4. There is **no staff-private note**: notes are `support_ticket_events` rows whose `body` is serialized to
   every tenant member who can `show?` the ticket.
5. `audited associated_with: :account` (`ticket.rb:23`) would publish Lynomia staff actions into the customer's
   own audit log.

Nothing in that list is superseded. `Operations::CaseBridge` keeps creating tenant `Support::Ticket` rows for
operational signals, untouched, and `Support::Ticket::SOURCE_TYPES` is not widened.

---

## 10. The proofs the final combined gate must contain

Not a wish list: each item below is a test that must exist and pass before this module may be proposed for merge.

**Isolation and authorization** — account isolation; cross-account IDOR on every member route (ticket, messages,
events, mark_viewed, attachment); an administrator sees every ticket of their account; a normal agent sees only
their own; a custom-role holder is treated exactly as an agent; a nil/unknown role resolves to `none`; 404 (not
403) for a ticket that is not yours; staff authority requires an active `PlatformSupport::Agent` row; a Super
Admin without one is refused; only an agent row can be an assignee; no `AccountUser` is ever created for staff.

**Internal-note secrecy** — no tenant route renders a note; no tenant serializer key exposes one; a note's
attachment 404s for every tenant request; an internal note produces no tenant-visible event and no notification.

**Attachments** — same-account permitted user may download; another account may not; an agent who did not create
the ticket may not; staff with an agent row may; guessing a blob id or a signed id does not bypass; no serializer
emits a blob URL.

**Domain** — the reference allocator under genuine concurrency (parallel transactions, no duplicate, no gap
claim); assignment; every status transition including customer-reply-reopens-resolved and reply-to-closed-is-422;
priority and category validation at the boundary; the 11-category and 6-status vocabularies.

**Commercial and lifecycle** — a billing-locked account can use the desk; an administratively suspended account
cannot (and that guard is unmodified); account deletion nulls `account_id`, keeps the name snapshot, keeps staff
and audit history, and makes the orphan unreadable by the tenant.

**Audit** — the actor is the real Super Admin; `associated` is nil so no row reaches the customer's audit page;
no body, payload or credential in `audited_changes`; a tenant administrator reading their own audit log never
sees a Platform Support row.

**Sessions** — a co-resident tenant session and Super Admin session in one browser do not bleed: the tenant API
never answers staff-only data, and the staff desk never authorizes through the tenant session.

**Notifications** — the six proofs in §5, plus the existing notification suites unchanged.

**SLA** — calendar-time arithmetic, pause/resume on `waiting_on_customer`, policy resolution by
`billing_plan_id` with the default row as fallback, and a policy with no threshold producing no promise. **No
production target values.** Test fixtures use obviously synthetic numbers.

**Rate limits and validation** — the throttle returns 429 and does not leak; every endpoint validates its params
at the boundary and returns 422 rather than reaching a model.

**Product surface** — EN, AR and RTL on every tenant screen; the navigation entry appears for administrator,
agent and custom-role holders and routes correctly; the staff desk renders inside the Super Admin shell;
Operations Account 360 shows the count and links both ways; contextual-help links resolve, and render nothing at
all when the installation has no `DOCUMENTATION_URL`.

**Performance** — the tenant list and the staff queue are flat in query count as tickets grow (the existing
`count_queries` idiom); no provider or external API call while rendering a ticket row; the staff queue paginates
for real.

**Secrets** — no credential, provider payload or internal note text in any tenant response, log line, audit row
or event metadata.

---

## 11. Owner decisions still required (and what happens until they arrive)

| # | Decision | Until then |
|---|---|---|
| 1 | **SLA target values** per plan, in calendar hours | No policy rows are seeded. The engine resolves no policy, promises nothing, and the staff desk shows "No SLA policy applies" rather than inventing a target |
| 2 | **The Lynomia support email alias** | No operator email is sent. The staff desk states that no support alias is configured; nothing falls back to an invented address |
| 3 | **Who the first `PlatformSupport::Agent` rows are** | No rows are seeded. The desk refuses staff actions until an operator creates an agent, which is the correct fail-closed behaviour |
| 4 | **The pilot account** | Account 21 is untouched. No pilot data, no fixtures against a real account |
| 5 | Whether the in-app bell ships in V1 or waits | Built per §5 with all six proofs, because the brief asks for it explicitly; it can be switched off by not writing rows if the owner prefers to wait |

---

## 12. Implementation sequence

1. **Agent 1** builds the domain, migrations, tenant API, policies and audit against §1–§3.
2. **Agent 2** builds the tenant and staff surfaces against §2's contract, with stubs only where Agent 1's
   endpoints do not exist yet.
3. **Agent 3** builds the SLA engine, the notification path, the attachment authorization, the throttles and the
   security suite against §1–§6.
4. The **orchestrator** integrates in that order, reconciles every stub, then runs the gate in §10. Agents do not
   merge. Nothing is deployed. Nothing merges into `lynomia-custom` until the gate passes and the owner approves.
