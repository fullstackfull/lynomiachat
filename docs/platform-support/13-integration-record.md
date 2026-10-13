# Platform Support Desk — integration record and gate status

> **STATUS: INTEGRATION COMPLETE. COMBINED GATE PARTIAL.** Branch `claude/platform-support`, cut from
> `lynomia-custom` `3cff6eb0`. Nothing is merged into `lynomia-custom`. Nothing is deployed.
>
> The frontend half of the gate ran and is green. **The Ruby half could not run in this session**: the
> container's PostgreSQL was restarted onto its packaged `pg_hba.conf` (local `peer`, TCP `scram-sha-256`),
> the session runs as an OS user with no matching database role, and every way to bridge that — relaxing
> `pg_hba`, setting a password on the `postgres` role, creating a role for the session user, or running the
> suite as the `postgres` OS user — was refused by the sandbox as a security change. §4 records exactly what
> ran, what did not, and what is therefore still unproven.

## 1. What was merged, in the contract's order

| # | Workstream | Branch tip | Scope |
|---|---|---|---|
| 1 | Core backend — domain, migrations, tenant API, policies, audit | `f252c6a3` | 66 files. Six migrations, six models, the tenant API, `PlatformSupport::TicketPolicy`, `AuditWriter`, `ReferenceAllocator` |
| 2 | Customer and staff surfaces | `0269680c` | 42 files. The tenant Vue pages and store, EN+AR locales, the Super Admin desk (queue, detail, six decisions), Operations Account 360 seam |
| 3 | SLA engine, notifications, attachments, hardening | `62c18487` | 40 files. `Sla::{Clock,PolicyResolver,State,Sweeper}`, `Notifications::ReplyNotifier`, `TicketMailer` + 7 templates, the notification allow-list branch, Rack::Attack throttles, the security suite |
| — | **Integration** | `69b7b373` + this commit | The wiring in §2, the seams in §3 |

Against the baseline: **166 files changed, ~16.2k insertions, 41 deletions**; 6 migrations; 39 spec files
holding **488 Ruby examples**; 5 frontend spec files holding **49 examples**.

## 2. What integration wired, and why there

Three agents each built a half of the same conversation. Integration gave every write exactly one owner, so the
staff desk and the tenant API cannot drift apart — a reply typed in Super Admin and a reply posted to the API
are now literally the same write.

| Service | Gained | Reason it lives there |
|---|---|---|
| `TicketCreation` | resolves the SLA policy, applies the clock, records `sla_policy_applied`, then mails the customer and the desk after the commit | Creation is the one moment a policy attaches. Measured from `created_at`, because the promise starts when the customer asked |
| `MessageCreation` | `Clock#record_first_response` in place of its own duplicate stamp; the `sla_first_response_met`/`_breached` event; `Clock#restart_resolution` on a customer reopen; after the commit, the one notification row and one email per side | A reply is the only trigger for all four, and this is the only writer of a reply |
| `TicketTransition` | `Clock#sync_pause` on every status change; the two customer emails that ask something (`resolved`, `waiting_on_customer`) | The pause rule reads the ticket's *current* status, so it belongs between the assignment and the save |
| `SuperAdmin::PlatformSupportActionsController` | validates input, then delegates to `MessageCreation`, `NoteCreation`, `TicketTransition`, `TicketAssignment`; `StaffAuthorizer` now answers both "is this person staff" and "may they reassign" | Eight inline writers deleted. The surface decides what a refusal says and where the operator lands; nothing else |
| `config/schedule.yml` | `platform_support_sla_sweep_job`, every five minutes, `housekeeping` | The job existed with no schedule; the tenant desk's own sweep is its neighbour at the same cadence |
| `lib/tasks/platform_support.rake` | `grant_agent`, `revoke_agent`, `agents` | **The bootstrap paradox**: no page can create the first `PlatformSupport::Agent`, and none is seeded. A page that created agent rows would need an agent row to protect it, or be open to every Super Admin — the distinction this module exists to draw |

Three services also **lock the ticket row** (`@ticket.lock!`) as the first statement of their transaction:
`TicketTransition`, `TicketAssignment` and `MessageCreation`. The staff controller held `with_lock` around every
mutation; consolidating onto the services would otherwise have dropped that silently. Each lock has a reason
stated at the call site — a `from` value read before the lock becomes a history row describing a state that
never existed.

## 3. Cross-agent seams closed at integration

Found only because the three halves were put together:

1. **Route drawer vs. views.** Agent 1 drew one-controller routes; Agent 2 built two controllers and called
   eight helpers. Rewritten to the singular `resource … collection` form; all **8 helpers verified present**
   against a booted app, and Administrate still enumerates both controllers.
2. **A duplicated opening message.** The detail page synthesized an opening bubble from `description` while
   `TicketCreation` writes it as a real message row. The computed property and its unused import are gone; the
   frontend fixture now carries the opening message the API actually returns.
3. **Operations Account 360 key shape.** The view read a flat key; the snapshot ships it nested.
4. **The mailer's `%{account}` interpolation.** Two operator subjects interpolate an account name the mailer
   never passed. Proven fixed: all **9 EN subject keys render with no `%{` left**.
5. **A contract disagreement about zero.** Agent 1's `SlaPolicy` refuses a non-positive threshold; Agent 3's
   clock spec built a policy holding `0`. Resolved in favour of the model: the refusal is the guarantee, and the
   spec now asserts it.
6. **Both contract stubs deleted** (Agent 3's stub file, Agent 2's 233-line scaffold) in favour of one real
   `spec/factories/platform_support.rb`; 12 spec files rewired to it.
