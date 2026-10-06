# P1 — Lynomia branding foundation: audit output

Branch `claude/practical-thompson-9xfqed`. Phase base `87ef8f76`.

Sources: `docs/product-enablement/07-branding-audit.md` (discovery), plus a re-verification of every claim
against the working HEAD. Where the discovery and HEAD disagree, HEAD wins and the correction is recorded
below — the discovery doc was written against `6c381e96` and several of its line numbers and gating claims are
stale.

---

## 1. The branding revert — root cause and fix

**Root cause.** `enterprise/config/premium_installation_config.yml` still carried the upstream branding
(`INSTALLATION_NAME`/`BRAND_NAME` = `'Chatwoot'`, `BRAND_URL`/`WIDGET_BRAND_URL` = `https://www.chatwoot.com`,
`TERMS_URL` = `…/terms-of-service`, `PRIVACY_URL` = `…/privacy-policy`). The chain:

```
config/schedule.yml
  → Internal::TriggerDailyScheduledItemsJob:23
    → Internal::CheckNewVersionsJob:20
      → Enterprise::Internal::CheckNewVersionsJob:27-29   (prepended; ChatwootApp.extensions includes 'enterprise')
        → Internal::ReconcilePlanConfigService#perform:4   return if ChatwootHub.pricing_plan != 'community'
          → #reconcile_premium_config:38-46                update! every key in the overlay
```

`ChatwootHub.pricing_plan` reads `INSTALLATION_PRICING_PLAN`, whose seeded default is `'community'`
(`config/installation_config.yml`), so the guard does not fire. The same path is reachable on demand from
Super Admin → Settings without cron or any network call. Every run rewrote the live `InstallationConfig` rows
back to the upstream values and set `CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING`, which renders the
"Unauthorized premium changes detected" banner. The rebrand that set the Lynomia values in
`config/installation_config.yml` never touched the overlay.

**Severity beyond the name.** `isACustomBrandedInstance` is the literal test
`installationName !== 'Chatwoot'` (`app/javascript/shared/store/globalConfig.js`). Resetting
`INSTALLATION_NAME` therefore un-suppressed roughly forty upstream help, docs and changelog links at once,
including the widget and survey "Powered by" footer shown to end customers.

**Fix.** The overlay now holds the same ten values as the branding block in `config/installation_config.yml`.
`#reconcile_premium_config:42` skips any key whose stored value already equals its own, so the service has
nothing to write: `ConfigLoader` is the single authoritative writer by construction, not by a guard, and no
second job was added to undo the first. `reconcile_premium_features` / `premium_features.yml` — the licence
enforcement side — is untouched, so plan gating still behaves exactly as before.

`DOCUMENTATION_URL`, `SUPPORT_URL` and `CHANGELOG_URL` are deliberately **absent** from the overlay. Listing
them would make the plan reconcile overwrite an operator's configured links, which is the defect itself.

**Regression coverage** (`spec/enterprise/services/internal/reconcile_plan_config_service_spec.rb`):
- `leaves the branding seeded from the installation config in place` — seed through `ConfigLoader`, run the
  reconcile, assert every branding row is unchanged and no reset warning is raised. Proven to fail (3 of 8
  examples) when the overlay is reverted to `'Chatwoot'`.
- the two examples that previously asserted the reset to `'Chatwoot'` now read the expected values from
  `config/installation_config.yml`, so they still verify that a *tampered* value is reset — to the
  installation's own branding.

---

## 2. Canonical brand configuration

Everything below is one `InstallationConfig` row, editable in Super Admin → Installation Configs, read through
`GlobalConfig` on the server and `window.globalConfig` in the browser.

| Identity | Key | Status |
|---|---|---|
| Product name | `INSTALLATION_NAME` | existing |
| Email/widget brand name | `BRAND_NAME` | existing |
| Logo (light / dark) | `LOGO`, `LOGO_DARK` | existing |
| Favicon / PWA icon | `LOGO_THUMBNAIL` | existing |
| Website | `BRAND_URL` | existing |
| Widget "Powered by" | `WIDGET_BRAND_URL` | existing |
| Terms | `TERMS_URL` | existing |
| Privacy | `PRIVACY_URL` | existing |
| Installation metadata (favicons, manifest, upgrade banner) | `DISPLAY_MANIFEST` | existing |
| **Documentation** | `DOCUMENTATION_URL` | **new, blank** |
| **Support / status / community** | `SUPPORT_URL` | **new, blank** |
| **Changelog** | `CHANGELOG_URL` | **new, blank** |

