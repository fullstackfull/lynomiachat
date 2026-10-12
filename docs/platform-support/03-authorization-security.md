# Platform Support Desk — authorization and security

> Phase 0. Addresses all eleven security requirements in the brief, in order, plus the one risk discovery
> found that the brief did not anticipate (§10).

## 1. The authorization boundary, per actor

| Actor | May | May not |
|---|---|---|
| Tenant administrator | Open tickets for their account; read every ticket of their account; reply publicly; attach files; read customer-visible events | See internal notes, operator identity, SLA targets, links, `metadata`, or any other account's ticket |
| Tenant agent (built-in `agent`) | Open a ticket; read and reply on tickets **they reported**; attach files | See other members' tickets in the same account (see D-1) |
| Tenant member with a custom role | Exactly the same as `agent`. No `CustomRole::PERMISSIONS` entry governs this module and none is added | — |
| Lynomia Super Admin **without** a `PlatformSupport::Agent` row | Nothing on the desk; the page renders an explicit "you are not a support agent" state | Read, reply, assign, or note |
| `PlatformSupport::Agent` (`role: agent`) | Read every ticket; reply; note; change status, priority, category; assign to self; pick up unassigned; read account context | Reassign another agent's ticket; edit SLA policies; create agents |
| `PlatformSupport::Agent` (`role: lead`) | Everything an agent may, plus reassign across agents and edit SLA policies | Create agents (that stays an Administrate/`super_admin` action) |
| Future dedicated Lynomia support role | The `agent` row exists already; the only change is relaxing the `user.is_a?(SuperAdmin)` create validation (`02-data-model.md` §4) | — |

> **D-1 — APPROVED as proposed.** Account administrators see every Platform Support ticket belonging to their
> account; a normal agent sees only the tickets they personally created. Custom-role expansion is explicitly
> deferred, so no `CustomRole::PERMISSIONS` entry is added for this module in V1 and the custom-role holder is
> treated exactly as `agent` (the row above).

## 2. Requirement 1 — cross-tenant isolation

Three independent layers, so no single omission leaks:

1. **The policy scope adds the predicate itself.**
   ```ruby
   class PlatformSupport::TicketPolicy < ApplicationPolicy
     class Scope < ApplicationPolicy::Scope
       def resolve
         base = scope.where(account_id: account.id)   # <-- here, not in the caller
         return base if account_user&.administrator?
         base.where(reporter_id: user.id)
       end
     end
   end
   ```
   This is a deliberate departure from `Support::TicketPolicy::Scope#resolve`, which carries **no** account
   predicate and relies on each caller supplying one (`ticket_policy.rb:37-43`, and
   `base_controller.rb:28-30`). That arrangement is safe today because there are two callers. A cross-account
   table cannot afford to depend on caller discipline.
2. **The controller never reads `params[:account_id]`.** `Current.account` is set by
   `Api::V1::Accounts::BaseController`; the existing support base controller records this explicitly —
   *"`params[:account_id]` is never read here"*
   (`custom/app/controllers/api/v1/accounts/support/base_controller.rb:5-6`).
3. **The model refuses a cross-tenant write.** `reporter` must be an `AccountUser` of `account_id`, which is
   the same net `Support::Ticket#validate_user_in_account` provides (`support/ticket.rb:145-151`) — reused
   here for the *reporter*, where it is correct, and never for the assignee, where it was the blocker.

## 3. Requirement 2 — IDOR, and 404 over 403

Every tenant lookup goes through the policy scope, so a foreign or non-existent id raises
`ActiveRecord::RecordNotFound` and renders 404. The pattern already exists and already carries the reason in a
comment: *"Found through the policy scope, so a case the caller may not see is a 404 and not a 403 that
confirms it exists"* (`custom/app/controllers/api/v1/accounts/support/tickets_controller.rb:40-47`).

Reference lookup needs one extra note. A global `LYN-` sequence means `find_by!(reference_number: n)` would
reach any account's ticket — but the tenant controller resolves it *inside* the already-account-scoped policy
scope, so the predicate is applied first and the lookup cannot escape. Stated so the implementer does not
"optimise" the scope away:

```ruby
ticket_scope.find_by!(reference_number: PlatformSupport::Ticket.reference_number_from(params[:id]))
```

Probing is additionally rate-limited (§8).

## 4. Requirement 3 — Super Admin session isolation

Super admin authenticates under Devise scope `:super_admin`
(`app/controllers/super_admin/devise/sessions_controller.rb:14`); tenant users under `:user`. Warden keys both
scopes into one cookie, so **one browser can hold both sessions at once** — and the Super Admin navigation
links straight to the agent dashboard (`app/views/super_admin/application/_navigation.html.erb:60`,
`url: '/'`), which is how an operator acquires both with one click.

