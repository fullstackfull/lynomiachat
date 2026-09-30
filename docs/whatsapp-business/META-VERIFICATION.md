# واتساب بزنس: Meta verification (Phase 15)

**How each item was verified**

1. **Meta official documentation.** `developers.facebook.com` is blocked by this environment's network policy (HTTP 403 for both the container and the web-fetch tool). The Meta pages were therefore read through the web-search tool's summaries of the **official pages**; the URLs are listed below. Where a summary was ambiguous, the item stays open.
2. **Chatwoot 4.18.0 upstream implementation**, with file and line evidence.
3. **Runtime staging test** against an in-process Meta Graph simulator. This is **not** a real Meta account: it proves Lynomia's side of the contract, not Meta's behaviour.

**Official pages used**

- Onboard WhatsApp Business app users: https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users/
- Embedded Signup implementation: https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/implementation/
- Phone number deregister API: https://developers.facebook.com/documentation/business-messaging/whatsapp/reference/whatsapp-business-phone-number/phone-number-deregister-api
- `smb_message_echoes` webhook reference: https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/smb_message_echoes
- Reconnect offboarded coexistence clients: https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/reconnect-offboarded-coexistence-clients/

| # | Item | Meta docs | Chatwoot 4.18 | Staging | Status |
|---|---|---|---|---|---|
| 1 | Completion payload | A normal flow sends `FINISH` with `phone_number_id`, `waba_id` and `business_id`. A Business-App flow sends `event: FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING` (session info v3) with `waba_id` and other asset IDs. | `whatsapp/utils.js:38-40,70-75` classifies both events; `useWhatsappEmbeddedSignup.js:62-75` sends `is_coexistence` | Frontend spec: the Coexistence credentials reach the same store action | **CLOSED** |
| 2 | WABA ID | Meta converts the Business App account into a Messaging account and **keeps the same ID**, returned in `waba_id` | `business_account_id = waba_id` (`channel_creation_service.rb`) | Stored `business_account_id` = the WABA from the callback | **CLOSED** |
| 3 | `business_id` | Not needed for the Business-App completion | Optional everywhere (`authorizations_controller.rb:76-83`, `embedded_signup_service.rb:92-99`) | Onboarding with `code` + `waba_id` only → 200 | **CLOSED** |
| 4 | `phone_number_id` | May be absent in the Business-App completion (the summary lists `waba_id` + "other asset IDs") | Strict resolution: by id if given; else the only number on the WABA; else an error (`phone_info_service.rb:36-58`) | Single number → OK; multi-number WABA without id → 422, nothing created | **CLOSED (code)** / real payload not observed |
| 5 | `/register` | "Skip the phone number registration step, as the number is already registered" | `webhook_setup_service.rb:33-38` skips `/register` when `is_coexistence`, and also when Meta reports `is_on_biz_app` | No `/register` call during onboarding | **CLOSED** |
| 6 | `subscribed_apps` | Partner app must subscribe to the WABA before a callback override | `facebook_api_client.rb:144-176`: `POST /{waba}/subscribed_apps` then the phone-level `override_callback_uri` | Both calls observed with the right callback URL | **CLOSED** |
| 7 | Webhook fields | Business-App messages sent from the phone arrive as `smb_message_echoes`, "which you must digest" | Subscribed fields `messages`, `smb_message_echoes` (+ `calls` if calling is on) | Subscription body contains both fields | **CLOSED** |
| 8 | Message echoes | Each message sent from the Business App triggers `smb_message_echoes` | Stored as outgoing in the same conversation, `external_echo`, deduplicated (`incoming_message_base_service.rb:164-179`) | Text + image echoes land in the same conversation; duplicate echo and echo of a Lynomia-sent message are not duplicated | **CLOSED** |
| 9 | Eligibility | WhatsApp Business app **≥ 2.24.17**; companion devices are unlinked at onboarding and can be re-linked (WhatsApp for Windows / WearOS unsupported); Groups API not available for these numbers; **fixed 20 msg/s throughput** | n/a | n/a | **CLOSED** (shown in the UI note). **OPEN:** per-country availability (not found in the summaries) |
| 10 | History sync | Partner may synchronise message history; "you have **24 hours** … otherwise they must be offboarded and complete the flow again" | **Not implemented** (no `history` subscription, handler, flag or `smb_app_data` call) | n/a | **OFF by design** (Phase 16). **OPEN:** whether skipping the sync has any effect beyond "no history" |
| 11 | Contact sync | `smb_app_state_sync` webhooks describe the app's contacts after a sync request; the same 24h window applies | **Not implemented** | n/a | **OFF by design**, same open question as #10 |
| 12 | Deregister on inbox delete | "You cannot use the deregister endpoint" for a number in use with both Cloud API and the Business App | Teardown calls `/deregister` for embedded-signup numbers, and any error is logged and swallowed (`webhook_teardown_service.rb:6-17,41-53`) | Deleting a Business-App inbox succeeds; other tenants' WABAs are not unsubscribed | **CLOSED:** harmless. Offboarding is done from the phone app. |
| 13 | Offboarding lifecycle | Meta sends `account_offboarded` / `account_reconnected`; a client that re-registers the app is re-onboarded automatically | **Not handled** by Chatwoot 4.18 | n/a | **OPEN** (known limitation: Lynomia is not told when a business disconnects in the app) |
| 14 | Lynomia's Meta app / Configuration ID enabled for Business-App onboarding (Tech Provider) | Required | n/a | n/a | **OPEN:** account-level; check in Meta Business Manager |
| 15 | End-to-end with a real number | n/a | n/a | Only simulated | **OPEN:** needs one real WhatsApp Business App number on Lynomia's Meta app, in a staging deployment with a public HTTPS `FRONTEND_URL` |

**Remaining VERIFY-META items:** #4 (real payload), #9 (countries), #10/#11 (effect of not syncing), #13, #14, #15.
