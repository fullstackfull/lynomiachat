# Lynomia Chat — Chatwoot Enterprise removal

**Status:** `enterprise/` and `spec/enterprise/` no longer exist. Lynomia Chat runs on **Chatwoot
core (`app/`, `lib/`) plus Lynomia's own code (`custom/`)**, proved by booting the application in
`RAILS_ENV=production` with eager loading on, with the directory physically absent and
`DISABLE_ENTERPRISE` set nowhere in the repository or the environment.

**The external production-data gates are now satisfied for the removal.** All eight checks have been
run against `chatwoot_production` and the operator returned the results, recorded as supplied in
section 16. The three
values that could have broken a live request path all came back **zero**. Two checks returned live
data — 123 contacts with a legacy `company_id`, and 0 accounts entitled to the audit log page — and
both are non-blocking follow-ups rather than removal defects, described below. Verdict in section 19.

**Inputs:** `00-enterprise-dependency-audit.md` (the dependency map),
`01-zero-dependency-readiness.md` (*READY AFTER SMALL REPLACEMENTS*),
`02-zero-dependency-implementation.md` (*READY FOR ENTERPRISE REMOVAL WITH PRODUCTION DATA GATE*),
and the three production data gates the operator returned before the removal:

| Gate | Value | Consequence |
|:--|:--|:--|
| `campaign_recipients` rows | 0 | no recipient data to migrate; the table is reused as-is |
| accounts with `advanced_assignment` enabled | 0 | no flag remediation needed |
| `audits` rows | 4845 | **history exists and is preserved** — and must stay readable (section 7) |

Two findings carry forward, neither of them an Enterprise-removal defect and neither blocking.
**One:** **123 contacts still carry a `company_id`** into the orphaned `companies` table, which holds
**97 rows**; **the `companies` table must not be dropped** before a reviewed backfill and cleanup
phase, because it is the only remaining source of those company names (sections 12 and 16).
**Two:** **0 accounts** have the `audit_logs` feature enabled, so the reader restored in section 7 is
inert in production until an administrator turns the feature on — hidden exactly as it was before the
removal, so not a regression (sections 7 and 16).

Nothing was deployed. **This phase did not connect to production** — the eight gates in section 16
were specified as bare `count(*)` statements to run inside `SET TRANSACTION READ ONLY`, and the
operator returned the counts. No production SQL was issued from this phase, no credentials were rotated, no Google OAuth setting was touched, no WhatsApp token was
revoked. No table was dropped, no column or foreign key was removed, and no migration was added.

---

## 1. Pre-removal checkpoint

| | |
|:--|:--|
| Branch | `claude/practical-thompson-9xfqed` |
| **PRE_REMOVAL_SHA** | `65e57b6fe188c7b62a69d8c6e6dfbda7f6fb107f` |
| Tag | `pre-enterprise-removal` → the same commit |
| Worktree at start | `git status --porcelain` empty |
| `enterprise/` tracked files | 541 |
| `spec/enterprise/` tracked files | 282 |
| `config/routes.rb` | 720 lines |
| Backend baseline | full suite green at `65e57b6f`, with and without `enterprise/` (removal delta 0, `02-…` §9.6) |
| Frontend baseline | 499 test files passed, 1 failed (pre-existing); `pnpm test` 492 files / 5206 tests after the phase's own corrections |
| **POST_REMOVAL_SHA (final HEAD)** | `db9132860e4b0f5741962b4bf021de1c887aedcf` |

The tag is the rollback point (section 18). It was created before the first removal commit, from a
clean tree, so a revert needs no file reconstruction.

## 2. Commits

| SHA | What |
|:--|:--|
| `79ca68fb` | `enterprise/` and `spec/enterprise/` removed — 823 files |
| `ccef76e5` | boot, autoload and tooling paths |
| `120a3b50` | the eight enterprise-only route regions |
| `c4e7875b` | the enterprise-only branches in Ruby and the views |
| `32339600` | the enterprise-gated UI, and three regressions repaired |
| `f8827681` | orphan factories and stale enterprise test assumptions |
| `b2b3d695` | the Captain and onboarding references the broadened constant sweep found |
| `8f3a7891` | the audit log reader brought back, as Lynomia's own |
| `6ad23267` | the Enterprise feature source the removal left unreachable |
| `db913286` | stale comments corrected, lint backlog cleared |

Measured `65e57b6f..HEAD`: **1145 files changed, 242 insertions, 95 271 deletions.**

| Kind | Count |
|:--|:--|
| Deleted | **1065** — 821 inside `enterprise/` + `spec/enterprise/`, 244 outside |
| Modified | 77 |
| Added | 1 (`spec/requests/custom/audit_log_reader_spec.rb`) |
| Renamed | 2 — the audit reader controller and view, `enterprise/` → `custom/` (git scores them 73% and 97% similar, i.e. relocated, not rewritten) |

823 files were removed in `79ca68fb` against 541 + 282 = 823 tracked. The 2-file difference against
the 821 counted in the diff is the two renames: git attributes them to `custom/`, not to the deletion.

## 3. `enterprise/` is gone, and the namespace does not load

Measured in the production boot of section 14:

```
Dir.exist?('enterprise')           = false
Dir.exist?('spec/enterprise')      = false
git ls-files enterprise spec/enterprise  → 0
defined?(Enterprise)               = nil
Object.const_defined?(:Enterprise) = false
constantize('Enterprise')          = nil
ChatwootApp.enterprise?            = false
ChatwootApp.extensions             = ["custom"]
ChatwootApp.respond_to?(:self_hosted_enterprise?) = false
eager_load_paths naming "enterprise" = []
view paths naming "enterprise"       = []
```

`rm -rf`, not only `git rm`: `ChatwootApp.enterprise?` was `root.join('enterprise').exist?`, which an
empty leftover directory would still satisfy.

**Boot and path changes** (`ccef76e5`): four lines left `config/application.rb` — `enterprise/lib` on
the autoload path, `enterprise/listeners` (which never existed), the
`Dir["#{Rails.root}/enterprise/app/**"]` eager-load glob, and the
`paths['app/views'].unshift('enterprise/app/views')`. The enterprise initializer loader went with
them.

`config/initializers/01_inject_enterprise_edition_module.rb` **stays**. It is the mechanism, not the
overlay: `const_get_maybe_false` returns `false` for a missing namespace and the yield only fires when
the lookup is truthy, so a missing overlay silently no-ops — and roughly 125 `prepend_mod_with` /
`include_mod_with` call sites reach `custom/` through it. Removing it would unhook Lynomia.

**Ordering matters.** Editing `config/application.rb` *before* deleting the tree raises
`NameError: uninitialized constant AccountDashboard::AccountLimitsField` under eager load — the views
path is dropped while Administrate field classes under `enterprise/app/` are still on disk and
referenced. Development hides it; `RAILS_ENV=production` and `rails zeitwerk:check` do not. Delete the
tree first.

## 4. Every surviving reference, classified

A first sweep over `Enterprise::`, `enterprise/`, `ChatwootApp.enterprise?` and `DISABLE_ENTERPRISE`
was **not sufficient**, and this is the most important methodological finding of the phase: most
Enterprise-owned constants are not `Enterprise::`-namespaced. `Captain::Assistant`,
`ConversationOutcome`, `CaptainInbox`, `Company`, `Call`, `SlaPolicy` and `AccountSamlSettings` are
all top level.

So the sweep was rebuilt from the deletion itself: `git show 79ca68fb --diff-filter=D` yields **260
top-level constants that existed only inside `enterprise/`**, under 47 distinct namespace roots. Each
was grepped literally across `app lib custom config db spec bin`, together with its longest inner
suffix for constants referenced from inside their own namespace.

That is what found the four files in `b2b3d695` — the earlier sweep could not have.

| Class | Count | Disposition |
|:--|:--|:--|
| **A — obsolete, removed** | 4 Ruby files + 153 frontend files | sections 9, 10 |
| **B — compatibility-safe, justified** | 8 call sites in 6 migrations, 4 methods in `lib/chatwoot_app.rb` | below |
| **C — Lynomia-owned replacement, verified** | campaign recipients, audit behaviour, permissions | sections 6, 7, 8 |
| **D — test-only, updated** | `spec/requests/custom/tenant_help_center_removal_spec.rb` | section 9 |
| **E — explanatory, corrected or kept** | 8 comments | below |

