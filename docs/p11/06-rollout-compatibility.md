# P11 — Rollout and compatibility

Why deploying this changes nothing, what an operator switches on and in what order, and what rolling back
costs.

---

## 1. The claim, and the chain of facts behind it

> **Deploying P11 to an installation changes no account's access, no account's capabilities and no account's
> limits.** Nothing is enforced until an operator deliberately configures it.

Each link is a repository fact, not an intention:

1. **The account lock needs billing to be set up.** `Billing::AccessGuard#ensure_billing_access` returns early
   unless `subscription.accessible?` is false. `BillingSubscription#accessible?` is
   `usable? || (status == 'inactive' && !Billing::Settings.enforced?)`, and
   `Billing::Settings.enforced?` is `stripe_configured? || Billing::TrialStarter.configured?`. On an
   installation with no Stripe keys and no trial plan both are false, so an `inactive` subscription is
   accessible and nothing is locked.
2. **An account with no subscription row is never locked.** `TrialStarter.subscription_for` returns
   `account.billing_subscription || (new(account).perform if configured?)` — with nothing configured it
   returns `nil`, and the guard returns early on `subscription.nil?`.
3. **With no plan there is no ceiling.** `Billing::Entitlements.limit` reads `plan_for(account)&.limit_for`,
   and `plan_for` returns `nil` when there is no subscription or its plan is nil. `Billing::ResourceLimit`
   returns `nil` from `exceeded` and `false` from `reached?` the moment the limit is `nil`, before it counts
   anything or takes a lock.
4. **With no override rows, every capability falls through to today's answer.** `Billing::Entitlements.allowed?`
   returns `account.feature_enabled?(capability)` when `override_for` finds nothing — the identical expression
   the product used before P11.
5. **A plan that names no channels denies none.** `channel_allowed?` returns `true` when
   `plan.channel_entitlements` is blank, which is the column default for every row that exists.
6. **`FeatureSync` only fires on a plan change.** `BillingSubscription` syncs
   `if: -> { saved_change_to_plan_id? && plan.present? }`, and `BillingPlan` syncs
   `if: :saved_change_to_features?`. A deploy changes neither.

Nothing in the four P11 migrations writes a row, and no application code raises when a row is absent.

---

## 2. The migrations

| Migration | Shape | Rewrites rows? | Rollback |
|---|---|---|---|
| `20261010100000_create_billing_entitlement_overrides` | new table, 2 indexes | no | `drop_table` |
| `20261010100100_add_channel_entitlements_to_billing_plans` | `add_column … :jsonb, default: [], null: false` | **no** — Postgres 11+ records a non-volatile default as metadata, so there is no table rewrite; `billing_plans` holds a handful of rows in any case | `remove_column` |
| `20261010110000_create_billing_webhook_events` | new table, 3 indexes (one partial) | no | `drop_table` |
| `20261010110100_add_last_event_at_to_billing_subscriptions` | `add_column … :datetime` (nullable) | no | `remove_column` |

All four were applied, rolled back and re-applied on this branch, producing a **byte-identical
`db/schema.rb`** each time.

`last_event_at` is nullable **on purpose**: every existing subscription has already had events applied whose
timestamps were never recorded, and inventing one would either reject the next legitimate event or accept a
stale one. `nil` means *no ordering information yet*, which accepts the next event and records its timestamp —
so the out-of-order guard becomes effective from the first event after deployment, with no backfill.

**No backfill is required before the application boots.** The one backfill that exists,
`Billing::TrialStarter.backfill!`, is an explicit, operator-invoked one-off that raises
`NotConfigured` unless a trial is set up, and nothing calls it automatically.

---

## 3. Switching it on, in order

Each step is reversible and each one is inert until the next.

| # | Step | Where | What becomes true |
|---|---|---|---|
| 1 | Create the plans | Super Admin → Billing Plans | Rows exist. Nothing is enforced: no account has a subscription pointing at them. |
| 2 | Set the Stripe secret key **and** the webhook secret | Super Admin → Billing Settings | `stripe_configured?` → true, so `enforced?` → true. **An `inactive` account is now locked.** Do step 3 or 4 first on an installation with live accounts. |
| 3 | Start trials for existing accounts | `Billing::TrialStarter.backfill!` | Every account without a subscription gets the trial plan. The once-per-user rule is deliberately skipped for existing accounts. |
| 4 | Or grant plans individually | Super Admin → Subscriptions → Grant plan | Chosen accounts are `active` on a plan with no end date. |
| 5 | Point the Stripe webhook at `POST /billing/webhooks/stripe` | Stripe dashboard | Subscription state starts syncing. Before this the endpoint answers `401` on a blank secret and never guesses. |
| 6 | Fill in `limits` on the plans | Super Admin → Billing Plans | Seat, inbox and store ceilings start applying **to new creates only**. |
| 7 | Fill in `channel_entitlements` on the plans | Super Admin → Billing Plans | Channel permissions start applying **to new inboxes only**. |
| 8 | Grant overrides where a customer needs an exception | Super Admin → Subscriptions → Overrides | Audited, reasoned, optionally expiring. |

