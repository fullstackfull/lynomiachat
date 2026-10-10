# P11.0 — Discovery: what commercial machinery this fork already has

Read before any schema was designed. Every statement below was checked first-hand against the code on this
branch; file:line references are to `claude/p11-saas-commercialization` at the P10 tip `d304d013`.

---

## 0. The headline, stated first

**This fork already has a working SaaS billing subsystem.** Not a stub, not a flag, not an upstream leftover:
three tables, eleven services, a Stripe integration with Checkout and the Customer Portal, trials with an
anti-abuse rule, a grace period, an account-level 402 lock, a Super Admin plan catalogue with custom form
fields, a Platform API, and a mobile checkout path.

```
custom/db/migrate/20260926100000_create_billing_plans.rb
custom/db/migrate/20260926100100_create_billing_subscriptions.rb
custom/db/migrate/20260926120000_create_billing_trial_usages.rb
custom/app/models/billing_plan.rb            custom/app/models/billing_subscription.rb
custom/app/models/billing_trial_usage.rb     custom/app/models/billing/{agent,inbox}_limit.rb
custom/app/models/billing/plan_limits.rb     custom/app/models/billing/api_serializer.rb
custom/app/services/billing/{settings,checkout,plan_change,plan_sync,subscription_sync,
                             subscription_canceller,trial_starter,webhook_handler,
                             feature_sync,admin_actions}.rb
custom/app/controllers/api/v1/accounts/billing_controller.rb
custom/app/controllers/billing/{access_guard,webhooks_controller}.rb
custom/app/controllers/super_admin/billing_{plans,subscriptions}_controller.rb
custom/app/controllers/platform/api/v1/billing/{plans,settings,stats,subscriptions}_controller.rb
custom/app/dashboards/billing_{plan,subscription}_dashboard.rb
custom/app/fields/billing_plan_{features,limits}_field.rb
config/initializers/billing.rb               config/routes/billing.rb
```

So P11's job is **not** to build plans, subscriptions, trials or a billing provider integration. The
architecture rule that governed P10 — do not build a second system — applies with equal force here. P11 is an
**audit-and-close** phase: confirm what is already right, and close the specific gaps that stop this from
being commercially enforceable.

Writing a second `Plan` model, a second entitlement resolver or a second webhook receiver would be the
mistake this phase is most exposed to.

---

## 1. Q1 — What account feature system already exists?

Two independent systems, and they must not be conflated.

**(a) Account feature flags.** `config/features.yml` is the catalogue; `Account` stores them as bitmasks in
two columns via `flag_shih_tzu`:

```ruby
# db/schema.rb, accounts
t.bigint "feature_flags",       default: 0, null: false
t.bigint "feature_flags_ext_1", default: 0, null: false
```

`account.enable_features!`, `disable_features!`, `feature_enabled?(name)`. Super Admin has a features page
(`app/helpers/super_admin/features_helper.rb`). P10 added `lynomia_unified_identity` at `1 << 10`.

Each entry in `features.yml` can carry `chatwoot_internal`, `deprecated` or `premium` (the Enterprise-licensed
ones), which is how the plan form already decides what an operator may sell (§2).

**(b) Custom role permissions.** Per-`AccountUser` strings checked in policies, e.g. P10's
`Custom::ContactPolicy::MANAGE_PERMISSION = 'contact_manage'`. These are *who inside the account may act*,
not *what the account bought*. P11 does not touch them.

## 2. Q2 — What premium flag semantics exist?

`BillingPlan.assignable_features` (`custom/app/models/billing_plan.rb:35-41`) is the existing answer:

```ruby
YAML.safe_load(FEATURES_FILE.read)
    .reject { |f| f['chatwoot_internal'] || f['deprecated'] || f['premium'] }
    .reject { |f| SYSTEM_FEATURES.include?(f['name']) }
```

with `SYSTEM_FEATURES = %w[chatwoot_v4 assignment_v2 report_rollup]` — "flags that must never be switched off
by a plan". So `premium:` already means *Enterprise-licensed, not ours to sell*, and is excluded. That is
correct for this fork, where `enterprise/` is absent, and P11 keeps it.

## 3. Q3 — Can an account currently be disabled or suspended?

Yes, and it is **already separate from billing**, which is what P11.34 asks for:

```ruby
# app/models/account.rb:111
enum :status, { active: 0, suspended: 1 }
```

Operator-set from Super Admin (`app/dashboards/account_dashboard.rb:19`), with its own frontend route
`account_suspended`. Billing restriction is an entirely different mechanism — `billing_subscriptions.status`
plus the 402 guard in §6. **The two are not overloaded onto one boolean, and P11 must keep it that way:**
a past-due account is not `suspended`, and an administratively suspended account is not a billing state.

