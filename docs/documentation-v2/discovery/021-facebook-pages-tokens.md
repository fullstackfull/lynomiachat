---
agent: 021
scope: Facebook Pages as a messaging asset — Page access tokens, /me/accounts, Page roles and tasks, subscribed_apps, appsecret_proof, page-level failures
confidence: medium
sources_normative: 16
sources_observational: 1
---

# Agent 021 — Facebook Pages: access tokens, tasks, subscriptions, app secret proof, page-level failures

All external reading was read-only. No Graph endpoint was called, no credential was used, no form was
submitted. Date checked for every row below: **2026-10-13**.

Confidence is **medium**, not high, for one reason stated plainly up front: **Meta's own documentation does not
state the error returned when `appsecret_proof` is wrong or missing**, and it does not state what the Graph API
returns for a deleted, merged or renumbered Page id. Those are the two questions the brief flagged as live, and
both end in a documented gap rather than an answer. Everything else in this report is normative.

## 1. Source register

| # | Source URL | Page title | Product | API / version context | Date checked | Normative? |
|---|---|---|---|---|---|---|
| S1 | https://developers.facebook.com/docs/graph-api/changelog | Graph API Changelog | Graph API | all versions; states latest | 2026-10-13 | normative |
| S2 | https://developers.facebook.com/docs/pages/access-tokens | Page Access Tokens | Graph API / Pages API | unversioned | 2026-10-13 | normative |
| S3 | https://developers.facebook.com/docs/facebook-login/guides/access-tokens/ | Access Tokens for Meta Technologies | Facebook Login | unversioned | 2026-10-13 | normative |
| S4 | https://developers.facebook.com/docs/facebook-login/guides/access-tokens/get-long-lived | Get a Long-Lived Access Token | Facebook Login | `{graph-api-version}` placeholder | 2026-10-13 | normative |
| S5 | https://developers.facebook.com/docs/graph-api/reference/user/accounts/ | User `accounts` edge reference | Graph API | current version reference | 2026-10-13 | normative |
| S6 | https://developers.facebook.com/docs/pages/overview | Pages API Overview | Pages API | unversioned | 2026-10-13 | normative |
| S7 | https://developers.facebook.com/docs/permissions/reference/pages_messaging | Permissions Reference — `pages_messaging` | Graph API permissions | unversioned | 2026-10-13 | normative |
| S8 | https://developers.facebook.com/docs/graph-api/reference/page/subscribed_apps/ | Page `subscribed_apps` edge reference | Graph API | current version reference | 2026-10-13 | normative |
| S9 | https://developers.facebook.com/docs/graph-api/securing-requests | Securing Graph API Requests | Graph API | unversioned | 2026-10-13 | normative |
| S10 | https://developers.facebook.com/docs/facebook-login/security | Login Security | Facebook Login | unversioned | 2026-10-13 | normative |
| S11 | https://developers.facebook.com/docs/graph-api/guides/error-handling | Handling Errors | Graph API | unversioned | 2026-10-13 | normative |
| S12 | https://developers.facebook.com/docs/graph-api/reference/page/ | Page node reference | Graph API | current version reference | 2026-10-13 | normative |
| S13 | https://developers.facebook.com/docs/graph-api/changelog/version26.0 | Graph API v26.0 changelog | Graph API | v26.0 | 2026-10-13 | normative |
| S14 | https://developers.facebook.com/docs/graph-api/changelog/version25.0 | Graph API v25.0 changelog | Graph API | v25.0 | 2026-10-13 | normative |
| S15 | https://developers.facebook.com/docs/graph-api/changelog/non-versioned-changes | Out-of-cycle changes index | Graph API | non-versioned | 2026-10-13 | normative |
| S16 | https://developers.facebook.com/docs/graph-api/webhooks/getting-started/webhooks-for-pages | Webhooks for Pages | Graph API webhooks | unversioned | 2026-10-13 | normative |
| S17 | https://www.facebook.com/help/249601088403018 | Merge 2 Facebook Pages | Facebook Help Center | n/a | 2026-10-13 | **observational** — reached only as search-result snippets, the page itself was not read end to end |

Row S17 is the only non-normative row and is marked as such everywhere it is used.

## 2. The rules

### 2.1 How a Page access token is obtained

There is one documented path and it has two legs (S2, S4, S6).

1. A person logs in through Facebook Login and grants the app permission. That produces a **User access token**.
2. The app reads the Pages edge of that user and takes the `access_token` field off each Page entry:
   `GET https://graph.facebook.com/{user-id}/accounts?access_token={user-access-token}` (S2). S4 writes the same
   call as `GET https://graph.facebook.com/{graph-api-version}/{app-scoped-user-id}/accounts`.

