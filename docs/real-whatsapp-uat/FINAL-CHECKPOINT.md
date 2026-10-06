# P5 FINAL CHECKPOINT — WhatsApp diagnosis and inbound reliability hardening

The sixty-item report the phase asks for. Where an item is a live result this environment cannot produce, it says
**BLOCKED — RUN ON REAL SERVER** and names where the answer comes from, rather than guessing.

---

### 1. Branch + HEAD

`claude/practical-thompson-9xfqed` at `46a73fdf`. HEAD before the continuation was `cbd2a91d`.

### 2. Commits

Nine, each one change:

| | |
|---|---|
| `e027ee45` | inbound no longer dropped by the reauth latch, and setup failure tells the truth |
| `05e27feb` | credentials out of query strings, media 401 gating, retry keeps Meta's reason |
| `539a57fd` | the inbound-reliability regressions |
| `39d614a0` | the diagnosis restructured into the seven operator sections |
| `939cc2a9` | the regression matrix completed — and the fifth credential-bearing URL it found |
| `18cc3bca` | docs 06, 07, 10, plus updates to 00, 01, 02, 03, 09 |
| `899a5546` | one odd Meta response must not cost the whole diagnosis |
| `b98794f5` | this checkpoint, and two corrections |
| `46a73fdf` | the diagnosis was writing to the database, including a credential |

### 3. Repository defects proven

Six, each proven by reading the code and executing the failure — not inferred. The full statement is `08`'s
**PROVEN — repository defects** table.

| # | Defect |
|---|---|
| 1 | `Webhooks::WhatsappEventsJob#channel_is_inactive?` discarded every inbound payload for an embedded-signup channel whose `reauthorization_required?` flag was set — permanently, since the flag has no expiry, and silently, since Meta had already been answered 200 OK and Sidekiq recorded a success |
| 2 | `Channel::Whatsapp#setup_webhooks` rescued a real webhook-setup failure, latched the channel and reported success, so an inbox could be created that can never receive |
| 3 | `Whatsapp::MessageDedupLock` had no release, so one exception made a message id unprocessable for a day and every redelivery from Meta was silently discarded |
| 4 | a media-read 401 counted as an authorization error on the bare HTTP status, so two per-resource failures latched a healthy channel |
| 5 | pressing **Retry** erased `external_error`, destroying the only record of why Meta refused the message |
| 6 | five call sites sent the access token in a URL or query hash, where it reaches access logs, proxy logs and exception messages; two of them ran on every channel validation |

The sentence this phase is entitled to write, and does: **a repository containing defects 1 and 2 is capable of
producing exactly the four symptoms reported.** Not "production root cause confirmed" — that needs §51's command.

A seventh defect belongs in the record but not in that table, because this phase **introduced** it rather than
found it: the diagnosis task itself was writing to the database, and on a production server would have written the
Meta app secret into `installation_configs`. It was caught by a stray row in the test database and is fixed — §27
and §42 tell it in full.

### 4. Production facts still unproven

Every one of these is a statement about the real installation that only the real server can settle. None is
asserted anywhere in this document set:

- whether the real channel's `reauthorization_required?` flag is set
- whether `WHATSAPP_APP_SECRET` is configured there, which decides whether inbound is being answered 401
- whether any app is subscribed to the real WABA, and whether it is the configured one
- whether the callback Meta holds for the number is this installation (app-level or phone-level override)
- whether the stored `phone_number_id` equals Meta's
- whether a Sidekiq process is consuming `low`
- whether any inbound message has ever persisted for the inbox
- whether the real number is on Coexistence

### 5. `setup_webhooks` swallow defect result

**Confirmed, and worse than the first draft of `02` said.** `Whatsapp::WebhookSetupService#setup_webhook` does
re-raise (`"Webhook setup failed: …"`), but the model's `rescue StandardError => e` → log →
`prompt_reauthorization!` swallowed it with no re-raise. Since it is an `after_commit … on: :create`, the inbox was
already saved and the API answered success. The correction is recorded in place in `02` rather than quietly edited.

