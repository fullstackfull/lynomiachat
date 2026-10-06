# Branding audit and replacement plan

Repo `/home/user/lynomiachat`, branch `claude/practical-thompson-9xfqed`, HEAD `6c381e96`.

Provenance: the `branding` and `external_links` area inventories, corrected by the `branding-counts` adversarial
verifier. Where they disagreed the verifier wins and the line is marked **(V)**. Counts marked **(R)** I reproduced
myself against this HEAD; counts marked **(R≠)** I reproduced and got a *different* answer from both the inventory and
the verifier, and the number shown is mine. Claims I could not cite are marked **UNVERIFIED**. No migration is proposed
anywhere in this document — where one would be needed the requirement is stated and left for approval.

Covers brief parts **0.10, 6, 24**.

---

## 1. The decision in one page

**A central white-label mechanism already exists, and its defaults in this repo already say Lynomia. The large majority
of the brand surface is therefore CONFIGURE, not REPLACE. The work that matters is not renaming strings — it is stopping
the Enterprise overlay from silently renaming them back to Chatwoot.**

Ten `InstallationConfig` keys (`config/installation_config.yml:17-58`) flow:

```
config/installation_config.yml  ->  ConfigLoader#reconcile_general_config (lib/config_loader.rb:40-46)
  -> installation_configs table  ->  GlobalConfig (Redis, V1:GLOBAL_CONFIG:<KEY>, lib/global_config.rb:41-51)
  -> DashboardController::GLOBAL_CONFIG_KEYS (app/controllers/dashboard_controller.rb:5-28)
  -> window.globalConfig  ->  app/javascript/shared/store/globalConfig.js:4-30
  -> useBranding().replaceInstallationName (app/javascript/shared/composables/useBranding.js:15-22)
```

All ten already carry Lynomia values: `INSTALLATION_NAME` and `BRAND_NAME` are `'Lynomia chat'`
(`config/installation_config.yml:18,42`), `BRAND_URL`/`WIDGET_BRAND_URL` are `https://www.chat.lynomia.com` (`:34,:38`),
`TERMS_URL`/`PRIVACY_URL` point at `chat.lynomia.com` (`:46,:50`), logos at `/brand-assets/logo*.svg` (`:22,:26,:30`)
**(R)**. Because `isACustomBrandedInstance` is literally `installationName !== 'Chatwoot'`
(`app/javascript/shared/store/globalConfig.js:67`) **(R)**, the white-label suppression in
`CustomBrandPolicyWrapper.vue:1-26` is *already* active and the chatwoot.com Docs/Changelog menu entries are already
hidden — purely as a consequence of configuration.

### The two findings that dominate strategy

| # | Finding | Verdict |
|---|---|---|
| **1** | `enterprise/config/premium_installation_config.yml:1-22` **still holds the Chatwoot values**, and `Internal::ReconcilePlanConfigService#reconcile_premium_config` (`enterprise/app/services/internal/reconcile_plan_config_service.rb:38-46`) **overwrites the live branding rows back to them** whenever `ChatwootHub.pricing_plan == 'community'` — the seeded default. Driven daily. **The branding silently reverts to Chatwoot.** | **LIVE DEFECT — PATCH. Highest-value fix in the whole program.** §3 |
| **2** | `ConfigLoader` defaults `reconcile_only_new: true` (`lib/config_loader.rb:2-5,48-55`) and **both** callers pass no args (`db/seeds.rb:3`, `lib/tasks/db_enhancements.rake:5`) **(R)**, so the Lynomia yml values **never overwrite already-seeded rows** on an existing install. | **PATCH (operationally, not necessarily in code).** §4 |

And the gate that makes both worse: the Super Admin branding UI (`custom_branding`) is gated on
`pricing_plan != 'community'` (`app/helpers/super_admin/features.yml:15`,
`enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb:16`) **(R)**, so on a community install
**there is no UI path to change branding at all** — see §5. A defect that reverts the brand plus no UI to put it back is
a support incident, not a cosmetic issue.

### Capability verdicts

| Capability | Verdict | Why |
|---|---|---|
| Installation-wide brand name, logos, brand/terms/privacy URLs | **REUSE** | 10 config keys, already Lynomia, already shipped to the browser. §2 |
| Runtime string substitution of "Chatwoot" in copy | **REUSE** | `replaceInstallationName`, 42 invocations across 32 non-spec files **(V)(R)**. §2.2 |
| Protect configured brand values from the EE overlay | **PATCH** | One-line guard or one yml file; no new primitive. §3.4 |
| Reachable branding editor on a community install | **PATCH** | Three independent gates, all one-line. §5 |
| Configurable docs / help-centre base URL | **NEW PRIMITIVE REQUIRED** | No `HELP_URL`/`DOCS_URL` key exists among the 133 names in `config/installation_config.yml`; today the only mitigation is suppression, not substitution. §7 |
| Configurable mailer sender identity from Super Admin | **NEW PRIMITIVE REQUIRED** | `MAILER_SENDER_EMAIL` is ENV-only across 6 production call sites. §8.3 |
| Configurable MFA/TOTP issuer, PWA manifest name, SPA `<title>` | **NEW PRIMITIVE REQUIRED** (small) | Bare literals, no config read. §9 |
| Per-account (tenant) branding | **DO NOT CREATE** | `installation_configs` is keyed on `name` only, no `account_id`; the sole account-scoped control is the `disable_branding` flag (`config/features.yml:35`). §2.3 |
| Mass rename of internal `chatwoot_*` / `woot-*` identifiers | **DO NOT CREATE** | 921 runtime lines are upstream contract surface — embed snippets, webhook headers, mobile apps. §10 |
| Global i18n post-processor so every string is auto-substituted | **EXTEND** (recommended) — not a new primitive | `replaceInstallationName` is opt-in per call site; vue-i18n's `postTranslation` hook is unused (`rg postTranslation app/javascript` → 0) **(R)**. §6.4 |

