---
agent: 003
scope: Meta permissions and scopes for WhatsApp / Messenger / Instagram inbox integration — exact strings, grants, review requirements, failure modes, renames
confidence: medium
sources_normative: 14
sources_observational: 2
---

# Agent 003 — Permissions and scopes

**Date checked for every row and claim below: 2026-10-13.**

**Method note, stated so later agents can weigh the evidence.** Pages were fetched read-only. No Meta API was
called, no token was used, no form submitted. The fetch tool returns a reading of each page under a short-quote
limit, so **permission strings in this report are exact** (they are machine-readable identifiers and were
requested verbatim), while **the prose describing what a permission grants is a faithful paraphrase, not a
quotation**, except where quotation marks appear. Where a page did not state something, the cell says
`not stated` rather than being filled by inference. Where I inferred an endpoint mapping, the row says
`(inference)`.

## 1. Source register

| # | Source URL | Page title | Product | API / version context | Date checked | Normative? |
|---|---|---|---|---|---|---|
| S1 | https://developers.facebook.com/docs/permissions | Permissions Reference | Graph API | No version stated; current reference | 2026-10-13 | normative |
| S2 | https://developers.facebook.com/docs/graph-api/overview/access-levels | Access Levels | Graph API | No version stated | 2026-10-13 | normative |
| S3 | https://developers.facebook.com/docs/graph-api/changelog | Graph API Changelog (index) | Graph API | Version table v13.0 – v26.0 | 2026-10-13 | normative |
| S4 | https://developers.facebook.com/docs/graph-api/changelog/version23.0 | Graph API v23.0 changelog | Graph API | v23.0, launched 2025-05-29 | 2026-10-13 | normative |
| S5 | https://developers.facebook.com/docs/graph-api/changelog/version7.0 | Graph API v7.0 changelog | Graph API | v7.0, launched 2020-05-05 | 2026-10-13 | normative |
| S6 | https://developers.facebook.com/docs/instagram-platform/overview/ | Overview of the Instagram API | Instagram Platform | Two configurations; no single version | 2026-10-13 | normative |
| S7 | https://developers.facebook.com/docs/instagram-platform | Instagram Platform (landing) | Instagram Platform | none | 2026-10-13 | normative (thin) |
| S8 | https://developers.facebook.com/docs/instagram-platform/changelog | Instagram Platform Changelog | Instagram Platform | Dated entries, not versioned | 2026-10-13 | normative |
| S9 | https://developers.facebook.com/documentation/business-messaging/messenger-platform/overview | Overview for the Messenger Platform | Messenger Platform | No version stated | 2026-10-13 | normative |
| S10 | https://developers.facebook.com/docs/graph-api/guides/error-handling | Handling Errors | Graph API | No version stated | 2026-10-13 | normative |
| S11 | https://developers.facebook.com/docs/whatsapp/cloud-api/overview | Cloud API Overview | WhatsApp Cloud API | No version stated | 2026-10-13 | normative |
| S12 | https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes | Error Codes | WhatsApp Cloud API | No version stated | 2026-10-13 | normative |
| S13 | https://developers.facebook.com/documentation/business-messaging/whatsapp/access-tokens/ | Access Tokens Guide | WhatsApp Business Platform | No version stated | 2026-10-13 | normative |
| S14 | https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/overview/ | Embedded Signup | WhatsApp Business Platform | No version stated | 2026-10-13 | normative |
| O1 | Web search aggregation over `developers.facebook.com` (Solution Partner overview, WhatsApp Get Started) | — | WhatsApp Business Platform | — | 2026-10-13 | **observational, unconfirmed** — snippets only, those pages were not fetched |
| O2 | Web search aggregation over `developers.facebook.com` (Instagram messaging permission sets) | — | Instagram Platform / Messenger | — | 2026-10-13 | **observational, unconfirmed** — snippets only |

Every claim below references a row. Nothing in this report comes from a blog post, Stack Overflow or a community
thread; where a claim rests only on O1/O2 it is labelled unconfirmed.

## 2. The rules

### 2.1 Two access levels, and that is the whole gate

