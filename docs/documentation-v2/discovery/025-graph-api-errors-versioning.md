---
agent: 025
scope: Graph API error envelope, OAuthException family, common error codes, rate-limit envelopes, versioning and deprecation — the layer beneath WhatsApp, Messenger and Instagram alike
confidence: high
sources_normative: 13
sources_observational: 2
---

## 1. Source register

Every claim below cites a row ID from this table. Date checked for all rows: **2026-10-13**.

| Row | Source URL | Page title | Product | API/version context stated by the page | Normative? |
|---|---|---|---|---|---|
| S1 | https://developers.facebook.com/docs/graph-api/guides/error-handling/ | Handling Errors | Graph API | version-agnostic | normative |
| S2 | https://developers.facebook.com/docs/graph-api/overview/rate-limiting/ | Rate Limits | Graph API | version-agnostic; `X-Ad-Account-Usage` scoped to "v3.3 and older" Ads API | normative |
| S3 | https://developers.facebook.com/docs/graph-api/guides/versioning | Versioning | Graph API | states v26.0 is the latest version | normative |
| S4 | https://developers.facebook.com/docs/graph-api/changelog | Graph API Changelog | Graph API | version table v13.0 → v26.0 | normative |
| S5 | https://developers.facebook.com/docs/graph-api/changelog/version26.0/ | Graph API v26.0 | Graph API | v26.0 | normative |
| S6 | https://developers.facebook.com/docs/facebook-login/access-tokens/debugging-and-error-handling | Debugging & Errors | Facebook Login (Graph token layer) | version-agnostic | normative |
| S7 | https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/ | Error Codes | WhatsApp Cloud API | states `error_subcode` not returned in v16.0+ | normative |
| S8 | https://developers.facebook.com/docs/messenger-platform/error-codes | Error Codes | Messenger Platform | version-agnostic; one row references API v8 | normative |
| S9 | https://developers.facebook.com/docs/instagram-api/reference/error-codes/ | Error Codes | Instagram Platform | version-agnostic | normative |
| S10 | https://developers.facebook.com/docs/marketing-api/error-reference/ | Marketing API error codes | Marketing API (same Graph error layer) | version-agnostic | normative |
| S11 | https://developers.facebook.com/docs/graph-api/guides/upgrading | Upgrading | Graph API | version-agnostic | normative |
| S12 | https://developers.facebook.com/docs/whatsapp/business-platform/changelog | Changelog | WhatsApp Business Platform | entries dated to v16.0 and v24.0 | normative |
| S13 | https://developers.facebook.com/docs/graph-api/security/ | Securing Graph API Requests | Graph API | version-agnostic | normative |
| O1 | (fetch result, 2026-10-13) `…/docs/facebook-login/guides/access-tokens/debugging-and-error-handling` returns **HTTP 404**; the live path is the S6 path without `/guides/`. | — | — | — | observational |
| O2 | A Meta developer-community thread surfaced in search reports code 190 with `error_subcode` 459 and a checkpoint message. Community-reported. | — | — | — | observational, unconfirmed |

Two scope items could not be sourced and are **not** asserted anywhere below: a stand-alone common error **code 33**, and a normative page for **code 104**. See §6.

---

## 2. The rules — the error envelope, field by field

### 2.1 The envelope

A failed Graph API call returns a JSON body with a single top-level `error` object. S1 documents seven fields:
`message`, `type`, `code`, `error_subcode`, `error_user_title`, `error_user_msg`, `fbtrace_id`. S8 (Messenger) shows
the same five-field core (`message`, `type`, `code`, `error_subcode`, `fbtrace_id`). S9 (Instagram) and S10
(Marketing) additionally show an `is_transient` boolean in their sample JSON. S7 (WhatsApp Cloud API) shows a
product-specific variant: `message`, `type`, `code`, `error_data.messaging_product`, `error_data.details`,
`error_subcode`, `fbtrace_id` — note that WhatsApp's human-readable cause lives at `error.error_data.details`, not at
the top level of `error`.

Two normative statements govern how code should consume this envelope:

- **Key logic on `code`, never on `message`.** S10 warns that description strings "may change without notice" and
  that error handling should rely on error codes. S7 says the same for Cloud API: build handling around `code` and
  `details`, and explicitly advises against building it around HTTP status codes.
- **HTTP status is not the contract.** S7 does not publish HTTP statuses for its authorization or throttling rows at
  all. S9 is the only page read that tabulates HTTP status per row (almost all `400`, two `403`).

### 2.2 Safe to show a user — the explicit per-field judgement

This is the deliverable. "User" below means three distinct audiences Lynomia must not conflate: the **end customer**
(the person on WhatsApp/Messenger/Instagram), the **agent** (a Lynomia user handling the conversation), and the
**admin/operator** (the account administrator or Lynomia platform support).

