# P11 FINAL COMPLETION REPORT

**Branch:** `claude/p11-saas-commercialization` · **Base:** P10 tip `d304d013` · **Head:** `94fc5421`, plus this
document — the last code commit is `94fc5421` and every gate was run on it or proven unaffected (§Z)
**Production is unchanged:** `lynomia-custom b03ea43df6abf18cb9c4e5d6a9271ba040b689f4`

---

## A. Executive summary

Two things were asked for and both are done: the P10 security closure, and SaaS commercialization.

**The security closure found that one of the six areas was not what the P10 report had implied.** WhatsApp
inbound routing could not misroute a webhook — `channel_whatsapp.phone_number` is globally unique, so the old
code dropped rather than cross-delivered. The real hole was next to it: a `nil == nil` comparison plus a
payload that could waive its own signature check. Bandwidth was worse than reported and is the one genuine
cross-tenant defect found: the endpoint accepted any unauthenticated body and picked the receiving channel
from body fields. Nine of twelve new Bandwidth examples fail without the fix.

**A sweep beyond the brief's six areas found five more forgeable public endpoints**, including the Stripe
webhook itself: it passed `stripe_webhook_secret.to_s` to the SDK, and `compute_signature` only requires a
`String`, so an unset secret became `""` and anyone could sign an event with an empty key — then name any
account on the installation and move its subscription. That sweep was justified by the brief's own instruction
not to carry a known cross-tenant webhook risk into billing.

**Commercialization turned out to be an audit, not a build.** This fork already had a working billing
subsystem: three tables, eleven services, Stripe Checkout and Portal, trials with an anti-abuse rule, a grace
period, a 402 lock, a Super Admin plan catalogue and a Platform API. The work was therefore to make a plan
*enforceable* rather than to invent a second system — one canonical entitlement service, one canonical count
per resource, a limit two concurrent requests cannot walk past, channel entitlements, and audited per-account
overrides on the Super Admin page that already existed. `Billing::PlanLimits`, a second limit module that
could not see an override, was deleted rather than left beside the new one.

**Then an adversarial audit of my own work found six more defects, and they are fixed here.** The most
important was mine: a feature override did not do what the console said it did. Any Platform App token could
overwrite the installation's Stripe credentials, and a token scoped to one tenant could re-price or re-limit a
plan every other tenant was on. A plan edit through the Platform API was never audited, because the audit
row's own `after_save` raised on a non-User actor. A parallel first access answered 422 on an ordinary GET.
The Operations Center called a billing-locked account healthy.

One of those six I first declined, on the argument that a Platform App token may already create accounts at
will, so a catalogue write was within its existing power. The verifier could not refute the mechanism and the
argument does not hold on inspection — creating an account is additive and harms nobody, while mutating a
shared plan is destructive across tenants the token was never granted. It is fixed, by applying upstream's own
rule (create freely, modify only what you were granted) to the one resource every tenant shares.

**Then the full test suite found two more, which no targeted run could have.** Its first complete execution
failed six examples: a security fix had left an upstream spec asserting the behaviour it removed, and the X
webhook-route removal had left the channel's OAuth connect flow calling a route helper that no longer existed —
a path whose own spec stubbed the broken object whole. Both are fixed, and the suite is green on the re-run
(§Z). Running it to the end, rather than inferring it from the targeted runs, is what produced them.

Nineteen commits, 134 files, +7,610/−730. **No unclosed cross-tenant risk remains in anything this phase
touched**, and commercial enforcement is inert until an operator configures it.

**Verdict: PASS WITH KNOWN LIMITATIONS** (§AH).

---

## B. P10 security closure

`docs/p11/00-p10-security-closure.md` classifies every finding. Summary of the six named areas plus the sweep:

| Area | Outcome |
|---|---|
| SC1 Bandwidth webhook | **FIXED.** HTTP Basic per channel — the only mechanism Bandwidth documents; no HMAC invented. Channel from the path, never the body. Fail-closed with `WWW-Authenticate` when unconfigured, which is also the handshake Bandwidth requires. Replays deduplicated on the provider's message id. |
| SC2 Bandwidth delivery receipts | **FIXED.** Every event enqueued with its channel; the DLR handler receives the documented envelope (`type`, `description`, `errorCode`). Nothing swallowed, no status fabricated. |
| SC3 WhatsApp routing | **PROVEN SAFE, then improved.** Could not misroute (global uniqueness → drop). Now authoritative on `phone_number_id` with a bounded fallback; the adjacent `nil == nil` and signature-exemption holes are closed. |
| SC4 TikTok | **FIXED** (state TTL + `required_claims`, authority before scopes, generic errors, 5 s webhook tolerance, secret-in-query-string method deleted). The P10 duplicate-contact fix is intact. No provider approval claimed. |
| SC5 Dead voice endpoints | **MADE HONEST.** Three unusable channels removed from the two pickers, with reasons. No placeholder endpoint created, no Voice built. |
| SC6 X / retired channel | **MADE HONEST.** Webhook routes and controller removed, and — after gate 5 proved the remainder could only raise — the OAuth connect flow with them (§6.1 of the closure). The channel model, outbound service, parsers, factories and capability row stay: **no historical data deleted**. |
| Sweep (beyond the brief) | **FIXED:** the Stripe webhook's blank-secret hole, Twilio inbound and delivery status (now `X-Twilio-Signature`), the Slack integration webhook's blank secret, and `facebook-messenger`'s `return unless app_secret_for(...)` — a nil secret skipped verification entirely, now backed by a memoized random secret so verification always fails closed. |

Two findings were **deliberately not fixed**, with the reasoning recorded: the WABA `calls` subscription (the
fix would mutate live provider state on a judgement call) and the Facebook page fan-out (needs a Graph check
plus a uniqueness migration whose production duplicates cannot be read from here).

