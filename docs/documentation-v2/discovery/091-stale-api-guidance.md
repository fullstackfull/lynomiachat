---
agent: 091
scope: stale Meta API guidance — deprecated Graph versions, retired endpoints, fields and permissions, and claims that were true at a past version; in the code, the corpus, this repository's internal records and the Phase 1 discovery reports
confidence: high
sources_normative: 11
sources_observational: 1
---

## 0. Source register

Every claim below references a row here. Date checked for all rows: **2026-10-13**. No Meta endpoint was called,
no credential used, no form submitted.

| # | Source URL | Page title | Product | Version context | Normative? |
|---|---|---|---|---|---|
| S1 | https://developers.facebook.com/docs/graph-api/changelog/versions/ | Versions — Graph API | Graph API | the version table itself | normative |
| S2 | https://developers.facebook.com/docs/graph-api/changelog/ | Changelog — Graph API | Graph API | v13.0 → v26.0 | normative |
| S3 | https://developers.facebook.com/docs/graph-api/guides/versioning | Versioning — Graph API | Graph API | version-independent rules | normative |
| S4 | https://developers.facebook.com/docs/apps/versions | Versioning — App Development | Graph API | version-independent rules | normative |
| S5 | https://developers.facebook.com/docs/javascript/reference/FB.init/ | FB.init — JavaScript SDK | Graph API / JS SDK | none stated | normative |
| S6 | https://developers.facebook.com/docs/messenger-platform/changelog/ | Changelog — Messenger Platform | Messenger Platform | dated entries, 2021 → 2026 | normative |
| S7 | https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/ | Error Codes — WhatsApp Cloud API | WhatsApp Cloud API | states v16.0+ and v23.0 | normative |
| S8 | https://developers.facebook.com/docs/whatsapp/on-premises/sunset | On-Premises API Sunset | WhatsApp Business Platform | On-Premises v2.53 → v2.63 | normative |
| S9 | https://developers.facebook.com/docs/instagram-platform/changelog | Changelog — Instagram Platform | Instagram Platform | dated entries, 2024 → 2026 | normative |
| S10 | https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/messaging-api | Send Messages — Instagram API with Instagram Login | Instagram Platform | examples at v25.0 | normative |
| S11 | https://developers.facebook.com/docs/whatsapp/api/messages/message-templates/interactive-message-templates/ | Interactive Message Templates | WhatsApp On-Premises API | On-Premises | normative |
| S12 | search result summary only; the Messenger message-tags page and its `/documentation/` equivalent both returned navigation markup with no content on two attempts | Message Tags | Messenger Platform | — | **observational, unconfirmed** |

### The authority: Graph version status at 2026-10-13

From S1 verbatim (release / "Available Until"), with status computed against today. S2 carries the same table for
v13.0 and later.

| Version | Introduced | Available until (S1) | Status on 2026-10-13 |
|---|---|---|---|
| v26.0 | 2026-07-29 | TBD | **current** |
| v25.0 | 2026-02-18 | 2028-07-29 | usable |
| v24.0 | 2025-10-08 | 2028-02-18 | usable |
| v23.0 | 2025-05-29 | 2027-10-08 | usable |
| v22.0 | 2025-01-21 | 2027-05-20 | usable |
| v21.0 | 2024-10-02 | 2027-01-21 | usable — **oldest usable version** |
| v20.0 | 2024-05-21 | 2026-09-24 | **expired 19 days ago** |
| v19.0 | 2024-01-23 | 2026-05-21 | expired |
| v18.0 | 2023-09-12 | 2026-01-26 | **expired 260 days ago** |
| v11.0 | 2021-06-08 | 2023-09-14 | **expired 3 years 1 month ago** |
| v3.2 | 2018-10-23 | 2021-05-04 | **expired 5 years 5 months ago** |

Three rules from S3, restated identically on S4, decide everything in this report:

1. "Each version is guaranteed to operate for at least two years." / "A version will no longer be usable two
   years after the date that the subsequent version is released."
2. "For APIs, once a version is no longer usable, any calls made to it will be defaulted to the next oldest,
   usable version."
3. "An unversioned call uses the version set in the app dashboard Upgrade API Version card under Settings >
   Advanced." And: "We recommend you always specify the version where possible."

Rule 2 is the one this installation's records get wrong, and it is why half this report exists. **An expired pin
is not a pin and it is not a failure. It is a silent substitution that moves on Meta's schedule.**

This corroborates agent 025 §5.2 and `_ARBITRATION.md:237-239` independently, from the same S1 table: v21.0 is
the oldest usable version, v20.0 retired 2026-09-24.

---

## 1. What I attacked

- **Deliverable 1 — the version inventory of this installation.** Every Graph/Instagram/WhatsApp version string
  in executable code, configuration and vendored gems, and what Meta serves for each today (§1.1).
- Agent 041's claim of **v3.2 pinned in a vendored facebook-messenger gem** and agent 042's claim of **v11.0 on a
  legacy Instagram path** — both verified against S1 (§1.1 rows 5, 6, 4; verdict in §2 R1, R2).
- `docs/p7/07-graph-api-versions.md` — this repository's own standing record of its Meta versions, and the
  decision log that chose *not* to move v3.2, v11.0 and Koala. Four of its claims are refuted (R1, R2, R3, R11).
- `docs/whatsapp-template-manager/01-meta-api-contract.md` and `custom/app/services/whatsapp/templates/` — the
  error-subcode contract (R5).
- The 12-section Markdown corpus under `custom/db/documentation/en/`, searched for every version string, Graph
  reference and endpoint/permission/field name (R10, and the basis of §5).