| Field | Meta's own description (source) | End customer | Agent | Admin / operator | Why |
|---|---|---|---|---|---|
| `error.message` | "a human-readable description of the error" (S1) | **Never** | **Never raw** | Yes, and always logged | It is developer copy, not product copy. It embeds internal identifiers — S6's documented examples are literally `"Error validating access token: User {user-id} has not authorized application {your-app-id}."` Showing it leaks a Meta user ID and Lynomia's app ID. S7 shows it also embeds the code and title inline, e.g. `(#130429) Rate limit hit`. S10 says the wording can change without notice, so it must never be parsed or displayed as a stable string. |
| `error.type` | the error category; `OAuthException` is the documented example (S1) | Never | Never | Yes | A classifier token, not a sentence. S1 does not describe the field beyond giving an example value. Useful only for routing. |
| `error.code` | the error code, with Meta-published common values and recovery steps (S1) | **Never bare** | Yes, as a labelled reference | Yes — this is the join key | This is the one stable value in the envelope (S10, S7). It is the correct key for Lynomia's own error-article registry: surface it as `Meta error 190` next to Lynomia-authored prose, never as a bare number to a customer. |
| `error.error_subcode` | "extra detail about the error" (S1) | Never | Yes when present | Yes | Operator-grade, and **frequently absent**. Normatively absent for WhatsApp Cloud API: subcodes "will no longer be included in v16.0+ error responses" (S12, Feb 2 2023 entry), restated on S7 as deprecated and not returned in v16.0+. Messenger (S8) and Instagram (S9) still use subcodes heavily, so the field's reliability is *per product*. |
| `error.error_user_title` | "the dialog title, if shown"; language follows the request's locale (S1) | **Yes, when present** | Yes | Yes | One of only two fields Meta frames as user-facing. Present only when Meta intends a dialog, so Lynomia must treat it as optional and never let a missing value produce an empty heading. |
| `error.error_user_msg` | "The message to display to the user" (S1) | **Yes — the only sanctioned field** | Yes | Yes | S1's wording is unambiguous and is the sole normative licence to show Meta text to a person. Two caveats: (a) it is optional — S9 and S10 show it only in sample JSON and neither page defines when it appears; (b) its **language follows the request's locale, not the reader's** (S1), so a Lynomia API call made in English yields English copy even for an Arabic-locale agent or an Arabic-speaking customer. Pass-through without a locale strategy is an RTL/i18n defect, not a feature. |
| `error.fbtrace_id` | an internal support identifier; include it when reporting a bug; "this ID will expire shortly" (S1) | Never | Yes, as a copyable support reference | **Yes, and must be captured at failure time** | The expiry note is operationally decisive: a trace ID is worthless if Lynomia only surfaces it when a human later opens a ticket. It must be persisted with the failed message/webhook row at the moment of failure. |
| `error.is_transient` | **not defined on any page read** — appears only in sample JSON on S9 and S10 | Never | Never | Treat as advisory only | Documented by example, not by rule. Do not build retry logic on it; use the per-code retry guidance in §3 instead. |
| `error.error_data.messaging_product` (WhatsApp) | always `whatsapp` (S7) | Never | Never | Yes | Constant; no information value for Lynomia, which already knows the channel. |
| `error.error_data.details` (WhatsApp) | "the description and likely cause" (S7) | **Never** | Yes | Yes | Operator-grade by content: S7's own `details` text instructs the reader to check quality status in WhatsApp Manager, review template limits, use the Access Token Debugger. None of that is customer copy, and most of it is not agent copy either. |

**The resulting rule for Lynomia's layered error experience.** Exactly one field — `error_user_msg`, plus
`error_user_title` as its heading — may be rendered to a person as Meta's words, and even that needs a locale guard.
Everything else is either a routing key (`code`, `type`, `error_subcode`) or an operator artefact (`message`,
`details`, `fbtrace_id`). The layered experience therefore has to be: **Lynomia-authored prose keyed on `code`** as
the primary surface; `error_user_msg` as an optional verbatim supplement when Meta supplies one; `message` +
`error_subcode` + `fbtrace_id` in an operator-only detail panel and in logs. There is no normative basis for showing
`error.message` to anyone outside that panel.

---

## 3. Error codes and failures

### 3.1 The `OAuthException` family

