---
agent: 050
scope: `conversations` section of the corpus (6 articles x EN/AR) - classification, accuracy against the conversation/inbox/composer code, and what an all-day inbox agent cannot find
confidence: high
---

# 050 - Corpus: conversations

Read-only pass on branch `claude/documentation-v2`. Every code citation was read in this tree; nothing was run (no browser, no
Rails), so UI behaviour that I infer from source says so. Agents 029/030 own the feature audit - where I touch behaviour it is
only to check what an article asserts. `01-current-system.md` was used as a map and re-verified where I relied on it
(`content_seeder.rb:85-87` slug rule, `portal_helper.rb:77-83` article address, `featureHelper.js` wiring all held).

Method note for other corpus agents: word counts below are body words (front matter excluded) from a Python split. On this
machine `wc -w` undercounts Arabic about four-fold (it reports 180-272 for files whose real count is 736-936), so do not size the
AR corpus with it.

## 1. Inventory

Files are `custom/db/documentation/{en,ar}/conversations/<key>.md`. Manifest section: `conversations`, position 20, icon
`messages-square` (`custom/db/documentation/manifest.yml:17-25`). Six files per locale, exact parity. English slug = key, Arabic
slug = `<key>-ar` (`content_seeder.rb:85-87`).

| key | title EN / AR | pos | EN words | AR words | `DOC_ARTICLES` key -> where the product links to it |
|---|---|---|---|---|---|
| `work-in-the-inbox` | Work in the inbox / العمل في صندوق الوارد | 10 | 1033 | 936 | `conversations` - **wired nowhere** (`documentationLinks.js:19`) |
| `assign-and-prioritise` | Assign and prioritise / الإسناد والأولوية | 20 | 947 | 826 | `assignAndPrioritise` - **wired nowhere** (`documentationLinks.js:20`) |
| `labels` | Labels / الوسوم | 30 | 1036 | 903 | `labels` - Settings > Labels page header only (`labels/Index.vue:135`) |
| `canned-responses` | Canned responses / الردود الجاهزة | 40 | 916 | 736 | `cannedResponses` - Settings > Canned responses header only (`canned/Index.vue:155`) |
| `macros` | Macros / ماكروس | 50 | 1006 | 801 | `macros` - Settings > Macros header only (`macros/Index.vue:171`) |
| `macros-or-automation` | Macros or automation? / ماكروس أم أتمتة؟ | 60 | 1047 | 928 | `macrosOrAutomation` - **wired nowhere** (`documentationLinks.js:24`; admitted in `docs/product-refinement/11-notifications-and-navigation.md` section 3.3) |
| **total** | | | **5985** | **5130** | |

How the four wired links work: `BaseSettingsHeader.vue:46` -> `getHelpUrlForFeature` (`featureHelper.js:66-80`), which only
returns a documentation URL on a **branded** installation (`featureHelper.js:75-77`). The `automation` header resolves to
`automation-rules`, not to `macros-or-automation` (`featureHelper.js:10`). The inbox itself - conversation list, filter panel,
status dropdown, composer, side panel, bulk bar - carries **no** documentation link: the only callers of `DocsLink`/`docsLink`
are Commerce, Platform Support, `MessageError.vue` and the profile-menu "Documentation" item (grep across `app/javascript`).

## 2. Per-article verdict

| key | verdict | reason (one sentence) | evidence |
|---|---|---|---|
| `work-in-the-inbox` | **SPLIT**, then REWRITE the pieces | One 1,033-word landing page carries nine tasks (statuses, narrowing, folders, notes, mentions, permissions, bulk, block, troubleshooting) with no click paths, and it holds the section's worst errors (the Pending row, "Participating", custom-role narrowing, folder conditions). | W3, W12, W16, W24, W25, W28, W29 |
| `assign-and-prioritise` | **REWRITE** the auto-assignment half; keep the manual half | Manual assignment, team behaviour and "priority is a marker" are right, but "online" omits dashboard presence/Auto-offline (the commonest cause of "nothing is assigned") and the policy paragraph promises a "balanced" order and a "paid capability" this build can neither store nor sell. | A6, A11, A12 |
| `labels` | **KEEP** (two sentence fixes) | The strongest article: conversation-vs-contact labels, naming rules, permissions, rename/delete and bulk limits all check out; only the opening "nothing ever adds a label" and the sidebar unread-count claim need changing. | L1, L10 |
| `canned-responses` | **REWRITE** the Variables section | Picker, search, scope and permissions are right, but three statements about variables are contradicted by code (a pre-send warning exists; a misspelled variable renders empty, not literally; the composer does not always show the final text). | C8, C9, C10 |
| `macros` | **KEEP** (one fix, add visuals) | All 15 actions, visibility, per-agent order, silent failure, Self and Mute semantics confirmed; the "label that does not exist" troubleshooting claim is wrong, and the starter gallery and `#` picker are visual features with no image. | M17 |
| `macros-or-automation` | **EXPAND** (+3 corrections) | The "person vs event" distinction is right, but the trigger and action inventories are presented as complete and are not (WhatsApp-template action, cart-abandoned trigger, message-level delayed triggers) and one sentence about commerce rules is wrong. | MA4, MA6, MA7, MA10 |

Nothing proposed for MERGE, RETIRE or RELOCATE: I found no evidence for moving `macros-or-automation` into the automation
section (charter section 8 item 5 needs evidence), and `work-in-the-inbox` must keep its key because `DOC_ARTICLES.conversations`
and any bookmarked `/docs/work-in-the-inbox` depend on it (`01-current-system.md` section 10).

### Proposed split of `work-in-the-inbox`

The existing key stays as a short orientation page that links to the children; the children are new keys.

| new key | question it answers | takes from the current article |
|---|---|---|
| `conversation-statuses` | What do Open / Pending / Snoozed / Resolved do, and why did this one change by itself? | status table (corrected), snooze (all six options, 09:00 rule), auto-resolve, Mark as pending, bot-owned pending and Take over, required attributes on resolve |
| `find-your-conversations` | How do I find my queue, or the conversation about X? | Mine/Unassigned/All, status filter, the ten sort orders, sidebar views, the Filter builder, saving a folder, global search |
| `private-notes-and-mentions` | How do I leave a handover note or get a colleague's attention? | Private notes, @mentions, who can be mentioned, what silently fails |
| `change-many-conversations-at-once` | How do I resolve/assign/label a batch? | bulk limits, what is skipped, no priority in bulk |
| `block-a-contact` | How do I stop a sender, and undo it? | "Mute" paragraph - the UI calls it Block Contact (W29) |

