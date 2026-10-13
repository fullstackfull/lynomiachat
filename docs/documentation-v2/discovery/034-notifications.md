---
agent: 034
scope: Notifications — types and triggers, the in-app feed and its authorization, email, push, per-user/per-account settings, read/unread/snooze, operator-visible delivery failures
confidence: high
---

## 1. What the feature is

A notification in this product is one row in `notifications`, owned by a `(user, account)` pair, pointing at a
`primary_actor` (a `Conversation`, or — new in this installation — a `PlatformSupport::Ticket`) and optionally a
`secondary_actor` (the `Message` that caused it, or the acting `User`). The row is the bell: it is the unit the
in-app feed lists, the unit the sidebar badge counts, and the unit read/unread/snooze/delete act on
(`app/models/notification.rb:30-56`, schema `db/schema.rb:1589-1609`).

Nine types exist (`app/models/notification.rb:38-56`):

| # | type | written by | trigger |
|---|---|---|---|
| 1 | `conversation_creation` | `NotificationListener#conversation_created` / `#conversation_bot_handoff` (`app/listeners/notification_listener.rb:16-28`, `:2-14`) | a non-`pending` conversation is created, or a bot hands off — one row **per inbox member** |
| 2 | `conversation_assignment` | `NotificationListener#assignee_changed` (`:30-48`) | assignee set, `notifiable_assignee_change` present, conversation not pending |
| 3 | `assigned_conversation_new_message` | `Messages::NewMessageNotificationService#notify_conversation_assignee` (`app/services/messages/new_message_notification_service.rb:15-27`) | a notifiable message (incoming/outgoing, not private — `app/models/concerns/message_filter_helpers.rb:16-18`) arrives and the assignee is not the sender |
| 4 | `conversation_mention` | `Messages::MentionService#generate_notifications_for_mentions` (`app/services/messages/mention_service.rb:51-62`) | `@user` or `@team` inside a **private** note; team mentions expand to members (`:30-38`), filtered to inbox members + account admins (`:40-49`) |
| 5 | `participating_conversation_new_message` | `…#notify_participating_users` (`new_message_notification_service.rb:29-44`) | notifiable message, one row per `conversation_participants` user who is not the sender |
| 6-8 | `sla_missed_first_response` / `_next_response` / `_resolution` | **nothing** | declared enum values with no creation site anywhere in `app/`, `custom/` or `lib/` — confirmed by grep and by `custom/app/services/notifications/conversation_visibility.rb:78-79` |
| 9 | `platform_support_reply` | `PlatformSupport::Notifications::ReplyNotifier#perform` (`custom/app/services/platform_support/notifications/reply_notifier.rb:40-47`), called from `custom/app/services/platform_support/message_creation.rb:146` | an **operator's public reply** on a Platform Support ticket; never creation, assignment, status, SLA or an internal note |

Two deliberate suppressions at the write boundary: a notification is not created for a conversation whose
contact is `blocked?` unless it is a mention (`app/builders/notification_builder.rb:29`), and
`conversation_creation` is created **only if** the recipient has the email or push flag for it
(`:27`, predicate at `:14-23`) — so for that one type the bell is gated by delivery preferences.

Delivery fans out from an `after_create_commit` on the row itself (`app/models/notification.rb:76`,
`:184-203`): push job if `push_<type>?`, email job if `email_<type>?`, and always
`RemoveDuplicateNotificationJob`. `IN_APP_ONLY_TYPES = %w[platform_support_reply]`
(`app/models/notification.rb:71`) makes `platform_support_reply` bell-only — its email goes through
`PlatformSupport::TicketMailer` instead (`custom/app/mailers/platform_support/ticket_mailer.rb:8-11`).

Beyond this table there is a second, unrelated family of "notifications" that are **email only and never
produce a bell row**: `AdministratorNotifications::ChannelNotificationsMailer` (channel disconnects —
Facebook, Instagram, TikTok, WhatsApp, email inbox: `app/mailers/administrator_notifications/channel_notifications_mailer.rb:2-25`),
`AdministratorNotifications::AccountNotificationMailer` (account deletion scheduled, contact import/export
done or failed, automation rule disabled: `app/mailers/administrator_notifications/account_notification_mailer.rb:2-59`),
`AdministratorNotifications::IntegrationsNotificationMailer`, and
`TeamNotifications::AutomationNotificationMailer`. All address `Current.account.administrators`
(`app/mailers/administrator_notifications/base_mailer.rb:24-26`) and have **no user-facing on/off switch at
all**.