### 6. Fix implemented

`setup_webhooks!` reports and **raises**; `setup_webhooks` is kept only for the `after_commit` path and returns a
documented boolean. Every caller was inspected before choosing, which is what the phase asked for: `after_commit`
cannot usefully raise for a record already committed, while `Whatsapp::EmbeddedSignupService` and manual setup v2
call setup explicitly *so that their API responses reflect the real result* — that stated intent was what the
rescue defeated. `EmbeddedSignupService` now calls the bang form. A structured result was considered and rejected:
no caller wanted to branch on a reason, and raising is what the existing error handling already propagates.

### 7. Reauthorization latch semantics

| | |
|---|---|
| Set by | `Reauthorizable#prompt_reauthorization!` — `Redis::Alfred.set(key, true)` with **no `ex:`**, so no expiry |
| Set via | `authorization_error!` reaching `AUTHORIZATION_ERROR_THRESHOLD = 2`, or a direct call from `Channel::Whatsapp#setup_webhooks!` on failure and `EmbeddedSignupService#check_channel_health_and_prompt_reauth` on an unhealthy number |
| Cleared by | `reauthorized!` only — completing the reauthorization flow for the inbox in the dashboard |
| Means now | *somebody needs to reauthorize this channel.* Nothing more: it no longer gates ingestion |

**No TTL was added, deliberately.** A TTL is a guess at how long an authorization problem takes to fix, and it
would silently re-enable a channel whose token is still dead — trading a visible problem for an intermittent one.
The correct fix was to stop the flag gating inbound at all. `09` §2 records the reasoning.

### 8. Inbound processing behaviour after the fix

A channel awaiting reauthorization **ingests**. Contact, ContactInbox, Conversation and Message are all local
writes needing no Meta credential; only the media download needs one, and
`Whatsapp::IncomingMessageBaseService#attach_files` already returned early on a failed download while
`@message.save!` still ran. So the guard destroyed customer data to protect nothing, and an attachment-less message
is a supported state. The worst case is now a message with its text and caption and no attachment.

### 9. Does the reauth flag still block inbound, and why

**No.** `ingestible?` replaced the guard and refuses only two cases, both where there is genuinely nothing to write
to: a payload naming a `phone_number_id` this installation does not own, and a suspended account. Neither is
retryable — the id will never start matching — so both are reported as structured `[WHATSAPP INGEST]` lines rather
than retried forever.

### 10. Authorization error threshold result

`AUTHORIZATION_ERROR_THRESHOLD = 2`, unchanged, and now pinned by a boundary test: one error leaves the channel
unlatched, the second latches it. One consequence worth stating, because it looks like a contradiction in the
report: `prompt_reauthorization!` sets the flag **without** incrementing the counter, so a latched channel can show
`authorization_error_count: 0`. The diagnosis prints both, with a note, because neither can be inferred from the
other.

### 11. Media 401 handling

Only Meta's own verdict counts: `error['type'] == 'OAuthException' || error['code'].to_i == 190`, which is the rule
three Instagram call sites in this repository already use. A 401 Meta attributes elsewhere logs
`event=media_unauthorized` and is not counted. A 401 whose body cannot be parsed **still counts**, so an
unreadable response keeps the previous, safer behaviour rather than silently ignoring a real expiry. A genuinely
dead token produces 190 on every call, including this one, so real authorization handling is not weakened.

### 12. Redis latch lifecycle

Fully stated in §7 and in `09` §2, with its triggers, its single supported clear, and its side effects (a
`whatsapp_disconnect` administrator email and a websocket event, both guarded by `state_changed`, so a repeat set
is quiet). Left as it is.

### 13. Supported reauthorization clearing behaviour

`reauthorized!` deletes both the flag and the error counter, and a regression pins it. **No existing production
flag was cleared by this work, and `redis-cli DEL` is never offered as a fix** — it hides the cause and the flag
returns after the next two authorization errors. The diagnosis reports the flag; it has no write path to clear it.

### 14. Dedup lock defect