- Discovery reports 022, 024, 025, 040, 041, 042 and `_ARBITRATION.md`, for claims that are version-dependent and
  not marked as such.
- Retired endpoints, permissions and fields still treated as current: `error_subcode`, the Instagram `share`
  attachment, the Instagram `standby`/Handover channel, Messenger message tags, the On-Premises `/v1` API, and
  the `instagram_basic` / `instagram_manage_messages` scope names (§2, §3).

### 1.1 Version inventory of this installation

Established by reading the files, not inferred. "What a call returns today" applies S3 rule 2; **no call was
made**, so every cell in that column is documentation-derived, not observed.

| # | Surface | Version | Where it is pinned | Overridable | Meta status (S1) | What a call to it returns today |
|---|---|---|---|---|---|---|
| 1 | WhatsApp Cloud + Business Management — every call site (send, media, templates, token debug, register, subscribed_apps, business profile, CSAT, contact info) | **v24.0** | `app/services/whatsapp/facebook_api_client.rb:7` (constant) and `config/installation_config.yml:190-194` (seeded row, which wins) | yes — `WHATSAPP_API_VERSION`, `locked: false` | usable until **2028-02-18** | served as v24.0. Two versions behind v26.0. |
| 2 | WhatsApp health / business profile | floor **≥ v24.0** | `app/services/whatsapp/health_service.rb:18,45-46` | same key, clamped upward | usable | served as the newer of the configured version and v24.0 |
| 3 | Instagram Login — `graph.instagram.com` sends, user details, message text, story/post reads | **v22.0** | `app/models/channel/instagram.rb:28` (constant) and `config/installation_config.yml:611-615` (`locked: true`) | **yes, despite `locked: true`** — `app/controllers/super_admin/app_configs_controller.rb:32` writes the row regardless (corroborates `_ARBITRATION.md:96`, IR-10) | usable until **2027-05-20** | served as v22.0. S10's own examples are at v25.0. |
| 4 | **Instagram via Facebook Page — outbound sends** | **v11.0** | `app/services/instagram/messenger/send_on_instagram_service.rb:9` (`DEFAULT_API_VERSION`), `:34-36`, URL at `:26`; seeded `config/installation_config.yml:157-161` | yes — `INSTAGRAM_MESSENGER_API_VERSION` | **expired 2023-09-14** | **not v11.0.** S3: "defaulted to the next oldest, usable version" → **v21.0** today |
| 5 | **Facebook Messenger — outbound sends** | **v3.2** | `vendor/bundle/ruby/3.4.0/gems/facebook-messenger-2.0.1/lib/facebook/messenger/bot.rb:16` — `base_uri 'https://graph.facebook.com/v3.2/me'`. No override: nothing in `app`, `lib`, `config` or `custom` sets `base_uri`, and `config/initializers/facebook_messenger.rb` configures only the provider and the event handlers | **no** | **expired 2021-05-04** | **not v3.2** → **v21.0** today |
| 6 | **Page webhook subscribe / unsubscribe** | **v3.2** | same gem, `lib/facebook/messenger/subscriptions.rb:12`; reached from `app/models/channel/facebook_page.rb:51,63` | **no** | **expired 2021-05-04** | → **v21.0** today |
| 7 | **Browser JS SDK — `FB.init` for Facebook Page connect and reauthorize** | **v18.0** | `config/installation_config.yml:152-156` (seeded value); read at `app/controllers/dashboard_controller.rb:85`; published at `app/views/layouts/vueapp.html.erb:44`; consumed at `app/javascript/dashboard/composables/useFacebookPageConnect.js:29` and `app/javascript/dashboard/routes/dashboard/settings/inbox/facebook/Reauthorize.vue:37` | yes — `FACEBOOK_API_VERSION`, `locked: false`, and it is in the Super Admin allow-list (`app_configs_controller.rb:64`) | **expired 2026-01-26** | **undetermined.** S5: `version` "is a required parameter" and "valid values are determined by currently available versions". S5 does not state the behaviour for an expired value. See R4. |
| 8 | Browser JS SDK — WhatsApp Embedded Signup | **v24.0** | `whatsappApiVersion` from `WHATSAPP_API_VERSION` (`vueapp.html.erb:47`), consumed `useWhatsappEmbeddedSignup.js:97`; fallback constant `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js:5` | yes, same key | usable | served as v24.0 |
| 9 | **Koala — all Facebook/Instagram Graph reads** (page details, page avatar via API, Facebook and Instagram-via-Page message builders, story/post link fetches, provider-name backfill) | **none** | `Koala.config.api_version` is set nowhere in the repository. The gem prepends a version only when it is set: `vendor/bundle/ruby/3.4.0/gems/koala-3.4.0/lib/koala/http_service/request.rb:37-41`, `lib/koala/oauth.rb:326`. Call sites: `app/services/facebook/page_details_service.rb:5-7`, `app/controllers/api/v1/accounts/callbacks_controller.rb` (OAuth + API), `app/builders/messages/facebook/message_builder.rb`, `app/builders/messages/instagram/messenger/message_builder.rb`, `app/services/instagram/messenger/message_text.rb`, `app/services/social_channels/provider_name_backfill_service.rb` | no | n/a | **unknowable from this repository.** S3/S4: the version is whatever the Meta app's dashboard "Upgrade API Version" card says. See R3. |
| 10 | Page avatar | unversioned | `app/controllers/api/v1/accounts/callbacks_controller.rb:103` — `graph.facebook.com/{page_id}/picture` | no | n/a | same as row 9 |
| 11 | Instagram token exchange and refresh | unversioned | `app/controllers/concerns/instagram_concern.rb:29` (`graph.instagram.com/access_token`), `app/services/instagram/refresh_oauth_token_service.rb:52` (`/refresh_access_token`) | no | n/a | same as row 9 |
| 12 | WhatsApp provider `default` — 360dialog | `/v1`, On-Premises-shaped | `app/services/whatsapp/providers/whatsapp_360_dialog_service.rb:55-56` — `https://waba.360dialog.io/v1`; selectable because `app/models/channel/whatsapp.rb:36` lists `default` | `360DIALOG_BASE_URL` env | **not a Meta host**; Meta's own On-Premises API was sunset 2025-10-23 (S8) | see R9 |
| 13 | Not Meta, recorded so the inventory is complete | TikTok `v1.3` (`app/services/tiktok/auth_client.rb:142`, `client.rb:119`, `installation_config.yml:619-623`); Shopify Admin `2026-07` (`custom/app/services/commerce/shopify/config.rb:12`); Intercom `2.15` (`app/services/data_imports/intercom/client.rb:24`); Microsoft `v2.0` (`app/controllers/concerns/microsoft_concern.rb:11-12`) | — | — | out of scope | — |

