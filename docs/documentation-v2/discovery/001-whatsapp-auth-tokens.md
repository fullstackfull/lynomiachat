---
agent: 001
scope: WhatsApp Cloud API authentication — token types, lifetimes, expiry, revocation, debugging, and the expired/revoked/unpermitted distinction
confidence: high
sources_normative: 13
sources_observational: 0
---

# WhatsApp Cloud API authentication: the token model

This report establishes the vocabulary and the failure semantics that agents 002 (system users, permanent
tokens, rotation), 003 (permissions and scopes) and 004 (roles, asset ownership, revocation) build on. It is
deliberately strict about terminology, because Meta uses three different names for the same artifact across
three of its own pages and that inconsistency is the single largest source of confusion in this area.

All external research was read-only: pages were fetched and read. No Graph API endpoint was called, no
credential was used, nothing was authenticated, no form was submitted.

## 1. Source register

Every claim below references a row ID from this table. Date checked for all rows: **2026-10-13**.

| Row | Source URL | Page title | Product | API / version context | Normative? |
|---|---|---|---|---|---|
| S1 | `https://developers.facebook.com/docs/facebook-login/guides/access-tokens` | Access Tokens for Meta Technologies (`/docs/` path) | Graph API / Facebook Login | No version stated; examples use unversioned `graph.facebook.com` | normative |
| S2 | `https://developers.facebook.com/documentation/facebook-login/guides/access-tokens` | Access Tokens for Meta Technologies (`/documentation/` path) | Graph API / Facebook Login | No version stated | normative |
| S3 | `https://developers.facebook.com/docs/whatsapp/cloud-api/get-started` | Get Started | WhatsApp Cloud API | `v23.0` in the Step 6 send example | normative |
| S4 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/access-tokens/` | Access Tokens Guide | WhatsApp Business Platform | `v25.0` in the `/message_templates` example | normative |
| S5 | `https://developers.facebook.com/docs/facebook-login/guides/access-tokens/get-long-lived` | Generate Long-Lived User and Page Access Tokens | Facebook Login / Graph API | No version stated | normative |
| S6 | `https://developers.facebook.com/docs/graph-api/reference/debug_token/` | Debug Token | Graph API | `v26.0` in the request path | normative |
| S7 | `https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes` | Error Codes | WhatsApp Cloud API | States subcode behaviour for `v16.0+` | normative |
| S8 | `https://developers.facebook.com/docs/graph-api/guides/error-handling/` | Error Handling | Graph API | No version stated | normative |
| S9 | `https://developers.facebook.com/documentation/facebook-login/facebook-login-for-business` | Facebook Login for Business | Facebook Login for Business | No version stated | normative |
| S10 | `https://developers.facebook.com/docs/business-management-apis/system-users/install-apps-and-generate-tokens/` | Install Apps, Generate, Refresh, and Revoke Tokens | Business Management API | Placeholders only (`API-VERSION`, `{graph-api-version}`) | normative |
| S11 | `https://developers.facebook.com/docs/graph-api/changelog` | Graph API Changelog | Graph API | v13.0 – v26.0 | normative |
| S12 | `https://developers.facebook.com/docs/whatsapp/business-platform/changelog` | Changelog | WhatsApp Business Platform | Entries cite v16.0, v17, v23.0, v24.0 | normative (changelog) |
| S13 | `https://developers.facebook.com/docs/whatsapp/cloud-api/reference/messages` | Messages | WhatsApp Cloud API | `{Version}` placeholder, no version named | normative |

Two further URLs are recorded as negative evidence, not as sources:

| Row | URL | Result on 2026-10-13 |
|---|---|---|
| D1 | `https://developers.facebook.com/docs/facebook-login/guides/access-tokens/debugging` | **HTTP 404** |
| D2 | `https://developers.facebook.com/docs/facebook-login/guides/access-tokens/expiration-and-extension` | **HTTP 404** |

D1 and D2 matter: historically these were the pages that enumerated *why* a token becomes invalid. Neither
resolves today. See §6, gap 9 — the authoritative invalidation-conditions list could not be retrieved from any
page consulted, and this report therefore does not state it.