### B — why `ChatwootApp.enterprise?` stays as a literal `false`

Six already-applied migrations name deleted constants in their bodies, each behind that predicate:

| Migration | Constant it would dereference |
|:--|:--|
| `20250116061033_convert_document_to_polymorphic_association` | `Captain::AssistantResponse` |
| `20250808123008_add_feature_citation_to_assistant_config` | `Captain::Assistant` |
| `20260320074636_backfill_feature_contact_attributes_for_assistants` | `Captain::Assistant` |
| `20260410092753_backfill_edited_on_captain_assistant_responses` | `Captain::AssistantResponse` |
| `20260428120000_backfill_captain_document_sync_metadata` | `Captain::Document` |
| `20260803000000_enqueue_copy_captain_auto_resolve_mode_to_assistants_job` | `Migration::CopyCaptainAutoResolveModeToAssistantsJob` |

One `false` keeps all eight inert. Deleting the method would mean rewriting applied migration
history, which is strictly worse. An earlier version of this section, and the comment in
`lib/chatwoot_app.rb`, also claimed `app/helpers/super_admin/features.yml` interpolates the predicate
through ERB and that "roughly forty callers" read it. **Both were false** — that file contains no
`enterprise` reference and no ERB, and the measured inventory is 8 migration call sites, the 3
internal `enterprise? &&` uses below, and 2 stubs in `spec/lib/chatwoot_app_spec.rb`, with no other
caller anywhere in `app/`, `custom/`, `lib/`, `config/`, `spec/` or `bin/`. The code comment has been
corrected to match.
`chatwoot_cloud?`, `self_hosted_paid?` and `advanced_search_allowed?` each begin `enterprise? &&`, so
they are permanently false and are left verbatim for upstream parity.
`self_hosted_enterprise?` had zero callers and is deleted.

### E — the eight remaining textual occurrences

| Where | Why it is safe |
|:--|:--|
| `custom/app/models/custom/audit_log.rb:5` | "Carried over from `Enterprise::AuditLog`" — provenance, explicitly historical |
| `custom/app/models/whatsapp/message_template.rb:44` | cites the upstream precedent for an unguarded `audited` declaration |
| `spec/requests/custom/audit_log_reader_spec.rb:16` | asserts `'Enterprise::AuditLog'.safe_constantize` is **nil** — a proof of absence |
| `spec/requests/custom/tenant_help_center_removal_spec.rb:27` | names the removed Cloudflare `ssl_status` action as the thing not reimplemented |
| `app/actions/contact_merge_action.rb:51`, `app/models/inbox.rb:257` | upstream Chatwoot's own "overridden in enterprise/…" markers, untouched for merge parity |
| `app/models/portal.rb` | **corrected** in `db913286`: the reserved-slug list no longer claims a live service explains it |
| `custom/app/policies/custom/portal_policy.rb` | **corrected** in `db913286`: no longer says the Enterprise grant "is installed" |

`DISABLE_ENTERPRISE`: **0 occurrences in code or configuration**. All 21 occurrences in the
repository are in `docs/` — this report (6), `00-enterprise-dependency-audit.md` (5),
`02-zero-dependency-implementation.md` (4), `docs/p7/00-discovery-findings.md` (3),
`docs/product-enablement/07-branding-audit.md` (2) and `docs/p7/00b-discovery-informational.md` (1) —
audit prose discussing the variable, read by nothing. `isEnterprise` / `IS_ENTERPRISE`: **0** in
`app/javascript` and `app/views`.

## 5. Routes

| | |
|:--|:--|
| `config/routes.rb` | 720 → **657 lines** |
| `ChatwootApp.enterprise?` call sites in routes | 9 → **0** |
| Total routes (production boot) | **786** |
| Distinct controllers named by routes | 218 |
| Routes naming a missing controller | **0 Enterprise** (see below) |

**Eight regions removed** (`120a3b50`): conversation `reporting_events`; contact `call`; the CSAT
`PATCH`; account `reporting_events`; `calls` + `whatsapp_calls`; inbox `conference` and the voice
toggles; the WhatsApp `access_request`; the whole `/enterprise` namespace (Stripe billing, Firecrawl
webhook); the Twilio voice TwiML callbacks.

**One route added back**, deliberately: `resource :audit_logs, only: [:show]` — section 7.

Two route entries do resolve to controllers that do not exist: `conversations#show` and
`accounts#*` under `/app`. These are upstream Chatwoot's URL-helper-only declarations under the
comment *"Used in mailer templates"*; the `get '/app/*params'` catch-all at `config/routes.rb:20`
matches first and serves the SPA shell. They are pre-existing, untouched by this phase, and the HTTP
probe confirms `/app/...` returns 200.

**HTTP probe, production Puma, enterprise absent.** Must-work:

| Path | Code | Path | Code |
|:--|:--|:--|:--|
| `/` | 200 | `/super_admin/sign_in` | 200 |
| `/app` | 200 | `/api` | 200 |
| `/app/login` | 200 | `/installation/onboarding` | 302 |
| `/app/accounts/1/dashboard` | 200 | `/api/v1/accounts/1/audit_logs` | **401** (route present, auth required) |

Must be gone — all **404, never 500**: `/api/v1/accounts/1/` + `companies`, `captain/assistants`,
`sla_policies`, `calls`, `agent_capacity_policies`, `applied_slas`, `captain/copilot_threads`,
`saml_settings`, `conversations/1/calls`; `/enterprise/api/v1/accounts/1/limits`;
`/enterprise/webhooks/stripe`. A missing controller raises `ActionController::RoutingError`, which
Rails renders as 404 — removed capabilities are simply absent, as required.

`/docs` and `/changelog` returned 404 in the probe **because the throwaway database has zero
portals** (`Portal.count = 0`), not because the routes are gone:

```
/docs       → {controller: "documentation", action: "show"}
/changelog  → {controller: "documentation", action: "changelog"}
/hc/lynomia-docs → {controller: "public/api/v1/portals", action: "show", slug: "lynomia-docs"}
```

The seeded chain `/docs → /hc/lynomia-docs → /hc/lynomia-docs/en → 200` was verified against a
running production instance in the P4 phase and is unchanged here. Super Admin, Commerce, Campaigns
and the WhatsApp Template Manager routes are all intact.

## 6. WhatsApp and campaigns

Lynomia owns the campaign recipient path, and the removal did not touch it. Measured end to end on a
seeded account:

```
STEP 1  sent        → 3 recipients at "sent" with their wamids
STEP 2  delivered   → 2 progress to "delivered" with delivered_at; the third stays "sent"
STEP 3  final       → delivered / read (read_at set) / failed with Meta's own 131049 wording:
                      "This message was not delivered to maintain healthy ecosystem engagement."
STEP 4  analytics   → audience 3, sent 3, delivered 2, read 1, failed 1, skipped 0
                      status_counts {queued 0, skipped 0, sent 0, delivered 1, read 1, failed 1}
                      — identical to the DB GROUP BY
STEP 5  drill-down  → the contact id behind each status bucket matches the recipient row
```

`process_statuses` ancestry, which §5 of the brief asks for explicitly:

```
owners:          [Custom::Whatsapp::IncomingMessageBaseService, Whatsapp::IncomingMessageBaseService]
ancestor chain:  Custom::Whatsapp::IncomingMessageBaseService, Whatsapp::IncomingMessageBaseService,
                 Whatsapp::IncomingContactMessageHandler, Whatsapp::IncomingMessageIdentifierHelper,
                 Whatsapp::IncomingMessageServiceHelpers, …
any Enterprise module in the chain: false
```

Lynomia's `Custom::` module prepends onto the OSS service; nothing Enterprise sits between them.
**Exactly one** `UpdateRecipientStatusJob` is enqueued per status callback — no duplicate processing,
no double deferral.

No replacement campaign engine was built. The existing `campaign_recipients` table is reused
unchanged; with 0 production rows, no migration was needed and none was written.

## 7. Auditing — and the one regression this phase had to repair

```
Audited.audit_class      = Custom::AuditLog   on table "audits"
'Enterprise::AuditLog'.safe_constantize = nil
audited declarations (11): Account, AccountUser, AgentBot, AutomationRule, Conversation,
                           CustomFilter, Inbox, Macro, Team, Webhook, Whatsapp::MessageTemplate
```

