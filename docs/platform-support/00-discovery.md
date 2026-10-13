# Platform Support Desk — Phase 0 discovery

> Read-only discovery against `claude/platform-support-discovery`, branched from `lynomia-custom` HEAD
> `524bd8db`. Nothing in this phase changes behaviour, schema or production. Every claim below cites a file and
> line, or the command that produced it.

Method: eight parallel read-only subsystem readers plus one adversarial completeness critic that re-opened
every cited file. The critic found **four misstatements** in the readers' own output; those are recorded in §9
rather than quietly dropped, because a discovery document that hides its corrections is not evidence.

---

## 1. What already exists, and what it is not

### 1.1 The existing account-level Support Cases (P9)

`support_tickets` is one tenant-owned table plus a history table, both hard-scoped by a `NOT NULL account_id`.

| Fact | Citation |
|---|---|
| 26 columns + id; `account_id bigint NOT NULL` | `db/schema.rb:1763-1791` |
| 8 indexes; six lead with `account_id`; two bare (`contact_id`, `conversation_id`) | `db/schema.rb:1792-1799` |
| Two **partial** SLA indexes, both hard-coding `status < 4` | `db/schema.rb:1793,1796` |
| `support_tickets.account_id` is `ON DELETE CASCADE`; every other FK nullifies | `db/schema.rb:2006-2013` |
| A case holds **no messages, no attachments, no channel** — the customer thread is delegated to an optional `conversation_id` | `custom/app/models/support/ticket.rb:3-12` |
| `support_ticket_events` has **no** visibility / private / audience column | `db/schema.rb:1750-1760` |
| 16 allow-listed event types | `custom/app/models/support/ticket_event.rb:15-20` |
| Visibility is ownership: assignee OR my team OR I opened it, unless administrator or `support_ticket_manage` | `custom/app/policies/support/ticket_policy.rb:31-43` |
| `index?`/`create?` are unconditionally `true` for any account member; `destroy?` is always `false` | `custom/app/policies/support/ticket_policy.rb:17-23` |
| Reference is **per-account**: `pg_advisory_xact_lock(hashtext('support_tickets_reference'), account_id)` then `MAX+1` | `custom/app/services/support/tickets/reference_allocator.rb:19-27` |
| Six statuses; only `waiting_on_customer` pauses the SLA clock | `custom/app/models/support/ticket.rb:31-37` |
| Exactly one machine origin, and it is **manual**: an operator clicking "Open case" on a signal | `custom/app/services/operations/case_bridge.rb:39-49`; sole call site `custom/app/controllers/super_admin/operations_controller.rb:37` |
| The whole family 404s behind the account feature `lynomia_support_tickets` | `custom/app/controllers/api/v1/accounts/support/base_controller.rb:7,17-21` |

**The blocker that settles the bounded-context question.** `Support::Ticket` validates that every user it
references is a member of the owning account:

```ruby
return if AccountUser.exists?(account_id:, user_id:)
errors.add(name, 'must be a member of the same account')
```
`custom/app/models/support/ticket.rb:146-151`

A Lynomia staff member is not an `AccountUser` of the customer's account. So `assignee_id` and `created_by_id`
on this table **cannot** hold a Lynomia operator without deleting that validation — which is the validation
that keeps tenant cases tenant-scoped. See `01-architecture.md` §2.

### 1.2 Super Admin

| Fact | Citation |
|---|---|
| `class SuperAdmin < User` with an **empty body** — STI on `users`, discriminated by `users.type` | `app/models/super_admin.rb:47` |
| `users` has `t.string "type"` and **no index on it** | `db/schema.rb:1871-1908` |
| There is **no** `super_admins` table, no role column, no capability column | `grep -n 'create_table "super_admins"' db/schema.rb` → empty |
| Super admin signs in under Devise scope `:super_admin` | `app/controllers/super_admin/devise/sessions_controller.rb:14` |
| **No Pundit on the Super Admin surface at all** | `grep -rn "Punditize\|punditize" app custom lib config` → no matches |
| Administrate's controller inherits `ActionController::Base`, default `authorized_action?` → `true` | `administrate-0.20.1/app/controllers/administrate/application_controller.rb:2` |
| Super Admin layout has **no `dir` attribute** and the Operations views contain **zero** `t(` calls | `app/views/layouts/super_admin/application.html.erb:16`; `grep -c "t(" app/views/super_admin/operations/*.erb` → 0 for all 7 |

