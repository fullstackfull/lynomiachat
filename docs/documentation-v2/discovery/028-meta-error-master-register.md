---
agent: 028
scope: Cross-Meta error-code master auditor — the program's single authoritative error register, and an audit of agents 001–027 against it
confidence: high
sources_normative: 12
sources_observational: 3
---

# 028 — Meta error-code master register and cross-agent audit

I collected first and read other agents second, so nothing below was anchored to another agent's claim. Every
code in §3 was read on a `developers.facebook.com` page I rendered myself on 2026-10-13. Where I could not
render a page, the row says so and the code is **not** in the register.

The single most important structural fact, and the one that governs how every other agent's table must be
read: **Meta's WhatsApp Cloud API error-code reference does not publish titles.** Its tables are
`Code | details | Possible reasons and solutions` (S1). The webhook reference confirms the direction of travel —
`title` and `message` carry *the same text* and `error_data.details` is the field with the real cause (S6). So
any report whose column is "Title as Meta words it" is, for Cloud API codes, quoting `details` or quoting
nothing. Several reports handled this correctly and said `not stated`; one did not (§9).

---

## 1. Source register

| # | Source URL | Page title | Product | API / version context | Date checked | Status |
|---|---|---|---|---|---|---|
| S1 | https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/ | Error codes | WhatsApp Cloud API + Marketing Messages API | `error_subcode` not returned v16.0+; some MM codes v23.0+ | 2026-10-13 | normative |
| S2 | https://developers.facebook.com/documentation/business-messaging/whatsapp/groups/error-codes.md | Groups API Error Codes and Troubleshooting | WhatsApp Business Platform (Groups API) | none stated | 2026-10-13 | normative |
| S3 | https://developers.facebook.com/docs/whatsapp/flows/reference/error-codes | WhatsApp Flows error codes | WhatsApp Flows (Management API, Cloud API, business endpoint, client) | Flow JSON ≥ 3.0 noted | 2026-10-13 | normative |
| S4 | https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/errors.md | Embedded Signup Flow Errors | WhatsApp Business Platform (Embedded Signup) | none stated | 2026-10-13 | normative |
| S5 | https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/authentication-templates/error-signals.md | Error Signals | WhatsApp Cloud API + Android SDK | Android; `com.whatsapp.OTP_ERROR` | 2026-10-13 | normative |
| S6 | https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/errors.md | Errors messages webhooks reference | WhatsApp Cloud API (webhooks) | none stated | 2026-10-13 | normative |
| S7 | https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users/ | Onboard WhatsApp Business app users | WhatsApp Business Platform (coexistence) | session payload `version: 3` | 2026-10-13 | normative |
| S8 | https://developers.facebook.com/documentation/business-messaging/whatsapp/business-phone-numbers/media.md | Media | WhatsApp Cloud API | `POST /<API_VERSION>/<PHONE_NUMBER_ID>/media` | 2026-10-13 | normative |
| S9 | https://developers.facebook.com/docs/graph-api/guides/error-handling/ | Handle Errors — Graph API | Graph API | no version stated on page | 2026-10-13 | normative |
| S10 | https://developers.facebook.com/docs/graph-api/overview/rate-limiting | Rate Limits — Graph API | Graph API | no version stated | 2026-10-13 | normative |
| S11 | https://developers.facebook.com/docs/messenger-platform/reference/send-api/error-codes/ | Common Error Codes | Messenger Platform **and Instagram Messaging** | no version stated | 2026-10-13 | normative |
| S12 | https://developers.facebook.com/docs/graph-api/changelog | Changelog — Graph API | Graph API | v13.0–v26.0 | 2026-10-13 | normative |
| S13 | https://developers.facebook.com/documentation/business-messaging/whatsapp/llms.txt | WhatsApp docs index | WhatsApp Business Platform | — | 2026-10-13 | normative (index only; used to locate S2/S4/S5/S6) |
| O1 | WebSearch for `"131060" WhatsApp Cloud API error code` | — | — | — | 2026-10-13 | **observational** — only third-party vendor help pages returned; used solely to establish *absence* from Meta's reference |
| O2 | WebSearch for an Instagram Platform error-codes reference (`developers.facebook.com` only) | — | — | — | 2026-10-13 | **observational** — establishes that no such dedicated page surfaced |
| X1 | https://developers.facebook.com/docs/instagram-platform/reference/error-codes (and `/` variant) | — | — | — | 2026-10-13 | **HTTP 404 — does not exist** |
| X2 | https://developers.facebook.com/docs/messenger-platform/instagram/features/error-codes | — | — | — | 2026-10-13 | **HTTP 404 — does not exist** |
| X3 | https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/components | messages webhook reference | WhatsApp Cloud API | — | 2026-10-13 | normative but **does not define the `errors` fields**; it points at S6 |

**Finding that matters to agents 023/024 and 042**: there is **no dedicated Instagram error-code reference on
Meta's site**. X1 and X2 both 404, and O2 surfaced none. Instagram Messaging error codes are published on the
**Messenger Platform** page S11, as the `2534xxx` subcode family plus code `36103`. Any report that cites an
"Instagram error codes page" is citing a page that does not exist.

---

## 2. The rules — what the error surface actually is

Four shapes, and conflating them is the main hazard in this area.

1. **A synchronous Graph error.** `error.code`, optional `error.error_subcode`, `type` (e.g. `OAuthException`),
   `message`, `fbtrace_id`, and optionally `error_user_title` / `error_user_msg` whose language follows the
   request locale (S9). `error_subcode` is **not returned in v16.0+ WhatsApp responses** (S1).
2. **An asynchronous webhook error.** `errors[]` with `code`, `title`, `message`, `error_data.details`, `href`
   (S6). S6 states plainly that `title` and `message` hold **the same text**, and that `error_data.details` is
   the longer explanation. It appears in three places: `value.errors` (system/app/account), `value.messages.errors`
   (inbound, with `type: unsupported`), and `value.statuses.errors` (outbound failure) (X3).
3. **A string identifier, not a number.** Flows client-side (`timeout_error`, `payload-schema-error`, …) (S3),
   authentication-template OTP signals (`otp_request_expired`, …) (S5), Embedded Signup abandonment steps
   (`PHONE_NUMBER_VERIFICATION`, …) (S4), and the display-name rejection reasons.
4. **A prose-only failure with no code at all.** Most of Embedded Signup (S4) is a message string and nothing
   else, and the error-codes reference carries none of it.

A documentation system that treats "Meta error" as "a number on the Cloud API error-codes page" will miss three
of these four shapes. That is the central coverage argument in §14.

---

## 3. The master error register

