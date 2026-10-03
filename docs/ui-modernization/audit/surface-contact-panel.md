# Surface audit — Contact panel inside a conversation

Read-only audit. Baseline for the feature-preservation contract of the visual/interaction modernization
phase. Every assertion below is anchored to `file:line` in the current tree.

Audit date: 2026-10-03. Repo root: `/home/user/lynomiachat`.

---

## 1. Routes and primary task

### 1.1 Where this surface renders

The panel component is `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue`. It is
mounted in exactly two places, both through the wrapper
`app/javascript/dashboard/components/widgets/conversation/ConversationSidebar.vue:63-67`:

| Host | Mount site | Gate |
|---|---|---|
| Conversation workspace | `routes/dashboard/conversation/ConversationView.vue:218-224` (`<Transition name="cw-sidebar-panel">`) | `shouldShowSidebar` = `currentChat.id` present AND `uiSettings.is_contact_sidebar_open` (`ConversationView.vue:84-92`) |
| Inbox (notifications) view | `routes/dashboard/inbox/InboxView.vue:217-220` | `isContactPanelOpen` = `currentChat.id` present AND `uiSettings.is_contact_sidebar_open` (`InboxView.vue:69-75`) |

### 1.2 Route list

All routes below render `ConversationView.vue`, so the panel is reachable on every one of them. Permissions
for all of them: `['administrator','agent','conversation_manage','conversation_unassigned_manage','conversation_participating_manage']`
(`conversation.routes.js:6-12`).

- `/app/accounts/:accountId/dashboard` — `home` (`conversation.routes.js:48-57`)
- `/app/accounts/:accountId/conversations/:conversation_id` — `inbox_conversation` (`:58-68`)
- `/app/accounts/:accountId/inbox/:inbox_id` — `inbox_dashboard` (`:69-79`)
- `/app/accounts/:accountId/inbox/:inbox_id/conversations/:conversation_id` — `conversation_through_inbox` (`:80-95`)
- `/app/accounts/:accountId/label/:label` — `label_conversations` (`:96-104`)
- `/app/accounts/:accountId/label/:label/conversations/:conversation_id` — `conversations_through_label` (`:105-118`)
- `/app/accounts/:accountId/team/:teamId` — `team_conversations` (`:119-127`)
- `/app/accounts/:accountId/team/:teamId/conversations/:conversationId` — `conversations_through_team` (`:128-141`)
- `/app/accounts/:accountId/custom_view/:id` — `folder_conversations` (`:142-151`, `beforeEnter` redirect guard `:23-29`)
- `/app/accounts/:accountId/custom_view/:id/conversations/:conversation_id` — `conversations_through_folders` (`:152-166`, guard `:31-43`)
- `/app/accounts/:accountId/mentions/conversations` — `conversation_mentions` (`:167-175`)
- `/app/accounts/:accountId/mentions/conversations/:conversationId` — `conversation_through_mentions` (`:176-189`)
- `/app/accounts/:accountId/unattended/conversations` — `conversation_unattended` (`:190-198`)
- `/app/accounts/:accountId/unattended/conversations/:conversationId` — `conversation_through_unattended` (`:199-212`)
- `/app/accounts/:accountId/participating/conversations` — `conversation_participating` (`:213-221`)
- `/app/accounts/:accountId/participating/conversations/:conversationId` — `conversation_through_participating` (`:222-235`)

Inbox-view routes (`routes/dashboard/inbox/routes.js`), permissions `[...ROLES, ...CONVERSATION_PERMISSIONS]`:

- `/app/accounts/:accountId/inbox-view` — `inbox_view` (`routes.js:16-22`, empty-state child, no panel)
- `/app/accounts/:accountId/inbox-view/:type/:id` — `inbox_view_conversation` (`routes.js:23-30`, panel renders here)

Note one route-name-sensitive behaviour inside the panel: `ViewAllConversations.vue:35` hides the
"View all conversations" control on any route whose name starts with `inbox_view`.

### 1.3 Primary task

Give the agent, without leaving the conversation thread, the full context on **who** they are talking to
and the ability to **act on the conversation**: read and inline-edit the contact identity (name, email,
phone, company), triage the conversation (assignee / team / priority / labels), bring in participants, run
macros, review prior conversations, notes, attachments and connected-system records (Linear, Shopify,
Lynomia Commerce), and reorder those sections to personal preference.

---

## 2. Feature parity manifest

This is the baseline. Every row must still exist, and must be no harder to discover, after any redesign.

### 2.1 Panel shell and sidebar lifecycle

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 1 | Contact sidebar open/close toggle (person icon, floating pill) | primary | `components-next/Conversation/SidepanelSwitch.vue:55-66`; rendered by `ConversationView.vue:215` and `InboxView.vue:209` | `currentChat.id` present |
| 2 | `Alt+O` toggles the contact sidebar | shortcut | `SidepanelSwitch.vue:43-48` | none |
| 3 | Copilot panel toggle (mutually exclusive with contact panel) | secondary | `SidepanelSwitch.vue:67-80` | `FEATURE_FLAGS.CAPTAIN` on account (`:17-19`) |
| 4 | Panel header title "Contact" | state | `ContactPanel.vue:150-153` + `SidebarActionsHeader.vue:26` | none |
| 5 | Panel header close (X) button | secondary | `SidebarActionsHeader.vue:37-43`, handler `ContactPanel.vue:132-137` (also clears `is_copilot_panel_open`) | none |
| 6 | Click-outside closes panel on small screens | mobile | `ConversationSidebar.vue:32-39, 44-53`; `isSmallScreen` = width < 768 (`:28-30`, `constants/globals.js:48`) | window < 768px |
| 7 | Panel slides over content as an overlay on mobile, docks as a column ≥ md | mobile | `ConversationSidebar.vue:54` (`fixed … w-full max-w-sm … md:static md:w-[320px] 2xl:w-[360px]`) | viewport |
| 8 | Panel enter/leave transition in conversation workspace | state | `ConversationView.vue:217` (`cw-sidebar-panel`) | none |
| 9 | Drag-to-reorder sidebar sections; order persisted to `ui_settings.conversation_sidebar_items_order` | primary | `ContactPanel.vue:156-165`, `onDragEnd` `:125-130`; handle `.drag-handle` on the accordion header `AccordionItem.vue:37` | none |
| 10 | Per-section expand/collapse persisted per user | primary | `ContactPanel.vue:173-176` etc.; `useUISettings.js:170-172` | none |
| 11 | Default section order (11 slots) | state | `useUISettings.js:5-17`: `conversation_actions`, `commerce`, `macros`, `conversation_info`, `contact_attributes`, `contact_notes`, `shared_files`, `previous_conversation`, `conversation_participants`, `linear_issues`, `shopify_orders` | none |
| 12 | New sections auto-appended to a stored custom order | state | `useUISettings.js:46-53` | none |
| 13 | On mount: fetch contact, fetch all attribute definitions, fetch `linear` integration | loading | `ContactPanel.vue:139-145` | none |
| 14 | Contact re-fetched when the conversation's sender changes | loading | `ContactPanel.vue:119-123` | `contactId` changed |

