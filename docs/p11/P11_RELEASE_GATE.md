# P11 — Release gate

All 68 questions, answered from the code on `claude/p11-saas-commercialization`. Every answer is a statement
about this repository, not an intention. Where the honest answer is "not built" or "needs a human", it says so.

---

## SECURITY CLOSURE (1–6)

**1. Is the Bandwidth webhook authenticated or fail-closed?**
Authenticated, and fail-closed when it cannot be. `Webhooks::SmsController` now requires HTTP Basic
credentials stored on the receiving `Channel::Sms` (`callback_username` / `callback_password`), compared with
`ActiveSupport::SecurityUtils.secure_compare` using `&` rather than `&&` so the answer does not reveal which
half matched. A channel with no credentials configured gets `401` with `WWW-Authenticate` — which is also
exactly the handshake Bandwidth's documented mechanism requires before it retries with credentials. HTTP Basic
on the Messaging Application is the **only** authentication Bandwidth documents for callbacks; no HMAC format
was invented. Both fields are required in the dashboard (EN + AR) and the callback URL is shown on the
configuration page. `spec/requests/webhooks/sms_security_spec.rb` — 12 examples, 9 of which failed before the
fix.

**2. Can a request body choose another tenant?**
No, on any endpoint this phase touched. The Bandwidth channel is resolved from the **path** (the inbox's own
callback URL), never from the body. Twilio inbound and delivery status now verify `X-Twilio-Signature` against
the candidate channel's own auth token. The Stripe webhook resolves the account from the subscription id this
installation stored, then the customer id its own checkout wrote, and only then from body metadata — which
must still name a real account. The Slack and Facebook paths fail closed on a blank secret.
`spec/requests/webhooks/public_endpoint_authentication_spec.rb` (12 examples) and
`spec/requests/billing/webhook_security_spec.rb` (12 examples).

**3. Are the Bandwidth receipts safe?**
Yes. Every callback event is enqueued with `channel_id`, and `Webhooks::SmsEventsJob` returns without doing
anything when the channel cannot be resolved — fail-closed for a rolling deploy rather than guessing. Delivery
receipts are handed the **envelope** (`inbox:`, `params:`), which is the shape Bandwidth documents and which
carries `type`, `description` and `errorCode`; nothing is swallowed and no delivery status is fabricated.
Replays cannot duplicate a message: `Sms::IncomingMessageService#already_recorded?` checks
`inbox.messages.exists?(source_id: params[:id])` against Bandwidth's own message id.

**4. Is WhatsApp routing proven tenant-safe?**
Yes, and the question was answered before anything was changed: the old routing **could not misroute** an
inbound webhook, because `channel_whatsapp.phone_number` is globally unique — it dropped rather than
cross-delivered. The real hole next to it was different: a `nil == nil` comparison plus a
body-chosen signature exemption. Routing is now authoritative on Meta's `phone_number_id` with a strictly
bounded fallback (an exact display-number row is accepted only when its stored id is blank), a blank id routes
nowhere, ambiguity is logged, and `meta_signature_verification_required?` returns true for any WhatsApp
Business payload. `spec/requests/webhooks/whatsapp_routing_isolation_spec.rb` — 12 examples including two
accounts with the conflicting Argentina display forms `+5491145551234` / `+541145551234` and distinct Meta ids.
The expression index on `provider_config->>'phone_number_id'` was **measured and declined**: at 50 channels it
is indistinguishable from a sequential scan (0.086 ms vs 0.084 ms).