The three new keys ship to the dashboard through the existing
`DashboardController::GLOBAL_CONFIG_KEYS` → `window.globalConfig` → `shared/store/globalConfig.js` path, and
to Liquid mail templates through `ApplicationMailer#liquid_locals`. Blank means **render no link** — nothing
points at a Lynomia destination that does not exist yet, which is the brief's constraint on placeholders.

Two shared accessors, both on the existing `shared/composables/useBranding`:
- `installationName` — for i18n strings carrying an `{installationName}` placeholder.
- `brandLink(kind, upstreamUrl)` — `'documentation' | 'support' | 'changelog'`. Returns `upstreamUrl`
  unchanged on an installation that has not been rebranded, the configured link on a branded one, and `''`
  when a branded installation has configured none.
Server side: `SuperAdmin::BrandingHelper#brand_support_url` and `#application_title`.

### Mechanism note, verified not assumed

The global `postTranslation` shortcut was tested and **ruled out**. vue-i18n 9.14.5 strips an unsupplied
named placeholder to an empty string *before* `postTranslation` runs:

```
messages: { A: 'The store rejected {installationName} credentials.' }
t('A')  →  "The store rejected  credentials."
```

A global hook would therefore have rendered a gap at 30 user-facing sites. `%{x}` is stripped the same way;
only non-vue-i18n tokens such as `{{x}}` survive the compiler. The parameter is consequently supplied per
call site, which is the convention the onboarding, integrations and MFA copy already use, and every renderer
is covered by a test.

---

## 3. Hard-coded Lynomia literals — CONFIGURE / KEEP

Reviewed: **~170 case-insensitive occurrences**, after excluding the "po*lynomia*l" grep trap (≈9 hits in
`vendor/bundle`, the help-centre article jobs and `webmOpusToOgg.js`). The brief's "~34" came from a
discovery table that was internally inconsistent with its own §8.1, which summed to 55.

### CONFIGURE — 38 occurrences, done

| Area | Count | Treatment |
|---|---|---|
| `i18n/locale/en/commerce.json` | 28 | `{installationName}`, supplied by 7 renderers + `useCommerceLabels` |
| `i18n/locale/en/automation.json` `COMMERCE_TRIGGER_NOTE` | 1 | `{installationName}` from `AutomationRuleForm.vue` |
| `i18n/locale/en/contactFilters.json` `AUDIENCE.COMMERCE_NOTE` | 1 | `{installationName}` from `ContactsFilter.vue` |
| `config/locales/en.yml` `automation.lynomia.extensions_disabled` | 1 | `%{installation_name}` from `Custom::AutomationRule#extensions_disabled_error` |
| `app/views/layouts/vueapp.html.erb` `<title>Lynomia Chat</title>` | 1 | `@global_config['INSTALLATION_NAME']` |
| `public/manifest.json` `name` / `short_name` | 2 | rendered route `GET /manifest.json` → `WebManifestController` |
| `config/installation_config.yml` `<your Lynomia URL>` ×2, `display_title: 'Lynomia Metadata'` | 3 | genericized to "your installation URL" / "Installation Metadata"; its own description said "Chatwoot metadata" on the same row and now matches |
| `app/views/super_admin/devise/sessions/new.html.erb`, `installation/onboarding/index.html.erb` `SuperAdmin \| Chatwoot` | 2 (Chatwoot side) | `GlobalConfig.get_value('INSTALLATION_NAME')` |

`i18n/locale/en/commerce.json` now contains **zero** `Lynomia` literals and 27 `{installationName}`
placeholders (one line carries two).

### KEEP — with the reason for each

