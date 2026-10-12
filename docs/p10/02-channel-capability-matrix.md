# P10.1 — Channel capability matrix

Twelve channels, read from the code rather than from what Chatwoot upstream supports. Every row here is a
repository fact; where the repository says nothing, this document says nothing rather than guessing. Compiled
from a per-channel read of the model, the connect flow, the send and receive paths, the webhook, the identity
field, the secret storage and the test coverage, then reconciled against `Channels::Capability`, which is the
machine-readable form of the first four columns.

---

## 1. The matrix

| channel | model / table | identity in `contact_inboxes.source_id` | auth | health this fork can see | readiness |
| --- | --- | --- | --- | --- | --- |
| Website (web widget) | `Channel::WebWidget` / `channel_web_widgets` | server-minted `SecureRandom.uuid` — a **browser session**, not a person | none (website_token + optional HMAC) | nothing to report: no provider | PRODUCTION_CAPABLE |
| API | `Channel::Api` / `channel_api` | whatever the client sends, else a minted uuid | self-issued identifier + optional HMAC | nothing to report: no provider | PRODUCTION_CAPABLE |
| WhatsApp | `Channel::Whatsapp` / `channel_whatsapp` | the phone `wa_id`, `+` stripped | bearer `provider_config['api_key']` (Cloud) or 360dialog key | reauth latch **and** `phone_number_health` jsonb | PRODUCTION_CAPABLE |
| Email | `Channel::Email` / `channel_email` | the sender's email address | IMAP/SMTP password, or Google / Microsoft OAuth | reauth latch (both variants) | CAPABLE_PENDING_CREDENTIALS |
| Facebook | `Channel::FacebookPage` / `channel_facebook_pages` | Messenger PSID | Facebook Login, page access token | reauth latch | CAPABLE_PENDING_CREDENTIALS |
| Instagram | `Channel::Instagram` / `channel_instagram` | IGSID | OAuth2, `access_token` + `expires_at` | reauth latch **and** a real token expiry | CAPABLE_PENDING_CREDENTIALS |
| TikTok | `Channel::Tiktok` / `channel_tiktok` | the TikTok **conversation id** (see §3) | OAuth2, access + refresh token with both expiries | reauth latch **and** a refresh-token expiry | CAPABLE_PENDING_CREDENTIALS |
| Telegram | `Channel::Telegram` / `channel_telegram` | Telegram numeric user id | one bot token | **nothing** | PRODUCTION_CAPABLE |
| LINE | `Channel::Line` / `channel_line` | LINE `userId` | channel id + secret + token | **nothing** | CAPABLE_PENDING_CREDENTIALS |
| Twilio SMS/WhatsApp | `Channel::TwilioSms` / `channel_twilio_sms` | `+E164`, or `whatsapp:+E164` | account SID + auth token, or API key SID | an on-demand probe that stores nothing (§4) | PRODUCTION_CAPABLE |
| Bandwidth SMS | `Channel::Sms` / `channel_sms` | `+E164`, untransformed | HTTP Basic from `provider_config` | **nothing** | PARTIAL (§5) |
| X (Twitter) | `Channel::TwitterProfile` / `channel_twitter_profiles` | Twitter numeric user id | OAuth 1.0a via the `twitty` gem | **nothing** | PARTIAL (§6) |

Readiness words mean exactly this: PRODUCTION_CAPABLE — the paths are complete and nothing in the code blocks
it; CAPABLE_PENDING_CREDENTIALS — complete, but it cannot be exercised here without a real provider credential,
so it stays PENDING REAL UAT; PARTIAL — defects are in the code, not in the configuration, and supplying
credentials would not make it whole.

### Identity, restated as the thing that matters

Four of the twelve put a **customer-identifying value** in `source_id` (WhatsApp, Email, Twilio, Bandwidth:
phone or email). Six put a **provider-scoped opaque id** there (Facebook, Instagram, TikTok, Telegram, LINE, X)
— meaningful to that provider and to nothing else. Two put a **session token** there (the web widget, and the
API channel when the client supplies nothing).