`acquire!` was `SET NX EX` with a one-day TTL, had no release method, and nothing anywhere deleted the key. It was
taken before `set_contact` and before the write transaction, so any exception after it left that message id
unprocessable for a day — and every redelivery from Meta was silently discarded, because the lock returns false
and `process_messages` returns.

### 15. Dedup lock fix

The lock is now what its own docstring always said it was — a mutex, not a tombstone — and is released in an
`ensure`. Durable deduplication is the persisted `Message` row, which `find_message_by_source_id` checks first, and
a regression pins that duplicates are still suppressed. The TTL stays as the backstop for a process that dies
before reaching its `ensure`.

### 16. Manual retry Meta-error defect

`claim_message_retry` called `StatusUpdateService.new(message, 'sent')` — permitted, because any transition out of
`failed` is allowed — and `resolved_external_error` returns nil for a non-failed status. Then `content_attributes`
was replaced wholesale. Pressing Retry destroyed the only record of why Meta refused the message, at the moment the
operator most needed it.

### 17. Retry fix

The reason is captured **before** the status change and kept as
`content_attributes['previous_external_error']`, with `retried_at` marking it historical so it cannot be read as
the current state. One slot, not an event store: the phase asked for the existing fields, and the useful thing is
the most recent real refusal.

### 18. Credential-in-query findings

Five, all GET reads: `providers/whatsapp_cloud_service.rb#message_templates` and `#phone_numbers` (both on the
channel-validation path, so a live token was written to logs routinely), `facebook_api_client.rb#fetch_phone_numbers`,
`health_service.rb#fetch_graph_data`, and `business_profile_service.rb#fetch`. The fifth was found by the new
regression, not by the text sweep, because it passed the token in a `query:` hash rather than interpolating it into
the URL — which is why the static guard now matches both shapes.

### 19. Credential transport fixes

All five send `Authorization: Bearer`; non-credential parameters such as `fields` and `limit` stay as proper query
parameters. **Two documented exceptions**, both left as Meta's contract requires and both now carrying a comment
saying why: `/oauth/access_token`, which is the token exchange itself and has no bearer token yet, and
`/debug_token`, where `input_token` is the subject being inspected and Meta passes the authorizing app token
alongside it. A regression pins that `FacebookApiClient` carries **exactly two** credential parameters, so the
exceptions cannot quietly become three. Nothing logs a credential-bearing URL: the diagnosis prints a callback
override as scheme, host, port and path only, because an `override_callback_uri` can carry a verify token in its
query string.

### 20. Dead fallback finding

An audit called `find_channel_by_url_param` unreachable for `whatsapp_business_account` payloads and suggested
reviving it as a fallback.

### 21. Fallback fix / removal

**Neither revived nor removed, and the audit was wrong.** Reviving it was tried, and
`spec/jobs/webhooks/whatsapp_events_job_spec.rb:44` immediately proved why it must not be: one Meta app serves many
numbers, and the URL is whatever the phone-level callback override was registered with, so falling back would file
one number's customer message under a **different** channel's inbox. For a Cloud delivery the payload metadata is
the only acceptable source. The lookup stays reachable for 360dialog (`provider == 'default'`), which posts a
different payload shape to the per-number route, so it is not dead code. A long comment now records the reasoning
so the next audit does not reach the same wrong conclusion.

### 22. Missing app-secret behaviour

With no channel-level secret and a blank `WHATSAPP_APP_SECRET`, the signature loop finds nothing to compare and
`verify_meta_signature!` answers **401 to every inbound webhook** — recorded by a single `Rails.logger.warn` and,
from Meta's side, visible only as a delivery-failure statistic. That is correct behaviour, and the fix is
configuration, not code. The diagnosis reports it as a top-priority `AUTH` failure. Nothing in the product ever
writes `provider_config['app_secret']`, so in practice the installation-wide value is the only reachable secret,
and it has no default in `config/installation_config.yml`.

### 23. Signature-verification result