S2 states the edge returns the Pages the person has a role on, and that each entry carries `access_token`,
`category`, `category_list`, `name`, `id` and `tasks`. S2 also states the key scoping rule: **"Page access tokens
are unique to each Page, admin, and app combination."** Three Lynomia accounts connecting the same Page through
the same app each get a token tied to the connecting admin, not to the Page alone — so the token dies with that
admin's access, not with the Page.

S6 adds the prerequisite on the person: **"In order to get a token from an app User, the app User must own or be
able to perform a Task on the Page."**

### 2.2 Lifetime, and how a long-lived Page token is produced

S3 gives the general shape: short-lived tokens last **about one to two hours**; long-lived tokens last **about 60
days**; tokens issued through web login are short-lived and are converted server-side using the app secret. S3
warns these lifetimes "may change without warning or expire early."

S4 gives the exchange exactly:

```
GET /{graph-api-version}/oauth/access_token
  ?grant_type=fb_exchange_token
  &client_id={app-id}
  &client_secret={app-secret}
  &fb_exchange_token={short-lived-user-access-token}
```

Conditions S4 states: an expired token cannot be exchanged (the person must log in again); the call must be made
server-side because it carries the app secret; the returned string is a *different* token and must replace the
stored one; one long-lived token must not be shared across multiple web clients.

**The long-lived Page token is a consequence, not a separate call.** S4: with a valid long-lived *User* token, the
same `/{app-scoped-user-id}/accounts` read returns Page `access_token` values that are themselves long-lived, and
S4 states: **"Long-lived Page access token do not have an expiration date and only expire or are invalidated under
certain conditions."** S4 does not list those conditions; it links out to debugging and error handling.

So the production rule for Lynomia is: *exchange the user token for a long-lived user token **before** reading
`/me/accounts`.* Reading `/me/accounts` with a short-lived user token yields Page tokens on the short-lived side of
that distinction. No page I read states the resulting Page-token lifetime in that case — see §6.

### 2.3 What invalidates a Page access token

No single normative page enumerates this. What *is* stated:

- S3: tokens with no time-based expiry "are still subject to invalidation for other reasons."
- S11 subcode **463** Expired, **467** Invalid Access Token ("expired, been revoked, or is invalid"), **460**
  Password Changed, **458** App Not Installed (the person has not logged into the app), **459** User
  Checkpointed, **464** Unconfirmed User.
- S11 subcode **492** Invalid Session, which S11 describes as the case where **the user tied to a Page access
  token lacks an appropriate Page role**. This is the one documented page-role invalidation: remove the
  connecting admin from the Page, or strip their task, and the stored Page token starts failing with 190/492 even
  though nothing about the Page changed.
- S5 error **283** names the permission set whose removal breaks the Pages read.

Practical consequence: a "non-expiring" Page token in Lynomia's database is non-expiring only while the
connecting admin keeps app access, keeps their Page task, and does not change their password or get
checkpointed. That is four independent revocation paths, none of which Lynomia controls.

### 2.4 `/me/accounts`, and why a Page may be missing from it

S5 is the edge reference. It states the edge returns "Pages the User has a role on," and that each node gets an
added `tasks` field (`list<enum>`, "The User's tasks assigned to the Page"). Notably:

- S5 **does not document the `access_token` field at all** on this edge — the token's presence there is stated by
  S2 and S4, not by the edge reference. Worth recording because it means the field is documented in the guides,
  not the reference.
- S5 **does not list the `tasks` enum values**; S6 does (§2.5).
- S5 **does not name a required permission** for reading the edge. The only permission strings on S5 appear inside
  error **283**: `pages_read_engagement` and/or `pages_read_user_content` and/or `pages_manage_ads` and/or
  `pages_manage_metadata`. S8 separately states `pages_show_list` is required for the Page subscription calls.

Documented reasons a Page does not appear:

| Reason | Source | Note |
|---|---|---|
| The person has no role / no task on the Page | S5, S6 | The edge is defined as Pages the user has a role on |
| `is_place` / `is_promotable` / `ad_id` filters applied | S5 | Optional filters that narrow the list |
| Pagination not followed | S5 | The edge is paged; `summary=total_count` gives the true count |
| The granting person declined the Page in the Login dialog | S6 (Login for Business) | Not restated as a list on S5 |

Not stated anywhere I read: whether a Page that is unpublished, country-restricted, or not yet claimed is
omitted from the edge. S12's token matrix (§2.7) implies unpublished Pages are still readable with a Page or user
token, which suggests they are listed — but that is an inference, not a normative statement. Recorded as a gap.

### 2.5 Page roles and tasks

S6 gives the current task enum, eight values:

