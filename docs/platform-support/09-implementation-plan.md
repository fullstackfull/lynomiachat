# Platform Support Desk — implementation plan

> Phase 0. **Nothing in this plan is implemented.** It begins on your approval.

## 1. Phases

Each phase is independently reviewable, leaves the tree green, and ships nothing user-visible until Phase F.

| Phase | Scope | Files (approx) | Depends on |
|---|---|---|---|
| **A** | **Foundation.** M1–M3 (`agents`, `sla_policies`, `tickets`), the three models, constants, the global reference allocator, the Agent Administrate dashboard. No API, no UI | ~10 new, 2 touched (`routes.rb`, nav) | D-4, D-8 approved |
| **B** | **Thread.** M4–M6 (`messages`, `internal_notes`, `events`), the three models, the event writer service, the audit writer | ~8 new | A |
| **C** | **Tenant API.** Base controller, tickets + messages + events controllers, `PlatformSupport::TicketPolicy`, jbuilder serializers, exceptions, `en.yml` error keys, `billing_exempt?` | ~14 new, 1 touched (`access_guard.rb`) | B, D-1 approved |
| **D** | **Tenant UI.** Routes, three pages, seven components, API client, composable, `platformSupport.json` in EN **and** AR, the sidebar filter fix | ~16 new, 1 touched (`Sidebar.vue`) | C |
| **E** | **Staff desk.** Route drawer, controller, queue with four tabs + filters + search, detail page, reply, note, status/priority/category/assignee actions, nav item | ~14 new, 1 touched (`_navigation.html.erb`) | B |
| **F** | **SLA + notifications.** Clock service, policy resolution, the sweep job, warning/breach events, the SLA policy admin page, both mailers, the derived unread badge | ~14 new | C, E, D-7 approved |
| **G** | **Security specs.** The nine suites in `08-rollout-migrations.md` §7 | ~9 new | C, D, E, F |
| **H** | **Rate limits + attachments.** `Rack::Attack` rules, the authorized download controller, model-level size/MIME validation | ~4 new, 1 touched (`rack_attack.rb`) | C |
| **I** | **Pilot rollout.** The `InstallationConfig` account allow-list, UAT execution, removal of the allow-list | ~1 new | all |

Then, separately and only if approved: the suspension exemption (D-5), which touches
`ensure_current_account_helper.rb` and ships on its own.

Phase ordering note: **H precedes the pilot but follows C**, because an unthrottled write endpoint should not
reach even one real customer. It is listed after G only because the specs in G cover the paths H hardens.

## 2. What changes outside the new module, in total

Five files, each a small, independently revertible edit (`08-rollout-migrations.md` §1):

1. `config/routes.rb` — `draw :platform_support`
2. `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:744` — the filter predicate
3. `custom/app/controllers/billing/access_guard.rb:50-52` — one `||`
4. `app/views/super_admin/application/_navigation.html.erb` — one nav item + one exclusion-list entry
5. `config/initializers/rack_attack.rb` — new rules only

Plus additive locale keys. **No existing table, model, policy, serializer or job is modified.**

## 3. Not in scope, stated so it is not added by drift

Ticket deletion; customer-facing macros; a knowledge-base suggester on the new-ticket form; chat/live support;
teams; CSAT; inbound email; push and Slack delivery; business-hours SLA; a staff JSON API; per-(plan, priority)
SLA rows; typed resource links (Phase 2 per `02-data-model.md` §11); the notification bell
(`06-sla-notifications.md` §4).

## 4. Decisions requiring your approval before Phase A

