---
agent: 030
scope: The message composer — reply vs private note, attachments, emoji, canned responses, signatures, templates, drafts, send failure and retry, message deletion, character limits, channel-specific behaviour
confidence: high
---

## 1. What the feature is

The composer is one Options-API component, `ReplyBox.vue` (1,569 lines), mounted under the message list for
every conversation. It is a mode switch, not two editors: the same ProseMirror instance serves **Reply** and
**Private note**, and almost every capability in the footer is computed from `isPrivate` plus the inbox's
channel type.

What an agent can do in it:

- write a public reply or an internal private note (`replyType`, `ReplyBox.vue:242-262`);
- attach files, by button, by drag-and-drop or by paste (`ReplyBottomPanel.vue:282-307`, `ReplyBox.vue:771-810`);
- record a voice note (`AudioRecorder`, format chosen per channel, `ReplyBox.vue:453-466`);
- insert an emoji from a picker, or inline by typing `:` + 2 characters (`Editor.vue:381-385`);
- insert a canned response by typing `/`, a variable by typing `{{`, a macro by typing `#`, a mention by typing
  `@` (`Editor.vue:339-386`);
- append a personal signature, toggled per channel (`ReplyBottomPanel.vue:236-248`);
- send a WhatsApp template or a Twilio Content template through a modal (`ReplyBox.vue:1499-1515`);
- quote the previous email thread on email inboxes (`ReplyBox.vue:1417-1423`);
- reply to one specific message (`inReplyTo`, `ReplyBox.vue:1250-1272`);
- keep a per-conversation, per-mode draft (`ReplyBox.vue:693-733`).

Two things an agent **cannot** do: edit a sent message (no edit path exists anywhere — the context menu offers
copy, delete, add-to-canned, copy link, translate, reply-to, report, `Message.vue:400-427`), and attach a file
to a canned response.

## 2. Surfaces and routes

| Surface | Path |
|---|---|
| Composer | `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue` |
| Mode toggle + character counter | `app/javascript/dashboard/components/widgets/WootWriter/ReplyTopPanel.vue:153-207` |
| Footer (attach, emoji, mic, signature, quote, templates, Send) | `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue:269-404` |
| Editor (ProseMirror, suggestion triggers, inline image paste) | `app/javascript/dashboard/components/widgets/WootWriter/Editor.vue` |
| Attachment chips | `app/javascript/dashboard/components/widgets/AttachmentsPreview.vue` |
| Canned-response picker | `app/javascript/dashboard/components/widgets/conversation/CannedResponse.vue` |
| Upload size/limit logic (composer) | `app/javascript/dashboard/mixins/fileUploadMixin.js` |
| Upload size/limit logic (new-conversation modal) | `app/javascript/dashboard/composables/useFileUpload.js` |
| Channel file rules (types + per-category MB) | `node_modules/@chatwoot/utils/src/fileUploadRules.ts:107-212` |
| Channel character limits | `app/javascript/shared/helpers/MessageTypeHelper.js:4-26` |
| Failure block + Retry | `app/javascript/dashboard/components-next/message/MessageError.vue` |
| Retry dispatch | `MessagesView.vue:445-449` → `store/modules/conversations/actions.js:397-427` |
| Drafts (client) | `app/javascript/dashboard/store/modules/draftMessages.js` |

Backend:

| Action | Route | Controller |
|---|---|---|
| Create | `POST /api/v1/accounts/:id/conversations/:conversation_id/messages` | `messages_controller.rb:8-14` → `Messages::MessageBuilder` |
| Delete | `DELETE .../messages/:id` | `messages_controller.rb:21-26`, overridden for audit by `custom/app/controllers/custom/api/v1/accounts/conversations/messages_controller.rb:16-25` |
| Retry | `POST .../messages/:id/retry` | `messages_controller.rb:33-46` (`config/routes.rb:119-124`) |
| Translate | `POST .../messages/:id/translate` | `messages_controller.rb:48-67` |
| Direct upload | `POST .../conversations/:conversation_id/direct_uploads` | `direct_uploads_controller.rb:17-21` |
| Draft (server, unused) | `GET/PATCH/DELETE .../draft_messages` | `draft_messages_controller.rb:1-28` |

Models: `app/models/message.rb`, `app/models/attachment.rb`.

## 3. User-visible states

