# 13 — Branding cleanup

The user-facing brand backlog P0 and P1 deferred, closed or classified. Each item was re-verified against the code
rather than taken from the earlier audit, which is older than the code and was wrong in three places.

---

## 1. What "done" means here

P4 §39 sets the goal and its limit:

> Goal: customers experience LYNOMIA CHAT. Do NOT require internal source identifiers to reach zero.

So the test applied to every finding is: **can a customer or an operator read this?** A class name, a package name, a
database column, a developer-only story fixture and a licence-enforcement banner all stay. A sentence, a link, an
alt text, an email From line and a sample message do not.

## 2. Closed in this phase

| Item | Where | What was wrong | What it does now |
|---|---|---|---|
| **"Howdy, Welcome to Chatwoot"** | `app/views/installation/onboarding/index.html.erb:16` | the very first screen of a fresh install named the upstream project | reads the installation's own name, through the helper P1 already built |
| **Logo alt text ×4** | the same file `:13-14`, `super_admin/devise/sessions/new.html.erb:13-14` | an accessible name read aloud by a screen reader | the installation's own name |
| **DOCUMENTATION_URL / CHANGELOG_URL blank** | `config/installation_config.yml` | P1 added the keys; they shipped empty, so ~20 help, documentation and changelog links resolved to **nothing** | `/docs` and `/changelog` — this installation's own, with no deployment step |
| **25 "Learn more" links** | `app/javascript/dashboard/helper/featureHelper.js` | every one resolved to `chwt.app` | each resolves to its own documentation article, or renders no link where there is no article yet. An unbranded installation keeps the upstream destination |
| **27 Arabic strings hard-coding "Lynomia"** | `ar/commerce.json` (26), `ar/automation.json` | their English siblings carried `{installationName}`, so only Arabic would have shown the wrong name on a differently branded install | the placeholder, in both languages |
| **A brand hard-coded in BOTH languages ×2** | `whatsappTemplateMgmt.json`, `conversation.json` | one is a regression this project introduced in P3; the other went through `replaceInstallationName`, which matches `/chatwoot/gi` and so could never touch the Arabic | one placeholder that works in either language, supplied at both renderers |
| **Campaigns empty state** | `CampaignEmptyStateContent.js:63,65` | the sample campaigns were signed *"Hi! Chatwoot here"* — the product appearing to message the visitor | signed by the fictional business the rest of the sample already uses |
| **Mailer fallback sender** | `app/mailers/application_mailer.rb:4` | `Chatwoot <accounts@chatwoot.com>` in a customer's mail client whenever `MAILER_SENDER_EMAIL` was unset | the display name is the installation's own. The address stays a deployment setting, because inventing one would be worse |
| **13 dead `chwt.app` help URLs in every page's source** | `config/features.yml` → `ApplicationHelper#feature_help_urls` → `window.chatwootConfig.helpUrls` | emitted into every dashboard page and read by **nothing** in `app/javascript` | removed, helper and all |

## 3. Classified and deliberately kept

Each of these was checked individually; none is reachable by a customer.

| Item | Class | Why it stays |
|---|---|---|
| `REPLY_POLICY` → developers.facebook.com / twilio.com | **upstream technical dependency** | these are the providers' own policy pages, linked from the 24-hour-window banner. They are correct, and replacing them with Lynomia pages would be substituting our summary for the provider's rule |
| `CHANGELOG_API_URL` → `hub.2.chatwoot.com` | **upstream technical dependency, inert here** | read only by the sidebar changelog card, which is gated on `isOnChatwootCloud && !isACustomBrandedInstance` and therefore never mounts on this installation. Setting `CHANGELOG_URL` does not change that gate, so no upstream feed appears |
| `AZURE_APP_ID` help text and five more in `installation_config.yml` | **developer / operator** | seen only by an operator in Super Admin → Installation Configs |
| Captain empty-state links ×7 | **not applicable** | AI is out of this phase; the feature is not documented, so there is no destination to point at |
| `super_admin/settings/show.html.erb:20` licence banner | **legal** | it is the licence-enforcement notice. Rewording it would misrepresent what it enforces |
| Signup terms sentence | **legal** | already replaced at render time with the configured `TERMS_URL` / `PRIVACY_URL` |
| `twilio-templates.js` sample content | **developer-facing** | reachable only from `.story.vue` files, which are not in the dashboard bundle |
| Class names, package names, database columns, `Chatwoot.config` | **internal identifier** | P4 §39 explicitly does not require these to reach zero |

## 4. Support — P4 §27, answered

**`SUPPORT_URL` is left blank, deliberately.** The brief says not to invent a support destination, and this
installation has none: there is no support inbox, no support address and no help desk configured anywhere in the
repository. The branding mechanism already handles that correctly — `brandLink('support')` returns an empty string
and every caller renders no link — so a blank value hides the support links rather than pointing them somewhere
wrong. **It is not pointed back at upstream support.**

When a real Lynomia support destination exists, setting that one config key turns every support link on at once.

## 5. Arabic coverage — P4 §16.3

An earlier pass in this phase counted these by **namespace** — a whole locale file was "ours" or "upstream's" — and
reported 62 ours and 204 upstream's. That rule is wrong, because this project added keys *into* upstream namespaces
(pagination controls in `components.json`, bulk-action copy in `contact.json`, sidebar groups in `settings.json`) and
those keys are ours wherever they sit. The figures below replace it, attributed per key by **the commit that
introduced that key** in the English file — this project's commits versus inherited ones:

| | Count | Whose |
|---|---|---|
| English keys with no Arabic sibling, introduced by **this project** | **78 → 0** | ours. All 78 are now translated |
| English keys with no Arabic sibling, introduced **upstream** | **188** | Crowdin and the community, per this repository's own translation rule |
| Keys the method could not attribute | **0** | — |

The 78 were every user-facing string this project had shipped English-only: the flow-builder canvas chrome, the
pagination footer, the contacts bulk-action bar, the settings sidebar's group names, the agent-bot and webhook empty
states, the SLA time units, the access-token and two-factor labels, the commerce order-number copy, and the
loading messages across campaigns, inboxes and billing. They are listed by file in
[15-content-quality-audit.md](15-content-quality-audit.md) §5.

The 188 are deliberately left to Crowdin: translating upstream strings by hand would collide with the next sync and
is explicitly not this phase's job. P4 §16.3's own instruction — "do not expand this into translation of every
developer-only string" — is why the line is drawn at authorship rather than at count.

## 6. What a verification pass should check

`16-regression-results.md` records the result of each:

1. A fresh installation's first screen names the installation, not the upstream project.
2. Every settings page's "Learn more" resolves to a Lynomia article or renders nothing.
3. No user-facing surface renders the string "Chatwoot" on a branded installation.
4. The sidebar profile menu's Documentation and Changelog rows both resolve.
5. The Arabic dashboard shows the installation name wherever the English one does.
