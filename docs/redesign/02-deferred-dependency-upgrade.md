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

**CORRECTION — this paragraph previously said the opposite, and it was wrong.** It read: *"per the
advisory's own text the confirmed-affected range is 1.0.0–1.0.2. The locked 0.7.7 matches only
because `patched_versions` carries no `unaffected_versions` entry — a mechanical match, not live
exposure."* An adversarial verifier disproved that by downloading and diffing the real gems rather
than reading the advisory's prose, and its evidence is decisive:

- **The guard added in 1.0.3 is absent from 0.7.7.** `1.0.2 → 1.0.3` adds, in `proxy.rb`, a rejection
  of a backend response carrying both `Transfer-Encoding` and `Content-Length` (`return [502, {}, []]`),
  with the comment *"Net::HTTP dechunks the body but retains the backend's Content-Length."* The anchor
  line above it is byte-identical in 0.7.7, 1.0.2 and 1.0.3. Guard present: 0.7.7 **no**, 1.0.0 no,
  1.0.2 no, 1.0.3 **yes**.
- **The old reasoning quoted the vulnerable line as proof of safety.** `HOP_BY_HOP_HEADERS` includes
  `'transfer-encoding' => true` (`proxy.rb:17`) and `proxy.rb:163` does
  `headers.reject! { |k| HOP_BY_HOP_HEADERS[k.downcase] }`. That stripping IS half the flaw. The bug is
  not a Content-Length rewrite; it is the ABSENCE of reconciliation *while* Transfer-Encoding is
  stripped.
- **0.7.7 shows the pattern in both modes**, including `streaming: true`, which is the default and what
  `vite_rails` uses: `http_streaming_response.rb:31-33` returns `response.to_hash` verbatim and
  `:36-42` reads through Net::HTTP's dechunking reader, then `proxy.rb:163` strips TE with no
  reconciliation.
- So bundler-audit's broad range is **correct here**, and upstream's *"versions before 1.0.0 were not
  assessed … they are not asserted to be unaffected"* was well-founded caution, not a metadata
  oversight.

Two consequences for the isolated PR:

1. **Do NOT file the `unaffected_versions: ["< 1.0.0"]` request with `ruby-advisory-db`.** That asks
   upstream to publish an assertion this diff disproves, suppressing a true finding for every consumer
   of that database.
2. **`docs/pre-deploy/00-security-audits.md` §1.3 carries the same false claim and must be corrected in
   that PR.** It is headed "NOT APPLICABLE", states *"The installed code is not the vulnerable code"*
   and *"The flaw was introduced in 1.0.0"*, and recommends the upstream report in (1). All three are
   wrong on the evidence above. That file is on the base branch and untouched by either redesign PR, so
   the correction belongs with the upgrade, not here — but it must not be left standing.

What does not change: the exposure is still **transitive and dev-only** — `vite_ruby`'s
`rack-proxy (~> 0.6, >= 0.6.1)` cap is the reason 0.7.7 is locked at all, and `ViteRuby#run_proxy?`
mounts the middleware only outside production. And the attribution is unchanged: `Gemfile`,
`Gemfile.lock`, `.bundler-audit.yml` and the workflow are byte-identical at `236b3dd8`, `255d1219`,
`80de56ae`, `98702ccc` and the real head, so none of this is caused by a redesign branch.

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