**Enforced, unchanged, and pinned.** Verified over `request.raw_post` with `ActiveSupport::SecurityUtils.secure_compare`,
required whenever `whatsapp_channel.blank? || provider == 'whatsapp_cloud'`. Three regressions: a mismatched
signature is refused, a correctly signed payload is accepted, and a blank secret refuses everything. It was never
weakened to make a test pass, and disabling it is not offered as a fix anywhere.

### 24. Phone callback override diagnostic

The `WEBHOOK` section reads `GET /<phone_number_id>?fields=webhook_configuration` and reports the phone-level
override, the app-level callback, and which one is **effective** — the override, because that is Meta's precedence.
This is the suspect a dashboard check cannot see: an override is invisible there, so a number can be overridden to
a stale URL while the Meta App's configuration still looks correct.

### 25. App-level callback diagnostic

Reported beside it, and the verdict names its source:
`MATCH (APP_LEVEL_CALLBACK)`, `MATCH (PHONE_LEVEL_OVERRIDE)`, `MISMATCH (…)`, or `UNKNOWN`. `UNKNOWN` is recorded
**BLOCKED, not FAIL**: unproven is not failing, and must not be read as passing either. `10` §3 is the operator's
table.

### 26. Diagnostic task result

`bundle exec rails whatsapp:diagnose [INBOX_ID=…] [CONTACT=+…]`, kept as a permanent operator-safe diagnostic and
restructured into the seven sections the phase specified: `CHANNEL`, `META IDENTITY`, `AUTH`, `WABA SUBSCRIPTION`,
`WEBHOOK`, `LOCAL PIPELINE`, `CONTACT TEST`, then `SUMMARY` and `WHAT TO FIX, IN ORDER`. Executed end to end
against a throwaway channel in a rolled-back transaction: all seven sections render, the Meta reads return Meta's
own `OAuthException 190` for a fixture token, and the fix order is prioritised. Thirteen specs pin its contract,
including the write-freedom ones §27 describes.

### 27. Confirmation the diagnostic is read-only

**Confirmed for Meta and Redis without qualification; for the database, with one named row.**

Meta: every call is a GET through the existing `Whatsapp::FacebookApiClient`. No subscribe, register, rotate or
delete exists anywhere in the service. Redis: no key is written, and the reauthorization flag is neither set nor
cleared. `spec/services/whatsapp/diagnosis_spec.rb` asserts all of it — no POST, PUT, PATCH or DELETE to
`graph.facebook.com`; Message, Contact, Conversation, Channel and Inbox counts unchanged; `Redis::Alfred` never
receives `set`, `delete` or `incr`; an existing reauthorization flag still set after the run.

The database qualification is worth stating plainly, because the first version of this work got it wrong and the
evidence that caught it was a stray row in the test database.

`GlobalConfigService.load` — the ordinary accessor, used by the diagnosis's first version — ends in
`InstallationConfig.where(name:).first_or_create(value: …)` plus `GlobalConfig.clear_cache`. It is create-on-read
by design, to migrate installations still relying on ENV. So the diagnosis was writing: it left a
`WHATSAPP_API_VERSION` row behind every run, and on a production server where `WHATSAPP_APP_SECRET` is set in ENV
but has no row it would have written **the app secret into the database**. Two fixes:

- `Whatsapp::Diagnosis::StoredConfig` is now the one place configuration is read, with a plain
  `InstallationConfig.find_by` then ENV then the caller's default. No create, no cache write.
- `/debug_token` is authorized with an app access token built as `app_id|app_secret` inside
  `FacebookApiClient#build_app_access_token`, which uses that accessor. The diagnosis is that endpoint's only
  caller in the repository, so it now skips the token-debug read unless **both** values are already stored, and
  reports `BLOCKED` naming what to configure. An unanswered check is cheaper than a credential written by a tool
  that promised not to write.

What remains is one row, and it is not the diagnosis's own doing: nine production call sites resolve the Graph
version through `GlobalConfigService.load`, `FacebookApiClient#initialize` among them, so constructing the API
client can create a `WHATSAPP_API_VERSION` row — a version string equal to the default already in use, exactly as
the first WhatsApp request of any kind on that server would create it. A regression pins that this is the **only**
name a run may add, so the set cannot widen unnoticed.

