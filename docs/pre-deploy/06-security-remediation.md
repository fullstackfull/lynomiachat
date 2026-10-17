# Security remediation — `security-scan` dependency advisories

`docs/pre-deploy/00-security-audits.md` classified four `bundle-audit` findings and closed none of them: one
as NOT APPLICABLE and unfixable, three as an OPEN SECURITY ADVISORY awaiting a major upgrade. Both verdicts
were correct when written. Both have been overtaken by upstream releases. This document records the
remediation, the evidence behind it, and what remains unverified.

**All four findings are now closed.** `bundle exec bundle-audit check` reports `No vulnerabilities found`.
Nothing was suppressed. **No ignore entry was added to `.bundler-audit.yml`** — its three pre-existing
entries are unchanged, and the only edit to that file is to a comment that described the `ruby_llm`
advisories as open. No `brakeman.ignore` was created.

---

## 1. Summary

| finding | gem, before → after | verdict |
|---|---|---|
| GHSA-42qh-8mx8-7wqm | `rack-proxy` 0.7.7 → **2.0.1** | **FIXED** — a real defect in 0.7.7, not a false positive (§2) |
| CVE-2026-67987 | `ruby_llm` 1.15.0 → **2.0.0** | **FIXED** — vulnerable code removed upstream |
| CVE-2026-67989 | `ruby_llm` 1.15.0 → **2.0.0** | **FIXED** — was unreachable; now also absent |
| CVE-2026-67991 | `ruby_llm` 1.15.0 → **2.0.0** | **FIXED** — named site was never present in 1.15.0 |
| Brakeman "Possible SQL injection" | `docs/commerce/e2e/realtime/sims.rb:100` | **NOT APPLICABLE** — verified false positive, not suppressed |

Full dependency delta, both commits combined:

| gem | before | after |
|---|---|---|
| `rack-proxy` | 0.7.7 | 2.0.1 |
| `vite_ruby` | 3.10.2 | 3.10.6 (held below 3.11.1 — see §2.1) |
| `ruby_llm` | 1.15.0 | 2.0.0 |
| `ai-agents` | 0.12.0 | 0.13.0 |
| `ruby_llm-schema` | 0.3.0 | 1.0.0 |
| `schematist` | — | 1.1.0 (new, transitive) |
| `dry-cli` | 1.1.0 | 1.4.1 (transitive of `vite_ruby`; used only by the `vite` CLI) |

`vite_rails` stays on 3.10.0. Both resolves used `--conservative`, so no other gem in the lockfile moves — in
particular the five collateral bumps an unconstrained `ruby_llm` resolve pulls in (`json`, `zeitwerk`,
`marcel`, `faraday`, `uri`) did not happen. `Gemfile` itself is unchanged; both existing constraints
(`gem 'ai-agents', '>= 0.12.0'`, `gem 'ruby_llm', '>= 1.14.1'`) already admit the new versions.

---

## 2. `rack-proxy` — GHSA-42qh-8mx8-7wqm

### What the advisory actually says

`ruby-advisory-db/gems/rack-proxy/GHSA-42qh-8mx8-7wqm.yml` sets `patched_versions: [">= 1.0.3"]` and carries
**no `unaffected_versions` key**, so `bundler-audit` reports every version below 1.0.3 — including the whole
0.x line. Its own notes are narrower than that:

> Confirmed affected: rack-proxy 1.0.0, 1.0.1, and 1.0.2. Fixed in the 1.x series: 1.0.3 … Versions before
> 1.0.0 were not assessed for this advisory; **they are not asserted to be unaffected.**

§1.3 of `00-security-audits.md` read this as "the installed code is not the vulnerable code". **That is
wrong, and it was checked rather than assumed.** Reading `rack-proxy` 0.7.7's own
`lib/rack/proxy.rb`, the defect the advisory describes is present verbatim:

```ruby
HOP_BY_HOP_HEADERS = { ... 'transfer-encoding' => true, ... }.freeze   # :10-19

headers = self.class.normalize_headers(... target_response.to_hash)   # :157 keeps backend Content-Length
body    = target_response.body || [""]                                 # :158 already dechunked by Net::HTTP
headers.reject! { |k| HOP_BY_HOP_HEADERS[k.downcase] }                 # :163 strips TE, keeps Content-Length
```

