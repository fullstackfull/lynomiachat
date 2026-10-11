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
| direct gems whose installed gemspec states a licence | 142 |

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

The 12 direct gems whose installed gemspec states no licence are: `ai-agents`, `annotaterb`, `bullet`,
`gmail_xoauth`, `letter_opener`, `meta_request`, `rack-mini-profiler`, `scss_lint`, `squasher`, `stackprof`,
`tidewave`, `web-console`. Nine of those twelve are in the `development` or `test` group and never load in
production. The three that are not — `ai-agents`, `gmail_xoauth` and `squasher` — are discussed in §4.

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

Measured:

- no reference to `ruby_llm`, `RubyLLM`, `ruby-openai` or the `Agents` SDK anywhere in `app/`, `custom/`, `lib/`
  or `config/` other than that one initializer;
- no `CAPTAIN_OPEN_AI_API_KEY` is configured on this installation, so the initializer's body does not run;
- the Captain *model* layer is gone with the overlay — `Captain::Assistant`, `Captain::AssistantResponse`,
  `Captain::Document`, `Captain::Task` and `Captain::Inbox` all resolve to `nil` — and the SPA's Captain surface
  is gated behind `captain_integration`, which is `enabled: false`.

So the product does not do AI, and cannot without an operator adding a key. What remains is an OpenAI HTTP
client and an LLM client in the production bundle with nothing calling them.

**One change was made here**, and only one: `captain_tasks` in `config/features.yml` was `enabled: true` and is
now `enabled: false`, so no newly created account carries an AI capability by default. That flag seeds
`ACCOUNT_LEVEL_FEATURE_DEFAULTS`, which `Featurable#enable_default_features` reads on create only — existing
accounts keep whatever they were created with, and this change does not alter their state.

**Two things were deliberately NOT changed**, and are recorded as known limitations instead:

| left alone | why |
|---|---|
| the four gems | they are inert without a key, and removing a dependency changes `Gemfile.lock` at the release gate. The gain is attack surface, not correctness. Recommended as a separate change with its own full suite run |
| the `openai` entry in `config/integration/apps.yml` | the product still lists an OpenAI integration in Settings → Integrations. Removing the app definition could break the integrations page of any account that has already connected one, and whether any has cannot be established from here without touching production. Recommended as a separate change, after checking `integrations_hooks` for `app_id = 'openai'` on the real database |

---

## 5. Pinning and supply-chain posture

| | state |
|---|---|
| `Gemfile.lock` committed | yes |
| `pnpm-lock.yaml` committed | yes |
| git-sourced or path-sourced gems | none in `Gemfile.lock`'s `GEM` sections other than the default rubygems source |
| vulnerability tooling present | `brakeman` and `bundler-audit` are in the `development` group of `Gemfile` |
| vendored third-party asset not managed by a package manager | `vendor/db/sentiment-analysis.onnx`, 66 MB, an upstream Chatwoot model file tracked in the repository |

Running `bundler-audit` and `pnpm audit` requires a network call to their advisory databases. This container's
network policy does not allow that, so **no vulnerability scan was run as part of P-FINAL and none is claimed**.
That is a gap, stated plainly: it should be run in CI or on a machine with access before the commercial release,
and it is listed in `docs/p-final/07-release-gate.md` as an open item rather than as a pass.

---

## 6. What this document establishes, and what it does not

It establishes: what the repository's own licence file says and that its conditional carve-out has no
directory to attach to; what each dependency's own metadata declares, with counts and the method to reproduce
them; which four items a reviewer should look at first and why; and that the AI dependencies are present but
unreferenced and inert.

It does not establish that this release may be distributed, sold or operated. It identifies no legal
conclusion and asserts none. The two LGPL items in §2.1 and §3.1 — one server-side library, one bundled into
the browser asset — and the notice-retention obligation in §1 are the three things to put in front of qualified
legal review.
