# 09 — The fix (P5 Part G)

Six repository defects, each the smallest change that makes the behaviour truthful, each inside the existing
pipeline. No new webhook endpoint, no second receiver, no second ingestion engine, no new setup engine, no
migration.

**Nothing in Meta was changed. Nothing in production Redis was changed. The Graph API version was not changed.**

---

## 1. Inbound is no longer discarded by the reauthorization latch

**Was:** `Webhooks::WhatsappEventsJob#channel_is_inactive?` returned true when
`reauthorization_required? && embedded_signup_channel?`, and `perform` returned after one `Rails.logger.warn`. Every
inbound customer message for the channel was discarded — permanently, because the flag has no expiry; silently,
because the controller had already answered Meta `200 OK` and Sidekiq recorded a success.

**The architectural question P5 Part 3 asks — which inbound operations truly need valid Meta credentials — has a
clear answer in this codebase:**

| Inbound step | Needs a Meta credential? |
|---|---|
| resolve or create the Contact and ContactInbox | **no** — local database writes |
| resolve or create the Conversation | **no** |
| persist the Message, including its text | **no** |
| download a media attachment | **yes** |

And the partial state already exists. `Whatsapp::IncomingMessageBaseService#attach_files` returns early when the
download fails, and `@message.save!` still runs:

```ruby
def create_regular_message(message)
  create_message(message, source_id: message[:id])
  attach_files                      # returns early if the download fails
  attach_location if message_type == 'location'
  @message.save!                    # the message is saved either way
end
```

So the guard destroyed customer data to protect nothing: an attachment-less message is a supported state, not a
broken one.

**Now:** `ingestible?` replaces it. A channel awaiting reauthorization **ingests**, and loses at most its
attachments. Two refusals remain, both for cases where there is genuinely nothing to write to:

```ruby
def ingestible?(channel, params)
  return report_unroutable(params) if channel.blank?
  return report_inactive_account(channel) unless channel.account.active?

  true
end
```

Neither is retryable — a payload naming a `phone_number_id` this installation does not own will never become
ingestible — so both are reported rather than retried, and neither is silent.

## 2. The reauthorization latch: lifecycle, triggers, and why no TTL was added

P5 Part 5 asks for correct lifecycle semantics rather than an arbitrary TTL. Here is the lifecycle as it stands,
unchanged:

| | |
|---|---|
| **Set by** | `Reauthorizable#prompt_reauthorization!` — `Redis::Alfred.set(key, true)` with no `ex:`, so no expiry |
| **Set via** | (a) `authorization_error!` reaching `AUTHORIZATION_ERROR_THRESHOLD = 2`; (b) a direct call — `Channel::Whatsapp#setup_webhooks` on failure, and `Whatsapp::EmbeddedSignupService#check_channel_health_and_prompt_reauth` on an unhealthy number |
| **Cleared by** | `Reauthorizable#reauthorized!` only, which deletes both the flag and the error counter |
| **Cleared via** | completing the reauthorization flow for the inbox in the dashboard |
| **Side effects on set** | a `whatsapp_disconnect` administrator email and a websocket reauthorization event — both guarded by `state_changed`, so a repeat set is quiet |
| **Reported by** | `Channel::Whatsapp#reauthorization_required?`, and now the diagnosis task |

**No TTL was added, deliberately.** A TTL would be a guess at how long a genuine authorization problem takes to
fix, and it would silently re-enable a channel whose token is still dead — trading a visible problem for an
intermittent one. The correct fix was to stop the flag from gating inbound at all, which is what §1 does. The flag
now means exactly what its name says: *somebody needs to reauthorize this channel*, surfaced in the UI and in the
diagnosis, with no hidden effect on message ingestion.

One consequence worth stating: `prompt_reauthorization!` sets the flag **without incrementing the counter**, so a
latched channel can show `authorization_error_count: 0`. The diagnosis prints both, because the counter cannot be
used to infer the flag.

## 3. The dedup lock is released

**Was:** `Whatsapp::MessageDedupLock#acquire!` was `SET NX EX` with a one-day TTL, had no release method, and
nothing anywhere deleted the key. It was taken at `incoming_message_base_service.rb:39` — before `set_contact` and
before the write transaction — so any exception after it left that message id unprocessable for a day, and every
one of Meta's redeliveries was silently discarded.

**Now:** the lock is what its own docstring always said it was — a mutex, not a tombstone. Durable deduplication is
the `Message` row, which `find_message_by_source_id` checks first. So the lock is released on every exit:

```ruby
return if find_message_by_source_id(messages_data.first[:id])
return unless lock_message_source_id!

begin
  ingest_messages
ensure
  release_message_source_id!
end
```