There is **no ambiguous-framing guard anywhere in 0.7.7**. The 1.0.3 fix adds exactly that guard before the
hop-by-hop strip:

```ruby
if headers.key?("Transfer-Encoding") && headers.key?("Content-Length")
  target_response.close if target_response.respond_to?(:close)
  return [502, {}, []]
end
```

So the advisory's "versions before 1.0.0 were not assessed" is not a reprieve: the vulnerable code shape is in
the installed version, in both streaming and `streaming: false` modes. This was a real defect, not a scanner
artefact — which makes the upgrade a fix rather than a way of quieting a false positive.

### Why it is fixable now and was not before

`vite_ruby` 3.10.2 constrained `rack-proxy` to `~> 0.6, >= 0.6.1`, and `~> 0.6` forbids 1.0.3 outright — the
blocker §1.3 recorded. **`vite_ruby` relaxed that constraint to `>= 0.6.1` in 3.10.6.** The pin no longer
exists, so the advisory's own remedy became reachable.

### Compatibility, verified against gem source

`rack-proxy` 2.x refuses a Host-derived backend with a 502 unless opted in. The guard is reached only when the
backend is `nil` (`lib/rack/proxy.rb:297-313`):

```ruby
backend = env.delete("rack.backend") || @backend
if backend.nil?
  unless @allow_dynamic_backend
    return [502, {}, []]
  end
end
unless backend_allowed?(backend)   # defaults to true
```

`ViteRuby::DevServerProxy#forward_to_vite_dev_server` assigns `env["rack.backend"] = URI(config.origin)`
before calling `super`, so `backend` is non-nil and the guard never fires. The subclassed API —
`initialize`, `call`, `rewrite_env`, `rewrite_response`, `perform_request` — is unchanged in 2.0.1.

### 2.1 Why `vite_ruby` is held at 3.10.6 and not the latest

The first attempt took `vite_ruby` to 3.11.1, the newest release. **That breaks Rails boot in every
environment**, and CI caught it:

```
ArgumentError: vite-plugin-ruby@^5.2.1 might not be compatible with vite_ruby-3.11.1
  vite_ruby-3.11.1/lib/vite_ruby/compatibility_check.rb:24
  vite_rails-3.10.0/lib/vite_rails/engine.rb:38
  config/environment.rb:5
Tasks: TOP => db:create => db:load_config => environment
```

3.11.1 raised `DEFAULT_PLUGIN_VERSION` from `^5.2.0` to `^5.2.5`, while `package.json:152` declares
`vite-plugin-ruby "^5.2.1"` and `skipCompatibilityCheck` is set nowhere (gem default `false`).
`ViteRuby::CompatibilityCheck.verify_plugin_version` reads the **declared range**, not what pnpm installed,
so `pnpm install` cannot fix it — `package.json` would have to change. `vite_rails/engine.rb:38` calls
`ViteRuby.config` unguarded, so the raise aborts `rails server`, `rails console`, `rspec`, `rake db:create`
and `rake assets:precompile`, including the production Docker build.

**Note how it presents in CI:** `security-scan` went **green** (neither Brakeman nor bundle-audit boots
Rails) while all 16 `backend-tests` shards went red. A green security job is not evidence that a dependency
bump is safe.

3.10.6 is the narrowest version that solves the original problem: it keeps `DEFAULT_PLUGIN_VERSION` at
`^5.2.0`, and it already carries the relaxed `rack-proxy (>= 0.6.1)` constraint. 3.11.0 would also work, but
3.10.6 is a patch-level move from the installed 3.10.2 and avoids 3.11.0's dev-server-detection rewrite.

`Gemfile` therefore gains one explicit constraint, `gem 'vite_ruby', '~> 3.10.6'`, with a comment recording
why, so a later `bundle update` cannot silently reintroduce the break. Lift it together with a
`vite-plugin-ruby` bump in `package.json`.

### Exposure

**Negligible; development only.** `vite_rails/engine.rb:7` is the sole middleware insertion site:

```ruby
app.middleware.insert_before 0, ViteRuby::DevServerProxy, ssl_verify_none: true if ViteRuby.run_proxy?
```