---

## 2. The mechanism that already exists

### 2.1 The ten keys — the entire centrally-configurable brand surface

`INSTALLATION_NAME`, `BRAND_NAME`, `LOGO`, `LOGO_DARK`, `LOGO_THUMBNAIL`, `BRAND_URL`, `WIDGET_BRAND_URL`, `TERMS_URL`,
`PRIVACY_URL`, `DISPLAY_MANIFEST` (`config/installation_config.yml:17-58`). The same ten, in the same order, are what the
Enterprise branding form enumerates (`enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb:43-56`)
**(R)** — independent confirmation that this list is the designed brand surface and not an accident.

Everything downstream of them needs **no code change**: all SPA logo surfaces
(`components-next/icon/Logo.vue:11-13`, `v3/views/login/Index.vue:366-367`, `v3/views/login/Saml.vue:76-83`,
`app/views/layouts/vueapp.html.erb:32`), the HTML meta description (`vueapp.html.erb:13`, interpolates
`INSTALLATION_NAME` twice) **(R)**, the widget/survey "Powered by" footer (`shared/components/Branding.vue:33-73`), the
help-centre portal footer (`app/views/public/api/v1/portals/_footer.html.erb:8-14`), and the email footer
(`app/views/layouts/mailer/base.liquid:93-130`, with `'Chatwoot'` only as the nil fallback at `:95`).

### 2.2 `replaceInstallationName` — corrected reach

`text.replace(/chatwoot/gi, installationName)` (`app/javascript/shared/composables/useBranding.js:21`) **(R)**.

| Measure | Value |
|---|---|
| Non-spec files importing it | **32** (38 including specs) **(V)(R)** |
| Textual occurrences (non-spec) | **83** **(V)(R)** |
| Real invocations (non-spec) | **42** **(V)(R)** |

The inventory's "36 files / ~64 call sites" was wrong in both directions. More importantly, **coverage is per CALL SITE,
not per i18n key (V)**: `generalSettings.json:126` (`GENERAL_SETTINGS.UPDATE_CHATWOOT`) is wrapped at
`BuildInfo.vue:42` but **not** at `UpdateBanner.vue:32`, which has no `useBranding` import. So the inventory's
"~30 uncovered EN keys" is a **floor, not a count** — any key with two renderers can be simultaneously covered and
leaking.

### 2.3 Tenancy

Branding is **installation-wide**. `installation_configs` is unique on `name` with no `account_id`
(`app/models/installation_config.rb:14`). The only account-scoped branding control is the boolean `disable_branding`
feature flag (`config/features.yml:35`), an EE plan feature (`enterprise/config/premium_features.yml:2`) that hides the
"Powered by" footer in three places (`shared/components/Branding.vue:56`, `app/views/layouts/portal.html.erb:12`,
`app/views/widgets/show.html.erb:31`). Per-tenant brand names, logos or URLs do not exist and would require schema —
**DO NOT CREATE** unless a tenant-branding requirement is approved separately.

---

## 3. LIVE DEFECT 1 — the Enterprise overlay resets the brand to Chatwoot

### 3.1 The chain, re-traced end to end

| Step | Evidence |
|---|---|
| `enterprise/` exists and `DISABLE_ENTERPRISE` is unset, so `ChatwootApp.enterprise?` is true | `lib/chatwoot_app.rb:14-18` **(V)** |
| `Internal::CheckNewVersionsJob` is prepended with the EE module | `app/jobs/internal/check_new_versions_job.rb:20`; `config/initializers/01_inject_enterprise_edition_module.rb:70-80` **(V)** |
| EE `perform` calls `super`, then calls `reconcile_premium_config_and_features` **unconditionally** | `enterprise/app/jobs/enterprise/internal/check_new_versions_job.rb:2-6,27-29` **(R)** |
| OSS `super` returns early off-production — but that guard does **not** stop the reconcile | `app/jobs/internal/check_new_versions_job.rb:4-5` **(R)** |
| `ChatwootHub.pricing_plan` reads `INSTALLATION_PRICING_PLAN`, seeded default `'community'` | `lib/chatwoot_hub.rb:39-43`; `config/installation_config.yml:331-332` **(V)** |
| So the guard at `:4` does not fire, and `:38-46` `update!`s every key in the premium yml over the live row | `enterprise/app/services/internal/reconcile_plan_config_service.rb:4,38-46` **(R)** |
| The premium yml still holds Chatwoot | `enterprise/config/premium_installation_config.yml:3,11,13,15,17,19` **(R)** |
| Daily trigger | `config/schedule.yml:7-10` → `app/jobs/internal/trigger_daily_scheduled_items_job.rb:12-15` **(R)** |
| On-demand trigger, **in any environment** | `app/controllers/super_admin/settings_controller.rb:5` (`Internal::CheckNewVersionsJob.perform_now`) **(R)** |