Duplicates are still suppressed — by the persisted row — and that is covered by its own regression
(`still suppresses a duplicate delivery of a message it already persisted`). The TTL stays as the backstop for a
process that dies before reaching its `ensure`.

## 4. A media 401 only counts when Meta says it is an OAuth problem

**Was:** `inbox.channel.authorization_error! if url_response.unauthorized?` — the bare HTTP status. Media ids are
app-scoped and expire, so Meta answers 401 for a media id this app may no longer read as well as for a dead token.
Two such per-resource failures tripped the threshold and raised a disconnect alarm for a healthy channel.

**Now:** only Meta's own verdict counts, which is the rule three Instagram call sites in this repository already
use (`channel.authorization_error! if error_code == 190`):

```ruby
def oauth_error?(response)
  error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : nil
  return true if error.blank?

  error['type'] == OAUTH_ERROR_TYPE || error['code'].to_i == 190
end
```

A 401 whose body cannot be read **still counts**, so an unparseable response keeps the previous, safer behaviour
rather than silently ignoring a real expiry. A 401 Meta attributes elsewhere is logged as
`event=media_unauthorized` and not counted.

This does not weaken real authorization handling: a genuinely dead token produces code 190 on every call, including
this one.

## 5. A retry keeps the provider's reason

**Was:** `claim_message_retry` called `StatusUpdateService.new(message, 'sent')` — permitted because any transition
out of `failed` is allowed — which nils `external_error` (a non-failed status resolves to no error), then replaced
`content_attributes` wholesale. Pressing Retry destroyed the only record of why Meta refused the message.

**Now:** the reason is captured before anything clears it, and kept on the message:

```ruby
failure_history = previous_failure_attributes   # BEFORE the status change
Messages::StatusUpdateService.new(message, 'sent').perform
retry_attributes = { content_attributes: retry_content_attributes.merge(failure_history) }
```

`content_attributes['previous_external_error']` holds the last real refusal and `retried_at` says it is from a
previous attempt, so it cannot be mistaken for the current state. One slot, not a history — the brief asks for the
existing fields rather than an event store, and the useful thing is the most recent real reason.

## 6. Credentials travel in headers

**Was:** four call sites sent the access token in the URL, where it reaches access logs, proxy logs and exception
messages.

| Site | Change |
|---|---|
| `providers/whatsapp_cloud_service.rb` `message_templates` | `headers: api_headers` — the Bearer helper already defined two methods below it |
| `providers/whatsapp_cloud_service.rb` `phone_numbers` | same, with `fields`/`limit` as proper query params |
| `facebook_api_client.rb#fetch_phone_numbers` | `headers: request_headers`, matching `fetch_all_phone_numbers` and every other read in the same class |
| `health_service.rb#fetch_graph_data` | `Authorization: Bearer` header, `fields` stays a query param |
| `business_profile_service.rb#fetch` | `Authorization: Bearer` header, `fields` stays a query param |

The first two ran on **every channel validation**, so a live credential was being written to logs routinely.

The fifth was found by the regression, not by the sweep. `Whatsapp::BusinessProfileService` passed the token in a
`query:` hash rather than interpolating it into the URL string, so a text search for `?access_token=` missed it
entirely — and it runs on every health read. That is the reason the static guard added with these fixes matches
two shapes rather than one (§9).

**Two documented exceptions**, both left as they are because Meta's contract requires them:

- `/oauth/access_token` — this is the token exchange itself; there is no bearer token yet, and `client_id`,
  `client_secret` and `code` are parameters by definition.
- `/debug_token` — `input_token` is the subject being inspected rather than a credential, and Meta passes the
  authorizing app token alongside it.

Both now carry a comment saying so, so the next audit does not re-flag them.

Nothing logs a credential-bearing URL: the diagnosis prints the callback override as host and path only, because an
`override_callback_uri` can carry a verify token in its query string.

## 7. What was deliberately NOT changed

**The URL fallback stays unreachable for Cloud deliveries.** An audit called
`find_channel_by_url_param` dead code for `whatsapp_business_account` payloads and suggested reviving it. It was
tried, and `spec/jobs/webhooks/whatsapp_events_job_spec.rb:44` immediately proved it wrong: one Meta app serves
many numbers, and the URL is whatever the phone-level callback override was registered with, so falling back would
file one number's customer message under a different channel's inbox. Refusing the payload and reporting it loudly
is correct. The comment now says why, so the next audit does not reach the same wrong conclusion.

**Signature verification was not weakened.** A blank `WHATSAPP_APP_SECRET` with no channel-level secret means
there is nothing to verify against and the controller refuses every payload with 401. That is correct, and the fix
is configuration, not code: the diagnosis reports it as the top-priority failure. Two regressions pin that
verification stays enforced and that a blank secret refuses everything.

