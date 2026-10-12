# Platform Support Desk — rollout and migrations

> Phase 0. **No migration files are written in this phase.** This is the plan to approve.

## 1. Migration strategy

**Seven new tables, zero changes to existing tables, plus one additive data concern.** That property is the
main reason Option A was chosen: the rollback story is "drop seven tables nothing else references".

| # | Migration | Touches existing schema? |
|---|---|---|
| M1 | `create_platform_support_agents` | No |
| M2 | `create_platform_support_sla_policies` | No |
| M3 | `create_platform_support_tickets` | No. FKs *out* to `accounts`, `users`, `billing_plans` |
| M4 | `create_platform_support_messages` | No |
| M5 | `create_platform_support_internal_notes` | No |
| M6 | `create_platform_support_events` | No |
| M7 | `create_platform_support_links` (Phase 2) | No |

Nothing is altered, renamed, dropped or backfilled on any existing table. No `support_tickets` column changes,
no `notifications` changes, no `sla_policies` changes, no `accounts` changes.

### Non-schema production changes

| Change | File | Risk |
|---|---|---|
| Sidebar child filter `child.href` → `child.href \|\| child.to` | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:744` | **This is the only edit to shipped tenant UI code.** It is additive in effect: today both children have `href`, so the new predicate returns the same result for them |
| `billing_exempt?` gains one `\|\|` | `custom/app/controllers/billing/access_guard.rb:50-52` | Exempts exactly one new base class. Cannot widen by accident |
| Suspension exemption (if D-5 approves) | `app/controllers/concerns/ensure_current_account_helper.rb` | Touches a guard on **every** account-scoped request. Needs its own review and its own spec; see §5 |
| Administrate nav exclusion list gains `"platform_support"` | `app/views/super_admin/application/_navigation.html.erb:40` | Super Admin only |
| New `nav_item` | `_navigation.html.erb` | Super Admin only |
| New `Rack::Attack` rules | `config/initializers/rack_attack.rb` | New path patterns only; no existing rule changed |
| New locale keys | `config/locales/en.yml`, `i18n/locale/{en,ar}/platformSupport.json` | Additive |

Per CLAUDE.md, only `en.yml` and `en.json` are edited for source strings; the Arabic file is added because this
is a Lynomia-owned module (`04-customer-ux.md` §5).

**No `config/features.yml` change at all** (`01-architecture.md` §6), so `feature_flags_ext_1` keeps all 52 of
its free slots (11 of 63 used, `config/features.yml:271-317`).

## 2. Index creation and table size

Every index is created with the table, in the same migration, because the tables start empty. There is no
`CONCURRENTLY` requirement and no `disable_ddl_transaction!`: an empty table's index builds instantly and a
transactional migration is the safer default.

The two partial SLA indexes hard-code `status < 4`, which is why the enum numbering in `02-data-model.md` §5
is fixed before M3 is written rather than after. Changing a status integer after release means rebuilding both
indexes against live data.

## 3. Seed data the migration does **not** create

Migrations create no rows. Three things must exist before the desk works, and each is an explicit operator
action in Super Admin, not a migration side effect:

| Seed | How | Why not in a migration |
|---|---|---|
| At least one `PlatformSupport::Agent` | A new Administrate dashboard under `/super_admin/platform_support_agents` | Who at Lynomia is on support is a business decision, and a migration that makes every existing super admin a support agent would silently grant the capability to anyone who ever had console access |
| A default `PlatformSupport::SlaPolicy` (the `billing_plan_id IS NULL` row) | The SLA policy page on the desk | The thresholds depend on D-7. A migration that invents them would ship a commitment nobody agreed to |
| The support alias `InstallationConfig` | `/super_admin/installation_configs` | It is an email address, which is environment-specific |

Until an agent row exists, the desk renders "no support agents configured" and the tenant entry can be
withheld — which is the rollout control this module uses in place of a feature flag (`01-architecture.md` §6).

## 4. Rollout sequence

| Step | Action | Verification before proceeding |
|---|---|---|
| 1 | Deploy M1–M6 with no UI wired up | `rails db:migrate:status` clean; seven tables present; the full existing suite green |
| 2 | Seed one agent, one default SLA policy, the alias | Each visible in Super Admin |
| 3 | Enable the **staff** desk only (nav item). No tenant route registered | An operator can open the desk, see an empty queue, and create nothing (there is no staff ticket-create path — tickets originate from customers) |
| 4 | Register the tenant route and the sidebar entry, **for one pilot account**, by shipping the route with the sidebar entry behind a server-rendered allow-list of account ids held in `InstallationConfig` | The pilot account's admin sees `My tickets`; a second account does not |
| 5 | Pilot: the pilot account opens a real ticket; an operator replies, notes, assigns, resolves | The ten UAT scenarios in `10-uat-plan.md` §2 pass against the pilot |
| 6 | Remove the allow-list; the entry is visible to every account | Isolation tests re-run (`10-uat-plan.md` §3) |

> Step 4's allow-list is the one piece of scaffolding in this plan, and it is temporary by design: it is an
> `InstallationConfig` value read in one place, deleted at step 6. It exists because this module has no feature
> flag, and a vendor support desk is exactly the kind of thing you want to try with one friendly customer
> before every customer finds it.

## 5. Risk register

| Risk | Severity | Mitigation |
|---|---|---|
| Suspension exemption (D-5) touches a guard on every account-scoped request | **High** | Separate commit, separate review, a spec asserting the 401 is unchanged for every other controller, and it ships *after* step 6 — the desk works for billing-locked accounts without it |
| An internal note reaching a tenant | **High** | Structural: a separate table with no tenant-reachable association (`02-data-model.md` §7). Tested directly (`10-uat-plan.md` §3) |
| Cross-account ticket visibility | **High** | Three layers (`03-authorization-security.md` §2). Tested directly |
| `audited` added to a platform model by a later contributor | **High** | A spec asserting no `platform_support_*` model responds to `audited_columns`, plus the rule in every model header (`03-authorization-security.md` §10) |
| The sidebar filter change breaks the existing two entries | Low | Both have `href`; the new predicate is a superset. Covered by the existing sidebar specs plus one new case |
| Queue N+1 on the staff desk | Medium | Snapshot columns instead of per-row joins, one aggregate count query, `includes(:account)` (`05-super-admin-operations.md` §2). Query count asserted in a spec |
| Global reference lock contention | Low | Analysed in `02-data-model.md` §8; transaction-scoped, different namespace from the tenant lock |
| Attachment abuse (size, type, malware) | Medium | Server-side limits and an allow-list; **no AV scanning, recorded as a known limitation** (`03-authorization-security.md` §7) |
| An operator sending a note as a reply | Medium | Two distinct compose tabs, note is non-default (`05-super-admin-operations.md` §9) |
| SLA thresholds too tight for calendar time | Medium | D-7; set generously in V1 |

## 6. Rollback

| Stage | Rollback |
|---|---|
| After M1–M6, before any ticket exists | `rails db:rollback STEP=6`. Nothing references the tables |
| After tickets exist | **Do not drop.** Revert the application code; the tables become inert. The sidebar entry and the nav item disappear; the data remains readable by a console. Dropping is a separate, deliberate decision |
| The sidebar filter change | Independently revertible; reverting restores today's behaviour exactly |
| `billing_exempt?` | Independently revertible; reverting re-locks the desk for billing-locked accounts, which degrades the feature rather than breaking the product |
| The suspension exemption | Independently revertible, and the reason it ships last and separately |

The asymmetry in row 2 is deliberate: support correspondence is a record of what Lynomia told a customer. A
rollback script that destroys it is worse than leaving seven unused tables in the schema.

## 7. Specs

CLAUDE.md says to avoid writing specs unless asked. The brief asks for a UAT plan, not a spec suite, so the
specs listed here are the minimum the **security** claims require — a security claim with no test is an
assertion.

| Spec | Asserts |
|---|---|
| `spec/policies/platform_support/ticket_policy_spec.rb` | Account A's admin cannot resolve Account B's ticket, through the scope and through `show?` |
| `spec/requests/api/v1/accounts/platform_support/tickets_spec.rb` | 404 (not 403) for a foreign id and a foreign reference; `PATCH` rejects `status`, `assignee_id`, `category` |
| `spec/requests/.../messages_spec.rb` | The tenant response contains no internal note under any parameter; reply to `closed` is 422; reply to `resolved` reopens |
| `spec/models/platform_support/ticket_spec.rb` | Global reference uniqueness; reporter must be an `AccountUser`; assignee FK rejects a non-agent |
| `spec/services/platform_support/sla_clock_spec.rb` | Pause/resume arithmetic; `waiting_on_lynomia` does not pause; reopen restarts resolution and clears the breach |
| `spec/models/platform_support/audit_spec.rb` | No `platform_support_*` model is `audited`; every mutation service writes a `Custom::AuditLog` row with a non-nil actor and **no** `associated` |
| `spec/controllers/billing/access_guard_spec.rb` (extend) | The desk is reachable at 402-lock; every other controller still 402s |
| `spec/.../attachments_spec.rb` | A note's attachment 404s for a tenant; an oversized or wrong-type upload is 422; no blob URL appears in any tenant response body |
| `app/javascript/.../specs/SidebarHelpEntry.spec.js` | The `My tickets` child survives the filter; the two existing children are unchanged |

Per CLAUDE.md: `let` values and direct per-example setup, no custom setup helpers; `with_modified_env` rather
than stubbing `ENV`; `error.class.name` comparisons rather than constant equality.

## 8. Enterprise overlay

Nothing to mirror. `enterprise/` does not exist in this fork: `ChatwootApp.extensions == ['custom']` and
`ChatwootApp.enterprise?` is hardcoded `false`. This module adds no `prepend_mod_with` / `include_mod_with`
hook, because there is no overlay to hook and a speculative extension point is the speculative guard CLAUDE.md
forbids. It is also, per the brief, not derived from any Chatwoot Enterprise implementation and introduces no
Enterprise dependency: the SLA clock algebra is copied from this fork's own
`custom/app/services/support/tickets/sla_clock.rb`, which carries its own clean-room note
(*"There is no SLA engine in this fork to reuse: Chatwoot's lived in enterprise/, which is permanently
absent"*, `sla_clock.rb:3-6`).