### 3.2 What is overwritten

`INSTALLATION_NAME` → `'Chatwoot'`, `BRAND_NAME` → `'Chatwoot'`, `BRAND_URL` and `WIDGET_BRAND_URL` →
`https://www.chatwoot.com`, `TERMS_URL` → `https://www.chatwoot.com/terms-of-service`, `PRIVACY_URL` →
`https://www.chatwoot.com/privacy-policy` (`enterprise/config/premium_installation_config.yml:2-19`) **(R)**.

### 3.3 The blast radius is larger than six strings

Because `isACustomBrandedInstance` is a string comparison against `'Chatwoot'`
(`app/javascript/shared/store/globalConfig.js:67`), resetting `INSTALLATION_NAME` **flips the entire white-label
suppression back on**: the chatwoot.com Docs and Changelog entries in `SidebarProfileMenu.vue:93,102` reappear, every
settings-page help link in `BaseSettingsHeader.vue:78-92` reappears, and every one of the 42 `replaceInstallationName`
call sites starts rendering "Chatwoot" again. The widget and survey footers served to *end customers* revert to
"Powered by Chatwoot" linking to chatwoot.com.

And the same service sets a Redis flag precisely when a Lynomia value differs from the premium yml
(`reconcile_plan_config_service.rb:30-36` → `:26-28`), which renders this banner in Super Admin:
*"Unauthorized premium changes detected in Chatwoot. To keep using them, please upgrade your plan. Contact for help :
sales@chatwoot.com"* (`app/views/super_admin/settings/show.html.erb:16-20`) **(R)**. Branding Lynomia correctly is what
triggers a Chatwoot sales banner.

### 3.4 Recommendation — **PATCH**, and do it first

Two shapes, both small; I recommend the first.

1. **Align the overlay's values.** Rewrite `enterprise/config/premium_installation_config.yml:1-22` to the Lynomia
   values that `config/installation_config.yml:17-58` already holds. The reconcile then becomes a no-op for branding
   (`:42` skips when values match), `premium_config_reset_required?` stops firing, and the sales banner stops appearing.
   No service change, no guard, no new primitive — and it keeps the premium-feature reconcile intact.
2. Exclude the ten branding keys from `reconcile_premium_config`. Smaller diff in the yml, but it edits an EE service and
   leaves a file in the tree that still says Chatwoot, which will be copied forward by the next upstream merge.

Corroborating evidence a reviewer should read before touching either: `spec/enterprise/services/internal/`
`reconcile_plan_config_service_spec.rb:44` asserts `LOGO` resets to `/brand-assets/logo.svg` — the spec encodes the
reset as intended behaviour, so option 1 keeps that spec meaningful while option 2 invalidates it.

**UNVERIFIED (runtime):** whether this fires on any specific deployment depends on `ChatwootHub.sync_with_hub` reaching
`hub.2.chatwoot.com`, the stored `INSTALLATION_PRICING_PLAN`, and Sidekiq-cron actually running. The code path and the
defaults are verified statically; the execution is not. Note that the on-demand path (`settings_controller.rb:5`) needs
none of that.

---

## 4. LIVE DEFECT 2 — editing the yml does not re-brand an existing install

`ConfigLoader::DEFAULT_OPTIONS` sets `reconcile_only_new: true` (`lib/config_loader.rb:2-5`); `save_general_config`
then writes **only when the row is absent** (`:48-55`) **(R)**. Both production callers pass no arguments:
`db/seeds.rb:3` and `lib/tasks/db_enhancements.rake:5` (the latter hooked onto every `db:migrate`) **(R)**.

Consequence: on any database seeded before the Lynomia values landed, the ten rows still hold whatever they were first
seeded with, and no deploy will change them. Combined with §5, that leaves **no supported path to correct them** short of
a rails-console write.

**Recommendation — PATCH, operational.** Do not change `reconcile_only_new`'s default: flipping it globally would
overwrite every operator-customised config in the file, not just branding. Instead make the brand-correction step
explicit and auditable (a one-off `ConfigLoader.new.process(reconcile_only_new: false)` is *not* safe for the same
reason). The clean version is covered by §5: make the ten keys editable and the UI reachable, then correct them there.

---

## 5. There is no UI path to branding on a community install

Three independent gates, all verified:

| Gate | Evidence |
|---|---|
| The Custom Branding card is disabled | `app/helpers/super_admin/features.yml:15` — `enabled: <%= (ChatwootHub.pricing_plan != 'community') %>` **(R)** |
| …so the gear link is not rendered | `app/views/super_admin/settings/show.html.erb:118` — needs `attrs[:config_key].present? && attrs[:enabled]` **(R)** |
| …and the EE controller falls through to OSS, whose mapping has no `custom_branding` key, silently serving GENERAL_CONFIGS instead | `enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb:16`; `app/controllers/super_admin/app_configs_controller.rb:69-88` **(R)** |
| The parallel Installation-configs list is also closed: it filters to `.editable` i.e. `locked: false`, and none of the ten keys declares `locked: false`, so `set_lock` forces `locked = true` | `app/controllers/super_admin/installation_configs_controller.rb:26`; `app/models/installation_config.rb:37,44,65-67` **(R)** |