**Mode.** The toggle shows Reply or Private note (`EditorModeToggle`). Reply is disabled when
`canSendPublicReply` is false (`ReplyBox.vue:232-238`): outside the messaging window, on a bot-owned pending
conversation, or when Meta sending is disabled on cloud for an Instagram inbox
(`globalConfig.js:69-70`). Instagram-restricted conversations are forced to Private note on mount
(`ReplyBox.vue:588-590`).

**Editor disabled.** For WhatsApp and API inboxes with `can_reply === false`, in reply mode, the editor is
read-only (`ReplyBox.vue:517-522`) and the whole footer collapses to the Send button: attach, emoji, mic,
signature and video-call buttons all hide on `isEditorDisabled` (`ReplyBottomPanel.vue:176-239, 273`). The
placeholder becomes the template-only sentence. The WhatsApp-template button is the only remaining way out, and
it is shown only when templates have actually been synced for the inbox (`ReplyBox.vue:216-224`).

**Send button.** Disabled when the editor is disabled, on any Twitter inbox unconditionally, or when there is
no attachment, no recorded audio and the body is empty or over the channel limit
(`ReplyBox.vue:308-318`).

**Character counter.** Hidden until within 50 characters of the limit, then counts down, then turns red and
counts up the overage (`ReplyBox.vue:302-306`, `ReplyTopPanel.vue:141-148, 164-168`). Over the limit the Send
button is disabled, so the state is terminal rather than advisory.

**Attachments.** Each attached file becomes a chip with a thumbnail (images) or a 📄 glyph, its name, its size
and a remove button (`AttachmentsPreview.vue:48-80`, inserted at `ReplyBox.vue:1426-1434`). Voice notes are filtered out of that list and shown by
the recorder's own controls (`AttachmentsPreview.vue:16-22`). Switching between Reply and Private note silently
discards every attachment (`ReplyBox.vue:996-1000`), and so does switching conversation
(`ReplyBox.vue:566, 687-692`).

**Signature.** With the signature toggle on and no signature saved, an inline alert appears above the footer
(`MessageSignatureMissingAlert`, `ReplyBox.vue:1436-1443`) reading "Message signature is not configured, please
configure it in profile settings." plus "Click here to update".

**Drafts.** Text survives a conversation switch and a page reload, held per
`draft-<conversationId>-<REPLY|NOTE>` in `localStorage` under `draftMessages`
(`ReplyBox.vue:689-733`, `draftMessages.js:7-8, 31-38`). Attachments and recorded audio are **not** part of a
draft.

**Sending.** An optimistic bubble appears immediately at status `progress`
(`actions.js:392-404`), then flips to `sent` or to `failed`.

**Failed.** A failed outgoing message renders a red "Failed to send" line, the provider's words (clamped to
three lines, full text in the `title` attribute), and — for the two WhatsApp codes this installation classifies
— a plain-language title and body plus a "What to do about this" documentation link
(`MessageError.vue:87-141`, `custom/app/services/whatsapp/delivery_failure.rb:28-31`). Retry is offered only
when the failure is not recipient-scoped, the message is under 24 hours old, and it has content or attachments
(`MessageError.vue:56-66`). Where retry is withheld the UI states why.

**Deleted.** Delete replaces the body with a placeholder and destroys the attachments
(`messages_controller.rb:22-25`); the bubble renders as deleted thereafter (`Message.vue:381-383`).

## 4. Errors and validation messages

Client-side, all shown as toasts (`app/javascript/dashboard/i18n/locale/en/conversation.json`):

