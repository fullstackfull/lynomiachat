# Lynomia Chat — Chatwoot Enterprise removal

**Status:** `enterprise/` and `spec/enterprise/` no longer exist. Lynomia Chat runs on **Chatwoot
core (`app/`, `lib/`) plus Lynomia's own code (`custom/`)**, proved by booting the application in
`RAILS_ENV=production` with eager loading on, with the directory physically absent and
`DISABLE_ENTERPRISE` set nowhere in the repository or the environment.

Verdict in section 18.

**Inputs:** `00-enterprise-dependency-audit.md` (the dependency map),
`01-zero-dependency-readiness.md` (*READY AFTER SMALL REPLACEMENTS*),
`02-zero-dependency-implementation.md` (*READY FOR ENTERPRISE REMOVAL WITH PRODUCTION DATA GATE*),
and the three production data gates the operator returned:

| Gate | Value | Consequence |
|:--|:--|:--|
| `campaign_recipients` rows | 0 | no recipient data to migrate; the table is reused as-is |
| accounts with `advanced_assignment` enabled | 0 | no flag remediation needed |
| `audits` rows | 4845 | **history exists and is preserved** — and must stay readable (section 7) |

Nothing was deployed. No production data was read or written by this phase, no production SQL was
run, no credentials were rotated, no Google OAuth setting was touched, no WhatsApp token was revoked.
No table was dropped, no column or foreign key was removed, and no migration was added.

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

The tag is the rollback point (section 17). It was created before the first removal commit, from a
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
| **B — compatibility-safe, justified** | 9 call sites in 6 migrations, 4 methods in `lib/chatwoot_app.rb` | below |
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

One `false` keeps all nine inert. Deleting the method would mean rewriting applied migration history,
which is strictly worse. `app/helpers/super_admin/features.yml` also interpolates it through ERB.
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
**`assignment_v2` is the OSS assignment engine** and is untouched — not disabled, not degraded. The
`assignment_order` enum keeps only `round_robin` because the other member lived in `enterprise/`; the
column default is `"round_robin"`, so no row can hold a value the enum cannot name. No dead
advanced-assignment UI and no missing constant remain (sections 5, 10, 14).

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
input OSS already renders. **This is an external gate** (section 15): an account with `companies`
enabled and `contacts.company_id` values set loses nothing at runtime, but those values become
unreferenced.

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
cascade. Row counts below are from the local throwaway database; **production counts are an external
gate** (section 15).

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
| 5 | Contacts | PASS | suite green; `CompanySelector` removed, free-text company name restored (§11) |
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
| 23 | **Audit logs** | PASS | reader relocated to `custom/`, 6 examples (§7) |
| 24 | Advanced assignment | NOT APPLICABLE | 0 accounts enabled; `assignment_v2` intact (§9) |
| 25 | Captain / Copilot product | NOT APPLICABLE | removed with the overlay; 7 OSS Captain task services remain (§10) |
| 26 | Captain task services (summary, rewrite, labels, reply, follow-up, CSAT) | PASS | live OSS callers (§10) |
| 27 | Tenant OpenAI → `ruby_llm` | PASS | hook and `Llm::Config` intact, `ruby_llm` 1.15.0 (§10) |
| 28 | SLA | NOT APPLICABLE | Enterprise feature, removed; `applied_slas` / `sla_policies` retained as orphan tables |
| 29 | Voice / calls | NOT APPLICABLE | Enterprise feature, removed; all call routes 404 |
| 30 | Companies | NOT APPLICABLE | Enterprise feature, removed; see the external gate below |
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

**External gates** — facts only production can answer, which the three supplied gates did not cover.
None of these can break boot; each decides whether some rows are now unreferenced:

| Query | Why it matters |
|:--|:--|
| `SELECT count(*) FROM conversations WHERE ai_assignee_type = 'Captain::Assistant'` | polymorphic column; surviving code dereferences `ai_assignee` |
| `SELECT count(*) FROM messages WHERE sender_type = 'Captain::Assistant'` | same; `app/models/message.rb` compares the **string**, so Ruby is safe, but `message.sender` on such a row would not resolve |
| `SELECT count(*) FROM contacts WHERE company_id IS NOT NULL` | the removed `CompanySelector` wrote this |
| `SELECT count(*) FROM assignment_policies WHERE assignment_order <> 0` | the enum now names only `round_robin` |
| `SELECT count(*) FROM channel_twilio_sms WHERE voice_enabled = true` | the Twilio voice callbacks are gone |
| `SELECT count(*) FROM accounts WHERE 'audit_logs' = ANY(...)` / feature check | confirms the restored reader is reachable for the accounts that had it |
| Row counts for the 22 orphaned tables | sizes the optional cleanup phase |

## 16. Test gate

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

## 17. Rollback

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

## 18. Verdict

**ENTERPRISE REMOVAL PASS WITH EXTERNAL GATES**

`enterprise/` and `spec/enterprise/` are gone — 823 tracked files. The namespace does not load, the
directory does not exist, `ChatwootApp.extensions` is `["custom"]`, and **no runtime path depends on
an Enterprise constant**: the operational dependency count is **ZERO**. Lynomia Chat boots, eager
loads, serves and schedules on Chatwoot core plus `custom/` alone, proved in production mode with the
directory physically absent and `DISABLE_ENTERPRISE` present nowhere.

The 17 remaining textual occurrences are accounted for individually in section 4: nine are inert
`enterprise?` guards in `lib/chatwoot_app.rb` and six already-applied migrations whose bodies name
deleted constants — the reason that predicate stays as a literal `false` rather than being deleted —
and eight are comments or an assertion of absence.

Every gate is green: production boot and eager load, `zeitwerk:check`, 786 routes with no Enterprise
controller missing, Sidekiq with 12/12 cron classes resolving, the WhatsApp campaign lifecycle
`sent → delivered / read / failed` with analytics agreeing with the database, the audit class and its
4845 rows, the permission triple, **the backend suite at 8651 examples / 0 failures / 70 pending**,
RuboCop 2706 files clean, the frontend suite at 472 files / 5100 tests / 0 failures, ESLint 0 errors,
and `vite build` and `build:sdk` both exit 0.

**Why "with external gates" and not a bare PASS.** Two things are outside what a repository phase can
settle:

1. **Seven production queries** (section 15) decide whether any rows now point at a removed class or
   capability. None can break boot — the polymorphic columns are compared as strings, and the removed
   UI simply stops writing — but an operator should know the numbers before deploying, and before
   deciding on the optional table cleanup.
2. **The audit log reader** is restored from Lynomia's own tree and proved by spec and by HTTP, but
   whether the `audit_logs` account feature is enabled for the production accounts that were using the
   page is a production fact. If it is enabled, the page returns exactly as before; if it is not, the
   page is correctly hidden. Either way no data was touched.

Neither is a defect in the removal. Both are facts to collect before the deploy phase.

## 19. Upgradeability, and what Lynomia now maintains

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
| **Audit behaviour** | `Custom::AuditLog`, the 11 mirrored `audited` declarations, the relocated reader and its view | upstream adding an `audited` model means mirroring it; upstream changing the audit payload means updating the jbuilder |
| **Permissions / custom roles** | `CustomRole`, `Custom::AccountUser#permissions` | upstream adding a permission constant needs merging into `CustomRole::PERMISSIONS` |

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
