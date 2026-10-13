---
agent: 014
scope: WABA structure, business phone number add/verify/register, two-step PIN, display name review, phone number status fields, quality and alert webhooks
confidence: medium
sources_normative: 15
sources_observational: 3
---

# 014 — WABA structure, phone number registration, display name review, two-step PIN

All pages were read on **2026-10-13**. Every fetch was read-only. No Graph endpoint was called, no credential
used, no form submitted.

A warning that governs this whole report: **Meta has moved this documentation into a new tree**
(`developers.facebook.com/documentation/business-messaging/whatsapp/**`) while the old tree
(`developers.facebook.com/docs/whatsapp/**`) is still live and still serves older copies of the same pages. The
two trees disagree on at least one field's semantics (`phone_number_quality_update`, see §3) and several old
URLs now 404. Anything Lynomia hard-codes as a doc link, or anything a Lynomia article copied from Meta before
2026, should be re-checked against the new tree.

## 1. Source register

| Row | Source URL | Page title | Product | API / version context | Date checked | Normative? |
|---|---|---|---|---|---|---|
| N1 | https://developers.facebook.com/docs/whatsapp/cloud-api/reference/phone-numbers | Business phone numbers | WhatsApp Cloud API | examples in v25.0 and v15.0; list endpoint uses an `<API_VERSION>` placeholder; no required version stated | 2026-10-13 | normative |
| N2 | https://developers.facebook.com/docs/whatsapp/cloud-api/reference/registration | Register a business phone number | WhatsApp Cloud API | examples in v25.0 | 2026-10-13 | normative |
| N3 | https://developers.facebook.com/docs/whatsapp/cloud-api/reference/two-step-verification | Two-Step Verification | WhatsApp Cloud API | example in v25.0 | 2026-10-13 | normative |
| N4 | https://developers.facebook.com/docs/whatsapp/overview/business-accounts | WhatsApp Business Accounts | WhatsApp Business Platform overview | none stated | 2026-10-13 | normative |
| N5 | https://developers.facebook.com/documentation/business-messaging/whatsapp/business-phone-numbers/phone-numbers.md | Business phone numbers | WhatsApp Business Platform (new tree) | examples in v25.0 and v15.0 | 2026-10-13 | normative |
| N6 | https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/phone_number_quality_update.md | phone_number_quality_update webhook reference | WhatsApp webhooks | none stated | 2026-10-13 | normative |
| N7 | https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/account_alerts.md | account_alerts webhook reference | WhatsApp webhooks | none stated | 2026-10-13 | normative |
| N8 | https://developers.facebook.com/documentation/business-messaging/whatsapp/display-names.md | Display names | WhatsApp Business Platform | none stated | 2026-10-13 | normative |
| N9 | https://developers.facebook.com/documentation/business-messaging/whatsapp/throughput.md | Throughput | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| N10 | https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/phone_number_name_update.md | phone_number_name_update webhook reference | WhatsApp webhooks | none stated | 2026-10-13 | normative |
| N11 | https://developers.facebook.com/documentation/business-messaging/whatsapp/messaging-limits.md | Messaging Limits | WhatsApp Business Platform | none stated | 2026-10-13 | normative |
| N12 | https://developers.facebook.com/documentation/business-messaging/whatsapp/support/health-status.md | Messaging and Calling Health Status | WhatsApp Business Platform | none stated | 2026-10-13 | normative |
| N13 | https://developers.facebook.com/documentation/business-messaging/whatsapp/llms.txt | WhatsApp documentation index (machine-readable) | WhatsApp Business Platform | n/a | 2026-10-13 | normative (index only) |
| N14 | https://developers.facebook.com/docs/graph-api/reference/whats-app-business-account/phone_numbers/ | WhatsApp Business Account > Phone Numbers (edge) | Graph API | **v26.0** | 2026-10-13 | normative |
| N15 | https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/components | Webhooks components | WhatsApp Cloud API | none stated | 2026-10-13 | normative (negative result: covers `messages` only) |
| O1 | search-index summary of `developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users/` | Onboard WhatsApp Business app users | WhatsApp Business Platform | none | 2026-10-13 | **observational** — normative page, but read only through a search summary, not fetched directly |
| O2 | search-index summary of `developers.facebook.com/docs/whatsapp/api/rate-limits/` | Capacity, Quality Rating, and Messaging Limits | WhatsApp (old On-Premises tree) | none | 2026-10-13 | **observational** — old tree, read only through a search summary |
| O3 | `developers.facebook.com/docs/whatsapp/overview/business-phone-numbers`, `/docs/graph-api/reference/whats-app-business-phone-number/`, `/docs/graph-api/reference/whatsapp-business-phone-number/`, `/documentation/business-messaging/whatsapp/reference/whatsapp-business-phone-number.md`, `/documentation/business-messaging/whatsapp/message-quality.md` | — | — | — | 2026-10-13 | **observational** — all returned HTTP 404. Recorded because the surviving pages point readers at a phone-number node reference whose URL I could not resolve (see §6) |

