---
agent: 023
scope: Instagram Messaging prerequisites — account types, Facebook Page requirement, the two integration paths and their permissions, the Connected Tools / "Allow Access to Messages" switch, linking and unlinking, and messaging deprecations
confidence: medium
sources_normative: 9          # S1-S9, fully normative doc pages
sources_observational: 5     # S10-S11 changelogs (disputed, see §1 note), S12-S13 bodies unreadable, S14 search summaries
---

# Agent 023 — Instagram messaging prerequisites and setup

Everything below answers one question: **what must already be true before Lynomia can read a single Instagram
message?** Runtime send failures, restrictions and story/mention semantics belong to Agent 024; business
verification and Tech Provider status belong to Agent 027; Page tokens and Page roles in general belong to
Agent 021.

Date checked for every row: **2026-10-13**. All fetches were read-only. No Graph endpoint was called, no
credential was used, no form was submitted.

## 1. Source register

| # | Source URL | Page title | Product | API / version context | Date checked | Type |
|---|---|---|---|---|---|---|
| S1 | https://developers.facebook.com/docs/instagram-platform | Instagram Platform | Instagram Platform | none stated | 2026-10-13 | normative |
| S2 | https://developers.facebook.com/docs/instagram-platform/overview | Overview | Instagram Platform | none stated | 2026-10-13 | normative |
| S3 | https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login | Instagram API with Instagram Login | Instagram Platform | none stated; scope-deprecation date 2025-01-27 | 2026-10-13 | normative |
| S4 | https://developers.facebook.com/docs/instagram-platform/instagram-api-with-facebook-login | Instagram API with Facebook Login | Instagram Platform | none stated | 2026-10-13 | normative |
| S5 | https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/messaging-api/ | Send Messages | Instagram Platform (Instagram Login) | none stated | 2026-10-13 | normative |
| S6 | https://developers.facebook.com/docs/messenger-platform/instagram/get-started | Getting Started | Messenger Platform → Instagram | Facebook Login Use Case; no version stated | 2026-10-13 | normative |
| S7 | https://developers.facebook.com/docs/messenger-platform/instagram | Instagram Messaging | Messenger Platform | landing page, no requirements | 2026-10-13 | normative (thin) |
| S8 | https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/business-login | Business Login for Instagram | Instagram Platform | `https://www.instagram.com/oauth/authorize` | 2026-10-13 | normative |
| S9 | https://developers.facebook.com/docs/instagram-platform/app-review | App Review for Instagram API | Instagram Platform | none stated | 2026-10-13 | normative |
| S10 | https://developers.facebook.com/docs/instagram-platform/changelog | Changelog | Instagram Platform | entries marked "all versions" where stated | 2026-10-13 | normative source, changelog (see note) |
| S11 | https://developers.facebook.com/docs/messenger-platform/changelog | Changelog | Messenger Platform | follows Graph API versioning; page lists v26.0 as latest | 2026-10-13 | normative source, changelog (see note) |
| S12 | https://www.facebook.com/business/help/898752960195806 | Connect or disconnect your professional Instagram account and a Facebook Page \| Meta Business Help Center | Business Help | n/a | 2026-10-13 | normative source, **body not retrievable** |
| S13 | https://help.instagram.com/502981923235522 | Help Center (article body not served) | Instagram Help | n/a | 2026-10-13 | **body not retrievable**; domain not in the charter's normative list |
| S14 | WebSearch result summaries (Page-linking steps, "Allow access to Instagram messages in Inbox") | — | — | n/a | 2026-10-13 | observational, unconfirmed |

**Note on changelogs.** Program charter §6.2 lists Meta's changelog pages among the normative domains *and*
gives "a changelog" as an example of observational evidence. Rows S10 and S11 are therefore marked
"normative source, changelog": the publisher is Meta, the genre is a change record. Agent 000 must decide which
reading governs — see §6, Blocker B1.

