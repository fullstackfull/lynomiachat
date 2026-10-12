# Platform Support Desk — architecture

> Phase 0. No implementation. Every decisive claim cites a file and line.

## 1. What this module is

A **vendor support desk**. A Lynomia customer opens a ticket *to Lynomia*; Lynomia staff work it centrally in
Super Admin. The owner of the record is Lynomia, the subject of the record is a customer account, and the
customer is a participant with read access to its own ticket and nothing else.

Today a tenant's only in-product path to Lynomia is an **external link**: the sidebar's `Contact Support` entry
resolves to whatever `supportURL` the installation configured
(`app/javascript/shared/composables/useBranding.js:9-13,50-54`, consumed at
`app/javascript/dashboard/components-next/sidebar/Sidebar.vue:57,742`), and renders nothing at all on an
installation that configured none. This module replaces that link with a record.

## 2. The bounded-context question, answered from the repository

The brief said: *"I strongly suspect Option C is WRONG … But prove it from the repository rather than simply
accepting my assumption."* Option C — extending `Support::Ticket` — is wrong. Six independent proofs, each one
sufficient on its own.

### C-1. The membership validation would have to be deleted

```ruby
def validate_user_in_account(name, user)
  return if user.nil?
  return if AccountUser.exists?(account_id: account_id, user_id: user.id)

  errors.add(name, 'must be a member of the same account')
end
```
`custom/app/models/support/ticket.rb:145-151`

A Lynomia operator is not an `AccountUser` of the customer's account. So `assignee_id` cannot hold one. The
only ways out are to delete the validation, to make it conditional on a new `kind` column, or to give Lynomia
staff `AccountUser` rows inside every customer account. The first two remove the guard that keeps *tenant*
cases tenant-scoped; the third is the tenant-boundary breach this module exists to avoid.

### C-2. A global reference cannot be enforced on that table

Reference uniqueness is `unique: [account_id, reference_number]`
(`db/schema.rb:1796`, `index_support_tickets_on_account_and_reference`), and the allocator takes the advisory
lock **keyed on account_id** (`custom/app/services/support/tickets/reference_allocator.rb:22`). A global
`LYN-000001` sequence needs a unique index on `reference_number` alone — which the existing rows, numbered
per-account, would immediately violate.

### C-3. Every existing read becomes a leak waiting for one forgotten predicate

`Support::TicketPolicy::Scope#resolve` contains **no account predicate at all**
(`custom/app/policies/support/ticket_policy.rb:37-43`); the account scoping is supplied by each caller —
`ticket_scope` in the API base controller
(`custom/app/controllers/api/v1/accounts/support/base_controller.rb:28-30`) and the explicit
`scope.where(account_id: account.id)` in `Scope.for` (`:34`). Sharing the table means every current reader —
`Support::Tickets::Query`, `Support::Tickets::Counts`, the contact activity timeline adapter, the ticket
analytics module, `Operations::CaseBridge` — needs a new `where(kind: :tenant)` predicate, and the first one
anybody forgets shows a tenant a Lynomia-internal ticket. That converts a *schema* invariant into a
*per-call-site* invariant.

### C-4. The audit trail would publish operator activity to the customer

`Support::Ticket` declares `audited associated_with: :account`
(`custom/app/models/support/ticket.rb:24`). The account audit trail is read by the tenant's own administrators
through `AuditTrail::Query`, which scopes to `Custom::AuditLog.for_account(@account)`
(`custom/app/services/audit_trail/query.rb:54`) and applies an `auditable_type` filter **only when the request
asks for one** (`:82`, `scope.of_type(@filters.types) if @filters.types`). So a Lynomia operator changing the
priority of a platform ticket would write a row that appears on the customer's Audit Logs settings page.
That is a direct disclosure of internal operator activity, produced by a macro nobody would think to re-check.

### C-5. Both SLA indexes hard-code the status numbering

```
where: "((resolution_due_at IS NOT NULL) AND (resolution_breached_at IS NULL) AND (status < 4))"
```
`db/schema.rb:1793,1796`

`status < 4` encodes "not yet resolved" against the existing six-value enum
(`custom/app/models/support/ticket.rb:31-37`). A different status vocabulary on the same table either reuses
those exact integers or silently falls out of both partial indexes.

### C-6. The history table has no visibility concept

`support_ticket_events` has `account_id`, `support_ticket_id`, `user_id`, `event_type`, `body`, `data`
(`db/schema.rb:1750-1760`) and nothing else. Internal notes live in it as `event_type = 'note'`
(`custom/app/models/support/ticket_event.rb:13`), and the event serializer emits `body` for every row.
Introducing a public/internal split there changes the meaning of every existing row and every existing read.

