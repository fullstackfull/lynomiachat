# 03 — Webhook configuration (P5 Part D)

**Status in this environment: the code side is answered below; the live read is BLOCKED** on the real token.

This document carries the finding most likely to be missed by someone checking the Meta App dashboard, so it leads
with it.

---

## 1. The code sets a phone-level callback override, and that override wins

`Whatsapp::WebhookSetupService#setup_webhook` does not only subscribe the app to the WABA. It then calls:

```ruby
# app/services/whatsapp/facebook_api_client.rb:168-181
def override_phone_number_callback(phone_number_id, callback_url, verify_token)
  HTTParty.post(
    "#{BASE_URI}/#{@api_version}/#{phone_number_id}",
    headers: request_headers,
    body: { webhook_configuration: { override_callback_uri: callback_url, verify_token: verify_token } }.to_json
  )
end
```

with

```ruby
# app/services/whatsapp/webhook_setup_service.rb:build_callback_url
"#{ENV.fetch('FRONTEND_URL', nil)}/webhooks/whatsapp/#{@channel.phone_number}"
```

Two consequences follow, and both are checkable:

**(a) The override takes precedence over the app-level webhook configuration.** The client's own comment says so:
*"Phone-level override takes precedence over WABA-level, so numbers on one WABA can route to different URLs."* That
is a feature — it is how several numbers on one WABA reach different installations — but it means **the Meta App
dashboard can show a perfectly correct callback URL while this specific number is overridden to somewhere else.**
A dashboard check is not evidence. Only reading the number's `webhook_configuration` back is.

**(b) The URL is frozen at setup time, from whatever `FRONTEND_URL` was then.** If the inbox was created while
`FRONTEND_URL` pointed at a dev tunnel, an old domain, or a staging host, Meta is still calling that, and nothing
in Lynomia will ever mention it. The number keeps working for *outbound* — which needs no callback at all — and
that is exactly the reported shape: sending works, receiving does not.

This is the single strongest candidate that a configuration review would not surface, and it costs one read to
rule in or out.

## 2. The read that answers it already exists

`Whatsapp::ManualWebhookStatusService` does precisely this comparison:

```ruby
phone_number = @api_client.fetch_phone_number(phone_number_id, fields: 'webhook_configuration')
webhook_configuration = phone_number.fetch('webhook_configuration', {})

%w[override_callback_uri phone_number whatsapp_business_account application].any? do |key|
  webhook_configuration[key] == callback_url
end
```

It checks all four places Meta can report a callback for a number, and compares each against the URL this
installation expects. The diagnosis reuses this service for the verdict rather than reimplementing it, and adds the
part it does not provide: **what Meta actually holds when the answer is no.**

```
callback configuration (Whatsapp::ManualWebhookStatusService):
  expected callback_url: https://<this installation>/webhooks/whatsapp/+<number>
  [PASS/FAIL] the callback Meta holds for this number matches this installation
  [PASS/FAIL] the WABA reports at least one subscribed app
what Meta actually holds (/<phone_number_id>?fields=webhook_configuration):
    override_callback_uri: https <host> <port> <path>
    (hosts only — an override URI can carry a verify token in its query string)
```

The actual URI is printed **as host and path only**, because an `override_callback_uri` can carry a verify token in
its query string and the report is meant to be shareable.

## 3. The webhook fields the implementation actually uses

P5 says not to assume field names. These are the ones this code declares and consumes:

| Field | Declared in | What Lynomia does with it |
|---|---|---|
| `messages` | `WebhookSetupService#subscribed_fields`, `FacebookApiClient::WEBHOOK_DEFAULT_FIELDS` | customer messages **and** delivery statuses (sent/delivered/read/failed) both arrive under this one field |
| `smb_message_echoes` | same | the Business-App side of a Coexistence number: messages the business sent from the phone app |
| `message_template_status_update` | same | Meta's approval/rejection of a template, so the Template Manager updates in seconds rather than at the next sync |
| `calls` | added conditionally | only when voice is enabled on this inbox or a sibling on the same WABA |

**`messages` carries statuses as well as messages.** That is worth stating because it collapses two of P5's
questions into one: if `messages` is missing, both inbound customer messages and all outbound delivery statuses
disappear together, which looks like two unrelated faults.

## 4. The documented asymmetry in template webhooks

From `WebhookSetupService#subscribed_fields`, verbatim:

> `message_template_status_update` … is a WABA-level field; Meta delivers it to the app's default callback URL,
> never to this channel's override.

So template-status webhooks arrive at **`/webhooks/whatsapp`** (no number in the path) while customer messages
arrive at **`/webhooks/whatsapp/+<number>`** (the override). This is why both routes exist, and why they verify
their handshake against different tokens:

| Route | Verify token |
|---|---|
| `/webhooks/whatsapp/:phone_number` | the channel's `provider_config['webhook_verify_token']` |
| `/webhooks/whatsapp` | the installation's `WHATSAPP_APP_WEBHOOK_VERIFY_TOKEN` |

A blank `WHATSAPP_APP_WEBHOOK_VERIFY_TOKEN` therefore breaks template-status delivery while leaving customer
messages alone — a narrow, specific symptom, not a general outage.

## 5. The two Lynomia-side rejections, both silent to Meta's dashboard

Before anything is enqueued, `Webhooks::WhatsappController#process_payload` can refuse the payload:

```ruby
if inactive_whatsapp_number?                      # → 422, logs a warning
return head :ok if tracking_events_only?          # → 200 with NO enqueue (correct: tracking noise)
```

and `before_action :verify_meta_signature!` can refuse it earlier still:

```ruby
# app/controllers/concerns/meta_token_verify_concern.rb
return if valid_meta_signature?
Rails.logger.warn("Rejected Meta webhook with #{signature_state} X-Hub-Signature-256: #{request.path}")
head :unauthorized                                 # → 401
```

`valid_meta_signature?` needs **at least one non-blank secret** to match: the channel's `app_secret` (or
`app_secret_key`/`client_secret`/`api_secret`), else the installation's `WHATSAPP_APP_SECRET`. With none configured
the loop finds nothing to compare and returns false, so **every inbound webhook is answered 401**, with nothing but
a log line to show for it.

In Meta's Webhooks dashboard this appears as a delivery failure rate, not as a Lynomia error — which is why it is
worth checking from this side first. The diagnosis reports it as the check *"a secret exists to verify Meta's
webhook signature"*.

Note the asymmetry: the inactive-number guard returns early **only when `params[:phone_number]` is present**, so it
applies to the per-number route and not to the app-level one.

## 6. Classification, if this part is the cause

| Observation | P5 Part F class |
|---|---|
| `callback_configured` false, override points elsewhere | `META_WEBHOOK_CONFIGURATION` |
| no app subscribed to the WABA | `META_SUBSCRIPTION` |
| 401 in the logs with a blank app secret | `WEBHOOK_SIGNATURE/VERIFICATION` |
| 422 in the logs, number on the inactive list | `OTHER_PROVEN_CAUSE` (an installation setting, not Meta) |
| Meta reports delivery attempts that never reach the host | `CALLBACK_NOT_REACHABLE` |
