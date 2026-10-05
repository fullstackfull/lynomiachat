# 01 — Channel identity (P5 Part A)

Where every piece of the real channel's identity lives, so the operator's diagnosis run can be read against a map
rather than guessed at.

---

## 1. The records, and what holds what

A WhatsApp channel in this product is three rows and one JSON blob:

| Thing | Where it lives |
|---|---|
| account | `inboxes.account_id` |
| inbox | `inboxes`, `channel_type = 'Channel::Whatsapp'`, `channel_id` → the channel row |
| channel | `channel_whatsapp`, with `phone_number`, `provider`, `provider_config` |
| WABA id | `provider_config['business_account_id']` |
| phone number id | `provider_config['phone_number_id']` |
| access token | `provider_config['api_key']` |
| app secret (per-channel) | `provider_config['app_secret']` — optional; falls back to the installation's `WHATSAPP_APP_SECRET` |
| webhook verify token | `provider_config['webhook_verify_token']` — per-number handshake |
| how it was connected | `provider_config['source']` — e.g. `embedded_signup` |

`provider` is `whatsapp_cloud` for Meta's Cloud API and `default` for 360dialog. **This matters for signature
verification**: `Webhooks::WhatsappController#meta_signature_verification_required?` returns true only for
`whatsapp_cloud` (or when no channel can be resolved at all), because 360dialog does not send Meta's signature.

## 2. The installation-wide settings that affect it

| Config | Read by | Effect when blank |
|---|---|---|
| `WHATSAPP_APP_SECRET` | `Webhooks::WhatsappController#meta_app_secrets` | with no per-channel `app_secret` either, **every inbound webhook is answered 401** |
| `WHATSAPP_APP_WEBHOOK_VERIFY_TOKEN` | `#app_level_token?` | the app-level callback handshake (`/webhooks/whatsapp`, no number in the path) fails |
| `WHATSAPP_APP_ID` | `Whatsapp::FacebookApiClient#build_app_access_token`, token exchange | `debug_token` cannot be built; subscription comparisons cannot be made |
| `WHATSAPP_API_VERSION` | every Graph call | falls back to `Whatsapp::FacebookApiClient::DEFAULT_API_VERSION` = **`v24.0`** |
| `INACTIVE_WHATSAPP_NUMBERS` | `#inactive_whatsapp_number?` | nothing; when it *contains* the number, inbound is answered **422** |
| `FRONTEND_URL` | callback URL construction | Meta has nowhere correct to call |

## 3. The two callback routes

```ruby
# config/routes.rb:678-679  — per number
get  'webhooks/whatsapp/:phone_number', to: 'webhooks/whatsapp#verify'
post 'webhooks/whatsapp/:phone_number', to: 'webhooks/whatsapp#process_payload'

# config/routes.rb:684-685  — app level, no number in the path
get  'webhooks/whatsapp', to: 'webhooks/whatsapp#verify'
post 'webhooks/whatsapp', to: 'webhooks/whatsapp#process_payload'
```

Both land on the same controller with the same signature check. They differ in two ways that matter:

1. **The verify handshake.** With a `:phone_number` the token is the channel's own
   `provider_config['webhook_verify_token']`; without one it is the installation's
   `WHATSAPP_APP_WEBHOOK_VERIFY_TOKEN`.
2. **The inactive-number guard.** `inactive_whatsapp_number?` returns false immediately when `params[:phone_number]`
   is blank, so **the app-level route is not subject to it** and the per-number route is.

The app-level route exists because template-status webhooks are delivered there rather than per number.

## 4. How the channel is resolved from a payload

`Webhooks::WhatsappController#whatsapp_channel` tries two things, in this order:

```ruby
@whatsapp_channel ||= whatsapp_business_payload_channel ||
                      Channel::Whatsapp.find_by(phone_number: params[:phone_number])
```

`whatsapp_business_payload_channel` reads
`params[:entry][0][:changes][0][:value][:metadata]` and hands `display_phone_number` and `phone_number_id` to
`Whatsapp::WebhookChannelFinderService`. So the payload's own metadata wins, and the URL segment is the fallback.

**The consequence to check on the real server:** if the channel's stored `phone_number_id` does not equal the
`phone_number_id` Meta sends, the finder misses. The diagnosis task prints both the stored value and Meta's own
value for the same number, so the comparison is a glance rather than an investigation.

## 5. What the diagnosis task reports for this part

```
CHANNEL IDENTITY (P5 Part A) — inbox #<id>
ids: account_id=… inbox_id=… channel_id=…
inbox name: …
provider: "whatsapp_cloud"
stored phone_number: +9659•••01          ← masked
business_account_id (WABA): …
phone_number_id: …
provider_config keys: api_key, business_account_id, phone_number_id, source
source: "embedded_signup"
access token: fixt…ey (11 chars)          ← masked
channel-level app_secret: <blank>
webhook_verify_token: <blank>
coexistence indicators: none recorded in provider_config
  [PASS/FAIL] a secret exists to verify Meta's webhook signature
  [PASS/FAIL] the number is NOT on the inactive list
```

Phone numbers are masked as `+9659•••01` and secrets as `abcd…yz (N chars)`, so the report can be shared without
exposing either a credential or a customer.
