# P11 — Commercial architecture

What a "plan" means on this fork, where the answer is produced, and where it is enforced. Read
`01-discovery.md` first: it establishes that the billing subsystem already existed, which is why this document
describes **one** system with a layer added rather than a new one.

---

## 0. The headline

A plan is not a label on an account. The commercial question — *may this account do this, right now?* — has
exactly one answer-producing service and that answer is enforced on the server, at the point where the thing
is created.

```
                 ┌──────────────────────────────────────────────────────────┐
  WHO ASKS       │  Billing::Entitlements        (the only answer)          │
                 │    allowed?(account, capability)  -> Boolean             │
  inbox create   │    limit(account, resource)       -> Integer or nil      │
  agent create   │    channel_allowed?(account, type)-> Boolean             │
  store connect  │    source(account, capability)    -> which layer said so │
  the dashboard  └──────────────────────────────────────────────────────────┘
  the console                        │  reads, in this order
                 ┌───────────────────┴──────────────────────────────────────┐
  1 SYSTEM       │ BillingPlan::SYSTEM_FEATURES — never a commercial question│
  2 OVERRIDE     │ billing_entitlement_overrides — one account, audited      │
  3 PLAN         │ billing_plans.features / .limits / .channel_entitlements  │
  4 DEFAULT      │ today's behaviour: the account's own feature flags        │
                 └──────────────────────────────────────────────────────────┘
```

`custom/app/services/billing/entitlements.rb`. Nothing else in the product compares a plan name, reads
`billing_plans.features` directly, or decides a commercial question in the frontend.

---

## 1. The four layers, and why each exists

| # | Layer | Stored in | Answers | Who changes it |
|---|-------|-----------|---------|----------------|
| 1 | System / installation | `BillingPlan::SYSTEM_FEATURES` (`custom/app/models/billing_plan.rb:12`), `config/features.yml` | "this installation does not offer that, and no plan may sell or withhold it" | a deploy |
| 2 | Account override | `billing_entitlement_overrides` | "a named operator decided this for this one account, for this reason" | Super Admin, audited |
| 3 | Plan entitlement | `billing_plans.features`, `.limits`, `.channel_entitlements` | "this is what the subscription bought" | Super Admin / Platform API |
| 4 | Default | `accounts.feature_flags` | "today's behaviour" | the product, as it always did |

Layer 1 is a hard block, not a precedence winner that a plan could outbid: `Billing::Entitlements.allowed?`
returns the account's own flag for a system capability and never looks at a plan or an override
(`entitlements.rb:28-32`). A plan that lists `chatwoot_v4` cannot grant it and a plan that omits it cannot take
it away. `BillingPlan.assignable_features` (`billing_plan.rb:36-42`) removes system, internal, deprecated and
`premium` (Enterprise-licensed) features from the form, so an operator cannot even select one.

Layer 4 is why deploying this changes nothing. With no Stripe configuration, no plan rows and no override
rows, every call falls through to `account.feature_enabled?` and `limit` returns `nil` — the exact behaviour of
the fork before P11. See `06-rollout-compatibility.md`.

---

## 2. Where the effective state lives, and why this is not a second system

The one decision that keeps this from becoming a parallel permission system: **a plan's features are applied by
writing them into the account's own feature flags**, by `Billing::FeatureSync`
(`custom/app/services/billing/feature_sync.rb:29-35`). The store of effective state stays
`accounts.feature_flags`, so all 124 existing `feature_enabled?` call sites in the product keep working
untouched and no call site had to learn about billing.

What the entitlement service adds on top of that store is the two things flags cannot express:

* **An override that a plan sync must not revert.** The old write was unconditional in both directions
  (`disable_features(*(managed - included))`), so an operator switching a managed feature on for one account
  lost it at the next sync, and nothing recorded that the decision was deliberate. `FeatureSync` now subtracts
  `overridden_capabilities` from the managed set (`feature_sync.rb:29, 42-44`).
* **Which layer produced the answer.** `Billing::Entitlements.source` returns `:system`, `:override`, `:plan`
  or `:default`. A flag alone cannot tell an operator's deliberate enablement from a plan's.

Limits and channel entitlements are *not* mirrored into flags, because there is nowhere to mirror them to: an
integer ceiling and a list of channel types have no flag representation. They are read from the plan (or the
override) at the moment of the check.

---

## 3. Feature flag vs entitlement (P11.4)

They are different questions and the repository keeps both:

| | FEATURE FLAG | ENTITLEMENT |
|---|---|---|
| Question | is this code path switched on for this account? | did this account pay for this capability? |
| Store | `accounts.feature_flags` (bitmask) + `config/features.yml` | `billing_plans.features` / an override |
| Changed by | a rollout decision, Super Admin, a deploy | a subscription, or an audited operator decision |
| Read by | `account.feature_enabled?(name)` — everywhere | `Billing::Entitlements.allowed?` |