**Note on S12/S13.** Both Meta help-centre URLs returned only a page title; the article bodies are
client-rendered and were not served to a plain fetch. The title of S12 is itself evidence that Meta documents
connect **and disconnect** as one flow, but no step, toggle name or consequence from those articles is quoted
below as normative. The linking-flow details in §2.5 come from S14 and are marked unconfirmed.

## 2. The rules

### 2.1 Which Instagram accounts can be messaged via API

Every path requires an **Instagram professional account**, which Meta defines as a **business or creator**
account (S2: "An Instagram professional account can be for a business or creator"; S3; S5). There is no third
professional flavour and no "messaging-only" account type.

A **personal (consumer) Instagram account cannot be used at all.** S4 states the API "cannot access consumer
(non-Business, non-Creator) accounts". Concretely, for a personal account: no messaging permission can be
granted, no Instagram User access token can be issued for it, no Instagram messaging webhook can fire for it,
and under the Facebook-Login path it is not exposed as a linkable asset of a Page. The account must be
converted to professional first; conversion is the business's own action inside Instagram and is not something a
third-party inbox can do for them.

One account-type nuance Meta does state, though it is publishing rather than messaging: content publishing is
available to all professional accounts, but **Stories publishing is limited to Business accounts** (S4). For
messaging there is no documented business-vs-creator split today: the Messenger Platform changelog records that
on **2023-06-20** Instagram messaging became available for *any* Instagram professional account, business or
creator (S11), superseding the 2021 rollout that had restricted Creator accounts to fewer than 500,000
followers (S11).

### 2.2 Is a linked Facebook Page required? — No, not since the Instagram-Login path

As of 2026-10-13 a linked Facebook Page is **required for one path and not required for the other**. This is the
single most important correction to any older Lynomia or Chatwoot documentation, which predates the change.

| | Path A — Instagram API with Instagram Login (a.k.a. Business Login for Instagram) | Path B — Instagram API with Facebook Login for Business / Messenger Platform Instagram messaging |
|---|---|---|
| Linked Facebook Page | **Not required.** S3 states the setup "does not require a Facebook Page linked to the Instagram professional account" | **Required.** S2: accounts "must be connected to a Facebook Page"; S6 "Before you start": "A Facebook Page connected to that account" |
| Who logs in | Instagram credentials (S2) | Facebook credentials (S2) |
| Token type | Instagram User access token (S2, S5) | Facebook User or Page access token (S2) |
| Host | `graph.instagram.com` (S2, S11) | `graph.facebook.com` (S2) |
| Messaging permissions | `instagram_business_basic`, `instagram_business_manage_messages` (S5, S8) | `instagram_basic`, `instagram_manage_messages`, `pages_manage_metadata` (S6) |
| Page role needed | none | a Meta Developer account that "can perform the MODERATE task on that Page" (S6); S2 additionally describes admin-equivalent task capability, and maps the Page "Messages" task (`PROFILE_PLUS_MESSAGING`) to `instagram_manage_messages` |
| Features not available | hashtag search, product tagging, Partnership Ads (S2) | — |
| Messaging surface | "Native Instagram messaging API" (S2) | "Messenger Platform Instagram Messaging API" (S2) |

The Messenger Platform changelog entries of **2025-12-19** and **2026-03-13** state the current division plainly:
Instagram messaging is split across two APIs — the Facebook Graph API for accounts linked with a Facebook Page,
and the Instagram API for Instagram-only accounts (S11). S6 routes businesses explicitly: an account without a
linked Page should use the Instagram API with Instagram Login instead.

Lynomia is on **Path A**: `app/controllers/api/v1/accounts/instagram/authorizations_controller.rb:10-12` sends
`scope=instagram_business_basic,instagram_business_manage_messages` (from
`app/helpers/instagram/integration_helper.rb:2`) with `enable_fb_login: '0'` and `force_reauth: 'true'`. Both
scope strings and both parameter names are documented exactly as the code spells them (S8). So Lynomia's
Instagram onboarding must **not** tell a business to link or create a Facebook Page — that requirement belongs
only to the Facebook/Messenger inbox. A separate IG-over-Page code path also exists in the repository
(`Instagram::Messenger::SendOnInstagramService`, per `docs/documentation-v2/discovery/042-instagram.md`), which
is Path B; Agent 042 owns its live/dead status.