S1 treats `OAuthException` as a `type`, not a code, and gives the governing rule: **with no subcode, the token or
login status is expired, revoked or invalid — get a new access token; with a subcode, follow the subcode.** Code
`102` (API Session) is handled identically.

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Source |
|---|---|---|---|---|---|---|
| — | — | `OAuthException` (type) | Token/login status expired, revoked or invalid | Get a new access token; if a subcode is present, follow it | nothing user-facing; no `error_user_msg` documented | S1 |
| 190 | (none) | "Access token has expired" | Token no longer accepted | Get a new access token | not stated | S1 |
| 190 | (none) | "Your access token has expired." | WhatsApp Cloud API wording | Get a new access token | not stated | S7 |
| 190 | (none) | "Access Token Error: Invalid OAuth access token." | Messenger wording | not stated beyond the envelope example | not stated | S8 |
| 190 | (none) | "Invalid OAuth 2.0 access token" | Marketing API wording | not stated | not stated | S10 |
| 190 | 458 | "App Not Installed" | The person de-authorized the app, or never authorized it. Documented message: "Error validating access token: User {user-id} has not authorized application {your-app-id}." | Re-authenticate; treat the person as a new user and run the normal login flow | not stated | S1, S6 |
| 190 | 459 | "User Checkpointed" | The person must log in at facebook.com or m.facebook.com to resolve an issue on their account | Nothing server-side fixes this — the person must clear the checkpoint | not stated | S1 (O2 is a community sighting only) |
| 190 | 460 | "Password Changed" | Token invalidated because the person logged out or changed their password. Documented message: "Error validating access token: The session is invalid because the user logged out." On iOS 6+ with the OS-integrated flow, send the person to Facebook OS settings | The person must log in again | not stated | S1, S6 |
| 190 | 463 | "Expired" | Login status or token expired, revoked or otherwise invalid. Documented message: "Error validating access token: Session has expired on …" | Handle as an expired token; re-authenticate | not stated | S1, S6 |
| 190 | 464 | "Unconfirmed User" | The person must log in at facebook.com or m.facebook.com to resolve an issue | Person-side only | not stated | S1 |
| 190 | 467 | "Invalid Access Token" | Token expired, revoked or otherwise invalid | Handle as an expired token | not stated | S1 |
| 190 | 492 | "Invalid Session" | **The person tied to the Page access token lacks an appropriate Page role** | Restore the person's Page role, or re-mint the token from someone who has one | not stated | S1 |
| 102 | (none) | "API Session" | Same semantics as `OAuthException` | No subcode → new token; subcode → follow it | not stated | S1 |
| 102 | (none) | "Session key invalid or expired" | Marketing API wording | not stated | not stated | S10 |
| 0 | (none) | not provided | "We were unable to authenticate the app user." Usually an expired/invalidated token, or the user blocked app access | Get a new access token | not stated | S7 |

S1's subcode table is attached to authentication generally; it does **not** state that every one of 458–492 can
arrive with code 190 specifically, although S6 confirms 458, 460 and 463 do. Treat the 190↔subcode pairing as
confirmed for 458/460/463 and documented-but-unpaired for 459/464/467/492. **Do not assert a 190 pairing for
subcodes beyond those.**

Two facts matter more than the table for Lynomia's error-190 article:

1. **Meta does not notify you.** S6: "Facebook will not notify you that an access token has become invalid." Unless
   the app stores the expiry, it learns of invalidity only when a request fails. Lynomia's two-refusal threshold is
   therefore the correct shape — there is no push signal to subscribe to instead.
2. **Tokens can die early.** S6: "Due to security related events, access tokens may be invalidated before the
   expected expiration time." A stored `expires_at` is a floor, not a guarantee.
3. **Subcode 492 is the one actionable diagnosis in the family** and it is a *Page role* problem, not a token
   problem. S6 lists no error case for app-level or permission changes at all, which corroborates the existing
   article's claim that Lynomia cannot report which permission was lost — Meta publishes no error that names a
   revoked permission. But note that for WhatsApp Cloud API the subcode is not even delivered (S7, S12), so Lynomia
   cannot distinguish 492 from 463 on a WhatsApp inbox. For a Facebook/Instagram inbox on the Messenger or
   Instagram APIs, the subcode is still present and 492 *is* distinguishable.

**Safe-to-show verdict for the whole `OAuthException` family: admin-only.** There is no agent action and no customer
action. A customer must never see it; an agent should see only "this inbox is disconnected, an administrator must
reconnect it"; the admin sees the code, the subcode if any, and the `fbtrace_id`.

### 3.2 The common error codes table (S1), with Meta's recommended handling

| Code | Title as Meta words it | What it means | Meta's recommended handling | Retry? | Safe-to-show audience |
|---|---|---|---|---|---|
| 1 | "API Unknown" | Possibly temporary downtime | Wait and retry; if it recurs, confirm the API exists | yes | operator |
| 2 | "API Service" | Temporary downtime | Wait and retry | yes | operator |
| 3 | "API Method" | Capability or permission issue | Confirm the app has the needed capability or permissions | no | admin |
| 4 | "API Too Many Calls" | App-level throttling | Wait and retry, or review request volume | yes | operator (agent sees only "try again shortly") |
| 10 | "API Permission Denied" | Permission not granted or removed | Handle the missing permission | no | admin |
| 17 | "API User Too Many Calls" | User-level throttling | Wait and retry, or review request volume | yes | operator |
| 102 | "API Session" | See §3.1 | New token, or follow the subcode | no | admin |
| 190 | "Access token has expired" | See §3.1 | Get a new access token | no | admin |
| 200–299 | "API Permission" | A range covering several permissions; permission not granted or removed | Handle the missing permission | no | admin |
| 341 | "Application limit reached" | Temporary downtime or throttling | Wait and retry, or review request volume | yes | operator |
| 368 | "Temporarily blocked for policies violations" | Policy block | Wait and retry | yes | **admin** — a retry alone is not a remedy; the account is in a policy state |
| 506 | "Duplicate Post" | Duplicate posts cannot be published back-to-back | Change the content and try again | no | agent |
| 1609005 | "Error Posting Link" | Problem scraping the linked URL | Check the URL and try again | no | agent |

S1 does not list code **32**, **104**, or a stand-alone **33** in this table. Supplementary normative rows found
elsewhere:

| Code | Subcode | Title as Meta words it | What it means | Handling | Source |
|---|---|---|---|---|---|
| 32 | — | not provided | Pages API: a User or app token has reached its rate limit | Rate-limit handling; see §4 | S2 |
| 104 | — | "Incorrect signature" | Request signature failed validation | not stated | S10 |
| 100 | 33 | "Unsupported get request. Object with ID * does not exist…" | The object does not exist, or the app lacks permission to it | Confirm the ID exists and the app has permission | S8, S10 |
| 294 | — | Requires `ads_management` and an allow-listed app | Marketing API access gate | implied: obtain the permission and allow-listing | S10 |
| 200 | — | not provided | No access token was included. Certain GET endpoints (e.g. `whatsapp_business_profile`) return "Provide valid app ID."; others may return 190 or 104 instead | Include a valid access token — distinct from 190, which is expired/invalid | S7 |
| 613 | — | "Custom rate limit reached" | Endpoint-specific limit | Check the specific API's docs | S2 |
| 613 | 1996 | "Inconsistent request volume detected" | Volume pattern flagged | — | S2 |

`104` is the weakest row in this report: S10 gives the title and nothing else, and S13 — the page that actually
documents `appsecret_proof` and the "Require App Secret" setting — says only that calls lacking the proof "will
fail" and **names no code at all**. The common inference that 104 is the `appsecret_proof` error is therefore
**not supported by any page read**. Recorded as an ambiguity in §6.

### 3.3 Channel-specific rows the Graph layer inherits — the ones that change Lynomia's error UX

Only rows whose safe-to-show audience is *not* "operator" are listed; the full Messenger and Instagram tables are
large and belong to agents 022/024. Every row below is S8 (Messenger/IG-via-Messenger) or S9 (Instagram Platform).

| Code | Subcode | Meta's message | Audience | Why it matters |
|---|---|---|---|---|
| 10 | 2534022 | "This message is sent outside of allowed window." | **agent** | The 24-hour window. The agent must learn this at compose time, not after a failed send. |
| 10 | 2018278 | "This message is sent outside of allowed window." (newer policy) | agent | S8 lists no handling. Two subcodes for one user-visible situation — Lynomia should map both to one article. |
| 10 | 1893015 | "(#10) This user has currently stopped notification messages for this topic" | agent | Opt-out. Stop sending; this is a permanent state per topic. |
| 10 | 1893063 | "You are temporarily restricted from sending messages." | **admin** | Page-level messaging-policy restriction. |
| 10 | 2534077 | "Cannot verify the connection between the IG account, the logged in user and the page." | **admin** | Page↔IG link broken or 2FA not enabled — a setup error that masquerades as a send failure. |
| 100 | 2534013 | "The page is not linked to an Instagram account" | admin | Same family as above. |
| 100 | 2534014 | "No matching Instagram user" | operator | An IG User ID was used where an Instagram-scoped ID is required — a Lynomia bug, not a customer problem. |
| 100 | 2018008 | "Failed to fetch the file from the url." | agent | Attachment URL must be valid, correctly certificated, within size, and fast enough. |
| 100 | 2018047 / 2018109 / 2018294 | upload failure / size exceeded / video timed out or corrupted | agent | Directly actionable at compose time. Video must be fetchable within 75 seconds. |
| 100 | 2534029 | "The business has been blocked from sending messages via the IG Messaging API" | **admin** | Policy violation; outstanding violations must be resolved. |
| 200 | 2534041 | "The account owner has disabled access to instagram direct messages." | admin | The IG account owner revoked app access — looks like a token problem, is not. |
| 200 | 1545041 | "Message Not Sent: This person isn't available right now." | agent | Transient recipient state. |
| 551 | — | "User Block Error: This person isn't receiving messages from you right now." | agent | The customer blocked or restricted the business. There is no customer to show anything to. |
| 2 | — | "An unexpected error has occurred. Please retry your request later." | operator | S8 notes it **can also mean the customer blocked the business** — so code 2 is not purely transient on Messenger. Important: a blind retry loop on code 2 will never succeed in that case. |
| 4 | 2018354 | minimum delay required between two notifications | agent/operator | Marketing frequency; "Not flagged for abuse." Track recipients and exclude them from the next broadcast. |
| 613 | 2018338 | "Warning! You are engaging in behavior that may be considered bothersome or abusive…" | **admin** | Reduce the rate of tagged messages or risk restrictions. |
| 9 | 2207042 | "You reached maximum number of posts that is allowed to be published by Content Publishing API." | admin | Instagram daily publishing cap; retry next day. |
| 4 | 2207051 | "We restrict certain activity to protect our community. Tell us if you think we made a mistake." | admin | Instagram treated the activity as spam; contestable. |
| 25 | 2207050 | "The Instagram account is restricted." | admin | Account inactive, checkpointed or restricted — the person must resolve it in the Instagram app. |
| 24 | 2207008 | "The media builder with creation id = … does not exist or has been expired." | operator | S9 gives the only concrete retry schedule found anywhere: retry 1–2 times after 30s–2min, then create a new container. |