## 4. Q4/Q5/Q6 — Existing subscription code, billing provider, customer ids

**Q4: yes** (§0). **Q5: Stripe, already integrated** — the `stripe` gem, `Stripe::Checkout::Session`,
`Stripe::BillingPortal::Session`, `Stripe::Subscription`, `Stripe::Invoice.create_preview`,
`Stripe::Webhook.construct_event`. The brief's "do not assume Stripe" is satisfied by evidence rather than by
assumption: it is here, it works, and P11 reuses it. No second provider, and no provider abstraction layer
invented for a second provider that does not exist.

**Q6: yes.** `billing_subscriptions` carries `stripe_customer_id`, `stripe_subscription_id`,
`stripe_price_id`, `stripe_schedule_id`; `billing_plans` carries `stripe_product_id`, `stripe_price_id`
(unique). Keys live in `installation_configs` as locked secrets via `Billing::Settings`, never in a column.

There is also one **upstream leftover**: `app/helpers/billing_helper.rb` reads
`account.custom_attributes['plan_name']` against an `InstallationConfig` named `CHATWOOT_CLOUD_PLANS`. That is
Chatwoot Cloud's own scheme, unrelated to `BillingPlan`, and it is a separate concept living in the same
vocabulary. Recorded in §12 as a naming hazard.

## 5. The existing schema, as it actually is

```
billing_plans         name, description, price_cents, currency, interval, pricing_type,
                      limits jsonb, features jsonb, active, position,
                      stripe_product_id, stripe_price_id (UNIQUE)

billing_subscriptions account_id (UNIQUE), plan_id, scheduled_plan_id, status, source,
                      quantity, trial_ends_at, current_period_end, grace_period_ends_at,
                      cancel_at_period_end, stripe_customer_id,
                      stripe_subscription_id (UNIQUE), stripe_price_id, stripe_schedule_id

billing_trial_usages  email (UNIQUE), account_id, trial_ends_at
```

Things worth naming:

- `billing_subscriptions.account_id` is **unique** — one subscription per account, enforced in the database
  and in the model. The whole design rests on this and it is sound.
- `billing_trial_usages.email` is **globally unique**, which is the anti-abuse rule: one trial per
  administrator email across the installation, not per account.
- `STATUSES = %w[inactive trialing active past_due canceled]`, `SOURCES = %w[stripe manual]` — `manual` is
  how a Super Admin grants a complimentary or internally-invoiced plan, so Q19 (free/internal accounts) is
  already answered.
- `scheduled_plan_id` + `stripe_schedule_id` exist, so a deferred plan change has somewhere to live.

## 6. What is already right, and must not be rebuilt

These are verified, not assumed, and each is a requirement the brief asks for that is **already met**:

| requirement | where it is already satisfied |
| --- | --- |
| Checkout is server-authoritative | `Billing::Checkout#session_params` takes `plan_id` from the browser and resolves `@plan.stripe_price_id` server-side. The browser never supplies a price. |
| Webhook signatures are verified | `Billing::WebhooksController#stripe` uses `Stripe::Webhook.construct_event` with the stored signing secret; `SignatureVerificationError` → 400. |
| Card data never touches Lynomia | Hosted Stripe Checkout and the hosted Customer Portal only. No PAN, no CVV, no payment-method token anywhere. |
| Tax is the provider's job | `Billing::Settings.stripe_tax_enabled?` → `automatic_tax: { enabled: true }`. No tax engine was written. |
| Secrets are never serialized | `Billing::ApiSerializer.settings` returns `{ set:, masked: }` for every `type: :secret` key; `Billing::Settings.masked` shows `first(7)…last(4)`. |
| Currency is explicit per plan | `billing_plans.currency`, validated against a 2-decimal allow-list. |
| Commercial enforcement is separately activatable | `Billing::Settings.enforced?` is false until Stripe keys or a trial plan exist, and `BillingSubscription#accessible?` keeps an un-subscribed account open while it is false. This is the rollout safety Q10/P11.41/42 demand, and it already exists. |
| Admin disable ≠ billing restriction | §3. |
| A plan cannot switch off system flags | `BillingPlan::SYSTEM_FEATURES`. |
| An ended Stripe subscription cannot clobber a manual grant | `Billing::SubscriptionSync#stale_event?` returns true for a terminal event against a `manual?` subscription. |

### 6a. The billing lock does not block inbound customer data

This is the single most important thing to get right about the existing design, and it is **already right**.
`Billing::AccessGuard` is mixed into `Api::V1::Accounts::BaseController` only
(`config/initializers/billing.rb:7`). That base class has 71 descendants — the agent dashboard API. The
inbound surfaces do **not** inherit from it:

```
Webhooks::WhatsappController      < ActionController::API
Webhooks::SmsController           < ActionController::API
Api::V1::Widget::BaseController   < ApplicationController
Public::Api::V1::InboxesController < PublicController
```