The existing `audits` table is reused. No second audit table, no migration, nothing that would
discard or recreate the 4845 rows. Lynomia's writers — `Flows::Audit`, `Commerce::AuditTrail`, the
Template Manager's own declaration — are unchanged, and the Lynomia audit assertions run
unconditionally.

**The regression.** `7a7779cb`, in the *preceding* phase, dropped `resource :audit_logs, only: [:show]`
along with the other route declarations pointing into `enterprise/`; this phase then deleted the page
itself as enterprise-gated UI. Both steps were locally defensible and together they were wrong.
Settings → Audit Logs is a **documented Lynomia feature** —
`custom/db/documentation/{en,ar}/administration/audit-logs.md` describes the page, its four event
families and its fourteen filters, down to the observation that Commerce and Flow rows appear in the
list without a description. Lynomia owns the entire write side. Only the *reader* was Chatwoot
Enterprise. Preserving 4845 rows with no way to read them is not what "audit history must be
preserved" means, and §11 of the brief forbids losing Lynomia functionality merely because its
implementation came from the overlay.

Repaired in `8f3a7891`, relocated rather than revived in place:

- `custom/app/controllers/api/v1/accounts/audit_logs_controller.rb` — on OSS
  `Api::V1::Accounts::BaseController` instead of the deleted `EnterpriseAccountsController`. Same
  `audit_logs` account feature and `administrator` permission as before.
- `custom/app/views/api/v1/accounts/audit_logs/show.json.jbuilder`.
- `Custom::AuditLog` regains `with_auditable_types`, `created_after`, `created_before`,
  `search_by_user` and `masked_remote_address`. **Not** carried over: the IP geolocation hook and
  `location`. That path needs the `ip_lookup` feature (disabled) plus an Enterprise job, so `city`,
  `country` and `country_code` stay null — the column is now always the address, under the "IP
  address" heading, rather than a "Location" heading over an address.
- The frontend page, its filter bar and its route are restored. The route meta drops
  `installationTypes`: Chatwoot gated the page on cloud-or-enterprise, there is no enterprise
  installation type left to name, and the account feature flag is the real gate. Pre-removal,
  `checkInstallationType(['cloud','enterprise'])` resolved truthy for every install, so this
  reproduces the old visibility exactly.

`spec/requests/custom/audit_log_reader_spec.rb` (6 examples, 0 failures) pins the path, that the
controller is the one under `custom/`, the audit class, the absence of `Enterprise::AuditLog`, the
administrator-allowed / agent-denied pair, the empty result when the feature is off, each filter, and
the IPv4 and IPv6 masking. The page's own 34 frontend tests pass unchanged.

### The Access family: a second relocation, found late and now closed

**The sentence above — "Lynomia owns the entire write side. Only the *reader* was Chatwoot
Enterprise" — was wrong when written.** It is kept, struck here rather than quietly edited, because
the sequence matters: the reader was relocated first, and only a later adversarial review of that
relocation found that a *writer* had gone with the overlay too.

**What was missing.** `Enterprise::DeviseOverrides::SessionsController` wrote the **sign-in and
sign-out** rows by hand — `create_audit_event('sign_in')` from `render_create_success`,
`create_audit_event('sign_out')` from `destroy`, both inserting into `audits` via
`Enterprise::AuditLog.insert_all!`. `User` is deliberately not attribute-audited (its Enterprise
`audited` declaration carried `unless: proc { |_u| true }`, whose only job was to register the class),
so those two events existed **only** in that controller. It went with the overlay, the OSS controller
it prepended onto survived, and for the interval between the removal and this fix **no code wrote a
sign-in or sign-out audit row** — confirmed by grepping every `insert_all`, `Audited::Audit.create`
and `*AuditLog.create*` call in `app/`, `custom/` and `lib/`.

Lynomia's own documentation
(`custom/db/documentation/{en,ar}/administration/audit-logs.md`) describes the audit log as a record of
"configuration changes **and sign-ins**" and lists **Access — sign-in and sign-out** as one of four
event families, so the gap was 2 of its 14 documented events.

**Why it was missed.** The mirroring exercise compared `audited` *declarations* — eleven of them — and
never looked for *manual* audit writers. The other three families were never affected: the eleven
declarations cover them, agent availability included, which is audited on `AccountUser` with a
declaration identical to the Enterprise one.

**Relocated, not restored.** `custom/app/controllers/custom/devise_overrides/sessions_controller.rb`
is a `Custom::` module prepended through the OSS controller's own
`prepend_mod_with('DeviseOverrides::SessionsController')` hook. It reproduces the Enterprise writer
field for field: the same `audits` table through `Custom::AuditLog`, the same `insert_all!` (so no
model callback fires and `username` is written explicitly), one row per account the user belongs to,
versions continuing that user's own sequence via the `audited` gem's `auditable_finder` scope, one
shared `request_uuid` and `created_at` per request, and `remote_address` as the `Audited::Sweeper`
captured it. No Enterprise namespace, no second audit system, no migration, no new table.

Two deliberate differences, neither of them a change to the rows:

- **No IP-geolocation enqueue.** The Enterprise writer queued
  `Enterprise::AuditLogSessionIpLookupJob` to resolve `remote_address` into a city and country. That
  job needed the `ip_lookup` feature (`config/features.yml`, `enabled: false`) and died with the
  overlay. `remote_address` is still recorded; `city`, `country` and `country_code` stay null — the
  same decision `Custom::AuditLog` already documents for the reader.
- **The helpers are private.** The Enterprise module left them public, which on a prepended
  controller makes them candidate actions. Nothing calls them from outside.

The SAML guard that shared the Enterprise module is **not** relocated: SAML left with the overlay.

**Historical rows were not touched.** The fix only adds new rows going forward; no existing `audits`
row was read, updated or deleted, and no migration was written.

`spec/controllers/custom/devise_overrides/sessions_controller_spec.rb` (10 examples) pins the
behaviour: **8 of its 10 examples failed before the fix and all 10 pass after.** It covers one
`sign_in` row on success with every column asserted, one `sign_out` row, nothing on failed
authentication, nothing for a user belonging to no account, one row per account with versions in
order sharing a `request_uuid` and timestamp, version continuation across repeated sign-ins,
`remote_address` matching what the sweeper captured, geolocation left null, that the writer's owner is
`Custom::DeviseOverrides::SessionsController` with no Enterprise module in the ancestor chain, and
that one sign-in produces exactly one row. `spec/requests/custom/audit_log_reader_spec.rb` gained an
example proving the inserted rows come back through the relocated reader under the same
`types: ['User']` filter the UI's ACCESS group sends.

**Production result: accounts with the `audit_logs` feature enabled = 0** (section 16, check 4).

So the restored reader is **currently inert in production**: with the flag off everywhere, the
controller returns `associated_audits.none` and the page stays hidden. This is **not** a regression
and **not** a blocker — the same account feature gated the page before the removal, so it is hidden
now exactly as it was hidden then, and the 4845 rows are preserved either way. It does mean the
repair in this section cannot be observed in production until an administrator enables `audit_logs`
for the accounts that should see Settings → Audit Logs. That is a configuration decision, carried
forward in section 19 as a non-Enterprise follow-up.

## 8. Permissions and custom roles

```
CustomRole::PERMISSIONS includes commerce_order_manage = true
AccountUser#permissions owner                          = Custom::AccountUser
```

Lynomia's `CustomRole` is the single RBAC system; no second one was introduced. `custom_role_id`
reaches the dashboard without an enterprise gate (`46553231`, previous phase). The
administrator-allowed / authorised-custom-role-allowed / unauthorised-agent-denied triple for
`commerce_order_manage` is asserted by the Lynomia permission specs, which run unconditionally and
pass.

Inbox, Contacts, Campaigns, Templates, Automations, Commerce, Audiences and Flow Builder authorisation
is unchanged: the policies involved are OSS or `custom/`, and the only policy methods this phase
touched were the removal of enterprise-only ones. `Custom::PortalPolicy` still prepends — now onto the
OSS `PortalPolicy` rather than the Enterprise one — and still denies tenant Help Center authoring
unconditionally.

## 9. Advanced assignment

```
AssignmentPolicy.assignment_orders = {"round_robin" => 0}
assignment_v2 present in config/features.yml = true
```

