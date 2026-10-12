# Platform Support Desk — UAT plan

> Phase 0. Written now so the acceptance criteria are agreed before anything is built. **Nothing here has been
> executed.**

## 1. Preconditions

| # | Precondition | How to confirm |
|---|---|---|
| P1 | Phases A–H deployed; `rails db:migrate:status` clean | seven `platform_support_*` tables present |
| P2 | At least two `PlatformSupport::Agent` rows, one `agent` and one `lead` | `/super_admin/platform_support_agents` |
| P3 | A default SLA policy (the `billing_plan_id IS NULL` row) with agreed thresholds | the SLA policy page |
| P4 | The support alias `InstallationConfig` set | `/super_admin/installation_configs` |
| P5 | **Two** tenant accounts, each with an administrator and a non-admin agent | Super Admin → Accounts |
| P6 | Account A on a plan that has its own SLA policy; Account B on a plan that does not | so the fallback path is exercised |
| P7 | A third account that is **billing-locked** (no accessible subscription) | `Billing::TrialStarter.subscription_for` → inaccessible |
| P8 | A fourth account **suspended** | `accounts.status = suspended` |

Accounts A and B must be genuinely separate tenants with no shared users. Every isolation test in §3 is
meaningless if a user is a member of both.

## 2. Functional scenarios

| # | Scenario | Expected |
|---|---|---|
| F1 | Account A admin: sidebar → Help & Support | **`My tickets` is present** — this is the one that proves the `Sidebar.vue:744` filter fix landed. Documentation and Contact support still present and still external |
| F2 | A admin opens My tickets with no tickets | Empty state explains what the desk is for *and* what it is not (Inbox is for your own customers) |
| F3 | A admin creates a ticket: category `whatsapp`, subject, description, priority `high`, one PNG attachment | 201; lands on the detail page; reference is `LYN-0000NN`; "a Lynomia engineer will reply here" |
| F4 | Second ticket created from Account B | Reference is the **next global number**, not `LYN-000001` — proves the sequence is global |
| F5 | Operator opens the desk | Both tickets visible in **Needs us**, with account name and plan name per row |
| F6 | Operator assigns F3's ticket to themselves, sets priority `urgent` | Both write events and `Custom::AuditLog` rows; the customer sees **neither** event |
| F7 | Operator adds an internal note | Visible on the staff detail page, visually distinct; `last_operator_message_at` **unchanged** |
| F8 | A admin reloads the ticket | No note, no note-shaped gap, no `internal_note_added` event, no operator name |
| F9 | Operator sends a public reply | Customer sees it attributed to **"Lynomia Support"**, never the individual's name |
| F10 | A admin reloads | Reply visible; unread dot shown; sidebar badge shows 1 |
| F11 | A admin opens the detail page, then returns to the list | Dot and badge cleared (`customer_last_viewed_at` stamped) |
| F12 | A admin replies with a 9 MB PDF | Accepted; operator can download it |
| F13 | A admin tries a 12 MB file, then a `.zip` | Both 422, each naming the limit / accepted types **before** the attempt and in the error |
| F14 | Operator sets status `waiting_on_customer` | Customer reads "We need something from you"; the SLA header shows **paused** |
| F15 | Operator sets status back to `in_progress` | Due times moved forward by exactly the paused duration; `sla_paused_seconds` reflects it |
| F16 | Operator resolves | Customer reads "Resolved. Reply here if it is not fixed." Resolution email sent |
| F17 | A admin replies to the resolved ticket | Ticket **reopens**; `reopened` event; a fresh resolution target; `resolution_breached_at` cleared |
| F18 | Operator closes | Customer's reply box is replaced by "Open a new ticket"; a reply attempt is 422 |
| F19 | Account A's **non-admin agent** opens Help & Support | `My tickets` present; sees only tickets they reported (D-1) |
| F20 | That agent creates a ticket; the A admin reloads | The admin sees it; the agent does not see the admin's ticket |
| F21 | Operator downloads an attachment from an internal note, then an attachment from a public message | Both work for the operator |
| F22 | Lead reassigns the `agent`'s ticket; then the `agent` attempts to reassign the lead's | First succeeds, second is refused |
| F23 | Deactivate an agent holding an open ticket | Ticket stays assigned; appears in **Reassign needed**; not silently unassigned |
| F24 | Account B's ticket: no plan-specific SLA policy | Falls back to the default policy; header shows the default targets, labelled **calendar** hours |
| F25 | Remove the default policy; create a new ticket | Header reads "no target set" — not a zero, not a blank |
| F26 | Reference search: operator types `LYN-000003`, then `3` | Both find the same ticket |
| F27 | Operator queue tabs | Needs us / Customer replied / Unassigned / SLA at risk / Mine / All each return the right set; header counts match the rows |
| F28 | Trigger the SLA sweep past a resolution target | `sla_resolution_breached` event; red in the header; ticket appears in **SLA at risk**; breach email to assignee and alias; **customer sees no SLA event** |
| F29 | Re-run the sweep | Writes nothing new (idempotent via the partial index) |
| F30 | Arabic: A admin switches locale to Arabic | Every label, status sentence, category name, empty state and error is Arabic; layout is RTL; chips, dots and chevrons mirror correctly; no Latin string leaks |

