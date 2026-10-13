---
agent: 006
scope: WhatsApp Cloud API message status lifecycle (sent, delivered, read, failed, played) and the limits of what each status proves
confidence: high
sources_normative: 12
sources_observational: 2
---

## 1. Source register

Every claim below references a row ID. Where the rendered page title was not captured (Meta's new docs shell is
client-rendered and the title element is not always returned), the title column gives the page's own heading or
its documentation path, and the cell is marked `(path)`.

| Row | Source URL | Page title | Product | API/version context | Date checked | Status |
|---|---|---|---|---|---|---|
| R1 | https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/status | Message status webhook reference `(path)` | WhatsApp Cloud API | states v24.0+ behaviour for `conversation`; `pricing_model` split at 2025-07-01 | 2026-10-13 | normative |
| R2 | https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/components | Webhook components `(path)` | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| R3 | https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/payload-examples | Webhook payload examples `(path)` | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| R4 | https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/overview/ | WhatsApp webhooks | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| R5 | https://developers.facebook.com/docs/graph-api/webhooks/getting-started | Webhooks, Getting Started | Graph API | version-independent | 2026-10-13 | normative |
| R6 | https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/send-messages | Send messages / Service messages `(path)` | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| R7 | https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes | WhatsApp error codes | WhatsApp Cloud API | states error `title` will be deprecated | 2026-10-13 | normative |
| R8 | https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/mark-message-as-read | Mark messages as read | WhatsApp Cloud API | example uses v25.0 | 2026-10-13 | normative |
| R9 | https://developers.facebook.com/docs/whatsapp/cloud-api/reference/messages | Messages (API reference) | WhatsApp Cloud API | `MessageResponsePayload` schema | 2026-10-13 | normative |
| R10 | https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/marketing-templates/per-user-limits/ | Per-user marketing template message limits | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| R11 | https://faq.whatsapp.com/665923838265756 | How to check read receipts | WhatsApp Help Center (consumer app) | n/a | 2026-10-13 | normative for the consumer app, **not** a Cloud API source — see note |
| R12 | https://faq.whatsapp.com/3307102709559968 | How to change your privacy settings | WhatsApp Help Center (consumer app) | n/a | 2026-10-13 | normative for the consumer app, **not** a Cloud API source — see note |
| O1 | — (search-engine summaries of Meta pages, body not read) | claim: a single message can receive **both** `delivered` and `failed` when the user is logged in on several devices | WhatsApp Cloud API | — | 2026-10-13 | **observational, unconfirmed** |
| O2 | — (search-engine summary citing the WhatsApp changelog) | claim: custom TTL ranges (e.g. authentication 30 s – 15 min) and "retry TTL changed from 24 hours to 30 days" | WhatsApp Cloud API | — | 2026-10-13 | **observational, unconfirmed** |

Notes on the register:

- **R11/R12 classification.** §6.2 of the charter lists `developers.facebook.com`, the Graph API changelog,
  `business.facebook.com` help and `www.facebook.com/business/help` as normative. `faq.whatsapp.com` is Meta-owned
  help for the **consumer** WhatsApp app. It is the only Meta source that states what the read-receipts privacy
  setting does, so it is used here, labelled, and never extended to the Cloud API's webhook behaviour. Its body is
  client-rendered; the quotes below were read out of the page's own embedded content payload, not from a summary.
- **A dead URL.** `https://developers.facebook.com/docs/whatsapp/cloud-api/guides/mark-messages-as-read` returns
  **HTTP 404**. The live page is R8, under `/documentation/business-messaging/`. Any Lynomia article or code
  comment pointing at the old `/docs/whatsapp/cloud-api/guides/...` path for this topic is already broken.
- **O1/O2 are not usable.** They are recorded so that no later agent re-derives them and treats them as fact. Two
  pages that would settle them (`/whatsapp/messages/time-to-live`, and whatever page carries the multi-device
  wording) returned navigation chrome only; their bodies could not be read. See §6.

## 2. The rules

### 2.1 The send response is not a status