**5. Were the TikTok security findings closed or classified?**
Closed where repository or provider evidence allowed, classified otherwise. The OAuth `state` token now has a
15-minute TTL and `required_claims: %w[exp sub uid]` — `jwt` 2.10.3's `verify_expiration` does **not** make
`exp` mandatory (`lib/jwt/claims/expiration.rb:22`), which is why the explicit option was needed. The callback
checks the state's authority (account present, the state's user is an administrator of it, `channel_tiktok`
enabled) **before** looking at granted scopes, errors are generic, and the error page falls back to
`FRONTEND_URL/app` when there is no account to scope to. The webhook enforces a 5-second timestamp tolerance.
`Tiktok::AuthClient#webhook_callback` was deleted: it put the app secret in a GET query string. The P10
duplicate-contact fix is intact. `spec/requests/tiktok/oauth_state_security_spec.rb` — 9 examples. No claim of
provider approval or real UAT is made.

**6. Are the dead and retired channels honestly represented?**
Yes. `ChannelFactory.vue` no longer offers `twitter`, `whatsapp_call` or `voice`, and `ChannelList.vue` no
longer pushes the `voice` and `whatsapp_call` entries — each removal carries a comment saying why. The X
webhook routes are gone and the controller with them, replaced by a comment, and so is the OAuth connect flow
those routes were the other half of: gate 5 proved it could only end in `NoMethodError`, since its last step
registers a delivery URL that no longer exists (§6.1 of the closure). **No historical data was deleted** — the
channel model, its outbound service, both inbound parsers, the factories and the `Channels::Capability` row all
stay, so Operations still answers `unknown` for an existing X inbox — and no placeholder endpoint was created.
Voice was not built.

---

## COMMERCIAL MODEL (7–10)

**7. What is the canonical Plan model?**
`BillingPlan` (`custom/app/models/billing_plan.rb`), one row per sellable tier, carrying price/currency/interval,
`pricing_type` (`flat` or `per_agent`), `features` (names from `config/features.yml`), `limits`
(`{agents, inboxes, stores}`) and `channel_entitlements` (`Channel::` class names). Three validations stop it
selling something that does not exist. See `03-plans-entitlements.md` §1.

**8. What is the canonical Subscription model?**
`BillingSubscription`, exactly one per account (`validates :account_id, uniqueness: true`), with five statuses,
a source (`stripe` or `manual`), the plan, and the period/trial/grace dates. `usable?` answers "may they use
the dashboard"; `accessible?` adds "and an account that never subscribed is not locked while there is nothing
to pay". §2 of the same document.

**9. Are plans version-safe?**
**Partly, and the asymmetry is deliberate and documented.** Price is version-safe by delegation: a Stripe Price
is immutable, so `Billing::PlanSync` creates a new one and `Billing::PriceMigrationJob` moves subscribers from
their next period — nobody is re-charged mid-period. Entitlements (`features`, `limits`,
`channel_entitlements`) are **not** versioned: editing them changes every subscriber immediately. There is no
`plan_versions` table, because the product rule is to create a new plan and move customers, which the system
already supports fully, and a snapshot would be a second store of entitlement state to reconcile. What was
built instead is the thing that makes the immediacy honest rather than silent: the plan form prints how many
accounts currently pay for the plan before those three fields are edited, and `Billing::PlanAudit` records the
before/after, the actor and the affected count on both writing paths. `03-plans-entitlements.md` §5 has the
full table and the shape to add if versioning is ever needed.

**10. Can existing accounts remain unaffected at rollout?**
Yes, and `06-rollout-compatibility.md` §1 proves it as a chain of six file:line facts: the lock needs billing
configured, an account with no subscription row is never locked, no plan means no ceiling, no override rows
means today's answer, an empty channel list denies nothing, and `FeatureSync` only fires on a plan change. No
migration writes a row.

---

## ENTITLEMENTS (11–15)

**11. Is there one canonical server-side entitlement service?**
Yes: `Billing::Entitlements` (`custom/app/services/billing/entitlements.rb`), with `allowed?`, `limit`,
`channel_allowed?`, `source` and `overrides`. Nothing else compares a plan name or reads
`billing_plans.features` directly. The companion `Billing::ResourceLimit` owns counting and locking, and
`Billing::PlanLimits` — a second module that read the plan directly and so could not see an override — was
**deleted**, with all three of its callers migrated.