## 3. Isolation and security scenarios — the ones that must not be waived

| # | Scenario | Expected |
|---|---|---|
| S1 | Account B admin requests `GET /api/v1/accounts/<B>/platform_support/tickets/<A's id>` | **404**, not 403 — existence not confirmed |
| S2 | Account B admin requests A's ticket by **reference** (`LYN-0000NN`) | **404** — the global sequence does not escape the account scope |
| S3 | Account B admin requests `GET /api/v1/accounts/<A>/platform_support/tickets` | The existing account-scope guard refuses before the module is reached |
| S4 | B admin lists tickets | `meta.total_entries` counts B's tickets only; nothing in the body references account A |
| S5 | `GET .../messages` on own ticket, with every parameter combination tried (`visibility=internal`, `include=notes`, `type=note`, …) | No internal note under any parameter; unknown params ignored or 422, never honoured |
| S6 | `GET .../events` on own ticket | Only the seven customer-visible types; no `assigned`, no `priority_changed`, no `sla_*`, no `internal_note_added`, no `metadata`, no operator name |
| S7 | Grep every tenant response body for `rails_blob`, `rails_storage`, `activestorage` | No match anywhere |
| S8 | B admin requests an attachment id belonging to A's message | 404 |
| S9 | Any tenant requests an attachment id belonging to an **internal note** | 404 |
| S10 | `PATCH .../tickets/:id` with `status: 'resolved'`, `assignee_id`, `sla_policy_id`, `account_id`, `reference_number`, `category` | Each ignored or 422; none persisted |
| S11 | `POST .../tickets` with `reference_number`, `account_id`, `status: 'resolved'` | All server-owned; the ticket opens as `open` with the next global reference |
| S12 | The **billing-locked** account's admin opens Help & Support and creates a ticket | **Succeeds** (201). Then confirm every other account-scoped endpoint for that account still returns **402** |
| S13 | The **suspended** account's admin | 401 `'Account is suspended'` in V1 (unchanged). If D-5 ships, re-test per its rule |
| S14 | A super admin **without** a `PlatformSupport::Agent` row opens the desk | Refused with an explicit "not a support agent" state; cannot read, reply, note or assign |
| S15 | A logged-in tenant user requests `/super_admin/platform_support` | Redirected to the super-admin login; no data |
| S16 | An operator acts on the desk while **also** holding a tenant session in the same browser | Every audit row names the **operator**, not the tenant principal. This is the §10 misattribution risk, tested directly |
| S17 | Query `audits` for rows whose `associated_type = 'Account'` and `auditable_type LIKE 'PlatformSupport%'` | **Zero rows.** Then confirm the tenant's Audit Logs page shows no platform-support activity |
| S18 | `grep -rn "audited" app/models/platform_support custom/app/models/platform_support` | Empty — the macro was never added |
| S19 | Create 6 tickets in an hour as one user | The sixth is 429 |
| S20 | 31 messages in an hour as one user | The 31st is 429 |
| S21 | Enumerate `tickets/1..200` as account B | 404s throttled after 30/minute per IP |
| S22 | Submit `<script>alert(1)</script>` and `<img src=x onerror=...>` as subject, description and message body | Stored verbatim; rendered as **text** on both surfaces; no execution; no `v-html` in the DOM path |
| S23 | Submit a filename containing `../` and one containing HTML | Rendered as text; download serves the stored blob, with the filename never taken from a request param |
| S24 | Inspect every event `metadata` and every audit `audited_changes` written during this UAT | No message body, no token, no header, no provider payload, no exception text |
| S25 | Delete the subject account of an existing ticket (on a scratch account, not a real one) | The account deletion **succeeds**; the ticket survives with `account_id` NULL and the name snapshot intact; no tenant can read it |