**Option B — reuse `Conversation`/`Message` — is also wrong**, for the reason the existing P9 header already
records: `conversations.inbox_id` is `NOT NULL` (`db/schema.rb:1077`) and validated
(`app/models/conversation.rb:77`), and a conversation cannot be created without a contact (validated at `:78`,
dereferenced in `before_create` at `:308`). A Lynomia ticket has no inbox and the reporter is a *user*, not a
contact. Using them means fabricating an inbox and a contact per account — the brief's explicit prohibition,
and a fabricated contact would appear in the tenant's own Contacts list, campaigns and analytics.

**Therefore: Option A.** New tables, new namespace.

## 3. Namespace

`PlatformSupport::`.

- `Platform::` is already taken by the token-authenticated platform admin API
  (`app/controllers/platform/api/v1/accounts_controller.rb:1` and five siblings, plus five Lynomia billing
  controllers under `custom/app/controllers/platform/api/v1/billing/`). Using it would put a tenant-facing
  support desk inside the namespace that means "installation-level machine API".
- `Support::` is taken by the tenant module (`custom/app/models/support/ticket.rb`, `sla_policy.rb`,
  `ticket_event.rb`).
- `PlatformSupport::` collides with nothing: `grep -rn "PlatformSupport" app custom lib config` → empty.

Classes: `PlatformSupport::Ticket`, `PlatformSupport::Message`, `PlatformSupport::InternalNote`,
`PlatformSupport::Event`, `PlatformSupport::SlaPolicy`, `PlatformSupport::Agent`, `PlatformSupport::Link`.
Table prefix `platform_support_`.

Exception namespace: `CustomExceptions::PlatformSupport` — and the reason is recorded upstream already. The
existing module is deliberately `CustomExceptions::Tickets`, not `CustomExceptions::Support`, because *"a
`CustomExceptions::Support` module would shadow the top-level `Support::` model namespace for any code written
inside it"* (`lib/custom_exceptions/tickets.rb:4-6`). The same hazard applies, so the new module must not be
named `CustomExceptions::PlatformSupport` if it will contain code referencing `PlatformSupport::Ticket`.
Use `CustomExceptions::PlatformTickets`, mirroring the existing choice.

## 4. Reuse decisions

| Primitive | Decision | Why, with citation |
|---|---|---|
| ActiveStorage | **Reuse** | Already configured, with `ActiveStorage::Streaming` prepended for authorized serving (`config/initializers/active_storage.rb:27-46`) and the bare direct-upload route already blocked (`:50+`). Adds no second blob store. |
| Authorized download controller | **New** | Blob URLs never expire here (`grep -rn "urls_expire_in\|resolve_model_to_route" config/ app/ custom/ lib/` → empty) and `Attachment`'s size/MIME validation runs only for the web widget (`app/models/attachment.rb:186-191`). Neither protects a support attachment. |
| `Custom::AuditLog`, explicit writes | **Reuse** | `custom/app/services/billing/override_grant.rb:131-141` is the precedent: it passes `user: @actor` directly. |
| `audited` macro | **Reject** | `config/initializers/audited.rb:3-5` leaves `current_user_method` at the gem default, so the Sweeper resolves the actor through Devise's `current_user` (scope `:user`) while a super admin is authenticated under scope `:super_admin` (`app/controllers/super_admin/devise/sessions_controller.rb:14`). Full chain in `00-discovery.md` §3. |
| `Rack::Attack` | **Reuse**, new rules | Existing support throttle is GET-only (`config/initializers/rack_attack.rb:384-387`); the new module needs write rules. `account_user_key` (`:371-379`) is the reusable keying helper. |
| `sla_policies` table | **Reject** | `account_id` is `null: false` (`db/schema.rb:1742`) and `Support::SlaPolicy belongs_to :account` without `optional` (`custom/app/models/support/sla_policy.rb:16`). A Lynomia-owned policy has no account; reusing the table needs either a fake house account or a nullable migration that weakens the tenant invariant. |
| SLA pause/resume arithmetic | **Re-implement, same algebra** | `Support::Tickets::SlaClock#pause/#resume` (`custom/app/services/support/tickets/sla_clock.rb:41-59`) is the correct algebra and is worth copying by hand; the class itself is bound to the tenant model and to the inbox-scoped business-hours path. |
| Business-hours calculator | **Not available** | `business_hours_applicable?` requires `@ticket.inbox.working_hours_enabled?` (`sla_clock.rb:62-69`); `working_hours` exists only on an inbox (`app/helpers/reporting_event_helper.rb:3-9,44`). The Lynomia desk has no inbox. V1 runs on calendar time. |
| `notifications` table | **Reject for V1** | Four separate reasons in `06-sla-notifications.md` §4. |
| ActionMailer | **Reuse** | `app/mailers/application_mailer.rb` plus the `agent_notifications`/`administrator_notifications` view convention. |
| `Operations::Signal` | **Reuse as a link target only** | `operations_signals.support_ticket_id` is already taken by the tenant case bridge (`db/schema.rb:1609`, `custom/app/services/operations/case_bridge.rb:39-49`), so the new link needs its own row, not that column. |
| `Billing::Entitlements` | **Reuse, read-only** | `plan_for` returns `nil unless subscription.accessible?` (`custom/app/services/billing/entitlements.rb:79-83`) — which is exactly the state a support ticket must survive, so the desk reads the subscription directly, not through this. |
| `features.yml` flag | **Reject** | See §6. |
| Vue design system + jbuilder conventions | **Reuse** | `components-next/`, the `_record.json.jbuilder` partial shape, `CustomExceptions` → 422 rendering (`custom/app/controllers/api/v1/accounts/support/base_controller.rb:25-28`). |
| Super Admin shell | **Reuse** | `SuperAdmin::OperationsController` is the proven precedent for a custom non-Administrate page: a route drawer (`config/routes/operations.rb`), a manual nav item (`app/views/super_admin/application/_navigation.html.erb:56`), and the resource name added to the Administrate exclusion list (`:41`). |