What this module must therefore never do:

- **Never derive staff authority from `Current.user`.** The staff controllers read `current_super_admin` and
  then resolve a `PlatformSupport::Agent`; the tenant controllers read `Current.user` and never look at
  `current_super_admin`. The two code paths share no authorization helper.
- **Never derive tenant authority from `current_super_admin`.** There is no "view as customer" affordance in
  V1. An operator who needs to see what the customer sees reads the customer-visible event list and public
  messages rendered on the staff page from the same allow-list the tenant serializer uses.
- **Never let the `audited` macro infer an actor** — §10, and it is the same root cause.

## 5. Requirement 4 — internal note secrecy, enforced structurally

| Layer | Mechanism |
|---|---|
| Schema | A separate table (`platform_support_internal_notes`). There is no `visibility` predicate to forget (`02-data-model.md` §7) |
| Model | `PlatformSupport::Ticket has_many :messages` and `has_many :internal_notes`; the tenant-facing query object references only the former |
| Serializer | Two serializer trees. `api/v1/accounts/platform_support/tickets/_ticket.json.jbuilder` has no `internal_notes` key and no `links` key. The staff ERB is the only renderer that touches notes |
| Controller | The tenant routes expose `messages` only: there is no tenant route whose controller could render a note (`07-api-contract.md` §2) |
| Events | `internal_note_added` is excluded from `CUSTOMER_VISIBLE_EVENT_TYPES`, so the *existence* of a note is also hidden |
| Attachments | A note's attachments are staff-only because of their parent class, with no flag to check (§7) |

No part of this relies on the front end.

## 6. Requirements 6 and 7 — billing lock, and suspension as a separate question

### Billing lock: one `||`, and nothing else

```ruby
def billing_exempt?
  is_a?(Api::V1::Accounts::BillingController)
end
```
`custom/app/controllers/billing/access_guard.rb:50-52`

The change is to add `|| is_a?(Api::V1::Accounts::PlatformSupport::BaseController)`. That is the narrowest
possible form: it exempts exactly the controllers under that one base class and cannot be widened by accident,
because widening it means editing this method.

What it does **not** touch: `AccessGuard` installs two `before_action`s (`:15-17`), and the second,
`ensure_agent_limit`, is conditioned on `controller_name == 'agents'` (`:16`), so it never runs for this module
at all. No second exemption is needed, and adding one would be the speculative guard CLAUDE.md forbids.

### Suspension is a different gate, one layer earlier

```ruby
render_unauthorized('Account is suspended') and return unless account.active?
```
`app/controllers/concerns/ensure_current_account_helper.rb:11`

This 401 fires in `ensure_current_account`, **before** `ensure_billing_access` ever runs. So **extending
`billing_exempt?` does nothing for a suspended account.** Any support access for a suspended account requires a
separate, equally narrow exception at this point.

The data needed to make that call is available, though not where the brief expected it:

- `accounts.status` is `enum { active: 0, suspended: 1 }` (`app/models/account.rb:111`).
- `SUSPENSION_CATEGORIES = %w[spam non_payment other]` (`app/models/account.rb:40`).
- `suspension_category` and `suspension_reason` are **not columns** — `grep -c "suspension" db/schema.rb` → 0.
  The Super Admin controller `extract!`s both out of the permitted params (`accounts_controller.rb:51`),
  validates them (`:103-115`), and writes them into `accounts.internal_attributes['suspensions']` as an
  append-only `{category, reason, suspended_at}` history (`:127-152`).
- `Account#suspension_history` reads it back (`app/models/account.rb:146-148`).

So the finer rule **is** implementable: `account.suspension_history.last&.dig('category')`.

**Recommendation:** a non-payment or `other` suspension keeps support access; a `spam` suspension does not. A
spam-suspended account is one Lynomia has decided is abusive, and a support desk is a free-text channel into
Lynomia's own staff inbox — exactly what an abusive account would use it for. Non-payment is the opposite: it
is the case the brief is about.

> **D-5 — APPROVED, and simpler than the proposal.** The approved V1 rule is:
>
> | Account state | Reaches Platform Support in V1? |
> |---|---|
> | Billing-locked (402, no accessible subscription) | **Yes** — the exemption in this section exists for exactly this case |
> | Administratively suspended (`accounts.status = suspended`) | **No.** No exemption in V1 |
> | Suspended for spam or security | **No, and never automatically.** Explicitly excluded from any future exemption |
>
> Because suspended accounts get no exemption at all in V1, **`ensure_current_account_helper.rb` is not
> touched** — the 401 stands as written. That removes the highest-risk edit in `08-rollout-migrations.md` §5
> from the plan entirely. The `suspension_history` jsonb read is not needed either; it stays documented above
> only as evidence that a finer rule would be *implementable* if a later phase ever wants one for `non_payment`,
> and the spam/security exclusion above is a standing constraint on that phase.

