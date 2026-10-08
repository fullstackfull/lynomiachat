# Final production release readiness

The last document before a controlled production deploy of Lynomia Chat. It answers one question — *what is left?* —
and it answers it at one revision, with the evidence attached to each claim.

**Nothing in this phase deployed, modified production, rotated a credential, dropped a table or changed production
data.** Where a fact could only come from the live server, it is marked as **operator-reported** and the report says
so rather than implying it was measured here.

---

## 1. The release

| | |
| --- | --- |
| Repository | `fullstackfull/lynomiachat` |
| Branch | `claude/practical-thompson-9xfqed` |
| Release SHA | `dfc8bf6e99b8c42958e04b603de0d29facf9707f` |
| Worktree | clean (`git status --porcelain` empty) |
| Upstream base | Chatwoot `4.18.0` (`config/app.yml`, `package.json`), last upstream commit merged `fcfad2d2` *"fix: limit app, widget, and admin search indexing (#15873)"* |
| Pre-removal reference tag | `pre-enterprise-removal` |
| Architecture | **Chatwoot OSS core (`app/`, `lib/`) + Lynomia custom (`custom/`)**. `enterprise/` is gone. |

### Architecture, verified at this revision

```
extensions                  ["custom"]
ChatwootApp.enterprise?     false
ChatwootApp.custom?         true
defined?(Enterprise)        nil
Audited.audit_class         Custom::AuditLog
advanced_search_allowed?    false
```

The overlay mechanism itself stays: `config/initializers/01_inject_enterprise_edition_module.rb` is what the **125**
`prepend_mod_with` / `include_mod_with` / `extend_mod_with` call sites in `app/` and `lib/` resolve through, and it is
how all **46** `Custom::` overlay modules attach. Most of those call sites now no-op, because they were sites only
Chatwoot Enterprise ever overrode — and that is exactly why the initializer is load-bearing: removing it would
silently detach Lynomia from core rather than raise.

### Migrations

| | |
| --- | --- |
| Migration files, `db/migrate` (OSS) | 180 |
| Migration files, `custom/db/migrate` (Lynomia) | 16 |
| Applied versions | 196 |
| Pending | **none** |
| Schema version | `20261006100000` |
| Invalid PostgreSQL indexes | **none** |

Measured against the local `chatwoot_test` database at this revision, not against production. The production
equivalents of the last two rows are run by `deployment/deploy.sh` step 5 (`ActiveRecord::Migration.check_all_pending!`
and the `pg_index WHERE NOT indisvalid` query), which is where they belong.

> **A deployment-critical detail.** The 16 Lynomia migrations are only visible to `rails db:migrate` because of
> `config/application.rb:52` — `config.paths['db/migrate'] << 'custom/db/migrate'`. If that line is ever lost, those
> 16 migrations do not fail: they quietly become pending, and `db:migrate` reports success having run nothing. The
> numbers above are the check: 180 + 16 = 196 applied.

### Gates re-run in this phase, at this revision

Every number below was produced in this phase, on a truncated test database, against the clean tree at
`dfc8bf6e`. The suite figures are deliberately **two focused runs rather than one full run**: the full Ruby suite was
run when this revision was created, and nothing in the tree has changed since, so what this phase adds is targeted
re-confirmation of each matrix row plus the environment-dependent gates.

| Gate | Command | Result |
| --- | --- | --- |
| Matrix-evidence suite — every product row | `rspec` over `spec/{controllers/devise_overrides,requests/custom,requests/documentation,models/custom,custom,services/custom,services/flows,services/whatsapp,lib/captain,models/commerce,services/commerce,policies/commerce}` and the Inbox, Audience, Flow, WhatsApp and Captain controller specs | **1,767 examples, 0 failures, 10 pending** in 4m34s |
| Contacts, Audiences, Campaigns, Automations | `rspec` over `spec/{controllers/api/v1/accounts/contacts,services/contacts,jobs/contacts,services/data_import,services/automation_rules}` plus the campaign and custom-filter model and controller specs | **249 examples, 0 failures** in 1m09s |
| The three relocated audit writers (§5.4) | `rspec spec/models/custom/channelable_audit_spec.rb spec/controllers/custom/api/v1/accounts/conversations/messages_controller_audit_spec.rb spec/jobs/custom/delete_object_job_audit_spec.rb` | **46 examples, 0 failures** — and **36 failures** with the three modules moved aside |
| Ruby style | `bundle exec rubocop --parallel` | **2,708 files inspected, no offenses** |
| JavaScript suite | `pnpm test` (vitest) | **472 files, 5,100 tests, all passed** |
| JavaScript / Vue lint — the repo's own gate | `pnpm eslint` (`eslint app/**/*.{js,vue}`) | exit 0 — **450 problems, 0 errors, 450 warnings**, all pre-existing `@intlify/vue-i18n/no-dynamic-keys` |
| The same lint, widened to locale JSON | `npx eslint app/javascript` | **65 problems: 11 errors, 54 warnings.** Every error is in Crowdin-owned translated locale JSON; none in any `.js` or `.vue` file. Attributed below |
| Production asset build | `pnpm vite build` | exit 0, **218 manifest entries** |
| Embeddable widget build | `pnpm build:sdk` | exit 0, `public/packs/js/sdk.js` **21,995 bytes** |
| Migration state | `migration_context` + `pg_index WHERE NOT indisvalid` | 196 applied, **0 pending, 0 invalid indexes** |
| Boot and wiring | `zeitwerk:check`, plus the probe in §1 | "All is good!"; `extensions ["custom"]`, `defined?(Enterprise)` nil |

The 10 pending examples are upstream skips, most of them `# Skipping since MFA is not configured in this
environment` — which is the expected consequence of §5.3, not a gap.

**The two lint invocations cover different things, and neither is a superset of the other** — worth stating, because
the numbers look contradictory otherwise. `pnpm eslint` passes the glob `app/**/*.{js,vue}`, so it lints JavaScript
and Vue across the whole of `app/` and nothing else. `npx eslint <directory>` lints `app/javascript` only, picks up
the locale JSON that the `@intlify/vue-i18n` plugin registers a processor for (`localeDir:
'./app/javascript/*/i18n/**.json'` in `.eslintrc.js`), and does **not** reach `.vue` files — which is why it reports
far fewer `no-dynamic-keys` warnings and the eleven JSON errors the repo's own gate never sees. **The repo's own gate
is green.**