S2 states the model plainly: **Standard Access** is the default, and "Permissions with Standard Access can only
be requested from app users who have a role on the requesting app." **Advanced Access** lets the permission be
requested from any app user. S2: "Business Verification is required to get Advanced Access," and "In some cases
additional App Review on an individual permission and feature basis might be required."

S2 also warns about the reverse move: downgrading a permission from Advanced to Standard "will invalidate/
deactivate any permission/feature for any app users who do not have a role on your app." For a multi-tenant
product like Lynomia that is a total-outage event for every connected customer inbox, not a degradation.

S6 says the same in Instagram's words: "Standard Access is the default access level for all apps and limits the
data your app can get"; "This access level requires App Review and Business Verification"; "Your app must
complete Meta App Review to be granted Advanced Access."

S9 adds the Messenger nuance that matters for self-hosted installs: App Review is "Not required if you only send
and receive messages for your own Facebook Page," and Business Verification applies "if your app is used by
people without a Role on the app."

**Consequence for Lynomia's documentation.** The operative question a stuck administrator has is never "which
permission do I tick" — it is "is my app in Standard Access, and is the person connecting an app role holder?"
A connection flow that works for the developer and fails for every customer is Standard Access, not a bad scope
string. No Meta page I read states a distinct error code for this case (see §3.4).

### 2.2 Permissions expire from disuse

S1 states: "If your app does not use a permission for 90 days," the user must regrant it. This is a normative
rule with real support consequences for a product where a tenant may connect a channel and then not use a given
capability for a quarter.

### 2.3 Permissions have declared dependencies

S1 lists dependencies per permission, and S9 restates one of them for Messenger. These are not optional
niceties: a dependency is another permission that must also be granted.

| Permission | Dependencies Meta declares | Source |
|---|---|---|
| `whatsapp_business_messaging` | `whatsapp_business_management` | S1 |
| `whatsapp_business_manage_events` | `whatsapp_business_management` | S1 |
| `whatsapp_business_management` | none | S1 |
| `pages_messaging` | `pages_manage_metadata`, `pages_show_list` | S1 |
| `pages_manage_metadata` | `pages_show_list` | S1 |
| `pages_read_engagement` | `pages_show_list` | S1 |
| `pages_show_list` | none | S1 |
| `instagram_basic` | `pages_read_user_content`, `pages_show_list` | S1 |
| `instagram_manage_messages` | `instagram_basic`, `pages_read_engagement`, `pages_show_list` | S1 |
| `instagram_business_basic` | none | S1 |
| `instagram_business_manage_messages` | `instagram_business_basic` | S1 |
| `business_management` | (not listed as depending on anything) — but S9 says it "is a dependency for `pages_messaging`, `pages_show_list`, and `instagram_manage_messages`" | S1, S9 |

S9 also instructs: for `business_management`, "Call this out in your App Review submission."

**Ambiguity, recorded not resolved.** S1's dependency table and S9's sentence disagree in direction.
S1 does not list `business_management` as a dependency of `pages_messaging`; S9 says it is. Both are normative
Meta pages. Treat `business_management` as required in practice for the Pages messaging flow (which is what
Lynomia already requests, `app/javascript/dashboard/helper/facebookScopes.js:5`) and record the contradiction.

### 2.4 Page tasks, not just permissions

S9 states that the app user requesting a Page access token "must be able to perform the `MESSAGING` and
`MODERATE` Page tasks," and that a Page access token is "Required to send and receive messages through the
Messenger Platform" and is "Generated after a Page admin grants your app the necessary permissions."

S6 states the Instagram equivalent: "your app user must also be able to perform admin-equivalent tasks on the
linked Facebook Page," and maps Facebook-Login Instagram permissions to Page tasks — `instagram_manage_messages`
is grantable through the **Messages** task, `instagram_manage_comments` through **Community Activity**,
`instagram_manage_insights` through **Insights**, `instagram_content_publish` through **Content** or **Full
control**.

This is the single most common real-world cause of "I granted everything and it still does not work": the
connecting user holds a Page role that does not carry the `MESSAGING` task. Agent 004 owns roles and asset
ownership; this report stops at naming the dependency.