---

## C. Discovery conclusions

`docs/p11/01-discovery.md` answers the thirteen questions. The three that changed the shape of the phase:

1. **A billing subsystem already exists.** Building a second one would have been the single worst outcome
   available, so every piece of P11 extends what is there.
2. **The 402 lock does not block inbound customer messages** — proven by reading which controller hierarchies
   include the guard, not assumed. That made it safe to keep the lock as-is.
3. **Nothing could stop an account connecting a channel its plan does not include.** Of twelve channel types
   only five had a feature flag at all, and where one existed it hid the dashboard tile and nothing more. P10
   had named this as its one real P11 dependency, and it was correct.

Eight hazards were listed up front; the one that mattered most was *do not mutate old feature flags into
billing records*, which is why `accounts.feature_flags` is untouched by every migration.

---

## D. Commercial architecture

`docs/p11/02-commercial-architecture.md`. Four layers, one answer-producing service:

```
1 SYSTEM / INSTALLATION   BillingPlan::SYSTEM_FEATURES — never a commercial question
2 ACCOUNT OVERRIDE        billing_entitlement_overrides — one account, reasoned, audited
3 PLAN ENTITLEMENT        billing_plans.features / .limits / .channel_entitlements
4 DEFAULT                 accounts.feature_flags — today's behaviour
```

`Billing::Entitlements` is the only producer of `allowed?`, `limit`, `channel_allowed?` and `source`.
Enforcement sits at the earliest shared entry point for each thing and is never repeated downstream: a
`before_action` for the lock, `AccountUser` and `Inbox` validations for seats, inboxes and channels, and
`Commerce::StoreConnection#attach`'s existing transaction for stores. Layer 1 is a hard block rather than a
precedence winner, so no plan can sell or withhold a system capability.

---

## E. Plan model

`BillingPlan`: price in cents + currency + interval, `pricing_type` (`flat` | `per_agent`), `features`,
`limits`, `channel_entitlements`, `active`, `position`. Three validations make it impossible to sell something
that does not exist — features against `assignable_features`, channels against
`Channels::Capability::BY_CHANNEL_TYPE`, limits non-negative — and `normalize_attributes` turns an empty limit
field into "no ceiling" rather than `0`.

**Versioning (P11.2).** Price is version-safe by delegation to Stripe's immutable Prices; entitlements are
not versioned and change every subscriber immediately. No `plan_versions` table was built: the product rule is
to create a new plan and move customers, which the system already supports. What was built is the thing that
makes the immediacy honest — the plan form prints how many accounts pay for the plan before those three fields
are edited, and `Billing::PlanAudit` records the before/after, the actor and the affected count on both
writing paths.

---

## F. Entitlement architecture

One service, four layers, and the answer to *which layer said so*. The override row is the piece that did not
exist: `billing_entitlement_overrides (account_id, kind, name)` unique, three kinds (`feature`, `limit`,
`channel`), a **required** reason, an optional expiry whose lapse needs no sweeper because the `live` scope
excludes it, and `granted_by` pointing at the `SuperAdmin` who acted (a `User` subclass on the `users` table).

`Billing::OverrideGrant` is the only writer, for the same reason `Operations::SignalRecorder` is the only
writer of a signal. A grant **applies**: for a feature override it writes the capability into the account's own
flags in the same transaction, and a revoke writes the plan's answer back. Until that was fixed the console's
promise — *switch one capability on or off regardless of the plan* — was false; the row existed and exempted
the capability from the next sync, but nothing turned it on. An override is refused for anything outside
`assignable_features`, because `disable_features!` on a system flag would break the installation.

---

## G. Feature flag interaction

Flag = rollout and availability. Entitlement = what a subscription bought. Both kept, and the bridge is
deliberate: plan features are written into `accounts.feature_flags` by `Billing::FeatureSync`, so that table
stays the single store of effective state and all 124 existing `feature_enabled?` call sites keep working
untouched.

Three corrections to `FeatureSync`:
1. It subtracts `overridden_capabilities` from the managed set, so an operator's audited decision is not the
   plan's to move.
2. Failures are reported — logger **and** Sentry **and** an operations signal — rather than swallowed into a
   log line.
3. It records what it switched **off** for an account that had it on
   (`billing.capabilities_revoked_by_plan_sync`), which is how a capability disappearing stays explainable
   even when the operator who enabled it wrote the flag directly instead of granting an override — the one
   decision the override layer cannot protect, because there is nothing to read.

---

## H. Resource limits

Three, and only three: `agents`, `inboxes`, `stores`. Conversations, messages, contacts, campaigns, flows,
templates, labels, automation rules and API calls are all countable and none is limited, because no plan
charges for them.

`Billing::ResourceLimit` owns three things that used to be scattered:

* **`COUNTS`** — one counting expression per resource, now used by the gate, the account API, the Super Admin
  page, the commerce endpoint and the per-agent Stripe quantity alike. Two of those previously disagreed.
* **`exceeded`** — the gate. `account.lock!` **before** counting, inside the save's own transaction.
* **`reached?`** — a read-only pre-flight, documented in the code as *not* a gate because it takes no lock.

The race (P11.23): the old check was `current_count >= limit` outside any lock, and there is no unique index
behind these counts to catch the loser. The serialization was demonstrated at SQL level — T2 blocked 1,175 ms
with `FOR UPDATE` held and did not wait without it. Stated plainly: a threaded Ruby harness did **not**
reproduce the end-to-end race, so no claim is made from it.

`nil` means unlimited everywhere — never `0`, never `-1`.

---

## I. Seat model

