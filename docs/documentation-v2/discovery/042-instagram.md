---
agent: 042
scope: Instagram integration — connect/OAuth/permissions, webhooks, inbound (story replies, mentions, echoes), outbound and its restrictions, reauthorization, disconnect, every surfaced error
confidence: high
---

## 1. What the feature is

Lynomia has **two different Instagram integrations behind one product word**, and almost every finding below
turns on which one an account is on.

| | **Instagram Login** (current) | **Instagram via Facebook Page** (legacy) |
|---|---|---|
| Channel model | `Channel::Instagram` (`app/models/channel/instagram.rb:17`) | `Channel::FacebookPage` with a non-null `instagram_id` (`app/models/channel/facebook_page.rb:21`) |
| How it is created | Instagram's own OAuth, `Instagram::CallbacksController` | side effect of connecting a Facebook Page — `Facebook::PageDetailsService` reads `instagram_business_account` and persists it as `instagram_id` (`app/services/facebook/page_details_service.rb:6,11`, written at `app/controllers/api/v1/accounts/callbacks_controller.rb:38-39`) |
| Credential | one `access_token` + `expires_at` (60-day long-lived IG token) | the Page's `page_access_token` |
| Host | `graph.instagram.com` | `graph.facebook.com` (and Koala, unversioned) |
| Graph version | `v22.0`, one constant, `INSTAGRAM_API_VERSION` | `v11.0` for sends (`INSTAGRAM_MESSENGER_API_VERSION`); **unversioned** for profile/story reads via Koala |
| Offered in the UI? | yes, **Settings → Inboxes → Add → Instagram** | no — there is no "connect Instagram through Facebook" tile; it only happens as a by-product of a Page connect |
| Conversation marker | none | `additional_attributes.type == 'instagram_direct_message'` (`app/builders/messages/instagram/messenger/message_builder.rb:30-32`) |

Both receive on the **same webhook endpoint** and both are resolved by the same `instagram_id` lookup, Instagram
Login first (`app/jobs/webhooks/instagram_events_job.rb:117-126`). A single Instagram account can therefore exist
as two inboxes at once, which is why there is migration copy in the product (§3).

`instagram_id` carries a **global unique index** (`db/schema.rb:733`) plus a model-level uniqueness validation
(`app/models/channel/instagram.rb:31`): one Instagram account can be connected to exactly one `Channel::Instagram`
row installation-wide, not per account.

### The Graph version, and where it is centralized

`Channel::Instagram::DEFAULT_API_VERSION = 'v22.0'` (`app/models/channel/instagram.rb:28`) is the single literal
for the Instagram Login generation. Five call sites read it through `GlobalConfigService.load('INSTAGRAM_API_VERSION', …)`:
`app/models/channel/instagram.rb:82`, `app/services/instagram/send_on_instagram_service.rb:14`,
`app/services/instagram/user_details_service.rb:15`, `app/services/instagram/message_text.rb:79`,
`app/builders/messages/instagram/message_builder.rb:40`. The seeded row is `v22.0`, **`locked: true`**
(`config/installation_config.yml:611-615`).

The legacy path is deliberately **not** on that key: `Instagram::Messenger::SendOnInstagramService::DEFAULT_API_VERSION = 'v11.0'`
read through `INSTAGRAM_MESSENGER_API_VERSION` (`app/services/instagram/messenger/send_on_instagram_service.rb:9,34-36`,
seeded `config/installation_config.yml:157-161`), with the reason written into the file: one key for two different
APIs would mean bumping one silently bumps the other. Its *read* path has no version at all — Koala is never
configured with `api_version`, so `Instagram::Messenger::MessageText:10-11` and
`Messages::Instagram::Messenger::MessageBuilder:9-10` issue unversioned Graph calls (corroborates
`docs/p7/00-discovery-findings.md:665`).

**`locked: true` does not make `INSTAGRAM_API_VERSION` read-only.** `locked` only narrows
`InstallationConfig.editable` (`app/models/installation_config.rb:61`), which is used by the generic Installation
Configs listing (`app/controllers/super_admin/installation_configs_controller.rb:26`) — but the per-group App
Configs form renders and saves every key in its allow-list regardless of `locked`
(`app/controllers/super_admin/app_configs_controller.rb:74`, `app/views/super_admin/app_configs/show.html.erb:18-65`,
`create` at `:26-35` with `locked: false` on first create). So Super Admin → Settings → Instagram **can** change it.
This corrects `docs/p7/00-discovery-findings.md:703-705` (SHO-48), which treated it as uneditable.

## 2. Surfaces and routes

