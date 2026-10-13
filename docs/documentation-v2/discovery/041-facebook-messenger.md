---
agent: 041
scope: Facebook Page / Messenger integration — connect, webhook subscription, inbound, outbound, messaging window, reauthorization, disconnect, and every operator-visible error
confidence: high
---

## 1. What the feature is

A `Channel::FacebookPage` is a Facebook Page whose Messenger thread is pulled into a Lynomia inbox. The record
holds exactly three things an operator cares about — `page_id`, `page_access_token`, `user_access_token` — plus an
`instagram_id` that is set opportunistically at connect time and silently turns the same inbox into an
Instagram-over-Page inbox (`app/models/channel/facebook_page.rb:1-18`, `app/models/inbox.rb:126-131`). Both tokens
are encrypted at rest only when the installation has ActiveRecord encryption keys configured; the guard is
explicit and marked for removal (`app/models/channel/facebook_page.rb:24-28`).

Connecting is a browser-side Meta OAuth flow followed by two server calls. The Vue layer loads the Meta JS SDK,
runs `FB.login` for four Page scopes, posts the returned **user** access token to the server, which exchanges it
for a long-lived token through Koala and lists the user's Pages; the operator picks one, and the browser posts the
Page's own `access_token` back to create the channel and inbox
(`app/javascript/dashboard/composables/useFacebookPageConnect.js:17-77`,
`app/controllers/api/v1/accounts/callbacks_controller.rb:4-35`).

Inbound traffic does not go through a Lynomia controller. The `facebook-messenger` gem's Rack app is mounted at
`/bot` (`config/routes.rb:531`) and a configuration provider supplies the verify token, app secret and page access
token (`config/initializers/facebook_messenger.rb:1-60`). Five gem hooks enqueue two jobs
(`config/initializers/facebook_messenger.rb:67-89`).

Outbound sends go through the same gem's `Bot.deliver`, wrapped by `Facebook::SendOnFacebookService`
(`app/services/facebook/send_on_facebook_service.rb:34-45`), which `SendReplyJob` selects by channel class — and
which it diverts to the Instagram-over-Messenger service when the conversation is an Instagram DM
(`app/jobs/send_reply_job.rb:22,32-38`).

### Graph API version — the answer the brief asked for

There is **no** central Graph version for this channel, and the one named `FACEBOOK_API_VERSION` does not govern
any server call.

| Surface | Version actually used | Configurable | Citation |
|---|---|---|---|
| Messenger send (`Bot.deliver`) | **`v3.2`**, hardcoded in the gem | no | `vendor/bundle/ruby/3.4.0/gems/facebook-messenger-2.0.1/lib/facebook/messenger/bot.rb:16` |
| Page webhook subscribe / unsubscribe | **`v3.2`**, hardcoded in the gem | no | `.../facebook/messenger/subscriptions.rb:12` |
| Page list, long-lived token exchange, page name/IG id, contact profile | **unversioned** (Koala, no `Koala.config.api_version` anywhere) | no | `callbacks_controller.rb:28,48,83,87-88`; `app/services/facebook/page_details_service.rb:5-7`; `app/builders/messages/facebook/message_builder.rb:147-148` |
| Page avatar | unversioned `/{page_id}/picture` | no | `callbacks_controller.rb:103` |
| Browser JS SDK (`FB.init`) only | `FACEBOOK_API_VERSION`, default **`v18.0`** | yes, Super Admin | `app/controllers/dashboard_controller.rb:85`; `config/installation_config.yml:152-156` |

`FACEBOOK_API_VERSION` is centralized, displayed in Super Admin as "Facebook API Version", and read by exactly one
server line — the one that publishes it to the browser. Nothing on the Ruby send or read path consults it. This is
recorded independently in `docs/p7/07-graph-api-versions.md:12-22` and `docs/p7/00-discovery-findings.md:671-675`,
and this report confirms both by re-reading the call sites.

## 2. Surfaces and routes