| # | Decision | Recommendation | Blocks |
|---|---|---|---|
| **D-1** | Who inside a tenant sees the account's tickets | Administrators see all; agents see their own | Phase C |
| **D-2** | Confirm GLOBAL reference | **Global `LYN-000001`** — confirmed correct, with the concurrency and operational analysis in `02-data-model.md` §8 | Phase A |
| **D-3** | Staff desk language | English/LTR in V1, matching the surface | Phase E |
| **D-4** | Account deletion vs support history | `account_id` nullable + name snapshot: the record survives, the tenant cannot read it | Phase A |
| **D-5** | Suspended accounts and support access | Billing-locked: yes. Suspended: no in V1; `spam` never. Ships separately and last | separate |
| **D-6** | In-app notification bell for tenants | Not in V1; derived badge instead. Phase 2 carries a `ConversationVisibility` prerequisite | Phase F |
| **D-7** | Calendar-time SLA thresholds | Calendar time, with generous V1 thresholds. Needs the actual numbers from you | Phase F |
| **D-8** | SLA keyed on plan only, not (plan, priority) | Plan only in V1 | Phase A |
| **D-9** | The eleven categories and the six statuses as written | Accept both as given | Phase A |

## 5. Open questions with no recommendation — they are yours

1. **The actual SLA numbers.** First response and resolution targets per plan, in calendar hours. The
   architecture is indifferent; the commitment is not.
2. **The Lynomia support email alias** for operator notifications.
3. **Whether the pilot account is Account 21** ("Hisham Test") or a real customer.
4. **Who the first `PlatformSupport::Agent` rows are.**

## 6. Review gates — each a thing to check, not a thing to trust

| Gate | Check |
|---|---|
| No `audited` macro on any `platform_support_*` model | `grep -rn "audited" app/models/platform_support custom/app/models/platform_support` → empty |
| No `associated_with: :account` on any platform audit write | grep the audit writer |
| No tenant-reachable path to an internal note | `grep -rn "InternalNote" custom/app/controllers/api custom/app/views/api app/javascript` → empty |
| No `v-html` in the new components | `grep -rn "v-html" app/javascript/dashboard/components-next/PlatformSupport` → empty |
| No blob URL in any tenant response | `grep -rn "rails_blob\|rails_storage" custom/app/views/api/v1/accounts/platform_support` → empty |
| Policy scope carries its own account predicate | read `PlatformSupport::TicketPolicy::Scope#resolve` |
| Staff queue query count bounded | assert in spec, per `05-super-admin-operations.md` §2 |
| Analytics shows counts, not medians, below the stated minimum | read the dashboard view (`06-sla-notifications.md` §6) |
| Arabic file present and complete | `diff <(jq -r 'paths(scalars)\|join(".")' en/platformSupport.json) <(jq … ar/…)` → empty |
| Logical Tailwind utilities only | `grep -rnE "\b(ml|mr|pl|pr|left-|right-|text-left|text-right)-" components-next/PlatformSupport` → empty |

## 7. The 25 questions, answered

**1. Should Platform Support be a separate bounded context from the current Support Cases module?**
Yes. Six independent repository proofs in `01-architecture.md` §2; the decisive one is the
`AccountUser.exists?` membership validation at `custom/app/models/support/ticket.rb:145-151`, which a Lynomia
operator cannot satisfy.

**2. Which existing infrastructure can be safely reused?**
ActiveStorage, ActionMailer, `Rack::Attack`, `Custom::AuditLog` on the explicit-actor path,
`Billing::Entitlements` read-only, `Operations::Signal` as a link target, the Vue design system, the jbuilder
and `CustomExceptions` conventions, the Super Admin shell, and the SLA pause/resume *algebra*. Full table with
reasons in `01-architecture.md` §4.

**3. Which infrastructure must NOT be reused, and why?**
`Support::Ticket` / `support_ticket_events` (Q1); `Conversation` / `Message` (both require a fabricated inbox
and contact — `conversations.inbox_id` NOT NULL at `db/schema.rb:1077`, contact validated at
`app/models/conversation.rb:78`); the `audited` macro (Devise-scope actor misattribution,
`03-authorization-security.md` §10); the `notifications` table (four reasons,
`06-sla-notifications.md` §4); the `sla_policies` table (`account_id` NOT NULL, `db/schema.rb:1742`);
`operations_signals.support_ticket_id` (already taken).