### 1.3 Thread and attachment primitives

| Fact | Citation |
|---|---|
| A `Message` cannot exist without a conversation and an inbox (`NOT NULL`) | `db/schema.rb` messages block; `app/models/message.rb` |
| A `Conversation` cannot exist without an inbox, and is not creatable without a contact | `app/models/conversation.rb:77-78,308`; `db/schema.rb:1077` |
| There is **no** existing generic ordered-thread table not tied to a conversation | reader searched notes/comments/events; none fits |
| `Attachment`'s size and MIME validation runs **only** for the web widget: `return unless message.inbox.channel_type == 'Channel::WebWidget'` | `app/models/attachment.rb:186-191` |
| Blob URLs **never expire**: no `urls_expire_in`, no `resolve_model_to_route` | `grep -rn "urls_expire_in\|resolve_model_to_route" config/ app/ custom/ lib/` → empty |
| The repo already prepends `ActiveStorage::Streaming` — the hook an authorized download would use | `config/initializers/active_storage.rb:27-46` |

### 1.4 Notifications

| Fact | Citation |
|---|---|
| `notifications.account_id`, `user_id`, `notification_type`, `primary_actor_type`, `primary_actor_id` are all `NOT NULL` | `db/schema.rb:1574-1594` |
| `notifications` has **no foreign keys at all** | `grep add_foreign_key db/schema.rb \| grep -i notif` → empty |
| `uniq_primary_actor_per_account_notifications` is **not unique** despite the name | `db/schema.rb:1590` |
| 8 notification types; `PRIMARY_ACTORS = ['Conversation']` | `app/models/notification.rb:38-56` |
| The index jbuilder calls `notification.primary_actor.push_event_data` **unconditionally** | `app/views/api/v1/accounts/notifications/index.json.jbuilder:17` |
| The read-time narrowing **passes through** any primary actor that is not Conversation or Message, with *zero* authorization | `custom/app/services/notifications/conversation_visibility.rb:60,86-88,98` |
| The dedup job keys on `user_id` + `primary_actor_id` only — ignoring type | `app/jobs/notification/remove_duplicate_notification_job.rb:7-15` |

### 1.5 Billing lock and suspension — **two different gates, and the brief's premise was wrong**

| Fact | Citation |
|---|---|
| `billing_exempt?` is a single class-identity test: `is_a?(Api::V1::Accounts::BillingController)` | `custom/app/controllers/billing/access_guard.rb:50-52` |
| `AccessGuard` installs **two** `before_action`s; `billing_exempt?` guards only the first | `custom/app/controllers/billing/access_guard.rb:14-17` |
| A locked account gets **402** `subscription_required` | `custom/app/controllers/billing/access_guard.rb:31-34` |
| **Suspension has zero schema presence** | `grep -c "suspension" db/schema.rb` → **0** |
| Suspension is `accounts.status` enum `{active: 0, suspended: 1}` | `app/models/account.rb:111` |
| `SUSPENSION_CATEGORIES = %w[spam non_payment other]` (stored outside the schema) | `app/models/account.rb:40` |
| A suspended account gets **401** `'Account is suspended'`, and that fires in `ensure_current_account` — **before** the billing 402 | `app/controllers/concerns/ensure_current_account_helper.rb:11` |
| `Billing::Entitlements.plan_for` returns `nil unless subscription.accessible?` | `custom/app/services/billing/entitlements.rb:79-83` |
| The support throttle is **GET-only**; there is no write throttle anywhere | `config/initializers/rack_attack.rb:384-387` |

