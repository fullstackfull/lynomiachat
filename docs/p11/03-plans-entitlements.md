# P11 — Plans, entitlements and overrides

The commercial model: what a plan carries, how an exception is granted, and what happens when an operator
edits a plan people are paying for.

---

## 1. The plan row

`billing_plans` (`custom/app/models/billing_plan.rb`). One row per sellable tier.

| Column | Type | Sells | Enforced by |
|---|---|---|---|
| `price_cents`, `currency`, `interval` | int, string, string | the money | Stripe (`Billing::PlanSync`) |
| `pricing_type` | `flat` \| `per_agent` | how the money scales | `Billing::PlanChange#quantity` |
| `features` | jsonb array of `config/features.yml` names | capabilities | written into the account's flags by `Billing::FeatureSync` |
| `limits` | jsonb `{agents:, inboxes:, stores:}` | counted ceilings | `Billing::ResourceLimit` |
| `channel_entitlements` | jsonb array of `Channel::` class names | which channels | `Billing::InboxLimit#billing_channel_entitlement` |
| `active`, `position` | boolean, int | whether and where it is offered | `BillingPlan.active.ordered` |

Three validations stop a plan selling something that does not exist:

* `validate_features` — every name must be in `BillingPlan.assignable_features`, which excludes system,
  internal, deprecated and `premium` (Enterprise-licensed) entries of `config/features.yml`.
* `validate_channel_entitlements` — every entry must be a key of `Channels::Capability::BY_CHANNEL_TYPE`, the
  one list of channel types this fork actually has (P10). A typo cannot sell a channel that does not exist.
* `validate_limits` — no negative ceiling. `normalize_attributes` also slices `limits` to `LIMIT_KEYS` and
  drops blanks, so an empty field becomes "no ceiling" rather than `0`.

**An empty list denies nothing.** `channel_entitlements: []` means the plan has no opinion about channels;
`BillingPlan#channel_included?` returns true for everything. That is what every plan that existed before P11
has, and it is why adding the column gated nothing.

---

## 2. The subscription row

`billing_subscriptions` — exactly one per account (`validates :account_id, uniqueness: true`). It holds the
status, the source (`stripe` or `manual`), the plan, and the period/trial/grace dates.

```
inactive   never subscribed, or nothing configured yet
trialing   usable while trial_ends_at is in the future
active     usable; a manual grant may carry an optional current_period_end
past_due   usable while grace_period_ends_at is in the future
canceled   not usable
```

Two predicates, and the difference matters:

* `usable?` — may the account use the dashboard right now?
* `accessible?` — `usable?` **or** (`inactive` and billing is not set up). An account that never subscribed is
  not locked while there is nothing to pay for.

`Billing::Entitlements.plan_for` returns the plan only when `accessible?` is true
(`custom/app/services/billing/entitlements.rb:78-84`). An unusable subscription sells nothing, so a canceled
account has no plan ceiling — which is harmless because `Billing::AccessGuard` answers `402` to every
account-scoped request before any create is attempted.

---

## 3. The override row

`billing_entitlement_overrides` — one audited commercial exception for one account.

```
account_id   kind                name                  value             reason       granted_by  expires_at
  42         feature   'channel_tiktok'        enabled: true      'paid pilot'    super admin   2026-12-01
  42         limit     'inboxes'               limit_value: 9     'migration'     super admin   nil
  99         channel   'Channel::Whatsapp'     enabled: false     'abuse case'    super admin   nil
```

| Kind | `name` is | Carries | Beats |
|---|---|---|---|
| `feature` | a `config/features.yml` feature name | `enabled` | the plan's `features`, and the next `FeatureSync` |
| `limit` | a `BillingPlan::LIMIT_KEYS` key | `limit_value` | the plan's `limits` |
| `channel` | a `Channel::` class name | `enabled` | the plan's `channel_entitlements` |

Rules the model enforces (`custom/app/models/billing_entitlement_override.rb`):