`run_proxy?` is `alias_method :run_proxy?, :dev_mode?` (`vite_ruby.rb:110`), and `dev_mode?` is
`config.mode == "development" || (config.mode == "test" && !ENV["CI"])` (`vite_ruby.rb:103-104`).
`vite_rails/config.rb:12` sets `mode: Rails.env.to_s`, so in production the guard is false. Because it is a
modifier `if`, the constant is never even resolved, and `require "rack/proxy"` (the gem's only require of it,
in `dev_server_proxy.rb:3`) never runs. `rack-proxy` code is not loaded in the production process at all.

`docker/Dockerfile` sets `RAILS_ENV=production` and precompiles assets; `Procfile` has no vite process and
`config/vite.json` declares only `development` and `test` blocks. No production path reaches it.

---

## 3. `ruby_llm` — CVE-2026-67987, CVE-2026-67989, CVE-2026-67991

CVSS 7.5 each, polynomial ReDoS, availability only. Patched release `>= 2.0.0.rc1`; the stable `2.0.0` is what
was taken.

### 1.16.0 was checked first and does not fix them

A minor bump would have been far cheaper. It is not available: `providers/openai/chat.rb:228-229` in 1.16.0
carries the identical pair from 1.15.0:213-214 —

```ruby
thinking = text.scan(%r{<think>(.*?)</think>}m).join
content  = text.gsub(%r{<think>.*?</think>}m, '').strip
```

In 2.0.0 the `<think>` pattern is absent from `lib/` entirely. **2.0.0 is a real code fix, not a version-number
bump.** It is also below the advisory's `>= 2.0.0.rc1` threshold, so 1.16.0 would not have cleared the scanner
either way.

### What the three advisories map to in the installed 1.15.0

| CVE | named site | present in 1.15.0? | reachable? |
|---|---|---|---|
| 2026-67987 | `providers/openai/chat.rb:210-217`, think-tag `scan` + `gsub` | **yes** | yes, but on the **provider's response**, not user input |
| 2026-67989 | `providers/mistral/capabilities.rb` matching | yes | **no** — Mistral is not a configured provider |
| 2026-67991 | `Utils.underscore`, `gsub(/([A-Z]+)([A-Z][a-z])/, …)` | **no — absent** | n/a |

CVE-2026-67991 deserves a note. `lib/ruby_llm/utils.rb` in 1.15.0 defines `hash_get`, `to_safe_array`,
`to_time`, `to_date`, `deep_merge`, `deep_dup`, `deep_stringify_keys`, `deep_symbolize_keys` — there is no
`underscore`. The method **first appears in 2.0.0** (`lib/ruby_llm/support/utils.rb:27`), and it is not in
`ai-agents` 0.12.0 or 0.13.0 either. The advisory range therefore appears over-broad for 1.15.0, the same
metadata problem as the `rack-proxy` entry.

This raised the obvious question of whether the upgrade *introduces* the vulnerable method. It does not —
2.0.0's implementation is the patched one, built from zero-width lookarounds with no quantifier to backtrack
on:

```ruby
UNDERSCORE_BOUNDARY = /(?<=[a-z\d])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])/
def underscore(name) = name.gsub(UNDERSCORE_BOUNDARY, '_').downcase
```

### Exposure before the fix

**Negligible, and lower than §1.4 recorded.** Two corrections to the earlier assessment:

1. §1.4 described the risk as "CPU exhaustion in a Sidekiq worker". The five Captain endpoints
   (`app/controllers/api/v1/accounts/captain/tasks_controller.rb:5,16,25,35,44`) call `.perform`
   **synchronously in the request thread**, not via Sidekiq. The blast radius is a request thread, not a
   queue. It is still bounded: `authorize(:'captain/tasks')` (`:69`) restricts it to authenticated agents and
   admins — an end customer cannot reach it.
2. The one advisory with live code, CVE-2026-67987, parses the **LLM provider's response**
   (`openai/chat.rb:65` → `extract_content_and_thinking(message_data['content'])`), not customer text. Customer
   text travels outbound via `chat.ask` (`base_task_service.rb:78`). Triggering it requires controlling the
   OpenAI response body. `CAPTAIN_OPEN_AI_ENDPOINT` is an `InstallationConfig` read (`lib/llm/config.rb:48`),
   super-admin only; the account-level `openai` hook supplies an API key and never a base URL
   (`base_task_service.rb:192`), so a tenant cannot redirect the endpoint.

