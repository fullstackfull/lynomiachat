# P-FINAL.0 — Repository and release baseline

Every number in this document was measured on this tree, with the command shown. Nothing here is carried over
from an earlier phase's report without being re-measured, because the point of a baseline is that it is
checkable by someone who does not trust the previous phase.

---

## 1. Branch and ancestry

| | |
|---|---|
| Branch | `claude/p-final-commercial-release-hardening` |
| Created from | `8bb3b49e` (the completed P11 tip, `origin/claude/p11-saas-commercialization`) |
| HEAD at baseline | `8bb3b49e` |
| Production revision | `b03ea43df6abf18cb9c4e5d6a9271ba040b689f4` (`lynomia-custom`) |
| Remotes | one: `origin  https://github.com/fullstackfull/lynomiachat` (fetch and push) |
| Working tree at baseline | clean (`git status --porcelain` → 0 lines) |

Required ancestry, verified with `git merge-base --is-ancestor <x> 8bb3b49e`:

| Commit | Is an ancestor of `8bb3b49e`? |
|---|---|
| `94fc5421` (last P11 code commit) | **yes** |
| `d304d013` (P10 tip) | **yes** |
| `b03ea43df6abf18cb9c4e5d6a9271ba040b689f4` (production) | **yes** |

P9 and P8 history is present in the same line: `git log 8bb3b49e --grep=…` finds
`b443cff0` (P9.5–P9.7 Operations Center), `5ff52677` (P9.1+P9.2 support foundation),
`faac8678` (P8.9), `2d375e6f` (P8.8), `16b6c4ac` (P8.6).

`origin/claude/p11-saas-commercialization` is `8bb3b49ecb7044a879d8ca7438cb2a82536aa5d1` — unchanged, and
P-FINAL does not write to it.

The repository's full history is 1134 commits; the oldest reachable commits are upstream Chatwoot release
merges (`ffc01838 Merge branch 'hotfix/3.11.1'`), so this is a fork of the upstream repository rather than a
re-import.

---

## 2. Runtime and toolchain

| | Value | Source |
|---|---|---|
| Ruby | `3.4.4` | `.ruby-version`, and `ruby '3.4.4'` in `Gemfile:3` |
| Rails | `7.2.3.1` | `Gemfile.lock` (`rails (7.2.3.1)`) |
| Node (installed) | `v22.22.0` | `node -v` |
| Node (declared) | `24.x` | `package.json` `engines.node` |
| pnpm | `10.2.0` | `pnpm -v`, matches `packageManager pnpm@10.2.0+sha512.…` |
| Package identity | `@chatwoot/chatwoot` `4.18.0` | `package.json` |
| `VERSION` file | **does not exist** | `ls VERSION` → no such file |
| Bundler path | `vendor/bundle`, `without: [:development]` | `.bundle/config` |

Two things to carry forward rather than fix blind:

- **Node mismatch.** The repo declares `engines.node: 24.x`; the environment that built and tested this tree
  runs Node 22.22.0. The build and the JS suite pass on 22, so this is a declaration/reality mismatch, not a
  defect — but the deployment target must run one of them deliberately. Recorded for §P-FINAL.31.
- **No `VERSION` file.** Upstream Chatwoot reads its own version from `package.json`; the only version-shaped
  runtime value is `Redis::Alfred::LATEST_CHATWOOT_VERSION`, which `Internal::CheckNewVersionsJob` writes from
  the upstream hub. There is nothing in the tree that states a *Lynomia* product version. Recorded, not
  invented.

---

## 3. Schema and migrations

| | Value |
|---|---|
| `db/schema.rb` version | `2026_10_10_110100` |
| Migration paths | `db/migrate` (upstream) **and** `custom/db/migrate`, registered at `config/application.rb:52` |
| Migrations in `db/migrate` | 180 |
| Migrations in `custom/db/migrate` | 24 |
| Migrations added since production | **8**, all under `custom/db/migrate` |

The eight (`git diff --diff-filter=A --name-only b03ea43d..HEAD -- '*migrate*'`):

| Migration | Phase |
|---|---|
| `20261009100000_create_support_tickets.rb` | P9 |
| `20261009100100_create_operations_signals.rb` | P9 |
| `20261009120000_create_contact_identities.rb` | P10 |
| `20261009130000_add_social_identity_index_to_contacts.rb` | P10 |
| `20261010100000_create_billing_entitlement_overrides.rb` | P11 |
| `20261010100100_add_channel_entitlements_to_billing_plans.rb` | P11 |
| `20261010110000_create_billing_webhook_events.rb` | P11 |
| `20261010110100_add_last_event_at_to_billing_subscriptions.rb` | P11 |

