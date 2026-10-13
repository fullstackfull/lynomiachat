---
agent: 090
scope: Refute Facebook / Messenger / Instagram claims — Graph version pins, the Messenger window and HUMAN_AGENT, message tag semantics, Instagram account-type and Page-link requirements, permission currency, handover protocol, and the "two Instagram paths are the same" claim
confidence: high
sources_normative: 21
sources_observational: 3
---

## 0. Source register

Every Meta claim below references a row here. All checked **2026-10-13**. Product column: GA = Graph API,
MP = Messenger Platform, IG = Instagram Platform, BH = Business Help / policy.

| # | URL | Page title | Product | Version context | Normative? |
|---|---|---|---|---|---|
| S1 | `https://developers.facebook.com/docs/graph-api/guides/versioning` | Versioning — Graph API | GA | names v26.0 as latest | normative |
| S2 | `https://developers.facebook.com/docs/graph-api/changelog/versions` | Versions — Graph API | GA | full version table | normative |
| S3 | `https://developers.facebook.com/docs/graph-api/changelog/version26.0/` | Graph API and Marketing API v26.0 Changelog | GA | v26.0 | normative |
| S4 | `https://developers.facebook.com/documentation/business-messaging/messenger-platform/send-messages` | Send a message — Messenger Platform | MP | examples v25.0 | normative |
| S5 | `https://developers.facebook.com/docs/messenger-platform/send-messages` | Send Messages — Messenger Platform | MP | examples v25.0 | normative |
| S6 | `https://developers.facebook.com/docs/features-reference/human-agent/` | Human Agent — Features Reference | MP/IG | none stated | normative |
| S7 | `https://developers.facebook.com/documentation/business-messaging/messenger-platform/policy` | Messenger Platform and IG Messaging API policy | BH | none stated | normative |
| S8 | `https://developers.facebook.com/docs/instagram-platform/overview` | Overview of the Instagram API | IG | none stated | normative |
| S9 | `https://developers.facebook.com/docs/instagram-platform/changelog` | Changelog — Instagram Platform | IG | dated entries | normative |
| S10 | `https://developers.facebook.com/docs/instagram-platform/webhooks` | Webhooks — Instagram Platform | IG | examples v25.0 | normative |
| S11 | `https://developers.facebook.com/documentation/instagram-platform/instagram-api-with-instagram-login/messaging-api` | Send Messages — Instagram API with Instagram Login | IG | examples v25.0 | normative |
| S12 | `https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/business-login` | Business Login for Instagram | IG | none stated | normative |
| S13 | `https://developers.facebook.com/docs/permissions` | Permissions Reference | GA | current | normative |
| S14 | `https://developers.facebook.com/docs/graph-api/reference/page/subscribed_apps/` | Page Subscribed Apps | GA | v26.0 | normative |
| S15 | `https://developers.facebook.com/docs/graph-api/guides/error-handling` | Handling Errors — Graph API | GA | none stated | normative |
| S16 | `https://developers.facebook.com/docs/marketing-api/error-reference/` | Marketing API error codes | GA | none stated | normative |
| S17 | `https://developers.facebook.com/docs/graph-api/webhooks/reference/page/` | Page Webhooks Reference | GA | none stated | normative |
| S18 | `https://developers.facebook.com/docs/messenger-platform/reference/webhook-events/standby/` | standby — Messenger Platform | MP | none stated | normative |
| S19 | `https://developers.facebook.com/docs/messenger-platform/changelog/` | Changelog — Messenger Platform | MP | dated entries | normative |
| S20 | `https://developers.facebook.com/docs/graph-api/securing-requests` | Securing Graph API Requests | GA | none stated | normative |
| S21 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/support/error-codes` | WhatsApp error codes | GA/WA | none stated | normative |
| O1 | S19, 2021–2022 entries | Messenger Platform changelog, handover entries | MP | 2021 | observational — the page confirms these entries exist in 2021–2022 but I did not read their text directly |
| O2 | `https://developers.facebook.com/success-stories/klm/` | KLM success story | BH | none | observational — names a 21-day human-agent window for one customer; not a general rule |
| O3 | `https://developers.facebook.com/docs/apps/versions` | Versioning — App Development | GA | stale | observational — still names v3.2 as "the latest Graph API version"; superseded by S2 |

Meta has also moved much Messenger and Instagram documentation from `/docs/...` to
`/documentation/business-messaging/...`. Both paths serve content today and they are not identical (S4 vs S5).
Any corpus article that cites a Meta URL must cite the `/documentation/...` form or it will rot.

---

## 1. What you attacked

Reports **021–025 do not exist**. The discovery directory at the time of this audit holds 002, 003, 004, 006,
008, 009, 010, 012, 013, 014 from the Meta block — and nothing from 021–028. There was no Facebook Pages
report, no Messenger Platform report, no Instagram Messaging report, no Instagram runtime report and no Graph
`OAuthException` report to attack. Nothing in this report refutes 021–025; it pre-empts them, which is what the
brief asked for.

What existed and was attacked:

- `docs/documentation-v2/discovery/041-facebook-messenger.md` (323 lines) — in full.
- `docs/documentation-v2/discovery/042-instagram.md` (468 lines) — in full.
- `docs/documentation-v2/discovery/003-permissions-scopes.md:235-265` — the Facebook/Instagram scope section and
  the dependency finding it explicitly routed to this agent.
