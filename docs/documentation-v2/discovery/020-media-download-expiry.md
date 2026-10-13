---
agent: 020
scope: WhatsApp Cloud API inbound media retrieval — webhook payload, two-step download, URL and media-ID expiry, failures
confidence: high
sources_normative: 13
sources_observational: 2
---

# 020 — Receiving media: retrieval, expiry and the failures a download produces

This report covers the **inbound** half of media: a customer sends Lynomia a photo, a PDF, a voice note or a
sticker, and Lynomia has a bounded amount of time to get the bytes before Meta stops serving them. Agent 019
owns the outbound/upload half; where the two touch (the 30-day life of media Lynomia itself uploads) it is
marked as such.

---

## 1. Source register

Every claim below references a row by its `S` number. All rows were fetched read-only on **2026-10-13**. No
Graph endpoint was called, no credential was used, no form submitted.

| # | Source URL | Page title | Product | API / version context | Date checked | Status |
|---|---|---|---|---|---|---|
| S1 | `https://developers.facebook.com/docs/whatsapp/cloud-api/reference/media` | Media | WhatsApp Cloud API | Cloud API reference; endpoint written `/<API_VERSION>/<MEDIA_ID>`, no version floor stated | 2026-10-13 | normative |
| S2 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/business-phone-numbers/media.md` | Media | WhatsApp Cloud API | current docs tree (`/documentation/business-messaging/`), same endpoint | 2026-10-13 | normative |
| S3 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/image.md` | Image messages (webhook reference) | WhatsApp Cloud API | webhooks `messages` field | 2026-10-13 | normative |
| S4 | `.../webhooks/reference/messages/document.md` | Document messages (webhook reference) | WhatsApp Cloud API | webhooks `messages` field | 2026-10-13 | normative |
| S5 | `.../webhooks/reference/messages/audio.md` | Audio messages (webhook reference) | WhatsApp Cloud API | webhooks `messages` field | 2026-10-13 | normative |
| S6 | `.../webhooks/reference/messages/sticker.md` | Sticker messages (webhook reference) | WhatsApp Cloud API | webhooks `messages` field | 2026-10-13 | normative |
| S7 | `.../webhooks/reference/messages/errors.md` | Errors (webhook reference) | WhatsApp Cloud API | webhooks `messages` field | 2026-10-13 | normative |
| S8 | `.../webhooks/reference/messages/unsupported.md` | Unsupported messages (webhook reference) | WhatsApp Cloud API | webhooks `messages` field | 2026-10-13 | normative |
| S9 | `https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes` | WhatsApp error codes | WhatsApp Cloud API | no version stated | 2026-10-13 | normative |
| S10 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/changelog` | WhatsApp changelog | WhatsApp Business Platform | dated entries, 2025–2026 | 2026-10-13 | normative |
| S11 | `https://developers.facebook.com/docs/graph-api/overview/rate-limiting` | Rate Limits | Graph API | Business Use Case rate limits | 2026-10-13 | normative |
| S12 | `https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/payload-examples` | Payload examples | WhatsApp Cloud API | — | 2026-10-13 | normative (negative check: contains **no** media example; only a text message. Media fields live on S3–S6) |
| S13 | `https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/components` | Components | WhatsApp Cloud API | — | 2026-10-13 | normative (negative check: does **not** define the media objects; defers to the per-type references) |
| S14 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/rate-limits` | — | — | — | 2026-10-13 | normative (negative check: **404 Page Not Found**; there is no such page at that path) |
| O1 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users/` | Onboard WhatsApp Business app users | WhatsApp Cloud API | — | 2026-10-13 | **observational, unconfirmed** — surfaced by search summary only, not fetched directly in this run. Claim: a feature-comparison table lists "View once message — Not supported." Treat as unverified until the page itself is read. |
| O2 | search-engine summaries (Meta domain restricted) | — | — | — | 2026-10-13 | **observational, unconfirmed** — used only to locate pages and to flag a February 2026 changelog entry adding unsupported message types, which was not read directly. |

