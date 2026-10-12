# Platform Support Desk — Super Admin operator experience

> Phase 0. MVP / Phase 2 / Future are separated explicitly, per the brief's *"Do not build a giant Zendesk
> clone in V1."*

## 1. Where it lives

A custom, server-rendered page inside the Administrate shell — the same arrangement the Operations Center
already uses, and the pattern is worth following exactly because all three of its moving parts are already
proven:

| Part | Operations Center precedent | This module |
|---|---|---|
| Route drawer | `config/routes/operations.rb`, drawn at `config/routes.rb:664` | `config/routes/platform_support.rb`, `draw :platform_support` |
| Controller | `SuperAdmin::OperationsController < SuperAdmin::ApplicationController` | `SuperAdmin::PlatformSupportController`, same parent |
| Authentication | `authenticate_super_admin!` applied by the parent to every action (`app/controllers/super_admin/application_controller.rb:16`) | identical |
| Navigation | A manual `render partial: "nav_item"` in the lower block (`app/views/super_admin/application/_navigation.html.erb:56`) | one more `nav_item`, labelled **Customer Support** |
| Administrate collision | `"operations"` added to the `next if …include? resource.resource` list (`_navigation.html.erb:40`) | `"platform_support"` added to the same list |
| View style | Tailwind ERB, no Vue island (`app/views/super_admin/operations/show.html.erb` and 6 partials) | identical |

Plus one layer the Operations Center does not have: a `before_action` resolving the acting
`PlatformSupport::Agent` and refusing the page when there is none (`03-authorization-security.md` §1). Once
staff identity is a real row, "is a super admin" stops being the same question as "is a support agent", and the
brief's future dedicated support role needs that separation to exist from day one.

Routes:

```
GET  /super_admin/platform_support                      # queue
GET  /super_admin/platform_support/tickets/:id          # detail
POST /super_admin/platform_support/tickets/:id/messages        # public reply
POST /super_admin/platform_support/tickets/:id/internal_notes  # internal note
PATCH /super_admin/platform_support/tickets/:id         # status / priority / category / assignee / sla
```

## 2. The queue (MVP)

Four saved queues as tabs, because an operator opening the desk has one of four questions:

| Tab | Predicate | Why it is a tab and not a filter |
|---|---|---|
| **Needs us** | `status IN (open, in_progress, waiting_on_lynomia)` ordered by `priority DESC, last_activity_at ASC` | The default. `waiting_on_lynomia` groups here because, from the operator's side, all three mean "ours" (`02-data-model.md` §5) |
| **Customer replied** | `last_customer_message_at > last_operator_message_at` and active | The single highest-value queue on a vendor desk: somebody is waiting on a human |
| **Unassigned** | `assignee_id IS NULL` and active | Served by the partial index in `02-data-model.md` §2 |
| **SLA at risk** | due within 25% of the target window, or already breached, and active | Served by the two partial SLA indexes |

Plus **Mine** (`assignee_id = current agent`) and **All**.

Filters on top of the active tab: status, priority, category, account, plan, assignee, SLA state, created and
updated date ranges. Search by reference, account name, or subject. Reference search accepts both
`LYN-000123` and `123` — the existing module already does this, with the recorded reason *"an operator pasting
a reference from an email should not have to strip it"*
(`custom/app/controllers/api/v1/accounts/support/tickets_controller.rb:41-47`, helper at
`custom/app/models/support/ticket.rb:96-99`).

Each row shows: reference, subject, account name, plan name, status, priority, assignee, age, SLA state, and a
marker when the customer replied last.

Header counts for the four tabs, computed in **one** query with `FILTER` clauses rather than four
round trips — because the Operations Center has a recorded measurement of what the naive shape costs on this
surface: `CountField` was ~40 queries per 20 rows, and `Billing::Settings.enforced?` was 75 of 85 queries at
`PER_PAGE=25` (`custom/app/services/operations/account_health.rb:7-10,93-103`). That is the N+1 trap this page
must avoid by construction, and the account/plan columns are exactly where it would reappear: the list
`includes(:account)` and reads `plan_name_at_creation` from the ticket's own snapshot column rather than
joining through `billing_subscriptions` per row.

## 3. Ticket detail (MVP)

Three regions. The brief's warning — *"do not make this page an uncontrolled dump"* — is handled by putting
exactly one thing in the main column and everything else behind a heading or a tab.

**Main column: the thread.** Public messages, internal notes and every event in one chronological list, with
notes visually distinct (a left border and a lock icon, not just a colour). Compose area with two tabs: *Reply
to customer* and *Internal note*. The compose tab is the only place the public/internal choice is made, and the
internal tab is styled so the two are not confusable — the single most likely operator error on a desk like
this is a note sent as a reply.

**Right column: account context.** Read-only, collapsed by default except the first block:

| Block | Contents | MVP |
|---|---|---|
| Account | Name, id, status (active/suspended + latest suspension category from `Account#suspension_history`), locale, created | **yes** |
| Billing | Current plan name, subscription status, and the plan/status **snapshot from ticket creation** when it differs from today's | **yes** |
| Links | Super Admin account page, the account's billing subscription page, Operations account health | **yes** — links, not embedded data |
| Inboxes | Count by channel type with health state | Phase 2 |
| Integrations / stores | Count and connection state | Phase 2 |
| Open Operations signals for this account | Count + link | Phase 2 |