One table per product, as the deliverable asks, with the source row and date on every line. `details`/`title`
quotes are Meta's own words where I read them verbatim; `paraphrase` marks a condensed description; `no title
given` means Meta publishes a code with no short name.

### 3.1 WhatsApp Cloud API + Marketing Messages API (S1 unless noted)

| Product | Code | Subcode | Meta's own title / `details` | Source | Checked |
|---|---|---|---|---|---|
| WA Cloud | 0 | — | paraphrase: app user could not be authenticated; token expired/invalidated or user restricted app access | S1 | 2026-10-13 |
| WA Cloud | 3 | — | paraphrase: capability or permissions issue | S1 | 2026-10-13 |
| WA Cloud | 10 | — | paraphrase: permission not granted or removed; also ineligible API access | S1 | 2026-10-13 |
| WA Cloud | 190 | — | "Your access token has expired." | S1 | 2026-10-13 |
| WA Cloud | 200 | — | paraphrase: no access token provided; some GETs say provide a valid app ID | S1 | 2026-10-13 |
| WA Cloud | 200–299 | — | paraphrase: permission not granted or removed (range) | S1 | 2026-10-13 |
| WA Cloud | 368 | — | paraphrase: WABA restricted or disabled for a platform policy violation | S1 | 2026-10-13 |
| WA Cloud | 130497 | — | paraphrase: WABA restricted from messaging users in certain countries | S1 | 2026-10-13 |
| WA Cloud | 131031 | — | paraphrase: WABA restricted/disabled for policy violation, or request data failed verification (e.g. wrong two-step PIN) | S1 | 2026-10-13 |
| WA Cloud | 4 | — | paraphrase: app reached its API call rate limit | S1 | 2026-10-13 |
| WA Cloud | 80007 | — | paraphrase: WABA reached its rate limit | S1 | 2026-10-13 |
| WA Cloud | 130429 | — | "Rate limit hit" *(the one title S1 prints; also S6's example)* | S1, S6 | 2026-10-13 |
| WA Cloud | 131048 | — | "Message failed to send because there are restrictions on how many messages can be sent from this phone number." | S1 | 2026-10-13 |
| WA Cloud | 131056 | — | paraphrase: too many messages between the same sender and recipient in a short period | S1 | 2026-10-13 |
| WA Cloud | 131064 | — | paraphrase: messaging limit reached due to template classification violations | S1 | 2026-10-13 |
| WA Cloud | 133016 | — | paraphrase: too many registration/deregistration attempts for this number | S1 | 2026-10-13 |
| WA Cloud | 1 | — | paraphrase: invalid request or possible server error | S1 | 2026-10-13 |
| WA Cloud | 2 | — | paraphrase: temporary downtime or overload | S1 | 2026-10-13 |
| WA Cloud | 33 | — | paraphrase: business phone number deleted | S1 | 2026-10-13 |
| WA Cloud | 100 | — | "The request included one or more unsupported or misspelled parameters." | S1 | 2026-10-13 |
| WA Cloud | 130403 | — | paraphrase: business blocked the end user on WhatsApp; do not retry | S1 | 2026-10-13 |
| WA Cloud | 130472 | — | paraphrase: message not sent as part of an experiment | S1 | 2026-10-13 |
| WA Cloud | 131000 | — | paraphrase: unknown error; retry or contact Direct Support | S1 | 2026-10-13 |
| WA Cloud | 131005 | — | paraphrase: permission not granted or removed | S1 | 2026-10-13 |
| WA Cloud | 131008 | — | "The request is missing a required parameter." | S1 | 2026-10-13 |
| WA Cloud | 131009 | — | "One or more parameter values are invalid." | S1 | 2026-10-13 |
| WA Cloud | 131016 | — | paraphrase: service temporarily unavailable | S1 | 2026-10-13 |
| WA Cloud | 131021 | — | paraphrase: sender and recipient numbers are the same | S1 | 2026-10-13 |
| WA Cloud | 131026 | — | "Unable to deliver message. Reasons can include:" *(S1's text is an open list: non-WhatsApp number, terms not accepted, outdated client)* | S1 | 2026-10-13 |
| WA Cloud | 131037 | — | paraphrase: a 555 test number lacks an approved display name | S1 | 2026-10-13 |
| WA Cloud | 131042 | — | "There was an error related to your payment method." | S1 | 2026-10-13 |
| WA Cloud | 131045 | — | paraphrase: phone number registration error | S1 | 2026-10-13 |
| WA Cloud | 131047 | — | "More than 24 hours have passed since the recipient last replied to the sender number." | S1 | 2026-10-13 |
| WA Cloud | 131049 | — | "This message was not delivered to maintain healthy ecosystem engagement." | S1 | 2026-10-13 |
| WA Cloud | 131050 | — | "Unable to deliver the message. This recipient has chosen to stop receiving marketing messages on WhatsApp from your business." | S1 | 2026-10-13 |
| WA Cloud | 131051 | — | paraphrase: unsupported message type | S1 | 2026-10-13 |
| WA Cloud | 131052 | — | "Unable to download the media sent by the user." / on S8: "Media file size too big. Max file size we currently support: 100MB." | S1, S8 | 2026-10-13 |
| WA Cloud | 131053 | — | "Unable to upload the media used in the message." / on S8: "Note that mismatched MIME type (`131053`) is a common error." | S1, S8 | 2026-10-13 |
| WA Cloud | 131057 | — | paraphrase: business account in maintenance mode | S1 | 2026-10-13 |
| WA Cloud | 131060 | — | **no title given.** S7: "you may receive an unsupported messages webhook with error code `131060`" — expected on a user's first message, or from an unsupported companion device. **Absent from S1.** | S7 | 2026-10-13 |
| WA Cloud | 131063 | — | paraphrase: marketing templates disabled on Cloud API for this configuration | S1 | 2026-10-13 |
| WA Cloud | 132000 | — | paraphrase: variable parameter count does not match the template | S1 | 2026-10-13 |
| WA Cloud | 132001 | — | paraphrase: template does not exist in that language, or is not approved | S1 | 2026-10-13 |
| WA Cloud | 132005 | — | paraphrase: translated text too long | S1 | 2026-10-13 |
| WA Cloud | 132007 | — | paraphrase: template content violates a WhatsApp policy | S1 | 2026-10-13 |
| WA Cloud | 132012 | — | paraphrase: variable parameter values formatted incorrectly | S1 | 2026-10-13 |
| WA Cloud | 132015 | — | paraphrase: template paused for low quality, so it cannot be sent | S1 | 2026-10-13 |
| WA Cloud | 132016 | — | paraphrase: template paused too many times and is now permanently disabled | S1 | 2026-10-13 |
| WA Cloud | 132068 | — | "Flow is blocked" | S1, S3 | 2026-10-13 |
| WA Cloud | 132069 | — | "Flow is throttled" — 10 messages using the Flow already sent in the last hour | S1, S3 | 2026-10-13 |
| WA Cloud | 133000 | — | paraphrase: a previous deregistration attempt failed | S1 | 2026-10-13 |
| WA Cloud | 133004 | — | paraphrase: server temporarily unavailable | S1 | 2026-10-13 |
| WA Cloud | 133005 | — | paraphrase: two-step verification PIN incorrect | S1 | 2026-10-13 |
| WA Cloud | 133006 | — | paraphrase: phone number must be verified before registering | S1 | 2026-10-13 |
| WA Cloud | 133008 | — | paraphrase: too many two-step PIN guesses | S1 | 2026-10-13 |
| WA Cloud | 133009 | — | paraphrase: two-step PIN entered too quickly | S1 | 2026-10-13 |
| WA Cloud | 133010 | — | paraphrase: phone number not registered on the platform | S1 | 2026-10-13 |
| WA Cloud | 133015 | — | paraphrase: number recently deleted; wait 5 minutes | S1 | 2026-10-13 |
| WA Cloud | 134011 | — | paraphrase: WhatsApp Payments terms acceptance pending | S1 | 2026-10-13 |
| WA Cloud | 135000 | — | paraphrase: unknown error with request parameters | S1 | 2026-10-13 |
| WA Mgmt | 2388012 | — | paraphrase: phone number already exists in the WhatsApp account | S1 | 2026-10-13 |
| WA Mgmt | 2388019 | — | paraphrase: template limit reached (up to 250 per WABA) | S1 | 2026-10-13 |
| WA Mgmt | 2388039 | — | paraphrase: template status cannot be changed (e.g. still in review) | S1 | 2026-10-13 |
| WA Mgmt | 2388040 | — | paraphrase: a template field exceeds its character limit | S1 | 2026-10-13 |
| WA Mgmt | 2388047 | — | paraphrase: header formatting invalid | S1 | 2026-10-13 |
| WA Mgmt | 2388072 | — | paraphrase: body formatting invalid | S1 | 2026-10-13 |
| WA Mgmt | 2388073 | — | paraphrase: footer formatting invalid | S1 | 2026-10-13 |
| WA Mgmt | 2388091 | — | "Code Couldn't Be Sent" (S4) / S1: number not eligible for code verification because it is not being migrated | S1, S4 | 2026-10-13 |
| WA Mgmt | 2388093 | — | "Code Couldn't Be Verified" (S4) / S1: as 2388091 | S1, S4 | 2026-10-13 |
| WA Mgmt | 2388103 | — | paraphrase: migration blocked — nine distinct stated causes, each with its own message | S1 | 2026-10-13 |
| WA Mgmt | 2388293 | — | paraphrase: too many variables for the template's length | S1 | 2026-10-13 |
| WA Mgmt | 2388299 | — | paraphrase: variables placed at the start or end of the template | S1 | 2026-10-13 |
| WA Mgmt | 2494100 | — | paraphrase: phone number in maintenance mode | S1 | 2026-10-13 |
| WA Mgmt | 200005 | — | paraphrase: template insights unavailable for this WABA | S1 | 2026-10-13 |
| WA Mgmt | 200006 | — | paraphrase: template insights cannot be disabled once enabled | S1 | 2026-10-13 |
| WA Mgmt | 200007 | — | paraphrase: template insights not enabled for this WABA | S1 | 2026-10-13 |
| WA Mgmt | 2593107 | — | paraphrase: maximum synchronization API calls exceeded for this number | S1 | 2026-10-13 |
| WA Mgmt | 2593108 | — | paraphrase: synchronization requested outside the 24-hour post-onboarding window | S1 | 2026-10-13 |
| WA coexist | 2593109 | — | "History sync is turned off by the business from the WhatsApp Business App." | S7 | 2026-10-13 |
| WA MM API | 100 | — | "(#100) Invalid parameter" — non-template message sent; use `template`. HTTP 400 | S1 | 2026-10-13 |
| WA MM API | 131009 | — | "(#131009) Parameter value is not valid" — ad syncing may be incomplete; wait 10 min. HTTP 400 | S1 | 2026-10-13 |
| WA MM API | 131055 | — | "(#131055) Method not allowed" — only marketing templates. HTTP 400 | S1 | 2026-10-13 |
| WA MM API | 132018 | — | "(#132018) Template validation error". HTTP 400 | S1 | 2026-10-13 |
| WA MM API | 134100 | — | "(#134100) Only marketing messages supported" (v23.0+). HTTP 400 | S1 | 2026-10-13 |
| WA MM API | 134101 | — | "(#134101) Your template is still syncing" (v23.0+). HTTP 400 | S1 | 2026-10-13 |
| WA MM API | 134102 | — | "(#134102) Template unavailable for use" (v23.0+). HTTP **500** | S1 | 2026-10-13 |
| WA MM API | 1752041 | — | "(#1752041) Duplicate Request" — client already invited to onboard by a partner. HTTP 400 | S1 | 2026-10-13 |

### 3.2 WhatsApp Groups API (S2) — a complete family no agent brief covers

| Product | Code | Meta's own title | HTTP | Source | Checked |
|---|---|---|---|---|---|
| WA Groups | 131020 | "Bad Group" | 400 | S2 | 2026-10-13 |
| WA Groups | 131041 | "Group unknown" | 400 | S2 | 2026-10-13 |
| WA Groups | 131059 | "Invalid cursor" | 400 | S2 | 2026-10-13 |
| WA Groups | 131201 | "Request partially succeeded" | 206 | S2 | 2026-10-13 |
| WA Groups | 131202 | "Duplicate participant" | 400 | S2 | 2026-10-13 |
| WA Groups | 131204 | "Participant overlimit" | 400 | S2 | 2026-10-13 |
| WA Groups | 131207 | "Group suspended" | 403 | S2 | 2026-10-13 |
| WA Groups | 131208 | "Group Rate Limit Hit" | 429 | S2 | 2026-10-13 |
| WA Groups | 131209 | "Invalid Group Profile Picture Aspect Ratio" | 400 | S2 | 2026-10-13 |
| WA Groups | 131210 | "Image is Too Small to Process" | 400 | S2 | 2026-10-13 |
| WA Groups | 131211 | "Group create limit reached" | 400 | S2 | 2026-10-13 |
| WA Groups | 131212 | "Participant is not a part of the group." | 400 | S2 | 2026-10-13 |
| WA Groups | 131213 | "Group join request does not exist." | 400 | S2 | 2026-10-13 |
| WA Groups | 131214 | "Group creation is temporarily disabled" — too many marketing messages in the service window over 7 days | 400 | S2 | 2026-10-13 |
| WA Groups | 131215 | "This phone number is not eligible to access Groups APIs" | 400 | S2 | 2026-10-13 |

### 3.3 WhatsApp Flows (S3)

| Surface | Code | Meta's own title | Source | Checked |
|---|---|---|---|---|
| Flows Mgmt | 100 | "Flow name is not unique"; "Invalid Flow JSON version"; "Invalid Flow JSON `data_api_version`"; "Flow with specified ID does not exist"; "Only one clone source can be set"; "Specify Endpoint Uri in Flow JSON"; "Invalid Endpoint URI" *(seven distinct titles under one code)* | S3 | 2026-10-13 |
| Flows Mgmt | 139000 | "Blocked By Integrity" | S3 | 2026-10-13 |
| Flows Mgmt | 139001 | "Flow can't be updated"; "Error while processing Flow JSON"; "Specify Endpoint Uri in Flow JSON" | S3 | 2026-10-13 |
| Flows Mgmt | 139002 | "Publishing Flow in invalid state" + 9 further titled variants (validation errors, missing `data_channel_uri`, missing `endpoint_uri`, unsupported version, no phone number, "Missing Flows Signed Public Key", "No Application Connected to the Flow", "Endpoint Not Available", webhook not subscribed) | S3 | 2026-10-13 |
| Flows Mgmt | 139003 | "Can't deprecate unpublished flow"; "Flow is already deprecated" | S3 | 2026-10-13 |
| Flows Mgmt | 139004 | "Can't delete published Flow" | S3 | 2026-10-13 |
| Business endpoint | HTTP 421 | no title given — payload cannot be decrypted | S3 | 2026-10-13 |
| Business endpoint | HTTP 427 | no title given — flow token no longer valid; CTA disabled | S3 | 2026-10-13 |
| Business endpoint | HTTP 432 | no title given — request signature authentication failed | S3 | 2026-10-13 |
| Client/webhook | `timeout_error`, `missing_capability`, `cannot_be_served`, `no_http_response_error`, `unexpected_http_status_code`, `public-key-missing`, `public-key-signiture-verification` *(Meta's own misspelling)*, `response-decryption-error`, `invalid-screen-transition`, `payload-schema-error`, `business-decryption-error` | — | string identifiers, not numbers | S3 | 2026-10-13 |

### 3.4 WhatsApp Embedded Signup (S4) — ~90 coded errors, plus prose-only and step identifiers

S4 is the largest single error page in Meta's WhatsApp documentation and **no report in the discovery directory
cites it**. I am not reproducing all ~90 rows verbatim; the register records the family, its codes, and the
page, which is what the program needs to stop an agent inventing one.

Coded (all S4, 2026-10-13), grouped by what they block:

- **Ad-account / payment**: 2655081, 2655055, 1752004, 1752140, 2455008, 2494149, 2446325, 1690214, 1784028, 1404163
- **Business portfolio creation / naming**: 1690114, 1752089, 1690089, 1690091, 1690062, 1690090, 2655091, 1690061, 1690181, 1752069, 1752206, 1752224, 1349246
- **WABA creation / limits / naming**: 2388098, 2494067, 2593010, 2388010, 2388009, 2593030, 2593072, 3771014
- **Phone number eligibility / linkage**: 3441041, 3441045, 2655095, 2655048, 3441042, 2655093, 2655082, 3441049, 3441030, 3441047, 3441051, 2655011, 2388002, 2655076, 2655005, 2593035, 2388107, 4563015, 2655094
- **Verification code**: 2593037, 2593039, 2494158, 2388091, 2388093
- **Business verification / partner sharing**: 2494030, 2494143, 2655049, 2494029, 2494028, 2494091, 2494120, 2494119
- **Rate / abuse / security**: 3441033, 3441046, 1390006, 1675004, 1390008, 2859015, 2859009, 2859043, 2136001, 4612001, 1357053
- **Misc / transient**: 1675030, 1675012, 3441003, 4056009, 2655069, 2494102, 2655089, 3441040

Prose-only failures (no code at all) across Meta Business Suite account creation, WABA creation, phone setup and
phone verification: S4 lists roughly 25 message strings with no numeric code. Abandonment step identifiers on the
`CANCEL` event's `data.current_step`: `BUSINESS_ACCOUNT_SELECTION`, `WABA_PHONE_PROFILE_PICKER`,
`WHATSAPP_BUSINESS_PROFILE_SETUP`, `PHONE_NUMBER_SETUP`, `PHONE_NUMBER_VERIFICATION`, `PERMISSIONS` (S4).

### 3.5 WhatsApp authentication-template OTP error signals (S5) — Android, string keys

`ambiguous_delivery_destination` (emulator only), `incompatible_os_version`, `incorrect_signature_hash`
(emulator only), `missing_handshake_or_disorder`, `otp_request_expired`,
`whatsapp_message_notification_disabled` (emulator only), `whatsapp_notification_disabled` (emulator only).
Delivered as broadcast intents on `com.whatsapp.OTP_ERROR` with `error` and `error_message` extras (S5,
2026-10-13). **No Lynomia surface can produce these** — they require the business's own Android app. Noted so
no agent treats them as send failures.

### 3.6 Graph API (S9, S10)

| Product | Code | Subcode | Meta's own title / wording | Source | Checked |
|---|---|---|---|---|---|
| Graph | — | — | `OAuthException` type with no subcode — login status or token expired, revoked or otherwise invalid | S9 | 2026-10-13 |
| Graph | 102 | — | "API Session" | S9 | 2026-10-13 |
| Graph | 1 | — | "API Unknown" | S9 | 2026-10-13 |
| Graph | 2 | — | "API Service" | S9 | 2026-10-13 |
| Graph | 3 | — | "API Method" | S9 | 2026-10-13 |
| Graph | 4 | — | "API Too Many Calls" — "the app whose token is being used in the request has reached its rate limit" | S9, S10 | 2026-10-13 |
| Graph | 10 | — | "API Permission Denied" — "Permission is either not granted or has been removed." | S9 | 2026-10-13 |
| Graph | 17 | — | "API User Too Many Calls" — user-token rate limit | S9, S10 | 2026-10-13 |
| Graph | 17 | 2446079 | Ads API v3.3-and-older ad-account rate limit | S10 | 2026-10-13 |
| Graph | 32 | — | Page rate limit (Pages API, user or app token) | S10 | 2026-10-13 |
| Graph | 190 | — | "Access token has expired" | S9 | 2026-10-13 |
| Graph | 190/102 | 458 | "App Not Installed" | S9 | 2026-10-13 |
| Graph | 190/102 | 459 | "User Checkpointed" | S9 | 2026-10-13 |
| Graph | 190/102 | 460 | "Password Changed" | S9 | 2026-10-13 |
| Graph | 190/102 | 463 | "Expired" | S9 | 2026-10-13 |
| Graph | 190/102 | 464 | "Unconfirmed User" | S9 | 2026-10-13 |
| Graph | 190/102 | 467 | "Invalid Access Token" | S9 | 2026-10-13 |
| Graph | 190/102 | 492 | "Invalid Session" — "The user tied to the Page access token lacks an appropriate Page role" | S9 | 2026-10-13 |
| Graph | 200–299 | — | "API Permission" | S9 | 2026-10-13 |
| Graph | 341 | — | "Application limit reached" | S9 | 2026-10-13 |
| Graph | 368 | — | "Temporarily blocked for policies violations" | S9 | 2026-10-13 |
| Graph | 506 | — | "Duplicate Post" | S9 | 2026-10-13 |
| Graph | 613 | — | "Indicates that a custom rate limit has been reached." | S10 | 2026-10-13 |
| Graph | 613 | 1996 | inconsistent API request volume noticed for the app | S10 | 2026-10-13 |
| Graph | 1609005 | — | "Error Posting Link" | S9 | 2026-10-13 |
| Graph BUC | 80000 | 2446079 | Ads Insights BUC limit | S10 | 2026-10-13 |
| Graph BUC | 80001 | — | Page calls with a Page or System User token | S10 | 2026-10-13 |
| Graph BUC | 80002 | — | **Instagram** BUC limit | S10 | 2026-10-13 |
| Graph BUC | 80003 | 2446079 | Custom Audience | S10 | 2026-10-13 |
| Graph BUC | 80004 | 2446079 | Ads Management | S10 | 2026-10-13 |
| Graph BUC | 80005 | — | LeadGen | S10 | 2026-10-13 |
| Graph BUC | 80006 | — | **Messenger** BUC limit | S10 | 2026-10-13 |
| Graph BUC | 80008 | — | **WhatsApp Business Management API** BUC limit | S10 | 2026-10-13 |
| Graph BUC | 80009 | — | Catalog Management | S10 | 2026-10-13 |
| Graph BUC | 80014 | — | Catalog Batch | S10 | 2026-10-13 |

Subcode `1349244` does **not** appear on S10; S10 states no CRM rate-limit type.

### 3.7 Messenger Platform and Instagram Messaging (S11) — one shared page

S11's table is `Code – Subcode | Message | Possible Solution`, so the "Message" strings below are Meta's own.
**The `2534xxx` subcodes and code `36103` are the Instagram Messaging rows**; everything else is Messenger, with
the Instant Games and SDK rows applying to neither Lynomia channel.

| Product | Code | Subcode | Meta's own message | Source | Checked |
|---|---|---|---|---|---|
| Messenger | 1 | 1–99 | "An unknown error occurred." | S11 | 2026-10-13 |
| Messenger | 1 | 1357046 | "Received invalid JSON reply." | S11 | 2026-10-13 |
| Messenger | 2 | — | "An unexpected error has occurred. Please retry your request later." | S11 | 2026-10-13 |
| Messenger | 2 | 2018344 | "Service temporarily unavailable" (Privacy ToS) | S11 | 2026-10-13 |
| Messenger | 4 | — | "Rate Limit error: Application request limit reached."; "Too many send requests to phone numbers" | S11 | 2026-10-13 |
| Messenger | 4 | 2018354 | minimum delay required between two Marketing Messages notifications | S11 | 2026-10-13 |
| Messenger | 9 | 2018352 | "User is performing too many actions" | S11 | 2026-10-13 |
| Messenger | 10 | — | "No Permission For Pages Associated to Instant Games." | S11 | 2026-10-13 |
| Messenger | 10 | 1404170 | "Application does not have permission for this action" | S11 | 2026-10-13 |
| Messenger | 10 | 1893015 | "(#10) This user has currently stopped notification messages for this topic" | S11 | 2026-10-13 |
| Messenger | 10 | 1893063 | "You are temporarily restricted from sending messages." | S11 | 2026-10-13 |
| Messenger | 10 | 2018336 | "User Thread Impact" | S11 | 2026-10-13 |
| Messenger | 10 | 2018065 | "This message is sent outside of allowed window." (News Messaging) | S11 | 2026-10-13 |
| Messenger | 10 | 2018108 | "They can't receive your messages right now." | S11 | 2026-10-13 |
| Messenger | 10 | 2018278 | "This message is sent outside of allowed window." | S11 | 2026-10-13 |
| **Instagram** | 10 | 2534022 | "This message is sent outside of allowed window." | S11 | 2026-10-13 |
| **Instagram** | 10 | 2534077 | "Cannot verify the connection between the IG account, the logged in user and the page." | S11 | 2026-10-13 |
| Messenger | 100 | — | "Bad Parameter Error: Invalid FBID."; "No matching user found."; `notification_messages_token` invalid / expired | S11 | 2026-10-13 |
| Messenger | 100 | 33 | "Unsupported get request. Object with ID * does not exist, cannot be loaded due to missing permissions…" | S11 | 2026-10-13 |
| Messenger | 100 | 2018001 | "No matching user found" | S11 | 2026-10-13 |
| Messenger | 100 | 2018008 | "Failed to fetch the file from the url." | S11 | 2026-10-13 |
| Messenger | 100 | 2018014 | "Cannot send both message and state at the same time." | S11 | 2026-10-13 |
| Messenger | 100 | 2018047 | "Upload attachment failure." | S11 | 2026-10-13 |
| Messenger | 100 | 2018074 | "Possible invalid ID or you do not own the attachment." | S11 | 2026-10-13 |
| Messenger | 100 | 2018109 | "Attachment size exceeds allowable limit" | S11 | 2026-10-13 |
| Messenger | 100 | 2018164 | "Incorrect App ID." | S11 | 2026-10-13 |
| Messenger | 100 | 2018294 | "Video upload timed out or video is corrupted." | S11 | 2026-10-13 |
| Messenger | 100 | 2018320 | "Invalid product id" | S11 | 2026-10-13 |
| Messenger | 100 | 2018328 | "Product template is not supported below version 8." | S11 | 2026-10-13 |
| **Instagram** | 100 | 2534013 | "The page is not linked to an Instagram account" | S11 | 2026-10-13 |
| **Instagram** | 100 | 2534014 | "No matching Instagram user" | S11 | 2026-10-13 |
| **Instagram** | 100 | 2534015 | "Invalid message data" | S11 | 2026-10-13 |
| **Instagram** | 100 | 2534025 | "The comment is invalid for a private reply" | S11 | 2026-10-13 |
| **Instagram** | 100 | 2534029 | "The business has been blocked from sending messages via the IG Messaging API" | S11 | 2026-10-13 |
| **Instagram** | 100 | 2534037 | "The action is invalid since it's not the thread owner." | S11 | 2026-10-13 |
| Messenger | 190 | — | "Access Token Error: Invalid OAuth access token." | S11 | 2026-10-13 |
| Messenger | 200 | — | "Permission Error: Cannot message users who are not admins, developers or testers of the app…" | S11 | 2026-10-13 |
| Messenger | 200 | 1545041 | "Message Not Sent: This person isn't available right now." | S11 | 2026-10-13 |
| Messenger | 200 | 2018021 | "Requires phone matching access fee to be paid by this page…" | S11 | 2026-10-13 |
| Messenger | 200 | 2018027 | app-tester-only restriction (`pages_messaging_phone_number`) | S11 | 2026-10-13 |
| Messenger | 200 | 2018028 | app-tester-only restriction (`pages_messaging`) | S11 | 2026-10-13 |
| **Instagram** | 200 | 2534041 | "The account owner has disabled access to instagram direct messages." | S11 | 2026-10-13 |
| Messenger | 551 | — | "User Block Error: This person isn't receiving messages from you right now." | S11 | 2026-10-13 |
| Messenger | 551 | 1545041 | "This person isn't available right now." | S11 | 2026-10-13 |
| Messenger | 613 | 1893016 | "Scope of service exceeded: You may not send multiple opt–in requests with the same topic to a user." | S11 | 2026-10-13 |
| Messenger | 613 | 2018338 | "Warning! You are engaging in behavior that may be considered bothersome or abusive by users." | S11 | 2026-10-13 |
| **Instagram** | 613 | 2534040 | "Calls to this api have exceeded the rate limit." | S11 | 2026-10-13 |
| Messenger | 2022 | — | "The ability to send commerce messages has been temporarily disabled." | S11 | 2026-10-13 |
| Messenger | 10303 | — | "Account Linking Error: Invalid account_linking_token." | S11 | 2026-10-13 |
| Messenger | 24001 | — | "User canceled payment flow" | S11 | 2026-10-13 |
| Messenger | 24002 | — | "Payment request cannot be processed due to missing privacy url" | S11 | 2026-10-13 |
| Messenger | 24005 | — | "Failed to get user ID" | S11 | 2026-10-13 |
| **Instagram** | 36103 | — | "This IG account is not eligible for API yet" | S11 | 2026-10-13 |
| Messenger | 2018144 | — | Instant Games notification cap (5 notifications) | S11 | 2026-10-13 |
| Messenger | 2018154 | — | "Messenger Extensions unexpected error" | S11 | 2026-10-13 |
| Messenger | 2018163 | — | "Begin Share Param Validation Error" | S11 | 2026-10-13 |
| Messenger | 2018166 | — | "Permission not valid to call the SDK API" | S11 | 2026-10-13 |
| Messenger | 2018171 | — | "Only available to Primary and Secondary Receivers." | S11 | 2026-10-13 |
| Messenger | 2018218 | — | "No profile available for this user." | S11 | 2026-10-13 |
| Messenger | 2018234 | — | secondary receiver cannot see another secondary receiver | S11 | 2026-10-13 |
| Messenger | 2018247 | — | "Insufficient permission to access user profile." | S11 | 2026-10-13 |
| Messenger | 2018300 | — | "Message failed to send because another app is controlling this thread now." | S11 | 2026-10-13 |
| Messenger | 2018321 | — | thread controlled by Messenger during an automated Q&A flow | S11 | 2026-10-13 |
| Messenger | 2071010–2071025 | — | 16 Messenger-Extensions / share-flow SDK validation messages | S11 | 2026-10-13 |
| Messenger | 2018389–2018396 | — | 8 calling errors ("Page Not Allowlisted", "Invalid call id", "Invalid connection parameter", "Invalid SDP parameter", "Invalid call participant page", "Insufficient permissions to join call", "Cannot join failed call", "Cannot join ended call") | S11 | 2026-10-13 |
| Messenger | *(S11 prints `TBD`)* | — | "Call rate limit exceeded" — **Meta has not assigned a code**; record as `not stated`, never as a number | S11 | 2026-10-13 |
| Messenger | 9000001 | — | "This Message has been deleted by the user or the business." | S11 | 2026-10-13 |

---

## 4. Limits and numbers

Only numbers a source states.

| Number | What it bounds | Source |
|---|---|---|
| 250 | message templates per WABA (code 2388019) | S1 |
| 100 MB | inbound media file size; over it fires code 131052 | S8 |
| 10 messages / hour | Flow sends before code 132069 | S1, S3 |
| 10 seconds | Flows endpoint response budget before `timeout_error` | S3 |
| 10 minutes | Marketing Messages template ad-sync wait (134101); also the OTP handshake window | S1, S5 |
| 24 hours | service window (131047); synchronization window after onboarding (2593108) | S1 |
| 5 minutes | wait after number deletion (133015) | S1 |
| 192 px | minimum group profile-picture dimension (131210) | S2 |
| 7 days | Groups marketing-message lookback that disables group creation (131214) | S2 |
| 255 characters | WABA name length (2593010) | S4 |
| ~12 hours | wait after too many wrong verification codes | S4 |
| 32 | maximum objects in an `X-Business-Use-Case-Usage` response | S10 |
| 1 hour | rolling window for `call_count` in the usage headers | S10 |

I did **not** verify the widely repeated "72-hour / 10 attempts" figure for 133016 (agents 013 and 014 both
state it, citing the registration reference). S1 gives 133016 without numbers. Treat the figure as **owned by
agents 013/014 and not corroborated here**.

---

## 5. Version and deprecation notes

- Latest Graph API version is **v26.0** (introduced 2026-07-29, no end date). v25.0 runs to 2028-07-29 (S12).
- **v18.0 expired 2026-01-26 and v19.0 expired 2026-05-21** — both are past their "Available Until" date as of
  today, 2026-10-13 (S12). Any Lynomia code or article pinned to v18/v19 is out of support. This is a direct
  input for agent 091.
- `error_subcode` is **not returned in WhatsApp v16.0+ responses** (S1). A Lynomia field that stores
  `error_subcode` from a WhatsApp call will be permanently null; from a Graph/Messenger/Instagram call it will not.
- Marketing Messages codes 134100, 134101, 134102 are **v23.0+** (S1).
- The Graph API changelog says **nothing** about error codes, `error_subcode` deprecation, or error-behaviour
  changes in any product (S12). An agent claiming a changelog entry for an error change must cite the
  product-specific changelog, not S12.
- S9 does not state an API version at all, so its code list carries no version context.

---

## 6. Ambiguities and gaps in Meta's own documentation

1. **131053 has two different official meanings on two official pages.** S1: "Unable to upload the media used in
   the message." S8: "mismatched MIME type (`131053`) is a common error." Meta does not reconcile them. This is
   an ambiguity to record, not resolve.
2. **131060 exists but is not in the error reference.** S1 does not list it; S7 does, with no title. Meta
   publishes no canonical description of it.
3. **2593109 is likewise reference-absent** — S1 lists 2593107 and 2593108 but not 2593109, which only S7 gives.
4. **`title` and `message` are the same value** (S6), and S1 publishes no titles at all. Meta is moving the real
   information into `error_data.details`. A product that stores only `code` + `title` discards the useful field.
5. **One code, many titles.** Flows code 100 carries seven distinct titles and 139002 carries ten (S3);
   WhatsApp 2388103 carries nine distinct messages (S1). A one-code-to-one-meaning data model is wrong.
6. **Meta ships an unassigned code.** S11 prints `TBD` for "Call rate limit exceeded".
7. **Meta ships a typo in an identifier**: `public-key-signiture-verification` (S3). It must be reproduced
   exactly, misspelling included.
8. **No Instagram error-code page exists** (X1, X2 both 404; O2 found none). IG errors live under Messenger.
9. **131026's `details` ends in a colon** — "Unable to deliver message. Reasons can include:" — so the code's
   meaning is an open list, not a fixed cause (S1).

---

## 7. What Lynomia users would ask

"Why does it say failed when the customer is clearly on WhatsApp?" (131026, 131049, 131050) · "I fixed the card,
why is it still failing?" (131042) · "Why did only some of my campaign send?" (131049 per-recipient vs 131048
number-level vs 131064 account-level — three different answers that look identical in the inbox) · "The customer
messaged us but nothing arrived" (131060 coexistence, and `pages_manage_metadata` never subscribing the Page) ·
"Why can't I send after 24 hours?" (131047) · "Why was my template refused?" (132001 vs 132007 vs 132015 vs
132016) · "Instagram says the account owner disabled DM access" (200/2534041) · "The connection wizard says my
number is already registered" (3441049, 3441030, 2655095).

---

## 8. What I attacked

Every "Error codes and failures" table in the eleven reports that existed when I looked: 002, 003, 004, 006, 008,
009, 010, 011, 012, 013, 014. Plus Lynomia's own two code-bearing files,
`custom/app/services/whatsapp/delivery_failure.rb` and
`app/javascript/dashboard/helper/documentationLinks.js:43-52`, and the code-shape claim in
`app/services/whatsapp/provider_error_log.rb:47`.

---

## 9. Codes claimed by other agents that I could NOT verify — BLOCKERS

Each is a blocker in the program's own terms: it must be re-cited with a page URL and a quoted line, or struck.
"Could not verify" here means **not present on any of S1–S12**, which includes every error-code reference Meta
publishes for the four products. It does not mean "invented" — most are plausibly on a Graph API *reference*
edge's own error list, which is not an error-code reference page. But none may be published without that cite.

| Code | Claimed by | The claim | What I found instead | Severity |
|---|---|---|---|---|
| `2061` | 010 | On-Premises API: paused template | Not on S1–S12. The On-Premises API is retired; a retired-product code in a user-facing article is worse than no code | blocker |
| `2062` | 010 | On-Premises API: disabled template | As above | blocker |
| `192` | 009 | "Invalid phone number" | Not on S1–S12. Repo-side, `192` occurs only in CSS and RFC1918 addresses, never as a code | blocker |
| `200002` | 009 | "HSM template creation failed" | Not on S1–S12 | blocker |
| `136024` | 014 | number already verified, HTTP 400 from `request_code` | Not on S1–S12 | blocker |
| `137000` | 014 | identity hash mismatch | Not on S1–S12 | blocker |
| `138024` | 014 | "WhatsApp Business calling cannot use SIP because it is not enabled." | Not on S1–S12. Plausibly a `health_status` value rather than an API error code — the distinction matters | blocker |
| `132021` | 011 | `template_name` in `direct_send_config` conflicts | Not on S1–S12 | blocker |
| `283` | 004 | "That action requires the extended permission pages_read_engagement…" | Not on S9/S10/S11 | blocker |
| `415` | 004 | two-factor authentication required | Not on S9/S10/S11 | blocker |
| `457` | 004 | "The session has an invalid origin" | Not on S9/S10/S11 | blocker |
| `104` | 004 | "Incorrect signature" — 004 itself flags it as absent from S2 | Not on S9/S10/S11 | blocker |
| `370` | 004 | "Invalid call to update this page" | Not on S9/S10/S11 | blocker |
| `240` | 004 | listed with no description | Not on S9/S10/S11; 004 concedes it has no meaning | blocker — nothing to publish |
| `200002`/`80008` title text | 009, 013 | "There have been too many calls to this WhatsApp Business account…" as 80008's title | S10 confirms **80008 exists** as the WhatsApp Business Management BUC code but publishes **no such sentence**. The code survives; the quoted title does not | major |
| `80001` title text | 004 | "There have been too many calls to this Page account." | S10 confirms **80001 exists** as a BUC code; the sentence is not on S10 | major |
| `131060` title | 013 | "Unsupported messages webhook" | **S7 gives 131060 no title.** The phrase is the name of the *webhook*, not the title of the code. The code and its meaning are normative; the title is 013's construction | major |
| 133016 "10 requests / 72-hour moving window" | 013, 014 | exact figures | S1 gives 133016 without numbers; I did not reach the registration reference | minor — attribute to 013/014, do not present as reference-sourced |

**One factual refutation, not a code.** Agent 002 §3 states that "the access-token debugging and error-handling
page 404s at the documented path" and defers the 190 subcode family on that basis. It does not 404:
`https://developers.facebook.com/docs/graph-api/guides/error-handling/` rendered for me today as S9, and agent
004 fetched the same page as its own S2. **002's stated reason for omitting the 190 family is wrong**, and the
family is fully documented (§3.6). Severity: major — it caused a real omission in 002.