## 3. Accuracy against the product

Verdicts: **confirmed** = code makes the sentence true as written; **wrong** = code contradicts it, or it omits something that
changes what the reader does; **unverifiable** = flag-, data- or runtime-dependent and not established here. Line numbers in the
claim column are the English article's. The Arabic text makes the same claims at the same positions (section 6).

### 3.1 `work-in-the-inbox`

| id | line | claim | verdict | evidence |
|---|---|---|---|---|
| W1 | 13 | A conversation has exactly one of four statuses | confirmed | `app/models/conversation.rb:86` |
| W2 | 18 | Pending = "a bot is handling it, or it is parked for one" | confirmed, incomplete | bot path: `conversation.rb:307-325`, `conversations/assignment_service.rb:37-47`. An agent can also set it by hand: "Mark as pending" (`ResolveAction.vue:247-258`). `your-first-conversation.md:30` defines Pending as "waiting on you, deliberately parked" - the two articles disagree and both are half the truth |
| W3 | 18 | Pending is reopened by "A human reply" | **wrong** | `message.rb:413-423`: the only code that opens on a human reply is gated on `captain_pending_conversation?`, which is hard-coded `false` (`:421-423`; no override anywhere in `app/`, `custom/`, `lib/`). `spec/models/message_spec.rb:274-280` asserts the conversation stays pending. What does reopen it: the Open button / status toggle, which also assigns the person (`conversations_controller.rb:82-93,180-186`); assigning a human to a bot-owned conversation (`conversations/assignment_service.rb:17-24`); a bot handoff (W4) |
| W4 | 18 | ...or "the bot handing it over" | confirmed | `conversation.rb:183-188`; `conversations_controller.rb:84-86,95-99` |
| W5 | 19 | Snoozed reopens at the set time or when the customer writes | confirmed | `app/jobs/conversations/reopen_snoozed_conversations_job.rb:5`; `message.rb:404-408`. Not for a blocked contact (`message.rb:405`) |
| W6 | 22-23 | Customer reply to a Resolved conversation -> Open; on a bot channel -> Pending | confirmed | `message.rb:425-435` |
| W7 | 25-27 | Snooze shapes: tomorrow, next week, a date, next reply | confirmed, incomplete | Six options: next reply, an hour from now, tomorrow, next week, next month, custom (`constants/globals.js:51-58`). Timed ones resolve to 09:00 browser time; "next week" and "next month" land on a **Monday** (`snoozeHelpers.js:24-31,47-53`). A typed natural-language parser also exists (`helper/snoozeDateParser/`, `i18n/locale/en/snooze.json`) - not traced. `your-first-conversation.md` lists the options correctly; this article under-lists |
| W8 | 26-27 | "Until next reply" stays snoozed indefinitely | confirmed | `action_service.rb:13-15` (`snoozed!`, no time), `conversation.rb:285-287` |
| W9 | 31-35 | Mine/Unassigned/All, Status, Sort are three independent controls | confirmed | `chatlist.json` `ASSIGNEE_TYPE_TABS`; `ConversationBasicFilter.vue:30-91` |
| W10 | 35 | Sort: last activity, created, priority, longest waiting, unread | confirmed, incomplete | Ten options (`ConversationBasicFilter.vue:55-91`). The "longest waiting" sorts are labelled **"Pending Response"** in the UI (`chatlist.json` `waiting_since_asc`), which collides with the Pending status |
| W11 | 41 | Mentions = conversations where your name was written in a private note | confirmed | `conversation_finder.rb:123-125`; `messages/mention_service.rb:17-18` |
| W12 | 42 | Participating = "conversations you have taken part in, even if you are not the assignee" | **wrong** (as worded) | Participation is a membership row created only by assignment (`listeners/participation_listener.rb:5-8`), an @mention (`mention_service.rb:69-73`) or the Participants panel (`conversations/participants_controller.rb:14,25`). Replying does not add you. A previous assignee stays a participant after reassignment. View: `conversation_finder.rb:126-128` |
| W13 | 43,46 | Unattended = never replied OR customer message unanswered; a private note does not count | confirmed | `conversation.rb:95`; `message.rb:225-228,340-343` |
| W14 | 44 | Teams / channels / labels have sidebar views | confirmed | `Sidebar.vue:477-538` |
| W15 | 48-55 | A conversation folder is saved filters, personal, cannot be shared | confirmed | `custom_filters_controller.rb:11-14,29-33`; overlay `custom/.../custom_filters_controller.rb:28-35` (`visible_to`) and `custom/app/models/custom/custom_filter.rb:7` (`shared_only_for_contacts`) |
| W16 | 51 | A folder "has its own unread count" in the sidebar | unverifiable | Badge is `0` unless `conversation_unread_counts` AND `unread_count_for_filters` are on (`Sidebar.vue:94-103,470-476`); both ship `enabled: false` and `chatwoot_internal: true` (`config/features.yml:28-31,237-240`), so a plan cannot grant them (`billing_plan.rb:41-47`). The code's own comment: "invisible on a default installation" (`custom/app/services/custom/conversations/unread_counts/counter.rb:23-24`). Same dependency in `labels.md:65` |
| W17 | 59-60 | A private note is never delivered to the customer on any channel | confirmed | `app/services/base/send_on_channel_service.rb:47-50`; `message.rb:211-212`. Instagram's Messenger send path not traced |
| W18 | 65-66 | Canned responses and variables are switched off in a note | confirmed (editor) | `Editor.vue:359-368`, `editorHelper.js:496-499`. The server still renders `{{ }}` in a note (`liquidable.rb:22-24` - notes are `outgoing`), so hand-typed braces in a note are evaluated |
| W19 | 70 | `@` offers a person or a team | confirmed | `TagAgents.vue:20-62` |
| W20 | 70-72 | Mention -> notification, Mentions view, becomes participant | confirmed | `mention_service.rb:10-12,51-73` |
| W21 | 74-75 | A mention works only in a private note; in a reply it notifies nobody | confirmed | `mention_service.rb:17-18`; `Editor.vue:270-272` |
| W22 | 77-78 | Only channel members or administrators; others silently ignored | confirmed | `mention_service.rb:40-48` |
| W23 | 71-72 | Mentioning a team notifies every member | confirmed, caveat | Team is expanded (`mention_service.rb:30-38`) and then cut by the same channel-member/admin rule (`:47-48`): a team member who is not on the channel is skipped silently |
| W24 | 93-94 | An agent can work any conversation on a channel they belong to, "or assigned to one of their teams" | **wrong** for browsing | The record policy opens by inbox OR team (`conversation_policy.rb:10-18,28-36`), but every list/filter/search goes through `PermissionFilterService`, which returns inbox-member conversations only (`permission_filter_service.rb:15-22`). The code names this asymmetry and leaves it (`custom/app/policies/custom/conversation_policy.rb:13-17`). A team-only agent can open such a conversation by link or notification but will not find it in the inbox |
| W25 | 94-95 | A custom role can narrow to "unassigned only" or "conversations the person is participating in" | **wrong** | `conversation_unassigned_manage` = unassigned **plus the holder's own**; `conversation_participating_manage` = **assigned to the holder** - `participant` rows are never consulted (`custom/app/services/conversations/capability_scope.rb:77-83,113-117`; browser mirror `store/modules/conversations/helpers.js:95-105`). The UI label says "participating" (`customRole.json:30`) so UI, doc and enforcement disagree. Same wording in `workspace/roles-and-permissions.md` ("their own, plus ones they are a participant in") |
| W26 | 100-101 | Bulk selection covers only the visible page | confirmed | `bulkActions.json` `ALL_CONVERSATIONS_SELECTED_ALERT` |
| W27 | 100-101 | Bulk reaches status, snooze, agent, team, labels - not priority | confirmed, incomplete | `bulk_actions_controller.rb:100-102,119`; bulk bar `conversationBulkActions/`. Omitted: bulk resolve **skips** conversations missing required attributes (`bulkActions.json` `RESOLVE.PARTIAL_SUCCESS`) |
| W28 | 102-104 | Folder conditions: status, assignee, priority, channel, team, contact, campaign, labels, browser language, referrer, dates, custom attributes | **wrong** (incomplete) | The live filter has two more: **message delivery status** (failed/sent/delivered/read) and **conversation ID** (`components-next/filter/provider.js:132-143,226`). The first is the only way to find a failed send and is the subject of `whatsapp-find-a-failed-message.md` |
| W29 | 105-106 | Muting resolves the conversation and blocks the contact | confirmed | `conversation_mute_helpers.rb:4-10`; new conversations from a blocked contact are born resolved (`conversation.rb:307-309`) and do not reopen (`message.rb:405`). **But the agent never sees the word "mute"**: the More-actions item is **"Block Contact" / "Unblock Contact"** (`MoreActions.vue:32-52`; `contact.json` `CONTACT_PANEL.MUTE_CONTACT`). "Mute" is only the macro/automation action name (`macros.json` `MUTE_CONVERSATION`). The article never says where it is or how to undo it |
| W30 | 121-122 | "Only send a template" = the WhatsApp 24-hour window, not permissions | confirmed (WhatsApp only) | `ReplyBox.vue:225-238`; `conversation.json` `MESSAGING_RESTRICTED_WHATSAPP`. Other channels have their own windows (Facebook/Instagram 24 h, TikTok 48 h, API inbox configurable - `MessagesView.vue:200-258`) and a **bot-owned Pending** conversation locks the composer to notes until "Take over" (`ReplyBox.vue:276-281`, `ReplyBoxBanner.vue:128-144`); the troubleshooting entry covers none of these |