| Surface | Path | Backend |
|---|---|---|
| Channel picker tile "Facebook / Connect your Facebook page" | `app/javascript/dashboard/routes/dashboard/settings/inbox/ChannelList.vue:32-37` | — |
| Legacy connect screen (FB login button, page picker, inbox name) | `.../settings/inbox/channels/Facebook.vue` (routed via `ChannelFactory.vue:3,28`) | — |
| New onboarding in-dialog page picker | `.../onboarding/inbox-setup/InboxFacebookForm.vue`; wired at `InboxChannelsDialog.vue:97-98,117-118,148-149`; channel entry `inbox-setup/constants.js:51-53` | — |
| Reauthorize banner + flow | `.../settings/inbox/facebook/Reauthorize.vue`; rendered from `Settings.vue:394-395,807-812` | — |
| List the user's Pages | `POST /api/v1/accounts/:id/callbacks/facebook_pages.json` (`config/routes.rb:89`) | `Api::V1::Accounts::CallbacksController#facebook_pages` (`:26-35`) |
| Create channel + inbox | `POST`/**`GET`** `/api/v1/accounts/:id/callbacks/register_facebook_page` (`config/routes.rb:87-88`) | `#register_facebook_page` (`:4-24`) |
| Re-attach a fresh page token | `POST /api/v1/accounts/:id/callbacks/reauthorize_page` (`config/routes.rb:90`) | `#reauthorize_page` (`:45-57`) |
| Meta webhook (GET verify + POST events) | `/bot` (`config/routes.rb:531`) | `Facebook::Messenger::Server` (gem `server.rb:25-38`) |
| Disconnect | `DELETE /api/v1/accounts/:id/inboxes/:id` → `DeleteObjectJob` (`app/controllers/api/v1/accounts/inboxes_controller.rb:80-83`) → `Inbox#belongs_to :channel, dependent: :destroy` (`app/models/inbox.rb:62`) → `before_destroy :unsubscribe` |

Permissions requested at connect and at reauthorize are identical and Lynomia-specific: `pages_manage_metadata`,
`business_management`, `pages_messaging`, `pages_show_list` — and deliberately **no** `pages_read_engagement` and
**no** Instagram scopes, even for a legacy inbox that already has an `instagram_id`
(`app/javascript/dashboard/helper/facebookScopes.js:1-8`;
`.../settings/inbox/facebook/Reauthorize.vue:24-27`).

Webhook fields subscribed at connect: `messages message_deliveries message_echoes message_reads standby
messaging_handovers messaging_postbacks` (`app/models/channel/facebook_page.rb:53-55`).

## 3. User-visible states

**New onboarding dialog** (`InboxFacebookForm.vue`): connect prompt → spinner "Loading your Facebook Pages…"
(`:74-82`) → page picker listing only Pages with `exists: false` (`:28-32,84-96`) → "No connectable Pages found.
All your Pages are already connected." when every Page is filtered out (`:118-132`) → inline error line (`:134-137`)
→ success toast and dialog close (`:62-63`). A cancelled Meta popup returns `null` and silently leaves the operator
on the connect prompt (`:42`, `useFacebookPageConnect.js:40-52`).

**Legacy connect screen** (`channels/Facebook.vue`): pre-login state showing the Facebook login image and the
privacy line (`:179-225`); an amber "Facebook inbox creation is temporarily unavailable…" banner with a status link
when Meta connections are switched off (`:200-223`); loading state "Authenticating you with Facebook…" /
"Creating your Inbox…" (`:51,151,234`); the page + inbox-name form (`:235-285`); a centred error heading (`:227-233`).

**Reauthorize**: `InboxReconnectionRequired` banner — "Your inbox is disconnected. You won't receive new messages
until you reauthorize it." / "Click here to reconnect." (`inboxMgmt.json:9-10`), shown when
`inbox.reauthorization_required` is true for a Facebook inbox (`Settings.vue:394-395`;
serialized at `app/views/api/v1/models/_inbox.json.jbuilder:56-57`). Success and failure are toasts only.

**Conversation**: a failed outgoing Messenger message renders `MessageError.vue` with the raw provider string
`"<code> - <message>"` and a Retry button, and **no** explanation and **no** documentation link, because
`deliveryFailure` is populated only for WhatsApp-shaped codes
(`app/services/facebook/send_on_facebook_service.rb:73-79`;
`app/javascript/dashboard/components-next/message/MessageError.vue:31-39,60-66,70-77`;
`custom/app/models/custom/message.rb:10-17`).

**Reply box**: once the Messenger window has closed, `Conversations::MessageWindowService#can_reply?` returns false
(`app/services/conversations/message_window_service.rb:9-13,21-22,51-53`) and the composer is blocked. There is no
Facebook-specific copy explaining why.

## 4. Errors and validation messages

Exact strings, with keys.

| String | Key | Citation |
|---|---|---|
| "Loading your Facebook Pages…" | `ONBOARDING_INBOX_SETUP.CHANNELS_DIALOG.FACEBOOK_LOADING` | `onboarding.json:87` |
| "Select a Page to connect" | `…FACEBOOK_SELECT_PAGE` | `onboarding.json:86` |
| "No connectable Pages found. All your Pages are already connected." | `…FACEBOOK_NO_PAGES` | `onboarding.json:88` |
| "Couldn't connect to Facebook. Please try again." | `…FACEBOOK_ERROR` | `onboarding.json:89` |
| "Continue with Facebook" | `…FACEBOOK_LAUNCH` | `onboarding.json:85` |
| "Authorize access and choose a Page to connect." | `…FACEBOOK_SUBTITLE` | `onboarding.json:84` |
| "Facebook connected successfully" | `ONBOARDING_INBOX_SETUP.FACEBOOK_CONNECTED` | `onboarding.json:41` |
| "Authenticating you with Facebook..." | `INBOX_MGMT.DETAILS.LOADING_FB` | `inboxMgmt.json:686` |
| "Error loading Facebook SDK. Please disable any ad-blockers and try again from a different browser." | `INBOX_MGMT.DETAILS.ERROR_FB_LOADING` | `inboxMgmt.json:687` |
| "Something went wrong, Please refresh page..." | `INBOX_MGMT.DETAILS.ERROR_FB_AUTH` | `inboxMgmt.json:688` |
| "You're not authorized to perform this action. " + Facebook-roles help link | `INBOX_MGMT.DETAILS.ERROR_FB_UNAUTHORIZED`, `…_HELP` | `inboxMgmt.json:689-690` — **dead strings, no reader in the Facebook flow** |
| "We were unable to create the inbox. Please try again." | `INBOX_MGMT.DETAILS.ERROR_CHANNEL_CREATION` | `inboxMgmt.json:691` |
| "Creating your Inbox..." | `INBOX_MGMT.DETAILS.CREATING_CHANNEL` | `inboxMgmt.json:692` |
| "Choose Page" / "Select a page from the list" / "Pick a value" | `INBOX_MGMT.ADD.FB.CHOOSE_PAGE`, `…CHOOSE_PLACEHOLDER`, `…PICK_A_VALUE` | `inboxMgmt.json:47-52` |
| "Inbox Name" / "Add a name for your inbox" / "Pick a Name for your Inbox" | `INBOX_MGMT.ADD.FB.INBOX_NAME`, `…ADD_NAME`, `…PICK_NAME` | `inboxMgmt.json:49-51` |
| "PS: By signing in, we only get access to your Page's messages. Your private messages can never be accessed by Chatwoot." | `INBOX_MGMT.ADD.FB.HELP` | `inboxMgmt.json:46` — passed through `replaceInstallationName` (`channels/Facebook.vue:198`) |
| "Facebook inbox creation is temporarily unavailable due to an API-level issue on Meta's side, not a problem with Chatwoot. …" + "View status updates" | `INBOX_MGMT.ADD.FB.RESTRICTED_WARNING`, `…STATUS_LINK` | `inboxMgmt.json:54-55` — **not** brand-filtered |
| "Reauthorize" / "Your Facebook connection has expired, please reconnect your Facebook page to continue services" / "Reconnection successful" / "There was an error, please try again" | `INBOX_MGMT.FACEBOOK_REAUTHORIZE.{TITLE,SUBTITLE,MESSAGE_SUCCESS,MESSAGE_ERROR}` | `inboxMgmt.json:1334-1339` |
| "Your inbox is disconnected. You won't receive new messages until you reauthorize it." / "Click here to reconnect." | `INBOX_MGMT.RECONNECTION_REQUIRED`, `…CLICK_TO_RECONNECT` | `inboxMgmt.json:9-10` |
| Email: subject "Your Facebook page connection has expired"; body "Your Facebook Inbox Access has expired." / "Please reconnect Facebook Page to continue receiving messages." | hardcoded, not i18n | `app/mailers/administrator_notifications/channel_notifications_mailer.rb:2-5`; `app/views/mailers/administrator_notifications/channel_notifications_mailer/facebook_disconnect.liquid:1-8` |

Client validations: the legacy screen requires a selected Page and a non-empty inbox name
(`channels/Facebook.vue:58-68`); the new dialog only disables Connect until a Page is chosen
(`InboxFacebookForm.vue:111`).

Provider-relayed errors reach the operator verbatim in three shapes, all from
`app/services/facebook/send_on_facebook_service.rb`:
- `"<error.code> - <error.message>"` from Meta's JSON error envelope (`:73-79`);
- `"Facebook was unable to process this request"` when the response is not JSON (`:37-40`);
- `"Request timed out, please try again later"` on `Net::OpenTimeout` (`:41-44`).

Server validations: `page_id` unique per account (`app/models/channel/facebook_page.rb:32`), and the DB enforces the
same (`index_channel_facebook_pages_on_page_id_and_account_id UNIQUE`, `:17`). `CustomExceptions::Inbox::LimitExceeded`
is the only error the create action renders (`callbacks_controller.rb:19-20`, handler at
`app/controllers/concerns/request_exception_handler.rb:12-14,78-81`).

## 5. Failure paths

**Webhook subscription failures are invisible.** `subscribe` rescues every `StandardError`, logs at `debug` and
returns `true` (`app/models/channel/facebook_page.rb:49-60`). It runs in `after_create_commit`, so the inbox is
created and reported as connected whether or not Meta accepted the `subscribed_apps` call. The operator's first
signal is that no message ever arrives. `unsubscribe` is rescued identically (`:62-67`), so a disconnect can leave
the app subscribed to the Page with nothing to receive the events.

**`register_facebook_page` turns any non-`LimitExceeded` failure into a 500.** The `rescue StandardError` branch
logs and captures but does not render (`callbacks_controller.rb:21-24`), so Rails falls through to
`register_facebook_page.json.jbuilder`, whose first line is `@facebook_inbox.id` on `nil`
(`app/views/api/v1/accounts/callbacks/register_facebook_page.json.jbuilder:1`). `NoMethodError` is not one of the
four classes `handle_with_exception` rescues (`request_exception_handler.rb:19-32`), so the browser gets a 500 and
shows the generic "We were unable to create the inbox." / `ONBOARDING_INBOX_SETUP.ERROR`.

**Reauthorize can report success having changed nothing.** `update_fb_page` wraps the token update,
`sync_page_details` and `reauthorized!` in a transaction whose *inner* `rescue StandardError` swallows the error
(`callbacks_controller.rb:65-75`); `reauthorize_page` then falls through to `render` and the UI shows "Reconnection
successful" (`facebook/Reauthorize.vue:90-100`). The banner stays up on the next page load.

**Reauthorize returns a bare 422 with no body** when the Page the inbox points at is not among the Pages the
re-authenticating user administers — a different Facebook account, a lost Page role, or a revoked app install
(`callbacks_controller.rb:56`). The UI maps that to "There was an error, please try again", which does not say that
the operator signed in as the wrong person.

**`long_lived_token` swallows its own failure and returns `nil`** (`callbacks_controller.rb:86-91`), after which
`Koala::Facebook::API.new(nil)` is handed to `get_connections` and the request fails as an unhandled Koala error →
500 → "Couldn't connect to Facebook."

**Token expiry is latched, not detected.** Two independent paths call `authorization_error!`: the send service, but
only when Meta's message contains the literal `'The session has been invalidated'` or `'Error validating access
token'` (`app/services/facebook/send_on_facebook_service.rb:114-119`), and the inbound builder on any
`Koala::Facebook::AuthenticationError` (`app/builders/messages/facebook/message_builder.rb:28-31,149-153`). The
threshold is two errors (`app/models/concerns/reauthorizable.rb:16,30-35`); the second one sets a Redis flag, emails
the administrators (`:90`) and dispatches a reauthorization event. Any Meta refusal whose wording differs — a
revoked `pages_messaging` scope, a removed Page role, a Page-level restriction — never latches, so the inbox keeps
failing sends with no banner and no email.

**Inbound stops entirely once the flag is set.** `Messages::Facebook::MessageBuilder#perform` returns early when
`reauthorization_required?` (`app/builders/messages/facebook/message_builder.rb:22`), so every message that arrives
during the disconnected period is discarded, not queued. Reconnecting does not backfill them, and nothing tells the
operator they were lost.

**Delivery and read receipts are matched to a conversation without scoping to the inbox.**
`Integrations::Facebook::DeliveryStatus` finds the contact by `ContactInbox.find_by(source_id:)` across the whole
installation and then takes `Conversation.find_by(contact_id:)` — any conversation of that contact, in any inbox, in
any account (`lib/integrations/facebook/delivery_status.rb:26-32`). The channel is looked up correctly
(`:34-36`) but never used to constrain either query, and `find_by` returns the lowest id. Read and delivered
watermarks can therefore be applied to the wrong conversation.

**Three of the seven subscribed webhook fields cannot produce anything.** The gem's Rack layer iterates only
`entry['messaging']` and skips any other key (`gem server.rb:156-170`), so `standby` entries are dropped before
reaching the parser — even though `Integrations::Facebook::MessageParser` is written to read them
(`lib/integrations/facebook/message_parser.rb:6`). `messaging_handovers` maps to the gem's `pass_thread_control`
event, for which no hook is registered, so it logs "Ignoring pass_thread_control (no hook registered)"
(`gem bot.rb:104-108`; hooks at `config/initializers/facebook_messenger.rb:67-89`). `message_reads` does arrive, via
the `:read` hook.

**With no `FB_APP_SECRET` configured the channel fails closed in both directions.** `app_secret_for` returns a
per-process random value rather than nil, deliberately, so the gem's signature check cannot be skipped
(`config/initializers/facebook_messenger.rb:9-34`; the skip it defends against is `gem server.rb:74-78`). Inbound
POSTs then fail integrity and the endpoint answers 400 (`gem server.rb:86-88,177-181`). The same method also feeds
`app_secret_proof_for` on the send path (`gem bot.rb:48-58`,
`gem configuration/providers/base.rb:14-18`), so every outbound send carries a proof computed from the random value
and is refused by Meta. The failure is loud, which is right, but nothing in the product names the missing setting:
the operator sees unexplained Meta codes in the conversation.

**The webhook verify handshake does not compare tokens.** `valid_verify_token?` ignores its argument and returns the
configured value (`config/initializers/facebook_messenger.rb:5-7`), which the gem treats as a boolean
(`gem server.rb:48-54`). Any GET to `/bot` with any `hub.verify_token` is answered with the `hub.challenge` as long
as `FB_VERIFY_TOKEN` is set; when it is unset the handshake fails with body `Error; wrong verify token` and status
200. This is upstream Chatwoot behaviour, carried unchanged.

**`v3.2` on the send path and unversioned Koala reads are undetectable from inside the product.** There is no
Facebook equivalent of the WhatsApp Account Health tab or diagnosis services; a Graph retirement surfaces only as
messages marked failed (`docs/p7/07-graph-api-versions.md:72-85`, re-confirmed here: nothing under
`custom/app/services/` touches Facebook). Failures are at least logged centrally —
`Custom::Messages::StatusUpdateService` emits `OUTGOING_DELIVERY_FAILED` through `Lynomia::OperatorLog` for every
channel including Facebook, at `:error` level with `classification: UNCLASSIFIED`
(`custom/app/services/custom/messages/status_update_service.rb:28-51`).

## 6. Permissions

| Surface | Gate | Citation |
|---|---|---|
| `callbacks#facebook_pages`, `#register_facebook_page`, `#reauthorize_page` | **authenticated account member only** — no `check_authorization`, no `authorize`, no admin check anywhere in the controller | `app/controllers/api/v1/accounts/callbacks_controller.rb:1-2` (whole file); base chain `app/controllers/api/v1/accounts/base_controller.rb:1-7`, `app/controllers/api/base_controller.rb:1-7` |
| Creating any other inbox | `InboxPolicy#create?` → administrator | `app/policies/inbox_policy.rb:51-53`; enforced at `app/controllers/api/v1/accounts/inboxes_controller.rb:6` |
| Deleting the inbox (disconnect) | `InboxPolicy#destroy?` → administrator | `app/policies/inbox_policy.rb:59-61` |
| Reauthorize target inbox | `Current.account.inboxes.find_by(id:)` — any inbox in the account, not restricted to assigned inboxes | `callbacks_controller.rb:61-63` |
| Connect UI visibility | the settings route group, not a Facebook-specific gate | `ChannelList.vue:32-37` |
| Connect button disabled | `isMetaInboxCreationDisabled` = `deploymentEnv === 'cloud' && DISABLE_META_INBOX_CREATION` | `app/javascript/shared/store/globalConfig.js:45,67-68`; consumed at `channels/Facebook.vue:88-90,96-99,103` |
| Messenger window length | `ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT`, installation-wide | `config/installation_config.yml:162-167`; `app/services/conversations/message_window_service.rb:51-53,63-65` |
| Super Admin editable FB config | `FB_APP_ID`, `FB_VERIFY_TOKEN`, `FB_APP_SECRET`, `FACEBOOK_API_VERSION`, `ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT` | `config/installation_config.yml:135-167`; `app/controllers/super_admin/app_configs_controller.rb:65` |

Two findings follow. First, `register_facebook_page` is a second, unpoliced door onto inbox creation: a plain agent
can create a Facebook inbox that `InboxesController` would have refused. Second, the restriction banner is
cloud-only by construction, so on a self-hosted Lynomia install `DISABLE_META_INBOX_CREATION` has no effect and the
banner can never appear.

Also note that the server trusts `page_id` and `page_access_token` exactly as the browser posts them
(`callbacks_controller.rb:4-18`); nothing re-reads `/me/accounts` to confirm the pair belongs to the authenticated
user, and `sync_page_details` failing is rescued and logged (`:37-42`), so an unverifiable pair still produces an
inbox.

## 7. Contextual-help opportunities

There is currently **no** Facebook or Messenger key in `DOC_ARTICLES`
(`app/javascript/dashboard/helper/documentationLinks.js:11-110`; a case-insensitive grep for facebook/messenger over
that file returns nothing).

| UI location | The question there | Proposed key | Exists in `DOC_ARTICLES`? |
|---|---|---|---|
| `ChannelList.vue:32-37` | "What does connecting a Facebook page give me?" | `facebook` | no |
| `InboxFacebookForm.vue:118-132` (no connectable Pages) | "Why is my Page not listed?" | `facebookPageNotListed` | no |
| `channels/Facebook.vue:197-199` (the HELP line) | "What exactly is Lynomia allowed to see?" | `facebookPermissions` | no |
| `channels/Facebook.vue:200-223` (restricted banner) | "Is this Meta or is this us?" | `facebookConnectUnavailable` | no — today it links to `META_RESTRICTION_STATUS_URL` via `brandLink('support', …)` (`:73-75`, `app/javascript/dashboard/constants/globals.js:81`) |
| `Settings.vue:807-812` / `facebook/Reauthorize.vue:106` (reconnect banner) | "Why did it expire and what do I lose?" | `facebookReconnect` | no |
| `MessageError.vue:70-77` on a Messenger failure | "What does this Meta code mean?" | `facebookSendErrors` | no — `learnMoreUrl` returns `''` for any non-WhatsApp failure |
| Reply box when `can_reply?` is false on a Messenger conversation (`message_window_service.rb:21-22,51-53`) | "Why can't I reply?" | `messengerWindow` | no — `whatsappWindow` exists (`documentationLinks.js:37`), Messenger has no equivalent |
| Super Admin Facebook config group (`app_configs_controller.rb:65`) | "Which of these does what?" | `facebookInstallationSetup` | no |

## 8. Current documentation coverage

Three passing mentions in the whole EN corpus, no article:

- `custom/db/documentation/en/getting-started/connect-your-first-channel.md:26` — one table row, "Facebook | a
  Facebook page's Messenger inbox".
- `custom/db/documentation/en/getting-started/connect-your-first-channel.md:31` — "Facebook and Instagram need a
  Meta app set up on the installation itself."
- `custom/db/documentation/en/workspace/set-up-an-inbox.md:18` — Facebook listed among available channel types.

Everything else that mentions Facebook does so about WhatsApp (`whatsapp/connect-whatsapp.md`,
`whatsapp/the-whatsapp-24-hour-window.md`, `whatsapp-errors/whatsapp-error-131042.md`). There is no `facebook`
section in the manifest and no Facebook article in any section.

Coverage verdict: **a connected channel with a full OAuth flow, a reauthorization flow, a messaging window and
nine distinct operator-visible error strings has zero documentation.**

## 9. Missing or stale documentation

What a stuck operator cannot find anywhere:

1. **How to connect a Page** — the prerequisites in particular: the installation needs `FB_APP_ID`,
   `FB_APP_SECRET` and `FB_VERIFY_TOKEN` configured before the flow can work at all
   (`config/installation_config.yml:135-146`), and the signing-in user needs a Page role that grants
   `pages_messaging` and `pages_show_list`.
2. **What Lynomia asks for and why** — the four scopes, and the deliberate absence of `pages_read_engagement` and
   Instagram scopes (`facebookScopes.js:1-8`). The in-product line claims only "your Page's messages", which is
   narrower than `business_management` actually grants.
3. **"My Page isn't in the list"** — the picker silently filters every Page already connected in this account
   (`InboxFacebookForm.vue:28-32`), which is the most likely reason the list is short or empty.
4. **The Messenger messaging window** — 24 hours by default, 7 days when `ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT` is
   on, measured from the last *incoming* message, installation-wide and not per inbox
   (`message_window_service.rb:34-38,51-53,63-65`). The WhatsApp window has a dedicated article
   (`the-whatsapp-24-hour-window.md`); Messenger has nothing, and the switch's own description points the operator
   at Meta's Human Agent approval requirement with no Lynomia-side guidance
   (`config/installation_config.yml:166`).
5. **Reconnecting an expired Page** — that the banner appears only after two latched auth errors, that it must be
   the same Facebook user who administers that exact Page, and that messages which arrive while disconnected are
   discarded rather than queued (`app/builders/messages/facebook/message_builder.rb:22`).
6. **What a Messenger send error means** — not one of the codes Meta can return on `/me/messages` is documented,
   and the UI shows the raw code with no link. Fourteen WhatsApp error articles exist; Messenger has none.

Nothing in the corpus is *stale* about this channel, because nothing in the corpus describes it. The one claim worth
flagging for an editor is the in-product string, not an article: `INBOX_MGMT.ADD.FB.HELP`
(`inboxMgmt.json:46`) and `INBOX_MGMT.ADD.FB.RESTRICTED_WARNING` (`:54`) both say "Chatwoot"; the first is filtered
through `replaceInstallationName` (`channels/Facebook.vue:198`), the second is not (`:211`).

## 10. Doc claims not proven by code

| Claim | Where claimed | Code | Verdict |
|---|---|---|---|
| "Facebook and Instagram need a Meta app set up on the installation itself." | `connect-your-first-channel.md:31` | `FB_APP_ID`/`FB_APP_SECRET`/`FB_VERIFY_TOKEN` at `config/installation_config.yml:135-146`, read at `dashboard_controller.rb:85` and `facebook_messenger.rb:6,21` | **confirmed** |
| "Facebook | a Facebook page's Messenger inbox" | `connect-your-first-channel.md:26` | accurate but incomplete: the same channel also carries Instagram DMs when `instagram_id` is set (`app/models/inbox.rb:131`, `app/jobs/send_reply_job.rb:33-34`) | **confirmed, understated** |
| "we only get access to your Page's messages. Your private messages can never be accessed" | `inboxMgmt.json:46` (product string) | the token granted is a Page access token with `business_management` among its scopes (`facebookScopes.js:3-8`); the product reads the contact's public profile through Koala (`message_builder.rb:147-148`) | **overstated** — the sentence is about Lynomia's use, not about what the grant permits, and an operator reading it as a scope description would be misled |
| "Facebook inbox creation is temporarily unavailable due to an API-level issue on Meta's side" | `inboxMgmt.json:54` (product string) | shown purely from `DISABLE_META_INBOX_CREATION` on cloud (`shared/store/globalConfig.js:67-68`); it is an operator switch, not a detected Meta condition, and it cannot fire on a self-hosted install | **unproven as written** |
| `FACEBOOK_API_VERSION` — "Configure this if you want to use a different Facebook API version." | `config/installation_config.yml:154` | one server reader, which only publishes it to the browser (`dashboard_controller.rb:85`); every Ruby Graph call is `v3.2` or unversioned | **wrong** — the control does not do what its own description says; independently recorded at `docs/p7/00-discovery-findings.md:671-675` |
| "Your Facebook Inbox Access has expired." | `facebook_disconnect.liquid:3` | the flag is set after two errors of any latched kind, including a revoked scope or a lost Page role, not only expiry (`reauthorizable.rb:30-35`; `send_on_facebook_service.rb:114-119`) | **narrower than the code** |
| "There is no Facebook health tab, diagnostic or spec" | `docs/p7/07-graph-api-versions.md:76-82` | re-verified: no Facebook diagnosis service under `custom/app/services/`, no Facebook branch in `delivery_failure.rb`, and `delivery_failure_data` matches WhatsApp codes only (`custom/app/models/custom/message.rb:10-17`) | **confirmed** |