---

## 10. Survived — claims I tried to break and could not

- **Agent 006's framing that `title` is being deprecated in favour of `details`.** I expected this to be an
  over-read. It is right, and stronger than 006 put it: S1 publishes *no* title column at all, and S6 states
  `title` and `message` hold the same text. 006's conclusion that a pipeline keeping only `code` + `title`
  discards the one field Meta tells you to read is correct.
- **Agent 011's `details` quotes.** I spot-checked 131047, 131049, 131050, 131063, 131064, 100, 131008, 131009,
  135000, 132018, 131055, 134100, 134101, 134102 against S1. Every one matches Meta's wording. 011 is the most
  accurately transcribed error table in the directory.
- **Agent 012's claim that 131053 is "mismatched MIME type".** I expected this to be a vendor-blog leak. S8
  really does say it. 012 is right and S1 is the page that is incomplete (§6.1).
- **Agent 013's 131060 and 2593109 codes.** Both are on S7 exactly as claimed, including 2593109's full title.
  I had provisionally scored 131060 as unverifiable after O1 returned only vendor pages; S7 rescued it. Only the
  *title* fails (§9).
- **Agent 004's 190 subcode table.** All seven subcodes (458, 459, 460, 463, 464, 467, 492) and their titles
  match S9 verbatim, including 492's Page-role meaning. Its separation of "normative meaning" from "inferred
  event→subcode mapping" is the correct epistemic treatment and should be the house style.