With 0 accounts having `advanced_assignment` enabled, no flag remediation was required. The
distinction worth recording: **`advanced_assignment` was the Enterprise feature flag**;
**`assignment_v2` is the OSS assignment engine** and is untouched — not disabled, not degraded. No
dead advanced-assignment UI and no missing constant remain (sections 5, 10, 14).

**Production result: `assignment_policies` with `assignment_order <> 0` = 0** (section 16, check 3).

An earlier version of this section argued that *"the column default is `round_robin`, so no row can
hold a value the enum cannot name"*. **That reasoning was wrong and has been struck.** A column
default only governs rows where no value was supplied; it says nothing about a row written while the
overlay was installed with `balanced` explicitly set. Chatwoot Enterprise added `balanced: 1`
(`enterprise/app/models/enterprise/concerns/assignment_policy.rb:5` at `65e57b6f`), and an
`assignment_policies` row is not gated by the feature flag — a policy created while
`advanced_assignment` was on survives the flag being turned off. So such a row was entirely possible
and the gate was right to exist.

Had one existed, the consequence would have been **silent degradation rather than a crash**. What was
measured: `AssignmentPolicy.type_for_attribute('assignment_order').deserialize(1)` returns `nil`, and
assigning `1` raises `ArgumentError` — so the row reads its order back as nil and could not be
re-saved as-is. What the consuming assignment code then does with a nil order was *not* traced, so
the precise behaviour is unestablished; it is simply not a raise at read time. Production returned 0,
so the question is moot.

## 10. Captain and AI — reported separately, as asked

**This section does not claim that removing Enterprise solved the Captain / `ruby_llm` product-control
question. It did not, and nothing here was redesigned to pretend otherwise.** Captain was not
redesigned, `ruby_llm` was not upgraded (still 1.15.0), and the tenant OpenAI hook was not changed.

**Gone with the overlay:** the Captain product — assistants, documents, FAQ suggestions, scenarios,
custom tools, playground, Copilot, the assistant overview and its stats, `Captain::Assistant` and the
other 13 `Captain::` models, the agent-session and conversation-outcome tracking, and all of their
controllers, jobs and frontend pages.

**Gone in `b2b3d695`, because the overlay was their only producer or consumer:**
`lib/captain/overview_summary_service.rb` and its prompt (fed by the deleted
`Captain::AssistantStatsBuilder`, called only by the deleted stats controller), the Captain half of
`lib/seeders/reports/report_data_seeder.rb`, and `lib/seeders/reports/assistant_conversation_creator.rb`.

**Still here, and still reached by live OSS callers:**

| Service | Caller |
|:--|:--|
| `Captain::BaseTaskService` | the base class below |
| `Captain::LabelSuggestionService` | `Api::V1::Accounts::Captain::TasksController` |
| `Captain::ReplySuggestionService` | same |
| `Captain::RewriteService` | same |
| `Captain::SummaryService` | same |
| `Captain::FollowUpService` | same |
| `Captain::CsatUtilityAnalysisService` | `app/services/csat_template_utility_analysis_service.rb` |
| `Captain::ToolInstrumentation` | the services above |

**Do tenant OpenAI integrations still reach `ruby_llm`? Yes, unchanged.**
`lib/captain/base_task_service.rb:200` resolves `account.hooks.find_by(app_id: 'openai', status: 'enabled')`
and uses `settings['api_key']` when `use_account_openai_hook?`; `lib/llm/config.rb` wires
`openai_api_key` and `openai_api_base` into `RubyLLM` (1.15.0 loaded in the production boot), with
`CAPTAIN_OPEN_AI_ENDPOINT` from `InstallationConfig` as the installation-level override.
`lib/llm/{config,models,feature_router,exception_trackable}.rb` all survive and are OSS.

The product-control question — which model a tenant's key is allowed to drive, and who decides — is
untouched by this phase and remains open for its own.

## 11. Frontend

Reachability was computed as a transitive walk from the **eight real Vite entrypoints**
(`dashboard, portal, sdk, superadmin, superadmin_pages, survey, v3app, widget`), resolving relative
specifiers, all nine Vite aliases, and `import('…')` string forms. There are no template-literal
dynamic imports in the codebase, so the resolver has no blind spot of that kind.

| | Files | Unreachable in production |
|:--|:--|:--|
| At `65e57b6f` | 2415 | 128 (pre-existing, mostly the tenant Help Center removed in the P7 correction) |
| After the route and menu removals | 2359 | 250 |
| **Orphaned by this removal** | | **122** |
| After the deletions, iterated to convergence | **2202** | **127**, of which **8 newly orphaned** |

Dead production source is now *below* the pre-removal baseline (127 against 128), and the 8 files this
removal orphaned are exactly the retained inventory below.

The 122 were not deleted by name-matching — an earlier attempt at that was rejected on evidence,
because live code imports *into* those trees. Reachability is precise by construction, and the two
known counterexamples are the two `components-next/captain/` files that survive:
`assistant/ToolsDropdown.vue` (imported by `components/widgets/conversation/TagTools.vue`) and
`assistant/BulkSelectBar.vue` (imported by `HelpCenter/.../ArticlesPage.vue` and
`contacts/components/ContactsBulkActionBar.vue`).

**Removed, 162 files in two passes:**

- `6ad23267`, 154 files: the Captain product pages and assistant components, Copilot, Companies,
  Calls, the SLA report components, `api/{calls,samlSettings,companies}.js`,
  `api/captain/assistantStats.js`, the `callHistory` and `companies` Pinia stores,
  `shared/helpers/documentHelper.js` (a Captain knowledge-document formatter), and 33 spec and story
  siblings.
- `db913286`, 8 more: `components-next/captain/AnimatingImg/` (five Captain assistant illustrations
  plus their story), `captain/pageComponents/assistant/settings/AssistantControlItems.vue` and
  `assistant/ToolsDropdown.story.vue`. These were **already dead at `65e57b6f`** — reachable only
  from a histoire story — so they are not part of this removal's 122, but they are unused Captain
  source and §2 of the brief leaves no reason to keep them.

**The one genuinely dead UI**, as opposed to merely unreachable source: `ContactsForm.vue` imported
`CompanySelector`, rendered when the `companies` account feature is on, talking to the deleted
`Api::V1::Accounts::CompaniesController`. The selector, its create dialog and the `companyId`
plumbing are removed, and `COMPANY_NAME` falls through to the plain `additionalAttributes.companyName`
input OSS already renders. **This was an external gate, now answered** (section 16, check 5):
**123 contacts** still carry a `company_id`. Nothing at runtime breaks, but those values are now
unreferenced — and the id is still emitted to API clients where the `companies` feature is on, so the
names behind them need backfilling from the 97 surviving `companies` rows before any cleanup.

**Retained orphan inventory** — 8 generic upstream primitives that merely lost their last consumer.
They are not Enterprise files, keeping them costs nothing, and deleting them would widen every future
Chatwoot merge. Same retain-and-inventory call as the tables in section 12.

`components-next/Accordion/Accordion.vue` · `components-next/audio/AudioPlayer.vue` ·
`components-next/vertical-tabs/VerticalTabs.vue` · `components-next/feature-spotlight/FeatureSpotlight.vue` ·
`components-next/feature-spotlight/FeatureSpotlightPopover.vue` · `components/widgets/TableFooter.vue` ·
`components/widgets/TableFooterPagination.vue` · `components/widgets/TableFooterResults.vue`

**Checked and found safe, so not changed:** the three `BasePaywallModal` consumers. The Conversation
Required Attributes paywall is `!isEnabled && isOnChatwootCloud`, so it never renders on Lynomia; the
Webhook and CSAT review-note paywalls pass `i18n-key="PAYWALL"` and route to **Lynomia** billing, not
to a Chatwoot Enterprise advert. No SAML UI, no cloud billing component, no Enterprise audit-log UI,
no Enterprise reports and no Enterprise voice path remain.

**Repaired rather than removed**, in `32339600`: the campaign Analytics button, the advanced-search
filter bar (the filters are OSS SQL behind an *account* flag — only the OpenSearch path needed
`advanced_search_allowed?`), and the Custom Roles paywall, rewritten as a Lynomia plan notice because
the gate keys off the `custom_roles` account flag, not `isEnterprise`.