### 3.2 `assign-and-prioritise`

| id | line | claim | verdict | evidence |
|---|---|---|---|---|
| A1 | 20-23 | Assigning a team clears an assignee who is not in it; then auto-picks if the team allows | confirmed | `models/concerns/assignment_handler.rb:6,12-29` (skipped when a bot owns the conversation, `:14`) |
| A2 | 25-26 | Only a channel member or administrator can be assigned; otherwise nothing is assigned | confirmed (UI, macros, automation) | picker lists assignable agents; `action_service.rb:104-109`. The raw assignments API does not enforce it (`conversations/assignment_service.rb:49-51` takes any account user) - irrelevant to an agent, noted for 029/030 |
| A3 | 30-31 | Auto-assignment switch per channel, set by an administrator | confirmed | `inbox.rb:15` (`enable_auto_assignment`, **default true**), `inbox_policy.rb:55-56`. The article does not say it is on by default |
| A4 | 36 | Oldest first | confirmed | `auto_assignment/assignment_service.rb:43-47` |
| A5 | 37 | Round robin | confirmed | `assignment_service.rb:75`; the only `assignment_order` value is `round_robin` (`assignment_policy.rb:38`) |
| A6 | 35, 116-118 | Only agents "set to online" are considered; checklist: "is at least one agent set to online" | **wrong** (incomplete in a misleading way) | "Online" is availability **and** live dashboard presence: presence expires after 20 s (`lib/online_status_tracker.rb:3,72-79`) unless the agent switched **Auto offline** off, and `auto_offline` defaults to **true** (`db/schema.rb:52`). `inbox_agent_availability.rb:4-12`. An agent set to "online" with the dashboard closed is never picked. Nothing in the corpus mentions Auto offline or where availability is set |
| A7 | 38-39 | At most five new conversations per agent per channel per five minutes | confirmed | `auto_assignment/rate_limiter.rb:20-26` (5 / 5 min when there is no policy) |
| A8 | 40-41 | Conversations idle for more than seven days are skipped | confirmed | `assignment_policy.rb:25` (168 h); `assignment_service.rb:52-66` |
| A9 | 42-43 | A team conversation considers only that team, and only if it allows auto-assignment | confirmed | `assignment_service.rb:78-85` |
| A10 | 94-96 | Without a policy, assignment fires on created/opened/resolved/snoozed; no sweep | confirmed | `auto_assignment_handler.rb:23-48`; the 30-minute sweep only visits inboxes **with** a policy (`periodic_assignment_job.rb:10`, `config/schedule.yml:58-61`). V2 is on by default (`features.yml:211-213`; `billing_plan.rb:12`) |
| A11 | 45-48 | "Assignment policies are a paid capability and the screen is hidden unless advanced assignment is enabled" | **wrong** (as a promise) | The **sidebar entry** is hidden without `advanced_assignment` (`Sidebar.vue:80-85,850`) but the pages need only `assignment_v2` (`assignmentPolicy.routes.js:25-60`), which is a default-on system flag. `advanced_assignment` is `premium: true` (`features.yml:272-275`) and `BillingPlan.assignable_features` rejects premium flags (`custom/app/models/billing_plan.rb:41-47`): **no Lynomia plan can sell it**. Whether a super admin can switch it on per account: unverifiable |
| A12 | 45-46, 97-98 | A policy can pick "balanced across current load"; balanced "falls back to round robin" without advanced assignment | **wrong** | The enum has one value, `round_robin` (`assignment_policy.rb:38`); the form merely disables the Balanced card without the premium flag (`AgentAssignmentPolicyForm.vue:132-151`). There is nothing to fall back from. Oldest-first/longest-waiting and the fair-distribution numbers do exist (`assignment_policy.rb:34,36`) |
| A13 | 54-60 | Priority is a marker: no queue effect, no extra notification, no clock; usable in sort, filter/folder, automation, macro | confirmed | assignment never reads priority (`assignment_service.rb:35-50`); SLA is premium and off (`features.yml:131-135`); a change only writes an activity line (`priority_activity_message_handler.rb:6-14`); filter `provider.js:145-158`; macro `change_priority` and automation `change_priority` exist. Five values incl. none: `conversation.rb:87` |
| A14 | 99 | Priority cannot be changed in bulk | confirmed | `bulk_actions_controller.rb:100-102` |
| A15 | 100-101 | Assigning a bot sets Pending and clears the human | confirmed | `conversations/assignment_service.rb:37-47` |
| A16 | 86-88 | Agents assign; only administrators switch on auto-assignment, create teams, create policies | confirmed | `inbox_policy.rb:55-56`, `team_policy.rb:14-16`, `assignment_policy_policy.rb:10-12` |