## 2. The rules

### 2.1 What a WABA is and what it holds

A WhatsApp Business Account represents a business on the WhatsApp Business Platform, and a business needs one in
order to send or receive messages and to create or manage message templates. After creating the WABA, the
business connects a phone number and sets up a payment method (N4).

A WABA belongs to exactly one business portfolio and **cannot be moved from one business to another** (N4). The
On-Behalf-Of ownership model is deprecated and no longer possible (N4). A WABA can be shared with up to two
partners (N4). Time zone and currency become uneditable once a line of credit is attached (N4).

The counting is worth being precise about, because it is the thing support desks get wrong. N4 states the
registered-business-phone-number cap **per Meta Business Account, not per WABA**: accounts start at 2 registered
business phone numbers, raisable to 20. N5 states the same ceiling differently — new portfolios are initially
capped at 2 registered numbers, and the cap rises to 20 either on verification or on reaching a 2,000 messaging
limit. Neither page states a per-WABA phone number maximum. **Meta does not state how many numbers a single WABA
may hold**; it states how many a portfolio/account may have registered. See §6.

### 2.2 Adding a phone number

Four methods add a number to a WABA (N5): the App Dashboard (WhatsApp > API Setup), Meta Business Suite,
WhatsApp Manager, or Embedded Signup (for Solution Partners). N5 is explicit that these methods **add the number
and verify ownership but do not register it for Cloud API use** — registration is a separate API call. This is
the single most load-bearing sentence in the whole area: a number can be present, owned and verified in WhatsApp
Manager and still be unable to send, because nobody called `register`.

Eligibility (N5): the number must be owned by the business, have a country and area code (short codes are not
supported), be able to receive voice calls or SMS, and have scaled capabilities. 1-800 and toll-free numbers must
additionally be reachable behind any IVR and able to accept international calls.

### 2.3 Phone number verification (SMS / voice code)

Three steps (N5):

1. `POST /PHONE_NUMBER_ID/request_code` with `code_method` (`SMS` or `VOICE`) and `language` (a two-character
   code such as `en`). A system user access token is used; requesting on behalf of another business requires
   Advanced Access to `whatsapp_business_management`.
2. Receive the code by the chosen method.
3. `POST /PHONE_NUMBER_ID/verify_code` with `code`. Success returns `"success": true`.

N5 says that if the number is already verified, `request_code` returns **HTTP 400 with error code 136024**, and
advises checking `code_verification_status` before calling it.

### 2.4 Registration with the Cloud API, and the two-step PIN

`POST PHONE_NUMBER_ID/register` with `messaging_product: "whatsapp"` (required) and `pin` (required, a 6-digit
value). `data_localization_region` is optional and takes a 2-letter ISO 3166 country code such as `IN` (N2).

The PIN semantics are stated plainly (N2) and are the part users misunderstand:

- If the number **already** has two-step verification enabled, `pin` must be that number's existing 6-digit PIN.
- If two-step verification is **not** enabled, the `pin` supplied **becomes** the number's new 6-digit two-step
  verification PIN.

So the same parameter is either an authentication factor or an enrolment, depending on prior state. Meta also
states that account creation uses two-step verification and that **Meta enforces it** (N2), and separately that
**"There is no endpoint to disable two-step verification"** (N3).

Setting or changing the PIN by API is `POST /PHONE_NUMBER_ID` with `{"pin": "6_DIGIT_PIN"}`, returning
`{"success": true}` (N3). The only format rule Meta states is that it is 6 digits; N3 gives no other constraint
(no "no repeated digits", no "not sequential" — if such a rule exists it is not in N3).

**When the PIN is lost or wrong.** Neither N2 nor N3 documents an API-based recovery. N3 gives a non-API reset
path through WhatsApp Manager: Settings > WhatsApp Accounts > the WABA's Settings > WhatsApp Manager > the phone
number's Settings > Two-step verification > Change PIN, then enter and confirm the new PIN. N2 says only that if
you do not remember the PIN you can change it, and links to that reset path. **Neither page states what error a
wrong PIN returns on `register`, nor whether repeated wrong PINs lock the number.** That is a genuine gap (§6)
and it matters, because the registration call is itself rate-limited (§4) — so wrong-PIN retries consume a quota
that locks the number out for 72 hours.

Registration can only be done **through the API — not through WhatsApp Manager and not through the App
Dashboard** (N2).

### 2.5 Deregistering

`POST PHONE_NUMBER_ID/deregister`, success `{"success": true}` (N2). Stated consequences:

- The number becomes unusable with Cloud API and must be re-registered to be used again.
- Local storage, if it was enabled, is disabled.
- Deregistration does **not** delete the number or its message history.
- A number **in use with both Cloud API and the WhatsApp Business app cannot be deregistered**.
- Without `whatsapp_business_management` permission the API returns **error code 200**.

Deregistration is also the documented mechanism for undoing local storage: once enabled, local storage cannot be
disabled or changed directly — you deregister and register again, either without the parameter or with a new
country code (N2).

A separate deletion rule from N5: a number **cannot be deleted if it sent paid messages within the last 30 days**.

### 2.6 Display names

A display name is required when registering a number and appears in the number's WhatsApp profile; once approved
through verification it can also appear at the top of individual chat threads and in the chat list. If a WhatsApp
user has set their own profile name for the business in their client, that name is shown instead (N8).

Review is **not** a prerequisite for getting started. N8 states that verification starts automatically when the
account reaches a higher messaging limit, and checks the name against the display name guidelines. Completion
fires a `phone_number_name_update` webhook and a Meta Business Suite notification (N8). On approval,
`decision: APPROVED` and `name_status: APPROVED`; on rejection, `decision: REJECTED` and `name_status: DECLINED`,
and the business may edit the name or appeal through Developer Support or Enterprise Developer Support (N8).

`verified_name` shows the string **under review**, not whether it was approved — `name_status` is the approval
signal (N8). This is an easy and consequential misreading for any integration that surfaces `verified_name` as
"the approved name".

**Why a name is rejected.** The normative, enumerated list is on the webhook reference (N10), not on the
guidelines page. N8 itself states no naming rules and defers to a Help Center article. The `rejection_reason`
values are in §3.

**Changing a display name on a live number** (N8):

- Limit: **10 changes per 30-day period**.
- Official Business Account numbers must contact direct support to change the name.
- Via WhatsApp Manager: Phone numbers > the number > Profile tab > Display name > Edit.
- Via API: `POST` with `new_display_name`; track with the `new_display_name` and `new_name_status` fields (N8's
  example shows `PENDING_REVIEW`). On approval, `verified_name` and `name_status` update and the webhooks fire.
- **The new name does not take effect until the number is re-registered.** Re-registering *before* approval has
  no effect (stated in both N8 and N2).
- After approval there is a **14-day window to re-register**. If it lapses, the name must be resubmitted for
  review (N8).
- Re-registration is `POST /<PHONE_NUMBER_ID>/register` with `messaging_product: whatsapp` and the PIN; Embedded
  Signup does not need repeating (N8).
- N8 **does not describe any service interruption** during or after a display name change. It says only that
  re-registration applies the new name with WhatsApp servers. Absence of a stated interruption is not a
  guarantee of none — recorded as a gap (§6), not as "no downtime".

### 2.7 The status fields, and what each value means

This is the part of the brief the documentation answers least completely. Below is exactly what the sources
state. **Nothing is filled in from memory.**

**`name_status`** — six values, all defined identically in N1 and N5:

| Value | Meaning as Meta words it |
|---|---|
| `APPROVED` | The name has been approved. |
| `AVAILABLE_WITHOUT_REVIEW` | The display name is ready to use without review. (N5 marks this **beta**.) |
| `DECLINED` | The name has not been approved. |
| `EXPIRED` | The phone number's certificate has expired and cannot be used to register the phone number for API use. |
| `PENDING_REVIEW` | Your name request is under review. |
| `NONE` | The phone number does not have a certificate and cannot be used to register the phone number for API use. |

N1 notes the `name_status` field itself as beta. `EXPIRED` and `NONE` both block registration, which makes them
the two values an operator must treat as hard blockers rather than informational.

**`code_verification_status`** — the only value appearing in N1 or N5 is **`VERIFIED`**. Neither page enumerates
the others or defines any of them. The existence of a non-verified state is implied by N5's instruction to
"check `code_verification_status` before calling" `request_code`, and by error 136024 ("already verified"), but
**no source I read names a second value.** Recorded as a gap — any Lynomia article or code branch that matches on
a specific unverified value is matching on an undocumented string.

**`quality_rating`** — N1 and N5 show `GREEN`, `NA` and `UNKNOWN` in example responses and **define none of
them**; N1 points to a Help Center article. N9 states a `YELLOW` level exists and equates it to "Medium quality
rating" in WhatsApp Manager. So `GREEN`, `YELLOW`, `NA` and `UNKNOWN` are attested; **`RED` is not attested by
any page I fetched** (it appears only in O2, a search summary of the old On-Premises rate-limits page) and is
recorded here as *observational, unconfirmed*. N9 additionally calls the field **`quality_score`**, not
`quality_rating` — an unresolved naming inconsistency between normative pages (§6).

