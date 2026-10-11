# P-FINAL — licence and dependency inventory

**This document is descriptive. It records what each licence file and each dependency's own metadata says, and
nothing more. It makes NO legal claim: it does not state that this release is cleared, safe, or free of legal
risk. Those are questions for qualified legal review, which a repository audit is not and cannot substitute
for. Where something needs that review, this document says so and stops.**

Measured on the integrated tree at `claude/p-final-commercial-release-hardening`, after the clean-room
exchange. The method is stated under each section so the figures can be reproduced.

---

## 1. The repository's own licence

`LICENSE` is the Chatwoot MIT Expat licence with a carve-out. Read in full, it says three things:

1. all content under the `enterprise/` directory of the repository, **"if that directory exists"**, is licensed
   under `enterprise/LICENSE`;
2. third-party components keep their own licences;
3. everything outside those is available under MIT Expat, with the copyright notice to be retained in all
   copies.

**`enterprise/` does not exist in this tree.** Verified: no such directory, no `spec/enterprise/`, no `enterprise`
namespace directory at any depth, and `ChatwootApp.extensions == ["custom"]` with `ChatwootApp.enterprise? ==
false` at runtime. The first clause therefore has nothing to attach to, and the file `enterprise/LICENSE` it
points at is not present either.

The MIT notice-retention requirement is a live obligation on this product: `LICENSE` retains the Chatwoot
copyright notice, and a branding pass must not strip it. It has not been stripped.

`SECURITY.md` and `CODE_OF_CONDUCT.md` are present and are upstream's. There is no `NOTICE` file.

### The one fact that was a blocker, and what changed

P-FINAL's provenance audit found 39 production files and 12 specs whose content traced to the pre-removal
Enterprise overlay, and raised it as a blocker rather than resolving it by argument
(`docs/p-final/04-code-provenance.md` §6). The product decision was taken that Lynomia does not depend on
Chatwoot Enterprise and no Enterprise subscription is relied on, and the affected implementation was replaced by
one authored independently from behavioural specifications, in a separate parentless repository, by an
implementer with no access to this repository, its history, the overlay, the provenance audit or the removed
specs. §8 of that document records the result and the re-sweep that checked it: the sweep that found 31 pairs
above threshold now finds four, none of them on a file the audit had classified as Enterprise-derived.

**That is process and measurement evidence. It is not a legal conclusion, and none is claimed here.**

---

## 2. Ruby dependencies

Method: direct dependencies are the `gem` declarations in `Gemfile`; the total resolved set is every gem in
`Gemfile.lock`; the licence for each is read from the `license`/`licenses` field of the gem's own installed
gemspec under `vendor/bundle/ruby/3.4.0/specifications/`.

| | count |
|---|---|
| direct gems declared in `Gemfile` | **152** |
| total resolved gems in `Gemfile.lock` | **381** |
| direct gems whose installed gemspec states a licence | **140** (this row said 142 in the first version; see §2.1) |

Declared licences across the 152 direct gems:

| licence as the gemspec states it | gems |
|---|---|
| MIT | 117 |
| Apache-2.0 | 13 |
| *not stated in the installed gemspec* | 12 |
| BSD-2-Clause | 2 |
| Ruby + BSD-2-Clause | 2 |
| WTFPL | 2 |
| BSD-3-Clause + Apache-2.0 | 1 |
| BSD-3-Clause | 1 |
| Brakeman Public Use License | 1 |
| **LGPL-3.0** | **1** |

### 2.1 Items a reviewer should look at, with what they are

| item | declared licence | what it is here |
|---|---|---|
| **`sidekiq`** | LGPL-3.0 | the background job processor. Used as an unmodified library dependency; nothing in this product modifies it or redistributes a modified copy. Runs server-side |
| `brakeman` | Brakeman Public Use License | a static security scanner, development group only, never loaded in production |
| `bundler-audit` | GPL-3.0+ | a dependency-vulnerability checker, tooling only |
| `diff-lcs` | MIT **or** Artistic-2.0 **or** GPL-2.0-or-later | a triple licence; the MIT option is available |
| `rdoc` | Ruby **or** GPL-2.0-only | a dual licence; the Ruby option is available |

**Two gems, not twelve, state no licence — the other ten were never measured.** The first version of this
section listed twelve: `ai-agents`, `annotaterb`, `bullet`, `gmail_xoauth`, `letter_opener`, `meta_request`,
`rack-mini-profiler`, `scss_lint`, `squasher`, `stackprof`, `tidewave`, `web-console`. The set is the right set
to ask about, but the characterisation was wrong, and the post-integration licence audit found why.