**Recommendation — PATCH.** The values *are* configurable; this is a UI-reachability gap, not a missing capability. Either
drop the `pricing_plan` gate on `custom_branding` for self-hosted installs, or add `locked: false` to the ten keys in
`config/installation_config.yml:17-58` so they surface in the existing Installation-configs editor. The second is the
smaller change and reuses a shipped screen, but note `compare_values` (`lib/config_loader.rb:57-60`) also compares
`locked`, so changing `locked` in the yml has no effect on already-seeded rows either — same trap as §4. Decide §4 and §5
together.

---

## 6. Part 24 — occurrence counts by class, with classification

Total: **8,302** case-insensitive `chatwoot` occurrences in **2,053** files over **10,987** tracked files **(R)** —
reproduced exactly against this HEAD.

**Read the convention before the table.** Category rows are *occurrence* counts (`rg -io`). The runtime residual is a
*line* count, because that is how it was measured (total matching lines case-insensitive is 7,035, not 8,302) **(V)**.
**The column therefore does not sum to 8,302 — do not add it up.**

| Class | Count | Classification | Rationale |
|---|---|---|---|
| Non-English locale files (Crowdin-owned) | 3,829 **(V)(R)** | **KEEP** | 46% of the total. CLAUDE.md forbids hand-editing; they inherit whatever EN says and pass through `replaceInstallationName` at covered call sites. Fix EN, not these. |
| Specs / fixtures / stories | ~1,634 (inventory; my wider glob reproduces 1,493) **(R≠)** | **KEEP** | Never served. Only rebrand a spec when the production string it asserts changes. The single approximate figure in this table. |
| Prior discovery docs under `docs/**` | 640 **(V)(R)** | **KEEP** | Internal engineering record, never served. |
| Deployment / CI / env / container identifiers | 409 (inventory) / 429 **(V)** over the same file set; my recount over `deployment/ docker* .github/ .circleci/ .devcontainer/ Makefile Procfile app.json .env*` gives 407 **(R≠)** | **KEEP** | systemd unit names, `POSTGRES_DB=chatwoot`, `db:chatwoot_prepare`, `IOS_APP_ID`/`ANDROID_BUNDLE_ID`. Renaming these breaks deploys and app-store identity for zero user-visible gain. |
| Swagger / OpenAPI | 169 **(V)(R)** | **KEEP** | `app/controllers/swagger_controller.rb:3-12` returns `head :not_found` outside dev/test, so not production-reachable. |
| Legal / licence / README / attribution | 84 **(V)(R)** | **LEGAL_REVIEW** | `LICENSE:1,6`; `enterprise/LICENSE:1-34` binds EE-overlay use to the Chatwoot Subscription Terms and requires a valid Chatwoot Enterprise License. Must not be edited to say Lynomia. The real question is whether the EE overlay may be shipped at all. |
| English source strings (`en/*.json`, `widget/survey en.json`, `config/locales/en.yml`) | 79 **(V)(R)** | **CONFIGURE** for the 22 keys reaching a `replaceInstallationName` call site; **REPLACE** for the rest | ~30 keys are uncovered and that figure is a floor (§2.2). `inboxMgmt.json:1605` is the `window.chatwootSettings` SDK snippet — **KEEP**. |
| Runtime product code, residual | **1,266 lines**, of which **921 are internal upstream identifiers** (inventory, undisputed by the verifier) | mixed — see below | The only class where real decisions live. |
| └ internal upstream identifiers | 921 of the 1,266: `@chatwoot/` npm 125, widget SDK globals/events 192, `X-Chatwoot-*` headers 19 names (141 occurrences across **18** genuinely distinct names **(V)**), Ruby/JS class names 407, `CHATWOOT_*`/`chatwoot_*` keys 280 | **KEEP** | §10 — explicit recommendation not to rename. |
| └ genuinely hard-coded user-visible literals | ~345 lines (1,266 − 921) | **REPLACE** | §9 enumerates the ones that reach a user. |
| `woot`-derived identifiers (no `chatwoot` substring) | **3,802** **(V)(R)**: `woot` 12,104 minus `chatwoot` 8,302 | **KEEP** | Corrected from the inventory's 2,464, understated by ~54%. `woot-widget` 93, `woot-elements` 8, `woot--` 30, `Woot<Pascal>` component refs 210, `woot_` 383 **(V)**. The `woot-*` CSS classes land in the customer's own page DOM via the embedded widget. §10 |
| `chwt.app` short-link domain | **59** **(R)** | **REPLACE** | Invisible to a `grep chatwoot` audit. §7 |
| Hard-coded **Lynomia** literals (the inverse problem) | 34 case-insensitive **(V)**, of which **32 are user-visible brand literals** and 2 are i18n key names **(R)** | **REPLACE** (with config reads) | §8.1 |

---

## 7. The `chwt.app` blind spot

`chwt.app` is a Chatwoot-owned short-link domain containing no `chatwoot` substring, so every "grep for chatwoot" audit —
including the first pass of this one — misses all 59 occurrences **(R)**.

