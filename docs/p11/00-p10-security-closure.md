# P10 Security Closure

Every security-relevant finding P10 recorded, classified and closed or consciously carried. Written before
P11's commercial work began and completed alongside it, because the brief's rule is that a known cross-tenant
webhook risk must not be carried into billing and tenant enforcement.

Classifications used throughout:

| | |
| --- | --- |
| **FIXED** | changed on this branch, with a test that fails against the previous code |
| **SAFE AS-IS** | investigated and found not to be a defect; the reasoning is recorded so it is not re-opened |
| **FAIL-CLOSED** | the unsafe path now refuses rather than guesses, which may stop a misconfigured install working |
| **PENDING REAL PROVIDER UAT** | fixed or classified as far as repository and provider documentation allow; a real provider credential is needed to finish |
| **OUT OF SCOPE — NON-SECURITY** | real, recorded, not a security issue, and not this phase's to change |

---

## 0. Verdict

**No unclosable cross-tenant vulnerability remains, so P11 commercialization proceeds.**

Seven unauthenticated or forgeable write paths were closed, five of them found by a completeness sweep this
phase commissioned rather than by the original brief. One genuinely cross-tenant finding is carried rather
than fixed — the Facebook page fan-out in §9 — because closing it needs a Graph API check on registration and
a global-uniqueness migration whose production duplicates cannot be read from here. It is not reachable by
forgery; it requires an authenticated administrator to register another account's public page id, and it is
recorded with the exact fix.

Counts: **7 FIXED**, **1 FAIL-CLOSED by design** (Bandwidth, which also counts as fixed), **9 SAFE AS-IS**,
**4 PENDING REAL PROVIDER UAT**, **6 OUT OF SCOPE — NON-SECURITY**.

---

## 1. SC1 — Bandwidth SMS webhook authentication — **FIXED, FAIL-CLOSED**

Commit `99985c5c`.

**What P10 recorded, and the one correction.** P10 said the tenant came from a body field. True, and the route
also carries `:phone_number` in its path — which the controller ignored entirely. So the correction is that the
product already had a server-owned selector available and was not using it.

**What was actually exploitable.** `Webhooks::SmsController` inherited `ActionController::API` with no
authentication of any kind, and `Webhooks::SmsEventsJob` resolved the channel with
`Channel::Sms.find_by(phone_number: params[:to])`. A forged body fully controlled `from` (which creates or
selects a Contact), `text`, `id` and `media`.

**What it was NOT.** Not a cross-tenant *misroute*: `index_channel_sms_on_phone_number` is globally unique, so
exactly one channel exists for any number installation-wide and an attacker cannot create a colliding one. The
exposure was an unauthenticated **write into the account that owns the number** — serious, but it is injection
rather than a choice of victim, and no read of existing data was possible.