## 2. Surfaces and routes

| Surface | Path |
|---|---|
| The feed ("My Inbox") | `app/javascript/dashboard/routes/dashboard/inbox/InboxList.vue`; routes `inbox_view` / `inbox_view_conversation` at `app/javascript/dashboard/routes/dashboard/inbox/routes.js:10-32` |
| Row renderer | `app/javascript/dashboard/components-next/Inbox/InboxCard.vue` (type icon map at `app/javascript/dashboard/routes/dashboard/inbox/helpers/InboxViewHelpers.js:1-16`) |
| Feed header / bulk menu | `…/inbox/components/InboxListHeader.vue:41-66`, `InboxOptionMenu.vue:13-21`, filters `InboxDisplayMenu.vue:25-48` |
| Snooze | `…/inbox/components/InboxItemHeader.vue:46-80` (+ `CmdBarConversationSnooze`, `CustomSnoozeModal`) |
| Sidebar badge | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:416` (`count: 'notifications/getUnreadCount'`), primed at `:286` |
| Preferences (email/push matrix) | `app/javascript/dashboard/routes/dashboard/settings/profile/NotificationPreferences.vue`, list in `…/profile/constants.js:1-37`, mounted from `…/profile/Index.vue:351-359`, route `profile_settings_index` (`…/profile/profile.routes.js:18-25`) |
| Audio alerts | `…/profile/AudioNotifications.vue`, engine `app/javascript/dashboard/helper/AudioAlerts/DashboardAudioNotificationHelper.js` |
| Store | `app/javascript/dashboard/store/modules/notifications/{actions,getters,helpers,mutations}.js`; settings store `…/modules/userNotificationSettings.js` |
| Operator push diagnostics | `SuperAdmin::PushDiagnosticsController` (`app/controllers/super_admin/push_diagnostics_controller.rb`), route `config/routes.rb:597-599`, service `app/services/notification/push_test_service.rb` |

API (`config/routes.rb:230-241`, controller `app/controllers/api/v1/accounts/notifications_controller.rb`):
`GET index` (`:9-13`), `POST read_all` (`:15-25`), `PATCH update` (`:27-30`), `POST :id/unread` (`:32-35`),
`DELETE :id` (`:37-40`), `POST destroy_all` (`:42-49`), `GET unread_count` (`:51-54`), `POST :id/snooze`
(`:56-60`). Settings: `GET/PATCH /notification_settings`
(`app/controllers/api/v1/accounts/notification_settings_controller.rb:1-30`, route `config/routes.rb:241`).
Push registration: `POST/DELETE /api/v1/notification_subscriptions`
(`app/controllers/api/v1/notification_subscriptions_controller.rb:1-26`, route `config/routes.rb:378`).
Feed serializer: `app/views/api/v1/accounts/notifications/index.json.jbuilder:1-28`.
Socket: `ActionCableListener#notification_created/_updated/_deleted`
(`app/listeners/action_cable_listener.rb:4-30`).

`read_all` is **not** a bulk route in practice: `NotificationsAPI#read(primaryActorType, primaryActorId)` POSTs
to it with one conversation's actor (`app/javascript/dashboard/api/notifications.js:29-34`) and the store calls
it on every row click (`…/store/modules/notifications/actions.js:47-67`). It is the per-row "mark read" path.

## 3. User-visible states

**Feed.** Default view is *unread and not snoozed* — `NotificationFinder` strips snoozed rows unless
`includes` contains `snoozed` and read rows unless it contains `read`
(`app/finders/notification_finder.rb:43-49`); the Display menu adds exactly those two
(`InboxDisplayMenu.vue:25-37`, keys at `app/javascript/dashboard/constants/globals.js:65-73`). 15 rows per page
(`notification_finder.rb:4`), infinite scroll (`InboxList.vue:81-91`), `isAllNotificationsLoaded` when a page
returns fewer than 15 (`…/notifications/actions.js:21-23`). Empty state renders
`INBOX.LIST.NO_NOTIFICATIONS` (`InboxList.vue:255-260`); a spinner while `uiFlags.isFetching` (`:252-254`).
A row shows an unread dot plus heavier type (`InboxCard.vue:95-101`), the type label from
`INBOX.TYPES_NEXT.*`, "Snoozed for {time}" while snoozed and "Snooze ended" once `meta.lastSnoozedAt` is set
(`InboxCard.vue:103-120`).