**Four distinct Meta Graph versions in executable code, from v3.2 to v24.0, plus two unversioned families. Three
of the four are past end of life: v3.2, v11.0 and v18.0.** Only WhatsApp's v24.0 and Instagram Login's v22.0 are
inside their window.

**The consequence, plainly.** Rows 4, 5 and 6 are not running on the versions the code names. Meta serves them on
the oldest version it still supports, which was **v20.0 until 2026-09-24 and is v21.0 as of 2026-09-25**. It
becomes v22.0 on **2027-01-21**, v23.0 on **2027-05-20**, and so on roughly every three to five months, for ever,
without a deploy and without a log line. Every behaviour on the Facebook Messenger send path, the Page
subscribe path and the Instagram-via-Page send path therefore changes on Meta's schedule rather than this
installation's, and nothing in the repository records which version is actually in force or detects when it
moves. That — not an outage — is the finding.

---

## 2. Refutations

### R1 — The evidence this repository said it was waiting for has existed since 2021. **blocker**

**The claim.** "I have no evidence from this repository that v3.2 is failing. **Evidence needed:** either a Meta
retirement notice naming v3.2 with a date, or an observed delivery failure on a Facebook Page inbox. Until one of
those exists, changing it is the blind upgrade the brief forbids."
— `docs/p7/07-graph-api-versions.md:61-64`.

**Why it is wrong.** The first condition was already met. S1 names v3.2 with a date: available until
**2021-05-04**. Likewise v11.0: **2023-09-14**. The record set a bar, and the bar was on Meta's published version
table at the moment the record was written. The same closing sentence recurs at `:160-162` — "the only evidence
pointing at `v3.2` and `v11.0` is that they predate two versions this repository records as expired, which is a
reason to probe production, not a reason to edit." S1 is not an inference from neighbouring versions; it is
Meta's own normative statement of the end date for v3.2 and for v11.0 specifically. No production probe is
needed to establish end of life.

**Severity: blocker**, because this sentence is the stated reason three live Meta call paths were left as they
are, and it is the sentence the matrix inherited.

### R2 — "Retirement would surface as messages silently failing to send" is wrong in the direction that matters. **blocker**

**The claim.** "There is no health tab, no diagnostic and no spec that would catch either version becoming
invalid. A v3.2 or v11.0 retirement would surface as messages silently **failing to send**, caught only by
`Messages::StatusUpdateService` marking them failed."
— `docs/p7/07-graph-api-versions.md:79-82`. Restated as a Phase 1 finding at
`docs/documentation-v2/discovery/041-facebook-messenger.md:218-220`: "`v3.2` on the send path and unversioned
Koala reads are undetectable from inside the product."

**Why it is wrong.** Meta does not fail the call. S3 and S4, identically: "For APIs, once a version is no longer
usable, any calls made to it will be defaulted to the next oldest, usable version." So retirement produces
**silent behaviour substitution**, not silent failure. A v3.2 request is answered — by v21.0 today — with v21.0's
field shapes, required parameters, error codes and permission checks.

This inverts the operational conclusion in three ways:

1. The detection the record hoped for cannot work. A monitor that watches for messages marked failed will never
   fire on a version retirement, because there is no failure to count. `Messages::StatusUpdateService` is
   watching for the wrong event.
2. The event already happened and nobody noticed. v3.2 was substituted away in 2021 and v11.0 in 2023. The
   substituted-to version has since moved at least seven times, most recently 19 days ago.
3. "Undetectable from inside the product" is correct but for the opposite reason: not because a failure is
   swallowed, but because there is no failure, and no response header or error code announces the substitution.
   S3 gives no error code, no warning and no header for the substitution (corroborated independently by agent
   025 §5.2: "S3 gives no error code and no warning header").

**Severity: blocker.** The risk statement the matrix carries is the wrong shape, so any monitoring or
documentation built on it will be built to catch an event that does not occur.

### R3 — "Meta resolves an unversioned call to the oldest available version" is false. **major**

**The claim.** "Nothing sets `Koala.config.api_version`, so Koala's Graph reads … go out unversioned. **Meta
resolves an unversioned call to the oldest available version**, which means these calls drift as Meta retires
versions, rather than failing cleanly."
— `docs/p7/07-graph-api-versions.md:66-70`. Carried forward into Phase 1 without correction at
`041-facebook-messenger.md:42` and `042-instagram.md:42-44`, which both describe the Koala reads as
"unversioned" and leave the resolution unstated.