> **Correction to the brief.** The brief says to "find the suspension columns/enum on Account
> (suspension_category, suspension_reason)". Those are *not* columns — `grep -c "suspension" db/schema.rb`
> returns 0. The Super Admin controller `extract!`s both out of the permitted params so neither is ever
> assigned as an attribute (`app/controllers/super_admin/accounts_controller.rb:51`), validates them
> (`:103-115`), and then writes them into `accounts.internal_attributes['suspensions']` as an append-only
> history of `{category, reason, suspended_at}` (`:127-152`). `Account#suspension_history` reads it back
> (`app/models/account.rb:146-148`) and `AccountStatusField` renders the latest entry
> (`app/fields/account_status_field.rb:17`).
>
> So the *lifecycle* state is `accounts.status`, and the *category* is available — in jsonb, not in a column,
> and not queryable by an index. That distinction decides whether the finer suspension rule in
> `03-authorization-security.md` §6 is implementable in V1. It is.

The consequence is architectural, not cosmetic: **extending `billing_exempt?` does nothing for a suspended
account**, because the 401 is raised one layer earlier. See `03-authorization-security.md` §6.

### 1.6 Operations and audit

| Fact | Citation |
|---|---|
| `Operations::Signal` has `belongs_to :account, optional: true` — a signal may be installation-wide | `custom/app/models/operations/signal.rb:43` |
| `operations_signals.support_ticket_id` already exists and is **taken** by the tenant case bridge | `db/schema.rb:1609`; FK nullify at `:2002` |
| `Operations::AccountHealth` is page-shaped; `row_for` is private; there is no single-account read | `custom/app/services/operations/account_health.rb` |
| Measured cost warnings in that file: `CountField` costs ~40 queries per 20 rows; `Billing::Settings.enforced?` was 75 of 85 queries at `PER_PAGE=25` | `custom/app/services/operations/account_health.rb:7-10,93-103` |
| `config/initializers/audited.rb` sets **only** `audit_class` — `current_user_method` is left at the gem default | `config/initializers/audited.rb:3-5` |
| `features.yml`: "The `feature_flags` column is FULL (63/63 slots used). Do NOT add to it." New flags **must** set `column: feature_flags_ext_1` | `config/features.yml:12-16` |

### 1.7 API, frontend and inbound email

| Fact | Citation |
|---|---|
| Swagger has 87 paths and **zero** Lynomia/custom endpoints | `python3 -c "...json.load(open('swagger/swagger.json'))..."` → `total paths: 87, custom hits: []` |
| The sidebar's `HelpAndSupport` group has exactly two **external `href`** children and ends `].filter(child => child.href)` | `Sidebar.vue:729-745` |
| `isReachable = child => child.href || (child.to && isAllowed(child.to))` — an `href` child bypasses gating entirely | `SidebarGroup.vue:113` |
| `isUpgradePageBypassRoute` names exactly 4 routes | `app/javascript/dashboard/helper/routeHelpers.js:149-155` |
| **Inbound email infrastructure already exists** and no reader had examined it | `ls app/mailboxes/` → `application_mailbox.rb`, `reply_mailbox.rb`, `mailbox_sanitizer.rb`, `imap/`, + helpers |

---

## 2. The two sidebar bugs this module would otherwise trip over

Both verified by the critic:

1. **Internal routes are silently dropped.** The `HelpAndSupport` children end with
   `.filter(child => child.href)` (`Sidebar.vue:744`). A new `My Tickets` entry uses `to:`, not `href:`, so it
   would vanish without error. The filter has to become `child => child.href || child.to`.
2. **`href` children bypass authorization.** `SidebarGroup.vue:113` short-circuits on `child.href` before
   consulting `isAllowed`. Today's two children are external links so nothing leaks, but it means the group's
   existing entries are ungated — relevant if a future entry is an internal link rendered as `href`.

---

## 3. The single most important risk, which only the critic found

**A `PlatformSupport::Ticket` declared with the `audited` macro would produce a staff audit trail that is
empty or attributed to the wrong person — silently.**

Verified chain:

1. `config/initializers/audited.rb:3-5` sets only `audit_class`; `current_user_method` stays at the gem
   default `:current_user` (`audited-5.4.1/lib/audited.rb:38`).
2. The Sweeper is installed on `ActionController::Base`
   (`audited-5.4.1/lib/audited/railtie.rb:8`), and Administrate's controller inherits it
   (`administrate-0.20.1/.../application_controller.rb:2`) — so **the Sweeper runs on every Super Admin
   request**.