### 2.5 WhatsApp: permissions are necessary but not sufficient

S13 is explicit that a system user token needs both the permissions and **business asset access**. It says to
"assign your app these three Graph API permissions" — `business_management`, `whatsapp_business_management`,
`whatsapp_business_messaging` — and separately that an Admin system user has "full access to all WhatsApp
Business Accounts (WABAs) and their assets" by default, while an Employee system user must be granted "Partial
or Full business asset access to each WABA." Partial access can be narrowed to specific assets or actions.

S13 states the failure for the asset half: if a system user lacks access to a resource or WABA the request fails
with "error code `200`," with the page's own caution that this is "not to be confused with HTTP status code
`200`."

S11 (Cloud API Overview) adds only the frame: "Authentication uses OAuth (not 2.0) access tokens, while
permissions restrict access to specific resources," and "You must have a business portfolio to use the platform."
S11 names no permission string at all — the permission strings live in S1 and S13.

### 2.6 Embedded Signup gates onboarding on Advanced Access

S14 is the clearest statement of the commercial gate: "You will not be able to onboard business customers until
your app has been approved for advanced access." In development mode the permissions appear in the flow for
admins, developers and testers; in live mode "only permissions that have been approved for advanced access
through the App Review process will appear in the flow."

S14 also splits the token model: "If you are a Tech Provider, you will use business tokens exclusively";
Solution Partners use a system user token to share a credit line and business tokens for everything else, and
for the credit-line case "The system user must have granted your app the `business_management` permission."

**This is the operative fact for Lynomia's Embedded Signup path**: a permission that is not approved for
Advanced Access does not fail at call time — it is **absent from the consent screen**, so the customer never
grants it and the resulting token silently lacks it.

### 2.7 "Private" apps cannot run an Instagram inbox

S6 states that for private apps "you can request approval only for the following permissions:" and lists
`instagram_basic` and `instagram_manage_comments`. `instagram_manage_messages` is not in that list. An app
configured as private therefore cannot be approved for Instagram Direct messaging.

### 2.8 Human Agent is a feature, not a permission

S6: Human Agent "allows your app to have a human agent respond to user messages using the **human_agent** tag
within 7 days of a user's message." S6 lists it under both Instagram configurations as a *feature* alongside
"Instagram Public Content Access." Features go through the same App Review surface but are not scopes and are
not requested in the OAuth `scope` parameter. Lynomia already has a config switch for this
(`ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT`, `app/controllers/super_admin/app_configs_controller.rb:74`).

## 3. The authoritative permission table

### 3.1 WhatsApp

| Permission string | What Meta states it grants | Endpoints that need it | Review / access level | What a missing grant looks like | Source |
|---|---|---|---|---|---|
| `whatsapp_business_management` | Read and/or manage WhatsApp business assets the developer owns or has been granted access to: WhatsApp Business Accounts, business phone numbers, message templates, QR codes and their messages, and webhook subscriptions. Allowed use includes managing those assets and showing WABA analytics in a customer portal. | *(inference from the asset list)* `GET/POST /{waba-id}/message_templates`, `GET /{waba-id}/phone_numbers`, `POST /{waba-id}/subscribed_apps`, QR-code endpoints. Lynomia reads exactly the first of these when validating this token (`app/services/whatsapp/business_management_token_validation_service.rb:31`). | Advanced Access needed to act on WABAs the app's own business does not own *(O1, unconfirmed)*. App Review asks for "specific examples of why your app requires access to the business assets" plus a screencast of creating a template or enabling the Call Button. | Error `200`–`299` family, "Permission is either not granted or has been removed" (S12). In Lynomia this surfaces as the message in `app/services/whatsapp/manual_setup_validation_service.rb:69`. | S1, S12, S13 |
| `whatsapp_business_messaging` | Send WhatsApp messages and make calls to a specific phone number; upload and retrieve message media; manage and get business profile information; register phone numbers with Meta. | *(inference)* `POST /{phone-number-id}/messages`, `POST /{phone-number-id}/media`, `GET /{media-id}`, `GET/POST /{phone-number-id}/whatsapp_business_profile`, `POST /{phone-number-id}/register`. | Depends on `whatsapp_business_management` (S1). App Review requires a screencast of a message landing in a WhatsApp client, or a call. | Error `200`–`299` / `10` (S12). Lynomia checks this one by reading `GET /me/permissions` and matching `permission == 'whatsapp_business_messaging' && status == 'granted'` (`app/services/whatsapp/manual_setup_validation_service.rb:3,72-84`). | S1, S12, S13 |
| `business_management` | "allows your app to read and write with the Business Manager API"; also covers managing business assets. | *(inference)* Business portfolio endpoints; required on system user tokens per S13 and for credit-line sharing per S14. | App Review requires "specific examples of why your app requires managing business assets on behalf of other businesses," with a screencast showing the full login flow. | `200`–`299`; for Embedded Signup, absence instead means the scope never appears on the consent screen (S14). | S1, S13, S14 |
| `whatsapp_business_manage_events` | Log events such as purchases, add-to-cart and leads "on behalf of a WhatsApp Business Account administered by an app user"; event data may go to Meta for ads targeting, optimisation and reporting. | *(inference)* conversion-event endpoints. | Depends on `whatsapp_business_management`. S1 defers the review wording to the App Review docs. | not stated | S1 |