A seat is one `AccountUser` row, whatever the role or custom role. The rule lives on `AccountUser` because
every way of adding a person — an invitation, a bulk invite, the Platform API, a reactivation — creates one;
a controller check would have had to be repeated in each and missed in the next. `Billing::AccessGuard` adds a
pre-flight on the agents-create actions so the refusal is readable before Chatwoot starts building a user, and
that pre-flight deliberately takes no lock because it runs outside any transaction.

---

## J. Channel entitlements

`billing_plans.channel_entitlements`, a jsonb array of `Channel::` class names validated against
`Channels::Capability` — the list P10 established as the one inventory of channel types this fork actually
has. Enforced by `Billing::InboxLimit#billing_channel_entitlement` on every inbox create, which covers the
dashboard, every provider's OAuth callback and the Platform API.

**An empty list denies nothing.** That is what every pre-P11 plan has, and it is why adding the column gated
nothing. A downgrade that drops a channel keeps every existing inbox of that type, its history and its
inbound traffic; only the next create is refused.

Channel entitlements are a separate rule from the inbox *count*, and the code says so: an account can be
within its inbox ceiling and still not be entitled to WhatsApp, and vice versa.

---

## K. Subscription lifecycle

`inactive → trialing → active → past_due → canceled`, one row per account. `usable?` answers "may they use the
dashboard"; `accessible?` adds "and an account that never subscribed is not locked while there is nothing to
pay". Stripe's wider vocabulary is mapped with a `fetch` default of `inactive`, so an unknown future status
fails closed rather than crashing. The grace period is set once, so a repeated `past_due` cannot extend it.

A cancellation closes the dashboard and **deletes nothing** — no conversation, message, inbox, contact,
`contact_identity` or store.

---

## L. Trials

`Billing::TrialStarter`: `trialing` on the configured trial plan, or `inactive` when nothing is configured, or
**no row at all** when there is nothing to pay — in which case the account is not locked. `BillingTrialUsage`
records administrator emails so `trial_once_per_user` can refuse a second.

One defect fixed: a parallel first access answered `422 "Account has already been taken"` on an ordinary GET.
Only `RecordNotUnique` was rescued, but `validates :account_id, uniqueness: true` fires before the index does,
so the losers of the dashboard's opening batch of GETs raised `RecordInvalid`. Both are now rescued and the
winner's row returned.

The `trial_once_per_user` rule is **not** covered by a repository spec, deliberately and with the reasoning in
the spec file: it reads `account.administrators` at the moment the trial starts, and `after_create_commit`
fires while a factory-built account still has none, so only the real signup flow exercises it. It is a UAT row
instead (`08-uat-runbook.md` §3.7).

---

## M. Billing provider architecture

Stripe, already selected before P11. Every Stripe API call lives in `custom/app/services/billing/` or
`custom/app/jobs/billing/` — this phase moved the last two out of controllers (`Billing::Portal`, which two
controllers had duplicated inline, and `Billing::PlanSync.archive_product!`). The one remaining exception is
`Stripe::Webhook.construct_event` in the webhook controller, which is signature verification at the request
boundary and belongs beside `MetaTokenVerifyConcern` and `TwilioRequestVerification`.

**There is no abstract provider adapter, deliberately.** One provider is integrated and an interface designed
for an unchosen second would be guesswork. The property an adapter would have been built for is guaranteed by
construction instead: `Billing::Entitlements`, `Billing::ResourceLimit` and `Billing::AccessGuard` contain no
`Stripe::` reference, so answering *may this account do this?* never leaves the database.

Server-authoritative pricing: the client sends a `plan_id` and nothing else that affects money. **Including the
proration quote** — `proration_date` decides how much of the period Stripe prorates, so a browser choosing it
was choosing its own price; only a timestamp this server minted, inside a 15-minute window and never in the
future, is accepted.

---

## N. Webhook security and idempotency