**The 11 lint errors, attributed rather than waved past.** All eleven are in translated locale JSON, and none in
any JavaScript or Vue file: ten `no-irregular-whitespace` across
`fr/{agentBots,conversation,helpCenter,teamsSettings}.json`, `lt/conversation.json`, `lv/settings.json`,
`pt_BR/sla.json` and `th/{labelsMgmt,sla}.json`, plus one `prettier/prettier` line-wrapping nit in
`zh/generalSettings.json`. The "irregular whitespace" is U+202F — the narrow no-break space French typography
correctly places before a question mark: `"Êtes-vous sûr de vouloir supprimer {name}\u202F?"`. Checked rather than
assumed: every file is valid JSON (`JSON.parse` succeeds), the production asset build is unaffected (exit 0, 218
manifest entries), and `git log --author=Claude` is **empty for all ten files** — their last commits are upstream's
own translation syncs, authored `Captain` (Chatwoot's Crowdin bot) and Chatwoot engineers.

This repository's own rule is that only `en.json` and `en.yml` are edited for product strings, and that Crowdin sync
changes to translated files are not to be flagged. So these are left exactly as they are. "Fixing" the French ones
would replace correct French typography with a plain space.

**Two environment notes, recorded because they cost time and will cost it again.** The local Postgres loses its
host-auth password across a container restart, so a gate run needs it re-set before `rspec` can connect; and the test
database must be truncated before a gate run, because `use_transactional_fixtures` does not clean up rows committed
outside an example — a leftover handful of rows produces dozens of failures that look like product defects and are
not.

### Runtime requirements

| | |
| --- | --- |
| Ruby | 3.4.4 (`.ruby-version`) |
| Rails | 7.2.3.1 |
| PostgreSQL | 16 with `pgvector` (`ivfflat` indexes exist) |
| Redis | required (Sidekiq, Rack::Attack, caches) |
| Node / pnpm | Vite build + `build:sdk` |
| Sidekiq queues | 16, declared in `config/sidekiq.yml`, no waits — strict priority |
| Cron entries | 12 in `config/schedule.yml`, **0 unresolvable classes** |
| Job classes | 112 under `app/jobs` + `custom/app/jobs`, **0 unresolvable** |
| Health endpoint | `GET /api` → `app/controllers/api_controller.rb#index` |
| OpenSearch | **not required** (see §6) |
| Active Record encryption | **not required to boot**; a hard precondition for two features (see §5.3) |

---

## 2. The authoritative release matrix

One row per area named in the release brief, at this revision. No row carries a status inherited from an earlier
document: every one was re-established here, and the stale rows in `docs/p7/13-release-gates.md` and
`docs/p7/14-readiness-matrix.md` are corrected in §7.5.

| Status | Meaning |
| --- | --- |
| `PASS` | exercised here, green, evidence named |
| `PASS WITH CONFIG DECISION` | the code is green; a production configuration value has to be chosen deliberately before or at deploy |
| `REAL UAT REQUIRED` | needs one live transaction against a real third party; cannot be settled from a repository |
| `EXTERNAL MAINTENANCE` | real work, owned outside this release, not gating it |
| `BLOCKED` | cannot deploy until this is resolved |

### Platform

| # | Area | Status | Evidence |
| --- | --- | --- | --- |
| 1 | **Rails boot** | `PASS` | `zeitwerk:check` → "All is good!"; the boot probe above resolves `extensions`, the audit class and the router with no missing constant. `defined?(Enterprise)` is `nil`, so no overlay is half-attached |
| 2 | **Sidekiq** | `PASS` | 16 queues declared in `config/sidekiq.yml`; all 112 job classes under `app/jobs` and `custom/app/jobs` constantize; all 12 `config/schedule.yml` entries resolve to a real class. `deployment/deploy.sh` step 8 additionally refuses to report success if no Sidekiq process registers after the restart |
| 3 | **Migrations** | `PASS` | 196 applied, 0 pending, 0 invalid indexes, schema `20261006100000`; 180 OSS + 16 `custom/db/migrate` reconciled (§1) |
| 4 | **Frontend build** | `PASS` | `pnpm vite build` exit 0 at this revision, **218 manifest entries** written to `public/vite/.vite/manifest.json` |
| 5 | **SDK build** | `PASS` | `pnpm build:sdk` exit 0, `public/packs/js/sdk.js` **21,995 bytes**. This is the script customer sites embed and it comes from its own pipeline (`vite.lib.config.ts`), not from `pnpm vite build` — which is why `deployment/deploy.sh` runs it as a separate step and asserts the artifact |

### Product surfaces

| # | Area | Status | Evidence |
| --- | --- | --- | --- |
| 6 | **Inbox** | `PASS` | `spec/finders/conversation_finder_discoverability_spec.rb` — the default queue stays Open, `status: 'all'` reaches resolved / outbound-first / failed-only conversations, narrow-then-restore, deterministic ordering, inbox membership. `spec/services/conversations/filter_service_message_status_spec.rb` — the `message_status` filter against real Postgres, including no-duplicates and cross-account |
| 7 | **Contacts** | `PASS` | `spec/controllers/api/v1/accounts/contacts/` (labels, notes, attachments, contact inboxes, conversations), `spec/services/contacts/bulk_{action,assign_labels,remove_labels,delete}_service_spec.rb`, `spec/jobs/contacts/bulk_action_job_spec.rb`, `spec/services/data_import/`, and the phone-uniqueness pair `spec/models/contact_phone_{uniqueness,race}_spec.rb`. `contacts.company_id` is read in exactly two flag-gated places and dereferences no model (§7.3) |
| 8 | **WhatsApp** | `REAL UAT REQUIRED` | Inbound, outbound-to-delivered, new-contact-from-inbound and the remaining live scenarios were verified on the real server in an earlier phase. The approved-template-to-new-contact transaction has not been run. Code path green: `spec/services/whatsapp/`, `spec/services/custom/whatsapp/`. Procedure: §4 |
| 9 | **Template Manager** | `PASS` | `spec/custom/services/whatsapp/templates/{query,validator,duplication,operation_error_mapping}_spec.rb`; cross-account isolation over show/update/destroy/submit/duplicate in `spec/requests/custom/cross_account_isolation_spec.rb`. The manager itself is complete; what is unproven is Meta accepting a send, which is row 8, not this row |
| 10 | **Campaigns** | `PASS` | `spec/services/custom/whatsapp/oneoff_campaign_service_spec.rb`, `spec/controllers/api/v1/accounts/campaigns_controller_spec.rb`, `spec/controllers/api/v1/accounts/campaigns_audience_spec.rb`, `spec/models/campaign_audience_spec.rb`. A WhatsApp campaign's first real send shares row 8's gate |
| 11 | **Commerce** | `PASS WITH CONFIG DECISION` | `spec/models/commerce/`, `spec/services/commerce/`, `spec/policies/commerce/`. Two installation switches ship `true` and are inert with zero connected stores; a store cannot be connected at all until Active Record encryption keys exist. Decision: §5.2 |
| 12 | **Salla** | `PASS WITH CONFIG DECISION` | Three independent locks, each shipped off: `SALLA_ENABLED` `false`, `SALLA_ACTIONS_ENABLED` / `SALLA_RECOVERY_ENABLED` `false`, and `Commerce::Switches::PRE_UAT` lists `salla` for both features. Must remain disabled |
| 13 | **Zid** | `PASS WITH CONFIG DECISION` | Same three locks, same defaults. Zid's real-store UAT has no available test environment, so it stays behind `PRE_UAT`; that is an unavailable external environment, not a release blocker, because nothing can reach the provider while the locks hold |
| 14 | **Shopify** | `PASS WITH CONFIG DECISION` | Same three locks, same defaults. `SHOPIFY_COMMERCE_ENABLED` is separate from the legacy Shopify integration and does not affect it |
| 15 | **Audiences** | `PASS` | `spec/controllers/api/v1/accounts/contacts/audiences_spec.rb`, `spec/controllers/api/v1/accounts/custom_filters_shared_spec.rb`, `spec/models/custom_filter_spec.rb`, `spec/services/automation_rules/conditions_filter_service_audience_spec.rb`; show/update/destroy isolation and the agent's refusal to **share** are both in `spec/requests/custom/cross_account_isolation_spec.rb` |
| 16 | **Automations** | `PASS` | `spec/services/automation_rules/` (the rule engine, conditions filter and action service), plus the Lynomia action itself: `spec/services/custom/automation_rules/template_action_spec.rb`, `spec/models/custom/automation_rule_template_action_spec.rb`. The `send_whatsapp_template` action's first real send shares row 8's gate |
| 17 | **Flow Builder** | `PASS` | `spec/services/flows/` — runner, runner security, graph validator, versions, and the `send_template`, `choice`, `commerce_lookup`, `set_attribute_labels_assignment` nodes; `spec/controllers/api/v1/accounts/flows_controller_spec.rb`; show/update/publish/destroy isolation in the cross-account spec |
| 18 | **Audit** | `PASS` | Single system, single table: `Custom::AuditLog < Audited::Audit` on OSS `audits`. Reader: `spec/requests/custom/audit_log_reader_spec.rb`. All **four** manual Enterprise writers are now relocated into `custom/`: sign-in / sign-out (`spec/controllers/custom/devise_overrides/sessions_controller_spec.rb`), channel credential changes, message deletion and inbox / conversation deletion (§5.4, 46 further examples). Twelve `audited` declarations mirrored. Known Enterprise audit writers unaccounted for: **0**. Production holds 4,845 audit rows (operator-reported) and they are preserved — nothing in this release reads, updates or deletes one |
| 19 | **Auth** | `PASS` | `spec/controllers/devise_overrides/` including the Lynomia session overlay; Rack::Attack throttles sign-in by IP and by email, super-admin sign-in, password reset, confirmation resend and MFA verification. MFA itself is off because encryption keys are unset (§5.3) — that is the shipped state, not a defect |
| 20 | **Super Admin** | `PASS` | `custom/app/controllers/super_admin/{portals,categories,articles,billing_plans,billing_subscriptions}_controller.rb`; the documentation corpus is managed here and is explicitly unaffected by the tenant-side policy denial (`spec/requests/custom/tenant_help_center_removal_spec.rb`) |
| 21 | **Help & Support** | `PASS` | Tenant Help Center authoring is closed at the policy, not merely hidden: `spec/requests/custom/tenant_help_center_removal_spec.rb` covers administrator, agent and a custom role holding **every** permission, over every verb of portals, categories and articles plus the four bulk actions. Contextual help links resolve through `DocumentationController#article`, which 404s on an unpublished slug rather than dropping the reader on a home page |
| 22 | **Docs** | `PASS` | `/docs` → `DocumentationController#show` → the Help Center public renderer. `spec/requests/documentation/entry_points_spec.rb`, `spec/requests/documentation/global_ownership_spec.rb`, `spec/custom/services/documentation/content_seeder_spec.rb` — upsert-only and idempotent: the second and third consecutive seed each assert `[created, updated, unchanged] == [0, 0, 2]`, and a changed file updates its article rather than adding a second one. `content_seeder_corpus_spec.rb` covers the real corpus, 114 articles (57 EN + 57 AR, of which 28 are the WhatsApp error pages) |
| 23 | **Changelog** | `PASS` | `/changelog` → `DocumentationController#changelog`, same renderer, same portal machinery, covered by the same entry-points and global-ownership specs. A missing portal renders `documentation.not_set_up` with `404` instead of raising |
| 24 | **Captain** | `PASS WITH CONFIG DECISION` | Two live doors survive Enterprise removal, both inert without a credential, and they are guarded asymmetrically. `spec/lib/captain/`, `spec/controllers/api/v1/accounts/captain/`, `spec/models/concerns/captain_featurable_spec.rb`. Full classification and the decision: §5.1 |
| 25 | **OpenSearch** | `PASS` | **Obsolete gate** — there is nothing left to pass or fail. `advanced_search_allowed?` is `enterprise? && OPENSEARCH_URL.present?` with `enterprise?` permanently `false`, so no code path can consult OpenSearch and setting `OPENSEARCH_URL` would change nothing. §6 |

### Release mechanics

| # | Area | Status | Evidence |
| --- | --- | --- | --- |
| 26 | **Deployment path** | `PASS` (repository) / `EXTERNAL MAINTENANCE` (host) | `deployment/deploy.sh` covers every required step (§3). The gap is not in the script: the host still has the old unversioned `/root/deploy-lynomia.sh`, and retiring it is an operator action |
| 27 | **Rollback path** | `PASS` | `deployment/ROLLBACK.md` is written against the same numbered steps, states plainly what a rollback *cannot* undo, and refuses to present `db:rollback` as a release-boundary tool. `deployment/INCIDENT.md` for the record. Prerequisites: §8 |

**No row is `BLOCKED`.**

---

## 3. The deployment path

`deployment/deploy.sh` (178 lines, already in the repository) is the supported flow. Measured against the fifteen
requirements in the release brief:

| # | Requirement | Where | Behaviour on failure |
| --- | --- | --- | --- |
| 1 | Exact release SHA | step 1 `git rev-parse @{u}`; step 3 asserts `HEAD == $RELEASE_SHA` after the fast-forward | abort, no restart |
| 2 | Clean worktree | step 0 refuses a dirty tree | abort before anything is touched |
| 3 | Fetch / update safely | step 1 fetch-and-compare **before** the backup; step 3 `git merge --ff-only @{u}` | an already-deployed revision exits 0 having done nothing |
| 4 | Database backup before migration | step 2 `pg_dump -Fc`, stamped with the outgoing SHA | abort |
| 5 | Backup verification and retention | `[[ -s $DUMP ]]`, `sha256sum` beside the dump, `KEEP_BACKUPS=14` pruned oldest-first at the end | an empty dump aborts |
| 6 | `BUNDLE_FROZEN` | step 4 `BUNDLE_FROZEN=true bundle install` | abort. The fix is to resolve and commit `Gemfile.lock`, never to drop the flag |
| 7 | pnpm frozen lockfile | step 4 `pnpm install --frozen-lockfile` | abort |
| 8 | Migration statement timeout | step 5 `POSTGRES_STATEMENT_TIMEOUT=0`, for that step only | — |
| 9 | `db:migrate` | step 5 | abort, no restart |
| 10 | Pending-migration verification | step 5 `ActiveRecord::Migration.check_all_pending!` | abort |
| 11 | Invalid index check | step 5 `SELECT indexrelid::regclass::text FROM pg_index WHERE NOT indisvalid` | abort |
| 12 | Frontend production build | step 6 `pnpm vite build` + manifest assertion | abort before the restart |
| 13 | `build:sdk` | step 6 `pnpm build:sdk` + `public/packs/js/sdk.js` assertion | abort before the restart |
| 14 | Service restart | step 7 `systemctl restart chatwoot.target` | — |
| 15 | Readiness / health checks | step 8: 30 × `curl` against `HEALTH_URL` (`http://127.0.0.1:3000/api`), `systemctl is-active` on the target and on `chatwoot-web.1` / `chatwoot-worker.1`, and a registered-Sidekiq-process assertion | names the rollback document and the previous SHA |

The script's governing property: `set -Eeuo pipefail` plus an `ERR` trap that **never restarts**. Any failure before
step 7 leaves the previous version serving. That is deliberate — a half-deployed restart is worse than a postponed
deploy.

### What the host still runs

The server's `/root/deploy-lynomia.sh` is, per earlier evidence, roughly `git pull && bundle install && pnpm install
&& db:migrate && vite build && restart`. Three of its omissions have each either bitten a release here or would:
no `build:sdk` (every customer site keeps loading the previous widget indefinitely), no migration statement-timeout
override (a killed `CREATE INDEX CONCURRENTLY` leaves an INVALID index and a silently unindexed table), and no backup
before the migration.

**This is an operational item, not a code item.** The repository's script is ready; nobody has retired the host's.
Shipping a better script does not retire the old one.

---

## 4. The one real UAT: approved template → new contact

### Correction to earlier documentation

`docs/p7/14-readiness-matrix.md` row `P2` records this as *"BLOCKED ONLY ON REAL APPROVED TEMPLATE"* because
`order_delivered` was `PENDING` at Meta. **That is stale.** Operator-reported production state:

| | |
| --- | --- |
| Template | `order_delivered` |
| Language | `en_US` |
| Category | `UTILITY` |
| Status | **APPROVED** |
| Template ID | `1898998951089221` |
| WABA | `4584909965122758` |

Meta approval is no longer the gate. The gate is the live transaction.

### Why a repository cannot close this

The send gate is structural and reads live state:
`Whatsapp::TemplateProcessorService#find_template` (`app/services/whatsapp/template_processor_service.rb:29-35`)
searches the **channel's own synced snapshot** for a row matching name, language *and* `status == 'approved'`, and
returns no name when it finds none — and every caller refuses to send on a blank name. So a send depends on Meta's
verdict having been synced into `channel.message_templates`, which is a fact about the live channel. Nothing in a test
can substitute for it without faking the snapshot, which would prove nothing.

### Procedure

Run on the real server, in this order. **Do not run it until explicitly instructed** — step 4 sends a real WhatsApp
message to a real person at real cost.

| # | What it proves | How |
| --- | --- | --- |
| 1 | The approved template exists locally | Force a sync, then read it back: `POST /api/v1/accounts/<account>/inboxes/<inbox>/sync_templates` (route `config/routes.rb:208`), then the Template Manager list. Expect `order_delivered` / `en_US` / `UTILITY` / `approved` |
| 2 | It is **sendable**, not merely present | Read the channel's own snapshot: `GET /api/v1/accounts/<account>/inboxes/<inbox>/message_templates`. `order_delivered` must be there with `status` `approved` — that snapshot, not the manager's row, is what the send path searches. `Whatsapp::Templates::Query#sendable_for(inbox)` applies the same rule the composer and campaign picker use. If it is absent here, **stop**: the sync did not land, and the send would fail on a blank name |
| 3 | The recipient is genuinely new | A phone number with **no** existing `Contact` and no `ContactInbox` on this inbox, so nothing can pass as a 24-hour session reply. Verify before sending, not after |
| 4 | Meta accepts the send | Send from the Inbox compose surface with the template selected (the normal operator path, not a console call). A `2xx` from Meta is acceptance |
| 5 | The `wamid` is persisted | `Whatsapp::SendOnWhatsappService#send_template_message` does `message.update!(source_id: message_id)`. Read `messages.source_id` for the new message: it must be a `wamid.` string. This is the join key for everything after |
| 6 | The status webhook arrives | Meta POSTs to the app-level callback; `Whatsapp::IncomingMessageBaseService#process_statuses` looks the message up **by that `source_id`**. If `source_id` were missing, the webhook would find nothing and the message would sit at `sent` forever |
| 7 | Local state updates | `Messages::StatusUpdateService` moves the message `sent` → `delivered` → `read`. Watch `messages.status` change |
| 8 | It appears correctly in the Inbox | A conversation exists for the new contact, with the template message as the first outbound message and the contact created from the send |
| 9 | Failure classification is correct **if** Meta rejects | `update_message_with_status` stores `"<code>: <title>"` in `external_error`; `Whatsapp::DeliveryFailure` classifies only `131049` (`META_RECIPIENT_DELIVERY_RESTRICTION`, recipient-scoped, Retry correctly withdrawn) and `131042` (`META_BILLING_ELIGIBILITY`, account-scoped, Retry correctly kept). Any other code is `UNCLASSIFIED` and behaves as before. **Do not add codes to `CODES` to make a UAT result look tidier** — only codes this installation has observed on its own traffic belong there |
| 10 | Nothing was faked | No row is written by hand into `whatsapp_message_templates` or `channel_whatsapp.message_templates`; no `status` is set directly; no stub, no `source_id` typed in. The only writes are the ones the product makes |

A failure at step 1 or 2 is a sync problem and is fixable here. A failure at step 4 with a classified code is Meta's
policy, correctly surfaced — that is a *passed* UAT of the failure path, not a product defect. A failure at steps 5–8
is a product defect and would reopen this gate.

---

## 5. Production configuration decisions

Three, each with one defensible answer, plus §5.4 — which was a fourth decision when this report was first written
and is now a closed item rather than a decision.

### 5.1 Captain / `ruby_llm`

Re-evaluated in the current no-Enterprise tree rather than from pre-removal notes — which matters, because two
pre-removal assumptions turned out to be false.

**What survives, classified:**

| Classification | What |
| --- | --- |
| **A — OSS Captain feature, live** | **Two** entry points reach `ruby_llm 1.15.0` through `lib/captain/base_task_service.rb` and its six subclasses — see the door table below |
| **C — inactive / dead** | `Integrations::LlmBaseService` — **no subclass and no caller** anywhere in `app/`, `lib/` or `custom/`; only its own spec references it. `Integrations::Captain::ProcessorService` — **no instantiator**, and it calls an external `CAPTAIN_API_URL` rather than `ruby_llm`. `Integrations::Hook#process_event` returns `{ error: 'No processor found' }`, so the `openai` integration hook is not an execution path |
| **C — inactive** | `captain_v1_action_classifier`, `captain_integration_v2`, `captain_document_auto_sync` — all `enabled: false` in `config/features.yml` |
| **D — production configuration decision** | the `captain_tasks` feature flag, which is the **only** Captain flag shipping `enabled: true` (`config/features.yml:241-243`), and the `CAPTAIN_OPEN_AI_API_KEY` installation config |
| **E — release blocker** | **none** |

**The two doors, and they are guarded very differently:**

| | Door | Gates, in order |
| --- | --- | --- |
| 1 | `POST /api/v1/accounts/:id/captain/tasks/{rewrite,summarize,reply_suggestion,label_suggestion,follow_up}` (plus `GET/PUT .../captain/preferences`) | `captain_tasks` flag — ships **`enabled: true`** — then an API key. `Captain::TasksPolicy` returns `true` for **every** action, so **any authenticated member of the account**, agents included, may call it |
| 2 | `POST /api/v1/accounts/:id/inboxes/:inbox_id/csat_template/analyze` → `CsatTemplateUtilityAnalysisService` → `Captain::CsatUtilityAnalysisService` | `check_admin_authorization?` (**administrator only**), then `validate_whatsapp_channel`, then the `captain_integration` flag — which ships **`enabled: false`** — then `captain_tasks`, then an API key. On any LLM error it falls back to the rule-based `baseline`, so a missing key is invisible to the caller |

Door 2 is the one with the `captain_integration` flag off, an administrator requirement, and a graceful degradation
path. Door 1 has none of those three. That asymmetry is not an accident of this release — the controller comment at
`app/controllers/api/v1/accounts/inbox_csat_templates_controller.rb:2-11` says in as many words that an agent
"could spend account LLM budget through `#analyze`", which is exactly why it was tightened. **The same reasoning has
never been applied to door 1.**

**Two corrections to pre-removal assumptions, both verified at this revision:**

1. *"Tenant OpenAI hooks are a second credential door."* They are not, any more.
   `Captain::BaseTaskService#use_account_openai_hook?` returns a literal `false` in OSS
   (`lib/captain/base_task_service.rb:187-189`) — it was the Enterprise module that overrode it, and that module is
   gone. `llm_credential` therefore resolves to `system_llm_credential` only. A tenant **cannot** bring its own key.
   The single credential source is the `CAPTAIN_OPEN_AI_API_KEY` installation config.
2. *"A deploy might switch `captain_tasks` on."* It cannot. `features.yml` defaults reach an account through
   `before_create :enable_default_features` (`app/models/concerns/featurable.rb:54`), which runs **at account
   creation only**. `ConfigLoader#reconcile_feature_config` updates the `ACCOUNT_LEVEL_FEATURE_DEFAULTS` list, never a
   per-account bitmask. Existing accounts' flags are untouched by this deploy.

**Current behaviour with no key configured** — `lib/captain/base_task_service.rb:42-44`, the OSS guards, which are now
the only guards:

```ruby
return { error: I18n.t('captain.disabled'),        error_code: 403 } unless captain_tasks_enabled?
return { error: I18n.t('captain.api_key_missing'), error_code: 401 } unless api_key_configured?
```

Both doors route through this same `make_api_call`, so today door 1 returns `401 api_key_missing` and door 2 silently
falls back to its rule-based baseline. Either way: no network call, no spend, no `ruby_llm` execution. The two High
ReDoS advisories against `ruby_llm 1.15.0` (CVE-2026-67987, CVE-2026-67989) are unreachable for that reason — the
library is loaded but never invoked.

**The smallest safe production decision:**

1. **Leave `CAPTAIN_OPEN_AI_API_KEY` unset.** This single value is what keeps Captain inert, the advisories
   unreachable, and the spend at zero. It is also the whole decision: nothing else needs changing.
2. **Leave `config/features.yml` alone — and know that editing it would do nothing here anyway.** This is worth
   stating precisely, because the obvious move is the wrong one. `ConfigLoader::DEFAULT_OPTIONS` sets
   `reconcile_only_new: true` (`lib/config_loader.rb:2-5`) and both seeding invocations take that default
   (`db/seeds.rb:3`, `lib/tasks/db_enhancements.rake:5`), so `compare_and_save_feature` computes
   `(config.value + account_features).uniq { |h| h['name'] }` — **existing row first**, which means the already-seeded
   `captain_tasks: true` wins and a `features.yml` edit is silently discarded (`:81-90`). The real controls are:
   - **New-account default** → `rake feature_defaults:toggle`, which writes `ACCOUNT_LEVEL_FEATURE_DEFAULTS` and
     clears the cache. Its own description says "affects new account signups only" (`lib/tasks/feature_defaults.rake:5`).
   - **Existing accounts** → they already have it on, and not by accident: the applied migration
     `db/migrate/20260120121402_enable_captain_tasks_for_existing_accounts.rb` does
     `account.enable_features!('captain_tasks')` over every account in batches. That is the explanation for the
     broad enablement observed in production. Turning it back off for existing accounts has **no rake task** — it
     would take a new migration in the repo's own established style (there are seven precedents, e.g.
     `20260226153427_disable_report_rollup_for_all_accounts.rb`), or a per-account change through Super Admin or the
     Platform API (`app/controllers/platform/api/v1/accounts_controller.rb:43`).

   None of that is needed for this release, because the credential — not the flag — is what keeps both doors shut.
