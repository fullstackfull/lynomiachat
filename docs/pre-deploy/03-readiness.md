# Pre-deploy condition 4 — readiness after the closures

What this branch changed, what was re-verified, what the deployment runbook got wrong, and what still blocks.

**Nothing was deployed. No production host was reached. No flag was activated. No WhatsApp message was sent.
No Stripe configuration was changed. No product semantics changed.**

---

## 1. What this branch changed

Branch `claude/pre-deploy-conditions-closure`, cut from `095a8472` on
`claude/p-final-commercial-release-hardening`. **That branch was not modified.**

### 1.1 Dependencies

| file | change |
|---|---|
| `Gemfile` | `rails` 7.2.3.1 → 7.2.3.2 (CVE-2026-66066) |
| `Gemfile.lock` | the 13 Rails component gems, plus `ruby-vips` 2.1.4 → 2.3.0, which the 7.2.3.2 Active Storage patch requires. Nothing else |
| `package.json` | 6 direct declarations bumped inside their major line; 7 new `pnpm.overrides` entries |
| `pnpm-lock.yaml` | the resulting resolution |
| `.bundler-audit.yml` | one suppression **removed** (CVE-2026-67991); the ten-entry comment block rewritten to record the gate's outcome. Nothing added |

### 1.2 Licence

| file | change |
|---|---|
| `app/javascript/shared/assets/fonts/OFL.txt` | **new** — upstream's `LICENSE.txt` from the exact commit the fonts name, byte for byte |
| `app/javascript/shared/assets/fonts/NOTICE.md` | rewritten: the version read from the binaries, the copyright holder corrected, the served-vs-committed count measured |

### 1.3 Deployment correctness

| file | change |
|---|---|
| `deployment/deploy.sh` | **new stage 4b** — the libvips precondition, checked after the bundle install and before the migrations. **Stage 6b drain probe fixed** — see §3.1 |
| `docs/p-final/08-production-uat-runbook.md` | §0.1 host precondition, §0.2 baselines, §0.3 phase map, §0.4 lever activation, §9a Stripe test-mode pilot, §13a new-contact inbound WhatsApp, §16 renumbered and extended |
| `docs/p-final/09-rollback-and-rollout.md` | observation-window hold points, the baseline source corrected, the phase handoff fixed, one line reference corrected |
| `deployment/ROLLBACK.md` | four confirmed factual errors fixed |

### 1.4 Documentation

`docs/pre-deploy/00`–`03`, plus corrections to `docs/p-final/02-license-audit.md` §5.1/§5.2 and five rows of
`docs/p-final/07-release-gate.md`.

**No file under `app/` except the two font notice files. No file under `custom/`. No migration. No locale
string. No product behaviour.**

---

## 2. Gates, re-run because the dependency graph moved

`docs/p-final/09-rollback-and-rollout.md` #74 records a full green suite at `095a8472`. **That result does not
cover this tree**, because Rails core moved. Everything below was re-run here.

| gate | result | exit |
|---|---|---|
| `bundle exec rspec` (full) | **9715 examples, 0 failures, 70 pending**, in 40m28s | 0 |
| `bundle exec rubocop` | **2899 files inspected, no offenses detected** | 0 |
| `pnpm eslint` | **0 errors**, 478 warnings — the same pre-existing warning count | 0 |
| `npx vite build` | **built in 1m35s** | 0 |
| `pnpm test` | **490 test files, 5293 tests, all passed** — after the fix in §2.2 | 0 |
| `bundle exec bundle-audit check --update` | 4 records, all classified — `00-security-audits.md` §1 | 1, by design |
| `pnpm audit` | 68 records over 77 paths, all classified — `00-security-audits.md` §2 | 1, by design |

### 2.1 Ruby

The suite was run on **this** tree, with Rails at 7.2.3.2 and `ruby-vips` at 2.3.0 — not inherited from
`095a8472`. The 70 pending examples are the pre-existing pending set; no example was skipped, quarantined or
disabled for this branch.

Two notes on getting there, because both are part of the result. `rails db:test:prepare` **aborted** on the
first attempt, with Active Storage's libvips refusal — that is how §3.3 was found, and it is the reason the
previous full-suite result could not be carried over. And the audit commands exit non-zero whenever any
advisory is reported, so exit 1 there is the expected outcome of a tree with documented open advisories, not a
gate failure.