**12. Are feature flags distinct from plan entitlements?**
Yes, and both are kept. A flag is availability and rollout; an entitlement is what a subscription bought. A
capability can require both. The bridge is deliberate: plan features are written into the account's own flags
by `Billing::FeatureSync`, so `accounts.feature_flags` stays the single store of effective state and all 124
existing `feature_enabled?` call sites keep working. No flag was migrated into a billing record, and no
migration touches `accounts.feature_flags`. `02-commercial-architecture.md` §3.

**13. Can frontend hiding ever substitute for server enforcement?**
No, and that was a real gap this phase closed. Before P11, five of the twelve channel types had an account
feature flag and the flag only hid the dashboard tile — an administrator POSTing to the inboxes endpoint got
the inbox. The channel rule is now an `Inbox` validation, asserted by a spec that posts past the UI
(`08-uat-runbook.md` §6.8 repeats it against a real server). The same holds for limits (model validations) and
the lock (a `before_action` on every account-scoped controller).

**14. Can channel creation be blocked by plan?**
Yes. `Billing::InboxLimit#billing_channel_entitlement` refuses an inbox whose `channel_type` is not in the
plan's `channel_entitlements`, with `errors.billing.channel_not_included` naming the channel. The option list
is `Channels::Capability`, so a plan cannot sell a channel this fork lacks. An empty list denies nothing, which
is what every pre-P11 plan has.

**15. Can Analytics, Tickets and the rest be entitled cleanly?**
Yes, with no new plumbing: each phase's capability is already a feature flag in the assignable set —
`reports` (P8), `lynomia_support_tickets` (P9), `lynomia_unified_identity` (P10), `lynomia_commerce`,
`lynomia_flow_builder` and 36 others, 41 in total out of the 74 entries in `config/features.yml`. Attaching one
to a plan is a Super Admin form field. (Note: `captain_tasks` appears in that generic list because it is a
non-premium flag upstream. P11 adds no AI capability and sells none; Captain stays inactive.)

---

## LIMITS (16–21)

**16. Which limits exist?**
Three, and only three: `agents` (seats), `inboxes`, `stores` (connected Commerce stores).
`BillingPlan::LIMIT_KEYS` is that list.

**17. Which are hard?**
All three. Each is refused at creation by a gate that holds a row lock: `AccountUser` validation, `Inbox`
validation, and `Commerce::StoreConnection#attach` inside its own transaction.

**18. Which are soft?**
None, in the sense of "exceed with a warning". But every limit is soft **backwards**: a downgrade never
removes what the account already has. All three rules are `on: :create`, so the existing resources survive and
the next create is refused (`05-usage-limits.md` §5).

**19. Which are metered?**
None. No plan in the catalogue charges per unit — `PRICING_TYPES` is `%w[flat per_agent]` — so no
usage-event table was built. `05-usage-limits.md` §6 states the decision, says what shape to add if a metered
price ever appears, and records that P8's message and conversation volumes are product analytics with a
retention window and are **not** safe to invoice from.

**20. Can concurrency bypass a hard limit?**
No. `Billing::ResourceLimit.exceeded` takes `account.lock!` **before** counting, inside the save's own
transaction, which is where a `validate … on: :create` already runs — the same idiom `AgentBuilder#perform`
and `DataImports::CreationService` use. The serialization was demonstrated at SQL level (T2 blocked 1,175 ms
with `FOR UPDATE` held; it did not wait without). Stated honestly: a threaded Ruby harness did **not**
reproduce the race, so no claim is made from it, and `reached?` is documented in the code as a pre-flight and
explicitly not a gate. The two-administrator case is `08-uat-runbook.md` §5.4.

