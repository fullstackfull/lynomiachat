---
agent: 013
scope: WhatsApp onboarding through Embedded Signup — prerequisites, every screen, the provider's app configuration, what the flow returns, the server-side finish, and every documented blocker
confidence: medium
sources_normative: 14
sources_observational: 1
---

# Agent 013 — Onboarding through Embedded Signup

All Meta pages were read read-only on **2026-10-13**. No Meta API was called, no form submitted, no
credential used. Four documentation URLs returned 404 or navigation-only shells; they are recorded in §1 as
**not retrieved** rather than silently dropped, and the facts they would have carried are marked as gaps in §6.

A note on the documentation estate itself, because it matters to anyone citing it: Meta is mid-migration from
`developers.facebook.com/docs/whatsapp/**` to `developers.facebook.com/documentation/business-messaging/whatsapp/**`.
Both path families are live, both serve content, and **neither is a complete mirror of the other** — the phone
number rules only rendered under `/docs/`, the default-flow screen list and the coexistence page only rendered
under `/documentation/`. Lynomia's own corpus must therefore carry both URL forms for the same rule, or it will
link to shells.

---

## 1. Source register

| # | Source URL | Page title | Product | API / version context | Date checked | Status |
|---|---|---|---|---|---|---|
| S1 | https://developers.facebook.com/docs/whatsapp/embedded-signup | Embedded Signup | WhatsApp Business Platform | v2 deprecation 2026-10-15; v4 current | 2026-10-13 | normative |
| S2 | https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/implementation/ | Implementation | WhatsApp Business Platform / Facebook Login for Business | sample uses Graph API v25.0 | 2026-10-13 | normative |
| S3 | https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/default-flow | Cloud API flow (default screens) | WhatsApp Business Platform | none stated | 2026-10-13 | normative |
| S4 | https://developers.facebook.com/docs/whatsapp/embedded-signup/pre-filled-data | Pre-filled data | WhatsApp Business Platform | `sessionInfoVersion: '3'` (v2-era) | 2026-10-13 | normative |
| S5 | https://developers.facebook.com/docs/whatsapp/embedded-signup/versions | Versions | WhatsApp Business Platform | v2 / v3 / v4 and their preview builds | 2026-10-13 | normative |
| S6 | https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users/ | Onboard WhatsApp Business app users (coexistence) | WhatsApp Business Platform | session payload `version: 3` | 2026-10-13 | normative |
| S7 | https://developers.facebook.com/documentation/business-messaging/whatsapp/access-tokens/ | Access Tokens Guide | WhatsApp Business Platform | none stated | 2026-10-13 | normative |
| S8 | https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/get-started-for-tech-providers | Become a Tech Provider | WhatsApp Business Platform | none stated | 2026-10-13 | normative |
| S9 | https://developers.facebook.com/docs/whatsapp/phone-numbers | Phone Numbers | WhatsApp Business Platform | none stated | 2026-10-13 | normative |
| S10 | https://developers.facebook.com/docs/whatsapp/cloud-api/reference/registration | Registration (reference) | WhatsApp Cloud API | example `https://graph.facebook.com/v25.0/{id}/register` | 2026-10-13 | normative |
| S11 | https://developers.facebook.com/docs/whatsapp/cloud-api/guides/set-up-webhooks | Set up Webhooks | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| S12 | https://developers.facebook.com/docs/graph-api/reference/whats-app-business-account/subscribed_apps/ | WhatsApp Business Account `subscribed_apps` | Graph API | `GET /v26.0/{waba-id}/subscribed_apps` | 2026-10-13 | normative |
| S13 | https://developers.facebook.com/documentation/business-messaging/whatsapp/whatsapp-business-accounts/ | WhatsApp accounts and Messaging accounts | WhatsApp Business Platform | none stated | 2026-10-13 | normative |
| S14 | https://developers.facebook.com/docs/whatsapp/cloud-api/get-started | Get Started | WhatsApp Cloud API | Graph API v23.0 in step 6 | 2026-10-13 | normative |
| O1 | developers.facebook.com indexed search summary (WebSearch over `developers.facebook.com` only) | — | — | — | 2026-10-13 | **observational, unconfirmed** — a search-engine summary of Meta pages, not a page I rendered |
| X1 | https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/tech-providers/onboarding-customers | Onboarding customers as a Tech Provider | — | — | 2026-10-13 | **not retrieved** (navigation-only shell) |
| X2 | https://developers.facebook.com/documentation/business-messaging/whatsapp/phone-numbers/ | Phone numbers (new path) | — | — | 2026-10-13 | **not retrieved** (navigation-only shell) |
| X3 | https://developers.facebook.com/documentation/business-messaging/whatsapp/cloud-api/phone-numbers/register-phone-numbers | Register phone numbers (new path) | — | — | 2026-10-13 | **not retrieved** (navigation-only shell) |
| X4 | https://developers.facebook.com/docs/whatsapp/cloud-api/guides/register-phone-number | — | — | — | 2026-10-13 | **not retrieved** (HTTP 404) |

