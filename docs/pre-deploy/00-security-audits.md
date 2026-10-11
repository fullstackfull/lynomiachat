# Pre-deploy condition 1 — dependency security audits, run with network access

P-FINAL left this condition open for one reason and said so plainly: `bundler-audit` and `pnpm audit` fetch
their advisory databases over a network the P-FINAL container did not have, so no scan was claimed
(`docs/p-final/07-release-gate.md` #48). Both have now been run against the live databases. This document is
the result, with every finding classified and nothing hidden.

**Classification used throughout.** PASS — scanned and clean. FIXED — a real advisory, closed in this branch by
a dependency change. OPEN — a real advisory still present, with no safe fix available now. NOT APPLICABLE — the
scanner flags it but the installed code is not the vulnerable code, with the evidence. REQUIRES REVIEW —
cannot be settled from here.

**No hidden suppressions.** `.bundler-audit.yml` holds three ignore entries, all pre-existing and all on
rationales checked below. One entry was **removed** in this branch (CVE-2026-67991) so that it appears in scan
output alongside its two siblings. Nothing was added.

---

## 1. Ruby — `bundle exec bundle-audit check --update`

| | |
|---|---|
| tool | `bundler-audit 0.9.1` |
| database | `ruby-advisory-db`, commit `a6847b0651a702488f5844081e848dd1ec9dbf1d`, 1263 advisories, last updated 2026-10-10 |
| exit status | 1 (`Vulnerabilities found!`) |
| findings | 4 records across 2 gems |

### 1.1 The ten suppressions P-FINAL removed — PASS, and this was the gate

P-FINAL deleted ten Rails and Active Storage ignore entries because each named its own expiry and the named
condition had been met. It recorded that as a correction of an expired rationale and **not** a clean scan, and
it named the gate: "the first `bundle exec bundler-audit check --update` with network access".

That gate has now been run. **Nine of the ten did not reappear.** They were genuinely closed by Rails 7.2.3.1,
and removing them was right.

| advisory | result against the live database |
|---|---|
| CVE-2026-33658, CVE-2026-33173, CVE-2026-33174, CVE-2026-33168, CVE-2026-33169, CVE-2026-33170, CVE-2026-33176, CVE-2026-33195, CVE-2026-33202 | **PASS** — not reported against 7.2.3.1 |
| CVE-2026-66066 | **returned** — see §1.2 |

### 1.2 CVE-2026-66066, `activestorage` — FIXED

| | |
|---|---|
| gem | `activestorage` (transitive, via `rails`; `rails` is a direct dependency at `Gemfile`:8) |
| installed before | 7.2.3.1 |
| exposure | runtime, production |
| remediation applied | `gem 'rails', '7.2.3.1'` → `'7.2.3.2'` |
| lockfile movement | exactly 13 gems, all Rails components, 7.2.3.1 → 7.2.3.2. Nothing else moved. |

This is the smallest change that resolves it: a patch-level bump of the framework that already declares the
vulnerable gem, with no minor or major move anywhere in the graph.

**It is not free, and the cost is a new host precondition.** The 7.2.3.2 Active Storage patch makes Active
Storage **refuse to load** when it cannot disable libvips's unfuzzed operations: it raises on `require` unless
libvips is 8.13 or later **and** `ruby-vips` is 2.2.1 or later
(`activestorage-7.2.3.2/lib/active_storage/vips.rb:34`). This was found by running the suite rather than by
reading the changelog — `rails db:test:prepare` aborted with:

```
libvips's unfuzzed operations are not safe to use with untrusted content, and Active Storage cannot
disable them. Disabling them requires libvips 8.13 or later and ruby-vips 2.2.1 or later.
```

The gem half is fixed here: `ruby-vips` 2.1.4 → 2.3.0, taken with `bundle update ruby-vips --conservative`,
which moved that one gem and nothing else. `ruby-vips` is transitive, via
`image_processing (1.12.2) → ruby-vips (>= 2.0.17, < 3)`, so 2.3.0 is inside the declaring constraint.

The libvips half is a **system package on the deployment host** and no change in this repository can install it.
Every Rails process aborts on an old libvips, web and worker alike, so an unchecked deploy would turn the
restart into an outage with no rollback of its own. Two things were added for it:

- `deployment/deploy.sh` stage **4b**, after the bundle install and before the migrations, which boots Ruby with
  `vips` and fails the deploy with the remedy if it cannot. A failure there costs one unused dump and leaves the
  schema untouched.
- `docs/p-final/08-production-uat-runbook.md` §0.1, which tells the operator to check it **before** the window
  opens.

Verified on this container: libvips 8.15.1, `ruby-vips` 2.3.0, Rails boots.

### 1.3 GHSA-42qh-8mx8-7wqm, `rack-proxy` 0.7.7 — NOT APPLICABLE

The scanner reports this. The installed code is not the vulnerable code, and the advisory's own text says so.

```
title: HTTP response smuggling via ambiguous backend response framing in rack-proxy 1.x
description: |
  rack-proxy 1.0.0 through 1.0.2 can forward an incorrect Content-Length
  when a backend response contains both Transfer-Encoding and Content-Length.
patched_versions:
  - ">= 1.0.3"
```

Two facts, both checkable:

1. The flaw was **introduced in 1.0.0**. The advisory names 1.0.0–1.0.2 as affected and titles itself "in
   rack-proxy 1.x". Installed is 0.7.7, which predates it.
2. The advisory file carries **no `unaffected_versions` key**. `bundler-audit` therefore treats every version
   below `1.0.3` as affected, including versions released before the flaw existed. This is a false positive
   produced by missing metadata, not by our dependency graph.

It is also unfixable as reported: `rack-proxy` is transitive via
`vite_ruby → rack-proxy (~> 0.6, >= 0.6.1)` (`Gemfile.lock`:1020), and `~> 0.6` forbids 1.0.3 outright.

**It was not suppressed.** Adding an ignore entry would hide it from the next operator for a reason that is
true today and might not be after an upstream metadata fix. It stays visible in scan output and is explained
here. Recommended follow-up, outside this branch: report the missing `unaffected_versions` to `ruby-advisory-db`.

### 1.4 CVE-2026-67987, CVE-2026-67989, CVE-2026-67991, `ruby_llm` 1.15.0 — OPEN SECURITY ADVISORY

All three are **open and unpatched in this release.** They appear in scan output on purpose.

| | |
|---|---|
| gem | `ruby_llm` 1.15.0 — a **direct** dependency (`Gemfile`:204) |
| severity | CVSS v3 **7.5** each; `bundler-audit` reports Criticality: High |
| class | polynomial-time regular expression denial of service (ReDoS). Availability only — no confidentiality or integrity impact in any of the three |
| only patched release | `>= 2.0.0.rc1` for all three |

#### Why it is not fixed

The only patched release is a **major** version, and it removes four APIs this application calls. Measured
against the installed `ruby_llm-2.0.0`, not inferred:

| what we call | where | state in 2.0.0 |
|---|---|---|
| `Chat#with_tool(tool)` | `lib/captain/base_task_service.rb:92` | **removed**; only `with_tools(*tools)` remains |
| `Chat#on_end_message { }` | `lib/captain/base_task_service.rb:93` | **removed**; renamed `after_message` |
| `Models#refresh!` | `lib/tasks/ruby_llm.rake:13` | **removed**; `Models.refresh` (no bang) |
| `Message#input_tokens` / `#output_tokens` | `lib/captain/base_task_service.rb:111-113`, `lib/integrations/llm_base_service.rb:149-151` | **removed** from `Message`; usage moved behind `Accounting::Usage` |
| `Message#content` | same | semantics changed: documented as "the message text as a String. **Empty** for assistant messages that only request tool calls", where 1.x returned `nil` |
| `ruby_llm-schema` | `Gemfile`:205 | renamed: 1.0.0 is a forwarding shim and `RubyLLM::Schema` becomes `Schematist::Schema` |

`RubyLLM.context` and `RubyLLM.configure` — the two entry points in `lib/llm/config.rb:24,35` — do survive
unchanged, with the same config accessors. The upgrade is therefore possible. It is not *validatable here*: the
resolve also moves `ai-agents` 0.12.0 → 0.13.0 and five collateral gems (`json` 2.19.9 → 2.21.2, `zeitwerk`
2.7.5 → 2.8.3, `marcel` 1.1.0 → 1.2.1, `faraday` 2.14.3 → 2.14.4, `uri` 1.1.1 → 1.1.2), and **every Captain
spec in this repository mocks the provider with `instance_double`** (`spec/lib/captain/*_spec.rb`). They would
pass by construction after four mechanical renames while the live provider protocol stayed unverified. Shipping
a green suite as evidence for a major LLM-library migration, in a branch whose purpose is to close
pre-deployment conditions, would be false assurance.

The experiment was run and then reverted. `Gemfile` and `Gemfile.lock` carry no part of it.

#### Exploitability in this installation, measured

Each advisory scopes its own claim to one Ruby version: "polynomial-time regular expression denial-of-service
conditions … **on Ruby 3.1.x**", and CVE-2026-67991 adds "exposure depends on untrusted data reaching the
affected operation". This application requires **Ruby 3.4.4** (`Gemfile`:5, `.ruby-version`).

The three named regex sites were located in the installed 1.15.0 and timed on this installation's Ruby. A
polynomial condition of degree 2 would show ~4× the time for 2× the input; all three are linear:

| CVE | site in `ruby_llm` 1.15.0 | input 1× → 16× | time 1× → 16× |
|---|---|---|---|
| 2026-67987 | `providers/openai/chat.rb:213-214`, `text.scan(%r{<think>(.*?)</think>}m)` then `text.gsub(...)` — the "two consecutive regular expressions" the advisory names | 1 000 → 16 000 unterminated `<think>` tags | 0.0015 s → 0.0133 s (**8.9×**) |
| 2026-67989 | `providers/mistral/capabilities.rb`, the `case model_id when /voxtral.*transcribe/` chain | 10 000 → 160 000 chars | 0.0001 s → 0.0010 s (**10×**) |
| 2026-67991 | `agent.rb:327` and `tool.rb:73`, `.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')` | 10 000 → 160 000 chars | 0.0010 s → 0.0279 s (**28×**, i.e. ~1.7× per doubling) |

A control run confirms the mechanism rather than asserting it: `/\A(a+)+\z/` against `('a'*n)+'b'`, the
textbook catastrophic-backtracking pattern, returns in under 0.00002 s at every n from 20 to 40 on this Ruby.
On an engine without the regexp memoization Ruby added in 3.2 that is hours of CPU at n=40. The optimizer is
active here, which is consistent with the advisories confining their claim to 3.1.x.

Scripts and raw output: `redos_bench.rb` and `redos_control.rb`, reproduced in §1.5.

#### Reachability of each, independently of the Ruby version

| CVE | reached from | assessment |
|---|---|---|
| 2026-67987 | a model response body containing many `<think>` tags, guarded by `return [text, nil] unless text.include?('<think>')` | **conditionally reachable.** See the condition below — it is weaker than it first looks, and an earlier draft of this section got it wrong |
| 2026-67989 | the **Mistral** provider's capability matching | **not reachable.** Only the OpenAI provider is configured (`lib/llm/config.rb` sets `openai_api_key` / `openai_api_base` and nothing else). No code path selects Mistral, and nothing in the product offers a provider choice |
| 2026-67991 | `underscore` over a "very long crafted class, agent, or tool name" | **not reachable from untrusted input.** The names are Ruby class names of tools defined in this repository. No endpoint accepts a tool or agent name |

#### The exact condition for CVE-2026-67987 — and a correction

An earlier draft of this section said an **installation-level** API key is required, and that leaving
`CAPTAIN_OPEN_AI_API_KEY` unset keeps the whole path dead. **That is wrong**, and the correction matters
because it is the difference between "an operator must act" and "an account administrator can act":

`Captain::BaseTaskService#llm_credential` (`lib/captain/base_task_service.rb:179-185`) branches on
`use_account_openai_hook?`. The base returns `false` (`:187-189`) — but **six subclasses override it to
`true`**: `csat_utility_analysis_service.rb:67`, `follow_up_service.rb:107`,
`label_suggestion_service.rb:90`, `reply_suggestion_service.rb:41`, `rewrite_service.rb:60`,
`summary_service.rb:28`. For those, `hook_llm_credential` (`:191-194`) reads
`account.hooks.find_by(app_id: 'openai', status: 'enabled')&.settings&.dig('api_key')`, and
`config/integration/apps.yml:26-43` declares `openai` with `hook_type: account` and `required: ['api_key']`.
**So an account administrator can supply the key through the ordinary integrations UI, with no installation
config and no operator involvement.** Five of those six are exposed to ordinary authenticated account users at
`app/controllers/api/v1/accounts/captain/tasks_controller.rb` (`rewrite`, `summarize`, `reply_suggestion`,
`label_suggestion`, `follow_up`).

The condition is therefore: **`captain_tasks` enabled for the account** (`base_task_service.rb:158-160`
returns 403 otherwise; `config/features.yml:254-256` ships it `enabled: false`) **AND** a credential from
either source — the installation config, **or** an account-level `openai` hook.

The single control that keeps the path dead for an account is therefore the **`captain_tasks` feature flag**,
not the absence of an installation key.

#### Safest mitigation available now

1. **Already in place:** Ruby 3.4.4, whose regexp optimizer makes all three linear, as measured above. This is
   the mitigation that does the work, and it does not depend on configuration.
2. **Already in place, but weaker than stated above:** `captain_tasks` ships disabled
   (`config/features.yml:254-256`), which is the one gate that stops all six affected services. Note that it is
   an **account** feature bit, so it is per-account and grantable — `config/features.yml`'s `enabled:` value
   only seeds the default for newly created accounts.
3. **Available, not applied:** `Regexp.timeout` is `nil` on this installation. Setting it in an initializer
   would bound any regex, these three included. It is not applied because the measurement shows linear
   behaviour, and a guard against a condition that is not present is a guard that will mislead whoever reads it
   later. If the owner wants belt and braces, this is the cheapest form of it.

One further note, so the citation is not read as more than it is: `lib/integrations/llm_base_service.rb`
contains the same `input_tokens`/`output_tokens` usage, but `git grep -rn "LlmBaseService"` returns only its
own definition and its own spec — **it has no subclasses and is not on a live path.** It matters for the
`ruby_llm` 2.x migration (the API it uses was removed) and not for reachability.

#### Deployment impact

**None for this deploy, as shipped.** The condition the advisories describe does not reproduce on Ruby 3.4.4 —
that is the measured finding and it holds regardless of configuration. `captain_tasks` ships disabled, which
additionally keeps the code from running at all on a default account.

The risk, if realised, is CPU exhaustion in a Sidekiq worker processing a Captain task — degradation of one
queue, not data loss and not disclosure. **If Captain is enabled for an account during the rollout**, the
reachable surface is the five `tasks_controller` endpoints above, and the mitigation that still applies is the
Ruby version.

**Recommended follow-up, as its own change:** a `ruby_llm` 2.x migration covering the four removed APIs, the
`Message#content` change, the `schematist` rename, and the `ai-agents` 0.13.0 move, validated against a real
provider rather than against `instance_double`. That is a day of work with a live key, and it does not belong in
a pre-deployment hardening pass.

### 1.5 Reproducing the measurement

```
$ ruby redos_bench.rb
RUBY_VERSION=3.4.4  RUBY_PLATFORM=x86_64-linux
Regexp.timeout default = nil

CVE-2026-67987 -- providers/openai/chat.rb:213-214 (think-tag, two consecutive regexes)
  scan+gsub              n=1000         0.0015 s
  scan+gsub              n=2000         0.0023 s
  scan+gsub              n=4000         0.0045 s
  scan+gsub              n=8000         0.0091 s
  scan+gsub              n=16000        0.0133 s

CVE-2026-67989 -- providers/mistral/capabilities.rb (capability matching)
  case/when chain        n=10000        0.0001 s
  case/when chain        n=20000        0.0002 s
  case/when chain        n=40000        0.0003 s
  case/when chain        n=80000        0.0005 s
  case/when chain        n=160000       0.0010 s

CVE-2026-67991 -- agent.rb:327 / tool.rb:73 (underscore)
  gsub x2                n=10000        0.0010 s
  gsub x2                n=20000        0.0020 s
  gsub x2                n=40000        0.0043 s
  gsub x2                n=80000        0.0128 s
  gsub x2                n=160000       0.0279 s

$ ruby redos_control.rb
  (a+)+  n=20      0.00002 s
  (a+)+  n=40      0.00000 s
```

### 1.6 The three remaining suppressions

Each was already present, and each rationale was re-checked rather than inherited.

| advisory | gem | rationale | still current? |
|---|---|---|---|
| CVE-2021-41098 | `nokogiri` (via Azure blob storage) | upstream Chatwoot issue 3097, pending an Azure storage update | **yes** — unchanged upstream |
| GHSA-57hq-95w6-v4fc | `devise` | confirmable race, patched locally in the `User` model | **yes** |
| GHSA-jp94-3292-c3xv | `devise` | the timeout redirect path; Timeoutable is not enabled | **yes** |
| ~~CVE-2026-67991~~ | ~~`ruby_llm`~~ | ~~ReDoS reported on Ruby 3.1~~ | **entry removed.** The reasoning in it was sound, but two sibling advisories with identical `patched_versions` were never suppressed, so the same risk was half-visible. All three are now visible and documented in §1.4 |

---

## 2. JavaScript — `pnpm audit`

| | |
|---|---|
| tool | `pnpm audit` against the committed `pnpm-lock.yaml` |
| baseline, before this branch | **126** advisory records over **140** dependency paths — 4 critical, 71 high, 56 moderate, 9 low |
| after the changes below | **68** advisory records over **77** dependency paths — 3 critical, 39 high, 23 moderate, 3 low |

Nothing was run with `pnpm audit --fix`, `npm audit fix --force`, or a blanket upgrade. Every change below is
a named package pinned to a named version, with the reason it was chosen.

### 2.1 FIXED — direct dependencies

Six direct declarations, all inside their existing major line.

| package | section | from | to | cleared |
|---|---|---|---|---|
| `axios` | dependencies | ^1.15.0 | ^1.20.0 | all `axios` advisories |
| `dompurify` | dependencies | 3.4.13 | 3.4.16 | all `dompurify` advisories. This one is the browser XSS sanitiser — a security control, not an ordinary dependency |
| `js-cookie` | dependencies | ^3.0.5 | ^3.0.8 | all `js-cookie` advisories |
| `markdown-it` | dependencies | ^14.1.1 | ^14.3.2 | the runtime copy. See §2.4 |
| `vite` | devDependencies **and** `pnpm.overrides` | 6.4.2 | 6.4.4 | all `vite` advisories, and `follow-redirects` with them |
| `vitest`, `@vitest/coverage-v8` | devDependencies; `vitest` also in `pnpm.overrides` | 3.0.5 | 3.2.7 | the `vitest` criticals |

`vite` and `vitest` needed editing in **two** places. `pnpm.overrides` pinned them to the old versions, and an
override wins over a `devDependencies` range, so the first pass changed `devDependencies` and the lockfile did
not move. It also left `@vitest/coverage-v8@3.2.7` resolved against a peer `vitest@3.0.5`. Both are now
consistent.

### 2.2 FIXED — transitive, via `pnpm.overrides`

Six transitive packages that reach the **browser**. An override is the targeted mechanism for a transitive, and
the file already used that pattern for `minimatch` and `rollup`.

| package | from | to | severity cleared | why it is browser code |
|---|---|---|---|---|
| `@xmldom/xmldom` | 0.8.13 | **0.8.15** | 8 × high | `video.js → @videojs/http-streaming → mpd-parser`; parses DASH manifests in the player |
| `prosemirror-view` | 1.34.1 | 1.42.6 | high | `@chatwoot/prosemirror-schema`; the message composer's editor |
| `@babel/runtime` | 7.26.7 | 7.29.10 | moderate | `@chatwoot/utils → date-fns`, and `video.js` |
| `@hotwired/turbo` | 8.0.13 | 8.0.23 | low | `@hotwired/turbo-rails`; the Rails-rendered pages |
| `min-document` | 2.19.0 | 2.19.2 | low | `video.js → @videojs/vhs-utils → global` |
| `source-map-js` | 1.2.1 | **1.2.2** | high (386 paths) | build-time (`@vue/compiler-*`, `postcss`, `vite`), included because one patch version is cheaper than the paragraph explaining why not |

**Each override is capped at its current major line, deliberately.** Written as `>=`, pnpm took the newest
release and crossed two major boundaries on the first attempt — `@babel/runtime` went to **8.0.7** and
`@xmldom/xmldom` to **0.9.12**. Both were caught by reading the resolved lockfile and re-pinned with `^`.
`@xmldom/xmldom` now sits at exactly the minimum patched version, 0.8.15.

### 2.3 OPEN — build and development tooling only

The remaining 68 records are in 26 packages. **Every entry point is a build or development tool.** This is the
dependency path, not the `package.json` section:

| entry point | packages flagged beneath it |
|---|---|
| `eslint`, `eslint-config-*`, `eslint-plugin-*`, `eslint-interactive`, `@intlify/eslint-plugin-vue-i18n` | `ajv`, `brace-expansion`, `flatted`, `fast-uri`, `js-yaml`, `lodash`, `postcss-selector-parser`, `@intlify/core-base` |
| `tailwindcss`, `@tailwindcss/typography`, `@egoist/tailwindcss-icons` | `brace-expansion`, `braces`, `glob`, `picomatch`, `postcss-selector-parser`, `yaml` |
| `histoire`, `@histoire/plugin-vue` | `shell-quote` (**critical**), `defu`, `form-data`, `launch-editor`, `linkify-it`, `markdown-it`, `sprintf-js`, `ws`, `@tootallnate/once` |
| `vitest`, `@vitest/coverage-v8` | `tinypool` (**2 × critical**), `@vitest/mocker`, `vitest`, `ws`, `glob`, `brace-expansion` |
| `jsdom` | `ws`, `source-map-js` |
| `lint-staged`, `size-limit`, `@size-limit/file` | `braces`, `picomatch`, `yaml` |
| `postcss-preset-env`, `autoprefixer`, `@rollup/plugin-yaml` | `browserslist`, `postcss-selector-parser`, `js-yaml` |

**One correction to how this would otherwise be classified.** `@tailwindcss/typography` and `vue` sit in
`dependencies` rather than `devDependencies`, which is upstream Chatwoot's placement. A classifier keyed on the
`package.json` section therefore labels everything beneath them "runtime". They are not: a Tailwind plugin is
consumed by `tailwind.config.js` at build time. The table above is keyed on **execution context**, which is the
honest basis. An earlier pass in this work mislabelled `markdown-it` the same way — see §2.4.

None of these 68 records is reachable by a customer, by a request, or by anything in the deployed artifact. They
are reachable by whoever runs `pnpm eslint`, `pnpm test` or `histoire dev` on a developer machine or in CI,
which is a real risk surface and a different one. They are **not suppressed**: they appear in every
`pnpm audit` run, and they are listed here by name.

Two have **no upstream fix at all** (`patched_versions: <0.0.0`): `braces` (high, GHSA-vfj7-8cjw-p6xm) and
`sprintf-js` (moderate, GHSA-hp3w-g68c-fv3c). For those two, no version exists to move to, so they would remain
even after retiring the toolchains below.

**Recommended follow-up, as its own change:** most of this tail is held by two old toolchains — `histoire`
0.17.15 and `eslint` 8.57.0, which is itself end-of-life ("This version is no longer supported", printed by
`pnpm install`). Replacing or retiring those two would close most of the remaining records, including both
criticals. That is a toolchain migration, not a security patch, and doing it inside a pre-deployment pass is
exactly the "broad dependency upgrade" this condition was told to avoid.

### 2.4 NOT APPLICABLE — `@vue/server-renderer`, and a correction

`@vue/server-renderer` is reported **high** across 35 paths, patched `>= 3.5.42`, installed 3.5.12/3.5.13.
Clearing it means moving `vue` itself. It was not moved, because the vulnerable package is not in the deployed
artifact:

- Nothing in `app/javascript` imports `@vue/server-renderer`, `createSSRApp` or `renderToString`. There is no
  SSR anywhere in this product; it is a SPA served by Rails.
- In the built bundle under `public/vite/assets`, the strings `renderToString` and `@vue/server-renderer`
  appear in **zero** chunks. `createSSRApp` and `ssrRender` appear in two, both in the Vue vendor chunk: those
  are Vue core's own runtime-dom exports and hydration hooks, a different package from the one flagged.

`vue` is declared `^3.5.12`, so a routine `pnpm update vue` would resolve to a 3.5.4x and clear this without
any range change. That is a reasonable thing to do on its own schedule. Doing it here, to clear an advisory on
a package that is not executed, is changing the framework version to make an audit count smaller.

**The correction.** During this work an internal classifier reported `markdown-it` as a still-affected *direct
runtime* dependency after the fix. It is not. Reading the advisory's own `findings[].paths` showed every
remaining path runs through `histoire` at `markdown-it@12.3.2`, while the runtime copy is 14.3.2 and clean. The
script had matched by package name instead of by path. It is recorded here because the same mistake is easy to
make from a summary table, and because the same shape of error is corrected again in §2.3.

---

## 3. Summary

| # | condition | verdict |
|---|---|---|
| 1 | Ruby advisory scan run against the live database | **PASS** — run, 4 records, all four classified |
| 2 | The ten removed suppressions re-verified | **PASS** — nine did not reappear |
| 3 | CVE-2026-66066 (`activestorage`) | **FIXED** — Rails 7.2.3.2; 13 gems moved, nothing else |
| 4 | The libvips precondition the fix introduces | **FIXED in the gem, GUARDED on the host** — `ruby-vips` 2.3.0; `deploy.sh` stage 4b; runbook §0.1 |
| 5 | GHSA-42qh-8mx8-7wqm (`rack-proxy`) | **NOT APPLICABLE** — flaw introduced in 1.0.0, advisory lacks `unaffected_versions`. Not suppressed |
| 6 | CVE-2026-67987 / 67989 / 67991 (`ruby_llm`) | **OPEN SECURITY ADVISORY** — see §1.4. Visible in scan output; the one suppression that existed was removed |
| 7 | JavaScript advisory scan run against the real lockfile | **PASS** — run; 126 → 68 records, 140 → 77 paths |
| 8 | Browser-runtime JavaScript advisories | **FIXED** — 12 packages, all inside their major line |
| 9 | Build and development JavaScript advisories | **OPEN, dev/build only** — 68 records in 26 packages, every entry point named in §2.3 |
| 10 | `@vue/server-renderer` | **NOT APPLICABLE** — no SSR, absent from the built bundle |

**Nothing in this document is a REQUIRES REVIEW.** Every finding is either closed, or open with its evidence
and its mitigation stated.

**What this does not claim.** Two scans ran on one day against two databases. A scan is a point in time, and
`docs/p-final/07-release-gate.md` #55 remains open: there is still no automated advisory watch in CI, so the
next regression in this area will be found by whoever next runs these commands by hand.