- **Agent 008's position that pricing/categories produce no numeric codes.** I looked for one and found none on
  S1–S12. Its string-valued table (`INCORRECT_CATEGORY`, `UTILITY_TEMPLATE_ABUSE`,
  `RATE_LIMITED_UTILITY_TEMPLATE_MESSAGING`, `RESTRICTED_UTILITY_TEMPLATES`) is the right shape for the area.
- **Agent 003's "missing grant looks like 200–299 / 10"** matches S9's wording exactly.

---

## 11. Codes NO agent found that belong in the register

Measured against the eleven reports that existed. Reports 001, 005, 007, 015–027 did not exist (§15), so some of
this is unwritten rather than missed — but four of these families are missed by an agent whose brief covers them.

1. **The entire Groups API family — 15 titled codes (§3.2).** No brief in 001–027 covers Groups. This is a gap in
   the *program*, not in an agent. Codes 131020, 131041 and 131059 sit inside the `131xxx` range Lynomia already
   parses, so a Groups error would reach `Whatsapp::DeliveryFailure` and be classified `UNCLASSIFIED` today.
2. **The Embedded Signup error page and its ~90 codes (§3.4).** Agent 013's brief *is* Embedded Signup. It cites
   five embedded-signup pages (S1–S5) and the coexistence page, but **not**
   `…/embedded-signup/errors.md`, and reports six codes where Meta publishes about ninety plus ~25 prose-only
   failures. This is the single largest coverage miss in the directory, and it lands squarely on Lynomia's
   connect-a-number wizard — the place where a self-serve user actually gets stuck.
