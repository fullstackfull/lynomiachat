# P-FINAL.32–.34, .41, .42 — Rollout, rollback and the levers in between

One deployment carries four phases. This document is what the operator needs that `deployment/deploy.sh` and
`deployment/ROLLBACK.md` do not say: which levers exist, what each one costs, what "no change for anyone" means
concretely, and what the first hours after the deploy should be spent watching.

Every lever below was read out of the code, not inferred from a changelog, and each row names where.

---

## 1. The rollout matrix (P-FINAL.33)

| Lever | Kind | Default after deploy | What it gates (server-side) | Rollback lever | Data effect of switching off |
|---|---|---|---|---|---|
| `lynomia_support_tickets` | account feature flag (`config/features.yml`, `feature_flags_ext_1`) | **off** for every account | every `support/*` endpoint answers **404** (`Api::V1::Accounts::Support::BaseController:17`), and the workspace disappears from the sidebar | turn the flag off for the account | **none.** Cases already created stay in `support_tickets`, simply unreachable until it is on again |
| `lynomia_unified_identity` | account feature flag | **off** for every account | `contacts/:id/identities` answers 404, and `Contacts::IdentityLinker` refuses (`:18`) — including the merge path, which checks the same flag | turn the flag off | **none.** Links already recorded stay in `contact_identities` |
| `reports` | **existing** account feature flag | whatever production already has | the dashboard route to Analytics (`analytics.routes.js:17`). It is not the server gate | turn the flag off | none — analytics is read-only |
| `ReportPolicy#view?` | policy, not a flag | administrator | **every** analytics endpoint and the account's timeline (`analytics_controller.rb:11,108`) | n/a — it is a role rule | none |
| Super Admin Operations Center | no flag | reachable by Super Admins only (`SuperAdmin::ApplicationController` authentication) | the console itself | n/a | none; see §1.1 |
| Billing enforcement | derived: `Billing::Settings.enforced?` = Stripe keys present **or** a trial plan configured | **off** — production has neither | the 402 lock (`Billing::AccessGuard`), trial creation, and whether a plan's entitlements resolve at all (`Billing::Entitlements.plan_for` → `subscription.accessible?`) | clear `BILLING_STRIPE_SECRET_KEY` / `BILLING_STRIPE_WEBHOOK_SECRET` and the trial plan in Super Admin → Billing → Settings | **none.** Subscriptions and overrides stay; nothing is enforced |
| Plan `limits` | per-plan data | whatever an operator sets; a missing key is unlimited | seat / inbox / store ceilings | clear the ceiling — **widening is always allowed**, even on a billed plan | none |
| Plan `channel_entitlements` | per-plan jsonb, default `[]` | **`[]` on every plan**, which sells every channel | channel gating (`BillingPlan#channel_included?`) | clear the list | none |
| Per-account overrides | `billing_entitlement_overrides` rows | none exist | one capability, ceiling or channel for one account | revoke the override (audited) | the capability returns to the plan's answer |

### 1.1 What is NOT behind a flag, and therefore starts the moment the deploy restarts

Two things begin writing on their own. Both are bounded and neither is customer-facing:

| What | Why it is not gated | Bound |
|---|---|---|
| `operations_signals` rows, written by `Lynomia::QueueHealthJob` and the IMAP failure recorder | the point of P9's Operations Center is that a problem which happens while a flag is off is still a problem. A signal nobody records is the gap P9 existed to close | **one row per distinct open problem**, not per occurrence — enforced by the partial unique index. A failing inbox polled every minute is one row with a rising `occurrences`, not 1,440 a day |
| `Support::SlaSweepJob`, every 5 minutes (`config/schedule.yml`) | it decides SLA outcomes, and a schedule that only runs for flagged accounts would silently skip them | two partial-index scans. With no tickets anywhere it touches an empty table; measured as two index scans returning nothing |

If either needs to be stopped, the lever is the scheduler entry (remove `support_sla_sweep_job` from
`config/schedule.yml` and restart) — not a flag, because there is no flag.

---

## 2. Existing-account compatibility, proven rather than asserted (P-FINAL.34)

The property: an account that existed before the release, which nobody configures afterwards, behaves exactly
as it did. `spec/requests/p_final/existing_account_compatibility_spec.rb` — **11 examples, 0 failures** — is the
regression test for it, and it starts by asserting the premise rather than assuming it (no subscription row, no
Stripe configuration, `enforced?` false, both new flags off, account active).

What it then proves:

| Claim | How |
|---|---|
| the working day is untouched | `conversations`, `contacts`, `inboxes`, `labels` and `agents` all serve an agent with no subscription |
| **no 402 anywhere** | five account endpoints asserted not to answer the billing lock — this is the trap `docs/p11/06-rollout-compatibility.md` names (configure Stripe before starting trials and every subscription-less account locks), and now its regression test |
| creating still works | an administrator creates a contact, an API inbox and an agent, with no ceiling refusing any of them |
| sending still works | an agent posts a message into a conversation and it is created outgoing |
| the new surfaces are inert, not broken | support cases → 404, contact identities → 404; a 404 and not a 500, and not a 403 that advertises what the account could have if it paid |
| analytics is unchanged | administrator 200, agent 401 — the `reports` permission the product already had |
| nothing commercial is invented | no plan, no ceilings (`limit` is nil for agents, inboxes and stores), every channel allowed, and after exercising the API: zero `BillingSubscription` rows and zero `BillingEntitlementOverride` rows |

---

## 3. Rollback: the decision tree for this release

`deployment/ROLLBACK.md` holds the executable procedure. What follows is which procedure to reach for.

