---
agent: 048
scope: Platform Support Desk (tenant + staff surfaces, lifecycle, SLA engine, attachments, notes, email, audit, bootstrap) and the Super Admin / Operations / billing console
confidence: high
---

Read against `claude/documentation-v2`. Every citation below was opened; where a prior design document and the
code disagree, §10 names both sides. Nothing was run — no `rails`, no `rake`, no database, no deploy. Account 21,
real agent rows and real SLA settings were not touched.

## 1. What the feature is

Two products share this report because they share one surface: Lynomia's own Super Admin console.

**(a) The Platform Support Desk** is the vendor help desk: the channel on which a Lynomia *customer* complains
to *Lynomia*. It is deliberately not the tenant helpdesk beside it. The tenant desk (`Support::Ticket`,
`support_tickets`) is an account's own team working its own end users' cases; this one is Lynomia's engineers
answering the account. The two were kept apart at the table, namespace, route, policy, reference-series,
i18n-root and sidebar level, and `docs/platform-support/12-refresh-against-product-refinement.md:423-446` is the
frozen collision table that did it. Five reasons `Support::Ticket` could not be reused are re-verified in that
document's §9 and still hold in code: an assignee must be an `AccountUser` of the customer's account
(`custom/app/models/support/ticket.rb:146-151`), any tenant administrator gets `manage_all?`
(`custom/app/policies/support/ticket_policy.rb:21,24-26`), `support_tickets.account_id` is NOT NULL and
cascades, there is no staff-private note, and `audited associated_with: :account` would publish Lynomia's own
staff actions into the customer's audit log.

Six tables, no change to any existing table: `platform_support_agents`, `platform_support_sla_policies`,
`platform_support_tickets`, `platform_support_messages`, `platform_support_internal_notes`,
`platform_support_events`. A ticket carries a globally unique integer `reference_number`, rendered as `LYN-000123`
by `custom/app/models/platform_support/ticket.rb:90-92`; the prefix and padding are never in the column. Secrecy
is structural rather than predicated: an internal note is a **separate table**
(`custom/app/models/platform_support/internal_note.rb`), not a visibility flag on a message, and the event feed
the customer reads is a positive 7-of-18 allow-list (`custom/app/models/platform_support/event.rb:21-27`).

**(b) The Super Admin console** is the operator surface around it: the Administrate shell plus three
hand-written non-Administrate consoles — the Operations Control Center
(`custom/app/controllers/super_admin/operations_controller.rb`), the Platform Support desk, and billing
plan/subscription management (`custom/app/controllers/super_admin/billing_subscriptions_controller.rb`).
Operations reads the product's own records and the `Operations::Signal` rows the product writes about itself;
`custom/app/controllers/super_admin/operations_controller.rb:1-13` states plainly that it is not a second
Grafana. Billing holds plans, subscriptions, trials, manual plan grants, per-account entitlement overrides, and
the usage limits that gate agent/inbox/store creation.

**One naming hazard for documentation.** The same desk is called four things: the namespace is
`PlatformSupport`, the Super Admin nav label is **"Customer Support"**
(`app/views/super_admin/application/_navigation.html.erb:68`), the queue's own heading is **"Customer support"**
(`app/views/super_admin/platform_support/show.html.erb:15-19`), and the tenant finds it under **Help & Support →
My tickets** (`app/javascript/dashboard/i18n/locale/en/platformSupport.json` `PLATFORM_SUPPORT.SIDEBAR.MY_TICKETS`).
Any article must pick the user's words — the tenant never sees the phrase "Platform Support".

### The lifecycle, in one place

Six statuses, integer-backed, ordered so the partial indexes can say `status < 4`
(`custom/app/models/platform_support/ticket.rb:26-31`): `open(0) in_progress(1) waiting_on_customer(2)
waiting_on_lynomia(3) resolved(4) closed(5)`. Eleven categories, frozen, `other` the default
(`ticket.rb:38-39`). Four priorities, the same scale as `Conversation` (`ticket.rb:28`).

| Who | May move a ticket | Mechanism |
|---|---|---|
| Staff | to **any** status | `custom/app/controllers/super_admin/platform_support_actions_controller.rb:50-59` → `TicketTransition` |
| Customer | **only** `resolved → closed` | `custom/app/services/platform_support/status_transition.rb:17` (`CUSTOMER_ALLOWED`), enforced at the request boundary, `tickets_controller.rb:82-86` |
| Customer, by replying | a reply on `resolved` **reopens** to `open` | `custom/app/services/platform_support/message_creation.rb:75-83` |
| Anyone | a reply on `closed` is **refused 422** | `message_creation.rb:37` |

Nothing auto-closes in V1 (`status_transition.rb:12-14`). A reopen clears `resolved_at`, `closed_at` and
`resolution_breached_at` and restarts the resolution clock — both halves, because dropping either leaves a
permanent false breach that the five-minute sweep stamps minutes after the work restarted
(`custom/app/services/platform_support/ticket_transition.rb:171-200`).

### The SLA engine

Four objects, and not one target value among them.

| Object | Answers | File |
|---|---|---|
| `Sla::PolicyResolver` | which policy governs a new ticket: the account's `billing_plan_id` row, then the single `billing_plan_id IS NULL` installation default, then **nil** | `custom/app/services/platform_support/sla/policy_resolver.rb:28-33` |
| `Sla::Clock` | calendar-time arithmetic: `apply`, `restart_resolution`, `sync_pause`, `record_first_response` | `custom/app/services/platform_support/sla/clock.rb` |
| `Sla::State` | what a surface may *say* — `governed?`, `*_promised?`, `*_breached?`, `paused?`, `resolved_late?` | `custom/app/services/platform_support/sla/state.rb` |
| `Sla::Sweeper` | records the two breaches decided against the desk, once | `custom/app/services/platform_support/sla/sweeper.rb` |

Two clocks, not three: "next response" and the 75 %-of-window warning are both cut, because the schema has no
column and the 18-type event allow-list has no type for them (`clock.rb:10-14`). Calendar time, not business
hours, because the product's working-hours calculator is inbox-scoped end to end and this desk has no inbox
(`clock.rb:3-8`); both surfaces say so out loud (`app/views/super_admin/platform_support/_sla.html.erb:92-97`).
Resolution is measured from `created_at`, not from the end of the creating transaction — the promise starts when
the customer asked (`custom/app/services/platform_support/ticket_creation.rb:89-95`).