| Item | Count | Why |
|---|---|---|
| `config/features.yml` `display_name: Lynomia Commerce` / `Lynomia Flow Builder` | 2 | Human label of a feature flag whose machine name is `lynomia_commerce` / `lynomia_flow_builder` (mirrored at `featureFlags.js`). Interpolating the installation name would render "Lynomia chat Commerce" — the module is a proper noun, not the installation. |
| `app/helpers/super_admin/features.yml` "Lynomia Commerce" ×4 | 4 | Same proper noun, in the Super Admin config-group titles and descriptions. |
| `config/installation_config.yml` "Lynomia Commerce" in Commerce descriptions | 6 | Same proper noun. |
| `config/installation_config.yml` YAML comments mentioning Lynomia | 9 | Render nowhere. (Corrects the discovery, which counted all 17 matching lines as "help text".) |
| `custom/app/views/fields/billing_plan_limits_field/_form.html.erb` | 1 | Feature-module name. |
| `custom/app/views/super_admin/billing_plans/settings.html.erb` `lynomia://billing` | 1 | Mobile deep-link URI scheme — a machine-readable identifier registered in the native app. Renaming breaks the mobile billing return. |
| `i18n/locale/en/automation.json` `"LYNOMIA": {` and `config/locales/en.yml` `lynomia:` | 2 | i18n **key names**, consumed at 18 call sites. Not rendered; renaming is pure cost. |
| Config *values* — `INSTALLATION_NAME`, `BRAND_NAME`, `BRAND_URL`, `WIDGET_BRAND_URL`, `TERMS_URL`, `PRIVACY_URL` | 6 | These **are** the configuration the CONFIGURE cases read from. |
| `custom/app/services/commerce/providers/woocommerce.rb` `WEBHOOK_NAME`, `commerce/http_client.rb` `USER_AGENT` | 2 | Integration identifiers. The webhook name is how the code recognises its own webhooks on re-registration; making it per-installation would orphan existing webhooks. |
| Shopify `staffNote` / `note`, WooCommerce refund `reason` | 3 | Brand text a merchant reads in their store admin, but written into immutable third-party records — a later rename cannot fix history. Decision recorded rather than made configurable. |
| `settings/billing/Index.vue` `https://lynomia.com/admin/subscriptions/${accountId}` | 1 | The Lynomia platform's own billing service endpoint, the same class as `hub.2.chatwoot.com`. The brief says not to touch live upstream service dependencies unless the dependency itself is being replaced. **Flagged** — see §9. |
| GraphQL operation names, server log tags, Ruby class/constant names, JS identifiers, a localStorage key, source comments, Shopify test fixtures | ~75 | Wire-level or internal identifiers, invisible to any user. |

### Non-English locales — not touched, flagged

35 hand-edited Lynomia literals exist in `ar/commerce.json` (28), `ar/automation.json` (2),
`ar/contactFilters.json` (1), `ar/conversation.json` (1) and `config/locales/ar.yml` (3). CLAUDE.md assigns
non-English locales to Crowdin, so they are left alone. Until Crowdin picks up the new `{installationName}`
placeholders, Arabic renders the literal brand name.

`ar/conversation.json` `NATIVE_APP_ADVISORY` is the instructive case: the same key, the same renderer
(`components-next/message/Message.vue`, wrapped in `replaceInstallationName`), renders correctly in English —
because the English string says "Chatwoot" and the `/chatwoot/gi` regex matches it — and is frozen in Arabic,
because the Arabic string already says "Lynomia Chat" and the regex cannot match. See §9.

---

## 4. User-facing Chatwoot references — classification

### REPLACE / CONFIGURE — done

| Surface | What changed |
|---|---|
| Dashboard page title | `<title>` reads `INSTALLATION_NAME` |
| PWA manifest `name` / `short_name` | rendered from `INSTALLATION_NAME` |
| Super Admin page titles | `SuperAdmin::BrandingHelper#application_title` overrides Administrate's Rails-module-name default; the two hard-coded `SuperAdmin \| Chatwoot` titles read config |
| Update banner | `GENERAL_SETTINGS.UPDATE_CHATWOOT` now goes through `replaceInstallationName`, the same treatment the build-info panel already gave the same key |
| Portal DNS configuration dialog | sentence interpolates the installation's help-centre host instead of naming `chatwoot.help` — it contradicted the copyable CNAME value directly beneath it |
| Help-centre category slug help text | worked example interpolates the installation's host instead of `app.chatwoot.com` |
| Account-deletion (user-initiated and inactivity) and compliance emails, and their subjects | read `BRAND_NAME`; the support line follows `SUPPORT_URL` or is omitted |
| Unregistered custom-domain 401 body | points at the installation's administrator instead of `support@chatwoot.com` |
| Captain document empty-state sample cards | `example.com` instead of six real upstream help-centre article URLs |
| Sample SMS campaign body | `example.com/feedback` instead of a G2 review solicitation for the upstream product |
| Super Admin "Community Support" button | follows `SUPPORT_URL`; hidden when unset, instead of linking to upstream's Discord |
| Sidebar Docs and Changelog | follow `DOCUMENTATION_URL` / `CHANGELOG_URL`; previously hidden outright on a branded installation, leaving no route to either |
| Inbox identity-validation "View docs", WhatsApp manual-migration guide ×2, WhatsApp business-management-token guide, Meta restriction status link ×6 | `brandLink` |