```
Something is wrong after the deploy
│
├─ Nothing serves: readiness ≠ 200, units not active, errors on every request
│    → CODE ROLLBACK (deployment/ROLLBACK.md "Code rollback"). Leave the schema. ~5 min.
│
├─ One new surface misbehaves (tickets, identities, analytics, billing)
│    → TURN ITS LEVER OFF (§1). No restart, no rollback, no data loss. Seconds.
│      This is the first response for anything feature-shaped, and it is why the levers exist.
│
├─ Billing does something unexpected — a lock, a wrong entitlement, a Stripe mismatch
│    → CLEAR THE STRIPE SETTINGS. Enforcement goes inert installation-wide and nothing is lost.
│      Do NOT roll the code back for this: the subscriptions and overrides written since the deploy
│      would then be read by code that does not know about them.
│
├─ The migration step failed
│    → DO NOT roll the code back first. Read docs/p-final/03-migration-review.md §4 and §6. The
│      likely cause is an interrupted CREATE INDEX CONCURRENTLY, which the deploy script detects;
│      re-running the migration step is safe and rebuilds it.
│
└─ Data looks wrong
     → STOP. Take a fresh dump before anything else, then investigate. A restore loses every
       conversation since the last dump, which on a messaging product is customer data.
```

### What a code rollback must NOT do

Drop the new tables. `docs/p-final/03-migration-review.md` §6 lists what each one would destroy; in short:
support cases and their history, the operational record, the identities agents linked, every commercial
exception with its reason, and the billing idempotency record — after which a replayed Stripe event would be
processed twice. **The schema stays.** Old production code cannot tell the difference, which §6 of that document
establishes against each of the three ways additive schema can still break old code.

### The one thing in flight worth knowing about

`Webhooks::SmsEventsJob` changed shape: it now takes the `channel_id` the authenticated controller resolved, and
**drops a job that does not carry one**. A Bandwidth inbound job enqueued by the pre-release code seconds before
the restart is therefore dropped rather than processed.

That is deliberate and it is the right trade: such a payload was accepted by the old controller **without any
authentication**, and letting the new code trust it would reopen exactly what the security closure fixed. The
exposure is bounded to jobs enqueued in the seconds before the restart, on one channel, and the `default` queue
drains in that time. The runbook's pre-restart step records queue depth so the window is observed rather than
assumed.

---

## 4. Observation window (P-FINAL.41)

No fixed number of hours is invented here, because nothing in the product requires one. What matters is that
each signal below has a known-good baseline taken **before** the deploy, so "elevated" means something.

| Watch | Where | What a problem looks like |
|---|---|---|
| 5xx rate | nginx access log, Sentry | any sustained rise over the pre-deploy baseline |
| Sidekiq retry and dead sets | `Sidekiq::Stats` (the deploy script already prints them) | `retry` or `dead` growing rather than draining |
| `operations_signals` | Super Admin → Operations → Issues | new CRITICAL rows, especially `authentication_failed` on an email channel or `no_workers` |
| Account health | Super Admin → Operations → Accounts | any account that was HEALTHY before the deploy and is not after |
| Provider webhook failures | `operations_signals`, provider dashboards | a channel going quiet is the shape to look for, not an error rate |
| Inbound message flow | conversation counts per channel against the same hour yesterday | a channel at zero |
| SLA sweep | `SUPPORT_SLA_SWEEP` operator log lines every 5 minutes | the line missing, or counts climbing without bound |
| Billing jobs | `billing_webhook_events` where `status = 2` (the partial index exists for this) | any row at all, while Stripe is unconfigured, would be surprising |
| DB and Redis | host metrics | connection saturation after the restart |
| Contact identity collisions | `operations_signals`, application log | a rise in refused links |

A controlled rollout for this release means: deploy with every lever off, watch the list above until the signals
look like they did before the deploy, then enable **one** lever for **one** pilot account and watch again. The
order is in `08-production-uat-runbook.md`.

---

## 5. NO-GO conditions, and the lever for each (P-FINAL.42)

A NO-GO is not a judgement call. If any of these is observed, stop and use the lever named.

| Condition | Lever |
|---|---|
| Cross-tenant data visible to any account | **code rollback**, and the release does not go out again until the path is closed and tested |
| Authentication or authorization bypass | **code rollback** |
| A public webhook accepting a forged or unsigned body | **code rollback**; the authentication is in the request path and cannot be switched off |
| A secret visible in a response, a page, a log or a diagnostic | **code rollback**, then rotate the exposed credential |
| Migration failure that leaves the schema half-applied | fix forward per `03-migration-review.md` §4; do not roll the code back first |
| Sustained 5xx, or Sidekiq crash-looping | **code rollback** |
| An account charged, locked or entitled wrongly | **clear the Stripe settings** (enforcement inert), then investigate; code rollback only if that does not stop it |
| Contact merge or identity link losing data | **turn `lynomia_unified_identity` off**; the merge path checks the same flag |
| Inbound messages routed to the wrong tenant or the wrong channel | **code rollback** — routing is not behind a lever |
| Anything requiring Enterprise at runtime | **code rollback**; this would mean the absence audit missed something |
| An unresolved licence or provenance blocker surfacing after release | stop distribution; this is a business decision, not an operational one |
| Tests red on the released revision | it should not have been released; roll back to the last green revision |

---

## 6. What the operator does first, in order

1. Take the baselines in §4 **before** running the deploy. Without them, §4 cannot be read.
2. Run `deployment/deploy.sh`. It refuses a dirty tree, backs the database up and verifies the backup, runs the
   migrations with no statement timeout, checks for invalid indexes and pending migrations, builds both
   bundles, restarts, and verifies readiness, the units and a registered Sidekiq process.
3. Work `08-production-uat-runbook.md` from PHASE 2 onwards, one command at a time.
4. Enable nothing until PHASE 6, and then one lever, one account.