`rg -l "Api::V1::Accounts::BaseController" app/controllers/webhooks app/controllers/public
app/controllers/api/v1/widget` returns nothing.

So a past-due or unsubscribed account still receives its customers' messages; what it loses is the dashboard.
That is exactly the policy P11.11 asks for — restrict the paid surface, never drop customer data — and it
holds today by construction rather than by intention. **P11 must not widen the guard onto an inbound path**,
and the regression tests should pin this.

---

## 7. Q8 — Which capabilities have no server-side gate?

**Channels. This is the gap P10 named as the one real P11 dependency, and it is confirmed.**

`BillingPlan::LIMIT_KEYS = %w[agents inboxes stores]`. There is no channel dimension at all: no
per-channel-type limit, and no entitlement consulted when an inbox of a given channel type is created. A plan
can cap the *number* of inboxes but cannot express "this plan does not include WhatsApp".

Per `docs/p10/02-channel-capability-matrix.md` §7, of the twelve channels six have no feature flag at all, and
for those that do the flag is enforced in the frontend only — it hides the tile in `ChannelList.vue` and
nothing more. An administrator who posts directly to `POST /api/v1/accounts/:id/inboxes` gets the inbox.

Everything else commercially interesting *does* have a server-side gate, because plan features are written
into the account's feature flags (§8) and those are checked server-side by the existing feature checks.

## 8. The architectural finding: entitlements and rollout flags are the same storage

`Billing::FeatureSync` (`custom/app/services/billing/feature_sync.rb`) applies a plan by **writing into the
account's feature flags**:

```ruby
managed  = BillingPlan.assignable_features.pluck('name')
included = @plan.features & managed
@account.enable_features(*included)
@account.disable_features(*(managed - included))
```

It runs from `BillingSubscription after_commit` when `plan_id` changes, and from
`BillingPlan after_update_commit` across every subscriber when a plan's feature list changes.

This is why entitlements are already enforced server-side — and it is also the gap P11.4 is about. Three
consequences, each verified:

1. **The two meanings are indistinguishable.** Once synced, nothing records whether `lynomia_commerce` is on
   because the plan includes it or because an operator switched it on for a rollout.
2. **A rollout decision is silently reverted.** An operator who enables a managed feature for one account
   loses it at the next plan sync, because `disable_features(*(managed - included))` is unconditional.
3. **A failure is invisible.** `perform` wraps everything in `rescue StandardError => e` and only logs. A
   plan change whose entitlement write failed leaves the account on the old entitlements with no signal
   anywhere — not Sentry, not Operations.

P11's answer must keep this working mechanism (it is what makes entitlements server-enforced today) while
making the *source* of a capability answerable. Replacing it with a parallel entitlement table that the
existing feature checks do not read would be the second-system mistake.

## 9. Q7/Q10/Q11 — Counting, synchronous enforcement, and the concurrency hole

**Q7, cheap current-state counts that already exist** (`Billing::ApiSerializer.usage`):

```ruby
agents:   { used: account.account_users.count,                 limit: plan&.limit_for(:agents) }
inboxes:  { used: account.inboxes.count,                       limit: plan&.limit_for(:inboxes) }
stores:   { used: account.commerce_stores.connected.count,     limit: plan&.limit_for(:stores) }
```

All three are indexed `account_id` counts. Cheap and canonical.

**Q10, enforced synchronously today:** agents and inboxes, in two places each —
`Billing::AgentLimit` / `Billing::InboxLimit` as `validate … on: :create` (wired by
`config/initializers/billing.rb`), plus `Billing::AccessGuard#ensure_agent_limit` as a `before_action` on the
agents controller. `stores` has a plan key but **no enforcement anywhere** — a limit that is displayed and
sold but never applied.

**The hole.** `Billing::PlanLimits.reached?` is a plain read-then-write:

```ruby
def reached?(account, key, current_count)
  limit = limit_for(account, key)
  !limit.nil? && current_count >= limit
end
```

Two simultaneous invitations at `count == limit - 1` both read `limit - 1`, both pass, both commit. This is
precisely what P11.23 forbids, and there is no unique index or advisory lock behind it to catch the loser.

**Q11, historical versus current-state.** Only current-state exists. There is **no period usage anywhere** —
no counter, no ledger, no billing-period association, nothing reported to Stripe as metered usage. Every
`pricing_type` is `flat` or `per_agent`, and `per_agent` resolves `quantity` from a live
`account.users.count` at checkout and at plan change, not from a usage record.

## 10. Q12 — What genuinely needs new durable data

Derived from the gaps above, deliberately short:

1. **Billing webhook receipts.** There is no record of a received Stripe event, and therefore no idempotency
   and no observability. `Billing::WebhooksController` returns 500 on any error so Stripe retries, and
   `Billing::WebhookHandler` then re-runs — including `Stripe::Subscription.retrieve` and a second
   `FeatureSync`. Nothing can answer "did we process `evt_…`?", which is also why P11.44 (billing failures in
   the Operations Center) has nothing to read today. A minimal table keyed on a unique `provider_event_id`
   is justified; full payloads are not.
2. **Nothing else, probably.** Channel entitlements fit in the existing `billing_plans.limits` /
   `features` jsonb. Account overrides need an answer (§11) but may not need a table. Period usage should
   not be built unless a metered price actually exists — and none does.

`accounts.limits` is **not** a candidate. It exists as a jsonb column, is operator-editable from Super Admin
(`account_dashboard.rb:91`) and is serialized on the Platform API account payload, but nothing server-side
reads it, and the only consumer is `UpgradePage.vue`, which expects Chatwoot Cloud's own
`{conversation:, non_web_inboxes:, agents:}` shape with `allowed`/`consumed` pairs. Reusing it for Lynomia
overrides would collide with that shape and with an upstream page. Recorded as cloud debris, not reused.

## 11. Q13 — What stays outside P11

- **A second billing provider, and the adapter layer for one.** One provider exists and is required; a
  provider abstraction with a single implementation is speculative structure the project's own guidelines
  forbid.
- **A tax engine, invoicing, receipts, FX.** Stripe does tax when enabled; currencies are explicit per plan
  and must never be summed across plans. No conversion.
- **A public pricing or marketing site.** P11.58.
- **Period/metered usage**, unless a metered price exists. None does.
- **AI anything.** No Captain, no AI quota, no AI billing.
- **The licence, provenance and commercial-security audits.** P-FINAL.
- **Replacing the feature-flag system.** §8.

## 12. Hazards found along the way, recorded so they are decided and not stumbled into

1. **Two "Billing" surfaces in the sidebar, one of which leaves the product.**
   `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:771` links `billing_settings_index` and
   `:777` links `subscription_settings_index`, side by side under Settings → Account. The second is the real
   page. The first renders
   `app/javascript/dashboard/routes/dashboard/settings/billing/Index.vue`, which is:

   ```js
   onMounted(() => {
     window.location.href = `https://lynomia.com/admin/subscriptions/${accountId.value}`;
   });
   ```

   A hardcoded external domain, with the account id in the path, reached from **13 places** including the
   sidebar, `PaymentPendingBanner.vue`, the suspended page, five paywalls and both upgrade pages. On a
   self-hosted installation this sends the customer off to someone else's host. Introduced by this fork
   (`7bb7e5d8`), not upstream. This is P11's to resolve: one in-app billing surface.
2. **`BillingHelper` vs `BillingPlan`** — two unrelated plan concepts sharing the word "plan" (§4).
3. **`Billing::PlanLimits.message` is a hardcoded English sentence** built in Ruby
   (`"Your plan allows up to #{limit} #{key}. Upgrade your plan to add more."`), returned to the API as
   `message`. No i18n, no structure, and the resource name is an interpolated English symbol. P11.29 wants a
   structured error; the brief wants Arabic parity.
4. **`billing_plans` has no stable `code` and no version.** Plans are identified by `id` and displayed by
   `name`; editing a plan's `features` immediately rewrites every subscriber's entitlements through
   `FeatureSync`. There is no snapshot of what a customer agreed to. P11.2's question is live and unanswered.
5. **Spec coverage is 17 examples** for the whole subsystem — `billing_controller_spec` (3),
   `billing_helper_spec` (4), `billing_plan_spec` (2), `platform/.../authorization_spec` (8). There is no
   spec for `SubscriptionSync`, `WebhookHandler`, `Checkout`, `PlanChange`, `TrialStarter`, `FeatureSync`,
   `AccessGuard`, `AgentLimit` or `InboxLimit`. For a subsystem that moves money, that is the largest single
   risk in this phase.
6. **Out-of-order Stripe events are only partly handled.** `stale_event?` guards terminal statuses against a
   manual grant or a newer subscription id; nothing orders two non-terminal events, so a delayed `past_due`
   arriving after `active` wins on recency of delivery rather than of truth.
7. **`Billing::TrialStarter.subscription_for` writes on read.** It is called from
   `AccessGuard#ensure_billing_access`, a `before_action`, and creates a `BillingSubscription` row — so a GET
   can insert. It is guarded by `RecordNotUnique` and the unique index, so it is safe, but it is worth
   knowing.
8. **`grace_period_ends_at` is sticky.** `grace_period_for` keeps an existing value
   (`subscription.grace_period_ends_at || …`), so a second past-due episode inherits the first episode's
   already-elapsed date and gets no grace at all. Plausibly intended; undocumented either way.
