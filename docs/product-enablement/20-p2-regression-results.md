# Phase P2 — regression results

Every gate, with its numbers. Then the findings this phase proved, including the ones against its own work.

Branch `claude/practical-thompson-9xfqed`.

---

## 1. Gates

| Gate | Command | Result |
|---|---|---|
| ESLint, repository-wide | `pnpm eslint` | **0 errors**, 495 warnings, exit 0. Every warning is a pre-existing category (`no-raw-text`, `no-dynamic-keys`); none is on a line this phase wrote except the dynamic-key warnings the recipe contract requires by design |
| Vitest, full suite | `npx vitest run` | **492 files, 5160 tests, 0 failures** |
| Vitest, P2 areas | recipes, recipe dialog, audience, contacts, macros, automation, campaigns | **28 files, 339 tests, 0 failures** |
| RSpec, audience and branding | 11 files covering custom filters, shared filters, audiences, campaign audience, installation config, branding | **100 examples, 0 failures** |
| RSpec, full suite | `bundle exec rspec` | in progress at the time of this commit, on a dropped and reloaded test database — see §1.1 for why the first run was discarded. The number lands in the next revision of this file |
| Production build | `bin/vite build` | exit 0; 5137 modules; the one notice is the pre-existing chunk-size advisory |
| RuboCop | `bundle exec rubocop` | **3418 files inspected, no offenses**, exit 0 (zero `.rb` files changed in this phase) |
| Browser journeys | four Playwright scripts against a production build | **52 checks, 0 failures** |
| Accessibility pass | one Playwright script | **5 checks, 0 failures** |

### 1.1 The first full RSpec run, and why it was discarded

The first attempt reported **421 failures**, spread across Facebook, CRM, message-window, conversation-model and
webhook specs — none of them anywhere near this phase, which changed no Ruby at all. Rather than call that a flake,
it was diagnosed:

`select count(*) from installation_configs` on `chatwoot_test` returned **136 rows**, while `accounts` returned 0.
So `installation_configs` had been **committed outside a transaction** by an earlier run in this session, while
everything else rolled back as `use_transactional_fixtures = true` intends. The failures follow from that directly:
seven are `ActiveRecord::RecordNotUnique` on `create(:installation_config, …)` hitting the unique index on `name`,
and the rest are specs that assume a given key is *absent* and read a seeded value instead — "when a signing secret
is configured only via ENV and config reconciliation left a blank row", "follows the installation kill switch",
"when ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT is enabled", and so on.

The suite was then re-run on a dropped and reloaded `chatwoot_test` with a flushed Redis and nothing else on the
machine. That is the run reported above.

**This is a pre-existing test-hygiene hazard worth fixing in its own right:** running any subset of the suite can
leave `installation_configs` rows behind, and the next run — subset or full — then fails in places that have
nothing to do with the change under test. The fix belongs with whatever commits those rows, not here.

**Zero `.rb` files changed in this phase.** The only non-JavaScript change is two values in
`config/installation_config.yml` and its enterprise overlay (the branding capitalization), which the focused RSpec
run above covers directly.

## 2. What the specs added

Eleven new spec files, six extended:

| New | Covers |
|---|---|
| `helper/specs/audienceSummary.spec.js` | condition summaries, including an attribute that no longer exists |
| `helper/specs/campaignDraft.spec.js` | read-once semantics, staleness, per-type isolation, storage that throws |
| `components-next/audience/specs/AudienceExplainer.spec.js` | that it says what an audience is, in both languages |
| `components-next/audience/specs/AudienceCard.spec.js` | the row's copy, its gating by role and by shared state, and that counting is an action |
| `components-next/audience/specs/audienceCopy.spec.js` | EN/AR parity for the audience blocks, placeholder sets, and a usable Arabic plural |
| `components-next/recipes/specs/RecipeInputs.spec.js` | that every declared input type renders as something other than the URL fallback |
| `components-next/Campaigns/.../specs/CampaignRecipients.spec.js` | the picker's descriptions and its empty state |
| `routes/dashboard/contacts/pages/specs/AudiencesIndex.spec.js` | the page: ordering, the on-demand count, the failed count, and that browsing evaluates nothing |
| `routes/dashboard/contacts/specs/routes.spec.js` | that `contacts/audiences` resolves to the page and not to a contact |
| `routes/dashboard/settings/macros/specs/Index.spec.js` | the starter path, the visibility decision, the failure, and from-scratch |
| `recipes/specs/macroStarters.spec.js` | the server allow-list, scalar parameters, builder-known types, and no embedded ids |

| Extended | With |
|---|---|
| `recipes/specs/catalogue.spec.js` | catalogue sizes as a tripwire, setup-recipe step names and kinds, platform notes in both languages |
| `recipes/specs/flowTemplates.spec.js` | the FAQ loop returning to its own menu, and the complaint handoffs carrying the chosen priority |
| `recipes/specs/automationRecipes.spec.js` | the label assertion rewritten to follow the input's `required` flag rather than an id list |
| `components-next/recipes/specs/RecipeDialog.spec.js` | the platform note in both places, and the recommendation marker |
| `routes/dashboard/settings/automation/specs/Index.spec.js` | the setup-step runner: order, id hand-off, partial failure, stop on first failure |
| `helper/specs/audienceHelper.spec.js` | the cross-module route builders |