No migration was modified or deleted since production (`--diff-filter=MD` over the same paths → empty), so
production's applied history is intact and the new work is append-only at the migration level. Lock risk,
reversibility and rollback tolerance are audited per-migration in `03-migration-review.md`.

### New tables

`git diff b03ea43d..HEAD -- db/schema.rb | grep create_table` shows six added and none removed:

`billing_entitlement_overrides`, `billing_webhook_events`, `contact_identities`, `operations_signals`,
`support_ticket_events`, `support_tickets`.

P8 added **no** schema, which matches its design as a read projection over existing tables.

---

## 4. Feature flags added by P8–P11

`git diff b03ea43d..HEAD -- config/features.yml` adds exactly two, both **off by default**:

| Flag | Display name | Default | Column |
|---|---|---|---|
| `lynomia_support_tickets` | Lynomia Support Tickets | `enabled: false` | `feature_flags_ext_1` |
| `lynomia_unified_identity` | Lynomia Unified Customer Identity | `enabled: false` | `feature_flags_ext_1` |

P8 analytics and P11 billing are therefore **not** flag-gated in `features.yml`; their gating is of a different
kind (an existing `reports` capability for analytics, and installation-level Stripe configuration plus plan
entitlements for billing). The exact rollout levers, including the ones that are not feature flags, are built
from code in the rollout matrix (`09-rollout-and-rollback.md`).

---

## 5. Routes and endpoints

Routing is `config/routes.rb` (666 lines) plus ten drawn files under `config/routes/` (283 lines), of which
`analytics.rb`, `support.rb` and `operations.rb` are new since production and `billing.rb` changed.

**New account-API routes** (all behind the authenticated account API):
`GET analytics` + `analytics/{overview,whatsapp,campaigns,automations,flows,commerce,tickets}` (P8);
`GET contacts/:id/activity` and `contacts/:id/identities` (`index`, `create`, `destroy`) (P8/P10);
`support/tickets` (`index`, `show`, `create`, `update`) with nested `events` (`index`, `create`), and
`support/sla_policies` (full CRUD) (P9).

**New Super Admin routes:** `super_admin/operations#show` with `accounts`, `issues` and `open_case`
collection actions (P9); `post grant_override` and `post revoke_override` on the billing subscription
resource (P11).

**New public / unauthenticated routes since production: none.** The delta is net-negative here — it *removed*
`GET/POST /webhooks/twitter`, `GET /twitter/callback` and `POST .../twitter/authorization`. The complete
inventory of every endpoint reachable without a dashboard session, with auth mechanism and tenant binding per
endpoint, is `05-security-audit.md`.

---

## 6. New and changed background jobs

| Job | Status |
|---|---|
| `custom/app/jobs/custom/inboxes/fetch_imap_emails_job.rb` | added |
| `custom/app/jobs/support/sla_sweep_job.rb` | added |
| `app/jobs/inboxes/fetch_imap_emails_job.rb` | modified |
| `app/jobs/webhooks/sms_events_job.rb` | modified |
| `custom/app/jobs/lynomia/queue_health_job.rb` | modified |

Idempotency, retry policy and tenant scope for each are audited in `03-migration-review.md` §jobs and
`05-security-audit.md`.

---

## 7. Dependencies

**Zero dependency changes since production.** Measured, not assumed:

```
git diff --stat b03ea43d..HEAD -- Gemfile Gemfile.lock package.json pnpm-lock.yaml
```

returns **empty** — no gem added, removed or upgraded, and no npm package added, removed or upgraded, across
all of P8, P9, P10, P11 and the security closure. Every new subsystem was built on dependencies production
already runs.

Scale of what is nonetheless being shipped and therefore must be licence-audited: 395 gem specs in
`Gemfile.lock`, 356 gem directories installed under `vendor/bundle`, 1089 packages in `node_modules/.pnpm`,
`pnpm-lock.yaml` 10,409 lines. `02-license-audit.md` classifies them from on-disk metadata.

---

## 8. Enterprise absence (baseline check; the deep audit is §P-FINAL.6)

| Check | Result | Command |
|---|---|---|
| `enterprise/` on disk | **absent** | `ls -d enterprise` → no such file |
| tracked `enterprise/` paths | **0** | `git ls-files \| grep -c '^enterprise/'` |
| `ChatwootApp.extensions` | `["custom"]` | `bundle exec ruby -e …` |
| `ChatwootApp.enterprise?` | `false` | same |
| `ChatwootApp.custom?` | `true` | same |

