# P11 — Security and performance

What this phase had to prove about isolation, secrets and cost, and the measurements behind each claim.

---

## 1. Tenant isolation

Four places where commercial code could have crossed a tenant boundary, and what stops each.

### The override row

`billing_entitlement_overrides.account_id` is the only way in. Every read goes through
`account.billing_entitlement_overrides` (`Billing::Entitlements.override_for`), so a capability is resolved
against one account's rows by construction — there is no global lookup by `name` to get wrong.

The revoke action resolves the id **inside** the subscription's own account:

```ruby
override = account&.billing_entitlement_overrides&.find_by(id: params[:override_id])
return back_with(error: 'That override no longer exists.') if override.nil?
```

So another account's override is not refused after being loaded; it is never found. `Billing::OverrideGrant#revoke!`
re-checks `override.account_id == @account&.id` because the service is also reachable from a console and from
future callers, and that check is its own contract rather than a duplicate of the controller's.

Asserted: `spec/controllers/super_admin/billing_overrides_spec.rb` — *"cannot revoke another account's override
through this subscription"*.

### The webhook

A verified Stripe event names an account in three possible ways and the server-owned ones win:
the `stripe_subscription_id` this installation stored, then the `stripe_customer_id` its own checkout wrote,
then — last — `metadata['account_id']` / `client_reference_id`, which must still name a real account.
**Metadata assists; it does not authorize** (P11.14). Before P11 the body's metadata was the first thing tried,
behind a signature check that an empty secret made forgeable — see `04-subscriptions-billing.md` §3 and
`00-p10-security-closure.md` SEC-7.

Asserted: `spec/requests/billing/webhook_security_spec.rb` (12 examples), including a forged event naming a
foreign account.

### The account API

`Api::V1::Accounts::BaseController` scopes every request to the account in the path and the caller's
membership of it. The billing controller adds `ensure_administrator` to the four money actions. A user of
another account reaches nothing, and the responses carry no other account's data.

Asserted: `spec/requests/billing/account_authorization_spec.rb` (7 examples).

### The Platform API

A Platform App reaches an **account** only when that account is among its `platform_app_permissibles`: its
subscription, its plan grants, its trial, its cancellation and its portal link are all behind that check.

**The shared plan catalogue is readable installation-wide and writable only within what the app was granted.**
A Platform App token is an installation-admin credential by upstream design — `PlatformController` exempts
`create` from the permissible check (`app/controllers/platform_controller.rb:7`) and
`Platform::Api::V1::AccountsController#create` creates accounts installation-wide and then makes itself
permissible on them — but upstream's rule is *create freely, modify only what you were granted*, which is why
`show`/`update`/`destroy` go through `validate_platform_app_permissible`. A plan is the one resource every
tenant shares, and a write to it modifies accounts the app may never have been granted: dropping
`limits.agents` from 25 to 1 blocks agent creation for every tenant on that plan, mid-period, and a price
change migrates them all. So `ensure_subscribers_permissible` refuses a plan `update`, `destroy` or `sync`
while any subscriber is outside the app's permissibles, with `non_permissible_subscribers`. Creating a plan
affects nobody and stays open, which is the case a legitimate integration needs. An edit that is in scope is
audited with the `PlatformApp` as the actor (`03-plans-entitlements.md` §5).

This was the one finding of the adversarial audit that survived verification as SECURITY, and it was initially
declined on the argument that an installation-admin token may already create accounts at will. That argument
does not hold: creating an account is additive and harms nobody, while mutating a shared plan is destructive
across tenants the token was never granted. The operator rule still stands alongside the gate — do not issue a
Platform App token to a party you would not give Super Admin to.

**The one thing it may not touch is the installation's Stripe credentials.** That is a different kind of power
from administering accounts: a replacement `stripe_secret_key` points this installation's customers at another
Stripe account, and a replacement `stripe_webhook_secret` both breaks every genuine delivery and re-opens the
forged-event path SEC-7 closed. The Platform API's settings endpoint therefore neither returns the two
`:secret` keys — not even their masked hints — nor accepts them in an update; they are set in Super Admin only,
behind `authenticate_super_admin!`. `stripe_configured` stays in the payload, which is what an integration
actually needs.