S9 also carries its own internal inconsistencies, which Lynomia must not reproduce as fact: the intro says code
`3600` while the table and sample JSON use `36000`; subcode `2207001` has no user message; and the recommendation
printed against `2207005` (image format) talks about permissions and containers and does not match its own message.

---

## 4. Limits and numbers

Only numbers a source states. All from S2 unless noted.

### 4.1 Which limit applies

S2 states the precedence rule plainly: **if both a Platform limit and a Business Use Case (BUC) limit could apply,
the BUC limit applies.** Platform limits cover Graph API requests generally; BUC limits cover Marketing API,
Instagram Platform and Pages API requests made with system-user or Page tokens — which is exactly how a Lynomia
Facebook/Instagram inbox calls Meta.

### 4.2 Stated formulas and windows relevant to Lynomia

| Category | Stated limit | Window |
|---|---|---|
| Platform, app level | 200 × number of users | rolling 1 hour |
| Platform, user level | **not disclosed**; calls from multiple apps count against the same user | — |
| Messenger API (BUC) | 200 × engaged users | rolling 24 hours |
| Pages (Page or system-user token) | 4,800 × engaged users | rolling 24 hours |
| Instagram Platform | 4,800 × impressions, per app and app-user pair | rolling 24 hours |
| WhatsApp Business Management API, default | 200 requests/hour per app per WABA | 1 hour |
| WhatsApp Business Management API, active WABA with a registered number | 5,000 requests/hour per app per WABA | 1 hour |
| LeadGen | 4,800 × leads generated in the past 90 days, per Page | rolling 24 hours |
| Catalog Batch | 8 + 8 × log2(DA impressions + PDP visits), per catalog ID | rolling 1 minute |
| Catalog Management | 20,000 + 20,000 × log2(DA impressions + PDP visits), per catalog ID | rolling 1 hour |

Per-second throughput limits (not formula-based):

| Surface | Stated limit |
|---|---|
| Messenger Send API | 300/sec text, links, reactions, stickers; 10/sec audio or video. Also rate-limited when too many messages go to one thread. |
| Messenger Conversations API | 2/sec per Page |
| Messenger Private Replies | 750/hour per Page |
| Instagram Send API | 100/sec text/links/reactions/stickers on Instagram Messaging; 300/sec for the same on Messenger API for Instagram; 10/sec audio or video |
| Instagram Conversations API | 2/sec per IG account |
| Instagram Private Replies | 100/sec for Live comments; 750/hour for post and reel comments |

Also stated: multiple IDs in one request count as **one call per ID** (`ids=4,5,6` counts as 3 calls), and S2 still
recommends batching for performance. Instagram caption limits appear on S9: 2,200 characters, 30 hashtags, 20 @ tags;
image maximum 8 MiB; aspect ratio between 4:5 and 1.91:1; carousels 2–10 items.

### 4.3 The headers, and how to read them

**`X-App-Usage`** (Platform; a JSON string; S2 says it is included once enough calls have been made):

| Field | Meaning |
|---|---|
| `call_count` | percentage of calls made by the app over a rolling one-hour period |
| `total_time` | percentage of total time allotted for query processing |
| `total_cputime` | percentage of CPU time allotted for query processing |

**`X-Business-Use-Case-Usage`** (BUC; a JSON string; **up to 32 objects per call**). The top level is keyed by
business object ID, and each value is an array of usage objects:

| Field | Meaning |
|---|---|
| `type` | one of `ads_insights`, `ads_management`, `custom_audience`, `instagram`, `leadgen`, `messenger`, `pages` |
| `call_count` | percentage of allowed calls made in a rolling one-hour period |
| `total_cputime` | percentage of CPU time allotted |
| `total_time` | percentage of total time allotted |
| `estimated_time_to_regain_access` | **minutes** until calls are no longer throttled |
| `ads_api_access_tier` | present only for `ads_insights` and `ads_management` |
| `business-id` | listed in S2's field table as the ID of the business tied to the token, but absent from S2's own sample JSON |

**`X-Ad-Account-Usage`** (S2 scopes this to "v3.3 and older" Ads API): `acc_id_util_pct`,
`reset_time_duration` (**seconds** until the score resets to 0), `ads_api_access_tier`
(`development_access` default, or `standard_access`).

**Reading them.** Every value is a percentage of its allowance, so 100 means the allowance is consumed. S2 states
that throttling *may* occur when `total_time` or `total_cputime` reaches 100; it **does not explicitly state** that
`call_count` reaching 100 blocks calls, only implying that requests fail once the limit is reached. The only retry
clocks Meta publishes are `estimated_time_to_regain_access` (minutes, BUC) and `reset_time_duration` (seconds,
ad-account). There is **no documented exponential-backoff schedule** anywhere in S2; it says only that calls
succeed again once "enough time has passed for the call count to drop below the limit."

The one normative behavioural instruction: **stop calling once the limit is reached, because continued calls extend
the wait.** A naive retry loop in Lynomia does not just fail — it lengthens the outage.

S2 also documents a query-level **stability throttle** with its own fields: `throttled` (`True`/`False`),
`backend_qps` and `complexity_score`, each as `actual_score` against `limit`, plus `more_info` guidance to simplify
or split queries. S2's sample shows `backend_qps` 8 against a limit of 5 and `complexity_score` 0.1 against 0.01.