The MVP deliberately links rather than embeds. Embedding inbox and integration state means per-ticket queries
against subsystems whose cost on this surface is already measured and high (§2); a link costs nothing and lands
the operator on a page that is already built and already correct.

**Header: actions.** Status, priority, category, assignee and SLA policy, each a small form posting to the
`PATCH` route. Every one writes an event and an explicit `Custom::AuditLog` row
(`03-authorization-security.md` §10).

What the detail page shows that the customer's does not: operator identity on every reply, internal notes, SLA
targets and clocks, assignment history, priority history, `events.metadata`, and the account context column.

## 4. Assignment

- Assignee options are `PlatformSupport::Agent.where(active: true)`, rendered by `display_name`.
- An agent may assign an unassigned ticket to themselves or take one over; reassigning *another* agent's ticket
  requires `role: lead` (`02-data-model.md` §4).
- Unassigning is explicit and writes an `unassigned` event; it does not silently happen on status change.
- A deactivated agent's tickets stay assigned to the row (which still exists) and appear in a **Reassign
  needed** filter rather than being silently dumped back into Unassigned — losing the assignment history is how
  a ticket gets forgotten.
- Teams are **not** modelled in V1. The tenant module has `team_id` because accounts have teams; Lynomia's
  desk has a handful of staff, and a team abstraction over four people is structure with no content. Phase 2,
  if the staff count justifies it.

## 5. Internal notes

One table, staff-only by construction (`02-data-model.md` §7). Operator-facing rules:

- A note never triggers a customer notification and never updates `last_operator_message_at` — only a public
  reply does. This matters: a desk where internal triage looks like a customer reply makes the "customer
  replied" queue lie.
- A note writes an `internal_note_added` event, which is **excluded** from the customer-visible event
  allow-list, so the customer cannot infer that internal discussion happened.
- Notes support attachments, authorized by their parent class.
- `@`-mentions of other agents: Phase 2 (it needs the notification path §7 defers).

## 6. SLA on the operator surface

- The header shows first-response and resolution targets with remaining time, and a clear **paused** state when
  the ticket is `waiting_on_customer` — including how long it has been paused, read from `sla_paused_seconds`.
- A breached target is red and names which one breached; a ticket that breached and was later resolved keeps
  the breach record (it is not cleared by resolution).
- Calendar time, labelled as such in V1 — "resolution target: 8 calendar hours" — because business hours are
  not available (`01-architecture.md` §4, `06-sla-notifications.md` §5). Labelling it is the difference between
  a limitation and a lie.
- Only a `lead` may change a ticket's SLA policy, and doing so writes an event and an audit row.

## 7. Localisation of the staff surface

**English, LTR, in V1.** Consistent with the surface as it exists:

- The Super Admin layout has no `dir` attribute (`app/views/layouts/super_admin/application.html.erb:16`).
- The seven Operations views contain **zero** `t(` calls — every string is hard-coded English
  (`for f in app/views/super_admin/operations/*.erb; do grep -c 't(' $f; done` → 0 for all seven).
- Only the controller's flash messages go through i18n (`t('super_admin.operations.case_opened')`,
  `config/locales/en.yml:731`).

So the surface is already English-only, and this module matching it is consistency, not neglect. Flash messages
go through `en.yml` like the Operations Center's do, so the convention is followed where it exists.

> **Decision D-3 needs your approval.** If Lynomia will employ Arabic-first support staff, the staff desk needs
> i18n and `dir` from the start — retrofitting it later means touching every view this module adds. The cost
> now is roughly one locale file and `dir="rtl"` plumbing on a layout that currently has none; the cost later
> is the same work plus a rewrite of every hard-coded string.

## 8. Phasing, explicitly

**MVP (ships first):** the four queues plus Mine and All; filters and search; detail page with thread, public
reply, internal note, status/priority/category/assignee/SLA actions; account + billing context blocks and
links; agent management via a plain Administrate dashboard; explicit audit on every mutation; email
notifications both directions.

**Phase 2:** inbox / integration / store / Operations-signal context blocks; typed links
(`02-data-model.md` §11); macros and canned replies; agent `@`-mentions; teams; per-user read markers; a staff
notification feed; merge/duplicate handling; CSV export; the in-app bell for tenants
(`06-sla-notifications.md` §4).

**Future:** inbound email (`01-architecture.md` §10); customer satisfaction survey on resolve; Slack and push
delivery; business-hours SLA with an installation calendar; per-(plan, priority) SLA rows; a public status
page fed from Operations; automated triage or routing.

Deliberately **not planned at all**, so nobody adds it by drift: a customer-facing knowledge-base suggester on
the new-ticket form (Lynomia's documentation is already linked two rows above it in the same sidebar group),
chat/live support, and any form of ticket deletion.

## 9. Operator error modes this design guards against

| Error | Guard |
|---|---|
| Internal note sent as a public reply | Two visibly distinct compose tabs; different submit label; the note tab is the non-default |
| Replying to the wrong ticket | Reference and account name pinned in the compose header, not only at the top of the page |
| A ticket silently orphaned when an agent leaves | Deactivation keeps the assignment and surfaces a **Reassign needed** filter (§4) |
| A ticket forgotten because nobody owns it | The **Unassigned** tab is one of four defaults, with a header count |
| "Resolved" used to clear the queue | Resolving writes a customer-visible event and the customer can reopen by replying; the reopen writes `reopened` and restarts the resolution clock (`06-sla-notifications.md` §5) |
| Operator reads stale plan context | Both are shown: today's plan, and the snapshot from ticket creation when they differ (§3) |