3. **If a key is ever set, two things must be done first**, because Enterprise removal took the guard rails with it:
   - **Add a Rack::Attack throttle covering both doors.** `config/initializers/rack_attack.rb` has no Captain rule
     at all; the only applicable limit is the global `req/ip` of 3000/minute. The Enterprise wrapper that enforced
     the `captain_responses` usage quota left with the overlay, so there is currently **no quota at all**.
   - **Bring door 1 up to door 2's authorization.** `Captain::TasksPolicy` returning `true` for every action means
     any agent of an account with `captain_tasks` on could make unmetered LLM calls at the installation's expense —
     precisely the exposure the CSAT controller's own comment identified and closed for door 2.
   Setting a key is therefore a separate, reviewed change. It is **not** part of this release, and nothing in this
   release needs it.

Not done here, per the brief: Captain is not redesigned and `ruby_llm` is not upgraded. The published fix for the
advisories is `>= 2.0.0.rc1`, a release-candidate major bump of the LLM client, which is exactly the blind upgrade a
release window should not contain.

### 5.2 Commerce

Three independent locks guard each un-UAT'd provider, and any one of them alone keeps it off
(`custom/app/services/commerce/switches.rb:20-30`):

```ruby
provider_actions_enabled?(p)  = actions_enabled? && Commerce::Providers.enabled?(p) && uat_cleared?(:actions, p) && flag(ACTION_KEYS[p], …)
provider_recovery_enabled?(p) = … && Commerce::Providers.enabled?(p) && uat_cleared?(:recovery, p) && flag(RECOVERY_KEYS[p], default: false)
```