3. **The Flows management family — 139000–139004 with their ~20 distinct titles, the business-endpoint statuses
   421/427/432, and the 11 client-side string codes (§3.3).** Agent 012's brief covers "flows and their
   send-time constraints" and it reports only the two Cloud API codes. Agent 037 (flow builder) is a product
   agent and would not have these.
4. **Authentication-template OTP error signals (§3.5).** Agent 012 reports three `HANDSHAKE_ID_*` identifiers
   from the autofill pages but not S5's seven `com.whatsapp.OTP_ERROR` keys. Low Lynomia impact (they need the
   business's own Android app) but they belong in the register so nobody documents them as send failures.
5. **Graph API codes 341, 506, 1609005, 17, 32, 613/1996 and the ten BUC codes 80000–80014 (§3.6).** Agent 025
   owns these and has not reported.
6. **The whole Messenger/Instagram surface (§3.7)** — 551, 613 and its three subcodes, 2022, 10303, 24001/2/5,
   36103, nine `2534xxx` Instagram subcodes, the `2018xxx` and `2071xxx` series, the eight calling codes, and
   9000001. Agents 021–024 and 026 have not reported. **Instagram's `2534xxx` family is the one a Lynomia
   Instagram inbox will actually hit**, especially 2534022 (outside window), 2534029 (business blocked from IG
   Messaging), 2534041 (owner disabled DM access) and 2534077 (IG/Page/user connection unverifiable).
