# 01 — The app-level webhook, corrected

## 1. What was wrong

Meta's **app-level** WhatsApp callback was registered as a phone-number-specific path:

```
https://chat.lynomia.com/webhooks/whatsapp/%2B15559655462
```

`+15559655462` is inbox **#60**, account **46** ("fatima"). Template-status events for account **6**'s WABA
`4584909965122758` were therefore being delivered down another account's inbox path.

## 2. Why that is architecturally wrong, from the code

| # | Mechanism | File | Consequence |
|---|---|---|---|
| 1 | `valid_token?` branches on `params[:phone_number].blank?` | `app/controllers/webhooks/whatsapp_controller.rb` | with a number in the path it verifies **that channel's** token, not the installation token |
| 2 | `process_payload` gates on `inactive_whatsapp_number?(params[:phone_number])` | same | **account 46's number decides** whether account 6's template events are accepted |
| 3 | the template handler keys on `entry[].id`, the WABA id | `custom/app/jobs/custom/webhooks/whatsapp_events_job.rb` | it needs no phone number at all, so the number in the path is pure liability |

Mechanism 2 is not hypothetical: it is exactly the Sep 29 `Inactive WhatsApp channel: unknown - +15559655462`
drop that lost a real `APPROVED` event (`00` §6).

## 3. The correct endpoint, and why no number belongs in it

```
config/routes.rb:684-685
  get  'webhooks/whatsapp', to: 'webhooks/whatsapp#verify'
  post 'webhooks/whatsapp', to: 'webhooks/whatsapp#process_payload'
```

The shared route already existed. `Custom::Webhooks::WhatsappEventsJob#perform` intercepts
`message_template_status_update` **before** the parent's channel resolution and routes by WABA id — its own comment
states the reason: *"a WABA-scoped template payload carries no metadata and no phone number at all."*

**Correct value: `https://chat.lynomia.com/webhooks/whatsapp`**

## 4. The two writes, in the order they had to happen

### Write 1 — `WHATSAPP_APP_WEBHOOK_VERIFY_TOKEN`

The supported mechanism, verified at `config/installation_config.yml:179-184` (`locked: false`, with a display
title, so it is an intended Super Admin field). Before: **BLANK**, proven live by `GET /webhooks/whatsapp → 401`.

Live result after storing:

```
stored in installation_configs : 64 chars
readable by the controller     : true
app_level_token? would accept  : true
channel token UNTOUCHED        : true
```

The handshake was verified **in-process**, reproducing `app_level_token?`'s `secure_compare` against
`GlobalConfigService.load`, deliberately *not* by an HTTP probe: `hub.verify_token` travels in a query string and
would have been written into the nginx and Rails logs.

This had to come first. `app_level_token?` requires `configured.present?`, so while the key was blank Meta's
verification `GET` would have been answered 401 and Meta would have refused to save the new URL.

### Write 2 — the Meta App-level callback

Changed in the Meta App dashboard, nothing else touched:

| | |
|---|---|
| from | `https://chat.lynomia.com/webhooks/whatsapp/%2B15559655462` |
| to | `https://chat.lynomia.com/webhooks/whatsapp` |

## 5. Verification

| Check | Result |
|---|---|
| Meta app-level verification GET | **`GET /webhooks/whatsapp → 200`** — handshake **PASS** |
| phone-level webhook still healthy | **`POST /webhooks/whatsapp/+965… → 200`** |
| inbound to inbox #77 still arrives | yes |
| delivery/read statuses still arrive | yes — e.g. `OUT msg=1672 status=1` after the change |
| cross-account routing | none |
| template-status events resolve by WABA | by construction (§3), confirmed by no `unroutable_payload` |
| new traffic to chat2 | none |
| new `[WHATSAPP INGEST]` / `Inactive WhatsApp channel` / `unroutable_payload` | none in the post-change window |

## 6. What was deliberately not touched

The phone-level override, the channel's own `webhook_verify_token`, the WhatsApp access token, the Meta app secret,
the Graph API version (**v22.0**, set in `installation_configs`), signature verification, Redis, the number
registration, WABA ownership, and Coexistence.