## 5. Existing Support Case vs Platform Support Ticket

| Dimension | `Support::Ticket` (P9, tenant) | `PlatformSupport::Ticket` (this module) |
|---|---|---|
| Who owns the record | The customer account | Lynomia |
| Who opens it | An account member, about the account's own end customer | An account member, about Lynomia |
| Who works it | Account agents and administrators | Lynomia staff only |
| Who the "customer" is | A `Contact` (optional) | An `AccountUser` of the subject account |
| Audience boundary | Within one account: ownership-based (`ticket_policy.rb:31-43`) | Across accounts: Lynomia sees all; a tenant sees only its own |
| Operators | `User` rows with `AccountUser` membership | `PlatformSupport::Agent` rows (staff), never `AccountUser` |
| Reference | Per-account `TCK-000001` (`support/ticket.rb:52`, allocator keyed on account) | **Global** `LYN-000001` |
| Table scoping column | `account_id` = owner, `NOT NULL`, `ON DELETE CASCADE` (`db/schema.rb:2006-2013`) | `account_id` = **subject**, FK nullify, with a name snapshot |
| Statuses | 6, incl. `waiting_on_internal` (`support/ticket.rb:31-37`) | 6, incl. `waiting_on_lynomia` |
| Thread | Delegated to an optional `Conversation`; the table holds no messages | Owns its own thread; no conversation, no inbox, no contact |
| Internal notes | Same table as history, `event_type = 'note'` (`ticket_event.rb:13`) | **Separate table** from public messages (§7 of `02-data-model.md`) |
| Attachments | None on the ticket | ActiveStorage, authorization-gated download |
| SLA policies | `sla_policies`, account-scoped, business-hours capable via an inbox | `platform_support_sla_policies`, installation-scoped, calendar time in V1 |
| Plan awareness | None | Plan and subscription status are first-class context |
| Billing lock | Blocked with the rest of the account API (402) | **Exempt** — the desk must stay reachable |
| Feature flag | `lynomia_support_tickets` (`features.yml:308-311`), 404 when off | **None** — never gated, never sold |
| Audit | `audited associated_with: :account` → visible on the tenant's audit page | Explicit `Custom::AuditLog`, **never** `associated_with: :account` |
| Machine origin | `SOURCE_TYPES = %w[Operations::Signal]`, operator-triggered only (`support/ticket.rb:49`) | Customer-created in V1; inbound email in Phase 3 |
| Analytics scope | One account's own support performance | Lynomia's performance across all customers |
| Deletion | `destroy? = false` (`ticket_policy.rb:22`) | Same: never deleted, only closed |

The two are the same word and nothing else.

## 6. No feature flag, and why that is the safe answer

The tenant side of this module ships **ungated**: no entry in `config/features.yml`, no `BillingPlan` feature,
no 404 branch.

- A flag exists to sell or stage a capability. `BillingPlan.assignable_features` is the one consumer that turns
  a flag into a sellable entitlement (`custom/app/models/billing_plan.rb:41-48`). Lynomia's own support channel
  is not a capability Lynomia sells to itself.
- Gating it would reproduce precisely the failure the brief forbids: an account whose plan lacks the module
  cannot reach Lynomia to complain that its plan lacks the module.
- It also conserves a scarce resource. `feature_flags` is full at 63/63 and `features.yml:12-16` forbids adding
  to it; `feature_flags_ext_1` currently holds 11 of its 63 slots (`config/features.yml:271-317`). Not spending
  one here is a small bonus, not the reason.

Operational staging instead comes from the one thing that is always true: **the module is invisible until a
`PlatformSupport::Agent` exists**. With no staff row seeded, the Super Admin desk shows an explicit "no support
agents configured" state and the tenant entry can be withheld by the one-line sidebar change in §9 — which is a
deploy-time choice, not a per-account entitlement.