| Property | How |
|---|---|
| Signature verified | `Stripe::Webhook.construct_event`, and **`401` on a blank secret** (the SEC-7 closure) |
| Tenant authority | the stored subscription id, then the customer id our own checkout wrote, then — last — body metadata, which must name a real account. **Metadata assists; it does not authorize.** |
| Exactly once | the unique index on `(provider, provider_event_id)`. `claim!` inserts before any work; a redelivery loses the insert and is acknowledged. The database picks the winner, so no lock. |
| Order | `billing_subscriptions.last_event_at` + `out_of_order?` drops an event older than the newest applied. Null means "no ordering info yet", so the guard starts working from the first event after deployment with no backfill. |
| Terminal-event safety | `stale_event?` refuses a `canceled` from an old subscription and never overwrites a manual grant |
| Failures visible | the row (`status: failed`, a **classified** reason — `error.class.name`, never the provider's prose) plus an operations signal, and the error is re-raised so Stripe retries |
| Nothing swallowed | a verified but unhandled event is recorded as `ignored` with its reason |
| Payload | **not stored.** The row keeps the event id, type, timestamps, resolved account and processed time. |

The deliberate non-signal: a customer's declined card is a commercial event, not an operational incident.

---

## O. Usage metering

Current resource counts: implemented, exact, one query each, derived from the live rows.
Period usage metering: **deliberately not built.** `PRICING_TYPES` is `%w[flat per_agent]` — no plan charges
per message, conversation or API call, so a `usage_events` table would be a table to write, index, migrate,
retain and reconcile against Stripe for revenue that does not exist. `05-usage-limits.md` §6 records the
decision, writes down the shape to add if a metered price ever appears, and states that P8's volumes are
product analytics with a retention window and are **not** safe to invoice from.

Currencies are explicit, validated and never combined: the only aggregate (the Platform API's MRR) totals per
currency.

---

## P. Upgrade and downgrade

**Upgrade.** Stripe prorates with `always_invoice` and `pending_if_incomplete`, so a failed charge means the
change is not applied — nobody lands on a more expensive plan without paying — and `perform` additionally
raises if `pending_update` came back set. The amount shown is the amount charged, because the quote's
timestamp is reused, within the window that makes it unforgeable.

**Downgrade.** One policy, applied everywhere:

> **A downgrade stops the next create. It never removes what the account already has.**

All three limits and the channel rule are `on: :create`. Four inboxes survive a one-inbox plan; the fifth is
refused. A WhatsApp inbox survives a plan that stops selling WhatsApp, and keeps receiving. The alternative —
deleting or disabling over-limit resources — was rejected outright: a billing event is exactly the moment a
customer is least willing to lose data.

**Price change on a live plan** moves subscribers from their next billing period
(`Billing::PriceMigrationJob`); nobody is re-charged mid-period.

---

## Q. Existing-account compatibility

`06-rollout-compatibility.md` §1 proves, as six file:line facts, that deploying changes nothing: the lock needs
billing configured, an account with no subscription is never locked, no plan means no ceiling, no override
rows means today's answer, an empty channel list denies nothing, and `FeatureSync` only fires on a plan
change. No migration writes a row and **no backfill is required before boot** — the one that exists is
operator-invoked and raises unless a trial is configured.

The switch-on order is written down, eight steps, each inert until the next, with the two that can surprise a
paying customer (filling in `limits`, filling in `channel_entitlements`) deliberately last. **The one ordering
trap is named:** configuring Stripe before starting trials locks every account that has no subscription row,
because `enforced?` becomes true and `inactive` stops being accessible; the safe order is 1 → 3 → 2, and the
recovery is to run the backfill.

And the operational point: **enforcement is data, not code.** A wrong limit at 2am is fixed by emptying a
field in the console, not by shipping a release.

---

## R. Super Admin commercial tools

Extended, not replaced. No second Super Admin was built.

| Surface | What P11 added |
|---|---|
| Billing Plans (Administrate) | a `channel_entitlements` field sourced from `Channels::Capability`, with a blast-radius warning on the edit form and an audit row on every entitlement change |
| Billing Subscriptions → show | the plan's channels, usage against the **enforced** limits, an Overrides table (kind, capability, effect, reason, granted by, expiry, lapsed state) and three grant forms |
| Billing Subscriptions → actions | `grant_override` and `revoke_override` beside the existing extend-trial, grant-plan and cancel |
| Operations → Accounts | a billing column, so a locked account no longer reads as healthy |

Boundaries asserted: an unauthenticated caller and a tenant administrator can grant nothing, and a revoke
resolves the override id **inside** the subscription's own account, so another account's override is never
found rather than merely refused.

---

## S. Account Billing and Usage UI

The off-product redirect to `lynomia.com/admin/subscriptions/:id` is gone. The `billing_settings_index` route
it sat behind is referenced 18 times across 14 dashboard files, every one of which now lands on the real
in-product subscription page (behind the existing account-loaded guard, kept because the billing API is
account-scoped), and the sidebar has one Billing entry instead of two.

The usage card reads `used / limit` where the limit is the **enforced** one — an operator's override included,
because a number on a screen that differs from what the server will do is the dishonesty P11.28 is about.
`null` renders as the localized **Unlimited** / **غير محدود**; `-1` is never produced. Administrators get
subscribe, change-plan and portal actions; agents get the page read-only.

---

## T. Operations Center integration

Three new signals through the existing `Operations::SignalRecorder`, with no new store:
`entitlement_sync_failed`, `unknown_provider_customer`, `billing_event_failed` — added to the `SOURCES`,
`SIGNALS` and `DETAIL_KEYS` allow-lists (a signal not declared there is silently dropped by validation, which
a test caught). Plus a durable `billing_webhook_events` row per failure with a partial index over the failures.

And the gap this phase closed: **Operations → Accounts called a billing-locked account healthy**, because its
only "cannot use the product" column read `accounts.status`, which a billing lock never touches. A sixth
component now warns, naming the subscription status, read off an association preloaded with the page so the
query count per page is unchanged.

---

## U. Support Ticket integration

Unchanged by design. A billing signal can be turned into a support case through the Operations Center's
existing `open_case!` bridge, which an operator invokes per signal — nothing opens a case automatically, and a
declined card is not a signal at all. No ticket code was modified; `Support::Ticket` is not referenced by
anything commercial.

---

## V. Database and schema changes

Four migrations, all additive, each applied → rolled back → re-applied with a **byte-identical `db/schema.rb`**.

| Migration | Shape | Rewrites rows? |
|---|---|---|
| `create_billing_entitlement_overrides` | new table, 2 indexes | no |
| `add_channel_entitlements_to_billing_plans` | `add_column :jsonb, default: [], null: false` | no — Postgres 11+ records a non-volatile default as metadata; the table holds a handful of rows anyway |
| `create_billing_webhook_events` | new table, 3 indexes (one partial) | no |
| `add_last_event_at_to_billing_subscriptions` | `add_column :datetime`, nullable **on purpose** | no |

`last_event_at` is nullable because every existing subscription has had events applied whose timestamps were
never recorded; inventing one would either reject the next legitimate event or accept a stale one. `nil` means
"no ordering information yet".

`db/schema.rb`: +37/−1. No existing column changed type, no existing row rewritten, no data migration.

One file was **deleted** rather than left: `custom/app/models/billing/plan_limits.rb`, with all three callers
migrated — a second limit module that read the plan directly and so could not see an override, and whose
message was an untranslatable English sentence built in Ruby.

---

## W. Indexes and EXPLAIN evidence

**Five indexes, all created with their own new table. Not one index was added to a pre-existing table.** Two of
the five are the correctness mechanism for uniqueness and for idempotency and would exist at any scale.

Measured at 2,001 override rows across 201 accounts, after `ANALYZE`:

```
Limit  (cost=0.28..8.30 rows=1) (actual time=0.047..0.048 rows=1 loops=1)
  ->  Index Scan using uniq_billing_override_per_account_capability on billing_entitlement_overrides
        Index Cond: ((account_id = 1091) AND (kind = 1) AND ((name)::text = 'agents'::text))
        Filter: ((expires_at IS NULL) OR (expires_at >= now))
        Buffers: shared hit=6
Execution Time: 0.074 ms
```

Seat count: `Aggregate → Seq Scan on account_users`, 0.039 ms — the planner being right on a one-page table
whose `account_id` index exists for production scale.

**Declined, with the measurement**: an expression index on `expires_at` (already a filter on the single row
the unique index found); indexes for the three resource counts (all three tables already lead with
`account_id`); a covering index for the Super Admin list (one row per account, Administrate paginates); and —
carried from the security closure — an expression index on `provider_config->>'phone_number_id'`, which at 50
WhatsApp channels is indistinguishable from a sequential scan (0.086 ms vs 0.084 ms) and only pays at ~2,000
(0.483 → 0.042 ms, 64 kB).

---

## X. Security

| Property | Status |
|---|---|
| Tenant isolation of overrides | by construction — every read goes through `account.billing_entitlement_overrides`; the revoke resolves the id inside the account |
| Webhook tenant authority | server-owned mappings first, metadata last and never alone |
| Cross-account billing API | refused by `Api::V1::Accounts::BaseController`; asserted |
| Agent vs administrator | the four money actions are administrator-only; reads are open to account members, stated plainly |
| Platform API account scope | `platform_app_permissibles` on every account-scoped action |
| Platform API shared plan writes | refused while any subscriber is outside what the app was granted (`non_permissible_subscribers`). A token scoped to one tenant could otherwise re-price or re-limit a plan twelve others were on, mid-period. Creating a plan affects nobody and stays open |
| Platform API and the Stripe credentials | **not readable, not even as a masked hint, and not writable.** This was a real hole: any Platform App token could replace the installation's secret key (pointing customers' payments at another Stripe account) or its webhook secret (breaking every genuine delivery and re-opening the forged-event path) |
| Secrets in responses, pages, logs, audits | none. Keys are locked `:secret` configs returned as `{set:, masked:}` in Super Admin only; failures store a class name; audit payloads are ids, names, numbers and a typed reason |
| Card data | never received, stored, logged or serialized |
| Event payloads | not persisted |
| Billing restriction vs administrative suspension | two columns in two tables, two status codes, two messages. Nothing in billing writes `accounts.status` |
| Inbound customer data under a billing lock | received and stored; the guard reaches only account-scoped API controllers |

One hazard is **documented rather than coded**: `Account::SUSPENSION_CATEGORIES` includes `non_payment`, an
upstream label that names a commercial reason on an administrative tool — and a manual suspension *does* cut
off inbound widget traffic with `401`, which the billing lock never does. The category was not removed (it has
a legitimate last-resort use, and the constant is upstream OSS referenced by Crowdin-managed locale files in
thirty languages). The fix is the operator rule — *non-payment belongs to the billing lock* — plus the UAT
step that demonstrates the difference, and a P-FINAL note that the suspension form should say out loud that
suspending stops inbound customer messages.

---

## Y. Performance

| Measurement | Result |
|---|---|
| Access guard, first call in a request, usable subscription | **1 query** (`usable?` short-circuits before any setting is read) |
| Access guard, every later call in the same request | **0** |
| Extra cost when the subscription is **not** usable | up to 3 `installation_configs` reads for `enforced?`, **once per subscription instance** rather than once per capability resolved — and only on requests that end in `402` |
| Writes across 200 guard calls for an account that has a subscription | **0** |
| 500 full guard cycles including a fresh `Account.find` | 0.358 s (≈0.7 ms each) |
| Override lookup | 0.074 ms, index scan, 6 buffers, at 2,001 rows |
| `Billing::Entitlements.limit` through ActiveRecord | 1.34 ms |
| `Billing::ResourceLimit.reached?` | 2.44 ms |
| Provider calls on an authorization path | **none** |

**Nothing commercial is cached across requests.** Routing `Billing::Settings` through `GlobalConfig`'s Redis
cache was tried and **rejected**: a commercial setting whose staleness decides whether an account is locked is
not a feature flag, and its invalidation is an `after_commit`, which does not fire under the suite's
transactional fixtures — correct in production and quietly stale in every spec that changes a setting
mid-example. The narrower fix was taken instead.

---

## Z. Tests — exact results

### The five gates, run sequentially on a clean tree

| # | Gate | Result | Tree |
|---|---|---|---|
| 1 | `bundle exec rubocop` | **2894 files inspected, 0 offences** | `94fc5421` |
| 2 | `pnpm eslint` | **478 problems, 0 errors** (478 warnings, every one pre-existing) | `cd829d1b` |
| 3 | `npx vite build` | **✓ built in 2m 15s** | `cd829d1b` |
| 4 | `pnpm test` | **491 test files, 5294 tests, 0 failures**, 346.47 s | `cd829d1b` |
| 5 | `bundle exec rspec` | **9609 examples, 0 failures, 70 pending**, 49m 42s, exit 0 | `94fc5421` |

Four things about that table are worth stating plainly rather than leaving to be inferred.

**Gates 2, 3 and 4 ran at `cd829d1b`, not at the final tree.** Every commit after it changes only `.rb` and
`.md` files — verified rather than assumed: `git diff --name-only cd829d1b..HEAD` lists paths whose only
extensions are `rb` and `md`. ESLint lints JavaScript and Vue, Vite builds JavaScript, CSS and assets, and
Vitest runs JavaScript specs; none of the three reads a Ruby or Markdown file. So the three results stand for
the final tree. A re-run of gate 4 was started at `f7fb32b2` and **interrupted by me** at 163 of 491 files
(exit 143, SIGTERM). That run is **void** and is counted as nothing, in either direction.

**Gate 1 ran twice**, and is reported at the final tree. The first run inspected 2902 files with no offences;
the second inspected 2894 — exactly the eight `.rb` files the X connect removal deleted.

**Gate 5 ran twice, and the first run failed.** Both runs are recorded below, because the first is what found
the only two defects this phase's targeted runs had missed.

**One commit follows gate 5**: this document, with §Z, §AC and three corrected lines. It touches no `.rb`,
`.js`, `.vue` or configuration file, so no gate result above is stale.

### Gate 5, run 1 — 9619 examples, **6 failures**, 70 pending, 48m 15s (tree `98902565`)

This was the first complete `bundle exec rspec` of the phase, and it earned its 48 minutes. Both causes were
this phase's own work, and both were invisible to every targeted run:

| # | Example | Cause |
|---|---|---|
| 1 | `requests/api/v1/integrations/webhooks_request_spec.rb:16` — *"skips verification and processes the webhook"* | The **upstream** spec still asserted, by name, the behaviour SEC-8 removed. Three fail-closed contexts were added to that file without updating the one that contradicted them, so the suite asserted both at once. |
| 2–6 | `services/twitter/webhook_subscribe_service_spec.rb` ×5 — `undefined method 'webhooks_twitter_url'` | SC6 (`2fb2985b`) removed X's inbound webhook routes and left the OAuth connect half standing. Its last step exists only to tell X where to deliver, through a route helper that no longer exists. The callback's own spec stubs that service whole, so no example had ever called it. |

Neither was a flake, and neither was a stale assertion about something decided deliberately — one was a
contradiction left inside a security fix, the other a live code path left pointing at a deleted route. Both are
fixed in `94fc5421`: finding 1 now asserts the refusal (401, and `IncomingMessageBuilder` never constructed);
findings 2–6 removed the X connect flow, which cannot be fixed without reviving an unauthenticated inbound
endpoint. §6.1 of `00-p10-security-closure.md` has the reasoning and the exact inventory of what went and what
deliberately stayed.

### Gate 5, run 2 — **9609 examples, 0 failures**, 70 pending, 49m 42s, exit 0 (tree `94fc5421`)

The ten-example drop is accounted for exactly, which is the point of stating it: the three removed specs held
5 (`webhook_subscribe_service`), 2 (`callbacks_controller`) and 3 (`authorizations_controller`) examples —
9619 − 10 = 9609. No example was skipped, renamed or silenced to reach zero failures, and the Slack example was
rewritten rather than deleted, so it still counts.

### New coverage in this phase

18 new spec files. Headline counts, each verified by running the file:

| Spec | Examples | What it proves |
|---|---|---|
| `requests/webhooks/sms_security_spec.rb` | 12 | Bandwidth authentication; 9 fail without the fix |
| `requests/webhooks/whatsapp_routing_isolation_spec.rb` | 12 | two accounts, conflicting Argentina display numbers, distinct Meta ids |
| `requests/webhooks/public_endpoint_authentication_spec.rb` | 12 | Twilio ×2, Slack, Facebook forged and unauthenticated |
| `requests/billing/webhook_security_spec.rb` | 12 | blank secret, forged signature, foreign account, redelivery, order |
| `requests/tiktok/oauth_state_security_spec.rb` | 9 | state TTL, required claims, authority before scopes |
| `controllers/super_admin/billing_overrides_spec.rb` | 18 | grant/revoke/audit/boundaries, the override actually applying, downgrade keeping data |
| `services/billing/entitlements_spec.rb` | 19 | precedence across all four layers |
| `models/billing/resource_limit_spec.rb` | 13 | the three ceilings and their messages |
| `requests/platform/api/v1/billing/authorization_spec.rb` | 11 (3 new) | permissible scoping + the credential boundary |
| `services/operations/account_health_spec.rb` | 14 (3 new) | the billing column |
| `services/billing/feature_sync_spec.rb` | 5 | override exemption, revocation record, failure reporting |
| `services/billing/settings_spec.rb` | 7 | defaults, secret retention, masking, enforcement |
| `services/billing/trial_starter_spec.rb` | 3 | no-config, first access, the parallel-access 422 |
| `services/billing/plan_change_spec.rb` | 3 | the proration quote window |
| `services/billing/plan_audit_spec.rb` | 4 | what moved, who moved it, a PlatformApp actor, a failed audit |
| `controllers/super_admin/billing_plans_spec.rb` | 4 | the Administrate wiring and the blast-radius warning |
| `requests/billing/account_authorization_spec.rb` | 7 | agent vs administrator, cross-account, no secret in a response |

### Deliberately changed existing assertions

Five specs, each encoding a contract this phase changed rather than a regression:

1. `billing_controller_spec` — `usage` is now `{used:, limit:}` per resource, not a bare count.
2. `commerce/stores_controller_spec` — `store_limit` now reports the enforced ceiling.
3. The two Twilio controller specs — the request body now derives from the channel, which is what the examples
   mean and what removes the `RSpec/LetSetup` offences.
4. `integrations/webhooks_request_spec` — the Slack endpoint fails closed when no signing secret is
   configured, so the example that asserted the opposite now asserts the refusal. This one was a miss rather
   than a decision: the contradiction shipped in `403d423f` and sat in the suite until gate 5 ran.

### Honest notes on testing

* A threaded harness did **not** reproduce the seat race; the serialization is proven at SQL level and
  `reached?` is documented as not a gate. No claim is made from the harness.
* One example was **removed** rather than bent: it asserted response parity between a foreign-account and an
  expired TikTok state, a property the design does not have and does not need, since minting any state
  requires the app secret.
* The `trial_once_per_user` rule is deliberately not spec'd, with the reason in the spec file, and is a UAT row
  instead.
* `billing_helper_spec` was observed to fail once in a multi-file batch (`CHATWOOT_CLOUD_PLANS` duplicate) and
  did not reproduce on repeated single-file runs on either tree; recorded as an observed flake rather than
  patched blind.

---

## AA. Frontend coverage

| Surface | Change |
|---|---|
`app/javascript/dashboard/routes/dashboard/settings/billing/Index.vue` | **deleted** — it was only `window.location.href = 'https://lynomia.com/admin/subscriptions/…'`
`billing/ProviderIndex.vue` | renders the real in-product subscription page behind the retained account-loaded guard
`components-next/sidebar/Sidebar.vue` | one Billing entry instead of Billing + Subscription
`settings/subscription/Index.vue` | usage reads `used / limit` from the enforced ceiling, with `Unlimited` semantics; EN and AR text updated
`inbox-mgmt/channels/BandwidthSms.vue` | two required callback credential fields with help text
`ChannelFactory.vue`, `ChannelList.vue` | three unusable channels removed, each with a reason
`inboxMixin.js`, `ConfigurationPage.vue` | `isABandwidthSmsChannel`; the callback URL rendered through previously orphaned strings

**EN/AR parity verified by script**, not by eye: the subscription page's inline dictionary has 49 keys in each
language with zero asymmetry, `commerce.json` has 357/357, and all 17 of this phase's `inboxMgmt` keys have
Arabic siblings. (The repo-wide `inboxMgmt` gap of 69 keys is pre-existing Crowdin territory, per the project
rule that only `en.json` is edited for source strings.)

---

## AB. Documentation

| File | Lines | Contents |
|---|---|---|
`docs/p11/00-p10-security-closure.md` | 394 | every P10 finding classified; the sweep; nine SAFE AS-IS; measurements |
`docs/p11/01-discovery.md` | 332 | Q1–Q13; the proof that the 402 lock does not block inbound; eight hazards |
`docs/p11/02-commercial-architecture.md` | 183 | the four layers, where each is enforced, what was not built and why |
`docs/p11/03-plans-entitlements.md` | 255 | plan, subscription, override; precedence; the versioning decision |
`docs/p11/04-subscriptions-billing.md` | 239 | Stripe flows; the webhook; what is never stored |
`docs/p11/05-usage-limits.md` | 247 | the three limits, the lock, display honesty, why metering is not built |
`docs/p11/06-rollout-compatibility.md` | 150 | why deploying changes nothing; the switch-on order and its one trap |
`docs/p11/07-security-performance.md` | 371 | isolation, the two lock states, secrets, measurements, declined indexes |
`docs/p11/08-uat-runbook.md` | 194 | ~70 steps a human runs against Stripe test mode; every row PENDING |
`docs/p11/P11_RELEASE_GATE.md` | 491 | all 68 questions |
`docs/p11/P11_FINAL_COMPLETION_REPORT.md` | this document | sections A–AI |

Totals: **eleven documents, 3,574 lines**, all written against the code rather than from the brief.

---

## AC. Commits

Nineteen, on `claude/p11-saas-commercialization`, first-to-last:

| | |
|---|---|
`99985c5c` | authenticate Bandwidth callbacks and stop the body choosing the tenant
`9b6b95d5` | discovery — this fork already has a billing subsystem
`2253e919` | bound the TikTok OAuth state in time and to a person
`71e84983` | route WhatsApp inbound by Meta's `phone_number_id`, and stop the body waiving its own signature
`417f24b4` | one entitlement service, channel entitlements, and a limit two requests cannot walk past
`fe5a26bb` | fail closed on an unset webhook secret; make events idempotent and order-safe
`403d423f` | authenticate the four remaining public endpoints that trusted their own body
`2fb2985b` | stop offering three channels that cannot work; remove the X webhook routes
`d7885ee7` | the P10 security closure, classified
`9154f392` | operable entitlement overrides and one enforced limit
`826dcdde` | validate the proration quote; audit plan entitlement edits
`727e56ed` | rollout safety, UAT runbook, account billing authorization specs
`102c21e8` | every Stripe API call in one layer
`b33695dc` | close five defects an adversarial audit proved
`cd829d1b` | make the Twilio channel dependency explicit; fix a stale spec pointer
`f7fb32b2` | scope a shared plan write to the accounts the app was granted
`98902565` | verifiable counts, and the final report in the reading order
`94fc5421` | remove the X connect flow the webhook-route removal left broken

Plus one more: this document, carrying the gate-5 results and the lines they correct. Its own hash cannot
appear inside itself, and `git log d304d013..HEAD` is the authority either way.

Measured at `94fc5421`, so excluding that last documentation commit: **134 files, +7,610/−730**. By area: 49
`custom/`, 34 `spec/`, 33 `app/`, 11 `docs/`, 4 `config/`, 2 `lib/`, 1 `db/`. The first nine commits are the
P10 security closure, as the brief required.

---

## AD. Known limitations

1. **Plan entitlements are not versioned.** Editing a live plan's `features`, `limits` or
   `channel_entitlements` changes every subscriber immediately and mid-period. Mitigated by the blast-radius
   warning on the form and a mandatory audit row; the product rule is to create a new plan instead. The shape
   to add if versioning is ever needed is written down.
2. **Period usage metering does not exist.** Correct today — no plan charges per unit — and the shape to add
   is recorded. If a metered price is introduced, this is the first thing to build.
3. **`non_payment` remains an administrative suspension category.** An operator who reaches for the wrong tool
   will cut off inbound customer messages, which the billing lock never does. Closed with an operator rule, a
   UAT step and a P-FINAL note rather than by removing an upstream constant referenced by thirty locale files.
4. **A raw feature-flag write still escapes the override layer.** The account features form and the Platform
   API's account update write `accounts.feature_flags` directly, and a later plan sync will undo such a write.
   The sync now records what it switched off, so the revert is explainable; routing those two writers through
   `Billing::OverrideGrant` needs a reason field in forms that do not have one and is a P-FINAL item.
5. **The billing read surface is open to every account member**, including custom-role users whom the
   dashboard route denies the page. Nothing writable is reachable and nothing crosses an account boundary; if
   the read is meant to be role-bounded, the one place to express it is a `before_action` on the three read
   actions.
6. **`Billing::Settings.masked` has no minimum-length floor**, so a stored value of eleven characters or fewer
   would be echoed whole. Not applicable to a real Stripe key (`sk_live_` + 24+, `whsec_` + ~32) and therefore
   not guarded, per the project rule against speculative guards — recorded here rather than silently left.

---

## AE. Pending real UAT

**P11 (new):** the whole of `08-uat-runbook.md` — a real Stripe test-mode round trip (Checkout, webhook,
Portal, a plan change with a real proration invoice, dunning into `past_due` and recovery), the
two-administrator seat race on a real server, the trial once-per-user rule, the suspension-versus-lock
contrast, and the forged-webhook steps against a running installation.

**Carried forward unchanged, and NOT marked passed from seeded tests:**

* **P8** — production rollups, the reports pilot, the Analytics screens, the Contact Timeline, real Meta status
  cases, a genuine-new-contact WhatsApp send.
* **P9** — all real Tickets / SLA / Operations UAT.
* **P10** — real channel and provider UAT, the contact identity pilot, the TikTok real-provider check, channel
  health validated against a real provider.

---

## AF. P8 / P9 / P10 regression

**537 examples, 0 failures** across `spec/services/{analytics,operations,support,channels,contacts}`,
`spec/models/{contact_identity,operations,support}`, `spec/services/social_channels` and the Super Admin
Operations controller.

Four semantics were changed deliberately, each with its spec updated rather than worked around: the `usage`
response shape, `Custom::AuditLog`'s non-User actor handling (148 examples across every audit writer re-run
green), the sixth `AccountHealth` component, and `Commerce::StoreConnection` reading its ceiling from the
entitlement service.