| String | Key | Raised at |
|---|---|---|
| "File exceeds the {MAXIMUM_SUPPORTED_FILE_UPLOAD_SIZE} MB attachment limit" | `CONVERSATION.FILE_SIZE_LIMIT` (`conversation.json:354`) | `fileUploadMixin.js:49-55` |
| "This {fileName} file type is not supported in this conversation" | `CONVERSATION.FILE_TYPE_NOT_SUPPORTED` (`conversation.json:355`) | `ReplyBox.vue:794-798` — **paste only** |
| "Unable to send this message, please try again later" | `CONVERSATION.MESSAGE_ERROR` (`conversation.json:356`) | `ReplyBox.vue:975-979`, only when the server returned no `error` field |
| "Audio conversion failed. Please try again." | `CONVERSATION.REPLYBOX.AUDIO_CONVERSION_FAILED` (`conversation.json:307`) | `ReplyBox.vue:1084-1087` |
| "You have {n} undefined variables in your message: … Would you like to send the message anyway?" | `CONVERSATION.REPLYBOX.UNDEFINED_VARIABLES.MESSAGE` (`conversation.json:329`) | `ReplyBox.vue:935-957` |
| "Message signature is not configured, please configure it in profile settings." | `CONVERSATION.FOOTER.MESSAGE_SIGNATURE_NOT_CONFIGURED` (`conversation.json:289`) | `MessageSignatureMissingAlert.vue` |
| "You can only reply using a template message due to 24-hour message window restriction" | `CONVERSATION.FOOTER.MESSAGING_RESTRICTED_WHATSAPP` (`conversation.json:287`) | placeholder, `ReplyBox.vue:288-301` |
| "You cannot reply to this conversation" / "…due to message window restriction" | `MESSAGING_RESTRICTED`, `MESSAGING_RESTRICTED_API` (`conversation.json:286, 288`) | same |
| "Please enter valid email addresses" | `CONVERSATION.REPLYBOX.EMAIL_HEAD.CC.ERROR` / `.BCC.ERROR` (`conversation.json:319, 324`) | `ReplyEmailHead.vue` |
| "Message deleted successfully" / "Couldn't delete message! Try again" | `CONVERSATION.SUCCESS_DELETE_MESSAGE`, `CONVERSATION.FAIL_DELETE_MESSSAGE` (`conversation.json:84-85`) | context-menu delete |
| "Are you sure you want to delete this message?" / "You cannot undo this action" | `CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.*` (`conversation.json:376-381`) | confirm dialog |
| Failure block: "Failed to send", "WhatsApp said:", "What to do about this", "Send this message again", "Sending this again would be refused the same way." | `CHAT_LIST.FAILED_TO_SEND`, `CHAT_LIST.DELIVERY_FAILURE.*` (`chatlist.json:28, 172-185`) | `MessageError.vue` |

Server-side validations that can reject a composer send:

| Condition | Message produced | Source |
|---|---|---|
| More than 15 attachments on one message | `Attachments exceeded maximum allowed` | `message.rb:46, 445-447` |
| ≥ `CONVERSATION_MESSAGE_PER_MINUTE_LIMIT` (default 200) messages in the conversation in the last minute | `Too many messages` | `message.rb:289-299`, `lib/limits.rb:14-16` |
| Body over 150,000 characters | standard Rails length message | `message.rb:80-81` |
| Web-widget attachment over `MAXIMUM_FILE_UPLOAD_SIZE` | `File size is too big` | `attachment.rb:208-213` |
| Web-widget attachment of a disallowed type | `File type not supported` | `attachment.rb:201-206` |
| `message_type: incoming` on a non-API inbox | `Incoming messages are only allowed in Api inboxes` | `message_builder.rb:108-114` |
| Retry of a recipient-scoped WhatsApp failure | "WhatsApp refused this message for this recipient (%{reason}). Retrying would repeat the same refusal, so it is not offered. The restriction is Meta's and lifts on its own." | `messages_controller.rb:36-41`, `config/locales/en.yml:186` |

All of these reach the agent as `422 { error: <raw message> }` (`request_exception_handler.rb:46-48, 87-91`),
which the composer surfaces verbatim in a toast (`ReplyBox.vue:974-980`). **The first six are untranslated
ActiveRecord strings**: an agent who attaches a 16th file is told `Validation failed: Attachments exceeded
maximum allowed`.

## 5. Failure paths

**Attachment type is validated almost nowhere.** `isFileTypeAllowedForChannel` exists
(`FileHelper.js:49-87`) and is called from exactly one place in the product: the paste handler
(`ReplyBox.vue:783-800`; the only other reference is the import at `ReplyBox.vue:57`). The file picker relies on
the `accept` attribute (`ReplyBottomPanel.vue:288`), which is an OS-level hint a user can override, and
`vue-upload-component` enforces nothing on add — its only extension check is behind the unused `extensions`
prop and runs inside its own `upload()` path (`node_modules/vue-upload-component/src/FileUpload.vue:974-983`),
which this product never triggers. **Drag-and-drop bypasses `accept` entirely.** Server-side,
`Attachment#should_validate_file?` returns early unless the inbox is `Channel::WebWidget`
(`attachment.rb:186-192`), so for WhatsApp, Instagram, Facebook, Telegram, SMS, email and API inboxes **no file
type validation runs at all, on either side**, unless the agent pasted the file. A `.exe` dropped on a WhatsApp
conversation uploads, saves, and fails at Meta with a provider error the agent has to interpret.