Every claim below carries its row. Where a fact exists only in O1, it is labelled *observational, unconfirmed*
in place.

---

## 2. The rules

### 2.1 What Embedded Signup is

Embedded Signup is Meta's hosted authentication-and-authorization interface that a business customer walks
through, in a popup window launched from the provider's own site, to produce the WhatsApp assets needed to be on
the WhatsApp Business Platform and to grant the provider's app access to them (S1). It is built on **Facebook
Login for Business** plus the **Facebook JavaScript SDK**, works on desktop and mobile, and is localised into
**30 languages**, chosen from the customer's own Facebook language setting (S1). It does three jobs in one
window: collect business information, create the assets (business portfolio, WABA, WhatsApp business profile,
phone number), and issue the provider an exchangeable authorization code (S1).

Two framings matter for Lynomia's help copy. First, **the customer owns the assets, not Lynomia**: "Customers
own their WhatsApp assets and have full WhatsApp Manager access, which you cannot restrict" (S1). A support
article that implies Lynomia can lock a customer out of their own WABA would be wrong. Second, **the flow does
not finish onboarding** — it ends with Meta handing back three IDs and a code, and the provider still has to
make server-side calls before a message can be sent (S1).

### 2.2 What it replaced — stated, and what is not stated

Meta's own pages are thinner here than the brief assumes, and I will not fill the gap by inference.

What Meta does state: the **On-Behalf-Of (OBO) ownership model is deprecated** (S13). The signup flow still
emits a dedicated finish event for migrating off it — `FINISH_OBO_MIGRATION` (S2) — and the overview links a
"Migrating business customer assets" section (S1). So Embedded Signup, in its current form, is the replacement
for the OBO arrangement in which the provider's own business portfolio owned the customer's WABA.

What Meta does **not** state on any page I retrieved: that Embedded Signup replaced a named earlier mechanism
such as a manual onboarding form or a v1 flow. The Versions page (S5) starts at v2 (January 2023) and never
mentions a v1. **Any Lynomia article claiming "Embedded Signup replaced X" must cite OBO deprecation (S13) and
stop there.** This is recorded again in §6.

### 2.3 What the business must already have before starting

| Prerequisite | What Meta states | Row |
|---|---|---|
| Facebook / Meta Business credentials | The customer must "Authenticate with Facebook or Meta Business credentials" on the first screen | S1, S3 |
| A business portfolio | Not required in advance. The customer may "Select an existing business portfolio or create one" inside the flow — but only "if they have not reached their portfolio limit" | S1, S3 |
| A verified business | **Not required to start.** Verification is a prerequisite for the *provider*, and it raises caps for the customer later: a new business portfolio is "initially capped at two registered business phone numbers", rising to 20 "after verification or after reaching a 2,000 messaging limit" | S8, S9 |
| A WABA | Not required in advance — create or select inside the flow. But a WABA "must belong to only one business portfolio", cannot be co-owned, and cannot be migrated to another business | S1, S13 |
| A phone number | Required, and heavily conditioned — see §2.4. Alternatively the provider supplies a pre-verified number via `extras` | S1, S4, S9 |
| Terms acceptance | The customer must accept terms for "Cloud API, WhatsApp Business, Meta, Marketing Messages Lite API, and Meta Business Tool Terms" | S1 |
| A payment method | Required **before messaging**, not before signup, for every customer except those under a Solution Partner credit line: "Customers must attach a payment method to their WABA before messaging" | S1 |

### 2.4 The phone number conditions — the real gate

This is where onboarding actually fails, and S9 is the normative page. Meta's stated conditions, in its own
words where quoted:

- **Owned by the customer.** The number must "be owned by you."
- **Country and area code; no short codes.** It must "have a country and area code (short codes are not
  supported)."
- **Reachable for the OTP.** It must "be able to receive voice calls or SMS." Verification itself: "Phone
  numbers must be verified using a code sent via an SMS/voice call."
- **Already on WhatsApp → must be deleted first.** Numbers already in use on WhatsApp "cannot be registered
  unless they are deleted first."
- **Once registered, it leaves consumer WhatsApp.** A registered number "cannot be used with WhatsApp
  Messenger" — though the line itself still works for ordinary calls and texts.
- **Banned numbers.** "it must be unbanned via the appeal process first."
- **Display name is part of registration.** "You must provide display name information when registering a
  business phone number", and if the display name's `name_status` is `EXPIRED` or `NONE`, the number "cannot be
  used to register the phone number for API use."