Implementation shape either way: a named predicate on the concern (`support_desk_exempt?`) checked alongside
`account.active?`, not a parallel code path. The 401's message must not change for any other request.

## 7. Requirement 5 — attachments

| Control | Decision | Reason |
|---|---|---|
| Storage | ActiveStorage, `has_many_attached :files` on both message models | No second blob store (`01-architecture.md` §4) |
| Download | A new controller prepending `ActiveStorage::Streaming`, authorizing against the *parent record* before serving | Blob URLs never expire here: `grep -rn "urls_expire_in\|resolve_model_to_route" config/ app/ custom/ lib/` → empty. A signed blob URL is therefore a permanent bearer token. The repo already prepends `ActiveStorage::Streaming` (`config/initializers/active_storage.rb:27-46`), so the hook exists |
| Never | Expose `rails_blob_path` / `rails_storage_proxy_path` for these attachments in any serializer | The brief: *"Never expose ActiveStorage blobs simply because somebody knows the URL"* |
| MIME allow-list | `image/png image/jpeg image/gif image/webp application/pdf text/plain text/csv` | Covers a screenshot, an invoice and a log excerpt, which is the whole realistic set. Archives are excluded: a zip cannot be inspected and is the standard malware carrier |
| Max size | 10 MB per file, 5 files per message, 25 MB per ticket | Enforced server-side at the model. The existing `Attachment` validator cannot be reused: it returns early unless the inbox channel is WebWidget (`app/models/attachment.rb:186-191`), and these records have no inbox |
| Disposition | Inline only for what the installation already allows inline (images, PDF, and the audio types added at `config/initializers/active_storage.rb:5-13`); `attachment` for everything else | Prevents a `text/html` upload rendering in the operator's session |
| Malware scanning | **None. Stated as a known limitation** | No scanner exists: `grep -rniE "clamav\|virus_scan\|malware" Gemfile config/ app/ custom/` finds only a test fixture filename. Adding one is infrastructure, not application code, and belongs in a separate decision |
| Direct upload | Through the existing scoped, authenticated upload endpoints | The bare Rails direct-upload route is already blocked (`config/initializers/active_storage.rb:48+`) |

## 8. Requirement 8 — rate limiting and spam

The existing support throttle is **GET-only** (`config/initializers/rack_attack.rb:384-387`), so there is no
write limit anywhere in the module family today. New rules, keyed with the existing `account_user_key` helper
(`:371-379`):

| Rule | Limit | Period | Rationale |
|---|---|---|---|
| Ticket create, per user | 5 | 1 hour | A human opening a sixth ticket in an hour is either confused or abusive; both want a human, not a form |
| Ticket create, per account | 20 | 1 hour | Stops one account's whole team being used as a pool |
| Message create, per user | 30 | 1 hour | Generous for a real conversation |
| Any `platform_support` request, per user | 300 | 1 minute | Mirrors the existing GET limit, extended to writes |
| Reference probing: 404s on `tickets/:id`, per IP | 30 | 1 minute | Enumeration defence for the global sequence (§3) |

All limits read from `ENV.fetch('RATE_LIMIT_…', default)`, the convention every existing rule uses.