Both mitigations named in §1.4 remain true: Ruby 3.4.4's regexp optimizer keeps all three linear (re-measured
on this branch: 56 KB → 6.7 ms, 3.5 MB → 457 ms, i.e. linear in input size), and `captain_tasks` ships
disabled in `config/features.yml`.

### Migration — four removed APIs across six files

Each replacement was read out of the installed 2.0.0 gem, not inferred:

| call site | 1.15.0 | 2.0.0 |
|---|---|---|
| `lib/captain/base_task_service.rb:92` | `chat.with_tool(tool)` | `chat.with_tools(*tools)` (`chat.rb:341`, returns `self`) |
| `lib/captain/base_task_service.rb:93` | `chat.on_end_message { }` | `chat.after_message { }` (`chat.rb:670`) |
| `lib/captain/base_task_service.rb:111-113` | `response.input_tokens` | `response.tokens.input` |
| `lib/captain/tool_instrumentation.rb:49-50` | `message.input_tokens` | `message.tokens.input` |
| `lib/integrations/llm_instrumentation_spans.rb:108-109` | `message.input_tokens` | `message.tokens.input` |
| `lib/integrations/llm_base_service.rb:149-151` | `response.input_tokens` | `response.tokens.input` |
| `lib/tasks/ruby_llm.rake:13` | `RubyLLM.models.refresh!` | `RubyLLM.models.refresh` (`models.rb:143`) |

**Two of these are not in §1.4's migration table.** `lib/captain/tool_instrumentation.rb:49` was unguarded and
would have raised `NoMethodError` on the first instrumented generation.
`lib/integrations/llm_instrumentation_spans.rb:108-109` is `respond_to?`-guarded and would have failed silently
instead, dropping token telemetry with no error — the worse of the two outcomes.

Nil behaviour is preserved. `Message#initialize` always assigns a `Tokens`
(`options[:tokens] || Tokens.new(...)`, `message.rb:94`), and `Tokens#input`/`#output` default to `nil`
(`tokens.rb:59`) — the same `nil` the old readers could return, so the existing `|| 0` arithmetic is unchanged.

Unchanged and verified present in 2.0.0: `RubyLLM.context`, `RubyLLM.configure` (`lib/llm/config.rb:24,35`),
`ask`, `with_instructions`, `with_schema`, `add_message`, `Models.save_to_json`, `Models.all`.

**Not required.** This application does not use `ruby_llm`'s ActiveRecord integration — `acts_as_chat`,
`acts_as_message` and `RubyLLM::ActiveRecord` appear nowhere in `app/`, `lib/`, `custom/`, `db/` or `config/`.
The 2.0 upgrade generator and its database migrations therefore do not apply, and **no migration is needed for
this deploy**. No caller passes `schema:`, so the `ruby_llm-schema` → `schematist` rename is inert here.

---

## 4. Brakeman — `docs/commerce/e2e/realtime/sims.rb:100`

**Verified false positive. Not suppressed; no `brakeman.ignore` was created.**

This never blocked CI: the step is `continue-on-error: true` in `.github/workflows/run_foss_spec.yml`, with a
comment recording 35 pre-existing findings. Only `bundle-audit` turns `security-scan` red.

The flagged line is `sim.count("#{request.method.upcase} #{request.uri.path} (outage)")`. Verified
independently:

1. `sim` is a plain Ruby Module — `SIMS = { 'salla' => SallaSim, … }.freeze` (`sims.rb:88`), bound by
   `SIMS.each do |provider, sim|` (`:95`). No `ApplicationRecord` ancestry, so
   `ActiveRecord::Calculations#count` is never in the lookup chain.
2. `count` is `redis.hincrby("#{PREFIX}::REQUESTS", name, 1)` (`sims.rb:74`). **No SQL executes on this path.**
   The value is a Redis HINCRBY *field name*, serialised by redis-rb as a length-prefixed RESP bulk string —
   never concatenated into a query language.
3. `request` is a `WebMock::RequestSignature` describing an **outbound** request the app's own commerce
   clients make, intercepted in-process (`sims.rb:28`). It is not attacker-controlled.
4. The file `require`s `webmock`, a `group :test` gem (`Gemfile:247-251`), so it **cannot load under a
   production bundle**. `docs/` is in no eager-load path (`config/application.rb:42,46`).