### Already correct — verified, no change needed

| Surface | Mechanism |
|---|---|
| Login title "Login to Chatwoot" | already wrapped in `replaceInstallationName` → renders the installation name |
| Signup heading | `REGISTER.GET_STARTED` ("…with Chatwoot") only renders when `isAChatwootInstance`; a branded install gets `REGISTER.TRY_WOOT` ("Create an account") |
| Signup testimonials (`testimonials.cdn.chatwoot.com`) | `<Testimonials v-if="isAChatwootInstance">` — never mounted, never fetched. **Corrects the discovery**, which reported this as ungated. |
| Help-centre upgrade page docs button | inside `v-if="isOnChatwootCloud"` — not rendered on a self-hosted install. **Corrects the discovery**, which reported this as ungated. |
| Confirmation / invite emails | already read `BRAND_NAME` |
| Password reset, password change, unlock emails | brand-neutral copy |
| Widget, survey and portal footers, terms and privacy links | already read `WIDGET_BRAND_URL` / `BRAND_URL` / `TERMS_URL` / `PRIVACY_URL` |
| `featureHelper.js` (26 links), `config/features.yml` `help_url` (13), Captain feature spotlights (7), campaign empty-state `trigger_rules` (3), `globals.js` `DOCS_URL` | suppressed by `CustomBrandPolicyWrapper` / `isOnChatwootCloud`, or dead with no reader at all |

### KEEP INTERNAL — no renames performed

Ruby modules and classes (`ChatwootApp`, `ChatwootHub`, `ChatwootMarkdownRenderer`,
`ChatwootExceptionTracker`, …), internal routes, database tables, migration names, package identifiers,
`window.chatwootConfig`, the `woot-` CSS and Tailwind token prefixes, `$chatwoot` widget SDK globals, Redis
key names such as `CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING`, the `CW_*` environment variables, and source
comments referencing upstream issues and commits.

### LEGAL / LICENSE — KEEP

`LICENSE`, `enterprise/LICENSE` (including the `chatwoot.com/terms-of-service` reference in its text), every
copyright notice, and the upstream attribution in `README.md` and `docs/`. Nothing was removed. The
`sales@chatwoot.com` address in the Super Admin premium-reset banner is part of that licence-enforcement
surface and is kept — and after §1 that banner no longer triggers on this installation.

### DEVELOPER-ONLY — KEEP

`chwt.app/dev/ms` in the Azure app-config help text, `chwt.app/v4/migration` in a migration's raise message,
`chwt.app/heroku-slug-size` in a rake comment, the 13 `github.com/chatwoot/chatwoot/...` references in source
comments, and the `MAILER_SENDER_EMAIL` default — see §9.

---

## 5. External links — classification

387 runtime occurrences across 10 distinct Chatwoot-owned hosts were classified. 280 were already invisible
(suppressed by brand or cloud gating) or dead (no reader). The visible residue was 17 items; each is resolved
below.

