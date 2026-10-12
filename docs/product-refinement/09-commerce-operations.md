# Commerce operations: per-store operational truth

Product Refinement, workstream F/G §9.7. Branch `claude/product-refinement`.

## 1. The problem this solves

Before this change the only durable answer to "is this store working?" was `commerce_stores.status`
(`active` / `disabled` / `needs_reauth` / `disconnected`).

That column records what an **administrator or a rejected token last decided**. It says nothing about whether
the provider has answered a request this week. So two very different stores read identically:

| | `status` | reality |
|---|---|---|
| Store A | `active` | Shopify answered a panel read 40 seconds ago |
| Store B | `active` | every request has timed out since Tuesday; nobody has noticed |

An operator looking at the Operations Center could not tell them apart, and the installation-wide
`Operations::ComputedSignals#commerce` area could not either: it counted `needs_reauth` **and**
`disconnected` stores as critical, which meant one merchant tidily disconnecting their store left the
console red forever.

## 2. What was already there, and what it could not answer

The brief required inspecting the existing systems first. Findings:

| source | what it holds | why it is not enough |
|---|---|---|
| `Commerce::Metrics` | an `ActiveSupport::Notifications` event plus one structured log line per provider request | **not durable.** No metrics backend on this installation, so the only trace is a log line nobody can query from a page |
| `commerce_stores.metadata` | `verified_at`, `token_refreshed_at`, `refresh_failed_at`, `write_access`, `realtime.status`, `zid_webhooks.registered_at` | real durable facts about **authorization and setup**, not about whether the provider is answering now. `verified_at` is reused by this work rather than duplicated |
| `Operations::Signal` | the incident lifecycle: one row per distinct open problem, with severity, occurrences, operator handling | the right home for an incident. But **nothing wrote `source: 'commerce_store'`** — the source and the `Commerce::Store` subject type were declared and unused |
| `Commerce::Backoff` | per-store rate-limit backoff in Redis | Redis, no TTL guarantees for reading historically, and only about rate limits |
| `Commerce::AuditTrail` | connect / disconnect / rotate / needs_reauth events | the record of record for *changes*, not a current-state answer, and read per store |

So two gaps: **no current-state snapshot per store**, and **no incident row when a store's authorization
dies**.

## 3. What was built

### 3.1 `commerce_store_health` — a snapshot, not a log

One row per store, overwritten in place. Migration `20261012100000`.

```
commerce_store_id          unique, FK → commerce_stores, ON DELETE CASCADE
last_api_success_at
last_api_failure_at
last_error_code            varchar(40)   a Commerce::Error::CODES value
last_error_reason          varchar(60)   one of Lynomia's own classified reasons
last_error_at
consecutive_failures       integer, default 0
last_webhook_received_at
last_webhook_processed_at
created_at / updated_at
```

**Why a snapshot.** The operator question is a *current* one. A row per provider request would be an
unbounded request log inside the product's own database — explicitly out of scope per the brief — and the
incident **history** already has a home in `Operations::Signal` plus its event timeline.

**Fields deliberately NOT added**, with reasons:

- `last_webhook_failure_at` — a webhook that fails to process is a Sidekiq retry or a dead job, and Sidekiq
  owns that record (§9.8 reuses it rather than recreating it). The gap between
  `last_webhook_received_at` and `last_webhook_processed_at` already exposes a stuck pipeline per store, and
  every provider now stamps receipt *before* applying so the gap is real for all four.
- `last_health_check_at` — `Commerce::StoreConnection` already writes `metadata['verified_at']` on every
  connect, rotate and enable. `Operations::CommerceOperations` reads it from there. Copying it into a new
  column would create two facts that can disagree.
- a status mirror — `commerce_stores.status` is already the durable answer to "active / disabled /
  needs_reauth / disconnected". The page reads it directly.

### 3.2 `Commerce::StoreHealthRecorder` — the only writer

The write strategy and the no-secrets rule live in one place, exactly as `Operations::SignalRecorder` does.