| | Salla | Zid | Shopify Commerce | WooCommerce |
| --- | --- | --- | --- | --- |
| Provider read switch | `SALLA_ENABLED` **false** | `ZID_ENABLED` **false** | `SHOPIFY_COMMERCE_ENABLED` **false** | inherits `Base.enabled? = true` |
| In `PRE_UAT`? | **yes**, both features | **yes**, both features | **yes**, both features | no |
| Actions switch | **false** | **false** | **false** | `WOOCOMMERCE_ACTIONS_ENABLED` true |
| Recovery switch | **false** | **false** | **false** | n/a (no carts) |

**The correct production defaults for this release:**

- **Safe to enable, and already correct as shipped:** `COMMERCE_ACTIONS_ENABLED=true` and
  `COMMERCE_RECOVERY_ENABLED=true`. These are installation kill switches, not features. With zero connected stores
  they are inert, and leaving them on means the kill switch is in its normal position rather than needing to be found
  during an incident.
- **Safe but unused:** WooCommerce order actions. Fully enabled at the installation level, and still requires the
  account-level `lynomia_commerce` feature flag (ships `enabled: false`), a connected store, and that store's
  administrator opting in with a Read/Write API key.
- **Must remain disabled:** Salla, Zid and Shopify Commerce — all three locks, on both features. Verify in
  **Super Admin → Settings → Lynomia Commerce**, *not* in the environment: `Commerce::Switches.flag` reads
  `GlobalConfig.get_value(name)` first and only falls back to `ENV` when that is `nil`. Because
  `config/installation_config.yml` seeds each of these rows with `value: false`, the Super Admin value wins and an
  `ENV` override would be silently ignored. Checking `.env` would give the wrong answer.