### 2.3 The authorization request (Path A)

S8 documents the authorize request to `https://www.instagram.com/oauth/authorize` with parameters `client_id`
(Instagram App ID), `redirect_uri` (must exactly match a valid OAuth redirect URI in app settings),
`response_type=code`, `scope`, `state` (optional, e.g. CSRF token, echoed back), `enable_fb_login` (optional
boolean, default `true`, shows or hides the Facebook Login option on the Instagram login page) and `force_reauth`
(optional boolean; when true the user must log in with Instagram professional-account credentials even if
already logged into Instagram). The login page itself appears only if the user is not already logged in or if
`force_reauth` is passed (S8) — which is why Lynomia's `force_reauth: 'true'` matters for a business whose
browser is signed into the wrong Instagram account, and is a documentable onboarding tip.

### 2.4 The Connected Tools / "Allow Access to Messages" switch

This is the prerequisite that lives inside the Instagram app rather than in any developer console, and Meta
documents it in exactly one place among the pages fetched. S6 (Messenger Platform → Instagram → Getting Started)
states, in Meta's words:

- "In order to manage Instagram messages via API, Instagram professional accounts will need to enable" … "the
  connected tools toggle under message controls settings."
- Path: **"Instagram Settings > Messages and story replies > Message controls > Connected Tools > toggle Allow
  Access to Messages"** (S6).

Three things must be said about this with no softening.

1. **Meta does not state what happens when it is off.** S6 gives the requirement and the path and stops. No
   fetched page names an error code, an empty-webhook behaviour, a failed subscription or a UI symptom for the
   off state. Any Lynomia article must therefore describe the symptom from Lynomia's own observed behaviour
   (Agent 042/024 territory) and cite Meta only for the requirement and the path.
2. **Meta documents it only on the Facebook-Login/Messenger page.** The Instagram-Login messaging page (S5),
   the Instagram-Login landing page (S3), the Business Login page (S8) and the Overview (S2) do not mention
   Connected Tools or "Allow Access to Messages" at all. Whether the toggle gates Path A — Lynomia's path — is
   **not stated anywhere I fetched**. Recorded as ambiguity A1 in §6; it must not be asserted either way.
3. The navigation path is Meta's wording for a mobile app that reorganises its settings regularly. An article
   should quote Meta's path and add "the exact labels move between Instagram app versions" rather than
   presenting the breadcrumb as permanent truth.

Separately, S2 names a **developer-side** switch that is easy to confuse with the business-side one: for
Facebook-Login apps the developer must enable "Messenger, including Instagram settings for sending and receiving
messages" in the App Dashboard (S2). That is Lynomia's own app configuration, not the customer's.

### 2.5 Account linking and unlinking

The normative Business Help article for this is S12, titled "Connect or disconnect your professional Instagram
account and a Facebook Page" — the title confirms Meta treats connect and disconnect as one documented flow, but
the body was not served to a read-only fetch, so no step is quoted here as normative.

From developer documentation, what *is* normative: under Path B the Instagram professional account must be
connected to a Facebook Page (S2, S6) and the person authorising must be able to perform the `MODERATE` task on
that Page (S6); Page tasks map to grantable permissions, with the Messages task (`PROFILE_PLUS_MESSAGING`)
granting `instagram_manage_messages` (S2). It follows directly that unlinking the Page, or losing the Messages
task, removes the basis on which `instagram_manage_messages` was granted — but **no fetched page states the
runtime consequence of unlinking** (token invalidation, webhook stoppage, error code). Ambiguity A2.

**Observational, unconfirmed (S14, search summaries only — the article bodies were not retrievable).** The
Page-linking flow is said to be performed by a Page admin, from the Page's settings or the Linked accounts
section of the professional dashboard, to require the Instagram account to be professional (a personal account
is prompted to convert during linking), and to present a toggle worded **"Allow access to Instagram messages in
Inbox"** which must be on. If that toggle is real it is a *third* message-access control, distinct from the
in-app Connected Tools toggle and from the App Dashboard setting, and it would matter for any Lynomia customer
who is also using Meta Business Suite Inbox. **Do not publish this without confirmation** — it needs a human to
open S12 in a browser, or an authenticated Business Help fetch, neither of which this agent may do.