3. The Sweeper resolves the actor by calling `controller.send(Audited.current_user_method)`
   (`audited-5.4.1/lib/audited/sweeper.rb:22-23`), i.e. Devise's `current_user`, which authenticates scope
   **`:user`**.
4. A super admin is signed in under scope **`:super_admin`**
   (`app/controllers/super_admin/devise/sessions_controller.rb:14`).

Two silent failure modes:

- **No co-resident session** → actor is `nil`, and `Custom::AuditLog#capture_actor_name` leaves `username`
  blank too (`custom/app/models/custom/audit_log.rb:45-51`). The row names nobody.
- **Co-resident session** → because `SuperAdmin` *is* a `users` row and the Super Admin nav links straight to
  the Agent Dashboard (`_navigation.html.erb:60`), one click gives the operator both sessions. Every
  subsequent `audited` row is attributed to the `:user`-scope principal. That is **misattribution**, and it is
  indistinguishable from a legitimate tenant-side edit.

The explicit-actor path is unaffected: `Billing::OverrideGrant` passes `user: @actor` directly
(`custom/app/services/billing/override_grant.rb:131-141`) and so bypasses the fallback. **The declarative
macro cannot be handed an actor.** Conclusion: staff accountability must use explicit `Custom::AuditLog`
writes, never `audited` on the platform tables. Recorded as the top security risk in
`03-authorization-security.md` §10.

---

## 4. Reuse inventory (summary; detail in `01-architecture.md` §4)

**Safe to reuse as-is:** ActiveStorage (with a new authorized-download controller), `Custom::AuditLog` on the
explicit-actor path, `Rack::Attack` (new write rules), `Operations::Signal` as a link target,
`Billing::Entitlements` for plan lookup (read-only), the Vue design system, the jbuilder/API conventions, the
`features.yml` flag mechanism (`feature_flags_ext_1` only).

**Reusable only after a named refactor:** the SLA arithmetic in
`custom/app/services/support/tickets/sla_clock.rb:39-66` (business-hours half is not reusable — `working_hours`
only exists on an inbox, `app/helpers/reporting_event_helper.rb:3-9,44`); `Operations::AccountHealth#row_for`
(private, page-shaped).

**Must NOT be reused:** `Support::Ticket` and `support_ticket_events` (§1.1 blocker), `Message`/`Conversation`
(would require fabricating inboxes and contacts), the `audited` macro for staff actions (§3), the existing
notification feed without a narrowing change (§1.4 pass-through), `operations_signals.support_ticket_id`
(already taken).

---

## 5. Open questions requiring a human decision

Carried into `09-implementation-plan.md` §7 and reported to the owner: who may open a ticket inside a tenant
(every member, as `Support::TicketPolicy` does, or administrators only); whether a `spam`-suspended account
keeps support access; whether the Super Admin desk may ship English-only/LTR; and whether Lynomia's own
support business hours get a calendar store in V1 or SLAs run on calendar time.

---

## 6. What was NOT examined

- The live production database (deliberately — no production access in this phase).
- `app/mailboxes/` beyond confirming it exists and listing it; the inbound-email design in
  `01-architecture.md` §8 is a feasibility argument, not a verified integration.
- Front-end rendering performance of a long thread.
- Any load testing of the central queue; the N+1 numbers quoted are the repo's own recorded measurements.

---

## 7. Corrections made to the readers' own output

The critic re-opened every load-bearing citation and spot-checked 27. Four did not hold:

| # | Reader claim | Reality |
|---|---|---|
| U1 | `EVENT_TYPES` has 15 values | **16** — `custom/app/models/support/ticket_event.rb:15-20` |
| U2 | `manage_all?` lacks safe navigation | It uses `&.` — `custom/app/policies/support/ticket_policy.rb:25,48-49` |
| U3 | No audit actor "because a super admin is not an AccountUser" | True conclusion, **wrong cause** — it is the Devise scope mismatch in §3 |
| U4 | The billing lock is "a single `before_action`" | **Two** — `access_guard.rb:14-17` |

U3 matters most: the wrong cause points at the wrong fix (granting staff `AccountUser` rows), which would
breach the tenant boundary this module exists to preserve.