`.bundle/config` excludes the `development` group, so ten of those twelve have **no installed gemspec in this
container at all**. "No gemspec to read" was reported as "a gemspec that states no licence". Checked directly
against `vendor/bundle/ruby/3.4.0/specifications/`:

| gem | what the measurement finds | group |
|---|---|---|
| `ai-agents` | installed, gemspec has no `licenses` field | default (production) |
| `gmail_xoauth` | installed, gemspec has no `licenses` field | default (production) |
| the other ten | not installed, so not measured — their licences are unknown from here, not absent | `development` or `test` |

So the honest statement is: **two** direct gems that load in production declare no licence in their installed
gemspec, and **ten** development or test gems were not measured and need checking on a machine that installs
that group. The arithmetic also corrects the §2 summary table: 152 direct gems, of which 140 state a licence
(the table said 142, which agrees with neither the per-licence breakdown below it nor a direct count).

`squasher` is declared inside the `group :development do` block at `Gemfile:228-245`, so it is
development-only. The gems that load in production and state no licence are `ai-agents` and `gmail_xoauth`;
both are discussed in §4 and §2.1 respectively.

No direct or transitive gem declares a source-available or commercial licence (BSL, SSPL, Elastic Licence,
Commons Clause): the count is zero in both sets.

---

## 3. JavaScript dependencies

Method: direct dependencies are `dependencies` plus `devDependencies` in `package.json`; the licence for each is
read from the `license` field of `node_modules/<package>/package.json`.

| | count |
|---|---|
| direct dependencies | **114** |

| licence as the package states it | packages |
|---|---|
| MIT | 94 |
| Apache-2.0 | 6 |
| ISC | 4 |
| BSD-3-Clause | 3 |
| CC0-1.0 | 2 |
| BSD-3-Clause-Clear | 2 |
| **LGPL-3.0** | **1** |
| Unlicense | 1 |
| MPL-2.0 OR Apache-2.0 | 1 |

### 3.1 The one item a reviewer should look at first

**`@breezystack/lamejs`, LGPL-3.0.** An MP3 encoder used by the audio-recording surface. Unlike `sidekiq`, this
one is **bundled into the JavaScript asset that is served to every browser**, which is a materially different
distribution posture from a server-side library. A reviewer should look at this one before the other.

Nothing in the direct set declares a source-available or commercial licence.

---

## 4. Four AI/LLM dependencies that load in production and have no call site

Recorded here because it is a dependency fact with a security dimension, not because anything is broken.

`Gemfile` declares, in the default group so they load at boot: `ai-agents (>= 0.12.0)`, `ruby-openai`,
`ruby_llm (>= 1.14.1)` and `ruby_llm-schema`. `config/initializers/ai_agents.rb` does `require 'agents'`
unconditionally, then configures the SDK **only if** an installation-level `CAPTAIN_OPEN_AI_API_KEY` row exists.

Measured. **The first measurement in this section's first version was wrong, and the post-integration licence
audit caught it.** It claimed "no reference to `ruby_llm`, `RubyLLM`, `ruby-openai` or the `Agents` SDK anywhere
in `app/`, `custom/`, `lib/` or `config/` other than that one initializer", and concluded that the gems sit in
the bundle "with nothing calling them". Both statements are false. What is actually there:

- `lib/llm/config.rb:1` is `require 'ruby_llm'`, and `:24` calls `RubyLLM.context`. It is reached from
  `lib/captain/base_task_service.rb:11,71` and `lib/integrations/llm_base_service.rb:10,106`, both of which are
  production code.
- `Llm::Models` and `Llm::FeatureRouter` are referenced from `app/controllers/api/v1/accounts/captain/preferences_controller.rb`
  and from `app/models/concerns/account_settings_schema.rb` — the second of which is loaded for every Account,
  so the LLM namespace is not even lazily unreachable.
- no `CAPTAIN_OPEN_AI_API_KEY` is configured on this installation, so the initializer's body does not run;
- the Captain *model* layer is gone with the overlay — `Captain::Assistant`, `Captain::AssistantResponse`,
  `Captain::Document`, `Captain::Task` and `Captain::Inbox` all resolve to `nil` — and the SPA's Captain surface
  is gated behind `captain_integration`, which is `enabled: false`.

**The corrected conclusion.** These are live production dependencies with real call sites, not dormant ones.
What makes the product not do AI is narrower and has to be stated as what it is: every path to a provider runs
through `Llm::Config.with_api_key`, which needs a credential, and no credential is configured; the Captain
surface is behind a capability that is off; and the Captain model layer it would have operated on is absent. So
the product cannot reach a provider today — but it is wired to, and a key is the only missing piece. That is a
different posture from "unreferenced", and it is the one to put in front of a reviewer.