| Location | Count | Reachable by a Lynomia user? |
|---|---|---|
| `app/javascript/dashboard/helper/featureHelper.js:2-27` — one hard-coded `FEATURE_HELP_URLS` table | **25** `chwt.app` URLs + 1 `www.chatwoot.com` URL (`whatsapp_templates`) = **26 entries** **(R≠)** | Partly. `getHelpUrlForFeature` (`:33-36`) has two consumers: `BaseSettingsHeader.vue:42` (wrapped in `CustomBrandPolicyWrapper`, so hidden on Lynomia) and `components-next/captain/pageComponents/overview/QuickLinks.vue:26` (**not gated** — the Captain "Docs" tile links to `chwt.app/captain-docs` on every install) |
| `config/features.yml:23,27,45,49,59,66,70,77,81,94,98,134,278` — `help_url:` lines | **13** **(R≠)** | **No UI reads them.** `rg helpUrls app/javascript` → **0 hits (R)**. They are still emitted into the HTML of every dashboard page via `app/helpers/application_helper.rb:6-11` → `vueapp.html.erb:58` as `window.chatwootConfig.helpUrls`, so they are discoverable by anyone viewing source, but drive no UI. **This is also a duplication defect**: the live links come from the parallel `featureHelper.js` table. |
| WhatsApp migration flow | 3 — `WhatsappManualMigrationBanner.vue:10`, `WhatsappManualMigrationDialog.vue:26`, `WhatsappBusinessManagementToken.vue:17` | **Yes, ungated** |
| Captain pages/empty states | 7 — `captain/{responses,documents,assistants}/Index.vue`, 4 `*PageEmptyState.vue` | No — each paired with `:hide-actions="!isOnChatwootCloud"` and `deploymentEnv !== 'cloud'` self-hosted |
| Campaign empty state | 1 — `CampaignEmptyStateContent.js:117` (`chwt.app/g2-review` inside a sample SMS body) | **Yes, ungated** |
| `config/installation_config.yml:177` (`chwt.app/dev/ms`) | 1 | Yes — rendered as the `AZURE_APP_ID` help text in Super Admin |
| Non-runtime (`README.md`, `deployment/setup_20.04.sh:999`, `db/migrate/…:30`, `lib/tasks/asset_clean.rake:1`, docs, one Playwright spec) | 9 | No |

Note the inventory's "28 help URLs in `featureHelper.js` and 14 more in `config/features.yml`" is wrong in both halves;
the verified figures are 25 (+1 chatwoot.com) and 13 **(R≠)**.

**Recommendation.** The table-driven links are **EXTEND**: `featureHelper.js:2-27` is already a single lookup keyed by
feature name, so repointing it at a Lynomia docs base is one table edit plus a base-URL config read — which is the
**NEW PRIMITIVE REQUIRED** from §1 (`HELP_DOCS_BASE_URL` as an eleventh branding key; no migration, it is a row in
`installation_configs`, pending approval). Delete the dead `config/features.yml` `help_url:` lines rather than
rebranding them — they are a second source of truth that nothing reads. Fix the two ungated reachable surfaces
(`QuickLinks.vue:26` and the WhatsApp migration trio) regardless, since suppression does not cover them.

---

## 8. The inverse problem the first pass missed

The first audit asked only "how much Chatwoot is left" and never "how much Lynomia is hard-coded" **(V)**. The brand
surface is now hard-coded in **both** directions, so a future rename — or the §3 reset — leaves a mixed-brand UI.

### 8.1 Hard-coded `Lynomia` literals that never read config

`replaceInstallationName`'s regex is `/chatwoot/gi` (`useBranding.js:21`), so it can **never** substitute these.

| Location | Occurrences | Note |
|---|---|---|
| `app/javascript/dashboard/i18n/locale/en/commerce.json` | 28 **(R)** | e.g. `:133`, `:178`, `:213-214`, `:230-232`, `:240-241`, `:254` |
| `app/javascript/dashboard/i18n/locale/en/automation.json:258` | 1 **(R)** | `COMMERCE_TRIGGER_NOTE`. (`:246` is the `"LYNOMIA"` *key* name, not a visible string) |
| `app/javascript/dashboard/i18n/locale/en/contactFilters.json:82` | 1 **(R)** | `COMMERCE_NOTE` |
| `config/locales/en.yml:614,619` | 2 **(R)** | (`:613` is the `lynomia:` key name) |
| `config/features.yml:283,287` | 2 **(R)** | `display_name: Lynomia Commerce` / `Lynomia Flow Builder` |
| `app/helpers/super_admin/features.yml:155,161,167,172` | 4 **(R)** | Super Admin card descriptions |
| `config/installation_config.yml:487-612` | **17** **(R)** | Super Admin App-config help text |
| `app/javascript/dashboard/i18n/locale/ar/commerce.json` | 28 **(V)** | **Hand-edited non-English locale, contrary to the CLAUDE.md Crowdin rule.** Flag for the translation owner. |

Also already inconsistent inside the branding block itself: `config/installation_config.yml:55-56` reads
`display_title: 'Lynomia Metadata'` with `description: 'Display default Chatwoot metadata…'` **(R)**.

**Recommendation — REPLACE with the existing convention.** The repo already has a second, better mechanism: the
`{installationName}` i18n placeholder (`conversation.json:442-446`, `mfa.json:44`, `integrationApps.json:64`; 8 EN
occurrences). Convert these 32 literals to that placeholder rather than adding more fixed brand text. Server-side yml
help text can read `GlobalConfig` directly. **Do not** convert `ar/commerce.json` by hand — route it through Crowdin.