S16, S17 and S18 are the three nobody would think to run, and they are the ones that catch the single highest
risk this discovery found (`03-authorization-security.md` §10). They are not optional.

## 4. Performance checks

| # | Check | Threshold |
|---|---|---|
| Q1 | Staff queue with 500 tickets across 50 accounts: query count per page load | Bounded and constant in page size — no per-row account or plan query. This is the trap the Operations Center measured at 75 of 85 queries (`custom/app/services/operations/account_health.rb:93-103`) |
| Q2 | Four tab counts | **One** aggregate query, not four |
| Q3 | `EXPLAIN` the four queue predicates | Each uses its intended index from `02-data-model.md` §2; the unassigned and SLA queues use their partial indexes |
| Q4 | Tenant list for an account with 100 tickets | One page, one count, `includes` on nothing per-row |
| Q5 | Ticket detail with 60 messages, 20 notes and 40 events | Constant query count; the merged ordering is done in Ruby, not with 120 queries |
| Q6 | 20 concurrent ticket creates across accounts | 20 distinct sequential references, no duplicate, no deadlock, no error |

## 5. Regression checks — this module must change nothing else

| # | Check |
|---|---|
| R1 | The full existing Ruby suite green, with no new skips or pending |
| R2 | The full existing JS suite green |
| R3 | `bundle exec rubocop` and `pnpm eslint` clean |
| R4 | The **tenant** Support Cases module unchanged: create, list, filter, assign, note, SLA, Operations case bridge all behave exactly as before |
| R5 | `support_tickets` reference allocation still **per-account**: a new tenant case in a fresh account is `TCK-000001` |
| R6 | The tenant Audit Logs settings page shows the same entry types as before (S17 is the negative half of this) |
| R7 | The notification bell is unchanged: no new types, no new preference toggles in notification settings |
| R8 | The existing two Help & Support links behave exactly as before, including on an installation with no `supportURL` configured (where they render as nothing) |
| R9 | `git diff --stat` against the base shows **no** modification to `config/features.yml`, `db/schema.rb` beyond the seven new tables, `app/models/notification.rb`, `app/models/notification_setting.rb`, `custom/app/models/support/*`, or `custom/app/policies/support/*` |
| R10 | Every account-scoped endpoint other than the desk still returns 402 for the billing-locked account (the second half of S12) |

R9 is the mechanical check that the architecture's central claim — *nothing existing is modified* — actually
held through implementation.

## 6. Sign-off

UAT passes only when:

- every F, S, Q and R row passes;
- S16, S17, S18 and S25 were executed, not reasoned about;
- the known limitations are **acknowledged in writing** rather than treated as failures: no AV scanning
  (`03-authorization-security.md` §7), calendar-time SLAs (`06-sla-notifications.md` §5), the per-account
  rather than per-user read marker (`04-customer-ux.md` §6), an English/LTR staff desk (D-3), and no
  notification bell (D-6);
- the pilot allow-list has been removed and S1–S4 re-run afterwards (`08-rollout-migrations.md` §4 step 6).

A failure in any S row is a release blocker. A failure in an F row is a bug. A failure in a Q row is a
follow-up unless it is Q6, which is a blocker because a duplicate reference cannot be repaired after the fact.