---

## AG. Enterprise verification

| Check | Result |
|---|---|
`ls -d enterprise` | **absent** |
`ChatwootApp.extensions` | `["custom"]` |
`ChatwootApp.enterprise?` | `false` |
`ChatwootApp.custom?` | `true` |

No Enterprise billing, SLA or audit code was copied. The only two mentions of "enterprise" in the new code are
comments explaining an avoidance: the per-request Stripe `api_key` (so nothing inherits a global one Enterprise
code may set) and the exclusion of `premium` features from what a plan may sell.

**AI boundary honoured:** Captain was not activated, no `CAPTAIN_OPEN_AI_API_KEY` was added, and no AI billing,
quota, matching or assistant was implemented. (`captain_tasks` appears in the generic assignable-features list
because it is a non-premium flag upstream; P11 sells no AI capability.)

**P-FINAL boundary honoured:** no licence audit, no provenance audit, no clean-code campaign, no final
commercial security audit.

---

## AH. Final verdict

# PASS WITH KNOWN LIMITATIONS

The P10 security closure is complete and no unclosed cross-tenant risk remains in anything this phase touched:
the one genuine cross-tenant defect (Bandwidth) is fixed and tested, the five additional forgeable endpoints
found by the sweep are closed, and WhatsApp routing was proven safe before being improved. Commercialization is
server-enforced rather than labelled, inert until an operator configures it, additive and reversible in the
schema, and audited where an operator can change a customer's commercial reality.