**4. Is a dedicated message table required, or can an existing primitive be reused?**
Dedicated — two of them. No generic ordered-thread primitive exists that is not tied to a conversation, and the
two-table split (public messages / internal notes) is what makes internal-note secrecy structural rather than a
predicate (`02-data-model.md` §7).

**5. How should attachments be handled?**
ActiveStorage with `has_many_attached`, served only through a new controller that authorizes the parent record
and prepends `ActiveStorage::Streaming`. Never a blob URL: they never expire here. Server-side MIME allow-list
and size limits, because the existing `Attachment` validator returns early unless the inbox is WebWidget
(`app/models/attachment.rb:186-191`). No AV scanning, recorded as a limitation
(`03-authorization-security.md` §7).

**6. Can Super Admin users be used directly as support agents?**
No. `SuperAdmin` is STI on `users` with an empty body, no `super_admins` table, no role column, no index on
`users.type`, and no Pundit on the surface — so it carries no capability model, and STI constrains reads but
not writes. Hence `platform_support_agents` (`01-architecture.md` §7).

**7. Is a PlatformSupportAgent abstraction needed?**
Yes, in MVP. One table, one unique FK, and it turns "only Lynomia staff can be assigned" into a foreign-key
invariant. It is also where the brief's future dedicated support role lives (`02-data-model.md` §4).

**8. Should the reference be global or per-account?**
**Global**, confirming your preference. The deciding argument is operational, not technical: `LYN-000123`
resolves to one ticket in an email, a call or an escalation with no "which account?" follow-up, and it is the
precondition for reference-based email threading. Concurrency: a single installation-wide advisory lock,
transaction-scoped, on a human-rate operation (`02-data-model.md` §8).

**9. Is the proposed status set correct?**
Yes, accepted as written. Two notes: `waiting_on_lynomia` earns its place as customer-facing copy rather than
as a queue state, and `resolved`/`closed` must be integers 4 and 5 so the partial indexes can use `status < 4`
(`02-data-model.md` §5).

**10. Should categories be an enum or a table?**
A frozen Ruby constant on a string column — this repo's own pattern for a constrained type. A table buys
per-category routing, SLA and operator-managed taxonomy, all three of which are unrequested Phase 2 features,
and can be introduced later by backfilling from the constant (`02-data-model.md` §6).

**11. How should SLA be modelled, and should it reuse tenant SLAs?**
A separate `platform_support_sla_policies` table. Reuse is unsafe: `sla_policies.account_id` is NOT NULL. Plan
mapping is by `billing_plans.id`, never by name, because `billing_plans` has no tier or code column and `name`
is free text (`db/schema.rb:341-359`).

**12. Should `waiting_on_customer` pause the resolution SLA?**
**Yes — and it pauses all three clocks. `waiting_on_lynomia` pauses none.** Decided explicitly;
`06-sla-notifications.md` §3.

**13. Which notifications are needed, and through which channel?**
Four customer emails (created, operator reply, resolved, waiting-on-customer) and five operator emails
(`06-sla-notifications.md` §4). In-app for the customer is a derived badge from the ticket's own columns, not a
`notifications` row. No push, no Slack in V1 — both are additive against the same trigger set.

**14. How do we keep tenants isolated from each other?**
Three layers: the policy scope adds `where(account_id:)` itself (unlike the tenant module's, which delegates to
callers); the controller never reads `params[:account_id]`; the model refuses a cross-tenant reporter
(`03-authorization-security.md` §2).

**15. How do we prevent internal notes leaking?**
Structurally: a separate table with no tenant-reachable association, two serializer trees, no tenant route,
`internal_note_added` excluded from the customer-visible event allow-list, and attachment authorization
inherited from the parent class. Nothing depends on the front end
(`03-authorization-security.md` §5).

**16. How should billing lock interact with support access?**
One `||` in `billing_exempt?` (`custom/app/controllers/billing/access_guard.rb:50-52`), exempting exactly one
base class. The guard's second `before_action` is conditioned on the agents controller and never runs here, so
no second exemption is needed.

