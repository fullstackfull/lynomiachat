# 02 — WABA app subscription (P5 Part C)

P5 names this the primary suspect. This document says what the code does about subscription, what can therefore go
wrong, and how the operator reads the real answer.

**Status in this environment: BLOCKED** — reading `/{WABA-ID}/subscribed_apps` needs the real token. Nothing below
is a claim about the production WABA.

---

## 1. What the code does

`Whatsapp::WebhookSetupService#setup_webhook` → `Whatsapp::FacebookApiClient#subscribe_phone_number_webhook`, which
does **two** things in a deliberate order:

```ruby
# app/services/whatsapp/facebook_api_client.rb:149-156
def subscribe_phone_number_webhook(waba_id, phone_number_id, callback_url, verify_token, subscribed_fields: nil)
  # Subscribe app to WABA first — Meta requires it before any callback override (issue #13097).
  subscribe_app_to_waba(waba_id, subscribed_fields: subscribed_fields || WEBHOOK_DEFAULT_FIELDS)

  # Phone-level override takes precedence over WABA-level, so numbers on one WABA can route to different URLs.
  override_phone_number_callback(phone_number_id, callback_url, verify_token)
end
```

1. `POST /{WABA_ID}/subscribed_apps` with `{ subscribed_fields: [...] }`
2. `POST /{PHONE_NUMBER_ID}` with `{ webhook_configuration: { override_callback_uri:, verify_token: } }`

The fields subscribed are built in `Whatsapp::WebhookSetupService#subscribed_fields`:

```ruby
fields = %w[messages smb_message_echoes message_template_status_update]
fields << 'calls' if calls_enabled_on_waba?
```

So **`messages` is subscribed by the code** — the field Meta needs in order to post customer messages and delivery
statuses at all. `smb_message_echoes` is the Business-App side of a Coexistence number. The same list is
`Whatsapp::FacebookApiClient::WEBHOOK_DEFAULT_FIELDS`, and the diagnosis task imports that constant rather than
repeating it, so the check and the subscription cannot drift.

`calls_enabled_on_waba?` deliberately keeps `calls` if **any sibling channel on the same WABA** has voice enabled,
because `subscribed_fields` is WABA-wide: a non-calling sibling's setup would otherwise rewrite the shared
subscription and silently drop calls for a calling-enabled sibling. That is a real multi-number hazard already
handled.

## 2. What can go wrong, and whether the code would notice

> **Correction.** An earlier draft of this document said a `subscribe_app_to_waba` failure surfaces "loudly" and
> that inbox creation fails rather than appearing to succeed. **That is wrong, and the truth is worse.** The
> service does re-raise, but the model's callback swallows it. The corrected table is below, and the consequence is
> the root cause in `08`.

| Failure | Does the code notice? |
|---|---|
| `subscribe_app_to_waba` returns an error | **no.** `Whatsapp::WebhookSetupService#setup_webhook` re-raises as `"Webhook setup failed: …"`, but `Channel::Whatsapp#setup_webhooks` (`app/models/channel/whatsapp.rb:158-163`) is `rescue StandardError => e` → log → `prompt_reauthorization!`, with **no re-raise**. It is an `after_commit … on: :create`, so the inbox is already saved. The API answers success, and the channel is left **latched** — see below |
| `register_phone_number` fails | **no, deliberately.** It rescues, stores `@registration_error`, logs a warning and continues — registration is not always needed (a Coexistence number is pre-registered) |
| the subscription is later removed at Meta, outside this app | **never noticed.** Nothing re-reads `subscribed_apps` on a schedule |
| the subscription is removed by this app | `Whatsapp::FacebookApiClient#unsubscribe_app_from_waba` exists and is called when the last inbox on a WABA is deleted |

### What that rescue actually does

```ruby
# app/models/channel/whatsapp.rb:158-163
def setup_webhooks(is_coexistence: nil)
  perform_webhook_setup(is_coexistence: is_coexistence)
rescue StandardError => e
  Rails.logger.error "[WHATSAPP] Webhook setup failed: #{e.message}"
  prompt_reauthorization!
end
```

`prompt_reauthorization!` sets a Redis flag with **no expiry**. And
`Webhooks::WhatsappEventsJob#channel_is_inactive?` drops every inbound webhook for an embedded-signup channel while
that flag is set. So a webhook-setup failure at connect time does not merely fail to subscribe — it **permanently
disables inbound for that channel** and reports success. That chain is `08`.

**The gap that matters:** the code asserts the subscription **once, at setup**, and never again. There is no
periodic reconciliation. So a WABA that was correctly subscribed in the past and is not subscribed now produces
exactly the reported symptom — inbound stops, with no error anywhere in Lynomia, because Meta simply stops calling.

The one existing read is `Whatsapp::ManualWebhookStatusService#subscription_verified?`, which checks
`fetch_subscribed_apps(...).fetch('data', []).present?`. It is surfaced in the manual-setup UI, not run
automatically.

## 3. What to read, and how to read it

```bash
bundle exec rails whatsapp:diagnose
```

The relevant block:

```
WABA app subscription (/<WABA_ID>/subscribed_apps):
  subscribed apps: N
    app_id=… name="…"
    subscribed_fields: messages, smb_message_echoes, message_template_status_update
  [PASS/FAIL] at least one app is subscribed to this WABA
  [PASS/FAIL] the required webhook fields are subscribed
  [PASS/FAIL] the configured app (<WHATSAPP_APP_ID>) is the subscribed one
```

Reading the three checks:

- **no app subscribed** → Meta has nowhere to deliver and never calls the callback URL. Classify as
  `META_SUBSCRIPTION`. The fix is the existing `subscribe_app_to_waba`, reached through the product's own
  re-registration path — not a hand-rolled POST.
- **subscribed, but `messages` missing** → Meta calls for other events but never for customer messages. Classify as
  `META_WEBHOOK_CONFIGURATION`. Same fix: re-subscribe with the full field list the code already declares.
- **subscribed, but a different `app_id`** → another Meta app owns this WABA's subscription. Webhooks are signed
  with *that* app's secret and delivered to *its* callback URL, so this installation would reject them even if they
  arrived. Classify as `PHONE_ID / WABA MISMATCH` and resolve which app is meant to own the number before changing
  anything.

Note that `subscribed_fields` is **not always returned** by this endpoint; when it is absent the task says
`<not reported by this endpoint>` and skips the field check rather than inventing a failure.

## 4. What is deliberately not done here

- **Nothing is subscribed or unsubscribed.** P5 Part C says to mark a root-cause candidate and continue, and Part T
  forbids destructive Meta operations during UAT. The diagnosis is read-only by construction.
- **No second subscription mechanism was written.** `subscribe_app_to_waba` already exists, already sends the right
  field list, and is already ordered correctly against the callback override. If the fix turns out to be
  re-subscription, that is the call to make.