### 4.4 Throttling error codes

| Code | Subcode | Scope | Source |
|---|---|---|---|
| 4 | — | app has reached its rate limit (Platform) | S2, S1 |
| 17 | — | user has reached their rate limit (Platform) | S2, S1 |
| 17 | 2446079 | Ads API v3.3 or older token at its limit; also BUC for v3.3-and-older Ads API excluding Ads Insights | S2 |
| 32 | — | User or app token on a Pages API request at its limit; also BUC for Page calls with a User token | S2 |
| 613 | — | custom rate limit reached; check the specific API's docs | S2 |
| 613 | 1996 | inconsistent request volume detected | S2 |
| 80000 | 2446079 | Ads Insights (BUC) | S2 |
| 80001 | — | **Page calls with a Page or System User access token (BUC)** | S2 |
| 80002 | — | **Instagram (BUC)** | S2 |
| 80003 | 2446079 | Custom Audience (BUC) | S2 |
| 80004 | 2446079 | Ads Management (BUC) | S2 |
| 80005 | — | LeadGen (BUC) | S2 |
| 80006 | — | **Messenger (BUC)** | S2 |
| 80008 | — | **WhatsApp Business Management API (BUC)** | S2 |
| 80009 | — | Catalog Management (BUC) | S2 |
| 80014 | — | Catalog Batch (BUC) | S2 |
| 80007 | — | the WhatsApp Business Account has reached its rate limit; check WABA rate limits, retry later or reduce volume | S7 |
| 130429 | — | "Rate limit hit" — Cloud API message **throughput** reached; review throughput limits, retry later or send less often | S7 |
| 131056 | — | too many messages from the sender to the same recipient in a short period; wait and retry **for that recipient only** — other recipients still work | S7 |
| 133016 | — | registration/deregistration failed after too many attempts for this number in a short period; wait until unblocked | S7 |
| 131048 | — | sending from this number is restricted, possibly because earlier messages were blocked or flagged as spam; check quality status in WhatsApp Manager | S7 |
| 613 | 2534040 | "Calls to this api have exceeded the rate limit." (Messenger/IG) | S8 |
| 2018144 | — | Instant Game message limit, 5 per user within 10 days of last play | S8 |

The four codes Lynomia will actually see — **80001** (Pages), **80002** (Instagram), **80006** (Messenger),
**80008** (WhatsApp Business Management) — are bolded above. Note that 80007/130429/131056 are *WhatsApp
message-sending* limits and sit above, not inside, the BUC layer; `X-Business-Use-Case-Usage` will not explain them.

**Safe-to-show verdict for every rate-limit code: operator, with one derived agent-safe rendering.** None of these
strings is customer copy. The only defensible customer-facing rendering is a generic "try again shortly", and only
when the send was synchronous. 131056 is the single rate-limit code with a *scoped* remedy an agent can act on
(switch to a different recipient), and 131048 / 133016 / 80007 are admin-facing because they describe an account
state, not a transient burst.

---

## 5. Version and deprecation notes

### 5.1 Naming and lifecycle

Versions are `v<major>.<minor>`, e.g. `v26.0` (S3). S3 states the lifecycle in two sentences that must be read
together:

- each version is "guaranteed to operate for at least two years";
- "A version will no longer be usable two years after the date that the subsequent version is released."

So the clock starts at the *successor's* release, not at the version's own release. S3's worked example: v2.3 was
released 25 March 2015, v2.4 on 7 August 2015, so v2.3 expired 7 August 2017.

### 5.2 Current version as of the date checked, and what is already retired

S3 and S4 both state the latest version is **v26.0**. S4 and S5 give its release date as **29 July 2026**, with
"Available Until" **TBD**.

| Version | Introduced | Available until (S4) | State as of 2026-10-13 |
|---|---|---|---|
| v26.0 | 2026-07-29 | TBD | **current** |
| v25.0 | 2026-02-18 | 2028-07-29 | usable |
| v24.0 | 2025-10-08 | 2028-02-18 | usable |
| v23.0 | 2025-05-29 | 2027-10-08 | usable |
| v22.0 | 2025-01-21 | 2027-05-20 | usable |
| v21.0 | 2024-10-02 | 2027-01-21 | usable — **oldest usable version** |
| v20.0 | 2024-05-21 | 2026-09-24 | **retired 19 days ago** |
| v19.0 | 2024-01-23 | 2026-05-21 | retired |
| v18.0 | 2023-09-12 | 2026-01-26 | retired |
| v17.0 and older | — | ≤2025-09-12 | retired |

S5 corroborates the two most recent retirements directly: "Graph API v20.0 is removed September 24, 2026. Graph API
v21.0 is removed January 21, 2027," and adds that Facebook Platform SDK v20.0 is deprecated in September 2026 and
v21.0 in January 2027. **Three Graph versions have retired inside the last twelve months**, and the next retirement
(v21.0) is 2027-01-21 — roughly 100 days after the date checked. Any Lynomia code or article that pins a version at
or below v21.0 is on a short clock.

### 5.3 What a call to a retired version actually returns — and why this is the most dangerous finding here