| Class | Items | Action |
|---|---|---|
| PRODUCT HELP | Captain doc samples ×6, category slug example, DNS dialog host, WhatsApp migration guide ×2, WhatsApp token guide | genericized or routed through `DOCUMENTATION_URL` |
| DOCUMENTATION | identity-validation SDK docs, help-centre docs constant | `DOCUMENTATION_URL`; the second was already cloud-gated |
| CHANGELOG | sidebar changelog entry, changelog blog link, `hub.2.chatwoot.com/changelogs` feed | sidebar follows `CHANGELOG_URL`; the feed and blog link stay, already suppressed by `isOnChatwootCloud && !isACustomBrandedInstance` |
| SUPPORT | `status.chatwoot.com/incidents` (6 consumers), Super Admin Discord, `support@chatwoot.com`, `hello@chatwoot.com` | `SUPPORT_URL`, or genericized |
| WEBSITE | `testimonials.cdn.chatwoot.com`, `chwt.app/g2-review`, campaign `trigger_rules` hosts | already gated, or replaced with `example.com` sample copy |
| UPSTREAM DEPENDENCY | `hub.2.chatwoot.com` (6 endpoints: `/ping`, `/instances`, `/send_push`, `/events`, `/billing`, `/changelogs`), `github.com/chatwoot/chatwoot/releases` in the update banner, `app.chatwoot.com` as the `FRONTEND_URL` fallback in push test | **not replaced.** These are live service endpoints and the actual location of upstream releases. |
| LEGAL | signup terms/privacy URL rewrite, `enterprise/LICENSE` | **not replaced.** The signup rewrite (`Form.vue` replacing the two literal upstream URLs with `termsURL`/`privacyURL`) is brittle but currently correct in all 57 locale files; it will break the day Crowdin localizes one of those two `href` values. Flagged, not rewritten. |
| DEVELOPER | `chwt.app/dev/ms`, `chwt.app/v4/migration`, `chwt.app/heroku-slug-size`, 13 source comments, `zh/inboxMgmt.json` domain example | **not replaced** |

`brandLink` is now called at 12 sites. The frontend `CHANGELOG_API_URL` literal
(`shared/constants/links.js`) does not derive from `ChatwootHub.base_url`, so the two hub hosts can drift
independently — recorded, not changed, since it is an upstream dependency.

---

## 6. Auth / email / PWA verification

| Surface | Result |
|---|---|
| Login | installation name (existing `replaceInstallationName`) ✔ |
| Signup | installation-aware heading, testimonials not mounted ✔ |
| Password reset / change / unlock | brand-neutral ✔ |
| Invite / confirmation email | `BRAND_NAME` ✔ |
| Account-deletion and compliance emails | `BRAND_NAME` + `SUPPORT_URL` ✔ (changed) |
| Mail layout "Powered by" | `BRAND_NAME` / `BRAND_URL` ✔ |
| Browser title | `INSTALLATION_NAME` ✔ (changed) |
| Favicon | `LOGO_THUMBNAIL` ✔ |
| PWA manifest | rendered from `INSTALLATION_NAME` ✔ (changed) |
| Meta description | already interpolated `INSTALLATION_NAME` ✔ |
| Onboarding | `{installationName}` placeholders already in use ✔ |
| Error pages (404/422/500) | brand-neutral ✔ |
| Support / help links | `SUPPORT_URL` / `DOCUMENTATION_URL` ✔ (changed) |

---

## 7. Tests added

| Test | What it proves |
|---|---|
| `shared/composables/specs/useBranding.spec.js` (+7) | `installationName` is exposed; `brandLink` keeps the upstream link on an unbranded install, returns the configured link on a branded one, and returns `''` — never the upstream link — when nothing is configured or globalConfig is missing |
| 11 commerce spec files | every branded renderer substitutes a deliberately unbranded test name (`Acme Desk`), so the assertions prove the substitution rather than restating the current brand |
| `spec/controllers/dashboard_controller_spec.rb` (+2) | the page title is the installation name; the three link keys reach the browser |
| `spec/controllers/web_manifest_controller_spec.rb` (new) | the manifest is named after the installation, short name derived, icon set and display options preserved |
| `spec/helpers/super_admin/branding_helper_spec.rb` (new) | Super Admin title reads config; `brand_support_url` keeps upstream unbranded, uses config when branded, returns nil when unset |
| `spec/enterprise/services/internal/reconcile_plan_config_service_spec.rb` (+1, 2 repointed) | branding survives the reconcile lifecycle; a tampered value is still reset to the installation's own branding |
| `spec/services/automation_rules/conditions_filter_service_audience_spec.rb` (+1) | the backend refusal message names the installation |

No repository-wide "grep must be zero" test was added — internal upstream identifiers are intentionally
retained, so such a test would be false by construction.