That split is why P10 did not try to unify `source_id`: a provider-scoped id cannot be normalized into a phone
number, and normalizing a session token would be meaningless. What P10 unified instead is the layer above —
`contacts`' own phone and email plus `contact_identities` — which is where the values that CAN be compared live
(docs/p10/03-unified-customer-identity.md).

## 2. Who reports their own health, and who does not

| health source | channels | what it is |
| --- | --- | --- |
| reauth latch (`Reauthorizable`) | WhatsApp, Email, Facebook, Instagram, TikTok | a Redis flag + counter, and since P9 a durable `operations_signals` row on each state change |
| real token expiry on the row | Instagram (`expires_at`), TikTok (`refresh_token_expires_at`) | a timestamp, used by the refresh services and — before P10 — by nothing else |
| the provider's own health | WhatsApp (`phone_number_health`, `_checked_at`, `_error`) | `Whatsapp::HealthService` stores status, quality rating, messaging tier |
| nothing | Telegram, LINE, Twilio, Bandwidth SMS, X | no `Reauthorizable`, no status column, no signal — a failure shows on the MESSAGE and nowhere else |
| nothing to report | Website, API | no external provider; these cannot be disconnected |

`Channels::Capability` is this table in code, and `spec/services/channels/capability_spec.rb` asserts each claim
against the thing that would produce it: the `Reauthorizable` include list, the presence of an `expires_at`
column, the presence of `phone_number_health`. A channel added later with no entry fails that spec rather than
quietly rendering as healthy.

## 3. TikTok: every conversation used to create a new customer

**The defect.** `Tiktok::MessageService` passes `content[:conversation_id]` as the builder's `source_id`
(`app/services/tiktok/message_service.rb:34` → `app/services/tiktok/messaging_helpers.rb:4-9`). The customer's
actual TikTok user id goes only into `contacts.additional_attributes['social_tiktok_user_id']`
(`messaging_helpers.rb:19-27`), and nothing ever read it back. `ContactInboxWithContactBuilder#find_contact`
matches on identifier, email and phone — TikTok supplies none of the three — and its cross-channel `source_id`
branch is gated to `Channel::Instagram`. So **a new TikTok conversation created a brand-new Contact for a
customer the account already had**: one human, one channel, as many contacts as conversations.

**The fix.** A third fallback in `Custom::ContactInboxWithContactBuilder`: for a TikTok inbox, look the contact
up by the `social_tiktok_user_id` the payload already carries. It is an exact match on a provider-issued id, so
it is as deterministic as the `source_id` match itself — nothing is guessed. A partial expression index
(`custom/db/migrate/20261009130000_add_social_identity_index_to_contacts.rb`) makes it an index probe rather
than a sequential scan, and holds nothing on an account with no TikTok inbox.

`source_id` is deliberately left as the conversation id: `find_conversation` keys on it
(`messaging_helpers.rb:29-39`) and the reply path depends on it, so changing it would mean migrating existing
rows and rewriting the send path on a channel there are no credentials to test against.

**What the fix does not do.** It prevents new duplicates. Contacts already duplicated by this remain
duplicated; joining them is a merge, which P10.3 made non-destructive and auditable
(docs/p10/04-contact-merge-linking.md). No backfill is proposed and none is run.

**Status: PENDING REAL UAT.** There is no TikTok credential here, so the fix is proven by spec
(`spec/builders/contact_inbox_with_contact_builder_identity_spec.rb`, six examples) and against the payload
shape the repository's own TikTok specs use.

### Also found on TikTok, recorded and NOT acted on

These are real and they are out of P10's scope; each needs a provider credential to verify and a channel-owner
decision. They belong in the P-FINAL security audit, not in a blind fix here:

- Nothing in the TikTok path calls `authorization_error!`. A 401 from the send endpoint raises a bare
  `RuntimeError`, is caught, and marks one message failed; the only route to the latch is
  `Tiktok::TokenService:12`, which fires exclusively when the **refresh** token has also expired.
  P10's connection state reads `refresh_token_expires_at` directly, which is why an expired TikTok
  authorization is now visible without waiting for that one path.
- `Tiktok::AuthClient#webhook_callback` and `#update_webhook_callback` exist and have **no callers**, so
  connecting an inbox does not subscribe the webhook.
- The OAuth `state` is a bespoke JWT with no `exp` claim, while every other OAuth channel uses the 15-minute
  signed GlobalID from `OauthAuthorizationController`.
- The webhook replay guard rejects only `delay > 5`, so a future timestamp yields a negative delay and passes.

## 3a. WhatsApp inbound routing keys on the phone number, not on Meta's id

Recorded, **not changed**. `Whatsapp::WebhookChannelFinderService#perform` resolves the channel by
`phone_number`, derived from Meta's `display_phone_number`:

```ruby
candidates = [Channel::Whatsapp.find_by(phone_number: "+#{digits}"), channel_by_normalized_number]
candidates.compact.find { |channel| channel.provider_config['phone_number_id'] == @phone_number_id }
```