- `docs/documentation-v2/discovery/_ARBITRATION.md:135-136` — the three questions routed to 021/023/024/025,
  which this report settles instead.
- The four corpus files that mention these channels: `custom/db/documentation/en/getting-started/connect-your-first-channel.md`,
  `custom/db/documentation/en/workspace/set-up-an-inbox.md`, its Arabic counterpart
  `custom/db/documentation/ar/workspace/set-up-an-inbox.md`, and
  `custom/db/documentation/en/whatsapp/the-whatsapp-24-hour-window.md`.
- The code both reports rest on, re-read at this HEAD rather than taken from the reports:
  `app/services/conversations/message_window_service.rb`, `app/models/channel/instagram.rb`,
  `app/services/instagram/send_on_instagram_service.rb`,
  `app/services/instagram/messenger/send_on_instagram_service.rb`,
  `app/services/instagram/base_send_service.rb`, `app/services/facebook/send_on_facebook_service.rb`,
  `app/jobs/send_reply_job.rb`, `config/installation_config.yml:135-167`, and the vendored gem at
  `vendor/bundle/ruby/3.4.0/gems/facebook-messenger-2.0.1/lib/facebook/messenger/{bot,subscriptions}.rb`.

The targets the brief named: the Messenger window and the HUMAN_AGENT extension; message tag semantics;
Instagram account-type and Page-link requirements as of today; permission currency; handover protocol; and the
claim that the two Instagram paths behave alike.

---

## 2. Refutations

### R1 — "v3.2 and v11.0 are a retirement risk." They are not a risk. They are already gone, and the calls did not fail. **blocker**

**The claim.** `041:40-41` records Messenger send and Page subscribe as pinned to **v3.2** in the vendored gem,
`042:20` records the legacy Instagram send path on **v11.0**, and both frame the consequence as prospective:
"a Graph retirement surfaces only as messages marked failed" (`041:218-220`, citing
`docs/p7/07-graph-api-versions.md:72-85`). `app/services/instagram/messenger/send_on_instagram_service.rb:5-8`
states the same theory in a code comment — the version is made configurable "so that Meta retiring it is an
environment change rather than a code change and a deploy."

**Why it is wrong.** Both versions expired years ago, and Meta does not reject calls to an expired version.

| Version | Released | Expired | Source |
|---|---|---|---|
| v3.2 | 23 October 2018 | **4 May 2021** | S2 |
| v11.0 | 8 June 2021 | **14 September 2023** | S2 |
| v18.0 | 12 September 2023 | **26 January 2026** | S2 |
| v19.0 | 23 January 2024 | **21 May 2026** | S2 |
| v20.0 | 21 May 2024 | **24 September 2026** | S2, S3 |
| v21.0 | 2 October 2024 | 21 January 2027 | S2, S3 |
| v26.0 | 29 July 2026 | TBD (latest) | S2, S3 |

S1 states the behaviour: a version "will no longer be usable two years after the date that the subsequent
version is released," and **"For APIs, once a version is no longer usable, any calls made to it will be defaulted
to the next oldest, usable version."**

So, as of today:

- v3.2 has been unusable for **5 years and 5 months**. v11.0 for **3 years and 1 month**.
- The oldest usable version today is **v21.0** — v20.0 was removed on 24 September 2026 (S3), nineteen days ago.
- Every `graph.facebook.com/v3.2/me/messages` send from the gem, every `v3.2/me/subscribed_apps` Page
  subscription, and every `v11.0/me/messages` legacy Instagram DM is today being served by **v21.0**.

Three consequences the reports do not state, each of which would be a wrong foundation if written into an
article:

1. **The configuration keys are cosmetic, and not only `FACEBOOK_API_VERSION`.** `041:46-48` correctly finds
   `FACEBOOK_API_VERSION` has no server reader. But `INSTAGRAM_MESSENGER_API_VERSION` (`config/installation_config.yml:157-161`),
   which `042:34-39` treats as a working control and praises for being separately keyed, has had no effect on
   behaviour since September 2023 whatever value it holds, because any value at or below v20.0 resolves to the
   same served version. The in-code rationale at
   `app/services/instagram/messenger/send_on_instagram_service.rb:5-8` is therefore describing a mitigation that
   was already too late when it was written.
2. **The exposure is not "a future break" but a silent, continuing version drift.** The version these paths
   actually talk rolls forward every time Meta removes the oldest one — most recently on 24 September 2026
   (v20.0), next on **21 January 2027** (v21.0 → the served version becomes v22.0, S3). The product cannot
   observe that, and `041:218-220` is right that there is no diagnostic; but the thing to document is a dated,
   recurring change, not a one-off cliff.
3. **Breaking changes between v3.2 and v21.0 apply now, not later.** The product constructs v3.2-era request and
   response shapes and gets v21.0 semantics. S1's defaulting rule routes the *call*; it does not preserve the old
   version's behaviour. Anything removed from the Send API or from `subscribed_apps` between those versions is
   already removed for this product.

**Severity: blocker.** 021–025 must not be written on the premise that these pins are a pending risk with a
remediation ("bump the key"). There is no bump that changes anything below v21.0, and the first real decision
point is 21 January 2027.

### R2 — `FACEBOOK_API_VERSION`'s own default is an expired version, and the SDK rule is not the API rule. **major**