**Snooze.** `snoozed_until` is a timestamp; snoozing clears `meta.last_snoozed_at`
(`notifications_controller.rb:57`). `ReopenSnoozedNotificationsJob` (every 5 min via
`TriggerScheduledItemsJob` — `app/jobs/trigger_scheduled_items_job.rb:24`, `config/schedule.yml:12-15`) clears
`snoozed_until`, **resets `read_at` to nil**, bumps `last_activity_at` and stamps
`meta.last_snoozed_at` (`app/jobs/notification/reopen_snoozed_notifications_job.rb:14-24`) — so a reopened
notification returns to the top of the feed as unread.

**Badge vs feed can legitimately disagree.** `platform_support_reply` rows are returned by the API and counted
in `meta.unread_count`, but the store drops them before rendering
(`FEED_EXCLUDED_PRIMARY_ACTOR_TYPES` — `app/javascript/dashboard/store/modules/notifications/helpers.js:245-263`,
applied in both feed getters `…/getters.js:186-203`). The exclusion is deliberate and documented there: the
feed is conversation-shaped (`InboxList.vue:164-196` destructures `primaryActor.inboxId`/`id` and routes to
`inbox_view_conversation`). The user-visible consequence is a bell count higher than the list, with the ticket
readable only on the Platform Support surface. The Platform Support screens carry their own separate unread
count (`Sidebar.vue:65-69`).

**Access removed / restored.** A notification disappears from feed, counts, socket and the by-id routes the
moment the recipient loses access to its conversation, and reappears unchanged when access returns — no row is
purged or rewritten (`docs/pre-deploy/05-notification-authorization-closure.md` §4; implementation
`custom/app/finders/custom/notification_finder.rb:43-46`).

**Preferences.** Matrix of type × {Email, Push}; SLA rows are hidden unless the account has the `sla` feature
flag (`NotificationPreferences.vue:43-53`). A per-browser push toggle reflects
`Notification.permission === 'granted'` plus an actual `pushManager` subscription
(`:63-68`, `:107-121`). Defaults for a new membership: email **and** push for `conversation_assignment` only
(`app/models/account_user.rb:47-52`).

**Audio alerts** are a separate layer: tone, scope (`assigned`/`unassigned`/`notme`), only-when-window-hidden,
and recurring re-alert every 30 s (`DashboardAudioNotificationHelper.js:16-20`, `:69-90`).

## 4. Errors and validation messages

| String | Key | `file:line` |
|---|---|---|
| "No notifications" | `INBOX.LIST.NO_NOTIFICATIONS` | `app/javascript/dashboard/i18n/locale/en/inbox.json:8` |
| "There are no active notifications in this group." | `INBOX.LIST.404` | `inbox.json:7` |
| "Oops! Not able to fetch messages" | `INBOX.LIST.NO_MESSAGES_AVAILABLE` | `inbox.json:10` |
| "No content available" | `INBOX.NO_CONTENT` | `inbox.json:42` |
| "Notification marked as read / unread / snoozed / deleted", "All notifications deleted" | `INBOX.ALERTS.*` | `inbox.json:67-75` |
| "Your notification preferences are updated successfully" | `PROFILE_SETTINGS.FORM.API.UPDATE_SUCCESS` | `app/javascript/dashboard/i18n/locale/en/settings.json:183` |
| "There is an error while updating the preferences, please try again" | `PROFILE_SETTINGS.FORM.API.UPDATE_ERROR` | `settings.json:184` — **unreachable**, see §5 |
| "Enable push notifications for your browser so you're able to receive them" | `…NOTIFICATIONS.BROWSER_PERMISSION` | `settings.json:181` |
| "You have enabled push for this browser." / "Enable push notifications" | `…PUSH_NOTIFICATIONS_SECTION.HAS_ENABLED_PUSH` / `.REQUEST_PUSH` | `settings.json:195-196` — **orphaned**, no component references either key (grep over `app/javascript/dashboard/**/*.vue`); the live toggle uses `BROWSER_PERMISSION` at `NotificationPreferences.vue:295` |
| "Autoplay is disabled in your browser…" | `…AUDIO_NOTIFICATIONS_SECTION.SOUND_PERMISSION_ERROR` | `settings.json:151` |
| "This browser does not support desktop notification" | **none — bare string, twice** | `app/javascript/dashboard/helper/pushHelper.js:74`, `:82` |
| Bell/push titles, e.g. "A conversation (#%{display_id}) has been created in %{inbox_name}" | `notifications.notification_title.*` | `config/locales/en.yml:382-390` |
| "Attachment" / "No content" (push body when a message has no text) | `notifications.attachment`, `notifications.no_content` | `config/locales/en.yml:391-392` |
| Email subjects — e.g. "%{name}, A new conversation [ID - %{id}] has been assigned to you." | **none — interpolated in Ruby, not i18n** | `app/mailers/agent_notifications/conversation_notifications_mailer.rb:8,18,29,41,53` |
| "Your Facebook page connection has expired", "Your Whatsapp connection has expired", "Your email inbox has been disconnected. Please update the credentials for SMTP/IMAP" | **none — hard-coded English** | `app/mailers/administrator_notifications/channel_notifications_mailer.rb:3,18,23` |
| "User not found.", "Select at least one subscription to test." | `super_admin.push_diagnostics.*` | `config/locales/en.yml:847-853` |