### 2.2 Contact identity header (`contact/ContactInfo.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 15 | Contact avatar, 48px, with availability-status dot | state | `ContactInfo.vue:197-204`; `hide-offline-status` set, so offline shows no dot (`components-next/avatar/Avatar.vue:31-48`) | `showAvatar` prop (default `true`) |
| 16 | Contact name, capitalized, click-to-edit | primary | `ContactInfo.vue:220-227`, `startEditingName` `:137-143` | `showAvatar` |
| 17 | Name pencil button, appears on row hover / keyboard focus | contextual | `ContactInfo.vue:228-241` | `showAvatar`, not already editing |
| 18 | Inline name editor: Enter saves, Escape cancels, blur saves | primary | `ContactInfo.vue:210-219`; `saveNameEdit` `:144-151`, `cancelNameEdit` `:152-154` | `isEditingName` |
| 19 | "Created <exact timestamp>" info icon with left tooltip | status | `ContactInfo.vue:244-252` | `contact.created_at` present |
| 20 | Open full contact profile in a new tab (external-link icon) | navigation | `ContactInfo.vue:253-260`; href built at `:66-68` → `/app/accounts/:accountId/contacts/:contactId` | none |
| 21 | Contact description / bio line | state | `ContactInfo.vue:264-266` | `additional_attributes.description` present |
| 22 | Email row — `mailto:` link, copy, inline edit | primary | `ContactInfo.vue:268-277` | always rendered (shows "Not Available" when empty) |
| 23 | Phone row — `tel:` link, copy, inline edit | primary | `ContactInfo.vue:278-287` | always rendered |
| 24 | WhatsApp username row (read-only, copy) | state | `ContactInfo.vue:288-295`; value from `social_profiles.whatsapp` or `social_whatsapp_user_name`, `@` re-prefixed (`:101-111`) | a WhatsApp username exists |
| 25 | Identifier row (read-only, no copy) | state | `ContactInfo.vue:296-302` | `contact.identifier` present |
| 26 | Company row — inline edit, writes into `additional_attributes.company_name` | primary | `ContactInfo.vue:303-318` | always rendered |
| 27 | Location row — "City, Country" + country flag (`fi fi-xx`) or 🌎 fallback, rendered via `v-dompurify-html` | state | `ContactInfo.vue:319-325`; `location` `:72-84`, `findCountryFlag` `:125-136` | `location` or `additional_attributes.location` |
| 28 | Social profile icon links (new tab, `noopener noreferrer nofollow`) | navigation | `contact/SocialIcons.vue:33-48`; supported keys facebook, twitter, linkedin, github, instagram, telegram, tiktok (`:11-19`) | at least one profile present (`:23-27`) |
| 29 | Twitter fallback from `screen_name`, Telegram fallback from `social_telegram_user_name` | state | `ContactInfo.vue:85-100` | legacy attribute present |
| 30 | Inline-edit success toast | state | `ContactInfo.vue:165` → `CONTACT_FORM.SUCCESS_MESSAGE` | after a successful field save |
| 31 | Duplicate-contact error handling on inline edit (per-field email / phone duplicate messages) | error | `ContactInfo.vue:167-187` | API returns `DuplicateContactException` |
| 32 | Contactable inboxes refetched after a contact edit and whenever `contact.id` changes | loading | `ContactInfo.vue:113-120, 166` | none |

### 2.3 Contact info row component (`contact/ContactInfoRow.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 33 | Icon-or-emoji leading glyph (respects `ui_settings.icon_type === 'emoji'`) | state | `ContactInfoRow.vue:84-89, 106-111, 144-149`; `shared/components/EmojiOrIcon.vue:14-23` | user setting |
| 34 | Copy-to-clipboard button + "Copied to clipboard successfully" toast | secondary | `ContactInfoRow.vue:122-130, 158-166`; `onCopy` `:52-56` | `showCopy` prop |
| 35 | Hover-revealed pencil to start inline edit | contextual | `ContactInfoRow.vue:131-139, 167-175` | `editable` prop |
| 36 | Inline edit: Enter saves, Escape cancels, blur saves; emits only on change | primary | `ContactInfoRow.vue:90-97`; `saveEdit` `:65-72` | `editable` |
| 37 | "Not Available" placeholder when the value is empty | empty | `ContactInfoRow.vue:119-121, 155-157` | value empty |
| 38 | Truncation with native `title` tooltip on the linked variant | state | `ContactInfoRow.vue:112-118` | `href` present |