`041:44` records the browser `FB.init` version as `FACEBOOK_API_VERSION`, default **v18.0**
(`config/installation_config.yml:152-156`), and treats the key as harmless because only the browser reads it.
v18.0 expired **26 January 2026** (S2), so the Super Admin-visible default is a dead version — and S1 draws an
explicit distinction the report does not carry: the "defaults to the next oldest, usable version" rule is stated
**"For APIs"**, while for SDKs S1 says "you should assume an end-of-life SDK is no longer functional," and
further states that unversioned calls "are not supported for the Facebook JavaScript SDK." The browser login
flow is therefore the one surface where the expired version is *not* covered by the defaulting rule, and it is
the surface 041 dismisses as inert.

**Severity: major.** An article or an operator runbook that says "`FACEBOOK_API_VERSION` only affects the browser,
so leave it alone" inverts the risk.

### R3 — The HUMAN_AGENT toggle is documented as a window setting. It is an app-review-gated policy commitment, and the product violates its terms on every send. **blocker**

**The claim.** `041:296-299`: the Messenger window is "24 hours by default, 7 days when
`ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT` is on". `042` lists the same for Instagram
(`ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT`). Both name this as a missing article. Neither states a precondition or a
constraint on use.

**What Meta states.** S6: the Human Agent feature "requires successful completion of the App Review process
before your app can access live data," and "This permission or feature is only available with business
verification." Allowed use is to "Provide human agent support in cases where a user's issue cannot be resolved in
the standard messaging window." S7 states the window as "a Human Agent tag that allows businesses to manually
respond to user messages within a 7-day period," and warns that "Use of Message Tags outside the approved use
cases may result in restrictions on the Page" (S5). S4/S5 define the three message types: Response and Updates
are *inside* the standard window; a **Tagged Message** is the one "sent outside the window, with a message tag."

**What the product does.** `merge_human_agent_tag` sets `messaging_type = 'MESSAGE_TAG'` and `tag = 'HUMAN_AGENT'`
unconditionally whenever the global config is on — on all four send paths:

- `app/services/facebook/send_on_facebook_service.rb:53,94,97-104`
- `app/services/instagram/base_send_service.rb:37,53,92-93` (abstract), implemented at
  `app/services/instagram/send_on_instagram_service.rb:25-33` and
  `app/services/instagram/messenger/send_on_instagram_service.rb:44-52`

There is no check on where in the window the message sits, and no check on who or what produced it.
`app/jobs/send_reply_job.rb:19-38` is the single outbound path for every channel, so a flow-builder reply, an
automation-rule message and a campaign send all arrive at the same `merge_human_agent_tag`. The result is that an
installation with the toggle on tags **automated** messages, and **in-window** messages, as human-agent tagged
messages. S6 names automated messages as a disallowed usage; S4/S5 reserve `MESSAGE_TAG` for out-of-window sends;
S5 states the consequence as a restriction on the Page's ability to send.

**Severity: blocker.** This is the single most dangerous article in the brief's scope. "Switch this on to get
7 days" is the obvious article to write from the code and from the switch's own description
(`config/installation_config.yml:166`), and writing it without the App Review + business verification
precondition and without the in-window/automation problem would instruct operators straight into a Page or
Instagram messaging restriction. The toggle is installation-wide
(`app/services/conversations/message_window_service.rb:63-65`), so one operator's choice applies that risk to
every tenant on the install.

### R4 — "Message tags" is no longer a family of options. Three of the four were retired six months ago. **major**

Any report writing message tag semantics from recall will describe a surface that no longer exists. S19, entry
dated **27 March 2026**, retires `CONFIRMED_EVENT_UPDATE`, `ACCOUNT_UPDATE` and `POST_PURCHASE_UPDATE`; S4/S5
state that "Effective April 27th, 2026, all API requests containing the Message Tags" those three "will receive
error code 100." S19's quoted wording: requests using them "will receive error code 100 indicating deprecated
message tags are no longer allowed in API Requests."

Consequences for 021–025:

- `HUMAN_AGENT` is effectively the only tag a product like Lynomia can use. S7 additionally names
  `NON_PROMOTIONAL_SUBSCRIPTION`, restricted to NPI-registered news Pages, which does not apply here.
- The retirement signal is **error code 100**, which S16 also defines generically as "Invalid parameter." An
  operator receiving `100 - ...` in the failed-message bubble
  (`app/services/facebook/send_on_facebook_service.rb:73-79`) cannot distinguish a retired tag from a malformed
  recipient id. That is a documentation requirement, not an optional nicety.
- S7 states "Some tags are available on both Messenger Platform and IG Messaging API, while others are applicable
  only to Messenger Platform" and **does not say which** — so a table claiming per-platform tag availability
  cannot be sourced. Record the ambiguity; do not fill it in.

**Severity: major.**

### R5 — "Two Instagram integration paths." Meta documents three configurations, and Lynomia's "legacy" path is not the one Meta's Facebook-Login documentation describes. **major**

`042:11-21` builds its whole report on a two-column table: "Instagram Login (current)" versus "Instagram via
Facebook Page (legacy)". S8 and S10 together describe **three** configurations:

| Meta's configuration | Host | Messaging webhook fields | Source |
|---|---|---|---|
| Instagram API with Business Login for Instagram | `graph.instagram.com` | available | S8, S10, S12 |
| Instagram API with Facebook Login for Business | `graph.facebook.com` | **unavailable** | S8, S10 |
| Instagram Messaging via Messenger Platform | `graph.facebook.com` | available | S10 |