Asserted: `spec/requests/platform/api/v1/billing/authorization_spec.rb` (11 examples, including that the
credentials are unreadable and unwritable while the settings an integration may legitimately change still
work).

---

## 2. Billing restriction is not administrative suspension (P11.34)

Two independent states, stored in two places, and **no boolean is overloaded**:

| | Administrative / security suspension | Billing restriction |
|---|---|---|
| Stored in | `accounts.status` (`enum status: { active: 0, suspended: 1 }`) | `billing_subscriptions.status` |
| Set by | a super admin, for a security or policy reason | Stripe, a trial expiry, or a cancellation |
| Vocabulary | 2 values | 5 values (`inactive`, `trialing`, `active`, `past_due`, `canceled`) |
| Enforced by | Chatwoot's own account checks | `Billing::AccessGuard#ensure_billing_access` |
| What the caller is told | the account's own suspension response | `402 payment_required`, `{"error": "subscription_required"}` |
| How it is lifted | an operator un-suspends the account | the customer pays, or an operator grants a plan |

Nothing in the billing subsystem writes `accounts.status`, and nothing in the account-suspension path writes
`billing_subscriptions.status`. The two responses are different codes with different error strings, so a
customer can tell *"pay us"* from *"contact support"*, and an operator can tell them apart in a log.

A third state is deliberately distinct from both: **a plan simply not including a capability** is neither a
suspension nor a restriction — it is a `422` naming the capability or the channel, with an upgrade path.

### The one place the two could be confused, and the operator rule

`Account::SUSPENSION_CATEGORIES` is `%w[spam non_payment other]` (`app/models/account.rb:40`), an upstream
Chatwoot label an operator picks when manually suspending an account. The label `non_payment` names a
*commercial* reason on an *administrative* tool, so the two can be confused by a person even though the code
cannot confuse them: `suspension_category` is an `attr_accessor` stored into `accounts.settings` by
`SuperAdmin::AccountsController` alone, and nothing in the billing subsystem reads or writes it, or
`accounts.status`.

What matters operationally is that the two actions have **different consequences for the customer's data**:

| | Billing lock (`402`) | Manual suspension (`401`) |
|---|---|---|
| Dashboard | closed, except the billing page so they can pay | closed |
| Inbound customer messages | **received and stored** | **refused** — `widgets_controller.rb:62`, `website_token_helper.rb:10`, `ensure_current_account_helper.rb:11` all check `account.active?` |
| Lifted by | the customer paying, or an operator granting a plan | an operator un-suspending |

> **Operator rule: use the billing lock for non-payment.** Manual suspension is for abuse, or for a final
> deliberate shutdown, and it stops the account's customers from reaching it at all.

`non_payment` was **not** removed from the category list. It has a legitimate last-resort use — a long-term
non-payer an operator decides to shut down completely — and the constant is upstream OSS referenced by the
Crowdin-managed locale files in thirty languages, which this project does not edit. The honest fix here is the
rule above plus the UAT step that demonstrates the difference (`08-uat-runbook.md` §4.19), and a note for
P-FINAL that the suspension form should say out loud that suspending stops inbound customer messages.

---

## 3. A billing state never destroys customer data

Three separate guarantees, each proven by where the code is rather than by intent:

1. **Inbound customer messages are never refused.** `Billing::AccessGuard` is included into
   `Api::V1::Accounts::BaseController` only (`config/initializers/billing.rb`). Provider webhooks live under
   the `Webhooks::` and `Platform::` hierarchies, which do not inherit from it. A locked account still
   receives, stores and attributes every WhatsApp, Instagram, Facebook, SMS, email and widget message. The
   account holder cannot open the dashboard; the customer's conversation is not lost (P11.11).
2. **A downgrade deletes nothing.** Every limit and the channel rule are `validate … on: :create`. What the
   account has survives; the next create is refused (`05-usage-limits.md` §5).