Server-side validation of notification input is thin: `NotificationSubscription` validates only
`identifier` presence (`app/models/notification_subscription.rb:21`); `Notification` has no validations beyond
the `belongs_to` presence defaults; neither notifications controller calls `authorize`.

## 5. Failure paths

1. **Invalid notification flag → 500, not 422.** `NotificationSettingsController#update_flags`
   (`notification_settings_controller.rb:26-29`) assigns the permitted array straight into FlagShihTzu's
   `selected_email_flags=`, which calls `enable_flag` → `check_flag` →
   `raise ArgumentError, 'Invalid flag "…"'` (`vendor/…/flag_shih_tzu.rb:217-223`, `:468-470`, `:257-265`).
   `selected_email_flags: []` is permitted as an arbitrary array (`:23`), so any unknown string from any client
   is an unhandled 500 reaching Sentry instead of a 422. The record is not saved, because the raise precedes
   `save!` (`:6-10`).
2. **Preferences UI reports success on failure.** `updateNotificationSettings`
   (`NotificationPreferences.vue:122-132`) does **not** `await` the dispatch, while the store action rethrows
   (`userNotificationSettings.js:53-58`). The `try/catch` cannot see the rejection: `UPDATE_SUCCESS` is shown
   unconditionally, `UPDATE_ERROR` (`settings.json:184`) is dead, the rejection is unhandled, and the checkbox
   stays visually toggled against a server that refused it.
3. **Missing `notification_settings` row.** `load_notification_setting` uses `find_by`
   (`notification_settings_controller.rb:18-20`) and both `show` (jbuilder reads seven attributes off it,
   `app/views/api/v1/accounts/notification_settings/show.json.jbuilder:1-7`) and `update` dereference it with
   no nil check. The same nil is handled at `app/models/notification.rb:198-199` and
   `app/builders/notification_builder.rb:17` but **not** in `Notification::EmailNotificationService#user_subscribed_to_notification?`
   (`app/services/notification/email_notification_service.rb:26-31`) or
   `Notification::PushNotificationService#user_subscribed_to_notification?`
   (`app/services/notification/push_notification_service.rb:22-27`) — a membership removed between enqueue and
   perform makes the job raise.
4. **Snooze accepts only epoch seconds.** `parse_date_time` is `DateTime.strptime(datetime, '%s')`
   (`app/helpers/date_range_helper.rb:13-18`); any other format raises `Date::Error` → 500
   (`notifications_controller.rb:58`). Omitting `snoozed_until` entirely is a silent 200 no-op (`:58-59`).
