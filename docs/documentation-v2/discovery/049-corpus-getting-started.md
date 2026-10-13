---
agent: 049
scope: corpus section `getting-started` (5 articles, EN + AR) - classification, accuracy against the product code, and what a day-one operator still lacks
confidence: high
---

# 049 - Corpus: getting-started

Working tree: `claude/documentation-v2`, code identical to baseline `021ea6e3` plus the charter commit. Read-only: `cat`, `sed`, `grep`,
`awk`, and one word-counting script kept outside the repository. Nothing was run against a database, nothing was rendered in a browser.

**Reference conventions.** `welcome:35` is line 35 of `custom/db/documentation/en/getting-started/welcome-to-lynomia-chat.md`;
`ar/welcome:40` is the Arabic file. Article keys are shortened to `welcome`, `set-up`, `invite`, `connect`, `first`. All other paths are
repository-relative.

**Bottom line.** This section is well written and not yet safe to rely on. Voice, structure and honesty about limits are strong -
`set-up` tells an operator the truth about timezones, and every one of its timezone claims survives a code check. But the section was written from a capability map, not from a walk through the product, and
it shows in three places a first-day operator cannot avoid: **the reopen-versus-new-conversation model is wrong by default**
(`first`), **the channel picker and the WhatsApp manual setup it describes are not what the product shows** (`connect`), and **the
Arabic edition links every in-text reference to the English article** (all 28 links). Separately, the section never mentions four
things the product puts in front of a new operator in the first ten minutes: the first-run "review your details" screen, agent
availability, the trial/plan/limit machinery, and how to reach Lynomia. Of 68 claims checked, 17 are wrong (several only partly), 3 could
not be verified from code, and 48 hold.

---

## 1. Inventory

Word counts are whitespace tokens of the body after stripping Markdown punctuation (approximate; AR is naturally about 18 percent
shorter). All ten files carry front matter; none carries `seo_title`, `version` or `release_date`; all ten carry
`tags: [getting-started]` and nothing else. None contains an image (0 of 10). Positions are identical in both languages.

| Key | EN file | AR file | Title (EN / AR) | Position | EN words | AR words |
|---|---|---|---|---|---|---|
| `welcome-to-lynomia-chat` | `en/getting-started/welcome-to-lynomia-chat.md` | `ar/getting-started/welcome-to-lynomia-chat.md` | Welcome to Lynomia Chat / مرحباً بك في لينوميا تشات | 10 | 475 | 382 |
| `set-up-your-account` | `en/getting-started/set-up-your-account.md` | `ar/getting-started/set-up-your-account.md` | Set up your account / جهّز حسابك | 20 | 730 | 613 |
| `invite-your-team` | `en/getting-started/invite-your-team.md` | `ar/getting-started/invite-your-team.md` | Invite your team / ادعُ فريقك | 30 | 823 | 657 |
| `connect-your-first-channel` | `en/getting-started/connect-your-first-channel.md` | `ar/getting-started/connect-your-first-channel.md` | Connect your first channel / اربط أول قناة | 40 | 942 | 762 |
| `your-first-conversation` | `en/getting-started/your-first-conversation.md` | `ar/getting-started/your-first-conversation.md` | Your first conversation / أول محادثة لك | 50 | 969 | 797 |
| **Total** | 5 files | 5 files | | | **3,939** | **3,211** |

Facts about the section as a whole, each checked:

- The manifest entry is `getting-started`, position 10, icon `rocket` (`custom/db/documentation/manifest.yml:7-15`). Both locales have
  exactly five files; EN and AR key sets are identical for the whole corpus (scripted: 63 = 63).
- All five keys exist in the contextual-help registry (`app/javascript/dashboard/helper/documentationLinks.js:13-17`), **but no
  dashboard surface uses any of them**. `DocsLink` is placed only in Commerce dialogs and the Platform Support pages
  (`CommercePanel.vue:415`, `ProviderPicker.vue:118`, `ShopifyConnectDialog.vue:116`, `SallaConnectDialog.vue:221`,
  `StoreDialog.vue:213`, `ZidConnectDialog.vue:86`, `PlatformSupport*Page.vue`); the sidebar "Read documentation" item opens the
  documentation home (`SidebarProfileMenu.vue:58-60,101-107`). The one surface that is literally an empty first-run screen -
  `OnboardingView` (`EmptyState.vue:77-79`) - carries no link, even though the program's own rule says a link belongs "looking at an
  empty surface" (`docs/global-documentation/12-contextual-help.md:58-60`).
- Every in-text link target in the section exists as a published EN key and as an AR key (scripted over all 56 links: 0 unresolved).
  What the links *do* in Arabic is a different matter (X1 below).
- Correction to the baseline map: `01-current-system.md` section 7 says `DOC_ARTICLES` has 87 keys. The object at
  `documentationLinks.js:11-94` has **62**.

## 2. Per-article verdict