## 7. Staff identity: `PlatformSupport::Agent`, not raw `SuperAdmin`

`SuperAdmin` is unsuitable as a support workforce model, and the evidence is that it is not a workforce model
at all:

| Fact | Citation |
|---|---|
| `class SuperAdmin < User` with an empty body — STI on `users` | `app/models/super_admin.rb` |
| No `super_admins` table, no role column, no capability column | `grep -n 'create_table "super_admins"' db/schema.rb` → empty |
| `users.type` has no index | `db/schema.rb:1871-1908` |
| No Pundit anywhere on the Super Admin surface | `grep -rn "Punditize\|punditize" app custom lib config` → no matches |
| Administrate's base controller answers `authorized_action?` with `true` | `administrate-0.20.1/app/controllers/administrate/application_controller.rb` |

Consequences: every super admin can do everything; there is no way to express "may work support tickets but
may not edit billing plans"; and STI adds `WHERE type = 'SuperAdmin'` on *reads* only, so a column declared
`class_name: 'SuperAdmin'` will happily persist a plain tenant user's id.

`platform_support_agents` fixes all three for the cost of one table: assignment points at
`platform_support_agents.id`, so "only Lynomia staff can be an assignee" becomes a **foreign-key invariant**
rather than a validation somebody can bypass from a console. It is also where the brief's future "Lynomia
support-agent role" lives without handing that person the whole Super Admin console.

It does **not** fake account users as Lynomia employees: an `Agent` row references a `users` row (super admins
already are `users` rows) and creates no `AccountUser` anywhere.

## 8. Surfaces

| Surface | Auth | Rendering | Why |
|---|---|---|---|
| Tenant: `/app/accounts/:id/help/tickets` | Devise scope `:user`, account-scoped API | Vue, `components-next/` | Matches every other tenant page; `Current.account` does the scoping so `params[:account_id]` is never read (`support/base_controller.rb:8-9`) |
| Tenant API: `/api/v1/accounts/:account_id/platform_support/*` | `access_token` / cookie, Pundit | jbuilder | Mobile-ready with no new auth (`07-api-contract.md` §1) |
| Staff: `/super_admin/platform_support*` | Devise scope `:super_admin` + `PlatformSupport::Agent` check | server-rendered ERB in the Administrate shell | Inherits `authenticate_super_admin!` (`app/controllers/super_admin/application_controller.rb:17`) and the existing `super_admin_login/ip` + `/email` throttles (`rack_attack.rb:78-86`) |

The staff desk adds an authorization layer the Operations Center does not have (`PlatformSupport::Agent` must
exist and be active), because once staff identity is a real row, "is a super admin" stops being the same
question as "is a support agent". It stays a `before_action` calling a plain service object rather than a new
Pundit installation, because installing Pundit for one controller on a surface that has none is a
half-installed framework.

## 9. One production change this module cannot ship without

`Sidebar.vue:729-745` builds the `HelpAndSupport` group and ends its children with:

```js
].filter(child => child.href)
```

Today both children are external links, so the filter is invisible. A `My Tickets` entry uses `to:`, not
`href:`, so **it would be silently dropped**. The filter must become `child => child.href || child.to`.

A second, latent defect in the same area: `SidebarGroup.vue:113` is
`isReachable = child => child.href || (child.to && isAllowed(child.to))`, so an `href` child bypasses
`isAllowed` entirely. Harmless today (both are external), but it means a future internal destination rendered
as `href` would be ungated. Fixing it is not required by this module and is listed separately in
`09-implementation-plan.md` §8.

## 10. Inbound email: feasibility, not a V1 commitment

Inbound email infrastructure already exists — `app/mailboxes/application_mailbox.rb`,
`reply_mailbox.rb`, `mailbox_sanitizer.rb` and an `imap/` subtree. So `support@lynomia.com` → a
`PlatformSupport::Ticket` is a mailbox class plus a routing rule, not new infrastructure.

What today's architecture must not foreclose, and does not:

1. **A message author that is not a logged-in user.** `platform_support_messages.author_type` is a frozen
   allow-list string including `'System'`, and `author_name` is a snapshot, so an email-sourced reply has a
   place to be attributed.
2. **A ticket whose reporter is unknown.** `reporter_id` is nullable with a `reporter_name` snapshot.
3. **Reference-based threading.** A global `LYN-000001` in the subject line resolves to exactly one ticket
   installation-wide, with no "which account?" ambiguity — which a per-account reference could not do.
4. **Account attribution from the sender.** Resolvable through `users.email` → `AccountUser`.

That is the whole extent of the claim. It was not implemented or tested, and is listed in `00-discovery.md` §6
as not examined beyond confirming the files exist.