* `reason` is **required**. An exception nobody can explain a year later is the failure this prevents.
* One row per `(account_id, kind, name)`, by unique index. Granting the same capability twice is an edit.
* `value_matches_kind` — a `limit` override must carry a number, a `feature`/`channel` override a boolean.
  Accepting the wrong one would make the entitlement service answer `nil` silently.
* `expires_at` is optional. The `live` scope excludes lapsed rows, so an expiry needs no sweeper job: the
  ceiling falls back to the plan's the moment it passes.
* The `kind` enum is `_prefix: :kind`, so the predicates are `kind_limit?` rather than `limit?` — the same
  reason P10's `ContactIdentity` prefixes its `source` enum.

### Who may grant one

`Billing::OverrideGrant` is the only writer (`custom/app/services/billing/override_grant.rb`), for the same
reason `Operations::SignalRecorder` is the only writer of a signal: the audit row is not optional and a second
caller that forgot it would leave an exception nobody can explain.

* `grant!(kind:, name:, reason:, value:, expires_at: nil)` → upserts the row, then writes one
  `Custom::AuditLog` row (`billing.override_granted`) against the account.
* `revoke!(override)` → refuses an override belonging to another account, destroys it, writes
  `billing.override_revoked` with a snapshot of what was removed.
* A failed audit write logs and does **not** undo the grant: the customer's access is the thing that matters,
  and the same reasoning governs P10's contact-merge audit.
* The audit payload is ids, names, numbers and the operator's typed reason. No secret can reach it.

The surface is the Super Admin subscription page that already existed — `grant_override` and `revoke_override`
on `SuperAdmin::BillingSubscriptionsController`, an Overrides table and three forms (feature / limit / channel)
on `custom/app/views/super_admin/billing_subscriptions/show.html.erb`. **No second Super Admin was built.**

Boundaries, asserted in `spec/controllers/super_admin/billing_overrides_spec.rb`:

| Caller | Can grant? |
|---|---|
| Unauthenticated | no — redirected, no row written |
| A tenant administrator of the account | no — there is no session that makes an account user an operator |
| A super admin | yes, with a reason; the grant is audited |

A revoke resolves the override id **inside the subscription's own account** before it is loaded, so another
account's override is not merely refused — it is never found.

---

## 4. Precedence

```
Billing::Entitlements.allowed?(account, capability)
  1. system?    -> account.feature_enabled?(capability)        and stop. Plans cannot sell or withhold it.
  2. override?  -> override.enabled
  3. (the plan's features are already in the account's flags)
  4. default    -> account.feature_enabled?(capability)

Billing::Entitlements.limit(account, resource)
  1. override?  -> override.limit_value
  2. plan       -> plan.limit_for(resource)
  3. default    -> nil (unlimited)

Billing::Entitlements.channel_allowed?(account, channel_type)
  1. override?  -> override.enabled
  2. plan sells channels? -> entitled.include?(channel_type)
  3. default    -> true
```

`Billing::Entitlements.source` returns which layer answered (`:system`, `:override`, `:plan`, `:default`). That
is the question the feature flags alone could never answer, and the reason an operator's deliberate enablement
used to be indistinguishable from a plan's — and therefore silently reverted by the next sync.

---

## 5. Editing a plan: the versioning decision (P11.2)

**There is no `plan_versions` table, and this is a deliberate choice.** The brief asks to avoid premature
complexity while preventing obvious commercial inconsistency. Here is the honest accounting of what each
column does when an operator edits a live plan:

| Edited | Effect on existing subscribers | Safe? |
|---|---|---|
| `price_cents`, `currency`, `interval` | A Stripe Price is immutable, so `Billing::PlanSync` creates a new one, archives the old, and `Billing::PriceMigrationJob` moves subscribers **from their next billing period**. Nobody is re-charged mid-period. | yes, already deferred |
| `name`, `description`, `position`, `active` | cosmetic / catalogue only | yes |
| `features` | `after_update_commit sync_subscribers_features` re-syncs **every** subscriber's flags at once, mid-period | **immediate** |
| `limits` | read live by `Billing::Entitlements.limit`; the new ceiling applies to the next create, mid-period | **immediate** |
| `channel_entitlements` | read live; the next inbox of a dropped channel is refused, mid-period | **immediate** |