Brakeman reaches it only because it scans the repository tree. The same pattern is already reported at
`docs/commerce/e2e/zid/zid_sim.rb:34` and `docs/commerce/e2e/shopify/shopify_sim.rb:45`.

Action taken: a three-line comment at the `count` definition recording why the warning appears and why there is
no SQL, so the next reader does not repeat this investigation. A `brakeman.ignore` entry was deliberately
**not** added — it would suppress 3 of 35 findings on an arbitrary basis, and this repository's stated posture
is to leave findings visible and explained.

---

## 5. Testing

| check | result |
|---|---|
| `bundler` dependency resolution | **PASS** — both resolves succeeded with `--conservative` |
| `bundle-audit check` | **PASS** — `No vulnerabilities found` (was 4 findings) |
| Ruby syntax, all changed files | **PASS** |
| Backend specs, lint, frontend — CI | see the pull request; CI is the system of record |
| Brakeman | unchanged, non-blocking, 35 pre-existing findings |

Verified locally on Ruby 3.4.4 with `bundler` 2.5.16 and `bundler-audit` 0.9.3 against ruby-advisory-db commit
`a6847b0`, the same database CI fetches.

### Unverified

**The live provider protocol is NOT verified.** Every Captain spec mocks the provider with `instance_double`,
and this environment has no OpenAI key. `instance_double` is a *verifying* double, so it does confirm that the
2.0.0 methods it stubs genuinely exist on `RubyLLM::Message` and `RubyLLM::Chat` — a real check on the
rename — but it cannot exercise a request/response round trip against OpenAI.

**This is the gate to clear before `captain_tasks` is enabled for any account.** Exercise the five
`tasks_controller` endpoints (`rewrite`, `summarize`, `reply_suggestion`, `label_suggestion`, `follow_up`)
against a live key and confirm both the response text and the recorded `prompt_tokens` / `completion_tokens`.
`captain_tasks` ships disabled, so no account exercises this path on deploy as shipped.

One behaviour change to watch for there: `Message#content` in 2.0.0 is documented as returning an **empty
string** for assistant messages that only request tool calls, where 1.x returned `nil`.

---

## 6. Deployment risk and rollback

**Risk: low.**

- `rack-proxy` / `vite_ruby` — no production code path; development asset proxy only (§2). Worst case is a
  broken local dev server, visible immediately and to developers only.
- `ruby_llm` / `ai-agents` — reachable in production, but only through `captain_tasks`, which ships disabled.
  With it disabled the changed code does not execute.
- No database migration. No schema change. No change to Stripe credentials, prices, plans, subscription
  statuses, invoices, or any customer data. Nothing in `enterprise/` or the Odoo integration is touched.

**Rollback.** Both commits are lockfile-and-code only, so reverting restores the previous gem set exactly:

```
git revert 51be4f79   # ruby_llm 2.0.0 migration
git revert db806373   # rack-proxy / vite_ruby
bundle install
```

Revert the `ruby_llm` commit alone if a Captain regression appears; it is independent of the `rack-proxy`
commit and touches a disjoint set of files. After either revert, `bundle-audit` reports the corresponding
findings again — which is the intended behaviour, not a regression to hide.

---

## 7. Remaining security concerns

1. **The live-provider gate above.** The single open item, and the reason `captain_tasks` should not be
   enabled for an account until it is cleared.
2. **`Regexp.timeout` is still unset.** §1.4 named it as the cheapest belt-and-braces mitigation. It is not
   applied: the measured behaviour is linear on Ruby 3.4.4, and the three advisories are now closed, so a
   guard against an absent condition would mislead a later reader. It remains available if a global bound is
   wanted on its own merits.
3. **Two upstream advisories carry ranges broader than their own evidence** — `rack-proxy`
   GHSA-42qh-8mx8-7wqm (no `unaffected_versions`, 0.x never assessed) and `ruby_llm` CVE-2026-67991 (names a
   method absent from 1.15.0). Worth reporting to `ruby-advisory-db` so the next consumer is not misled.
   Neither affects this repository now, since both gems moved past the advised versions.
4. **Brakeman's 35 pre-existing findings, 13 at High confidence,** are still untriaged, which is why the step
   is non-blocking. Out of scope here; this document settles only the one finding named in the brief.