### 2.4 Contact action bar (`contact/ContactInfo.vue:329-389`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 39 | New message — opens the compose popover pre-scoped to this contact | primary | `ContactInfo.vue:330-340`; `components-next/NewConversation/ComposeConversation.vue` | none |
| 40 | View all conversations — applies a `contact_id equal_to` conversation filter, sorted `created_at_desc` | contextual | `contact/ViewAllConversations.vue:48-82, 86-95` | visible only when the contact has >1 conversation neighbour AND the route is not `inbox_view*` (`:34-37`) |
| 41 | "View all" leaves folder scope / expanded-layout list before filtering, then restores the open conversation | contextual | `ViewAllConversations.vue:40-45, 50-63, 81` | folder view / expanded layout |
| 42 | "View all" failure toast `CHAT_LIST.FETCH_ERROR` | error | `ViewAllConversations.vue:80` | filter dispatch rejects |
| 43 | Voice call button | contextual | `ContactInfo.vue:342-351`; `components-next/Contacts/VoiceCallButton.vue:127-137` | `shouldRender`: at least one voice-enabled inbox AND (contact phone present OR the conversation's inbox is a WhatsApp voice inbox) — `VoiceCallButton.vue:49-69` |
| 44 | Voice inbox picker dialog when >1 voice inbox and the current inbox is not voice-capable | contextual | `VoiceCallButton.vue:139-152`, `onClick` `:181-196` | >1 voice inbox |
| 45 | Call button disabled while any call is active/ringing or an init is in flight | state | `VoiceCallButton.vue:78-83, 131` | call store state |
| 46 | Call loading spinner on the button | loading | `VoiceCallButton.vue:132` (`isInitiatingCall`, `:71-73`) | `contacts.uiFlags.isInitiatingCall` |
| 47 | Call toasts: initiated / failed / WhatsApp permission requested / permission already pending | state + error | `VoiceCallButton.vue:118-123, 137, 152-158, 169-178`; keys `CONTACT_PANEL.CALL_INITIATED`, `CALL_FAILED`, `WHATSAPP_CALL_PERMISSION_REQUESTED`, `WHATSAPP_CALL_PERMISSION_PENDING` | per outcome |
| 48 | Navigate to the call's conversation after placing a call | navigation | `VoiceCallButton.vue:85-96, 143, 174` | call succeeded |
| 49 | Edit contact (pencil) — opens the full edit drawer | primary | `ContactInfo.vue:352-359`, `toggleEditModal` `:122-124` | none |
| 50 | Merge contact — opens the merge popover with this contact as primary | destructive-ish | `ContactInfo.vue:360-371`; `modules/contact/ContactMergeModal.vue` | disabled while `uiFlags.isMerging` (`:368`) |
| 51 | Merge: search other contacts, error toast on search failure | contextual | `ContactMergeModal.vue:37-53` | none |
| 52 | Delete contact | destructive | `ContactInfo.vue:372-388`; `modules/contact/ContactDeleteModal.vue:59-...` | **admin only** (`v-if="isAdmin"`, `ContactInfo.vue:373`; `composables/useAdmin.js:11-12`) |
| 53 | Delete disabled while `uiFlags.isDeleting` | state | `ContactInfo.vue:385` | contacts store flag |
| 54 | Delete confirmation popover with contact name interpolated | destructive | `ContactDeleteModal.vue:34-36, 63-71` | none |
| 55 | After delete: success/error toast and route away to the conversation dashboard | state | `ContactDeleteModal.vue:40-55` | none |
| 56 | `panelClose` emitted after a delete | state | `ContactInfo.vue:46, 375` — **not handled by `ContactPanel.vue:154`** (see V-01) | n/a |

### 2.5 Edit contact drawer (`contact/EditContact.vue` + `contact/ContactForm.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 57 | Right-side fixed drawer, 30rem, slide-in/out transition, RTL-mirrored | state | `EditContact.vue:38-47` | `show` |
| 58 | Drawer title `Edit contact - <name or email>` + description | state | `EditContact.vue:48-58` | none |
| 59 | Drawer close (X) button | secondary | `EditContact.vue:59` | none |
| 60 | `Escape` closes the drawer (works while an input is focused) | shortcut | `EditContact.vue:27-34` | `show` |
| 61 | Avatar upload + delete | primary | `ContactForm.vue:308-321`; `handleImageUpload` `:278-281`, `handleAvatarDelete` `:282-298` | none |
| 62 | Avatar delete success/error toast | state + error | `ContactForm.vue:286, 292-297` | none |
| 63 | Name field, required validation | form | `ContactForm.vue:324-332`, validations `:74-77` | none |
| 64 | Email field with email-format validation + inline error | form | `ContactForm.vue:334-345` | none |
| 65 | Bio / description textarea | form | `ContactForm.vue:349-357` | none |
| 66 | Phone input with dial-code picker, validity check, inline error, and a persistent E.164 help banner | form | `ContactForm.vue:361-385`; `isPhoneNumberNotValid` `:90-98`, `phoneNumberError` `:99-107` | banner shows when invalid **or empty** (`:380`) |
| 67 | Company name field | form | `ContactForm.vue:387-392` | none |
| 68 | Country combobox (searchable, `Name (CODE)` labels) | form | `ContactForm.vue:393-410`, `countryNameWithCode` `:139-143` | none |
| 69 | City field | form | `ContactForm.vue:411-416` | none |
| 70 | Social profile inputs with URL prefix affixes: facebook, twitter, linkedin, github, telegram, whatsapp (`@`), tiktok | form | `ContactForm.vue:63-71, 418-436` | none — **`instagram` is read into state (`:194`) but has no input row** (see V-02) |
| 71 | WhatsApp username normalized (leading `@` stripped) on read and write | form | `ContactForm.vue:130-132, 196-198, 209-213` | none |
| 72 | Submit button with loading state; blocked when invalid | primary | `ContactForm.vue:438-442`, `handleSubmit` `:255-259` | `v$.$invalid` / phone invalid |
| 73 | Cancel / reset button | secondary | `ContactForm.vue:443-449` | none |
| 74 | Submit success toast, duplicate email/phone toasts, generic error toast | state + error | `ContactForm.vue:263-276` | per outcome |
| 75 | Contactable inboxes refetched after a drawer save | loading | `EditContact.vue:20-23` | none |

### 2.6 Accordion section chrome (`components/Accordion/AccordionItem.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 76 | Section header is a `<button>` that toggles the body | primary | `AccordionItem.vue:36-54` | none |
| 77 | Expand/collapse `+` / `−` affordance (fluent `add` / `subtract`, 24px, blue) | state | `AccordionItem.vue:49-52` | none |
| 78 | Same header is the drag handle (`.drag-handle`, `cursor-grab`) | primary | `AccordionItem.vue:37` | none |
| 79 | Optional icon/emoji slot in the header | state | `AccordionItem.vue:42` | `icon`/`emoji` prop — **never passed by `ContactPanel.vue`** |
| 80 | Optional `#button` slot in the header right rail | contextual | `AccordionItem.vue:48` | **never used by `ContactPanel.vue`** |
| 81 | `compact` body padding mode | state | `AccordionItem.vue:58` — used by every section except `conversation_actions` / `conversation_participants` | per section |
| 82 | Header corners square off when open | state | `AccordionItem.vue:38` | `isOpen` |
| 83 | Drag ghost styling (`ghost-class="ghost"`) | state | `ContactPanel.vue:159` — **no `.ghost` rule exists in `ContactPanel.vue`'s style block** (see V-03) | dragging |

### 2.7 Section: Conversation actions (`ConversationAction.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 84 | Accordion "Conversation Actions", key `is_conv_actions_open` | tab | `ContactPanel.vue:167-183` | none |
| 85 | Assigned Agent multiselect with search, includes AI assignees | primary | `ConversationAction.vue:251-263`; `useAgentsList(true, { includeAIAssignees: true })` `:28-30` | none |
| 86 | "Assign to me" quick action | primary | `ConversationAction.vue:240-248`, `onSelfAssign` `:176-198` | `showSelfAssign` — hidden when you are already the `User` assignee (`:162-173`) |
| 87 | Re-selecting the current agent unassigns | contextual | `ConversationAction.vue:199-209` | none |
| 88 | Assignee change toast `CONVERSATION.CHANGE_AGENT` | state | `ConversationAction.vue:109` | none |
| 89 | Assigned Team multiselect with search and emoji icons | primary | `ConversationAction.vue:266-283` | none |
| 90 | "None" team option injected when a team is assigned | contextual | `ConversationAction.vue:76-83` | `hasAnAssignedTeam` |
| 91 | Re-selecting the current team unassigns | contextual | `ConversationAction.vue:211-217` | none |
| 92 | Team change toast `CONVERSATION.CHANGE_TEAM` | state | `ConversationAction.vue:124` | none |
| 93 | Priority multiselect: None / Urgent / High / Medium / Low with per-level icons | primary | `ConversationAction.vue:36-64, 286-301` | none |
| 94 | Re-selecting the current priority resets to None | contextual | `ConversationAction.vue:219-227` | none |
| 95 | Priority change toast + analytics event (`from: 'Conversation Sidebar'`) | state | `ConversationAction.vue:146-158` | none |
| 96 | "Conversation Labels" sub-heading | state | `ConversationAction.vue:303-306` | none |
| 97 | Conversation label chips with remove (×) | primary | `labels/LabelBox.vue:93-103` | none |
| 98 | "Add label" trigger chip | primary | `labels/LabelBox.vue:92` (`shared/components/ui/dropdown/AddLabel.vue`) | none |
| 99 | Label search dropdown with create-new-label | primary | `labels/LabelBox.vue:105-120` | `allow-creation` bound to `isAdmin` (`:116`) — **admin-gated label creation** |
| 100 | `L` toggles the label dropdown | shortcut | `labels/LabelBox.vue:39-44` | only while this accordion is expanded (component mounted) |
| 101 | `Escape` closes the label dropdown (works in inputs) | shortcut | `labels/LabelBox.vue:45-52` | dropdown open |
| 102 | Click-away closes the label dropdown | contextual | `labels/LabelBox.vue:88` | none |
| 103 | Labels loading spinner | loading | `labels/LabelBox.vue:123` | `conversationLabels.uiFlags.isFetching` |

### 2.8 Section: Conversation participants (`ConversationParticipant.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 104 | Accordion "Conversation participants", key `is_conv_participants_open` | tab | `ContactPanel.vue:184-201` | none |
| 105 | Participant count line ("N people are participating.") | status | `ConversationParticipant.vue:162-165, 81-90` | ≥1 participant |
| 106 | "No one is participating!" empty state | empty | `ConversationParticipant.vue:166-168` | 0 participants |
| 107 | Inline fetching spinner next to the count | loading | `ConversationParticipant.vue:163` | `conversationWatchers.uiFlags.isFetching` |
| 108 | Avatar thumbnail group, max 4, "+N other(s)" overflow | status | `ConversationParticipant.vue:183-187`; `thumbnailList` `:61-63`, `moreThumbnailsText` `:68-77` | >4 participants for overflow |
| 109 | "Select participants" gear button opening the picker | primary | `ConversationParticipant.vue:170-179` | none |
| 110 | Participant picker: multiselect list with thumbnails, toggle on click | primary | `ConversationParticipant.vue:221-226`, `onClickItem` `:135-149` | none |
| 111 | Picker close (X) | secondary | `ConversationParticipant.vue:219` | none |
| 112 | Click-away closes the picker | contextual | `ConversationParticipant.vue:202-206` | none |
| 113 | "Join conversation" self-add | primary | `ConversationParticipant.vue:191-199`, `onSelfAssign` `:150-152` | hidden when already watching |
| 114 | "You are participating" badge | status | `ConversationParticipant.vue:188-190`, `isUserWatching` `:56-60` | you are a watcher |
| 115 | Participants update success / error toast | state + error | `ConversationParticipant.vue:109-128` | per outcome |
| 116 | Participants refetched on conversation change and after each update | loading | `ConversationParticipant.vue:92-99, 127` | none |

### 2.9 Section: Conversation information (`ConversationInfo.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 117 | Accordion "Conversation Information", key `is_conv_details_open`, compact | tab | `ContactPanel.vue:202-216` | none |
| 118 | Initiated at — re-rendered in the agent's timezone/locale, raw string fallback | state | `ConversationInfo.vue:27-35, 62-67` | `conversationAttributes.initiated_at.timestamp` |
| 119 | Browser language (resolved to a language name) | state | `ConversationInfo.vue:46-48, 68-72` | `browser_language` |
| 120 | Initiated from — referer rendered as an external link (`text-n-brand`, new tab) | navigation | `ConversationInfo.vue:73-78, 114-123` | `conversationAttributes.referer` |
| 121 | Browser name + version | state | `ConversationInfo.vue:39-44, 79-83` | `browser` object |
| 122 | Operating system name + version | state | `ConversationInfo.vue:50-55, 84-89` | `browser` object |
| 123 | IP address (from the **contact's** `created_at_ip`) | state | `ConversationInfo.vue:57, 90-95` | `contactAttributes.created_at_ip` |
| 124 | Empty rows auto-hidden | state | `ConversationInfo.vue:97` (`.filter(a => !!a.content.value)`) | none |
| 125 | Conversation custom attributes rendered in the same list, interleaved with the static rows | state | `ConversationInfo.vue:103-108` (`attribute-type="conversation_attribute"`, `attribute-from="conversation_panel"`) | attribute definitions exist |
| 126 | No empty-state message for this section | empty | `ConversationInfo.vue:103-108` — `empty-state-message` not passed, so `CustomAttributes.vue:308-313` renders nothing (see V-04) | n/a |

### 2.10 Section: Contact attributes (`customAttributes/CustomAttributes.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 127 | Accordion "Contact Attributes", key `is_contact_attributes_open`, compact | tab | `ContactPanel.vue:217-236` | none |
| 128 | Attribute rows (text / number / link / date / list / checkbox) | state | `CustomAttributes.vue:286-303`; `components/CustomAttribute.vue` | definitions for `contact_attribute` |
| 129 | Inline edit an attribute (pencil → input → ✓ confirm) | primary | `CustomAttribute.vue:244-266, 307-315` | `show-actions` (always set here, `CustomAttributes.vue:295`) |
| 130 | Copy an attribute value + toast | secondary | `CustomAttribute.vue:297-305`; `onCopy` `CustomAttributes.vue:244-247` | `showActions && hasValue` |
| 131 | Delete an attribute value + toast | destructive | `CustomAttribute.vue:233-240`; `onDelete` `CustomAttributes.vue:222-242` | `showActions && hasValue` |
| 132 | Per-attribute regex validation with a cue message | form | `CustomAttribute.vue:106-114, 267-272`; props `:296` in `CustomAttributes.vue` | attribute has `regex_pattern` |
| 133 | Attribute description tooltip | state | `CustomAttribute.vue:227-231` | description present |
| 134 | Update / delete success and error toasts | state + error | `CustomAttributes.vue:214-219, 236-241` | per outcome |
| 135 | "Show more / Show less" above 5 rows, persisted as `show_all_attributes_<from>` | secondary | `CustomAttributes.vue:123-130, 193-198, 314-325` | `combinedElements.length > 5` |
| 136 | Drag-to-reorder attribute rows — **only while expanded** | primary | `CustomAttributes.vue:261-281` (`:disabled="!showAllAttributes"`, `cursor-grab` conditional) | `showAllAttributes` |
| 137 | Row order persisted as `conversation_elements_order_<from>`, hidden static rows kept in place | state | `CustomAttributes.vue:92-94, 136-178` | none |
| 138 | Zebra striping of rows (light + dark variants) | state | `CustomAttributes.vue:253-256, 269` | none |
| 139 | "No attributes found" empty state | empty | `ContactPanel.vue:231-233` → `CONVERSATION_CUSTOM_ATTRIBUTES.NO_RECORDS_FOUND`; rendered at `CustomAttributes.vue:308-313` | no rows |
| 140 | Attribute drag ghost styling | state | `CustomAttributes.vue:329-333` | dragging |

### 2.11 Section: Previous conversations (`ContactConversations.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 141 | Accordion "Previous Conversations", key `is_previous_conv_open`, compact | tab | `ContactPanel.vue:237-258` | `contact.id` present (`:243`) AND NOT `isListScopedToContact` (`:239`) |
| 142 | Whole section hidden once the conversation list is already filtered to this contact in condensed layout | contextual | `ContactPanel.vue:105-111` (`isListScopedToContact` = not expanded layout AND `appliedContactFilter.id === contactId`) | layout + applied filter |
| 143 | Conversation cards (compact, no thumbnail), current conversation excluded | state | `ContactConversations.vue:111-124`; `previousConversations` `:39-41` | none |
| 144 | Active-chat highlight on a card | state | `ContactConversations.vue:118` | `currentChat.id === conversation.id` |
| 145 | Inbox name shown on cards when no inbox is selected and the account has >1 inbox | state | `ContactConversations.vue:26-30, 119` | computed |
| 146 | Click a card to open that conversation | navigation | `ContactConversations.vue:52-67, 122` | path resolvable |
| 147 | Cmd/Ctrl+click a card opens it in a new tab | shortcut | `ContactConversations.vue:56-64` | modifier held |
| 148 | Right-click context menu on a card, limited to "Open in new tab" and "Copy link" | contextual | `ContactConversations.vue:69-75, 126-143`; `:allowed-options="['open-new-tab','copy-link']"` `:140` | none |
| 149 | Context menu closes on outside interaction / contact change | contextual | `ContactConversations.vue:77-93, 130` | none |
| 150 | "There are no previous conversations associated to this contact." empty state | empty | `ContactConversations.vue:102-106` | no previous conversations |
| 151 | Centered loading spinner | loading | `ContactConversations.vue:145-147` | `contactConversations.uiFlags.isFetching` |
| 152 | Last card's bottom border/radius normalized | state | `ContactConversations.vue:109` | none |

### 2.12 Section: Macros (`Macros/List.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 153 | Accordion "Macros", key `is_macro_open`, compact | tab | `ContactPanel.vue:259-271` | `woot-feature-toggle feature-key="macros"` → `FEATURE_FLAGS.MACROS` (`'macros'`) on the account (`components/widgets/FeatureToggle.vue:15-17, 24`) |
| 154 | Macro rows with name, truncated | state | `Macros/MacroItem.vue:36-40` | none |
| 155 | Macro preview (info icon) popover, closes on click-away | secondary | `Macros/MacroItem.vue:42-49, 61-67` | none |
| 156 | Execute macro (play icon) with per-row loading + disabled state | primary | `Macros/MacroItem.vue:50-59`; `onExecuteMacro` `Macros/List.vue:41-49` | none |
| 157 | "Resolve attributes" modal when a macro needs missing custom attributes | contextual | `Macros/List.vue:44-47, 99-103` | macro has unresolved attributes |
| 158 | Drag-to-reorder macros | primary | `Macros/List.vue:79-98`; handle is the row itself unless its preview is open (`MacroItem.vue:34`) | none |
| 159 | "No macros found" empty state + "Add macro" link to `settings/macros` | empty | `Macros/List.vue:58-71` | `!isFetching && !macros.length` |
| 160 | "Loading macros" text + spinner | loading | `Macros/List.vue:72-78` | `macros.uiFlags.isFetching` |
| 161 | Macros fetched on section mount | loading | `Macros/List.vue:51-53` | none |

### 2.13 Section: Linear issues

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 162 | Accordion "Linked Linear Issues", key `is_linear_issues_open`, compact | tab | `ContactPanel.vue:272-290` | `FEATURE_FLAGS.LINEAR` (`'linear_integration'`) cloud feature AND the `linear` integration record exists (`ContactPanel.vue:62-77, 274-276`) |
| 163 | Setup CTA (logo, title, description, "Connect" button) when Linear is not connected | empty | `ContactPanel.vue:287`; `widgets/conversation/linear/LinearSetupCTA.vue:25-53` | `!isLinearConnected` |
| 164 | CTA copy and button differ for non-admins (agent description, no button) | empty | `LinearSetupCTA.vue:42-52` | **admin-gated action** |
| 165 | Light/dark integration logo variants | state | `LinearSetupCTA.vue:28-35` | theme |
| 166 | "Add or link issue" button | primary | `widgets/conversation/linear/IssuesList.vue:94` | Linear connected |
| 167 | Linked issue list, scrollable, max 300px | state | `IssuesList.vue:109` | issues exist |
| 168 | Unlink issue, with success/error toast | destructive | `IssuesList.vue:56-62` | none |
| 169 | Issues loading spinner | loading | `IssuesList.vue:99-101` | `isLoading` |
| 170 | "No linked issues" empty state | empty | `IssuesList.vue:103-106` | `!hasIssues` |

### 2.14 Section: Shopify orders

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 171 | Accordion "Shopify Orders", key `is_shopify_orders_open`, compact | tab | `ContactPanel.vue:291-306` | `integrations/getIntegration('shopify').enabled` (`ContactPanel.vue:51-58, 293`) |
| 172 | "No orders found" when the contact has no searchable email/phone | empty | `widgets/conversation/ShopifyOrdersList.vue:51-53` | `!hasSearchableInfo` |
| 173 | Orders loading spinner (brand-coloured, 32px) | loading | `ShopifyOrdersList.vue:54-56` | `loading` |
| 174 | Order fetch error message (ruby) | error | `ShopifyOrdersList.vue:57-59` | `error` |
| 175 | "No orders found" when the API returns none | empty | `ShopifyOrdersList.vue:60-62` | empty list |
| 176 | Order rows with `Order #<id>`, financial status and fulfillment status labels | state | `ShopifyOrdersList.vue:63+`; i18n `CONVERSATION_SIDEBAR.SHOPIFY.*` | orders exist |

### 2.15 Section: Commerce (Lynomia)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 177 | Accordion "Commerce" (`COMMERCE.TITLE`), key `is_commerce_open`, compact | tab | `ContactPanel.vue:307-319` | `FEATURE_FLAGS.LYNOMIA_COMMERCE` (`'lynomia_commerce'`) cloud feature (`:66-68, 307`) |
| 178 | Initial loading spinner | loading | `widgets/conversation/commerce/CommercePanel.vue:299-303` | `isLoading && !panel && !overview` |
| 179 | "No stores" empty state, with an extra admin-only line | empty | `CommercePanel.vue:306-311` | `!stores.length`; second line **admin only** (`:310`) |
| 180 | Overview / store tab switch | tab | `CommercePanel.vue:316-335` | `hasOverview` |
| 181 | Refresh button with cooldown notice | secondary | `CommercePanel.vue:343, 355-360, 193` | none |
| 182 | Store selector when >1 store | filter | `CommercePanel.vue:382-390` | `stores.length > 1` |
| 183 | Load error message (ruby) in both tabs | error | `CommercePanel.vue:363-365, 394-396` | `loadError` |
| 184 | "Update failed" banner with stale/last-updated detail | error | `CommercePanel.vue:400-408` | `panel.error` |
| 185 | Linked customer block with name, match-source note, Change / Unlink | primary + destructive | `CommercePanel.vue:411-437, 91, 104` | `panel.state === 'linked'` |
| 186 | "No orders" empty state inside a linked store | empty | `CommercePanel.vue:441-447` | `panel.orders` empty |
| 187 | "Link customer" flow: search box, search button, hint, error, "No results" | primary | `CommercePanel.vue:461-507` | `panel.state !== 'unavailable'` |
| 188 | Candidate list with Registered / Guest badge and per-row "Link" | primary | `CommercePanel.vue:509-542` | candidates present |
| 189 | Carts block | state | `CommercePanel.vue:557+` | `hasCarts` |

### 2.16 Section: Contact notes (`contact/ContactNotes.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 190 | Accordion "Contact Notes", key `is_contact_notes_open`, compact | tab | `ContactPanel.vue:320-331` | none |
| 191 | "Add note" ghost button | primary | `ContactNotes.vue:101-110` | disabled when no `contactId` or notes are loading (`:107`) |
| 192 | Add-note modal: rich-text editor, autofocus, placeholder | primary | `ContactNotes.vue:137-152` | none |
| 193 | Save note button with loading + disabled-when-empty | primary | `ContactNotes.vue:153-162` | `noteContent` non-empty |
| 194 | `Cmd/Ctrl+Enter` saves the note (works while the editor is focused) | shortcut | `ContactNotes.vue:78-85` | none (guarded by `onAdd` `:54-57`) |
| 195 | Modal does not close on backdrop click | state | `ContactNotes.vue:140` | none |
| 196 | Note list, scrollable, max 300px | state | `ContactNotes.vue:118-132` | notes exist |
| 197 | Per-note author line: "You" / agent name / "Bot" fallback | state | `ContactNotes.vue:33-38`; `ContactNoteItem.vue:69-82` | none |
| 198 | Per-note relative time with exact-timestamp tooltip | status | `ContactNoteItem.vue:72-80` | none |
| 199 | Per-note delete, revealed on row hover | destructive | `ContactNoteItem.vue:84-92`; `onDelete` `ContactNotes.vue:67-76` | `allow-delete` (set, `ContactNotes.vue:129`) |
| 200 | Long notes clamped to 4 lines with Expand / Collapse | secondary | `ContactNoteItem.vue:44-51, 94-117` | `collapsible` (set, `ContactNotes.vue:130`) and content taller than ~84px |
| 201 | Notes loading spinner | loading | `ContactNotes.vue:112-117` | `contactNotes.uiFlags.isFetching` |
| 202 | Notes empty state (`CONTACTS_LAYOUT.SIDEBAR.NOTES.CONVERSATION_EMPTY_STATE`) | empty | `ContactNotes.vue:133-135` | no notes |
| 203 | Notes refetched and the modal force-closed when the contact changes | loading | `ContactNotes.vue:87-96` | contact changed |

### 2.17 Section: Attachments / shared files (`SharedFiles.vue`)

| # | Feature | Kind | Where it lives today | Gate |
|---|---|---|---|---|
| 204 | Accordion "Attachments", key `is_shared_files_open`, compact | tab | `ContactPanel.vue:332-343` | none |
| 205 | Loading spinner until attachments are loaded | loading | `SharedFiles.vue:51-53` | `!getSelectedChatAttachmentsLoaded` |
| 206 | "No attachments yet" empty state | empty | `SharedFiles.vue:54-56` | no non-`NON_FILE_TYPES` attachment with a `data_url` (`:28-32`) |
| 207 | Media grid, newest first, peek limit 6 | state | `SharedFiles.vue:15, 22-26, 58-62`; `components-next/SharedAttachments/Media.vue:44-54` | media exist |
| 208 | Media "View all" / "Show less" toggle and a `+N` overflow tile | secondary | `Media.vue:169-181, 297-304` | overflow > 0 |
| 209 | Media tile previews: image, video with play badge, audio inline player, type-fallback icon | state | `Media.vue:194-246` | per file type |
| 210 | Media tile timestamp overlay | status | `Media.vue:257` | `displayTime` |
| 211 | Per-tile download button (with `aria-label`) | secondary | `Media.vue:268-277` | none |
| 212 | Download failure toast | error | `Media.vue:146-149`; `Files.vue:77-80` | download throws |
| 213 | Click a media tile to open the full-screen gallery (autoplay), scoped to media only | primary | `SharedFiles.vue:37-40, 69-76` | tile clicked |
| 214 | Files list, peek limit 3, "View all" / "Show less" | state + secondary | `SharedFiles.vue:16, 63-67`; `Files.vue:100-112` | files exist |
| 215 | File rows with name (`Untitled file` fallback), timestamp, download | state | `Files.vue:52-58, 121-180` | none |
| 216 | Click a file row to open it in a new tab | navigation | `SharedFiles.vue:42-46` | `data_url` present |
| 217 | "Jump to message" per attachment | contextual | `Media.vue:280-292`; `Files.vue:154-167` | `show-jump-to-message` prop — **NOT passed by `SharedFiles.vue:58-67`, so this is unavailable in the contact panel today** (it is available in the contacts sidebar, `components-next/Contacts/ContactsSidebar/ContactMedia.vue`) |

### 2.18 Cross-module contextual links out of this surface

| # | Link | Target | Where |
|---|---|---|---|
| 218 | Contact profile | `/app/accounts/:accountId/contacts/:id` (new tab) | `ContactInfo.vue:66-68, 253-260` |
| 219 | Conversation list filtered to this contact | current conversation list + applied filter | `ViewAllConversations.vue:65-82` |
| 220 | A previous conversation | `buildConversationPath(id)` (same tab, new tab, or copied link) | `ContactConversations.vue:52-67, 126-143` |
| 221 | Macro settings | `settings/macros` | `Macros/List.vue:62` |
| 222 | Linear integration settings | `accounts/:id/settings/integrations/linear` (new tab) | `LinearSetupCTA.vue:14-22` |
| 223 | Social profiles | facebook / twitter / linkedin / github / instagram / telegram / tiktok (new tab) | `SocialIcons.vue:11-19, 35-47` |
| 224 | Referer URL of the conversation | external site (new tab) | `ConversationInfo.vue:114-123` |
| 225 | A call's conversation | `conversationUrl(...)` | `VoiceCallButton.vue:85-96` |

### 2.19 Permission / flag summary

| Gate | What it controls |
|---|---|
| `isAdmin` (`useAdmin.js:11-12`) | Delete contact button (#52); label creation in the label dropdown (#99); Linear CTA description + Connect button (#164); Commerce "no stores" admin line (#179) |
| `FEATURE_FLAGS.MACROS` = `macros` | Macros section (#153) |
| `FEATURE_FLAGS.LINEAR` = `linear_integration` + integration record present | Linear section (#162) |
| `FEATURE_FLAGS.LYNOMIA_COMMERCE` = `lynomia_commerce` | Commerce section (#177) |
| `FEATURE_FLAGS.CAPTAIN` | Copilot toggle sharing the switch with this panel (#3) |
| `integrations/getIntegration('shopify').enabled` | Shopify section (#171) |
| Voice-enabled inbox present | Call button and inbox picker (#43, #44) |
| Route-name check `inbox_view*` | "View all conversations" hidden (#40) |
| `appliedContactFilter` + condensed layout | Previous conversations section hidden (#142) |
| Route `meta.permissions` | Reaching the surface at all (§1.2) |

**Feature count: 225.**

---

## 3. Visual audit

### V-01 — `panelClose` from `ContactInfo` is never handled (high, consistency)

`ContactInfo.vue:46` declares `emits: ['panelClose']` and `ContactInfo.vue:375` fires it after a successful
delete, but the only mount point, `ContactPanel.vue:154`, is
`<ContactInfo :contact="contact" :channel-type="channelType" />` — no `@panel-close` listener. After deleting
a contact the panel stays open showing a now-deleted contact until `ContactDeleteModal.vue:46-52` happens to
route away. Dead contract that a redesign will likely copy forward.

### V-02 — Instagram is displayable but not editable (medium, consistency)

`SocialIcons.vue:16` renders an Instagram link, and `ContactForm.vue:194` reads
`socialProfiles.instagram` into form state — but `socialProfileKeys` (`ContactForm.vue:63-71`) has no
`instagram` entry, so the edit drawer never shows an Instagram input. Agents can see the icon and never set
it. The same list also diverges in order and membership from `SocialIcons.vue:11-19` (form has no instagram;
icons have no whatsapp), so the two lists must be reconciled, not just restyled.

### V-03 — `.ghost` drag class declared but undefined for the section list (medium, consistency)

`ContactPanel.vue:159` passes `ghost-class="ghost"` to the top-level `Draggable`, but the component's only
style rule is `:deep(.contact--profile)` (`ContactPanel.vue:350-354`). `Macros/List.vue:107-111` and
`CustomAttributes.vue:329-333` each define their own `.ghost`. Result: reordering sidebar sections has **no**
drop-placeholder feedback, while reordering macros and attributes does.

### V-04 — Dead `:deep(.contact--profile)` rule / missing section divider (medium, spacing)

`ContactPanel.vue:350-354` styles `.contact--profile` with `pb-3 border-b border-n-weak`, but no element in
the tree carries that class (verified across `app/javascript`). `ContactInfo.vue:194` renders
`class="relative items-center w-full p-4"`. So the intended divider between the contact header and the
section stack does not render; the header's `p-4` runs straight into the `px-2` section list
(`ContactPanel.vue:155`), giving an unaligned, undivided seam.

### V-05 — Horizontal alignment is inconsistent across the panel (high, alignment)

Four different left insets stack vertically:
- header `px-4 py-2` (`SidebarActionsHeader.vue:23`)
- contact block `p-4` (`ContactInfo.vue:194`)
- info rows pulled back by a negative margin `ltr:-ml-1 rtl:-mr-1` (`ContactInfoRow.vue:81`) and then pushed
  in again with `ltr:ml-1 rtl:mr-1` on the icon (`:88, :110, :148`)
- section list `px-2` (`ContactPanel.vue:155`), accordion header `px-4` (`AccordionItem.vue:37`), accordion
  body `px-2 py-4` or `p-0` when `compact` (`AccordionItem.vue:58`), and then each section's own padding —
  `px-4 pt-3 pb-2` (`ContactNotes.vue:101`), `p-2` (`SharedFiles.vue:50`), `p-3` (`LinearSetupCTA.vue:26`),
  `p-1` (`Macros/List.vue:82`), `py-3 px-4` (`ContactDetailsItem.vue:12`).

No single text baseline runs down the panel.

### V-06 — Contact info rows are height-clamped and will clip (high, density)

`ContactInfoRow.vue:81` sets `h-5` (20px) on the row while the inner content is a flex row containing an
`h-6` input in edit mode (`InlineInput.vue:121`) and `xs` buttons that are `h-6 w-6`
(`Button.vue:165`). A 24px control inside a 20px row overflows by 4px on every editable row, and
`whitespace-nowrap text-ellipsis` (`ContactInfoRow.vue:114, 153`) means long emails lose characters rather
than wrapping. In the 320px panel (`ConversationSidebar.vue:54`) the row is icon + value + copy + pencil,
leaving roughly 200px for the value.

### V-07 — Accordion header is a button, a drag handle, and has no expanded semantics (high, a11y)

`AccordionItem.vue:36-54`: a single `<button>` carries `cursor-grab` and the `.drag-handle` class and is the
only way to expand the section. There is no `aria-expanded`, no `aria-controls`, and no `type="button"`
(inside a form this would submit). Keyboard users cannot reorder sections at all — the only reorder affordance
is a pointer drag (`ContactPanel.vue:156-165`). The expand affordance itself is a nested `div` with
`cursor-pointer` (`AccordionItem.vue:49`) inside the button, which both duplicates the hit target and lies
about the cursor.

### V-08 — Nested `.drag-handle` selectors collide across three Draggables (high, consistency)

`ContactPanel.vue:160` (`handle=".drag-handle"`), `Macros/List.vue:86` (`handle=".drag-handle"`, applied to
the whole macro row, `MacroItem.vue:34`), and `CustomAttributes.vue:265` (`handle=".drag-handle"`, applied to
every attribute row, `:275`) all use the same selector, and the inner lists are rendered inside the outer
list's items. Dragging a macro row or an attribute row can satisfy the outer list's handle test as well.

### V-09 — Icon-only buttons have no accessible name (high, a11y)

`components-next/button/Button.vue` never derives an `aria-label` from the tooltip (`:49-59` only filters
attrs; `EXCLUDED_ATTRS` in `./constants.js`). Across this surface only `ViewAllConversations.vue:89` sets
`aria-label`. Unnamed icon-only controls therefore include: panel close (`SidebarActionsHeader.vue:37-43`),
New message (`ContactInfo.vue:333-338`), Call (`ContactInfo.vue:342-351`), Edit contact
(`ContactInfo.vue:352-359`), Merge (`ContactInfo.vue:361-369`), Delete (`ContactInfo.vue:378-386`), the name
pencil (`ContactInfo.vue:228-241`), every row copy/pencil (`ContactInfoRow.vue:122-139, 158-175`), macro
preview and execute (`MacroItem.vue:42-59`), and the participant picker close
(`ConversationParticipant.vue:219`). `v-tooltip` is not an accessible name.

### V-10 — "Open contact profile" has no label at all (medium, a11y)

`ContactInfo.vue:253-260` is a bare `<a>` wrapping a decorative `<span class="i-lucide-external-link">`. No
text, no `title`, no `aria-label`. The string `CONTACT_PANEL.VIEW_PROFILE` ("View Profile") exists in
`i18n/locale/en/contact.json` and is unused here. Screen readers announce an empty link; sighted users get no
tooltip either (unlike the adjacent `v-tooltip.left` info icon, `:246-251`).

### V-11 — Seven equally-weighted icon buttons form a flat action row (high, cta-clarity / hierarchy)

`ContactInfo.vue:329-389` renders New message, View all, Call, Edit, Merge, Delete as same-size `sm` `faded`
`slate` icon buttons; only Delete differs, by colour (`ruby`, `:384`). Nothing marks the primary action, the
icons are mixed sets (`i-ph-chat-circle-dots`, `i-lucide-history`, `i-lucide-phone`, `i-ph-pencil-simple`,
`i-ph-arrows-merge`, `i-ph-trash`), and a destructive action sits in the same undifferentiated row as "New
message". Conditional members (#40, #43, #52) mean the row's length and the position of every button change
between contexts, so muscle memory lands on the wrong control.

### V-12 — Two different edit affordances for the same data (high, consistency)

The same fields are editable in two places with different interaction models and different validation: inline
on the row (`ContactInfoRow.vue:90-97` — no validation at all; email saved raw via
`ContactInfo.vue:276`) and in the drawer (`ContactForm.vue:334-345` — Vuelidate `email` rule, phone validity,
required name). Inline edit of `company_name` spreads `additionalAttributes` by hand
(`ContactInfo.vue:309-317`) while the drawer rebuilds the whole `additional_attributes` object
(`ContactForm.vue:219-231`). Two write paths to one record, with the shallower one unvalidated.

### V-13 — Mixed icon sets and sizes throughout (medium, consistency)

In one panel: Phosphor (`i-ph-chat-circle-dots`, `i-ph-pencil-simple`, `i-ph-arrows-merge`, `i-ph-trash` —
`ContactInfo.vue:334, 354, 364, 380`), Lucide (`i-lucide-pencil`, `i-lucide-clipboard`, `i-lucide-phone`,
`i-lucide-history`, `i-lucide-x`, `i-lucide-settings`, `i-lucide-arrow-right`), legacy `fluent-icon`
(`AccordionItem.vue:50-51` at `size="24"`, `SocialIcons.vue:42-46` at `size="16"`), and the
explicitly deprecated `EmojiOrIcon` ("🚨 This component is deprecated", `shared/components/EmojiOrIcon.vue:2`)
at `icon-size="14"` (`ContactInfoRow.vue:87`). Four icon systems, five sizes.

### V-14 — Accordion open/close icons are 24px blue in a 14px-text panel (medium, hierarchy)

`AccordionItem.vue:49-52` renders `add`/`subtract` at `size="24"` in `text-n-blue-11` inside a 3-unit-wide
box (`w-3` = 12px). The glyph is twice the section title's type size (`text-sm`, `:43`) and the only blue
element in an otherwise slate panel, so the chrome outweighs the content it labels. The `w-3` container is
also narrower than the 24px icon.

### V-15 — Every section is collapsed on first use (high, empty-state / hierarchy)

`AccordionItem.vue:21-24` defaults `isOpen: true`, but `ContactPanel.vue` always passes
`isContactSidebarItemOpen(key)`, which is `!!uiSettings.value[key]` (`useUISettings.js:170`). No default seeds
these keys (no `is_conv_actions_open` / `is_contact_notes_open` / … default exists in
`store/modules/auth.js` or in the Rails `users.ui_settings` column, `app/models/user.rb:32`). A new agent
therefore sees the contact header followed by up to eleven identical collapsed grey bars with no content and
no indication which hold data.

### V-16 — Accordion `toggle` contract is broken on both ends (medium, consistency)

`AccordionItem.vue:29-31` emits `toggle` with **no payload**. Every call site passes a handler expecting one:
`value => toggleSidebarUIState('is_conv_actions_open', value)` (`ContactPanel.vue:174-176`, and the same
shape at `:191-194, :207-209, :222-225, :249-251, :267, :283-285, :300-302, :312, :325-327, :336-339`).
`useUISettings.js:171-172` then drops the second argument entirely and inverts the stored flag. Three layers,
two dead parameters. It happens to work only because toggle == invert.

### V-17 — Dead props passed into `ContactInfo` (low, consistency)

`ContactPanel.vue:154` passes `:channel-type="channelType"` (computed at `:96`), but `ContactInfo.vue:36-45`
declares only `contact` and `showAvatar`. With no `inheritAttrs: false`, the value lands as a raw
`channel-type` attribute on `ContactInfo.vue:194`'s root `div`. The panel also never passes `showAvatar`,
whose `false` branch silently removes the name, the created-at tooltip and the profile link
(`ContactInfo.vue:198, 208`) — an untested configuration.

### V-18 — The attribute reorder affordance is hidden behind "Show more" (medium, navigation)

`CustomAttributes.vue:265` sets `:disabled="!showAllAttributes"` and `:277` only applies `cursor-grab` when
expanded, while the `.drag-handle` class is unconditional (`:275`). With ≤5 attributes there is no "Show
more" button at all (`:315`), so reordering is permanently unreachable for small attribute sets. There is no
visible hint that expanding unlocks dragging.

### V-19 — Three unlabeled scroll regions nest inside the panel's own scroll (medium, density)

The panel column scrolls (`ConversationSidebar.vue:62`, `flex flex-1 overflow-auto`). Inside it,
`ContactNotes.vue:120` (`max-h-[300px] overflow-y-auto`), `IssuesList.vue:109`
(`max-h-[300px] overflow-y-auto`) and `ContactDetailsItem.vue:12` (`overflow-auto`) each create their own
scroller, none with a visible boundary or shadow. Scroll chaining in a 320px column is unpredictable, and
content below a 300px cut has no affordance indicating more exists.

### V-20 — Popovers and dropdowns use hard-coded `z-[9999]` (medium, consistency)

`ConversationParticipant.vue:211` and `labels/LabelBox.vue:110` both set `z-[9999]`, while the panel sits at
`z-40` (`ConversationSidebar.vue:54`), the edit drawer at `z-50` (`EditContact.vue:46`), and the sidepanel
switch at `!z-20` (`SidepanelSwitch.vue:53`). Both dropdowns are also absolutely positioned at a fixed
offset (`top-8`, `top-6`) inside a scrolling column, so they do not reposition when clipped by the panel
bottom.

### V-21 — RTL is handled per-utility and misses several places (high, rtl)

Correct logical handling exists at `ContactInfoRow.vue:81, 88, 110, 127, 136, 148, 164, 172`,
`ContactInfo.vue:195` (`text-left rtl:text-right`), `EditContact.vue:40-46`, `ConversationSidebar.vue:54`,
`ConversationBox.vue:99` and `ContactForm.vue:426, 432`. Missing:
- `AccordionItem.vue:43` — `pr-2 pl-0` on the section title is physical; in RTL the title's padding lands on
  the wrong side.
- `SidepanelSwitch.vue:53` — `top-36 xl:top-24 ltr:right-2 rtl:left-2` is handled, but
  `AccordionItem.vue:38` `rounded-bl-none rounded-br-none` is physical (acceptable for a symmetric bottom,
  noted for completeness).
- `ContactInfo.vue:234` — `-mx-1` is symmetric, fine; but `ContactDetailsItem.vue:12` `py-3 px-4` and
  `ContactNotes.vue:101` `px-4` are symmetric only by luck.
- `ConversationView.vue:131-145` — the decorative shell glows are positioned with physical `right: 4%` /
  `left: 30%`, so the panel's visual backdrop does not mirror.
- `Media.vue:242` uses `ms-0.5` correctly, confirming the codebase knows the logical utilities — the misses
  above are inconsistency, not ignorance.

### V-22 — Mobile: the panel covers the thread with no in-panel way back (high, mobile)

Below 768px (`ConversationSidebar.vue:28-30`, `constants/globals.js:48`) the panel is
`fixed top-0 … w-full max-w-sm` with `z-40` (`:54`). On a 360px device `max-w-sm` (384px) means the panel
covers the viewport entirely. The only dismissals are the header X (`SidebarActionsHeader.vue:37-43`) and a
click-outside (`:44-53`) that has almost no outside left to click. The floating `SidepanelSwitch`
(`SidepanelSwitch.vue:53`, `z-20`) sits **below** the panel's `z-40`, so the toggle that opened the panel is
covered by it.

### V-23 — Mobile: the edit drawer is a second full-screen overlay (medium, mobile)

`EditContact.vue:46` is `fixed inset-y-0 … w-[30rem] max-w-full` at `z-50`. On a phone it covers the panel
that launched it, with no back affordance other than the X at `:59` and `Escape` at `:27-34` (no touch
equivalent, no backdrop to tap — the drawer has no backdrop element at all).

### V-24 — Loading states use four different treatments (medium, loading-error)

Within one panel: bare centered `Spinner` (`ContactConversations.vue:145-147`, `IssuesList.vue:99-101`,
`ContactNotes.vue:112-117`), `Spinner class="size-5"` (`SharedFiles.vue:51-53`), spinner + text
(`Macros/List.vue:72-78`), brand-coloured `Spinner size="32"` (`ShopifyOrdersList.vue:54-56`), an inline
`shared/components/Spinner.vue` at `size="tiny"` next to text (`ConversationParticipant.vue:163`), and a
plain `Spinner` with no wrapper (`labels/LabelBox.vue:123`). Two different Spinner components are in use
(`components-next/spinner/Spinner.vue` and `shared/components/Spinner.vue`). No section uses a skeleton, so
expanding a section collapses and re-expands the panel height as content arrives.

### V-25 — Error states are inconsistent and mostly invisible (high, loading-error)

Only Shopify (`ShopifyOrdersList.vue:57-59`) and Commerce (`CommercePanel.vue:363-365, 394-396, 400-408`)
render an in-place error. Everything else routes failures to a transient toast —
`ContactInfo.vue:167-187`, `ContactInfoRow` (none at all: a failed copy is silently swallowed, `:52-56` has
no `catch`), `ViewAllConversations.vue:80`, `ConversationParticipant.vue:120-125`,
`CustomAttributes.vue:214-219, 236-241`, `IssuesList.vue:56-62`, `Media.vue:146-149`. `ContactConversations.vue`
and `ContactNotes.vue` have **no** error branch: a failed fetch leaves the "no records" empty state showing,
which reads as "this contact has no history" instead of "we could not load it".

### V-26 — Empty-state quality varies from a full CTA to a bare sentence (medium, empty-state)

Best: Linear (`LinearSetupCTA.vue:25-53` — logo, title, role-aware description, action) and Macros
(`Macros/List.vue:58-71` — message plus a settings link). Mid: Commerce (`CommercePanel.vue:306-311`).
Worst: a single unstyled sentence with no action — previous conversations
(`ContactConversations.vue:102-106`, styled only by the scoped `.no-label-message`, `:150-154`), participants
(`ConversationParticipant.vue:166-168`), attachments (`SharedFiles.vue:54-56`), notes
(`ContactNotes.vue:133-135`), attributes (`CustomAttributes.vue:308-313`). "Not Available"
(`ContactInfoRow.vue:119-121, 155-157`) is used for a missing email on a row that is simultaneously a
`mailto:` link with an empty `href` — a dead link rendered as if clickable.

### V-27 — Conversation Actions renders four label/control pairs with no grouping (medium, form)

`ConversationAction.vue:232-308` emits `ContactDetailsItem` + `MultiselectDropdown` four times with no
fieldset, no spacing scale and `compact` padding (`ContactDetailsItem.vue:12` → `py-0 px-0`), so Assignee,
Team, Priority and Labels run together. The "Assign to me" action is a `link xs` button jammed into the
label's `#button` slot (`:239-249`), making it visually part of the *label* rather than an action on the
field. "Join conversation" in the neighbouring section uses the identical `link xs i-lucide-arrow-right`
treatment (`ConversationParticipant.vue:191-199`) for a semantically different operation.

### V-28 — Attribute list is a table in everything but markup (medium, table)

`CustomAttributes.vue:259-306` builds a zebra-striped, reorderable, per-row-actioned list of key/value pairs
with `div`s. Zebra classes are applied with `nth-child(odd)/(even)` arbitrary selectors (`:253-256`), borders
with `border-b border-n-weak/50 dark:border-n-weak/90` plus a conditional last-row transparent override
(`:275-280`). There is no `role="table"`, no column alignment between key and value, and the key/value pair
is stacked (`ContactDetailsItem.vue:13-23` puts the title above the value), so values do not line up
vertically and scanning requires reading every title.

### V-29 — Hover-only reveals are the sole affordance for several actions (high, a11y / discoverability)

`opacity-0 group-hover/*:opacity-100` is the only indication that these exist: the name pencil
(`ContactInfo.vue:234-239`, which does add `focus-visible:opacity-100`), the row pencils
(`ContactInfoRow.vue:136, 172` — **no** focus variant), and note delete
(`ContactNoteItem.vue:90` — **no** focus variant). On touch there is no hover, so on mobile the row-level
edit and the note delete are effectively undiscoverable. `ContactInfo.vue:222` also makes the `<h3>` name a
click target with `cursor-pointer` but leaves it a non-focusable heading.

### V-30 — Section titles are `h5`/`h3` with no document outline (low, a11y)

`AccordionItem.vue:43` uses `<h5>` for every section title while the contact name above it is `<h3>`
(`ContactInfo.vue:220`) and the panel's own title is a `<span>` (`SidebarActionsHeader.vue:26`). Heading
levels skip h4 and the panel region has no landmark or `aria-label`.

### V-31 — `v-dompurify-html` on contact-controlled strings (medium, consistency)

`ContactInfoRow.vue:152` renders the value through `v-dompurify-html` so that `findCountryFlag`'s
`<span class="fi fi-xx">` markup works (`ContactInfo.vue:132`). The same code path renders the identifier
(#25) and company (#26). Building a flag by string-concatenating HTML and then sanitising it, in a component
shared by plain-text fields, is an avoidable coupling that a redesign should not carry forward.

### V-32 — The surface violates the repo's own styling rule in three places (medium, consistency)

`CLAUDE.md` states "Tailwind Only — Do not write custom CSS / Do not use scoped CSS". Present:
`ContactPanel.vue:350-354` (scoped SCSS, and dead — V-04), `ContactConversations.vue:150-154`,
`labels/LabelBox.vue:127-138` (raw `margin-bottom`, `line-height`, `position`),
`Macros/List.vue:107-111`, `CustomAttributes.vue:329-333`, `EmojiOrIcon.vue:49-53`, and the panel's own
container in `ConversationView.vue:230-719` (~490 lines of scoped CSS with hard-coded hex colours,
`--cw-accent: #6366f1` at `:239`, `rgba()` shadows, and physical-direction glow positioning — V-21).

### V-33 — Panel width leaves ~288px of usable content (medium, density)

`ConversationSidebar.vue:54` fixes the column at `md:w-[320px]`, `2xl:w-[360px]`. Subtract the section list's
`px-2` (16px) and the accordion header's `px-4` (32px) and a section body gets ~272px, into which the
Commerce panel fits tabs + refresh + store selector + search + candidate rows
(`CommercePanel.vue:316-343, 477-542`), and the action bar fits up to seven buttons at 32px each plus `gap-2`
(`ContactInfo.vue:329`) = ~266px minimum. The action row has no wrap class, so it will overflow rather than
wrap when all conditional buttons are present.

---

## 4. What this surface already does well and must not be lost

1. **User-ordered, user-collapsed sections, persisted server-side.** `ContactPanel.vue:156-165` +
   `useUISettings.js:39-56, 170-172` + `ui_settings` persistence. Each agent arranges the panel for their own
   workflow and it follows them across devices. New sections are appended rather than resetting a stored
   order (`useUISettings.js:46-53`) — a genuinely careful detail.
2. **Inline editing where the data is read.** `ContactInfoRow.vue:90-97` and `ContactInfo.vue:210-219` let an
   agent correct a name, email, phone or company without opening a drawer, with Enter/Escape/blur all
   behaving sensibly and an emit only on actual change (`:65-72`, `:144-151`).
3. **Keyboard affordances that genuinely save time.** `Alt+O` for the panel (`SidepanelSwitch.vue:43-48`),
   `L` for labels (`LabelBox.vue:39-44`), `Cmd/Ctrl+Enter` to save a note (`ContactNotes.vue:78-85`),
   `Escape` to close the drawer *even from inside an input* (`EditContact.vue:27-34`), and Cmd/Ctrl+click to
   open a previous conversation in a new tab (`ContactConversations.vue:56-64`).
4. **"View all conversations" is unusually well engineered.** It is hidden when it would be a no-op
   (`ViewAllConversations.vue:34-37`), leaves folder scope and expanded-layout list state deliberately
   (`:50-63`), restores the open conversation that applying a filter would have dropped (`:40-45, 81`), and
   matches the in-thread chronological sort (`:78`). The comments at `:33, 39, 47, 52` explain why.
5. **Timestamps rendered in the agent's own timezone with a raw fallback.** `ConversationInfo.vue:24-35` and
   `useExactTimestamp({ showTimeZone: true })` at `:22`. Heterogeneous stored formats are handled without
   throwing away unparseable values.
6. **Static conversation-info rows disappear when empty, and their stored order survives.**
   `ConversationInfo.vue:97` plus `CustomAttributes.vue:136-162`, which re-inserts hidden `static-*` keys at
   the right position so an agent's ordering is not scrambled when switching between an email conversation
   and a widget one.
7. **Role-aware integration CTA.** `LinearSetupCTA.vue:42-52` tells an admin how to connect and an agent who
   to ask, instead of showing a dead button. This is the model the weaker empty states (V-26) should follow.
8. **Destructive actions are confirmed and permission-gated.** Delete is admin-only
   (`ContactInfo.vue:373`), confirms with the contact's name interpolated (`ContactDeleteModal.vue:34-36`),
   disables during flight (`ContactInfo.vue:385`), and routes the agent somewhere valid afterwards
   (`ContactDeleteModal.vue:46-52`). Merge likewise disables during flight (`ContactInfo.vue:368`).
9. **Call button refuses to lie about state.** `VoiceCallButton.vue:75-83` blocks a second call while any
   provider call is live, and `:152-158, 169-178` distinguish "permission requested", "permission already
   pending" and "call started" instead of claiming success. `:33-45, 102-117` document the reasoning.
10. **Previous-conversation cards reuse the real list card.** `ContactConversations.vue:111-124` renders
    `ConversationCard` with `compact hide-thumbnail`, so status, priority, labels, assignee, unread and inbox
    all stay consistent with the main list, including a deliberately narrowed context menu
    (`:140`).
11. **Shared files peek-then-expand with safe downloads.** `SharedFiles.vue:15-16, 58-67` shows 6 media and 3
    files, with `View all`/`Show less` and a `+N` overflow tile (`Media.vue:169-181, 297-304`); downloads
    carry real `aria-label`s (`Media.vue:271`, `Files.vue:164, 176`) — the only properly labelled icon
    buttons on the surface.
12. **Collapsible long notes with author attribution and exact-time tooltips.**
    `ContactNoteItem.vue:44-51, 69-82, 94-117` clamps to 4 lines only when actually needed, and falls back to
    "Bot" with the bot avatar for system-written notes (`ContactNotes.vue:33-38`, `ContactNoteItem.vue:59-66`).
13. **Re-selecting the current value clears it.** Assignee, team and priority all treat a second click as
    "unset" (`ConversationAction.vue:199-227`) — fast, and consistent across all three.
14. **The panel is self-healing on context change.** Contact refetched (`ContactPanel.vue:119-123`),
    contactable inboxes refetched (`ContactInfo.vue:113-120`), notes refetched and their modal force-closed
    (`ContactNotes.vue:87-96`), participants refetched (`ConversationParticipant.vue:92-95`), previous
    conversations refetched with the context menu reset (`ContactConversations.vue:84-93`).
15. **Legacy social-profile attributes are still honoured.** `ContactInfo.vue:85-100` falls back to
    `screen_name` and `social_telegram_user_name`, and WhatsApp usernames are normalized on both read and
    write (`:101-111`, `ContactForm.vue:130-132, 209-213`), so older records keep rendering.
16. **Emoji-or-icon user preference is respected.** `EmojiOrIcon.vue:14-23` honours
    `ui_settings.icon_type === 'emoji'`, and every `ContactInfoRow` supplies both an icon and an emoji
    (`ContactInfo.vue:268-325`). Deprecated or not, the *preference* is a feature and must survive.
17. **Section visibility is context-aware, not just flag-aware.** Previous conversations hides itself when
    the list is already scoped to the contact (`ContactPanel.vue:105-111`), "View all" hides itself on
    inbox-view routes (`ViewAllConversations.vue:35`), and the Shopify empty state distinguishes "no
    searchable contact info" from "no orders" (`ShopifyOrdersList.vue:51-62`).