**Why it is wrong.** S3 and S4 both state: "An unversioned call uses the version set in the app dashboard Upgrade
API Version card under Settings > Advanced." The resolved version is a per-app setting held in the Meta App
Dashboard — outside this repository, outside `installation_config.yml`, and changeable by whoever administers the
Lynomia Meta app. It is not "the oldest available version". Neither S3 nor S4 states what happens when an app has
never set that card, so the honest statement about Koala's eleven call sites (inventory row 9) is **"unknown, and
not discoverable from code"**, not "oldest".

The practical difference is large. Under the record's version of the rule, the Koala reads drift downward with
Meta's retirements and the drift is at least predictable from S1. Under Meta's actual rule, the version is a
hidden operator setting that can be changed by someone who is not deploying anything, and a Lynomia engineer
reading the code cannot determine what version the product's Facebook reads run on.

**Severity: major.** The corpus and the coverage matrix cannot state the Facebook read version at all until
someone reads that card, and R3 means no amount of repository reading will produce it.

### R4 — `FACEBOOK_API_VERSION` ships a value Meta stopped serving on 2026-01-26, into a parameter Meta says must be a currently-available version. **major**

**The claim.** `config/installation_config.yml:154`: "Configure this if you want to use a different Facebook API
version." Seeded value, `:155`: `v18.0`.

**What is already established.** Agent 041 (`041-facebook-messenger.md:321`) and `_ARBITRATION.md:232` (U-02)
already refute the *scope* of this control: one server-side reader, which only publishes the value to the
browser, so no Ruby Graph call is affected. I am not re-reporting that.

**What I add.** The value itself is past end of life, and the parameter it feeds is one Meta constrains. S1:
v18.0 available until **2026-01-26**, 260 days before today. The value goes to `FB.init({version})` on both
Facebook Page OAuth surfaces — `useFacebookPageConnect.js:29` (connect a new Page) and
`facebook/Reauthorize.vue:37` (recover a broken Page inbox). S5 states `version` "is a required parameter" and
that "valid values are determined by currently available versions". v18.0 is not a currently available version.

S5 does not state what `FB.init` does with an expired value, and S3's substitution rule is written for API calls,
not for the SDK — S3 says only that for SDKs "you should assume an end-of-life SDK is no longer functional", which
is about SDK releases, not about this parameter. So the consequence is **undetermined** (see §4). What cannot
stand is any statement that this is fine: the two flows that recover a broken Facebook inbox initialise Meta's
SDK at a version Meta no longer lists as valid, and nobody has established what that does.

One detail that makes it worse rather than better: `utils.js:5` carries
`DEFAULT_FACEBOOK_SDK_VERSION = 'v24.0'` with the comment "Only reached when the server did not supply
`WHATSAPP_API_VERSION`". For the Facebook path the server *always* supplies a value, because
`installation_config.yml:155` seeds one — so the healthy fallback is unreachable and the expired seeded value
always wins.

**Severity: major.** It is on the recovery path for a broken channel, and its consequence is unknown.

### R5 — The template manager's first error branch depends on a field Meta deprecated at v16.0, and its test fabricates that field. **major**

**The claim, in three places, each stated as current fact with no version qualifier:**

- Code comment, `custom/app/services/whatsapp/templates/operation.rb:9`: "Meta: 'Content in This Language Already
  Exists' -- code 100 with this subcode." Constant at `:10`, branch at `:53`:
  `return Whatsapp::Templates::Error.new('NAME_TAKEN') if error.subcode == DUPLICATE_NAME_SUBCODE`. It is the
  **first** branch in `mapped`.
- Internal record, `docs/whatsapp-template-manager/01-meta-api-contract.md:63-65`: "a duplicate returns `code
  100`, subcode `2388024`, 'Content in This Language Already Exists'. **Both statements in Meta's docs are true
  at once**"; repeated at `06-meta-submit-edit-delete.md`.
- Phase 1, `040-whatsapp-runtime.md`, which lists the subcode as a **classified** code mapping to `NAME_TAKEN`,
  and `053-corpus-whatsapp.md` (M-37), which reasons from it.

**Why it is now wrong.** S7, on the `error_subcode` property: "**Deprecated. Will not be returned in v16.0+
responses**", and "Not all responses will include a subcode, so build your error handling logic around `code` and
`details` properties instead." The request in question goes to v24.0:
`custom/app/services/whatsapp/templates/meta_client.rb:57` builds `"#{BASE_URI}/#{@api_version}/#{path}"` from
`Whatsapp::FacebookApiClient`'s `@api_version`, which is `WHATSAPP_API_VERSION` → **v24.0** (inventory row 1).

This is the dangerous category the brief names: the claim was true when the API was called at v15.0 or earlier,
reads as correct, carries a plausible number, and is cited by two Phase 1 reports. Nothing in the repository
reads `details` on a template error — `rg` for `'details'` finds it only on WhatsApp *send* failures
(`custom/app/services/whatsapp/delivery_report.rb:44`, `custom/app/services/whatsapp/send_failure.rb:33`) and on
Line and JSON-schema paths, never in `Whatsapp::Templates`.

**The test does not catch it, because the test writes the payload.**
`spec/custom/services/whatsapp/templates/operation_error_mapping_spec.rb:23` stubs
`https://graph.facebook.com/v24.0/555` and `:39-40` returns a body the spec itself constructs containing
`error_subcode: described_class::DUPLICATE_NAME_SUBCODE`. The example therefore asserts that the mapping works
*given* a response shape S7 says v24.0 does not send. It is self-confirming. The same fabrication appears at
`spec/controllers/api/v1/accounts/whatsapp/message_templates_controller_spec.rb`.

