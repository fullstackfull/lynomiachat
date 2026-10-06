# 12 — Proposed implementation phases

Repo `/home/user/lynomiachat`, branch `claude/practical-thompson-9xfqed`, HEAD `6c381e96`.

Covers brief **Part 27** and the decision summary. Provenance: all fifteen area inventories, all six adversarial
verdicts, and `/tmp/claude-0/disc/AUTHORITATIVE-CORRECTIONS.md` — where an inventory and a verifier disagreed the
verifier wins and the line is marked **(V)**. Claims marked **(R)** I re-read in the repo myself at this HEAD while
writing this document. Sizes are estimates, not repo facts, and are marked as such. **No migration is proposed here.**
Where one is required the requirement is stated and left for approval (§11).

---

## 1. The decision

**Run the defect pre-phase first — it is four to six days and one of its eight items makes every other branding
decision in this program meaningless until it lands. Then ship the audience and campaign entry path, because two of
the thirteen starter recipes already in the tree cannot be used until it exists. Put the starter library third, the
Documentation Center fourth, and the WhatsApp template manager last, because it is the only phase that needs a
migration and the only one whose core value depends on a webhook route that does not exist.**

| # | Phase | Shippable alone? | Needs migration? | Rough size (est.) |
|---|---|---|---|---|
| **P0** | Defect pre-phase — eight items | yes, item by item | no | 4–6 days |
| **1** | Audience and campaign entry path | yes | no | 8–12 days |
| **2** | Starter library v1 (recipe-contract EXTEND + macro catalogue) | yes | no | 10–15 days |
| **3** | Documentation Center and brand-owned links | yes | no | 12–18 days |
| **4** | WhatsApp template read-side truth | yes | no | 4–6 days |
| **5** | WhatsApp template manager (per-template record + starter templates + narrow edit) | yes | **yes — approval gate** | 15–25 days |
| **6** | Push template status (app-default webhook) | yes | no | 8–12 days |

### Why this departs from the deliverable ordering

The eleven preceding documents in this directory run starter library (`01`) → commerce (`03`) → WhatsApp (`04`,`05`)
→ audience/contacts UX (`06`) → branding (`07`) → documentation (`08`,`09`,`10`) → permissions (`11`). Read as a build
sequence that puts the headline first and branding and UX late. Discovery inverts it for three reasons, each citable:

1. **Branding is not cosmetic here, it is a reverting defect.** `Internal::ReconcilePlanConfigService` overwrites the
   live branding rows back to Chatwoot values whenever `ChatwootHub.pricing_plan == 'community'` — the seeded default
   (`enterprise/app/services/internal/reconcile_plan_config_service.rb:4,38-46`;
   `config/installation_config.yml:331-332`) **(R)**. Any brand-facing work shipped before that fix is on a timer.
2. **Part of the starter library is already blocked by the audience UX.** `automationRecipes.js:142` and
   `flowTemplates.js:281` declare `requires: [REQUIREMENTS.SHARED_AUDIENCE, …]`, and `useRecipeContext.js:51` marks
   them unavailable while `context.audiences.length === 0` **(R)**. The only way to create a shared audience today is
   to apply a contact filter and press an icon-only button, and doing it from a campaign destroys the campaign draft
   (`WhatsAppCampaignForm.vue:46-50,133-136`; `Dashboard.vue:156` renders the campaigns subtree with no `keep-alive`).
   Shipping more audience-gated recipes onto a dead-end creation path multiplies a known failure.
3. **The WhatsApp manager cannot be first because its read side is wrong.** The Graph `v14.0` pin
   (`app/services/whatsapp/providers/whatsapp_cloud_service.rb:124-126`; `app/services/whatsapp/csat_template_service.rb:4`)
   **(R)** is past Meta's support window (v14.0 expired 2024-09-17 **(V)**), and a submitted draft is unusable without
   status truth, which is `04 §4.1`'s missing app-default callback route. Phase 5 before Phase 4 ships a surface that
   lies.

---

## 2. PRE-PHASE P0 — defects found during discovery

These are not improvements. Each is live at this HEAD, each has a user-visible or data-visible consequence, and none
needs a migration. **Do these before any new feature.**