S3 is explicit and counter-intuitive: a call to a no-longer-usable version is **not rejected**. "Any calls made to
it will be defaulted to the next oldest, usable version." S3 gives no error code and no warning header.

The consequence for Lynomia is that **version retirement is silent**. A request pinned to `v20.0` today does not
fail; it is served by `v21.0` semantics, and the first symptom is a behavioural change — a field that stopped being
returned, a parameter that is now ignored, a payload shape that moved — not an error anyone can grep for. S5's
v26.0 notes show exactly what that silent reinterpretation can do: requests carrying `date_format` now return an
error, root requests using `GET /?ids=…` now return an error, `pretty` and `debug` are ignored, `If-None-Match` is
ignored and `304 Not Modified` responses are removed. Several of those are listed as applying to **all versions**,
including unversioned calls.

There is one documented exception to the silence: S5 says Page requests for the deprecated New Pages Experience
fields "return a version error." Meta does not publish that error's code or subcode. Recorded as an ambiguity.

### 5.4 Unversioned calls and the back-version rule

- A call with no version uses the version configured in the App Dashboard, Settings > Advanced > "Upgrade API
  Version" card. S3 recommends always specifying the version explicitly. Unversioned calls are not supported for
  the Facebook JavaScript SDK. (S3)
- An app may call an older version **only if it has already made calls to that version**. S3's example: an app
  whose first call was v2.2 cannot use v2.0 or v2.1. Rolling *back* is therefore not always available. (S3)
- S11 describes the App Dashboard controls: "Upgrading Developers and Admins" moves only the app's developers and
  admins to the next version, which allows testing against real users at small scale; "Upgrading All Calls" moves
  everything, and upgrading early preserves the option to revert if bugs appear.

### 5.5 How deprecations are announced

S4 distinguishes two mechanisms:

- **Versioned changes** ship with each new API version. They typically apply to the newest version immediately and
  reach older versions later; each release's changelog states which changes apply to the current release and which
  apply to other versions.
- **Out-of-cycle changes** happen outside the release schedule, usually apply to **all** versions immediately, and
  are introduced infrequently.

S5 shows the recurring shapes in practice: "v26.0+ from July 29, 2026, and on all remaining supported versions from
October 27, 2026" (an approximately 90-day tail), "deprecated fields remain available on v25.0 and earlier for two
years after launch", and a Page-fields change that "will apply to all versions approximately 90 days after the
v26.0 launch; date to be confirmed."

Two gaps in the announcement story. First, S3 warns that Meta may change any API "in a short period of time" for
security or privacy reasons, saying such changes are infrequent but do occur — i.e. the two-year guarantee has a
stated escape hatch. Second, **S11 documents no notification channel at all**: it names only the changelog and the
API Upgrade Tool, and does not mention developer alerts or emails. The Upgrade Tool has limitations of its own —
caller must be an app admin or developer, it returns no data if the app made too few calls from the source version,
and its call volumes are sampled and aggregated over the prior week, so they are estimates. **There is no documented
push notification of an impending breaking change.** Watching the changelog is the only documented mechanism.

S4 additionally notes the Marketing API auto-upgrades versions on 2026-07-29.

### 5.6 WhatsApp's version relationship

S12 states that Embedded Signup Version 3 (29 May 2025) introduced versioning that "will align with Graph API's
release cadence," and several Cloud API entries reference Graph versions. But the latest version S12 itself
references is **24.0** (changes dated 8 October 2025 applying to requests for 24.0 and newer), while Graph is at
v26.0 — the WhatsApp changelog lags. S12 sets out **no deprecation schedule for Cloud API versions and says nothing
about how calls to retired versions behave**; the S3 "defaults to next oldest usable" rule is a Graph API statement
that S12 does not restate for WhatsApp.

The version-dependent error fact Lynomia most needs: S12's 2 February 2023 entry states that error subcodes "will
no longer be included in v16.0+ error responses", describing them as rarely used and advising `code` and `details`
instead. S7 restates this as `error_subcode` being deprecated and not returned in v16.0+. **On any supported
version, a WhatsApp Cloud API error has no subcode.**

---

## 6. Ambiguities and gaps

1. **Code 104 is effectively undocumented.** S10 gives the title "Incorrect signature" and nothing else. S13 — the
   page that documents `appsecret_proof` and the "Require App Secret" setting — states only that calls lacking the
   proof "will fail" and names no code, subcode or message. The widespread belief that 104 is the `appsecret_proof`
   error **cannot be sourced from the pages read.** Lynomia must not publish that link as fact.
2. **A stand-alone common error code 33 does not exist on any page read.** What exists is code `100` with
   `error_subcode 33` (S8, S10), "Unsupported get request. Object with ID * does not exist…". The brief listed 33 as
   a common code; that appears to be a mis-transcription of `100/33` and the orchestrator should correct it.
3. **`is_transient` is documented only by example.** It appears in S9's and S10's sample JSON (value `false`) and is
   defined on neither page, nor on S1. No retry semantics may be attached to it.
4. **`call_count` at 100** — S2 never states that `call_count` reaching 100 blocks calls, only that throttling may
   occur when `total_time` or `total_cputime` reaches 100. The blocking behaviour of `call_count` is inferred, not
   stated.
