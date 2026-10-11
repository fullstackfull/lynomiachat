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

### 1.0 The five replaced packages' levers

**This section was missing, and the post-integration deployment audit was right to say so.** The matrix above
was written for P8–P11 and lists none of the flags the five clean-room packages depend on — which is to say,
nothing in it covers the part of this release that was rewritten. Every default below is read from
`config/features.yml` at this revision, and none of these is on for an account that does not already have it.

| Lever | Kind | Default after deploy | What it gates (server-side) | Rollback lever | Data effect of switching off |
|---|---|---|---|---|---|
| `audit_logs` | account feature flag, premium | **off** | the whole audit trail READ surface: `AuditTrail::Query` returns `Custom::AuditLog.none`, so the page gets an empty list and a 200 rather than a refusal (`custom/app/services/audit_trail/query.rb:52`). **Capture is NOT gated** — see below | turn the flag off for the account | **none.** Entries keep being written and reappear when it is on again |
| `audit_log_ip_address` | account feature flag, premium | **off** | whether the trail shows a full originating address or a coarse network (`AuditTrail::Disclosure`) | turn the flag off | none; it is a rendering decision over already-stored data |
| `custom_roles` | account feature flag, premium | **off** | all five role endpoints answer with the standard authorization refusal (`custom_roles_controller.rb:52`). **Attachment and the capability list are NOT gated** — see below | turn the flag off | **none.** Sets and their attachments stay, and keep granting what they grant |
| `whatsapp_campaign` | account feature flag | **off** | whether a WhatsApp campaign may be created, and `Campaign#trigger!` returns without sending (`campaign.rb:62-67,78`) | turn the flag off | **none** on stored rows, but see the caveat below: an active campaign stalls rather than refusing |
| `unread_count_for_filters` | account feature flag | **off** | the filtered unread counts entirely: `FilteredCountInvalidator#enabled?` and the counter both return early, so no Redis key is written or read | turn the flag off | **none.** Redis keys expire on their own TTL |

**Two things these flags do not gate, and an operator must know which:**

- **Audit capture runs whether or not `audit_logs` is on.** The flag gates reading, not writing: every
  `audited` declaration and every Lynomia writer records regardless. That is deliberate — a trail with holes
  in it for the period the flag was off would be worse than no trail — but it means turning the flag off is
  not a way to stop recording, and the `audits` table grows either way.
- **A permission set keeps granting its capabilities after `custom_roles` is turned off.** The flag gates
  administering sets, not the capability list a membership already holds: `Custom::AccountUser#permissions`
  has no feature check, and neither do the three policies that read it. So revoking the entitlement from a
  downgraded account stops it defining or attaching sets and leaves the ones already attached working. This
  is a defensible product rule — a downgrade should not silently strip an agent's access mid-shift — but it is
  a rule, not an accident, and it is the one an operator will be asked about. Enforcing it the other way is a
  product decision, not a bug fix, because it would revoke access from live agents the moment a plan lapsed.

**The `whatsapp_campaign` caveat.** With the flag off, `Campaign#trigger!` returns early without sending and
**without marking the campaign anything** (`app/models/campaign.rb:62-67`), so a campaign scheduled while the
flag was on sits in its existing state and the operator sees neither a send nor a refusal. Turning the flag
off is therefore a pause, not a cancellation, and an active campaign should be cancelled explicitly rather
than left to a flag. Recorded here rather than changed: making the trigger refuse loudly would change upstream
behaviour on a path shared with SMS campaigns.

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

What matters most is that each signal below has a known-good baseline taken **before** the deploy, so
"elevated" means something. `08-production-uat-runbook.md` §0.2 is the capture; nine of these ten signals had
no capture step until it was added, which made the comparisons here unreadable as written.

**The hold points.** These are defaults, not findings — the product does not derive a number, and the owner may
shorten or lengthen them. What they are for is to stop "watch for a while" becoming "watch until someone feels
ready", which is how a deploy gets declared done at the first green page.

| after | hold for | before |
|---|---|---|
| the restart (§6 step 2) | **30 minutes** with every lever still off | starting the UAT sections that write data |
| the UAT sections that need no lever | **60 minutes** | enabling the first lever |
| each lever, one account | **60 minutes** on that account's signals | enabling the next lever |
| the last lever | **24 hours**, spanning one full business day for this installation's customers | the real WhatsApp send in runbook §13 |

A hold ends when the signals look like the baseline, not merely when the clock runs out: a signal still moving
at the end of a hold extends it. Write the start and end of each hold into `deployment/INCIDENT.md`, because a
hold nobody recorded is a hold nobody took.

| Watch | Where | What a problem looks like |
|---|---|---|
| 5xx rate | nginx access log, Sentry | any sustained rise over the pre-deploy baseline |
| Sidekiq retry and dead sets | `Sidekiq::Stats` — the **pre-deploy** capture in runbook §0.2; the deploy script's own print is one post-restart sample and is not a baseline | `retry` or `dead` growing rather than draining |
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
3. Work `08-production-uat-runbook.md` one command at a time. That document is numbered by section, not by
   phase; its §0.3 maps the phases named here onto its section numbers. Start at its §2.
4. Enable nothing until that map's PHASE 4 (runbook §4 and §6), and then one lever, one account. Runbook §0.4
   is how to enable one for a single account and how to put it back.