| # | Defect | Nature | Evidence | Fix size (est.) |
|---|---|---|---|---|
| **D1** | **The EE reconcile job reverts all branding to Chatwoot daily on a community install** | Live defect — configuration overwrite, silent | chain re-traced **(R)**: `lib/chatwoot_app.rb:14-18,40-48` → `config/initializers/01_inject_enterprise_edition_module.rb:70-80` → `app/jobs/internal/check_new_versions_job.rb:20` → `enterprise/app/jobs/enterprise/internal/check_new_versions_job.rb:27-29` calls `reconcile_premium_config_and_features` **unconditionally** → `enterprise/app/services/internal/reconcile_plan_config_service.rb:4` passes because `ChatwootHub.pricing_plan` reads `INSTALLATION_PRICING_PLAN`, seeded `'community'` (`lib/chatwoot_hub.rb:39-43`, `config/installation_config.yml:331-332`) → `:38-46` `update!`s every key in `enterprise/config/premium_installation_config.yml:1-22`, which still holds `INSTALLATION_NAME: 'Chatwoot'`, `BRAND_NAME: 'Chatwoot'` and `chatwoot.com` URLs | **0.5 day** |
| **D2** | **The Vuex export action drops `q` and `active`, so exporting from a search exports the whole account** | Live defect — **data exposure**, in just-shipped work whose commit claimed it fixed this **(V)** | `app/javascript/dashboard/store/modules/contacts/actions.js:202` destructures only `{ payload, label }` and forwards only those at `:205` **(R)**. The caller passes the full view (`ContactListHeaderWrapper.vue:134`) and the controller already honours all four — its own comment at `app/controllers/api/v1/accounts/contacts_controller.rb:51-52` names this exact bug: *"dropping `q` and `active` here is what made exporting from a search export the whole account"* **(R)** | **0.5 day** |
| **D3** | **Graph API `v14.0` hardcoded for WhatsApp template sync** | Live defect — third-party deprecation, will take sync offline | `app/services/whatsapp/providers/whatsapp_cloud_service.rb:124-126` (`business_account_path`, `v14.0`) and `:120-122` (`phone_id_path`, `v13.0`); `app/services/whatsapp/csat_template_service.rb:4` (`WHATSAPP_API_VERSION = 'v14.0'`) **(R)**. Meta's version table: v13.0 expired 2024-05-28, v14.0 expired 2024-09-17 **(V)**. The pattern to copy already exists one file away — `app/services/whatsapp/facebook_api_client.rb:8` reads a configurable `v22.0` | **1 day** |
| **D4** | **CSAT delete-then-recreate destroys a live approved template** | Live defect, but **not** a 30-day-block collision — that claim is withdrawn (see `00` §6.1). Deleting an approved template and submitting a fresh one takes CSAT **offline until Meta re-approves** | `app/services/csat_template_management_service.rb:28` calls `delete_existing_template_if_needed` before every create; `:181-197` fetches status then `DELETE …?name=` via `app/services/whatsapp/csat_template_service.rb:21-28` **(R)**. Meta: *"If you delete an approved template, you cannot create a new template with the same name for 30 days"* **(V)**. Meta's 30-day same-name block is avoided **by design**: `app/services/csat_template_name_service.rb:19-25` mints `…_<n+1>` rather than reusing the name **(R)**. That versioning is load-bearing — do not remove it. The defect is the destructive delete itself, not the naming. P0 scope: **stop deleting the approved template**; the proper replacement (a `components` edit) is Phase 5 | **1 day** (P0 part) |
| **D5** | **`TemplateNormalizer` reads body example keys for TEXT headers, so header variable examples are mis-read** | Live defect — broader than first reported **(V)** | `app/javascript/dashboard/services/TemplateNormalizer.js:67-85` applies the lookup to **every** component carrying `.text`: named branch reads `example.body_text_named_params` (`:75`), positional reads `example.body_text[0][position]` (`:81`) **(R)**. Meta's TEXT header uses `header_text_named_params` / flat `header_text: ["…"]` **(V)**. The BODY positional read is correct — Meta's shape is nested — so do not "fix" `:81` for body | **0.5 day** |
| **D6** | **Search `meta.count` is the page size, so "Select all N in this view" is unreachable on a search view** | Live defect — the Phase D bulk feature is silently off on the one view users search from | `app/controllers/api/v1/accounts/contacts_controller.rb:183` sets `@contacts_count = results.size` after `results.first(RESULTS_PER_PAGE)` (max 15) **(R)**, so `totalItems <= 15` and `ContactsBulkActionBar`'s `canSelectAllMatching` (`totalCount > visible`, `:66-74`) can never be true | **0.5 day** |
| **D7** | **`sla_policy_id` is a dead condition key that silently auto-disables a rule** | Live defect — accepted on write, unmatchable at run time **(V)** | `enterprise/app/models/enterprise/automation_rule.rb:2-4` adds it to `conditions_attributes` **(R)**; it has no `lib/filters/filter_keys.yml` entry, no `ConditionsFilterService` branch and no UI, so it falls through `app/services/automation_rules/condition_validation_service.rb:36-47` to `custom_attribute_present?` (`:58-64`) and returns false. The rule never matches and is auto-disabled after two evaluations. Either implement it or remove the key | **0.5 day** |
| **D8** | **`event_name` has no inclusion validation, so a typo'd trigger saves and never fires** | Live defect — and the single most dangerous failure mode for a starter catalogue **(V)** | `app/models/automation_rule.rb:34-41` is the complete validation list — no inclusion on `event_name` **(R)**; the only constraint is `db/schema.rb:313` `null: false`; `app/controllers/api/v1/accounts/automation_rules_controller.rb:62` permits it as a free string. An `AutomationRule` with `event_name: 'commerce_cart_abandoned'` persists successfully and is an invisible no-op | **0.5 day** |

**Ordering inside P0.** D1 first (smallest, highest leverage, and it gates every brand-facing decision). D2 and D6
next — they are one-line and two-line fixes to just-shipped work. D8 before Phase 2 is a hard prerequisite. D3, D4, D5
before Phase 4.

**Two things a reviewer must know before touching D1.**
`spec/enterprise/services/internal/reconcile_plan_config_service_spec.rb:44-45` asserts `INSTALLATION_NAME` resets to `Chatwoot` and `LOGO` resets to
`/brand-assets/logo.svg` — the spec encodes the reset as intended behaviour, so aligning
`enterprise/config/premium_installation_config.yml` to the Lynomia values keeps that spec meaningful while excluding the
keys from the service invalidates it. Prefer the yml. And `enterprise/LICENSE:1-34` binds use of the `enterprise/`
overlay to Chatwoot subscription terms while `ChatwootApp.enterprise?` is true merely because the directory exists
(`lib/chatwoot_app.rb:14-18`) — **whether to fix the reset or disable the overlay is a licensing decision before it is
an engineering one (LEGAL_REVIEW, per `07 §11.1`).**

**One honest limit on D1.** Whether the daily path fires on a given deployment depends on `ChatwootHub.sync_with_hub`
reaching `hub.2.chatwoot.com`, the stored `INSTALLATION_PRICING_PLAN`, and Sidekiq-cron running. The code path and the
defaults are verified statically; the live execution is **UNVERIFIED**. The on-demand Super Admin path needs none of
those.

---

## 3. Phase 1 — Audience and campaign entry path

**Goal.** Make a Shared Audience creatable, shareable and discoverable without losing work, and stop the campaign
recipients empty state from being a dead end. Zero new persistence.

| | |
|---|---|
| **Reuses** | The `?audience=` / `?label=` query-param bridge (`app/javascript/dashboard/helper/audienceHelper.js:7,11,13-20,27-35`), already proven in the audience→campaign direction; `CreateSegmentDialog` + `customViews/create` + the admin `shared` checkbox (`CreateSegmentDialog.vue:39-47,98-116`); `ADD_CUSTOM_VIEW` pushing the new record into the store so it appears in the picker without a reload (`customViews.js:118-123`); `initialSharedAudienceIds` → `state.selectedSharedAudiences` (`WhatsAppCampaignsPage.vue:71`, `WhatsAppCampaignForm.vue:48-49`); the shared `CampaignRecipients` picker already rendered by `SMSCampaignForm.vue:147-150`; `Contacts::ViewScope` and the 10,000-bounded bulk path, which **already ship** (`app/controllers/api/v1/accounts/bulk_actions_controller.rb:10,51-75,107-114`) |
| **Extends** | The bridge, with a return target, so Campaign → Contacts → save → back preselects the new audience; the same bridge for SMS (the server already accepts `Audience` entries on any one-off campaign — `custom/app/models/custom/campaign_audience.rb:26` checks only `one_off?`); `shared` on the audience **edit** panel (the API already permits it on update, `custom/app/controllers/custom/api/v1/accounts/custom_filters_controller.rb:38`, and handles the shared→false transition with an in-use guard at `:14`; the UI simply never sends it); `Audience::Usage` to count flow-graph references (`custom/app/services/audience/usage.rb:8-22` queries only `automation_rules` and `campaigns.one_off` **(R)**, while `custom/app/services/flows/node_validator.rb:91` makes `contact_audience` a first-class flow condition) |
| **Creates** | No new persisted object types. An Audiences **list route and page** (there is none today — `contacts/routes.js:11-41` has four routes, all rendering `ContactsIndex.vue`; the only enumeration is a sidebar group at `Sidebar.vue:547-568`). A **client-side** campaign-draft store, scoped to the one-off campaign form, cleared on successful create and on explicit cancel |
| **Prerequisites** | None. D2 and D6 should ride along because they are in the same files and the same user journey |
| **Risks** | A client-side draft is per-browser and lost on sign-out — acceptable for this journey, and the alternative needs schema approval (§11, M5). Un-sharing an audience that a published flow references currently deletes without warning and the runtime takes the silent `false` branch (`custom/app/services/automation/lynomia_condition.rb:108-114` raises `InvalidValue`, which `app/services/automation_rules/conditions_filter_service.rb:40-44` swallows) — the `Audience::Usage` extension is what closes that, and it must land in this phase, not after it |
| **Explicitly does NOT** | add static audience membership; add an "add selected contacts to an audience" action; add an `id` contact filter key; persist a campaign draft server-side; touch `Contacts::FilterService`'s multi-value collapse (reported, deferred — see §10) |
| **Size (est.)** | **8–12 days** |

