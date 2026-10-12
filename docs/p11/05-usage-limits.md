# P11 — Usage and limits

What this fork counts, what it refuses, and why the number on the screen is the number the server compares.

---

## 0. What is metered, and what deliberately is not

The brief's rule is *do not meter everything simply because it is countable*. Three resources are limited,
because three resources are sold:

| Resource | Plan key | Counted as | Where the ceiling is enforced |
|---|---|---|---|
| Team members (seats) | `agents` | `account.account_users.count` | `AccountUser` validation `on: :create` |
| Inboxes | `inboxes` | `account.inboxes.count` | `Inbox` validation `on: :create` |
| Commerce stores | `stores` | `account.commerce_stores.connected.count` | inside `Commerce::StoreConnection#attach` |

`BillingPlan::LIMIT_KEYS` (`custom/app/models/billing_plan.rb:9`) is that list and nothing else. Conversations,
messages, contacts, campaigns, flows, templates, labels, automation rules and API calls are all countable and
none of them is limited, because no plan in the catalogue charges for them and a ceiling nobody sells is a
support ticket waiting to happen.

**`nil` means unlimited.** Not `0`, not `-1`. `BillingPlan#limit_for` returns whatever the `limits` jsonb holds
for the key, which is `nil` when the Super Admin form left the field empty, and every reader treats `nil` as no
ceiling (`custom/app/models/billing/resource_limit.rb:43-44`).

---

## 1. One count per resource

`Billing::ResourceLimit::COUNTS` (`custom/app/models/billing/resource_limit.rb:28-32`) is the canonical
counting query per resource:

```ruby
COUNTS = {
  agents:  ->(account) { account.account_users.count },
  inboxes: ->(account) { account.inboxes.count },
  stores:  ->(account) { account.commerce_stores.connected.count }
}.freeze
```

Before P11 the count was written out again at each site that needed it: the two validators, the access guard,
the commerce connector, the account billing API and the Super Admin page. Two of those disagreed — the billing
API's `show` counted `account.users.count` while the seat gate counted `account.account_users.count`, and the
per-agent Stripe quantity counted a third way. Same cardinality today, but three independent expressions of one
commercial rule, any of which could drift. There is now one.

`stores` counts **connected** stores only: a disconnected store holds no slot. That was always
`Commerce::StoreConnection`'s rule and it is now stated once.

---

## 2. The gate, and the thing that is not the gate

Two methods, deliberately different jobs:

| | `exceeded(account, resource)` | `reached?(account, resource)` |
|---|---|---|
| Takes a row lock | **yes** — `account.lock!` | no |
| Where it runs | inside the caller's transaction | anywhere |
| What it is for | **refusing** a create | a clear early error, and showing state |
| Concurrency-safe | yes | no, and it says so |

```ruby
def exceeded(account, resource)
  limit = Billing::Entitlements.limit(account, resource)
  return nil if limit.nil?

  account.lock!                                        # serialize every concurrent create for this account
  current_count(account, resource) >= limit ? limit : nil
end
```

### Why the lock (P11.23)

The previous check was `current_count >= limit`, read outside any lock. Two requests arriving when the count is
`limit - 1` both read `limit - 1`, both pass, both commit, and the account ends up one over. There is no unique
index behind any of these three counts that could catch the loser, so the read-then-write is the whole gate and
it had to be serialized.

`account.lock!` is this repository's established idiom for exactly this shape — `AgentBuilder#perform` and
`DataImports::CreationService` both take it — and the validators run inside the save's own transaction, which
is where `validate ... on: :create` already executes. The second request blocks on the account row until the
first has committed, then counts the row the first inserted and is refused.

`Commerce::StoreConnection#attach` already held `@account.lock!` inside its own transaction before P11
(`custom/app/services/commerce/store_connection.rb:28`); re-acquiring the same row lock in the same
transaction is a no-op, so the store path keeps its single lock.