7. **Eight dangling foreign keys in fixtures.** Agent 2 and Agent 3 built against stub schemas with no foreign
   keys, so four tickets carried `sla_policy_id: 7` and four internal notes carried `agent_id: 1`. Against the
   real schema — which has `add_foreign_key` on both — every one of those inserts is refused by PostgreSQL.
   All eight now create a real row through the factory.
8. **A defect in integration's own wiring, caught by reading Agent 1's spec rather than by running it.**
   Delegating the reopen's `resolution_breached_at = nil` to `Clock#restart_resolution` silently stopped
   clearing it when a ticket has no policy — reachable in production, because `sla_policy_id` is
   `on_delete: :nullify`, so deleting a policy leaves tickets holding a breach and no clock to ask. The
   lifecycle fact (a reopened ticket did not breach and finish) is now cleared unconditionally beside the other
   two timestamps; only the fresh due *time* is the clock's.

## 4. Gate results, as run

### Ran, with real exit codes

| Gate | Result |
|---|---|
| `bundle exec rubocop` (whole repository, 3022 files) | **0 offenses**. No cop disabled, no exclusion added; the two alignment offenses it found were fixed properly |
| `npx eslint` on every changed JS/Vue file | **0 errors**, 1 pre-existing dynamic-i18n-key warning |
| `pnpm vitest run` (whole frontend suite) | **499 files, 5393 examples, 0 failures, exit 0** |
| Platform Support frontend specs within that run | **49 examples, 0 failures** |
| App boot + `Rails.application.eager_load!` | **OK** — every constant in the wiring resolves, including the SLA, notifier and mailer references added at integration |
| The 8 staff route helpers | **all present**; 14 distinct Platform Support route paths drawn |
| 9 mailer subject keys, EN, with the real interpolations | **all render, none leaves a `%{}` unresolved** |
| `config/schedule.yml` | **15 entries; every class constantizes and every cron parses**; the new entry fires every 5 minutes |
| EN/AR locale parity, `platformSupport.json` | **93 = 93 keys, no gaps either way** |
| Static contract proofs | No blob URL, signed id or `url_for` in any tenant serializer; the tenant ticket serializer emits exactly its 18 contract keys and none of the forbidden ones; no `audited` macro on any `platform_support_*` model; no `associated:` on any Platform Support audit write; no feature gate on any endpoint or route; no hard-coded support address; **no SLA target value anywhere** (the only number is a 365-day sanity ceiling on the policy column); five Rack::Attack throttles present; `platform_support_reply` and `PlatformSupport::Ticket` present in `NOTIFICATION_TYPES`, `PRIMARY_ACTORS` and the visibility allow-list; every attribute the specs pass to a Platform Support model exists in `db/schema.rb` (49 columns, 6 tables) |

### Did not run

**488 Ruby examples across 39 spec files**, and with them most of doc 12 §10: isolation and IDOR, staff
authorization, internal-note secrecy, the attachment proofs, the reference allocator under concurrency,
transitions, billing-lock vs. suspension, audit attribution, the six notification proofs, the SLA suite, the
rate limits, and the query budgets. They are blocked on database access, not on the code: see the status note
at the top.

What is known about them: all 488 passed in the agents' own worktrees before integration (259 + 322 + 150
examples in three separate runs), and integration has since changed four production files, two of which are
covered by new examples added here. Until the suite runs on this branch, **treat §10 as unproven**.

### Added here, unrun

Integration wired behaviour that no agent could have covered, so it carries its own examples: the SLA policy
resolved and applied at creation (3), the two creation mails (1), the reply's bell row and the two reply mails
(2), the first-response outcome met / breached / not-promised (3), the pause rule and its resume (4), the two
status mails and the silence of every other transition (3), the staff reply's consequences and its refusal on a
closed ticket (2). **18 examples, written but not run.**

## 5. V1 limitations the owner should decide on

1. **A billing-locked customer cannot attach a file.** The desk is exempt from the billing guard, but the
   shared `/api/v1/accounts/:id/upload` endpoint is not, and doc 03 §7 deliberately routes attachments through
   it rather than adding a second upload path. The customer can still open the ticket and describe the problem;
   the picker shows a readable upload failure. Exempting the shared endpoint would turn a locked account into
   free file hosting with non-expiring blob URLs, so the fix is a product decision, not a patch.
2. **The 25 MB per-ticket aggregate** in doc 03 is not implemented; per-file (10 MB), per-message (5 files) and
   the content-type allow-list are.
3. **No 404-probe throttle** on the attachment route beyond the five existing throttles.
4. **`swagger/swagger.json` is untouched**, so the tenant endpoints are undocumented there (doc 07 §9 wanted
   them; still the first Lynomia module that would have a published contract).
5. **The unread marker is per account, not per user**: `customer_last_viewed_at` is one column on the ticket.
6. **Arabic mailer subjects fall back to English.** Backend strings live in `en.yml` and Crowdin owns the rest
   (CLAUDE.md); `config.i18n.fallbacks` makes that a silent, correct fallback rather than a blank subject.
7. **Still required as data, not code**: the SLA target values, the support email alias, and the first agent
   rows. Until they exist the desk promises nothing, sends no operator mail, and refuses every staff action —
   each the intended fail-closed state, and the rake task in §2 is how the third one is answered.

## 6. Before this may merge into `lynomia-custom`

1. Run the 488 + 18 Ruby examples on this branch and fix whatever they find.
2. Run `bundle exec rails db:migrate` forward and back on a scratch database to re-prove the byte-identical
   schema round trip on the merged branch (Agent 1 proved it on theirs).
3. Re-run the repository gates on a clean tree and record the exit codes.
4. Then, and only with owner approval, merge. Nothing here is deployed by this session.