| Surface | Path / file |
|---|---|
| Add-channel tile | `app/javascript/dashboard/routes/dashboard/settings/inbox/ChannelList.vue:74-79` (key `instagram`) |
| Connect page | `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Instagram.vue`, mounted via `ChannelFactory.vue:11,36` |
| Connect page route | `GET /app/accounts/:account_id/settings/inboxes/new/instagram` (`config/routes.rb:22`, `app_new_instagram_inbox`) |
| Onboarding tile | `routes/dashboard/onboarding/inbox-setup/constants.js:46-48`, gated at `useChannelConfig.js:31-34`, connected at `useChannelConnect.js:33-45` |
| Authorize URL (API) | `POST /api/v1/accounts/:id/instagram/authorization` → `Api::V1::Accounts::Instagram::AuthorizationsController#create` (`config/routes.rb:268-270`, controller `:5-22`) |
| Frontend client | `app/javascript/dashboard/api/channel/instagramClient.js:9-11` |
| OAuth callback | `GET /instagram/callback` → `Instagram::CallbacksController#show` (`config/routes.rb:571`, controller `:5-18`) |
| Webhook verify | `GET /webhooks/instagram` → `Webhooks::InstagramController#verify` (`config/routes.rb:556`; `MetaTokenVerifyConcern#verify:9-17`) |
| Webhook events | `POST /webhooks/instagram` → `#events` (`config/routes.rb:557`, controller `:6-24`) |
| Async processing | `Webhooks::InstagramEventsJob` (`app/jobs/webhooks/instagram_events_job.rb`) |
| Inbound (Login) | `Instagram::MessageText` → `Messages::Instagram::MessageBuilder` |
| Inbound (legacy) | `Instagram::Messenger::MessageText` → `Messages::Instagram::Messenger::MessageBuilder` |
| Read receipts | `Instagram::ReadStatusService` (both paths, `instagram_events_job.rb:140-143`) |
| Outbound (Login) | `Instagram::SendOnInstagramService` ← `SendReplyJob::CHANNEL_SERVICES` (`app/jobs/send_reply_job.rb:11`) |
| Outbound (legacy) | `Instagram::Messenger::SendOnInstagramService` ← `SendReplyJob#send_on_facebook_page:32-38` |
| Inbox settings | `routes/dashboard/settings/inbox/Settings.vue` — reauthorize banner `:819-824`, duplicate banner `:838-843`, restriction banner `:844-866` |
| Reauthorize | `settings/inbox/channels/instagram/Reauthorize.vue` → same `POST …/instagram/authorization` |
| Finish-setup banner | `settings/inbox/FinishSetup.vue:45-53,188-191` |
| Conversation banners | `components/widgets/conversation/MessagesView.vue:467-474` (restriction), `:483-488` (old-inbox) |
| Composer gating | `components/widgets/conversation/ReplyBox.vue:232-254`, uploads `:783-797` |
| Story bubble | `components-next/message/bubbles/InstagramStory.vue`, selected at `components-next/message/Message.vue:342-350` |
| API payload | `app/views/api/v1/models/_inbox.json.jbuilder:34,61,62,204` |
| Operator config | Super Admin → Settings → Instagram (`app/controllers/super_admin/app_configs_controller.rb:74`) |

### Connect flow, step by step

1. `POST …/instagram/authorization` builds Instagram's authorize URL with
   `scope=instagram_business_basic,instagram_business_manage_messages`, `enable_fb_login=0`, `force_reauth=true`,
   and `state` = a JWT signed with `INSTAGRAM_APP_SECRET` carrying `{sub: account_id, iat}` and an optional
   `return_to: 'onboarding'` (`authorizations_controller.rb:7-16`; scopes at
   `app/helpers/instagram/integration_helper.rb:2`; token at `:9-22`).
2. Browser goes to `https://www.instagram.com/oauth/authorize` (`app/controllers/concerns/instagram_concern.rb:9-15`).
3. `GET /instagram/callback` exchanges the code at `https://api.instagram.com/oauth/access_token`
   (`callbacks_controller.rb:24-28`), then exchanges for a long-lived token at
   `https://graph.instagram.com/access_token` with `grant_type=ig_exchange_token`
   (`instagram_concern.rb:28-38`).
4. `Instagram::UserDetailsService` reads `/me?fields=id,username,user_id,name,profile_picture_url,account_type`
   (`:14-21`).
5. Channel + inbox are created in one transaction, named after the IG `username`, with
   `expires_at = now + expires_in` (`callbacks_controller.rb:136-156`). An existing channel **for the same account**
   is updated instead (`:120-134`).
6. `reauthorized!` clears the reauthorization latch (`:115`).
7. `after_create_commit :subscribe` POSTs `{instagram_id}/subscribed_apps` with
   `subscribed_fields = messages, message_reactions, messaging_seen` (`channel/instagram.rb:33,48-56`).
8. Redirect: onboarding → inbox setup; existing channel → inbox settings; new channel → the agents step
   (`callbacks_controller.rb:33-39`).

**The Page link does not exist on this path.** Instagram Login needs no Facebook Page, no Page selection step and
no `pages_*` scope. The Page link matters only for the legacy path, and there the Facebook connect flow requests
**no Instagram scopes at all**: `buildFacebookLoginScopes()` is called with no arguments by both callers, so the
`INSTAGRAM_SCOPES` branch is dead (`app/javascript/dashboard/helper/facebookScopes.js:10-22`,
`composables/useFacebookPageConnect.js:50`, `settings/inbox/facebook/Reauthorize.vue:26`). Verified still true at
this HEAD; this is `docs/p7/00-discovery-findings.md:1148` (EXT-01) unchanged.

### Webhook handling

`#events` accepts only `object == 'instagram'` (case-insensitive) and otherwise returns 422
(`webhooks/instagram_controller.rb:8,20-23`). Signature: `X-Hub-Signature-256`, HMAC-SHA256 over the raw body,
`secure_compare`, **fail-closed** — any secret in `meta_app_secrets` may match
(`concerns/meta_token_verify_concern.rb:21-40`). For Instagram the candidate list is per-channel secrets plus
`INSTAGRAM_APP_SECRET` and `FB_APP_SECRET` (`instagram_controller.rb:45-51`). The per-channel half is dead work:
neither `Channel::Instagram` nor `Channel::FacebookPage` has `app_secret` or `provider_config`
(schemas at `channel/instagram.rb:1-16`, `channel/facebook_page.rb:1-19`), so
`instagram_channels_from_payload` (`:57-66`) runs two DB lookups per messaging entry and contributes nothing.

If a payload contains an echo (`message.is_echo`), the job is enqueued with a deliberate 2-second delay to avoid
racing the send API (`instagram_controller.rb:11-17`).