| Key | Verdict | Reason | Evidence (IDs from section 3) |
|---|---|---|---|
| `welcome-to-lynomia-chat` | **EXPAND** | Good orientation, but step 1 promises a timezone the very next article says does not exist, and it never mentions the first-run screen, availability, the trial/plan, or how to reach Lynomia. Two small sentences to correct, four things to add. | W1; section 4 items 1-4 |
| `set-up-your-account` | **SPLIT** | Keep the admin account-settings content (it is the best-verified article in the section) and extract a personal-setup article - language, availability, notifications, MFA, signature - that the information architecture promised to merge in and never did. The invitation-email quote needs correcting in both languages. | S3, S4, P3; `docs/global-documentation/03-chatwoot-doc-map.md:114-116,159,164,271,289` |
| `invite-your-team` | **EXPAND** | The core flow, including the non-obvious "no email for someone who already has a login", is correct. Four specifics are wrong (permission list, limit message, error string, invitation wording/language) and plan-gating of custom roles goes unstated; the pending-invitation state is not mentioned. | I3, I5, I10, I11, S3 |
| `connect-your-first-channel` | **REWRITE** | Lists channels the picker no longer offers, describes a manual-setup form that is no longer the live path, overlaps and contradicts `connect-whatsapp`, and mixes a channel overview with a WhatsApp procedure. Rebuild as a channel-neutral picker article that hands WhatsApp to `connect-whatsapp`, and add the website-widget path. | C4, C5, C6, C7, C15, C16, X4, X6 |
| `your-first-conversation` | **REWRITE** | The four-move skeleton (reply, assign, label, resolve) is right and worth keeping. Three of its central claims are wrong or self-contradictory: reopen versus new conversation, what Pending means, and what the composer does outside the 24-hour window. | F2, F4, F15, F16, X3, X7 |

No article should be RETIRED, MERGED away or RELOCATED. One duplication is worth removing at rewrite time: the "three languages" table
appears twice (`welcome:51-58` and `set-up:38-46`) with different columns; keep the fuller one in `set-up` and link to it.

## 3. Accuracy against the product

**68 claims checked: 48 confirmed, 17 wrong (several only partly), 3 unverifiable from code.** "Wrong" is used for partly wrong where
the wrong part would mislead; the evidence cell says which part. IDs are stable for cross-reference.

### welcome-to-lynomia-chat

| ID | Claim (article line) | Status | Evidence |
|---|---|---|---|
| W1 | Step 1 is "Set up your account - your business name, your timezone, your language" (`welcome:35`, `ar/welcome:32`) | **wrong** | The account form has name and language, plus domain and support email only when inbound email is enabled (`app/javascript/dashboard/routes/dashboard/settings/account/Index.vue:171-237`). No timezone field. The only timezone prompt is the first-run screen (`onboarding/Index.vue:315`), stored in `custom_attributes` (`app/controllers/api/v1/accounts/onboardings_controller.rb:75-77`) and read by nothing. `set-up:50` says so itself, so the section contradicts itself in adjacent articles. |
| W2 | Setting up the account, connecting channels and inviting people are administrator jobs (`welcome:43-45`) | confirmed | `account.routes.js:9-11,17-19`; `inbox.routes.js:32,60`; `agent.routes.js:24`; `app/policies/user_policy.rb:5-19`. |
| W3 | Dashboard language is set in your profile, account language in account settings (`welcome:51-55`) | confirmed | User locale wins, otherwise account locale: `app/javascript/dashboard/App.vue:111-118`. |
| W4 | Template language "is set on the template itself" (`welcome:55`) | unverifiable | Template internals are agent 040/053 territory; not checked here. |
| W5 | Step 5 "Connect your store" links to `commerce-overview` (`welcome:39`) | wrong (minor) | The label promises a procedure; the target's title is "What connecting a store gives you" (`commerce/commerce-overview.md:2`). Four `connect-*` procedure articles exist. |
| W6 | Context beside the conversation (orders) and rules that "route, reply, tag and assign" (`welcome:16-19`) | confirmed | `components/widgets/conversation/commerce/CommercePanel.vue`; automation actions `assign_agent`, `assign_team`, `add_label`, `send_message` at `settings/automation/constants.js:92-120`. Behaviour belongs to agents 036/043. |
| W7 | "Built around WhatsApp, because that is where customers in this region actually are"; "not a marketing blast tool" (`welcome:12,23`) | unverifiable | Positioning statements; no code evidence is possible. |

### set-up-your-account