5. **FCM failures are logged as successes and stale tokens are never pruned.**
   `remove_subscription_if_error` tests `JSON.parse(response[:body])['results']&.first&.keys`
   (`push_notification_service.rb:118-124`) — that is the **legacy** FCM HTTP response shape. `send_v1` is
   FCM HTTP v1 (`vendor/…/fcm-1.0.8/lib/fcm.rb:54-67`, `:244-263`), whose bodies carry `name` on success and
   `error.details[].errorCode` (e.g. `UNREGISTERED`) on failure — no `results` key either way. So an
   unregistered device logs "FCM push sent to …" and its subscription row survives indefinitely. An empty body
   (401/503) makes `JSON.parse('')` raise, and `send_fcm_push` has **no rescue** (unlike browser push), so the
   job fails into Sidekiq retries.
6. **Browser push failure handling is the one path that is right.** `handle_browser_push_error`
   (`push_notification_service.rb:75-88`) destroys the subscription on `ExpiredSubscription` /
   `InvalidSubscription` / `Unauthorized`, logs rate limiting and transport errors, and reports anything else
   to `ChatwootExceptionTracker`.
7. **No email at all when SMTP is unset.** Every agent mailer action returns early unless
   `smtp_config_set_or_development?` (`app/mailers/application_mailer.rb:26-28`;
   `conversation_notifications_mailer.rb:3,14,25,35,47`). Nothing surfaces in the UI — the bell row still
   exists, so the user sees a notification and never an email, with no indication why.
8. **No push at all when VAPID/Firebase are unset.** Browser push needs `VapidService.public_key`
   (`push_notification_service.rb:45-47`) and the client needs `window.chatwootConfig.vapidPublicKey`
   (`app/javascript/dashboard/helper/pushHelper.js:56-59`, emitted at
   `app/views/layouts/vueapp.html.erb:51-52`); FCM needs `FIREBASE_PROJECT_ID` + `FIREBASE_CREDENTIALS`
   (`config/installation_config.yml:397-402`), otherwise delivery falls back to the hub relay if
   `ENABLE_PUSH_RELAY_SERVER` is truthy (`push_notification_service.rb:102-116`). The relay swallows every
   exception (`lib/chatwoot_hub.rb:105-111`). Super Admin → Push diagnostics is the only way to see which of
   these is failing (`app/controllers/super_admin/push_diagnostics_controller.rb`,
   `app/services/notification/push_test_service.rb:43-82` — it reports `HTTP <code> — <body>` per subscription
   and can delete stale subscriptions).
9. **Cloud email rate limit silently drops notification email.** `EmailNotificationService` returns unless
   `account.within_email_rate_limit?` (`email_notification_service.rb:10`), which only applies on
   `chatwoot_cloud?` and logs a warning (`app/models/concerns/account_email_rate_limitable.rb:19-25`,
   `:65-67`). No user-facing signal.
10. **Email suppressed for online agents, by design, undocumented.** `assigned_conversation_new_message` and
    `participating_conversation_new_message` return early when `OnlineStatusTracker.get_presence` says the
    agent is online (`conversation_notifications_mailer.rb:36-37`, `:48-49`). Also no email if the
    notification was already read (`email_notification_service.rb:6`,
    `app/jobs/notification/email_notification_job.rb:6`) or the user is unconfirmed (`:8`).
11. **A snooze that expires during a >3-day worker outage never reopens.** The sweep selects
    `snoozed_until: 3.days.ago..Time.current` (`reopen_snoozed_notifications_job.rb:5`); an older expiry is
    outside the window forever, and the row stays invisible in the default feed.
12. **Retention is silent.** `RemoveOldNotificationJob` (daily 22:30, `config/schedule.yml:64-69`) deletes
    every notification older than one month and trims each user to the newest 300
    (`app/jobs/notification/remove_old_notification_job.rb:4-5`, `:14-52`). Nothing in the UI says the feed is
    a 1-month / 300-row window.
13. **Deduplication can drop a row the user has not seen.** `RemoveDuplicateNotificationJob` keeps one row per
    `(account_id, user_id, primary_actor_type, primary_actor_id)` and destroys the rest
    (`app/jobs/notification/remove_duplicate_notification_job.rb:26-39`) — intended, documented at `:1-22`,
    but it means a mention and a later new-message on the same conversation collapse into the newest row only.