### 2.2 JavaScript — and the regression this branch caused and fixed

The first `pnpm test` run after the JavaScript changes **failed**: 7 tests in
`app/javascript/dashboard/components/widgets/WootWriter/FullEditor.spec.js`, all with

```
RangeError: Can not convert <image> to a Fragment
(looks like multiple versions of prosemirror-model were loaded)
```

**This branch caused it.** The `prosemirror-view` override resolved to 1.42.6, which requires
`prosemirror-model ^1.25.12`, while the lockfile still held `prosemirror-model@1.22.3` for the direct
`devDependencies` entry and for `@chatwoot/prosemirror-schema@1.4.5`. Two copies of `prosemirror-model` loaded
in one runtime, and that library refuses to mix nodes across copies — in the browser as much as in a test.

It is a real editor defect on the clipboard-paste path, not a test artefact. Both declarations are `^1.22.3`,
which **admits** 1.25.12, so one copy satisfies everything: `"prosemirror-model": "^1.25.12"` was added to
`pnpm.overrides`. The lockfile then holds a single copy, and the spec passes 152/152.

**This is the reason PC.8 exists.** A `prosemirror-view` bump that cleared a high-severity advisory and shipped
a broken composer would have been a worse outcome than the advisory.

---

## 3. The deployment runbook, verified against the code

Sixteen items were checked against `deployment/deploy.sh`, `deployment/ROLLBACK.md`,
`08-production-uat-runbook.md` and `09-rollback-and-rollout.md` — in the code, not from the headings.

| # | item | before | after |
|---|---|---|---|
| 1 | **Worker drain at stage 6b**, with the reason (this release deletes a job the previous revision queued with delay and retries) | **YES** | **YES**, plus the fix in §3.1 |
| 2 | Backup before migrations | YES | YES |
| 3 | Backup **verified**, not merely created | YES | YES |
| 4 | Migration execution | YES | YES |
| 5 | Drain/restart sequencing | YES | YES |
| 6 | Readiness check after restart | YES | YES |
| 7 | Sidekiq state including the dead set | PARTIAL | **YES** — the pre-deploy baseline it compares against now exists (runbook §0.2) |
| 8 | Additive-schema rollback strategy | PARTIAL | **YES** — four factual errors fixed, §3.2 |
| 9 | Feature flags initially safe/off | PARTIAL | **YES** — the flag table was already accurate; what was missing is how to turn one on for one account and back off (runbook §0.4) |
| 10 | P8 pilot | PARTIAL | **YES** — now a phase in a sequence (runbook §0.3) rather than a loose exercise |
| 11 | P9 pilot | PARTIAL | **YES** — plus the flag it needs, which it did not name |
| 12 | P10 pilot | PARTIAL | **YES** — same |
| 13 | **P11 Stripe test-mode pilot** | **NO — absent entirely** | **YES** — new runbook §9a, including a deliberately wrong webhook signature as a stop condition |
| 14 | Genuine new-contact WhatsApp UAT | PARTIAL | **YES** — new runbook §13a |
| 15 | Defined observation window | PARTIAL | **YES** — hold points in `09` §4 |
| 16 | Rollback / NO-GO conditions | YES | YES |

### 3.0 The structural gap that mattered most

Four UAT sections instructed the operator to exercise surfaces whose capability **is not granted by default**,
and no step in the document granted it:

| section | capability | what the surface does while the account lacks it |
|---|---|---|
| §4 audit trail read | `audit_logs` (`features.yml:112-115`, `premium`) | `AuditTrail::Query` returns `Custom::AuditLog.none`, so the page shows zero rows whatever the table holds |
| §6 permission sets | `custom_roles` (`:148-151`, `premium`) | all five endpoints raise `Pundit::NotAuthorizedError` |
| §7 support cases | `lynomia_support_tickets` (`:304-307`) | every support endpoint 404s |
| §8 identity | `lynomia_unified_identity` (`:308-311`) | both identity writers refuse |

