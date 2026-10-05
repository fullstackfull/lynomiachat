# 08 — Root cause (P5 Parts F, I)

**One mechanism in this repository explains all four reported symptoms at once.** It was found by reading the code,
proven by executing it, and it is checkable on the real server in one command with no call to Meta.

It is a **code defect**, not a Meta misconfiguration. That matters: the brief's instinct was to suspect Meta-side
state, and the first pass of this phase suspected the same. The evidence points elsewhere.

---

## 1. The mechanism

```ruby
# app/jobs/webhooks/whatsapp_events_job.rb:8-14
def perform(params = {})
  channel = find_channel_from_whatsapp_business_payload(params)

  if channel_is_inactive?(channel)
    Rails.logger.warn("Inactive WhatsApp channel: #{channel&.phone_number || "unknown - #{params[:phone_number]}"}")
    return
  end
  …

# app/jobs/webhooks/whatsapp_events_job.rb:148-156
def channel_is_inactive?(channel)
  return true if channel.blank?
  # Only skip for embedded signup when reauth is required; manual flow uses API keys and should still receive webhooks
  return true if channel.reauthorization_required? && embedded_signup_channel?(channel)
  return true unless channel.account.active?

  false
end
```

`reauthorization_required?` is a **Redis key with no expiry**:

```ruby
# app/models/concerns/reauthorizable.rb
AUTHORIZATION_ERROR_THRESHOLD = 2

def reauthorization_required?
  ::Redis::Alfred.get(reauthorization_required_key).present?     # REAUTHORIZATION_REQUIRED:channel_whatsapp:<id>
end

def prompt_reauthorization!
  ::Redis::Alfred.set(reauthorization_required_key, true)         # no `ex:` — never expires
  …
end

def reauthorized!                                                 # the ONLY thing that clears it
  ::Redis::Alfred.delete(authorization_error_count_key)
  ::Redis::Alfred.delete(reauthorization_required_key)
  …
end
```

So once that flag is set on an **embedded-signup** channel:

- every inbound webhook is discarded in `perform`, before any message handling
- with **one `Rails.logger.warn`** and nothing else — no raise, no retry, no Sentry
- so Sidekiq records the job as a **success**
- and the controller has **already answered Meta `200 OK`**, so Meta never retries
- while **outbound keeps working**, because sending never consults this flag

It is cleared only by somebody completing the reauthorization flow in the dashboard. Nothing times it out, and
nothing re-checks whether the original problem is gone.

## 2. How it maps onto every reported symptom

| Reported symptom | Explained by |
|---|---|
| 1. the number appeared as "not registered on WhatsApp", now resolved | the condition that most plausibly set the flag in the first place (see §3) |
| 2. outbound to an **old** contact arrives | sending never reads the flag. Outbound is genuinely healthy |
| 3. a customer's message **does not appear** in Lynomia | the flag drops the webhook in `perform` |
| 4. outbound to a **new** contact does not arrive | a consequence of 3, not a separate fault — see `05`. No inbound row ⇒ `can_reply?` false ⇒ `SendOnWhatsappService` fails the message **locally**, without contacting Meta |

The shape "sending works, receiving does not" is the signature of this defect, because it is the only part of the
system that treats the two directions asymmetrically.

## 3. How the flag gets set — two confirmed routes

### (a) A swallowed webhook-setup failure at connect time

```ruby
# app/models/channel/whatsapp.rb:158-163
def setup_webhooks(is_coexistence: nil)
  perform_webhook_setup(is_coexistence: is_coexistence)
rescue StandardError => e
  Rails.logger.error "[WHATSAPP] Webhook setup failed: #{e.message}"
  prompt_reauthorization!
end
```

`Whatsapp::WebhookSetupService#setup_webhook` **does** re-raise on failure (`"Webhook setup failed: …"`). This
`rescue` catches it, logs it, sets the latch, and **does not re-raise**. It is an
`after_commit :setup_webhooks, on: :create`, so the inbox is already saved; the API answers `success: true`.

The result is a channel that looks connected, sends fine, and can never receive — created in exactly that state,
with nothing in the UI to say so.

**This is the most likely history for the production number**, because symptom 1 says it was previously showing as
"not registered on WhatsApp". A number in that state is precisely one whose `register`/subscribe calls fail, which
is what trips this rescue.

### (b) Two authorization errors

`AUTHORIZATION_ERROR_THRESHOLD = 2`, and `authorization_error!` latches on the second. One confirmed trigger:

```ruby
# app/services/whatsapp/incoming_message_whatsapp_cloud_service.rb:11-20
url_response = HTTParty.get(inbox.channel.media_url(…), headers: inbox.channel.api_headers)
inbox.channel.authorization_error! if url_response.unauthorized?     # ← before the success check
return unless url_response.success?
```

Two inbound **media** messages whose download returns 401 are enough to kill all inbound — including plain text —
permanently.

### A detail that matters when reading the evidence

`prompt_reauthorization!` sets the flag **without touching the error counter**. Proven in this container:

```
source="embedded_signup"
reauthorization_required?=true   error_count=0
```

So **`authorization_error_count` can be 0 on a latched channel.** Route (a) always looks like that. Do not infer
the flag from the counter; read the flag.

One more evidence trail: `prompt_reauthorization!` fires the `whatsapp_disconnect` administrator email and a
websocket reauthorization event. **If the account's admins received a "WhatsApp disconnected" email around the time
inbound stopped, that is this.**

## 4. Proven by execution, not only by reading

Run in this container against the fixture channel:

```ruby
channel = Channel::Whatsapp.first            # source == "embedded_signup"
job = Webhooks::WhatsappEventsJob.new

job.send(:channel_is_inactive?, channel)     # => false
channel.prompt_reauthorization!
job.send(:channel_is_inactive?, channel)     # => true    ← every inbound webhook now dropped
channel.reauthorized!
job.send(:channel_is_inactive?, channel)     # => false   ← and restored
```

The container's own fixture channel carries `source: "embedded_signup"`, the same value the embedded-signup flow
writes in production (`Whatsapp::ManualSetupService` writes `source: 'manual'` instead, and the guard deliberately
spares manual channels).

## 5. The check, and what it looks like

No Meta call is needed. From the diagnosis task:

```
authorization_error_count: 0 (threshold 2)
reauthorization_required: true, source is embedded_signup: true
  [FAIL] inbox #N: the channel is NOT latched into reauthorization-required
         — LATCHED — every inbound webhook is being dropped
```

```bash
bundle exec rails whatsapp:diagnose
```

If that line reads `LATCHED`, the diagnosis is finished and §6 is the fix. If it reads `latched=false`, this is not
the cause and the ranked candidates in §7 apply instead.

## 6. The fix, and the order it has to happen in

**Do not just clear the flag.** It will latch again on the next two authorization errors, or stay useless if the
subscription was never created. The order is:

1. **Confirm the Meta side is actually healthy** — `subscribed_apps` non-empty, `messages` subscribed, the callback
   Meta holds for the number matching this installation, the token valid. All four are in the same diagnosis run.
2. **Fix whatever is wrong there first**, using the existing mechanisms (`subscribe_app_to_waba`,
   `override_phone_number_callback`) through the product's own re-registration path.
3. **Then clear the latch**, by completing the reauthorization flow for that inbox in the dashboard — which calls
   `reauthorized!`, the supported path, and also clears the error counter.
4. **Re-run the diagnosis** and confirm `latched=false` and an inbound message persisting.

Step 3 is a UI action, not a code change, and it is the operator's to take. Nothing in this phase clears it for
them: P5 Rule 1 requires the proof first, and the proof needs the real server.

### The code changes this argues for, which are NOT applied in this phase

P5 Part G says implement the smallest fix only after the root cause is proven on the real system. The root cause is
proven **in the code**; that it is the active cause on the production number is not yet proven, so nothing is
changed. Recorded for the next phase, in priority order:

| # | Change | Why |
|---|---|---|
| 1 | `channel_is_inactive?` must distinguish its three cases, and log which one, with the channel id and the payload's `phone_number_id` | today "channel not found", "latched" and "account inactive" are one indistinguishable warn line. This alone would have made the diagnosis immediate |
| 2 | `Channel::Whatsapp#setup_webhooks` must not report success when setup failed | swallowing the raise creates a channel that can never receive. At minimum it should surface the failure to the connecting user |
| 3 | The latch needs an escape — a TTL, or a re-check before dropping | an unbounded flag set by a transient 401 is a permanent outage |
| 4 | `PATCH /inboxes/:id` can rewrite `business_account_id`, `phone_number_id` and `api_key` without re-registering the webhook (`after_commit … on: :create` only) | editing a channel silently breaks inbound the same way |

## 7. If the latch is NOT set — the ranked alternatives

In the order the diagnosis reports them, each with its P5 Part F class:

| Rank | Candidate | Class | How it reads |
|---|---|---|---|
| 1 | no app subscribed to the WABA | `META_SUBSCRIPTION` | `subscribed apps: 0` |
| 2 | `messages` not among the subscribed fields | `META_WEBHOOK_CONFIGURATION` | `MISSING messages` |
| 3 | stale phone-level callback override (see `03`) | `META_WEBHOOK_CONFIGURATION` | `callback Meta holds … FAIL`, with the host it actually holds |
| 4 | no app secret anywhere ⇒ 401 on every webhook | `WEBHOOK_SIGNATURE/VERIFICATION` | `NO SECRET AVAILABLE` |
| 5 | the number on `INACTIVE_WHATSAPP_NUMBERS` ⇒ 422 | `OTHER_PROVEN_CAUSE` | `LISTED AS INACTIVE` |
| 6 | stored `phone_number_id` ≠ Meta's | `PHONE_ID / WABA MISMATCH` | the two values printed side by side |
| 7 | no Sidekiq process, or `low` not consumed | `JOB_NOT_ENQUEUED` / `JOB_FAILURE` | `0 process(es)` |
| 8 | the dedup lock jammed on a message id (§8) | `JOB_FAILURE` | inbound stopped for one conversation, not all |

## 8. Other confirmed findings, not the cause here

Each survived adversarial verification, and none is this phase's symptom. Recorded so they are not re-discovered.

| Finding | Evidence |
|---|---|
| **The URL fallback is dead code for Cloud deliveries.** `find_channel_from_whatsapp_business_payload:171` always returns `get_channel_from_wb_payload` for `object == 'whatsapp_business_account'`, so `find_channel_by_url_param` never runs — despite a comment calling it "priority". Resolution depends *entirely* on a strict `provider_config['phone_number_id'] == metadata[:phone_number_id]` match | `whatsapp_events_job.rb:161-182`, `webhook_channel_finder_service.rb:19` |
| **The dedup lock is never released.** `Whatsapp::MessageDedupLock#acquire!` is `SET NX EX` with a 1-day TTL, has no release method, and nothing in `app/`, `enterprise/`, `custom/` or `lib/` deletes the key. It is taken at `incoming_message_base_service.rb:39`, *before* `set_contact` and before the write transaction — so any exception after it (a media download timeout, a validation failure) leaves that message id unprocessable for 24h, and every Meta retry is silently swallowed | `message_dedup_lock.rb:7,16-18`; `incoming_message_base_service.rb:38-48` |
| **A media message whose download Meta failed is dropped but its conversation is kept.** `error_webhook_event?` logs one warn and returns, after the Contact, ContactInbox and an empty Conversation have been committed — an empty conversation with no message | `incoming_message_base_service.rb:70-79`, `incoming_message_service_helpers.rb:75-77` |
| **Manual retry erases Meta's failure reason.** `claim_message_retry` calls `StatusUpdateService.new(message, 'sent')` — permitted because any transition out of `failed` is allowed — which nils `external_error`, then blanks `content_attributes`. A retried message reports as sent and loses the evidence | `messages_controller.rb:67-81`, `status_update_service.rb:29-33,44` |
| **Access tokens travel in URL query strings** at ~7 call sites (e.g. `whatsapp_cloud_service.rb:66,71`, `health_service.rb:87-93`), where they reach access logs and proxies, instead of the `Authorization: Bearer` header the client uses elsewhere | P5 Part S — recorded, not changed |
| **`Channel::Whatsapp#phone_number` has no E.164 format validation**, and create never cross-checks the typed number against Meta's `display_phone_number` for the submitted `phone_number_id` | `channel/whatsapp.rb:40` |
| **A dead duck-type branch** — `secrets << channel.app_secret if channel.respond_to?(:app_secret)` can never be true; no channel defines `app_secret` or has the column | `meta_token_verify_concern.rb:58` |

## 9. Verification discipline

Nine dimensions of the message path were audited and every claimed defect was then put to independent adversarial
verifiers instructed to refute it and to default to "refuted" when they could not positively confirm it from the
code.

**63 verifications: 20 confirmed, 43 refuted.** The refutation rate is the point — it is why the findings above are
worth acting on. Three verifier runs came back with a note that the safety classifier had timed out; those three
all concerned the coexistence dimension, and none of their claims is relied on above.

The two findings this phase leads with were additionally proven by **executing** the code (§4), not only by reading
it. One of my own earlier claims — that a webhook-setup failure surfaces loudly — was **wrong**, and is corrected
in `02`.