**Pause**: exactly one status pauses, `waiting_on_customer` (`clock.rb:35`). `waiting_on_lynomia` pauses nothing
— waiting on ourselves is our own delay. `resume` moves every outstanding due time forward by the stopped
interval and accumulates `sla_paused_seconds`, so a resolution-time average is not silently inflated by customer
wait (`clock.rb:78-88`). A comparison made *during* a pause credits the open pause through `#effective_due`
(`clock.rb:114-122`).

**Breach**: the sweeper runs every five minutes (`config/schedule.yml:105-108`, queue `housekeeping`,
`custom/app/jobs/platform_support/sla_sweep_job.rb`). It is idempotent by construction, not by a guard —
stamping the breach column removes the row from the partial-index predicate (`sweeper.rb:15-17`). It filters
`sla_paused_at IS NULL` and `sla_policy_id IS NOT NULL` in SQL so it cannot disagree with what `State#governed?`
renders (`sweeper.rb:59-78`). It writes an event and emails the desk, and deliberately writes **no** audit row
(a sweep has no operator actor) and **no** notification row (`sweeper.rb:30-33`). A breach is written once and
never un-written; only a reopen clears the resolution breach.

**Met** is decided at reply time by the clock, never by the sweep, comparing message time against due time
(`clock.rb:94-105`), and the outcome event is written by whoever decided it (`message_creation.rb:109-123`). A
first response against no promise records nothing — a `met` event against no target would read as a target that
existed and was hit. `State#resolved_late?` makes the comparison the sweep would have made for a ticket resolved
after its target but never swept (`state.rb:45-53`).

### Reference numbers, attachments, notes, email, audit

**Reference allocation** takes `pg_advisory_xact_lock(hashtext('platform_support_reference'), 0)` then
`MAX + 1` inside the creating transaction (`custom/app/services/platform_support/reference_allocator.rb`,
contract at `docs/platform-support/12-refresh-against-product-refinement.md:160-166`). A different lock namespace
from the tenant allocator; no Postgres sequence, because a sequence absent from `db/schema.rb` breaks a fresh
schema load.

**Attachments are the first authorized ActiveStorage download in this repository**, and the header of
`custom/app/controllers/api/v1/accounts/platform_support/attachments_controller.rb:1-39` states why: every other
blob here is served by ActiveStorage's own signed-id redirect with no policy check and no expiry, so a signed
blob URL is a permanent bearer token. No Platform Support serializer emits a URL. Authorization is a **parent
lookup, not a permission check on the blob**: one relation reads "the files attached to the public messages of
the tickets this caller may see" (`attachments_controller.rb:57-67`). An internal note's attachment therefore
404s as a *consequence* — a tenant has exactly one reachable parent type, `PlatformSupport::Message` — with no
`unless note?` for a later reader to delete. Limits: 10 MB per file, 5 files per message, and a seven-entry
content-type allow-list (`custom/app/models/platform_support/message.rb:32-34`).

**Email** is one mailer, two audiences, no shared recipient logic: four customer messages and five operator ones
(`custom/app/mailers/platform_support/ticket_mailer.rb:38-82`). Returning without calling `mail` yields a
`NullMail`, which is the mechanism behind "no alias configured sends no operator email" — nothing queued, no
address invented (`ticket_mailer.rb:23-25,97-114`). It is never routed through
`AgentNotifications::ConversationNotificationsMailer` (`ticket_mailer.rb:8-11`).

**The bell** writes exactly one row type, `platform_support_reply`, once per operator public reply per eligible
recipient, and never for a note, a creation, an assignment or an SLA event
(`custom/app/services/platform_support/notifications/reply_notifier.rb:1-7,33-47`).
`app/models/notification.rb:55,71,84` adds the type, marks it `IN_APP_ONLY_TYPES` (suppressing email and push at
`notification.rb:196`) and adds `'PlatformSupport::Ticket'` to `PRIMARY_ACTORS`;
`custom/app/services/notifications/conversation_visibility.rb:135,164,187-224` gives the type its **own branch**
in both `narrow` and `permits?`, because applying the conversation subselect to the whole allowed set would
compare a ticket id against conversation ids. The Inbox feed excludes the type in the store rather than trying to
render it (`app/javascript/dashboard/store/modules/notifications/helpers.js:20-37`, consumed at
`getters.js:8`): the feed destructures a conversation shape from the list down, so a ticket row would route to
`inbox_view_conversation` with a ticket id in the conversation slot. The badge is unaffected.

**Audit** is explicit writes only. No `audited` macro on any `platform_support_*` model, and
`custom/app/services/platform_support/audit_writer.rb:4-23` gives the reason: the gem's Sweeper resolves its
actor through Devise's `:user` scope while a Super Admin authenticates under `:super_admin`, so a declared macro
would file rows against nobody — or, with a co-resident tenant session, against the *tenant* principal.
`associated` is deliberately absent, so `Custom::AuditLog.for_account` (`custom/app/models/custom/audit_log.rb:26`)
cannot serve an operator row to the customer's own Audit Logs page. `comment` is `platform_support.<event>`;
`audited_changes` carries ids, enum values, counts, timestamps and the reference only. The actor is a required
keyword and the writer refuses without one; there is no `rescue`.