**Stated precisely, because the first draft of this section overstated it.** `config/features.yml`'s
`enabled:` value is not a code gate: `Featurable` loads it into `FEATURE_LIST` and it seeds the
`ACCOUNT_LEVEL_FEATURE_DEFAULTS` row that `before_create :enable_default_features` applies to **newly created**
accounts (`app/models/concerns/featurable.rb:13,53,115-121`). The actual gate is the account's own
`feature_flags` / `feature_flags_ext_1` bitfield, read by `feature_enabled?` (`:95-97`). So the correct
statement is **conditional**: these four sections pass only if the nominated test account carries the bit, and
with the shipped defaults a freshly created one does not.

The practical consequence was the same either way — an operator working the document in order on a new test
account would have hit four sections that refuse, with no written instruction for any of them, and §4's first
expectation ("the page loads | rows, newest first") directly contradicted the runbook's own caveat 25 lines
later.

**And the lever was already in the same document, in the wrong place.** `lynomia_support_tickets` and
`lynomia_unified_identity` carry no `premium:` key, so they are in `BillingPlan.assignable_features` and
`Billing::OverrideGrant#grant!` accepts them, calling `enable_features!` — which is precisely the Super Admin
override the runbook already exercises at §9 ("Super Admin → account → grant an override | the account gains
the capability"). §9 came **after** §7 and §8 in document order, and §7/§8 never named their capability. Runbook
§0.4 now gives the per-account enable and the undo up front, and §0.3 places each section in the rollout
sequence.

**And the handoff between the two documents was broken.** `09` §6 said to "work
`08-production-uat-runbook.md` from PHASE 2 onwards" and "enable nothing until PHASE 6". The runbook has no
phases — it is §0–§16 and the string "PHASE" appeared **zero** times in it. So the only document specifying the
flags-off pilot sequence delegated the order to a structure that did not exist. §0.3 is the map; `09` §6 now
points at it.

**Baselines were ordered but not taken.** `09`:194 says "take the baselines in §4 before running the deploy.
Without them, §4 cannot be read", and both documents compare the dead set against "the pre-deploy number". The
runbook's only pre-deploy capture was `Sidekiq::Stats.new.queues.inspect` — **nine of the ten signals in `09`
§4 had no baseline step at all**, so the comparison both documents rest on was impossible as written. `09`:155
also treated the deploy script's own post-restart print as a baseline, which it is not. Runbook §0.2 now
captures queues, enqueued, scheduled, retry, dead, processed, failed, operations signals, billing webhook
events, per-inbox inbound counts and audit rows.

### 3.1 Two defects in the deploy script's drain path

Both in stage 6b, the stage this release most depends on.

**The probe's own failure was reported as a drain.** The loop read
`busy="$(as_app '…' 2>/dev/null || echo 0)"` and then broke on `"$busy" == "0"` printing
"sidekiq: in-flight set drained". A Redis refusal or a `rails runner` exception produced `0` and announced
success — the exact reading stage 6b exists to rule out. It now distinguishes a numeric answer from no answer,
reports an unreadable probe as unknown, and keeps asking.

**The 60-second cap had no instruction attached.** It printed "restarting anyway" and continued, with nothing
in either document telling the operator what to do — even though the whole point of 6b is that restarting under
load double-sends WhatsApp messages. There is now a `WARNING`, a new `REQUIRE_DRAIN=1` that turns it into a
refusal for an unattended deploy, and runbook **§16** with three ordered options. §16 also moved: it used to
sit after §15, so the one instruction that must be read *before* the restart was read after it.

**One ordering fact neither document stated:** 6b runs *after* the migrations (stage 5), so the old worker code
drains against the already-migrated schema. That is safe here because the release is additive — but it was safe
by accident of reading, not by statement. It is now stated in §16.

### 3.2 Four factual errors in `deployment/ROLLBACK.md`, each confirmed against the code

| claim | reality |
|---|---|
| "two that edit an installation config row", listing four migrations | **one** does: `db/migrate/20261011160000` edits `ACCOUNT_LEVEL_FEATURE_DEFAULTS`. And `custom/db/migrate/20261011140000` is **not additive** — it drops and re-adds two foreign keys to change their `on_delete` |
| all four cited under `db/migrate/` | **three of the four are under `custom/db/migrate/`** |
| "only the three `CONCURRENTLY` index builds" | there are **four** — two in `…150000` (`audits`), two in `…150100` (`campaign_recipients`). An operator clearing INVALID indexes by a count of three stops one short |
| a post-rollback re-run "aborts at stage 3" | it aborts in **stage 1**, at `RELEASE_SHA="$(as_app 'git rev-parse @{u}')"` (`deploy.sh`:90) — a detached HEAD has no upstream and `set -Eeuo pipefail` turns that into an abort. Before the backup, before the checkout. Stage 3 is the `git merge --ff-only` line the script never reaches. The paragraph containing this error advertised itself as correcting an earlier inaccuracy |

All four are now correct, and `09`:34's reference to `query.rb:41` is corrected to
`custom/app/services/audit_trail/query.rb:52`.

### 3.3 The new host precondition, which is the most important line in this document

Rails 7.2.3.2's Active Storage **refuses to load** unless libvips ≥ 8.13 and `ruby-vips` ≥ 2.2.1. The gem half
is fixed in the lockfile. **The libvips half is a system package on the production host, and nothing in this
repository can install it.** Every Rails process aborts on an old libvips — web and worker — so an unchecked
deploy turns the restart into an outage with no rollback of its own.

This was found by running `rails db:test:prepare`, not by reading a changelog. `deploy.sh` stage 4b now fails
the deploy with the remedy, after the backup and before any schema change; runbook §0.1 tells the operator to
check it before the window opens.

**Verify libvips on the production host before scheduling the deploy.** This container has 8.15.1; the
production host's version is not known from here.

---

## 4. What still blocks, and what does not

### 4.1 Does not block a controlled deployment

| item | why not |
|---|---|
| The three `ruby_llm` ReDoS advisories | availability-only; measured linear on Ruby 3.4.4; no LLM credential is configured, so the code does not run. `00-security-audits.md` §1.4 |
| `rack-proxy` GHSA-42qh-8mx8-7wqm | not the vulnerable code; the advisory's own text dates the flaw to 1.0.0 |
| 68 JavaScript advisories | every entry point is a build or development tool; none is in the deployed artifact |
| `@vue/server-renderer` | no SSR; absent from the built bundle |
| The transitive licence tally (`#52`) | a scoping decision, not a defect |
| **The six product rules** | the product ships today with these semantics. Each is a decision about whether to change them, not a defect that must be fixed first — with the one qualification below |

### 4.2 Blocks, or must be answered first

| # | item | nature |
|---|---|---|
| 1 | **libvips ≥ 8.13 on the production host** | **hard blocker.** Not checkable from here. The deploy aborts at stage 4b if it is missing — which is the designed behaviour, but it means the deploy does not complete until the host is upgraded |
| 2 | **RULE 1** — `conversation_*` capabilities | **not a blocker for deployment; is a blocker for selling the restriction.** Today's behaviour is a privilege boundary the UI displays and the server does not enforce. It is not an escalation and not a regression, and it ships that way today. But if `custom_roles` is being sold on "restrict agents to their own conversations", that claim is not true of the API, and the honest options are to make it true (RULE 1 option A) or to stop making it |
| 3 | `07-release-gate.md` #55 | no automated advisory watch in CI. Both scans here were run by hand; the next regression will be found the same way |
| 4 | `07-release-gate.md` #71 | nothing has been exercised against production. That is this release's whole remaining risk and the runbook is what retires it |

**Nothing in the four closed conditions blocks a controlled deployment, with the single exception of the
libvips host precondition — which is new, was introduced by the security fix itself, and is the reason this
document exists.**

---

## 5. Verdicts

| | |
|---|---|
| **PRE-DEPLOY CONDITIONS** | **CLOSED.** All four conditions are addressed: both audits run with network access and every finding classified; the Inter OFL committed byte-for-byte from the version-matched upstream commit; all six product rules documented with options and recommendations; the runbook re-verified against the code, with one `NO`, eight `PARTIAL`s, four factual errors and two deploy-script defects found and fixed |
| **CONTROLLED DEPLOYMENT** | **READY, conditional on one host check.** Confirm libvips ≥ 8.13 on the production host, then work `08-production-uat-runbook.md` from §0. Not ready without that check |
| **COMMERCIAL RELEASE** | **NOT YET.** Two things stand between here and selling it: the six product decisions, of which RULE 1 is the one with a security boundary in it and RULE 4 the one with a licence position in it; and a successful controlled deployment with UAT, which `07-release-gate.md` #71 is still open on |

**No deployment was performed in this session.**