**21. What counts as a seat?**
One `AccountUser` row — `account.account_users.count`, whatever the role or custom role. That is the canonical
count in `Billing::ResourceLimit::COUNTS`, and it is now also what the per-agent Stripe quantity uses; the
quantity previously counted `account.users` and the account billing API counted a third way.

---

## SUBSCRIPTIONS (22–27)

**22. What states exist?**
`inactive`, `trialing`, `active`, `past_due`, `canceled`. Stripe's wider vocabulary is mapped in
`Billing::SubscriptionSync::STATUS_MAP` with a `fetch` default of `inactive`, so an unknown future Stripe
status fails closed instead of crashing.

**23. How do trials work?**
`Billing::TrialStarter` gives an account its first subscription: `trialing` on the configured trial plan, or
`inactive` when no trial is configured. `BillingTrialUsage` records the administrator emails that have used
one, so `trial_once_per_user` can refuse a second. An account with no subscription and no trial configured is
**not** locked. A parallel first access used to answer `422` on an ordinary GET; both uniqueness failure
classes are now rescued and the winner's row returned.

**24. How does past_due work?**
A grace period, set once: `grace_period_ends_at || Billing::Settings.grace_period_days.days.from_now`, so a
repeated `past_due` webhook cannot keep extending it. `usable?` is true while the grace period lasts, false
after. The customer sees the deadline on the billing page.

**25. What happens on cancellation?**
`Billing::SubscriptionCanceller` cancels at Stripe, then the row goes `canceled` and the account is locked. A
Stripe error leaves everything unchanged and says so (*"Stripe error, nothing was changed"*).

**26. Does billing cancellation delete data?**
**No.** Nothing in the commercial path deletes, archives or disables a conversation, a message, an inbox, a
contact, a `contact_identity` or a store. A cancellation closes the dashboard and nothing else. The brief's
rule and P10's identity records meet here: historical customer identity is customer data, not a plan feature
to erase.

**27. Can inactive billing accidentally block inbound customer data?**
No, and this was verified by reading the controller hierarchies rather than assumed. `Billing::AccessGuard` is
included into `Api::V1::Accounts::BaseController` only; provider webhooks live under `Webhooks::` and
`Platform::`, which do not inherit from it. A locked account still receives and stores every WhatsApp,
Instagram, Facebook, SMS, email and widget message. **One adjacent hazard is documented rather than code:** an
operator who expresses non-payment as an *administrative suspension* (category `non_payment`) **does** cut off
inbound widget traffic with `401`. The operator rule — non-payment belongs to the billing lock — is in
`07-security-performance.md` §2, with the contrast step at `08-uat-runbook.md` §4.22.

---

## BILLING (28–35)

**28. Which provider was selected and why?**
Stripe, and it was already selected: the integration predates P11 (`01-discovery.md`). It is kept because
Checkout and the Customer Portal keep card data entirely off this installation, Prices are immutable (which
gives correct price-change semantics for free), and the SDK is already a dependency.

**29. Is provider logic isolated behind an adapter?**
It is **confined**, not abstracted, and the distinction is deliberate. Every Stripe API call is inside
`custom/app/services/billing/` or `custom/app/jobs/billing/` — this phase moved the last two out of
controllers (`Billing::Portal`, `Billing::PlanSync.archive_product!`). The one exception is
`Stripe::Webhook.construct_event` in the webhook controller, which is signature verification at the request
boundary and belongs there. There is no abstract adapter because one provider is integrated and an interface
designed for an unchosen second would be guesswork. The property an adapter would have been built for is
guaranteed by construction instead: **no authorization path calls the provider** —
`Billing::Entitlements`, `Billing::ResourceLimit` and `Billing::AccessGuard` contain no `Stripe::` reference.

**30. Is checkout server-authoritative?**
Yes. The request carries a `plan_id`; the server loads `BillingPlan.active.find(plan_id)` and uses that row's
`stripe_price_id`. A client cannot name an amount, a currency, an interval or a Stripe price. **And the
proration quote is now server-authoritative too**: `proration_date` decides how much of the period Stripe
prorates, so a browser choosing it was choosing its price. Only a timestamp this server could have minted is
accepted — inside `QUOTE_VALIDITY` (15 minutes) and never in the future.