### 8.2 The LLM system prompts leak the brand to the model provider

Both files begin *"You are an AI writing assistant integrated into **Chatwoot**, an omnichannel customer support
platform"*: `lib/integrations/openai/openai_prompts/tone_rewrite.liquid:1` and
`lib/integrations/openai/openai_prompts/fix_spelling_grammar.liquid:1` **(R)**. These are sent to the model provider on
**every AI-assist rewrite**, so the upstream brand leaves the installation on every request and can surface in model
output that an agent then pastes to a customer. Neither appeared anywhere in the first audit.

**Recommendation — PATCH.** These are Liquid templates already rendered with a variable context; substituting a brand
variable is the same mechanism the mailer layout already uses (`app/views/layouts/mailer/base.liquid:93`). Worth checking
the other six prompts in that directory for the same opening before shipping. **Classification: REPLACE** (and a
privacy/brand-egress item worth noting alongside the telemetry item in §11).

### 8.3 `MAILER_SENDER_EMAIL` — six production call sites, ENV-only

| Call site | Default |
|---|---|
| `config/initializers/devise.rb:15` **(V)(R)** — governs **every Devise email** | `Chatwoot <accounts@chatwoot.com>` |
| `app/mailers/application_mailer.rb:4` **(R)** | `Chatwoot <accounts@chatwoot.com>` |
| `app/mailers/conversation_reply_mailer.rb:9` **(R)** | `Chatwoot <accounts@chatwoot.com>` |
| `app/presenters/mail_presenter.rb:178` **(R)** | `Chatwoot <accounts@chatwoot.com>` |
| `app/models/concerns/email_address_parseable.rb:13` **(V)(R)** | bare `accounts@chatwoot.com` |
| `app/models/account.rb:156` **(V)(R)** | falls back to `MAILER_SUPPORT_EMAIL` |
| `.env.example:86` **(R)** | documents the Chatwoot default |

The first audit missed the Devise initializer and the concern. `MAILER_SENDER_EMAIL` is **not** an `InstallationConfig`
key — `config/installation_config.yml` declares `MAILER_INBOUND_EMAIL_DOMAIN` (`:100`) and `MAILER_SUPPORT_EMAIL`
(`:105`) but not this one — so it is unreachable from Super Admin and invisible to an operator who does not read the
source. **NEW PRIMITIVE REQUIRED**: an `InstallationConfig` key for the sender identity (a row, not a migration;
pending approval). Until then, setting the ENV var in every environment is mandatory, not optional.

### 8.4 `BRAND_URL` reaches the browser and no SPA code can read it

`BRAND_URL` is in `GLOBAL_CONFIG_KEYS` (`app/controllers/dashboard_controller.rb:12`) and is therefore serialised into
`window.globalConfig` on every page — but it is **never destructured** in
`app/javascript/shared/store/globalConfig.js:4-30`, which pulls `WIDGET_BRAND_URL` (`:24`) and not `BRAND_URL` **(R)**.
`rg brandURL app/javascript` returns **zero** hits **(R)**. It is consumed only server-side
(`app/mailers/application_mailer.rb:15,57`, `app/views/layouts/mailer/base.liquid:97`,
`app/controllers/public/api/v1/portals/base_controller.rb:78`, `_footer.html.erb:14`).

**Recommendation — PATCH, one line**, either direction: destructure it if the SPA should link the brand, or drop it from
`GLOBAL_CONFIG_KEYS` if not. Shipping a value to the browser that nothing can read is a trap for the next developer who
assumes it works.

---

## 9. Hard-coded user-visible literals worth fixing, enumerated

Against the ten config keys, the genuinely hard-coded runtime surface is small and finite. All **REPLACE**.