`Webhooks::InstagramEventsJob` takes a 3-second Redis mutex keyed on sender + IG account, retries three times on
lock conflict and then processes **without** the lock rather than dropping the webhook (`:11,19-31`). It handles
exactly three event keys — `message`, `read`, `postback` (`:14,128-130`) — reading from `entry[:messaging]` or
falling back to `entry[:standby]` (`:153-155`). An `entry` carrying `changes` is treated as Meta's app-review test
payload and routed to `Instagram::TestEventService` (`:70-82`), which writes the test message into
**`Channel::Instagram.last`** — the most recently created Instagram channel on the whole installation
(`app/services/instagram/test_event_service.rb:21-26`).

### Inbound message handling

`Instagram::BaseMessageText#perform` (`app/services/instagram/base_message_text.rb:9-25`): resolve inbox, drop if
`reauthorization_required?`, handle `is_deleted` by replacing the message body with
`I18n.t('conversations.messages.deleted')` and destroying its attachments (`:51-59`), fetch the contact on first
contact, then build.

Story replies and mentions are both handled in `Messages::Instagram::BaseMessageBuilder`:

- **Story reply** — `message.reply_to.story` (`:86-88`). Creates an `ig_story` attachment from
  `story.url`, downloads it, sets `content_attributes.image_type = 'ig_story_reply'` and stores
  `story_id/story_sender/story_url` via `Message#save_story_info` (`:111-134`; `app/models/message.rb:236-245`).
  A failed download is swallowed with a warning (`:128-131`).
- **Story mention** — arrives as an attachment of type `story_mention`; `fetch_story_link` calls
  `get_story_object_from_source_id(message.source_id)` for `story,from` and writes
  `I18n.t('conversations.messages.instagram_story_content', story_sender: …)`
  (`app/builders/messages/messenger/message_builder.rb:26,84-97`).
- **Shared story / shared post** — `ig_story` and `ig_post` attachments get fixed content
  (`:99-112`); `ig_story` reads its URL from `payload.story_media_url`, not `payload.url` (`:63-68`).
- **Reply-to a message** — `message.reply_to.mid` → `content_attributes.in_reply_to_external_id` (`:90-92,167`).
- **Echoes** — `message.is_echo` flips sender/recipient and produces an `outgoing` message with
  `content_attributes.external_echo = true`, status `delivered`, no sender (`:30-39,156-173`).
- **Dedupe** — `Message.find_by(source_id: mid)` **account-wide**, because the same DM can arrive twice when one
  IG account is connected through both generations (`:94-99,175-183`).
- **Unsupported** — `template`, `unsupported_type`, `ephemeral` attachments are skipped
  (`messenger/message_builder.rb:150-152`); a message whose only attachments are unsupported and which has no text
  is not created at all (`:101`).

### Outbound send and its restrictions

`Instagram::BaseSendService` sends each attachment as its own Graph message, then the text
(`app/services/instagram/base_send_service.rb:8-23`), so a reply with two images and a caption is three API calls
and three `message_id`s, only the last of which is stored on the message (`:56-60`).