A capability can require **both**: the flag is how the rollout is staged, the plan is how it is sold. Because
plan features are written into the flags, `feature_enabled?` is the conjunction in practice — a capability the
plan does not include is disabled on the account, and a capability the installation has not rolled out is not
in `assignable_features` and so cannot be sold.

The old flags were **not** migrated into billing records, and no migration touches `accounts.feature_flags`.
The compatibility layer is `FeatureSync` writing into the existing store; `config/features.yml` holds 74 entries, of which 41 are
assignable to a plan; `01-discovery.md` §4 has the inventory.

---

## 4. Where enforcement actually happens

Enforcement is at the earliest shared entry point for each thing, never repeated downstream.

| Commercial rule | Enforced at | File |
|---|---|---|
| No usable subscription → account locked | `before_action` on every account-scoped API controller | `custom/app/controllers/billing/access_guard.rb:15` |
| Agent / seat ceiling | `AccountUser` validation `on: :create` | `custom/app/models/billing/agent_limit.rb:13` |
| Inbox ceiling | `Inbox` validation `on: :create` | `custom/app/models/billing/inbox_limit.rb:15` |
| Channel type not sold | `Inbox` validation `on: :create` | `custom/app/models/billing/inbox_limit.rb:16` |
| Commerce store ceiling | inside `Commerce::StoreConnection#attach`'s transaction and account lock | `custom/app/services/commerce/store_connection.rb:47,130` |
| Plan change price | derived server-side from the `BillingPlan` row; the client sends only a `plan_id` | `custom/app/services/billing/plan_change.rb` |

`AccountUser` and `Inbox` are model validations on purpose. Every way of adding a person to an account — an
invitation, a bulk invite, the Platform API, a reactivation — creates an `AccountUser`, and every way of
creating an inbox — the dashboard, each provider's OAuth callback, the Platform API — creates an `Inbox`. One
validation covers all of them; a controller check would have had to be repeated in each and would have been
missed in the next one. The three extensions are attached in `config/initializers/billing.rb`.

**Frontend hiding is not enforcement**, and the repository now treats it that way. Before P11, five of twelve
channel types had an account feature flag and that flag only hid the tile — an administrator POSTing to the
inboxes endpoint got the inbox. The channel rule is now a validation; the frontend tile is a convenience on
top of it.

---

## 5. What P11 deliberately did not build

| Not built | Why |
|---|---|
| A second Super Admin | One exists. The override surface is two actions and a section on `custom/app/views/super_admin/billing_subscriptions/show.html.erb`. |
| A usage-event table / period metering | No metered price exists in the catalogue: every `BillingPlan` is `flat` or `per_agent` (`billing_plan.rb:5`). Counting what nobody bills is a table to maintain and migrate for no revenue. See `05-usage-limits.md` §6. |
| Enterprise billing / SLA / audit code | `enterprise/` is absent on this fork; `ChatwootApp.extensions == ["custom"]`. Nothing was copied from it. |
| A public pricing website | Out of scope (P11.58). The in-product plan list is the only catalogue surface. |
| AI / Captain billing or quota | Out of scope. Captain stays inactive and no AI capability is sold. |
| Raw card handling | Lynomia never sees a PAN or CVV. Checkout and the Customer Portal are Stripe-hosted; see `04-subscriptions-billing.md`. |

---

## 6. The five commercial tables

```
billing_plans                      the catalogue: price, interval, features, limits, channel_entitlements
billing_subscriptions              one per account: status, source, plan, period and trial dates
billing_trial_usages               the once-per-user trial rule (email -> trial already used)
billing_entitlement_overrides      P11: one audited exception per (account, kind, name)
billing_webhook_events             P11: one row per Stripe event id, for idempotency
```

Three existed. P11 added two, both additive, both reversible with a byte-identical `db/schema.rb`, neither
carrying a backfill. The minimum was derived from what the repository could not already answer
(`01-discovery.md` §12), not from a five-table template: there is no `plan_versions` table and no
`usage_events` table because nothing in the product needs one yet, and §5 above says why.

---

## 7. Reading order for the rest of P11

| Document | Answers |
|---|---|
| `00-p10-security-closure.md` | every P10 finding, and why no cross-tenant risk was carried into P11 |
| `01-discovery.md` | what already existed, and the eight hazards that shaped this phase |
| `02-commercial-architecture.md` | this document: the layers and where they are enforced |
| `03-plans-entitlements.md` | the plan model, overrides, channel entitlements, plan editing semantics |
| `04-subscriptions-billing.md` | Stripe: checkout, portal, webhooks, idempotency, what is never stored |
| `05-usage-limits.md` | the three counted limits, the lock, and display honesty |
| `06-rollout-compatibility.md` | why deploying this changes nothing, and the order to switch it on |
| `07-security-performance.md` | isolation, secret handling, measurements |
| `08-uat-runbook.md` | what a human must verify on a real installation |
| `P11_RELEASE_GATE.md` | the 68 release questions, answered |