14. **Feed can 500 on a hard-deleted conversation.** `index.json.jbuilder:12,17` calls
    `push_message_title` and `primary_actor.push_event_data` unconditionally while
    `Conversation has_many :notifications, dependent: :destroy_async`
    (`app/models/conversation.rb:131`) leaves rows alive until the async job runs. For a restricted member the
    conversation subselect excludes them, but `conversation_rows` returns the relation untouched for an
    unrestricted member (`custom/app/services/notifications/conversation_visibility.rb:199-204`), so an
    administrator's feed can raise during that window. `Message` as `secondary_actor` is safe (`&.` at
    `index.json.jbuilder:20`; `nil.try` paths at `app/models/notification.rb:169-182`).
15. **An SLA notification would raise if one were ever created.** `EmailNotificationService`
    `public_send(notification_type, …)` (`email_notification_service.rb:21-23`) against a mailer with no
    `sla_missed_*` method (`conversation_notifications_mailer.rb:2-56`), even though three Liquid templates
    exist (`app/views/mailers/agent_notifications/conversation_notifications_mailer/sla_missed_*.liquid`).
16. **Invalid push registration payload.** `NotificationSubscriptionBuilder#identifier`
    (`app/builders/notification_subscription_builder.rb:13-17`) returns nil for any `subscription_type` other
    than `browser_push`/`fcm`, so `create!` fails the presence validation → 500; a missing
    `subscription_attributes` is a `NoMethodError`.

## 6. Permissions

| Surface | Gate | `file:line` |
|---|---|---|
| Every notification API action | account membership only (`Api::V1::Accounts::BaseController`), then rows scoped to `current_user.notifications` | `app/controllers/api/v1/accounts/base_controller.rb:1-15`; `notifications_controller.rb:72`, `:80` |
| Feed / `unread_count` / `count` / websocket badge | `Notifications::ConversationVisibility#narrow`, injected at the finder's single source relation | `custom/app/finders/custom/notification_finder.rb:43-46`; `app/finders/notification_finder.rb:13-31, 39-41`; `app/listeners/base_listener.rb:9-15` |
| `update`, `destroy`, `snooze`, `unread` (by id) | `#permits?` → `ConversationPolicy#show?` (or `PlatformSupport::TicketPolicy#show?`); refusal is `ActiveRecord::RecordNotFound` → 404, byte-identical to an unknown id | `custom/app/controllers/custom/api/v1/accounts/notifications_controller.rb:64-69`; `custom/app/services/notifications/conversation_visibility.rb:147-195` |
| `read_all` | narrowed unless the membership is unrestricted | `custom/…/notifications_controller.rb:48-57` |
| `destroy_all` | narrowed with **no** administrator short-circuit, so it cannot destroy what it cannot show | `custom/app/jobs/custom/notification/delete_notification_job.rb:102-110` |
| `notification.created` / `.updated` socket payload | same `#permits?`; `.deleted` deliberately ungated (id only) | `custom/app/listeners/custom/action_cable_listener.rb:31-56` |
| Which actor types may ever be shown | positive allow-list `['Conversation', 'PlatformSupport::Ticket']`, fail-closed for every member including administrators, kept in step with `Notification::PRIMARY_ACTORS` by spec | `custom/app/services/notifications/conversation_visibility.rb:100`; `app/models/notification.rb:84` |
| Write-time access check | `ConversationPolicy#show?` — the same expression as read time | `app/builders/notification_builder.rb:31, 42-53` |
| `inbox_view` route | `[...ROLES, ...CONVERSATION_PERMISSIONS]` | `…/inbox/routes.js:19-21, 26-29`; `app/javascript/dashboard/constants/permissions.js:14-20` |
| Preferences section | `[...ROLES, ...CONVERSATION_PERMISSIONS]` — a custom role with no `conversation_*` permission cannot see or change its own email/push flags | `…/profile/Index.vue:95, 351-359` |
| SLA preference rows | account feature flag `sla` | `NotificationPreferences.vue:40-53` |
| Push registration | authenticated user only, no account scope | `app/controllers/api/v1/notification_subscriptions_controller.rb:16, 133-135` |
| Push diagnostics | Devise `:super_admin` scope via `SuperAdmin::ApplicationController` | `app/controllers/super_admin/push_diagnostics_controller.rb:1` |
| Admin email notifications | recipient set is `Current.account.administrators`; no opt-out exists | `app/mailers/administrator_notifications/base_mailer.rb:24-26` |