| Restriction | Where |
|---|---|
| Only outgoing, non-private, no `source_id`, not `voice_call` | `app/services/base/send_on_channel_service.rb:13-19,42-51` |
| Messaging window: **24h**, or **7 days** when `ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT` | `app/services/conversations/message_window_service.rb:23-24,55-65` |
| `HUMAN_AGENT` tag added to every send when that config is on | `send_on_instagram_service.rb:25-33` (legacy: `ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT`, `messenger/send_on_instagram_service.rb:44-52`) |
| Markdown is flattened to IG-safe text (`*bold*`, `_italic_`, links become bare URLs) | `app/services/messages/markdown_renderer_service.rb:7-8,69-73`, `markdown_renderers/instagram_renderer.rb` |
| Composer marks: no headings, no blockquote, no link mark | `app/javascript/dashboard/constants/editor.js:99-113` |
| Uploads: image png/jpeg/gif ≤16MB, video mp4/ogg/avi/mov/webm ≤25MB, audio aac/m4a/wav/mp4 ≤25MB | `@chatwoot/utils` CHANNEL_CONFIGS (`node_modules/@chatwoot/utils/dist/utils.cjs.development.js:2155-2167`, citing Meta's messaging-api requirements page), applied via `app/javascript/shared/helpers/FileHelper.js:49-73` and `ReplyBottomPanel.vue:205-219` |
| Attachment type coerced to `image/audio/video/file` | `base_send_service.rb:81-85` |
| `DISABLE_META_MESSAGE_SENDING` (cloud only) forces the composer into private-note mode | `ReplyBox.vue:232-254`, getter `app/javascript/shared/store/globalConfig.js:69-70` |

The legacy send path additionally computes `appsecret_proof` from `FB_APP_SECRET`
(`messenger/send_on_instagram_service.rb:21-23,38-42`); the Instagram Login path sends no proof.

### Reauthorization and token refresh

`Channel::Instagram#access_token` is not an attribute read — every call goes through
`Instagram::RefreshOauthTokenService` (`channel/instagram.rb:75-77`). That service returns `nil` if
`expires_at` is blank or past; refreshes via `graph.instagram.com/refresh_access_token` with
`grant_type=ig_refresh_token` only when the token is valid, ≥24h old and inside 10 days of expiry; and on any
refresh failure logs and falls back to the stored token (`refresh_oauth_token_service.rb:12-19,34-46,51-83`).

`AUTHORIZATION_ERROR_THRESHOLD = 1` (`channel/instagram.rb:25`) overrides the default of 2
(`app/models/concerns/reauthorizable.rb:16`), so **one** Graph code 190 latches the inbox, invalidates the inbox
cache, dispatches a reauthorization event and emails the administrators via
`ChannelNotificationsMailer#instagram_disconnect` (`reauthorizable.rb:30-48,91`;
`app/mailers/administrator_notifications/channel_notifications_mailer.rb:7-10`;
`app/views/mailers/administrator_notifications/channel_notifications_mailer/instagram_disconnect.liquid`).
Code 190 is detected in three places: sends (`base_send_service.rb:69-78`), profile fetch
(`message_text.rb:44`) and story fetch (`messages/instagram/message_builder.rb:27`).

Reauthorizing re-runs the full OAuth flow from the inbox-settings banner; the callback updates the token and calls
`reauthorized!` (`callbacks_controller.rb:107-117`).

### Disconnect

Deleting the inbox destroys the channel (`app/models/inbox.rb:62` `dependent: :destroy`), whose
`before_destroy :unsubscribe` DELETEs `{instagram_id}/subscribed_apps` and **swallows every error**
(`channel/instagram.rb:34,62-73`). There is no separate "disconnect Instagram" action; there is no UI that
unsubscribes without deleting.

## 3. User-visible states

| State | What produces it |
|---|---|
| Tile greyed out / warning banner on the connect page | `isMetaInboxCreationDisabled` = cloud **and** `DISABLE_META_INBOX_CREATION`; `Instagram.vue:20,26-28,97-120` |
| Onboarding tile hidden | missing `INSTAGRAM_APP_ID`, or `channel_instagram` feature off on cloud (`useChannelConfig.js:31-34`; flag `config/features.yml:183-185`, default enabled) |
| Settings tile always shown | `ChannelList.vue:74-79` has **no** config or flag check — the Instagram card appears even with no `INSTAGRAM_APP_ID`, and the connect button then redirects into a broken OAuth URL |
| "Connect your Instagram Profile" + button | default state, `Instagram.vue:80-96` |
| Button spinner | `isRequestingAuthorization`, `Instagram.vue:25,91-93` |
| Error panel on the connect page | any `error_message` query param from the callback redirect, `Instagram.vue:30-50,68-74` |
| Agents step, then Finish | brand-new channel (`callbacks_controller.rb:38`) |
| Inbox settings, no agents step | the account already had this channel (`callbacks_controller.rb:36`) |
| Red "Your inbox is disconnected…" banner with reconnect action | `reauthorization_required` true, `Settings.vue:367-368,819-824` → `InboxReconnectionRequired.vue:23-30` |
| Amber "migrated to the new Instagram channel inbox" on the **legacy** inbox | a `Channel::Instagram` exists with the same `instagram_id`, `Settings.vue:381-390,838-843` |
| Amber "previously linked to a different inbox and has now been migrated here" on the **new** inbox's finish page | a `Channel::FacebookPage` exists with the same `instagram_id`, `FinishSetup.vue:45-53,188-191` |
| Amber Meta-incident banner in settings and in the conversation | `DISABLE_META_MESSAGE_SENDING` on cloud, `Settings.vue:370-371,844-866`, `MessagesView.vue:197-199,467-474` |
| Composer locked to private note | same flag, `ReplyBox.vue:239-254` |
| Red "you cannot reply" banner | `can_reply` false — outside the 24h/7d window, `MessagesView.vue:476-482` |
| Grey "This story is no longer available." bubble | story media fails to load in the browser (`InstagramStory.vue:65-73`) or Graph refused the story fetch (`messages/instagram/message_builder.rb:31-34`) |
| "Replied to your story:" label | `content_attributes.image_type == 'ig_story_reply'` (`InstagramStory.vue:21-22,48-50`) |
| "%{sender} mentioned you in the story:" | `fetch_story_link` success (`messenger/message_builder.rb:95`) |
| "Shared story" / "Shared post" | `ig_story` / `ig_post` attachments (`messenger/message_builder.rb:103,110`) |
| "This message was deleted" | `message.is_deleted` webhook (`base_message_text.rb:58`) |
| Contact named `Unknown (IG: …)` | Graph error 9010 or 100 on profile fetch (`message_text.rb:60,65,88-93`) |
| Silence — inbound messages dropped, nothing shown | reauthorization latched (`base_message_text.rb:15-18`, `base_message_builder.rb:12`), or webhook signature rejected, or `subscribe` failed at create |

`connection_state` (which reports "the provider authorization expires soon" inside ten days, and reuses
Instagram's own refresh window as the threshold) is emitted on every inbox payload
(`app/views/api/v1/models/_inbox.json.jbuilder:204`, `custom/app/services/channels/connection_state.rb:30-32,106-121`)
but **no frontend file reads it** — grep for `connection_state` across `app/javascript` returns nothing outside
specs. It is operator-facing only (`custom/app/services/operations/account_health.rb`, `channel_matrix.rb`).

## 4. Errors and validation messages

Frontend strings (all under `INBOX_MGMT.ADD.INSTAGRAM`, `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json`):

| Key | Exact string | Line | Shown where |
|---|---|---|---|
| `ERROR_MESSAGE` | "There was an error connecting to Instagram, please try again" | `:61` | connect page heading for any non-400 callback error (`Instagram.vue:43`) |
| `ERROR_AUTH` | "There was an error connecting to Instagram, please try again" | `:62` | connect-page sub-text for a 400 (`Instagram.vue:41`), and the reauthorize toast (`instagram/Reauthorize.vue:25`) |
| `HELP` | "To add your Instagram profile as a channel, you need to authenticate your Instagram Profile by clicking on 'Continue with Instagram' " | `:60` | connect page |
| `RESTRICTED_WARNING` | "Instagram inbox creation is temporarily unavailable due to an API-level issue on Meta's side, not a problem with Chatwoot. …" | `:65` | connect page banner |
| `SETTINGS_RESTRICTED_WARNING` | "Instagram messaging is currently affected by an API-level issue on Meta's side, not a problem with Chatwoot. …" | `:66` | inbox settings banner |
| `NEW_INBOX_SUGGESTION` | "This Instagram account was previously linked to a different inbox and has now been migrated here. …" | `:63` | finish-setup banner |
| `DUPLICATE_INBOX_BANNER` | "This Instagram account was migrated to the new Instagram channel inbox. You won't be able to send/receive Instagram messages from this inbox anymore." | `:64` | legacy inbox settings |
| `STATUS_LINK` | "View status updates" | `:67` | link beside both restriction banners |

Other frontend strings: `CONVERSATION.INSTAGRAM_RESTRICTION_BANNER` and `…_STATUS_LINK`
(`conversation.json:59-60`), `CONVERSATION.OLD_INSTAGRAM_INBOX_REPLY_BANNER` (`:58`),
`COMPONENTS.FILE_BUBBLE.INSTAGRAM_STORY_UNAVAILABLE` / `INSTAGRAM_STORY_REPLY` (`settings.json:295-296`),
`INBOX_MGMT.RECONNECTION_REQUIRED` / `CLICK_TO_RECONNECT` (`inboxMgmt.json:9-10`),
`CONVERSATION.FILE_TYPE_NOT_SUPPORTED` on a rejected paste (`ReplyBox.vue:792-796`),
`ONBOARDING_INBOX_SETUP.META_RESTRICTION.MESSAGE` and `…ERROR` on the onboarding path (`useChannelConnect.js:34,44`).

`CONVERSATION.REPLIED_TO_STORY` and `CHAT_LIST.LINK_TO_STORY` exist in en.json's siblings but have **no reader in
`app/javascript`** — dead keys from the deprecated bubble components.

Backend strings (`config/locales/en.yml:445-448`): `instagram_story_content` "%{story_sender} mentioned you in the
story: ", `instagram_deleted_story_content` "This story is no longer available.",
`instagram_shared_story_content` "Shared story", `instagram_shared_post_content` "Shared post".
Plus `errors.billing.channel_not_included` "Your plan does not include the %{channel} channel. Upgrade your plan
to connect it." (`config/locales/en.yml:303`), reached through `Billing::InboxLimit`
(`custom/app/models/billing/inbox_limit.rb:36-45`) when a plan's `channel_entitlements` excludes
`Channel::Instagram`.

Provider-relayed errors reaching the user:

| Code | Handling | Where |
|---|---|---|
| 190 | latch reauthorization (threshold 1) **and** message marked failed with `"190 - <message>"` | `base_send_service.rb:69-78`, `message_text.rb:44`, `messages/instagram/message_builder.rb:27` |
| 230 (user consent required) | silently ignored; no contact enrichment | `message_text.rb:53`, `messenger/message_text.rb:31-34` |
| 9010 (no matching Instagram user) | contact created as `Unknown (IG: <id>)` on the Login path; ignored entirely on the legacy path | `message_text.rb:60`, `messenger/message_text.rb:39-44` |
| 100 (object missing / no permission) | same `Unknown (IG: …)` contact | `message_text.rb:65` |
| 1609005 (link scrape failed) | attachments destroyed, body replaced with "This story is no longer available." | `messages/instagram/message_builder.rb:31-34` |
| anything else | logged, sent to Sentry, empty hash returned → contact not enriched, message still created | `message_text.rb:67-75` |
| any send failure | `Messages::StatusUpdateService(message, 'failed', "<code> - <message>")` | `base_send_service.rb:62-66` |

Error strings surfaced by the OAuth callback are **raw provider text**, not localized: `error_description` from
Instagram's cancel redirect (`callbacks_controller.rb:79-88`), the JSON body of an `OAuth2::Error`
(`:61-74`), `CustomExceptions::Inbox::LimitExceeded#message` "Account limit exceeded. Upgrade to a higher plan"
(`lib/custom_exceptions/inbox/limit_exceeded.rb:5`) — which is **never raised anywhere in this tree**, so that
rescue at `callbacks_controller.rb:14` is dead here — or `error.message` for anything else, including
`ActiveRecord::RecordInvalid`. Two real ones a user can hit:

- **"Validation failed: Instagram has already been taken"** — the Instagram account is already connected on a
  *different* Lynomia account. `find_channel_by_instagram_id` scopes by account
  (`callbacks_controller.rb:120-122`) so it does not find the row, `create!` then trips the global uniqueness
  index (`channel/instagram.rb:31`, `db/schema.rb:733`), and the user sees "There was an error connecting to
  Instagram, please try again" with the Rails validation sentence underneath.
- **"Validation failed: Your plan does not include the Instagram channel. Upgrade your plan to connect it."** —
  same shape, via the billing validation.

## 5. Failure paths

1. **No app secret configured → every webhook is 401.** `meta_signature_verification_required?` is unconditionally
   true (`meta_token_verify_concern.rb:50-52`) and `valid_meta_signature?` skips blank secrets
   (`:34-36`), so with neither `INSTAGRAM_APP_SECRET` nor `FB_APP_SECRET` set, nothing matches and every delivery
   is rejected with a log line only (`:25-27`). The inbox looks healthy and receives nothing. Nothing in the
   product surfaces this.
2. **`subscribe` failing at create is invisible.** `after_create_commit :subscribe` rescues every error and
   returns `true` (`channel/instagram.rb:57-59`). The inbox exists, the agents step completes, Finish says
   "Nailed It!", and no message ever arrives. Same for `unsubscribe` on delete (`:70-72`) — Meta keeps sending to
   an endpoint that no longer resolves a channel, and the job silently drops it (`instagram_events_job.rb:58`).
   **Unverified, and untestable here:** `subscribe` passes `subscribed_fields` as a Ruby array in HTTParty's
   `query:`, which serializes as repeated `subscribed_fields[]=…` rather than the comma-separated list Graph's
   reference documents; the legacy path sends a JSON body instead
   (`vendor/.../facebook-messenger-2.0.1/lib/facebook/messenger/subscriptions.rb:30-41`). Whether Graph accepts
   the bracketed form cannot be established without calling Meta.
3. **A token that expires while the inbox is quiet is a dead end.** Nothing refreshes proactively: the only caller
   of `Instagram::RefreshOauthTokenService` is `Channel::Instagram#access_token` (`channel/instagram.rb:76`) —
   there is no scheduled job (no Instagram entry in `app/jobs/` beyond the webhook job, nothing in
   `config/schedule.yml`). After 60 days with no inbound webhook and no send, `expires_at` passes, `token_valid?`
   is false and `access_token` returns **`nil`** forever (`refresh_oauth_token_service.rb:12-28`). Sends then go
   out with `access_token=` empty. Whether Graph answers 190 — the only code that latches reauthorization — for a
   blank token is **unverified**; if it does not, the inbox never shows the red reconnect banner and the only
   signal is `connection_state`, which no UI reads (§3).
4. **Reauthorization silently discards inbound messages.** Once latched, `Instagram::BaseMessageText#perform`
   returns early (`base_message_text.rb:15-18`) and `BaseMessageBuilder#perform` returns early
   (`base_message_builder.rb:12`). Messages sent during the outage are not stored and are not recoverable from
   Lynomia afterwards — Meta does not redeliver on reauthorization. The banner says "You won't receive new
   messages until you reauthorize it" (`inboxMgmt.json:9`), which is accurate but does not say the gap is permanent.
5. **`DISABLE_META_MESSAGE_SENDING` is frontend-only.** No Ruby reads it except the allow-list and the
   `window.globalConfig` exposure (`super_admin/app_configs_controller.rb:9`, `dashboard_controller.rb:30`). The
   dashboard composer is forced into note mode, but the API, automations, campaigns and bots still call
   `SendReplyJob`. Both incident flags are also seeded **`value: true`** (`config/installation_config.yml:264-274`)
   and are only honoured on `deploymentEnv === 'cloud'` (`shared/store/globalConfig.js:67-70`) — so a self-hosted
   Lynomia install shows no incident banner regardless, and a cloud one blocks Instagram creation out of the box.
6. **`Instagram::TestEventService` writes into a real inbox.** Meta's app-review test payload (sender `12334`,
   recipient `23245`) creates a contact, conversation and message in `Channel::Instagram.last`
   (`test_event_service.rb:17,21-26`), which on a multi-tenant installation is whichever tenant connected most
   recently. The test event bypasses signature verification only if unsigned — it does not — but it does bypass
   tenant resolution entirely.
7. **Attachment downloads are best-effort.** A story attachment whose media URL has expired leaves an attachment
   row with no blob and a warning in the log (`base_message_builder.rb:128-131`); the bubble then shows "This story
   is no longer available." Instagram CDN URLs are short-lived, so this is the expected shape of a delayed job.
8. **Partial outbound delivery is not represented.** Attachments are sent before text and each is its own call
   (`base_send_service.rb:8-23`); if the second of three succeeds and the third fails, the single `Message` row is
   marked `failed` with one error, and only the last successful `message_id` was stored. An agent cannot tell what
   the customer received.
9. **No diagnostic surface.** Unlike WhatsApp (`custom/app/services/whatsapp/diagnosis/`, an Account Health tab,
   `Whatsapp::DeliveryFailure` classification), Instagram has no health tab, no error classification and no
   article mapping — a failed Instagram message shows `"<code> - <message>"` from Meta and nothing else.
   Corroborated by `docs/p7/07-graph-api-versions.md` ("Facebook and Instagram have nothing equivalent").
10. **Subscribed but unhandled.** `message_reactions` is subscribed at create (`channel/instagram.rb:53`) but
    `SUPPORTED_EVENTS` has no `reaction` key (`instagram_events_job.rb:14`), so reactions are received and
    discarded. Conversely `postback` is handled (`:145-151`) but `messaging_postbacks` is not in the subscribed
    fields — on the Instagram Login path those events should never arrive.
11. **The OAuth `state` JWT never expires.** `token_payload` sets `sub` and `iat` but no `exp`
    (`integration_helper.rb:18-22`), and `JWT.decode(..., verify_expiration: true)` does not fail on a missing
    `exp`. Contrast the shared base controller, which uses a 15-minute sgid
    (`api/v1/accounts/oauth_authorization_controller.rb:15`). A captured authorize URL stays valid indefinitely.
12. **`verify` accepts an empty token when none is configured.** `valid_token?` compares against
    `GlobalConfigService.load('IG_VERIFY_TOKEN', '')` and `INSTAGRAM_VERIFY_TOKEN` with the same `''` default
    (`webhooks/instagram_controller.rb:38-43`), so on an installation with neither set, `hub.verify_token=` (empty)
    verifies. It only echoes `hub.challenge`; event delivery is still signature-gated. Observational.

## 6. Permissions

| Surface | Gate | Where |
|---|---|---|
| `POST …/instagram/authorization` | **administrator only** — `Pundit::NotAuthorizedError` otherwise | `api/v1/accounts/oauth_authorization_controller.rb:2,28-30` |
| `GET /instagram/callback` | no authentication; the account comes from the signed `state` JWT | `instagram/callbacks_controller.rb:158-162`, `integration_helper.rb:28-32` |
| `POST /webhooks/instagram` | `ActionController::API`, no auth; HMAC signature only | `webhooks/instagram_controller.rb:1-4` |
| Onboarding Instagram tile | `INSTAGRAM_APP_ID` present **and** `channel_instagram` cloud feature flag | `useChannelConfig.js:31-34`, `config/features.yml:183-185` |
| Settings Instagram tile | **nothing** | `ChannelList.vue:74-79` |
| Inbox creation | cloud + `DISABLE_META_INBOX_CREATION` blocks it in the UI only; `Billing::Entitlements.channel_allowed?` blocks it server-side at every entry point | `Instagram.vue:26-28,53`, `useChannelConnect.js:33-36`; `custom/app/models/billing/inbox_limit.rb:14-45`, `custom/app/services/billing/entitlements.rb:59-69` |
| Sending | cloud + `DISABLE_META_MESSAGE_SENDING` in the composer only (no server guard) | `ReplyBox.vue:232-254` |
| `INSTAGRAM_API_VERSION`, app id/secret, verify token, human-agent toggle | Super Admin, Instagram group | `super_admin/app_configs_controller.rb:74` |
| `IG_VERIFY_TOKEN`, `INSTAGRAM_MESSENGER_API_VERSION` | Super Admin, **Facebook** group | `super_admin/app_configs_controller.rb:64-65` |
| Meta incident flags | Super Admin general, and only when `ChatwootApp.chatwoot_cloud?` | `super_admin/app_configs_controller.rb:9,61`, `lib/chatwoot_app.rb:23-25` |
| Channel capability record | `[:instagram, 'Channel::Instagram', :provider_scoped, :provider_oauth, [:reauth_latch, :token_expiry]]` | `custom/app/services/channels/capability.rb:62` |

## 7. Contextual-help opportunities

No Instagram key exists in `DOC_ARTICLES` today (`app/javascript/dashboard/helper/documentationLinks.js:11-94`
— the registry has six WhatsApp-connection keys, seven WhatsApp-error keys and five commerce-error keys, and
nothing for Instagram, Facebook or TikTok).

| UI location | The question a user has there | Proposed registry key | Exists in `DOC_ARTICLES`? |
|---|---|---|---|
| `channels/Instagram.vue:80-96` (connect page) | What kind of Instagram account do I need, and what will Lynomia be able to do? | `instagram` → `connect-instagram` | no |
| `channels/Instagram.vue:68-74` (error panel) | Instagram refused — what do I fix? | `instagramConnectFailed` | no |
| `callbacks_controller.rb:120-122` → "Instagram has already been taken" | This account is connected somewhere else; how do I move it? | `instagramAccountTaken` | no |
| `Settings.vue:819-824` (reconnect banner) | Why did it disconnect and will I lose the messages? | `instagramReconnect` | no |
| `Settings.vue:838-843` / `FinishSetup.vue:188-191` (migration banners) | I have two Instagram inboxes — which one is live? | `instagramMigration` | no |
| `MessagesView.vue:476-482` (cannot reply) | Why can't I answer this DM? | `instagramWindow` | no (the WhatsApp equivalent `whatsappWindow` exists at `:37`) |
| `base_send_service.rb:62-66` → failed bubble "190 - …" | My reply failed with a code — what now? | `instagramError190` (or a shared `metaError190`) | no (`whatsappError190` exists at `:48`) |
| `ReplyBox.vue:792-796` (file rejected) | What can I actually send on Instagram? | `instagramAttachments` | no |
| `InstagramStory.vue:65-73` ("story no longer available") | Why can't I see the story they replied to? | `instagramStories` | no |
| `Settings.vue:844-866` / `MessagesView.vue:467-474` (incident banner) | Is this me or Meta? | reuse `troubleshooting`, or `instagramIncident` | `troubleshooting` exists at `:87` |
| Super Admin Instagram group (`app_configs_controller.rb:74`) | Which Meta app settings does Instagram need? | operator-facing; not a tenant article | n/a |

## 8. Current documentation coverage

Four corpus files mention Instagram at all, and none is about it:

- `custom/db/documentation/en/workspace/set-up-an-inbox.md:17-21` — Instagram in the list of nine
  always-offered channels.
- `custom/db/documentation/en/getting-started/connect-your-first-channel.md:27,31-34` — one table row
  ("an Instagram account's direct messages") and one sentence ("Facebook and Instagram need a Meta app set up on
  the installation itself").
- `custom/db/documentation/ar/workspace/set-up-an-inbox.md` — the Arabic counterpart of the first.
- `custom/db/documentation/en/whatsapp/the-whatsapp-24-hour-window.md` — a passing contrast.

`custom/db/documentation/manifest.yml:6-120` has twelve sections and **no Instagram section**; there is no
Instagram article in any of them. There is no "how to connect Instagram" article, so
`connect-your-first-channel.md`'s claim that connecting is "covered in Connect your first channel" is, for
Instagram, a pointer to two sentences.

## 9. Missing or stale documentation

Missing, in rough order of how often a stuck user would hit it:

1. **Connect Instagram** — eligibility (the code requests `instagram_business_basic` and
   `instagram_business_manage_messages`, i.e. a professional account), what the authorize screen asks, that
   `force_reauth=true` means they will always re-enter credentials, and that no Facebook Page is involved.
2. **One Instagram account, one inbox** — the global unique index and the exact sentence a user sees when the
   account is already connected elsewhere.
3. **The two Instagram generations** — what the "migrated to the new Instagram channel inbox" banners mean, which
   inbox is live, and that the old one keeps history but cannot send.
4. **The Instagram reply window** — 24 hours by default, 7 days only where the human-agent tag is approved and
   `ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT` is on. Nothing in the corpus states either number for Instagram.
5. **Reconnecting Instagram** — that one code 190 disconnects the inbox, that an email goes to administrators,
   and that messages received while disconnected are lost rather than queued.
6. **The 60-day token** — that the token refreshes itself only inside the last ten days and only when the inbox is
   being used, and what a long-idle inbox looks like.
7. **What you can send** — the file types and size ceilings, that each attachment is a separate DM, and that
   headings, blockquotes and link text are flattened.
8. **Stories, mentions and shared posts** — what each bubble means, and why story media disappears.
9. **A failed Instagram message** — where to find it and how to read `"<code> - <message>"`.
   `whatsapp-find-a-failed-message` exists for WhatsApp; Instagram has no equivalent.
10. **Instagram error codes** — 190, 230, 100/9010 (the `Unknown (IG: …)` contact a user will see and wonder
    about), 1609005. The corpus has fourteen WhatsApp error articles and zero Instagram ones.
11. **Operator setup** — which Meta app, which keys, and that `IG_VERIFY_TOKEN` and
    `INSTAGRAM_MESSENGER_API_VERSION` live under the **Facebook** group in Super Admin while the rest live under
    Instagram.

Stale or wrong where Instagram is mentioned:

- `set-up-an-inbox.md:17-21` says nine channels "are always offered". For Instagram that is literally true of the
  settings tile (`ChannelList.vue:74-79` has no gate) but the onboarding tile is gated on `INSTAGRAM_APP_ID` and
  the `channel_instagram` flag (`useChannelConfig.js:31-34`), and on cloud both surfaces can be switched off by
  `DISABLE_META_INBOX_CREATION`. The article does not mention the incident switch at all.
- `connect-your-first-channel.md:30-34` says unavailable channels "will be greyed out rather than hidden". For
  Instagram in the settings list that is wrong: it is neither greyed nor hidden when unconfigured — it is fully
  clickable and fails at the Instagram redirect.

## 10. Doc claims not proven by code

| Claim | Source | Verdict |
|---|---|---|
| `INSTAGRAM_API_VERSION` is `locked: true`, so "there is no supported path to change it without a deploy" | `docs/p7/00-discovery-findings.md:703-705` (SHO-48) | **Wrong as stated.** `locked` only filters `InstallationConfig.editable` (`app/models/installation_config.rb:61`), used by `super_admin/installation_configs_controller.rb:26`. The Instagram App Configs form has no such filter (`super_admin/app_configs_controller.rb:26-35,74`; `app/views/super_admin/app_configs/show.html.erb:18-65`) and `InstallationConfig` has no guard against writing a locked row. The key is editable from Super Admin → Settings → Instagram. |
| `instagram/messenger/send_on_instagram_service.rb:17` hardcodes v11.0 "with no configuration path" | `docs/p7/00-discovery-findings.md:679-683` (SHO-45) | **Fixed since.** Now `DEFAULT_API_VERSION = 'v11.0'` read through `INSTAGRAM_MESSENGER_API_VERSION` (`:9,34-36`) and seeded at `config/installation_config.yml:157-161`. The *value* is unchanged, as `docs/p7/07-graph-api-versions.md` records. |
| `'v22.0'` is "COPY-PASTED into five separate files" | `docs/p7/00-discovery-findings.md:689` | **Fixed since.** One constant (`channel/instagram.rb:28`), five readers. |
| Instagram Graph calls put live tokens in query strings | `docs/p7/00-discovery-findings.md:503-507,695-699` (SHO-23 / SHO-47) | **Still true at this HEAD.** Interpolated into the URL at `message_text.rb:11` and `messages/instagram/message_builder.rb:9`; passed as HTTParty `query:` at `send_on_instagram_service.rb:12,16-20`, `user_details_service.rb:14-21`, `refresh_oauth_token_service.rb:52-58`, `channel/instagram.rb:50-56,62-68`, `messenger/send_on_instagram_service.rb:22-29`. |
| Facebook connect requests no Instagram scopes while three code paths depend on them | `docs/p7/00-discovery-findings.md:1148-1152` (EXT-01) | **Confirmed unchanged.** `facebookScopes.js:10-22` still exports a dead `INSTAGRAM_SCOPES`; neither caller passes `includeInstagramScopes` (`useFacebookPageConnect.js:50`, `facebook/Reauthorize.vue:26`). |
| Facebook and Instagram have no health/diagnostic surface, so a version retirement surfaces only as silently failed messages | `docs/p7/07-graph-api-versions.md` | **Confirmed**, with one refinement: `Channels::ConnectionState` (`custom/app/services/channels/connection_state.rb`) does compute an Instagram token-expiry warning and it *is* serialized (`_inbox.json.jbuilder:204`), but nothing in `app/javascript` reads `connection_state`, so no agent or administrator ever sees it. |
| The restriction banners are branded correctly for self-hosted installs | implied by `Instagram.vue:15-19` and `MessagesView.vue:200-204`, which carefully route the *link* through `brandLink('support', …)` | **Not proven.** The banner *bodies* hardcode "Chatwoot" (`inboxMgmt.json:65,66`, `conversation.json:59`) and are rendered raw (`Instagram.vue:108`, `Settings.vue:855`, `MessagesView.vue:471`) without `replaceInstallationName`, which the repository's own branding rule asks for. Also `Settings.vue:856-863` renders the status link with no `v-if` on the URL, unlike `Instagram.vue:110` — on a branded install with no `SUPPORT_URL` it renders "View status updates" with an empty `href`. |
| `CustomExceptions::Inbox::LimitExceeded` protects Instagram inbox creation | `callbacks_controller.rb:14,52-58` | **Unreachable here.** Nothing in `app/`, `custom/` or `lib/` raises it (there is no `enterprise/` tree in this repository). The real server-side gate is `Billing::InboxLimit` (`custom/app/models/billing/inbox_limit.rb:14-45`), whose failures arrive as `ActiveRecord::RecordInvalid` and fall through to the generic 500 branch. |