**Lynomia does not use `whatsapp_business_manage_events` anywhere** — recorded for completeness, because it is
the fourth WhatsApp permission in S1 and will otherwise look like an omission to a reader auditing the list.

### 3.2 Facebook Pages / Messenger

| Permission string | What Meta states it grants | Endpoints that need it | Review / access level | What a missing grant looks like | Source |
|---|---|---|---|---|---|
| `pages_show_list` | "allows your app to access the list of Pages a person manages." No dependencies. | `GET /me/accounts` | App Review wants examples of why the app needs the list of pages a user owns; if requested only as a dependency, the dependent permission must be named in the submission. | The Page picker is empty — the user sees "no pages" rather than an error. | S1, S9 |
| `pages_manage_metadata` | "allows your app to subscribe and receive webhooks about activity on the Page, and to update settings on the Page." Depends on `pages_show_list`. | *(inference)* `POST /{page-id}/subscribed_apps`, Page settings writes. | Requires examples of managing "accounts, settings, or webhooks for a page on behalf of other users who own the page(s)." | The inbox connects but **no inbound message webhook ever arrives**, because the app was never subscribed to the Page. This is the quietest failure in the set. | S1, S9 |
| `pages_messaging` | "allows your app to manage and access Page conversations and calling in Messenger." Depends on `pages_manage_metadata` and `pages_show_list`. | `POST /{page-id}/messages` (Send API), conversations reads. | App Review requires a screencast of a Messenger message being sent, or inbound/outbound calls. **S1's use-case text for this permission appears to be a copy of the `pages_manage_ads` text** — see §6. | Error `200`–`299` on send; `10` "Permission is either not granted or has been removed" (S10, S12). | S1, S9 |
| `pages_read_engagement` | "allows your app to read content (posts, photos, videos, events) posted by the Page," plus follower data and Page insights. Depends on `pages_show_list`. | *(inference)* Page content and insights reads. | Requires examples of reading content on pages owned by other users. | Reads of Page content/insights fail with the `200`–`299` family. | S1, S9 |
| `business_management` | see §3.1 | — | S9 names it a dependency for `pages_messaging`, `pages_show_list` and `instagram_manage_messages`. | see §3.1 | S1, S9 |

**S9's Messenger permission list is exactly five strings**: `pages_show_list`, `pages_manage_metadata`,
`pages_messaging`, `pages_read_engagement`, `business_management`.

**Lynomia requests four of the five.** `app/javascript/dashboard/helper/facebookScopes.js:1-8` requests
`pages_manage_metadata`, `business_management`, `pages_messaging`, `pages_show_list`, and its own comment says
the omission is deliberate: "(no pages_read_engagement, no Instagram scopes) for connect and reauthorize." For
**Messenger-only** inboxes that is defensible — nothing in S9 says Messenger *send/receive* needs
`pages_read_engagement`, and S1 does not list it as a dependency of `pages_messaging`. It is **not** defensible
for Instagram: see §3.3.