**31. Are webhook signatures verified?**
Yes, and **fail-closed on a blank secret**, which is the SEC-7 closure. The endpoint used to pass
`stripe_webhook_secret.to_s` to the SDK, and `compute_signature` only requires a `String`, so an unset secret
became `""` and `OpenSSL::HMAC` signed with an empty key. A blank secret is now `401`.

**32. Are webhooks idempotent?**
Yes, by the unique index on `billing_webhook_events (provider, provider_event_id)`.
`BillingWebhookEvent.claim!` inserts before any work; a redelivery loses the insert and is acknowledged
without being processed. Concurrency-safe without a lock, because the database picks the winner.

**33. Are out-of-order events safe?**
Yes. `billing_subscriptions.last_event_at` holds the provider timestamp of the newest event applied, and
`SubscriptionSync#out_of_order?` drops anything older — the delayed `past_due` arriving after `active` case. A
null means "no ordering information yet", which accepts the event and records its timestamp, so the guard
becomes effective from the first event after deployment with no backfill. `stale_event?` separately refuses a
terminal event from an old subscription and never overwrites a manual grant.

**34. Can forged metadata select another tenant?**
No. Server-owned mappings are tried first (the stored subscription id, then the customer id this
installation's own checkout wrote) and metadata is the last resort and must name a real account. Reaching the
resolver at all now requires a signature only Stripe can produce. Asserted with a forged event naming a
foreign account.

**35. Is card data kept out of Lynomia?**
Yes. No PAN, CVV, expiry or payment-method token is ever received, stored, logged or serialized — Checkout
and the Portal are Stripe-hosted and the endpoints return a URL. The Stripe event payload is deliberately not
persisted. A repository-wide grep for `payment_method|cvv|card_number|last4|setup_intent|payment_intent|client_secret`
returns no billing hits.

---

## USAGE (36–40)

**36. What usage metrics are implemented?**
Three current-resource counts: seats, inboxes, connected stores. Reported as `{ used:, limit: }` per resource
by `Billing::ApiSerializer.usage`.

**37. What canonical data source supports each?**
`Billing::ResourceLimit::COUNTS` — `account.account_users.count`, `account.inboxes.count`,
`account.commerce_stores.connected.count`. One expression per resource, used by the gate, the account API, the
Super Admin page and the commerce endpoint alike, so the number shown is the number compared.

**38. Is any usage invented from transient logs?**
No. All three counts are derived from the live rows at the moment of the request. Nothing is read from a log,
a Redis key or a sampled rollup. P8's analytics rollups are explicitly **not** used as a billing quantity.

**39. Are currencies explicit?**
Yes. `billing_plans.currency` is validated against `CURRENCIES` (seven two-decimal currencies), prices are
stored in cents, and every API response that carries an amount carries its currency beside it.
`errors.billing.currency_locked` prevents changing an account's billing currency after billing is set up.

**40. Is unlike currency ever combined?**
No. The only aggregate in the product is the Platform API's MRR, and it is computed **per currency** into a
hash keyed by currency (`totals[plan.currency] += …`), never summed across them. Yearly plans are divided by
12 within their own currency.

---

## SUPER ADMIN (41–45)

**41. Can plans be managed?**
Yes, through the Administrate dashboard that already existed, and — within what it was granted — through the
Platform API: a plan `update`, `destroy` or `sync` is refused while any subscriber is outside the app's
permissibles, because a plan write changes what every tenant on it has. Creating a plan affects nobody and
stays open. The console surface is: price, currency, interval, pricing type,
`limits` (custom field), `features` (custom field), `channel_entitlements` (custom field added this phase,
sourced from `Channels::Capability`), active and position — plus the Stripe sync on save and the
subscriber count on the index and show pages.

**42. Can subscriptions be inspected safely?**
Yes. The subscription page shows the account, the plan, the plan's channels, usage against the **enforced**
limits, status with a usable/locked reading, source, all three date fields, and the Stripe customer and
subscription ids. Those ids identify and do not authenticate; no secret reaches the page, asserted by a spec
that matches the rendered HTML against `sk_test_|sk_live_|whsec_`.

**43. Can overrides be granted?**
Yes, from that same page: three forms (feature, limit, channel) whose option lists come from
`BillingPlan.assignable_features`, `BillingPlan::LIMIT_KEYS` and `Channels::Capability`. A reason is required,
an expiry is optional, the kind and the value are validated at the controller boundary, and a feature override
**writes the capability into the account's flags** so it takes effect rather than merely recording an
intention.

**44. Are overrides audited?**
Yes. `Billing::OverrideGrant` is the only writer and writes one `Custom::AuditLog` row per grant
(`billing.override_granted`) and per revoke (`billing.override_revoked`) against the account, carrying the
actor, the reason, the value and the expiry. A failed audit never undoes the grant. Plan entitlement edits are
audited too (`billing.plan_entitlements_changed`, with the affected subscriber count), and a plan sync records
what it switched off (`billing.capabilities_revoked_by_plan_sync`).

**45. Can internal and complimentary accounts exist?**
Yes, three ways, all pre-existing or audited: *Grant a plan manually* (`source: 'manual'`, `status: 'active'`,
optional end date, no Stripe subscription), *Extend trial* by any number of days, and an override for a single
capability or a single ceiling. A manually granted account is never touched by a Stripe webhook —
`stale_event?` refuses to overwrite a manual grant.

---

## ACCOUNT UI (46–48)

**46. Can customer admins see their plan and status?**
Yes, at Settings → Billing, which is now an in-product page. The off-product redirect to
`lynomia.com/admin/subscriptions/:id` that thirteen surfaces linked to was deleted; the route renders the
real subscription page behind the existing account-loaded guard, and the sidebar has one Billing entry instead
of two.

**47. Can they see limits and usage?**
Yes: a usage card reading `used / limit` per resource, where the limit is the **enforced** one (an operator's
override included). `null` renders as the localized **Unlimited** / **غير محدود**; `-1` is never produced and
`12 / -1` cannot appear. Every string on the page exists in English and Arabic.

**48. Can normal agents modify billing?**
No. `ensure_administrator` guards `checkout`, `portal`, `change_plan_preview` and `change_plan`, each
answering `403 "Only administrators can manage billing"`. Agents **can** read `show`, `plans` and
`entitlements` — stated plainly because it is a real property: reading your own account's plan carries no
secret and the dashboard shows it. One honest note: the dashboard route denies a custom-role user the page
while the API would serve the read, so the UI gate is not a description of the API's gate. Nothing writable is
reachable and nothing crosses an account boundary
(`spec/requests/billing/account_authorization_spec.rb`).

---

## OPERATIONS (49–51)

**49. Are billing failures visible in P9?**
Yes, three ways, all through the existing `Operations::SignalRecorder` with no new store: an entitlement sync
failure, an unknown provider customer, and a failed billing event — added to the `SOURCES`, `SIGNALS` and
`DETAIL_KEYS` allow-lists (a signal not declared there is silently dropped by validation, which a test
caught). `billing_webhook_events` keeps a durable row per failure with a partial index over the failures, and
**a locked account now shows as a warning in Operations → Accounts**, which it did not: the only
"cannot use the product" column read `accounts.status`, which a billing lock never touches.

**50. Are the diagnostics secret-safe?**
Yes. `BillingWebhookEvent#failed!` stores `error.class.name`, never the provider's message, because a Stripe
error body can quote the request it was given. The operations signal details are drawn from a `DETAIL_KEYS`
allow-list. The audit payloads are ids, names, numbers and an operator's typed reason.

**51. Can billing issues link to a P9 support case without spam?**
Yes, through the Operations Center's existing `open_case!` bridge, which an operator invokes per signal —
nothing opens a case automatically. And the deliberate non-signal: **a customer's failed card payment is not
recorded as an operational incident.** Dunning is Stripe's job, the customer sees it in the Portal, and an
operator paged on every declined card learns to ignore the feed.

---

## PERFORMANCE (52–56)

**52. Are the hot entitlement checks efficient?**
Yes, and measured. The access guard costs **1 query** on the first call in a request and **0** afterwards for a
usable subscription; 500 full cycles including a fresh `Account.find` took 0.358 s. The override lookup is a
three-column equality probe on a unique index: **0.074 ms**, 6 buffer hits, at 2,001 rows across 201 accounts.
`Billing::Entitlements.limit` is 1.34 ms per call through ActiveRecord and is not on an ordinary request's
path. The one extra cost — up to 3 `installation_configs` reads for `enforced?` — falls only on requests whose
subscription is not usable, which are being refused anyway, and is now paid once per subscription instance
rather than once per capability resolved.

**53. What is cached?**
**Nothing commercial, across requests.** No Redis key, no `Rails.cache`, no class-level state. Routing
`Billing::Settings` through `GlobalConfig`'s Redis cache was tried and rejected: a commercial setting whose
staleness decides whether an account is locked is not a feature flag, and its invalidation is an
`after_commit`, which does not fire under the suite's transactional fixtures — correct in production and
quietly stale in every spec. The narrower fix was taken instead:
`BillingSubscription#billing_enforced?` memoizes only the installation-wide setting, per instance, while
`usable?` stays live because the row can be written during a request.

**54. Are the cache keys tenant-safe?**
The question does not arise, which is the safest possible answer: there is no commercial cache key. The only
reuse is ActiveRecord's per-request association memoization on the `Current.account` object, which cannot
address another tenant.

**55. What indexes were added?**
Five, **all created with their own new table; not one index was added to a pre-existing table.** Two of the
five are not optimisations but the correctness mechanism for uniqueness and for idempotency, and would exist
at any scale. `07-security-performance.md` §8 lists them, and lists the four candidate indexes that were
measured or reasoned about and **declined**.

**56. What EXPLAIN evidence justified them?**
`07-security-performance.md` §7 carries the plans: the override lookup
(`Index Scan using uniq_billing_override_per_account_capability`, Index Cond on all three columns, 0.074 ms)
and the seat count (`Seq Scan`, 0.039 ms — the planner being right on a one-page table whose `account_id`
index exists for production scale). The declined WhatsApp expression index carries its own measurement
(0.086 ms vs 0.084 ms at 50 channels; 0.483 → 0.042 ms and 64 kB only at ~2,000).

---

## REGRESSION (57–60)

**57. Are the P8 tests green?** Yes — included in the 537-example P8/P9/P10 regression run, 0 failures.
**58. Are the P9 tests green?** Yes — same run. The P9 Operations Center gained a billing column, with three
new examples in its own spec, and its existing 14 examples still pass.
**59. Are the P10 tests green?** Yes — same run, including channel capability, connection state, contact
identity and the identity linker.
**60. Did P11 change their semantics?**
In four places, each deliberate and each with its spec updated rather than worked around:

| Change | Why |
|---|---|
| `Billing::ApiSerializer.usage` returns `{used:, limit:}` per resource instead of a bare count | the displayed ceiling must be the enforced ceiling (P11.28); one stale assertion in `billing_controller_spec` updated |
| `Custom::AuditLog` resolves a non-User actor's username | a `PlatformApp` actor raised and rolled the audit row back; 148 examples across every audit writer re-run green |
| `Operations::AccountHealth` rows carry a sixth component | a billing-locked account read as healthy |
| `Commerce::StoreConnection` reads the limit from `Billing::Entitlements` | so the store ceiling honours an override; the `connected`-only counting rule is unchanged and its five existing examples pass |

---

## ENTERPRISE (61–63)

**61. Is `enterprise/` absent?** Yes — `ls -d enterprise` reports no such directory.
**62. `extensions == ["custom"]`?** Yes — `ChatwootApp.extensions` is `["custom"]`.
**63. `enterprise? == false`?** Yes — `ChatwootApp.enterprise?` is `false`, `custom?` is `true`.
No Enterprise billing, SLA or audit code was copied. The only two mentions of "enterprise" in the new code are
comments explaining why something is avoided: the per-request Stripe api_key (so nothing inherits a global one
Enterprise code may set) and the exclusion of `premium` features from what a plan may sell.

---

## RELEASE (64–68)

**64. What automated tests passed?**
All five gates, run sequentially on a clean tree: `rubocop` 2894 files / 0 offences, `pnpm eslint` 0 errors
(478 pre-existing warnings), `npx vite build` ✓ 2m 15s, `pnpm test` 491 files / 5294 tests / 0 failures, and
`bundle exec rspec` **9609 examples, 0 failures, 70 pending** in 49m 42s. Gate 5's first run failed six
examples and both causes were this phase's own — they are fixed, and `P11_FINAL_COMPLETION_REPORT.md` §Z
records both runs, which gates ran on which tree, and why the three frontend gates are unaffected by the
commits after them.

**65. What simulated UAT passed?**
Everything a repository test can establish: forged and unauthenticated webhooks on seven endpoints, a forged
Stripe event naming a foreign account, webhook redelivery and out-of-order delivery, cross-account override
revocation, WhatsApp routing isolation with conflicting display numbers, the TikTok OAuth state boundary, the
seat/inbox/store ceilings and their refusal messages, channel entitlement refusal past the UI, the override
raising a ceiling and withholding a channel, a lapsed override falling back, a downgrade keeping existing
inboxes, the proration quote window, agent-versus-administrator billing writes, cross-account billing reads,
the Platform API's credential boundary, and that no rendered page or response carries a secret-shaped value.

**66. What real UAT remains?**
All of `08-uat-runbook.md` — a real Stripe test-mode round trip, dunning into the lock and back, the
two-administrator seat race on a real server, the trial once-per-user rule (which only the real signup flow
exercises), and the suspension-versus-lock contrast. Carried forward unchanged and **not** marked passed: P8's
production rollups, reports pilot, Analytics screens, Contact Timeline, real Meta status cases and
genuine-new-contact WhatsApp send; P9's Tickets, SLA and Operations UAT; P10's channel and provider UAT,
contact identity pilot, TikTok real-provider check and channel health validation.

**67. Is P11 safe to enter P-FINAL?**
Yes. No unclosed cross-tenant risk remains in anything this phase touched; commercial enforcement is inert
until an operator configures it; every new table is additive and reversible with a byte-identical
`db/schema.rb`; and the six known limitations are listed in the final report with what each needs. The
P-FINAL work P11 deliberately did not do — the licence audit, the provenance audit, the clean-code campaign
and the final commercial security audit — is untouched.

**68. Is the combined P8+P9+P10+P11 ready for a later controlled deployment after P-FINAL?**
Ready to enter P-FINAL, **not** ready to deploy, and the gap is human verification rather than code: the real
UAT debt in Q66 is the blocker, and it can only be discharged on a real server with real providers and a
Stripe test-mode account. The deployment order itself is written down (`06-rollout-compatibility.md` §3),
including the one trap — configuring Stripe before starting trials locks accounts that have no subscription
row — and its recovery. Production remains `b03ea43df6abf18cb9c4e5d6a9271ba040b689f4`; nothing in this phase
was deployed, no production configuration was changed, and no real billing provider was called.