---

## 4. Phase 2 — Starter library v1

**Goal.** Ship the catalogue that is the program's headline, restricted to what the engines can actually honour, and
add the one agent-reachable gallery the product does not have.

| | |
|---|---|
| **Reuses** | Every engine, unchanged. Automation rules: 12 triggers, **20** actions **(V)** (19 at `app/models/automation_rule.rb:54-59` plus `add_sla` from `enterprise/app/models/enterprise/automation_rule.rb:6-8`), 18 OSS + 12 Lynomia condition keys. Flow Builder: 21 node types (`custom/app/services/flows/node_types.rb:9-34`), publish/draft, Test Mode. Macros: 16 server-valid actions (`app/models/macro.rb:33-35`). All three already share one action vocabulary — `app/services/action_service.rb:9-96` is the base of both `AutomationRules::ActionService` and `Macros::ExecutionService` and is instantiated directly by the flow handoff node (`custom/app/services/flows/nodes/handoff.rb:7,15-19`). `RecipeDialog.vue` and `useRecipeContext.js` as the gallery mechanics. Zero new authorization — the gallery inherits the host page's route meta (`11 §12.4b`) |
| **Extends** | The recipe **contract**, and only that: a `macro` type plus a macros-page mount (`app/javascript/dashboard/recipes/index.js:13` `type` is a scalar, `:19-20` `build` returns one payload, `RecipeDialog.vue:101` emits one `create`); a `macros` entry in `REQUIREMENTS` (`index.js:34-45`) and in `useRecipeContext`'s `satisfied` map; input types the vocabulary lacks — inbox, agent, free text, boolean (`INPUT_TYPES`, `index.js:48-60`). Note `INPUT_TYPES.LABEL` is declared at `:49`, used by no recipe, and has no branch in `RecipeInputs.vue` — an unrecognised type falls through to a `type="url"` text field at `:127-135`, so the catch-all must be closed or every future type fails silently |
| **Creates** | `AutomationRule` rows (`active: false`, as today), `AgentBot(bot_type: :flow)` + a draft `FlowVersion` (as today — `flows/Index.vue:125-144`), and `Macro` rows. **No new tables, no new endpoints, no server-side catalogue.** The macro route needs no new policy: `MacroPolicy#create?` is already true for any agent, which is what makes this the first gallery an agent can reach |
| **Prerequisites** | **D8 is blocking.** A catalogue whose entries carry an unvalidated `event_name` can ship a rule that saves and never fires. **D7** should land first too, so the catalogue can never emit the dead key |
| **Risks** | **No provenance.** The only link from a created object back to its recipe is interpolated, user-editable prose in `description` (`flows/Index.vue:130-133`, `automation/Index.vue:209-212`); audiences get none at all. Nothing reads it back, so "which objects came from a starter" is unanswerable and `version` has no upgrade path. **No telemetry** — `useTrack` is inert without `CLOUD_ANALYTICS_TOKEN`, which ships blank (`config/installation_config.yml:299`), so every call site is a no-op. **Locale coverage is `en` and `ar` only** (2 of 57 locale directories ship a `recipes.json`), and the flow templates' bot copy is literal text in `starterCopy.js:34-171`, not i18n — a third locale needs a new copy branch, not a new JSON file |
| **Explicitly does NOT** | build multi-object kits (`NEW PRIMITIVE REQUIRED`, not needed for v1); build commerce-event recipes beyond the webhook bridge and WooCommerce/Shopify `paid`/`refunded` (`03 §1`); build out-of-hours recipes (no time-of-day condition exists anywhere); build contact-lifecycle recipes; build abandoned-cart recipes; build WhatsApp-template starters (gated on Phase 5); add a cross-type recipes gallery route; add per-account saved recipes; add provenance columns (that is a migration — §11, M4) |
| **Size (est.)** | **10–15 days** |

---

## 5. Phase 3 — Documentation Center and brand-owned links

**Goal.** First-party Lynomia product documentation served at `/hc/<slug>` from a portal owned by one internal
account, manageable from Super Admin, with a change trail — and the in-product "Learn more" links pointed at it.