| ID | Claim | Status | Evidence |
|---|---|---|---|
| S1 | **Account Settings -> General** holds business name and language; administrators only (`set-up:11-13,17`) | confirmed | Sidebar entry `components-next/sidebar/Sidebar.vue:793` (under the "Account" heading, `settings.json:438`); "General settings" is a *section heading inside* the page (`generalSettings.json:40`), not a menu level; route is admin-only (`account.routes.js:9-11,17-19`). |
| S2 | Name and language are both required (`set-up:22,28,93-94`) | confirmed | Client validation `account/Index.vue:48-53`; server requires name only (`app/models/account.rb:44`). |
| S3 | The invitation reads "You are invited to join <business>" (`set-up:22-24`; `ar/set-up:20-21`) | **wrong** (partly) | Heading is "You're invited to join {account_name}" (`app/views/devise/mailer/confirmation_instructions.html.erb:37`, pinned by `spec/mailers/confirmation_instructions_spec.rb:61`); body line "{inviter} invited you to join the {account} workspace on {brand}" (`:39`); button "Accept invitation" (`:44`). The AR quote is worse - see P2. |
| S4 | Account language sets the language of "the notification emails Lynomia Chat sends" (`set-up:31`) | **wrong** (partly) | True for notification mailers: `app/mailers/application_mailer.rb:71-87` picks the account locale. Not true for the invitation or password-reset mail: their text is hard-coded English (`confirmation_instructions.html.erb:9-47`; `reset_password_instructions.html.erb:1-8`); only the subject is localised (`config/locales/devise.ar.yml:19-20`; EN subject is "Confirmation Instructions", `devise.en.yml:20-21`). |
| S5 | Account language is the dashboard default for anyone without their own choice (`set-up:30`) | confirmed | `App.vue:111-118`. |
| S6 | Account language decides the live-chat widget's language (`set-up:32`) | confirmed | `app/views/widgets/show.html.erb:12`; `app/javascript/widget/App.vue:93-94`. |
| S7 | Own language wins for the dashboard but not for emails; "Use account default" resets it (`set-up:44-46`) | confirmed | `App.vue:111-118`; `application_mailer.rb:82-87` (mail ignores the recipient's choice); `settings.json:60`. AR label - see P3. |
| S8 | No account-wide timezone; business hours use the channel's timezone (`set-up:50-55`) | confirmed | `inboxes.timezone` (`db/schema.rb:1418`), `working_hours_enabled` default false (`:1416`), hours computed in the inbox zone (`app/models/working_hour.rb:46-54`), zone validated (`app/models/inbox.rb:54`). Nuance: `Account` has a hidden `settings.reporting_timezone` (`account.rb:59,217-221`) used only for rollups (`app/services/reporting_events/rollup_service.rb:25-30`); it is not in the form or in the permitted API settings (`app/controllers/api/v1/accounts_controller.rb:122-124`), so it changes nothing for an operator. |
| S9 | Reports use the timezone of the browser (`set-up:56`) | confirmed | `app/javascript/dashboard/api/reports.js:4,29,57,80`; `app/controllers/api/v2/accounts/reports_controller.rb:48-49`. |
| S10 | The first-run timezone is "recorded as a business detail" and drives neither (`set-up:57`) | confirmed | Stored at `onboardings_controller.rb:75-77`; grep of `app/`, `lib/`, `custom/` finds no reader of `custom_attributes['timezone']`. |
| S11 | A new channel is created on UTC (`set-up:59`) | confirmed | `db/schema.rb:1418`. |
| S12 | `Asia/Kuwait` and `Asia/Riyadh` can be chosen for business hours (`set-up:61`) | confirmed | Both present in `settings/inbox/helpers/timezones.json`; selector is `WeeklyAvailability.vue:62-71`. |
| S13 | Custom reply domain and support email appear only if inbound email is enabled (`set-up:80-81`) | confirmed | `account/Index.vue:77-90`: needs `inbound_emails` plus `custom_reply_domain` / `custom_reply_email`. |

Omitted from `set-up` although the same page carries them: the audio-transcription switch, the Account ID block and the build
information (`AudioTranscription.vue`, `AccountId.vue`, `BuildInfo.vue`, mounted at `account/Index.vue:247-249`). Account ID is the
first thing any support desk asks for.

### invite-your-team

| ID | Claim | Status | Evidence |
|---|---|---|---|
| I1 | **Settings -> Agents -> Add agent** (`invite:48`) | confirmed | `Sidebar.vue:816`; `agentMgmt.json:4` ("Add Agent"); the sidebar groups it under a "People" heading (`settings.json:439`). |
| I2 | Role choice is Administrator, Agent, or a custom role, in one dropdown (`invite:25-29`) | confirmed | `settings/agents/AddAgent.vue:34-54,128`. |
| I3 | A custom role is built from six permissions (`invite:31-38`) | **wrong** | The client offers **seven**: the list plus `support_ticket_manage`, "Manage every support case in the account" (`app/javascript/dashboard/constants/permissions.js:4-12`; `customRole.json:35`). The server vocabulary has eight, including the retired `knowledge_base_manage` (`custom/app/models/custom_role.rb:19-28`). The sibling `workspace/roles-and-permissions.md:3,22` repeats "exact six". |
| I4 | Refunds and cancellations stay administrator-only (`invite:40-41,82-83`) | confirmed | `custom/app/policies/commerce/action_policy.rb:6,23-29`. |
| I5 | Custom roles presented as always available (`invite:29`) | **wrong** (omission) | Plan-gated: `custom_roles` is `enabled: false` in `config/features.yml:155-157` and the Custom Roles page needs the flag (`customRole.routes.js:23`). `roles-and-permissions.md:9` says "on paid plans"; this article never does. |
| I6 | New address: invitation email, button leads to choosing a password, signed in afterwards (`invite:55-57`) | confirmed | `app/builders/agent_builder.rb:34,62-64`; template `:44-47`; `app/controllers/devise_overrides/passwords_controller.rb:15-24` signs the user in. |
| I7 | Existing login: no email, added at once (`invite:59-61`) | confirmed | `agent_builder.rb:47-49,62-64` - `@new_user` is set only for a brand-new user, so no mail is queued. |
| I8 | Never set a password for them (`invite:20-21`) | confirmed | `agent_builder.rb:51-53` creates a random temporary password nobody sees. |
| I9 | An administrator can send a reset email from the agent's page, cannot read or choose the password (`invite:75-77,88`) | confirmed | `settings/agents/EditAgent.vue:146-148,215`; `agentMgmt.json:94-95`. "Agent's own page" is the Edit agent dialog. |
| I10 | A plan limit makes the save fail "with a message about licences" (`invite:86-87`) | **wrong** | The message is "Your plan allows up to %{limit} team members. Upgrade your plan to invite more." (`config/locales/en.yml:300`, raised by `custom/app/controllers/billing/access_guard.rb:40-47` and shown by `AddAgent.vue:100`). The "purchase more licenses" string (`agent_builder.rb:5`) is upstream; its ceiling is 100,000 (`lib/chatwoot_app.rb:10-12`, `account.rb:159-163`) so it is never reached. |
| I11 | The error is "This email address is already in use." (`invite:98-99`) | **wrong** | Actual text: "Agent email already in use, Please try another email address" (`agentMgmt.json:47`), shown for any 422 without a `base` attribute (`AddAgent.vue:94-97`) - so also for a malformed address. |
| I12 | An agent sees nothing until made a channel member; administrators see every channel (`invite:51,84-85,105-106`) | confirmed | `app/models/user.rb:138-140`; `EmptyState.vue:77-79`; `conversation.json:20`. |
| I13 | Auto-assignment gives a new conversation to an online member (`invite:15-16`) | confirmed | `app/services/auto_assignment/agent_assignment_service.rb:61-71`; default on (`schema.rb:1412`). Caveat: a separate `assignment_v2` path exists (`app/models/inbox.rb:206-208`, `app/models/concerns/auto_assignment_handler.rb:15-27`); not examined (agent 032). |
| I14 | Role names are fixed at administrator and agent (`invite:81`) | confirmed | `app/models/account_user.rb:34`; `agentMgmt.json` `AGENT_TYPES`. |

### connect-your-first-channel

| ID | Claim | Status | Evidence |
|---|---|---|---|
| C1 | Nine channels are connectable (`connect:18-28`) | confirmed | `settings/inbox/ChannelList.vue:25-80`; SMS providers Twilio/Bandwidth at `inboxMgmt.json:197-201`. |
| C2 | Facebook and Instagram need an installation-level Meta app; unavailable tiles are greyed, not hidden (`connect:30-31`) | confirmed | `components/widgets/ChannelItem.vue:20-26,40-51,123` (`:disabled`). |
| C3 | TikTok appears only where configured (`connect:31-32`) | confirmed | `ChannelList.vue:19-21,82-98`. |
| C4 | "Voice and WhatsApp calling are marked beta and depend on being switched on for your account" (`connect:32-33`; `ar/connect:30-31`) | **wrong** | The cards were removed - "neither could create a working inbox" (`ChannelList.vue:96-99`); neither is in the list at `:25-80`. Dead branches survive in `ChannelItem.vue:57-59,82-84`. The same sentence sits in `workspace/set-up-an-inbox.md` (X4). |
| C5 | A greyed tile means an installation setting, "not something you can change from your account" (`connect:33-34,105-106`) | **wrong** (partly) | Tiles are also disabled by account feature flags (`ChannelItem.vue:32-52`), which the plan writes (`custom/app/services/billing/feature_sync.rb:25-34`), and creating a channel the plan excludes is refused with "Your plan does not include the %{channel} channel. Upgrade your plan to connect it." (`custom/app/models/billing/inbox_limit.rb:36-40`; `en.yml:303`). A plan change is an account-level remedy. |
| C6 | Four WhatsApp providers to choose from (`connect:57-62`) | **wrong** (partly) | The picker shows three tiles: WhatsApp Cloud (quick setup, or "manual setup" wording when Meta quick setup is restricted), Twilio, and WhatsApp Business, the last only when embedded signup is available (`settings/inbox/channels/Whatsapp.vue:60-68,98-125,127-139`). Manual setup is a link under quick setup (`:271-290`). 360dialog code is present but not offered (`:307-310`). |
| C7 | Manual setup asks for the phone number, phone number ID, business account ID, "an API key and a webhook verify token" (`connect:64-65`; `ar/connect:59-60`) | **wrong** | The live manual flow collects Phone Number ID, WhatsApp Business Account ID and a "Permanent access token" (`inboxMgmt.json:356-361`; `WhatsappManualSetup.vue:471-486,570`), then Lynomia "is checking number access and configuring your Meta webhook" (`inboxMgmt.json:375-376`). The API-key plus verify-token form is the legacy `CloudWhatsapp.vue`, reached only by a `v-else` fallback (`Whatsapp.vue:311`). `whatsapp/connect-whatsapp.md:31` states the three-field version, so the two articles contradict each other (X6). |
| C8 | A step lets you choose which agents work in the channel (`connect:66-67`) | confirmed | `settings/inbox/AddAgents.vue`; route listed in `Sidebar.vue` `activeOn` (`settings_inboxes_add_agents`). |
| C9 | The WhatsApp finish step shows a QR code for a test message (`connect:68-69`) | confirmed | `settings/inbox/FinishSetup.vue:71-73,119-121`; `inboxMgmt.json:706`. |
| C10 | A Meta setup that ends without a number "cannot produce a channel" (`connect:108-109`) | confirmed | `inboxMgmt.json:434` ("finished without a WhatsApp phone number that can be connected"). |
| C11 | Auto-assignment is on for a new channel and considers only online members (`connect:88-89`) | confirmed | `db/schema.rb:1412`; `agent_assignment_service.rb:61-71`. |
| C12 | A new channel is on UTC (`connect:77,86-87`) | confirmed | `db/schema.rb:1418`. |
| C13 | Agents cannot reach Inboxes settings (`connect:82`) | confirmed | Route-level: `inbox.routes.js:32,60`. Sidebar filtering not separately checked. |
| C14 | Quick setup is not available on every account and Meta sometimes restricts it (`connect:92-93`) | confirmed | `Whatsapp.vue:48-53,60-68,102-104`; `inboxMgmt.json:274-275`. |
| C15 | "Contacts are created by the messages that arrive through a channel... Until a channel exists, the dashboard has nothing to show you" (`connect:12-14`) | **wrong** (overstated) | A contact can be created and imported with no inbox (`app/controllers/api/v1/accounts/contacts_controller.rb:89-97,188`; `contacts/import-contacts.md:2-4`). |
| C16 | "WhatsApp templates belong to the WhatsApp number" (`connect:90`) | **wrong** (imprecise) | Lynomia reads templates from the business account, not the number (`app/services/whatsapp/providers/whatsapp_cloud_service.rb:50,128`). Meta-side semantics belong to agents 009/014. |
| C17 | The number must "not already be in use on personal WhatsApp" (`connect:48-49`) | unverifiable | A Meta rule; not a code claim. Agents 013-015. |

### your-first-conversation

| ID | Claim | Status | Evidence |
|---|---|---|---|
| F1 | Four statuses: open, pending, snoozed, resolved (`first:24-29`) | confirmed | `app/models/conversation.rb:86`. |
| F2 | Pending means "waiting on you, deliberately parked" (`first:27`; `ar/first:26`) | **wrong** | The product creates pending conversations for bots (`conversation.rb:320-322`; `ReplyBox.vue:276-281`; `app/models/message.rb:425-428`). `conversations/work-in-the-inbox.md:18` defines it as "A bot is handling it, or it is parked for one". A person can set it from the context menu (`conversation.json:240`), but "waiting on you" describes Open. |
| F3 | Snooze: until a chosen time or until the customer replies; the listed options (`first:28,81-83`) | confirmed | `app/javascript/dashboard/constants/globals.js:52-57`; `message.rb:404-408` (snoozed becomes open on an incoming message). |
| F4 | When the customer writes after a resolve, "the conversation reopens with its history intact"; the worked example's three-week-later reopen; "A new message from the same contact reopens the same conversation" (`first:9-10,29,76-78,95-97,112`; `ar/first:88-90,103`) | **wrong** | By default a *new* conversation is created. `lock_to_single_conversation` defaults to false (`db/schema.rb:1423`); WhatsApp chooses `conversations.where.not(status: :resolved).last` when it is false (`app/services/whatsapp/incoming_message_base_service.rb:130-137`) and nothing sets it true at creation. The inbox setting is "Conversation Routing": "Reopen same conversation" / "Create new conversations - A new conversation will be created each time after the previous one is resolved" (`inboxMgmt.json:757-760,1151`; `Settings.vue:573,696`). `message.rb:404-422` reopens only a message that lands on a resolved conversation, i.e. when the setting is on (or via the API). The same claim is in `conversations/work-in-the-inbox.md:16-24` (X3). |
| F5 | Assignment tabs Mine / Unassigned / All (`first:31`) | confirmed | `chatlist.json:37-41`. |
| F6 | Auto-assign to an online member, otherwise unassigned and waiting (`first:36-38,109-110`) | confirmed | `agent_assignment_service.rb:61-71`; `assignment_service.rb:6`. |
| F7 | Composer has Reply and Private Note modes (`first:44-45`) | confirmed | `conversation.json:295-296`. |
| F8 | `/` opens canned responses in a reply, not in a note (`first:50-51`) | confirmed | `components/widgets/WootWriter/Editor.vue:262` (`!props.isPrivate`); `conversation.json:284`. |
| F9 | `@` in a private note mentions a colleague or a team, which notifies them (`first:52`) | confirmed | `Editor.vue:271`; `TagAgents.vue:44-62`; `app/services/messages/mention_service.rb:22-36` expands team mentions. |
| F10 | `Shift + Enter` is a new line (`first:54`) | confirmed (default) | `conversation.json:284`. The send key is a profile preference (`settings/profile/Index.vue:207`), so with Cmd/Ctrl+Enter chosen, plain Enter is the newline. |
| F11 | Side panel sets agent, team, priority (low/medium/high/urgent), self-assign (`first:58-64`) | confirmed | `routes/dashboard/conversation/ConversationAction.vue`; `conversation.rb:87`; `conversation.json` `SELF_ASSIGN`. |
| F12 | `L` adds a label; only an administrator can create one from there (`first:68-72`) | confirmed | `routes/dashboard/conversation/labels/LabelBox.vue:39-44,116` (`:allow-creation="isAdmin"`). |
| F13 | Resolve button in the conversation header; Snooze; Reopen (`first:76-83`) | confirmed | `components/widgets/conversation/MoreActions.vue:95`; `components/buttons/ResolveAction.vue`; `conversation.json:142-143`. |
| F14 | Accounts can require fields before resolving (`first:85-86`) | confirmed | `composables/useConversationRequiredAttributes.js:24-37` (behind a feature flag). |
| F15 | Past 24 hours a plain reply "is marked as failed... The composer will still let you type it" (`first:105-108`) | **wrong** (partly) | The failure text is exact (`en.yml:185`; `app/services/whatsapp/send_on_whatsapp_service.rb:15-17`). But the dashboard *disables* the editor when the window is closed (`ReplyBox.vue:517-523`, placeholder `:289-292`, send disabled `:309`, copy `conversation.json:287`, banner `MessagesView.vue:476-481`). The failed-message path is reached by automation, flows or the API - as `whatsapp/the-whatsapp-24-hour-window.md:41-47` says. |
| F16 | "The composer tells you that you can only reply with a template. Same cause, stated before you send." (`first:128`) | confirmed | Same evidence as F15 - and it contradicts F15 two sections earlier in the same article. |
| F17 | A private note is readable by every agent on the conversation (`first:113`) | confirmed | Placeholder "visible only to Agents" (`conversation.json:285`). |

### Findings outside this section that the orchestrator must arbitrate

These were found while checking the section above and are verified, but they belong to other agents' files.

| ID | Finding | Evidence | Owner |
|---|---|---|---|
| X1 | **Every in-text link in the Arabic edition resolves to the English article.** The AR article's slug is `<key>-ar` (`content_seeder.rb:85-87`), but its body links are bare keys; nothing rewrites them (`content_seeder.rb` whole file; `lib/chatwoot_markdown_renderer.rb:13-19`; `lib/custom_markdown_renderer.rb:54-59`; `lib/markdown_renderer_url_sanitizer.rb:6-9`); the article URL has no locale segment (`config/routes.rb:519`: `hc/:slug/articles/:article_slug`); the lookup is by slug alone (`articles_controller.rb:80-82`). So `[Invite your team](invite-your-team)` inside `invite-your-team-ar` resolves to `/hc/lynomia-docs/articles/invite-your-team`, the English page. All 28 internal-link occurrences in this section's AR files are affected; the same applies corpus-wide. Not browser-verified: derived from URL resolution rules. | as cited | 061, 076, 094 |
| X2 | **Product links never carry a locale, so an Arabic operator always lands on the English article.** `documentationArticleUrl` returns `<base>/<slug>` (`documentationLinks.js:102-107`); `DocumentationController#article` passes only `params[:locale]` (`documentation_controller.rb:22`); `Library.article_for` with a nil locale falls straight to English (`library.rb:54-57`). The design record says the opposite (`docs/global-documentation/12-contextual-help.md:51`), as does the commit that introduced the pipeline. Correction to `01-current-system.md` section 7. | as cited | 076, 094 |
| X3 | The "resolved conversation reopens" claim is also in the conversations section. | `conversations/work-in-the-inbox.md:16-24` vs F4 | 050 |
| X4 | The stale "Voice and WhatsApp calling depend on being switched on" sentence is also in the workspace section. | `workspace/set-up-an-inbox.md` ("The channels you can connect") vs C4 | 057 |
| X5 | `roles-and-permissions` says the permission list is "exact six"; the client offers seven. | `workspace/roles-and-permissions.md:3,22` vs `permissions.js:4-12` | 057, 033 |
| X6 | `connect-whatsapp` and `connect-your-first-channel` describe two different manual-setup forms. The code agrees with `connect-whatsapp`. | C7 | 053, 039 |
| X7 | `the-whatsapp-24-hour-window` says the composer is switched off; `your-first-conversation` says it still lets you type. The code agrees with the first. | F15 | 053 |
| X8 | Invitation and reset-password emails are hard-coded English; documentation that quotes them in Arabic describes mail nobody receives. | S3, S4 | 034, 094 |
| X9 | Billing, trial and plan limits shape what a new operator can do on day one, and no article in the corpus describes them (grep of all 63 EN files for trial / subscription / plan limit finds only unrelated hits). | section 4, item 3 | 048, 059 |

## 4. Missing articles

Ordered by how soon a new operator hits the problem. "Evidence" is the product behaviour that exists today and is undocumented. P0 means
a day-one operator is blocked, misled or silently unserved without it.

| # | Article | The question it answers | Evidence in the product | Priority |
|---|---|---|---|---|
| 1 | **Sign in, and what you see first** | "I have a login. Where do I go? What is this 'review your details' screen? Why does it insist on a website? Why is there a banner asking me to verify my email?" (banner: `App.vue:146`, `PendingEmailVerificationBanner.vue:10-19`) | A guard redirects an administrator to onboarding until the step clears (`routes/index.js:10,38-56`); one screen collects role, website (required, `onboarding/Index.vue:57`), language, timezone, industry, company size, source (`onboarding.json:2-33`). On this deployment it is one step: the second is cloud-only and `chatwoot_cloud?` needs an enterprise tree that does not exist (`onboardings_controller.rb:35-42`; `lib/chatwoot_app.rb:19-25`). Accounts get the step only through signup (`app/builders/account_builder.rb:46-52`); signup is off by default (`config/installation_config.yml:73-76`). Otherwise an administrator with no inboxes sees four cards - inbox, team, canned responses, labels (`EmptyState.vue:77-79`; `OnboardingView.vue:47-78`) - in a different order from the corpus's five steps. Unverified: which entry path production accounts take. | P0 |
| 2 | **Go online: availability, notifications and your own settings** | "I am in but nothing is assigned to me." "How do I get notified?" "How do I turn on two-factor?" | Auto-assignment skips anyone not Online (`agent_assignment_service.rb:61-71`); statuses Online / Busy / Offline (`settings.json:214-222`); new users default to `auto_offline: true` (`db/schema.rb:52`). The profile page carries `NotificationPreferences.vue`, `MfaSettings.vue`, `MessageSignature.vue`, `UserLanguageSelect.vue`, `AudioNotifications.vue`, `AccessToken.vue` (`settings/profile/`). The corpus mentions availability only in passing (`conversations/assign-and-prioritise.md:35`) and `first:133` says "Set yourself online" without saying where. The IA promised to merge profile, notifications, signature and MFA into `set-up-your-account` (`docs/global-documentation/03-chatwoot-doc-map.md:114-116,159,164`); none of it is there. | P0 |
| 3 | **Your plan, your trial and your limits** | "Why does it say my plan allows N team members?" "Why am I sent to a subscription page?" "How long is the trial?" | A 402 `subscription_required` on any account API call (`custom/app/controllers/billing/access_guard.rb:21-34`) redirects to the subscription page (`helper/billingGuard.js:1-18`); plan caps on agents, inboxes, stores and channel types (`config/initializers/billing.rb:6-12`; `billing/inbox_limit.rb:21-40`; `en.yml:298-304`); trial defaults to 14 days once a trial plan is set (`custom/app/services/billing/settings.rb:11-12`; `trial_starter.rb:19-27`); Billing is an administrator page (`Sidebar.vue:802`; `billing.routes.js:10,19`). Unverified: whether enforcement is on in production - the code is inert until a plan exists. | P0 if enforcement is live, else P1 |
| 4 | **Getting help from Lynomia** | "Something is wrong and the docs do not say what. Who do I ask?" | The desk exists (`routes/dashboard/help/pages/PlatformSupport*.vue`) and so does `troubleshooting/contact-lynomia-support.md` and its registry key (`documentationLinks.js:93`). None of the five articles links to either. A pointer in `welcome` and in each "If it does not work" block, not a new article. | P0 (small) |
| 5 | **Connect your website live chat** | "How do I put the chat bubble on my site?" | The tile is first in the picker (`ChannelList.vue:27-31`); the finish step shows the script to paste (`FinishSetup.vue:104-105,200`; `inboxMgmt.json:705`). `welcome` promises messages "on your website"; the only mention of the widget is a settings tab row in `workspace/set-up-an-inbox.md`. | P1 |
| 6 | **Connect email, Telegram, Line, SMS, Facebook, Instagram** | One short procedure per tile the picker offers. | `ChannelList.vue:25-80`. The corpus has WhatsApp procedures and a one-line table row for everything else. | P1 (owners 041, 042, 058) |
| 7 | **Before your agents start: labels, canned responses, business hours** | "What should an administrator prepare so agents do not get stuck?" | `first:71-72,130-131` tells agents to ask an administrator for labels, but nothing tells the administrator to prepare them; the product's own onboarding cards do (`OnboardingView.vue:63-78`). The UTC business-hours trap is described inside two other articles with no procedure (`set-up:59-61`, `connect:77-78`; the procedure is in `workspace/set-up-an-inbox.md`). | P1 |
| 8 | **Agent day one** | "I am not an administrator. What do I do first?" | The section's stated reader is "a new admin, in their first hour" (`docs/global-documentation/06-information-architecture.md:27`). An agent's first screen is "Looks like you are not part of any inbox" (`conversation.json:20`), then availability, then the keyboard-shortcuts dialog (`SidebarProfileMenu.vue:77-82`). Only `first` speaks to them, and it assumes setup is finished. | P1 |
| 9 | **Glossary: the words Lynomia uses** | channel versus inbox; administrator, agent, custom role; team; label; status; window; template - with the Arabic terms the Arabic UI actually shows. | `docs/global-documentation/03-chatwoot-doc-map.md:79` planned a glossary and delivered a three-row language table. Arabic UI uses one word, "قنوات التواصل", for Inboxes (`ar/settings.json:353`), which collides with "قناة" (channel). | P1 |
| 10 | **Check that it works** | "I connected a channel - what does 'working' look like, and what are the five reasons it is not?" | The five reasons already appear scattered as "if it does not work" bullets: UTC hours, offline agents, not a member, window closed, Meta restriction (`set-up:59-61`, `invite:105-106`, `connect:105-115`, `first:125-134`). One end-to-end test page would carry them. | P1 |

Not assessed: a mobile app. `docs/global-documentation/03-chatwoot-doc-map.md:268-269` says to mention it "only where true"; `Billing::Settings`
has a mobile checkout switch (`settings.rb:17`) which suggests one exists, but whether this installation ships one cannot be settled
from the repository.

## 5. Quality

**Structure.** All five share a skeleton - what you need first, body, a worked example, who can do this, limits, related, if it does not
work - and it is the right one for task-oriented support content. Headings are `##` throughout; the front-matter `description` is
written as an outcome ("You will have..."), which suits a category card. The sequence is signposted only in `welcome` (`## Next`,
`welcome:60-62`); articles two to five end with "Related" lists and no "Next" link, so the numbered path the welcome page promises is not
walkable.

**Task orientation.** `invite` and `connect` are step lists; `set-up` is mostly explanation with one action (change the channel's
timezone); `welcome` and `first` are orientation. The two with the strongest "do this" shape are the two with the most stale
procedural detail (C4-C7).

**Length.** 475 to 969 words. The two longest (`connect`, `first`) carry nine of the seventeen wrong claims.

**Screenshots and media.** None. This is the section where "where do I click" is the whole question, and the authoring surface has no
way to add an image (`01-current-system.md` section 9, item 8). The worst gaps are the channel picker and the WhatsApp provider tiles.

**Front matter and SEO fields.** Titles are 10-26 characters (limit 60); `seo_description` is 76-124 characters in both languages, inside
the audit's 50-160 band, so `lynomia:docs:seo_audit` raises no warning for this section (`lib/tasks/documentation_seo_audit.rake:18-20,73-92`).
No `seo_title`, so the search-result title is the bare page title ("Set up your account"). `tags` repeat the section name and add nothing.

**Honesty about limits.** The strongest quality in the section. `set-up` refuses to pretend there is an account timezone, `invite`
warns that existing logins get no email, `first` warns about unassigned queues. Reading the code confirms these are real surprises; 48 of
68 claims hold, including the least obvious ones.

**Maintenance risks.** The three-languages table is duplicated (`welcome:51-58`, `set-up:38-46`). `connect` repeats the WhatsApp
procedure that `connect-whatsapp` owns and the two have already diverged (X6). Three articles hard-code UI paths ("Settings -> Agents")
that omit the sidebar group heading ("People", "Channels", "Account") the user will see; harmless today, brittle if the groups are renamed.
Link text drifts from target titles in both languages (for example "Connect WhatsApp" versus "Connect a WhatsApp number", "Commerce"
versus "What connecting a store gives you").

## 6. EN/AR parity

**Structural parity is exact.** Same headings (6, 10, 10, 9, 12), same tables, same 28 link occurrences, same worked examples. The
translation is faithful - which means every English error is also an Arabic error, and the items below are the *additional* Arabic
problems.

| ID | Issue | Evidence | Severity |
|---|---|---|---|
| P1 | **All 28 in-text links lead to English articles** (X1). An Arabic reader who follows "اربط أول قناة" from the welcome page lands on the English page. | X1 | major |
| P2 | **The Arabic quote of the invitation email describes mail nobody receives.** `ar/set-up:20-21` and `ar/invite:55-56` quote «تمت دعوتك للانضمام إلى <اسم عملك>». The email is English (S3, S4); only its subject is Arabic. The English article at least quotes a message that exists. | `confirmation_instructions.html.erb:9-47` | major |
| P3 | **Arabic labels the Arabic UI does not show.** `ar/set-up:41-43` names the profile option «استخدام لغة الحساب الافتراضية»; the Arabic UI shows the English "Use account default" (`ar/settings.json:60`). The window-closed placeholder the Arabic article tells the reader to expect is also English on screen (`ar/conversation.json:274`). | as cited | minor |
| P4 | **Two names for one role.** `ar/welcome:26,36,40,53` and `ar/connect:67-68` call the agent «الموظف» ("employee"); `ar/invite`, `ar/set-up` and `ar/first` use «وكيل الدعم», which is the Arabic UI's own word (`ar/agentMgmt.json:10`). Welcome's bold role name at `ar/welcome:40` does not match the role table two articles later. | `grep` of the five AR files | major (terminology) |
| P5 | **Channel versus inbox cannot be told apart in Arabic.** The UI calls Inboxes «قنوات التواصل» (`ar/settings.json:353`) and the article uses «القناة» for Channel; the English sentence "channel and inbox are the same thing from different sides" (`connect:8-10`) becomes "the channel appears under قنوات التواصل and has its own صندوق وارد" (`ar/connect:8-10`), which reads as two things. The AR link text for `set-up-an-inbox` is «تجهيز صندوق وارد» while the target is titled «إعداد قناة تواصل». | as cited | minor |
| P6 | **Numerals are mixed.** «نافذة الـ24 ساعة» (Western) in link text and `ar/welcome:23`, against «٢٤ ساعة» (Eastern) in prose at `ar/connect:38` and `ar/first:97`. A numeral policy is a decision for agent 061. | as cited | minor |
| P7 | **Bidirectional hazards, not rendered.** `ar/connect:54-57` joins Latin product names and Arabic around an em dash inside table cells ("WhatsApp Cloud - تجهيز سريع عبر Meta"); inline `UTC`, `Asia/Kuwait`, `Shift + Enter`, `/`, `@`, `L` sit in code spans inside right-to-left sentences. Arrow glyphs are correctly mirrored (`←` in AR paths, `→` in EN), which shows the author was thinking about direction. Needs a render check by agent 072. | as cited | unverified |

**What the Arabic gets right, verified against `app/javascript/dashboard/i18n/locale/ar/*.json`.** The article uses the exact strings the
Arabic dashboard shows: «محادثاتي / غير معيّن / الكل» (`ar/chatlist.json`), «فتح / معلق / مؤجلة / تم حلها», «إضافة رد / إضافة ملاحظة
خاصة» (`ar/conversation.json:282-283`), «حل المحادثة» (`:129`), «إضافة وكيل» (`ar/agentMgmt.json:4`), «قنوات التواصل»
(`ar/settings.json:353`), «الوسوم», «الردود الجاهزة», «ماكروس», «المتجر» for Commerce, and the priority labels «عاجل / عالية / متوسطة /
منخفضة» (`ar/conversation.json:204-212`). That terminology discipline - tying every UI reference to the shipped Arabic string - is
exactly what the rest of the Arabic corpus should be checked against, and is a quality bar for agent 061.

## 7. Not checked

Whether production runs billing enforcement; which entry path (signup or Super Admin) production accounts use; any rendered output (RTL,
links, the portal's language switcher); the `assignment_v2` behaviour; template language semantics; the Meta rules in `connect:48-49,90`;
the mobile app; the sidebar's own filtering of Settings for agents (only the route guard was checked).