### 3.3 `canned-responses`

| id | line | claim | verdict | evidence |
|---|---|---|---|---|
| C1 | 32 | Settings > Canned responses > Add canned response | confirmed | `Sidebar.vue:969`, `cannedMgmt.json` `HEADER_BTN_TXT`; it sits under the Settings group "Conversation data" |
| C2 | 33-34 | Short code unique per account | confirmed | `canned_response.rb:20`. The form also requires at least 2 characters (`AddCanned.vue:42-45`) - not stated |
| C3 | 38-39 | `/` search matches code and body, code matches first | confirmed | picker: `CannedResponse.vue:88-94` (fuzzy `picoSearch`, short code weighted); the picker also shows a **preview** of the resolved text (`:129-134`) |
| C4 | 46-56 | The variable table and custom-attribute forms | confirmed | `shared/constants/messages.js:103-155` (13 variables); `@chatwoot/utils` `getMessageVariables` for `custom_attribute` keys |
| C5 | 60-61 | `{{agent.*}}` is the sender, not the assignee | confirmed | `ReplyBox.vue:465-477`, `liquidable.rb:15` (`sender || assignee`; automation messages have no sender so they fall back to the assignee) |
| C6 | 63-64 | Names are capitalised word by word | confirmed | `contact_drop.rb:2-4`; `editorHelper.js:470-483` |
| C7 | 66-67 | A variable with no value disappears; nothing warns | confirmed for a known-but-empty variable | `editorHelper.js:460-463` leaves the placeholder, `liquidable.rb:38` renders it empty |
| C8 | 69-70 | After insertion "what you see before pressing send is what the customer gets" | **wrong** for empty values | an empty variable stays visible as `{{contact.name}}` in the composer (`editorHelper.js:460-463`) and is blanked on the server at send (`liquidable.rb:26-44`) |
| C9 | 99 | "Nothing checks that your variables are spelled correctly" | **wrong** | `ReplyBox.vue:935-955` runs `getUndefinedVariablesInMessage` before send and opens a confirmation: "You have N undefined variables in your message: ... Would you like to send the message anyway?" (`conversation.json` `REPLYBOX.UNDEFINED_VARIABLES`) |
| C10 | 112-113 | "The customer received `{{contact.name}}` as literal text - the variable name is misspelled" | **wrong** | Liquid renders an unknown name as empty (`liquidable.rb:38`, no strict mode set - read from code, not executed). Braces survive only inside backtick code spans (`liquidable.rb:64-67`) or when Liquid fails to parse (`:42-44`) |
| C11 | 72-73 | Formatting the channel cannot carry is stripped on insertion | confirmed | `editorHelper.js:532-540` |
| C12 | 95, 110 | `/` is off inside a private note | confirmed | `Editor.vue:359-363` |
| C13 | 87-89, 93 | Any agent can create/edit/delete; account-wide only; plain text | confirmed | `canned_responses_controller.rb:1-45` (no authorization gate; params `short_code`, `content` only) |
| C14 | 17-20, 118-119 | Outside the WhatsApp window a canned response cannot be sent | confirmed | `ReplyBox.vue:225-238` |

### 3.4 `labels`