### 28. Confirmation the diagnostic masks secrets

**Confirmed, by test.** `AUTH` reports credential **presence and provenance only** — not a masked value, because a
masked secret still leaks its length and nothing in the report needs it. A customer or business number prints as
`+9655•••21`. A callback URI prints as scheme, host, port and path. The spec asserts the output contains neither
the channel's `api_key` nor its `webhook_verify_token` nor its full phone number.

### 29. 24-hour send-path result

`Whatsapp::SendOnWhatsappService#perform_reply` refuses a plain reply **locally** when
`conversation.can_reply?` is false, writing `status: :failed` and
`external_error: I18n.t('errors.whatsapp.message_outside_messaging_window')`. The existing string was checked
against the wording the phase asks for and already says it, with the next action attached:

> Message not sent because the WhatsApp 24-hour customer service window is closed and no template parameters were
> provided. Send an approved template message instead.

So it was left alone — it is not disguised as a Meta delivery failure, and Meta was never contacted. A regression
asserts no request reaches `graph.facebook.com`. This path is unchanged by this phase, and it is the mechanism that
turns a broken inbound into a reported *outbound* failure, which is why symptom 4 was reported the way it was.

### 30. Approved-template bypass result

A template takes the first branch of `perform_reply` and never consults the window, so an approved template reaches
a brand-new contact. Pinned by a regression. This is why the phase insists the first send to a truly new contact be
an approved template rather than free-form text: *approved template succeeds + plain text fails before inbound* is
normal 24-hour-window behaviour, not a defect.

### 31. Local failure vs Meta failure distinction

Preserved and made explicit. A local refusal carries the window message and Meta was never contacted; a Meta
refusal carries Meta's own code and title (`"131047: Re-engagement message"`), flattened by
`update_message_with_status`. Both land in `external_error`, so the operator reads which it was from the value, and
the diagnosis prints recent failures verbatim. The retry fix matters here: it used to erase exactly this
distinction.

### 32. Observability improvements

Inside the installation's **existing** observability — no second monitoring stack. A refused inbound payload writes
one structured line at error level:

```
[WHATSAPP INGEST] event=unroutable_payload phone_number_id=… url_phone_number=… detail=…
[WHATSAPP INGEST] event=inactive_account channel_id=… inbox_id=… account_id=… phone_number_id=… detail=…
[WHATSAPP INGEST] event=webhook_setup_failed channel_id=… inbox_id=… account_id=… phone_number_id=… source=… failure_class=…
[WHATSAPP INGEST] event=media_unauthorized channel_id=… inbox_id=… detail=…
```

A webhook-setup failure also reaches `ChatwootExceptionTracker`, which is Sentry where it is configured, because it
disables inbound until somebody reauthorizes. **No token, no secret, no customer message body** — the fields are
the ones needed to find the channel and the Meta-side record. A permanently dropped inbound webhook is no longer
visible only as one warning line.

### 33. Sidekiq success/failure semantics

Reassessed per failure class, from the architecture rather than by default:

| Outcome | Class | Why |
|---|---|---|
| unroutable payload | **success, reported** | the id will never match; retrying repeats the drop and floods the queue |
| suspended account | **success, reported** | a product decision, not a transient fault |
| lock contention | **retryable** — `retry_on LockAcquisitionError, wait: 2s, attempts: 20` | genuinely transient; the 38s budget deliberately exceeds the 30s lock TTL |
| an exception during ingestion | **retryable**, Sidekiq's default | and now safe to retry, because the dedup lock is released in an `ensure` |
| media download failure | **persisted with degraded media state** | the partial state the architecture already supported |
| enqueue failure in the controller | **500 to Meta** | the event was not durably accepted |

No infinite retries, and nothing retried that cannot succeed.

### 34. Meta webhook HTTP semantics