### 3.3 Instagram — two different permission families

S6 is the decisive page. There are two configurations with **disjoint** scope vocabularies, and conflating them
is the main documentation hazard in this area.

**Instagram API with Instagram Login** — host `graph.instagram.com` (S6: "all endpoints are accessed via the
**`graph.instagram.com`** host"):

| Permission string | Grants | Review / access | Source |
|---|---|---|---|
| `instagram_business_basic` | "allows your app to read an Instagram Business account profile's info and media." No dependencies. | App Review wants examples of why basic Instagram Business profile metadata is needed for other businesses. | S1, S6 |
| `instagram_business_manage_messages` | "allows an app to access messages on an Instagram professional account." Depends on `instagram_business_basic`. | Use case must explain the messaging functionality offered to onboarded business customers and how they perform it. | S1, S6 |
| `instagram_business_manage_comments` | *(S6 lists the string; S1's description not captured)* | not captured | S6 |
| `instagram_business_content_publish` | *(S6 lists the string)* | not captured | S6 |
| Human Agent *(feature, not a scope)* | human agent reply within 7 days using the `human_agent` tag | App Review feature | S6 |

**Instagram API with Facebook Login for Business** — host `graph.facebook.com` (S6: "all endpoints are accessed
via the **`graph.facebook.com`** host"):

| Permission string | Grants | Review / access | Source |
|---|---|---|---|
| `instagram_basic` | "allows your app to read an Instagram account profile's info and media." Depends on `pages_read_user_content` and `pages_show_list`. | Use case must list which Professional-account profile fields are needed and where they appear. Approvable for private apps. | S1, S6 |
| `instagram_manage_messages` | "allows business users to read and respond to Instagram Direct messages." Depends on `instagram_basic`, `pages_read_engagement`, `pages_show_list`. | Submission must include a **recording** of a message sent from the app — "not screenshots." Advanced Access required for professional accounts the app does not own or manage *(S6 + O2)*. **Not approvable for private apps** (S6). | S1, S6 |
| `instagram_manage_comments` | *(string listed)* | Approvable for private apps (S6) | S6 |
| `instagram_manage_insights` | *(string listed)*; maps to the Page **Insights** task | not captured | S6 |
| `instagram_content_publish` | *(string listed)*; maps to **Content** / **Full control** tasks | not captured | S6 |
| `pages_show_list`, `pages_read_engagement` | S6 lists both as part of this configuration's permission set | see §3.2 | S6 |
| Human Agent, Instagram Public Content Access *(features)* | — | App Review features | S6 |

Account requirement, both configurations: S6, "To use the APIs, your app users must have an Instagram
professional account." The Facebook-Login configuration additionally requires the account to be linked to a
Facebook Page (S7: "Requires an Instagram Business or Creator Account linked to a Facbook Page" — Meta's own
typo, reproduced).

**Lynomia uses both families, in different code paths.**

- Instagram Login path: `app/helpers/instagram/integration_helper.rb:2` —
  `REQUIRED_SCOPES = %w[instagram_business_basic instagram_business_manage_messages]`, with the OAuth authorize
  URL `https://www.instagram.com/oauth/authorize` and token URL `https://api.instagram.com/oauth/access_token`
  (`app/controllers/concerns/instagram_concern.rb:9-11`) and host `graph.instagram.com`
  (`app/models/channel/instagram.rb:82`). These two strings are the current, correct names (§4).
- Facebook Login path: `app/javascript/dashboard/helper/facebookScopes.js:10-13` —
  `INSTAGRAM_SCOPES = ['instagram_basic', 'instagram_manage_messages']`, appended to the four Page scopes.

**Finding (major).** On the Facebook Login path, S1 lists `pages_read_engagement` as a declared dependency of
`instagram_manage_messages`, and S6 lists `pages_read_engagement` in that configuration's permission set — but
`facebookScopes.js:1-8` deliberately omits it. The combined request Lynomia sends when
`includeInstagramScopes` is true is therefore missing a permission Meta declares as a dependency of one it does
request. S1 also lists `pages_read_user_content` as a dependency of `instagram_basic`, and that string is not
requested anywhere in the repository. Whether Meta enforces declared dependencies at authorization time, at
review time, or at call time is **not stated on any page I read** — so this is a flagged risk with a cited
dependency, not a proven runtime break. Agent 042 (Instagram integration) and Agent 090 should settle it
against observed behaviour.

### 3.4 What a missing permission actually looks like

S10 (Graph API) and S12 (WhatsApp Cloud API) are consistent. These are the codes; nothing here is invented.

| Code | Subcode | Meta's name / details | Meaning | Source |
|---|---|---|---|---|
| `OAuthException` | — | error `type` value | With no subcode: token expired, revoked or invalid — get a new one. With a subcode: check the subcode. | S10 |
| `102` | — | "API Session" | Same handling as OAuthException. | S10 |
| `3` | — | "API Method" / "Capability or permissions issue." | A capability or permission is missing; confirm the app has what the call needs. | S10, S12 |
| `10` | — | "API Permission Denied" / "Permission is either not granted or has been removed." | The permission was not granted or was removed. | S10, S12 |
| `190` | — | "Access token has expired" / "Your access token has expired." | Get a new access token. | S10, S12 |
| `200` | — | "API Permission"; WhatsApp: "No access token was provided. The API returns the message \"Provide valid app ID\"." Also returned when a system user lacks access to the resource or WABA (S13). | Permission or asset access missing. | S10, S12, S13 |
| `200`–`299` | — | "API Permission" / "Permission is either not granted or has been removed." | "The exact code depends on the permission." | S10, S12 |
| `131005` | — | "Permission is either not granted or has been removed." | WhatsApp "Other errors" table. | S12 |
| `0` | — | "We were unable to authenticate the app user." | WhatsApp authorization table. | S12 |
| — | `458` | "App Not Installed" | The user has not logged into the app; reauthenticate. | S10 |
| — | `459` | "User Checkpointed" | The user must log in on facebook.com to clear an issue. | S10 |
| — | `460` | "Password Changed" | Token invalidated by a password change. | S10 |
| — | `463` | "Expired" | Token expired, revoked or invalid. | S10 |
| — | `464` | "Unconfirmed User" | The user must log in on facebook.com. | S10 |
| — | `467` | "Invalid Access Token" | Token expired, revoked or invalid. | S10 |
| — | `492` | "Invalid Session" | **"The user tied to the Page access token lacks an appropriate Page role."** | S10 |

Subcode `492` is the one worth writing an article about: it is not a scope problem and no amount of re-granting
permissions fixes it. It means the Page role behind the token lost the required task (§2.4).

The error envelope fields, per S10: `message`, `type`, `code`, `error_subcode`, `error_user_title`,
`error_user_msg`, `fbtrace_id` — with the note that `fbtrace_id` "expires quickly." Lynomia already captures
`code`, `error_subcode`, `type`, `fbtrace_id` (`app/services/whatsapp/provider_error_log.rb:35`), which matches
the envelope exactly.

**Ambiguity, recorded.** No page I read states a distinct error code for "the app only has Standard Access and
the user has no app role." S2 describes the consequence (the permission cannot be requested; features are
inactive) without naming a code. Do not assert one.

## 4. Renames, splits and deprecations, with dates

| Change | Old string(s) | New string(s) | When | Source |
|---|---|---|---|---|
| Page permissions split into granular scopes | `manage_pages` | `pages_manage_ads`, `pages_manage_metadata`, `pages_read_engagement`, `pages_read_user_content` | Graph API v7.0, released 2020-05-05; already-approved apps migrated by 2020-06-01; old strings unselectable in App Review after 2020-06-01; "will be fully deprecated in May of 2022" | S5 |
| Publishing permissions split | `publish_pages` | `pages_manage_posts`, `pages_manage_engagement` | Graph API v7.0, same dates as above | S5 |
| Instagram Login permission family introduced | — | `instagram_business_basic`, `instagram_business_content_publish`, `instagram_business_manage_comments`, `instagram_business_manage_messages` | 2024-07-23, with the Instagram API with Instagram Login | S8 |
| Short-form Instagram Login scopes renamed | `business_basic`, `business_content_publish`, `business_manage_comments`, `business_manage_messages` | the four `instagram_business_*` strings above | Renamed 2024-09-17; **old values deprecated 2025-01-27** (a correction of an earlier 2024-12-17 date). S8 warns apps that do not update "risk being unable to call Instagram endpoints." | S8 |
| Instagram Basic Display API deprecated | *(whole API)* | migrate to the Instagram API | 2024-12-04; requests return an error | S8 |
| New Instagram permission for deleting media | — | `instagram_manage_contents` | 2025-12-03 | S8 |
| Collaboration-invite endpoints require a permission | — | `instagram_basic` | 2025-12-03 | S8 |
| New Instagram permission for liking/unliking | — | `instagram_manage_engagement` | 2026-04-22 | S8 |
| Webhook field requirement moved | `instagram_manage_comments` | `instagram_manage_insights` (for the `story_insights` webhook field) | 2019-05-09 | S8 |

**What is NOT deprecated, stated so nobody assumes it.** S8 contains **no** entry saying `instagram_basic`,
`instagram_manage_messages` or `instagram_manage_comments` is deprecated, legacy or replaced, and S6 still lists
all three as the live permission set for the Facebook-Login configuration. The two Instagram families coexist.
S1 lists both families side by side. Anyone writing "`instagram_basic` is deprecated" would be wrong as of
2026-10-13.

**What I could not source.** `read_page_mailboxes` — the pre-v7 Page-inbox permission that `pages_messaging`
superseded — is **not mentioned** in S5 and I did not find a normative page naming its replacement. Recorded as
a gap, not filled by memory.

S4 (v23.0) and S3 contain **no** permission-rename entries at all: S3 is an index that does not inline version
contents, and S4's deprecations are advertising fields (`smart_promotion_type`, `instagram_actor_id`,
`is_sac_cfca_terms_certified`, `is_eligible_for_sac_campaigns`) with no messaging relevance. An agent looking
for permission changes in the Graph API changelog will not find them there; permission churn for this product
lives in the **Instagram Platform changelog** (S8) and the **permissions reference** (S1).

## 5. Version and deprecation notes

S3 gives the live version table. As of 2026-10-13 the **current Graph API version is v26.0, introduced
2026-07-29, "Available Until" TBD.**

| Version | Introduced | Available until |
|---|---|---|
| v26.0 | 2026-07-29 | TBD |
| v25.0 | 2026-02-18 | 2028-07-29 |
| v24.0 | 2025-10-08 | 2028-02-18 |
| v23.0 | 2025-05-29 | 2027-10-08 |
| v22.0 | 2025-01-21 | 2027-05-20 |
| v21.0 | 2024-10-02 | 2027-01-21 |
| v20.0 | 2024-05-21 | 2026-09-24 |
| v19.0 | 2024-01-23 | 2026-05-21 |
| v18.0 | 2023-09-12 | **2026-01-26** |
| v17.0 | 2023-05-23 | 2025-09-12 |
| v16.0 | 2023-02-02 | 2025-05-14 |

**Finding (blocker-class, outside my scope to fix).** `app/controllers/dashboard_controller.rb:85` defaults
`FACEBOOK_API_VERSION` to `'v18.0'`. Per S3, v18.0's availability ended **2026-01-26** — roughly nine months
before today. Any installation that has not overridden `FACEBOOK_API_VERSION` is calling a version past its
stated availability. v20.0 (2026-09-24) has also now passed. By contrast
`app/models/channel/instagram.rb:28` defaults to `v22.0` (available until 2027-05-20) and
`app/services/whatsapp/health_service.rb:18` floors WhatsApp health calls at `v24.0` (2028-02-18) — both inside
their windows. Agent 091 (stale API guidance) should own this; I am recording it because it changes what any
permissions article can honestly tell a reader about where to look in the App Dashboard.

## 6. Ambiguities and gaps in Meta's own documentation

1. **`business_management` as a dependency.** S1's dependency table does not list it for `pages_messaging`;
   S9 says it is a dependency for `pages_messaging`, `pages_show_list` and `instagram_manage_messages`. Two
   normative pages, opposite answers. Unresolved.
2. **S1's `pages_messaging` review text looks like an editing error** — the use-case guidance reads as a copy of
   the `pages_manage_ads` text while the screencast guidance is correctly about Messenger. Flagged as an apparent
   documentation defect on Meta's side, not a product finding.
3. **No error code for the Standard-Access-plus-no-role case** (§3.4). S2 describes the behaviour, names no code.
4. **No page enumerates endpoints per permission.** S11 explicitly defers to separate pages and names no
   permission; S6 and S9 list permission strings without per-endpoint mapping. Every endpoint cell marked
   `(inference)` in §3 is mine, derived from the permission's own description plus Lynomia's call sites. A
   documentation claim of the form "endpoint X requires permission Y" is not currently backed by a single Meta
   page for most X.
5. **Whether declared dependencies are enforced, and where.** S1 declares dependencies but no page I read states
   whether omitting one fails at authorization, at review, or at call time. This is the crux of the
   `pages_read_engagement` question in §3.3.
6. **Advanced Access requirement for `whatsapp_business_management`.** The specific claim that acting on WABAs
   the app's business does not own requires Advanced Access, and that calls otherwise return error `200`, reached
   me only through O1 (search snippets attributed to the Solution Partner docs). S13 independently confirms the
   error-`200`-for-missing-asset-access half, normatively. The Advanced-Access half is
   **observational, unconfirmed** — one fetch of the Solution Partner overview would settle it.
7. **S1's descriptions for `instagram_business_manage_comments`, `instagram_business_content_publish`,
   `instagram_manage_comments`, `instagram_manage_insights` and `instagram_content_publish`** were not captured
   in my reads; the strings are confirmed by S6, the grant wording is not. Marked not captured, not guessed.
8. **No normative replacement named for `read_page_mailboxes`** (§4).

## 7. What Lynomia users would ask

These are the questions this area generates for a support desk, in the order they actually arrive. Each one is a
candidate article; none is currently answerable from the corpus by a stuck administrator.

| The question as a user asks it | What it really is | What the answer rests on |
|---|---|---|
| "It worked for me but no customer can connect their Page." | Standard vs Advanced Access | §2.1, S2 |
| "I ticked every permission and sending still fails." | Page role lacks the `MESSAGING`/`MODERATE` task | §2.4, subcode `492`, S9/S10 |
| "The connect screen doesn't show the WhatsApp permission at all." | Advanced Access not approved, so the scope is absent from Embedded Signup | §2.6, S14 |
| "Templates don't load but messages send." | token has `whatsapp_business_messaging` without `whatsapp_business_management` | §3.1, `manual_setup_validation_service.rb:65-70` |
| "Messages send but nothing arrives in the inbox." | `pages_manage_metadata` missing, so the app was never subscribed to the Page | §3.2 |
| "Which Instagram permissions do I need?" | depends entirely on which of the two configurations the install uses | §3.3 |
| "Our integration broke and we changed nothing." | 90-day disuse regrant, or token expiry (`190`, subcodes `463`/`467`) | §2.2, §3.4 |
| "What does error 200 mean?" | permission **or** business asset access — two different fixes behind one code | §3.4, S12/S13 |
| "Our Meta app is private — can we do Instagram DMs?" | no: `instagram_manage_messages` is not approvable for private apps | §2.7, S6 |
| "Can an agent reply four days later?" | Human Agent feature, 7-day window, separate from scopes | §2.8, S6 |

A documentation set that answers "which scope string do I need" and stops there answers the least common of
these ten. The failure modes are overwhelmingly about **access level, Page task and asset access** — three
things that are not scopes.