3. **Contact identity is untouchable from the commercial path.** Nothing reachable from a plan change, a
   subscription status change or `FeatureSync` writes to `contacts` or `contact_identities`. P10 identity
   survives any downgrade, because historical customer identity is customer data, not a plan feature to erase
   (P11.33).

---

## 4. Secrets

| Secret | Where it lives | Can it be read back? |
|---|---|---|
| Stripe secret key | a locked `InstallationConfig` (`Billing::Settings::KEYS`, `type: :secret`) | no — `ApiSerializer.settings` returns `{ set:, masked: }` |
| Stripe webhook signing secret | the same | no — same shape |
| Card PAN / CVV / expiry | **nowhere.** Stripe-hosted Checkout and Portal | n/a |
| Payment method token | **not stored** | n/a |
| Stripe event payload | **not stored** — `billing_webhook_events` keeps the id, type, timestamps, resolved account and a classified failure | n/a |

Specific decisions:

* **The masked hint is deliberate.** `Billing::Settings.masked` returns `"#{value.first(7)}...#{value.last(4)}"`
  — for `sk_test_51Abc…` that is the public prefix plus four trailing characters. An operator has to be able
  to confirm *which* key is configured and a boolean cannot do that; it is the convention Stripe's own
  dashboard uses. The full value is never returned by any endpoint or rendered on any page.
* **The API key is per-request**, `{ api_key: Billing::Settings.stripe_secret_key }`, never assigned to the
  global `Stripe.api_key`, so nothing else in the process inherits it.
* **A failure stores a class name, not provider prose.** `BillingWebhookEvent#failed!` writes
  `error.class.name`. A Stripe error body can quote the request it was given, and this table is read by
  operators.
* **The audit payload is ids, names, numbers and an operator's typed reason.** `Billing::OverrideGrant#audit_payload`
  and `Billing::PlanAudit` cannot reach a secret.
* **Super Admin pages carry identifiers, not secrets.** The subscription page shows `stripe_customer_id` and
  `stripe_subscription_id`, which identify but do not authenticate.

Asserted: `spec/controllers/super_admin/billing_overrides_spec.rb` (the page matches no `sk_test_` /
`sk_live_` / `whsec_` pattern) and `spec/requests/billing/account_authorization_spec.rb` (the customer API
carries no Stripe identifier and no secret).

---

## 5. Provider isolation (P11.29)

Every Stripe API call is inside `custom/app/services/billing/` or `custom/app/jobs/billing/`:

```
Billing::Checkout              Stripe::Customer, Stripe::Checkout::Session
Billing::Portal                Stripe::BillingPortal::Session
Billing::PlanChange            Stripe::Subscription, Stripe::Invoice
Billing::PlanSync              Stripe::Product, Stripe::Price
Billing::SubscriptionCanceller Stripe::Subscription
Billing::WebhookHandler        Stripe::Subscription
Billing::PriceMigrationJob     Stripe::Subscription
```

The one exception is `Stripe::Webhook.construct_event` in `Billing::WebhooksController`, which is **signature
verification at the request boundary** — the same place `MetaTokenVerifyConcern` and
`TwilioRequestVerification` live. Moving it into a service would move an authentication decision away from the
request it authenticates.

**There is no abstract provider adapter, and that is deliberate.** One provider is integrated, and an
interface designed for a second provider nobody has chosen would be guesswork — the shape of a Stripe
Checkout Session is not the shape of a Paddle or Lemon Squeezy one. What the architecture does guarantee is
the property an adapter would have been built for: **no authorization path calls the provider.**
`Billing::Entitlements`, `Billing::ResourceLimit` and `Billing::AccessGuard` contain no `Stripe::`
reference at all, so answering *"may this account do this?"* never leaves the database.

---

## 6. Caching (P11.53, P11.54)

**Nothing commercial is cached across requests.** No Redis key, no `Rails.cache`, no class-level state.
Entitlement answers, plan limits, channel entitlements and the Stripe settings are all read from the database.

That answers both questions at once: there is no cache to invalidate when an operator grants an override, and
there is no cache key that could be built without a tenant in it. A stale entitlement cache is a customer
either paying for something they cannot use or using something they have not paid for.