**How this was demonstrated.** A threaded Ruby harness did *not* reproduce the race reliably — the unlocked
version also passed — so the claim is not made from that harness. What was demonstrated is the mechanism
directly at SQL level: with `SELECT ... FOR UPDATE` held by T1, T2 blocked for 1,175 ms until T1 committed;
without it, T2 did not wait at all. The honest statement is therefore: *the serialization is proven, the
end-to-end race is argued from it*, which is also why `reached?` is labelled as not a gate rather than quietly
relied upon.

### Where `reached?` is used

One place: `Billing::AccessGuard#ensure_agent_limit` (`custom/app/controllers/billing/access_guard.rb:40-48`),
a pre-flight so an invitation is refused with a readable message before Chatwoot starts creating a user. It
runs outside any transaction, where a lock would be released immediately and so would be theatre. The real
refusal is the `AccountUser` validation a moment later.

---

## 3. The ceiling comes from the entitlement service, not the plan

`exceeded` and `reached?` both read `Billing::Entitlements.limit`, never `plan.limit_for` directly. So an
operator's override applies wherever a limit is enforced, not only where it is displayed. This is why
`Billing::PlanLimits` was deleted rather than kept alongside: it read
`account.billing_subscription.plan.limit_for` and therefore could not see an override, and its message was an
English sentence built in Ruby (`"Your plan allows up to #{limit} #{key}"`) that could not be translated and
read "up to 5 agents" in Arabic.

Messages now come from `config/locales/en.yml` under `errors.billing.limit_reached`, per resource with a
`generic` fallback, and `errors.billing.channel_not_included` for the channel rule.

---

## 4. Display honesty (P11.28)

`Billing::ApiSerializer.usage` returns, for every key in `LIMIT_KEYS`:

```json
{ "agents": { "used": 3, "limit": 5 }, "inboxes": { "used": 2, "limit": null }, "stores": { "used": 1, "limit": 9 } }
```

* `used` is `ResourceLimit.current_count` — the same query the gate runs.
* `limit` is `Billing::Entitlements.limit` — the same ceiling the gate compares, override included.
* `null` is unlimited. The subscription page renders it through `limitText`, which prints the localized
  **Unlimited** / **غير محدود**. `-1` is never produced and `12 / -1` cannot appear.

Three surfaces read that one shape: the account billing API (`show` and `entitlements`), the Super Admin
subscription page, and the commerce stores endpoint's `store_limit`. A plan card in the plans list still shows
that *plan's* own `limits`, which is a different fact — what you would buy, not what applies to you.

