# Platform Support Desk — approved decisions and freeze record

> **STATUS: FROZEN AT DISCOVERY/ARCHITECTURE.** The architecture in `00`–`10` is approved. Implementation is
> intentionally paused until the separate **Product Refinement** phase is completed and merged into
> `lynomia-custom`.
>
> Branch `claude/platform-support-discovery`, architecture commit `f429fce1`, branched from `lynomia-custom`
> `524bd8db`. Nothing on this branch is implementation: no migration, no model, no controller, no production
> code. The branch is **not** merged.

## 1. Read this first when work resumes

1. Re-read this file. It is the authoritative record of what was approved; the chat transcript it came from is
   not durable.
2. Rebase/refresh the architecture against the then-current `lynomia-custom` HEAD. Product Refinement is
   expected to change the Operations Center, the documentation corpus, the Inbox and the Shopify surface, and
   **three of this module's cited anchors sit in files that phase is likely to touch** — see §4.
3. Only then begin Phase A from `09-implementation-plan.md` §1.

## 2. The nine decisions, as approved

| # | Decision | Approved outcome | Where it now lives |
|---|---|---|---|
| **D-1** | Tenant visibility | Account **administrators** see every ticket belonging to their account. A normal **agent** sees only tickets they personally created. Custom-role expansion deferred — no `CustomRole::PERMISSIONS` entry in V1; a custom-role holder is treated exactly as `agent` | `03` §1 |
| **D-2** | Reference format | Globally unique `LYN-000001` style references | `02` §8 |
| **D-3** | Staff desk language | English/LTR acceptable for the V1 Super Admin desk. **Tenant and customer surfaces remain EN + AR with RTL** | `04` §5, `05` §7 |
| **D-4** | Account deletion | Nullable `account_id` + a **minimal** account-name snapshot. Support and audit history preserved; the tenant cannot read an orphaned ticket | `02` §3 |
| **D-5** | Suspensions | Billing-locked accounts **must** reach Platform Support. Administratively suspended accounts get **no** exemption in V1. Spam/security suspension **never** gets an automatic bypass | `03` §6 |
| **D-6** | Notification bell | Deferred. The current notification path **must not** be reused until the positive allow-list authorization issue is fixed separately | `06` §4 |
| **D-7** | SLA targets | No numbers hard-coded. Policies stay configurable and data-driven, keyed by commercial plan/policy **record**, never by plan name in code. Actual targets approved when implementation resumes | `02` §10, `06` §2, §5 |
| **D-8** | SLA by plan | Approved for V1, through configurable policy records | `02` §10 |
| **D-9** | Taxonomy | The 11 categories and 6 statuses as proposed | `02` §5, §6 |

## 3. What the approvals changed in the architecture

Three approvals were **tighter** than the proposal. The documents were updated; this is the record of what
moved, so a reader of `f429fce1` alone is not misled.

| Approval | Proposal said | Approved state |
|---|---|---|
| **D-4** — "do not snapshot unnecessary personal or sensitive data" | `platform_support_tickets` carried a `reporter_email` snapshot, justified as "a reply address that survives the user record" | **`reporter_email` removed.** It is personal data and it is not necessary: the live address is reachable through `reporter_id` while the user exists, and once the user is deleted there is nobody to reply to. `reporter_name` is kept as the only personal-data snapshot, being the minimum that keeps a thread attributable — the same rule `Custom::AuditLog#capture_actor_name` already applies to every audit row (`custom/app/models/custom/audit_log.rb:45-51`) |
| **D-5** — suspended accounts get no exemption | A separate, later, separately-reviewed change to `app/controllers/concerns/ensure_current_account_helper.rb`, flagged **High** risk because it guards every account-scoped request | **That change is removed from the plan, not deferred.** The suspension guard is never edited. This deletes the highest-risk item from the risk register and the tenth phase from the plan |
| **D-6** — do not reuse the path until fixed separately | The `ConversationVisibility` allow-list fix was "a Phase 2 prerequisite" | **An absolute block.** No phase may write to `notifications` or add a `Notification::NOTIFICATION_TYPES` entry until `custom/app/services/notifications/conversation_visibility.rb:60,86-88,98` denies unknown primary-actor types by default. V1's derived unread badge needs none of it |

Three further standing constraints, approved alongside:

- **Support email alias stays configurable.** No address is hard-coded in code, config or seed. An installation
  with none configured sends no operator email and says so on the desk, rather than falling back to a built-in
  address. (`06` §4)
- **No staff identities seeded or invented.** Migrations create no `platform_support_agents` rows; who at
  Lynomia works support is an operator action in Super Admin. (`08` §3)