**Size is validated only on the client.** `fileUploadMixin.maxSizeFor` takes the smaller of the channel rule
and the installation limit (`fileUploadMixin.js:26-47`), e.g. 5 MB for a WhatsApp image, 16 MB for WhatsApp
video/audio, 40 MB for a WhatsApp document capped by the 40 MB installation default
(`fileUploadRules.ts:122-141`, `config/installation_config.yml:104-108`). The server re-checks only for web
widget (`attachment.rb:186-213`). Anything posted outside the dashboard — or by a dashboard whose JS limit is
stale — is stored unchecked.

**`:size="4096 * 4096"` on the picker is dead config.** The 16 MiB figure in `ReplyBottomPanel.vue:287` (and
`ActionButtons.vue:228`) is only consulted by the component's own uploader, which is never used. It reads like a
limit and is not one.

**Every attachment is base64'd in the browser before it is sent.** `attachFile` runs
`FileReader.readAsDataURL` over the whole file to build a thumbnail (`ReplyBox.vue:1110-1126`), even for a
40 MB video whose chip shows the 📄 glyph. That is ~53 MB of string per attachment, on the main thread.

**A send that fails before reaching the server loses the agent's text.** `confirmOnSendReply` clears the editor
without awaiting the result (`ReplyBox.vue:841-878`), and `clearMessage` sets `message = ''`
(`ReplyBox.vue:1017-1035`), which fires the autosave watcher and overwrites the draft with an empty string
(`ReplyBox.vue:600-611`, `draftMessages.js:31-38`). `removeFromDraft` is only called on success
(`ReplyBox.vue:965`). The typed words then exist only in the in-memory failed bubble; a reload loses them.

**Retry of a client-side failure re-POSTs, retry of a provider failure calls the retry endpoint.** The branch is
`hasMessageFailedWithExternalError` (`actions.js:54-64`, used at `actions.js:404-406`). The second path is
Lynomia's: it refuses recipient-scoped WhatsApp refusals with Meta's reason, preserves the previous
`external_error` as `previous_external_error` + `retried_at` so pressing Retry cannot erase why Meta refused,
and clears `source_id` for non-API/non-widget inboxes (`messages_controller.rb:28-115`).

**Pending attachment placeholders never render.** `createPendingMessage` sets
`attachments: file ? [{id}] : null` (`helper/commons.js:49-61`), but the composer sends `files` (plural,
`ReplyBox.vue:1206-1217`). `data.file` is always undefined, so an optimistic bubble for an attachment-only
message has no attachment in it until the server responds.

**New-conversation composer loses the channel rules.** `useFileUpload` expects `{ inbox, attachFile }` but is
called with `{ isATwilioSMSChannel, attachFile }` (`ActionButtons.vue:122-137`), so `inbox` is undefined and
`maxSizeFor` returns the installation limit for every file (`useFileUpload.js:33-56`). It also builds the
direct-upload URL from `currentChat.value.id` (`useFileUpload.js:76-84`), and `getSelectedChat` returns `{}`
when nothing is selected (`conversations/getters.js:53-58`), so with `DIRECT_UPLOADS_ENABLED=true` a
new-conversation upload posts to `/conversations/undefined/direct_uploads`, which `find_by(display_id:)` cannot
resolve and the controller answers with nothing (`direct_uploads_controller.rb:17-21, 35-37`). The attach
button there is limited to email and web-widget inboxes (`ActionButtons.vue:224-225`), which hides most of the
impact without fixing it.

**Multi-message splitting is invisible to the agent.** On WhatsApp, Instagram and TikTok the composer silently
turns one Send into several API calls: one message per attachment, and the body either as the first
attachment's caption (WhatsApp) or as a separate message (Instagram, TikTok)
(`ReplyBox.vue:841-884, 1142-1190`). Each one can fail independently, and `sendMessageAsMultipleMessages`
fires them without awaiting (`ReplyBox.vue:879-889`), so partial delivery shows up as some bubbles sent and
others failed with no explanation that they were one composition.

**The server-side draft endpoint is unreachable from this product.** `draft_messages_controller.rb` stores a
draft in Redis, and nothing in `app/javascript` calls it (`grep -rn "draft_messages" app/javascript` is empty).
Drafts are therefore per-browser: an agent does not see on their phone what they typed on their laptop.