| | |
|---|---|
| **Reuses** | Portal → Category → Article as-is. The public reader is **already globally scoped**: `Portal.find_by!(slug:, archived: false)` with no account id in any `/hc` route (`app/controllers/public/api/v1/portals_controller.rb:26`; `config/routes.rb:649-660`). The host guard does **not** block a branded install — `DomainHelper.chatwoot_domain?` compares `request.host` against the hosts of `ENV['FRONTEND_URL']` / `ENV['HELPCENTER_URL']`, not against any Chatwoot domain (`app/controllers/concerns/domain_helper.rb:2-4`) **(V)**. The account feature gate is cloud-only (`app/controllers/public_controller.rb:22-27`). The Administrate pattern, with a working proof in the `custom/` tree (`custom/app/dashboards/billing_plan_dashboard.rb` + `custom/app/controllers/super_admin/billing_plans_controller.rb` + `config/routes/billing.rb:4-19`, drawn at `config/routes.rb:782` **(V)**). The polymorphic `audits` table, which already exists with `auditable_type/auditable_id/version/audited_changes` (`db/schema.rb:264-288`) **(V)**. `articles.meta` jsonb for release dates and tags, so the changelog needs no table (`10 §4`) |
| **Extends** | Super Admin: routes under `namespace :super_admin` + `Administrate::BaseDashboard` subclasses + `sidebar_icons` entries for Portal/Category/Article (the sidebar auto-derives from `Administrate::Namespace`, `app/views/super_admin/application/_navigation.html.erb:36-37`). `audited` on `Article` with a column allow-list — **a model change, no migration (V)**. `Article` strong params for the `meta` keys the changelog needs. `Article.search` to filter on tags (it scopes only category_slug, locale, author, status — `app/models/article.rb:105-114`). The contextual-help link table: 28 `chwt.app` URLs in one hard-coded JS table (`app/javascript/dashboard/helper/featureHelper.js:2-28`) plus 14 in `config/features.yml`, re-pointed through a new `InstallationConfig` row (a row in an existing table, no schema change) |
| **Creates** | One `Portal` in an internal Lynomia account, its `Category` rows and `Article` rows; `audits` rows. No new tables |
| **Prerequisites** | **`Portal::RESERVED_SLUGS` + an exclusion validation, mirroring `app/models/article.rb:61,67` — blocking.** Portal slugs are a single global, first-come-first-served namespace: `app/models/portal.rb:44` is a bare `validates :slug, presence: true, uniqueness: true` and there is no `Portal` reserved list **(V)**. Worse, tenant onboarding actively claims global slugs — `Onboarding::HelpCenterCreationService#slug_candidates` tries `<account-name>`, `<first-token>`, `<first-token>-docs`, `<first-token>-help` against a global `Portal.exists?(slug:)` (`enterprise/app/services/onboarding/help_center_creation_service.rb:114-124`) **(V)**. Also: `FRONTEND_URL` / `HELPCENTER_URL` must be set to the serving host, or every guarded portal page 401s with a hardcoded `support@chatwoot.com` message (`app/controllers/public_controller.rb:9-20`) **(V)**. Also: fix `@portal.update(archive: true)` against the column `archived` (`app/controllers/api/v1/accounts/portals_controller.rb:44` vs `db/schema.rb:1551`) before Super Admin exposes archiving |
| **Risks** | The portal is account-scoped, so **whoever owns the internal account can edit the global docs** — Super Admin is outside Pundit and outside tenancy (`app/controllers/super_admin/application_controller.rb:14`), so the reader gate has to be decided, not copied (§11, R1). Two public endpoints have no custom-domain guard and serve on any host that reaches the app: `portals#sitemap` and `articles#tracking_pixel` **(V)**. Six enterprise Help Center services were omitted from the first inventory and are wired end to end — they are the actual portal creator and must be read before changing portal creation (`enterprise/app/services/onboarding/{help_center_creation_service,help_center_curator,help_center_errors,help_center_generation_state}.rb`, `enterprise/app/services/captain/llm/{help_center_curation_service,help_center_curation_schema}.rb`) **(V)** |
| **Explicitly does NOT** | create an accountless "global portal" (needs a migration across three tables and buys nothing the slug path does not — `09 §1`); create a `release_notes` or `changelog` table (reuse `Article` + `meta` — `10 §1`); build a second CMS; add article scheduling, expiry, or review-and-approve states; add per-portal membership; mass-rename internal `chatwoot`/`woot` identifiers (3,802 `woot`-derived identifiers **(V)** — `07 §10`) |
| **Size (est.)** | **12–18 days** |

**Branding work that belongs here, not in P0.** D1 stops the reversion; the remaining branding items are real but not
defects: three new `InstallationConfig` rows (docs/help base URL, mailer sender identity, MFA/TOTP issuer — rows in an
existing table); `BRAND_URL` reaches `window.globalConfig` (`app/controllers/dashboard_controller.rb:12`) but is never
destructured in `app/javascript/shared/store/globalConfig.js:4-30`, so no SPA code can read it **(V)**; the two LLM
system prompts open *"an AI writing assistant integrated into Chatwoot"* and leak the brand to the model provider on
every AI-assist rewrite (`lib/integrations/openai/openai_prompts/tone_rewrite.liquid:1`,
`fix_spelling_grammar.liquid:1`) **(V)**; and the inverse problem the first pass missed entirely — **34 hard-coded
`Lynomia` literals in EN source strings** (`commerce.json` 28, `automation.json:246,258`, `contactFilters.json:82`,
`config/locales/en.yml:613-619`), plus `config/features.yml:283,287`,
`app/helpers/super_admin/features.yml:155,161,167,172`, plus 17 description lines in
`config/installation_config.yml:487-612` — none of which read `INSTALLATION_NAME`, and none of which
`replaceInstallationName` can ever touch because its regex is `/chatwoot/gi` **(V)**. The brand is hard-coded in both
directions; a future rename leaves a mixed-brand UI either way.

---

## 6. Phase 4 — WhatsApp template read-side truth

**Goal.** Make the template inventory tell the truth, with no new persistence and no new Meta write capability. Worth
doing whether or not Phase 5 is ever approved.