Routing `Billing::Settings` through `GlobalConfig` — the Redis-backed reader the rest of the product uses for
installation configs — was tried and **rejected**. Two reasons, in order of weight: a commercial setting whose
staleness decides whether an account is locked is not the same kind of value as a feature flag; and its
invalidation is an `after_commit`, which does not fire under the test suite's transactional fixtures, so the
cache would be correct in production and quietly stale in every spec that changes a setting mid-example. The
measured benefit did not justify either.

What was done instead is narrower and solves the cost where it actually occurred. `accessible?` is asked again
for every capability and every limit resolved in a request (`Billing::Entitlements.plan_for`), and each ask
re-read up to five installation configs. `BillingSubscription#billing_enforced?` now memoizes **only the
installation-wide setting**, per instance. `usable?` stays live, because that one is derived from the row and
the row can be written during a request.

The other reuse is ActiveRecord's own per-request association memoization: `Current.account` is loaded once per
request, so `account.billing_subscription` and `subscription.plan` are each loaded once however many
capabilities are resolved.

---

## 7. Measurements

All figures measured on this branch against the test database.

### The access guard, which runs on every account-scoped request

| | Result |
|---|---|
| Queries on the first call in a request, subscription **usable** | **1** (loads `account.billing_subscription`; `usable?` short-circuits before any setting is read) |
| Queries on every later call in the same request | **0** (association memoized) |
| Extra queries when the subscription is **not** usable | up to **3** `installation_configs` reads for `enforced?`, **once per subscription instance** rather than once per capability resolved |
| Writes across 200 calls for an account that already has a subscription | **0** |
| On an installation with nothing configured | returns `nil` immediately; **0** writes |
| 500 full cycles including a fresh `Account.find` | **0.358 s**, ≈0.7 ms each |

Two honest notes on this path:

* **The extra reads fall on requests that are being refused.** `enforced?` is only reached when `usable?` is
  false — an expired trial, a lapsed grace period, a cancellation — and those requests end in `402`. A paying
  account's request costs one indexed read.
* **The one write is intentional and happens once per account.** With a trial configured,
  `Billing::TrialStarter.subscription_for` creates that account's first subscription row on its first request.
  A parallel first access used to raise `ActiveRecord::RecordInvalid` from the loser — `validates :account_id,
  uniqueness: true` fires before the index does — so the dashboard's opening batch of GETs could return
  `422 "Account has already been taken"` on an ordinary read during rollout. Both classes are now rescued and
  the winner's row is returned (`spec/services/billing/trial_starter_spec.rb`).

### The override lookup — the one query the entitlement layer adds

Measured with 2,001 override rows across 201 accounts, after `ANALYZE`:

```
Limit  (cost=0.28..8.30 rows=1) (actual time=0.047..0.048 rows=1 loops=1)
  ->  Index Scan using uniq_billing_override_per_account_capability on billing_entitlement_overrides
        Index Cond: ((account_id = 1091) AND (kind = 1) AND ((name)::text = 'agents'::text))
        Filter: ((expires_at IS NULL) OR (expires_at >= now))
        Buffers: shared hit=6
Execution Time: 0.074 ms
```

### The seat count

```
Aggregate  (actual time=0.017..0.018 rows=1 loops=1)
  ->  Seq Scan on account_users  Filter: (account_id = 1091)  Buffers: shared hit=1
Execution Time: 0.039 ms
```

A sequential scan is the planner being right, not an index being missing:
`index_account_users_on_account_id` exists (`db/schema.rb:56`) and the table is one page in this database.

### Through ActiveRecord

| Call | 1,000 iterations | per call |
|---|---|---|
| `Billing::Entitlements.limit(account, :agents)` | 1.34 s | 1.34 ms |
| `Billing::ResourceLimit.reached?(account, :agents)` | 2.44 s | 2.44 ms |

Neither is on the hot path of an ordinary request: `limit` runs when something is created and `reached?` runs
only on the agents-create pre-flight.

---

## 8. Indexes added, and the ones that were not (P11.55, P11.56)

**Five indexes, all created with their own new table. Not one index was added to a pre-existing table.**