One page appeared in search results and was deliberately **not** consulted:
`https://developers.facebook.com/blog/post/2022/12/05/auth-tokens/` ("Using Authorization Tokens for the
WhatsApp Business Platform"). It is a Meta blog post from 2022. Under §6.2 it would be observational at best
and it is four years stale. No claim here rests on it.

Note on path migration: Meta is serving the same access-token guide at both `/docs/...` (S1) and
`/documentation/...` (S2), and the authoritative WhatsApp token page (S4) exists **only** under
`/documentation/business-messaging/whatsapp/...`. Most `/docs/` paths still resolve (S3, S5, S6, S7, S8, S10,
S11, S12, S13 all did), but D1 and D2 did not. Any Lynomia article that deep-links a Meta `/docs/` auth URL is
at risk and should be re-checked before Phase 5.

## 2. The rules

### 2.1 Which tokens exist, and which exist *for WhatsApp*

These are two different questions and conflating them is the usual error.

The general Graph API token catalogue (S1, S2) names five types: **app access token**, **client token**,
**page access token**, **system user access token**, **user access token**. S1 does not define a
"business-scoped token" type at all; the nearest thing it names is the system user token, which is tied to a
business portfolio.

The WhatsApp Business Platform's own Access Tokens Guide (S4) names exactly **three**, and explicitly covers
nothing else:

| Meta's name | Meta's short name | Who it is for (S4) |
|---|---|---|
| System user access token | "system token" | A direct developer — you or your business accessing only your own data |
| Business Integration System User access token | "business token", BISU | Tech Providers; and Solution Partners for everything except line-of-credit sharing |
| User access token | — | All app developers; typically only the first test message from the App Dashboard |

S4 does **not** mention app access tokens or granular tokens. Per S4, a Solution Partner uses *system user
tokens* specifically to share its line of credit with newly onboarded customers, and BISU tokens for
everything else — so the two are not alternatives, they are both required in that topology.

The term **"business-scoped token"** in the brief maps to Meta's **Business Integration System User access
token**. S9 confirms the scoping: a BISU token is tied to the *client business's business portfolio*, not to
one user, and its access is "explicitly delegated by the client business during authorization" — limited to
the assets the client designated during login. By contrast a user access token's access is "inherited from the
app user's current account access", tied to that person's personal Facebook account.

S9 uses "System-user access token" in its setup steps and "Business System User Access Token" in its
troubleshooting section without defining a difference. They appear to be the same artifact, but **S9 does not
say so outright**. Agents 002 and 004 must not treat that as settled.

### 2.2 Lifetimes — what Meta actually states

| Token | Stated lifetime | Source |
|---|---|---|
| User access token, short-lived (web login) | "typically last about one to two hours" | S1, S2 |
| User access token, for WhatsApp | "expire quickly"; regenerate "every few hours" — no exact figure | S4 |
| App Dashboard temporary token (Cloud API Get Started) | "expires quickly and is not suitable for development purposes" — **duration not stated** | S3 |
| User access token, long-lived | "generally lasts about 60 days"; sample `expires_in` of 5183944 seconds | S5 |
| User access token, native mobile SDK | "good for about 60 days", refreshed once per day when the user makes a request | S5 |
| Page access token, long-lived | "do not have an expiration date and only expire or are invalidated under certain conditions" | S5 |
| System user access token | **S4 states no duration.** You choose an "expiration preference" at generation | S4 |
| System user token, non-expiring option | Lifetime "Never expires"; need to refresh: "No" | S10 |
| System user token, expiring option ("suggested expiring") | "Valid for 60 days"; need to refresh: "Yes"; Meta labels it **"Recommended"** | S10 |
| BISU access token | "Defaults to never expire for the common offline server-to-server communication" | S9 |
| BISU with optional expiry | 60 days, via `set_token_expires_in_60_days=true` | S9, S10 |

The 5183944-second sample in S5 is 60 days minus 56 seconds. It is a sample value in a documented response,
not a guarantee.

Two caveats are themselves normative and should be reproduced in any Lynomia article that quotes a duration.
S1 and S2 state: do not "depend on these lifetimes remaining the same", because tokens "may change without
warning or expire early". And non-expiring tokens — both Marketing API Standard access tokens and tokens for
System Users in Business Manager — "do not expire based on time" but remain "still subject to invalidation for
other reasons" (S1, S2). **"Never expires" is not "never stops working."**

### 2.3 The word "permanent"

S3, the Cloud API Get Started page, titles its Step 5 "Create a system user and generate a permanent access
token" and tells you to create a permanent token "for use across the platform". It states no expiry for it.

S4, the WhatsApp Access Tokens Guide, never uses the word "permanent". It calls the same artifact
"long-lived" and says you pick an "expiration preference".

S10 uses neither word: it says "Never expires" for one option and "Valid for 60 days" for the other.

So Meta ships three vocabularies for one artifact and defines "permanent" nowhere. Lynomia documentation
should use **"system user access token, non-expiring"** and **"system user access token, 60-day"**, and should
say explicitly that Meta's own setup guide calls the first one "permanent". Agents 002 and 039 must not invent
a fourth term.

### 2.4 How each token is generated

**System user access token** (S3, S4, S10). Via the UI: Business settings → System Users; add a system user
with the **Admin** or **Employee** role; assign your app with the **"Manage app"** permission and confirm
**"Full control"**; click **Generate token**; select the permissions. S3 and S4 both name the same three
permissions for WhatsApp: `business_management`, `whatsapp_business_management`,
`whatsapp_business_messaging`. (Scope detail belongs to agent 003.)

Via the API (S10): the app must first be installed — `POST SYSTEM-USER-ID/applications` with `business_app`
and `access_token` — then the token is generated at `/SYSTEM-USER-ID/access_tokens`. S10 states three
prerequisites verbatim: "A system user or an admin system user must install the app that will be used for
generating an access token"; the system user and the app must belong to the same Business Manager; and "Only
apps with Ads Management API standard access and above can be installed." That last sentence is a problem for
a WhatsApp-only app and is flagged as gap 6 in §6.

**BISU access token** (S4, S9). Implement Embedded Signup configured with Facebook Login for Businesses, then
exchange the code returned when the customer completes the flow. S9 states the OAuth grant is **Authorization
Code only** — no implicit grant. The onboarding flow itself is agent 013's scope.

**User access token** (S4). Three routes: App Dashboard → WhatsApp → API setup (which "generates a new token
on each visit", scoped to your developer user); the Graph API Explorer; or Facebook Login.

**Short-lived → long-lived user token** (S5). `GET oauth/access_token` with `grant_type=fb_exchange_token`,
the app ID, the app secret and the existing token. Two normative constraints: "You can not use an expired
token to request a long-lived token", and the call must be made from your server, not a client, because the
app secret is included.

### 2.5 Refresh, rotation and revocation

All from S10 unless noted.

An expiring system user token is "valid for 60 days from generated or refreshed date". Refresh is
`GET oauth/access_token` with `grant_type=fb_exchange_token`, `client_id`, `client_secret`,
`set_token_expires_in_60_days=true` and `fb_exchange_token`. If you do not: "Failing to do so would result in
forfeiting the access token", and you must obtain a new one to regain API access.

Meta's stated rotation order is: refresh, deploy the new token, then revoke the old one. During the overlap,
"The old access token can still work until it expires (i.e., creation date + 60)."

Revocation is `GET oauth/revoke` with `client_id`, `client_secret`, `revoke_token` and `access_token`. The
`client_id` must match the actual app; the app must not be throttled, disabled or deleted; and the
`client_id`, the installed app of each token and the `client_secret` must all be the same. Effect: "The
invalidation takes place immediately, and the token cannot be used again after the revocation." S10 says
nothing about whether other tokens are affected.

Revocation by the other party, from S9 — this is the one an agency hand-over breaks:

| Token | Who can invalidate it | Where |
|---|---|---|
| BISU | the client business | Business Manager → Settings → Business Settings → Integrations → **Connected apps**, remove the app |
| User access token | the person | Facebook settings → Security and login → **Business Integrations**, remove the app |

S10 gives no Business Manager UI route for revoking an ordinary system user token — only the `oauth/revoke`
endpoint.

### 2.6 What a token can and cannot do against WhatsApp endpoints

Authentication is the easy half. Authorisation is where live installations break, and S4 is explicit about the
mechanism: "Most endpoints check whether the token's user has access to the resource. If not, the request
fails with error code 200 (not HTTP 200)." Many endpoints additionally require **Partial** or **Full business
asset access** to the WABA, and Partial access can be narrowed to specific assets or actions — S4's example is
read-only template access. Business asset access is granted in Meta Business Suite → Accounts → WhatsApp
Accounts → WhatsApp Account Access → **+Add people**.

The role on the system user determines the default (S4): an **Admin** system user has full access to all WABAs
and assets by default, overridable per WABA with partial access; an **Employee** system user has **no access**
until Partial or Full business asset access is granted per WABA. A correctly scoped token held by an Employee
system user with no WABA grant authenticates fine and fails every call.

S12 corroborates and dates this: 12 September 2023 added new WABA Access levels, with GET requests returning
error code `200` when the token's user lacks appropriate access; 6 September 2024 added a "Messages" business
asset access level for more granular WABA access control.

S4 does not enumerate per-endpoint capability — it gives one worked example (reading message templates).
S13, the `/messages` reference itself, names **no required permission at all**; it states only that the
`Authorization` header is a required "Bearer token for API authentication" which "should be a valid access
token obtained through the appropriate OAuth flow or system user token", and that "All endpoints require:
bearerAuth". The permission requirement for sending comes from S3 and S4, not from the endpoint reference.

### 2.7 Transport and storage

The header is `Authorization: Bearer <token>` (S4, S13). S4 adds a storage rule that is directly relevant to
Lynomia's schema: tokens are **opaque** — "Do not parse, decode, or assume a format" — and should be stored in
"a variable-length data type with no fixed maximum size". Any Lynomia column, log truncation or UI field that
assumes a maximum token length contradicts Meta's own instruction.

### 2.8 Token debugging

Programmatically (S6): `GET /v26.0/debug_token?input_token={input-token}`. The caller needs **either an app
access token or an app developer's user access token** for the app the `input_token` belongs to — so a support
agent holding only the customer's system user token cannot debug it without the app's own credentials. This is
a real operational constraint for a support desk.

Fields S6 documents: `app_id`, `application`, `error` (`code`, `message`, `subcode`), `expires_at` (Unix
timestamp of expiry), `data_access_expires_at` (Unix timestamp when "the app's access to the user's data
ends"), `is_valid` (boolean), `issued_at`, `metadata` (examples given: `sso`, `auth_type`, `auth_nonce`),
`profile_id` (for impersonated tokens, the Page the token covers), `scopes` (array of granted permissions),
`granular_scopes` (array of `{scope, target_ids}`; target IDs are omitted when the permission applies to all
targets), and `user_id`.

Two fields people rely on are **not** in S6: there is no documented `type` field, and S6 does not say what
`expires_at: 0` means. See §6, gap 5.

By hand, S2 links the **"Access Token Tool"** at `https://developers.facebook.com/tools/accesstoken` and
describes it as a way to see your access tokens and debugging information for each. Note the naming drift: S7
calls the same thing "the access token debugger" and recommends it as the first step for codes 3, 10, 200–299
and 131005.

### 2.9 Expired vs revoked vs lacking a permission

This is the question the brief asks and the answer is uncomfortable.

**Expired and revoked are not distinguishable from the error response.** S8 assigns codes 102, 190, 463 and
467 all to "expired, revoked, or otherwise invalid", gives the same recommended handling for all of them —
get a new access token — and provides no method for telling the cases apart. That is not an omission this
report can route around; it is the documented state of the API.

**Lacking a permission is distinguishable**, and it splits in two:

| State | How it surfaces | Source |
|---|---|---|
| No token sent, or no valid app ID | `200` — "No access token was provided." S7 says this is explicitly *different* from 190 | S7 |
| Token present but cannot be authenticated (expired **or** revoked **or** invalidated **or** blocked by a user setting) | `0`, or `190` | S7 |
| Token authenticates, but the **app** lacks the permission/scope the endpoint needs | `3`, `10`, `200`–`299`, `131005` | S7, S8 |
| Token authenticates and has the scope, but the token's **user** lacks business asset access to this WABA | `200` | S4, S12 |

Code `200` therefore carries two unrelated meanings — "you sent no token" (S7) and "your system user has no
access to this asset" (S4, S12) — and Lynomia cannot classify a 200 without additional context. This is
flagged as a contradiction for agents 005, 025 and 028.

A fourth state is neither: codes `131031` and `368` mean the WABA itself has been restricted or disabled. The
token is fine. Treating those as auth failures sends the user to regenerate a token that was never the
problem.

## 3. Error codes and failures

Verbatim where the source is verbatim. Cells read `not stated` where Meta states nothing. Nothing here is
inferred. The "end user sees" column is "nothing" for every row because all of these are request-time API
errors on the business's own call — the WhatsApp recipient is never shown anything.

| Code | Subcode | Title / details as Meta words it | What it means | What the business can do | End user sees | Source |
|---|---|---|---|---|---|---|
| 0 | not stated | "We were unable to authenticate the app user." | Usually an expired or invalidated token, or a user setting that blocks app access | "Get a new access token." | nothing | S7 |
| 3 | not stated | "Capability or permissions issue." / Graph API name: "API Method" | The app lacks a capability or permission the endpoint requires | Confirm with the access token debugger that the app has the required permissions | nothing | S7, S8 |
| 10 | not stated | "Permission is either not granted or has been removed." / Graph API name: "API Permission Denied" | Permission denied | Verify permissions in the debugger. For Flows with Endpoint, confirm the phone number used to set the business public key is allowlisted. Check the API's eligibility requirements | nothing | S7, S8 |
| 102 | varies | "API Session" | With no subcode: login status or access token expired, revoked or otherwise invalid. With a subcode: see the subcode | Get a new access token | nothing | S8 |
| 190 | not returned by Cloud API v16.0+ | "Your access token has expired." | Token expired | "Get a new access token." | nothing | S7, S8 |
| 200 | not stated | "No access token was provided." The API returns "Provide valid app ID." | S7: no token supplied — explicitly distinct from 190. S4 and S12: **also** returned when the token's user lacks access to the resource | Include a valid access token; or grant the system user Partial/Full business asset access on the WABA | nothing | S7, S4, S12 |
| 200–299 | not stated | "Permission is either not granted or has been removed." / Graph API name: "API Permission" | Permission range; values vary by permission | Verify permissions in the debugger | nothing | S7, S8 |
| 1 | — | "API Unknown" | Possibly temporary downtime | Wait and retry; if it recurs, confirm the API you are calling exists | nothing | S8 |
| 2 | — | "API Service" | Temporary downtime | Wait and retry | nothing | S8 |
| 131005 | not stated | "Permission is either not granted or has been removed." (listed under "Other errors") | Permission problem | Verify permissions with the access token debugger | nothing | S7 |
| 131031 | not stated | "The WhatsApp Business Account associated with the app has been restricted or disabled…" — also covers failed data verification such as an incorrect two-step PIN | Account-level restriction. **Not a token problem** | Review the Policy Enforcement document; the Health Status API may give more detail | nothing | S7 |
| 368 | not stated | "The WhatsApp Business Account associated with the app has been restricted or disabled for violating a platform policy." | Policy enforcement. **Not a token problem** | Review the Policy Enforcement document | nothing | S7 |
| 33 | not stated | "The business phone number has been deleted." | S7 classifies this under "Other errors", **not** authorization | Verify the phone number is correct | nothing | S7 |
| 2500 | — | not stated | **Not listed on S7 or S8.** Do not use | not stated | not stated | — |

Code `2500` was in the brief's candidate list. It appears on neither the Cloud API error-codes page (S7) nor
the Graph API error-handling page (S8). Per §6.2 this report will not invent it. If another agent needs it,
the source must be found first.

### 3.1 Graph API authentication subcodes

S8 documents these, and they matter for Lynomia's Facebook and Instagram inboxes (agents 021–024) more than
for WhatsApp — see the caveat below the table.

| Subcode | Name | Meta's recommended handling |
|---|---|---|
| 458 | App Not Installed | The user has not logged into the app. Reauthenticate the user |
| 459 | User Checkpointed | The user must log in at facebook.com or m.facebook.com to resolve an issue |
| 460 | Password Changed | On iOS 6+, if the user logged in through the OS-integrated flow, direct them to Facebook OS settings to update their password; otherwise they must log in to the app again |
| 463 | Expired | Login status or access token is expired, revoked or otherwise invalid |
| 464 | Unconfirmed User | The user must log in at facebook.com or m.facebook.com to resolve an issue |
| 467 | Invalid Access Token | Access token is expired, revoked or otherwise invalid |
| 492 | Invalid Session | The user tied to the Page access token lacks an appropriate role on the Page |

**Critical caveat.** S7 states that `error_subcode` is "deprecated and not returned in v16.0+", and S12 dates
the change to 2 February 2023 for the Cloud API: "Error subcodes are no longer included in responses." So
subcode 460 — the only code in Meta's documentation that names a password change as a cause — **cannot be
observed on a WhatsApp Cloud API response at all.** Any Lynomia article that tells a WhatsApp user to look at
a subcode is wrong. Subcode 492 is likewise Page-specific and belongs to agent 021.

S8's own error-response example is `code: 190` with `error_subcode: 460`, type `OAuthException`. On a Cloud API
response at v16.0+ that shape is not reachable. S8 is a Graph API page and does not carry the WhatsApp caveat.

### 3.2 Error object shape

S7, for the Cloud API: `message` (the code and its title combined, e.g. `(#130429) Rate limit hit.` — there is
**no separate title field**), `type` (e.g. `OAuthException`), `code` (integer — "Meta recommends building
error handling around this"), `error_data` (containing `messaging_product`, always `whatsapp`, and `details`),
`error_subcode` (deprecated, not returned in v16.0+), `fbtrace_id`. S7 does not list HTTP status codes for the
authorization errors.

S8, for the Graph API: `message`, `type`, `code`, `error_subcode`, `error_user_title`, `error_user_msg`,
`fbtrace_id`. `error_user_title` and `error_user_msg` are localised to the request locale and are the only
fields Meta intends to be shown to a person. `fbtrace_id` "will expire shortly", so a support desk that logs
it late has nothing.

Lynomia's parser must read the code out of the integer `code` field, not out of the `(#nnn)` prefix in
`message` — S7 says to build handling around `code`, and the prefix is a formatting convenience.

## 4. Limits and numbers

Only figures a source states. Nothing extrapolated.

| Number | What it measures | Source |
|---|---|---|
| "about one to two hours" | Short-lived user access token lifetime (web login) | S1, S2 |
| "every few hours" | How often a WhatsApp user access token must be regenerated | S4 |
| "about 60 days" | Long-lived user access token lifetime | S1, S2, S5 |
| 5183944 seconds | `expires_in` in S5's sample long-lived-token response (60 days less 56 seconds) | S5 |
| "about 60 days" | Native mobile SDK user token lifetime; also the idle period after which it expires | S5 |
| once per day | How often a native mobile SDK token is refreshed, when the user makes a request | S5 |
| 60 days | "Valid for 60 days" — the expiring system user token option, from generated **or refreshed** date | S10 |
| 60 days | `set_token_expires_in_60_days=true` — the optional BISU expiry | S9, S10 |
| 3 | Permissions named for a WhatsApp system user token: `business_management`, `whatsapp_business_management`, `whatsapp_business_messaging` | S3, S4 |
| creation date + 60 | How long an old token keeps working during rotation | S10 |

Deliberately absent: no duration for the App Dashboard temporary token (S3 says only "expires quickly"); no
duration for a system user token on S4; no duration for a BISU token on S4; no figure for
`data_access_expires_at`; no maximum token length (S4 forbids assuming one).

## 5. Version and deprecation notes

Graph API versions, from S11. S11 "doesn't label versions as available or deprecated. It only gives end
dates" — so the status column below is arithmetic against today's date, 2026-10-13, not a Meta label.

| Version | Introduced | Available until | Status on 2026-10-13 |
|---|---|---|---|
| v26.0 | 2026-07-29 | TBD | current |
| v25.0 | 2026-02-18 | 2028-07-29 | in window |
| v24.0 | 2025-10-08 | 2028-02-18 | in window |
| v23.0 | 2025-05-29 | 2027-10-08 | in window |
| v22.0 | 2025-01-21 | 2027-05-20 | in window |
| v21.0 | 2024-10-02 | 2027-01-21 | in window — lowest still inside its window |
| v20.0 | 2024-05-21 | 2026-09-24 | end date passed 19 days ago |
| v19.0 | 2024-01-23 | 2026-05-21 | end date passed |
| v18.0 | 2023-09-12 | 2026-01-26 | end date passed |
| v17.0 and below | — | 2025-09-12 or earlier | end date passed |

Marketing API: v26.0 (2026-07-29, TBD), v25.0 (2026-02-18, TBD), v24.0 (2025-10-08, until 2026-10-06).
Marketing API version auto-upgrade was scheduled for 2026-07-29 (S11).

Version-dependent facts relevant to authentication:

- **`error_subcode` removed from Cloud API responses at v16.0+**, dated 2023-02-02 (S7, S12). The same entry
  changed the title of error code 100 to "Invalid parameter" and changed several other titles.
- **Error code 200 for insufficient WABA access** on GET requests, Business Management API, 2023-09-12 (S12).
- **"Messages" business asset access level** added for finer WABA access control, 2024-09-06 (S12).
- **Endpoint added for retrieving business tokens** for customers onboarded through a Multi-Partner Solution,
  2024-11-13 (S12).
- **Opt-in granular business tokens at the client business level**, Embedded Signup, 2023-08-09 (S12).
- **`whatsapp_business_manage_events` permission** added 2025-08-04; S12 specifies no version for it.
- **Access verification no longer required to become a Tech Provider**, 2025-10-03 (S12) — affects agent 027.
- **`/SYSTEM-USER-ID/ads_access_token` "no longer works"**; the current endpoint is
  `/SYSTEM-USER-ID/access_tokens` (S10). No date given.
- **Embedded Signup v4 public preview**, 2026-05-12 (S12) — the most recent entry on the WhatsApp changelog.

S11 carries **no** changelog entries on access tokens, authentication, `error_subcode`, `OAuthException`,
permissions or token expiry. S12 carries **no** entries on token expiry, `OAuthException`, system users, or
API authentication changes — its "authentication template" entries concern OTP message templates, not API
auth. Agent 091 should note that: the absence of auth entries in both changelogs means a token-model change
would likely arrive undocumented in either.

Meta's own WhatsApp pages are not version-synchronised: S3 shows v23.0, S4 shows v25.0, S6 shows v26.0, and
S13 shows only a `{Version}` placeholder. A Lynomia article that pins a version by quoting a Meta example is
pinning whatever that page happened to show.

## 6. Ambiguities and gaps

Stated plainly, not resolved by guessing.

1. **Expired and revoked are indistinguishable.** S8 maps 102, 190, 463 and 467 all to "expired, revoked, or
   otherwise invalid" with identical handling and offers no way to tell them apart. Lynomia cannot build a UI
   that says "your token was revoked" from an API response alone. This is the single most consequential
   finding in this report.
2. **"Permanent" is undefined.** S3 says "permanent access token"; S4 says "long-lived" and "expiration
   preference"; S10 says "Never expires". Meta defines "permanent" nowhere. Agents 002 and 039 must pick one
   vocabulary and say which Meta page each term comes from.
3. **S4 states no lifetime for either the system user token or the BISU token.** Every duration for those
   comes from S9 and S10, which are Facebook Login for Business and Business Management API pages, not
   WhatsApp pages. The WhatsApp documentation does not confirm them.
4. **Whether an app access token works against WhatsApp endpoints is not stated.** S4 does not list app access
   tokens among the WhatsApp token types. No page consulted says an app access token can or cannot call
   `/messages`. Do not assume either way. The one documented WhatsApp-adjacent use of an app access token is
   calling `debug_token` (S6).
5. **`debug_token` has no documented `type` field, and `expires_at: 0` is undefined.** S6 lists neither. Code
   that branches on `data.type` or reads `expires_at == 0` as "never expires" is relying on undocumented
   behaviour. Record as unverified.
6. **"Only apps with Ads Management API standard access and above can be installed"** (S10) is stated as a
   prerequisite for installing an app on a system user, which is in turn a prerequisite for API-based token
   generation. S10 does not say whether a WhatsApp-only app satisfies it. If read literally, the API
   generation and refresh path is closed to WhatsApp-only apps and only the Business Settings UI path works —
   which would make the 60-day refresh story unworkable for them. **Agent 002 must arbitrate this**; it is the
   most load-bearing unresolved question in the token-rotation design.
7. **Error code 200 is overloaded** across "no access token was provided" (S7) and "the token's user lacks
   access to the resource" (S4, S12). Lynomia cannot classify a bare 200 without knowing whether a token was
   sent. Agents 005, 025 and 028 must reconcile this.
8. **The `/messages` reference names no required permission** (S13). The requirement is documented only on the
   Get Started page (S3) and the Access Tokens Guide (S4). Anyone generating documentation from the endpoint
   reference alone will omit it.
9. **The authoritative list of invalidation conditions was not retrievable.** Both D1 and D2 returned HTTP 404
   on 2026-10-13. S2 says only that lifetimes "may change without warning or expire early" and refers readers
   to a separate error-handling page. S5 says Page tokens are "invalidated under certain conditions" and does
   not list them. **This report therefore does not assert that a password change, a user de-authorisation, a
   logout, an app secret reset or a 90-day data-access expiry invalidates a token** — those are commonly
   repeated but are not supported by any page consulted today. The only password-change evidence found is
   subcode 460 (S8), and S7 and S12 establish that subcodes are not returned by the Cloud API at v16.0+.
   Lynomia must not publish an invalidation-causes list until a live normative page is found. Agent 002 or 004
   should hunt for the current URL.
10. **`data_access_expires_at` is defined but unquantified.** S6 defines it as the timestamp when "the app's
    access to the user's data ends". No page consulted states its duration, or what it means for a system user
    token where there is no consumer user. The widely cited 90 days is **unconfirmed here**.
11. **"Defaults to never expire"** for BISU (S9) is stated on a Facebook Login for Business page. S4 does not
    confirm it for WhatsApp. Treat as normative-but-unconfirmed-for-WhatsApp.
12. **Revocation blast radius is unstated.** S10 says invalidation of the revoked token is immediate, and
    "says nothing about other tokens being affected". Whether revoking one system user token affects siblings
    is unknown. Agent 004 should pursue it.
13. **S9 does not define the relationship between "system user access token" and "Business System User Access
    Token".** It uses both without distinguishing them.
14. **Naming drift in Meta's own tooling.** S2 calls it the "Access Token Tool"; S7 calls it "the access token
    debugger". Same tool at `developers.facebook.com/tools/accesstoken`. Lynomia should name it once and link
    it once.

## 7. What Lynomia users would ask

These are the support-desk questions this area generates. They are the input to the coverage matrix in Phase 2,
and most of them have no article today.

| The question, as a user would ask it | What it actually is | Where the answer comes from |
|---|---|---|
| "WhatsApp stopped sending this morning and we changed nothing." | 190 or 0 at send time | §2.2, §3 |
| "The token worked yesterday." | A 60-day expiring system user token that was never refreshed, or an App Dashboard user token that lasts hours | S10, S4 |
| "I pasted the token from the WhatsApp API setup tab and it died after lunch." | That tab issues a new short-lived **user** token on every visit. It is for one test message | S4 |
| "How do I get a token that doesn't expire?" | System user token with the non-expiring preference — but Meta labels the 60-day option "Recommended", and non-expiring tokens are still subject to invalidation | S10, S1, S2 |
| "Which permissions do I tick?" | `business_management`, `whatsapp_business_management`, `whatsapp_business_messaging` | S3, S4 |
| "The token is valid in the debugger but I still can't send / templates won't load." | Business asset access on the WABA, not the token. Error 200. Employee system users start with no access | S4, S12 |
| "Did someone revoke our token, or did it expire?" | **Meta's error does not say.** Both produce the same code and the same guidance | S8 |
| "The agency that set up our WhatsApp has left. What happens to our connection?" | Depends on whether it is a BISU token (client revokes via Connected apps) or a system user token in their Business Manager | S9, S10 |
| "Our token field is truncated in your system." | Tokens are opaque and have no documented maximum length; Lynomia must store variable-length | S4 |
| "Can you check how long our token has left?" | `debug_token` → `expires_at` — but calling it needs the **app's** access token or an app developer's user token, which a customer-facing agent may not hold | S6 |
| "We rotated our app secret / someone changed a Facebook password. Is that why WhatsApp is down?" | **Not answerable from current Meta documentation** (gap 9). Lynomia must not assert it | D1, D2 |
| "We got error 131031 — do I need a new token?" | No. The WABA is restricted. A new token will not help | S7 |
| "What's the safe way to change our token without downtime?" | Refresh, deploy, then revoke. The old token works until creation date + 60 | S10 |
| "Why does your error message show a number and Meta's page show a different title?" | The Cloud API has no separate title field; the title is embedded in `message` and several titles changed at v16.0 | S7, S12 |

A note for agents 053 and 054. The program charter records 14 WhatsApp error articles and five classified
codes. On the evidence above, the authentication and authorisation codes a live WhatsApp inbox can actually
produce are `0`, `3`, `10`, `190`, `200`, `200`–`299` and `131005`, with `131031` and `368` as the two
adjacent account-state codes that users will misread as auth failures. That is nine codes in this one area
alone, and the distinction between them is exactly what determines whether the user should regenerate a token,
grant an asset permission, or stop and contact Meta.