**The ambiguity I will not resolve by guessing.** S7 is the WhatsApp Cloud API error-codes page, and the
deprecation sentence sits in its error-object property table. Template create/edit/delete are WhatsApp Business
Management API calls on the same `graph.facebook.com` host. I found no page that scopes the v16.0+ deprecation to
Cloud-API-messaging responses only, and none that exempts Business Management. Per §6.2 I record this as
ambiguous rather than deciding it. What is not ambiguous: Meta tells implementers to branch on `code` and
`details`, this code branches on `error_subcode` first and only, and nothing reads `details`.

**Severity: major.** If v24.0 omits the subcode, the only mapping for `NAME_TAKEN` is dead and every duplicate
name falls through to the generic `META_REJECTED_REQUEST` — which is what agent 053's M-37 already noticed from
the other end, without identifying the cause.

### R6 — Instagram `standby` is read as a live channel; Meta removed the mechanism it belongs to on 2025-10-23. **major**

**The claim, in code.** Three Instagram webhook paths treat `standby` as a current delivery channel:
`app/controllers/webhooks/instagram_controller.rb:69` (`entry[:messaging].presence || entry[:standby] || []`),
`app/jobs/webhooks/instagram_events_job.rb:101` and `:154` (same pattern), and
`lib/integrations/facebook/message_parser.rb:6` (`@response['messaging'] || @response['standby']`).

**Why it is stale.** S6, 2025-10-23, verbatim: "Meta no longer supports the Handover Protocol for Instagram." /
"All businesses have been migrated to Conversation Routing." The `standby` channel is a Handover Protocol
construct — agent 022 establishes this from Meta's own reference (`022-messenger-platform.md:260-275`, its R5:
standby "fires when a message has been sent to your page, but your application is not the current thread owner",
and `:322` describes standby as "A conversation has been idle for the app during the Handover Protocol"). With
Handover Protocol removed for Instagram, the Instagram `standby` branches describe a mechanism Meta says it no
longer supports.

**What I deliberately do not claim.** I am not calling `Channel::FacebookPage#subscribe` stale.
`app/models/channel/facebook_page.rb:54` requests `standby messaging_handovers` for a **Page**, and S6's removal
is scoped to Instagram; agent 022's own unresolved item 11 (`:616-618`) records that no page says handover is
deprecated for Messenger. So the Page subscription stands and the Instagram read paths do not.

**Severity: major** — as documentation ground, not as an outage. It is a dead branch the corpus must not describe
as a feature, and agent 022's §2.7 and §4 treatment of standby needs an Instagram/Messenger split.

### R7 — The Instagram `share` attachment type is handled as current; its removal date passed on 2026-04-27. **major**

**The claim, in code.** `app/models/attachment.rb:47` enumerates `:share => 6` alongside `:ig_post => 10`.
`app/builders/messages/messenger/message_builder.rb:50` admits `:share` as a supported Instagram attachment type
and `:78` fetches a story link for it (`return unless attachment.file_type == 'share' || ... 'story_mention'`).

**Why it is stale.** S6, 2025-10-30: "The old `share` attachment type will continue to be supported for Instagram
posts **until February 1, 2026**, after which it will be removed." S6, 2026-04-27: "The legacy `share` attachment
type **is being removed** from Instagram post share webhook payloads. As announced on October 30, 2025, the
`share` attachment has been deprecated in favor of the `ig_post` attachment type … webhooks will return only the
`ig_post` attachment once rollout reaches your app."

Agent 024 (`024-instagram-runtime.md:59`) marks the row "**Migrating to `ig_post`**". That is now understated: the
announced removal date is 169 days past. `ig_post` is already handled (`message_builder.rb:28,107-109`), so this
is a dead branch plus stale corpus ground, not a break.

**What I deliberately do not claim.** S6's removal statement is scoped to Instagram post shares. For Facebook,
`app/builders/messages/facebook/message_builder.rb:104` maps `:share` and `:post` to `:fallback`, and I found no
Meta statement removing `share` from Messenger payloads. That branch stands.

**Severity: major** for the corpus (an article describing shared-post handling would describe the wrong field),
minor for the product.

### R8 — The vendored gem presents two retired message tags as "Supported tags". **minor**

**The claim.** `vendor/bundle/ruby/3.4.0/gems/facebook-messenger-2.0.1/lib/facebook/messenger/bot/tag.rb:4`
comments "Supported tags." and exports, among 16 constants, `ACCOUNT_UPDATE` and `NON_PROMOTIONAL_SUBSCRIPTION`.

**Why it is stale.** S6, 2026-03-27: "Effective **April 27, 2026** all API requests containing the deprecated
Message Tags CONFIRMED_EVENT_UPDATE, ACCOUNT_UPDATE, and POST_PURCHASE_UPDATE will receive **error code 100**
indicating deprecated message tags are no longer allowed in API Requests. Migrate to Utility Templates or
Marketing Messages API before the deadline."

**Why it is only minor.** Nothing in `app`, `lib` or `custom` references any of the three. The only tag this
product sends is `HUMAN_AGENT`, at `app/services/facebook/send_on_facebook_service.rb:103-104`,
`app/services/instagram/messenger/send_on_instagram_service.rb:49-50` and
`app/services/instagram/send_on_instagram_service.rb:30-31`, and `HUMAN_AGENT` is not on S6's retired list. The
hazard is documentary: the gem's list is the nearest thing in the tree to a tag reference, and it is wrong.