### 2.6 What the business sees in Instagram when a third-party inbox is connected

S5 is normative and specific, and it is the basis for the most likely "Lynomia is broken" support ticket:

- "Webhooks notifications or messages delivered via the API will not be considered as Read in the Instagram app
  inbox." (S5)
- "Only after a reply is sent will a message be considered Read." (S5)

So a business watching the Instagram app while Lynomia pulls messages sees **unread** conversations and unread
badges, even though an agent is reading them in Lynomia. That is Meta's documented design, not a Lynomia defect.

Folders, per S5: new conversations from **followers** appear in **Primary**; new conversations from users who are
**not followers** appear in **Requests**; a conversation moves to **General** once the app user replies through
the app — "regardless of the inbox settings". And the API itself is folder-blind: "Inbox folders are not
supported", so folder information does not reach the connected tool. A Lynomia article should therefore not
promise folder parity, and should warn that answering a message request from Lynomia moves that thread to
General inside Instagram.

S5 also notes that the Instagram inbox is where a user organises messages and controls message notifications;
S2 adds that message notifications are off by default under Inbox Settings. Neither page makes notifications a
prerequisite for the API.

### 2.7 Access level, App Review and app testers

Before a real customer's messages can be read, Lynomia's Meta app needs the right access level:

- **Advanced Access** is required if the app serves Instagram professional accounts the app does not own or
  manage; **Standard Access** suffices for accounts the developer owns or manages, or that have been added in
  the App Dashboard, and "some features may not work until Advanced Access is granted" (S5).
- Both messaging permissions are Advanced-Access permissions: `instagram_manage_messages` (Facebook Login) and
  `instagram_business_manage_messages` (Instagram Login), with "Human Agent" listed under both login types (S9).
- "Your app must complete App Review before it can request permissions with Advanced Access from any app user."
  (S9) Migrated apps may be granted Advanced Access automatically for the corresponding permission (S9).
- S9 does **not** mention business verification. Search summaries claim the Messenger route requires an app
  owned by a verified business — observational, unconfirmed (S14); Agent 027 owns that question.
- App testers must have a role on the app, be granted the required permissions, **and have a role on the
  Instagram professional account that owns the app** (S5) — the last clause is the one that breaks internal
  testing.

### 2.8 Webhooks and the conversation-start rule

Path A subscriptions, exactly as S5 lists them: `messages`, `messaging_optins`, `messaging_postbacks`,
`messaging_reactions`, `messaging_referrals`, `messaging_seen`. S11 adds `message_edit`, introduced
**2025-09-10** for both Business Login for Instagram and Facebook Login for Business. Path B additionally
requires the Instagram topic webhooks to be subscribed (S6).

Two rules make "read a message" conditional on the end user acting first: the app "can only message a user after
that user has sent a message to your app user", after which the app has 24 hours to respond (S5); and the app
user must own any media or posts the app sends (S5).

## 3. Error codes and failures

Prerequisite failures are almost entirely undocumented as codes. Only one numeric code appears in any source I
fetched, and it is a feature-gating code rather than a setup code.

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Source |
|---|---|---|---|---|---|---|
| `2534068` | not stated | not stated | Returned to accounts not yet enabled for sending multiple images in Instagram Direct (beta from 2025-11-03) | wait for enablement; the feature left beta 2026-05-06 and is available to all accounts | not stated | S10 |

Everything else is **not stated**: there is no documented code for Connected Tools being off, for a personal
account, for an unlinked Page, for a missing `MODERATE` task, for a revoked messaging permission, or for a
missing webhook subscription. No code is invented here. Agent 024 should be asked to hunt Instagram runtime
error families, and Agent 025 for the `OAuthException` families that a missing permission actually produces.

## 4. Limits and numbers