7. **Cloud API codes no existing report names**: 0, 2, 33, 130403, 130472, 130497, 131005, 131016, 131021,
   131037, 131045, 131048, 131051, 131056, 131063*, 133000, 133004, 133005, 133006, 133008, 133009, 133010,
   133015, 134011, 2388012, 2388039, 2388040, 2388047, 2388072, 2388073, 2388103, 2388293, 2388299, 2494100,
   200005, 200006, 200007, 2593107, 2593108, 1752041. (*131063 is in 011; listed because it is also unowned by
   any setup agent.) Of these, **130403** (business blocked the end user) and **131048/131056** (number-level and
   pair-level throttling) are the ones a Lynomia agent will see and cannot currently be told anything about.

---

## 12. Contradictions between agents, named

| # | Contradiction | Who | Resolution I recommend |
|---|---|---|---|
| 1 | **132001 means two different things.** 010: "the code returned for paused **and** disabled templates **before** v17.0". 011 (quoting S1): "The template does not exist in the specified language or the template has not been approved." | 010 vs 011 | Both can be true because the meaning is version-scoped, but the register must carry **one row with both meanings and the version boundary**. 011's is the current meaning; 010's is pre-v17.0 history. Do not let a reader meet 132001 twice with different answers. Agent 000 arbitrates. |
| 2 | **131053 means two different things, and Meta is the one contradicting itself.** 012: "Mismatched MIME type" (S8). 006 and 011: "Unable to upload the media used in the message" (S1). | 012 vs 006/011 | Not an agent error. Publish both, attributed to both pages, and say Meta does not reconcile them. This is §6.1. |
| 3 | **Is the Graph error-handling page reachable?** 002: it "404s at the documented path", and omits the 190 family because of it. 004: fetches it as S2 and transcribes it fully. I fetched it as S9. | 002 vs 004 | 004 and I are right. 002's omission must be filled from §3.6. |
| 4 | **131060's title.** 013 gives it "Unsupported messages webhook"; S7 gives it none. | 013 vs the source | Strike the title; keep the code and S7's meaning. |
| 5 | **80008's title.** 009 and 013 both attach a sentence to it that S10 does not print. | 009/013 vs S10 | Keep the code, strike the quoted sentence or re-cite it. |
| 6 | **Whether 200 is "Permissions error" with a title.** 002 says "not stated — S3 gives the code without a title". 004 and 013 both give it the title "Permissions error". | 002 vs 004/013 | 002 is the careful one and matches S1, which publishes no titles. "Permissions error" is a convention, not Meta's word. |