---

## 2. The rules

### 2.1 What an inbound media webhook actually contains

The media payload is nested at `entry[].changes[].value.messages[].<type>`, where `<type>` is `image`, `audio`,
`video`, `document` or `sticker`. Per-type fields, from S3–S6:

| Field | image | audio | video | document | sticker | Meta's description |
|---|---|---|---|---|---|---|
| `id` | yes | yes | yes | yes | yes | the media asset ID; S4 words it "Send a GET request to this ID to retrieve the asset URL" |
| `mime_type` | yes | yes | yes | yes | yes | the asset's MIME type (`image/jpeg`, `audio/ogg; codecs=opus`, `image/webp` in the examples) |
| `sha256` | yes | yes | yes | yes | yes | SHA-256 hash of the asset |
| `caption` | yes | no | yes | yes | no | caption text the user added |
| `filename` | no | no | no | **yes** | no | "Original name of the file" — the document type is the only one carrying it |
| `voice` | no | **yes** | no | no | no | boolean, "indicating if audio is a recording made with the WhatsApp client voice recording feature" |
| `animated` | no | no | no | no | **yes** | boolean, true for an animated sticker |
| `url` | yes | yes | yes | yes | yes | **new in 2025** — see §2.2 and §5 |

Context fields sit beside the media object, not inside it: `messages[].context.forwarded` /
`frequently_forwarded` (present only when forwarded), and a `messages[].referral` object with `source_url`,
`source_id`, `source_type`, `body`, `headline`, `media_type`, `image_url`, `video_url`, `thumbnail_url`,
`ctwa_clid` and `welcome_message.text` when the media arrived through a Click-to-WhatsApp ad (S3, S5, S6).

The field a documentation reader most often expects and does **not** get is file size. The webhook does not
carry `file_size`; only the `GET /<MEDIA_ID>` response does (S1, S2).

### 2.2 The two-step retrieval, and the 2025 change that makes step one conditional