- **`COMMERCE_ALLOW_PRE_UAT_PROVIDERS` must remain absent entirely.** It is the one switch that bypasses `PRE_UAT`,
  and by design it is read **only** from `ENV` (`ENV.fetch`, never `GlobalConfig`), so it cannot be set from Super
  Admin. It exists for staging and simulated end-to-end runs. Setting it in production would turn on three providers
  that have never completed a real UAT.
- **External UAT blocked:** Zid, for want of an available test environment. This does not gate the release, because
  the locks above mean nothing in production can reach Zid. A provider leaves `PRE_UAT` through a reviewed code
  change, not a switch.

**The cross-dependency that matters more than any switch:** `Commerce::Store` declares `encrypts :credentials` and
validates `credentials_encryptable` (`custom/app/models/commerce/store.rb:42-59`), which adds
`errors.add(:credentials, :encryption_not_configured)` unless all three Active Record encryption keys are present. So
**no store of any provider can be connected until §5.3 is done.** Commerce is doubly inert today, and it fails as a
validation error rather than a crash.

### 5.3 Active Record encryption

Operator-reported: `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` is not set. `Chatwoot.encryption_configured?`
(`config/application.rb:101-107`) requires **all three** of the primary key, the deterministic key and the key
derivation salt.

Every `encrypts` field in the current tree, classified:

| Field | Classification | Why it cannot be reached today |
| --- | --- | --- |
| `User#otp_secret`, `User#otp_backup_codes` | **future-only** | MFA is gated on `Chatwoot.mfa_enabled?`, which delegates to `encryption_configured?`; `mfa_controller.rb:37` refuses before any write |
| `Commerce::Store#credentials` | **future-only** | the `credentials_encryptable` validation refuses the save with `:encryption_not_configured` |
| `Commerce::Cart`, `Commerce::CustomerLink#external_customer_id` | **future-only** | both require a `Commerce::Store`, which cannot exist |
| — | **not applicable after Enterprise removal** | no `encrypts` field was left behind by the removed overlay |
| — | **currently used production field** | **none** |
| — | **release blocker** | **none** |

**Not a blocker; a hard precondition for two features.** The app boots and serves without the keys, and no existing
production data is encrypted, so there is nothing to decrypt and no migration to run. But:

> **Active Record encryption keys are a precondition for ever connecting a Commerce store, and for MFA.** Neither
> feature can be switched on by configuration alone.

One trap to avoid when the keys are eventually set: `config/application.rb:75` configures Rails encryption when the
**primary key alone** is present, while `encryption_configured?` requires all three. Setting one or two leaves a state
where Rails believes encryption is configured but Lynomia's own guards still report it off. The product stays safe
(both guarded features check `encryption_configured?`), but it is a misconfiguration. **Set all three together or
none.**

No key is generated or configured in this phase, per the brief.

---

### 5.4 Three severed Enterprise audit writers — found, and now closed

**This section previously recorded two un-relocated writers as an open gap and a hold on the `audit_logs` feature.
All three are now closed** (a sweep by mechanism rather than by kind found a third), so the hold is lifted and the
only remaining decision about `audit_logs` is the ordinary one of whether to turn the feature on.

The sweep that settles the surface is one query, and it is the one that should have been run in the removal phase:

```
git grep -n -E "AuditLog\.(create|create!|new|insert_all)|Audited::Audit\.(create|create!|new|insert_all)|insert_all!?\(" \
    pre-enterprise-removal -- enterprise app lib
```

Six manual Enterprise audit writers, and nothing else. Three had come across with the declarations or in the earlier
repair; three had not, and all three shared one shape — a **live** OSS extension point (a callback or a
`prepend_mod_with`) whose body is an **empty method**, with no `Custom::` counterpart. Nothing raises, no request
fails, the row is simply never written:

| Writer | OSS extension point, still wired | Relocated to |
| --- | --- | --- |
| Channel credential / configuration change → `Inbox` `update` row | `app/models/concerns/channelable.rb` — `after_update` at `:7`, empty body at `:10`, `prepend_mod_with` at `:13` | `custom/app/models/custom/channelable.rb` (owner on all **twelve** Channelable models) |
| Message deletion → `Message` `destroy` row | `app/controllers/api/v1/accounts/conversations/messages_controller.rb` — OSS `destroy` at `:21`, `prepend_mod_with` at `:132` | `custom/app/controllers/custom/api/v1/accounts/conversations/messages_controller.rb` |
| Inbox and conversation deletion → `destroy` row with attributes | `app/jobs/delete_object_job.rb` — empty `process_post_deletion_tasks` at `:16`, `prepend_mod_with` at `:43`; `inboxes_controller.rb:81` and `conversations/delete_service.rb:6` thread a user and an IP through to it for no other purpose | `custom/app/jobs/custom/delete_object_job.rb` |

The third was the one a declaration-level comparison could never have reached, and it also explains an apparent
orphan: `inbox:destroy` has a translation key in the dashboard's activity map while `Custom::Audit::Inbox` is
declared `on: [:create, :update]`. Inbox deletion rows never came from the declaration — they came from that job.

**One deliberate deviation, and it is a security fix rather than a port.** The Enterprise channel writer audited
`saved_changes.except('updated_at', 'secret')`, excluding exactly one credential column — `secret`, which only
`channel_api` has. Every other channel credential would have gone into `audits.audited_changes` in plaintext, old
value and new, on a row the reader renders verbatim to any administrator: `imap_password`, `smtp_password`,
`page_access_token`, `access_token`, `refresh_token`, `line_channel_secret`, `bot_token`, `auth_token`,
`api_key_secret`, `twitter_access_token_secret`, `website_token`, `hmac_token`, `business_management_token` and the
`provider_config` blob carrying the WhatsApp `api_key`. The relocated writer keeps the key and replaces the value
with `[FILTERED]`; which changes write a row at all is unchanged. **Reported rather than copied, per the brief's
instruction not to weaken security for behavioural parity.**

**Evidence.** `spec/models/custom/channelable_audit_spec.rb`,
`spec/controllers/custom/api/v1/accounts/conversations/messages_controller_audit_spec.rb` and
`spec/jobs/custom/delete_object_job_audit_spec.rb` — **46 examples; 36 fail with the three modules moved aside and 0
fail with them in place.** The examples that pass either way assert the product behaviour (the message is still
soft-deleted, its attachments still destroyed) and the cases where no row is expected, which is exactly the shape of
this gap: the product worked, the audit trail did not. Secret safety is eleven separate examples, one per credential
column with a factory, each asserting the secret string itself is absent from the payload rather than that a marker
is present.

**No frontend change and no documentation change were needed**, which is the clearest sign these were severed
writers and not absent features: the serializer already special-cased `auditable_type == 'Message'`, the activity map
already carried `message:destroy` and `inbox:destroy`, both types were already filterable, and Lynomia's own user
documentation (`custom/db/documentation/en/administration/audit-logs.md`) already lists message and conversation
deletions as an event family — its worked example is an administrator filtering to **Inboxes** and finding the entry
that says a colleague changed that inbox, which is the channel writer's row and could not be produced until now. Reader compatibility is proven through the real
endpoint — both row types come back under the `types: ['Inbox']` and `types: ['Message']` filters the dashboard
sends, the message row without its deleted body and the channel row with the credential filtered.

**Known Enterprise audit writers unaccounted for: 0.** Twelve `audited` declarations mirrored, six manual writers
enumerated and each one placed. `accounts_with_audit_logs` remains **0** in production and nothing here enables the
feature, so none of this is observable in production until an administrator turns it on — which is now a plain
product decision rather than a decision gated on missing writers.

---

## 6. OpenSearch — an obsolete gate

`docs/p7/14-readiness-matrix.md` carries row `S18` as `NOT TESTED` for want of a reachable OpenSearch, and both that
document (rows `S1`, `S18`, and §"Run four — the gate") and `docs/p7/13-release-gates.md` (§"Test suites") describe
the full Ruby suite as "1 failure" on that basis. Re-evaluated at this revision:

1. **The spec is gone.** The one failure was `spec/enterprise/services/voice/call_transcription_service_spec.rb`.
   `Voice::` was Enterprise, and the spec was deleted with the overlay. There is nothing left to run.