| Number | What it governs | Source |
|---|---|---|
| 24 hours | "Your app has 24 hours to respond to any message sent from an Instagram user to your app user"; the human-agent tag allows a response outside the window | S5 |
| 500,000 followers | historical 2021 Creator-account rollout ceiling, **superseded** by the 2023-06-20 opening to any professional account | S11 |
| 4 | documented Business Login scope values (`instagram_business_basic`, `instagram_business_content_publish`, `instagram_business_manage_messages`, `instagram_business_manage_comments`) | S3, S8 |
| 6 (+1) | Path A messaging webhook fields in S5, plus `message_edit` from 2025-09-10 | S5, S11 |

No other numeric limit relevant to prerequisites is stated on any page fetched. Rate limits, send limits and
media sizes were out of scope and are not guessed.

## 5. Version and deprecation notes

| Date | Version context | What changed | Source |
|---|---|---|---|
| 2024-06-23 / 2024-07-23 | not stated | Instagram API with Instagram Login launched: no Facebook Page required, host `graph.instagram.com`, new `instagram_business_*` permissions; "The Messenger API will no longer be used to send Instagram messages". **The two changelogs date this launch differently** — S11 says 2024-06-23, S10 says 2024-07-23 | S10, S11 |
| 2024-09-17 | all versions | Scope values `business_basic`, `business_content_publish`, `business_manage_comments`, `business_manage_messages` **replaced** by `instagram_business_basic`, `instagram_business_content_publish`, `instagram_business_manage_comments`, `instagram_business_manage_messages`; apps not updated would be "unable to call the Instagram endpoints" | S10 |
| 2025-01-27 | all versions | Effective deprecation date for those old scope values (moved from 2024-12-17 by a later correction); also restated on S3 | S10, S3 |
| 2024-12-04 | all versions | **Instagram Basic Display API deprecated**; all its requests now return an error; migrate to the Instagram API | S10 |
| 2025-06-14 | not stated | `enable_fb_login` and `force_authentication` deprecated for Business Login for Instagram | S10 |
| 2026-02-06 | not stated | `enable_fb_login` supported again in Instagram OAuth requests; defaults to `true`; controls whether the Facebook Login option appears on the Instagram login page | S10 |
| 2025-10-23 | not stated | **Handover Protocol retired for Instagram** — "Meta no longer supports the Handover Protocol for Instagram"; businesses moved to Conversation Routing, described as mostly backward compatible | S11 |
| 2025-10-30 → 2026-04-27 | not stated | Post-share webhook `share` attachment deprecated in favour of `ig_post` (media ID, URL, title). Both were sent from 2025-11-03; original removal date 2026-02-01; removal "rolling out gradually" as of 2026-04-27 | S11 |
| 2021-09-14 | not stated | Conversations API stopped returning `IGID` and relies fully on `IGSID` (migration due 2021-12-14) | S11 |
| 2021-09-14 | not stated | Emoji reaction webhooks moved to a new unicode format allowing multiple reactions (migrate before 2021-12-14) | S11 |
| 2021-08-06 | not stated | Private Reply API calls with the Human Agent tag stopped working after 2021-09-13 | S11 |
| 2021-06-08 | Graph API v11.0+ | `mid` added to `messaging_postback` events for Messenger and the Messenger API for Instagram | S11 |
| — | Messenger Platform follows Graph API versioning; S11 lists **v26.0** as latest | version floor for Path B | S11 |

**Nothing retires `instagram_manage_messages`.** Neither changelog mentions that permission by name, and S11
gives **no retirement date for the Messenger API for Instagram itself** (S10, S11) — while the 2024 launch entry
says the Messenger API "will no longer be used to send Instagram messages". Those two statements sit in tension;
see ambiguity A3.

**Direct relevance to Lynomia's code.** The 2025-06-14 entry names `force_authentication` as deprecated, but the
live Business Login page (S8) documents `force_reauth`, not `force_authentication`, and documents
`enable_fb_login` as current with default `true`. Lynomia sends `enable_fb_login: '0'` and `force_reauth: 'true'`
(`app/controllers/api/v1/accounts/instagram/authorizations_controller.rb:11-12`), which matches S8 as of today.
The naming mismatch between S10 and S8 is Meta's, not Lynomia's, and is recorded as ambiguity A4 rather than
resolved.