Dangling imports: **22, all pre-existing** in `i18n/locale/zh/index.js`; **0 introduced** (one
pre-existing one was cleaned up). Locale JSON files are reachable through each locale's `index.js`
and were left alone, per the repo's Crowdin rule.

## 12. Database — nothing dropped

No `DROP TABLE`, no destructive migration, no data deletion, no column removal, no foreign-key
removal. Nothing was objectively required for boot: production eager load and `rails zeitwerk:check`
("All is good!") both pass with every table in place.

**Orphaned-table inventory for a future, optional cleanup phase.** Computed from a booted,
eager-loaded production app: 110 tables, 86 mapped to a surviving ActiveRecord model, **24
unmapped**. Every one has **zero inbound foreign keys from a live table**, so a future drop would not
cascade.

**Production row counts are now in** (section 16, check 6): of the 22 tables this removal orphaned,
**21 hold 0 rows** and **`companies` holds 97**.

> **`companies` must NOT be dropped.** For any of the **123 contacts** that carry a `company_id`
> (section 16, check 5) and whose `additional_attributes->>'company_name'` is blank, those 97 rows are
> the only remaining source of the company name. Contacts may **also** hold a free-text name there
> independently — `ContactsForm.vue` maps the form's company field to
> `additionalAttributes.companyName` — so the overlap is unknown from here and is a production
> question. Until it is answered, dropping `companies` risks destroying names irrecoverably. The
> required order is: **establish the gap, backfill, review, then consider cleanup.** No cleanup is
> authorized by this phase, and none has been performed.
>
> The gap is one more read-only query, not run and not part of the eight:
> `SELECT count(*) FROM contacts WHERE company_id IS NOT NULL AND (additional_attributes->>'company_name') IS NULL;`

The other 21 tables are empty, so a future cleanup phase would be dropping nothing but structure.
That is still a separate, reviewed decision — this phase drops no table.

| Table | Orphaned by | Table | Orphaned by |
|:--|:--|:--|:--|
| `account_saml_settings` | this removal | `captain_message_reports` | this removal |
| `agent_capacity_policies` | this removal | `captain_scenarios` | this removal |
| `agent_sessions` | this removal | `companies` | this removal |
| `applied_slas` | this removal | `conversation_outcomes` | this removal |
| `article_embeddings` | this removal | `copilot_messages` | this removal |
| `calls` | this removal | `copilot_threads` | this removal |
| `captain_assistant_responses` | this removal | `inbox_capacity_limits` | this removal |
| `captain_assistants` | this removal | `sla_events` | this removal |
| `captain_custom_tools` | this removal | `sla_policies` | this removal |
| `captain_documents` | this removal | `leaves` | **pre-existing** |
| `captain_faq_observations` | this removal | `portals_members` | **pre-existing** |
| `captain_faq_suggestions` | this removal | | |
| `captain_inboxes` | this removal | | |

**22 orphaned by this removal, 2 pre-existing.** `leaves` and `portals_members` had no model in
either `app/` or `enterprise/` at `65e57b6f`, so they are not this phase's doing.

**`audits` is explicitly NOT an orphan:** `mapped = true`, `Audited.audit_class = Custom::AuditLog`,
`table = audits`. It carries the 4845 production rows and must never appear on a cleanup list.

## 13. Sidekiq

Booted with `bundle exec sidekiq -C config/sidekiq.yml` in `RAILS_ENV=production`, enterprise absent:

```
Booted Rails 7.2.3.1 application in production environment
errors / NameError / "uninitialized constant" in the log: 0
```

Cron registry:

| | |
|:--|:--|
| `config/schedule.yml` entries | 12 |
| Unresolvable scheduled classes | **0** |
| Entries naming an Enterprise constant | **0** |
| Registered with `sidekiq-cron` | **12** |

Both Lynomia cron jobs register and are read back from the registry rather than inferred from a log
line (`sidekiq-cron` only logs on first registration): `Commerce::ActionSweepJob` at `*/10 * * * *`
and `Lynomia::QueueHealthJob` at `*/5 * * * *`. The WhatsApp and Campaign jobs execute — proved by the
section 6 lifecycle run, which goes through `UpdateRecipientStatusJob`.

## 14. Production boot simulation — no `DISABLE_ENTERPRISE`

`RAILS_ENV=production`, `eager_load = true`, `enterprise/` physically absent,
`DISABLE_ENTERPRISE in ENV = false` and **0 occurrences of the name in code or configuration**
(section 4), so the simulation cannot be leaning on it. Enterprise is absent because the files are
gone, not because a switch is off.

| Check | Result |
|:--|:--|
| Rails production boot | OK |
| Eager load (`Rails.application.eager_load!`) | OK |
| `rails zeitwerk:check` | "All is good!" |
| Routes compile | 786 routes, 218 controllers |
| Sidekiq boot | OK, 0 errors |
| Cron registration | 12/12 |
| `/`, `/app/login`, `/super_admin/sign_in` | 200, 200, 200 |
| Tenant dashboard (`/app/accounts/1/dashboard`) | 200 |
| `defined?(Enterprise)` | **nil** |

15 formerly-Enterprise constants spot-checked, every one `nil`: `Enterprise::AuditLog`,
`Captain::Assistant`, `Captain::Document`, `CopilotThread`, `SlaPolicy`, `AppliedSla`, `Company`,
`Call`, `AccountSamlSettings`, `AgentCapacityPolicy`, `InboxCapacityLimit`, `ConversationOutcome`,
`CaptainInbox`, `Api::V1::Accounts::CompaniesController`,
`Api::V1::Accounts::Captain::AssistantsController`.

## 15. Product regression matrix

| # | Area | Verdict | Evidence |
|:--|:--|:--|:--|
| 1 | Login / auth | PASS | `/app/login` 200; SAML login button removed with the feature |
| 2 | Tenant dashboard | PASS | `/app/accounts/1/dashboard` 200 |
| 3 | Inbox / conversations | PASS | suite green; policies unchanged (§8) |
| 4 | Conversation reporting events | NOT APPLICABLE | the route was enterprise-gated; capability absent, 404 |
| 5 | Contacts | PASS | suite green; `CompanySelector` removed, free-text company name restored (§11); 123 contacts hold a legacy `company_id` — backfill item, not a defect (§16 check 5) |
| 6 | Contact import / bulk actions | PASS | suite green, OSS DataImport path untouched |
| 7 | Labels / audiences | PASS | suite green |
| 8 | Campaigns (WhatsApp) | PASS | full lifecycle probe, §6 |
| 9 | Campaign analytics | PASS | status counts match the DB GROUP BY, §6 |
| 10 | Campaign recipient tracking | PASS | Lynomia-owned, ancestry proof, §6 |
| 11 | WhatsApp inbound (text) | PASS | `process_statuses` chain + suite |
| 12 | WhatsApp outbound | PASS | suite green |
| 13 | WhatsApp Cloud API / coexistence | PASS | suite green, no Enterprise module in the chain |
| 14 | Webhook verification + status webhook | PASS | §6 steps 1–3 |
| 15 | 131049 / 131042 handling | PASS | Meta's own wording asserted, §6 |
| 16 | Retry policy | PASS | exactly 1 deferral job enqueued, §6 |
| 17 | WhatsApp Template Manager | PASS | routes intact (§5); the template `audited` declaration is one of the 11 (§7) |
| 18 | Template status sync | PASS | suite green |
| 19 | Commerce | PASS | routes intact; `Commerce::ActionSweepJob` registered (§13); `commerce_order_manage` (§8) |
| 20 | Flow Builder | PASS | routes intact; `Flows::Audit` writes to `audits` (§7) |
| 21 | Automations / macros | PASS | suite green; both are among the 11 audited models |
| 22 | Custom roles / permissions | PASS | §8; paywall rewritten as a Lynomia plan notice |
| 23 | **Audit logs** | PASS | reader relocated to `custom/`, 6 examples (§7); 0 accounts have the feature on, so the page is hidden in production exactly as before the removal (§16 check 4) |
| 24 | Advanced assignment | NOT APPLICABLE | 0 accounts enabled; 0 policies with a non-`round_robin` order (§16 check 3); `assignment_v2` intact (§9) |
| 25 | Captain / Copilot product | NOT APPLICABLE | removed with the overlay; 7 OSS Captain task services remain (§10) |
| 26 | Captain task services (summary, rewrite, labels, reply, follow-up, CSAT) | PASS | live OSS callers (§10) |
| 27 | Tenant OpenAI → `ruby_llm` | PASS | hook and `Llm::Config` intact, `ruby_llm` 1.15.0 (§10) |
| 28 | SLA | NOT APPLICABLE | Enterprise feature, removed; `applied_slas` / `sla_policies` retained as orphan tables |
| 29 | Voice / calls | NOT APPLICABLE | Enterprise feature, removed; all call routes 404; 0 Twilio channels with `voice_enabled` and 0 with `api_key_secret` (§16 checks 1, 8) |
| 30 | Companies | NOT APPLICABLE | Enterprise feature, removed; 97 rows retained, **not to be dropped** before the backfill (§12, §16 check 6) |
| 31 | SAML | NOT APPLICABLE | Enterprise feature, removed; `account_saml_settings` retained |
| 32 | Chatwoot Cloud billing | NOT APPLICABLE | removed in the previous phase; Lynomia billing under `custom/` is intact |
| 33 | Super Admin | PASS | `/super_admin/sign_in` 200; Administrate dashboards eager-load |
| 34 | Docs (`/docs`) and Changelog | PASS | routes resolve (§5); 404 in the probe is an empty database |
| 35 | Help & Support | PASS | public portal renderer route intact |
| 36 | Reports (non-SLA) | PASS | suite green |
| 37 | Advanced search | PASS | OSS SQL filters behind the account flag; installation gate removed (§11) |
| 38 | Sidekiq + both Lynomia cron jobs | PASS | §13 |
| 39 | Production boot + eager load | PASS | §14 |
| 40 | Audit history (4845 rows) | PASS | same table, same class, no migration (§7) |