`lib/chatwoot_app.rb` keeps `enterprise?` as a hard-coded `false` on purpose, with the reason in a comment: 8
call sites across 6 already-applied migrations name `Captain::` constants that no longer exist, and one `false`
is what keeps them inert without rewriting applied migration history. The deeper question — whether any
*runtime* path still needs Enterprise — is answered in `04-code-provenance.md` and `05-security-audit.md`.

---

## 9. Delta from production

```
git diff --shortstat b03ea43d..HEAD   →  440 files changed, 43125 insertions(+), 799 deletions(-)
git rev-list --count b03ea43d..HEAD   →  50
git diff --name-status b03ea43d..HEAD →  315 added, 114 modified, 11 deleted
```

By top-level directory: `custom/` 143 files, `app/` 141, `spec/` 95, `docs/` 45, `config/` 10, `lib/` 5,
`db/` 1.

Repository scale for context: 2,626 tracked `.rb` files, 843 RSpec files, 491 JS/Vue spec files.

### The eleven deletions

| Path | Why |
|---|---|
| `app/controllers/api/v1/webhooks_controller.rb` | X/Twitter inbound webhook controller (security closure SC6) |
| `app/controllers/twitter/{base,callbacks}_controller.rb` | X OAuth connect flow, dead after its inbound half went |
| `app/controllers/api/v1/accounts/twitter/authorizations_controller.rb` | same flow's initiator |
| `app/controllers/concerns/twitter_concern.rb` | used only by those three |
| `app/services/twitter/webhook_subscribe_service.rb` | registers a delivery URL that no longer exists |
| 3 × matching specs | the specs for the above |
| `custom/app/models/billing/plan_limits.rb` | duplicate limit module that could not see an override (P11) |
| `app/javascript/dashboard/routes/dashboard/settings/billing/Index.vue` | superseded by the P11 subscription page |

### The 50 commits

Oldest first, `git log --reverse --format='%h %ad %s' --date=short b03ea43d..HEAD`:

| | | |
|---|---|---|
| `9d24283f` | 2026-10-09 | docs(p8): discovery — analytics and contact timeline source mapping |
| `afc9b295` | 2026-10-09 | feat(analytics): P8.1 analytics foundation |
| `79e07227` | 2026-10-09 | feat(analytics): P8.2 overview and conversation analytics |
| `5af94605` | 2026-10-09 | feat(analytics): P8.3 WhatsApp delivery and campaign performance |
| `f8cc65e6` | 2026-10-09 | feat(analytics): P8.4 automation execution and flow sessions |
| `7944ed62` | 2026-10-09 | feat(analytics): P8.5 commerce cart lifecycle and order actions |
| `16b6c4ac` | 2026-10-09 | feat(contacts): P8.6 contact activity timeline, as a read projection |
| `ca6acc83` | 2026-10-09 | feat(contacts): P8.7 contact Activity tab |
| `2d375e6f` | 2026-10-09 | perf(p8): P8.8 EXPLAIN every shipped shape, prove tenant isolation |
| `faac8678` | 2026-10-09 | docs(p8): P8.9 UAT runbook, release gate and the refreshed analytics contract |
| `35bd4a06` | 2026-10-09 | fix(analytics): exclude private notes from WhatsApp delivery metrics |
| `f3c2fa1d` | 2026-10-09 | docs(p8): record the executed UAT, its prerequisites and what it found |
| `4e8e3d0b` | 2026-10-09 | docs(p8): P8 final completion report, UAT matrix and the brief's 36 gate questions |
| `55e04ad8` | 2026-10-09 | docs(p9): discovery and architecture |
| `5ff52677` | 2026-10-09 | feat(support): P9.1 + P9.2 support case foundation, workflow and SLA |
| `f3f7921f` | 2026-10-09 | feat(support): P9.4 cases in Customer 360 and in P8 analytics |
| `b443cff0` | 2026-10-09 | feat(operations): P9.5-P9.7 Operations Center, provider health and support bridge |
| `7c7a0c9a` | 2026-10-09 | feat(support): P9.3 support case workspace, panels and SLA settings |
| `7afc61de` | 2026-10-09 | fix(support): P9.8 index, scope and redaction defects found by measurement |
| `065188d7` | 2026-10-09 | docs(p9): support cases, SLA, operations, integration health, UAT and the release gate |
| `15efa6a7` | 2026-10-09 | docs(p9): final completion report and the gate results from the release build |
| `58b5b295` | 2026-10-09 | docs(p10): omnichannel and identity discovery |
| `265171bb` | 2026-10-09 | feat(contacts): make contact merge non-destructive and auditable |
| `a53027a5` | 2026-10-09 | feat(contacts): record the phone numbers and addresses a contact cannot hold |
| `fd7508b2` | 2026-10-09 | feat(channels): one honest connection state per channel, and stop three silent greens |
| `47b706e8` | 2026-10-09 | feat(contacts): show everything a customer can be reached at |
| `5d836ef0` | 2026-10-09 | fix(contacts): a discarded duplicate must not take anything else with it |
| `5b06f61d` | 2026-10-10 | fix(channels): stop sending three encrypted credentials to the browser |
| `acc2ab03` | 2026-10-10 | docs(p10): final completion report |
| `e0d24af1` | 2026-10-10 | test: update two assertions P10 deliberately changed |
| `d304d013` | 2026-10-10 | docs(p10): record the five gate results, both RSpec runs included |
| `99985c5c` | 2026-10-10 | fix(sms): authenticate Bandwidth callbacks and stop the body choosing the tenant |
| `9b6b95d5` | 2026-10-10 | docs(p11): discovery — this fork already has a billing subsystem |
| `2253e919` | 2026-10-10 | fix(tiktok): bound the OAuth state in time and to a person |
| `71e84983` | 2026-10-10 | fix(whatsapp): route inbound by Meta's phone_number_id, and stop the body waiving its own signature |
| `417f24b4` | 2026-10-10 | feat(billing): one entitlement service, channel entitlements, and a limit two requests cannot walk past |
| `fe5a26bb` | 2026-10-10 | fix(billing): fail closed on an unset webhook secret, and make events idempotent and order-safe |
| `403d423f` | 2026-10-10 | fix(webhooks): authenticate the four remaining public endpoints that trusted their own body |
| `2fb2985b` | 2026-10-10 | fix(channels): stop offering three channels that cannot work, and remove the X webhook routes |
| `d7885ee7` | 2026-10-10 | docs(p11): the P10 security closure, classified |
| `9154f392` | 2026-10-10 | feat(billing): operable entitlement overrides and one enforced limit |
| `826dcdde` | 2026-10-10 | feat(billing): validate the proration quote, audit plan entitlement edits |
| `727e56ed` | 2026-10-10 | docs(p11): rollout safety, UAT runbook, and account billing authorization specs |
| `102c21e8` | 2026-10-10 | refactor(billing): every Stripe API call in one layer |
| `b33695dc` | 2026-10-10 | fix(billing): close five defects an adversarial audit proved |
| `cd829d1b` | 2026-10-10 | test(twilio): make the channel dependency explicit and fix a stale spec pointer |
| `f7fb32b2` | 2026-10-10 | fix(billing): scope a shared plan write to the accounts the app was granted |
| `98902565` | 2026-10-10 | docs(p11): verifiable counts and the final report in the reading order |
| `94fc5421` | 2026-10-10 | fix(channels): remove the X connect flow the webhook-route removal left broken |
| `8bb3b49e` | 2026-10-10 | docs(p11): the gate-5 results, and the lines they correct |

---

## 10. Inherited test and lint position

These are the figures P11 recorded at `94fc5421`. They are the **starting** position, not a P-FINAL result;
§P-FINAL.35 re-runs all five gates on P-FINAL's own clean tree and `07-release-gate.md` reports those numbers.

| Gate | P11's result | Tree it ran on |
|---|---|---|
| `bundle exec rubocop` | 2894 files, 0 offences | `94fc5421` |
| `pnpm eslint` | 0 errors, 478 warnings (all pre-existing) | `cd829d1b` |
| `npx vite build` | ✓ 2m 15s | `cd829d1b` |
| `pnpm test` | 491 files, 5294 tests, 0 failures | `cd829d1b` |
| `bundle exec rspec` | 9609 examples, 0 failures, 70 pending | `94fc5421` |

---

## 11. What this baseline establishes for the rest of P-FINAL

1. The branch is where it should be, and the three required ancestors are proven rather than asserted.
2. The release carries **no new dependency risk** — the licence and supply-chain audits are therefore about
   what production *already* ships, not about anything P8–P11 introduced.
3. The schema delta is eight append-only migrations and six new tables, which is the whole surface the
   rollback policy has to reason about.
4. The release adds **no new public endpoint**, and removes three.
5. Only two feature flags were added, both off, so "preserve current production behaviour on deploy" is
   mostly a question about the levers that are *not* feature flags — analytics' `reports` capability and
   billing's installation configuration.