**17. How should suspended or abusive accounts be handled?**
Separately, because the suspension 401 fires in `ensure_current_account` **before** the billing gate
(`app/controllers/concerns/ensure_current_account_helper.rb:11`) — so the billing exemption does nothing for
them. The category is readable from `accounts.internal_attributes['suspensions']` via
`Account#suspension_history` (`app/models/account.rb:146-148`), so a `spam`-excluded carve-out is
implementable. Recommended as a separate, later, separately-reviewed change (D-5).

**18. What audit trail is required, and how do we keep it attributable?**
Explicit `Custom::AuditLog` writes with an explicit actor, on every assignment, priority, status, note, reply,
SLA and link change. **Never** the `audited` macro — the Sweeper resolves the actor through Devise's
`current_user` (scope `:user`) while a super admin is `:super_admin`, producing silent nil-or-wrong
attribution. **Never** `associated_with: :account` — that would publish operator activity to the customer's own
audit page (`03-authorization-security.md` §10).

**19. How should Operations Center data relate to tickets?**
One-way, operator-only, Phase 2: a `platform_support_links` row pointing at an `Operations::Signal`. Not
`operations_signals.support_ticket_id`, which the tenant case bridge already owns. The tenant serializer has no
`links` key, so Operations internals are never exposed (`02-data-model.md` §11).

**20. What is the right data model: A, B or C?**
**A.** Comparison table and the six proofs against C in `02-data-model.md` §1 and `01-architecture.md` §2.

**21. What should the namespace be?**
`PlatformSupport::`. `Platform::` is taken by the platform admin API (eleven controllers), `Support::` by the
tenant module, and `PlatformSupport` collides with nothing
(`grep -rn "PlatformSupport\|platform_support" app custom lib config db` → empty). Exceptions go in
`CustomExceptions::PlatformTickets`, following the shadowing hazard the existing module documents
(`lib/custom_exceptions/tickets.rb:4-6`).

**22. What is MVP vs later?**
MVP: tickets, thread, internal notes, assignment, status/priority/category, the four queues, account + billing
context, attachments, SLA with calendar time, email both directions, full audit, isolation specs. Phase 2 and
Future listed in `05-super-admin-operations.md` §8.

**23. What does the customer experience look like?**
A portal, not a CRM table: `Help & Support → My tickets`, card list, one-page create form, thread with plain
status language instead of enum names. EN + AR with logical Tailwind utilities from the first commit
(`04-customer-ux.md`).

**24. What analytics are possible, honestly?**
First response time, resolution time (both pause-adjusted via `sla_paused_seconds`), breach rates, volume by
category/priority/account/plan-at-creation, reopen rate, backlog age. **Not** possible and therefore not built:
handle time, CSAT, per-operator productivity, or any median below a stated minimum sample
(`06-sla-notifications.md` §6).

**25. Should inbound email be supported?**
Not in V1. It is feasible — `app/mailboxes/` already exists with `application_mailbox.rb`,
`reply_mailbox.rb` and `mailbox_sanitizer.rb` — and the V1 model deliberately does not foreclose it: a `System`
author type, a nullable reporter with a name snapshot, and a globally unique reference for subject-line
threading (`01-architecture.md` §10).

## 8. Pre-existing defects noted but not fixed here

| Defect | Location | Why not here |
|---|---|---|
| `href` children bypass `isAllowed` | `SidebarGroup.vue:113` | Latent, not triggered by this module (both existing children are external). Fixing it is a sidebar-authorization change deserving its own review |
| Non-Conversation notification actors pass the read-time narrowing unauthorized | `custom/app/services/notifications/conversation_visibility.rb:60,86-88,98` | Not triggered, because V1 writes no notification rows. Becomes a prerequisite only if D-6 is approved |
| `uniq_primary_actor_per_account_notifications` is not unique despite its name | `db/schema.rb:1590` | Pre-existing; same reason |
| Super Admin views are hard-coded English | `app/views/super_admin/operations/*.erb` (0 `t(` calls) | Surface-wide, not module-specific. D-3 |