**`platform_type`** — **not mentioned on N1 and not mentioned on N5 or N9.** O1 (observational: a normative page
read only via search summary) reports that `platform_type` is requested alongside `is_on_biz_app` to confirm a
number is set up for both Cloud API and the WhatsApp Business app, and that the value `CLOUD_API` indicates Cloud
API capability. O2 context indicates `ON_PREMISE` is a legacy value: the final supported On-Premises client
version expired on 2025-10-23 and numbers have only been registrable for Cloud API since 2024-07-01. **I did not
confirm the full `platform_type` enum on any page I fetched directly.** Agent 088 or 091 should settle it.

**`throughput`** — retrieved with `GET /<WHATSAPP_BUSINESS_PHONE_NUMBER_ID>?fields=throughput` (N1, N5, N9).
**Neither N1 nor N5 nor N9 states the enum the field returns.** N9 describes the *levels* in messages per second
rather than as field values: 80 mps default for Cloud API; 1,000 mps "higher throughput" for numbers meeting
eligibility, upgraded automatically at no cost; and a fixed 20 mps for numbers used with both the WhatsApp
Business app and Cloud API. So the operator-facing concept is documented but the machine-readable value set is
not. Recorded as a gap.

**`status`** — N1 and N5 show only **`CONNECTED`**, and N5 states a number must have a status of "connected" to
send and receive messages via the API, and that status reflects quality rating and messaging limit. Both pages
defer the full value list to an API reference. **I could not resolve that reference to a working URL** (five
candidate URLs 404'd, O3). **No source I read enumerates the other `status` values.** This is the largest gap in
this scope and it is directly in the critical path of "why can't this number send". Do not let any Lynomia
article assert a `status` value that is not re-confirmed.

**`account_mode`** — N1 states the filterable values **`SANDBOX`** and **`LIVE`**, defines neither, and notes
the filter is in beta and not available to all developers.

**`health_status`** (N12) — not in the brief's field list, but it is the field that actually answers "can this
number send", so it belongs here. `GET /<NODE_ID>?fields=health_status` works on a WABA, a business phone number
or a message template. `can_send_message` takes three values:

| Value | Meaning as Meta words it |
|---|---|
| `AVAILABLE` | "Indicates that the node meets all messaging or calling requirements." |
| `LIMITED` | "Indicates that the node meets messaging or calling requirements, but has some limitations." Includes `additional_info`. |
| `BLOCKED` | "Indicates that the node does not meet one or more messaging or calling requirements." Includes `errors`. |

The response checks several entities — `PHONE_NUMBER` (only when targeting a number), `MESSAGE_TEMPLATE` (only
when targeting a template), and always `WABA`, `BUSINESS` and `APP`. The aggregate is `BLOCKED` if any node is
blocked, else `LIMITED` if any is limited, else `AVAILABLE` (N12).

### 2.8 The two trouble webhooks

Both arrive on the `whatsapp_business_account` object. N15 (the Cloud API "Webhooks components" page) documents
only the `messages` field and does **not** cover these — the per-field references in the new tree do.

**`phone_number_quality_update`** (N6). Its trigger, as the new tree now words it, is: **"A business phone
number's throughput level changes."** Payload `value`: `display_phone_number`, `event`, `old_limit` (included
only for messaging limit changes), `current_limit`, `max_daily_conversations_per_business`.

`event` values, with Meta's definitions:

| Value | Meaning |
|---|---|
| `ONBOARDING` | The business phone number is still being registered. |
| `THROUGHPUT_UPGRADE` | The throughput level has increased to higher throughput. |

`old_limit` and `current_limit` are both marked **deprecated, to be removed in February 2026**, replaced by
`max_daily_conversations_per_business`. The value set for `current_limit` and for
`max_daily_conversations_per_business`: `TIER_50` (limit 50), `TIER_250` (250), `TIER_2K` (2,000), `TIER_10K`
(10,000), `TIER_100K` (100,000), `TIER_NOT_SET` (the number has not been used to send a message yet),
`TIER_UNLIMITED` (higher throughput). N6's table for `old_limit` omits `TIER_UNLIMITED` although its own example
payload uses it — a documentation inconsistency, recorded in §6.

**This is a material change from how this webhook is widely understood.** As N6 now words it,
`phone_number_quality_update` reports throughput and messaging-limit movement. It does **not**, on this page,
carry a quality-rating event or any `FLAGGED` / `UNFLAGGED` event value, and it does not carry
`current_quality_rating`. Any Lynomia code or article that parses this webhook for a quality-rating drop should
be checked against N6 directly. I am flagging this rather than resolving it: the older tree may still describe
the quality-rating form of this webhook, and I did not fetch an old-tree copy to compare. **Agent 091 (stale API
guidance) should arbitrate.**

**`account_alerts`** (N7). Purpose: changes to a business phone number's messaging limit, business profile, and
Official Business Account (OBA) status. Triggers: a messaging-limit increase for all of a portfolio's numbers is
denied, deferred or needs more information; a number's OBA status is approved or denied; a number's business
profile photo is deleted.