## 3. Browser journeys

Run against a production Vite build served by Puma in `RAILS_ENV=production`, on a freshly created database
(schema load, `db:seed`, then an account with two teams, three labels, three contacts and three audiences).

**Journey 1 — the Audiences destination (25 checks).** The sidebar carries a destination before any audience
exists. The page lists three audiences, shared first, each with its conditions; nothing is counted until a button
is pressed, and then exactly one row gains a number. Each card's menu is reachable by keyboard and names its own
audience. The page fits 390, 768, 1024 and 1280 with no horizontal scroll. The macro and automation galleries open
from both their entry points, a commerce recipe says what is missing instead of offering Create, the platform note
is shown, and the audience-based recipe is marked "Uses an audience you have".

**Journey 2 — galleries and the empty page (4 checks).** All six macro starters are offered, every one of them
usable with nothing set up. With the account's audiences deleted, the Audiences page says "No audiences yet" and
offers both ways in; the preset gallery opens from that empty state with all nine presets.

**Journey 3 — the campaign round trip (10 checks).** On an account with no audience: a campaign explains what one
is, offers to create it, carries the half-filled campaign to Contacts with `?returnTo=campaigns_whatsapp_index`,
and the draft is in `sessionStorage` with the typed title. Applying a filter reveals the labelled
"Save as audience" control; saving lands back on `/campaigns/whatsapp?audience=5` with the title restored **and**
the new audience already selected.

**Journey 4 — Arabic (13 checks).** With the account in Arabic the page computes `rtl`, its copy is
Arabic rather than an English fallback, the card's menu follows the reading direction, and the platform note is
translated. No horizontal scroll at any width tested.

**Accessibility (5 checks).** Every visible control on the page and in the gallery has an accessible name. The page
has an `h1` that names it and a live region for its loading state. Tab order reaches both header actions and, per
card, the menu and the count.

Screenshots and the per-journey JSON reports: `screenshots/p2/`.

## 4. Findings this phase proved

### 4.1 Fixed in its own additions

| Finding | Where it would have shown | Fix |
|---|---|---|
| `INPUT_TYPES.LABEL` was declared but nothing rendered it | `RecipeInputs` falls through to a URL field, so a macro starter asking for one label offered a URL box | `LABEL` removed; every label action takes a list of titles, so `LABELS` is the only shape. A spec now asserts every declared input type renders as something other than the fallback |
| the flow templates' `handoff` helper dropped a `priority` it was handed | `complaint_intake` collects a priority; it would have done nothing | helper extended; a spec asserts all three handoffs carry it |
| the Arabic contact count had six plural forms | with no Arabic plural rule configured, vue-i18n reads the first three as 0/1/many, so every count above one read "two contacts" with no number | three forms, number in the "many" form; a spec caps the form count and requires the number |

### 4.2 Pre-existing, proven, and left with a reason

| Finding | Evidence | Why it was left |
|---|---|---|
| `commerce_order_shipped` can never fire for a WooCommerce store, `delivered` only for Salla and Zid, `cancelled` never for Shopify | each provider's own `STATUSES` map against `Commerce::OrderTransitions::FACTS` | the behaviour is correct; what was missing was saying so. Four starters now carry a platform note. Changing the normalizers is a Commerce change, not a starter-library one |
| 27 Arabic strings hardcode the brand where English takes `{installationName}` | 26 in `ar/commerce.json`, one in `ar/automation.json` | all on surfaces this phase did not touch. The brief ruled out general branding cleanup here; they are counted and located in `docs/branding/P1-branding-audit.md` §9.4 for a branding phase. The one on an audience surface was fixed |
| 10 English strings have no Arabic sibling | 5 in `CONTACTS_BULK_ACTIONS`, 2 in `CONTACTS_LAYOUT.SIDEBAR.NOTES`, 3 in `CONTACT_PANEL` | bulk action bar and contact panel, none on a P2 surface. The audience and contacts-header strings this phase's pages read were written |
| the installation onboarding view says "Welcome to Chatwoot" | seen while bringing up a fresh install for the browser journeys | an installation-setup view, outside the dashboard P1 covered and outside this phase's scope. Worth a branding phase's attention because it is the very first screen an operator sees |

### 4.3 Checked and found correct

| Checked because it looked wrong | Verdict |
|---|---|
| the campaign title appeared not to be restored on the return trip | the test was reading page text; an input's value is not page text. Reading the field proved the restore works |
| the Audiences page appeared to render LTR in Arabic | the app sets direction on a wrapper inside the shell, not on `<html>` or `#app`. The page content computes `rtl` and the layout is mirrored |
| `components-next/ConversationWorkflow/` looked like a workflow engine | it is upstream Chatwoot's conversation-required-attributes UI. Not touched, and no conflict with the prohibition on building one |

## 5. Zero migrations

`git diff --name-only` across the phase lists no file under `db/`. No item in Part A through Part G required one.
