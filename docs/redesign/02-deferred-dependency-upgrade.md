# Deferred: the `ruby_llm` 2.x upgrade

**Status:** recorded, not scheduled. Owner's decision: this is a security/maintenance task and must
land as its own isolated, tested PR. It is explicitly NOT part of the redesign and must not block
visual work.

## What is open

`bundle exec bundle-audit check` is the only step that fails the `security-scan` job — the Brakeman
step above it carries `continue-on-error: true`. It reports four advisories:

| gem | advisory | severity | patched |
|---|---|---|---|
| `rack-proxy 0.7.7` | GHSA-42qh-8mx8-7wqm | unknown | `>= 1.0.3` |
| `ruby_llm 1.15.0` | CVE-2026-67987 | High (ReDoS) | `>= 2.0.0.rc1` |
| `ruby_llm 1.15.0` | CVE-2026-67989 | High (ReDoS) | `>= 2.0.0.rc1` |
| `ruby_llm 1.15.0` | CVE-2026-67991 | High (ReDoS) | `>= 2.0.0.rc1` |

The check has failed on **37 of 37** runs since it was added on 2026-09-30. It is not caused by any
redesign branch; the version caps are on the base branch.

## Correct the stale premise first

`.bundler-audit.yml` states the ruby_llm CVEs' *"only patched release is 2.0.0.rc1+"*. **That expired
on 2026-09-18.** When this work is picked up, that comment must be corrected, not copied.

- `ruby_llm` stable: **2.0.0** (2026-09-18), 2.1.0 (2026-10-08), 2.1.1 (2026-10-11).
- `ai-agents` **0.13.0** (2026-10-07) declares `ruby_llm ~> 2.0.0`, lifting the `~> 1.14` cap that
  `ai-agents 0.12.0` imposes. Both Gemfile lines are already open (`>= 0.12.0`, `>= 1.14.1`), so
  nothing in the Gemfile blocks the bump.
- `~> 2.0.0` resolves to exactly **2.0.0** — not 2.1.x.

## Cost, measured

### `rack-proxy` — lockfile only, no code change

`vite_ruby 3.10.3+` dropped the `~> 0.6` cap (latest 3.11.1). `bundle update vite_ruby rack-proxy`
clears it. No `vite_rails` bump needed: locked 3.10.0 already allows `vite_ruby ~> 3.0, >= 3.2.2`.

Worth recording in that PR: per the advisory's own text the confirmed-affected range is
**1.0.0–1.0.2**. The locked 0.7.7 matches only because `patched_versions: [">= 1.0.3"]` carries no
`unaffected_versions` entry — a mechanical match, not live exposure.

### `ruby_llm` — four call sites, one of them a design decision

`bundle update ai-agents ruby_llm`, then:

| file:line | change |
|---|---|
| `lib/captain/base_task_service.rb:94` | `chat.with_tool(tool)` → `chat = chat.with_tools(*tools)` (singular removed) |
| `lib/captain/base_task_service.rb:95` | **`chat.on_end_message { … }` has no 2.0.0 replacement.** `record_generation` must be re-implemented — either after `chat.ask` returns, or via the new `instrumenter` config option. This is the one that needs a decision, and it touches generation recording. |
| `lib/captain/base_task_service.rb:110-111` | `response.input_tokens` / `output_tokens` → `response.tokens.input` / `.output` |
| `lib/integrations/llm_base_service.rb:148-149` | same token-accessor change |

Also: `ruby_llm 2.0.0` drops `ruby_llm-schema` in favour of `schematist ~> 1.1`. `RubyLLM::Schema`
has zero references in the tree, so `gem 'ruby_llm-schema'` (Gemfile:205) can go with it.

## Acceptance for that PR

1. `bundle exec bundle-audit check` exits 0.
2. Captain generation recording still writes a row per generation — the `on_end_message` replacement
   is covered by a test, not assumed.
3. Token accounting still reports input/output per call.
4. `.bundler-audit.yml`'s expired rationale is corrected or removed.