Asserted by `spec/controllers/api/v1/accounts/billing_controller_spec.rb` ("reports an operator's override as
the ceiling rather than the plan's", "ignores an override that has lapsed").

---

## 5. Downgrade: nothing is deleted (P11.5, P11.33)

Both inbox rules and the seat rule are `on: :create`. The policy, chosen once and applied everywhere:

> **A downgrade stops the next create. It never removes what the account already has.**

An account that drops to a plan allowing one inbox keeps the four it has; the fifth is refused. An account whose
new plan does not sell WhatsApp keeps its WhatsApp inbox and its history; it cannot connect another. No job
sweeps, no inbox is archived, no contact or `contact_identity` is touched — the P10 identity records are
customer data, not a plan feature, and nothing in the commercial path can reach them. `08-uat-runbook.md` has
the operator-facing wording for telling a customer what a downgrade will and will not do.

The alternative — deleting or disabling over-limit resources — was rejected outright: it destroys customer data
on a billing event, and a billing event is exactly the moment a customer is least willing to lose data.

Asserted by `spec/controllers/super_admin/billing_overrides_spec.rb` ("keeps inboxes the account already has
when the plan stops allowing them").

---

## 6. Period usage is deliberately not built (P11.20-P11.22)

The brief separates CURRENT RESOURCE COUNT from PERIOD USAGE and warns against inventing usage from transient
logs or building a giant usage-event table unless it is needed. Both apply here:

* **Current resource count** is what this fork has, and what it sells: seats, inboxes, stores. All three are
  derivable from the live tables at any instant, exactly, with one query each. No event table can be more
  correct than the rows themselves.
* **Period usage** — messages this month, conversations this month, API calls this month — is **not** stored,
  **not** aggregated and **not** displayed as a billing quantity, because `BillingPlan::PRICING_TYPES` is
  `%w[flat per_agent]`: no plan in this catalogue charges per message or per conversation. A `usage_events`
  table would be a table to write, index, migrate, retain and reconcile against Stripe, for revenue that does
  not exist.

If a metered price is ever added, the shape to add is a `usage_events` table keyed by
`(account_id, metric, period_start)` with the Stripe usage-record id for idempotency, written from the existing
message/conversation creation paths — not derived from logs, which are transient and sampled. That is written
down here so the next phase does not have to rediscover it, and it is **not** built now.

P8 already reports message and conversation volume as *product analytics* (`docs/p8/`). That is a different
question from a billing quantity and its numbers are not safe to invoice from: they are rollups with a
retention window.

---

## 7. Measurements

Measured on this branch against the test database with 2,001 override rows across 201 accounts, after
`ANALYZE`.

**Override lookup** — the one query the entitlement layer adds per capability resolved:

```
Limit  (cost=0.28..8.30 rows=1) (actual time=0.047..0.048 rows=1 loops=1)
  ->  Index Scan using uniq_billing_override_per_account_capability on billing_entitlement_overrides
        Index Cond: ((account_id = 1091) AND (kind = 1) AND ((name)::text = 'agents'::text))
        Filter: ((expires_at IS NULL) OR (expires_at >= now))
        Buffers: shared hit=6
Execution Time: 0.074 ms
```

The unique index created with the table serves it; `expires_at` is a filter on the single matched row, not a
scan. **No index was added for this**, and none is needed: the query is a three-column equality probe on a
unique index.

**Seat count:**

```
Aggregate  (actual time=0.017..0.018 rows=1 loops=1)
  ->  Seq Scan on account_users  Filter: (account_id = 1091)  Buffers: shared hit=1
Execution Time: 0.039 ms
```

A sequential scan here is the planner being right, not an index being missing:
`index_account_users_on_account_id` exists (`db/schema.rb:56`) and the table is one page in this database, so a
scan is cheaper than the index. At production cardinality the index is used.

**End-to-end, through ActiveRecord:**

| Call | 1,000 iterations | per call |
|---|---|---|
| `Billing::Entitlements.limit(account, :agents)` | 1.34 s wall | **1.34 ms** |
| `Billing::ResourceLimit.reached?(account, :agents)` | 2.44 s wall | **2.44 ms** |

`limit` is one query (the override probe; the subscription and plan associations are memoized on the account
object). `reached?` is that plus the count. Neither is on the hot path of an ordinary request: `limit` runs when
something is created, and `reached?` runs only on the agents-create pre-flight. `07-security-performance.md`
records what the commercial path costs on *every* account-scoped request.

**No provider call on an authorization path.** `Billing::Entitlements`, `Billing::ResourceLimit` and
`Billing::AccessGuard` contain no `Stripe::` reference; the only Stripe calls are in checkout, the portal, a
plan change and the webhook handler, all of which are explicit customer or operator actions.

---

## 8. What a limit refusal looks like

| Surface | What the caller gets |
|---|---|
| Invite an agent over the seat limit | `422`, `{ "error": "plan_limit_reached", "message": "Your plan allows up to 5 team members. Upgrade your plan to invite more." }` |
| Create an inbox over the inbox limit | `422` with the model's error: `errors.billing.limit_reached.inboxes` |
| Create an inbox of a channel the plan does not sell | `422` with `errors.billing.channel_not_included`, naming the channel |
| Connect a store over the store limit | `422`, `{ "error": { "code": "STORE_LIMIT_REACHED" } }`, rendered by the dashboard from `commerce.json` in English and Arabic |
| Any request while the subscription is unusable | `402 payment_required`, `{ "error": "subscription_required" }` — a different state, see `06-rollout-compatibility.md` |

Every message is a locale key. None of them names a price, a plan id or an internal limit key.