5. **S2's own sample is inconsistent** — its `X-Business-Use-Case-Usage` example shows a duplicate object key
   (`10153848260347724`), and `business-id` appears in the field table but not in the sample.
6. **No documented error for calling a retired version.** S3 says the call silently falls back; S5 mentions a
   "version error" for deprecated Page fields without publishing its code. Lynomia cannot detect retirement from an
   error code.
7. **No documented backoff schedule.** S2 publishes `estimated_time_to_regain_access` and `reset_time_duration` but
   no retry curve. The only concrete retry interval found in any source is Instagram's `24/2207008`: retry 1–2 times
   after 30s–2min (S9).
8. **190↔subcode pairing is only partly confirmed.** S6 confirms 458, 460, 463 arrive with code 190. S1 lists 459,
   464, 467, 492 in an authentication-subcode table without binding them to 190. Subcode 490 — which Lynomia support
   folklore may reference — appears on **no** page read. Do not publish it.
9. **No normative guidance on *how* to present `error_user_msg`.** S1 licenses displaying it; S9 shows it in a
   sample and explicitly "doesn't define how these fields should be shown to users." There is no Meta rule on
   truncation, styling, or what to do when the field is absent — those are Lynomia product decisions.
10. **Locale of `error_user_msg` / `error_user_title` follows the request, not the reader** (S1). Meta documents the
    behaviour but offers no mechanism for requesting a different locale per reader. For a bilingual EN/AR product
    this is an unresolved design problem, not a bug to fix downstream.
11. **Meta's own URL for the token-error page has moved** (O1): the `/docs/facebook-login/guides/access-tokens/…`
    path 404s; the live path omits `/guides/`. Any Lynomia article or code comment citing the old path is dead.
12. **Subcode reliability is per product, not per platform.** Subcodes are gone for WhatsApp Cloud API v16.0+ (S7,
    S12) but central to Messenger (S8) and Instagram (S9), where many user-visible distinctions exist *only* at the
    subcode level (10/2534022 vs 10/2018278; 200/1545041 vs 551/1545041). A single cross-channel error model keyed
    on `code` alone will lose information on Facebook and Instagram inboxes.

---

## 7. What Lynomia users would ask

**Admins, on the error-190 surface.** "Why did my connection break when I changed nothing?" — because Meta does not
notify you and tokens can be invalidated early by security events (S6), so the first signal is a failed send. "Which
permission did I lose?" — Meta publishes no error that names a revoked permission (S6 documents no case for
permission or app-level changes), and on WhatsApp the subcode that would narrow it is not even returned (S7, S12).
"Why does it say the session is invalid when my password is fine?" — subcode 492 is a *Page role* problem, not a
credential problem (S1), and it is the one diagnosis in the family an admin can actually act on — but only on a
Facebook/Instagram inbox, where subcodes still arrive.

**Admins, on rate limits.** "We are not sending many messages, why are we throttled?" — the app-level Platform limit
is 200 × users per rolling hour and is shared across everything the app does (S2); and for Pages/Instagram/Messenger
the BUC limit supersedes it (S2). "How long until it clears?" — `estimated_time_to_regain_access` in minutes, or
`reset_time_duration` in seconds, and nothing else (S2). "Should we retry harder?" — no: continued calls extend the
wait (S2). "The WhatsApp number is blocked but the headers look fine" — 80007, 130429, 131048 and 133016 are not
BUC-layer limits and do not appear in `X-Business-Use-Case-Usage` (S7 vs S2).

**Agents.** "Why can't I reply to this person?" — three unrelated causes with three different remedies and no shared
code: outside the 24-hour window (10/2534022 or 10/2018278), the person blocked the business (551, and sometimes a
bare code 2 on Messenger), or the IG account owner revoked app access (200/2534041). S8's note that code 2 can mean
"the customer blocked the business" is the trap: it reads as transient and is not. "Why did my attachment fail?" —
100/2018008, 100/2018047, 100/2018109 or 100/2018294, each with a different fix.

**Developers and Lynomia platform support.** "Nothing changed on our side and the payload shape moved" — a pinned
retired version is silently served by the next oldest usable version (S3), and v20.0 retired on 2026-09-24 (S4, S5).
"Which version should we be on?" — v26.0 is current; v21.0 is the oldest usable version and retires 2027-01-21 (S4,
S5). "Will Meta tell us before a breaking change?" — no push channel is documented; the changelog and the API
Upgrade Tool are the only documented mechanisms (S4, S11), and out-of-cycle changes can apply to all versions
immediately (S4). "Why is the error text different this week?" — description strings may change without notice; key
on `code` (S10, S7). "Where is the trace ID?" — `fbtrace_id`, and it "will expire shortly" (S1), so it must be
captured at the moment of failure or it is lost.

**The question behind all of them.** Meta's error layer gives a person-facing sentence (`error_user_msg`) only
sometimes, in the locale of the *request*, and gives a stable machine key (`code`) always. Lynomia's layered error
experience has to invert that asymmetry: own the prose, key it on the code, and keep every other field behind an
operator boundary.