**Step one — resolve the ID to a URL.** `GET https://graph.facebook.com/<API_VERSION>/<MEDIA_ID>`, Bearer token
in the `Authorization` header, with an optional `?phone_number_id=<BUSINESS_PHONE_NUMBER_ID>`. S1 and S2 state
that when `phone_number_id` is supplied the request is processed only if that ID matches the business number the
media was uploaded on. The response carries `messaging_product`, `url`, `mime_type`, `sha256`, `file_size`
(rendered as a string in Meta's example) and `id` (S1, S2).

**Step two — download the bytes.** `GET <MEDIA_URL>` with the same Bearer token. The body is the binary asset
and the `Content-Type` response header gives the MIME type (S1, S2).

**Why it is two steps.** Meta does not state a rationale anywhere in S1–S13. What the documentation *does* state
is that the URL is short-lived and must be re-requested: "Media URLs expire after 5 minutes, after which you
must query the ID again to get a new URL" (S1, S2). The example URLs in S3 and S5 are on
`lookaside.fbsbx.com/whatsapp_business/attachments/?mid=...`, i.e. a CDN host distinct from `graph.facebook.com`.
That the indirection exists *because* a 5-minute CDN link cannot be a durable identifier is an **inference, not
normative** — and Meta does not promise that host either (§6).

**The change.** Since late 2025 the inbound webhook itself carries a `url`. S1 states: "Note that incoming media
messages webhooks (image messages, video messages, and so on) include the media URL, which is assigned to the
`url` property." S4 describes the field as a "Media URL that you can query with your access token to download
the file," adding that the property "is being released gradually and may not be available to you yet." S3, S5
and S6 give the rollout wording: the property "is being released to developers gradually over several weeks,
starting November 12, 2025, and may not be available to you immediately."

So for an installation that is receiving `url` in webhooks, step one is skippable *within the URL's validity
window*. It is **not** removable: Meta keeps documenting the `id` as the thing you GET to obtain a URL (S4), and
whether the webhook-delivered URL carries the same 5-minute life is **not stated** (§6.1). Lynomia's design must
keep the ID path as the real path and treat a webhook `url` as a fast path that may be absent, by rollout, and
may already be dead by the time a retry runs.

### 2.3 Authentication on the download

This is the detail most often got wrong. The media URL is **not** a pre-signed public link. S1 and S2 both
state "Include your access token in the request" and, flatly, "If you omit your token, the request will fail."
The documented call is `curl '<MEDIA_URL>' -H 'Authorization: Bearer <token>' -o '<DESIRED_FILE_NAME>'` (S1).

Two consequences for an inbox product. First, the URL cannot be handed to a browser, an `<img src>`, a mobile
client or a third-party service — the bytes must be fetched server-side by something holding the WABA access
token, then stored by Lynomia and served from Lynomia. Second, a download failure can be a *token* failure
rather than an *expiry* failure, which is exactly why Meta's own remediation ladder ends at "renew your access
token" (§2.5). No `User-Agent` requirement, redirect-following rule, or range-request support is documented in
S1 or S2 — all three are **not stated**.

### 2.4 The three validity windows — quoted

These are the numbers Meta commits to. Quoted verbatim from S1 and S2, which agree word for word:

| What | Window | Meta's exact words | Source |
|---|---|---|---|
| A media URL, once obtained | **5 minutes** | "Media URLs expire after 5 minutes, after which you must query the ID again to get a new URL." and "The URL is only valid for 5 minutes." | S1, S2 |
| A media ID **received in a webhook** (i.e. a customer's file) | **7 days** | "Media IDs in webhooks expire after 7 days." and "Note that when retrieving a media from a media ID received via webhook, the media ID will only be available to download for 7 days." | S1, S2 |
| A media ID **returned by the API** (i.e. media Lynomia uploaded) | **30 days** | "Media IDs returned by the API expire after 30 days." and "All media files sent through this API are encrypted and persist for 30 days, unless they are deleted earlier." | S1, S2 |

The 7-day number is the one that governs inbound and it is the one most likely to be wrong in any integration
written before October 2025 — it used to be 30 days (§5).

### 2.5 What the download returns once the window has passed

One response, quoted from S1 and S2: "If the download attempt fails, you will receive a `404 Not Found`
response code." The documented remediation is, in order: "In that case, try to get a new media URL and download
it again," then "If doing so doesn't resolve the issue, renew your access token and attempt to download the
media asset again."

That is the whole of it. Meta documents **no distinct error code, subcode or body** that separates an expired
URL from an expired media ID from a deleted asset from a wrong or revoked token. All four present as the same
bare `404`. There is no documented "media expired" code on either step, and the error-code reference (S9) does
not document the media GET endpoint at all.

### 2.6 The operational consequence — what Lynomia's documentation must say

Stated honestly, and separating commitment from silence:

**What Meta commits to.**
- A customer's inbound file is retrievable, via its webhook media ID, for **7 days** from the webhook (S1, S2).
- Each URL obtained for it is usable for **5 minutes** (S1, S2).
- Media that *Lynomia* uploads persists **30 days** unless deleted earlier, and is encrypted at rest (S1, S2).

**What is not stated.**
- Any retention of inbound customer media beyond 7 days, for any reason, under any plan or support tier.
- Any recovery, re-issue, archive, "undelete" or support path once the 7 days have passed.
- Any warning, webhook, or notification before a media ID expires.
- Whether the 7-day clock starts at the message `timestamp`, at webhook delivery, or at first successful
  retrieval.
- Whether a webhook-delivered `url` has its own validity window, or inherits the 5-minute rule (§6.1).
- Whether `DELETE /<MEDIA_ID>` applies to inbound customer media at all; S1 and S2 document delete beside
  upload and say nothing about assets Lynomia did not upload.

**Therefore.** If Lynomia has not downloaded and persisted the bytes within 7 days of receiving the webhook, the
customer's attachment is **gone from the provider and cannot be recovered through any documented API**. The only
remedy Meta itself documents is social, not technical: for error 131052 the error-code reference tells the
business to "ask the user to resend it through a non-WhatsApp method" (S9). Lynomia's help articles must not
promise an agent that an old conversation's attachment can be re-fetched, must not describe a 30-day inbound
window, and should state the 7-day fact plainly, because it converts "retrieval is slow" from a performance
problem into permanent data loss. A retrieval that is merely *retried later* is not a retry; after the window it
is a guaranteed 404.

### 2.7 Rate limits on media retrieval

Meta documents **no media-endpoint-specific rate limit**. S2 says nothing about rate limits on the media
endpoints; the path a reader would guess, `/documentation/business-messaging/whatsapp/rate-limits`, is a 404
(S14).

What is documented is the Graph-level envelope (S11). Business Use Case (BUC) rate limits apply to WhatsApp
Business Management API endpoints and are stated as request counts per hour, not a formula: "200 requests per
hour, per app, per WABA, by default," rising to "5000 requests per hour, per app, per active WABA" for WABAs
with at least one registered phone number. S11 also states that "If both Platform and Business Use Case rate
limits can be applied to a request, BUC rate limits will be applied," and that throttled responses carry
`X-Business-Use-Case-Usage` with `call_count`, `total_cputime`, `total_time`, `estimated_time_to_regain_access`
and `type`.

Crucially, S11's WhatsApp tables enumerate management endpoints (`GET /<WHATSAPP_BUSINESS_ACCOUNT_ID>`,
`phone_numbers`, `message_templates`, `subscribed_apps`) and **do not name `GET /<MEDIA_ID>`**. Whether the
200/5000-per-hour figures govern media-ID resolution is therefore **not stated** — an inference at best. And
nothing in S1, S2 or S11 states any limit on the CDN download itself. A documentation claim of the form "you may
resolve N media IDs per hour" has no normative basis and must not be written.

### 2.8 Encryption, stickers, voice notes, view-once

**Encryption.** One sentence exists: "All media files sent through this API are encrypted and persist for 30
days, unless they are deleted earlier" (S2). Nothing about keys, algorithms, or a decryption step the caller
must perform — and the download is documented as returning the binary asset with a `Content-Type` header (S1,
S2), so no caller-side decryption is described. Beyond that sentence, **not stated**.

**Stickers.** `sticker.animated` is a boolean, true for animated (S6); the example `mime_type` is `image/webp`.
S2 states "WebP images can only be sent in sticker messages," and gives send-side caps of 500 KB animated /
100 KB static. Retrieval is the same two steps — no sticker-specific path.

**Voice notes.** There is no separate type: a voice note arrives as `type: audio` with `audio.voice: true`,
described as "a recording made with the WhatsApp client voice recording feature" (S5); the example MIME is
`audio/ogg; codecs=opus`. A dictated-vs-attached distinction is therefore available to the UI, which matters for
rendering a waveform player rather than a file chip. Separately, the changelog adds a `played` status value
"which indicates when a voice message is played by the WhatsApp user" (S10, 2025-11-03) — that is outbound
status, not retrieval, but it belongs in the same help article.

**View-once.** Meta's inbound webhook references (S3–S6) do not mention view-once media at all, and there is no
view-once message type. The unsupported-message reference (S8) enumerates `unsupported.type` values —
`button`, `edit`, `errors`, `gif`, `group_invite`, `hsm`, `image`, `interactive`, `keep_in_chat`,
`link_preview`, `list`, `location`, `media_placeholder`, `order`, `pin`, `poll_creation`, `poll_update`,
`product`, `reaction` — of which `media_placeholder` and `keep_in_chat` look related, but **Meta does not state
what produces either**. The claim that view-once is simply "not supported" comes from O1, a search summary, and
is recorded as **observational, unconfirmed**. Note also that `image` and `gif` appear in that enumeration: an
image can arrive as `type: unsupported` with `unsupported.type: image` and no media ID to retrieve.

---

## 3. Error codes and failures

Both retrieval steps, plus the webhook-side failures that mean there is nothing to retrieve. `not stated` is
used wherever Meta's pages are silent — nothing here is inferred or invented.

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Source |
|---|---|---|---|---|---|---|
| *(no code; HTTP `404 Not Found`)* | not stated | not stated — S1/S2 say only "you will receive a `404 Not Found` response code" | The download of `<MEDIA_URL>` failed. Overloaded: expired URL, expired media ID, missing/invalid token, or deleted asset all present identically | "try to get a new media URL and download it again"; then "renew your access token and attempt to download the media asset again" | nothing | S1, S2 |
| 131052 | not stated | **Two conflicting titles across normative pages.** S9: "Unable to download the media sent by the user." S2: "Media file size too big. Max file size we currently support: 100MB." | Inbound media could not be retrieved by Meta/the business. S2 attributes it specifically to a customer file over 100 MB | S9: inspect `error.error_data.details` in the related `messages` webhook; if the file still cannot be retrieved, **"ask the user to resend it through a non-WhatsApp method"**. S2: send the customer a warning | nothing automatic; the customer believes the file was delivered | S9, S2 |
| 131053 | not stated | "Unable to upload the media used in the message." | Send-side, not retrieval. S2 calls mismatched MIME type "a common error" | Inspect `error.error_data.details`; verify the real type with `file -I` against the supported list | send fails | S9, S2 |
| 131051 | not stated | "Message type unknown" — details: "Message type is currently not supported." | The message arrives as `type: unsupported` with `unsupported.type` naming the real type. There is no media ID; nothing can be retrieved | Nothing retrievable. Surface to the agent that an unmirrorable message exists | the customer sees their own message as sent | S8, S9 |
| 131060 | not stated | "This message is currently unavailable." | S8: typically a user's first message to a business onboarded with a WhatsApp Business app phone number | not stated beyond the above | not stated | S8 |
| 130429 | not stated | "Rate limit hit" — details: "Message failed to send because there were too many messages sent from this phone number in a short period of time" | Send throughput, delivered via the `errors` webhook. **Not** a media-retrieval limit | retry | not stated | S7 |
| 100 | not stated | "The request included one or more unsupported or misspelled parameters." | Generic Graph parameter error. S9 does not document the media GET endpoint, so its application to `GET /<MEDIA_ID>` is **inference** | check the endpoint reference for supported parameter names and length limits | n/a | S9 |
| 190 | not stated | "Your access token has expired." | Token expiry — the second rung of Meta's own 404 ladder | get a new access token | n/a | S9 |
| 200 | not stated | "No access token was provided." | Omitted token. S9 notes this is distinct from 190 | include a valid token | n/a | S9 |
| 0 | not stated | "We were unable to authenticate the app user." | authentication failure | get a new access token | n/a | S9 |
| 3 / 10 / 200–299 | not stated | capability or permission errors | the app lacks a required permission | confirm permissions with the access token debugger | n/a | S9 |
| 131008 | not stated | "The request is missing a required parameter." | generic | check the endpoint reference | n/a | S9 |
| 131009 | not stated | "One or more parameter values are invalid." | generic | check the endpoint reference | n/a | S9 |
| 1 / 2 / 131016 | not stated | server or temporary errors | transient | check the WhatsApp Business Platform status page and retry | n/a | S9 |
| 131000 | not stated | "Message failed to send due to an unknown error." | unknown | retry; if persistent, open a Direct Support ticket | n/a | S9 |
| 4 | not stated | app has reached its rate limit (Platform) | Graph throttle | back off | n/a | S11 |
| 17 | not stated / 2446079 | user has reached their rate limit (Platform); subcode 2446079 is Ads-API-specific and not WhatsApp | Graph throttle | back off | n/a | S11 |
| 32 | not stated | user or app limit on a Pages API request | not WhatsApp media | — | — | S11 |
| 613 | not stated / 1996 | a custom rate limit has been reached; subcode 1996 is "inconsistent API request volume was detected for your app" | Graph throttle | consult the specific API's docs; spread queries evenly | n/a | S11 |
| 80008 | not stated | listed in S11's BUC error table under the title "WhatsApp Business Management API" | BUC throttle on management endpoints | honour `X-Business-Use-Case-Usage` and back off | n/a | S11 |

**Explicitly not found:** no code for "media ID expired", no code for "media URL expired", no code for "media
deleted", and no documented error body on `GET /<MEDIA_ID>` for an expired webhook media ID. Any article that
names such a code would be inventing it.

---

## 4. Limits and numbers

Only numbers a source states.

| Number | What it bounds | Source |
|---|---|---|
| 5 minutes | validity of an obtained media URL | S1, S2 |
| 7 days | validity of a media ID received via webhook (inbound customer media) | S1, S2 |
| 30 days | validity of a media ID returned by the API; persistence of uploaded media unless deleted | S1, S2 |
| 100 MB | "The maximum supported file size for media messages on Cloud API is 100MB." Exceeding it on inbound produces 131052 | S2 |
| 5 MB / 16 MB / 16 MB / 100 MB | outbound upload caps for images / video / audio / documents (Agent 019's territory; listed for cross-reference) | S2 |
| 500 KB / 100 KB | animated / static sticker caps | S2 |
| 200 requests/hour/app/WABA | default BUC limit on the *named* WhatsApp Business Management endpoints — media endpoints are not among them | S11 |
| 5000 requests/hour/app/active WABA | BUC limit for WABAs with at least one registered phone number | S11 |
| up to 32 objects | maximum entries in `X-Business-Use-Case-Usage` | S11 |

No number is documented for media-retrieval throughput or for CDN download concurrency.

---

## 5. Version and deprecation notes

The endpoint is Graph-versioned (`https://graph.facebook.com/<API_VERSION>/<MEDIA_ID>`), but S1 and S2 state no
minimum version for any of the behaviour above, including the new `url` property. The changes that matter are
dated changelog entries (S10):

| Date | Entry | Why it matters |
|---|---|---|
| 2025-09-24 | A note was added that when retrieving media from a media ID received via webhook, "the media ID will only be available to download for 30 days," followed by: "After October 9th this will only be available for 7 days." | **The inbound window was cut from 30 days to 7 on 2025-10-09.** Any Lynomia code, article or runbook written before then that assumes 30 days for *customer* media is wrong by a factor of four. |
| 2025-10-16 | Incoming media messages webhooks "now include the incoming media asset's media URL, which is assigned to the `url` property." | The `url` fast path exists. |
| 2025-11-03 | A new `played` status was added, "which indicates when a voice message is played by the WhatsApp user." | Voice-note lifecycle; belongs in the voice-note article. |
| 2025-11-03 | The unsupported messages webhook was updated "by adding details about the actual message type." | `unsupported.type` is why an agent can be told *what* could not be mirrored. |
| 2026-02 (month only; **observational, unconfirmed** via O2) | further unsupported message types added to that webhook | the `unsupported.type` enumeration in S8 may already have grown; re-read S8 before publishing a list. |

**Date inconsistency, unresolved.** S10 dates the webhook `url` feature 2025-10-16. S3, S5 and S6 say the
property is "being released to developers gradually over several weeks, starting November 12, 2025." S4 says
only that it "is being released gradually and may not be available to you yet," with no date. Both are
normative Meta pages. The honest reading is that the capability shipped in mid-October and per-account rollout
began 12 November 2025, but Meta does not say that — and no page states when the rollout completed, so as of
2026-10-13 there is no normative basis for assuming every account receives `url`.

---

## 6. Ambiguities and gaps

Stated plainly rather than resolved by guessing.

1. **Does a webhook-delivered `url` expire in 5 minutes?** The 5-minute rule is stated for "media URLs"
   generally (S1, S2) and was written when the only way to get one was `GET /<MEDIA_ID>`. S3–S6 attach no
   window to the webhook `url` field. Meta never says whether the clock starts at URL minting, at webhook
   delivery, or whether webhook URLs are longer-lived. **Not stated.** The only safe engineering posture is to
   treat it as already possibly expired and fall back to the ID.
2. **131052 has two different titles on two normative Meta pages** — S9's "Unable to download the media sent by
   the user." versus S2's "Media file size too big. Max file size we currently support: 100MB." These describe
   different causes. Lynomia must not publish one as *the* meaning; it should state that 131052 means Meta could
   not hand over the customer's file and that an over-100 MB file is one documented cause.
3. **No code distinguishes expiry from auth failure.** A bare `404` covers expired URL, expired ID, deleted
   asset and bad token. Lynomia cannot build a user-facing diagnosis from the response alone, and the help
   article cannot promise one.
4. **No documented error for an expired webhook media ID on step one.** S9 does not document the media GET
   endpoint; whether an expired ID yields 404, code 100, or something else is unverified.
5. **Media endpoints are absent from every documented rate-limit table** (S11, S2, and S14 is a 404). No number
   may be published for media retrieval.
6. **`media_placeholder` and `keep_in_chat`** appear as `unsupported.type` values (S8) with no definition of
   what produces them. The natural guesses — view-once, kept-in-chat disappearing messages — are guesses.
7. **View-once inbound behaviour is undocumented** in S3–S8. The "not supported" claim is O1, unconfirmed.
8. **The CDN host is not promised.** `lookaside.fbsbx.com` appears in examples (S3, S5) but no page commits to
   it, so it must not become an allowlist entry in documentation without being flagged as example-derived.
9. **No `User-Agent`, redirect-following or range-request behaviour is documented** for the download (S1, S2).
10. **The 7-day clock's start point is not stated** — message `timestamp` versus webhook delivery. For a product
    recovering from a webhook outage this is the difference between having time and not.
11. **`DELETE /<MEDIA_ID>` is documented beside upload only** (S1, S2); whether it is valid for inbound customer
    media is not stated.
12. **No webhook announces expiry.** There is no documented signal that an unretrieved asset is about to become
    or has become unavailable; the first indication is a 404 on demand.

---

## 7. What Lynomia users would ask

The support-desk questions this area generates, which the corpus must answer:

- "A customer sent a photo an hour ago and the conversation shows a broken attachment. Where did it go?"
- "Can you re-download an attachment from a conversation from last month?" — the answer is no, and the article
  must say so without hedging.
- "Why can agents open attachments from this week but not from two weeks ago?"
- "The customer insists they sent the invoice. Our record shows nothing." — maps to 131052 and to the
  unsupported-message path, which are different causes with the same appearance.
- "Can I share the WhatsApp media link with our warehouse team?" — no: the URL requires the WABA access token
  and dies in five minutes (§2.3).
- "Why is a 120 MB video missing?" — the 100 MB inbound ceiling and 131052.
- "We rotated the system-user token on Tuesday and attachments stopped arriving." — the token is required on the
  download, so a token change breaks retrieval, not just sending.
- "Our webhook endpoint was down for a weekend. Do we lose the files?" — depends on redelivery versus the 7-day
  window, whose start point Meta does not state (§6.10).
- "Why does a voice note look different from an audio file?" — `audio.voice`.
- "Why did a sticker arrive but not render?" — `image/webp` plus `animated`.
- "What does 'this message is currently unavailable' mean in our inbox?" — 131060.
- "Does Meta keep a copy we can request for a dispute or an audit?" — not beyond the documented windows, and
  nothing is stated about a support-side retrieval path.