| id | line | claim | verdict | evidence |
|---|---|---|---|---|
| L1 | 8-9 | "Nothing in Lynomia Chat ever adds or removes one on its own" | **wrong** as phrased | Auto-resolve can add a conversation label (`conversations/resolution_job.rb:11`); the web-widget SDK can label a conversation from the visitor's page (`widget/labels_controller.rb:4`); automation/macros add conversation labels (the article itself says so at 26-27); contact merge moves labels (`custom/app/services/contacts/merge_relocation.rb:124-130`). True for **contact** labels apart from merge |
| L2 | 17-24 | Conversation and contact labels share a catalogue but are stored separately | confirmed | `Labelable` is included by both `conversation.rb:58` and `contact.rb:47` (`labelable.rb:5`) |
| L3 | 26-27 | Automation "add label" labels the conversation; nothing labels a contact | confirmed | `action_service.rb:37-41`; contact labelling is human-driven (`contacts/bulk_assign_labels_service.rb:14`) |
| L4 | 69-73 | Lower-cased; >=2 characters; starts with a letter/number; letters, numbers, hyphen, underscore; Arabic fine; unique | confirmed | `lib/regex_helper.rb:9`, `label.rb:25-28,33-35`, `labelsMgmt.json` `MINIMUM_LENGTH_ERROR` / `VALID_ERROR` |
| L5 | 75-78 | Settings > Labels > Add label; name, description, colour, sidebar toggle | confirmed | `labelsMgmt.json` `FORM`, `Sidebar.vue:957` |
| L6 | 95-99 | Administrators manage the catalogue; agents apply existing labels | confirmed | `label_policy.rb:2-20` |
| L7 | 66-67 | Rename updates every conversation and contact | confirmed (asynchronous) | `label.rb:30`, `labels/update_service.rb:6-19` |
| L8 | 109 | Delete removes it from everything; no undo | confirmed (asynchronous) | `labels_controller.rb` `destroy` -> `Labels::RemoveAssociationsJob` |
| L9 | 106-108 | Conversation bulk label = visible page; contact bulk up to 10,000, refuses above | confirmed | `bulkActions.json:20`; `bulk_actions_controller.rb:10-12` |
| L10 | 65 | Sidebar labels each have an unread count | unverifiable | same two default-off flags as W16 |
| L11 | 90-91 | Contacts > Tagged with > "Use in a new WhatsApp campaign" | confirmed | `settings.json:379`, `contact.json:320` |
| L12 | 104-105 | No automation trigger for contact create/change; no automation condition on a contact label | confirmed (negative, grep) | triggers `automation/constants.js:689-709` + `lynomiaAutomation.js:13-22`; the only `labels` condition is the conversation's |

### 3.5 `macros`

| id | line | claim | verdict | evidence |
|---|---|---|---|---|
| M1 | 29-37 | Fifteen actions in five groups | confirmed | `settings/macros/constants.js:1-80` (count 15) |
| M2 | 41-42 | "Assign an agent" offers Self = whoever presses | confirmed | `composables/useMacros.js:43` (hard-coded English `'Self'`), `macros/execution_service.rb:25-28` |
| M3 | 44-45 | Snooze in a macro sets no time | confirmed | `action_service.rb:13-15` |
| M4 | 49-50 | Settings > Macros > Add macro; a starter gallery exists | confirmed | `macros/Index.vue:16-39`; `macros.json` `HEADER_BTN_TXT` ("Add a new macro") |
| M5 | 53 | Actions run top to bottom and can be dragged | confirmed | `MacroNodes.vue:2,63`; `macros.json` `ORDER_INFO` |
| M6 | 57-58 | Run from the side panel or by `#` in the composer, with a preview | confirmed | `Editor.vue:375-379` (needs the Macros feature, `ReplyBox.vue:194-199`); `Macros/List.vue:81`, `MacroList.vue` preview slot |
| M7 | 77-84 | Permission matrix; an agent choosing Public gets Private, enforced on the server | confirmed | `macro_policy.rb:1-28`, `macro.rb:37-40` |
| M8 | 86-87 | Display order is per agent | confirmed | `composables/useOrderedMacros.js:5-37` (`macros_display_order` in UI settings) |
| M9 | 91-92 | No conditions, no branches | confirmed | `execution_service.rb:11-20` |
| M10 | 93-95 | No commerce action | confirmed | `macros/constants.js` has none |
| M11 | 95-97, 121 | A failed action is not reported; the rest still run; runs in background | confirmed | `execution_service.rb:15-18` (rescue -> exception tracker); `macros_controller.rb` `execute` -> `perform_later` |
| M12 | 98-100 | Sending ordinary WhatsApp text outside the window does not deliver; rest of the macro runs | unverifiable end to end | the message is created through `Messages::MessageBuilder` (`execution_service.rb:40-47`); the channel refusal path was not traced. The reader is not told the refused message appears **in the thread as a failed message** |
| M13 | 101-102 | Mute resolves and blocks the contact | confirmed | `conversation_mute_helpers.rb:4-10` |
| M14 | 103-105 | Dismissing the required-attributes prompt still runs the macro, leaves it unresolved | confirmed | `useMacroExecution.js:102-109`; `macros.json` `EXECUTE.EXECUTED_WITHOUT_RESOLVING` |
| M15 | 106-107 | Variables in macro text are filled "exactly as in a canned response" | confirmed | `liquidable.rb:12-44` applies to every outgoing message |
| M16 | 122-123 | A macro "did nothing" is most often an agent not on the channel | confirmed | `action_service.rb:104-109` |
| M17 | 122-123 | ...or "adding a label that does not exist in Settings" "could not complete" | **wrong** | `add_label` calls `add_labels`, which tags with any string (`labelable.rb:12-18`); the code's own comment: "`add_labels` would create one for any string" (`bulk_actions_controller.rb:90-93`). A deleted label referenced by a macro silently re-creates an uncatalogued tag that no sidebar or report lists |
| M18 | 54-55 | Private = only you; Public = whole account | confirmed | `macros.json` `EDITOR.VISIBILITY` |
| M19 | 36 | "send an email transcript" is a macro action | confirmed, caveat | silently does nothing when `email_transcript_enabled?` is false; it is hard-coded `true` here (`account_email_rate_limitable.rb:15-17`), so no practical effect |

### 3.6 `macros-or-automation`