The authorization rule itself is the **intersection** of `Conversations::AccessCeiling` (inbox **or** team
membership, administrators and agent bots unrestricted) and `Conversations::CapabilityScope`
(`base` / `unassigned_and_mine` / `mine` / `none` — `custom/app/services/conversations/capability_scope.rb:46`,
`:67-84`), composed in one place (`conversation_visibility.rb:235-246`) and never restated. Platform Support
ticket visibility is **not** affected by `unrestricted?`: it is always
`PlatformSupport::TicketPolicy::Scope` (`conversation_visibility.rb:210-225`).

## 7. Contextual-help opportunities

| UI location | The question a user has there | Suggested registry key | Exists in `DOC_ARTICLES`? |
|---|---|---|---|
| `…/profile/Index.vue:351-359` (Notification preferences section) | "Which of these actually emails me, and when?" | `notificationPreferences` | **No** |
| `NotificationPreferences.vue:174-180` (Email column header) | "Why did I not get an email?" (online-agent suppression, unconfirmed user, no SMTP) | `notificationEmail` | **No** |
| `NotificationPreferences.vue:285-302` (browser push toggle, `BROWSER_PERMISSION` at `:295`) | "Push says enabled but nothing arrives" | `notificationPush` | **No** |
| `pushHelper.js:74,82` ("This browser does not support desktop notification") | "Which browsers work, and what do I do on iOS?" | `notificationPush` | **No** |
| `InboxList.vue:255-260` (`INBOX.LIST.NO_NOTIFICATIONS`) | "Why is My Inbox empty when there are new conversations?" (default = unread + unsnoozed; 1-month/300-row retention) | `myInbox` | **No** |
| `InboxItemHeader.vue:132` (snooze button) | "What does snoozing do, and when does it come back?" | `myInbox` | **No** |
| `InboxOptionMenu.vue:13-21` ("Delete all", "Delete all read") | "Does this delete for everyone? Can I undo it?" | `myInbox` | **No** |
| Sidebar Inbox badge (`Sidebar.vue:416`) | "Why is the badge higher than the list?" (Platform Support rows) | `contactLynomiaSupport` | **Yes** (`documentationLinks.js:93`) |
| `…/profile/Index.vue:340-350` (Audio Alerts) | "Why do I hear no sound / too much sound?" | `notificationPreferences` | **No** |
| Super Admin → Push diagnostics (`app/views/super_admin/push_diagnostics/show.html.erb`) | "What does this HTTP code mean, and should I delete the subscription?" | operator-facing, no key today | **No** |

`DOC_ARTICLES` (`app/javascript/dashboard/helper/documentationLinks.js:11-94`) contains **no notification key
of any kind**. Nothing in the notification UI calls `documentationArticleUrl`.

## 8. Current documentation coverage

Effectively none. Five files in the EN corpus mention the word "notification", each in one passing clause, and
none explains the feature:

| File | What it says |
|---|---|
| `custom/db/documentation/en/conversations/work-in-the-inbox.md:70` | "They get a notification, the conversation appears in…" (mentions) |
| `custom/db/documentation/en/conversations/assign-and-prioritise.md:17` | a table cell: "the Mine tab, their notifications" |
| `custom/db/documentation/en/getting-started/set-up-your-account.md:31` | "the language of the notification emails Lynomia Chat sends" |
| `custom/db/documentation/en/contacts/contacts.md:81` | blocked contacts: "no notifications are raised" |
| `custom/db/documentation/en/integrations/integrations.md:48` | Slack *Alert* mode: "the thread is a notification, not a…" |

No section owns notifications. `workspace/` has four articles (inboxes, teams, roles, help centre),
`conversations/` six (none about My Inbox), `troubleshooting/` seven (all commerce + the support-desk article).
The AR corpus mirrors the EN one, so the gap is symmetric.

## 9. Missing or stale documentation

1. **No "My Inbox" article.** A user cannot find out that the feed defaults to unread-and-unsnoozed, that
   "Snoozed" and "Read" are additive display toggles (`InboxDisplayMenu.vue:25-37`), that pages are 15 rows,
   or that there is one row per conversation because of deduplication
   (`remove_duplicate_notification_job.rb:26-39`).
2. **No notification-preferences article.** The nine types, which two are on by default
   (`app/models/account_user.rb:49-50`), the difference between the bell (always) and email/push (flagged),
   and the fact that `conversation_creation` produces **no bell row at all** unless a flag is on
   (`notification_builder.rb:27`) are all undocumented.