**Severity: minor.** It becomes major only if a corpus article or a future feature uses the gem's list as the
source of truth.

### R9 — The `default` WhatsApp provider is selectable and speaks an API shape Meta sunset on 2025-10-23. **major**

**The claim.** `app/models/channel/whatsapp.rb:36`: `PROVIDERS = %w[default whatsapp_cloud].freeze`, validated at
`:39`. `default` routes to `Whatsapp::Providers::Whatsapp360DialogService`, whose every call goes to
`https://waba.360dialog.io/v1` (`:55-56`) with a `D360-API-KEY` header (`:44`) and On-Premises-shaped paths —
`/messages`, `/configs/templates`, `/configs/webhook`, `/media/{id}`.

**Why it is stale ground.** S8 verbatim: "The final version of On-Premises API (v2.63) will expire" on
**October 23, 2025**; "Messages sent to or from business numbers still registered for use with On-Premises API
will not be delivered"; and since **July 1, 2024**, "Attempting to register a number for use with On-Premises API
will return error code 1005." S11 restates it: On-Premises "was officially sunset on October 23, 2025 and is no
longer available. Please use Cloud API instead."

**The limit of what I can say.** `waba.360dialog.io` is 360dialog's host, not Meta's. Whether 360dialog still
serves a `/v1` façade over Cloud API is a fact about 360dialog, and 360dialog's documentation is not a normative
source under §6.2. So the consequence for this installation is **unverified** (§4). What cannot stand is a
documentation claim that `default` is a current, Meta-supported way to connect WhatsApp: the API shape it speaks
is one Meta has sunset, and the number-registration path it implies has returned error 1005 since 2024-07-01.

**Severity: major** for the corpus and for the coverage matrix, which must not present `default` as a live choice
without that caveat.

### R10 — Nothing in the corpus states a version, a source or a date, so no article can age honestly. **major (program-level)**

**The evidence.** Across all of `custom/db/documentation/en`, `rg -i 'api version|graph api|\bv2[0-9]\b'` returns
**zero** matches on 2026-10-13. The word "version" appears five times in total and never about a Meta API
(`whatsapp/whatsapp-business-coexistence.md`, `whatsapp/whatsapp-template-lifecycle.md`,
`administration/audit-logs.md`, `automation/flow-builder.md`, `conversations/canned-responses.md`). Front matter
is six keys — `title`, `description`, `position`, `tags`, `seo_title`, `seo_description` (e.g.
`custom/db/documentation/en/whatsapp-errors/whatsapp-error-190.md:1-7`). There is no version field, no
checked-on date, and no source URL.

**Why that is a refutation and not just a gap.** Fourteen `whatsapp-errors` articles make normative claims about
Meta's behaviour — `whatsapp-error-190.md:8-10` tells the reader what code 190 means and what causes it — and
every one of them is unfalsifiable by its own reader. Meta's own pages are more precise than this corpus: S7
qualifies with "Will not be returned in v16.0+ responses" and "Will be available with Graph API version 23.0".
An article that drops a qualifier its source carries is less accurate than its source, and after a version
retirement there is nothing in the file that would tell anyone to re-check it.

**Severity: major** as a program finding, because it applies to the whole corpus and the corpus is about to grow
several times over. §5 states what the record must contain.

### R11 — "A reason to probe production, not a reason to edit" cannot survive S1. **major**

`docs/p7/07-graph-api-versions.md:160-162`. Covered under R1; recorded separately because it is the line the
Phase 1 reports inherited, and because it asserts a *method* — that only a production probe can settle this —
which S1 disproves. Meta's published, dated version table settles end of life without touching production, which
matters here because §3 of the charter forbids the probe.

---

## 3. Survived

Claims I tried to break and could not. Each lists what I tried.