| id | line | claim | verdict | evidence |
|---|---|---|---|---|
| MA1 | 20-29 | Side-by-side table (who starts, conditions, preview, who creates, on/off) | confirmed | `macro_policy.rb`, `automation_rule_policy.rb:2-20`, `automation_rule.rb:49` (`active`), `Macros/List.vue` preview |
| MA2 | 58-65 | Events: created, updated, opened, resolved, message created | confirmed | `settings/automation/constants.js:689-709`; `automation_rule.rb:55-57` |
| MA3 | 67 | Commerce rules act on the contact's most recent conversation | confirmed | `custom/app/services/automation/commerce_events.rb:8,60-62` |
| MA4 | 65 | Commerce events: created / updated / paid / shipped / delivered / cancelled / refunded (presented as the list) | **wrong** (incomplete) | an eighth trigger exists: `commerce_cart_abandoned` (`lynomiaAutomation.js:13-22`; `commerce_events.rb:12-14`) |
| MA5 | 43-50 | A rule can condition on text, country, language, channel, label, custom attribute, shared audience, store data | confirmed | `automation_rule.rb:59-62` (`conditions_attributes`), `lynomiaAutomation.js` groups |
| MA6 | 67-69 | Commerce events "deliberately offer no customer-facing message action" | **wrong** | only `send_message` and `send_attachment` are withheld; **`send_whatsapp_template` stays available** because a template is the one thing WhatsApp allows outside the window (`lynomiaAutomation.js:21-28`) |
| MA7 | 73-79 | "Automation only: email a team, reopen, mark pending. Macro only: Self. Everything else is in both" | **wrong** (incomplete) | automation also has `send_whatsapp_template` (`constants.js:789`), `add_sla` (`:809`; SLA is premium and off, `features.yml:131-135`) and a "last responding agent" assignee (`action_service.rb:46`) |
| MA8 | 101-102 | A rule's actions do not trigger other rules | confirmed | `automation_rule_listener.rb:40` (`performed_by_automation?`) |
| MA9 | 103-105 | Delayed automation must be enabled for the account and is off by default | confirmed | `features.yml:297-300` (`delayed_automations`, `enabled: false`); `automation_rule_listener.rb:72-80` |
| MA10 | 103-107 | A delayed rule means "still in this status N minutes later" and can wait only on status and channel | **wrong** (incomplete) | that is only the conversation-level form (`automation_rule.rb:28,131-136`). Message-level delayed triggers exist - "customer unresponsive" / "agent unresponsive" - without that restriction (`constants.js:823-835`, `automation_rule.rb:132`); delay range 10 min to 30 days (`automation_rule.rb:25,41`) |
| MA11 | 110 | Neither reports a failed action | confirmed | `automation_rules/action_service.rb:11-19` |
| MA12 | 122-127 | A macro never runs on its own; rule troubleshooting | confirmed | follows from MA1 |

### 3.7 Cross-article contradictions inside the corpus

| where | contradiction |
|---|---|
| `your-first-conversation.md:30` vs `work-in-the-inbox.md:18` | Pending = "waiting on you, deliberately parked" vs "a bot is handling it, or parked for one". The code has both (W2); neither article says so |
| `your-first-conversation.md` (snooze list) vs `work-in-the-inbox.md:25-27` | the first lists hour / tomorrow / next week / next month / custom / next reply (correct); the second under-lists |
| `workspace/roles-and-permissions.md` vs `capability_scope.rb:81` | "their own, plus ones they are a participant in" - same error as W25 (belongs to agent 057) |
| `workspace/teams-and-agents.md:44-58` vs `assign-and-prioritise.md:20-26` | the team-assignment rule is written twice, consistently (A1) - a drift risk, not a defect today |

### 3.8 Not checked / unverifiable