S10's field table marks `messages`, `message_reactions`, `messaging_seen`, `messaging_postbacks` and `standby` as
**unavailable** under Facebook Login for Business; the messaging fields "require either Instagram Login
permissions or the Messenger Platform setup." S10 states the host split directly: "Business Login for Instagram:
`graph.instagram.com`; Facebook Login for Business **and Instagram Messaging via Messenger Platform**:
`graph.facebook.com`." S9's entry of **19 December 2025** states the same division in product terms —
Page-linked accounts use the Graph API, Instagram-only accounts use the Instagram API.

Lynomia's legacy path receives Instagram DMs on a Page token and sends to `graph.facebook.com/.../me/messages`
(`app/services/instagram/messenger/send_on_instagram_service.rb:18-31`). That is the **third** configuration,
Instagram Messaging via Messenger Platform — not "Instagram API with Facebook Login". The distinction is not
pedantic: S8's permission list for the Facebook-Login path is `instagram_basic`, `instagram_content_publish`,
`instagram_manage_comments`, `instagram_manage_insights`, `instagram_manage_messages`, `pages_show_list`,
`pages_read_engagement`, Human Agent and Instagram Public Content Access — and Lynomia requests **none** of the
`instagram_*` ones (`app/javascript/dashboard/helper/facebookScopes.js:1-8`, confirmed dead
`INSTAGRAM_SCOPES` branch at `:10-22`). A writer who opens Meta's "Instagram API with Facebook Login" pages to
document Lynomia's legacy Instagram inbox will document a configuration this product does not use and a
permission set it does not request.

**Severity: major.** 042's table is not false about Lynomia; it is false about Meta, and 023/024 will inherit it.

### R6 — "Legacy" and "migrated" imply Meta is retiring the Page path. Meta is not. **major**

`042:11` labels the Page path "legacy"; the product ships banners saying an account "was migrated to the new
Instagram channel inbox" (`inboxMgmt.json:64`) and "has now been migrated here" (`:63`). Read as a Meta
statement, that is wrong. S9 has **no** entry in 2025 or 2026 deprecating or retiring the Facebook-Login or
Page-linked path. Meta was still shipping Facebook-Login-**only** Instagram features five months ago and four
months ago: the Instagram Audio API on **1 June 2026** and `reposts_count` / `saved_count` / `shares_count` plus
the Collaborative Media API on **22 April 2026** (S9). The only retirement S9 records in this area is the v1.0
endpoints (**21 January 2025**), and S9 itself gives that entry's effective date inconsistently
("Will apply to all versions April 21, 2025 May 20, 2025") — an ambiguity to record, not resolve.

"Legacy" is Lynomia's own vocabulary for which of its two channel models it prefers. An article that tells a
customer Meta is sunsetting Instagram-through-a-Page will be wrong, and will be quoted back.

**Severity: major.**

### R7 — Handover protocol: the model in the code is two generations stale, and for Instagram Meta withdrew it a year ago. **major**

`041:198-200` and `app/models/channel/facebook_page.rb:53-55` subscribe `standby` and `messaging_handovers`;
`lib/integrations/facebook/message_parser.rb:6` is written to read standby entries. Four separate corrections:

1. **Meta ended Handover Protocol support for Instagram.** S19, entry dated **23 October 2025**: "Meta no longer
   supports the Handover Protocol for Instagram." Businesses were moved to **Conversation Routing**. So for the
   legacy Instagram inbox — which rides a Page — there is no handover protocol left to document.
2. **Primary and secondary receiver roles no longer exist.** The 2021 handover improvements added Exclusive mode
   and Idle mode and **removed the requirement to assign primary or secondary roles** (O1, confirmed present on
   S19 but read via search snippet, so recorded as observational). Any 021/022 report written from the
   primary/secondary model — still the most common framing in third-party material — will describe a mechanism
   Meta retired five years ago.
3. **`standby` is a valid `subscribed_fields` value but is not in the Page webhooks reference.** S14's
   `subscribed_fields` enum does include all seven fields Lynomia subscribes — `messages`, `message_deliveries`,
   `message_echoes`, `message_reads`, `standby`, `messaging_handovers`, `messaging_postbacks` — so the Page
   subscription call's field list is well-formed. But S17, the Page Webhooks Reference, lists
   `messages`, `message_deliveries`, `message_echoes`, `message_reads`, `messaging_handovers` and
   `messaging_postbacks` and **does not list `standby` at all**. S18 says standby is enabled "by selecting the
   `standby` field when setting up your webhook" — the app dashboard, not the Page subscription. Lynomia
   subscribes to a channel at the Page level that the Page webhook reference does not document delivering, and
   `041:198` establishes the gem would drop it anyway.
4. **The field names differ by platform and the reports do not say so.** Pages use `messaging_handovers`
   (plural, S14/S17). Instagram uses `messaging_handover` (singular, S10). 041 has the Page spelling right; a
   writer copying Instagram's documented field name into a Facebook article would produce an invalid enum value
   and, per S14, error **100**.

**Severity: major.** On the positive side, S18 corroborates 041's standby finding exactly: the example places a
`standby` array "inside `entry`, alongside `id` and `time`", and the four event types delivered there are
`message_reads`, `message_deliveries`, `messages`, `messaging_postbacks`, with postback payloads omitted. The
gem's `entry['messaging']`-only loop therefore does drop them.