**`draftMessages/delete` never removes the key.** The action commits `SET_DRAFT_MESSAGES` with no message,
writing `undefined` under the key; `REMOVE_DRAFT_MESSAGES` is defined and never dispatched
(`draftMessages.js:23-25, 39-43`). The `draftMessages` localStorage object grows one key per
conversation-and-mode forever.

**Emoji, canned responses, variables and macros are not available in a private note.** `/`, `{{` and the
variable input rule are gated on `!isPrivate` (`Editor.vue:359-374`); `@` switches from Captain tools to user
mentions inside a note (`Editor.vue:346-357`). The placeholder for a note does not mention this
(`conversation.json:285`).

## 6. Permissions

There is **no message policy**. Everything hangs off `ConversationPolicy#show?`, applied once in
`Api::V1::Accounts::Conversations::BaseController#conversation` (`base_controller.rb:6-9`). Any user who can
open a conversation can send a reply, add a private note, delete any message in it and retry a failed one.

`show?` is `administrator? || agent_bot? || (inbox_access? || team_access?)`
(`app/policies/conversation_policy.rb:10-36`), narrowed by Lynomia's custom-role capability scope:
`Custom::ConversationPolicy#show?` is `super && capability_scope.permits?(record, user:)`
(`custom/app/policies/custom/conversation_policy.rb:40-42`), delegating the inbox/team ceiling to
`Conversations::AccessCeiling`. So custom roles gate *reaching* a conversation, not *what you may do in it*.

Composer capabilities gated by something other than conversation access:

| Capability | Gate | Where |
|---|---|---|
| Macro picker (`#`) | account feature flag `MACROS` | `ReplyBox.vue:194-199` |
| Voice recorder | account feature flag `VOICE_RECORDER` | `ReplyBottomPanel.vue:190-197` |
| Copilot menu | `captainTasksEnabled` | `ReplyTopPanel.vue:171-196` |
| Reply on an Instagram inbox | `deploymentEnv === 'cloud' && disableMetaMessageSending` | `globalConfig.js:69-70`, `ReplyBox.vue:239-241` |
| Message status update endpoint | API inboxes only | `messages_controller.rb:126-129` |
| Direct uploads | `DIRECT_UPLOADS_ENABLED` installation config, plus `api_and_webhooks_enabled?` for token callers | `installation_config.yml:99-103`, `direct_uploads_controller.rb:29-33` |
| Bare `/rails/active_storage/direct_uploads` | blocked outright | `config/initializers/active_storage.rb:52-64` |

## 7. Contextual-help opportunities

| UI location | The question an agent has there | Registry key that should link | Exists in `DOC_ARTICLES`? |
|---|---|---|---|
| `ReplyTopPanel.vue:157-162` (mode toggle) | "What is the difference between a reply and a private note? Who sees a note?" | `conversations` | yes (`documentationLinks.js:19`) |
| `ReplyBottomPanel.vue:282-307` (attach button) | "What file types and sizes can I send on this channel?" | needs a new key, e.g. `attachments` | **no** |
| `fileUploadMixin.js:49-55` (size toast) | "Why is 6 MB too big here when it was fine on email?" | needs `attachments` | **no** |
| `ReplyBox.vue:794-798` (type toast) | "Which types does WhatsApp accept?" | needs `attachments` | **no** |
| `MessageSignatureMissingAlert.vue` | "Where do I write my signature, and which channels use it?" | needs a new key, e.g. `messageSignature` | **no** |
| `ReplyBottomPanel.vue:327-336` (signature toggle) | "Is the signature per channel or global?" | needs `messageSignature` | **no** |
| `ReplyBox.vue:288-301` (restricted placeholder) | "Why can I only send a template?" | `whatsappWindow` | yes (`documentationLinks.js:37`) |
| `ReplyBottomPanel.vue:348-357` (WhatsApp template button) | "How do I pick and fill a template?" | `whatsappTemplates` | yes (`documentationLinks.js:38`) |
| `ReplyTopPanel.vue:164-168` (character counter) | "Why does this channel cut off at 1,000 characters?" | needs a new key, e.g. `channelMessageLimits` | **no** |
| `MessageError.vue:113-139` (failure block) | "What do I do about this refusal?" | `whatsappError*` / `whatsappTroubleshooting` | yes, already wired (`MessageError.vue:70-77`) |
| `MessageError.vue` on a non-WhatsApp failure | "Why did this email/SMS fail, and can I retry?" | needs a new key, e.g. `sendFailures` | **no** |
| `conversation.json:376-381` (delete confirmation) | "Does the customer still have the message? Does deleting remove it from WhatsApp?" | needs a new key, e.g. `deleteAMessage` | **no** |
| `Editor.vue:359-363` (`/` trigger) | "How do canned responses work?" | `cannedResponses` | yes (`documentationLinks.js:22`) |
| `Editor.vue:375-379` (`#` trigger) | "What can a macro do from here?" | `macros` | yes (`documentationLinks.js:23`) |
| `ReplyBottomPanel.vue:309-317` (mic) | "Which channels accept a voice note, and in what format?" | needs `attachments` or a `voiceNotes` key | **no** |
| `ReplyBox.vue:1417-1423` (quoted-email toggle) | "What gets quoted, and can the customer see it?" | needs an email-composer key | **no** |
| `ReplyBox.vue:935-957` (undefined-variable dialog) | "Which variables exist?" | `cannedResponses` | yes |