Nothing was run, so: the rendered output of any article in a browser (including relative-link resolution, section 6 finding 1); whether
Liquid really blanks an unknown name (read from `liquidable.rb` and Liquid's non-strict default, not executed); production state of
`conversation_unread_counts`, `unread_count_for_filters`, `delayed_automations` and `advanced_assignment` on real accounts (the
charter forbids touching them); whether a super admin can set a premium flag per account; the macro-sent WhatsApp message delivery
path (M12); the Instagram Messenger send path's private-note exclusion; the natural-language snooze parser's accepted phrases.

## 4. Missing articles

### 4.1 What the section must add, ranked by how often an inbox agent needs it

"Evidence" shows the code that proves the feature exists; none of these is covered anywhere in the 63-article corpus (grep of
`custom/db/documentation/en` for each topic returned nothing relevant, except where noted).

| # | proposed key | the question it answers | evidence the feature exists | note |
|---|---|---|---|---|
| 1 | `reply-composer` | How do I send an attachment, a voice note, an emoji, an email with CC/BCC, a reply to a specific message, a template? What do `/` `{{` `#` `@` `:` each open? | `ReplyBox.vue:1307-1500` (emoji picker, audio recorder, attachments, `ReplyEmailHead` CC/BCC, `ReplyToMessage`, signature, quoted email, WhatsApp/content template buttons); triggers `Editor.vue:346-386` (`:` emoji, 2 chars) | `/` `{{` `#` `@` are scattered across four articles; `:` and the rest are in none |
| 2 | `keyboard-shortcuts-and-command-bar` | How do I work faster without the mouse? | 14 shortcuts `components/widgets/modal/constants.js:10-95` (Alt+E resolve, Cmd+Alt+E resolve-and-next, Alt+M status menu, Alt+P note, Alt+L reply, Alt+J/K, Cmd+/ ...); extras not in that list: `L` label box (`LabelBox.vue:39`), Alt+C/V/R/S (`useSidebarKeyboardShortcuts.js`), the Cmd+K command bar (`useInboxHotKeys.js`) | `00-program` master map promised "shortcuts" for `work-in-the-inbox` (`docs/global-documentation/09-content-master-map.md` section 3); the article has none |
| 3 | `find-your-conversations` (see split) | How do I find the conversation about X, or every failed send from last week? | Filter builder `components-next/filter/provider.js:114-310` (14 attributes + custom attributes); save/edit folder strings `advancedFilters.json`; global search with Contacts / Conversations / Messages / Articles tabs `modules/search/components/SearchView.vue:22-45` | the article says "save it as a folder" but never says where the Filter control is or what to press |
| 4 | `start-a-conversation` | How do I message a customer first? | Compose button `Sidebar.vue:1134-1148`, `components-next/NewConversation/` ("To:" / "Via:", subject and CC for email, template picker for WhatsApp `WhatsAppOptions.vue`) | `automation-or-flow-builder.md:70` says "to start a conversation you need a campaign"; that is true of automation, and the corpus never says an agent can do it by hand |
| 5 | `conversation-statuses` (see split) | Why did this conversation resolve itself / why can't I reply / why did nobody get notified? | auto-resolve account setting `account_settings_schema.rb:11-13`, `resolution_job.rb:1-30`; bot-owned Pending and "Take over" (`ReplyBox.vue:276-281`, `ReplyBoxBanner.vue:128-144`, `conversation.json` `BOT_HANDOFF_*`); Mark as pending (`ResolveAction.vue:247-258`); **pending conversations raise no new-conversation or assigned-to-you notification** (`notification_listener.rb:4,18,40`); required attributes on resolve (Settings > Conversation Workflow, `settings.json` `CONVERSATION_WORKFLOW`, `ResolveAction.vue:120-136`) | `grep -i "auto.resolve\|required attribute"` over the EN corpus: no hits |
| 6 | `notifications` | Where do mentions and assignments show up? What decides whether I get an email? | top-level sidebar item **"My Inbox"** = the notification list (`Sidebar.vue:410-418`, `settings.json` `SIDEBAR.INBOX`); notification types and preferences `settings.json:124-176`; sources `notification_listener.rb`, `new_message_notification_service.rb:25-48` | also fixes a naming collision: the corpus uses "inbox" for the conversation list, the product's "My Inbox" is something else |
| 7 | `block-a-contact` | How do I stop a spammer, and undo it? | `MoreActions.vue:32-52`, `conversation_mute_helpers.rb:4-21` | covered only as a warning inside two articles, under the wrong name |
| 8 | `the-conversation-side-panel` | Where is the contact's history, notes, participants, files, order panel? | sections: actions, participants, conversation info, contact attributes, previous conversations, macros, Linear, Commerce, notes, shared files (`ContactPanel.vue:165-307`) | participants and notes are mentioned nowhere; Commerce/Linear are in other sections |
| 9 | `availability-and-auto-offline` | Where do I set online/busy/offline, and why am I not getting conversations? | `SidebarProfileMenuStatus.vue`; `online_status_tracker.rb:3,72-79`; `schema.rb:52`; `profiles_controller.rb:23-25` | decisive for A6; may belong in `workspace` (agent 057) but the assignment article needs it |
| 10 | `message-delivery-indicators` | What do the tick, clock and question mark mean; what do I do about each? | `docs/product-refinement/04-inbox-modernization.md` sections 2-3 (sent / delivered / read / in-progress / **unknown** / failed); `MessageError.vue` links failures to WhatsApp error articles | `whatsapp-find-a-failed-message.md` covers failures on WhatsApp only |
| 11 | `reply-windows-by-channel` | Why can't I reply on Instagram / Facebook / TikTok / API? | `MessagesView.vue:200-258`, `ReplyBox.vue:239-241` (Instagram restriction banner), `conversation.json` window strings | only the WhatsApp window has an article; cross-section with 053/058 |
| 12 | `send-a-transcript` | How do I email a conversation to someone? | `MoreActions.vue:47-52`, `conversations_controller.rb:72-80` | appears only as a macro action name |

### 4.2 Troubleshooting entries the section lacks

The three "If it does not work" entries in `work-in-the-inbox` cover filters, the WhatsApp window and a missing snoozed
conversation. Missing, each with a cause the code establishes: "a colleague can see a conversation I can't" (inbox membership
ceiling, `permission_filter_service.rb:15-22`; custom-role scope, `capability_scope.rb:77-83`; folders/filters stacked), "I get no
notification" (Pending suppresses them; availability; preferences), "it resolved by itself" (auto-resolve), "I can't type a reply"
beyond WhatsApp (bot-owned Pending; Instagram restriction; channel windows), "my message has a question mark".

### 4.3 What the product links to, and what it should (UI location | question | registry key | exists?)

| UI location | question there | key | in `DOC_ARTICLES`? |
|---|---|---|---|
| Conversation list header, Filter and status/sort panel (`ConversationBasicFilter.vue`, tooltip "Filter and sort conversations") | what do these filters do / how do I save one | `conversations` (or a new `findConversations`) | `conversations` yes, **unwired** |
| Status dropdown (`ResolveAction.vue:229-260`) | what is Pending / Snooze | `conversations` (or `conversationStatuses`) | yes / no |
| Bot "Take over" banner (`ReplyBoxBanner.vue:144`) | why can't I reply | new | no |
| Side panel > Conversation actions (assignee, team, priority) | what does assigning a team do | `assignAndPrioritise` | yes, **unwired** |
| Composer "Private note" tab / `@` menu | what does a note do, who is notified | `conversations` | yes, unwired |
| Settings > Automation header | macro or rule | `automation` -> `automation-rules`; `macrosOrAutomation` | the second is **unwired** |

The registry's own design rule is "a link belongs where someone is confused or blocked" (`docs/global-documentation/12-contextual-help.md`
section 3); all five rows above meet it and none is wired. Only the four Settings headers are, and only on branded installs.

## 5. Quality