### R8 — Both reports treat a failed `subscribe` as the invisible failure. The invisible failure is a *successful* subscribe that still delivers nothing. **major**

`041:149` and `042:5`/§5.2 both find that `subscribe` swallows its error and the inbox reports healthy. True,
and confirmed in code (`app/models/channel/facebook_page.rb:49-67`, `app/models/channel/instagram.rb:48-73`).
But both reports stop there, and the larger cause of "connected, no messages" is not in the product at all:

- S14 states that **"only fields subscribed at both the Page level and the app level will deliver webhooks."**
  The `subscribed_apps` call is the Page level. The app level is a Meta App Dashboard setting.
- S10 makes this a numbered sequence: Step 2 is "Subscribe your app to webhook fields in the Meta App
  Dashboard"; Step 3 is the `/subscribed_apps` API call. Both are required.
- S10 adds a third out-of-product precondition: **"Your app must also be set to Live to receive notifications."**
- S14 further states, for the Page endpoint, that `subscribed_fields` "cannot be used to subscribe to Instagram
  webhooks. Use the app dashboard for those."

Nothing in Lynomia performs or checks any of these, and nothing in the product or the corpus mentions them.
`041:1-5` lists `FB_APP_ID`, `FB_APP_SECRET` and `FB_VERIFY_TOKEN` as the prerequisites; the real prerequisite
list is longer by three items, all of which produce exactly the same symptom — a connected inbox that never
receives a message.

**Severity: major.** This is the first troubleshooting article either channel needs, and neither report
identified it.

### R9 — "Each Instagram attachment is a separate DM" is presented as an Instagram constraint. It is a product choice, and it has been one since May. **major**

`042` §"Outbound send and its restrictions" and failure path 8 describe
`app/services/instagram/base_send_service.rb:8-23` sending each attachment as its own Graph message, and frame
the resulting partial-delivery problem as the shape of the API. S11 states that for images you can send
**"up to ten `attachment` objects"** in one request. S9 records multi-image sending entering beta on
**3 November 2025** and leaving beta — "available to all accounts" — on **6 May 2026**, and Direct Send
accepting attachment IDs as well as image URLs from **13 March 2026**.

So an article saying "Instagram only accepts one attachment per message, which is why your three images arrive
as three DMs" would be wrong. The correct statement is that Lynomia sends one request per attachment, which
produces one DM per attachment, and that the API has not required this since at least May 2026.

**Severity: major**, because it is the kind of claim that gets written confidently and is directly falsifiable
by a customer.

### R10 — The "inside 10 days of expiry" refresh rule is Lynomia's, not Meta's. **minor**

`042` states the token "refreshes via `graph.instagram.com/refresh_access_token` ... only when the token is
valid, ≥24h old and inside 10 days of expiry". S12 states Meta's conditions and they are three: the token "must
be at least 24 hours old", must not be expired, and the user must have granted `instagram_business_basic`. S12
also states the hard rule the report does not: **"A token not refreshed within 60 days expires and cannot be
refreshed."** The ten-day window exists only in
`app/services/instagram/refresh_oauth_token_service.rb` and in `custom/app/services/channels/connection_state.rb:30-32`.
An article presenting it as an Instagram rule is wrong; presenting it as Lynomia's refresh policy is right.

**Severity: minor**, but it is exactly the kind of borrowed number that ends up in a "how Instagram tokens work"
article.

### R11 — `enable_fb_login` was deprecated and then re-introduced. The reports got the behaviour right by luck. **minor**

`app/controllers/concerns/instagram_concern.rb:9-15` sends `enable_fb_login=0` and `force_reauth=true`. S9 has
two entries on this parameter: **14 June 2025** — `force_reauth` added, "`enable_fb_login` and
`force_authentication` deprecated"; and **6 February 2026** — "`enable_fb_login` parameter added to Instagram
OAuth. Controls whether the Facebook Login option appears on the login page. Default is `true`." S12 confirms
the current state: `enable_fb_login` is listed as current, default `true`, "Controls whether the Facebook Login
option is displayed on the Instagram login page during OAuth authorization."

So the parameter is live again, with a default that would show a Facebook Login option, and Lynomia's `0`
suppresses it — a meaningful current behaviour. Any report that consults only the June 2025 changelog entry will
call `enable_fb_login` dead and the product's use of it vestigial. Both are wrong today.

Secondly, `042` glosses `force_reauth=true` as meaning users "will always re-enter credentials". S12's words are
narrower: "When set to `true` it forces an app user to use their Instagram professional account credentials" —
about *which* credentials, not about forcing a fresh credential entry.

**Severity: minor.**

### R12 — The missing-permission-dependency finding is on the dead branch. The live branch has the same defect. **major**

`003:245-252` finds that `pages_read_engagement` is a declared dependency of `instagram_manage_messages` and is
omitted from `facebookScopes.js:1-8`, and routes the question here. The finding is correct but is scoped to the
`INSTAGRAM_SCOPES` branch, which `042` proves is dead (no caller passes `includeInstagramScopes`). S13 shows the
same gap on the branch that every Facebook connect actually uses:

| Permission Lynomia requests | S13's stated dependencies | Requested by Lynomia? |
|---|---|---|
| `pages_show_list` | none | yes |
| `pages_manage_metadata` | `pages_show_list` | yes |
| `pages_messaging` | `pages_manage_metadata`, `pages_show_list` | yes |
| `business_management` | **`pages_read_engagement`**, `pages_show_list` | **`pages_read_engagement` NOT requested** |