## 6. Ambiguities and gaps

- **A1 — Does the Connected Tools / "Allow Access to Messages" toggle gate the Instagram-Login path?** Meta
  documents it only on the Facebook-Login/Messenger Getting Started page (S6). S2, S3, S5 and S8 never mention
  it. Lynomia uses the Instagram-Login path, so the most operationally important prerequisite in this whole
  report is documented only for the path Lynomia does *not* use. Unresolved; needs product-observed evidence
  from Agent 042, not a guess.
- **A2 — What happens when Connected Tools is off, or when the Page is unlinked?** No fetched page states a
  symptom, error code or timing. Not stated.
- **A3 — Is the Messenger API for Instagram deprecated?** S10's 2024 entry says the Messenger API "will no
  longer be used to send Instagram messages", yet S6 still documents the Facebook-Login/Messenger path as
  current with live permissions, S9 still lists `instagram_manage_messages` as reviewable, and S11 gives it no
  retirement date. Meta is ambiguous. Record both, retire neither.
- **A4 — `force_authentication` vs `force_reauth`**, and `enable_fb_login` deprecated 2025-06-14 then
  re-supported 2026-02-06 (S10) while S8 documents it as current. Parameter naming across changelog and
  reference page does not agree.
- **A5 — Launch date of the Instagram-Login API** differs between the two changelogs (2024-06-23 vs 2024-07-23).
- **A6 — Business verification** for Instagram messaging: absent from S9; only an unconfirmed search summary
  claims it. Hand to Agent 027.
- **A7 — Meta help-centre bodies (S12, S13) are not readable by a plain fetch.** Linking and unlinking steps,
  the "Allow access to Instagram messages in Inbox" toggle, and the personal→professional conversion steps are
  consequently unverified. A human must open S12 and S13 in a browser before any Lynomia article states them.
- **A8 — Creator vs business messaging differences** beyond Stories publishing: not stated anywhere fetched.

**Blocker B1 (for Agent 000).** Charter §6.2 classifies Meta changelogs as normative domains in one sentence and
as observational evidence in another. Six of this report's deprecation facts exist only in a changelog. Agent
000 must rule on how a changelog-only fact is cited in published documentation before Phase 5 writers reuse
these rows.

## 7. What Lynomia users would ask

Lynomia has an Instagram integration and **zero** documentation articles for it, so every question below is
currently unanswerable from the corpus.

| The question a business asks | What the answer rests on |
|---|---|
| "Why can't I connect my Instagram account?" — it is personal, not professional | §2.1 (S2, S4) |
| "Do I need a Facebook Page for Instagram?" — not on Lynomia's path | §2.2 (S3, S2, S6) |
| "Which Instagram permissions is Lynomia asking for and why?" | §2.2, §2.3 (S5, S8) |
| "I connected Instagram but no messages arrive." — Connected Tools / Allow Access to Messages, plus access level and webhook subscriptions | §2.4, §2.7, §2.8 (S6, S5, S9) |
| "Instagram still shows my messages as unread while my agents reply in Lynomia." | §2.6 (S5) — Meta's documented behaviour |
| "A message request I answered in Lynomia vanished from Requests." — it moved to General | §2.6 (S5) |
| "Why can't we message a customer first?" — the user must message you, then 24 hours | §2.8 (S5) |
| "The Instagram login screen signed me into the wrong account." — `force_reauth` and the Facebook Login option | §2.3 (S8) |
| "We unlinked / relinked our Facebook Page and Instagram broke." | §2.5 — partly unanswerable (A2) |
| "Our agency manages this account — who has to authorise?" | §2.2 Page tasks, §2.7 app testers (S2, S6, S5) |
| "Why did our Instagram handover/routing integration change?" | §5, Handover Protocol retired 2025-10-23 (S11) |