---

## 13. Codes Lynomia already classifies

Two files. They disagree with each other, and the comment in one of them asserts something the other does not do.

**`custom/app/services/whatsapp/delivery_failure.rb`** classifies exactly **two** codes:
`CODES = { 131_049 => RECIPIENT_DELIVERY_RESTRICTION/:recipient, 131_042 => BILLING_ELIGIBILITY/:account }`.

**`app/javascript/dashboard/helper/documentationLinks.js:43-52`** registers **five** coded articles
(`whatsappError131049`, `131042`, `131053`, `131060`, `190`), under a comment that reads "The five coded ones are
the codes this installation classifies (`custom/app/services/whatsapp/delivery_failure.rb` and the call sites
that name them)". **Three of the five are not classified there.** The corpus matches the registry: five files
exist under `custom/db/documentation/en/whatsapp-errors/`.

| Lynomia code | Classified in `delivery_failure.rb`? | Article? | Meta's verdict | Where Meta differs from Lynomia |
|---|---|---|---|---|
| 131049 | yes — `:recipient`, `DO_NOT_AUTO_RETRY`, `recipient_scoped? == true` | yes | **Confirmed.** S1: "This message was not delivered to maintain healthy ecosystem engagement." | **Meta documents it differently.** `recipient_scoped?`'s comment says "nothing an operator changes about the message or the installation makes Meta accept it, so re-sending it is refused rather than offered." Meta's remediation (S1, as 011 and 006 both transcribe) is "wait at least 24 hours before resending the template message" — i.e. a later resend is Meta's *recommended* action. Lynomia's permanent refusal is stricter than the documentation. The *code* is right; the *article* must not tell a reader the message can never be sent to that person. |
| 131042 | yes — `:account`, retry stays available | yes | **Confirmed.** S1: "There was an error related to your payment method." | No divergence. Lynomia's "an operator can fix this outside Lynomia, so the same message may later send" matches S1's remediation. |
| 131053 | **no** | yes | **Confirmed, twice, differently.** S1: "Unable to upload the media used in the message." S8: mismatched MIME type is "a common error". | The article exists for a code the classifier ignores, so `whatsappErrorArticle(131053)` resolves while `DeliveryFailure#classification` returns `UNCLASSIFIED`. Not a bug — the two registries serve different purposes — but the JS comment claiming they are the same set is false. |
| 131060 | **no** | yes | **Documented, but only on S7 (coexistence onboarding), with no title, and absent from Meta's error-code reference (S1).** O1 found it only on third-party vendor help pages. | **The weakest-sourced code in the Lynomia corpus.** It is *not* invented — S7 is normative — but it is the one code here that a reader cannot look up on Meta's error reference. The article must cite S7 explicitly, or a future reader will conclude Lynomia made it up. It is also the only one of the five whose meaning is "expected, and not a failure of yours". |
| 190 | **no** | yes | **Confirmed.** S1: "Your access token has expired." S9: "Access token has expired", type `OAuthException`. | **Meta documents more than Lynomia treats.** S9 gives 190 seven subcodes (458, 459, 460, 463, 464, 467, 492) with distinct remedies — 492 in particular means a Page-role loss, not an expiry, and is the Facebook/Instagram-side failure a Lynomia operator is most likely to meet. A single "your token expired" article under-serves the family. |
| 133010 | no | no | Confirmed on S1 (number not registered) | Used in Lynomia only as the spec fixture for an *unclassified* code (`MessageError.spec.js:192`, `documentationLinks.spec.js:50`). Correct choice of example: it is a real Meta code with no Lynomia article. |

**Two code-shape claims in Lynomia that my collection contradicts.**

1. `custom/app/services/whatsapp/delivery_failure.rb` — `CODE_IN_ERROR = /\A(\d{3,6}):/`. Meta's codes run from
   **one digit to seven**: `0`, `1`, `2`, `3`, `4`, `10`, `33` at the low end (S1, S9) and `2388019`, `2655081`,
   `1752041`, `2018300`, `9000001` at the high end (S1, S4, S11). The regex sees neither end. Behaviour does not
   change today — an unmatched code and an unclassified code both yield `UNCLASSIFIED` — so this is not a
   production bug. It becomes one the moment a 7-digit code is classified, and it means the class cannot report
   the code of, say, 2388019 to the dashboard at all.
2. `app/services/whatsapp/provider_error_log.rb:47` — "Meta's error codes are three to six digits (100, 190,
   131030) and its SUBCODES are seven (2655007)". **Both halves are wrong as stated.** Codes reach seven digits
   routinely (`2388019`, `2593109`, `9000001`); subcodes run from two digits (`33`) through `458`, `1996`,
   `2446079` (S9, S10, S11). The *conclusion* — `MIN_CONTACT_DIGITS = 9` — still holds, because no Meta code or
   subcode I found anywhere reaches nine digits, so no code is redacted as a phone number. The reasoning needs
   correcting; the constant does not. Also worth noting for agent 087: the file's choice to drop
   `error_user_msg` / `error_user_title` is well-founded — S9 confirms those are localized, customer-facing
   prose whose language follows the request locale.