---

## 8. Counts

| Metric | Value |
|---|---|
| Lynomia literals reviewed | ~170 (excluding the "polynomial" grep trap) |
| Lynomia literals moved to configuration | 38 |
| Lynomia literals deliberately kept | ~110 (identifiers, log tags, GraphQL names, comments) + 9 YAML comments + 6 config values + 16 feature/module proper nouns + 5 store-side integration identifiers |
| Chatwoot runtime occurrences classified | 387 |
| Already invisible or dead before this phase | 280 |
| User-facing occurrences replaced or configured | 29 |
| Intentionally retained — internal | all module/route/table/migration/package identifiers; no renames |
| Intentionally retained — legal | `LICENSE`, `enterprise/LICENSE`, copyright notices, upstream attribution, the licence-banner contact address |
| Intentionally retained — developer | 3 `chwt.app` operator links, 13 source comments, 1 stale `zh` translation |
| Intentionally retained — upstream dependency | 6 `hub.2.chatwoot.com` endpoints, the GitHub releases link, the push-test `FRONTEND_URL` fallback |
| New configuration keys | 3 |
| Migrations | 0 |

---

## 9. Unresolved — for the brand owner, not code

1. ~~**Casing.**~~ **Resolved in P2.** `INSTALLATION_NAME` and `BRAND_NAME` are now `'Lynomia Chat'` in
   `config/installation_config.yml`, mirrored in the enterprise overlay so the plan reconcile stays a
   non-writer. Note the reach of that change, verified by running `ConfigLoader` both ways: a **fresh**
   installation seeds `"Lynomia Chat"`, but an **existing** installation whose row already holds
   `"Lynomia chat"` keeps it, because `ConfigLoader` defaults to `reconcile_only_new: true` and both callers
   pass no arguments. On a running installation the row is the source of truth and an operator updates it in
   Super Admin → Installation Configs. No data migration was written for this: a second writer of branding is
   exactly what §1 removed.
2. **`MAILER_SENDER_EMAIL`** defaults to `Chatwoot <accounts@chatwoot.com>` in five places. In production the
   operator sets this ENV variable; if it is unset, outbound mail carries the upstream brand in the `From:`
   header. This is already configuration, so it is an operator action, not a code change.
3. **Destinations.** `DOCUMENTATION_URL`, `SUPPORT_URL` and `CHANGELOG_URL` ship blank, which hides every
   corresponding link. They need real Lynomia destinations before those links return.
4. **Arabic locale drift.** 35 hand-edited Lynomia literals in `ar/*` bypass the branding mechanism, and
   `ar/conversation.json` `NATIVE_APP_ADVISORY` cannot track `INSTALLATION_NAME` at all because it already
   contains the brand name that `replaceInstallationName` is looking to replace. Owned by the translation
   process, not by this phase.

   **Narrowed in P2, with a count.** The damaging subset is the strings where the English **does** take
   `{installationName}` and the Arabic hardcodes the brand instead, so the two languages disagree on a
   white-labelled install. There are **28** of them: 26 in `ar/commerce.json`, one in `ar/automation.json`
   (`AUTOMATION.LYNOMIA.COMMERCE_TRIGGER_NOTE`), and one in `ar/contactFilters.json`
   (`CONTACTS_FILTER.AUDIENCE.COMMERCE_NOTE`). P2 fixed the last of these, because it sits on a surface P2 owns,
   and left the other 27 for a branding phase rather than widening this one. The full list is reproducible by
   comparing `{installationName}` between each `en/*.json` and its Arabic sibling.

   A locale-parity gate now exists, scoped to the audience blocks
   (`components-next/audience/specs/audienceCopy.spec.js`): same keys in both languages, same placeholder set per
   string, and an Arabic plural the renderer can actually use. It is deliberately not repository-wide — a gate
   that fails on 27 pre-existing strings gets switched off instead of fixed.
5. **Billing portal host.** `settings/billing/Index.vue` redirects to `https://lynomia.com/admin/...`. Treated
   as a service endpoint and kept. If that host is ever meant to vary per installation, it needs a config key.
6. **`chwt.app` shortlink liveness.** Whether the retained `chwt.app` and `www.chatwoot.com/hc/...` targets
   still resolve was not verified; no outbound requests were made.

