# P11 — Subscriptions and billing

How money moves, what Stripe is trusted for, what this installation stores, and what it refuses to store.

---

## 1. Lynomia never touches a card

| | Where it happens |
|---|---|
| Entering card details | Stripe Checkout, on Stripe's domain (`Billing::Checkout`) |
| Changing a card, seeing invoices, cancelling | Stripe Customer Portal, on Stripe's domain |
| Charging, retrying, dunning, tax | Stripe |

**Never stored, never logged, never serialized:** a card number (PAN), a CVV, an expiry, a payment-method
token, a Stripe secret key or a webhook signing secret. The only Stripe identifiers this installation keeps are
`stripe_customer_id`, `stripe_subscription_id`, `stripe_price_id`, `stripe_product_id` — opaque references that
identify but do not authenticate, and that are useless without the secret key.

The secret key and the webhook secret live in locked installation configs (`Billing::Settings::KEYS`, both
`type: :secret`) so they never appear on the generic Installation Configs page. `Billing::ApiSerializer.settings`
returns `{ set: true/false, masked: "sk_test...1234" }` for each — the *shape* of the key, never the key. The
masked hint is deliberate: an operator has to be able to confirm *which* key is configured, and a boolean alone
cannot do that. It is the same convention Stripe's own dashboard uses.

The API key is passed **per request** (`{ api_key: Billing::Settings.stripe_secret_key }`) rather than set on
`Stripe.api_key` globally, so nothing else in the process inherits it.

---

## 2. The flows

### Subscribe

```
customer clicks a plan
  -> POST /api/v1/accounts/:id/billing/checkout        (administrators only)
  -> Billing::Checkout creates a Stripe Checkout Session with client_reference_id = account id
  -> customer pays on Stripe
  -> Stripe sends checkout.session.completed
  -> Billing::WebhookHandler retrieves the subscription and syncs it
```

The price is **never** taken from the browser. The request carries a `plan_id`; the server loads
`BillingPlan.active.find(plan_id)` and uses that row's `stripe_price_id`. A client cannot name an amount, a
currency, an interval or a Stripe price.

### Change plan

`POST /change_plan_preview` returns what the customer will pay or be credited **now**; `POST /change_plan`
applies it. Both are administrators-only.

Stripe is asked to prorate (`proration_behavior: 'always_invoice'`) with
`payment_behavior: 'pending_if_incomplete'`, so if the charge fails Stripe does **not** apply the change —
nobody lands on a more expensive plan without paying. `Billing::PlanChange#perform` additionally raises if
`pending_update` came back set.

**The proration timestamp is validated (P11.16).** `proration_date` decides how much of the period Stripe
prorates, so a browser that chooses it chooses its own price — a timestamp near the period end makes an upgrade
nearly free. The preview returns the instant it quoted and the confirm echoes it back, but only a timestamp
this server could have minted is accepted: within `Billing::PlanChange::QUOTE_VALIDITY` (15 minutes) and never
in the future. Anything else is refused with *"This quote is no longer valid"* rather than silently repriced.
Asserted in `spec/services/billing/plan_change_spec.rb`.

The per-agent quantity is counted the one canonical way
(`Billing::ResourceLimit.current_count(account, :agents)`), so the number billed is the number the seat gate
compares.

### Trial

`Billing::TrialStarter.subscription_for(account)` gives an account its first subscription on first access:
`trialing` on the configured trial plan, or `inactive` when no trial is configured. `BillingTrialUsage` records
the administrator emails that have used a trial, so `trial_once_per_user` can refuse a second one. An account
with no subscription and no trial configured is **not** locked — there is nothing it could pay.

### Cancel

`Billing::SubscriptionCanceller` cancels at Stripe, then the row goes `canceled` and the account is locked. A
Stripe error leaves everything unchanged and is reported (`"Stripe error, nothing was changed: ..."`).

### Price change on a live plan

A Stripe Price is immutable. `Billing::PlanSync` creates a new Price, archives the old one, and
`Billing::PriceMigrationJob` moves existing subscribers **from their next billing period**. No customer is
re-charged mid-period for an operator's price edit. (Entitlement edits are different: see
`03-plans-entitlements.md` §5.)

---

## 3. The webhook: `POST /billing/webhooks/stripe`

### It fails closed

```ruby
secret = Billing::Settings.stripe_webhook_secret
return head :unauthorized if secret.blank?
```

This is the SEC-7 closure from `00-p10-security-closure.md`. The endpoint used to pass
`stripe_webhook_secret.to_s` to the SDK, and `Stripe::Webhook::Signature.compute_signature` only requires the
secret to be a `String` — so an unset secret became `""` and `OpenSSL::HMAC` signed with an empty key, which
anyone can reproduce. A forged event reached `Billing::SubscriptionSync`, which took the account from
`client_reference_id` or `metadata['account_id']` checked only with `Account.exists?`, so a caller could name
**any account on the installation** and move its subscription. The route is mounted unconditionally and does
not consult `Billing::Settings.enforced?`, so the hole was open on exactly the installations that had not
finished setting billing up. Asserted in `spec/requests/billing/webhook_security_spec.rb`.

### Tenant authority is server-owned (P11.14)

`Billing::SubscriptionSync#account_id` resolves the account in this order:

1. the `stripe_subscription_id` **this installation already stored** (`find_subscription`),
2. the `stripe_customer_id` **this installation's own checkout wrote** (`account_id_from_customer`),
3. only then `metadata['account_id']` / `client_reference_id` — and even that must name an existing account.

Metadata assists; it does not authorize. The first two are mappings nobody outside this installation could
have created.

### Exactly once (P11.15)