**External gates — now run and satisfied.** These were the facts only production could answer, which
the three pre-removal gates did not cover. **All eight have been run against `chatwoot_production` and
the results returned to this phase; the counts, and the SQL as specified, are in section 16.**

An earlier version of this section introduced them with *"None of these can break boot; each decides
whether some rows are now unreferenced."* **The first clause is true but was read as reassurance it
does not support, and the second was wrong for three of them. Both have been struck.** Nothing here
breaks *boot* — the application starts and eager-loads with any of these values. But three of the
eight would have broken a **live request path**, which was then measured rather than argued. For the
two `Captain::Assistant` cases the HTTP 500 itself was measured; for the Twilio case the raise on the
reachable code path was measured, and the 500 is the inference from that path being reached by a live
endpoint:

| Dangling value | Measured consequence |
|:--|:--|
| `conversations.ai_assignee_type = 'Captain::Assistant'` | `conv.ai_assignee` → `NameError: uninitialized constant Captain::Assistant`; `GET /api/v1/accounts/:id/conversations` → **500**; `GET …/conversations/:id` → **500** |
| `messages.sender_type = 'Captain::Assistant'` | `msg.sender` → the same `NameError`; `GET …/conversations/:id/messages` → **500**, and `GET …/conversations` → **500** for any conversation holding such a message |
| `channel_twilio_sms.voice_enabled = true` | `Twilio::HealthService#phone_number_webhooks` → `NoMethodError: undefined method 'voice_call_webhook_url'`; reachable at `GET …/inboxes/:id/health`. With the flag false, no error |

The specific error in the old wording: it said `app/models/message.rb` *"compares the string, so Ruby
is safe."* The string comparisons at `message.rb:229` and `:376` are only two of the readers. The
polymorphic **association** is dereferenced by the serializers and the conversation preloads, and
that raises.

**Production returned 0 for all three.** Section 16 has every count.

## 16. Production data gates — all eight, run and recorded

**Provenance.** The results below were **returned by the operator** against `chatwoot_production` and
are recorded here as supplied. This phase did not connect to production and does not assert how the
queries were executed — only what came back.

The procedure specified for them was: each check as a bare `count(*)` inside
`BEGIN; SET TRANSACTION READ ONLY; SET LOCAL search_path = public, pg_catalog; SET LOCAL statement_timeout; SET LOCAL lock_timeout; … COMMIT;`
run through `psql -X -v ON_ERROR_STOP=1`, authenticating via `~/.pgpass` so no password reaches a
command line, and `psql` rather than `rails runner` — because booting the application is not
read-only: `lib/global_config_service.rb:12` is
`InstallationConfig.where(name: config_key).first_or_create(…)`, a read-named API that INSERTs, and
that is how a production-mode `rails runner` wrote 4 rows into `installation_configs` earlier in this
work (section 17). A read-only transaction was separately verified to refuse `INSERT`, `UPDATE`,
`DELETE` and `DROP TABLE`.

By construction a `count(*)` returns an integer and nothing else, so no credential or row content can
appear in the output of any of the eight.

| # | Check | Result | Verdict |
|:--|:--|:--|:--|
| 1 | `channel_twilio_sms` with `voice_enabled = true` | **0** | **CLEAR** — blocker ruled out |
| 2 | `messages` with `sender_type = 'Captain::Assistant'` | **0** | **CLEAR** — blocker ruled out |
| 3 | `assignment_policies` with `assignment_order <> 0` | **0** | CLEAR (section 9) |
| 4 | `accounts` with `audit_logs` enabled (`feature_flags & 134217728 = 134217728`) | **0** | Not a blocker — the restored reader is inert until the flag is enabled (section 7) |
| 5 | `contacts` with `company_id IS NOT NULL` | **123** | Not a blocker — **backfill item**, carried forward |
| 6 | Row counts for the 22 removal-orphaned tables | **`companies` = 97; the other 21 = 0** | Not a blocker — **`companies` must not be dropped** (section 12) |
| 7 | `conversations` with `ai_assignee_type = 'Captain::Assistant'` | **0** | **CLEAR** — blocker ruled out |
| 8 | `channel_twilio_sms` with `api_key_secret IS NOT NULL` | **0** | **CLEAR** — the encryption-compatibility finding below cannot bite |

Checks 1–7 are the seven external gates of section 15. Check 8 was added after the removal, from the
finding below, and is not one of the seven.

The queries as specified, in the intended execution order:

```sql
-- 1
SELECT count(*) AS twilio_voice_enabled           FROM channel_twilio_sms  WHERE voice_enabled = true;
-- 2
SELECT count(*) AS captain_sender_messages        FROM messages            WHERE sender_type = 'Captain::Assistant';
-- 3
SELECT count(*) AS non_round_robin_policies       FROM assignment_policies WHERE assignment_order <> 0;
-- 4  134217728 = 2^27, the audit_logs flag_shih_tzu bit (config/features.yml via
--    app/models/concerns/featurable.rb:19-25); matches the app's own generated predicate.
SELECT count(*) AS accounts_with_audit_logs       FROM accounts            WHERE (feature_flags & 134217728) = 134217728;
-- 5
SELECT count(*) AS contacts_with_company          FROM contacts            WHERE company_id IS NOT NULL;
-- 6  one UNION ALL over the 22 tables of section 12, so a single surprise cannot cost the other 21 counts
SELECT 'companies' AS orphaned_table, count(*) AS rows FROM companies
UNION ALL SELECT 'captain_assistants', count(*) FROM captain_assistants
--   … abridged here: the full statement names all 22 tables listed in section 12 …
ORDER BY rows DESC, orphaned_table;
-- 7  no index on ai_assignee_type: EXPLAIN first, and never record a statement_timeout as a zero
SELECT count(*) AS captain_ai_assignee_conversations FROM conversations    WHERE ai_assignee_type = 'Captain::Assistant';
-- 8  count only; never SELECT the column itself
SELECT count(*) AS twilio_rows_with_api_key_secret  FROM channel_twilio_sms WHERE api_key_secret IS NOT NULL;
```

A note on cost rather than on what was actually run: four of the eight predicates are unindexed
(`channel_twilio_sms.voice_enabled`, `assignment_policies.assignment_order`, `accounts.feature_flags`
and `conversations.ai_assignee_type`), but only check 7 sits on a large table, so it is the only one
whose cost is unpredictable. Checks 2 and 5 are index-served
(`index_messages_on_sender_type_and_sender_id`, `index_contacts_on_company_id`); the other three
unindexed ones are on small tables. Check 7 was therefore specified to run after the cheap
ones and behind `EXPLAIN`, with the standing instruction that a `statement_timeout` there must never
be recorded as a zero. Check 8 is a count on the same small table as check 1, so its position after
check 7 in the list costs nothing.