| Task | What S6 says it permits |
|---|---|
| `ADVERTISE` | Create ads and unpublished Page posts; create ads for a connected Instagram account |
| `ANALYZE` | View Page Insights; see which admin published a post or comment |
| `CREATE_CONTENT` | Publish content as the Page |
| `MANAGE` | Assign and manage Page tasks |
| `MANAGE_LEADS` | View and manage leads |
| `MESSAGING` | **Send messages as the Page** |
| `MODERATE` | Respond to and delete comments on Page posts; for a connected Instagram account, publish content, handle comments and DMs, sync contact info, create ads |
| `VIEW_MONETIZATION_INSIGHTS` | View monetization insights |

S2's own sample response shows a smaller set — `ANALYZE`, `ADVERTISE`, `MODERATE`, `CREATE_CONTENT`, `MANAGE` —
because it is an illustrative payload, not an enum definition. **The enum is S6's.** S6 also states the legacy
role mapping: *"If a person is given Admin access to a Page in the UI, that person is able to perform all tasks
on that Page."* Meta's developer documentation describes tasks, not the old Admin/Editor/Moderator/Advertiser/
Analyst role names; the only role word S6 uses is Admin.

**Which task is needed to read and send messages** — this is the sharpest finding in the report, and it is a
split answer:

| Capability | Required task | Required permission | Source |
|---|---|---|---|
| Send messages as the Page | `MESSAGING` | — | S6 |
| Receive the `messages` webhook on the Page | `MESSAGING` | `pages_messaging` | S16 |
| Subscribe the app to the Page (`POST /{page-id}/subscribed_apps`) | `CREATE_CONTENT`, `MANAGE` **or** `MODERATE` | `pages_manage_metadata` + `pages_show_list` | S8 |
| Read the Page's current subscription (`GET /{page-id}/subscribed_apps`) | `CREATE_CONTENT`, `MANAGE` **or** `MODERATE` | `pages_manage_metadata` + `pages_show_list` | S8 |
| Read the Page node's user-containing fields | `MODERATE` | `pages_read_engagement`, `pages_read_user_content` | S12 |

**`MESSAGING` alone is not enough to connect a Page.** The token that subscribes the app must come from someone
who can `CREATE_CONTENT`, `MANAGE` or `MODERATE` (S8); the token that then sends needs `MESSAGING` (S6). A
person granted only the messaging task can hold a working send token and still be unable to complete the
subscription step. Lynomia's connect flow performs both with the same token
(`app/models/channel/facebook_page.rb:49-60`), so a Page connected by a messaging-only agent will send but may
never receive.

S7 (`pages_messaging`) states the permission "lets your app manage and access Page conversations and calling in
Messenger," with allowed uses including user-initiated interactive experiences, customer support messages, and
booking/purchase/order confirmations. Its stated dependencies are **`pages_manage_metadata` and
`pages_show_list`** — which matches S8's requirement set. S7 does **not** name a required Page task, does not
mention Page access tokens, and does not state a permission-specific App Review requirement; it states only the
general rule that Business Verification is required for all apps requesting Advanced Access. One caution: part of
S7's App Review column text reads as copy about creating and managing ads for other businesses' Pages, which
appears misplaced on that permission's row. Recorded as a documentation defect on Meta's side, not a rule.

### 2.6 Subscribing an app to a Page

S8 documents the edge:

- **GET** returns the webhooks the app is subscribed to for the Page. Each returned Application node carries
  `subscribed_fields`, "Webhook fields to which the app has subscribed on the page". No parameters.
