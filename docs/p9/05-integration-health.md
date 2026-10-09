# Integration and provider health

The console in `04-operations-center.md` can only show what something writes down. This document is about the
writing down — which is the part P9 actually had to add, because the audit in `00-discovery.md` found that
almost nothing operational in this product was durable.

---

## 1. What was there before

| Signal | Where it lived | What an operator could do with it |
| --- | --- | --- |
| channel authorization errors | two Redis keys, **no TTL** (`AUTHORIZATION_ERROR_COUNT`, `REAUTHORIZATION_REQUIRED`) | ask about one object, one at a time. "Every broken inbox, newest first" was not expressible. A Redis flush turned a broken inbox green. |
| IMAP fetch failure, plain password | **one log line per poll** | grep journald, if they knew to look |
| IMAP fetch failure, OAuth | the same Redis counter, after **10 consecutive failures** (`Channel::Email::AUTHORIZATION_ERROR_THRESHOLD`) | nothing durable until the tenth |
| outbound webhook failure | a `Lynomia::OperatorLog` line | grep |
| queue depth and dead set | a `Lynomia::QueueHealthJob` log line every 5 minutes | grep |
| commerce store reauth | `commerce_stores.status` — **already durable** | this one was fine |
| WhatsApp send failure | `messages.status` — **already durable** | this one was fine |

### The worst case, which is on the record

A plain-password IMAP inbox whose password is rotated:

1. `Inboxes::FetchImapEmailsJob` raises, is rescued, writes **one log line**, and the Sidekiq job reports
   **success**. No Postgres row, no Redis counter, no Sentry event.
2. Nothing increments `authorization_error_count`, because that is only called on `OAuth2::Error`.
3. If the OAuth variant *does* latch after ten failures, `should_fetch_email?` then stops polling the inbox —
   so the inbox goes **quiet** rather than erroring, and nothing durable says why.

That is the shape of the production incident recorded for email inbox 74. The symptom was "email stopped
arriving"; there was nothing to read.

---

## 2. The durable record

One table, `operations_signals`, holding **one row per distinct open problem**:

| | |
| --- | --- |
| identity | `(account_id, source, subject_type, subject_id, signal)` |
| recurrence | `occurrences`, `first_seen_at`, `last_seen_at` |
| severity | `info` / `warning` / `critical` — rises while open, never falls |
| `reason` | one sanitized, collapsed, bounded line |
| `detail` | jsonb, allow-listed keys, scalar values only |
| resolution | `resolved_at` — nil means open |
| bridge | `support_ticket_id` |

`account_id` is **nullable**, because some problems belong to the installation rather than to a tenant: no
Sidekiq workers, a growing dead set, a backlog.

### Dedup is a database constraint, not a convention

```sql
CREATE UNIQUE INDEX index_operations_signals_on_open_identity
  ON operations_signals (COALESCE(account_id, 0), source, COALESCE(subject_type, ''),
                         COALESCE(subject_id, 0), signal)
  WHERE resolved_at IS NULL;
```

`COALESCE` because NULLs are distinct from each other in a unique index, so without it an installation-wide
signal with no account and no subject would insert a fresh row on every single observation. `WHERE resolved_at
IS NULL` because the same problem recurring after it was fixed is a *new* row with its own `first_seen_at`,
which is how "this has happened three times this month" stays answerable.

The constraint is also the concurrency answer: two workers reporting the same failure at the same instant race
on the insert, the loser gets `RecordNotUnique`, and the recorder retries as an increment. P9.8's first
benchmark fixture tripped this index by accident, which was an unplanned proof that it works.

### One writer

`Operations::SignalRecorder` is the only thing that writes the table, for two reasons. The first is dedup: four
callers getting an upsert-on-open-identity right independently is four chances to get it wrong. The second, and
the more important, is that **this is where the no-secrets rule is enforced** — see §4.

```ruby
recorder = Operations::SignalRecorder.new(source: :email_channel, account: inbox.account, subject: inbox)
recorder.record(:authentication_failed, severity: :critical, reason: error.message)
recorder.resolve_all   # the next successful fetch
```

**Recording never raises into its caller.** These writers sit inside OSS jobs that fetch email and deliver
webhooks for every account on the installation; a validation bug in observability must not stop email arriving.
A failure is logged and returns nil — the same shape as `Custom::Account#start_billing_trial`.

---

## 3. The four writers

Each one is a `prepend_mod_with` module under `custom/`, so no OSS file gains logic. The two OSS files touched
gain **one line each**, the `prepend_mod_with` call that the Chatwoot architecture already expects.

### Channel reauthorization — `Custom::Reauthorizable`