| Claim | What I tried | Verdict |
|---|---|---|
| **WhatsApp runs v24.0 and it is current enough.** `facebook_api_client.rb:7` + `installation_config.yml:193` | Checked S1: available until **2028-02-18**, 28 months out. Searched every WhatsApp call site for one that bypasses the key — send, media upload, templates, token debug, register/deregister, subscribed_apps, business profile, CSAT, contact info — all resolve through `GlobalConfigService.load('WHATSAPP_API_VERSION', Whatsapp::FacebookApiClient::DEFAULT_API_VERSION)`. Found none. | **Survives.** Two versions behind v26.0, inside window, one key, one constant. |
| **Agent 041's v3.2 claim and agent 042's v11.0 claim are accurate as stated.** | Read both gem files (`bot.rb:16`, `subscriptions.rb:12`) and the Instagram service (`:9,26,34-36`). Searched `app lib config custom` for any `base_uri` override of the gem and for any second definition of the Instagram default. Confirmed reachability: `app/jobs/send_reply_job.rb:22,32-36` routes every `Channel::FacebookPage` message to one of the two paths, choosing Instagram when `additional_attributes['type'] == 'instagram_direct_message'`. | **Both survive, and are worse than reported** — see §1.1 and R2 for the consequence. |
| **The health service's version comparison is correct.** `health_service.rb:45-46` | `[configured, 'v24.0'].max_by { |v| v.delete_prefix('v').split('.').map(&:to_i) }`. Tried `v24.10` → `[24,10] > [24,0]`, correct, which the old Float code got wrong. Tried bare `v26` → `[26] > [24,0]`, returned unchanged, no `.0` appended. Tried below-floor `v23.0` → clamps to v24.0. No Float anywhere in the path. | **Survives.** The regression the p7 record claims to have fixed is genuinely fixed. |
| **Instagram Login's v22.0 is in window.** `channel/instagram.rb:28` | S1: available until **2027-05-20**, 19 months out. | **Survives**, with a caveat worth recording: S10's own examples are at v25.0, so v22.0 is three versions behind what Meta demonstrates. In window is not current. |
| **The Instagram Login permissions are the current ones.** `app/helpers/instagram/integration_helper.rb:2` — `instagram_business_basic`, `instagram_business_manage_messages` | S10 lists exactly these two under Requirements → Permissions. S9 confirms they were introduced 2024-07-23 for the Instagram API with Instagram Login. | **Survives — exact match.** |
| **`instagram_basic` / `instagram_manage_messages` are retired names.** `app/javascript/dashboard/helper/facebookScopes.js:10-13` | This was my best candidate for a retired-permission finding and it failed. S9 has **no** deprecation entry for either. The only scope deprecation on S9 — "the old `scope` values will be deprecated on **January 27, 2025**", "Failure to do so will result in your app being unable to call the Instagram endpoints" — concerns the Instagram-Login short forms `business_basic`, `business_content_publish`, `business_manage_comments`, `business_manage_messages`, which this repository does not use. S9's 2025-12-03 entry still says "`instagram_basic` permission is required to access these endpoints". | **My attack failed; the claim survives.** (The constant is dead code — `includeInstagramScopes` is never passed `true` from either caller, `useFacebookPageConnect.js:50` or `facebook/Reauthorize.vue:26`. That is agent 093's finding, not a staleness finding.) |
| **The Page scopes are current.** `facebookScopes.js:3-8` — `pages_manage_metadata`, `business_management`, `pages_messaging`, `pages_show_list` | Searched S6 and S9 for deprecations of each. S6's only `pages_messaging` entry is the 2022-04-19 business-verification requirement, long settled. Nothing retires any of the four. | **Survives.** |
| **`allow_category_change` is correctly absent.** `custom/app/services/whatsapp/templates/meta_client.rb:25-27` asserts "Meta stopped supporting it on 2025-04-09 and the behaviour it enabled is now the default" | Looked for a page contradicting it. Found none. Also did not find the page asserting it. | **Not refuted, and not confirmed.** The date is uncited in the repository; it needs an S-row before the corpus repeats it. |
| **`HUMAN_AGENT` is still a valid tag.** three send paths | S6's 2026-03-27 retirement names only CONFIRMED_EVENT_UPDATE, ACCOUNT_UPDATE and POST_PURCHASE_UPDATE. `HUMAN_AGENT` is not among them. | **Survives**, though the full current tag list is not checkable — see §4. |
| **`locked: true` does not pin `INSTAGRAM_API_VERSION`** (`_ARBITRATION.md:96`, IR-10, agent 042) | Verified the mechanism rather than the conclusion: `app/controllers/super_admin/app_configs_controller.rb:32` does `InstallationConfig.where(name: key).first_or_create(value: value, locked: false)` and then writes, never consulting `locked`; `INSTAGRAM_API_VERSION` is in the `instagram` allow-list at `:74`; `InstallationConfig.editable` (`:61`) exists but is not used on this path. | **Agent 042's refutation survives.** Treat `locked:` in `installation_config.yml` as documentation, not enforcement. |

---

## 4. Not checkable

Each of these would change a finding, and none of them can be settled from the repository or from read-only
documentation. I am naming what would be needed rather than guessing.

1. **What `https://graph.facebook.com/v3.2/me/messages` actually returns today.** Requires a live Graph call,
   which §3 and §6.5 forbid absolutely. The documented answer is S3's substitution rule — served by the next
   oldest usable version, v21.0 — and that is as far as documentation goes. `_ARBITRATION.md:233` (U-03) assigns
   the live verification to agent 090; **agent 090 cannot make that call either** under the same rules, so the
   orchestrator should expect a documentation answer there too, not an observation. If the owner wants an
   observation, it needs a throwaway Meta test app and a sandbox number — never Account 21 and never a real
   credential.
2. **What `FB.init({version: 'v18.0'})` does on 2026-10-13.** S5 states `version` is required and that valid
   values are "currently available versions", but states no behaviour for an expired value, and S3's SDK
   paragraph is about SDK releases rather than this parameter. Needed: a Meta statement on expired `version`
   values in `FB.init`, or a browser observation against a test app.
3. **Whether the WhatsApp Business Management API still returns `error_subcode` 2388024.** S7 carries the
   "Deprecated. Will not be returned in v16.0+ responses" sentence on the Cloud API error-codes page; I found no
   page scoping that to messaging responses or exempting Business Management. R5 stands either way, but which of
   its two consequences applies — dead branch, or merely contrary to Meta's stated guidance — is unresolved.
4. **The "Upgrade API Version" value for this installation's Meta apps** (the Facebook app, the WhatsApp app and
   the Instagram app). This determines the version of all eleven Koala call sites and the two unversioned
   `graph.instagram.com` token calls (inventory rows 9–11). It is not in the repository. Reading it means signing
   in to the app dashboard as an app administrator — an owner action, not an agent action.
5. **Whether 360dialog still serves `/v1`** after Meta's On-Premises sunset, and what it proxies to. Needs
   360dialog's own documentation, which is not normative under §6.2, or an owner statement about whether any
   `default`-provider inbox exists in this installation.
6. **The current, complete Messenger message-tag list.** Both
   `/docs/messenger-platform/send-messages/message-tags` and the `/documentation/business-messaging/...`
   equivalent returned navigation markup with no body text on two attempts (S12, observational). R8 therefore
   rests on S6's changelog entry alone, which is normative for the three retired tags but is not a list of what
   remains.