**The eight rules are enforced structurally, not by discipline.** The only failure input the recorder accepts
is a `Commerce::Error`:

- its `code` is validated against `Commerce::Error::CODES` **at construction**, so it cannot be a provider's
  prose;
- its `reason` is one of Lynomia's own lower-case identifiers, and the recorder stores it only if it matches
  `/\A\w{1,60}\z/` — anything else is dropped.

There is no parameter on any method through which a payload, a customer, a token, an `Authorization` header,
a webhook body, a provider response body or an exception's text could travel. `spec/services/commerce/store_health_recorder_spec.rb`
asserts the reason-dropping case directly with a credential-shaped string.

**Write amplification.** `SUCCESS_THROTTLE` (default 5 minutes, `COMMERCE_HEALTH_SUCCESS_THROTTLE_MINUTES`):

| event | written |
|---|---|
| provider answered, last success inside the window, no failures | **nothing** — the SQL predicate matches 0 rows |
| provider answered, last success older than the window | one UPDATE |
| provider answered while `consecutive_failures > 0` | one UPDATE, **immediately** — a recovery must be visible at once |
| provider failed | one UPDATE, immediately, `consecutive_failures = consecutive_failures + 1` in SQL so no race loses the count |
| authenticated webhook received / applied | throttled the same way |

So a store answering a request every second writes at most one row per five minutes.

Recording never raises: these calls sit inside the conversation panel's provider reads and inside the webhook
path that keeps a merchant's orders current.

### 3.3 Where it is called from

**Provider API outcomes: `Commerce::HttpClient`.** This is the single place every provider request passes
through — a panel read, an order action, a webhook subscription, a token refresh are all one of its six public
calls. It takes an optional `store:`; the four data-plane client constructions pass it
(`Providers::Woocommerce#http`, `Providers::Salla#http`, `Zid::Oauth.api`, `Shopify::Graphql`). The OAuth
exchanges that run **before a store exists** pass none, and nothing is recorded then rather than attributed to
a guess.

Two recording points inside the class, because there are two answer shapes:

- `#observed` wraps `get_json`, `post_json` and `delete`, which raise a classified `Commerce::Error` on
  anything but a 2xx;
- `#send_once` (behind `post_form`, `post_json_status`, `write_json`) answers `[status, body]` for **any**
  status, because an OAuth refusal is a 400 whose body says why and only the caller can read it. The HTTP
  status is classified here with the same `error_for` the rest of the class uses, so a 400 arriving is not
  recorded as the store working.

**Webhooks: only past the authentication boundary.** A rejected unauthenticated delivery says nothing about a
store's health and anyone on the internet could send one, so it never moves a timestamp.

| provider | receipt recorded | why there |
|---|---|---|
| WooCommerce | `Webhooks::WoocommerceController`, after `Webhook.authentic?` | the signature is checked against **this store's** secret and the store is in the path, so the store is known at the boundary. Recorded for any topic, including ones Lynomia does not subscribe to: the signature still proves the provider is talking |
| Zid | `Webhooks::ZidController`, after the Basic Auth check | same — per-store credentials, store in the path |
| Shopify | `Commerce::Shopify::WebhookJob`, after the store resolves | the app-level HMAC is checked at the request, but the delivery names its shop in the **signed body**, so the job is the first point that knows which store is healthy |
| Salla | `Commerce::Salla::WebhookJob#event_store` | same: the signature is app-level, the merchant is named in the signed body |

Processing (`webhook_processed`) is stamped after the handler has applied the event, in all four jobs.

### 3.4 The incident: `reauthorization_required`

A store losing its authorization is an operational problem a human must act on. It is now recorded as an
`Operations::Signal` (`source: commerce_store`, subject `Commerce::Store`, severity critical) — which means it
enters the attention queue, can be acknowledged, suppressed and resumed, gets an incident timeline, and can be
turned into a support case. All of that machinery already existed; commerce just never reached it.