---

## 10. Verification

### Test and build gates

| Gate | Result |
|---|---|
| Full RSpec | 10,601 examples, **2 failures**, 67 pending |
| Full Vitest | 481 files, **5,024 tests, 0 failures** |
| ESLint (41 changed JS/Vue) | **0 errors** (8 pre-existing `no-dynamic-keys` warnings) |
| RuboCop (changed Ruby) | **0 offenses** |
| Production build (`assets:precompile`) | **exit 0**, assets emitted in 1m24s |
| Migrations added | **0** |

Both RSpec failures were reproduced at the phase base `87ef8f76` and are not regressions:

- `spec/builders/agent_builder_spec.rb:47` — reproduced at base by running `spec/actions spec/assets spec/builders` (300 examples, 1 failure, identical message). Cross-example ActiveJob queue pollution: a leftover `Devise::Mailer#confirmation_instructions` job with zero arguments. Passes in isolation at base and at HEAD.
- `spec/enterprise/services/voice/call_transcription_service_spec.rb:77` — reproduced at base in isolation (19 examples, 1 failure, identical message). `Message` does not implement `reindex` for the verified double.

Three failures in the first full run **were** this phase's and are fixed: `inboxes_whatsapp_credentials_spec.rb` pinned its WebMock stubs to `graph.facebook.com/v14.0`, the version removed by the Graph centralization, so the PATCH reached an unstubbed request and the controller answered 500. The file writes the host as an escaped regex, which the literal-string sweep over the other eleven spec files did not match.

### End-to-end check on a running installation

Booted in `RAILS_ENV=production` with precompiled assets against a database created and seeded from scratch, to verify a fresh install rather than a mutated one.

Seeded configuration: `INSTALLATION_NAME` and `BRAND_NAME` = `Lynomia chat`; `DOCUMENTATION_URL`, `SUPPORT_URL`, `CHANGELOG_URL` = `""`.

| Surface | Observed |
|---|---|
| `GET /manifest.json` | `{"name": "Lynomia chat", "short_name": "Lynomia", …}`, `content-type: application/manifest+json` |
| `GET /app/login` `<title>` | `Lynomia chat` |
| `window.globalConfig` | `INSTALLATION_NAME: "Lynomia chat"`, the three link keys present and empty |
| Favicon / manifest links | `LOGO_THUMBNAIL`, `/manifest.json` — both intact |
| Super Admin onboarding `<title>` | `SuperAdmin | Lynomia chat` (was the hard-coded `SuperAdmin | Chatwoot`) |

### Browser check

Chromium, four combinations (1440×900 and 390×844, each under `en-US` and `ar-SA`):

| Check | Result |
|---|---|
| Page title | `Lynomia chat` in all four |
| Horizontal overflow at 390px | none |
| Controls present | email and password inputs, submit button, Privacy and Terms links |
| User-visible "Chatwoot" in page text | **none** |
| Page and console errors | **none** |

The rendered copy reads "Login to Lynomia chat" / "Sign in to continue to Lynomia chat" — the `replaceInstallationName` path working end to end.

**One honest limit on the RTL result.** `#app[dir]` stayed `ltr` in all four runs, including with `DEFAULT_LOCALE=ar`, because the dashboard derives direction from the signed-in account's locale, which does not exist on the unauthenticated login page. So that route cannot exercise RTL and the authenticated RTL surface was not re-driven in a browser this phase. What is established instead: the P1 diff changes **zero** `class` attributes, **zero** `ltr:`/`rtl:`/physical/logical direction utilities, **zero** responsive variants and **zero** `aria-*`, `role`, `tabindex` or `<label>` attributes, so there is no mechanism by which it could alter direction, breakpoint or accessible-name behaviour. The Arabic-locale pages rendered without error or overflow.

### Controls

No product control was removed. One link was: the Super Admin "Community Support" button, which pointed at upstream's Discord server. It renders again as soon as `SUPPORT_URL` is set, through the same suppression mechanism the codebase already applies to the forty upstream help links behind `CustomBrandPolicyWrapper`. The sidebar Docs and Changelog entries were already hidden on a branded installation and are now reachable once their keys are configured, so that surface gains a route rather than losing one.