Application-level spam control, which rate limits cannot provide: a ticket with an empty `description` is a 422
at the boundary; duplicate-subject detection is **not** built (it produces false positives on "WhatsApp down
again" and the staff queue's merge affordance handles the real case better).

## 9. Requirement 9 — XSS and content sanitisation

- `body` is a `text` column holding **plain text**. There is no HTML column, no markdown column, and no rich
  editor.
- Tenant rendering is Vue interpolation, which escapes by default. **No `v-html` in any component of this
  module** — stated as a review gate in `09-implementation-plan.md` §6.
- Staff rendering is ERB `<%= %>`, which escapes by default. No `raw`, no `html_safe`, no `sanitize` — because
  `sanitize` implies HTML is expected, and it is not.
- Attachment filenames are rendered as text and the download controller sets the filename from the blob, never
  from a request parameter.
- If inbound email arrives in Phase 3, `app/mailboxes/mailbox_sanitizer.rb` is the existing tool for stripping
  an HTML email body down to text. Not needed in V1.

## 10. Requirement 10 — audit, and the risk that nearly shipped silently

### The risk

**Declaring `audited` on `PlatformSupport::Ticket` would produce a staff audit trail that is empty or
attributed to the wrong person, with no error.** Verified chain:

1. `config/initializers/audited.rb:3-5` sets only `audit_class`. `Audited.current_user_method` stays at the gem
   default `:current_user` (`audited-5.4.1/lib/audited.rb:38`).
2. The Sweeper is installed on `ActionController::Base` (`audited-5.4.1/lib/audited/railtie.rb:8`), and
   Administrate's controller inherits it, so **the Sweeper runs on every Super Admin request**.
3. The Sweeper resolves the actor with `controller.send(Audited.current_user_method)`
   (`audited-5.4.1/lib/audited/sweeper.rb:22-23`) — Devise's `current_user`, scope `:user`.
4. A super admin is authenticated under scope `:super_admin`.

Outcomes: with no co-resident tenant session the actor is `nil` and `username` is blank too, because
`Custom::AuditLog#capture_actor_name` falls back through `user.try(...)`
(`custom/app/models/custom/audit_log.rb:45-51`) — the row names nobody. With a co-resident session (one click
from the Super Admin nav) every row is attributed to the `:user`-scope principal, indistinguishable from a
legitimate tenant-side edit.

### The rule

**Staff accountability uses explicit `Custom::AuditLog` writes with an explicit actor. The `audited` macro is
never declared on any `platform_support_*` model.** The explicit path is unaffected by the fallback —
`Billing::OverrideGrant` passes `user: @actor` directly
(`custom/app/services/billing/override_grant.rb:131-141`) and is the precedent to copy **for the actor only**:
that writer also passes `associated: @account` (`:133`), which is right for a billing override — the account's
administrators should see that their entitlements were changed — and wrong here, for the reason below.

**And never `associated_with: :account`.** `AuditTrail::Query` serves `Custom::AuditLog.for_account(@account)`
to the tenant's own administrators (`custom/app/services/audit_trail/query.rb:54`) with an `auditable_type`
filter applied only when the request asks for one (`:82`). An account-associated audit row for a platform
ticket would appear on the customer's Audit Logs page. Platform-support audit rows carry **no** `associated`,
which is what makes them installation-wide and correctly invisible there — the same arrangement
`custom/app/services/billing/plan_audit.rb` already uses, and which `Custom::AuditLog`'s own header documents
(`custom/app/models/custom/audit_log.rb:24-26`).

### What is audited

Every one the brief lists, as an explicit write: assignment change, priority change, status change, internal
note added, public reply sent, SLA policy applied or changed, link added or removed, agent created or
deactivated. Each row carries the acting `PlatformSupport::Agent`'s user, the ticket reference, and the
before/after values — never the message body (the same exclusion `Support::Ticket` applies with
`except: [:description]`, and for the same reason: *"an audit row is not the place for a second copy of it"*,
`support/ticket.rb:20-24`).

Retention: the existing 365-day audit retention applies, with no new mechanism.

## 11. Requirement 11 — no secrets, ever, into a ticket

Hard rule: **nothing in this module copies an exception, a provider payload, a header or a token into a
ticket, a message, a note or an event.** Specifically:

- There is no "attach diagnostics" button, no "include last error" checkbox, and no automatic ticket creation
  from an exception. The only machine writer is the SLA sweep, which writes `sla_*` events carrying timestamps
  and nothing else.
- `events.metadata` holds enum values and ids. The event writer is one service with a fixed per-event-type
  payload shape; it does not accept a free-form hash from a caller.
- `AuditTrail::Secrets.scrub` runs on every `Custom::AuditLog` write via `before_save :drop_secret_changes`
  (`custom/app/models/custom/audit_log.rb:18,53-57`), so the audit path is covered by the existing second line of
  defence whether or not the writer was careful.
- If a future phase links a ticket to an `Operations::Signal`, the tenant serializer still emits no links
  (`02-data-model.md` §11), so a signal's `detail` jsonb — which does carry provider reasons — never reaches a
  customer.

## 12. What this module deliberately does not harden

Stated so it is not mistaken for coverage:

- **The `SidebarGroup.vue:113` `href` bypass** is a pre-existing latent defect, not introduced here, and
  fixing it is listed separately (`09-implementation-plan.md` §8).
- **The tenant notification feed's non-Conversation pass-through**
  (`custom/app/services/notifications/conversation_visibility.rb:60,86-88,98`) is left untouched, because V1
  writes nothing to that table (`06-sla-notifications.md` §4). It becomes a prerequisite the moment Phase 2
  wants these in the bell.
- **No AV scanning** (§7).
- **The Super Admin surface has no Pundit and this module does not install it** (`01-architecture.md` §8).