Inspected and left correct. The controller does **not** fake durable acceptance: if `perform_later` raises, the 500
propagates and Meta redelivers, which is right because the event was not accepted. And it does not return 500 to
force a retry for an event it *has* accepted — once `perform_later` succeeds, the 200 is truthful and the job owns
the outcome. 401 (bad signature), 422 (inactive number) and 200-without-enqueue (a tracking-events-only delivery)
are each correct for their case; `04` §2 tabulates all five.

### 35. WhatsApp regressions

**622 examples, 0 failures.** `spec/services/whatsapp`, `spec/models/channel/whatsapp_spec.rb`,
`spec/jobs/webhooks/whatsapp_events_job_spec.rb`, `spec/controllers/webhooks/whatsapp_controller_spec.rb`,
`spec/requests/whatsapp`, `spec/jobs/channels/whatsapp`, `spec/controllers/api/v1/accounts/whatsapp`.

### 36. Coexistence regressions

**13 examples, 0 failures.** `spec/controllers/api/v1/accounts/whatsapp/coexistence_onboarding_spec.rb`. No
coexistence behaviour was changed; `07` records what it is and why re-registering a coexistence number is
destructive rather than merely wasteful.

### 37. Template Manager regressions

**85 examples, 0 failures.** Template processor, message-templates controller, parameter converter, the
authentication-template guard, parameter population, the Liquid processor and the sync job.

### 38. Campaign regressions

**91 examples, 0 failures.** Campaign and campaign-audience models and controllers, the WhatsApp one-off campaign
service (OSS and Enterprise), the trigger job and the campaign listener.

### 39. Flow regressions

**72 examples, 0 failures.** `spec/services/flows` (runner, versions, graph and template validators, nodes
including `send_template`, runner security), the run job, the flows controller and the agent-bot flow listener.

### 40. Contacts regressions

**203 examples, 0 failures.** Contact model, `spec/services/contacts` (filter, bulk actions, labels, view scope,
phone normalization) and the contacts controller.

### 41. Targeted webhook tests

**70 examples, 0 failures** across `FacebookApiClient`, `SendOnWhatsappService`, `MessageDedupLock`,
`BusinessProfileService`, `EmbeddedSignupService` and `HealthService`, plus the webhook controller and
`WhatsappEventsJob` inside §35. The new work itself: `spec/requests/whatsapp/inbound_reliability_spec.rb` — **37
examples**, covering all twenty required regressions (`09` §9 maps each one) — and
`spec/services/whatsapp/diagnosis_spec.rb` — **13 examples**, including the four that pin what the diagnosis
may and may not write (§27).

### 42. Full RSpec

**10714 examples, 2 failures, 67 pending** — and the two failures are **exactly** the declared baseline:

```
rspec ./spec/builders/agent_builder_spec.rb:47
rspec ./spec/enterprise/services/voice/call_transcription_service_spec.rb:77
```

Nothing else. This is the second run; the first returned 13 failures, and the extra 11 were investigated,
reproduced and classified rather than dismissed — none was called a flake. All 11 were **pre-existing test
database pollution** meeting globally unscoped assertions, from my own earlier `rails runner` debugging:

| Failures | Assertion | Leftover |
|---|---|---|
| `spec/enterprise/models/inbox_spec.rb:162, :194, :238` | `Audited::Audit.where(auditable_type: 'Inbox', action: 'create').count == 1` → got 3 | 2 `audits` rows |
| `spec/lib/config_loader_spec.rb:8` | `InstallationConfig.count == 0`, a precondition → got 1 | 1 `installation_configs` row |
| `spec/models/working_hour_spec.rb:13, :25, :37, :49, :63, :71, :107` | `WorkingHour.today` resolves its timezone via `first.inbox`, an unscoped `ORDER BY id LIMIT 1` | 14 orphaned `working_hours` rows |