## 8. Current documentation coverage

Covered, and well:

- **`custom/db/documentation/en/conversations/canned-responses.md`** (956 words) — the `/` trigger, short codes,
  `{{` variables, the per-channel formatting strip, the private-note exclusion, who can edit. Accurate against
  `CannedResponse.vue:66-86` and `Editor.vue:359-374`.
- **`custom/db/documentation/en/conversations/work-in-the-inbox.md`** (1,067 words) — private notes and
  `@mentions`, including the correct warning that a mention only works inside a note
  (`work-in-the-inbox.md:57-74` vs `Editor.vue:346-357`).
- **`custom/db/documentation/en/conversations/macros.md`** — the `#` macro actions, including "send attachment".
- **`custom/db/documentation/en/getting-started/your-first-conversation.md:50`** — one line on the `/` trigger.
- **`custom/db/documentation/en/whatsapp-errors/whatsapp-find-a-failed-message.md`** — where a failed WhatsApp
  message appears, that nothing is retried automatically, and that Retry is withheld where it would repeat the
  refusal. This matches `MessageError.vue:50-66` and `messages_controller.rb:28-46` exactly.
- **`custom/db/documentation/en/whatsapp/the-whatsapp-24-hour-window.md`** — the restriction behind the disabled
  editor.

Arabic parity is one-for-one at the file level for the whole `conversations` section
(`custom/db/documentation/ar/conversations/` has the same six files).

## 9. Missing or stale documentation

Nothing in the corpus documents the composer as a surface. `grep -rn "MB\b\|attachment" custom/db/documentation/en/`
returns ten hits, all about macros, automation actions, CSV import or support tickets — **none about sending an
attachment from the composer**.

Missing, in rough order of how often an agent will be stuck:

1. **Attachments.** No article names a single supported type or size. The real rules are per channel and per
   category (WhatsApp image 5 MB / video 16 MB / audio 16 MB / document 40 MB-capped; Instagram image 16 MB /
   video 25 MB; Facebook image 8 MB / everything else 25 MB; LINE image 10 MB; TikTok image 3 MB and images
   only; Twilio SMS and Twilio WhatsApp 5 MB; everything else the 40 MB installation default —
   `fileUploadRules.ts:107-212`, `installation_config.yml:104-108`). This is the single largest gap in my scope.
2. **Which channels accept an attachment at all.** `showFileUpload` excludes Twitter and excludes TikTok when
   the conversation's `tiktok_capabilities.image_send` is false (`ReplyBox.vue:366-385`), and multiple files are
   only allowed on email, web widget, API, WhatsApp and Telegram (`ReplyBox.vue:426-434`).
3. **Character limits per channel.** 10,000 general and private note, 25,000 email, 4,096 WhatsApp Cloud and
   Telegram, 2,000 Facebook and LINE, 1,600 Twilio WhatsApp, 1,000 Instagram, 6,000 TikTok, 320 Twilio SMS
   (`MessageTypeHelper.js:4-26`, `ReplyBox.vue:330-364`). Nothing explains the red counter or the dead Send
   button.