The Messages API's 200 response carries `messages[].message_status`, whose documented values are `accepted`
("The message has been accepted by WhatsApp and is being processed"), `held_for_quality_assessment` ("The message
is being held for quality assessment before delivery") and `paused` ("The message delivery has been paused") (R9).
R6 states the send response "does not indicate successful delivery of your message," and that delivery status
arrives through messages webhooks instead.

**`accepted` is therefore not a webhook status value.** It is the acknowledgement that Meta took the request. The
brief asked whether `accepted` is one of the statuses Meta sends: it is not — it is one of three *response*
values, and two of the three (`held_for_quality_assessment`, `paused`) mean the message is deliberately **not**
being delivered yet. Meta does not state anywhere I read whether a message in those two response states later
produces any webhook at all (§6).

### 2.2 The status values Meta sends

R1 is the authoritative enumeration. It defines **five** values:

| Status | What Meta says it means | Consumer-app equivalent (R1) |
|---|---|---|
| `sent` | Meta's servers successfully sent the message | one check mark |
| `delivered` | the message reached the user's device | two check marks |
| `read` | the message was displayed in an open chat on the user's device | two blue check marks |
| `failed` | the message could not be sent or delivered | red error triangle |
| `played` | a voice message was played for the first time | blue microphone |

`accepted`, `deleted` and `warning` are **not** in R1. No normative page I read lists `deleted` or `warning` as a
message status; `accepted` is the send-response value in §2.1. Lynomia must not persist, display or document a
provider status by those names as if Meta had sent it.

### 2.3 The fields a status carries

From R1 (confirmed in part by R2/R3): `id` (the `wamid`), `status`, `timestamp` (Unix, when the webhook was
triggered — not necessarily when the state changed), `recipient_id`, `recipient_type` (`"group"`, group messages
only), `recipient_participant_id` (group messages only), `recipient_identity_key_hash` (only when the identity
change check is enabled), `biz_opaque_callback_data` (only if the business set it on send), `conversation`
(`id`, `origin.type`, `expiration_timestamp`), `pricing` (`billable` — deprecated, `pricing_model`, `type`,
`category`) and `errors[]` (only when sending or delivery fails).

`conversation` and `pricing` are **conditional**: R1 states each appears with `sent`, and with `delivered` or
`read`, and that a `pricing` object appears in only one of those webhooks — its own `read` example omits pricing.
`conversation.origin.type` is the conversation category: `authentication`, `marketing`, `service`, `utility`,
`referral_conversion` (R1).

### 2.4 How many webhooks, and in what order

- R2: "each outgoing message can have up to three separate webhooks" — one each for `sent`, `delivered` and `read`.
  **"Up to"** is the operative phrase.
- **`read` implies `delivered`, and can suppress it.** R1: "A status is considered read only if it has been
  delivered," and if the user reads a message as soon as it arrives, **no `delivered` webhook is sent**, because
  delivery is implied. A message can therefore go `sent` → `read` with no `delivered` event, legitimately.
- **Meta states no ordering guarantee for the status events of one message.** R1, R4 and R5 are silent on it. The
  nearest normative statements are about something else: R6 says "the order in which messages are delivered is not
  guaranteed to match the order of your API requests," and advises confirming a `delivered` status before sending
  the next message when sequence matters. So: order across messages is explicitly **not** guaranteed; order within
  one message's status events is **not stated** (§6).
- **Duplicates are expected.** R4: a non-200 response triggers retries "with decreasing frequency until the request
  succeeds, for up to 7 days," and "These retries can result in duplicate webhook notifications." Retries go to
  every app subscribed to that WABA. R5 adds that notifications are batched "with a maximum of 1000 updates," that
  "batching cannot be guaranteed," and that "Your server should handle deduplication in these cases."
- **R4 and R5 disagree on the retry window** (7 days vs. "decreasing frequency over the next 36 hours", with
  unacknowledged responses "dropped after 36 hours"). Recorded as an ambiguity, not resolved (§6).
- R4: payloads can be up to 3 MB, and "some webhooks will not be sent if your app is in **Dev** mode."
- R5: historical notifications cannot be queried — whatever is not stored when it arrives is gone.

### 2.5 How long Meta tries before failing

This is the message **TTL**, and it is a different mechanism from webhook retries.

R6: if the Cloud API cannot deliver a message it "retries delivery for a period of time known as a time-to-live,
TTL, or the message validity period." Defaults: **"All messages except authentication templates: 30 days"** and
**"Authentication templates: 10 minutes"**. "The platform drops messages that cannot be delivered within the
default or customized TTL." Custom TTLs exist for authentication, utility and marketing (MM Lite) templates; R6
defers the ranges to a separate Time-to-live page whose body could not be read, so **no custom range is quoted
here** (§6, O2).

R6's operational guidance is the important part for a support desk: "If you do not receive a status messages
webhook with `status` set to `delivered` before the TTL is exceeded" — assume the message was dropped. And:
"If you send a message that fails (`status` set to `failed`), there could be a minor delay before you receive the
webhook," so build in a small buffer. Meta tells integrators to **infer** the drop from silence. It does not state
that a `failed` webhook is always emitted when the TTL expires.

### 2.6 Read receipts: what Meta actually says about disabling them

The developer documentation says **nothing** about the recipient's read-receipts privacy setting. R1, R2, R3, R4,
R6 and R8 do not mention it; a domain-restricted search of `developers.facebook.com` surfaced no page that states
whether the `read` status webhook is withheld when a user has read receipts off. That silence is the finding.

What Meta does state, in the consumer Help Center (R11, R12):

- R12: "If you turn off read receipts, you can't see read receipts from other users. **Read receipts are always
  sent for group chats.**"
- R11, under *Turn off read receipts*: "If you turn off read receipts, you won't be able to see read receipts from
  others," and "This won't disable the read receipts for group chats or play receipts for voice messages. There's
  no way to turn those settings off."
- R11, under *Missing read receipts* — the full list of reasons two blue check marks may never appear: "You or your
  recipient might have disabled read receipts in the privacy settings"; "The recipient might have blocked you";
  "The recipient might not have opened your conversation"; "You or the recipient might be experiencing connection
  issues"; "When a person gets your message for the first time, a read receipt might not be sent to you"; "The date
  and time settings are incorrect on your phone or the recipient's phone."
- R11 also pins the three check-mark meanings: single = "The message was successfully sent"; double gray = "The
  message was successfully delivered to the recipient's phone **or any of their linked devices**"; double blue =
  "The recipient has read your message." Its *Message info* screen defines **Delivered** as "Your message was
  delivered to your recipient's phone or linked devices, **but the recipient hasn't seen it**", **Read or Seen** as
  the recipient having read the message — and notes a recipient can have "seen your voice message, but hasn't
  played it", with **Played** reserved for actual playback.

So: the read receipt is a user-controlled, suppressible signal in the consumer app, with at least six documented
reasons for absence, only one of which is "unread". Whether the Cloud API's `read` webhook follows the consumer
setting is **not stated by Meta** and must not be asserted by Lynomia.

### 2.7 The business's own mark-as-read call is a different direction

R8: a business marks an **inbound** message read by POSTing `messaging_product: whatsapp`, `status: read` and
`message_id` (a `wamid` from a received message) to the phone number's `/messages` endpoint; the response is
`{"success": true}`. Incoming messages should be marked "within 30 days of receipt"; marking one message "also
marks earlier messages in the conversation as read"; an invalid ID returns **131009**. R8 says nothing about what
the user sees, and nothing about any webhook resulting from this call. The `read` status in §2.2 is the *user*
reading the *business's* outbound message — the two must never be conflated in a Lynomia article or in data.

### 2.8 Template versus free-form: what actually differs

Meta documents **one** status machine, not two. R1 enumerates five statuses without distinguishing template from
free-form, and defines no template-only status. The documented differences are these:

| Dimension | Free-form (service) message | Template message | Source |
|---|---|---|---|
| Status values | `sent`, `delivered`, `read`, `failed`, `played` | identical | R1 |
| Default TTL | 30 days | 30 days, **except authentication templates: 10 minutes** | R6 |
| `conversation.origin.type` | typically `service` | `authentication` / `marketing` / `utility` (also `referral_conversion`) | R1, R3 |
| `pricing.category` | `service` | the applied rate, e.g. `marketing`, `utility` | R1, R3 |
| Characteristic async failures | **131047** — more than 24 h since the recipient last replied | **131049** per-user marketing limit, **131050** marketing opt-out, **130472** experiment exclusion | R7, R10 |
| Pre-delivery hold | not stated | send response may be `held_for_quality_assessment` or `paused` | R9 |

The template path has one explicitly **asynchronous** failure that is worth calling out, because it is the shape
that confuses every support desk: R10 states that when the per-user marketing limit blocks a message, "the messages
webhook is triggered with status set to failed and error code set to 131049." The send succeeded as a request; the
message was never delivered. R7 generalises this: Cloud API errors can arrive synchronously in the Graph API
response, asynchronously via the `messages` webhook, **or both**, and Meta recommends monitoring both channels.

## 3. Error codes and failures

All rows from R7 unless stated. R7 warns that error `title`s will be deprecated and surfaces `details` instead, so
the "title as Meta words it" column quotes `details`. "What the end user sees" is `not stated` unless Meta says the
message was not delivered.

| Code | Subcode | Title as Meta words it (`details`) | What it means | What the business can do | What the end user sees | Row |
|---|---|---|---|---|---|---|
| 131026 | not stated | "Unable to deliver message." | recipient is not a WhatsApp number, has not accepted the latest Terms/Privacy Policy, or runs an outdated WhatsApp version | reach the user on another channel; ask them to confirm they can message the number, accept the terms, and update WhatsApp | nothing — not delivered | R7 |
| 131047 | not stated | "More than 24 hours have passed since the recipient last replied to the sender number." | the customer-service window has closed | send a template message instead | nothing — not delivered | R7 |
| 131049 | not stated | "This message was not delivered to maintain healthy ecosystem engagement." | per-user marketing limit blocked it; arrives as a `failed` status webhook | wait **at least 24 hours** before resending that template; resending sooner will likely fail again and can reduce the accuracy of delivery reporting | nothing — not delivered | R7, R10 |
| 131050 | not stated | "This recipient has chosen to stop receiving marketing messages on WhatsApp from your business." | the user opted out of marketing | do not retry; subscribe to the `user_preferences` webhook to track opt-outs and opt-ins | nothing — not delivered | R7 |
| 131051 | not stated | "Unsupported message type." | the message type is not supported | use a supported type | not stated | R7 |
| 131053 | not stated | "Unable to upload the media used in the message." | media could not be uploaded, e.g. unsupported type | check `error.error_data.details` on the `messages` webhook for the failed message; confirm the media type | not stated | R7 |
| 130472 | not stated | "Message was not sent as part of an experiment." | excluded from a Meta experiment | see Meta's Marketing Message Experiment documentation | nothing — not sent | R7 |
| 131000 | not stated | "Message failed to send due to an unknown error." | unspecified | retry; if it persists, open a Direct Support ticket | not stated | R7 |
| 131031 | not stated | "The WhatsApp Business Account associated with the app has been restricted or disabled for violating a platform policy" | account restricted/disabled, or request data could not be verified against the account (e.g. an incorrect two-step PIN) | review Policy Enforcement; use the Health Status API for detail on the lock | not stated | R7 |
| 131042 | not stated | "There was an error related to your payment method." | billing problem blocking delivery | verify billing: payment account attachment, credit line, timezone/currency, pending or declined request | not stated | R7 |
| 131009 | not stated | "Parameter value is not valid" | invalid `message_id` on a mark-as-read call | pass a valid `wamid` from a received message | nothing | R8 |

### 3.1 What a `failed` status actually carries

R1 gives the `errors[]` object: `code` (integer, e.g. `131049`), `title` (a short error title), `message` (R1:
**the same text as `title`**), `error_data.details` (a longer explanation) and `href` (a link to the error-code
documentation). `errors[]` is present only when sending or delivery fails.

Two consequences for Lynomia. First, `message` is not extra information — storing or displaying `title` and
`message` as if they were two distinct facts is noise. Second, `error_data.details` is the only field that carries
the specific cause (R7 explicitly directs integrators to it for 131053), so a status pipeline that keeps only
`code` and `title` discards the one field Meta tells you to read.

## 4. Limits and numbers

Only numbers a source states.

| Number | What it bounds | Row |
|---|---|---|
| 30 days | default message TTL, all messages except authentication templates | R6 |
| 10 minutes | default TTL for authentication templates | R6 |
| 30 days | window in which an incoming message should be marked as read | R8 |
| up to 3 | status webhooks per outgoing message (`sent`, `delivered`, `read`) | R2 |
| up to 7 days | WhatsApp webhook retry window after a non-200 response | R4 |
| 36 hours | Graph API webhook retry window; unacknowledged responses dropped afterwards | R5 |
| 1000 updates | maximum notifications per webhook batch; batching not guaranteed | R5 |
| 3 MB | maximum webhook payload size | R4 |
| at least 24 hours | wait before resending a template that failed with 131049 | R7, R10 |
| up to 24 hours | further delivery attempts to that one user may be blocked after repeated 131049 retries | R10 |
| 24 hours | customer-service window referenced by 131047 ("more than 24 hours ... since the recipient last replied") | R7 |

## 5. Version and deprecation notes

- **v24.0+**: R1 states the `conversation` object is omitted unless the message falls in a free entry point window.
  Pipelines that key conversation/pricing analytics off `conversation.id` will see it disappear on newer versions.
- **`pricing.billable` is deprecated** (R1); Meta recommends `pricing.type` and `pricing.category` instead.
- **`pricing.pricing_model`**: `PMP` (per-message pricing) or `CBP` (conversation-based pricing, "for webhooks sent
  before July 1, 2025") (R1). `CBP` in fresh traffic would be anomalous.
- **`pricing.type`**: `regular`, `free_customer_service`, `free_entry_point` (R1).
- **Error `title` will be deprecated** (R7) — classify on `code`, never on `title` text.
- **R8's example uses v25.0**; the API version segment is optional on that endpoint.
- **Documentation has moved** from `/docs/whatsapp/cloud-api/...` to `/documentation/business-messaging/whatsapp/...`
  for several of these pages; the mark-as-read guide under the old path is a hard 404 (§1).

## 6. Ambiguities and gaps

Stated plainly, unresolved on purpose.

1. **Does the recipient's read-receipts setting suppress the `read` webhook?** Meta's developer documentation does
   not say. The consumer Help Center documents the setting (R11, R12). Lynomia cannot claim either behaviour.
2. **Webhook retry window: 7 days (R4) or 36 hours (R5)?** The WhatsApp-specific page and the general Graph page
   disagree. Needs arbitration (probably: the WhatsApp page governs WABA webhooks), but neither page says so.
3. **Is a `failed` webhook guaranteed when the TTL expires?** Not stated. R6 instead tells integrators to assume a
   drop from the *absence* of `delivered`, which implies silence is a possible terminal outcome.
4. **Is the order of status events for a single message guaranteed?** Not stated anywhere I read. Only cross-message
   ordering is explicitly unguaranteed (R6).
5. **R1 contradicts itself on `conversation.expiration_timestamp`**: its field table says the field appears only
   with `sent`, while an adjacent note says the `conversation` object appears with `sent` and with `delivered`/`read`.
6. **`held_for_quality_assessment` and `paused`** are documented only as send-response `message_status` values (R9).
   Whether they ever surface as webhook statuses, and what webhook a held or paused message eventually produces, is
   not stated.
7. **Custom TTL ranges are unverified.** `/documentation/business-messaging/whatsapp/messages/time-to-live` returned
   navigation chrome only on two attempts (WebFetch and a direct read); the body is client-rendered. O2's numbers
   are unconfirmed and must not be published. Agent 088 or 091 should retry this page.
8. **The multi-device `delivered` + `failed` claim (O1)** — that one message can receive both, when the user is
   logged in on several devices — appeared repeatedly in search summaries attributed to Meta pages, but I could not
   locate it on any page body I read. It is plausible and consequential (it would mean `delivered` and `failed` are
   not mutually exclusive), so it needs confirming before any Lynomia article relies on, or contradicts, it.
9. **`deleted` and `warning`** do not appear as message statuses on any normative page read. If Lynomia's code or
   corpus references them, the reference is unsourced (hand-off to agents 007 and 040).
10. **Does the business's own mark-as-read call emit anything?** R8 documents only `{"success": true}`.

## 7. What Lynomia users would ask

- "It says Sent but the customer says they got nothing — where is it?"
- "Why does this message show Delivered but never Read? Did they ignore us?"
- "The message never changed from Sent at all. Is it stuck?"
- "We sent 50 campaign messages; 6 say Failed with a number. What do the numbers mean?"
- "Why did the same message arrive twice in our reporting?" (webhook retries and batching — R4, R5)
- "Why did the statuses arrive out of order / why did Delivered never appear but Read did?" (R1's read-implies-delivered)
- "The API said the message was accepted. Why is the customer complaining?" (R9 vs R6)
- "How long before we know a message will never arrive?" (TTL — R6)
- "An OTP template failed within minutes but a normal message to the same person was fine." (10-minute authentication TTL — R6)
- "We got 131049 — can we just send it again?" (no: 24 hours — R7, R10)
- "Can we tell whether a customer has read receipts turned off?" (no — §2.6)

## 8. The honesty line: what each status proves, and what it does not

This is the section Lynomia's troubleshooting articles must be written against. **Lynomia must never assert
provider state it did not receive**, and must never convert the absence of an event into an assertion about the
person.

| Status Lynomia holds | What the business may legitimately conclude | What it may **not** conclude | Row |
|---|---|---|---|
| send accepted (`message_status: accepted`) | Meta took the request and is processing it | that it was sent, delivered, or will ever be delivered — R6 says the response "does not indicate successful delivery" | R9, R6 |
| `sent` | Meta's servers sent the message toward the recipient | **nothing about arrival.** A message can be `sent` and then `failed` days later (TTL up to 30 days), or be dropped in silence | R1, R6 |
| `delivered` | the message reached the recipient's device (consumer wording: "the recipient's phone **or any of their linked devices**") | **that a human saw it.** Meta's own *Message info* wording is explicit: delivered means "but the recipient hasn't seen it". Device ≠ person, and one linked device ≠ the phone in their hand | R1, R11 |
| `read` | the message was displayed in an open chat on the device | that it was comprehended, acted on, or read by the intended person; and, where the account is shared or the chat was opened in a notification shade, not even that it was looked at. `read` also implies `delivered`, so a missing `delivered` is not a contradiction | R1 |
| `played` | a voice message was played for the first time | that it was listened to in full. R11 distinguishes "seen your voice message, but hasn't played it" from played | R1, R11 |
| `failed` | this delivery attempt failed, with the code and `error_data.details` Meta supplied | that the recipient did not get *some* copy (see O1, unconfirmed), or that retrying will work — 131050 explicitly must not be retried | R1, R7, R10 |
| no `delivered` yet | nothing has confirmed arrival | **not** that it failed. Statuses are asynchronous, webhooks are retried, batched, and can be delayed; R6 says a `failed` webhook itself can arrive after "a minor delay". Only TTL expiry licenses the inference "assume dropped" | R4, R5, R6 |
| no `read` | Lynomia never received a read event | **not** that the message is unread. R11 lists six causes for a missing read receipt, of which "not opened" is one: the recipient or the sender may have read receipts disabled, the recipient may have blocked the sender, either side may have connectivity problems, the clock may be wrong, and "When a person gets your message for the first time, a read receipt might not be sent to you" | R11, R12 |
| no status at all | the webhook never arrived, or was never sent | **not** that nothing happened. R4: webhooks are not all sent while the app is in Dev mode; R5: history cannot be queried, so a status lost at the HTTP boundary is lost permanently | R4, R5 |

### 8.1 The three questions the brief asks, answered

- **Does `delivered` mean the person saw it?** No, and Meta says so in its own words: delivered is "delivered to
  your recipient's phone or linked devices, **but the recipient hasn't seen it**" (R11). The Cloud API definition is
  device-level — "the message reached the user's device" (R1).
- **Does the absence of `read` mean unread?** No. It means no read event was received. Meta documents at least six
  distinct causes for a missing read receipt, including a privacy setting on either side, and additionally states
  that read receipts are *always* sent for group chats — so the signal's availability itself varies by context
  (R11, R12). Meta's developer docs never promise a `read` webhook for every read message, and R1 shows the related
  case where `delivered` is deliberately skipped.
- **Does `sent` guarantee anything?** Only that Meta's servers sent it onward (R1). It is compatible with a failure
  arriving up to 30 days later, with the message being dropped and no `failed` ever arriving (R6), and with a
  `failed` that was merely delayed (R6).

### 8.2 Drafting rules this produces for the corpus

1. Name the status, then name the uncertainty. "Delivered means it reached their device" — never "they got it".
2. Never render a missing status as a negative claim in UI copy or help text ("Unread", "Ignored", "Not delivered").
   The honest phrasing is "no read receipt received".
3. When an article explains a wait, give Meta's number and Meta's rule: no `delivered` before TTL (30 days;
   10 minutes for authentication templates) → assume dropped, with a buffer for a late `failed` (R6).
4. Classify failures on `code`, quote `error_data.details`, and link Meta's `href`. Do not paraphrase a code's
   meaning into a new sentence that Meta does not support, and never invent a code.
5. Do not document `accepted`, `deleted` or `warning` as statuses Meta sends (§2.2).
6. Say "read receipts may be unavailable" rather than explaining *why* in Cloud API terms — Meta does not document
   the API-side interaction with the privacy setting (§6.1).