Hooks `prompt_reauthorization!` and `reauthorized!`, and records **only the two state changes**, not every
error. The OSS concern already computes `state_changed` for both, so a channel failing once a minute produces
one row that gets incremented rather than a row per poll.

The Redis flag is left exactly as it was: the row sits *beside* it, not instead of it, so the UI's
`reauthorization_required?` keeps working unchanged.

`Reauthorizable` is also included by `AutomationRule` and `Integrations::Hook`, which have no inbox. Those are
skipped rather than recorded against a subject the console has no page for.

### Email fetch — `Custom::Inboxes::FetchImapEmailsJob`

Hooks `process_email_for_channel`, which is where the three outcomes are already distinguishable: it returns
true on success, false on `OAuth2::Error`, and raises for everything else.

```ruby
AUTHENTICATION_ERRORS = [Net::IMAP::NoResponseError, Net::IMAP::BadResponseError].freeze
```

An invalid login surfaces as a `NoResponse` or `Bad` response from the server. The connection-level errors in
`ExceptionList::IMAP_EXCEPTIONS` — `ECONNREFUSED`, timeouts, `SocketError` — are a different problem with a
different fix, so they are recorded as `connection_failed` at `warning` rather than `authentication_failed` at
`critical`. **The raised error is re-raised unchanged**, so the OSS job's own rescues, logging and exception
tracking behave exactly as before. A successful fetch calls `resolve_all`, so a fixed inbox clears itself.

### Outbound webhooks — `Custom::Webhooks::Trigger`

Records `delivery_failed` beside the existing operator-log line. The subject is the `Webhook` record where one
can be identified (`index_webhooks_on_account_id_and_url` is unique, so it is a single indexed lookup), so two
broken endpoints in one account stay two rows.

Neither the URL nor the payload is stored. `detail` carries `endpoint_host` — the host alone — plus the HTTP
status and the exception class.

### Queues — `Lynomia::QueueHealthJob`

Already ran every 5 minutes and already logged. Now also records: no workers (critical), a backlog above its
threshold, and a dead set that grew since the last check. A recovered backlog resolves itself.

---

## 4. No credential ever reaches the table

Two mechanisms in the one writer, and **neither of them guesses what a secret looks like**:

**By value.** The recorder is constructed with the record the observation is *about*, so it can read that
record's own secrets and remove them by exact match: `provider_config` and `credentials` (hash columns),
`imap_password` and `smtp_password` (plain columns), each read defensively so a subject class that does not
answer still gets its signal recorded. This is the only place in the product that knows both *what failed* and
*what its credentials are*, which is what makes an exact match possible here and nowhere else.

**By shape.** A URL's userinfo (`//user:pass@host`) and a `key=value` pair whose **key** names a credential
(`password`, `token`, `api_key`, `secret`, `authorization`, `bearer`, …).

`detail` is separately constrained: 24 allow-listed keys, scalar values, and a token shape with no whitespace —
so provider prose cannot arrive through `detail` either. A key nobody listed is a key nobody checked, so it is
dropped rather than stored.

Nothing is matched on entropy or length. That is a deliberate refusal: an entropy rule redacts the order ids,
`wamid`s and message ids an operator needs in order to act, while still missing a short password.

**P9.8 found this missing and added it.** Before that pass the `reason` was bounded in length but not in
content, so an IMAP server answering a failed LOGIN with the password it had been given stored it verbatim,
rendered it in the console, and copied it into a support case through the bridge. The test that found it is
`spec/requests/operations/p9_hardening_spec.rb`, which plants real credentials on real records and asserts they
are stored before asserting they do not appear.

---

## 5. Provider gates are untouched

P9 adds no provider call, changes no provider gate, and enables nothing. Salla, Zid and Shopify stay exactly as
`P7`/`P8` left them; Captain and `CAPTAIN_OPEN_AI_API_KEY` are not referenced anywhere in this phase. The
commerce area of the console reads `commerce_stores.status`, a column the product already maintained.

This matters for the deployment: nothing in P9 can change how a provider behaves, so the provider surface needs
no re-verification beyond the P8 regression smoke in `07-uat-runbook.md`.

---

## 6. What is still not durable

| Still not recorded | Why not, in this phase |
| --- | --- |
| per-poll channel error counts | The Redis counter stays the counter. One row per state change is what an operator can act on; one row per poll is a log. |
| provider API latency | Nothing measures it today, and adding timing to every provider call is a change to the provider layer, not to observability. |
| a time series of any signal | `operations_signals` holds one row per open problem with a recurrence count. "Was this worse last week?" needs a different table and a retention policy. |
| inbound message volume per channel | P8's analytics answer this per account; the installation-wide view would be a new rollup. |
| Sidekiq job-level failures | `Sidekiq::Web` has them, properly, at `/monitoring/sidekiq` behind the same guard. |