| | |
|---|---|
| **Reuses** | The 3-hourly sync and `channel_whatsapp.message_templates` jsonb as the Meta mirror and the only source the send path reads; the existing Settings → Templates page, which already fans the read across inboxes, dedupes, filters and previews; the existing credential and error-parsing path |
| **Extends** | Surface `rejected_reason`, which is **already in the column** and read by nothing (no production reader; the only occurrences are fixtures and `spec/factories/channel/channel_whatsapp.rb:15,24,33,84`) **(V)**. Badge coverage for the statuses the tone map omits — `IN_APPEAL`, `ARCHIVED`, `PENDING_DELETION`, `DELETED`, `LIMIT_EXCEEDED` (`templateUtils.js:121-131` handles only approved/pending/rejected/paused/disabled). Show observation age beside status. Add a single-template "Check status now" via `GET /{TEMPLATE_ID}`, which Meta supports and the repo never calls |
| **Creates** | Nothing persisted |
| **Prerequisites** | D3 and D5 |
| **Risks** | Low. The one trap: do not build a remaining-edit-budget counter — Lynomia cannot see edits made in WhatsApp Manager, so any counter is wrong in exactly the situation where it matters (`05 §9`) |
| **Explicitly does NOT** | add create, edit or delete; add quality surfacing (`quality_score` appears **nowhere** in the repo — the inventory's citation for it was **fabricated (V)**; the only quality data the product reads is per phone number, `app/services/whatsapp/health_service.rb:39,151,226`); mirror Meta's pacing or archival as actionable UI (Meta offers no verb for either) |
| **Size (est.)** | **4–6 days** |

---

## 7. Phase 5 — WhatsApp template manager

**Goal.** A draft-and-submit surface: Lynomia owns drafts, provenance and retained rejection reasons; Meta's synced
array stays the single source of truth for what may be sent.

| | |
|---|---|
| **Reuses** | `Channel::Whatsapp`, `provider_config`, `template_access_token`; the entire send chain (`SendOnWhatsappService` → `TemplateProcessorService` → `PopulateTemplateParametersService` → `provider.send_template`) untouched; Campaigns, the Flow `send_template` node and the composer as consumers only; the recipe gallery mechanics for the starter catalogue |
| **Extends** | A generic `POST /{WABA}/message_templates` submit service beside `Whatsapp::CsatTemplateService`, same credential path; `GET /{TEMPLATE_ID}` as the manual-refresh primitive; `POST /{TEMPLATE_ID}` for a narrow, conditional edit — **CSAT first**, replacing D4's delete-then-recreate with a `components` edit; generic `DELETE` only behind an explicit 30-day warning |
| **Creates** | **A per-template Lynomia record — the one new primitive in the whole program, and it needs a migration (§11, M1).** Plus a `whatsapp_template` recipe type and its starter catalogue |
| **Prerequisites** | **Migration approved.** Phase 4 shipped — a submitted draft is unusable without status truth. D3, D4, D5 landed |
| **Risks** | This is the first phase that creates state the product must then maintain. Meta's edit rules are hard: only `APPROVED`/`REJECTED`/`PAUSED` are editable; approved templates get 1 edit per 24 h and 10 per 30 days; components are replaced **wholesale**, never individually; the category of an approved template cannot be edited; the editable set is **category, components and time-to-live only** — the wider six-item list in the first pass came from the node reference, not Meta's normative page, and building on it ships calls Meta's own guidance says are not editable **(V)**. `InboxPolicy#message_templates?` returns a plain `true` (`app/policies/inbox_policy.rb:37-39`), which must be re-gated if this record becomes the system of record (§11, R4) |
| **Explicitly does NOT** | build a template authoring IDE; add a second WhatsApp provider or template-gateway layer; offer category review or appeal (WhatsApp Manager only **(V)**); build template versioning against Meta (Meta exposes no version, duplicate or clone operation **(V)**); use Meta's Template Library create; add per-template analytics; add `currency`/`date_time` or cart-derived template variables |
| **Size (est.)** | **15–25 days** |

**The one architectural property to hold.** A Lynomia draft must never enter `channel_whatsapp.message_templates`.
Every send-side consumer reads that column, so keeping drafts out of it makes "a draft can never be sent" a structural
fact rather than a UI rule (`05 §1`).

---

## 8. Phase 6 — Push template status

**Goal.** Replace up to three hours of staleness on a value that gates sending.

**Reuses** the existing webhook verification and dispatcher conventions. **Extends** nothing — this is a
**NEW PRIMITIVE REQUIRED**: an app-default `whatsapp_business_account` callback route, signature verification, a
dispatcher branch, then the field subscription. **Prerequisites:** Phase 5, because tenant resolution needs the
per-template record. **Risk:** the only Meta webhook route today is per-phone-number (`config/routes.rb:678-679`) and
`WEBHOOK_DEFAULT_FIELDS = %w[messages smb_message_echoes]` (`app/services/whatsapp/facebook_api_client.rb:4`), and
Meta states verbatim that the four template fields *"do not support callback overrides"* **(V)** — so a per-phone route
can never receive them. **Does NOT** add quality surfacing as a separate workstream; `message_template_quality_update`
rides the same subscription. **Size (est.) 8–12 days.**

---

## 9. Summary table — features needing NO backend work

| Feature | Where it lives | Phase | Class |
|---|---|---|---|
| Audiences list page | new route + page over `customViews` store | 1 | NEW PRIMITIVE REQUIRED (UI only) |
| Campaign draft survives leaving the page | client-side store, one-off campaign form | 1 | NEW PRIMITIVE REQUIRED (client-side) |
| Explain-in-place instead of inside the combobox (`ComboBoxDropdown.vue:120-122` renders `emptyState` as a bare `<li>` with no slot) | `CampaignRecipients` section | 1 | PATCH |
| `isFetching` guard so "No shared audiences yet" is not shown while loading | shared-audience picker | 1 | PATCH |
| Visible label on the icon-only save-as-audience button | contacts header | 1 | PATCH |
| Share / un-share from the audience edit panel (API already permits it) | `ContactsFilter.vue` + `ContactListHeaderWrapper.vue:282-291` | 1 | PATCH |
| `?audience=` bridge return target, and the same bridge for SMS | `audienceHelper.js`, `SMSCampaignsPage.vue` | 1 | EXTEND (frontend) |
| Contacts export forwarding `q`/`active` | `contacts/actions.js:202-205` | P0 | PATCH |
| First-selection row-checkbox affordance | contacts list rows | 1 | PATCH |
| Starter catalogue entries for automation and flow | `app/javascript/dashboard/recipes/*` | 2 | REUSE |
| Recipe contract: `macro` type, new input types, closing the `RecipeInputs.vue:127-135` catch-all | `recipes/index.js`, `RecipeInputs.vue` | 2 | EXTEND (frontend) |
| `change_status` added to `AUTOMATION_ACTION_TYPES` (today an API-created rule using it throws in the edit panel) | `automation/constants.js` | 2 | PATCH |
| Removing the dead per-event `actions:` arrays (`constants.js:90,232,378,518,648` — never read **(V)**) | `automation/constants.js` | 2 | PATCH |
| Empty state on the automation `Contact audience` condition | `ConditionRow.vue` | 1 | PATCH |
| Flow inbox pickers filtering on `provider == 'whatsapp_cloud'` | `BotConfiguration.vue:98`, `FlowBuilder.vue:102-107` | 2 | PATCH |
| `rejected_reason` + missing status badges + observation age | `TemplatePreviewDrawer.vue`, `templateUtils.js:121-131` | 4 | PATCH |
| TEXT-header example reading | `TemplateNormalizer.js:67-85` | P0 | PATCH |
| Hard-coded `Lynomia` literals and half-covered `replaceInstallationName` call sites (e.g. `UpdateBanner.vue:32` unwrapped while `BuildInfo.vue:42` is wrapped **(V)**) | i18n + Vue | 3 | PATCH |

---

## 10. Summary table — features needing backend extension

| Feature | Backend change | Phase | Class |
|---|---|---|---|
| `event_name` inclusion validation | one validation on `app/models/automation_rule.rb` | P0 | PATCH |
| `sla_policy_id` removed (or implemented) | `enterprise/app/models/enterprise/automation_rule.rb:2-4` | P0 | PATCH |
| Branding stops reverting | align `enterprise/config/premium_installation_config.yml:1-22` | P0 | PATCH |
| Graph API version from config | reuse the `WHATSAPP_API_VERSION` pattern at `facebook_api_client.rb:8` | P0 | PATCH |
| CSAT stops deleting an approved template | `csat_template_management_service.rb:28,181-197` | P0 / 5 | PATCH → EXTEND |
| Search `@contacts_count` | `contacts_controller.rb:183` | P0 | PATCH |
| `Audience::Usage` counts flow-graph references | `custom/app/services/audience/usage.rb:8-22` + a `flow_versions.graph` query | 1 | PATCH |
| Three new `InstallationConfig` rows (docs URL, mailer sender, MFA issuer) | rows in an existing table — **no schema change** | 3 | EXTEND |
| `Portal::RESERVED_SLUGS` + exclusion validation | `app/models/portal.rb` | 3 | NEW PRIMITIVE REQUIRED (code-only) |
| `audited` on `Article` with a column allow-list | model change only — the `audits` table exists (`db/schema.rb:264-288`) **(V)** | 3 | EXTEND |
| Super Admin Portal/Category/Article | routes + 3 Administrate dashboards + sidebar icons | 3 | EXTEND |
| Article `meta` strong params + a tag-filterable `Article.search` scope | `articles_controller.rb`, `app/models/article.rb:105-114` | 3 | EXTEND |
| Portal archive bug | `portals_controller.rb:44` (`archive` vs `archived`) | 3 | PATCH |
| `GET /{TEMPLATE_ID}` single-template status | new call on the existing client | 4 | EXTEND |
| Generic `POST /{WABA}/message_templates` submit | new service beside `Whatsapp::CsatTemplateService` | 5 | EXTEND |
| `POST /{TEMPLATE_ID}` narrow edit | new call, four conditionality rules | 5 | EXTEND |
| `InboxPolicy#message_templates?` re-gated | `app/policies/inbox_policy.rb:37-39` | 5 | PATCH |
| App-default `whatsapp_business_account` callback route | new route + verification + dispatcher branch | 6 | NEW PRIMITIVE REQUIRED |

**Reported and deliberately deferred:** the contact-filter multi-value collapse. `app/services/contacts/filter_service.rb:22`
takes `query_hash['values'][0]` and `:45-49` overrides the base `IN (:value_N)` with `= :value_N`, while the UI builds
and sends arrays and `labels` is a `multiSelect` — so picking labels `vip` and `gold` in a contact filter matches only
`vip`, with no warning and no spec coverage **(V)**. This is upstream behaviour with no `custom/`or `enterprise/`
override. It is a correctness bug that affects audience membership, so it needs its own decision; it is not in any
phase above because fixing it changes the meaning of every stored contact filter in every account.

---

## 11. Summary table — features explicitly NOT to build

| Feature | Class | Reason |
|---|---|---|
| **Abandoned-cart automation** | DO NOT CREATE | Verified twice, independently **(V)**. Zero `cart` lines in `db/schema.rb`; a cart is a `Data.define` (`custom/app/services/commerce/abandoned_cart.rb:12-15`) cached in Redis only (FRESH 120 s / KEEP 24 h, `cache.rb:8-9`); the cache is **deleted, not staled**, on every order and cart webhook (`realtime.rb:33,47,54-57`), so no durable prior state exists to diff. No provider-neutral abandonment transition, no trigger (a repo-wide grep for `commerce_cart_abandoned` returns zero), no condition. And carts are production-unreachable for all four providers anyway: `PRE_UAT` holds salla/zid/shopify for `recovery` and WooCommerce has no `RECOVERY_KEYS` entry (`switches.rb:15-16`) |
| **Static audience membership** | DO NOT CREATE | 108 tables checked; no `audiences`, `audience_members`, `audience_contacts` or `segments` table **(V)**. `campaigns.audience` is a jsonb list of `{type,id}` **references** (`db/schema.rb:442`); membership is re-resolved at send time via `CampaignAudience#audience_contacts → audiences.map(&:members)`; `campaign_recipients` is a send **log** created during the send, not a membership list. There is nowhere to write a static set. `id in (a set)` is not expressible either — `id` is not among the eleven contact filter keys (`lib/filters/filter_keys.yml:130-208`), an unknown key raises `InvalidAttribute`, and `custom_filters.query` is **unvalidated on write**, so the bad filter would persist and explode later at campaign send time **(V)**. Use a **label**: real `taggings` rows, a shipped additive bulk write, and campaigns already accept `{type:'Label', id}` |
| **A second macro runtime** | DO NOT CREATE | There is exactly one — `Macros::ExecutionService` with an Enterprise mixin for required-attribute gating — and it already shares `ActionService` with automation and the flow handoff node. A second engine would duplicate the action vocabulary with no new capability. The macro gap is the **catalogue** (Phase 2), not the runtime |
| **DocumentationCMSV2** | DO NOT CREATE | The existing Help Center carries this as an EXTEND with **no migration**: the public reader is already globally scoped, the host guard does not block a branded install **(V)**, Super Admin is additive via Administrate with a working `custom/` precedent, and revision history is `audited` on a model against an `audits` table that already exists **(V)**. A second CMS buys nothing and forks the reader path |
| **Another WhatsApp provider layer** | DO NOT CREATE | `PROVIDERS = %w[default whatsapp_cloud]` (`app/models/channel/whatsapp.rb:36`), and one of the two (360dialog) has no add-inbox entry point at all. `provider_service` delegation (`:146-150`) **is** the extension point. A layer above it adds indirection and no capability |
| **Contact-lifecycle triggers** (`contact_created` / `contact_updated` / entered-or-left-an-audience) | DO NOT CREATE **in this program** | Not because the trigger is hard — the events are already dispatched for other listeners — but because the **entire action vocabulary acts on `@conversation`**. There is no `add_contact_label`, no `set_contact_attribute`, no contact-scoped action of any kind; today only a flow can write a contact attribute. Shipping the trigger alone produces rules that fire and can do nothing. Requirement for a later program: triggers **plus** at least two contact-scoped actions, decided together |
| Accountless "global portal" | DO NOT CREATE | Needs `NOT NULL` dropped on three columns, three presence validations relaxed, two `ensure_account_id` callbacks reworked and six `Current.account.portals` lookups reworked — a migration, to buy what `/hc/<slug>` already gives **(V)** |
| A `release_notes` / `changelog` table | DO NOT CREATE | `Article` + `meta['release_date']` + tags carries every field the product needs, with no migration (`10 §4`) |
| Customer-facing messages on a commerce trigger | DO NOT CREATE | Two independent blocks: `send_message`/`send_attachment` are banned on every commerce trigger server-side (`custom/app/models/custom/automation_rule.rb:9,38-39`) and client-side (`lynomiaAutomation.js:24,173-174`), **and** the trigger is read-driven, so the notification would arrive whenever an agent opens the panel **(V)** |
| Commerce write actions from a rule or flow | DO NOT CREATE | Agent-confirmed by design, admin-only policy, and `PRE_UAT` holds salla/zid/shopify `actions` hard-off |
| Cross-provider `shipped` / `delivered` recipes | DO NOT CREATE | WooCommerce can never reach either status (`woocommerce/normalizer.rb:17-20,35`) and Shopify's `delivered` is derived and webhook-less |
| Out-of-hours recipes | DO NOT CREATE | No time-of-day or business-hours condition exists anywhere in the rule engine. Reuse the per-inbox setting |
| A "Conversation Workflow" engine | DO NOT CREATE | `grep -ci workflow db/schema.rb` is **0**. The name is a frontend route and a sidebar label over two unrelated toggles. Map every workflow ask onto Automation / Macro / Flow |
| Template versioning, category review, Template Library create, per-template analytics | DO NOT CREATE | Meta exposes no version/duplicate/clone operation **(V)**; review is WhatsApp Manager only **(V)**; the starter gallery delivers the Library's product outcome in Lynomia's own copy under our version control |
| A telemetry platform to answer "starter selected / completed / abandoned" | DO NOT CREATE **in this program** | It genuinely cannot be answered today — `useTrack` is inert without `CLOUD_ANALYTICS_TOKEN`, which ships blank and is typed `secret`, and there are **zero** tracking calls on any recipe path. Instrument the gallery when it ships; do not build the pipeline, which is an installation-level decision |

---

## 12. Required migrations — stated, not designed, for approval

| Ref | Requirement | Why current persistence cannot support it | Blocks |
|---|---|---|---|
| **M1** | **A sparse per-template Lynomia record**, joined to Meta's data on `(name, language)`, carrying draft state, provenance, `submitted_at` and a retained rejection reason | Templates live in **one jsonb column**, `channel_whatsapp.message_templates` (`db/schema.rb:800`), which `sync_templates` overwrites **verbatim** with Meta's `data` array via `update_columns` — so any Lynomia-owned field written into it is destroyed on the next 3-hourly sync. And every send-side consumer reads that column, so a draft placed there becomes sendable, which is exactly the property Phase 5 must make structurally impossible. A second jsonb column on the same row fails the same way for provenance and gives no stable primary key to hang status history on | **Phase 5** (and therefore Phase 6) |
| **M2** | **Starter provenance** on recipe-created objects, if "did anyone use a starter, and is it still in use" must be answerable | The only provenance today is interpolated, user-editable prose in the `description` field (`flows/Index.vue:130-133`, `automation/Index.vue:209-212`); audiences get none. Nothing reads it back, so there is no way to find, count or migrate objects created from a recipe, and the catalogue's `version` field has no upgrade path | Nothing. Phase 2 ships without it; the question stays unanswerable |
| **M3** | **Persisted prior cart state** plus a `Commerce::CartTransitions` emitting a provider-neutral `commerce_cart_abandoned` into the **existing** `Automation::CommerceEvents.dispatch` | See §11 row 1. The account-wide read it would need already exists (`custom/app/controllers/api/v1/accounts/commerce/carts_controller.rb:37-43`, `abandoned_carts(limit: 50)` behind the `:cart_queue` cache), so no new provider call is required — the gap is purely emission-side **(V)**. Reliability ceiling even then: Zid only; Shopify for linked customers but never guests (`shopify/carts.rb:51` hardcodes email/phone `nil`); Salla not reliably; WooCommerce impossible | Only an abandoned-cart feature, which §11 says not to build. **Contingent — do not approve unless that decision is revisited** |

**Not proposed, and why.** A server-side campaign draft (Phase 1 uses a client-side draft — the journey does not need
durability across devices). A `release_notes` table (M2 of doc `10` resolves to `Article` + `meta`). An accountless
portal. A contact `id` filter key. Article revision history needs **no** migration **(V)**.

---

## 13. Security and tenant risks

| Risk | Status | Phase that closes it |
|---|---|---|
| **Contacts export emails the whole account when run from a search** — data exposure, in just-shipped work **(V)** | **LIVE** (`contacts/actions.js:202-205`) | **P0 / D2** |
| **Portal slug squatting** — a single global, first-come-first-served namespace with no reservation, and tenant onboarding automatically claims `-docs` / `-help` **(V)** | **LIVE** (`app/models/portal.rb:44`; `help_center_creation_service.rb:114-124`) | **3** (blocking prerequisite) |
| `custom_filters.query` is unvalidated on write — the base controller permits `query: {}` wholesale and the model validates only name, so a malformed payload persists and raises later, including at campaign **send** time **(V)** | LIVE (`custom_filters_controller.rb:46`; `app/models/custom_filter.rb:25,30-34`) | not scheduled — see §10 note; a stored time bomb, worth its own decision |
| `InboxPolicy#message_templates?` is a plain `true`, so the template read is open to any member of an assigned inbox | LIVE (`app/policies/inbox_policy.rb:37-39`) | **5** (re-gate when the record becomes the system of record) |
| Super Admin is outside Pundit and outside tenancy, so whoever owns the internal docs account can edit global documentation | by design (`super_admin/application_controller.rb:14`) | **3** — the reader/writer gate must be **decided**, not copied from `PlatformBanner`'s cloud gate |
| Two public endpoints with no custom-domain guard: `portals#sitemap`, `articles#tracking_pixel` **(V)** | LIVE | **3** (know before publishing) |
| A shared audience referenced by a published flow deletes without warning; the runtime then takes the silent `false` branch | LIVE (`audience/usage.rb:8-22` vs `flows/node_validator.rb:91`) | **1** |
| Zid webhooks are **unsigned** — HTTP Basic Auth with a per-store random pair, and the field that hands Zid those credentials is marked unverified in the code | LIVE, by provider | not closeable by us; gate recipes accordingly (`03 §2.4`) |
| Automation `send_webhook_event` is **unsigned**, while the flow webhook node signs | LIVE | NEW PRIMITIVE REQUIRED, unscheduled |
| Brand and instance egress to `hub.2.chatwoot.com` — host, version, edition, account/user/inbox/conversation/message counts (`lib/chatwoot_hub.rb:59-79`); base URL overridable **only** in `Rails.env.development?` | LIVE | **LEGAL_REVIEW** (`07 §11.2`); needs a production-overridable base URL, which no mechanism provides today |
| LLM system prompts leak the brand to the model provider on every AI-assist rewrite **(V)** | LIVE (`tone_rewrite.liquid:1`, `fix_spelling_grammar.liquid:1`) | **3** |
| Custom roles are unreachable on a community-plan install, and a custom-role user is **neither** agent nor administrator for route gating | by configuration | none — do not gate any new surface on custom roles (`11 §11.3`) |
| `meta.featureFlag` is not enforced on navigation, only on rendering | LIVE (`routeHelpers.js:15-18`) | cosmetic — every endpoint re-checks server-side |

**Strongest existing guards, for the record — nothing to add.** Tenancy fires once, at
`EnsureCurrentAccountHelper` (`app/controllers/concerns/ensure_current_account_helper.rb:9-21`), inherited by every
account-scoped controller including all of `custom/`. `channel_whatsapp.phone_number` is globally unique at the
**database** (`db/schema.rb:806`), so one WABA number cannot exist in two accounts. Commerce stores are protected by a
DB unique `(provider, external_store_id)` plus `Commerce::StoreConnection#claim`, which fails loud. Foreign audience
ids fail `audiences_shared_in_account?`, enforced both as a validation and in the preview endpoint.

---

## 14. Provider-specific limitations

**WhatsApp / Meta** — all **(V)** unless marked **(R)**:

| Limitation | Consequence for the roadmap |
|---|---|
| Graph `v14.0` / `v13.0` pinned; both past Meta's support window | **P0/D3.** Template sync goes offline on enforcement, if it has not already |
| The four template webhook fields (`message_template_status_update`, `_quality_update`, `_components_update`, `template_category_update`) **do not support callback overrides** | The only WhatsApp route is per-phone (`config/routes.rb:678-679`) **(R)**, so push status is impossible without a new app-default route → Phase 6 |
| Edit allowed only on `APPROVED` / `REJECTED` / `PAUSED`; approved capped at 1/24 h and 10/30 d; components replaced **wholesale**; approved category not editable; editable set is **category, components, TTL only** | Shapes every control Phase 5 is permitted to render. Do not build on the wider six-item node-reference list |
| Deleting an approved template blocks the same name for **30 days** | Avoided by design — `CsatTemplateNameService` mints a new versioned name. Keep it that way; the P0/D4 item is the destructive delete, not the name |
| Category review / appeal is WhatsApp Manager only | Phase 5 must **say it**, not offer it |
| Flow Builder runs on **WhatsApp Cloud only** (`Flows::ChannelCapabilities.for`) | Every flow starter is WhatsApp-Cloud-only; the inbox pickers must stop offering others (Phase 2 patch) |
| 360dialog has no add-inbox entry point in the UI | Any "all providers" template claim is false |

**Commerce** — the gating facts, before any per-provider nuance: `Commerce::Switches::PRE_UAT` holds salla/zid/shopify
for **both** `actions` and `recovery`, and WooCommerce has no `RECOVERY_KEYS` entry, so writes and all cart/recovery
features are hard-off for **every** provider in a default install (`custom/app/services/commerce/switches.rb:15-16`);
and `SALLA_ENABLED`, `ZID_ENABLED`, `SHOPIFY_COMMERCE_ENABLED` all ship `value: false`
(`config/installation_config.yml:488-490,515-517,535-537`), leaving WooCommerce — the weakest provider — as the only one
enabled by default.

| Provider | Carts | Orders | Writes |
|---|---|---|---|
| **WooCommerce** | **none** — no cart code at all; inherits `supports_carts? = false` | can **never** report `shipped` or `delivered` (`woocommerce/normalizer.rb:17-20,35`); reliable `paid` and refunds | 5 of 7 action types, and the only provider not held by `PRE_UAT` |
| **Shopify** | linked customers only — `shopify/carts.rb:51` hardcodes email/phone `nil`, so **guests can never match** | `delivered` is derived, bounded and webhook-less; reliable `paid` and `REFUNDED`/`PARTIALLY_REFUNDED` | cancel + refund only |
| **Zid** | the best cart data (customer-filtered list + per-cart detail + an explicit recovered signal) | usable | one status change, two transitions — but the webhook transport is **unsigned** |
| **Salla** | unreliable — an unfiltered 30-row page, `abandoned_cart` is a linear scan of it, `status` hardcoded `'abandoned'`, path/scope marked `VERIFY` in the code | can **never** be `paid` (`salla/normalizer.rb:74-75`); the only refund signal is a `restored` slug with unverified semantics | **none** |

**The fact that outranks all of the above:** commerce automation is **read-driven**, not webhook-driven **(V)**.
`Automation::CommerceEvents.dispatch` has exactly one call site (`custom/app/models/commerce/contact_metric.rb:27`),
and `ContactMetric.record` has exactly two callers (`realtime.rb:93`, `conversation_panel.rb:62`). A provider webhook
only invalidates cache; the event fires when something **re-reads** the order — in practice when an agent opens the
conversation panel. **No commerce recipe may promise "the moment X happens."** The only commerce action that is not a
false promise is `send_webhook_event`, which the `custom/` overlay enriches with
`commerce: {event, store_id, provider, order}` (`custom/app/services/custom/automation_rules/action_service.rb:4-14`)
— an overlay the first inventory missed entirely **(V)**.

---

## 15. Recommended first phase

**Run P0 as the first sprint. It is not a phase and it is not optional. Then make Phase 1 — the audience and campaign
entry path — the first feature phase.**

P0 is four to six days for eight live defects, two of which are data-visible (D2 exports an entire account's contacts
to someone who searched for three of them; D6 silently disables the bulk feature that shipped last). D1 alone is half a
day and decides whether anything else brand-related in this program survives a daily job.

Against the three alternatives:

**Why not the branding pre-phase as the *phase*.** Because it is not a phase. D1 is one yml file and belongs in P0; the
rest of branding (three config rows, the `BRAND_URL` store gap, the LLM prompts, the 34 hard-coded `Lynomia` literals)
has no coherent user outcome on its own and shares its most valuable piece — re-pointing the 28 `chwt.app` help URLs in
`featureHelper.js:2-28` — with Phase 3, because those links need somewhere to point. Splitting it out would ship a
config key with no destination.

**Why not the starter library first, even though it is the headline.** Three reasons, in order. (1) It is **gated on
D8**: a catalogue whose entries carry an unvalidated `event_name` can ship a rule that saves and never fires, which is
the worst possible failure for a product whose value proposition is "this just works." (2) It is **gated on Phase 1 for
part of its content**: `automationRecipes.js:142` and `flowTemplates.js:281` require a shared audience, and
`useRecipeContext.js:51` hides them while none exists **(R)** — so shipping more audience-gated recipes onto a creation
path that destroys a campaign draft multiplies a known failure instead of fixing it. (3) The contract EXTEND it needs
is small and will not get smaller by waiting, but the catalogue's value compounds with the number of users who can
complete a recipe, and Phase 1 is what makes that number go up.

**Why not the WhatsApp manager first, even though it is the highest value.** It is the only phase that needs a
migration (M1), the only one that creates state the product must then maintain, and the one whose headline benefit —
status truth — depends on a webhook route Meta will not deliver to the route we have. Its read-side truth work
(Phase 4) is four to six days and is worth doing whether or not the manager is ever built; its write side should not
start until that has shipped and the migration is approved. Starting here means asking for a schema decision in week
one, on the basis of the least-settled architecture in the program.

**Why Phase 1.** It is pure UX with no new persistence and no new authorization. It removes a daily, user-visible
failure — a half-written campaign destroyed by going to create the audience it needs — that has no workaround today. It
closes a silent correctness hole on the way (a flow-referenced audience deleting without warning). It unblocks part of
Phase 2. And it is the one phase where everything it needs already exists in the repo and merely needs connecting: the
query-param bridge, the create dialog, the store mutation that makes the new audience appear in the picker, and the
preselect prop. Measured against the program's actual bottleneck — the brief's own framing is that the engines are
finished and the **entry path** is missing — this is the entry path.

---

## 16. What is UNVERIFIED

- **Whether D1's daily path fires on any specific deployment.** Depends on `ChatwootHub.sync_with_hub` reaching
  `hub.2.chatwoot.com`, the live `INSTALLATION_PRICING_PLAN` row, and Sidekiq-cron running. Code path and defaults
  verified statically; execution not. Confirm the live row before relying on any premium-feature conclusion
  (`11 §R7`).
- **All sizes in this document are estimates**, not measurements. No phase has been prototyped.
- **The campaign draft loss** is inferred from the router composition (`campaigns.routes.js:15-26` →
  `Dashboard.vue:156` bare `<router-view />` → `CampaignsPageRouteView.vue:21-26`) plus `resetState`; it was not
  reproduced in a browser for this document.
- **Meta's current enforcement posture on v14.0.** The version table says expired 2024-09-17 **(V)**; whether calls
  are currently rejected or merely deprecated on this app was not tested against live Graph.