2. **Setting `OPENSEARCH_URL` would change nothing.** `ChatwootApp.advanced_search_allowed?` is
   `enterprise? && ENV['OPENSEARCH_URL'].present?`, and `enterprise?` is now a literal `false`. The conjunction can
   never be true.
3. **Search always takes the SQL path.** `advanced_search` is an empty stub in OSS. There is no second search
   implementation to be degraded to.

So: **not a production blocker, and not an unavailable optional test dependency either — an obsolete gate.** No real
production impact exists, because no code path consults OpenSearch. The three stale references are corrected in §7.5.

---

## 7. External and non-blocking maintenance

Four maintenance items (§7.1–§7.4), none of which blocks this deploy and each of which has an owner outside the
release, plus a record of the stale gates this document supersedes (§7.5).

### 7.1 Google OAuth client secret rotation — `EXTERNAL MAINTENANCE`

The secret was disclosed into a session transcript in an earlier phase and must be treated as compromised. Steps and
rollback: `docs/pre-p7-closeout/05-security-cleanup.md` §A.

**Timing: independently of this deploy, and preferably before it. Never concurrently with it.**

- **Independent**, because this release does not touch the server-side Google OAuth path. Measured with
  `git log --author=Claude -- <file>`, which is how this fork's own commits are distinguished from upstream's:
  **zero** Lynomia commits touch `app/controllers/api/v1/accounts/google/authorizations_controller.rb`,
  `app/controllers/concerns/google_concern.rb`, `app/services/google/refresh_oauth_token_service.rb` or
  `config/initializers/omniauth.rb`. The one Google-related change on this branch is a button's branding.
- **Preferably before**, because the exposure window is open now, and the rotation is cheap and reversible: adding a
  new secret in Google Cloud before deleting the old one leaves both valid, so there is no outage.
- **Never concurrently**, because the rotation edits `.env` and needs `systemctl daemon-reload && systemctl restart
  chatwoot.target`. Interleaving that restart with the deploy's restart makes any failure unattributable. Rotate,
  verify Google sign-in, then deploy.

A related hardening item, separate from the rotation: the Google values live **both** as `Environment=` lines in the
systemd units and in `.env`, and unit-file environment is readable by any local user through `systemctl cat` and
`/proc/<pid>/environ`. `.env` alone is the better single home. WhatsApp credentials are not exposed this way — there
are no `WHATSAPP_*` entries in either unit.

### 7.2 The dormant `chatwoot2_production` database — `EXTERNAL MAINTENANCE`

Operator-reported state: `chatwoot2_production` holds `channel_whatsapp id=1` carrying the **same** phone number,
`phone_number_id` and WABA as live inbox #77, but a **different** `api_key` fingerprint. No application serves that
database — only `chatwoot-web.1` and `chatwoot-worker.1` exist, both on `/home/chatwoot/chatwoot`.

A different fingerprint resolves the question that kept this open: it is a **separate** token in an unserved database,
not the live one. So revoking it cannot break inbox #77.

**Does not block the deploy.** No active dependency: nothing in this codebase connects to `chatwoot2_production`, and
inbox #77 reads its own credential from `chatwoot_production`.

**Safe post-release cleanup, in this order, after the deploy has been verified:**

1. `pg_dump -Fc` the dormant database, so every step below is recoverable.
2. Re-run the fingerprint comparison in **`docs/pre-p7-closeout/05-security-cleanup.md` §B** and confirm the two
   still differ. Do not act on the earlier reading alone — an unknown credential is not touched until its identity is
   proven **at the time of acting**.

   > **Use §B and not the variant in `docs/p7/01-secrets-remediation.md`.** That one queries
   > `SELECT api_key FROM channel_api`, and `channel_api` **has no `api_key` column** (`db/schema.rb`: it carries
   > `hmac_token` and `secret`). With `2>/dev/null` swallowing the error and `head -c 16` truncating empty output, it
   > prints an empty fingerprint for *both* databases — which reads as a MATCH, and MATCH is exactly the outcome that
   > says "do not revoke". A broken query would therefore manufacture agreement. §B reads the right place:
   > `channel_whatsapp.provider_config->>'api_key'`, which is where a WhatsApp token actually lives.
3. Revoke that token at Meta. This is the only irreversible step, and it is also the only one that closes the
   exposure, which is why it comes after 1 and 2 and not before.
4. Confirm inbox #77 is still sending and receiving — the direct check that the right token was revoked.
5. Only then drop the dormant database, or delete the row.

**Nothing is revoked, deleted or dropped in this phase.**

### 7.3 `companies` legacy data — **post-release migration, then future cleanup**

Operator-reported production counts: `companies` = 97 rows, `contacts.company_id IS NOT NULL` = 123 contacts.

**Classification: not a deploy blocker. A post-release migration decision, and then a future cleanup.**

Runtime correctness was checked rather than assumed. After Enterprise removal there is **no `Company` model, no
controller, no route and no frontend component** — `app/models/company.rb` does not exist and no `belongs_to :company`
is declared anywhere. What remains that reads the data is exactly two places, and both read the raw integer column:

- `app/models/contact.rb:163` — `data[:company_id] = company_id if account.feature_enabled?('companies')`
- `app/views/api/v1/models/_contact.json.jbuilder:9` — the same, same flag

Because no association exists, **no dereference is possible**: there is no code path that can turn `company_id` into
an object and fail. The `companies` feature flag itself ships `enabled: false` (`config/features.yml:230-233`). So
these 123 rows are inert in production today, and would remain merely an emitted integer even if an account had the
flag on.

> **The `companies` table must NOT be dropped, and `contacts.company_id` must NOT be nulled, before a reviewed
> backfill and cleanup phase.** The 97 company names are the only remaining record of those relationships; a contact
> can hold a free-text `company_name` in `additional_attributes`, but that is a different field and is not populated
> from these rows. Dropping first and backfilling later is not available.

Also left in place, and deliberately: the orphaned `companies.json` locale strings, which are loaded into the i18n
bundle but referenced by nothing now that the Companies UI is gone. Dead translation data, harmless, upstream-owned
and Crowdin-managed. Removing it is cleanup, not release work, and this phase does not modify unrelated locale files.

### 7.4 Host operations — `EXTERNAL MAINTENANCE`, separate window

Known host state: a pending Ubuntu restart and available package/security updates.

**Handle these in their own window, before the application deploy, not inside it.** The reasoning is attribution: a
host reboot restarts `chatwoot.target` anyway, so combining them means a boot-time failure and a new-release failure
look identical. Reboot first, confirm the **current** release comes back healthy, then deploy — each change isolated
and attributable.

One read-only precondition the operator should check **before** the reboot, so the reboot is not where it is
discovered: `systemctl is-enabled chatwoot.target chatwoot-web.1.service chatwoot-worker.1.service`. If any of them is
not enabled, the host comes back without the application.

Scope discipline: the host updates are not part of the application release and nothing in this release depends on
them. Application release safety is the priority, and the only coupling is the restart, which is handled by
sequencing.

### 7.5 Stale gates corrected

For the record, since the brief requires no stale gates:

| Stale assertion | Where | Correct position |
| --- | --- | --- |
| Full Ruby suite has "1 failure" needing OpenSearch | `14-readiness-matrix.md` rows `S1` / `S18` and §"Run four"; `13-release-gates.md` test-suites table | The spec was Enterprise's `Voice::CallTranscriptionService` and was deleted with the overlay. OpenSearch is an obsolete gate (§6) |
| `P2` — WhatsApp scenario 3 blocked on Meta approval | `14-readiness-matrix.md` | `order_delivered` is **APPROVED**. The gate is the live transaction (§4) |
| `C10` — dormant token identity unknown | `14-readiness-matrix.md` | Fingerprints **differ**; it is a separate token in an unserved database (§7.2) |
| `C5` — `ruby_llm` advisories, "every Captain feature flag ships disabled" | `14-readiness-matrix.md` | That reason was imprecise: `captain_tasks` ships **enabled**. The advisories are unreachable for a different and firmer reason — both doors to `ruby_llm` require a credential and there is none, and a tenant can no longer supply one (§5.1) |
| `O5` — commerce provider switches unconfirmed on the host | `14-readiness-matrix.md` | Still an operator confirmation, but the place to confirm is **Super Admin**, not `ENV` (§5.2) |
| `L1` / `L2` — `enterprise/LICENSE` and Enterprise licensing | `14-readiness-matrix.md` | Moot. `enterprise/` no longer exists in this tree; the architecture is Chatwoot OSS core + Lynomia custom |

---

## 8. Prerequisites

### Deployment prerequisites

1. **Host operations done and verified first**, in their own window (§7.4).
2. **Google OAuth rotation done, or explicitly deferred** — but not scheduled inside the release window (§7.1).
3. **Confirmed in Super Admin, not `ENV`:** `SALLA_ENABLED`, `ZID_ENABLED`, `SHOPIFY_COMMERCE_ENABLED` and all six
   per-provider action/recovery switches are off (§5.2).
4. **`COMMERCE_ALLOW_PRE_UAT_PROVIDERS` absent from the environment and from both systemd units** (§5.2).
5. **`CAPTAIN_OPEN_AI_API_KEY` unset** (§5.1).
6. **Active Record encryption keys: all three, or none.** Not required for this deploy (§5.3).
7. **The `audit_logs` account feature needs no hold.** All four manual writers are relocated (§5.4), so enabling it
   is now an ordinary product decision. It is off on every production account today; leaving it off changes nothing.
8. **The release SHA is pushed and is the branch's upstream tip**, so `git merge --ff-only @{u}` resolves to it.
9. **Disk:** at least 2 GB free on the application filesystem — the script checks, but checking late costs a window.
10. **Deploy with `deployment/deploy.sh`**, not `/root/deploy-lynomia.sh` (§3).
11. **`rails db:migrate` must run through the application's own configuration**, so that
    `config/application.rb:52` contributes `custom/db/migrate`. 16 of the 196 migrations live there.

### Rollback prerequisites

1. **The outgoing SHA and the pre-deploy dump path.** `deployment/deploy.sh` prints both at the start and the end of
   every run. Capture that output — `git reflog` and `/var/backups/lynomia/` are the fallback, not the plan.
2. **Both bundles must be rebuilt on the way back.** `public/vite` and `public/packs` are gitignored build output;
   checking out old code does not restore old assets, and a new-asset/old-code mix fails in the browser rather than on
   the server. This is the step people skip (`ROLLBACK.md` step 3).
3. **Know what the release migrated before assuming old code is safe on the new schema.**
   `git diff --name-only $PREVIOUS_SHA..<release-sha> -- db/migrate custom/db/migrate`. That check has since been
   performed for this release, migration by migration, in
   `docs/p7/CONTROLLED-PRODUCTION-DEPLOY-RUNBOOK.md` §3 — **and it found one exception to the generic
   "the migrations are additive" assumption.** `custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb`
   adds a unique index whose satisfiability depends on `app/models/contact.rb:231`, a blank→NULL normalisation that
   ships in the same release (commit `6cc48231`). A code-only rollback therefore leaves the index enforcing a rule
   nothing upholds, and a contact write with a blank phone number raises `ActiveRecord::RecordNotUnique` on the second
   one in an account — verified by executing it. That one migration must be reversed by
   `rails db:migrate:down VERSION=20261004110000` (its own `down` re-adds the plain index before dropping the unique
   one), **before** the old code is checked out. The runbook's §3, §4 and **M6** are the authority on this; where
   `ROLLBACK.md`'s release-agnostic wording differs, they govern.
4. **Do not reflexively `db:rollback`.** It runs the `down` of the last migration only, knows nothing about a release
   boundary, and raises `IrreversibleMigration` on the ten `def up`-only migrations the runbook's §3 enumerates.
   `db:migrate:down VERSION=` targeting one known version is a different command and is the only database rollback
   the runbook sanctions.
5. **A dump restore loses every message, conversation and order written since the dump.** On a live messaging product
   that is minutes of real customer conversations. It needs the service owner's explicit decision, not an operator's
   judgment call mid-incident.
6. **Accept what no rollback can undo:** WhatsApp messages already sent, provider-side configuration the release
   changed (above all a phone-level `override_callback_uri`, which outranks the app-level callback and is invisible in
   the Meta App dashboard), Stripe state, delivered webhooks, sent emails, and Sidekiq jobs the new code already
   enqueued.

---

## 9. Final release recommendation

**No release blocker was found at this revision.** The platform rows are green, every product surface is covered by
tests that run here, the deployment script covers all fifteen required steps with abort-before-restart semantics
throughout, and the rollback path is written against those same steps.

What is left divides cleanly:

- **One gate needs a live transaction.** The approved template → new contact WhatsApp send (§4). It cannot be closed
  from a repository, and nothing short of doing it honestly would close it. Everything that depends on it — WhatsApp
  campaigns, the `send_whatsapp_template` automation action, the template picker in flows — is green in code and
  waits on the same single transaction.
- **Three configuration decisions**, all "leave it as it is, knowingly": `CAPTAIN_OPEN_AI_API_KEY` unset (which is
  what keeps **both** `ruby_llm` doors inert and the two ReDoS advisories unreachable), the three Commerce provider
  switches off, and `COMMERCE_ALLOW_PRE_UAT_PROVIDERS` absent. Active Record encryption keys are a precondition for
  Commerce and MFA, not for this deploy.
- **Four items are owned outside this release** and gate nothing: the Google OAuth rotation, the dormant database's
  token, the `companies` legacy rows, and the host's pending restart and updates.
- **The audit-provenance gap this report opened is closed.** Three severed Enterprise audit writers — channel
  credential changes, message deletion, and inbox / conversation deletion — are relocated into `custom/` with 46
  examples behind them, and the pre-removal writer surface is now enumerated by mechanism with **0 unaccounted**
  (§5.4). The channel writer no longer stores credentials, which the Enterprise original did.

**The recommendation is to deploy under control, with the WhatsApp UAT run immediately afterwards on the live
release**, in this order: host window → Google OAuth rotation → application deploy via `deployment/deploy.sh` →
verify readiness → run the §4 UAT → then the §7.2 dormant-database cleanup.

The UAT is placed after the deploy deliberately. It exercises the template sync, the send path, the `wamid` round
trip and the status webhook **of the release being shipped**; running it against the current production code would
prove something about code that is about to be replaced.

---

## Verdict

> ## READY AFTER REAL UAT

Zero release blockers. One real-UAT item: the approved-template-to-new-contact WhatsApp send (§4), which must be run
against the deployed release. Three configuration decisions (§5), all deliberate no-ops. Four external maintenance
items, none gating (§7). The audit-provenance gap recorded in §5.4 is closed, with 0 Enterprise audit writers
unaccounted for.

**Nothing in this phase deployed, modified production, rotated a credential, dropped a table or changed production
data.**
