# Odoo Accounting Integration — Repository Discovery

What this repository already does about money, who owns which record, and what the Odoo integration may
therefore reuse rather than rebuild. Read before changing anything (the owner's brief, §1).

Baseline: `lynomia-custom` @ `8f0e5c6b`. Rails 7.2.3.2, Ruby 3.4.4, PostgreSQL, Sidekiq.

---

## 1. The commerce boundary — the single most important answer

Two completely different kinds of money pass through this installation, and only one of them is Lynomia's.

### Lynomia's OWN SaaS revenue — exported to Odoo

| Table | What it holds |
|---|---|
| `billing_plans` | The plan catalogue the platform owner sells (price, currency, interval, Stripe price/product ids) |
| `billing_subscriptions` | One row per Lynomia `Account`; the tenant's subscription to Lynomia (unique index on `account_id`) |
| `billing_webhook_events` | Every Stripe event this installation accepted, claimed against a unique index |
| `billing_entitlement_overrides` | Super-Admin grants on top of a plan |
| `billing_trial_usages` | Trial-once-per-email ledger |

The Stripe customer behind a `billing_subscriptions` row **is the Lynomia tenant**. Its invoices are the
platform owner's sales invoices. These are the only records the Odoo integration may export.

### MERCHANT revenue — must NEVER reach the platform owner's Odoo

| Table | What it holds | Money column |
|---|---|---|
| `commerce_stores` | A tenant's connected WooCommerce / Salla / Zid / Shopify store | — |
| `commerce_carts` | A cart in **the tenant's own shop** | `visible_total`, `currency` |
| `commerce_contact_metrics` | A tenant's customer's lifetime spend | `spend` (jsonb), `orders_count` |
| `commerce_customer_links` | A tenant's shopper identity | — |

A `commerce_carts.visible_total` is a sale by **Lynomia's customer to their customer**. Lynomia is not a party
to it; it is not Lynomia's revenue, not Lynomia's VAT, and posting it into the platform owner's ledger would be
a material misstatement of that ledger. The same is true of `commerce_contact_metrics.spend`.

`site_quote_requests` is a sales lead, not a transaction, and is also out of scope.

**Rule:** the integration reads `billing_*` and Stripe. It has no reason to read any `commerce_*` table, and a
test asserts that it does not.

---

## 2. What Stripe identifiers are persisted today

`billing_subscriptions` stores exactly four Stripe identifiers:

```
stripe_customer_id      stripe_subscription_id (unique)     stripe_price_id     stripe_schedule_id
```

**No Stripe invoice id, charge id, payment-intent id, refund id or balance-transaction id is persisted
anywhere in this repository today.** `billing_webhook_events` stores the event id, type and a status — not the
payload.

Three consequences for the design:

1. The integration cannot reconstruct invoice history from local tables. Invoice, payment and refund facts must
   come from the **Stripe API** (or from a webhook body, at the moment it arrives). `Billing::Settings.stripe_secret_key`
   already exists and `Billing::Checkout` already passes it as `{ api_key: … }`, so the credential path is in place.
2. Every sync event row must therefore carry the Stripe object id it is about (`in_…`, `ch_…`, `re_…`,
   `pi_…`), so a worker can re-fetch the authoritative object instead of trusting a cached copy.
3. Those ids are new state. They live on the integration's own mapping tables — nothing in `billing_*` is
   modified, which keeps the change additive and reversible.

---

## 3. Stripe is the payment authority; subscription status is not evidence of payment

`Billing::SubscriptionSync::STATUS_MAP` maps Stripe `trialing` → our **`active`**, with the comment
*"a real subscription with a card, first charge later"*. And `BillingSubscription::STATUSES` includes a
`trialing` of its own, used by `Billing::AdminActions#extend_trial` and `Billing::TrialStarter` for a
**local** trial that Stripe has never heard of. `source` is `stripe` or `manual`;
`Billing::AdminActions#grant_plan` writes `source: 'manual', status: 'active'` with
`stripe_subscription_id: nil`.

So the row `status = 'active'` can mean any of: paying, in a Stripe trial, or granted free by the platform
owner. **No subscription status, on its own, is evidence that money moved.** Revenue entries derive from a real
Stripe invoice or charge, and from nothing else. A manual grant and a trial produce no accounting document.

---

## 4. The Stripe webhook path, and where to extend it

```
POST /billing/webhooks/stripe
  → Billing::WebhooksController#stripe
      head :unauthorized           if the webhook secret is blank     (fails closed)
      Stripe::Webhook.construct_event(body, Stripe-Signature, secret)
      head :bad_request            on JSON::ParserError / SignatureVerificationError
  → Billing::WebhookHandler#perform
      BillingWebhookEvent.claim!   ← the unique index IS the dedup; a redelivery returns early
      #process → #dispatch
          'checkout.session.completed'      → Stripe::Subscription.retrieve → SubscriptionSync
          'customer.subscription.{created,updated,deleted}' → SubscriptionSync
      receipt.succeeded!(subscription.account)  when dispatch returned truthy
      receipt.ignored!(reason)                  when it returned nil
      rescue → receipt.failed!(e); Billing::OperationsSignal; re-raise  ← the raise makes Stripe retry
```

Facts that constrain the extension:

- `handled_type?` and `dispatch` are two parallel `case`/`include?` lists. A new event type must be added to
  **both**, or it is accepted, recorded as `ignored` with reason *"event type not handled"*, and silently dropped.
- `#process` calls `receipt.succeeded!(subscription.account)` on whatever `dispatch` returns. Anything a new
  branch returns must respond to `#account` (and `BillingWebhookEvent#succeeded!` tolerates a nil account).
- The handler is **synchronous inside the request**. The brief forbids synchronous Odoo calls here, so an
  `invoice.*` or `charge.*` branch must do nothing but **enqueue** — which also keeps the webhook's p99 off
  Odoo's availability.
- The signature check means reaching the handler at all requires a signature only Stripe can produce. The event
  body is still not trusted for authorization: `Billing::SubscriptionSync#account_id` prefers server-owned
  mappings (`stripe_subscription_id`, then `stripe_customer_id`) over the body's `metadata`. The Odoo mapping
  must resolve the account the same way.

---

## 5. Secret storage — two precedents, one of them correct for this job

**`Billing::Settings`** (`custom/app/services/billing/settings.rb`) keeps Stripe keys in `installation_configs`
rows marked `locked: true`, with:

- `update!` — `next if definition[:type] == :secret && raw.blank?` → **a blank secret field preserves the stored value**;
- `masked(key)` — `SHORT_VALUE_MASK = '••••••••'` below `REVEALED_CHARACTERS * 2`, else `"#{first(7)}...#{last(4)}"`,
  with a fixed bullet count so a short value does not disclose its length;
- `get` — a direct `InstallationConfig.find_by`, deliberately not through GlobalConfig's Redis cache.

The blank-preserves and masking rules are exactly what the brief asks for and are reused verbatim. But the
**value itself is not encrypted at rest** — `locked` only hides the row from the generic Installation Configs
page.

**`Commerce::Store`** (`custom/app/models/commerce/store.rb`) is the encrypted precedent:

```ruby
serialize :credentials, coder: JSON
encrypts :credentials
validate :credentials_encryptable, if: -> { credentials.present? }
def serializable_hash(options = nil) = super.except('credentials')
```

with `credentials_encryptable` adding `errors.add(:credentials, :encryption_not_configured) unless Chatwoot.encryption_configured?`
— so **the record cannot be saved at all without encryption keys**.

Active Record encryption *is* configured (`config/application.rb:75-85`), gated on
`ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` being present, and `Chatwoot.encryption_configured?`
(`config/application.rb:101`) requires all three keys. `spec/support/commerce_encryption.rb` provides the
`'with commerce encryption'` shared context for specs.

**Decision:** Odoo credentials follow `Commerce::Store`, not `Billing::Settings` — encrypted at rest, refusing
to persist without keys, excluded from `serializable_hash` — while reusing `Billing::Settings`' masking and
blank-preserves-secret rules for the form. The brief requires encryption; a `locked` config row is not encryption.

`spec/models/application_record_external_credentials_encryption_spec.rb` is the repository's enumerated
at-rest proof for every external credential. The Odoo credential is added to it.

---

## 6. Super Admin surface

Two kinds of page coexist:

- **Administrate resources** (`accounts`, `users`, `billing_plans`, `site_pages`, …) — dashboards + generated views.
- **Hand-rolled operator consoles** — `SuperAdmin::OperationsController`, `SuperAdmin::PlatformSupportController`,
  `SuperAdmin::MarketingSettingsController`. Server-rendered ERB inside the Administrate shell, Tailwind, no Vue
  island. One controller, many actions, one tab per action, `_tabs.html.erb` partial marking the active tab with
  `current_page?`.

**A trap that must not be stepped in.** `app/views/super_admin/application/_navigation.html.erb` enumerates every
controller under `super_admin/` from the route table and asks each for an index route and a dashboard. A
controller with neither **raises, and the raise breaks the nav partial on every Super Admin page** — not just its
own. Every hand-rolled controller is therefore excluded by name in that partial's `next if [...].include? resource.resource`
list. The Odoo controller must be added to that list in the same commit as its route.

Also: a nav item's icon id must exist as a `<symbol>` in `app/views/super_admin/application/_icons.html.erb`, or
the item renders a blank square.

**Authorization** is `authenticate_super_admin!`, applied by `SuperAdmin::ApplicationController` to every action.
That is the whole boundary on this surface; no page invents a second one. CSRF comes from `ApplicationController`'s
`protect_from_forgery`, so every write is a POST/PATCH form carrying the Rails token. Request specs assert a
tenant administrator and a tenant agent both bounce off it.

Routes live in `config/routes/<area>.rb`, drawn from `config/routes.rb` with `draw :area`.

---

## 7. Background work

`config/sidekiq.yml` declares, in priority order: `critical, high, medium, default, mailers,
action_mailbox_routing, low, scheduled_jobs, deferred, purgable, housekeeping, …`. Global `:max_retries: 3`.

The relevant precedent is **`Commerce::ActionJob`**:

```ruby
class Commerce::ActionJob < ApplicationJob
  queue_as :high
  sidekiq_options retry: false
```

> *"Never retried: a write is sent at most once, and a lost answer is reconciled by reading the store, not by
> sending again."*

That is precisely the semantics an accounting write needs, and it is adopted here: **an Odoo write is attempted at most
once per attempt record, and a lost answer is recovered by searching Odoo for our own stamped source identifier
— never by creating a second document.** `Commerce::HttpClient#send_once` already distinguishes `not_sent`
(DNS failure, refused connection, connect timeout — the server provably never saw it) from `unknown_outcome`
(it may have acted), which is the same distinction the Odoo reconciler needs.

Recurring sweeps exist as `*_sweep_job.rb` (`Support::SlaSweepJob`, `Commerce::ActionSweepJob`,
`PlatformSupport::SlaSweepJob`).

---

## 8. Observability and audit

**`Operations::SignalRecorder`** is the only writer of an `Operations::Signal`. It never raises into its caller,
dedupes on the open identity, bounds `reason` to 500 characters, scrubs credentials structurally (URL userinfo
and `key=value` pairs whose key names a credential), and accepts only allow-listed `detail` keys holding
scalars. `Operations::Signal::SOURCES`, `::SIGNALS` and `::SUBJECT_TYPES` are allow-lists — a value nobody
declared is dropped, so a new source must be added explicitly.

**`Custom::AuditLog`** is the `audited` gem's audit class, extended to capture the actor's display name at write
time and to scrub secrets from `audited_changes` via `AuditTrail::Secrets`. `Billing::OverrideGrant` is the
pattern for an audited Super-Admin write: one service that is the **only** writer, taking an explicit
`actor:` (because the `audited` Sweeper resolves actors through Devise's `:user` scope while this surface
authenticates under `:super_admin`, so an inferred actor would be nil or the wrong person).

---

## 9. Outbound HTTP

`Commerce::HttpClient` is the house client for third-party JSON APIs and the model to follow:

- every request through **`SsrfFilter`** (gem `ssrf_filter ~> 1.5`): the host is resolved, private / loopback /
  link-local / metadata addresses are refused, and the connection is pinned to the checked IP so DNS cannot be
  rebound between check and connect;
- redirects **never** followed — a 3xx is an error, so nothing can bounce us to another host;
- bounded: connect 3 s, read 8 s, whole body 10 s and 5 MB;
- one retry, **GET only**, for a dropped connection or 502/503/504; writes are never retried;
- errors are codes, never provider prose; credentials, query strings and response bodies are never logged.

**`xmlrpc` is not available in this bundle** — it is absent from `Gemfile.lock` and `require 'xmlrpc/client'`
fails. This is not a preference but a constraint, and it happens to point at the better design: Odoo's
`/jsonrpc` endpoint speaks plain JSON over HTTP on every supported version, and Odoo 19 adds a newer JSON API.
The adapter is therefore **JSON-only**, built on the same `SsrfFilter` + `Net::HTTP` + bounded-read machinery as
`Commerce::HttpClient`, with no new gem and no hand-rolled XML.

---

## 10. Conventions that bind this change

- **Layout.** Fork-specific code lives in `custom/app/**` (in `eager_load_paths`, so `zeitwerk:check` covers it)
  with views in `custom/app/views`. Upstream Chatwoot's Enterprise overlay (`enterprise/`) is not vendored in
  this fork at all, and this feature has no OSS counterpart to override, so it is Lynomia-only under `custom/`.
- **Migrations.** Recent Lynomia tables went to `db/migrate` (`create_platform_support_*`,
  `create_commerce_store_health`), even though `custom/db/migrate` is also a migration path. New tables follow
  `db/migrate`. Style: timestamped `YYYYMMDDHHMMSS_verb_noun.rb`, `ActiveRecord::Migration[7.2]`, `change`-based
  and additive so it inverts mechanically, with a comment saying what each column is for and why an index is a
  guarantee rather than an optimisation.
- **Specs.** `spec/models`, `spec/services`, `spec/jobs`, `spec/requests`, plus `spec/custom/requests` for some
  Lynomia request specs. Factories in `spec/factories` (`spec/factories/commerce/` for namespaced ones).
  `let` over helper methods; `with_modified_env` over stubbing `ENV`.
- **CI.** `.github/workflows/run_foss_spec.yml`: `lint-backend` (rubocop), `lint-frontend` (eslint),
  `frontend-tests`, 16 `backend-tests` shards, `security-scan`, and a node-0-only step running
  `bundle exec rake -T | grep -q '^rake documentation:content'` and `bundle exec rake zeitwerk:check`.
  A PR title must be Conventional Commits.
  **`security-scan` was red on the base branch while this work started** — `ruby_llm` and `rack-proxy` carried
  open advisories that `.bundler-audit.yml` deliberately did not suppress. Both were fixed on `lynomia-custom`
  (`ruby_llm` 1.15.0 -> 2.0.0, `rack-proxy` 0.7.7 -> 2.0.1; see `docs/pre-deploy/06-security-remediation.md`),
  and after merging that base in, `bundle exec bundle-audit check` reports no vulnerabilities, so the gate is
  expected to pass.
  **Shard hazard:** shards are assigned round-robin over `find spec -name '*_spec.rb' | sort`, so adding any
  spec file moves every later file into a different shard. One latent id collision this could have surfaced --
  `spec/services/operations/attention_queue_spec.rb` searching for `'535'`, which also matched
  `account_id: 535` -- was fixed on the base before this branch added specs; the search term is now `'5.7.8'`.
- **Rubocop** 150-character lines. **No bare strings** in user-facing templates — i18n under
  `config/locales/en.yml` (`super_admin:` at line 819) and `en.json` for the frontend; only English is edited
  by hand, the rest comes through Crowdin.

---

## 11. What this integration will NOT do

- It will not implement a second billing, checkout, customer-subscription or payment processor. Stripe remains
  the payment and subscription authority; Odoo is the accounting destination.
- It will not change any existing `billing_*` column, plan price, Stripe subscription id, subscription status or
  customer permission.
- It will not touch the marketing website, pricing page, public auth, dashboard billing UI, subscription
  checkout or the mobile app.
- It will not export merchant commerce data (§1).
- It will not run a historical import automatically on deploy.
