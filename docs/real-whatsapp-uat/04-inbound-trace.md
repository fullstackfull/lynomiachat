# 04 — The inbound trace (P5 Parts E, F)

P5 Part E asks for a live inbound test and insists the trace not stop at *"the webhook endpoint returned 200"*.
The live half is **BLOCKED** here — no real phone, and this container is not Meta's callback destination. What
follows is the path traced statically and exercised by tests, with the twelve questions answered and a note on
which answer needs the real server.

---

## 1. The twelve steps, and where each is now observable

| # | P5's question | Where it is decided | Observable? |
|---|---|---|---|
| 1 | Does Meta attempt to POST? | Meta's side | **real server only** — Meta's Webhooks dashboard delivery stats, or the absence of any request in the access log |
| 2 | Does the request reach the server? | the host's access log | **real server only** |
| 3 | What status does Lynomia return? | `Webhooks::WhatsappController` | 200, 401, 422 or 500 — §2 |
| 4 | Does Rails receive the webhook? | the route | yes once 3 is non-401 |
| 5 | Does the job enqueue? | `process_payload` | yes, unless the tracking-events gate fires |
| 6 | Does the job execute? | Sidekiq on the `low` queue | the diagnosis reports process liveness and queue depth |
| 7 | Does the payload reach the handler? | `Webhooks::WhatsappEventsJob#perform` | **now reported** — a refusal logs `[WHATSAPP INGEST]` |
| 8 | Is the right inbox/channel resolved? | `Whatsapp::WebhookChannelFinderService` | **now reported** — `event=unroutable_payload` names the `phone_number_id` |
| 9 | Is a Contact resolved or created? | `ContactInboxSourceIdResolver` | DB |
| 10 | Is a Conversation created or found? | `set_conversation` | DB |
| 11 | Is an incoming Message persisted? | `create_messages` | DB, and the diagnosis counts incoming messages per inbox |
| 12 | Does the realtime update reach the frontend? | ActionCable | **real server only** |

Steps 7 and 8 are the ones this phase changed. They were previously a single `Rails.logger.warn` that could not
distinguish "no channel matched" from "the channel is latched" from "the account is suspended" — see `08`.

## 2. Every way the controller can answer, and which ones are silent

```ruby
before_action :verify_meta_signature!, only: :process_payload

def process_payload
  if inactive_whatsapp_number?
    render json: { error: 'Inactive WhatsApp number' }, status: :unprocessable_entity and return
  end
  return head :ok if tracking_events_only?

  Webhooks::WhatsappEventsJob.perform_later(params.to_unsafe_hash)
  head :ok
end
```

| Response | When | Visible how |
|---|---|---|
| **401** | the signature is missing, malformed, or matches no configured secret | `Rails.logger.warn("Rejected Meta webhook with …")`. **This is the quiet one** — nothing else records it, and from Meta's side it is a delivery failure statistic |
| **422** | the URL's number is on `INACTIVE_WHATSAPP_NUMBERS` | `Rails.logger.warn("Rejected webhook for inactive WhatsApp number: …")` |
| **200, no enqueue** | every change in the delivery is `field: 'tracking_events'` | nothing — correct, this is noise Meta sends and the gate is tight (it needs *all* changes to be tracking events) |
| **200, enqueued** | the normal path | the job then decides |
| **500** | Redis or Sidekiq unavailable, so `perform_later` raises | Meta retries, which is the right outcome: the event was not durably accepted |

That last row is the answer to P5's webhook-HTTP question. The controller does **not** fake durable acceptance: if
the enqueue raises, the 500 propagates and Meta redelivers. It also does not return 500 to force a retry for an
event it *has* accepted — once `perform_later` succeeds, the 200 is truthful.

## 3. Signature verification, in full

```ruby
def valid_meta_signature?
  signature = request.headers['X-Hub-Signature-256']
  return false unless signature&.start_with?('sha256=')

  meta_app_secrets.any? do |secret|
    next false if secret.blank?
    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, request.raw_post)}"
    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end
end
```

Verified over `request.raw_post` — the exact bytes, which is correct — with `secure_compare`. Required whenever
`whatsapp_channel.blank? || provider == 'whatsapp_cloud'`, so only 360dialog (`provider == 'default'`) is exempt.

The candidate secrets are the channel's `app_secret` / `app_secret_key` / `client_secret` / `api_secret` from
`provider_config`, plus the installation's `WHATSAPP_APP_SECRET`. **With none configured, the loop finds nothing
to compare and returns false, so every inbound webhook is answered 401.** Two regressions pin this
(`spec/requests/whatsapp/inbound_reliability_spec.rb`): one that a mismatched signature is refused, one that a
blank secret refuses everything. It is not weakened; it is reported.

Note that nothing in the product ever writes `provider_config['app_secret']` — neither
`Whatsapp::ManualSetupService` nor the manual-setup controller's permitted params include it — so in practice the
installation-wide `WHATSAPP_APP_SECRET` is the only reachable secret, and it has no default value in
`config/installation_config.yml`.

## 4. Channel resolution, and the one way it can go wrong

For a `whatsapp_business_account` payload the metadata is authoritative:

```ruby
metadata = params[:entry][0][:changes][0][:value][:metadata]
Whatsapp::WebhookChannelFinderService.new(
  display_phone_number: metadata[:display_phone_number],
  phone_number_id: metadata[:phone_number_id]
).perform
```

and the finder requires a **strict match** on `provider_config['phone_number_id']`. The URL segment is
deliberately not used as a fallback here — see `09` §7 for why reviving it would misattribute messages between
numbers on the same Meta app.

So the failure mode is precise: **a stored `phone_number_id` that is not the one Meta sends** means no channel
resolves, and every inbound message is refused. The diagnosis prints the stored value and Meta's own value for the
same number, so the comparison is a glance. The refusal now logs:

```
[WHATSAPP INGEST] event=unroutable_payload phone_number_id=<what Meta sent> url_phone_number=<the URL segment>
                  detail=no Channel::Whatsapp has this phone_number_id in provider_config
```

## 5. Sidekiq semantics for a dropped event

P5 asks which failure class each outcome should be. As implemented:

| Class | Behaviour | Why |
|---|---|---|
| unroutable payload (no channel for the `phone_number_id`) | **success, reported** | retrying cannot help — the id will never match. An infinite retry would repeat the drop and flood the queue |
| suspended account | **success, reported** | a product decision, not a transient fault |
| lock contention | **retryable**, `retry_on LockAcquisitionError, wait: 2s, attempts: 20` | genuinely transient; the budget deliberately exceeds the 30s lock TTL |
| an exception during ingestion | **retryable**, Sidekiq's default | and now safe to retry, because the dedup lock is released in an `ensure` (`09` §3) |
| media download failure | **message still persisted**, attachment skipped | the partial state the architecture already supported |
| enqueue failure in the controller | **500 to Meta** | the event was not durably accepted, so Meta should redeliver |

No infinite retries, and nothing retried that cannot succeed.

## 6. What the live test will add

The command, and the exact fields to return, are in `10`. What the real run establishes that this trace cannot:

1. whether Meta is attempting delivery at all (step 1)
2. the HTTP status the real host returns (step 3) — in particular whether it is 401
3. whether a Sidekiq process is consuming `low` (step 6)
4. whether the stored `phone_number_id` matches Meta's (step 8)
5. whether the realtime update reaches the dashboard (step 12)

Everything between 7 and 11 is now covered by tests and, on a real failure, by a structured log line naming which
step refused and why.
