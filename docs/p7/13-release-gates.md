# P7 — Full release gates on a clean tree

Every gate re-run at the final tree of this session, with `git status --porcelain` carrying only the files this
session intends to commit. Where a gate could not be run here, it says so rather than being left out.

## Static analysis and formatting

| Gate | Command | Result |
| --- | --- | --- |
| Ruby style, whole repository | `bundle exec rubocop --parallel` | **3515 files inspected, no offenses detected** |
| JavaScript and Vue | `npx eslint app/javascript --ext .js,.vue` | **0 errors**, 517 warnings |
| Prettier, on every `.js` / `.vue` file this session touched | `npx prettier --check` | clean |

Prettier's remit in this repository is `app/**/*.{js,vue}` (`package.json` → `lint-staged`). The
documentation corpus under `custom/db/documentation/` is hand-wrapped and all 57 of its English articles are
prettier-nonconforming, so it is not a gate there and reformatting it would be a 57-file diff with no owner.

The 517 eslint warnings are all `@intlify/vue-i18n/no-dynamic-keys`, spread across the codebase and pre-existing:
the repository ships with them, the rule is configured as a warning rather than an error, and building a
translation key from a variable is how the status, priority and delivery-status option lists are all written. The
count is reported rather than hidden; what matters for a gate is that there are no errors.

## Test suites

| Gate | Result |
| --- | --- |
| JavaScript, full suite (`npx vitest run`) | **500 files, 5253 tests, 5253 passed** |
| Ruby, full suite (`bundle exec rspec`) | run three: **11,269 examples, 2 failures, 70 pending** in 34m09s — both attributed; see `14-readiness-matrix.md` §"What the full suite found" |

The Ruby suite ran with the overlay composed the way production composes it — `enterprise` and `custom` both
active — which is deliberate: the upstream FOSS workflow deletes `enterprise/` before running, so it never
exercises the `prepend_mod_with` composition this installation actually boots with.

## Build

| Gate | Result |
| --- | --- |
| `npx vite build` (production) | **exit 0**, `public/vite/.vite/manifest.json` with 218 entries |
| `pnpm build:sdk` | **exit 0**, `public/packs/js/sdk.js` at 22.00 kB (7.03 kB gzipped) |
| build artefacts leave the tree clean | `git status --porcelain` empty — both outputs are gitignored |

The SDK build is the one the previous deploy script omitted: `public/packs/js/sdk.js` is the script customers embed
on their own sites, it comes from its own Vite pipeline rather than from `vite build`, and it is gitignored — so a
deploy that skips it leaves every customer site on the previous widget indefinitely. It is now both in the deploy
script and in this gate list.

Rollup warns that some chunks exceed 500 kB after minification. That is upstream's bundling, unchanged by this
work, and it is a performance note rather than a gate failure.

## API document

| Gate | Result |
| --- | --- |
| `rake swagger:build` then `git status swagger/` | **empty** — the committed document is in sync with its YAML sources |
| `openapi-generator-cli 7.19.0 validate` — the exact command CI runs | **"No validation issues detected."** |
| OpenAPI 3.1 meta-schema, via skooma | pass |
| every published operation resolves to a real route | 149 / 149 |

## Dependency audit — the one gate that does not pass

`bundle exec bundle-audit check` reports **three advisories**. Neither was introduced by this work, and the
standing instruction is not to upgrade a version without evidence, so each was assessed for reachability rather
than bumped.

### `rack-proxy 0.7.7` — not reachable in production. Proven.

GHSA-42qh-8mx8-7wqm, HTTP response smuggling, fixed in 1.0.3. It is a transitive dependency of `vite_ruby`, which
uses it for `ViteRuby::DevServerProxy`. That middleware is inserted only `if ViteRuby.run_proxy?`, and
`run_proxy?` is `config.mode == "development" || (config.mode == "test" && !ENV["CI"])`.

Booted in production mode to check rather than reasoning from the source:

```
run_proxy?=false
DevServerProxy mounted=false
```

So the vulnerable class is not in the production middleware stack at all. **Not exposed.** Upgrading would still
be tidy, and it is a `vite_ruby` dependency bound at `~> 0.6`, so it is not a change this project can make
unilaterally.

### `ruby_llm 1.15.0` — two High ReDoS advisories, and the fix is a release candidate

CVE-2026-67987 and CVE-2026-67989, both polynomial-time ReDoS, both fixed in **`>= 2.0.0.rc1`**.

This one is loaded in production: `ruby_llm` is a direct dependency and `RubyLLM` is used throughout
`enterprise/app/services/captain/` and `enterprise/app/services/llm/`. But the path is gated twice:

- every Captain feature flag ships **disabled** (`captain_integration`, `captain_integration_v2`,
  `captain_v1_action_classifier`, `captain_document_auto_sync` are all `enabled: false`, `premium: true` in
  `config/features.yml`), and
- `CAPTAIN_OPEN_AI_API_KEY` is seeded with **no value**.

So on an installation that has not deliberately enabled Captain and supplied a key, no LLM request is made and the
vulnerable regexes are never fed. That is a configuration-dependent mitigation, not a fix, and it is stated as
such.

**The upgrade is not made here, deliberately.** The only published fix is a release candidate of a new major
version of the LLM client. Taking an RC major bump as part of a release whose whole point is to be verifiable is
the blind upgrade the brief forbids: it would need its own evidence, its own regression pass over every Captain
surface, and a decision about shipping an RC at all. That is a decision for the operator, with a named condition:

> **If Captain is enabled on this installation, `ruby_llm` must be addressed before that happens.** If Captain
> stays off, the advisories are present in the bundle and unreachable.

This is why the verdict below is not an unqualified GO.

## What could not be gated here

| Gate | Why |
| --- | --- |
| CircleCI's own pipeline | the swagger and rspec jobs are CircleCI-only and CircleCI does not appear to run on this fork; the two checks it performs on `swagger/` were replicated locally and in the suite |
| GitHub Actions | the one workflow that runs the backend suite on a feature branch deletes `enterprise/` first, so it never tests the composition production boots with |
| Brakeman | configured `continue-on-error: true` upstream with 35 findings awaiting triage, so it cannot fail a build and was not treated as a gate |
| a real deploy | no systemd, no production database, no nginx here — see `12-deployment-validation.md` |