### The three blockers, and why zero is durable

Checks 1, 2 and 7 are the values that would have broken a live request path (section 15) — a measured
500 for the two `Captain::Assistant` cases, a measured raise on a reachable path for the Twilio one.
They came back zero, and that zero does not depend on luck — **no surviving code can write any of these values**:

- `conversations.ai_assignee` has **two** writers that supply a value, and both supply an `AgentBot`:
  `Conversations::AssignmentService#assign_ai_assignee`, whose only caller is
  `assign_agent_bot` → `assign_ai_assignee(agent_bot)`; and `app/models/conversation.rb:324`,
  `self.ai_assignee = inbox.agent_bot`. The remaining four assignments
  (`conversations_controller.rb:182`, `assignment_service.rb:23`, `conversation.rb:185`, `:304`) are
  `= nil`. So the column can only hold `AgentBot` or NULL.
- `messages.sender_type`: there is no surviving writer that names any `Captain::` class.
- `channel_twilio_sms.voice_enabled` has no surviving writer at all — no surviving controller permits
  the parameter and no surviving service sets it. Before the removal it was writable because
  `enterprise/app/controllers/enterprise/api/v1/accounts/inboxes_controller.rb:106` added
  `:voice_enabled` to the permitted inbox-update attributes (and `:126` set it when creating a voice
  channel). That controller went with the overlay.

So these are not "zero today, unknown tomorrow". The classes are gone, the writers are gone, and the
columns cannot reacquire the values through the application.

One case check 7 could not see, for completeness: `ai_assignee` is polymorphic over the shared foreign
key `assignee_agent_bot_id`, and the two applied backfills
(`db/migrate/20260811000000`, `20260811000001`) set `ai_assignee_type = 'AgentBot'` for any row that
had a bot id but no type. A conversation that had been Captain-assigned could therefore have been
relabelled `AgentBot` over an id with no matching `agent_bots` row. The association is
`optional: true` (`app/models/conversation.rb:117-121`), so such a row resolves to `nil` rather than
raising, and the conversation shows no AI assignee. Neither backfill can write `'Captain::Assistant'`
— each writes only `'AgentBot'` or `nil`.

### Carried forward: the Companies backfill

**123 contacts** hold a `company_id`; **`companies` holds 97 rows.** Nothing dereferences the column —
there is no surviving `belongs_to :company` and no foreign key — so this breaks nothing at runtime.
But the value is **still emitted to API clients** when an account has the `companies` feature on:
`app/views/api/v1/models/_contact.json.jbuilder:9` and `app/models/contact.rb:163`. Clients receive
an id they can no longer resolve.

Those 97 rows are the only remaining source of the company name **for whichever of the 123 contacts
has no free-text `additional_attributes->>'company_name'` already** — contacts can hold that
independently, so the size of the real gap is a production question the eight checks did not ask. The
order is **establish the gap, backfill, review, then consider cleanup** — never cleanup first. See the
boxed rule in section 12.

### Carried forward: Twilio `api_key_secret` encryption compatibility

A separate finding, surfaced while preparing the gates, recorded here because check 8 settles it.
`encrypts :api_key_secret if Chatwoot.encryption_configured?` existed only at
`enterprise/app/models/enterprise/channel/twilio_sms.rb:7` (verified at `65e57b6f`); the surviving
`app/models/channel/twilio_sms.rb:36` declares only `encrypts :auth_token`, while
`app/services/twilio/media_download_service.rb:12` still reads
`channel.api_key_secret.presence || channel.auth_token`. Any row written with that column populated
while the overlay was installed **and** `Chatwoot.encryption_configured?` was true at that time would
now be read back as **raw ciphertext**, failing Twilio media auth. Where encryption was not
configured the column was stored in clear and still reads correctly.

**Check 8 returned 0, so no such row exists and this is not a production blocker.** The code gap is
real and remains: if `api_key_secret` is ever used again, the `encrypts` declaration must be restored
under `custom/` first. Recorded as a Lynomia maintenance surface in section 20.

## 17. Test gate

Isolated environment: PostgreSQL database `chatwoot_test` (reset with `db:test:prepare`,
`installation_configs` verified at 0 rows) and Redis logical database 2 (`FLUSHDB`), on a clean
working tree with nothing else running against either.

| Gate | Result |
|:--|:--|
| **Backend — `bundle exec rspec`** | **8651 examples, 0 failures, 70 pending, exit 0** |
| **RuboCop — `bundle exec rubocop`** | **2706 files inspected, 0 offenses** |
| **Frontend unit — `pnpm test`** | **472 files, 5100 tests, 0 failures, exit 0** |
| **ESLint — `pnpm eslint`** | **0 errors** (450 pre-existing `no-raw-text` / `no-dynamic-keys` warnings) |
| **Production frontend build — `vite build`** | **exit 0** |
| **SDK build — `pnpm run build:sdk`** | **exit 0** |

The 70 pending are upstream Chatwoot `skip`/`pending` markers, unchanged by this phase.

Frontend totals moved from 492 files / 5206 tests to 472 / 5100 — 20 files and 106 tests fewer,
which are the deleted Captain, Copilot, Companies, Calls and SLA specs, against the audit log
reader's 6 new backend examples.

### The first run, and why its 92 failures were not real

An earlier full run of the same suite reported **92 failures**. They are recorded here rather than
quietly replaced, because the reason matters.

Both causes were **mine, not the removal's**. I ran that suite while continuing to work:

1. A production-mode `rails runner` and a Sidekiq boot (the section 13 and 14 gates) were pointed at
   **the same `chatwoot_test` database**, and wrote 4 `installation_configs` rows into it.
   `spec/lib/config_loader_spec.rb` says it outright — `expected: 0, got: 4` — and
   `global_config_service_spec`, `vapid_service_spec` and the two `accounts_controller` specs read the
   same table.
2. I edited and deleted files on disk mid-run. With reloading enabled in the test environment, that
   reloads the autoload paths, and the suite ended up holding **two different `Account` class
   objects**: `ActiveRecord::AssociationTypeMismatch: Account(#151632) expected, got … Account(#35096)`.
   The same artefact explains `expected MutexApplicationJob::LockAcquisitionError, got
   #<MutexApplicationJob::LockAcquisitionError: …>` — the object *is* of the expected class, under a
   different class identity. This is the hazard `CLAUDE.md` already names for this repository
   ("prefer comparing `error.class.name` over constant class equality when asserting raised errors").

Rather than assert that, it was verified: **every file that failed was re-run in isolation on the
second, untouched database — 568 examples plus 37, 0 failures.** That covers all 92, including the two
in the removal's own blast radius (`Campaigns::UpdateRecipientStatusJob`) and
`spec/jobs/flows/run_job_spec.rb`. The clean full run above then returned 0 failures over the same
8651 examples.

Classification per the four categories asked for: **92 class B (environment / test harness), 0 class
A (pre-existing failure), 0 class C (stale Enterprise test assumption), 0 class D (real removal
regression).** No assertion was weakened and no spec was skipped, disabled or quarantined to reach
this.

Stale Enterprise test assumptions were handled earlier and separately, as code changes with their own
commits: `f8827681` removed the orphan factories and the four `if: ChatwootApp.enterprise?` examples
in `spec/controllers/super_admin/accounts_controller_spec.rb`, `b2b3d695` rebased the onboarding
assertion onto the absence of the path rather than the presence of a `Custom::` override, and
`0811f4c9` (previous phase) re-pointed 24 audit assertions at `Custom::AuditLog`.

## 18. Rollback

Rollback is a revert to the commit immediately before the first removal commit. No file needs
reconstructing — every deleted file is in git history at that commit.

| | |
|:--|:--|
| **Rollback SHA** | `65e57b6fe188c7b62a69d8c6e6dfbda7f6fb107f` |
| Tag | `pre-enterprise-removal` |
| First removal commit | `79ca68fb` |
| **POST_REMOVAL_SHA** | `db9132860e4b0f5741962b4bf021de1c887aedcf` |