Payload `value`: `entity_type`, `entity_id`, and an `alert_info` object holding `alert_severity`,
`alert_status`, `alert_type`, `alert_description`.

| Field | Values |
|---|---|
| `entity_type` | `BUSINESS` (a business portfolio), `PHONE_NUMBER` (a business phone number), `CURRENT_STATUS_ID` (a phone number's business profile) |
| `entity_id` | a business portfolio ID or business phone number ID |
| `alert_severity` | `CRITICAL` (a rejection or denial; the description may cover resolution actions), `INFORMATIONAL` (no action needed), `WARNING` (action may be needed; the description lists possible actions) |
| `alert_status` | `ACTIVE`, `NONE` |
| `alert_type` | `INCREASED_CAPABILITIES_ELIGIBILITY_DEFERRED`, `INCREASED_CAPABILITIES_ELIGIBILITY_FAILED`, `INCREASED_CAPABILITIES_ELIGIBILITY_NEED_MORE_INFO`, `OBA_APPROVED`, `OBA_REJECTED`, `PROFILE_PICTURE_LOST` |

`alert_type` meanings (N7): `INCREASED_CAPABILITIES_ELIGIBILITY_DEFERRED` — Meta lacks enough message signal to
decide, identity verification was rejected, or message quality is too low. `..._FAILED` — the limit cannot be
increased because of past messaging activity. `..._NEED_MORE_INFO` — same, and more information is needed.
`OBA_APPROVED` / `OBA_REJECTED` — OBA status approved or denied. `PROFILE_PICTURE_LOST` — the business profile
photo was deleted.

N11 adds the remediation Meta attaches to each denial: for `DEFERRED` and `FAILED`, deliver 2,000 messages
outside customer service windows to unique numbers within 30 days using high-quality templates; for
`NEED_MORE_INFO`, verify your identity **or** deliver those 2,000 messages.

Note what `account_alerts` is **not**: nothing in N7 reports a number being blocked, disconnected or banned. The
`alert_type` set is limited to capability-scaling outcomes, OBA decisions and a lost profile photo. An operator
waiting for a webhook to tell them a number stopped working will not get one from this field.

`phone_number_name_update` (N10) is the third webhook in this area and is covered in §3.

## 3. Error codes and failures

Only codes a source states. Cells left `not stated` rather than guessed.

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Source row |
|---|---|---|---|---|---|---|
| `136024` | not stated | not stated (N5 gives the code only) | The number is already verified; returned from `request_code` with HTTP 400 | Check `code_verification_status` before requesting a code; proceed to `register` | nothing — pre-launch | N5 |
| `137000` | not stated | not stated (N5 gives the code only) | Identity hash mismatch | not stated | nothing — pre-launch | N5 |
| `133016` | not stated | not stated (N2 gives the code only) | More than 10 register **or** deregister requests for one business number in a 72-hour moving window | Stop retrying; the number is blocked from registration for the next 72 hours | number stays unregistered, so messages cannot be sent | N2 |
| `200` | not stated | not stated | Missing `whatsapp_business_management` permission (N2, on deregister). N4 reports the same code for partner API calls lacking Advanced access to `whatsapp_business_management` | Fix the token's permissions / request Advanced Access | nothing — management-plane failure | N2, N4 |
| `131057` | not stated | not stated | Returned while a number is being upgraded to higher throughput; the upgrade takes up to 1 minute and the number is unusable during it | Wait and retry; later increases happen with no downtime | sends fail for up to a minute | N9 |
| `130429` | not stated | not stated | The number exceeded its throughput level | Throttle to within the level; sends succeed again once back inside it | delayed or failed messages | N9 |
| `138024` | not stated | "WhatsApp Business calling cannot use SIP because it is not enabled." | Phone-number-level `health_status` error | "Configure SIP using {PHONE_NUMBER_ID}/settings API." | calling only, not messaging | N12 |

**Display name rejection reasons** — `rejection_reason` on `phone_number_name_update` (N10):

| Value | What it means |
|---|---|
| `NAME_EMPLOYEE_ISSUE` | The name included a person's name or employee identifier. |
| `NAME_INDIVIDUAL_ISSUE` | The name included a person's name or employee identifier. (N10 gives this the same description as `NAME_EMPLOYEE_ISSUE` — the two are not distinguished.) |
| `NAME_ENDCLIENT_NOTRELATED` | The name included an unrelated business's name. |
| `NAME_FORMAT_UNACCEPTABLE` | The name used an unacceptable format. |
| `NAME_NOT_CONSISTENT` | The name did not match the business's branding. |
| `UNKNOWN` | Rejected for an unknown reason; contact support. |
| `null` | The name was accepted. |

`decision` values on the same webhook (N10): `APPROVED` (the name is approved and appears at the top of the
number's profile in the WhatsApp client), `DEFERRED` (a decision has been deferred), `PENDING` (a decision is
still awaiting further review), `REJECTED` (the name is rejected; edit it in WhatsApp Manager after reviewing
the guidelines). Note that `decision` has four values while `name_status` has six, and the two sets do not map
one-to-one — there is no `name_status` counterpart to `DEFERRED` or `PENDING` stated anywhere I read, and `PENDING`
vs `PENDING_REVIEW` are different strings on different fields.

N10 also contains a self-contradiction worth recording: its parameter table lists `APPROVED` as an example value
for `rejection_reason`, while the example payload shows `null`. Treat `null` as correct for an accepted name.

## 4. Limits and numbers

Every number below is stated by the cited row. No number here is inferred.

| Limit | Value | Source row |
|---|---|---|
| Registered business phone numbers per Meta Business Account | starts at 2, can be raised to 20 | N4 |
| Registered numbers per new portfolio | initially capped at 2; rises to 20 on verification or on reaching a 2,000 messaging limit | N5 |
| WABAs per Meta Business Account | starts at 20 | N4 |
| Message templates per WABA | up to 250 | N4 |
| Partners a WABA can be shared with | up to 2 | N4 |
| Register requests per business number | 10 per 72-hour moving window; exceeding returns `133016` and blocks registration for 72 hours | N2 |
| Deregister requests per business number | 10 per 72-hour moving window, same `133016` and same 72-hour block | N2 |
| PIN length | 6 digits | N2, N3 |
| `data_localization_region` | 2-letter ISO 3166 country code | N2 |
| Display name changes | 10 per 30-day period | N8 |
| Re-registration window after display name approval | 14 days | N8 |
| Deletion hold after paid messages | a number cannot be deleted if it sent paid messages within the last 30 days | N5 |
| Default Cloud API throughput | 80 messages per second per business phone number | N9 |
| Higher throughput | 1,000 mps; automatic and free for eligible numbers; upgrade takes up to 1 minute, number unusable during it (`131057`) | N9 |
| WhatsApp Business app + Cloud API numbers | fixed 20 mps | N9 |
| Higher-throughput eligibility (all three required) | portfolio has an unlimited messaging limit; the number messages at least 100K unique WhatsApp user numbers outside a customer service window in a moving 24-hour period; the number has a `quality_score` of `YELLOW` (Medium) or higher | N9 |
| Messaging limit tiers | 250 (starting limit for new portfolios), 2,000, 10,000, 100,000, Unlimited | N11 |
| Scaling path to 2,000 | any one of: verify your business; have your partner verify it if a partner onboarded you; deliver 2,000 messages outside customer service windows to unique numbers within 30 days using high-quality templates | N11 |
| Automatic scaling above 2,000 | one level within 6 hours when both hold: high-quality messages across all numbers and templates, **and** at least half the current limit used in the last 7 days | N11 |
| Webhook delivery capacity to plan for | 3x outgoing message traffic and 1x expected incoming | N9 |
| Webhook latency standards | median no higher than 250 ms; fewer than 1% of requests over 1 s | N9 |
| Webhook retry window | failed webhooks retried for up to 7 days with exponential backoff | N9 |

Messaging limits are **per business portfolio and shared by every business phone number in it** (N11) — a
distinction that matters when one number's behaviour throttles another's.

## 5. Version and deprecation notes

- `old_limit` and `current_limit` on `phone_number_quality_update` are **deprecated and slated for removal in
  February 2026**; `max_daily_conversations_per_business` replaces both (N6). Today is 2026-10-13, so **that
  removal date has passed.** N6 still carries the deprecation notice rather than the removal, so either the
  removal slipped or the page is stale. Either way, no Lynomia code should depend on `old_limit`/`current_limit`.
- `messaging_limit_tier` is deprecated; request `whatsapp_business_manager_messaging_limit` instead (N11).
- `name_status` is marked beta (N1); `AVAILABLE_WITHOUT_REVIEW` is marked beta (N5); the `account_mode` filter is
  in beta and not available to all developers (N1).
- The On-Behalf-Of WABA ownership model is deprecated and no longer possible (N4).
- Per O2 (observational): the final supported On-Premises API client version expired 2025-10-23, and numbers have
  only been registrable for Cloud API since 2024-07-01. This bears on `platform_type` and on agent 015's scope.
- Version context is inconsistent across the surviving pages: N1 and N5 mix v25.0 and v15.0 examples in the same
  page, N14 is v26.0, and the list endpoint uses an `<API_VERSION>` placeholder. **No page states a minimum or
  recommended version for this surface.**
- Meta Business Suite WABA creation is unavailable for portfolios with a Brazil or India address (N4).

## 6. Ambiguities and gaps

Stated plainly, because several of these sit directly in the support path.

1. **The full `status` enum is not stated on any page I could reach.** N1 and N5 show only `CONNECTED` and defer
   to a phone-number node reference; five candidate URLs for that reference returned 404 (O3). This is the
   field an operator most needs enumerated.
2. **The full `code_verification_status` enum is not stated.** Only `VERIFIED` appears. N5 tells you to check the
   field before requesting a code but never names the value you would be checking for.
3. **`platform_type` is absent from the phone-number reference pages entirely.** `CLOUD_API` is attested only
   through O1, a search summary of a normative page I did not fetch directly. The complete enum is unconfirmed.
4. **The `throughput` field's returned value shape is not stated.** N9 describes levels in mps; no page states
   whether the field returns a level name, an object, or a number.
5. **`quality_rating` values are shown but never defined.** `GREEN`, `NA`, `UNKNOWN` appear in examples (N1, N5);
   `YELLOW` is attested by N9. **`RED` is unconfirmed by any page I fetched** (observational only, O2). And N9
   calls the field `quality_score` while N1/N5 call it `quality_rating` — unresolved.
6. **What happens on a wrong PIN at `register` is not documented.** No error code, no lockout behaviour, no
   attempt limit. Combined with the 10-request / 72-hour cap and `133016`, a business guessing its PIN can lock
   its own number out of registration for three days. Meta documents neither the hazard nor the error.
7. **No per-WABA phone number limit is stated.** N4 and N5 both state the cap at account/portfolio level. Whether
   one WABA can hold all 20 numbers is not answered.
8. **Whether a display name change interrupts service is not stated.** N8 describes re-registration applying the
   new name and says nothing about downtime. Do not document "no downtime" on this basis.
9. **`NAME_EMPLOYEE_ISSUE` and `NAME_INDIVIDUAL_ISSUE` carry identical descriptions** (N10), so an integration
   cannot tell the operator anything different for the two.
10. **`phone_number_quality_update` as documented in the new tree reports throughput and messaging limits, not
    quality rating** (N6) — no `FLAGGED`/`UNFLAGGED` event, no quality-rating field. This contradicts the common
    understanding of this webhook. **Needs arbitration (agent 091, with 088).** I did not fetch an old-tree copy
    to compare, so I am recording the contradiction rather than declaring the old behaviour gone.
11. **N6's `old_limit` table omits `TIER_UNLIMITED` while N6's own example payload uses it.** Meta's page is
    internally inconsistent.
12. **Display name *rules* live only in a Help Center article**, not in the developer docs (N8 defers to it). The
    enumerated rejection reasons (N10) are the closest normative substitute and are coarse: five named reasons
    plus `UNKNOWN`. I did not fetch the Help Center guidelines article, so the formatting rules themselves
    (capitalisation, URLs, punctuation, generic terms) are **not checked** in this report.
13. **Documentation tree split.** The old `/docs/whatsapp/**` tree and the new
    `/documentation/business-messaging/whatsapp/**` tree both serve this material. `llms.txt` (N13) is the
    reliable index into the new tree and should be the starting point for any later agent.
14. **`account_alerts` reports no outage condition.** Nothing in its `alert_type` set covers a number being
    blocked, disconnected or banned. If Lynomia needs to learn that a number stopped working, no webhook in this
    scope delivers it; `health_status` must be polled.

## 7. What Lynomia users would ask

- "I added my number in WhatsApp Manager and it shows as verified — why can't I send?" (The answer is §2.2:
  adding and verifying is not registering.)
- "What is this 6-digit PIN, and what happens if I set it to something and forget it?"
- "I don't know my two-step PIN and registration keeps failing. Can I just keep trying?" (No — `133016`.)
- "Why was my business name rejected? It is our actual trading name." (Likely `NAME_NOT_CONSISTENT` or
  `NAME_INDIVIDUAL_ISSUE`.)
- "I changed my display name two days ago and customers still see the old one." (Approval does not apply the
  name; re-registration does, within 14 days.)
- "My quality rating went yellow. What happens next, and does it stop my campaigns?"
- "What is `TIER_NOT_SET` and why does my limit say that?"
- "I got an `account_alerts` webhook saying limits cannot be increased. What do I actually do?"
- "Can I move this WABA to our other business?" (No — N4.)
- "How many numbers can I put on one account?" (2, raisable to 20 — per account, not per WABA.)
- "We deregistered to move a number and now nothing works." (Re-register; history is not lost.)
- "Sends started failing for about a minute with 131057." (Throughput upgrade in progress.)

## 8. Operator triage order: a number cannot send

Ordered so that each step is cheaper than the next and rules out a whole class of cause. Every step cites the row
it rests on. Where a value set is undocumented, that is said rather than papered over.

**Step 0 — Ask the aggregate question first.** `GET /<PHONE_NUMBER_ID>?fields=health_status` (N12). This is the
one call that evaluates the number *and* the WABA, business and app together, and it returns `errors` on
`BLOCKED` and `additional_info` on `LIMITED`. `AVAILABLE` means the messaging requirements are met and the cause
is elsewhere (template, recipient, window, token — agents 005, 011, 016). `BLOCKED` names the failing entity, so
it tells you immediately whether this is a phone-number problem at all or a WABA/business/app problem.

**Step 1 — Is the number registered with the Cloud API?** The commonest cause of "it was set up but never
worked". Adding a number through the App Dashboard, Business Suite, WhatsApp Manager or Embedded Signup verifies
ownership but does **not** register it (N5). Fix: `POST /PHONE_NUMBER_ID/register` with `messaging_product` and
the 6-digit `pin` (N2). Registration is API-only — it cannot be done in WhatsApp Manager or the App Dashboard
(N2).

**Step 2 — Check `status`.** A number must be `CONNECTED` to send and receive via the API (N5). Anything else is
the cause. **Caveat that must be carried into any Lynomia article: Meta does not publish the full `status` enum
on any page reachable today (§6.1), so an operator seeing a value other than `CONNECTED` cannot look its meaning
up.** Record the literal value and escalate; do not guess what it means.

**Step 3 — Check `code_verification_status`.** If it is not `VERIFIED`, run the two-step verification flow:
`request_code` with `SMS` or `VOICE`, then `verify_code` (N5). If `request_code` returns HTTP 400 with `136024`,
the number was already verified and the problem is elsewhere — go back to step 1.

**Step 4 — Check `name_status`.** `EXPIRED` and `NONE` are hard blockers: both state that the number "cannot be
used to register the phone number for API use" (N1, N5). `PENDING_REVIEW` means a name is in review — if a name
change is in flight, the number keeps serving the old name until re-registration, so pending review is not
itself a send blocker. `DECLINED` means the submitted name was rejected: read `rejection_reason` from the
`phone_number_name_update` webhook (N10) and either edit the name or appeal (N8). If a name was recently
approved, confirm the number was **re-registered within 14 days** (N8) — a lapsed window sends the name back to
review.

**Step 5 — Check `quality_rating` and the portfolio messaging limit.** Status reflects quality rating and
messaging limit (N5). `NA` or `UNKNOWN` generally means too little signal rather than a problem. `YELLOW`
("Medium", N9) is a warning: it is still above the floor for higher-throughput eligibility, but automatic limit
increases depend on high-quality messaging (N11). Separately check the limit itself — `TIER_NOT_SET` means the
number has not yet been used to send (N6), and the limit is **portfolio-wide**, so another number's volume can
be the reason this one is capped (N11). Limits are read in WhatsApp Manager under Account tools > Messaging
limits, or via the `whatsapp_business_manager_messaging_limit` field (`messaging_limit_tier` is deprecated, N11).

**Step 6 — Look for throughput causes if failures are intermittent rather than total.** `131057` means a
higher-throughput upgrade is in progress and the number is unusable for up to a minute (N9) — wait, do not
re-register. `130429` means the number exceeded its throughput level (N9) — throttle. Remember the ceilings: 80
mps default, 1,000 mps on higher throughput, and a fixed **20 mps** for numbers shared with the WhatsApp Business
app (N9), which is the trap for coexistence setups.

**Step 7 — Read the alerts that were already delivered.** `account_alerts` (N7) will already have reported a
denied, deferred or more-info-needed limit increase, an OBA decision, or a lost profile photo. Map
`alert_type` to the action N11 states: `DEFERRED` and `FAILED` → deliver 2,000 messages outside customer service
windows to unique numbers within 30 days using high-quality templates; `NEED_MORE_INFO` → verify identity, or
deliver those 2,000 messages. `alert_severity` tells the operator how to treat it: `CRITICAL` is a rejection or
denial, `WARNING` means action may be needed, `INFORMATIONAL` needs none. **But note (§6.14): no `alert_type`
reports a number being blocked or disconnected**, so a quiet `account_alerts` feed is not evidence of health.

**Step 8 — Check the management plane.** Error `200` on a management call means the token lacks
`whatsapp_business_management`, or a partner call lacks Advanced Access to it (N2, N4). This presents as "the
dashboard cannot read or change the number" rather than as a send failure, and it will also block the fix for
every step above. Hand off to agents 003 and 004.

**What not to do, in order.** Do not retry `register` to "see if it works" — 10 attempts per 72 hours, then
`133016` locks registration for 72 hours (N2). Do not deregister to reset a problem: it makes the number
unusable until re-registered, disables local storage, and cannot be done at all for a number shared with the
WhatsApp Business app (N2). Do not re-register before a display name is approved — it has no effect (N2, N8).
Do not change the display name to clear a block: 10 changes per 30 days (N8), and an Official Business Account
needs direct support to change it at all (N8).