- **Account 21 is untouched.** It may be used for controlled UAT later; nothing about it changes now.

## 4. Preserved invariants — do not relitigate these at implementation time

These were approved explicitly and are load-bearing. Each is a decision whose *reason* is a specific line in
this repository, not a preference.

| Invariant | The line that makes it necessary |
|---|---|
| **Separate `PlatformSupport::` bounded context.** Not an extension of `Support::Ticket` | Six proofs in `01` §2; decisively `custom/app/models/support/ticket.rb:145-151`, the `AccountUser` membership validation a Lynomia operator cannot satisfy |
| **Explicit `Custom::AuditLog` writes with the real actor. The `audited` macro is never declared on a `platform_support_*` model** | `config/initializers/audited.rb:3-5` leaves `current_user_method` at the gem default, so the Sweeper resolves the actor through Devise's `current_user` (scope `:user`) while a super admin authenticates under `:super_admin`. Silent nil-or-wrong attribution. Full chain in `00` §3 |
| **Never `associated_with: :account` on a platform audit row** | `AuditTrail::Query` serves `Custom::AuditLog.for_account` to the tenant's own administrators with an `auditable_type` filter applied only when the request asks for one (`custom/app/services/audit_trail/query.rb:54,82`) — an account-associated row would publish operator activity to the customer's audit page |
| **Two tables for the thread: public messages and internal notes stay structurally separate** | Secrecy must not be a `where` clause anybody can forget. `02` §7 |
| **Tenant-visible events are a positive allow-list of event types** | Default-deny: a type added later is invisible to the customer until deliberately listed. `02` §9 |
| **The policy scope adds `where(account_id:)` itself** | Unlike `Support::TicketPolicy::Scope#resolve`, which carries no account predicate and relies on callers (`custom/app/policies/support/ticket_policy.rb:37-43`) |
| **404, never 403, for a ticket the caller may not see** | `03` §3 |
| **No feature flag; the desk is never gated or sold** | A customer whose plan excludes paid modules must still be able to complain about it. `01` §6 |

## 5. Anchors Product Refinement may invalidate

This module cites specific lines in files the Product Refinement phase is expected to change. **Re-verify each
before Phase A**; a stale anchor is a silent defect, not a formatting problem.

| Anchor | Cited as | Why it may move |
|---|---|---|
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:744` | `].filter(child => child.href)` — the one production edit this module requires, without which the `My tickets` entry is silently dropped | Product Refinement touches navigation and contextual help. **If that phase already fixes this filter, this module's Phase D has one fewer change** — verify rather than re-apply |
| `custom/app/services/operations/*`, `custom/app/controllers/super_admin/operations_controller.rb`, `app/views/super_admin/operations/*` | The precedent for a custom non-Administrate Super Admin page (`01` §4, `05` §1), and the measured N+1 warning (`05` §2) | Product Refinement rebuilds the Operations Center. The *precedent* may become a better one; the N+1 measurement may no longer describe the code |
| `custom/db/documentation/*`, `app/javascript/dashboard/helper/documentationLinks.js` | Not cited by this module today | Product Refinement expands documentation and the contextual-help registry. When this module ships, its tenant portal and its error states **should** route through whatever registry that phase establishes, instead of adding a parallel one |
| `app/views/super_admin/application/_navigation.html.erb:40,56` | The nav-item pattern and the Administrate exclusion list (`05` §1) | Any Super Admin UI modernization moves these line numbers |
| `custom/app/services/notifications/conversation_visibility.rb:60,86-88,98` | The D-6 block | Product Refinement touches notifications. **If it fixes the pass-through, the D-6 block lifts** — and that is the one change that would let a later phase reconsider the bell |

## 6. Still unanswered, and still needed before Phase A

Not blocking the freeze; blocking implementation.

1. **The SLA target values** — per plan, in calendar hours. D-7 keeps them out of code; they are still needed as
   data before the desk can promise anything.
2. **The Lynomia support email alias** — configurable, still unset.
3. **Who the first `PlatformSupport::Agent` rows are** — not to be invented.
4. **Which account is the pilot** — Account 21 is available but untouched for now.

## 7. Out of scope on this branch, permanently

This branch contains documentation only, and that is now final for it. The following are **not** here and must
not be added to it: migrations, models, controllers, policies, serializers, views, components, specs, locale
keys, route drawers, or any edit to an existing file. Implementation begins on a **new** branch cut from the
post-Product-Refinement `lynomia-custom`, following `09-implementation-plan.md` §1 and the corrections in §3
and §5 above.