- **Two-step PIN is mandatory.** "You must set a two-step verification PIN when registering a business phone
  number."
- **Signup alone does not register it.** Embedded Signup and the other onboarding methods "do not register the
  number for Cloud API use" — a separate `register` call is required (S9, and §2.7 below).
- **Status must be `connected`** before the number can send or receive via the API.

Number-type suitability, from S9's table (this is the single most useful thing Lynomia can put in front of a
customer *before* they start):

| Number type | SMS OTP | Voice OTP |
|---|---|---|
| Mobile | Standard **(recommended)** | Standard |
| Fixed line | Not Recommended | Standard |
| Freephone / toll-free | Not Recommended | Standard |
| Premium rate, universal access, inbound only | Not Recommended | Standard |
| VoIP | Not Recommended | Standard — provider must support international SMS/calls for OTPs |
| Shared cost, personal number | Not Recommended | Not Recommended |
| M2M / IoT | Not Recommended | Not Recommended |
| Pager | Not supported | Not supported |

Toll-free and IVR numbers specifically (S9): they "can be registered, but must be able to accept calls from
international numbers" and must "be able to redirect the SMS message or voice call to a real person". Numbers
behind an IVR that "are unable to receive registration calls are not supported."

**On "a number already on another WABA":** S9 does **not** state that this is forbidden. What it states is that
"You can migrate phone numbers from one WABA to another." Separately, S13 states a WABA "must belong to only
one business portfolio." I found no page saying a number may sit on two WABAs at once, and I found no page
saying it may not. This is an ambiguity, logged in §6 — Lynomia must not assert either way.