So the live four-scope request (`app/javascript/dashboard/helper/facebookScopes.js:1-8`, reused verbatim at
`app/javascript/dashboard/routes/dashboard/settings/inbox/facebook/Reauthorize.vue:24-27`) is missing a declared
dependency of `business_management`, which it does request. The `pages_messaging` chain, by contrast, is complete
— so an article may safely say Lynomia asks for everything Messenger receiving and sending needs, and must not
say the same of `business_management`.

S13 also shows **no** permission in this area is deprecated, retired or renamed: `pages_messaging`,
`pages_manage_metadata`, `pages_show_list`, `pages_read_engagement`, `business_management`, `instagram_basic`,
`instagram_manage_messages`, `instagram_business_basic` and `instagram_business_manage_messages` are all current.
Two were **added**: `instagram_manage_contents` (S9, 3 December 2025) and `instagram_manage_engagement` (S9,
22 April 2026). The only rename in this area is on the Instagram Login path, where S12 records the old
`business_basic` / `business_content_publish` / `business_manage_comments` / `business_manage_messages` values as
deprecated on **27 January 2025** in favour of the `instagram_business_*` names — and Lynomia already uses the new
names (`app/helpers/instagram/integration_helper.rb:2`).

**Severity: major** for the `business_management` gap; the currency question itself resolves clean.

### R13 — "Not one of the codes Meta can return on `/me/messages` is documented." The corpus gap is real; the source gap is not. **minor**

`041:6` (§9) says "not one of the codes Meta can return on `/me/messages` is documented, and the UI shows the raw
code with no link." True of the Lynomia corpus. But S4 publishes a compact Messenger send error table, which
means the article is small and cheap rather than open-ended:

| Code | Meta's description (S4) |
|---|---|
| 10 | Permissions problem; the app needs `pages_messaging` and a valid Page access token |
| 100 | Invalid parameter; check the recipient ID, message format, and required fields |
| 190 | Access token has expired; generate a new Page access token |
| 551 | Recipient unreachable — for example, blocked the Page or deactivated their account |
| 613 | Rate limit exceeded; reduce call frequency |
| 1545041 | The 24-hour standard messaging window has closed |

Code **1545041** is the one that matters most and neither 041 nor 042 names it: it is the code an agent sees when
the window has shut, and it is the code that distinguishes "window closed" from "token dead" (190) in a product
whose reauthorization latch keys on the literal strings `'The session has been invalidated'` and
`'Error validating access token'` (`app/services/facebook/send_on_facebook_service.rb:114-119`). A Messenger send
that fails with 1545041 is not an auth problem and must not be documented as one.

**Severity: minor** as a refutation, but the table is a deliverable 022/024 should carry.

---

## 3. The three deferred questions

`_ARBITRATION.md:135-136` routed three questions away from 041/042. Each is answered below with a normative
source or an honest "not stated". None required calling Meta.

### Q1 — What does Graph return for a wrong or missing `appsecret_proof`?

**Not stated.** S20, Meta's own page on the subject, documents how to compute the proof (HMAC-SHA256 of the
access token keyed with the app secret), where to enable **Require App Secret** (App Dashboard → App Settings →
Advanced → Security), and says only that a call without it will "fail". It gives **no error code, no subcode, no
type and no message text**, and it does not say how to validate a proof or what an incorrect proof returns.

The nearest normative anchor is error code **104**, which S16 describes as **"Incorrect signature."** S14 lists
104 among the errors `POST`, `GET` and `DELETE` on `/{page-id}/subscribed_apps` can return, and S21 states that
some endpoints "may return error code 190 or 104 instead" when a token problem occurs. **But no Meta page I read
ties 104 to `appsecret_proof` specifically.** Treat 104 as the likely code and say so as a likelihood, not a
fact.

Why this matters here beyond curiosity: `config/initializers/facebook_messenger.rb:9-34` deliberately returns a
per-process **random** app secret when `FB_APP_SECRET` is unset, so every outbound Messenger send carries a proof
computed from a random key — a guaranteed signature mismatch. `041:1-5` (§5) is right that this fails loudly.
What it cannot say, and what Meta does not let anyone say from documentation, is which code the operator will see
in the failed-message bubble. If the answer is 104, then neither of the two literal strings the reauthorization
latch matches (`send_on_facebook_service.rb:114-119`) will appear, and the inbox will fail silently forever with
no banner. That is a documented-behaviour gap, and the corpus must describe the *symptom* (every send fails,
no banner, check `FB_APP_SECRET`) rather than a code it cannot source.

### Q2 — Does `subscribed_apps` accept a bracketed `subscribed_fields[]=` array form, or require a JSON body?

**Settled normatively for Instagram; not stated for Pages.** The two paths differ, and the answer is the opposite
of the one `042` guessed.

**Instagram (`graph.instagram.com/{ig-id}/subscribed_apps`)** — S10 states it explicitly: `subscribed_fields`
goes in the **query string**, and **"It must be a comma-separated list, not an array."** S10's description of the
parameter is "A comma-separated list of webhook fields that your app is subscribed to", and its example is
`https://graph.instagram.com/v25.0/<ID>/subscribed_apps?subscribed_fields=comments,messages&access_token=...`.

`app/models/channel/instagram.rb:48-56` passes a Ruby array to HTTParty's `query:`:

```ruby
query: {
  subscribed_fields: %w[messages message_reactions messaging_seen],
  access_token: access_token
}
```

HTTParty serializes that as `subscribed_fields[]=messages&subscribed_fields[]=message_reactions&subscribed_fields[]=messaging_seen`
— the bracketed array form Meta's documentation says must not be used. `042` recorded this as "unverified, and
untestable here". It is verifiable from documentation, and the documented answer is that this is not the
documented form. Whether Graph nevertheless tolerates it is a separate, genuinely untestable question (§4) — but
the product cannot find out either way, because `:57-59` rescues everything and returns `true`.

**Pages (`graph.facebook.com/{page-id}/subscribed_apps`)** — **not stated.** S14 declares the parameter's type as
`array<enum {feed, mention, name, picture, category, description, conversations, agent_messages, agent_questions, ...}>`
and marks it **Required**; the enum runs to roughly 105 values and contains all seven fields Lynomia subscribes.
S14's examples send form-encoded body fields (`-F 'subscribed_fields="leadgen"'`), all with a single value. S14
**does not state** whether a query string or a JSON body is accepted, and **does not state** how multiple values
must be separated. The vendored gem sends a JSON body
(`vendor/bundle/ruby/3.4.0/gems/facebook-messenger-2.0.1/lib/facebook/messenger/subscriptions.rb:30-41`:
`headers: { 'Content-Type' => 'application/json' }`, body `{access_token:, subscribed_fields: [...]}.to_json`),
which is a third form Meta documents neither for nor against. Record as not stated.

One related fact S14 does state, and which outranks the serialization question: **"only fields subscribed at both
the Page level and the app level will deliver webhooks"** — see R8.

### Q3 — What code does Graph return for an empty access token?

**Not stated for the Messenger or Instagram send endpoints.** The only normative Meta statement I found about a
*missing* token is scoped to WhatsApp Cloud API. S21, code **200**: details "No access token was provided", and
"The API returns the message `Provide valid app ID`"; the page says this "occurs on certain GET endpoints, such
as `whatsapp_business_profile`, when no token is included," distinguishes it from 190 (expired or invalid), and
adds that **"other endpoints may return error code 190 or 104 instead."** S15, the general Graph error-handling
guide, has no entry for a missing token at all: it covers 102 and 190 for invalid or expired tokens, with
subcodes 463 (Expired) and 467 (Invalid Access Token). S16 gives 190 as "Invalid OAuth 2.0 Access Token" and 200
as "Permission error" — note that S15 and S16 give **different descriptions for code 190**, which is an
ambiguity to record rather than resolve.

So the documented answer is: **Meta does not commit to a single code, and explicitly says it varies by
endpoint — 200, 190 or 104.** That is enough to settle the question 042 raised, and the answer is the bad one for
this product:

`Channel::Instagram#access_token` returns **`nil`** once `expires_at` has passed
(`app/services/instagram/refresh_oauth_token_service.rb:12-28`), after which sends go out with an empty
`access_token` query parameter. `app/services/instagram/base_send_service.rb:69-78` latches reauthorization on
code **190 only**, with `AUTHORIZATION_ERROR_THRESHOLD = 1` (`app/models/channel/instagram.rb:25`). If Graph
answers **200** or **104** instead — both of which Meta says it may — the latch never fires, no email is sent, no
red banner appears, and the only signal is `connection_state`, which `042` proves no frontend reads. 042 filed
this as "unverified"; it should be filed as **a documented non-guarantee**, which is a stronger finding than an
unknown.

---

## 4. Survived

Claims I attacked and could not break. Each lists what I tried.