Each was reproduced deliberately — insert the row, watch exactly those lines fail with exactly that message;
remove it, watch the file pass — by three independent agents before being attributed. The orphaned working hours
are structurally possible because `working_hours` has **no foreign key** to `inboxes` and `out_of_offisable.rb`
associates them `dependent: :destroy_async`, so the job never runs under `Sidekiq::Testing`: even a correct
`destroy` strands seven rows per inbox, permanently. The fix was `rails db:test:prepare`, which rebuilds the
schema rather than guessing which tables to clean; this run started on a rebuilt database. `00` §5 records the
hazard, which has now cost three rounds.

**And the pollution produced the §27 finding.** The stray `installation_configs` row was named
`WHATSAPP_API_VERSION`, timestamped to the minute the diagnosis task was first run by hand — which is how the
diagnosis's own database write, and the app-secret write behind it, came to light.

### 43. Full Vitest

**493 test files, 5177 tests, all passed**, exit 0. No JavaScript or Vue file was changed in this phase, so this
gate confirms the absence of collateral damage rather than new behaviour.

### 44. ESLint

**0 errors**, 510 warnings, exit 0. The warnings are the repository's pre-existing baseline
(`@intlify/vue-i18n/no-dynamic-keys` and friends); this phase added none, and changed no JavaScript or Vue file.

### 45. RuboCop

**3470 files inspected, no offenses detected**, exit 0. Every change in this phase passed RuboCop without a
single cop disabled: the ClassLength limit is what split the diagnosis into six collaborators, and the
`allow_any_instance_of` ban is why the specs stub at class level.

### 46. Production build

**Succeeded: `✓ built in 1m 39s`, "Build with Vite complete"**, exit 0, with
`SECRET_KEY_BASE=<throwaway> NODE_ENV=production RAILS_ENV=production bin/vite build --force`. The remaining
warnings are the repository's pre-existing ones: chunks over 500 kB, and an outdated `caniuse-lite`.

Worth recording how it was verified, because the first attempt was a false green of exactly the kind this phase
is about. Run without a `SECRET_KEY_BASE`, `bin/vite build` printed

```
Unable to initialize Rails application before Vite build:
  Missing `secret_key_base` for 'production' environment …
Skipping vite build. Watched files have not changed since the last build at …
```

and **still exited 0**. A gate that reports success for a build it declined to run is worth no more than the
`setup_webhooks` that reported success for a registration it had not performed. The result above is from a build
that actually compiled, forced past the no-change check; its 530 MB of artefacts were then removed, since
`public/vite*` is gitignored and the disk allowance is finite.

### 47. Migration count

**Zero.** No migration, no schema change, no new column and no new table. Every fix is behavioural, inside the
existing pipeline.

### 48. Meta configuration changed?

**No.** Nothing was subscribed, unsubscribed, registered, re-registered, overridden or deleted at Meta. No Meta App
was created, no WABA was created, no number was re-registered, no Coexistence connection was touched, no production
template was deleted, no callback URL was changed and no credential was rotated. The only Meta traffic from this
environment was GET reads that returned `OAuthException 190` for a fixture token.

### 49. Production Redis changed?

**No.** No key was written and none was deleted. No reauthorization flag was cleared. The diagnosis has no Redis
write path, and a spec asserts that `Redis::Alfred` receives no `set`, `delete` or `incr` during a run. Note that
this is why the diagnosis reads configuration with a plain `SELECT` rather than through `GlobalConfig`, whose
`load_from_cache` writes a cache key with a one-day TTL whenever the cache is cold (§27).

### 50. Graph API changed?

**No.** `DEFAULT_API_VERSION` remains `v24.0`, overridable by `WHATSAPP_API_VERSION`. No upgrade was attempted, and
nothing found in this phase points at the API version: every proven defect is in this repository's own handling.
API-version work should reopen only if official Meta evidence shows an endpoint incompatibility.

### 51. Production UAT status

**BLOCKED — REAL SERVER DIAGNOSIS REQUIRED.** Four structural reasons, none removable by further local work: no
real access token (and the phase says not to ask for one), fixture WABA and `phone_number_id`, no handset, and this
container is not Meta's callback destination. What is *not* blocked: the network path to Meta works from here — a
token-bearing GET reaches the Graph API and returns a genuine Meta error — so the operator's run will return real
answers.