The practical consequence for the gem decision below is the opposite of what the wrong measurement implied:
the four gems **cannot** be removed as unused, because `lib/llm/` and `lib/captain/` use them. Removing AI from
the product means removing that code, which is a product decision and not a dependency cleanup.

**Two changes were made here, and the second is what makes the first work.** `captain_tasks` in
`config/features.yml` was `enabled: true` and is now `enabled: false`, so no newly created account carries an
AI capability by default.

That was first recorded here as the whole of the change, on the reasoning that the yml "seeds
ACCOUNT_LEVEL_FEATURE_DEFAULTS". **On an installation that already exists, the yml edit alone does nothing**,
and the post-integration deployment audit found it. `Featurable#enable_default_features` reads the
`ACCOUNT_LEVEL_FEATURE_DEFAULTS` installation config row; `rake db:migrate` does re-run `ConfigLoader`
(`lib/tasks/db_enhancements.rake:1-7`), but with the default `reconcile_only_new: true` it computes
`(config.value + account_features).uniq { |h| h['name'] }` (`lib/config_loader.rb:82-90`), so the **existing
row's entry wins** and the yml's new value is discarded. The yml decides the default only for an installation
whose row does not exist yet — which production is not.

`db/migrate/20261011160000_default_captain_tasks_off_for_new_accounts.rb` edits the row, which is what two
earlier migrations in this repository already do for the same reason and say so in their own comments. Verified
after migrating: the row's entry reads `"enabled" => false`, and an account created afterwards reports
`feature_enabled?('captain_tasks') == false`.

It still does not touch any existing account, and deliberately: `enable_default_features` is a `before_create`
hook, so what an existing tenant already holds is its own state, and changing that is a decision about live
accounts rather than a default.

**Two things were deliberately NOT changed**, and are recorded as known limitations instead:

| left alone | why |
|---|---|
| the four gems | **they have live call sites** (see the correction above), so they are not removable as unused at all. They are unreachable only in the sense that no credential is configured. Removing AI from the product would mean removing `lib/llm/`, `lib/captain/` and the Captain preferences endpoint — a product decision for its own change, not a dependency cleanup |
| the `openai` entry in `config/integration/apps.yml` | the product still lists an OpenAI integration in Settings → Integrations. Removing the app definition could break the integrations page of any account that has already connected one, and whether any has cannot be established from here without touching production. Recommended as a separate change, after checking `integrations_hooks` for `app_id = 'openai'` on the real database |

---

## 5. Pinning and supply-chain posture

| | state |
|---|---|
| `Gemfile.lock` committed | yes |
| `pnpm-lock.yaml` committed | yes |
| git-sourced or path-sourced gems | none in `Gemfile.lock`'s `GEM` sections other than the default rubygems source |
| vulnerability tooling present | `brakeman` and `bundler-audit` are in `group :development, :test` of `Gemfile` (`:257`, declared at `:261`, `:262`) — **not** the development group, which is what keeps them installed at all, since `.bundle/config:3` excludes `development` and they survive on their `:test` membership. Brakeman runs in CI but does not block it |
| vendored third-party assets not managed by a package manager | `vendor/db/sentiment-analysis.onnx`, 66 MB, an upstream Chatwoot model file; **and 38 `.woff2` font binaries** under `app/javascript/shared/assets/fonts/{Inter,InterDisplay}/`, which the first version of this table missed entirely |
| JavaScript dependency scanning | **none.** `.dependabot/config.yml` is the discontinued Dependabot v1 schema at the old path, with upstream Chatwoot maintainers as its reviewers, and there is no `.github/dependabot.yml`; no workflow runs `pnpm audit`. So the 1,144 locked JS packages have no automated advisory watch at all |

### 5.1 The fonts are redistributed without their licence — CLOSED

**This section described an open obligation. It has been closed; see `docs/pre-deploy/01-license-closure.md`
§1 for the full record.** What this audit found and what was done:

The 38 font binaries are redistributed, and the SIL Open Font License under which Inter is published requires
its copyright notice and licence text to accompany every copy. **Neither was in this repository**: no
`OFL.txt`, no attribution file, and no mention in any stylesheet — confirmed by searching the whole tree and
`node_modules` for the licence's text. The notice file deliberately did not reproduce the licence from memory:
an approximate copy of a licence is worse than a pointer to the real one.

The remaining step needed network access this audit did not have. With it:

- The bundled version was read out of the binaries' own `name` table: **Inter `Version 4.000;git-a52131595`**,
  identical across all 38 files, copyright `The Inter Project Authors`.