4. **Message signatures.** Where to write one, that the toggle is per channel, that formatting the channel
   cannot carry is stripped, that it is never added to a private note, and that it is removed from drafts when
   the toggle is turned off (`editorHelper.js:95-200`, `ReplyBox.vue:734-756`).
5. **Drafts.** That a draft is per conversation *and* per mode, lives in that browser only, and never includes
   attachments (`ReplyBox.vue:689-733`).
6. **Deleting a message.** That it cannot be undone, that it destroys the attachments, that the customer's copy
   on WhatsApp is untouched, and that there is no way to edit a message
   (`messages_controller.rb:21-26`, `Message.vue:400-427`).
7. **Send failures that are not WhatsApp.** The 24-hour Retry cutoff (`MessageError.vue:60-66`), what the
   "Failed to send" block means on email or SMS, and that a failure before the request reached the server loses
   the text.
8. **Voice notes.** That they exist, which channels and feature flag allow them, and that the recording format
   differs per channel — OGG for WhatsApp Cloud, MP3 for other WhatsApp/Telegram/API, WAV otherwise
   (`ReplyBox.vue:453-466`).
9. **The multi-message split.** That one Send on WhatsApp, Instagram or TikTok becomes several messages, and
   that the caption lands on the first attachment on WhatsApp only (`ReplyBox.vue:1142-1190`).
10. **Quoted email replies and CC/BCC.** The toggle, what gets quoted, and that CC/BCC are prefilled from the
    last email (`ReplyBox.vue:1234-1249`, `getRecipients`).
11. **Emoji.** The picker and the `:` + 2-character inline trigger are undocumented
    (`Editor.vue:381-385`).

## 10. Doc claims not proven by code

**Claim: "Nothing checks that your variables are spelled correctly."**
(`custom/db/documentation/en/conversations/canned-responses.md:99`) — **wrong**. On Send,
`getUndefinedVariablesInMessage` collects every `{{…}}` whose key is not in the resolved variable map and the
composer blocks the send behind a confirmation dialog naming them
(`ReplyBox.vue:935-957`; helper at `node_modules/@chatwoot/utils/src/canned.ts:111-131`; the dialog's strings at
`conversation.json:327-334`). A misspelled variable is caught; a *defined but empty* one is not.

**Claim: "A variable with no value disappears… Nothing warns you."**
(`canned-responses.md:66-67`) — **confirmed**, and the reason is worth recording. In the composer
`resolveVariableText` leaves the literal `{{key}}` when the value is empty (`editorHelper.js:460-468`), and the
server then renders the body through Liquid on create (`app/models/concerns/liquidable.rb:26-43`,
`message.rb:45`), where an empty drop value renders as nothing. The warning is skipped because
`getUndefinedVariablesInMessage` tests `=== undefined`, and `getNameVariables` always supplies a key, with `''`
as its value (`editorHelper.js:472-493`).

**Claim: "The customer received `{{contact.name}}` as literal text. The variable name is misspelled…"**
(`canned-responses.md:112-113`) — **not reproducible as written, and it contradicts line 99 of the same file.**
Every outgoing message body is Liquid-rendered before create (`liquidable.rb:26-43`), and Liquid renders an
unknown expression as an empty string, so a misspelled variable arrives as *nothing*, not as literal braces —
which is what line 99 of the same article says. One of the two statements must be wrong; on the code I read it
is line 112. I could not construct the literal-braces case without running the app, so I record this as a
contradiction for the corpus owner (agent 050) rather than a resolved finding.

**Claim: "A canned response is plain text and attachments are not part of it."**
(`canned-responses.md:97`) — **confirmed**. The picker emits only `content` through `replace`
(`CannedResponse.vue:69-86`); nothing in the insertion path touches `attachedFiles`.

**Claim: "They are switched off inside a private note, along with variables."**
(`canned-responses.md:95-96`) — **confirmed** at `Editor.vue:359-374`, fed by `isOnPrivateNote` at
`ReplyBox.vue:1391`.

**Not checked:** whether the WhatsApp/Content template modals validate parameters before send (deferred to
agents 040 and 039); the Platform Support Desk's own composer and its attachment path
(`custom/app/controllers/api/v1/accounts/platform_support/attachments_controller.rb`,
`custom/app/services/platform_support/message_creation.rb`), which belongs to agent 048; and whether
`useSnakeCase` on a retried indirect-upload payload preserves a `File` object
(`MessagesView.vue:445-449`) — I could not determine that by reading alone.