- **POST** subscribes the app. Required parameter `subscribed_fields` (`array<enum>`, "Page Webhooks fields that
  you want to subscribe"). Returns `Struct { success: bool }` and supports read-after-write. S8 contains one
  surprising sentence: *"When posting to this edge, a Page will be created."* That is the reference's own wording
  and I am not going to reinterpret it — flagged in §6.
- **DELETE** removes the app's subscription and dissociates the Application from the Page. Returns
  `Struct { success: bool, messaging_success: bool }`. **An app can remove its own subscription with an App
  Access Token** — no Page token required.
- **Updating**: "You can't perform this operation on this endpoint."
- Instagram caveat: *"You cannot use the subscribed_fields parameter to configure or subscribe to Webhooks for
  Instagram."*
- The two-level rule: *"only fields with subscriptions at both the page and app levels will get Webhooks."* S16
  words the same requirement differently — *"Webhook notifications will only be sent if your Page has installed
  your Webhooks configured-app"* — and adds a second kill switch: notifications also depend on the Page not having
  disabled the **App** platform in its Page App Settings.

Fields available: S8 states the enum is long and begins `feed, mention, name, picture, category, description,
conversations`, covering messaging, lead generation, calls, invoices and page details. **S8 does not print the
full enum**, and S16 — the Pages webhook reference — documents only two fields, `feed` and `messages`, and refers
readers to the Messenger webhooks guide for the rest. So the authoritative list of messaging subscription fields
lives on the Messenger Platform side (agent 022's scope), not on either Pages page. I am not reproducing a field
list I did not read.

From S16, for the two fields it does document:

| Field | Description (S16) | Permission | Token |
|---|---|---|---|
| `feed` | "Notifies you when an Page's feed has changed" | `pages_manage_metadata` + `pages_show_list` | Page token from someone with `CREATE_CONTENT`, `MANAGE` or `MODERATE` |
| `messages` | "Notifies you when your page has received a message via Messenger" | `pages_messaging` | Page token from someone with the **`MESSAGING`** task |

Lynomia subscribes seven fields — `messages message_deliveries message_echoes message_reads standby
messaging_handovers messaging_postbacks` (`app/models/channel/facebook_page.rb:53-55`). Only `messages` is
documented on S16; the other six are Messenger-guide fields. None of them is invented, but their normative
definitions are outside this report's sources.

### 2.7 `appsecret_proof`

**What it is** (S9): a parameter added to server-side Graph API calls that binds the request to the app secret,
so a stolen access token cannot be used from a system that does not hold the secret. S9's rationale is explicit:
access tokens are portable and can be stolen.

**How it is computed.** The two normative pages do not agree on the message, and this matters for Lynomia's code:

| Source | Formula shown | Message hashed |
|---|---|---|
| S9 | `hash_hmac('sha256', $access_token, $app_secret)` | the access token alone |
| S10 | `hash_hmac('sha256', $access_token.'|'.time(), $app_secret)` | access token, a literal `|`, then the Unix timestamp |

Both are HMAC-SHA256 keyed with the **app secret** (App Dashboard → Settings → Basic, per S9). S10 adds three
details S9 omits: convert the timestamp to an integer because some systems return a float; **"Be sure to express
the hash as a hexadecimal object"**; and **"Time-stamped app secret proofs will be considered expired after 5
minutes,"** with the recommendation to generate a new proof for every Graph API call. S9 does not state the
output encoding at all, and S9 does not mention the timestamped form.

Read together: the plain form (token only) has no expiry; the timestamped form expires after five minutes. Meta
documents both without saying which one an app should prefer or whether the server accepts both. That ambiguity
is recorded in §6 rather than resolved.

**When it is required.** Neither page says proofs are globally mandatory. The switch is the app setting S9 and
S10 both call **Require App Secret** (App Dashboard → App Settings → Advanced → Security). S9's warning: *"If this
setting is enabled, all client-initiated calls must be proxied through your backend where the `appsecret_proof`
parameter can be added to the request before sending it to the Graph API, or the call will fail."* Neither page
uses the phrase "Require proof on all calls". S9 also notes the official PHP SDK appends the parameter
automatically.

**What Meta returns when the proof is wrong or missing — not stated.** S9 says only "the call will fail". S10
gives no code or message. S11, the error-handling guide, **does not mention `appsecret_proof`, app secret proof,
or invalid signature anywhere.** A domain-restricted search of `developers.facebook.com` for the commonly quoted
string "Invalid appsecret_proof provided in the API argument" returned no documentation page containing it — only
the two how-to pages above and one developer-community thread, which is not normative under §6.2.

The closest documented code is **104 "Incorrect signature"**, which S8 lists for all three `subscribed_apps`
operations and S12 does not list for the Page node. **No source I read connects 104 to `appsecret_proof`.** I am
not asserting that link. For Lynomia this means: the proof-failure signature cannot be classified from Meta's
documentation, and any error mapping must be derived from observed responses in this installation's own logs and
labelled observational.

Repository context for this live question: Lynomia computes and sends a proof on exactly one path —
`app/services/instagram/messenger/send_on_instagram_service.rb:21`, `:23`, `:38` (Instagram DMs over a connected
Facebook Page, guarded by `if app_secret_proof`). The Facebook Messenger paths go through Koala with a bare Page
token (`app/builders/messages/facebook/message_builder.rb:147`,
`app/builders/messages/instagram/messenger/message_text.rb:10`) and the subscribe/unsubscribe path goes through
`Facebook::Messenger::Subscriptions` (`app/models/channel/facebook_page.rb:51`), neither of which is passed a
proof. **If Require App Secret is ever enabled on the Meta app, the Instagram-over-Messenger send keeps working
and the Facebook Messenger send and the Page subscription stop** — and the subscribe failure is silent, because
`app/models/channel/facebook_page.rb:57-59` rescues `StandardError`, writes `Rails.logger.debug` and returns
`true`.

### 2.8 Page-level failures

S12's token-and-permission matrix is the one normative statement that distinguishes Page states:

| Page status (S12) | Token accepted | Feature / permission |
|---|---|---|
| **Unpublished** | Page access token **or** user access token | "no feature or permission needed" |
| **Published, unrestricted** | App access token **or** user access token | PPCA or PPMA for public data; or `pages_read_engagement` + `pages_read_user_content` + `pages_show_list` for Page-owned data |
| **Published, restricted** | Page access token **or** user access token | same options as unrestricted |

S12 defines restriction broadly in its Public Page Data section: **"Restrictions include any visibility
restrictions such as by age or region."** So a country restriction is, for Graph API purposes, the same class of
thing as an age gate: it removes app-token and public-data access and forces a Page or user token. S12 lists no
dedicated field for age or country gating.

Status fields S12 does define, quoted:

| Field | S12 description | Readable with |
|---|---|---|
| `is_published` | "Indicates whether the Page is published and visible to non-admins" | — |
| `is_permanently_closed` | "Whether the business corresponding to this Page is permanently closed." | PPCA or PPMA |
| `is_unclaimed` | "Indicates whether the Page is unclaimed" | — |
| `verification_status` | "Showing whether this Page is verified." Value can be `blue_verified` or `gray_verified` | PPMA |
| `country_page_likes` | "If this is a Page in a Global Pages hierarchy, the number of people who are being directed to this Page." | PPCA or PPMA |
| `is_eligible_for_branded_content` | "Indicates whether the page is eligible for the branded content tool" | — |

**Deleted, merged and renumbered Pages: no normative answer found.** No page in the register states the Graph API
error for reading or sending to a Page id that has been deleted, merged away, or reassigned. S17 (observational,
snippet-level only) describes merging from the user's side: both Pages must be admin-held, same name, same thing,
same address for physical locations, same Business Manager account; the source Page cannot be the primary Page of
a Business Manager account; a person with task-only access cannot merge; the kept Page "will remain unchanged,
except for the addition of people who follow the other Page"; the merged-away Page "will be removed from Facebook
and you won't be able to unmerge it," losing posts, photos, reviews, ratings and username. **Whether the
merged-away Page's id continues to resolve, 404s, or redirects to the surviving id is not stated** — the search
summary explicitly flagged its own "IDs would logically go with it" as an inference. I am recording it as
unanswered. Likewise "Page migrated to a new id": I found no Meta page documenting a Page-id migration contract,
and I will not describe one.

What *is* documented for a failing Page-bound call is the generic set: 190 (+ subcode 492 when the role is gone),
200 "Permissions error", 210 "User not visible", 230 "Permissions disallow message to user", 100 "Invalid
parameter", 368 policy block, 80001 Page-level rate limit (S8, S11, S12).

## 3. Error codes and failures

Every row is from a normative source. `not stated` means the source does not say.

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Source |
|---|---|---|---|---|---|---|
| 1 | — | API Unknown | "Possibly temporary. Wait and retry. If it recurs, confirm the API exists." | Retry; verify the endpoint exists in the version used | not stated | S11 |
| 2 | — | API Service | Temporary downtime | Wait and retry | not stated | S11 |
| 3 | — | API Method | Capability or permission missing for the method | Check app capability/permissions | not stated | S11 |
| 4 | — | API Too Many Calls | App-level throttling | Wait, reduce volume | not stated | S11 |
| 10 | — | API Permission Denied | Permission missing or removed | Handle the missing permission | not stated | S11 |
| 17 | — | API User Too Many Calls | Per-user throttling | Wait, reduce volume | not stated | S11 |
| 100 | — | Invalid parameter | Malformed or unsupported parameter | Fix the request | not stated | S5, S8, S12 |
| 102 | — | API Session / "Session key invalid or no longer valid" | Session invalid; follow subcode if present | Re-acquire a token | not stated | S8, S11, S12 |
| 104 | — | Incorrect signature | Signature on the request is wrong | not stated | not stated | S8 |
| 190 | — | Invalid OAuth 2.0 Access Token / "Access token expired" | Token unusable | Get a new access token | not stated | S5, S8, S11, S12 |
| 190 | 458 | App Not Installed | Person has not logged into the app | Reauthenticate the person | not stated | S11 |
| 190 | 459 | User Checkpointed | Person must resolve an issue on facebook.com | Ask the person to log in on Facebook | not stated | S11 |
| 190 | 460 | Password Changed | Credentials changed | Person must log in again | not stated | S11 |
| 190 | 463 | Expired | Login status or token expired/invalid | Handle expired token | not stated | S11 |
| 190 | 464 | Unconfirmed User | Person must resolve an issue on facebook.com | Ask the person to log in on Facebook | not stated | S11 |
| 190 | 467 | Invalid Access Token | "expired, been revoked, or is invalid" | Reauthorize | not stated | S11 |
| 190 | 492 | Invalid Session | "The user tied to a Page access token lacks an appropriate Page role" | Restore the person's Page task, or reconnect with an eligible admin | not stated | S11 |
| 200–299 | — | API Permission | Range; varies by permission | Handle the missing permission | not stated | S11 |
| 200 | — | Permissions error | Caller lacks required permission/task | Grant permission or task | not stated | S5, S8, S12 |
| 210 | — | User not visible | Target user not visible to the caller | not stated | not stated | S5, S8, S12 |
| 230 | — | Permissions disallow message to user | Messaging to this user not permitted | not stated | not stated | S12 |
| 283 | — | "That action requires the extended permission pages_read_engagement and/or pages_read_user_content and/or pages_manage_ads and/or pages_manage_metadata" | Missing Pages permission on the accounts read | Request the permission | not stated | S5 |
| 341 | — | Application limit reached | Temporary downtime or throttling | Wait, reduce volume | not stated | S11 |
| 368 | — | "The action attempted has been deemed abusive or is otherwise disallowed" / Temporarily blocked for policy violations | Policy block | Wait and retry | not stated | S5, S11, S12 |
| 459 | — | "The session is invalid because the user has been checkpointed" | Person checkpointed (as an edge-level code) | Person resolves on facebook.com | not stated | S5 |
| 483 | — | "The session is invalid because the user is in consent app blocking" | Consent blocking | not stated | not stated | S5 |
| 506 | — | Duplicate Post | Identical content re-posted | Change the content | not stated | S11 |
| 2500 | — | Error parsing graph query | Malformed query | Fix the query | not stated | S5 |
| 80001 | — | "There have been too many calls to this Page account. Wait a bit and try again." | Page-level rate limit | Back off | not stated | S5, S8, S12 |
| 80002 | — | "There have been too many calls to this Instagram account. Wait a bit and try again." | IG account rate limit | Back off | not stated | S5, S12 |
| 80005 | — | Too many leadgen API calls to this Page account | Leadgen rate limit | Back off | not stated | S12 |
| 1609005 | — | Error Posting Link | Link rejected | Check the URL | not stated | S11 |

Error envelope (S11): `error` carries `message`, `type` (e.g. `OAuthException`), `code`, `error_subcode`
(present only for some errors), `fbtrace_id`, plus `error_user_title` and `error_user_msg` as display strings in
the request's locale. S11 notes `fbtrace_id` expires quickly, so it must be captured at failure time, not looked
up later. S11 also states explicitly that an `OAuthException` with **no** subcode means "get a new access token",
while one **with** a subcode must be handled by the subcode — the subcode is the actionable field, not the code.

**No `appsecret_proof` row exists in this table because no normative source states one.** Do not add one from a
community thread.

## 4. Limits and numbers

| Number | What it governs | Source |
|---|---|---|
| ~1–2 hours | Typical short-lived access token lifetime | S3 |
| ~60 days | Typical long-lived access token lifetime | S3 |
| 5183944 seconds | `expires_in` in S4's sample long-lived-token response | S4 |
| no expiration date | Long-lived **Page** access token, "only expire or are invalidated under certain conditions" | S4 |
| 5 minutes | Expiry of a **time-stamped** app secret proof | S10 |
| 90 days | Window within which the iOS/Android/JavaScript SDKs auto-refresh a token if the person used the app | S4 |
| 2 | **Not Meta's** — Lynomia's `AUTHORIZATION_ERROR_THRESHOLD` before a channel is flagged for reauthorization (`app/models/concerns/reauthorizable.rb:16`, `:34`) | repository |

No other numeric limit is claimed. Page-level rate-limit ceilings behind 80001/80005 are not stated on any page
in the register.

## 5. Version and deprecation notes

**Current Graph API version as of 2026-10-13: v26.0**, introduced **July 29, 2026** (S1 states "The latest Graph
API version is: v26.0").

**Oldest still-supported version as of 2026-10-13: v21.0**, available until **January 21, 2027**. S1 does not
label versions "supported"; it publishes an *Available Until* date per version, and v20.0's date — **September 24,
2026** — has passed as of the date checked, making v21.0 the oldest version whose window is still open. That
derivation is mine from S1's table, not a sentence on the page.

| Version | Introduced | Available until (S1) |
|---|---|---|
| v26.0 | July 29, 2026 | TBD |
| v25.0 | February 18, 2026 | July 29, 2028 |
| v24.0 | October 8, 2025 | February 18, 2028 |
| v23.0 | May 29, 2025 | October 8, 2027 |
| v22.0 | January 21, 2025 | May 20, 2027 |
| v21.0 | October 2, 2024 | January 21, 2027 |
| v20.0 | May 21, 2024 | September 24, 2026 — **passed** |
| v19.0 | January 23, 2024 | May 21, 2026 — passed |
| v18.0 | September 12, 2023 | January 26, 2026 — passed |

**Page token or permission consolidation: nothing found.** This was an explicit question in the brief and the
answer is negative on every source checked:

- **S13 (v26.0)** contains no Page-token, Page-permission or `subscribed_apps` change. Its Page items are legacy
  field deprecations for New Pages Experience only — `current_location`, `genre`, `network`, `parking`,
  `start_info` return a version error on v26.0+, with the note that it "Will apply to all versions approximately
  90 days after the v26.0 launch; date to be confirmed" — plus removal of the `auto_publish_page_info_updates`
  setting from the Page settings edge, with "no replacement". Separately, `GET /{page-id}/commerce_orders` is among
  47 Commerce Order Management endpoints deprecated: blocked on v26.0+ from July 29, 2026 and removed from all
  remaining versions on October 27, 2026, with "No replacement API is available." On Messenger, the `story` value
  in Marketing API `messenger_positions` is silently removed for v26.0+ and deprecated across all Marketing API
  versions, including unversioned calls, on October 27, 2026.
- **S14 (v25.0)**, released February 18, 2026, contains no Page-token, Page-permission, task, `subscribed_apps`,
  Messenger or `/me/accounts` change. Its relevant items are Page/Post/Video/Stories **Insights** metric
  deprecations (including `page_impressions_unique`, `post_impressions_unique`,
  `PAGE_STORY_IMPRESSIONS_BY_STORY_ID`, replaced by `page_total_media_view_unique`, `page_media_view`,
  `STORY_MEDIA_VIEW`; once deprecated they "will return an error if requested using any API version"), deprecation
  of the `metadata=1` query parameter (v25.0+, all versions on May 19, 2026), and one item that *does* affect this
  installation: **Meta re-signs the webhook mTLS certificate from a Meta-owned CA starting March 31, 2026** —
  servers that verify the certificate must trust the new CA by that date "or TLS handshakes will fail and webhook
  delivery will stop" (recommended download: `meta-outbound-api-ca-2025-12.pem`).
- **S15** lists exactly one out-of-cycle entry, **April 8, 2025**, and no 2026 entries. The index page does not
  describe that entry's contents, so whether it touches Pages is **not checked** — I did not spend a fetch on the
  2025 sub-page. That is the one register hole I would close first.

**Lynomia is pinned to expired versions.** `config/installation_config.yml:155` sets `FACEBOOK_API_VERSION` to
`v18.0`, whose availability ended **January 26, 2026** (S1), and `config/installation_config.yml:160` sets
`INSTAGRAM_MESSENGER_API_VERSION` to `v11.0`, which S1's table does not even list. `v11.0` is also hard-coded as
`DEFAULT_API_VERSION` in `app/services/instagram/messenger/send_on_instagram_service.rb:9`. By contrast
`WHATSAPP_API_VERSION` is `v24.0` (`config/installation_config.yml:193`) and the WhatsApp client defaults to
`v24.0` (`app/services/whatsapp/facebook_api_client.rb:7`). The Facebook/Messenger side of this installation is
two expired versions behind the WhatsApp side. This is an input for agent 091 and for the orchestrator, not a
doc gap — but any article that tells a user "reconnect your Page" will keep failing while the pinned version is
out of support.

## 6. Ambiguities and gaps in Meta's documentation

1. **`appsecret_proof` failure is undocumented.** S9 says "the call will fail"; S10 says nothing; S11 — the error
   guide — never mentions the parameter. There is no normative code, subcode or message. 104 "Incorrect
   signature" (S8) is adjacent but unconnected by any source. **Unresolved; must not be guessed.**
2. **Two different proof formulas.** S9 hashes the token alone; S10 hashes `token|timestamp` and imposes a
   5-minute expiry. Neither page says which the server expects, whether both are accepted, or whether the choice
   depends on the Require App Secret setting. Recorded, not resolved.
3. **Page-token expiry is stated two ways.** S6: Page access tokens "have an expiration time." S4: long-lived
   Page access tokens "do not have an expiration date." Reconcilable if S6 means the short-lived case, but
   neither page says so.
4. **The invalidation conditions are never enumerated.** S4 promises "certain conditions" and links out; the
   linked error guide lists subcodes but does not present them as the Page-token invalidation list.
5. **`access_token` is not documented on the `/me/accounts` edge reference** (S5), only in the guides (S2, S4).
6. **The `tasks` enum is not on the edge reference** (S5); it is on the overview (S6). An integrator reading only
   the reference cannot learn the values.
7. **No full `subscribed_fields` enum on either Pages page.** S8 truncates it; S16 documents two fields. The
   messaging fields Lynomia actually subscribes are defined only in the Messenger guide.
8. **"When posting to this edge, a Page will be created"** (S8) is unexplained in a reference for subscribing an
   existing Page. Either a documentation defect or a behaviour nobody should rely on.
9. **Deleted / merged / renumbered Page ids have no documented Graph contract.** Not the error, not whether the
   old id resolves, not whether a surviving id is returned. S17 is user-facing and observational.
10. **Whether unpublished or region-restricted Pages appear in `/me/accounts`** is not stated.
11. **`pages_messaging` states no required Page task** (S7) while S6 and S16 both require `MESSAGING`. The
    permissions reference and the Pages docs do not cross-reference.
12. **S7 contains apparently misplaced App Review copy** about creating and managing ads for other businesses'
    Pages. Treat S7's review requirements as unreliable and verify against the App Review flow itself.
13. **Not checked**: the April 8, 2025 out-of-cycle sub-page (S15); the Messenger webhooks field reference; the
    Login for Business Page-selection dialog behaviour; S17 read in full; business-help pages on unpublishing a
    Page and on country/age restriction, which the domain search did not surface.

## 7. What Lynomia users would ask

These are the support questions this area generates, each traceable to a rule above. They are the input to the
coverage matrix, not article titles.

| Question | Where the answer comes from | Does the product currently help? |
|---|---|---|
| "My Facebook Page isn't in the list when I connect." | §2.4 — no role/task, declined in the dialog, pagination | The picker renders whatever `/me/accounts` returned (`app/controllers/api/v1/accounts/callbacks_controller.rb:28`, `:48`; `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Facebook.vue:142`) with no explanation of absence |
| "Messages send but nothing arrives in Lynomia." | §2.5, §2.6 — subscription needs `CREATE_CONTENT`/`MANAGE`/`MODERATE`; sending needs `MESSAGING`; both Page-level and app-level subscription must exist; the Page can disable the App platform | No. The subscribe failure is swallowed at `app/models/channel/facebook_page.rb:57-59` |
| "Why did my Facebook inbox ask me to reconnect?" | §2.3 — 190 with subcode 458/460/463/467/492; 492 specifically means the connecting person lost their Page task | Partly: `Reauthorizable` flags after 2 errors (`app/models/concerns/reauthorizable.rb:16`) but the cause is not surfaced |
| "We removed an employee and Facebook stopped working." | §2.1, §2.3 — the token is tied to the Page/admin/app triple; subcode 492 | No documentation found at this level |
| "Does the Facebook token expire? Do I have to reconnect every 60 days?" | §2.2 — long-lived Page tokens have no expiry date, but only if the user token was exchanged first | Not documented |
| "Our agent can reply to Messenger but cannot finish the setup." | §2.5 — `MESSAGING`-only is insufficient for `subscribed_apps` | Not documented |
| "What permissions is Lynomia asking for and why?" | §2.4, §2.5 — `pages_messaging`, `pages_manage_metadata`, `pages_show_list`, `pages_read_engagement` | Not documented against Meta's stated purposes |
| "We unpublished our Page for maintenance and the integration broke." | §2.8 — unpublished/restricted Pages change the accepted token class | Not documented |
| "We merged two Pages. Do we reconnect?" | §2.8 — **no normative answer**; the merged-away Page is removed and cannot be unmerged (S17, observational) | Not documented, and cannot be documented normatively today |
| "Facebook returns 'Incorrect signature' / our app secret setting changed." | §2.7 — Require App Secret forces a proof on every call; Lynomia sends one on exactly one code path | Not documented; and the behaviour is a real code gap, not just a doc gap |
| "Why is Facebook slower/erroring under load?" | §3 — 80001 Page-level rate limit, 368 policy block, 4/17 throttling | Not documented |

Two items here are code findings rather than documentation findings, and the orchestrator should route them:
the swallowed subscribe failure (`app/models/channel/facebook_page.rb:57-59`) and the asymmetric
`appsecret_proof` coverage (present at
`app/services/instagram/messenger/send_on_instagram_service.rb:21-23`, absent on every Koala and
`Facebook::Messenger::Subscriptions` call). Neither is mine to fix in Phase 1.