| Claim | Who | What I tried | Outcome |
|---|---|---|---|
| The Messenger/Instagram window is 24 hours, extending to 7 days with the human-agent toggle | 041:296-299, 042 | Checked S4, S5, S6, S7 and S11 for a changed number, and S19/S9 for any 2024–2026 change to the window | **Survives.** S4/S5: "The Standard Messaging Window is the 24 hour time period in which you are allowed to send a message to a person." S7: 24 hours, and a Human Agent tag "within a 7-day period". S6: "within 7 days of a user's message." S11, Instagram: "Your app has 24 hours to respond". No 2024–2026 changelog entry alters either number. The only contrary figure is O2, a 21-day window for one named customer — a one-off, not a rule. The *numbers* are right; R3 is about everything around them |
| The window is measured from the last **incoming** message, and the toggle is installation-wide, not per inbox | 041:296-299 | Re-read `app/services/conversations/message_window_service.rb` at this HEAD | **Survives.** `last_incoming_message` is `@conversation.messages...incoming&.last` (`:67-69`), and `meta_messaging_window` reads a `GlobalConfigService` key with no inbox or account scope (`:63-65`). Matches S4's framing of the window opening when a person messages |
| `standby` entries never reach the parser because the gem iterates only `entry['messaging']` | 041:198-200 | Checked S18 for the actual delivery shape | **Survives and is corroborated.** S18 places a `standby` array "inside `entry`, alongside `id` and `time`" and names the four event types delivered there. The gem's loop cannot see it |
| `FACEBOOK_API_VERSION` governs only the browser SDK; no Ruby send or read path consults it | 041:33-48 | Grepped the call sites; read `config/installation_config.yml:152-156` | **Survives.** R2 adds that the default value is itself expired and that S1's defaulting rule does not cover SDKs |
| `subscribe` / `unsubscribe` failures are swallowed and the inbox still reports connected | 041:149, 042 §5.2 | Re-read `app/models/channel/facebook_page.rb:49-67` and `app/models/channel/instagram.rb:48-73` | **Survives.** Both rescue `StandardError` and return `true`. R8 adds that this is not even the main cause of silent non-delivery |
| Instagram Login requires no Facebook Page; a professional account is required | 042:11-21 | S8's comparison table; S9's 2025–2026 entries for any account-type or Page-link change | **Survives.** S8: "An Instagram professional account can be for a business or creator"; the comparison table marks Facebook Page as "x" for the Instagram Login path, and states that for the Facebook Login path "your app users' Instagram professional accounts must be connected to a Facebook Page." **No 2025 or 2026 changelog entry changes which account types are supported or whether a Page is required** |
| `instagram_business_basic` and `instagram_business_manage_messages` are the current scope names | 003:235-240, 042 | S12 and S13 for renames | **Survives.** S12 records the old `business_*` forms as deprecated 27 January 2025 in favour of these; S13 lists both as current, with `instagram_business_manage_messages` depending on `instagram_business_basic` — which Lynomia requests |
| One Instagram account can exist as two Lynomia inboxes at once | 042:22-24 | Checked whether Meta forbids the overlap | **Survives.** S10's three configurations and S9's 19 December 2025 entry treat Page-linked and Instagram-only as distinct setups with distinct hosts; nothing read forbids an account being reachable through both. The global unique index is on `Channel::Instagram` only (`db/schema.rb:733`) |
| The product's `appsecret_proof` computation is correct | `app/services/instagram/messenger/send_on_instagram_service.rb:38-42`, gem `AppSecretProofCalculator` | Compared against S20 | **Survives.** S20: HMAC-SHA256, access token as the message, app secret as the key. The gem matches |
| Facebook and Instagram have no diagnostic surface, so a version or permission problem surfaces only as failed messages | 041:218-220, 042 §5.9 | Re-checked `custom/app/services/` for a Facebook or Instagram diagnosis path; checked `custom/app/models/custom/message.rb:10-17` | **Survives.** Nothing Facebook- or Instagram-specific; `delivery_failure_data` matches WhatsApp codes only. R1 and R8 make this worse, not better |

---

## 5. Not checkable

| Question | Why not | What would settle it |
|---|---|---|
| Whether Graph in fact accepts the bracketed `subscribed_fields[]=` form on `graph.instagram.com`, despite S10 saying it must be comma-separated | Needs a live call with a real token; forbidden by §3 of the charter | A single read-only `POST` with a disposable test app and a test Instagram account, outside this program. Note the product itself cannot observe the answer because it rescues the response |
| Whether Graph accepts the gem's JSON-body array on `graph.facebook.com/{page-id}/subscribed_apps` | S14 states neither way; needs a live call | Same. Upstream Chatwoot has shipped this gem for years, which is suggestive but is not evidence and must not be written as such |
| The exact error for a wrong or missing `appsecret_proof` | S20 does not state it (Q1) | A live call, or a Meta documentation update. Until then, document the symptom, not the code |
| The exact code for an empty access token on `/{ig-id}/messages` or `/me/messages` | S21 states Meta does not commit to one (Q3) | A live call. The documentation answer is "200, 190 or 104, endpoint-dependent", which is itself the finding |
| Whether the Instagram Login send endpoint accepts the Messenger pair `messaging_type: 'MESSAGE_TAG'` + `tag: 'HUMAN_AGENT'` as `app/services/instagram/send_on_instagram_service.rb:25-33` sends it | S11 says only that an app "can tag the response to allow your app to send the message outside the 24 hour messaging window" and **does not name the tag or the parameters**. S8 and S6 name the Instagram feature's tag as `human_agent` (lower case); S4/S5 use `HUMAN_AGENT` for Messenger. The casing and the parameter pairing are unresolved in Meta's own prose | A live call, or a Meta documentation update. Record the ambiguity; do not assert either form |
| Whether `access_token` as a query parameter is still accepted on `graph.instagram.com` | S11's examples authenticate with `Authorization: Bearer <INSTAGRAM_USER_ACCESS_TOKEN>` only. The product passes it in `query:` everywhere (`app/services/instagram/send_on_instagram_service.rb:11,20`, `app/models/channel/instagram.rb:50-56,62-68`). S11 does not say the query form is unsupported, and does not say it is supported | A live call. Also an open security point already filed by 042 (tokens in query strings) |
| Which message tags are available on Instagram versus Messenger only | S7 states the split exists and does not say which tags fall where (R4) | A Meta documentation update. Do not build the table |
| Whether Meta enforces declared permission dependencies at authorization, at review, or at call time — the question 003:250 routed here | No page I read states it. S13 lists dependencies without saying what enforcement they carry | Not resolvable from documentation. 003's finding stands as a cited dependency gap (extended by R12 to `business_management`), not a proven runtime break |
| Everything in reports 021–025 | They do not exist (§1) | Those reports being written. This report's R1–R13 are the constraints they should be checked against before Checkpoint 1 closes |
| The exact text of the 2021 handover-protocol entries that removed primary/secondary receiver roles | S19's own summary confirms the entries exist in 2021–2022 but I read them through a search snippet (O1), not the page body | A direct read of S19's 2021 section. The claim is strong enough to act on and weak enough that 022 should re-read it |