**`prompt_reauthorization!`'s side effects were left alone.** The disconnect email and the websocket event are
useful signals, already guarded against repetition.

## 8. Deferred, with reasons

| Finding | Why it is deferred |
|---|---|
| `PATCH /inboxes/:id` can rewrite `business_account_id`, `phone_number_id` and `api_key` with no webhook re-registration (`after_commit … on: :create` only) | a real defect on a different surface, and nothing in the reported symptoms points at it. Changing it means deciding whether an edit should re-register, which is a product decision |
| `Message.find_by(source_id:)` is globally unscoped | verified as unable to cause any of the reported symptoms; a collision needs two accounts to share a wamid, which Meta does not do |
| A media message whose download failed logs one warning and keeps an empty Conversation | now less severe, since §1 means the message itself persists. Worth revisiting with the attachment-failure UX |
| `meta_token_verify_concern.rb:58`'s `channel.respond_to?(:app_secret)` branch can never be true | cosmetic; it drops nothing |
| The `low` queue is seventh in Sidekiq's priority list | a latency consideration, not a drop. The diagnosis reports queue depth so it can be seen |

## 9. The regression matrix

All twenty required regressions live in `spec/requests/whatsapp/inbound_reliability_spec.rb` — 37 examples, green —
except where an existing spec already owned the behaviour, in which case it is cited rather than duplicated.

| # | Required test | Example |
|---|---|---|
| 1 | webhook setup error does not look successful | `raises from the bang version the explicit callers use`; `returns false from the after_commit version instead of nil`; `propagates out of the embedded signup service` |
| 2 | setup error produces truthful channel/operator state | `latches the channel, reports to the exception tracker and logs a structured line` |
| 3 | reauthorization-required inbound behaviour | `persists an inbound text message on a channel awaiting reauthorization` |
| 4 | plain inbound message preservation where architecturally valid | same example, asserting content and `source_id` survive |
| 5 | a media/API auth failure does not erase the whole inbound event | `persists the message and its caption with no attachment` |
| 6 | correct authorization-error threshold semantics | `latches only once the threshold is reached`; the three `media authorization errors` examples; `does not latch the channel on a single non-OAuth media failure` |
| 7 | the supported reauthorization clears the latch | `is cleared by the supported reauthorization path` |
| 8 | stale latch behaviour | `does not suppress inbound while it is still set` |
| 9 | missing app secret | `refuses every payload when no app secret is configured` |
| 10 | webhook signature remains enforced | `rejects a payload whose signature does not match`; `accepts a correctly signed payload` |
| 11 | dedup lock released on success | `is released once the message is persisted` |
| 12 | dedup lock released on failure | `is released when ingestion raises, so a redelivery can still succeed`; `lets Meta's redelivery succeed after a failed attempt` |
| 13 | duplicates still suppressed | `still suppresses a duplicate delivery of a message it already persisted` |
| 14 | manual retry preserves the useful Meta error | `preserves the original Meta error after the retry clears it` |
| 15 | no credential-bearing URL | `sends the token as a bearer header on a template read, not as a query value`; `keeps credential query parameters out of the WhatsApp request construction`; `limits credential parameters to the two endpoints Meta requires them on` |
| 16 | callback source / override selection | the five `callback source and override selection` classification examples, plus `refuses a Cloud payload whose metadata matches no channel, rather than trusting the URL` |
| 17 | the 24-hour local rejection is distinguished from a Meta rejection | `fails a plain reply locally, without calling Meta, and says why` |
| 18 | an approved template bypasses the 24-hour plain-text restriction | `lets an approved template through the closed window` |
| 19 | a persisted inbound message opens reply eligibility | `opens reply eligibility for the conversation it creates`; `leaves a conversation with no inbound message outside the window` |
| 20 | no second ingestion engine | `routes inbound through the one existing job and service` |

Two of these are worth naming as more than box-ticking.

**#15's static guard is not a grep.** A search for the string `access_token` flags four innocent Ruby keyword
arguments, and a guard that cries wolf teaches the next reader to ignore it. It matches two precise shapes
instead — an interpolated URL query parameter, and an HTTParty `query:` hash holding a credential — which is
exactly what a credential-bearing request looks like and nothing else. The companion example pins that
`FacebookApiClient` still carries **exactly two** credential parameters, so the documented exceptions cannot
quietly become three.

**#5 is the example that justifies §1.** It posts a real image payload, stubs Meta's media read to 401, and
asserts the message, its `source_id` and its caption all persist with no attachment, and that the channel is not
latched. That is the architectural claim of this whole fix, executed rather than argued.