| Index | Table | Query it serves |
|---|---|---|
| `uniq_billing_override_per_account_capability` (unique, `account_id, kind, name`) | `billing_entitlement_overrides` | resolve one capability for one account — and it *is* the uniqueness rule |
| `index_billing_overrides_on_expiry` (partial, `WHERE expires_at IS NOT NULL`) | `billing_entitlement_overrides` | find what has lapsed, over only the rows that can lapse |
| `uniq_billing_webhook_event_per_provider` (unique, `provider, provider_event_id`) | `billing_webhook_events` | "have we seen this event?" — and it *is* the idempotency mechanism |
| `index_billing_webhook_events_on_account` (`account_id, created_at`) | `billing_webhook_events` | an account's recent billing events |
| `index_billing_webhook_events_on_failures` (partial, `WHERE status = 2`) | `billing_webhook_events` | what is failing right now |

Two of the five are not optimisations at all — they are the correctness mechanism for uniqueness and for
idempotency, and would exist at any scale.

### Declined, with the measurement

The P10 pattern of recording what was *not* added:

* **An expression index on `expires_at` evaluated at query time.** Not added: the EXPLAIN above shows
  `expires_at` applied as a filter on the single row the unique index already found. Indexing it would make
  the planner choose between two indexes for a query that takes 0.074 ms.
* **An index for the three resource counts.** Not added: all three tables already lead with `account_id` —
  `index_account_users_on_account_id` (`db/schema.rb:56`), `index_inboxes_on_account_id` (1407) and the
  composite `index_commerce_stores_on_account_id_and_provider` (945) — and the counts are single-column
  equality aggregates over them.
* **A composite covering index for the Super Admin subscription list.** Not added: it is an operator page
  reading `billing_subscriptions`, one row per account, with Administrate's own pagination.
* **An index on `provider_config->>'phone_number_id'`** (carried from the security closure): measured at
  realistic scale (50 WhatsApp channels) the expression index and a sequential scan were indistinguishable
  (0.086 ms vs 0.084 ms); it only pays at ~2,000 channels (0.483 → 0.042 ms, 64 kB). Not added.

---

## 9. Concurrency

| Race | Serialized by | Evidence |
|---|---|---|
| Two simultaneous invitations at the seat limit | `account.lock!` inside the `AccountUser` save transaction | the mechanism demonstrated at SQL level: T2 blocked 1,175 ms with `FOR UPDATE` held, and did not wait without it |
| Two simultaneous inbox creates at the inbox limit | the same, inside the `Inbox` save transaction | as above |
| Two simultaneous store connections at the store limit | `@account.lock!` already held by `Commerce::StoreConnection#attach` | as above |
| A Stripe event delivered twice | the unique index on `(provider, provider_event_id)` — the database picks the winner, no lock needed | `spec/requests/billing/webhook_security_spec.rb` |
| Two concurrent grants of the same override | the unique index on `(account_id, kind, name)`; `find_or_initialize_by` makes the second an edit | `spec/controllers/super_admin/billing_overrides_spec.rb` |

**Honest limitation.** A threaded Ruby harness did not reproduce the seat race reliably — the *unlocked*
version also passed — so no claim is made from it. What is demonstrated is the serialization itself, directly
at SQL level, and `Billing::ResourceLimit#reached?` is explicitly documented as *not* a gate for exactly this
reason. See `05-usage-limits.md` §2.

---

## 10. What a commercial refusal reveals

Nothing an attacker can use. Every refusal names the capability or the resource and an upgrade path, and never
a plan id the caller is not on, a price, another account, a Stripe identifier or an internal limit key:

```
402  {"error":"subscription_required","message":"This account has no active subscription."}
422  {"error":"plan_limit_reached","message":"Your plan allows up to 5 team members. …"}
422  errors.billing.channel_not_included  -> "Your plan does not include the WhatsApp channel. …"
422  {"error":{"code":"STORE_LIMIT_REACHED"}}
422  "This quote is no longer valid. Please review the amount again."
403  {"error":"Only administrators can manage billing"}
```

All of them are locale keys or fixed strings in English and Arabic. None interpolates a provider message.