```
git checkout claude/practical-thompson-9xfqed
git revert --no-commit 65e57b6f..HEAD && git commit -m "revert: restore Chatwoot Enterprise"
# or, to inspect first:
git diff 65e57b6f..HEAD
```

Nothing about the rollback touches the database: no migration was added and no schema change was
made, so `db/schema.rb` is identical at both SHAs and the same database serves either. **No
production rollback action has been executed** — this records the procedure only.

## 19. Verdict

**ENTERPRISE REMOVAL PASS**

Both qualifiers are discharged.

The *EXTERNAL GATES* qualifier rested on the production queries and on whether the restored audit log
reader was reachable; **both are answered** (section 16). The queries returned zero for every value
that could have broken a request path, and the audit entitlement returned 0 accounts — a
configuration follow-up, not an open risk.

The *OPEN REGRESSION* qualifier rested on the sign-in/sign-out audit writer that went with the
overlay. **It has been relocated to Lynomia's own code** (section 7):
`custom/app/controllers/custom/devise_overrides/sessions_controller.rb`, prepended through the OSS
controller's own hook, writing the same rows to the same `audits` table through `Custom::AuditLog`.
The Access family is recorded again, there is exactly one session audit writer in the tree, the rows
read back through the relocated reader, and no historical row was modified. Pinned by 10 examples that
failed 8/10 before the fix and pass 10/10 after.

`enterprise/` and `spec/enterprise/` are gone — 823 tracked files. The namespace does not load, the
directory does not exist, `ChatwootApp.extensions` is `["custom"]`, and **no runtime path depends on
an Enterprise constant**: the operational dependency count is **ZERO**. Lynomia Chat boots, eager
loads, serves and schedules on Chatwoot core plus `custom/` alone, proved in production mode with the
directory physically absent and `DISABLE_ENTERPRISE` present nowhere.

The remaining textual occurrences partition exactly as section 4 enumerates them: **8** inert
`ChatwootApp.enterprise?` call sites across the six already-applied migrations whose bodies name
deleted constants — the reason that predicate stays as a literal `false` rather than being deleted —
**4** methods in `lib/chatwoot_app.rb` (the predicate plus the three that begin `enterprise? &&`),
and **8** comments or assertions of absence. The two `enterprise?` stubs in
`spec/lib/chatwoot_app_spec.rb` belong to none of those classes.

Every gate is green: production boot and eager load, `zeitwerk:check`, 786 routes with no Enterprise
controller missing, Sidekiq with 12/12 cron classes resolving, the WhatsApp campaign lifecycle
`sent → delivered / read / failed` with analytics agreeing with the database, the audit class and its
4845 rows, the permission triple, **the backend suite at 8651 examples / 0 failures / 70 pending**,
RuboCop 2706 files clean, the frontend suite at 472 files / 5100 tests / 0 failures, ESLint 0 errors,
and `vite build` and `build:sdk` both exit 0.

**The external gates are closed.** All eight checks have been run against `chatwoot_production` and
the operator returned the results (section 16). The three that would have broken a live endpoint — dangling
`Captain::Assistant` rows in `conversations.ai_assignee_type` and `messages.sender_type`, and
`channel_twilio_sms.voice_enabled = true` — each returned **0**, and no surviving code can write any
of those values, so the result is durable rather than incidental. `assignment_order <> 0` returned 0.
The `api_key_secret` encryption-compatibility finding returned 0 and cannot bite.

**What an earlier version of this verdict got wrong.** It argued the gates could not break anything,
on reasoning about string comparison that was incorrect. The correction and the measurements are in
section 15. The conclusion is unchanged only because production returned zero for all three values;
had any been non-zero, this phase would have been blocked.

**Two follow-ups carry forward. Neither is an Enterprise-removal defect, and neither blocks the
removal:**

1. **Companies backfill.** 123 contacts hold a `company_id`; `companies` holds 97 rows. Nothing
   dereferences the column, but the id is still emitted to API clients when an account has the
   `companies` feature on. Those 97 rows are the only source of the names behind the 123 references,
   so **`companies` must not be dropped before a reviewed backfill and cleanup phase** (sections 12
   and 16). No cleanup is authorized by this phase and none has been performed.
2. **Audit log entitlement.** 0 accounts have the `audit_logs` feature enabled, so the reader
   restored in section 7 is inert in production. This is not a regression — the same flag gated the
   page before the removal — but the repair cannot be observed until an administrator enables the
   feature for the accounts that should see Settings → Audit Logs. A configuration decision.

Both are product decisions about Lynomia's own features, not residue of the overlay. `enterprise/`
is gone and nothing in the running system depends on it.

## 20. Upgradeability, and what Lynomia now maintains

**What gets easier.** Chatwoot upstream ships `app/` and `enterprise/` as separate trees. With the
overlay gone, an upstream merge no longer has to reconcile `enterprise/` at all — 823 files of merge
surface disappear. `config/initializers/01_inject_enterprise_edition_module.rb` is retained precisely
so that upstream's ~125 `prepend_mod_with` call sites keep working; they now silently no-op for
Enterprise and resolve for `Custom::`.

**What gets harder.** Three things Chatwoot maintained are now Lynomia's. These are the **Lynomia
maintenance surfaces**, and each needs a deliberate decision at every upstream merge:

| Surface | Lynomia owner | What an upstream change could do |
|:--|:--|:--|
| **WhatsApp campaign recipient behaviour** | `Custom::Whatsapp::IncomingMessageBaseService`, `campaign_recipients`, `UpdateRecipientStatusJob` | upstream reworking `process_statuses` changes what the `Custom::` prepend wraps |
| **Audit behaviour** | `Custom::AuditLog`, the 11 mirrored `audited` declarations, the relocated reader and its view, and the relocated sign-in/sign-out writer in `custom/app/controllers/custom/devise_overrides/sessions_controller.rb` | upstream adding an `audited` model means mirroring it; upstream changing the audit payload means updating the jbuilder; upstream reworking `DeviseOverrides::SessionsController#render_create_success` or `#destroy` changes what the session writer's prepend wraps |
| **Permissions / custom roles** | `CustomRole`, `Custom::AccountUser#permissions` | upstream adding a permission constant needs merging into `CustomRole::PERMISSIONS` |

**A lesson this phase paid for twice.** Both audit regressions — the reader, then the writer — were
missed by the same method: comparing `audited` *declarations* between the two trees. Declarations are
not the whole audit surface. When checking audit coverage against an upstream change, grep for manual
writers too (`insert_all`, `Audited::Audit.create`, `*AuditLog.create*`) and for controllers that
prepend onto an authentication or session action.

**One known code gap, dormant rather than closed.** `encrypts :api_key_secret` lived only in the
overlay (`enterprise/app/models/enterprise/channel/twilio_sms.rb:7` at `65e57b6f`); the surviving
`app/models/channel/twilio_sms.rb:36` encrypts `auth_token` only, while
`app/services/twilio/media_download_service.rb:12` still reads `api_key_secret`. Production holds no
such row (section 16, check 8), so nothing is broken now — but **before `api_key_secret` is used
again, the `encrypts` declaration must be restored under `custom/`** — and restored *before* anything
writes to the column, so the first stored value and every later one are handled the same way. Check 8
found no existing values, so there is nothing to reconcile today.

Two further standing items:

- **The `enterprise?` predicate.** Upstream will keep adding `ChatwootApp.enterprise?` guards. They
  arrive inert, which is the desired outcome, but a merge that introduces a guard whose *else* branch
  Lynomia needs will silently take the wrong path. Grep new guards on every merge.
- **Upstream code that reaches into `enterprise/`.** Two upstream markers remain
  (`app/actions/contact_merge_action.rb:51`, `app/models/inbox.rb:257`). They are comments today; if
  upstream converts either into a hard reference, the merge breaks loudly rather than silently, which
  is the right failure mode.

**Retained for merge parity, deliberately:** `config/features.yml` in full (including `audit_logs`,
`sla`, `captain`, `companies`, `advanced_assignment`), the Gemfile, `:saml` in `user.rb`,
`lib/llm/feature_router.rb`, `config/initializers/ai_agents.rb` (its `Agents::` namespace is shared
with OSS `app/jobs/agents/destroy_job.rb`), the OSS policy methods, and the 8 frontend primitives in
section 11. None is an Enterprise file; each would cost a conflict later for no gain now.