Recorded from `Commerce::Store`'s `after_update_commit` on a status change, **not** from the services that flip
the status, because there are six of those — `StoreConnection#attach`, `#rotate_credentials`, `#enable`,
`#credentials_rejected`, `#disconnect` and `TokenManager#needs_reauth!` — and the model is the one place every
one of them passes through. A seventh writer added later is covered without anybody remembering to be.

Resolved when the store works again, **and when it is disconnected**: a merchant who disconnected their store
did exactly what the product offers them and did not leave an incident behind.

### 3.5 Honest states

`Commerce::StoreHealth#api_state`:

| state | meaning | maps to |
|---|---|---|
| `failing` | the last outcome was a failure; `consecutive_failures` says how many | warning, or critical at 3+ |
| `healthy` | a request succeeded inside `STALE_AFTER` (default 24 h) | healthy |
| `stale` | a request succeeded, but not recently enough to be the current answer | **unknown** |
| `unknown` | nothing has ever been recorded for this store | **unknown** |

`stale` maps to `unknown` on purpose. A store is only called when something asks it something, so a quiet
store legitimately goes a long time with nothing to report — that is the limit of what we know, not a fault,
and calling it green would be the one thing this console must never do.

`#webhook_state` is `unsupported` / `none` / `received` / `processed`, and `unsupported` is read from the
provider contract itself (`Commerce::Providers::Base.supports_realtime?`) rather than from a second list that
could disagree with it. **On this installation all four providers answer `true`**, so `unsupported` is what a
provider added *without* webhooks would read — never a dressed-up "we have no signal". A provider with
webhooks and no delivery yet reads `none`, never unhealthy.

## 4. The operator surface

`/super_admin/operations/commerce` — `Operations::CommerceOperations`.

Five counts in **one** `SELECT` with `COUNT(*) FILTER (WHERE …)` clauses, so the tab labels cannot disagree
with the lists under them: connected stores, need reconnecting, provider failing, no signal yet, last success
stale. Four views: needs action (default), provider failing, no signal yet, all stores.

`needs_action` is deliberately **only** a lost authorization or a refusing provider. A store nobody has called
yet is a gap in our knowledge, not a job, and putting it in the work list is how an operator learns to ignore
the work list.

Nothing on the page calls a provider: an operator diagnosing an outage must not be made to wait on the thing
that is down, and a page that probed each store would take as long as the slowest broken store's timeout.
Query count is constant in the number of stores, asserted by a spec that grows the installation between two
runs.

The same facts appear per store on the Account 360 page.

## 5. Compatibility with the frozen Platform Support architecture

Nothing here touches `docs/platform-support/`. The two points of contact:

- `Operations::Signal` gains a real commerce writer, which is what the Platform Support case bridge already
  consumes — no contract change.
- `Operations::AccountSnapshot#support` is documented as the seam a Platform Support ticket count arrives at.
  Not implemented: that phase stays frozen at discovery.

## 6. Verification

- `spec/services/commerce/store_health_recorder_spec.rb` — 14 examples: throttle, immediate failure,
  immediate recovery, consecutive counting, classified code and reason only, a credential-shaped reason
  dropped, webhook receipt vs applied, nil and unsaved stores, never raises.
- `spec/models/commerce/store_health_spec.rb` — 8 examples: the four api states, the escalation, the two
  honest webhook states.
- `spec/services/commerce/http_client_spec.rb` — 5 new examples: success, a 401 recorded as `AUTH_INVALID`
  with no body, a non-2xx single-shot answer not counted as a success, a transport failure, and nothing
  recorded for a client with no store.
- `spec/models/commerce/store_signal_spec.rb` — 5 examples, driven through the real `StoreConnection`
  methods: opened, resolved on recovery, resolved on disconnect, not opened for an unrelated status change,
  not opened for a rename.
- `spec/services/operations/commerce_operations_spec.rb` — 9 examples including the one-statement summary
  matching the lists and a constant query count.
- `spec/controllers/super_admin/operations_control_center_spec.rb` — the commerce page is in the full
  authorization boundary (unauthenticated, tenant administrator, tenant agent) and has a no-credential
  assertion.