---

## 14. Recommended coverage decision

The full register is roughly **380 distinct code/subcode entries** across the four products (≈85 WhatsApp Cloud
+ Management, 15 Groups, ~45 Flows entries, ~90 Embedded Signup coded plus ~25 prose-only, 7 OTP signals, ~35
Graph, ~90 Messenger/Instagram). **One article per code is not a plan, it is a denial-of-service on the corpus.**

### Keep the one-article-per-class rule. Keep it *because* of this scale, not in spite of it.

The rule is already stated twice in this installation — in `documentationLinks.js` for commerce ("thirty codes
have five distinct answers… five articles somebody will read beat thirty nobody will") and implicitly in the
WhatsApp registry. I attacked it and it holds, for three reasons the register itself supplies:

1. **Meta's own codes are not one-to-one with meanings.** Flows code 100 has seven titles; 139002 has ten;
   2388103 has nine; 131026's `details` ends in a colon. A per-code article would have to say "this means one of
   nine things" — which is a class article wearing a code's name.
2. **Many codes have an identical remedy.** 131048, 131056, 131064, 130429, 80007, 4, 80008, 131208 all mean
   "you are being throttled, at some scope, slow down" — the *scope* differs, the *action* does not. One article
   that names the scopes beats eight.
3. **The reader does not arrive with a code.** They arrive with "my campaign half-sent". The code is what the
   article must *contain and be findable by*, not what it must be *titled*.

### But amend the rule in one specific way, or it will fail at this scale.

The current rule couples two things that should be decoupled: **whether a code has an article** and **whether a
code is explained anywhere**. Today, `whatsappErrorArticle(131048)` returns `undefined` and the reader gets the
general troubleshooting article, which does not mention 131048 at all. At five codes that is honest minimalism.
At 380 it is a dead end for 375 of them. Recommendation to agent 000 for decision 4 (the Meta error knowledge
model): **every code in this register gets a row of structured metadata — code, product, Meta's `details`, source
URL, remedy class — and that row resolves to a class article that names the code in its body.** That is an
extension of the existing `Article` + `meta` jsonb model and the existing registry, not a new table and not a new
app, which is what §2 of the charter requires. A code with a row and no article is still answerable; a code with
neither is not.

### The three-way split

**A. Own article — a code whose answer is specific, frequent, and actionable by a Lynomia user (12).**

131049, 131042, 131047, 131050, 131026, 131053, 131060, 190, 130403, 131031, 131064, 132015/132016 *(one article,
they are one story: paused then permanently disabled)*. These are the codes where the remedy is genuinely
unique. Five already have articles; this adds seven and keeps the section under fifteen files. Note that 131060
earns its article not because it is common but because it is the only one that means **"this is expected, do not
try to fix it"** — and S7 is the only page that says so.

**B. Grouped article — a code whose answer is shared with others (≈110).**

| Proposed class article | Codes it must name in its body |
|---|---|
| Your messages are being throttled | 4, 80007, 80008, 130429, 131048, 131056, 131208, 133016, 613, 17, 32, 80000–80014 |
| Your template was refused | 132000, 132001, 132005, 132007, 132012, 132018, 2388040, 2388047, 2388072, 2388073, 2388293, 2388299, 2388039, 2388019 |
| Your account is restricted | 368, 130497, 131031, 131207, 139000, 2655089, 3441040, 2388107, 1357053 |
| Your connection has expired or lost access | 0, 190 (+458/459/460/463/464/467/**492**), 102, 10, 200–299, 131005, 3 |
| We could not add or verify your number | the ~40 S4 phone-setup and verification codes, plus 133005/133006/133008/133009/133010/133015/131045/2388012/2494100 |
| Media did not go through | 131051, 131052, 131053, 2018008, 2018047, 2018074, 2018109, 2018294, 131209, 131210 |
| Instagram will not let us send | 2534013, 2534014, 2534015, 2534022, 2534025, 2534029, 2534037, 2534040, 2534041, 2534077, 36103 |
| Messenger will not let us send | 551, 1545041, 2018065, 2018108, 2018278, 2018300, 2018321, 2018336, 1893063, 2022, 9000001 |
| Your flow did not open | 132068, 132069, 139001–139004, 421/427/432, and the 11 client-side strings |
| Something went wrong on Meta's side | 1, 2, 131000, 131016, 133004, 135000, 3441003, 1675012, 1675030 |

**C. No article at all — a code no Lynomia user can reach (≈255).**

Everything whose precondition Lynomia does not have. Named so the exclusion is a decision and not an oversight:

- **Instant Games and Messenger Extensions SDK**: 2018144, 2018154, 2018163, 2018166, 2071010–2071025, 10303 —
  Lynomia ships no Messenger SDK surface.
- **Messenger calling**: 2018389–2018396 and the `TBD` call rate limit.
- **Payments**: 24001, 24002, 24005, 134011 — no WhatsApp or Messenger payments surface.
- **Handover protocol**: 2018171, 2018234 — only if agent 022 finds Lynomia participates; today, exclude.
- **Groups API**: all 15 — Lynomia has no group messaging. **But §11.1 stands: 131020/131041/131059 would
  reach the classifier.** Exclude from the corpus, include in the metadata rows.
- **Authentication-template OTP signals**: all 7 — they need the business's own Android app.
- **Ads and advertising**: 2655081, 1752004, 1752140, 2455008, 2494149, 2446325, 1784028, 1404163, 1690214,
  80000/80003/80004, 17/2446079 — Lynomia creates no ad accounts. *Caveat for agent 000*: if Marketing Messages
  Lite is ever in scope, 1752041, 134100, 134101, 134102 and 131055 move from C to B.
- **Template insights**: 200005, 200006, 200007. **Synchronization**: 2593107, 2593108. **Phone migration**:
  2388091, 2388093, 2388103 — unless agent 015 shows Lynomia drives migration, in which case 2388103's nine
  causes need their own article in group B.
- **Partner / Solution-Partner sharing**: 2494028, 2494029, 2494091, 2494119, 2494120, 2655049, 2655093 —
  relevant to Lynomia as *operator*, which is the super-admin runbook in agent 048's scope, not a tenant article.
- **Graph content publishing**: 506, 1609005, 341.

**The honest number**: about **12 own + 10 grouped = 22 articles** cover the ~120 codes a Lynomia user can
actually reach, against today's 5. Everything else gets a metadata row and no prose. That is a four-fold increase
in the `whatsapp-errors` section, not a seventy-fold one, and it is defensible line by line against this
register.

---

## 15. Not checkable, and what still needs auditing

**Reports that did not exist when I looked** (checked twice: at the start of my run and after my collection).
The orchestrator must route these for audit once written — I have audited none of them:

`001`, `005`, `007`, `015`, `016`, `017`, `018`, `019`, `020`, `021`, `022`, `023`, `024`, `025`, `026`, `027`.

That is **16 of the 27**, including the four whose scope carries the largest unaudited code families: **005**
(request-time send-failure families), **021/022** (Pages and Messenger — §3.7 is entirely unclaimed), **024**
(Instagram runtime — the `2534xxx` family), and **025** (Graph `OAuthException`, subcodes, rate-limit envelopes —
§3.6). Until 005, 022, 024 and 025 are audited against §3, the program has no verified coverage of three of its
four products.

**What I could not check myself**
- The ~90 S4 Embedded Signup codes are recorded as a family with their page. I read all of them once but did not
  transcribe each `details` string verbatim; a writer using them must re-read S4.
- Whether 2061/2062/192/200002/136024/137000/138024/132021/283/415/457/104/370/240 appear on a *reference edge's*
  own error list (as opposed to an error-code reference page). That needs one fetch per edge, which is outside
  my budget and belongs to the claiming agent.
- The "10 requests / 72 hours" figure for 133016.
- Nothing was fetched outside `developers.facebook.com`. I did not call a Meta API, authenticate, submit a form,
  or use any credential.