**The bootstrap paradox and its answer.** No `PlatformSupport::Agent` row is seeded and no page can create one:
a page that created agent rows would itself need an agent row to protect it, or be open to every Super Admin —
the distinction the module exists to draw. `lib/tasks/platform_support.rake:25-60` is the whole answer:
`grant_agent` (EMAIL=, optional ROLE=agent|lead, refuses an email that names no `SuperAdmin`), `revoke_agent`
(deactivates, never deletes, and prints how many open tickets stay assigned), `agents` (lists, and says "The
desk refuses every staff action until one is granted"). No audit row is written, because the actor of a shell
command is whoever holds the server.

## 2. Surfaces and routes

### Tenant API — `config/routes/platform_support.rb:30-50`

| Verb | Path | Controller + action | Notes |
|---|---|---|---|
| GET | `/api/v1/accounts/:id/platform_support/tickets` | `tickets_controller.rb:18-22` | filters `status[] category[] priority[] q page per_page`; `meta.counts{open,closed,unread}` |
| GET | `…/tickets/:id` | `tickets_controller.rb:24-26` | numeric id **or** a `LYN-` reference, resolved inside the policy scope (`base_controller.rb:47-53`) |
| POST | `…/tickets` | `tickets_controller.rb:28-35` | 201; description required (`:64-70`) |
| PATCH | `…/tickets/:id` | `tickets_controller.rb:37-43` | accepts `priority`, and `status` only to close a resolved ticket |
| GET/POST | `…/tickets/:id/messages` | `messages_controller.rb:17-29` | public messages only; 50 per page |
| GET | `…/tickets/:id/events` | `events_controller.rb:12-14` | `customer_visible` allow-list applied in the query |
| POST | `…/tickets/:id/mark_viewed` | `tickets_controller.rb:47-50` | POST, not GET, so no prefetch marks replies read |
| GET | `…/platform_support/attachments/:id` | `attachments_controller.rb:48-51` | streams; parent authorized through the policy scope |

No internal-note route of any kind, and no `destroy` anywhere: a ticket is closed, never deleted
(`config/routes/platform_support.rb:28-29`).

Ticket payload: 18 keys, `app/views/api/v1/accounts/platform_support/tickets/_ticket.json.jbuilder`. Absent by
construction: `assignee_id`, `assignee_name`, every `*_due_at` and `*_breached_at`, `sla_paused_*`, the whole
`sla` object, `plan_*_at_creation`, `internal_notes`. `unread` is derived from two columns, not stored
(`custom/app/models/platform_support/ticket.rb:84-87`). Operator messages are authored by the literal
**"Lynomia Support"**; the individual's name is never serialized.

### Tenant UI

| Surface | File |
|---|---|
| Routes `platform_support_tickets_{index,new,show}` under `accounts/:accountId/help/tickets` | `app/javascript/dashboard/routes/dashboard/help/help.routes.js:27-54` |
| Sidebar children `PlatformSupportMyTickets` (with unread badge) and `PlatformSupportNewTicket`, inside the existing `HelpAndSupport` group | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:744-760` |
| Index / New / Detail pages | `app/javascript/dashboard/routes/dashboard/help/pages/PlatformSupport{Index,New,Detail}Page.vue` |
| Components: `AttachmentList`, `AttachmentPicker`, `NewTicketForm`, `ReplyBox`, `StatusChip`, `ThreadEvent`, `ThreadMessage`, `TicketCard`, `TicketListSkeleton` | `…/help/components/` |
| Client vocabulary, tones, limits, page size | `…/help/constants.js` |
| Store + shared unread count | `…/help/platformSupportStore.js:42-98` |
| i18n, one root key `PLATFORM_SUPPORT`, EN + AR | `app/javascript/dashboard/i18n/locale/{en,ar}/platformSupport.json` |

### Staff desk — `config/routes/platform_support.rb:52-80`

Server-rendered ERB inside the Super Admin shell, **not** Administrate, following the Operations V2 precedent.
Two controllers on purpose: reads are GET on `SuperAdmin::PlatformSupportController`, the six decisions are
POST/PATCH on `SuperAdmin::PlatformSupportActionsController`, which **inherits** the acting-agent guard rather
than restating it.

| Verb | Path | Action |
|---|---|---|
| GET | `/super_admin/platform_support` | queue: `platform_support_controller.rb:41-44`, 25/page, order `status, priority DESC, last_activity_at DESC` (`:104-114`) |
| GET | `…/tickets/:id` | detail: `platform_support_controller.rb:47-55` |
| GET | `…/attachments/:id` | `platform_support_controller.rb:63-70`, restricted to this module's two attachment names and two parent types |
| POST | `…/tickets/:id/reply` | `platform_support_actions_controller.rb:20-34` |
| POST | `…/tickets/:id/note` | `:40-48` |
| PATCH | `…/tickets/:id/status` | `:50-59` |
| PATCH | `…/tickets/:id/triage` | `:61-70` |
| POST | `…/tickets/:id/assign` | `:74-76,125-141` |

Views: `app/views/super_admin/platform_support/{show,ticket}.html.erb` plus `_sla`, `_attachments`,
`_status_badge`, `_priority_badge`. The Administrate exclusion entries `"platform_support"` and
`"platform_support_actions"` are in the nav's array at
`app/views/super_admin/application/_navigation.html.erb:47` — omitting either breaks the sidebar on **every**
Super Admin page, because Administrate enumerates every controller under `super_admin/` from the route table.
The nav item is at `:68`.

### Operations Control Center — `config/routes/operations.rb:8-29`

Six tabs (`app/views/super_admin/operations/_tabs.html.erb:7-15`): Overview, Queue, Accounts, Channels, Commerce,
Issues — a hard-coded array, plus `signal` and `account` detail pages outside the bar. Reads are GET; the three
operator decisions (`acknowledge_signal`, `suppress_signal`, `resume_signal`) and `open_case` are POST, each
going through `Operations::SignalLifecycle`, the only writer, which takes an explicit actor and audits
(`operations_controller.rb:70-108`). Fifteen services under `custom/app/services/operations/`. The signal
vocabulary is three frozen allow-lists: 8 sources, 12 signals, 4 subject types
(`custom/app/models/operations/signal.rb:22-41`).

**The Platform Support ↔ Operations seam is two links and one count.** `Operations::AccountSnapshot#support`
gains one key — one grouped count plus the queue path filtered to that account
(`custom/app/services/operations/account_snapshot.rb:168-183`) — and the staff ticket detail links back to
Account 360 and to the billing subscription (`app/views/super_admin/platform_support/ticket.html.erb:268-276`).
Nothing more: no support ticket becomes an `Operations::Signal`, there is no Platform Support tab, no rows in the
attention queue or issue feed, and `Operations::CaseBridge` is untouched
(`docs/platform-support/12-refresh-against-product-refinement.md:296-316`).

### Billing — `config/routes/billing.rb`

| Surface | Routes |
|---|---|
| Super Admin plans (Administrate) + Billing Settings | `:5-10`, `custom/app/controllers/super_admin/billing_plans_controller.rb`, `custom/app/dashboards/billing_plan_dashboard.rb` |
| Super Admin subscriptions: index/show (Administrate) + five POST buttons — `extend_trial`, `grant_plan`, `cancel_subscription`, `grant_override`, `revoke_override` | `:12-20`, `custom/app/controllers/super_admin/billing_subscriptions_controller.rb:10-85`, `custom/app/dashboards/billing_subscription_dashboard.rb` |
| Tenant API | `:27-34` — `show`, `plans`, `entitlements`, `checkout`, `portal`, `change_plan_preview`, `change_plan` |
| Platform API (Platform App token) | `:41-67` |
| Stripe webhook | `:71` |
| Tenant UI | `app/javascript/dashboard/routes/dashboard/settings/billing/` |

Fifteen services under `custom/app/services/billing/`. Entitlements resolve plan + override
(`custom/app/services/billing/entitlements.rb:28-92`); the override surface is per-account and explicitly not a
plan edit, because a plan edit moves every subscriber
(`billing_subscriptions_controller.rb:46-65`). Usage limits are counted in exactly one place and gated under
`account.with_lock` inside the save's own transaction, because the old `count >= limit` read outside any lock let
two concurrent creates both pass (`custom/app/models/billing/resource_limit.rb:8-48`). `Billing::AccessGuard` is
included into `Api::V1::Accounts::BaseController` and answers **402 `subscription_required`** for a locked
account and **422 `plan_limit_reached`** for an agent create over the limit
(`custom/app/controllers/billing/access_guard.rb:21-48`); the browser redirects a 402 to
`/settings/subscription` (`app/javascript/dashboard/helper/billingGuard.js:7-19`).

**Account seeding**: Super Admin → Accounts → Seed enqueues `Internal::SeedAccountJob`
(`app/controllers/super_admin/accounts_controller.rb:65-68` → `app/jobs/internal/seed_account_job.rb` →
`Seeders::AccountSeeder`).

## 3. User-visible states

### Tenant list — `PlatformSupportIndexPage.vue`

| State | What produces it |
|---|---|
| Skeleton | first load only: `isLoading && !hasLoadedOnce` (`:157`) |
| Error banner | any failed list request; server `message` preferred over a raw error (`:69-77,155`) |
| Empty | `hasLoadedOnce && !error && tickets.length === 0` (`:58,160`) — copy distinguishes "no tickets yet" and tells the reader the Inbox is for *their* customers |
| Two groups | Open and Closed sections rendered only when non-empty (`:183,196`) |
| Unread marker | "Lynomia has replied since you last looked", from the derived `unread` flag |
| Pagination | rendered only past one page (`:213`) |

### Tenant detail — `PlatformSupportDetailPage.vue`

Loading skeleton with `aria-busy` (`:194`); a 404 renders `ERROR.NOT_FOUND` — "This ticket does not exist, or it
is not one you can see" (`:64`), which is also what another account's ticket id produces, by design; an
`arrivedUnread` "New reply" marker (`:212`); a per-status sentence telling the customer whose turn it is
(`:238`); the reply box hidden when closed and replaced by `DETAIL.CLOSED_HINT` plus an "Open a new ticket"
action (`:257-267`); on a resolved ticket the reply box warns `REPLY.REOPENS_HINT` — "This ticket is resolved.
Replying reopens it." `mark_viewed` fires on load and after a reply (`:136-174`).

**The sidebar badge is not live.** `usePlatformSupportUnread` refreshes on account switch and `immediate`
(`platformSupportStore.js:82-92`); the index page sets it from `meta.counts.unread` (`IndexPage:100`); the detail
page refreshes it after `mark_viewed` (`DetailPage:139`). There is no polling and no cable subscription for this
badge, so a reply arriving while the customer is elsewhere in the product raises the **bell** (a real
notification row, delivered by the existing notification path) but not the sidebar leaf count until they
navigate. A refresh failure is deliberately silent — the previous number stands rather than a wrong one
(`platformSupportStore.js:66-69`).

### Staff queue — `show.html.erb`

| State | Produced by |
|---|---|
| **"No operator support alias is configured"** yellow banner | `PlatformSupport::SupportAlias.configured?` false (`:27-39`). Today's default state |
| Empty, no filters: "No customer has raised a ticket with Lynomia yet." | `:87-91` |
| Empty, with filters: "No ticket matches these filters. Clear them to see the whole desk." | `:87-91` |
| Account deleted | `ticket.account` nil → the `account_name_at_creation` snapshot plus "account deleted" (`:119-126`) |
| Assignee deactivated | "reassign needed" beside the name; the assignment is kept, never dumped back to Unassigned (`:136-140`) |
| Unassigned | yellow "Unassigned" (`:141-143`) |
| "customer replied last" | the highest-value reading on a vendor desk: `last_customer_message_at` newer than `last_operator_message_at` (`:147-151`) |
| Not an agent | the whole desk redirects to the Super Admin root with an alert (`platform_support_controller.rb:77-84`) |

### SLA, as rendered — `_sla.html.erb`

`governed?` false is the honest **"No SLA policy applies to this ticket, so Lynomia has made no timing
commitment on it. Nothing is late and nothing is on time."** (`:24-29`) — and the partial's own header says this
is the state **every** ticket is in today, so it must look correct rather than broken. The two clocks render
independently: a policy with only one threshold shows "not promised by this policy" on the other
(`:36-38,55-56`), never a dash or a zero. Resolution reads breached / "resolved N late" / "resolved in time" /
"due in N" (`:57-72`). A pause renders as parked, not late (`:76-82`), with the accumulated total beside it. A
calendar-time footnote states that a target spans nights and weekends (`:92-97`).

### Staff ticket detail — `ticket.html.erb`

One chronological list merging public messages, internal notes and events (`:88-130`), because an operator
picking the ticket up reads one story. Two compose boxes, deliberately **not** one form with a visibility
checkbox: the public/internal choice is made by which box you type in, and the note box is yellow, lock-marked
and submits "Save internal note" (`:144-186`). Reference and account are pinned beside the reply box, because
replying to the wrong ticket is the mistake this page can make (`:152`). The billing block shows today's plan and
flags **drift** when `plan_name_at_creation` or `subscription_status_at_creation` differ from the live row
(`:252-259`).

## 4. Errors and validation messages

### Tenant, server-rendered (all 422, `lib/custom_exceptions/platform_tickets.rb`)

| Key (`errors.platform_support.*`) | String | en.yml |
|---|---|---|
| `invalid_status_transition` | `You cannot move this ticket from '%{from}' to '%{to}'. Allowed: %{allowed}.` | `config/locales/en.yml:257` |
| `unsupported_category` | `'%{category}' is not a support category. Allowed: %{allowed}.` | `:258` |
| `unsupported_status` | `'%{status}' is not a support ticket status. Allowed: %{allowed}.` | `:259` |
| `unsupported_priority` | `'%{priority}' is not a support ticket priority. Allowed: %{allowed}.` | `:260` |
| `unknown_filter_value` | `The value given for '%{filter}' is not one this list accepts: '%{value}'.` | `:261` |
| `invalid_limit` | `per_page must be a whole number between 1 and %{maximum}, got '%{limit}'.` | `:262` |
| `ticket_closed` | `This ticket is closed. Open a new one.` | `:263` |
| `attachment_type_rejected` | `'%{content_type}' files cannot be attached. Accepted types: %{allowed}.` | `:264` |
| `attachment_too_large` | `'%{filename}' is larger than the %{maximum} limit for one file.` | `:265` |
| `too_many_attachments` | `A message may carry at most %{maximum} files.` | `:266` |

Each refusal names what *would* be accepted. A missing or invisible ticket is deliberately **not** in this list:
it is an `ActiveRecord::RecordNotFound` raised by the policy scope and rendered 404, because 422 would confirm
another account's ticket exists (`platform_tickets.rb:11-12`).

### Tenant, client-side (`app/javascript/dashboard/i18n/locale/en/platformSupport.json`)

`FORM.SUBJECT_REQUIRED` "Add a subject so we know what this is about."; `FORM.DESCRIPTION_REQUIRED` "Add a
description so we can start without asking first."; `FORM.ATTACHMENT_TYPE_REFUSED` "{name} is not an accepted
file type."; `FORM.ATTACHMENT_TOO_LARGE` "{name} is larger than {size}."; `FORM.ATTACHMENT_COUNT_REFUSED` "You
can attach up to {count} files."; `FORM.ATTACHMENT_UPLOAD_FAILED` "That file could not be uploaded. Try again,
or send the ticket without it."; `FORM.ATTACHMENTS_FULL` "That is the maximum of {count} files."; and five
`ERROR.*` strings (`LIST_FAILED`, `DETAIL_FAILED`, `NOT_FOUND`, `CREATE_FAILED`, `REPLY_FAILED`). Limits are
stated *before* the picker, not after a rejection (`constants.js:91-103`). AR parity: both files carry the same
93 keys.

### Staff-side operator messages — **no i18n keys exist**

Five refusals are bare English literals with no key at all:
`'A reply cannot be empty.'` (`platform_support_actions_controller.rb:23`), `'A note cannot be empty.'` (`:43`),
`"#{target} is not a status."` (`:53`), `"#{value} is not a #{field}."` (`:108`),
`'Choose an agent, or Unassign.'` and `'That agent does not exist, or is not active.'` (`:127,132`).
Four more call `t()` with an inline `default:` — `super_admin.platform_support.{not_an_agent, ticket_not_found,
ticket_closed, ticket_updated, lead_required}` (`platform_support_controller.rb:82,90`,
`platform_support_actions_controller.rb:31,90,144`) — and **none of those keys is defined**: `en.yml`'s
`super_admin:` block at `:783` has `operations:` and `account_suspension:` and no `platform_support:`. The strings
render from the `default:`, so nothing is broken; but the keys the frozen contract reserved
(`docs/platform-support/12-refresh-against-product-refinement.md:441`, "Backend i18n → `super_admin.platform_support.*`")
do not exist, and the staff surface is not translatable. See §10.

Billing and Operations operator strings are likewise plain English literals
(`billing_subscriptions_controller.rb:13,17,35,39,52,55,58,71`), consistent with the console being deliberately
English and LTR (`app/views/super_admin/platform_support/show.html.erb:12-13`).

### Mailer subjects — `config/locales/en.yml:399-443`

Nine operator/customer subjects, each `[%{reference}] …`, plus `shared.operator_context`
`'Account: %{account} · Plan: %{plan} · Category: %{category} · Priority: %{priority}'` and `shared.no_plan`
`'No plan on record'`. The block's own comment states the rule: a key that reads an interpolation its caller does
not pass raises at send time rather than rendering blank (`:396-398`).

## 5. Failure paths

| What goes wrong | How it surfaces | Can the user tell what to do? |
|---|---|---|
| **No `PlatformSupport::Agent` row exists** (today's state) | every staff read and write redirects to the Super Admin root with "You are not an active Lynomia support agent…" (`platform_support_controller.rb:77-84`). Customer side works normally; tickets accumulate unanswered | The operator is told *they* are not an agent, not that **nobody** is. Nothing on the surface names `rake platform_support:grant_agent`. Doc gap |
| **No support alias configured** (today's state) | no operator email is queued at all (`ticket_mailer.rb:97-114` returns `NullMail`); one `PLATFORM_SUPPORT_OPERATOR_MAIL_UNDELIVERABLE` operator-log line per attempt; the queue page carries the yellow banner | Yes, on the queue page, with the exact config key. But an operator who never opens that page learns nothing |
| **No SLA policy rows** (today's state) | `PolicyResolver` returns nil, no due times are written, `State#governed?` is false, the sweeper's `sla_policy_id IS NOT NULL` filter excludes every ticket, and the desk renders "No SLA policy applies" | Honest, and correct. But see the next row |
| **There is no way to create an SLA policy row** | no route, no page, no dashboard, no rake task, no seed. Grep for `SlaPolicy` outside the model and resolver returns nothing | **No.** Only `rails console` activates the SLA engine. `StaffAuthorizer#may_edit_sla_policies?` exists and is called by nothing but its own spec (`staff_authorizer.rb:52`). See §10 |
| **Billing-locked account tries to attach a file** | the shared upload endpoint is **not** billing-exempt (`app/controllers/api/v1/accounts/upload_controller.rb:1` inherits the guarded base; only `BillingController` and this module's own base override `billing_exempt?`), so the picker shows a readable upload failure while the ticket itself can still be opened and described | Partly. The copy says "send the ticket without it", which is true, but never says *why*. Known V1 limitation (`docs/platform-support/13-integration-record.md` §6.1) |
| **Administratively suspended account** | 401 from the untouched `ensure_current_account` guard, one layer before billing. No exemption, ever (`base_controller.rb:21-23`) | Only via the suspension notice, which is outside this module |
| **Subject account deleted** | `account_id` goes NULL; the snapshot preserves attribution; the tenant can no longer read the orphan (the policy scope needs a concrete match); staff and audit history survive; the notifier returns `[]` (`reply_notifier.rb:41-44`) | N/A — the account is gone |
| **Reporter user deleted** | `reporter_id` NULL. `platform_support_tickets` holds `reporter_name` and deliberately **never** `reporter_email`, so there is no address left: the customer email is simply not sent, and the reply still belongs in the thread (`ticket_mailer.rb:120-125`, `ticket.html.erb:158`) | Documented on the staff page only |
| **Arabic customer email** | backend strings live in `en.yml` and Crowdin owns the rest, so `config.i18n.fallbacks` renders an English subject rather than a blank one | No. Known limitation (`13-integration-record.md` §6.6) |
| **`FRONTEND_URL` unset** | both mailer links become `/app/accounts/…` with no host (`ticket_mailer.rb:142-148`) — a relative URL in an email | No. Not checked for anywhere in this module |
| **SMTP failure** | `ApplicationMailer`'s `rescue_from(*ExceptionList::SMTP_EXCEPTIONS)` logs and does not fail the request that saved the reply (`ticket_mailer.rb:18-21`) | The reply is visibly saved, which is the right trade |
| **Sweep stamps a breach, then the operator replies** | the clock decides once; the reply records the response without re-dating the breach, and `MessageCreation` writes the outcome event only when it was the decider (`clock.rb:98-104`, `message_creation.rb:93-96,113-123`) | Operator sees "breached", correctly |
| **Policy row deleted while tickets reference it** | FK is `on_delete: :nullify`, so tickets keep due times with no policy. `governed?` and the sweeper both require `sla_policy_id IS NOT NULL`, so they cannot disagree (`sweeper.rb:59-78`) | Renders as "No SLA policy applies" |
| **Rate limited** | 429 from one of five throttles: 300/min per user across the module, 5/h and 20/h on ticket create (per user, per account), 30/h and 120/h on message create (`config/initializers/rack_attack.rb:412-447`), each overridable by ENV | A bare 429; no module-specific copy |
| **Tenant endpoints are absent from `swagger/swagger.json`** | zero occurrences of `platform_support` | API consumers cannot discover the desk. Known (`13-integration-record.md` §6.4) |

Two more V1 limitations the owner should see in any operator documentation: the **25 MB per-ticket aggregate** in
doc 03 is **not** implemented (per-file, per-message and the type allow-list are), and the **unread marker is per
account, not per user** — `customer_last_viewed_at` is one column on the ticket, so one administrator opening a
ticket clears the dot for every administrator (`13-integration-record.md` §6.2, §6.5).

## 6. Permissions

### Tenant — `custom/app/policies/platform_support/ticket_policy.rb`

| Role | Sees | Citation |
|---|---|---|
| `administrator` | every ticket whose `account_id` is their account | `:44-45` |
| `agent` | only tickets where `reporter_id` is their own user id | `:46` |
| custom-role holder | **exactly** as an agent — V1 adds **no** `CustomRole::PERMISSIONS` entry, and the header says why | `:8-13,47-49` |
| nil account / nil membership / nil user / unrecognised role | `none` | `:40,49` |

Scoping lives **in the policy**: `#resolve` applies `where(account_id:)` itself and callers hand it the unscoped
relation (`:15-18`, `base_controller.rb:38-40`) — deliberately unlike `Support::TicketPolicy::Scope`, which
depends on two callers remembering. Every member record is fetched through that scope, so an invisible ticket is
a 404, never a 403 (`:20-23`). `index?` and `create?` are `true` for every member — every member may open a
ticket. `destroy?` is `false` and no endpoint could call it.

**No feature flag, ever** (`base_controller.rb:11-13`, `help.routes.js:20-22`, collision table at
`docs/platform-support/12-refresh-against-product-refinement.md:437`): a customer who did not buy the tenant
ticketing module must still be able to raise a ticket with Lynomia, and the desk is never sold.
**Billing-exempt** (`base_controller.rb:29-31`) — the exemption is declared once and covers exactly the
subclasses of that controller. **Never suspension-exempt** (`:21-23`).

### Staff — `custom/app/policies/platform_support/staff_authorizer.rb`

Two layers. `authenticate_super_admin!` from `SuperAdmin::ApplicationController` is the first. The second — the
one the Operations console does not have — is `require_support_agent!`, which resolves an **active**
`PlatformSupport::Agent` for `current_super_admin` and refuses otherwise
(`platform_support_controller.rb:38,77-84`; `staff_authorizer.rb:79-83`). Being a Super Admin is not being
support staff. This is not Pundit, deliberately: the Super Admin surface has no Pundit anywhere
(`staff_authorizer.rb:63-65`), and the two authorization paths share no helper and no method name, which is the
session-isolation rule made structural — Warden keys both Devise scopes into one cookie
(`staff_authorizer.rb:67-71`).

Role is a row, not a string: `{agent: 0, lead: 1}` (`custom/app/models/platform_support/agent.rb:25`), unique on
`user_id`, validated on create to be a `SuperAdmin`. A **lead** may reassign another agent's ticket; an agent may
take unassigned work and hand back its own (`staff_authorizer.rb:97-101`, enforced at
`platform_support_actions_controller.rb:128`). Only an `Agent` row may be an assignee — the FK says so — and
**no `AccountUser` membership is ever created for Lynomia staff**.

Operations and billing are `authenticate_super_admin!` only, with no second layer
(`operations_controller.rb:7-9`, `config/routes/operations.rb:5-7`). The Platform Support desk is the only Super
Admin surface in this installation with an authority layer above Super Admin.

## 7. Contextual-help opportunities

Registry: `app/javascript/dashboard/helper/documentationLinks.js`. One Platform Support key exists today:
`contactLynomiaSupport: 'contact-lynomia-support'` (`:93`), rendered through
`components-next/docs-link/DocsLink.vue` at three places. Branded installations with no `DOCUMENTATION_URL`
render **no link at all**, never a broken one (`:37-42`).

| UI location | The question a user has there | Registry key | Exists? |
|---|---|---|---|
| `PlatformSupportIndexPage.vue:148-150` | "What is this desk, and is it the right one?" | `contactLynomiaSupport` | yes |
| `PlatformSupportNewPage.vue:79-81` | "What do I need to put in so this is answerable?" | `contactLynomiaSupport` | yes |
| `PlatformSupportDetailPage.vue:280-282` | "What does *With Lynomia* mean — whose turn is it?" | `contactLynomiaSupport` | yes |
| `AttachmentPicker.vue` limits row (`constants.js:91-103`) | "Why was my zip/screenshot refused, and what is accepted?" | needs its own key or an anchor | no |
| `ReplyBox.vue` on a resolved ticket (`REPLY.REOPENS_HINT`) | "If I reply, what happens to the ticket?" | covered by the status article's anchor | partly |
| `DETAIL.CLOSED_HINT` / "Open a new ticket" | "Why can't I reply, and how do I reference the old ticket?" | anchor into the status section | partly |
| Tenant billing / subscription page (`routes/dashboard/settings/billing/ProviderIndex.vue`) | "What does my plan include, what happens when a trial ends, what does locked mean?" | **no billing key exists at all** | **no** |
| The 402 redirect target `/settings/subscription` (`billingGuard.js:4,18`) | "Why was I just thrown out of what I was doing?" | needs a key | **no** |
| The 422 `plan_limit_reached` on agent create (`access_guard.rb:44-47`) | "Why can't I add another agent, and what raises the limit?" | needs a key | **no** |
| Inbox / store creation refused on a limit (`Billing::ResourceLimit`) | same question for inboxes and stores | needs a key | **no** |
| `administration` section | "Who at my company can see the tickets I open?" | `permissions` exists; the Platform Support rule is only inside the support article | partly |

Super Admin surfaces (queue, ticket detail, Operations, billing) carry **no** `DocsLink` and no operator
documentation of any kind: the help portal is tenant-facing, and operator runbooks live only in `docs/p9/`,
`docs/p11/` and `docs/platform-support/`, which are repository design records, not help content.

## 8. Current documentation coverage

| Corpus file | Covers | How well |
|---|---|---|
| `custom/db/documentation/en/troubleshooting/contact-lynomia-support.md` | the whole tenant side of the desk | **Good, and unusually accurate.** 117 lines. Three-desk disambiguation table; how to raise one; the four fields; the exact attachment limits (5 × 10 MB, PNG/JPEG/GIF/WebP/PDF/plain text/CSV, archives refused) matching `message.rb:32-34`; the `LYN-000123` reference; a six-row status table matching the enum and the tenant `ENUMS.STATUS` labels verbatim; reply-reopens-resolved; closed-is-final; priority as a request not a promise; coverage and five explicit non-coverage items; **billing-locked accounts can still reach it, suspended ones cannot**; and the role visibility rule stated as "that is the rule working, not a fault" |
| `custom/db/documentation/ar/troubleshooting/contact-lynomia-support.md` | the same | **At parity.** 111 lines against 117, every `##` heading and every table present, same structure and same claims |
| `custom/db/documentation/en/administration/audit-logs.md` (+ AR) | the tenant audit log | Correct, and by omission correct about this module too: operator Platform Support rows carry no `associated` and so never appear on the tenant page. It does not say so |

That is the whole of it. `manifest.yml` declares twelve sections; the Platform Support article sits in
`troubleshooting` at `position: 20` and needed no manifest edit, because the seeder globs each section
directory.

**Part (b) has no coverage at all.** The `administration` section contains exactly one article (`audit-logs.md`).
There is no article on billing, plans, subscriptions, trials, invoices, the portal, usage limits, or what a
locked account means — and the tenant-facing surfaces for all of those exist and are reachable
(`config/routes/billing.rb:27-34`, `routes/dashboard/settings/billing/`). Operations and the Super Admin console
are operator surfaces with no audience in a tenant portal, which is a reasonable omission for the *portal* and an
unreasonable one for the *program*: §9 proposes where operator material belongs.

## 9. Missing or stale documentation

Nothing in the corpus is **wrong** about these two areas. Everything below is absent.

**Tenant-facing, Platform Support (the one article is good but thin in three places).**

1. **Attachments, as their own answer.** A customer whose `.zip` or 15 MB video was refused needs the accepted
   list and the per-file ceiling at the moment of refusal. The article states them once, inside a paragraph, and
   the picker has no link.
2. **"I replied to a closed ticket and it was refused."** The 422 string tells the customer to open a new one;
   nothing tells them to reference the old `LYN-` number, which the article recommends but no refusal links to.
3. **The unread dot is per account, not per user.** An administrator clearing it for colleagues is surprising and
   undocumented.
4. **What email the desk sends, and from where.** Four customer emails exist (`ticket_created`,
   `operator_replied`, `ticket_resolved`, `waiting_on_customer`); nothing documents that administrators are
   copied on operator replies (`ticket_mailer.rb:127-129`), that Arabic subjects arrive in English, or that a
   deleted user's ticket sends no email.
5. **"Why is there no SLA on my ticket?"** Today every ticket renders no commitment, by design. A customer who
   was told a target exists has nowhere to read that none is configured. This becomes a *different* gap the day
   the owner sets targets — see the blocker in §10.

**Tenant-facing, billing and limits — the largest gap in this report.**

6. **Plans and what each includes** — no article, and `Billing::Entitlements` is the live authority.
7. **Trials: start, extension, expiry, grace period** — `trial_ends_at`, `grace_period_ends_at` and
   `Billing::TrialStarter` are all real and undocumented.
8. **"My account is locked"** — the 402 → `/settings/subscription` redirect is the single most disorienting thing
   this product does to a customer, and there is no article for the page they land on.
9. **Usage limits: agents, inboxes, stores** — the exact strings a customer hits
   (`Billing::ResourceLimit.message`) have no article naming the limit, what counts toward it (a *connected*
   store holds a slot; a disconnected one does not — `resource_limit.rb:28-32`), or how to raise it.
10. **Entitlement overrides** — a customer can be granted a capability their plan excludes. Nothing explains why
    their account behaves unlike the published plan.
11. **Changing plan** — `change_plan_preview` / `change_plan` with Stripe proration and the
    `pending_if_incomplete` failure path (`custom/app/services/billing/plan_change.rb:61-68`) produce a
    customer-visible failure message with no article behind it.

**Operator-facing (audience currently served by nothing).**

12. **Activating the desk** — the three owner-controlled values and the order to set them:
    `rake platform_support:grant_agent`, `PLATFORM_SUPPORT_OPERATOR_ALIAS`, SLA policy rows. This exists only in
    rake comments and `13-integration-record.md` §6.8.
13. **Working the desk** — agent vs lead, assignment rules, when a note is right and when a reply is, that a
    note never moves `last_operator_message_at`, and the five status moves that mail the customer.
14. **Reading the SLA panel** — calendar time, "not promised by this policy", paused totals, why a breach
    survives resolution, and why the sweep never calls a late resolution "in time".
15. **Revoking an agent** — deactivation keeps notes and keeps assignments, and the queue then shows "reassign
    needed". Only the rake task's output says so.
16. **Operations Control Center** — six tabs, 12 signal types, 8 sources, acknowledge/suppress/resume semantics,
    and the deliberate boundary that no support ticket ever becomes a signal.
17. **Billing operator actions** — `extend_trial`, `grant_plan`, `grant_override`, `revoke_override`,
    `cancel_subscription`, which of them refuse a Stripe-paid subscription, and that an override is per account
    while a plan edit moves every subscriber.

## 10. Doc claims not proven by code

Five, all internal design records rather than published articles. The corpus itself asserts nothing I could not
verify.

**1. `docs/platform-support/12-refresh-against-product-refinement.md:193` promises a staff administration
surface that does not exist.** Its §2 staff route table ends with:

> `GET/POST/PATCH` `/super_admin/platform_support/agents`, `/sla_policies` — Operator administration of staff
> rows and SLA policy records

Neither route exists. `config/routes/platform_support.rb:62-65` says the opposite, and gives the reason:

> `agents` and `sla_policies` are deliberately absent: the first PlatformSupport::Agent row cannot be created
> from a page that is itself behind the acting-agent guard, so it is created by `rails platform_support:grant_agent`
> instead …, and SLA policy records wait on the owner's target values

The agent half is fully answered by the rake task. **The SLA-policy half is not answered at all.** Severity:
major, and it is the one item in this report that an owner cannot work around from a page.

**2. There is no mechanism, anywhere, to create a `PlatformSupport::SlaPolicy` row.** No route, no controller, no
Administrate dashboard (`custom/app/dashboards/` holds five, none for this), no rake task, no seed, no migration
data. The only references outside the model are the resolver's two `find_by` calls
(`policy_resolver.rb:32,38`) and the ticket's `belongs_to` (`ticket.rb:52`).
`docs/platform-support/13-integration-record.md` §7.3 says the desk is inert "until an operator runs
`rake platform_support:grant_agent` and (optionally) sets the support alias and SLA policy rows" — the alias has
an Installation Config entry (`config/installation_config.yml:740-748`) and the agents have a rake task, but the
policy rows have **neither**. `rails console` is the only path. Severity: major. **For the orchestrator:** this is
a product gap, not a documentation gap, and no article can close it — an article that told an operator to open a
Rails console would be documenting a defect. It needs an owner decision (a third rake task, or the deferred
`sla_policies` page), and until it is made, item 5 in §9 cannot be written truthfully.

**3. `StaffAuthorizer#may_edit_sla_policies?` is unreachable.** `staff_authorizer.rb:52` defines it and
`staff_authorizer.rb:103-105` explains the rule it encodes ("Thresholds are Lynomia's commercial commitment, so
changing one is a lead's decision"). Its only callers are three lines of its own spec
(`spec/policies/platform_support/staff_authorizer_spec.rb:78-82`). It is the vestige of the surface in claim 1.
Severity: minor — but it is positive evidence that the `sla_policies` page was dropped rather than forgotten.

**4. The reserved backend i18n namespace `super_admin.platform_support.*` does not exist.** The collision table
(`12-refresh…md:441`) assigns it; five call sites use it with an inline `default:`
(`platform_support_controller.rb:82,90`; `platform_support_actions_controller.rb:31,90,144`); `config/locales/en.yml:783`
has no such block. Six further operator refusals have no key at all (§4). Nothing is broken — Rails renders the
`default:` — but the claim that the namespace is taken is not true in code, so a future contributor adding
`super_admin.platform_support.*` keys will find the existing strings do not move. Severity: minor.

**5. `13-integration-record.md` §2 describes `config/schedule.yml`'s new entry as the desk's sweep "neighbour at
the same cadence" as the tenant desk's own sweep.** The Platform Support entry is real
(`config/schedule.yml:105-108`, `*/5 * * * *`, `housekeeping`). I did not verify the tenant sweep's cadence, so
the *comparison* is unverified; the claim about this module's own entry is confirmed. Marked **unverified**
rather than contradicted.

### Checked and confirmed, against the contract

Worth recording because these are the claims a documentation writer will lean on: the 18/7 event allow-lists
(`event.rb:21-27`); the tenant serializer's absent keys; `author_name` always "Lynomia Support"
(`message.rb:55,constants.js:82-85`); no blob URL in any tenant serializer; `audited` declared on no
`platform_support_*` model; `associated` absent from every audit write; no feature gate on any route or endpoint;
no hard-coded support address and **no SLA target value anywhere** (the only number in the module is the 365-day
sanity ceiling on the policy column, `sla_policy.rb:19`); five Rack::Attack throttles; `platform_support_reply`
present in `NOTIFICATION_TYPES`, `PRIMARY_ACTORS`, `IN_APP_ONLY_TYPES` and the visibility allow-list with its own
branch; EN/AR `platformSupport.json` at 93 = 93 keys; the two Administrate exclusion entries present in the same
file as the nav item; `meta.counts` exactly `{open, closed, unread}`; `per_page` 1–100 with a 422 outside it;
unknown filter values 422 rather than silently dropped.