**On "a disallowed country":** no page I retrieved states a country allowlist or denylist for Embedded Signup or
for Cloud API number registration. S9's only country rules are that the number must have a country code, that
send requests should include the plus sign and country calling code (without it "your business phone number's
country calling code is prepended", which can misdeliver), and that "For Brazil and Mexico, the extra added
prefix of the phone number may be modified by the Cloud API." **The brief's premise of a documented disallowed
country is not confirmed by the pages I read.** Logged in §6 as a gap, not as a rule.

### 2.5 What the provider (Lynomia) must have and configure

**Provider-side eligibility** (S1, S8):

- A Meta app with the **WhatsApp use case** and a connected business portfolio, with **Tech Provider
  onboarding** selected under App Dashboard → Use cases → Customize.
- **Business verification.** "To become a tech provider you need to verify your business with Meta", and "Your
  business must be verified before you can start the app review process."
- **App Review for advanced access.** S1 is blunt: "You will not be able to onboard business customers until
  your app has been approved for advanced access" for each required permission. Advanced access is needed on
  `whatsapp_business_messaging` (sending on clients' behalf) and `whatsapp_business_management` (reaching
  clients' WABAs); without the latter, "API calls that use this permission on WABAs not owned by your business
  return error code `200`" (S8).
- App Review evidence: app icon, privacy policy, app category, plus two videos — one showing a message sent from
  the app and received in a WhatsApp client, one showing the app creating a message template. A screen recording
  of the API Setup cURL script or WhatsApp Manager can substitute for either (S8).
- **Token model.** "If you are a Tech Provider, you will use business tokens exclusively" (S1) — the Business
  Integration System User token, "scoped to individual customers" (S7).
- **Solution Partner only:** must already hold a line of credit, must have accepted the Credit Allocation API
  terms in Business Settings → Payments, must share the credit line during onboarding, and uses a system user
  token whose system user holds `business_management` and an Admin or Financial Editor role on the business
  portfolio (S1).

**Facebook Login for Business settings** — App Dashboard → Facebook Login for Business → Settings → Client OAuth
settings, all set to Yes (S2): Client OAuth login, Web OAuth login, Enforce HTTPS, Embedded Browser OAuth Login,
Strict Mode for redirect URIs, Login with the JavaScript SDK. **Allowed domains** and **Valid OAuth redirect
URIs** must list every page that hosts the flow, development domains included; only HTTPS domains are supported
and the host needs a valid SSL certificate (S2). Subscribe to the **`account_update`** webhook, "which fires
when a customer completes the flow and carries their business information" (S2).

**The configuration ID.** Create a Facebook Login for Business configuration — either from the template
"WhatsApp Embedded Signup Configuration With 60 Expiration Token", or as a custom configuration using the
**WhatsApp Embedded Signup** login variation — requesting only the assets and permissions actually needed, then
capture its ID for `config_id` (S2).

**Permissions.** `whatsapp_business_management` for WABA settings and message templates;
`whatsapp_business_messaging` for phone number settings and for sending/receiving (S1). In development mode
these appear on the authorization screen only for users holding admin, developer or tester role on the app; in
live mode **only permissions approved for advanced access appear at all** (S1). S2 gives no scope list of its
own — the permissions come from the Login configuration, not from the `FB.login` call.

**The launch call** (S2):

```js
FB.login(fbLoginCallback, {
  config_id: '<CONFIGURATION_ID>',
  response_type: 'code',
  override_default_response_type: true,
  extras: { setup: {} }
});
```

with `FB.init` taking `appId`, `autoLogAppEvents: true`, `xfbml: true` and `version`, and the SDK loaded from
`https://connect.facebook.net/en_US/sdk.js` (S2).

**The `extras` contract** is version-dependent and this is a live trap. S5 states that for **v4** "The extras
object is purposely empty for v4" — product selection moved into the Login configuration — and that pre-filled
screen-skipping exists in **v2 only**: "v2 lets users skip screens. v3, v3-public-preview, and v4 do not skip
screens." The whole `extras.setup` tree documented on S4 (`business` with `id`/`name`/`email`/`website`/
`address.*`/`phone.code`/`phone.number`/`timezone`; `preVerifiedPhone.ids[]`; `phone` with
`displayName`/`category`/`description`; `whatsAppBusinessAccount`), plus `featureType` and
`sessionInfoVersion: '3'`, therefore describes the **v2** contract. S4 itself still carries the v2-deprecation
banner. Lynomia should treat S4 as historical unless it is deliberately running v2.

`featureType` values Meta names (S5): `whatsapp_business_app_onboarding`; `only_waba_sharing` (v2 and
v2-public-preview only); `marketing_messages_lite` (v2 only); blank for the default flow. A separate `features`
field takes `app_only_install` and `marketing_messages_lite`. `sessionInfoVersion` is "Required in v2 to receive
the callback", value `3`; v2-public-preview does not use it and v3/v3-public-preview/v4 do not list it.

**The callback / redirect contract.** There is no server redirect in this flow. Two channels run in parallel
(S2):

1. The **`FB.login` response callback** delivers `response.authResponse.code` — the exchangeable code. S2 warns
   it "has a time-to-live of 30 seconds", so it must be posted to the provider's server immediately.
2. A **`window` `message` event listener** delivers the asset IDs. Guard it: return early unless
   `event.origin.endsWith('facebook.com')`, parse `event.data` as JSON, act only when
   `data.type === 'WA_EMBEDDED_SIGNUP'`.

The Valid OAuth redirect URIs and Allowed domains settings exist to authorise the *hosting page*, not to receive
a callback.

### 2.6 Every screen and decision in the default flow

S3 enumerates eight screens, in order:

1. **Authentication** — sign in with Facebook or Meta Business Suite credentials.
2. **Authorization** — review the data the provider's app is permitted to access.
3. **Business asset selection** — choose an existing Meta business portfolio and WABA, or create new ones "if
   they have not reached their portfolio limit".
4. **Business asset creation** — where new assets are created. S3 gives this screen the *same* description as
   screen 3, so what distinguishes them is not stated (see §6).
5. **Phone number addition** — enter a new business phone number to associate with the WABA and choose how to
   receive the verification code. S3 does not name the delivery methods; S9 states verification is "via an
   SMS/voice call". If the provider supplies numbers, the provider "must deliver the codes to the customer or
   provide pre-verified numbers instead."
6. **Phone number verification** — enter the code.
7. **Permissions review** — a summary of what was granted.
8. **Success** — Meta confirms the portfolio, WABA, display profile and phone number were created and linked.
   On **Finish**, the message event fires.

S1 adds steps that S3's screen list does not surface separately, and they are real decisions the customer makes:
accepting the five sets of terms, **selecting one or more WhatsApp APIs**, and **entering a display name** to
show in place of the number in WhatsApp clients. S3 explicitly does not describe a display-name screen or terms
screens; S1 does list both as steps. Treat S1 as the authority on *what the customer does* and S3 as the
authority on *screen sequence*, and note the discrepancy (§6).

Meta also notes a behaviour that trips up analytics: **closing the popup on the final screen counts as success,
not cancellation** (S2).

### 2.7 What the flow returns, and what the provider does next

**Returned to the launching window** (S1, S2) — `data.type === 'WA_EMBEDDED_SIGNUP'`:

| Field | Meaning |
|---|---|
| `waba_id` | the customer's WhatsApp Business Account ID |
| `phone_number_id` | the business phone number ID |
| `business_id` | the business portfolio ID |
| `waba_ids` | array, for multi-WABA results |
| `ad_account_ids`, `page_ids`, `dataset_ids`, `catalog_ids`, `instagram_account_ids` | optional arrays of other granted assets |
| `event` (top level) | the finish type |

Finish types (S2): `FINISH`, `FINISH_ONLY_WABA`, `FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING`,
`FINISH_OBO_MIGRATION`, `FINISH_GRANT_ONLY_API_ACCESS`, `ERROR`. Abandonment arrives as `event: 'CANCEL'` with
`data.current_step` — which is exactly the field a support desk needs, because it names the screen the customer
quit on. A customer-reported error arrives as `event: 'CANCEL'` with `data.error_message`, `error_code`,
`session_id`, `timestamp`.

**Returned to the response callback** (S2): `response.authResponse.code`, TTL 30 seconds.

**The four server-side finish steps** (S1):

1. **Exchange the code for a customer-scoped business token.** This must be server-to-server. **Neither S1, S2
   nor S7 states the endpoint or the parameters.** S7 says only that you must "implement Embedded Signup
   (configured with Facebook Login for Businesses) and exchange the code returned to you when a customer
   completes the flow", and defers to the Facebook Login for Business documentation, which I did not retrieve.
   I therefore record **no endpoint, no `client_id`/`client_secret`/`code`/`grant_type` shape** — see §6. The
   resulting token type is the **Business Integration System User token**, "scoped to individual customers", and
   S7 states business tokens "avoid the need for future re-authentication" with **no expiry value stated**.
2. **Register the business phone number for Cloud API** — `POST PHONE_NUMBER_ID/register` (example
   `https://graph.facebook.com/v25.0/{id}/register`), with `messaging_product: "whatsapp"` (required) and `pin`
   (required, 6 digits — the existing PIN if two-step is already on, otherwise a new one), plus optional
   `data_localization_region`, a 2-letter ISO 3166 code enabling local storage (S10). Auth needs
   `whatsapp_business_management` and `whatsapp_business_messaging` (S10). The register response body is not
   documented (S10). Deregistration is `POST PHONE_NUMBER_ID/deregister`, returning `{"success": true}` (S10).
3. **Subscribe the app to webhooks on the customer's WABA.** S1 names this as a required step. **The Graph API
   reference for the edge documents only the read**: `GET /v26.0/{whats-app-business-account-id}/subscribed_apps`,
   and both its Creating and Deleting sections say "You can't perform this operation on this endpoint" (S12).
   S11 describes subscription as an **App Dashboard** action (App Dashboard → WhatsApp → Configuration, or Use
   cases → Customize → Configuration) and names the permissions — `whatsapp_business_messaging` for `messages`
   webhooks, `whatsapp_business_management` for all others — but gives no per-WABA API call. O1 (search summary,
   *observational, unconfirmed*) says the docs show a POST to the `subscribed_apps` edge with a bearer token
   under a heading "Step 3: Subscribe to your WABA". **I could not confirm the POST form on a page I rendered.**
   This is the single biggest hole in this report; see §6.
4. **Share the credit line** — Solution Partners only (S1).

After that: Solution Partners and their partners "can start messaging immediately"; everyone else must first
attach a payment method (S1). Customers begin at standard messaging limits, which rise with API usage (S1).

### 2.8 Coexistence — the number already on the WhatsApp Business app

This is the documented answer to "my number is already on WhatsApp", and S6 is normative. Eligibility: the
customer must be on **WhatsApp Business app version 2.24.17 or higher**; "You must already be a Solution Partner
or Tech Provider"; "You must use Embedded Signup with session logging"; the provider's callback must accept and
digest webhooks. Completion returns `event: "FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING"` with
`type: "WA_EMBEDDED_SIGNUP"`, `version: 3` and the customer's `waba_id`. The provider onboards as normal but
**skips phone number registration**, because the number is already registered.

Stated limitations (S6), all of which generate support tickets: fixed throughput of **20 mps** for a number used
with both the app and Cloud API; group chats are not synchronised; disappearing messages, view-once messages,
live location and broadcast lists are disabled or unsupported; the Deregister API "cannot be used on a number
already in use with both platforms"; Cloud API messages follow the 24-hour customer service window but app
messages neither affect that window nor Cloud API pricing; previously shared credit lines "may cause an error
when switching partners"; and there is a hard clock — "you have 24 hours to synchronize their messaging history,
otherwise they must be offboarded". Each sync step (contacts, history) runs **once only**; repeating it requires
offboarding and re-running the flow.

---

## 3. Error codes and failures

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Row |
|---|---|---|---|---|---|---|
| `200` | not stated | Permissions error | The app lacks advanced access to `whatsapp_business_management`, or the system user lacks Partial/Full business asset access to the WABA. S8: "API calls that use this permission on WABAs not owned by your business return error code `200`." | Nothing customer-side — the provider must complete App Review for advanced access, or fix asset access | Nothing; the provider's integration appears broken or empty | S7, S8, S12, S13 |
| `100` | not stated | Invalid parameter | Bad parameter on the `subscribed_apps` edge | Provider-side fix | nothing | S12 |
| `80008` | not stated | "There have been too many calls to this WhatsApp Business account. Wait a bit and try again." | WABA-level rate limit | Wait and retry | nothing | S12 |
| `133016` | not stated | not stated | More than 10 registration **or** deregistration requests for one number in a 72-hour moving window. Exceeding it "blocks registration for the next 72 hours" | Stop retrying; wait out the 72 hours | Number never goes live; onboarding appears to hang | S10 |
| `131060` | not stated | Unsupported messages webhook | Coexistence: expected for first-time messaging or for unsupported companion devices, whose messages do not fire `messages` webhooks and so cannot be mirrored | "The business should check the WhatsApp Business app for the message" | A customer message is invisible in Lynomia but present in the WhatsApp Business app | S6 |
| `2593109` | not stated | History webhook | Coexistence: "the business declined to share its chat history" | Re-run the flow after offboarding if history is wanted | No historical conversations appear | S6 |
| *(flow)* `ERROR` | — | finish type `ERROR` | Flow terminated in error inside the popup | Retry the flow | The popup reports failure | S2 |
| *(flow)* `CANCEL` | — | abandonment / user-reported error | `data.current_step` on abandonment; `data.error_message`, `error_code`, `session_id`, `timestamp` on a user-reported error | Resume from the named step | Customer closed or reported from the popup | S2 |

**No code is invented here.** Where Meta gives no subcode or no title, the cell reads `not stated`. The
`error_code` carried inside a `CANCEL` payload is a flow-session code whose value set Meta does not enumerate on
any page I read.

---

## 4. Limits and numbers

Every number below is stated by its source row. Nothing is extrapolated.

| Number | What it limits | Row |
|---|---|---|
| **10 new customers per rolling 7-day window** | Default onboarding cap for a provider | S1 |
| **200** | The raised cap, after Business Verification, App Review and Access Verification. Above that, apply to become a Meta Business Partner | S1 |
| **30 seconds** | TTL of the exchangeable `code` returned to the `FB.login` callback | S2 |
| **10 requests / 72-hour moving window** | Register **and** deregister calls per phone number; excess returns `133016` and blocks registration for 72 hours | S10 |
| **6 digits** | Two-step verification PIN length | S10 |
| **2 → 20** | Registered business phone numbers per new business portfolio; the cap rises after verification or after reaching a 2,000 messaging limit | S9, S13 |
| **2,000** | The messaging limit that (alternatively) raises the phone-number cap | S9 |
| **20** | WABAs per Meta Business Account, initially | S13 |
| **250** | Message templates per WABA | S13 |
| **2** | Partners a WABA can be shared with, via Meta Business Suite | S13 |
| **30 days** | A number cannot be deleted if it "has been used to send paid messages within the last 30 days"; numbers cannot be deleted via the API, and only business portfolio admins can delete them | S9 |
| **30 days** | Sandbox account validity; claimed from App Dashboard → WhatsApp → Quickstart → Testing Integrations; their numbers cannot send or receive. Deletion rolling out from 25 June 2025 | S1 |
| **2** | 555 test numbers a customer may claim (+1 country code, 555 area code, auto-verified, require an approved display name, cannot be migrated or used off-platform) | S1 |
| **30** | Languages Embedded Signup is localised into | S1 |
| **100 characters** | `business.name` max (v2 `extras`) — also used as the WABA name | S4 |
| **512 characters** | `phone.description` max (v2 `extras`); no Markdown, hyperlinks not clickable, emoji must be Java/JavaScript-escaped | S4 |
| **2.24.17** | Minimum WhatsApp Business app version for coexistence | S6 |
| **20 mps** | Fixed throughput for a number used with both the app and Cloud API | S6 |
| **24 hours** | Window to synchronise messaging history in coexistence, "otherwise they must be offboarded" | S6 |
| **14 days** | *Observational, unconfirmed.* O1 reports Meta stating a number must be registered within 14 days of completing Embedded Signup, after which the number must go through the flow again before registration. **I did not render a page stating this** (X1–X4 all failed). Do not publish it as a rule without confirmation. | O1 |

---

## 5. Version and deprecation notes

| Version | Introduced | Available until | Row |
|---|---|---|---|
| v2 | January 2023 | October 2026 | S5 |
| v3 | 29 May 2025 | October 2026 | S5 |
| v2-public-preview | 14 August 2025 | October 2026 | S5 |
| v3-public-preview | 14 August 2025 | October 2026 | S5 |
| **v4 (latest)** | 8 October 2025 | TBD | S5 |
| v4-public-preview | 12 May 2026 | TBD | S5 |

- **"Embedded signup v2 will be deprecated on October 15, 2026."** This banner appears on S1, S2, S3, S4 and S5.
  As of the date checked (2026-10-13) that is **two days away.** If Lynomia is on v2, this is not a
  documentation task, it is an outage countdown — flagged in the digest.
- Version is selected inside `extras` via `extras.version`, taking `v2`, `v3`, `v2-public-preview`,
  `v3-public-preview`, `v4-public-preview` or `v4` (S5).
- Moving to v4 means creating a **new** Facebook Login for Business configuration and selecting products:
  "Selecting the products will automatically set you to v4", and "The extras object is purposely empty for v4"
  (S5). Products are Marketing Messages API for WhatsApp, Click to WhatsApp Ads, and Conversions API
  (WhatsApp); v3 and v3-public-preview do not support products (S5).
- **Behavioural difference that changes Lynomia's post-flow code:** in v4 "Users can finish with a verified,
  unverified, or no phone number", whereas "v2 requires a verified phone number" (S5). Post-flow code written
  against v2 that assumes `phone_number_id` is present and verified will break on v4.
- **Screen skipping is v2-only:** "v2 lets users skip screens. v3, v3-public-preview, and v4 do not skip
  screens" (S5). The whole pre-filled-data contract (S4) is therefore v2-era.
- Versions are not exclusive, so "Partners can gradually roll out a new version to reduce risk" (S5).
- The **On-Behalf-Of ownership model is deprecated** (S13); the flow still emits `FINISH_OBO_MIGRATION` (S2).
- The Graph API version each page samples differs: S2 uses v25.0, S10 uses v25.0, S12 uses v26.0, S14 uses
  v23.0. Meta's own pages are not internally consistent on current version.
- S5 says a refreshed UI, in Public Preview, "will roll out to all Embedded Signup versions in 'early
  September'" — **with no year stated.**

---

## 6. Ambiguities and gaps

These are recorded rather than resolved, per §6.2 of the charter.

1. **The token exchange endpoint is not stated anywhere in the WhatsApp documentation I read.** S1 and S7 both
   require the exchange and both defer to Facebook Login for Business documentation (not retrieved). I have **no
   normative endpoint path, no parameter names, no `grant_type`**. Anyone documenting this step must fetch
   `developers.facebook.com/docs/facebook-login/**` first. Writing `GET /oauth/access_token?...` from memory
   would be inventing a contract.
2. **The POST form of the WABA subscription is unconfirmed.** S1 requires the step; S12 says the
   `subscribed_apps` edge supports only read and that "You can't perform this operation on this endpoint" for
   create and delete; S11 describes subscription as an App Dashboard action. O1 claims a POST exists. These do
   not reconcile on the evidence I have. **This needs arbitration** — plausibly the App Dashboard subscribes the
   app to *fields* while a per-WABA POST subscribes it to a *customer's account*, but that is my inference, not
   Meta's statement.
3. **"A number already on another WABA" is not addressed.** S9 says numbers can be migrated between WABAs; S13
   says a WABA belongs to one portfolio. No page states whether a number can sit on two WABAs, or what error
   results. Lynomia must not assert a rule here.
4. **No disallowed-country list exists in the pages I read.** The brief assumes one. S9's only country-specific
   statements are the Brazil/Mexico prefix modification and the requirement for a country code. If a country
   restriction exists, it is on a page I did not reach (candidates: X2, or Meta Business Help, which I did not
   fetch within budget).
5. **The 14-day post-signup registration window rests on a search summary only** (O1). Unconfirmed.
6. **Screens 3 and 4 of the default flow carry identical descriptions** (S3), so the actual difference between
   "business asset selection" and "business asset creation" is not documented.
7. **S1 and S3 disagree on the screen inventory.** S1 lists API selection, terms acceptance and display-name
   entry as customer steps; S3's eight-screen list contains none of them. Neither page acknowledges the other.
8. **S4 contradicts itself on `whatsAppBusinessAccount`:** the syntax section shows `ids: '<WABA_ID>'` (a
   string) while the example shows `id: [ '...' ]` (an array). S4 itself does not resolve it.
9. **S4 does not document a v4 `extras` contract**, while carrying the v2-deprecation banner. The relationship
   between S4 and v4 is "S4 does not apply", inferred from S5's "extras object is purposely empty for v4" — S4
   never says so.
10. **What Embedded Signup replaced is weakly documented.** Only OBO deprecation (S13) and
    `FINISH_OBO_MIGRATION` (S2) support a "replaced" claim. No page names a pre-v2 mechanism.
11. **The `register` response body is undocumented** (S10), and the enumerated values of the `error_code` inside
    a `CANCEL` payload are undocumented (S2).
12. **Four documentation URLs would not render** (X1–X4). The Tech Provider onboarding-customers page (X1) is
    precisely the page that should close gaps 1, 2 and 5. A follow-up pass should retry it, and should try the
    `llms.txt` index S1 links (`developers.facebook.com/documentation/business-messaging/whatsapp/llms.txt`) to
    recover canonical paths.

---

## 7. What Lynomia users would ask

Ordered by how often this area produces a ticket, with the answer's source where one exists.

| The question | Where the answer is | Answerable today? |
|---|---|---|
| "I got to the phone number screen and it says my number is already in use." | The number is on WhatsApp already; it "cannot be registered unless they are deleted first" (S9) — or, if it is on the **WhatsApp Business app**, the coexistence flow applies instead (S6) | Yes |
| "If I connect this number, do I lose WhatsApp on my phone?" | Yes for WhatsApp Messenger — a registered number "cannot be used with WhatsApp Messenger", though calls and texts still work (S9) | Yes |
| "The verification code never arrived." | Number-type table: SMS OTP is "Not Recommended" for fixed line, toll-free, VoIP, shared-cost and personal numbers; voice OTP is Standard for most of those. IVR numbers must accept international calls and redirect to a real person (S9) | Yes |
| "Can I use my landline / 1-800 / VoIP number?" | S9's type table plus the IVR rules | Yes |
| "Can I use a short code?" | No — "short codes are not supported" (S9) | Yes |
| "I don't have a business portfolio — do I need one first?" | No; create one inside the flow, subject to the portfolio limit (S1, S3) | Yes |
| "Do I need my business verified before I start?" | Not to start. Verification raises the phone-number cap from 2 to 20 (S9) and is a **provider** prerequisite (S8) | Yes |
| "My number verified but I still can't send messages." | Three candidate causes, all documented: signup "do[es] not register the number for Cloud API use" and a separate `register` call is required (S9, S10); status must be `connected` (S9); and non-Solution-Partner customers "must attach a payment method to their WABA before messaging" (S1) | Yes |
| "Why is my display name pending / rejected?" | Display name information is required at registration, and with `name_status` of `EXPIRED` or `NONE` the number "cannot be used to register the phone number for API use". After a name change, "Re-registering before approval has no effect, so wait for approval first" (S9, S10) | Yes |
| "I was asked for a 6-digit PIN I don't remember setting." | Two-step verification PIN is mandatory at registration; reuse the existing PIN if two-step is already enabled (S9, S10) | Yes |
| "I closed the window by accident — did it work?" | Closing the popup on the final screen "counts as success, not cancellation" (S2); otherwise `CANCEL` with `current_step` names where it stopped | Yes |
| "I abandoned the flow halfway. Can I resume?" | Not stated. `current_step` tells the provider where, but no resume semantics are documented | **No — gap** |
| "Why does Lynomia say my WABA isn't accessible?" | Error `200`: the app lacks advanced access to `whatsapp_business_management`, or the system user lacks asset access (S8, S12) | Yes |
| "I'm switching from another provider — can you take over my WABA?" | A WABA "must belong to only one business portfolio" and cannot be migrated between businesses, but can be shared with up to two partners (S13). Coexistence adds that "previously shared credit lines may cause an error when switching partners" (S6) | Partly |
| "Can my existing WABA from a developer app be used?" | No — "WABAs originally created via the developer app cannot be selected or onboarded through the flow" (S1) | Yes |
| "Why can I only add two numbers?" | New business portfolios are "initially capped at two registered business phone numbers", rising to 20 after verification or a 2,000 messaging limit (S9, S13) | Yes |
| "Is my country supported?" | **Not answerable from the pages read** — see §6 item 4 | **No — gap** |
| "Registration keeps failing and now nothing happens at all." | Error `133016`: more than 10 register/deregister calls per number in 72 hours blocks registration for 72 hours (S10) | Yes |
| "My customer messaged me but Lynomia didn't show it." | Coexistence `131060`: unsupported companion devices do not fire `messages` webhooks, so they cannot be mirrored — "check the WhatsApp Business app for the message" (S6) | Yes |
| "Where are my old conversations?" | Coexistence: 24 hours to synchronise history or "they must be offboarded"; each sync step runs once; `2593109` means history sharing was declined (S6) | Yes |
| "Can Lynomia stop me from editing my own WhatsApp settings?" | No — customers "own their WhatsApp assets and have full WhatsApp Manager access, which you cannot restrict" (S1) | Yes |
| "Why is my throughput capped at 20 messages per second?" | Coexistence numbers have a fixed 20 mps throughput (S6) | Yes |