7. **Whether any of the retirements in R6, R7 and R8 has already changed observed behaviour in this
   installation.** There is no Facebook or Instagram diagnostic to read — the p7 record's asymmetry claim
   (`:77-84`) survives: WhatsApp has `custom/app/services/whatsapp/diagnosis/` and an Account Health tab,
   Facebook and Instagram have nothing. Needed: production webhook payload samples, which §3 forbids touching.
8. **Embedded Signup version.** `_ARBITRATION.md:231` (U-01) records v2's deprecation on **2026-10-15**, two days
   from today. I confirm only that it is not determinable from the repository: `useWhatsappEmbeddedSignup.js` and
   `utils.js:134-137` pass a `config_id` from `WHATSAPP_CONFIGURATION_ID` and no version literal exists. It
   belongs to agent 013 and to the owner.

---

## 5. A freshness rule for the corpus

The brief asks what an article must state to age honestly, and how the program should record "checked on date X
against version Y". This is a requirement on the record, not an implementation; Agent 000 owns the contract.

### 5.1 Why a rule is forced rather than nice

Meta's expiry is arithmetic, not discretionary: S3, "A version will no longer be usable two years after the date
that the subsequent version is released." So **every version this installation pins already has a computable end
date** (§1.1). And S3's substitution rule means expiry is invisible at runtime. Together those two facts mean a
documentation claim about Meta behaviour has a known shelf life and no alarm clock. R10 establishes that the
corpus currently carries neither the date nor the version, so there is nothing for a future reader to check
against. The corpus is about to grow several times over; the rule has to exist before the growth, not after.

### 5.2 What an article must state

**(a) Name the version context, or deny version-dependence explicitly.** An article that states a Meta behaviour
must either name the version it was checked against or say in the body that the behaviour is version-independent.
Meta's own pages do this — S7: "Will not be returned in v16.0+ responses"; "Will be available with Graph API
version 23.0". An article that drops a qualifier its source carries is less precise than its source. Silence is
not allowed: it is the state R10 found, and it is indistinguishable from "we never checked".

**(b) State the installation's version, not Meta's latest.** The reader's product talks v24.0 for WhatsApp, v22.0
for Instagram Login, and — per R2 — *whatever Meta substitutes* for the Facebook Messenger and Instagram-via-Page
paths. An article that says "the current Graph API version is v26.0" is true about Meta and useless to the
reader. The useful pair is **(what this installation sends, what Meta is serving it as)**, and for inventory rows
4–6 those differ. This is the single most important clause, because it is the one that makes R2 visible to a
reader instead of hidden.

**(c) Never write "the API" where "a version of the API" is meant, and never present an expired pin as a pin.**
"We are on v3.2" is false. The honest sentence is: "this path sends to the v3.2 URL; because v3.2 expired on
2021-05-04, Meta serves it on the oldest version it still supports — v20.0 until 2026-09-24, v21.0 since."

**(d) Carry the end date in the body.** Because (a)'s version has a computable expiry from S1, an article should
state the date its version context stops being served. That lets a reader in 2027 see the article is stale
without consulting Meta.

### 5.3 How to record "checked on date X against version Y"

Per §2's content-model row, `Article` already has a `meta` jsonb and the corpus already has YAML front matter.
This extends both rather than adding anything:

```yaml
meta_version_dependent: true          # false means "checked, and the behaviour does not depend on a version"
meta_checked_on: 2026-10-13           # when a human last verified it against Meta
meta_checked_against: v24.0           # the version THIS installation calls on the surface the article describes
meta_served_as: v21.0                 # only where it differs from the above — i.e. an expired pin (R2)
meta_version_expires: 2028-02-18      # from Meta's version table, for meta_checked_against
meta_latest_at_check: v26.0           # Meta's current version on meta_checked_on
meta_sources:
  - https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/
```

Four properties make this age honestly rather than merely look thorough:

- **`meta_checked_against` is the installation's version**, so the article is checked against what the reader's
  product actually does. The pair with `meta_latest_at_check` is what makes drift legible: v24.0 against v26.0 is
  two behind and in window; v18.0 against v26.0 is past end of life.
- **`meta_served_as` exists only because of R2.** Without it the corpus cannot express the single most dangerous
  fact in this report — that three send paths run on a version nobody chose.
- **`meta_version_expires` is copied from Meta's table, not computed per article**, so it is auditable against
  one checked-in copy of S1.
- **`meta_version_dependent: false` is a positive assertion**, so "no version named" stops being ambiguous
  between "independent" and "never checked". Per §6.5, not-checked must say not-checked.

### 5.4 What the program must hold centrally

One checked-in copy of Meta's version table (S1) with its own `checked_on`, as the single place the expiry dates
come from. Then the freshness question is two date comparisons an existing read-only audit can make — the same
shape as the `lynomia:docs:seo_audit` task the charter's §2 names as the SEO system to extend:

1. articles whose `meta_checked_on` is older than the review interval;
2. articles whose `meta_checked_against` names a version whose `available until` date has passed — which today
   would flag every article describing the Facebook Messenger, Instagram-via-Page or Facebook-OAuth surfaces.

Two dates, one table, no new system. The second check is the one that would have caught v18.0 on 2026-01-27,
v11.0 in 2023, and v3.2 in 2021.

### 5.5 The rule's hardest clause

The table itself goes stale. S1 carries "TBD" for v26.0's end date, so the checked-in copy must record the date
it was read and must be re-read, not trusted. A freshness rule whose own source has no freshness date reproduces
the defect it exists to prevent.