### The product rule

> To sell something different, **create a new plan** and move customers to it. Do not edit the entitlements of
> a plan people are paying for.

The system already supports that fully: plans are rows, and `grant_plan` (Super Admin) or `change_plan` (the
customer, or the Platform API) moves a subscriber. Existing customers stay on the plan they bought, which is
exactly what a version would have given them, without a second source of truth for entitlements to keep in
sync.

### What prevents the inconsistency being *silent*

Because an operator can still edit a live plan, two things make it deliberate rather than invisible:

1. **The blast radius is shown where the edit happens.** The plan form prints how many accounts currently pay
   for the plan and what changing the three entitlement fields will do
   (`custom/app/views/fields/billing_plan_limits_field/_form.html.erb`).
2. **The change is audited.** `Billing::PlanAudit.record` writes one `Custom::AuditLog` row
   (`billing.plan_entitlements_changed`) with the before/after of `features`, `limits` and
   `channel_entitlements`, the actor, and the number of paying accounts affected. Both writing paths call it:
   the Super Admin console (actor: the `SuperAdmin`) and the Platform API (actor: the `PlatformApp`).

Asserted in `spec/services/billing/plan_audit_spec.rb`, including that a canceled subscription is not counted
as affected and that a failed audit write never looks like a failed edit.

### If versioning is ever needed

The shape, written down so the next phase need not rediscover it: snapshot the three entitlement columns onto
`billing_subscriptions` when the plan is assigned, and have `Billing::Entitlements` prefer the snapshot over
the plan. That is a second store of entitlement state and a reconciliation problem — correct only once there
are enough live tiers that the "create a new plan" rule becomes unmanageable. It is **not** built now.

---

## 6. Feature sync, and what it must not touch

`Billing::FeatureSync` applies a plan by writing its features into `accounts.feature_flags`:

```ruby
managed  = BillingPlan.assignable_features.pluck('name') - overridden_capabilities
included = @plan.features & managed
@account.enable_features(*included)
@account.disable_features(*(managed - included))
```

Two P11 corrections are in those four lines:

1. `- overridden_capabilities` — an operator's audited decision is not the plan's to move. Without it, the
   unconditional `disable_features` reverted every manual enablement at the next sync.
2. Failures are reported rather than swallowed: `Rails.logger.error` **and**
   `ChatwootExceptionTracker` **and** `Billing::OperationsSignal.record_sync_failure`, so a plan change whose
   entitlement write failed is visible in the Operations Center where an operator looks, instead of leaving the
   account on its old entitlements with no signal anywhere.

The managed set is only `assignable_features`, so a system flag (`chatwoot_v4`, `assignment_v2`,
`report_rollup`), an internal flag, a deprecated flag or an Enterprise `premium` flag is never written by a
plan sync in either direction.

---

## 7. What the account itself sees

`GET /api/v1/accounts/:id/billing/entitlements` returns the effective state, not the plan's wish list:

```json
{
  "active": true, "status": "active", "source": "manual",
  "plan": { "id": 3, "name": "Pro" },
  "features": { "lynomia_commerce": true, "channel_tiktok": true },
  "limits": { "agents": { "used": 3, "limit": 5 },
              "inboxes": { "used": 2, "limit": null },
              "stores":  { "used": 1, "limit": 9 } }
}
```

`features` is read through the account's own flags, so an override shows as the capability being on. `limits`
is read through `Billing::Entitlements`, so an override shows as the ceiling. Nothing here names a plan id a
customer did not buy, a price, or any Stripe identifier beyond what `04-subscriptions-billing.md` lists.