The limitations are the six in §AD. None is a security or data-integrity risk; each is a recorded decision with
the smaller work it would take to close it. The verdict is not PASS because of the real UAT debt in §AE, which
no repository test can discharge, and because two of the limitations (plan versioning, the raw flag-write
escape) are commercial-correctness gaps that a human will eventually meet in production.

---

## AI. Recommended P-FINAL entry point

Enter P-FINAL at the branch tip of `claude/p11-saas-commercialization` — last code commit `94fc5421` — and take
these in order:

1. **Discharge the UAT debt first** (§AE), because it is the only thing standing between this branch and a
   deployable state, and because P-FINAL's audits are cheaper against a validated product. The Stripe
   test-mode round trip is the single highest-value run.
2. **The licence and provenance audits**, which P11 deliberately did not touch and which gate any release.
3. **The final commercial security audit**, using `docs/p11/07-security-performance.md` §1–§5 as its starting
   inventory rather than rediscovering it; the two deliberate non-fixes in §B and the six limitations in §AD
   are the list of things to re-decide with fresh eyes. Add to it the unreachable X frontend
   (`channels/Twitter.vue`, `twitterClient.js`) and the X inbound library, which §6.1 of the closure left for
   the licence and provenance audits rather than delete alongside the connect flow.
4. **The clean-code campaign**, last, because it touches the most files and benefits from everything above
   being settled.

Two P-FINAL items this phase generated and could not close itself: route the account-features form and the
Platform API's account update through `Billing::OverrideGrant` (§AD.4), and make the account suspension form
say out loud that suspending stops inbound customer messages (§AD.3).