**Structure.** The six articles share the corpus skeleton (when to use / when not / need first / steps / worked example / who can
/ limits / related / if it does not work). `work-in-the-inbox` and `assign-and-prioritise` drop "steps" and "need first" (the
design record calls them landing pages: `docs/global-documentation/15-content-quality-audit.md` section on "where a section is
deliberately absent"), which is why the daily-use article has no click path for the filter, snooze, folder or mention flows.
`labels`, `canned-responses` and `macros` are genuinely task-oriented and the best in the section.

**Depth per topic.** `work-in-the-inbox` spends 1,033 words on nine topics (about 110 each); the composer, shortcuts, search and
notifications - what an agent touches all day - get none.

**Screenshots.** Zero images in all twelve files (`grep -c '!\['` = 0), in a section whose subject is a dense UI (composer
triggers, status dropdown, filter panel, bulk bar, macro builder, starter gallery). `01-current-system.md` section 9.8 already
records that the corpus has no media story.

**Front matter and SEO.** All twelve parse; every file has `title`, `description`, `position`, `tags`, `seo_description`; none has
`seo_title`. Titles are 6-21 characters (EN) and 6-21 (AR), all under the audit's 60 (`documentation_seo_audit.rake`); `seo_description`
is 94-119 characters EN and 90-111 AR, all inside the 50-160 window. Audit-clean, but the two bare titles "Labels" and "Macros"
(6 characters) are poor search titles and identical to the Settings page names - useful for matching the UI, weak for "how do I
use macros". Tags: `[conversations]` plus cross-tags on `labels` (contacts) and `macros-or-automation` (automation).

**Links.** 54 internal links per locale, every target is a real EN key (script-checked against `custom/db/documentation/en/*/*.md`):
zero dangling. Cross-section: `shared-audiences`, `labels-or-shared-audiences`, `whatsapp-campaigns`, `contacts`, `automation-rules`,
`flow-builder`, `automation-or-flow-builder`, `commerce-overview`, `roles-and-permissions`, `teams-and-agents`, `whatsapp-templates`,
`the-whatsapp-24-hour-window`.

**Terminology versus the UI.** Three collisions an agent will hit: (1) "inbox" - the corpus's title word, the product's "My Inbox"
(notifications, `settings.json` `SIDEBAR.INBOX`) and Settings > "Inboxes" (channels) are three different things; (2) "Mute" in the
docs, "Block Contact" in the menu (W29); (3) the sort called "Pending Response" in the UI (W10). In Settings, the path
"Settings > Labels" omits the group level the sidebar shows ("Conversation data"; Macros sit under "Automation").

**Worked example fit.** The inbox example (Thursday, warehouse answers Sunday, back Monday) is a Sun-Thu working week mismatch
for the Kuwait audience the other examples target: "next week" snoozes to **Monday 09:00** (`snoozeHelpers.js:24-31`), so the
conversation wakes a day after the Sunday answer arrives. The article should say what "next week" means.

**Ordering.** Positions 10-60 are contiguous. Canned responses (40) and macros (50) are used more often than labels (30); order
follows concept rather than frequency. Not a defect.

## 6. EN/AR parity

**Structure** (headings, tables, bullets, numbered steps, links, code spans, numbers): identical in three of six files; the
other three differ only by one or two bold runs (`macros`, `macros-or-automation`, `work-in-the-inbox`) and, in
`work-in-the-inbox`, one extra paragraph. Every numeric token and code span matches except translated placeholders (script-checked).
**Every `wrong` in section 3 is present in both locales** - no case where AR is right and EN is wrong. The AR text also tracks the
**AR product strings** closely (statuses فتح / معلق / مؤجلة / تم حلها, tabs محادثاتي / غير معيّن / الكل, الإشارات / شارك / بدون حضور,
priority levels, عامة / خاص, الردود الجاهزة, ماكروس all match `app/javascript/dashboard/i18n/locale/ar/`).

**Meaning drift (AR text with no EN counterpart, or garbled):**

| AR location | EN counterpart | difference | severity |
|---|---|---|---|
| `ar/labels.md:65-66` | `labels.md:65` | adds "وعشرون منها ليست شريطاً جانبياً" ("and twenty of them are not a sidebar") - an invented figure and a clause that makes no sense | major (fabricated number) |
| `ar/macros-or-automation.md:27` | `macros-or-automation.md:28` | row label "تعمل وأحد لا يعمل" is garbled; EN is "Runs while nobody is working" (the answer column "no / yes" now has no readable question) | major |
| `ar/macros-or-automation.md:32-33` | `:33-34` | extra example "هل يبدو أن هذا العميل على وشك الرحيل؟ أقل من ذلك" not in EN | minor |
| `ar/macros-or-automation.md:42` | `:43-44` | adds "حلّ محادثة" (resolving a conversation) to the examples of a fact-trigger | minor |
| `ar/work-in-the-inbox.md:82` and `:88-89` | `:82`, `:88-89` | adds "بعد ظهر الخميس" (Thursday afternoon) and "فتراها يوم الجمعة" ("so you will see it on Friday") - invented, and Friday is a weekend day in Kuwait | minor |
| `ar/work-in-the-inbox.md:22` | (none) | extra lead-in sentence before the two bold paragraphs | cosmetic |
| `ar/labels.md:90-91` | `labels.md:90-91` | button left in English, "Use in a new WhatsApp campaign"; the AR UI string is "استخدمه في حملة واتساب جديدة" (`ar/contact.json:445`) | minor (reader cannot match the UI) |
| `ar/labels.md:82,89` | `labels.md:81-82,89` | "تعيين الوسوم"; the AR contacts bulk bar says "تعيين التسميات" (`ar/contact.json` `CONTACTS_BULK_ACTIONS.ASSIGN_LABELS`) and the conversation bulk bar says "إضافة وسم" - the AR product itself uses three words (وسم / تسمية) | minor |
| `ar/work-in-the-inbox.md:46` | `:44` | "قنوات التواصل"; the AR sidebar group is "القنوات" (`ar/settings.json` `SIDEBAR.CHANNELS`) | minor |
| Snooze button | n/a | AR UI shows "غفوة" on the status dropdown (`ar/conversation.json` `RESOLVE_DROPDOWN.SNOOZE_UNTIL`); docs say "تأجيل" | minor |

**Link behaviour (affects the whole AR corpus, not only this section).** All 54 Arabic internal links use English keys
(`(canned-responses)`). The renderer passes a relative URL through untouched (`markdown_renderer_url_sanitizer.rb:14-19`); an article is
served at `/hc/<portal>/articles/<slug>` with no locale segment (`portal_helper.rb:77-83`) and the Arabic article's slug is
`<key>-ar` (`content_seeder.rb:85-87`), so `canned-responses` from `/hc/lynomia-docs/articles/work-in-the-inbox-ar` resolves to the
**English** article (the show action looks up by slug alone, `articles_controller.rb:80-83`). Inferred from URL resolution, not
browser-tested. The `/docs/<key>` redirect already does reader-locale resolution (`library.rb:54-57`) but article-to-article links
do not use it.

**Rendering hazard, not checked:** `{{ }}` and `@name` inside Arabic sentences (`ar/canned-responses.md:76-78`, `ar/work-in-the-inbox.md:75`)
are bidi-sensitive (braces mirror inside an RTL run). Agent 061 owns RTL.