| Surface | Location | Who sees it |
|---|---|---|
| MFA/TOTP issuer `'Chatwoot'` | `app/services/mfa/management_service.rb:26` **(R)** | Every agent, inside their authenticator app, permanently. Contrast `enterprise/app/models/account_saml_settings.rb:61`, which *does* read `INSTALLATION_NAME` — the mechanism exists and was simply not applied here. |
| SPA `<title>Lynomia Chat</title>` | `app/views/layouts/vueapp.html.erb:4` **(R)** | Everyone. Already Lynomia, but a **literal** — it will not follow a config change. |
| Session device label `'Chatwoot Mobile'` | `app/services/user_session_tracking_service.rb:88` | Agents, in the active-sessions list |
| Account-deletion email subjects (×2) | `app/mailers/administrator_notifications/account_notification_mailer.rb:3,15` **(R)** | Account admins |
| Account-deletion / compliance email bodies | `account_deletion_for_inactivity.liquid:3,7,19`; `account_deletion_user_initiated.liquid:3,14`; `account_compliance_mailer/account_deleted.liquid:3,6,30` | Account admins. The surrounding layout footer *is* config-driven; these bodies are not. |
| Twilio TwiML app `friendly_name` | `enterprise/app/services/twilio/voice_webhook_setup_service.rb:64` | The customer, inside their own Twilio console |
| Public help-centre domain error naming `support@chatwoot.com` | `app/controllers/public_controller.rb:16-19` | **Any anonymous visitor** hitting an unregistered custom domain |
| Campaign empty-state seed content: sender `'Chatwoot'`, *"Hi! Chatwoot here. Need help setting up?"*, `chatwoot.com/features/chatbot`, `chatwoot.com/pricings`, `chwt.app/g2-review` | `components-next/Campaigns/EmptyState/CampaignEmptyStateContent.js:20,45,63,65,70,117`; `LiveChatCampaignEmptyState.vue:27-30` | Every agent opening Campaigns. None of the three empty-state components imports `useBranding`. |
| Captain empty-state `product_name: 'Chatwoot'` + chatwoot.com `external_link`s | `captainEmptyStateContent.js:68,80,92,104,116,128` and `:146,162,178,194,210,226` | Agents. The sibling `document.name`/`response.*` fields *are* wrapped — the config and link fields are not. |
| Changelog feed + card links | `shared/constants/links.js:11` (`hub.2.chatwoot.com/changelogs`); `SidebarChangelogCard.vue:88` (`chatwoot.com/blog/${slug}`) | Agents. **Not brand-gated**: every dashboard load fetches Chatwoot's changelog and renders Chatwoot marketing cards. |
| Meta restriction status link | `dashboard/constants/globals.js:81-82` → 8 call sites | Agents, in Meta-channel restriction banners |
| Identity-validation "View docs" | `settings/inbox/settingsPage/ConfigurationPage.vue:304` | Agents |
| Help-centre paywall docs link | `dashboard/constants/globals.js:42-43` → `helpcenter/.../UpgradePage.vue:12` | Agents |
| Update banner → `github.com/chatwoot/chatwoot/releases` | `components/app/UpdateBanner.vue:76` | Admins (gated on `DISPLAY_MANIFEST`, which is `true`). The only user-visible `github.com/chatwoot` link. |
| DNS dialog printing `chatwoot.help` as the CNAME target | `helpCenter.json:937` → `DNSConfigurationDialog.vue:100-113` | Admins — and **actively wrong**: the real CNAME is computed at `:35-41`. The mailer does it correctly (`app/mailers/portal_instructions_mailer.rb:21-29`). |
| Super Admin / first-run onboarding copy | `super_admin/devise/sessions/new.html.erb:5,13,14`; `super_admin/application/_navigation.html.erb:27,29`; `installation/onboarding/index.html.erb:5,13,14,16` | Operators. Image `src`s are already the Lynomia assets; only text and `alt` are stale. |
| "Restart Chatwoot web and worker processes" flash (×2) | `app/controllers/super_admin/app_configs_controller.rb:108`; `installation_configs_controller.rb:76` | Operators |
| PWA manifest name / static favicon set | `public/manifest.json:2-3` (already Lynomia, not config-driven); `vueapp.html.erb:17-30` hard-codes `/apple-icon-*`, `/android-icon-*`, `/favicon-*`, `/ms-icon-144x144.png` | Everyone. Only the 512×512 icon at `:32` reads `LOGO_THUMBNAIL`. |
| Default bot avatar `chatwoot_bot.png` | `app/javascript/dashboard/assets/images/chatwoot_bot.png`, `public/assets/images/chatwoot_bot.png`; used at `widget/components/AgentMessage.vue:88`, `UnreadMessage.vue:54`, `ContactNoteItem.vue:63` | **End customers**, in the widget — the brand name is in the URL path, visible in devtools |
| `MOBILE_DEEP_LINK_BASE` default `'chatwootapp'` | `devise_overrides/omniauth_callbacks_controller.rb:39`; `enterprise/app/controllers/api/v1/auth_controller.rb:57` | Users, on mobile OAuth return. Not declared in `installation_config.yml`, so the first call **persists** `chatwootapp` as an editable row via `GlobalConfigService.load` (`lib/global_config_service.rb:1-21`). |
| Signup terms/privacy links | `en/signup.json:8`, rewritten at `v3/views/auth/signup/components/Signup/Form.vue:52-59` | **CONFIGURE, with two bugs**: `de/signup.json:8` uses `/terms-of-service` and the `.replace` matches the `/terms` prefix, yielding `<termsURL>-of-service`; `fa`, `he`, `lt` hold a mangled needle so they render a live link to `https://www.chatwoot.com/` |

Brand assets, for completeness: `public/brand-assets/logo.svg`, `logo_dark.svg` and `logo_thumbnail.svg` are
**byte-identical** (md5 `039d5aaecd8acbc2893977436e99de3f`, 12,631 bytes) **(V)**, so dark mode and the favicon get the
same artwork; and `lynomia-logo.png`, `lynomia-logo-dark.png`, `lynomia-icon.png` are tracked but **referenced by
nothing** (`rg 'lynomia-logo|lynomia-icon'` → 0) **(V)**. **UNVERIFIED:** I did not render the SVG, so I cannot confirm
the artwork is Lynomia's rather than a traced upstream mark. Confirm with design before treating logos as done.

---

## 10. Part 6.1 — do NOT mass-rename internal identifiers

**Explicit recommendation: DO NOT CREATE a rename of the 921 internal upstream identifier lines, nor of the 3,802
`woot`-derived identifiers.** They are contract surface, not copy:

| Family | Scale | What breaks if renamed |
|---|---|---|
| Widget SDK globals and DOM events (`window.$chatwoot` 75, `chatwootSettings` 85, `chatwootConfig` 90, `chatwootWebChannel` 49, `chatwootSDK` 6, `chatwoot:*` events 24) **(V)** | 192 runtime lines | **Every customer's embed snippet on their own website.** `inboxMgmt.json:1605` documents `window.chatwootSettings` to the customer — that string must stay. |
| `X-Chatwoot-*` headers | 141 occurrences, **18** distinct names **(V)** | Webhook signature verification in every customer integration (`lib/webhooks/trigger.rb:56-60`) |
| `@chatwoot/*` npm packages (5: `ninja-keys`, `prosemirror-schema`, `utils`, `viz`, `pico-search`) | 125–173 **(V)** | Third-party published packages — not ours to rename |
| `CHATWOOT_*` / `chatwoot_*` config and DB keys | 280 | Existing rows, env files and deploy tooling |
| Ruby/JS class names, `ChatwootApp`, `ChatwootHub`, `Woot<Pascal>` components (210), `woot-*` CSS classes (131), `woot_` (383) | 407 + 3,802 | Nothing user-facing. A rename is a repo-wide diff with zero product value and a guaranteed conflict with every upstream merge. |

The one consequence worth recording for the product owner: the `woot-widget` / `woot-elements` / `woot--` CSS classes
land in the *customer's own page DOM* via the embedded widget, so a sufficiently curious customer can identify the
upstream product from devtools. That is a disclosure fact to accept knowingly — **KEEP** — not a reason to rename.

---

## 11. Requirements that need approval (no migration proposed)

1. **Decide the EE overlay question.** §3 is fixable in one yml file. But `enterprise/LICENSE:1-34` binds use of the
   `enterprise/` overlay to the Chatwoot Subscription Terms and requires a valid Chatwoot Enterprise License, and
   `ChatwootApp.enterprise?` is true merely because the directory exists (`lib/chatwoot_app.rb:14-18`).
   **LEGAL_REVIEW, blocking**: whether to fix the reset, or to disable the overlay (`DISABLE_ENTERPRISE`), is a licensing
   decision before it is an engineering one.
2. **Telemetry and brand egress to `hub.2.chatwoot.com`.** `lib/chatwoot_hub.rb:3` with `/ping`, `/instances`,
   `/send_push`, `/events`, `/billing`; the payload includes installation host, version, edition and account/user/inbox/
   conversation/message counts (`:59-79`). Suppressible only via `DISABLE_TELEMETRY` for events/metrics; the base URL is
   overridable **only** in `Rails.env.development?` (`enterprise/lib/enterprise/chatwoot_hub.rb:5`). Push notifications
   are relayed through Chatwoot Inc. **LEGAL_REVIEW** + **REPLACE** (needs a production-overridable base URL — no
   mechanism exists today).
3. **Three new `InstallationConfig` keys** (rows in an existing table, no schema change, listed for approval not
   implementation): a docs/help base URL (§7), a mailer sender identity (§8.3), and an MFA/TOTP issuer (§9).
4. **`DISPLAY_MANIFEST` semantics.** It gates both the favicon/PWA block *and* the upgrade banner
   (`vueapp.html.erb:9-31`, `UpdateBanner.vue:35-43`). An operator turning it off to suppress the Chatwoot releases
   banner also loses the favicons. Worth splitting — **EXTEND** — but it is a product decision.

## 12. Stale docs to correct, and what I could not verify

| Doc | Status |
|---|---|
| `docs/chatwoot-upgrade/00-4.14-to-4.18-discovery.md:163` | Accurate on the Lynomia defaults but **incomplete in a way that matters**: it does not record the §3 reset, so it presents those defaults as durable when they are not. |
| `docs/ui-modernization/FINAL-CHECKPOINT.md:327` | Build-footer claim correct (`BuildInfo.vue:42`). MFA claim **conflates two mechanisms**: the MFA surfaces use the `{installationName}` placeholder and never import `useBranding`; the TOTP issuer is still the literal at `management_service.rb:26` and `mfa.json:113` is unwrapped. |
| `docs/whatsapp-business/README.md:26` | Only partly true. Leaking: `inboxMgmt.json:365`, `:439`, `:456`, `:1164` (twice in one string). |
| `docs/ui-modernization/audit/surface-campaigns.md:818-823` | **Still accurate, still unfixed.** Recorded here so the campaign empty-state finding is not double-counted as new work. |
| `docs/ui-modernization/audit/surface-settings-admin.md:868-869` | Partly out of date: `integrations.json:60` and `:168` are now wrapped. Still leaking: `:42`, `:95`, `:270`. |

**UNVERIFIED / carried risks.** (a) The §3 execution on a live deployment (see §3.4). (b) The covered/uncovered EN i18n
split is per call site and derived by hand; treat any key not cited with *both* a locale line and a component line as
unverified — and per §2.2 a key can be both. (c) `integrations.json:20`
(`INTEGRATION_SETTINGS.SHOPIFY.HELP_TEXT.BODY`) looks dead by grep, but a dynamically built i18n key would evade that
grep — confirm before deleting rather than rewriting. (d) The logo artwork (§9). (e) Swagger's non-reachability rests on
`swagger_controller.rb:3-12`; if an external pipeline publishes the OpenAPI JSON, those 169 occurrences are user-facing
after all. (f) One binary (`app/javascript/shared/assets/audio/ding.mp3`) matches on a byte sequence and contributes a
false positive to the 8,302 total; the error is one occurrence, but other binaries could contribute similarly.