**Steps 6 and 7 are the only ones that can surprise a paying customer**, and they are last for that reason.
The plan form prints how many accounts pay for the plan before either field is changed, and every such change
is audited (`03-plans-entitlements.md` §5).

### The one ordering trap

Step 2 before step 3 or 4 locks every account that has no subscription row, because `enforced?` becomes true
and `inactive` stops being accessible. The safe order on a live installation is **1 → 3 → 2**, or
**1 → 4 → 2**. An operator who does it the other way recovers by running step 3 or granting plans; no data is
lost and no state needs repair.

---

## 4. No accidental lockout after migration (P11.42)

Three independent reasons an account cannot lose access by deploying:

* An account **with** a usable subscription keeps it: nothing in P11 writes to `billing_subscriptions.status`.
* An account **without** a subscription is only locked once `enforced?` is true, which needs an operator to
  configure Stripe or a trial plan — a deliberate act, after the deploy.
* An account on a plan keeps every capability it had: `FeatureSync` does not run on deploy, and the new
  override layer only ever *adds* an exception on top of the flags that are already set.

The downgrade policy reinforces this: nothing is ever deleted, archived or disabled when a limit changes. A
plan that stops allowing something refuses the next create and leaves everything that exists
(`05-usage-limits.md` §5). Contacts and the P10 `contact_identities` are untouchable from the commercial path —
historical customer identity is customer data, not a plan feature.

---

## 5. Rolling back

| Roll back | Cost |
|---|---|
| The code, keeping the schema | Full. The new tables are read by nothing else; `Billing::PlanLimits` returns, which means overrides stop applying (ceilings fall back to the plan) and the untranslated limit message returns. No data is lost. |
| The schema too | `drop_table` / `remove_column` on all four. Overrides are lost — they are operator decisions, so re-grant them; the audit log keeps the record of every grant and revoke, so what to re-grant is readable. Webhook receipts are lost, so idempotency and ordering degrade to the pre-P11 behaviour (a redelivery may be processed twice). |
| Just the enforcement, keeping everything | Clear `limits` and `channel_entitlements` on the plans. No deploy, no migration. |

The last row is the operational answer: **enforcement is data, not code.** If a limit turns out to be wrong at
2am, an operator empties a field in the console instead of shipping a release.

---

## 6. Compatibility with the earlier phases

| Phase | Interaction | Status |
|---|---|---|
| P8 analytics | reports message and conversation volume. P11 does **not** read it as a billing quantity, and does not change it. | untouched |
| P9 Operations Center | gains three billing signals (`entitlement_sync_failed`, `unknown_provider_customer`, `billing_event_failed`) through the existing `Operations::SignalRecorder`, added to its `SOURCES`/`SIGNALS`/`DETAIL_KEYS` allow-lists. No new store. | extended |
| P9 Tickets / SLA | not referenced by anything commercial. | untouched |
| P10 channel capability | `Channels::Capability` is the option list for a plan's channels and for a channel override, so a plan cannot sell a channel this fork lacks. | reused |
| P10 contact identity | nothing in the commercial path can reach `contacts` or `contact_identities`. | untouched, and asserted |
| Commerce (P6) | the store ceiling moved from `Billing::PlanLimits` to `Billing::ResourceLimit`, so it now honours an override. The `connected`-only counting rule is unchanged. | corrected |
| Enterprise overlay | absent. `ChatwootApp.extensions == ["custom"]`, `enterprise? == false`. Nothing was copied from it. | n/a |

---

## 7. What still needs a human on a real installation

Carried forward unchanged, and **not** marked passed from seeded tests:

* **P11:** a real Stripe test-mode round trip — Checkout, the webhook, the Customer Portal, a plan change
  with a real proration invoice, a dunning cycle into `past_due` and recovery. `08-uat-runbook.md` is the
  script.
* **P8:** production rollups, the reports pilot, the Analytics screens, the Contact Timeline, real Meta status
  cases, a genuine-new-contact WhatsApp send.
* **P9:** all real Tickets / SLA / Operations UAT.
* **P10:** real channel and provider UAT, the contact identity pilot, the TikTok real-provider check, channel
  health validated against a real provider.

Production remains `lynomia-custom b03ea43df6abf18cb9c4e5d6a9271ba040b689f4`. Nothing in this phase was
deployed, no production configuration was changed and no real billing provider was called.