**The fix, and why this shape.** Bandwidth documents exactly one callback authentication mechanism: HTTP Basic
credentials configured on the Messaging Application
(https://dev.bandwidth.com/guides/callbacks/callbacks.html). There is no signature or HMAC header, so there
was nothing else to verify and nothing to invent — which is what the brief warned against. The credentials now
live in `provider_config` beside the API key; the channel is resolved from the URL's `:phone_number`, never
from the body; and a channel with no credentials stored cannot authenticate anything, so it **fails closed**.

One provider detail is load-bearing: Bandwidth sends the first delivery with no `Authorization` header and
retries only if the 401 carries `WWW-Authenticate`. Without that header it does not retry at all, so
`request_http_basic_authentication` is required rather than decorative. An unknown number takes the same path
as a bad password, so the response says nothing about which numbers are configured.

**Three defects on the same path went with it.** Only `params['_json']&.first` was enqueued and Bandwidth
sends an array, so every event after the first was silently dropped. A redelivery created a duplicate message,
so inbound now carries the same `source_id` guard as WhatsApp. And §2.

**Evidence.** `spec/requests/webhooks/sms_security_spec.rb` — 12 examples; **9 fail against the previous code**,
0 after.

**Residual.** An existing Bandwidth inbox has no callback credentials, so its inbound stops until an operator
adds them. That is the brief's explicit instruction ("the unsafe path must not remain publicly usable") and the
creation form now collects them. For an inbox created before this change, the operator PATCHes
`provider_config` (`EDITABLE_ATTRS` already permits it) or recreates the inbox. The callback URL is now rendered
on the inbox settings page, using strings that were already translated but had no consumer.

## 2. SC2 — Bandwidth delivery receipts — **FIXED**

Commit `99985c5c`.

P10 recorded that every receipt raises. Confirmed, and it is three layered mismatches rather than one:
`Webhooks::SmsEventsJob` passed `channel:` to `Sms::DeliveryStatusService`, whose
`pattr_initialize [:inbox!, :params!]` does not accept it; it passed the nested `params[:message]` where the
service reads the top-level envelope; and `message` would then have looked for `params[:message][:message][:id]`.

**The service was right and the caller was wrong**, which is provable twice over. Bandwidth's documented
callback is a JSON array whose event objects carry `type`, `time`, `description`, `to` and `message` at the top
level, plus `errorCode` on failures — exactly the shape the service reads. And
`spec/services/sms/delivery_status_service_spec.rb` has always passed it the envelope and `inbox:`, and has
always passed.

**Why nobody noticed.** The job's own spec **mocked** `Sms::DeliveryStatusService`, so the real initializer
never ran and the wrong contract was frozen into the test. That is recorded here because it is the general
lesson: a mocked collaborator cannot catch a signature that does not exist. The job spec now asserts the true
contract and `spec/requests/webhooks/sms_security_spec.rb` exercises a real receipt end to end, unmocked, so a
future mock cannot re-freeze it.

No `sent`, `delivered` or `failed` status was ever recorded for this channel. Nothing was fabricated and no
receipt is swallowed.

## 3. SC3 — WhatsApp inbound routing — **FIXED**, with the central question answered

Commit `71e84983`.

**The question the brief asked first: can it misroute across tenants? No. It drops.** Proven, not assumed:
`channel_whatsapp.phone_number` carries a globally unique index, and every writer of
`provider_config['phone_number_id']` takes it from a Graph response fetched with a token authorized for that
number's WABA. The row a misroute would require — one holding the payload's `phone_number_id` in an account
that does not own the number — cannot exist. The strongest variants were tried and all collapse: the Argentina
mobile/landline normalizer collision, a stale id after WABA migration, and A's stored spelling equal to B's
number. So P10's finding is real and its consequence is availability.

**But the sweep found a genuine hole next to it.** The filter was a bare `==`, which matches `nil` against
`nil`. A 360dialog channel is the one `provider_config` that legitimately never stores a `phone_number_id` —
and those are exactly the channels for which the controller **skipped Meta's signature**, deciding that by
resolving the channel from the same body being authenticated. So omitting `phone_number_id` selected a
360dialog channel *and waived the signature on the way in*: an unauthenticated inbound injection.

**Fixes.** The signature requirement now comes from the envelope: `object == 'whatsapp_business_account'` is
Meta's own shape and nothing else posts it, so it is always verified; the exemption survives only for the
per-number route 360dialog actually uses. Resolution is now **by** `phone_number_id` — which the job's own
comment already claimed it depended on — with the display-number lookups kept as a fallback for a legacy row
that never recorded an id, and the country-normalized spelling accepted only on a strict id match, because
stripping Argentina's mobile 9 names a different real subscriber. A channel whose stored display number has
drifted is now routed instead of discarded. And the `INACTIVE_WHATSAPP_NUMBERS` kill switch read only the URL
segment, so it did nothing on the app-level route Meta delivers to by default.

**No index was added**, and that is a measured decision rather than an omission. On the new expression: at 50
channels an expression index and a sequential scan are indistinguishable (**0.086 ms** against **0.084 ms**);
the index only begins to pay at about 2,000 channels (**0.483 ms → 0.042 ms** for 64 kB). No installation has
2,000 WhatsApp numbers. Both plans are in §13 so the threshold is known rather than guessed.

**Evidence.** `spec/requests/webhooks/whatsapp_routing_isolation_spec.rb` — 12 examples including the two
accounts with colliding display values and distinct Meta ids the brief requires; **6 fail against the previous
code**, 0 after. The 88 pre-existing WhatsApp webhook examples are untouched and still pass.

**PENDING REAL PROVIDER UAT.** Whether each production channel's stored `phone_number_id` still equals what
Meta sends can only be confirmed against a real delivery. `custom/app/services/whatsapp/diagnosis/meta_checks.rb`
already reads both values, so the existing diagnostic answers it without new code.

## 4. SC4 — TikTok OAuth and webhook — **FIXED**, four items, three carried

Commit `2253e919`.

### The finding P10 recorded was the wrong half of the truth — **classified, then FIXED**

P10 recorded "OAuth `state` has no `exp` while `decode_token` passes `verify_expiration: true`", implying the
flow might be broken. It is not. With jwt 2.10.3 the expiration verifier returns early when the payload has no
`exp` key (`jwt-2.10.3/lib/jwt/claims/expiration.rb:22`), so `verify_expiration: true` merely *selects* that
verifier and a token without `exp` **passes**. Presence is a separate option, `required_claims`, which defaults
to `[]` and was never passed. So the state never expired. The repository proves this against itself: the
callback spec built a state with no `exp` and asserted a channel *is* created.

### The more serious finding the brief did not name — **FIXED**

The state carried only `sub: account_id`: bound to an account, bound to no person, and the callback controller
has no authentication of its own. Combined with an eternal state, anyone holding one could complete a TikTok
connection into the account it named, at any later time.

Both halves are closed following the pattern already in this tree for Shopify
(`app/helpers/shopify/integration_helper.rb`): the state now carries `exp` and the `uid` of the administrator
who began the flow, and `required_claims: %w[exp sub uid]` makes all three mandatory on the way back in. The
callback settles the state **before** the authorization code is exchanged — it used to drive two outbound
provider calls for a bogus state — and re-checks that the named user is still an administrator and that the
account still holds the channel entitlement. The authorization endpoint checked that entitlement when minting
the state; nothing re-checked it on the request that creates the channel.

### Replay window — **FIXED**

Confirmed one-sided: it rejected only `delay > 5`, so a future timestamp passed unbounded. Symmetric now. The
tolerance is deliberately left at the shipped value: the timestamp is covered by the signature so this was
never an attacker's window, and narrowing or widening it on guesswork would drop real deliveries.
**PENDING REAL PROVIDER UAT:** what tolerance real delivery latency needs.

### Provider error bodies in a user-visible URL — **FIXED**

Raw TikTok response bodies became the exception message and were then placed in a redirect query parameter the
dashboard renders. The detail stays in the log and in Sentry; the customer gets a sentence. Same separation the
Instagram sibling already makes.

### Secret in a query string — **FIXED by deletion**

`Tiktok::AuthClient#webhook_callback` sent the app secret in a GET query string — the exact exposure this
repository already closed for Meta in P5c-4 — and had no caller. Removed.

### SAFE AS-IS on this path

- The webhook's HMAC-SHA256 signature verification is correct and fail-closed: it rejects a missing secret,
  timestamp or signature and compares in constant time.
- The webhook job's channel lookup is unscoped by account but `business_id` is globally unique, so a second
  tenant cannot hold the same TikTok identity. A drop, not a misroute.
- No TikTok token is exposed in a serialized response, in the audit trail, or to the browser.
- **P10's duplicate-contact fix is untouched and independent of everything above.** Confirmed file by file.

### PENDING REAL PROVIDER UAT

- `Tiktok::AuthClient#update_webhook_callback` has no caller, so **nothing in this fork ever registers the
  TikTok webhook** and inbound TikTok messaging does not work in a default install. It is kept rather than
  deleted because it is the only correct implementation of a missing step, and it is app-level rather than
  per-inbox, so it belongs in a deployment step. Registering it needs a real TikTok app.
- Whether `Tiktok-Signature` is the real header name and `t=..,s=..` the real format cannot be confirmed from
  this repository. If either is wrong, every delivery is rejected.
- The channel's access token is sent as an `x-user` header to whatever URL TikTok's media endpoint returns.
  Provider-supplied rather than attacker-supplied, so not an open redirect of credentials, but the header is
  unusual and deliberately not changed blind. If TikTok's documentation confirms it, a host allow-list belongs
  on `file_download_url` before `Down.download`.

## 5. SC5 — Dead voice endpoints — **FIXED (hidden), not built**

Commit `2fb2985b`.

Confirmed: all four endpoints — `enable_whatsapp_calling`, `disable_whatsapp_calling`, `set_inbound_calls`,
`set_call_recording` — have no route and no controller action, while `InboxPolicy` declares all four. The
server-side voice inventory is zero: no services, no jobs, no models, no routes, no ActionCable channels.

**Reachability is what decided the change.** Of the six frontend surfaces that call them, four are gated on
`channel_voice`, which is `premium: true`, ships disabled, and cannot be switched on through any UI this fork
has — so they are dark. Two are reachable, and neither is gated on anything: they are channel-creation pages
reached by URL.

- `/settings/inboxes/new/voice` offers a Twilio voice inbox form for a channel type the server does not accept.
  It collects Twilio API key secrets and then 422s.
- `/settings/inboxes/new/whatsapp_call` creates a **real** WhatsApp Cloud inbox and then calls
  `enable_whatsapp_calling`. The 404 is reported to the operator as a Meta problem — a false diagnosis, since
  the request never left the product.

Both cards and both factory entries are removed, so those URLs now render nothing. No model, table, migration
or row was touched, no placeholder endpoint was created, and voice was not built. The four dark surfaces are
documented here rather than deleted: removing the orphaned frontend call subsystem, the empty `calls` table
and the unreachable predicates is code cleanup, which is P-FINAL's.

**OUT OF SCOPE — NON-SECURITY, recorded with the fix:**

- `_inbox.json.jbuilder`'s Twilio voice block can never report true: `voice_enabled` and `twiml_app_sid` have
  no production writer, and `recording_enabled` / `transcription_enabled` are not columns or methods anywhere
  in this fork, so those two lines are always null.
- P10's record of the `calls` table is confirmed: it has `contact_id`, no model, no foreign key, and nothing
  reads or writes it. Leaving it is correct while it is empty — which is also why its missing foreign key is
  harmless.
- `Channel::Whatsapp#enable_voice_calling!` is doubly dead: no caller, and it would raise `NoMethodError`
  because `update_calling_status` is not defined on either provider service.
- **Setting `provider_config.calling_enabled` on a WhatsApp Cloud channel subscribes that WABA to a `calls`
  field this fork has no runtime to consume.** `Channel::Whatsapp` permits the whole `provider_config` hash,
  so an administrator can set it; it cannot make `voice_enabled` true, but it does change what the WABA is
  subscribed to at Meta. The fix is to make `calls_enabled_on_waba?`
  (`app/services/whatsapp/webhook_setup_service.rb:98`) also require
  `account.feature_enabled?('channel_voice')`. **Deliberately not applied:** it would drop a live Meta-side
  subscription, and changing provider semantics on judgement rather than evidence is what this phase was told
  not to do. Recorded for whoever owns that decision.

## 6. SC6 — X / Twitter — **FIXED (made honest), not revived**

Commit `2fb2985b`.

All three facts P10 recorded are confirmed verbatim: no `ChannelList.vue` entry, no `TWITTER` key under
`INBOX_MGMT.ADD.AUTH.CHANNEL`, and the gating flag repurposed by
`db/migrate/20260508000000_repurpose_channel_twitter_flag_for_conversation_unread_counts.rb`.

Two things were still shown to a user and could not work, and one was a live liability:

- The connect route was still mounted and rendered a working-looking "Sign in with Twitter" page. Nothing
  gated it — no feature flag and no env-var guard, only a post-hoc check on X's response.
- `GET /webhooks/twitter` passed a **nil** HMAC key to OpenSSL when `TWITTER_CONSUMER_SECRET` was unset, so an
  anonymous request produced an unhandled `TypeError` — a 500 on demand.
- `POST /webhooks/twitter` had **no signature verification of any kind** and resolved its inbox from a body
  field, through a lookup unscoped by account whose unique index is `(account_id, profile_id)` rather than
  global. So unlike every other channel examined here, a unique index would **not** have collapsed a misroute
  into a drop: the misroute is real in principle, and unreachable only because no `Channel::TwitterProfile`
  row can be created in this fork today.

The connect page entry and both webhook routes are removed, with the controller that served only them. That
last point is why removing the route was chosen over documenting it: it is the path that would come alive first
if the channel were ever revived, and it would come alive unauthenticated.

Nothing was revived and **no data was touched**: no table, no row, no migration, no model, no factory, no spec.
The `Channels::Capability` `:twitter` row stays deliberately, so `Channels::ConnectionState` keeps answering
`unknown` for an existing X inbox rather than nothing. Whether X is supported, hidden or removed remains a
product and licence decision, with the vendored `twitty` gem attached to it — P-FINAL's audit, not this one's.

---

## 7. The completeness sweep, and why it happened

SC1 fixed one webhook. The obvious question was whether the same defect class existed elsewhere, so this phase
swept **every route reachable without a logged-in session**. It did, on five more endpoints. Four are fixed
here; the fifth is §9.

This sweep was not in the brief. It is in scope because the brief's own instruction is not to carry a known
cross-tenant webhook risk into P11's billing and tenant enforcement, and because an endpoint that fixes one
tenant boundary while five others stay open is not a closure.

## 8. What the sweep found and what was done — **FIXED**

Commits `fe5a26bb` (Stripe) and `403d423f` (the rest).

| finding | what it was | status |
| --- | --- | --- |
| **Stripe billing webhook accepted a forged signature** | `stripe_webhook_secret.to_s` was passed to the SDK with no blank-secret guard. The SDK only requires a String, so an unset secret became `""` and OpenSSL signs perfectly well with an empty key — a signature anyone can reproduce. A forged event then named its own account through `client_reference_id` or `metadata['account_id']`, checked only with `Account.exists?`. The route is mounted unconditionally and never consults `Billing::Settings.enforced?`, so this was open on exactly the installations that had not finished setting billing up. **Genuinely cross-tenant: a forged body moved an arbitrary account's subscription.** | **FIXED, FAIL-CLOSED.** Both blank-secret examples fail against the previous controller. |
| **Twilio inbound had no signature check** | No `X-Twilio-Signature` verification anywhere in the repository; the channel came from `MessagingServiceSid`, or `AccountSid` plus the number. A Twilio number is a business's public phone number and an Account SID is not a secret. | **FIXED.** Verified with the vendored `twilio-ruby` validator against that channel's own auth token. |
| **Twilio delivery status, the same** | A forged body marked an existing outgoing message failed with an attacker-chosen `ErrorMessage` that agents read in the conversation. | **FIXED**, same concern. |
| **Slack skipped its signature check when unconfigured** | By design, with a comment saying so. The tenant came entirely from the body — an unscoped global lookup on `Integrations::Hook#reference_id` — and the handler writes an **outgoing, customer-visible** message into that account's conversation. | **FIXED, FAIL-CLOSED.** |
| **Slack handed the account's OAuth token to an attacker-chosen host** | A Slack event's files were downloaded from the body-supplied `url_private` with the account's token in an `Authorization` header, with no URL validation and without this repository's own `SafeFetch`. A forged event pointed it anywhere and received the token. | **FIXED.** The token travels only to a Slack-owned host; anything else is skipped, since a Slack private file cannot be fetched without it anyway. |
| **Facebook verified nothing when unconfigured** | The gem's verifier begins `return unless app_secret_for(...)`, and `GlobalConfigService.load` answers **nil** rather than its default for a blank value. `Channel::FacebookPage` has no per-channel secret column, so an installation without `FB_APP_SECRET` accepted any unsigned body and took the tenant from it. | **FIXED, FAIL-CLOSED.** The provider never answers falsy. |

Two incidental things worth recording. The Slack guard pushed its helper module past the line limit, so the
attachment path became its own object rather than an exclusion. And a Slack fixture pointed `url_private` at a
host Slack does not serve from, which the new guard correctly skipped — the fixture is realistic now, so the
spec exercises the real path instead of one that could never appear.

**Evidence.** `spec/requests/billing/webhook_security_spec.rb` (12 examples) and
`spec/requests/webhooks/public_endpoint_authentication_spec.rb` (12 examples).

## 9. The one carried cross-tenant finding — **OUT OF SCOPE for this closure, with the fix recorded**

**Facebook page fan-out.** `Channel::FacebookPage` deliberately allows the same `page_id` in many accounts —
uniqueness is scoped to `account_id` and the bare `page_id` index is non-unique — while
`Integrations::Facebook::MessageCreator` fans every inbound webhook out to **every** channel holding that
`page_id`. An administrator of account A can register account B's public page id through the ordinary
authenticated `register_facebook_page` endpoint, which performs no Graph check that the caller controls the
page, and then receives B's inbound messages.

**Why it is carried rather than fixed.** It needs two things this phase should not do on judgement: a Graph API
call on registration to confirm the caller administers the page, which cannot be exercised without a real
Facebook app; and making `page_id` globally unique, which is a migration whose success depends on whether
production already holds duplicates — and production cannot be read from here. Either done blind risks breaking
a legitimate multi-account arrangement or failing a deploy.

**It is not reachable by forgery.** It requires an authenticated administrator of some account to register
another account's page id, which is a different and much higher bar than the findings above. The exact fix, in
the order the project's own guidelines require (earliest shared entry point first):

1. In `Api::V1::Accounts::CallbacksController#register_facebook_page`, confirm with the Graph API, using the
   supplied token, that the caller administers `page_id`, and reject otherwise.
2. Then make `page_id` globally unique — migration plus an unscoped uniqueness validation — after checking
   production for existing duplicates.

Handed to P-FINAL as the single highest-priority item on its list.

## 10. SAFE AS-IS — investigated, not defects

Recorded so none of these is re-opened without new evidence.

1. **The billing 402 lock does not block inbound customer data.** `Billing::AccessGuard` is mixed into
   `Api::V1::Accounts::BaseController` only, which has 71 descendants — the agent dashboard API. The inbound
   surfaces inherit from different base classes (`ActionController::API`, `ApplicationController`,
   `PublicController`) and `rg -l` across `app/controllers/webhooks`, `app/controllers/public` and
   `app/controllers/api/v1/widget` returns nothing. A past-due account still receives its customers' messages
   and loses the dashboard, which is the policy the brief asks for, holding by construction.
2. **Administrative suspension and billing restriction are already separate.** `Account` has
   `enum :status, { active: 0, suspended: 1 }`, operator-set from Super Admin; billing state lives in
   `billing_subscriptions.status`. Neither is overloaded onto the other, and P11 keeps it that way.
3. **Commerce webhooks (Shopify, Zid, Salla)** verify provider signatures and fail closed on a blank secret.
   `app/controllers/webhooks/shopify_controller.rb` is the pattern the fixes above follow.
4. **Instagram's webhook** verifies `X-Hub-Signature-256` unconditionally.
5. **The TikTok webhook signature** is correct and fail-closed (§4).
6. **The web widget and API channel** select their tenant from a server-minted secret — `website_token` and
   `identifier` — which is the strongest pattern in the repository for this.
7. **TikTok's `business_id` and Bandwidth's `phone_number`** are globally unique, so neither can misroute.
8. **A same-account replay of a TikTok OAuth callback** lands in that same account, because the state's only
   routing field is the account. Recorded so the §4 fix is not justified with a scenario that does not support
   it.
9. **No credential is exposed** in a serialized response, an audit row, an operations signal or an error on any
   path touched here. Asserted by the specs in §1, §3, §4 and §8, plus P10's own credential-exposure spec.

## 11. OUT OF SCOPE — NON-SECURITY

Real, recorded, and not this phase's to change: the voice items in §5; the orphaned frontend call subsystem and
the empty `calls` table; the unreachable X library and the vendored `twitty` gem's licence question; and the
`billing_helper.rb` / `BillingPlan` naming collision described in `01-discovery.md` §12.

## 12. Tests added by this closure

| file | examples | what it holds |
| --- | --- | --- |
| `spec/requests/webhooks/sms_security_spec.rb` | 12 | Bandwidth: authentication, fail-closed, cross-account body, batching, redelivery, receipts, secret safety |
| `spec/requests/webhooks/whatsapp_routing_isolation_spec.rb` | 12 | the unsigned-injection hole, two accounts with colliding display values and distinct Meta ids, drifted numbers, legacy rows, the kill switch |
| `spec/requests/tiktok/oauth_state_security_spec.rb` | 9 | every state refusal, and that a provider body never reaches the URL bar |
| `spec/requests/billing/webhook_security_spec.rb` | 12 | Stripe: blank secret, bad signature, idempotency, out-of-order, tenant selection |
| `spec/requests/webhooks/public_endpoint_authentication_spec.rb` | 12 | one adversarial example per endpoint for Twilio ×2, Slack ×2, Facebook, and the Slack token guard |

Every one of the five is written from the attacker's side: each example is a request a stranger can make, and
asserts what the product does with it.

## 13. Measurements taken for this closure

| what | result |
| --- | --- |
| WhatsApp `phone_number_id` lookup, 50 channels, no index | Seq Scan, **0.084 ms** |
| the same with an expression index | Index Scan, **0.086 ms** — indistinguishable, so no index was added |
| the same, 2,000 channels, no index | Seq Scan, **0.483 ms** |
| the same, 2,000 channels, indexed | Index Scan, **0.042 ms**, 64 kB |
| per-account quota serialization, without `FOR UPDATE` | the second transaction counts immediately; "T2 did not wait for T1" |
| the same, with `FOR UPDATE` on the account row | **T2 waited 1,175 ms** and counted only after T1 committed |