`phone_number_id` — Meta's own stable identifier for the number — is only a post-hoc **filter** over the
candidates the phone lookup produced; it is never queried. So a channel whose `phone_number_id` matches exactly,
but whose stored `phone_number` differs from Meta's `display_phone_number` in a way the country normalizers do
not reconcile, is reported `unroutable_payload` and the message is dropped. `docs/real-whatsapp-uat/01-channel-identity.md`
§4 already flags the mirror-image case (a stored `phone_number_id` that does not match Meta's) and the
diagnosis task prints both values; this is the same fragility from the other direction.

**Why P10 does not change it.** This is the inbound path of the channel production actually runs, it cannot be
exercised without a real Meta webhook, and the WhatsApp boundary for this phase is explicit. The candidate fix
is a direct lookup on `provider_config->>'phone_number_id'` **before** the phone candidates, with the phone
lookup kept as the fallback — additive, and it would need an index on that jsonb key plus a real webhook UAT.
Carried forward with the other pending WhatsApp items.

## 3b. Voice calling is wired in the dashboard to endpoints that do not exist

Recorded, **not fixed**, and verified first-hand rather than taken from a report.
`app/javascript/dashboard/api/inboxes.js` posts to four inbox endpoints:

```
POST .../inboxes/:id/enable_whatsapp_calling
POST .../inboxes/:id/disable_whatsapp_calling
POST .../inboxes/:id/set_inbound_calls
POST .../inboxes/:id/set_call_recording
```

None of the four has a route in `config/routes.rb` and none has a controller action — `grep` for the route
names and for `def enable_whatsapp_calling` (and its three siblings) in `app/controllers/` both return nothing.
`InboxPolicy` does declare all four, and `_inbox.json.jbuilder` serializes `voice_enabled`,
`inbound_calls_enabled`, `recording_enabled` and `transcription_enabled`, so the surface looks present from
every side except the one that matters.

Consequences, as they actually land:

- The two **connect** flows that call it (`CloudWhatsapp.vue`, `WhatsappEmbeddedSignup.vue`) wrap the call in
  `try/catch` and show an alert, so a WhatsApp number still connects; the operator is told calling could not be
  enabled.
- The three **settings** surfaces that call it — `WhatsappCallingPage.vue`, `VoiceConfigurationPage.vue`,
  `CallRecordingSettings.vue`, all rendered from `Settings.vue` — have no such fallback for their primary
  action, so those toggles do not work.

**Why P10 does not fix it.** Voice is not channel identity and not channel health; making it work means adding
four controller actions, four routes and a provider method that does not exist — a new feature, on a surface
with no provider credential here to exercise it. The decision is implement-or-hide and it belongs to whoever
owns voice. Carried forward as a known broken surface.

## 4. Twilio: a probe that stores nothing

`Twilio::HealthService#perform` returns `status`, `account`, `sender`, `voice_enabled` and `webhooks` and
**writes nothing** — no column, no Redis key, no row. The inbox settings page calls it on demand. So Twilio's
connection state is `unknown`, and that is by design rather than by omission: making `connection_state` call it
would put an outbound HTTP request inside every inbox serialization. Recorded here so the gap is a decision.

## 5. Bandwidth SMS is PARTIAL, and why

Four defects are in the code, not the configuration:

1. **Every delivery receipt raises.** `app/jobs/webhooks/sms_events_job.rb:19` passes `channel:` to a service
   whose `pattr_initialize [:inbox!, :params!]` rejects unknown keys, and it passes the nested `params[:message]`
   where the service reads the top-level envelope. `sent`/`delivered`/`failed` is never persisted.
2. **The webhook is unauthenticated** and picks the tenant from a body field (`params[:to]`), so anyone who
   knows a configured number can inject inbound messages into that account.
3. **Batched webhooks lose events** — only `params['_json']&.first` is enqueued.
4. **No durable health state of any kind**, so a revoked key looks healthy indefinitely.

(4) is now visible: the channel reports `unknown` instead of green. (1)–(3) are untouched by P10 — they are a
channel repair with a security component, they need a Bandwidth account to verify, and (2) is a tenant-isolation
issue that belongs in the P-FINAL security audit with the evidence above. **Recorded, not fixed.**

## 6. X (Twitter) is PARTIAL, and is effectively retired

The send path, receive path and OAuth 1.0a round trip all exist and are specced. What is gone is the way in:
`ChannelList.vue` has no X entry, `inboxMgmt.json` has no `TWITTER` key under `ADD.AUTH.CHANNEL`, and the
gating flag was **deliberately deleted** — `db/migrate/20260508000000_repurpose_channel_twitter_flag_for_conversation_unread_counts.rb`
renamed `channel_twitter` to `conversation_unread_counts` and stripped it from the account defaults. An
administrator can only reach the connect page by typing the URL. `EDITABLE_ATTRS = [:tweets_enabled]` is still
honoured by the API and specced, but its UI control has no consumer.

P10 changes nothing here. Deciding whether X is supported, hidden or removed is a product call with a licence
and dependency dimension (the vendored `twitty` gem), which is P-FINAL's audit, not P10's.

## 7. Feature flags, as they actually are

| channel | flag | enforced where |
| --- | --- | --- |
| Website | `channel_website` (enabled) | frontend only — hides the tile |
| Email | `channel_email` (enabled) | nowhere in the send/receive path |
| Facebook | `channel_facebook` (enabled) | frontend only |
| Instagram | `channel_instagram` (enabled) | frontend only |
| TikTok | `channel_tiktok` (enabled) | server-side on the authorizations endpoint only; not the webhook, callback or send path |
| WhatsApp | five flags, none gating the channel | `whatsapp_campaign` gates campaigns; the rest are deprecated or unconsumed |
| API, Telegram, LINE, Twilio, Bandwidth SMS, X | none | — |

So "disable a channel for an account" is not a capability this product has for most channels: the tile
disappears and the endpoints stay open. P10 does not change that — adding server-side gating to six channels is
a behaviour change for existing accounts and belongs with the plan decisions in P11, not here. Recorded.

## 8. What the matrix is used for

`Channels::Capability` is consumed by `Channels::ConnectionState`
(docs/p10/06-channel-lifecycle-health.md), by the inbox serializer through it, and by
`Operations::AccountHealth`'s channels column. It deliberately does **not** absorb the three vocabularies that
answer different questions — icons and labels in `dashboard/helper/inbox.js`, flow node limits in
`Flows::ChannelCapabilities`, and the outbound service map in `SendReplyJob::CHANNEL_SERVICES` — because
merging them would mean touching 297 `Channel::` literals across 68 frontend files for no gain in correctness.