`billing_webhook_events` has a unique index on `(provider, provider_event_id)` and **that index is the
idempotency mechanism**. `BillingWebhookEvent.claim!` inserts before any work happens; a redelivery loses the
insert, gets `nil`, and is acknowledged without being processed. Concurrency-safe without a lock, because the
database decides the winner.

This matters because the controller returns 500 on a processing failure so that Stripe retries, and Stripe also
documents that it may deliver an event more than once on its own. Without the claim, a retry re-ran a
`Stripe::Subscription.retrieve` and a second `FeatureSync` from the top.

**The payload is not stored.** A Stripe event body carries customer details and, for some types, partial
payment-instrument data, and none of it is needed to answer *"did we process `evt_...`?"*. The row keeps the
event id, its type, its provider-side timestamp, the account it resolved to, when it was processed, and a
**classified** failure string — `error.class.name`, never the provider's message, because a Stripe error body
can quote the request it was given.

### Order (P11.15)

Stripe does not guarantee delivery order. `billing_subscriptions.last_event_at` records the provider timestamp
of the newest event applied, and `SubscriptionSync#out_of_order?` drops anything older — the delayed `past_due`
arriving after `active` case. A subscription with no recorded timestamp has no ordering information yet, so it
accepts the event and records it.

`stale_event?` is a separate rule for a separate problem: a terminal event (`canceled`,
`incomplete_expired`) from an **old** Stripe subscription must not overwrite a newer one, and must never
overwrite a plan the super admin granted manually.

### Failures are visible (P11.44)

A failure is recorded **and** re-raised. The raise makes Stripe retry; the row (`status: failed`,
`failure_reason`) and `Billing::OperationsSignal.record_event_failure` make a repeated failure visible in the
P9 Operations Center, where there was previously nothing at all to read. The partial index
`index_billing_webhook_events_on_failures` (`WHERE status = 2`) is what the failures view reads.

An event that is verified but not interesting — a type this installation does not handle, or one whose account
could not be resolved — is recorded as `ignored` with the reason. **Nothing is silently swallowed.**

### What is *not* signalled

A customer's failed card payment is a normal commercial event, not an operational incident.
`Billing::OperationsSignal` deliberately does not record one: an operator paging on every declined card learns
to ignore the feed. Dunning is Stripe's job and the customer sees it in the Customer Portal; the account's own
state is carried by `past_due` plus the grace period.

---

## 4. Status mapping

Stripe's vocabulary is wider than this product's. `Billing::SubscriptionSync::STATUS_MAP`:

| Stripe | Here | Why |
|---|---|---|
| `active` | `active` | — |
| `trialing` | `active` | a real subscription with a card; the first charge is later. Our `trialing` means *our* trial, with no card. |
| `past_due`, `unpaid` | `past_due` | usable while the grace period lasts |
| `canceled`, `incomplete_expired` | `canceled` | terminal |
| `incomplete`, `paused` | `inactive` | never started, or stopped without being cancelled |
| anything else | `inactive` | `fetch` with a default, so an unknown future Stripe status fails closed rather than crashing |

The grace period is set once when the status first becomes `past_due`
(`subscription.grace_period_ends_at || Billing::Settings.grace_period_days.days.from_now`), so a repeated
`past_due` webhook cannot keep extending it.

---

## 5. The account lock, and what it does not block

`Billing::AccessGuard#ensure_billing_access` answers `402 payment_required` with
`{ "error": "subscription_required" }` to every account-scoped API request when the subscription is not
`accessible?`. The billing controller itself is exempt (`billing_exempt?`), so a locked customer can still see
their plan and pay.

**It does not block inbound customer messages.** The guard is included into
`Api::V1::Accounts::BaseController` only. Provider webhooks live under `Webhooks::` and `Platform::`
controller hierarchies that do not inherit from it, so a WhatsApp, Instagram, Facebook, SMS, email or widget
message from a customer is received, stored and attributed exactly as before while the account is locked. That
is deliberate (P11.11): refusing inbound traffic over a billing state destroys a customer's data to make a
commercial point, and the data is the customer's, not the account holder's. The account holder simply cannot
*open the dashboard* until they pay.

Billing restriction and administrative suspension are also two different states, stored separately — see
`07-security-performance.md` §2.

---

## 6. The Platform API

`/platform/api/v1/billing/...`, authenticated by a Platform App access token
(`api_access_token` header → `AccessToken` → `PlatformApp`).

| Scope | Resources |
|---|---|
| Account-scoped, restricted to the app's `platform_app_permissibles` | subscriptions, subscribers, portal links, plan grants, trials, cancellation |
| Installation-wide | the plan catalogue, the non-secret billing settings, stats |
| **Never** | the Stripe secret key and the webhook signing secret — not readable, not even as a masked hint, and not writable |

A Platform App token is an installation-admin credential by upstream design, so the installation-wide scope is
consistent rather than a widening: `PlatformController` exempts `create` from its permissible check and
`Platform::Api::V1::AccountsController#create` creates accounts installation-wide. The two Stripe credentials
are excluded anyway, because replacing them is not administration — see `07-security-performance.md` §1.

A plan edit through this API is audited exactly as a console edit is, with the `PlatformApp` as the actor
(`Billing::PlanAudit`). That needed a fix of its own: `Custom::AuditLog`'s `after_save` read `user.email`
unconditionally, and `PlatformApp` has a name and no email, so the lookup raised and rolled the audit row
back — the actor with the least accountability was the one whose plan edits went unrecorded.

---

## 7. Mobile

`mobile_checkout_enabled` is a kill switch, default **off**. When on, `checkout` and `portal` accept
`mobile: true` and send the customer back to `BILLING_MOBILE_RETURN_URL` via `/mobile/billing/return`, which
deep-links into the app. When off, the endpoint answers `403 mobile_checkout_disabled` — so a stale app build
cannot start a payment the operator has turned off.