### 52. Exact command still required on production

```bash
bundle exec rails whatsapp:diagnose INBOX_ID=<id> CONTACT=+<old_test_number>
```

Run on the server whose database owns the real WhatsApp inbox, as the application user, in the application
directory. GET-only, changes nothing in Meta or Redis, no credential printed or written (§27), safe to paste
back. Use the **old** test contact: its
conversation has a persisted inbound message, so its window state is the control for the new contact's.

### 53. Exact output fields the operator must return

The whole report, unedited — it is already masked. Specifically these decide the open questions:

| Section | Fields |
|---|---|
| `CHANNEL` | `reauthorization_required`, `authorization_error_count`, `source`, coexistence indicators, stored `phone_number_id` |
| `META IDENTITY` | `status`, `code_verification_status`, `platform_type`, and Meta's `phone_number_id` for comparison |
| `AUTH` | token validity, scopes, expiry; whether a Meta app secret is configured |
| `WABA SUBSCRIPTION` | the subscribed apps and their ids, and whether the configured app is among them |
| `WEBHOOK` | the classification verdict and source, and the subscribed field list |
| `LOCAL PIPELINE` | Sidekiq process count, `low` queue depth, dead and retrying WhatsApp jobs |
| `CONTACT TEST` | incoming/outgoing counts and timestamps, the outbound status mix, `can_reply?`, and recent `external_error` values |

Plus, from the operator rather than the report: any `[WHATSAPP INGEST] event=…` lines in `log/production.log`
during the test, and Meta → Webhooks delivery statistics for the number. `10` §6 is the paste-back template.

### 54. Live inbound status

**BLOCKED — RUN ON REAL SERVER.** Needs a real handset and the real callback destination. The path is traced
statically in `04` and covered end to end by tests; what the live run adds is whether Meta is attempting delivery
and what status the real host returns.

### 55. Live old-contact outbound status

**BLOCKED — RUN ON REAL SERVER.** `10` §5 STEP 4 items 1 and 2.

### 56. Live new-contact approved-template status

**BLOCKED — RUN ON REAL SERVER.** `10` §5 STEP 4 item 3. Must be an approved template, never free-form text.

### 57. Live service-window reply status

**BLOCKED — RUN ON REAL SERVER.** `10` §5 STEP 4 items 4 and 5. The expected chain after the fix: new contact sends
a message → the incoming message persists → `conversation.can_reply?` is true → a plain reply is allowed.

### 58. Live coexistence status

**BLOCKED — RUN ON REAL SERVER.** `10` §5 STEP 4 item 7. Whether the Business App still holds the number is
something only the operator's phone can answer, and it is the reason the DO-NOT list exists.

### 59. Remaining production blockers

1. no real credential, and it should stay that way — the diagnostic exists so the credential never has to move
2. no handset able to send to the business number
3. this container is not the registered callback destination
4. host-level evidence (the access log for the callback path, and Meta's delivery statistics) is outside any
   command this repository can run

### 60. Final verdict

**P5 SOFTWARE HARDENING:**
**COMPLETE**

**REAL WHATSAPP UAT:**
**BLOCKED — REAL SERVER DIAGNOSIS REQUIRED**

Not `PRODUCTION GO`. Six repository defects are fixed and pinned by tests; the production state they would explain
is unproven until §52's command runs.

---

**WHATSAPP RELIABILITY:**
**HARDENED THE EXISTING LYNOMIA / CHATWOOT WHATSAPP PIPELINE SO SETUP FAILURES, REAUTHORIZATION STATE, WEBHOOK
INGESTION, RETRIES AND DELIVERY FAILURES ARE TRUTHFUL AND OBSERVABLE WITHOUT CREATING A SECOND WHATSAPP ENGINE**

**REAL META:**
**NO PRODUCTION CONFIGURATION WAS CHANGED WITHOUT DIRECT EVIDENCE FROM THE REAL SERVER**
