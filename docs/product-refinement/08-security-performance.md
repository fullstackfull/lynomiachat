# Security and performance of the operator surface

Product Refinement, workstreams F and G. Branch `claude/product-refinement`.

This document covers the operator surface built in this phase. The phase-wide security, performance and
integration QA is workstream H and is recorded separately.

## 1. Authorization

### 1.1 The boundary

Every Operations endpoint is Super Admin only, through the `authenticate_super_admin!` that
`SuperAdmin::ApplicationController` applies to every action. **There is no Pundit layer on the Super Admin
surface at all** — not in this fork, not in upstream Chatwoot — and this phase did not invent one, because a
policy layer that exists on five controllers out of forty is worse than none: it reads as a guarantee and is
not one.

What this phase did instead was keep the surface almost entirely read-only, and route the four mutations
through one audited service.

Asserted in full by `spec/controllers/super_admin/operations_control_center_spec.rb` for every endpoint, reads
and mutations alike — unauthenticated (redirected to `super_admin/sign_in`), tenant **administrator**, tenant
**agent**, then Super Admin. The endpoint list is a `let` in that spec, so a new endpoint cannot be added
without appearing in the boundary tests.

### 1.2 No account scoping, deliberately

Signals and accounts are looked up by id with no account scoping. That is correct on this surface: Operations
is installation-wide and an operator works across accounts. The boundary that matters is
`authenticate_super_admin!`, and the spec proves a tenant administrator and a tenant agent both bounce off it.

### 1.3 Mutations are POSTs

`acknowledge_signal`, `suppress_signal`, `resume_signal` and `open_case` are POSTs, so none can be triggered by
a link somebody pastes into a chat. The routes carry no guard of their own, which is the same arrangement as
every other page on this surface.

## 2. Audit: why the actor is explicit

**The `audited` gem cannot be trusted to attribute an action on this surface.** Its Sweeper resolves the
current actor through Devise's `current_user`, which is the `:user` scope. A Super Admin authenticates under
the `:super_admin` scope. Warden keys both into one cookie, so a Super Admin who is *also* signed in as a
tenant user in the same browser has a live `:user` session — and an inferred actor would be either `nil` or
**the wrong person**.

So `Operations::SignalLifecycle` takes an explicit actor and `raise`s `InvalidAction` without one. The
controller passes `current_super_admin` by name. Every operator decision writes:

- an `Operations::SignalEvent` row with `actor_id` and `actor_name`, and
- a `Custom::AuditLog` row with `user: @actor`.

Neither is best-effort. Unlike `Billing::OverrideGrant` — where a failed audit must not undo a customer's
access — nothing depends on an acknowledgement having happened, so if it cannot be recorded, it did not happen.

`Custom::AuditLog` rows written here carry **no `associated`**, which files them installation-wide.
`Custom::AuditLog.for_account` serves account-associated rows to that account's own administrators, so
associating them would publish Lynomia's internal operator activity to the customer.

The co-resident-session case is tested directly: a request made while both a Super Admin session and a tenant
user session exist attributes the action to the Super Admin.

## 3. No secrets on the page

Three layers, each enforced at a single writer rather than by review discipline:

| table | writer | what it accepts |
|---|---|---|
| `operations_signals` | `Operations::SignalRecorder` | `reason` collapsed, redacted by value and by the two credential patterns, truncated to 500; `detail` allow-listed keys holding scalars only |
| `operations_signal_events` | `Operations::SignalLifecycle` | the operator's typed reason, sanitized the same way; `detail` allow-listed |
| `commerce_store_health` | `Commerce::StoreHealthRecorder` | a `Commerce::Error` only — code validated against `Commerce::Error::CODES` at construction, reason kept only if it matches `/\A\w{1,60}\z/` |

There is nowhere in any of the three for a provider response body, a webhook payload, a customer, a token or
an `Authorization` header to go. The signal's `detail` is therefore rendered verbatim in the UI: the recorder
already refused anything that is not an allow-listed scalar.

Asserted end to end:

- an IMAP channel's real password written into a signal's reason is `[redacted]` on both the queue and the
  detail page;
- a WooCommerce store's `consumer_key` and `consumer_secret` do not appear on the commerce page;
- a provider's 401 body (`Bearer sk_live_… is not authorized`) produces `last_error_code = AUTH_INVALID` and a
  **null** reason, not the body.

The operator's own free text is sanitized too: it is free text that reaches a screen, so a wall of text — or a
credential copied out of a log — is collapsed, redacted and truncated before it is stored.

## 4. Performance

Every page on this surface is bounded by design, not by hoping the installation stays small.

| read | cost |
|---|---|
| Overview probes | one `SELECT 1`, one Redis `PING`, one Sidekiq process-set read |
| Overview derived blocks | cached 5 minutes with the moment they were produced |
| Queue tab counts | **one** `select_one` with eight `COUNT(*) FILTER (WHERE …)` clauses |
| Queue list | one page over `index_operations_signals_on_unacknowledged` / `_on_open_feed` |
| Commerce summary | **one** `SELECT` with five `FILTER` clauses over a `LEFT JOIN` |
| Commerce list | one page, `includes(:account, :health)`, plus one grouped signal query |
| Channel matrix | two grouped queries, whatever the installation holds |
| Recovered feed | `index_operations_signals_on_recovered`, added by `20261012101000` because every other index on the table is partial on `resolved_at IS NULL` |
| Account 360 | fixed query count: every collection is a grouped count or a `limit`ed read |
| Billing locked list | bounded to the lockable statuses and the 200 most recently changed, and labelled a recent list rather than a total |

**Three specs assert constancy rather than asserting a number**, by growing the data between two runs and
comparing the query count: `Operations::AccountSnapshot`, `Operations::CommerceOperations` and
`Operations::ChannelMatrix`.

**Nothing on this surface calls a provider.** An operator diagnosing an outage must not be made to wait on the
thing that is down, and a page that probed each store or each channel would take as long as the slowest broken
one's timeout. The one live read is `Channels::ConnectionState` on Account 360, which reads Redis and the
channel row's own columns — one account, at most 50 inboxes, `includes(:channel)`, no network.

### Write amplification in the provider path

`Commerce::StoreHealthRecorder` sits inside every provider request. Its throttle (default 5 minutes) means a
store answering a request every second writes at most one row per five minutes; failures, recoveries and state
transitions are written immediately. The throttle predicate is in SQL, so two workers cannot both decide to
write, and the failure counter is incremented in the `UPDATE` so no race loses a count. Full reasoning in
`09-commerce-operations.md` §3.2.

## 5. Two dependencies this phase did not fix here

Both are workstream E, and both are recorded here because the operator surface is where they would otherwise
have been quietly worked around:

1. **`Notifications::ConversationVisibility`** lets an unknown, non-`Conversation` actor type pass through.
   Until that is a fail-closed positive allow-list, this phase adds **no** notification path for operational
   signals — the bell stays deferred rather than reusing a path with an open authorization question.
2. **The sidebar `href` filter** (`.filter(child => child.href)`) is an accidental navigation contract. The
   Operations pages are server-rendered ERB inside the Administrate shell and do not depend on it, so nothing
   here is blocked; the contract is made explicit and regression-tested in workstream E rather than worked
   around.