- `app/javascript/shared/assets/fonts/OFL.txt` is upstream's `LICENSE.txt` from that exact commit, copied byte
  for byte. SHA-256 `262481e844521b326f5ecd053e59b98c8b2da78c8ee1bdbb6e8174305e54935a`; the `v4.0` tag returns
  the identical file.
- Two corrections to `NOTICE.md`: the copyright **holder** is The Inter Project Authors, not the designer
  (Rasmus Andersson, who is now named as the designer); and **18 of the 38** are referenced by a `@font-face`
  rule, not all of them — the other 20 are committed but served to nobody.

No legal clearance is claimed, here or there.

### 5.2 Ten advisory suppressions had expired

`.bundler-audit.yml` ignored 13 advisories. Ten were Rails and Active Storage entries whose own written
rationale named its expiry — "Rails 7.1 has no patched release", "should be removed once we upgrade to Rails
7.2.3.1+" — while `Gemfile.lock` pins `rails (7.2.3.1)`. The condition they named had been met, so they were
suppressing advisories on a premise that no longer held, which is how a patched advisory becomes a shipped one.
All ten were removed, with the reason recorded in the file.

**That was a correction of an expired rationale, not a clean scan, and the note below named the gate. The gate
has since been run** — see `docs/pre-deploy/00-security-audits.md` §1.1. **Nine of the ten did not reappear**
against the live `ruby-advisory-db`, which vindicates the removal. The tenth, CVE-2026-66066, returned and was
**fixed rather than re-suppressed**: Rails moved 7.2.3.1 → 7.2.3.2.

A fourth entry was then also removed — CVE-2026-67991, a RubyLLM ReDoS — because two sibling advisories with
identical `patched_versions` had never been suppressed, so the same risk was only half-visible. All three
RubyLLM advisories now appear in scan output and are carried as OPEN SECURITY ADVISORY with measured
reachability evidence. **Three** suppressions remain: an Azure blob storage issue and two Devise issues (one
patched locally, one on a code path this product does not enable).

Running `bundler-audit` and `pnpm audit` requires a network call to their advisory databases. This container's
network policy does not allow that, so **no vulnerability scan was run as part of P-FINAL and none is claimed**.
That is a gap, stated plainly: it should be run in CI or on a machine with access before the commercial release,
and it is listed in `docs/p-final/07-release-gate.md` as an open item rather than as a pass.

It follows that none of the ten suppressions removed in §5.2 was re-checked against the advisory database here.
The first `bundle exec bundler-audit check --update` with network access is the gate. If one of the ten is still
open against Rails 7.2.3.1, the tool will say so, and the entry belongs back in the file with a current reason
rather than an inherited one.

---

## 6. What this document establishes, and what it does not

It establishes: what the repository's own licence file says and that its conditional carve-out has no
directory to attach to; what each **direct** dependency's own metadata declares, with counts and the method to
reproduce them; which items a reviewer should look at first and why; and what the AI dependencies actually are
— present, called, and unable to reach a provider without a credential (§4).

**Scope limits, stated rather than implied.** Three of them, all found by the post-integration audit of this
document:

- **Only direct dependencies are tallied.** The 152 direct gems of §2 and the 114 direct JS packages of §3 are
  counted; the 381 resolved gems and 1,144 locked JS packages are not. Transitive items with weak-copyleft or
  absent declarations are therefore named nowhere here.
- **Ten development and test gems were not measured at all** (§2.1), because the group they are in is excluded
  from this container's bundle.
- **`package.json` makes its own licence declaration about this repository** — `"name": "@chatwoot/chatwoot"`,
  `"version": "4.18.0"`, `"license": "MIT"`, with no `"private": true` — which §1 does not record because it
  read the root `LICENSE` only. A second, differently worded licence statement carrying the upstream package
  identity is exactly the kind of thing a licence review asks about, and the fork's intended position on both
  fields is a decision to take rather than to leave inherited.
- **`vendor/bundle` is excluded from git by a machine-local file, not by `.gitignore`.** The 543 MB of
  third-party gem source there — including the LGPL-3.0 `sidekiq` and GPL-3.0+ `bundler-audit` sources — is
  kept out of the repository only by `.git/info/exclude`, which no clone inherits. A fresh clone that bundles
  into `vendor/bundle` would show those sources as untracked and could commit them. Adding `vendor/bundle/` to
  `.gitignore` is the one-line fix; it is named here rather than done because `.gitignore` is upstream-shared.

It does not establish that this release may be distributed, sold or operated. It identifies no legal
conclusion and asserts none. The two LGPL items in §2.1 and §3.1 — one server-side library, one bundled into
the browser asset — and the notice-retention obligation in §1 are the three things to put in front of qualified
legal review.