3. **No "why no email" article.** The five silent suppressions — online agent, already read, unconfirmed user,
   SMTP unset, cloud rate limit (§5 items 7, 9, 10) — are the most likely support ticket in this area and
   nothing explains any of them.
4. **No push-setup article, operator or user.** VAPID keys, `FIREBASE_PROJECT_ID`/`FIREBASE_CREDENTIALS`,
   `ENABLE_PUSH_RELAY_SERVER`, the `/sw.js` service worker (`public/sw.js:3-37`), per-browser re-registration,
   and Super Admin → Push diagnostics have no documentation at all.
5. **No retention statement.** One month / 300 rows per user, deleted without warning
   (`remove_old_notification_job.rb:4-5`).
6. **Nothing on the authorization behaviour that a user will notice.** "A notification vanished" and "an old
   notification reappeared" are both expected behaviour (`docs/pre-deploy/05-notification-authorization-closure.md` §4)
   and neither is in the corpus. Same for "Delete all" deleting only what you can currently see
   (`custom/…/delete_notification_job.rb:102-110`) and for the bell counting Platform Support replies the feed
   does not list (`helpers.js:245-263`).
7. **Admin email notifications are undocumented and unswitchable.** Channel-disconnect and import/export
   emails go to every administrator with no preference (`administrator_notifications/base_mailer.rb:24-26`);
   `whatsapp-troubleshooting` / `whatsapp-reconnect-a-number` exist as articles but nothing tells an
   administrator that the trigger for reading them arrives by email.

Nothing in the corpus is *wrong* about notifications — there is too little of it to be wrong.

## 10. Doc claims not proven by code

| Claim | Where | Verdict |
|---|---|---|
| "Notifications from all subscribed inboxes" (`INBOX.LIST.NOTE`, `inbox.json:9`) | UI string, not an article | **Wrong, or at best half true.** The ceiling is inbox membership **or** team membership (`docs/pre-deploy/05-notification-authorization-closure.md` §2; `custom/app/services/conversations/access_ceiling.rb` via `ConversationPolicy`), and the capability scope narrows further to `mine` / `unassigned_and_mine` / `none` (`capability_scope.rb:77-84`). "Subscribed inboxes" describes neither bound. |
| The preferences UI offers SLA email/push rows when the `sla` flag is on (`constants.js:25-36`, `NotificationPreferences.vue:43-53`), and `settings.json:162-164,197-199` promise "Send email notifications when a conversation misses first response SLA" | product copy | **Unverifiable as a promise; refuted as behaviour.** The three `sla_missed_*` enum values have no creation site in `app/`, `custom/` or `lib/` (grep; corroborated at `conversation_visibility.rb:78-79`), so the toggles cannot fire. Email would in fact raise (§5 item 15). |
| "the language of the notification emails Lynomia Chat sends" is set by the account language (`set-up-your-account.md:31`) | corpus | **Confirmed for the body, wrong for the subject.** `ApplicationMailer#switch_locale` uses the account locale (`application_mailer.rb:82-88`), but every agent-notification subject is an English Ruby string (`conversation_notifications_mailer.rb:8,18,29,41,53`) and so is every administrator-notification subject (`channel_notifications_mailer.rb:3-24`). |
| Blocked contacts raise "no notifications" (`contacts.md:81`) | corpus | **Confirmed with one exception the article omits:** mentions are explicitly excluded from the block (`app/builders/notification_builder.rb:29`). |
| Mentioning someone notifies them (`work-in-the-inbox.md:70`) | corpus | **Confirmed, with two undocumented conditions:** the message must be a **private** note with content (`mention_service.rb:17-19`), and the mentioned user must be an inbox member or an account administrator or the mention is dropped silently (`:40-49`). |
| `docs/platform-support/06-sla-notifications.md` describes Platform Support SLA notifications | prior design record | **Not checked against a notification row.** No Platform Support SLA event writes a `notifications` row: `platform_support_reply` is the only type and the only writer (`reply_notifier.rb:34, 40-47`), confirmed by the allow-list reasoning at `conversation_visibility.rb:81-89`. Any SLA signalling in that module is email/desk-side, outside this scope. |
